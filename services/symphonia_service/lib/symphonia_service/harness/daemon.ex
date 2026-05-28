defmodule SymphoniaService.Harness.Daemon do
  @moduledoc """
  Always-on scheduler for enabled repositories.
  """

  use GenServer

  alias SymphoniaService.{CodingAssistant, RepositoryRegistry, TaskStore}
  alias SymphoniaService.CodingAssistant.{ProviderCatalog, RunEvents, RunStore}
  alias SymphoniaService.Harness.{Automation, Eligibility}

  @max_recent_decisions 50
  @max_claims_per_tick 1
  @max_claims_per_repo 1
  @max_concurrent_runs 1

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def ensure_started(registry_path \\ SymphoniaService.default_registry_path()) do
    case Process.whereis(__MODULE__) do
      nil ->
        case GenServer.start_link(__MODULE__, [registry_path: registry_path], name: __MODULE__) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

      _pid ->
        :ok
    end
  end

  def tick(name \\ __MODULE__), do: GenServer.call(name, :tick, 30_000)
  def status(name \\ __MODULE__), do: GenServer.call(name, :status)

  @impl true
  def init(opts) do
    state = %{
      registry_path: Keyword.get(opts, :registry_path, SymphoniaService.default_registry_path()),
      interval_ms: Keyword.get(opts, :interval_ms, interval_ms()),
      limits: %{
        max_claims_per_tick: Keyword.get(opts, :max_claims_per_tick, @max_claims_per_tick),
        max_claims_per_repo: Keyword.get(opts, :max_claims_per_repo, @max_claims_per_repo),
        max_concurrent_runs: Keyword.get(opts, :max_concurrent_runs, @max_concurrent_runs)
      },
      last_heartbeat_at: nil,
      last_dispatch: nil,
      last_error: nil,
      recent_decisions: [],
      claimed: MapSet.new(),
      timer?: Keyword.get(opts, :timer?, true)
    }

    if state.timer?, do: schedule_tick(state.interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, status_payload(state), state}
  end

  def handle_call(:tick, _from, state) do
    {decisions, state} = dispatch_once(state)
    {:reply, Map.merge(status_payload(state), %{"decisions" => decisions}), state}
  end

  @impl true
  def handle_info(:tick, state) do
    {_decisions, state} = dispatch_once(state)
    if state.timer?, do: schedule_tick(state.interval_ms)
    {:noreply, state}
  end

  defp dispatch_once(state) do
    heartbeat_at = now()
    active_count = active_run_count()

    dispatch_context = %{
      claims_this_tick: 0,
      active_run_count: active_count,
      repo_claims: %{},
      claimed: state.claimed,
      decisions: [],
      last_dispatch: state.last_dispatch,
      last_error: state.last_error,
      halted?: false
    }

    context =
      state.registry_path
      |> RepositoryRegistry.list()
      |> Enum.filter(&Automation.enabled?/1)
      |> Enum.reduce_while(dispatch_context, fn repository, context ->
        context = dispatch_repository(state, repository, context)

        if context.halted? do
          {:halt, context}
        else
          {:cont, context}
        end
      end)

    decisions = context.decisions

    state = %{
      state
      | claimed: context.claimed,
        last_heartbeat_at: heartbeat_at,
        last_dispatch: context.last_dispatch,
        last_error: context.last_error,
        recent_decisions: take_recent(decisions ++ state.recent_decisions)
    }

    {decisions, state}
  end

  defp dispatch_repository(state, repository, context) do
    repository
    |> TaskStore.list_tasks()
    |> Enum.reduce_while(context, fn task, context ->
      context = dispatch_task(state, repository, task, context)

      if context.halted? do
        {:halt, context}
      else
        {:cont, context}
      end
    end)
  end

  defp dispatch_task(state, repository, task, context) do
    claim_key = "#{repository["key"]}:#{task["key"]}"
    eligibility = Eligibility.explain(repository, task)

    cond do
      context.active_run_count >= state.limits.max_concurrent_runs ->
        context
        |> add_decision(
          decision(
            repository,
            task,
            "max_concurrent_runs_reached",
            false,
            "The daemon is already running the maximum number of Coding Assistant runs."
          )
        )
        |> Map.put(:halted?, true)

      not eligibility["eligible"] ->
        add_decision(
          context,
          decision(repository, task, eligibility["code"], false, eligibility["reason"])
        )

      MapSet.member?(context.claimed, claim_key) ->
        add_decision(
          context,
          decision(
            repository,
            task,
            "already_claimed",
            false,
            "Task is already claimed by this daemon process."
          )
        )

      context.claims_this_tick >= state.limits.max_claims_per_tick ->
        context
        |> add_decision(
          decision(
            repository,
            task,
            "max_claims_per_tick_reached",
            false,
            "The daemon already claimed the maximum number of tasks for this tick."
          )
        )
        |> Map.put(:halted?, true)

      Map.get(context.repo_claims, repository["key"], 0) >= state.limits.max_claims_per_repo ->
        add_decision(
          context,
          decision(
            repository,
            task,
            "max_claims_per_repo_reached",
            false,
            "The daemon already claimed a task for this repository in this tick."
          )
        )

      true ->
        claim_and_dispatch(state, repository, task, eligibility, claim_key, context)
    end
  rescue
    error ->
      context
      |> add_decision(
        decision(repository, task, "dispatch_error", false, Exception.message(error))
      )
      |> Map.put(:last_error, %{
        "at" => now(),
        "repo" => repository["key"],
        "task" => task["key"],
        "message" => Exception.message(error)
      })
  end

  defp claim_and_dispatch(state, repository, task, eligibility, claim_key, context) do
    claimed = MapSet.put(context.claimed, claim_key)

    result =
      CodingAssistant.start_harness_run(state.registry_path, repository, task["key"], %{
        "eligibility_reason" => eligibility["reason"]
      })

    run_id = result["run"]["id"]

    context
    |> Map.put(:claimed, claimed)
    |> Map.update!(:claims_this_tick, &(&1 + 1))
    |> Map.update!(:active_run_count, &(&1 + 1))
    |> Map.update!(:repo_claims, &Map.update(&1, repository["key"], 1, fn count -> count + 1 end))
    |> Map.put(:last_dispatch, %{
      "at" => now(),
      "repo" => repository["key"],
      "task" => task["key"],
      "runId" => run_id
    })
    |> add_decision(decision(repository, task, "dispatched", true, "Dispatched run #{run_id}."))
  rescue
    error ->
      context
      |> Map.put(:claimed, MapSet.delete(context.claimed, claim_key))
      |> add_decision(
        decision(repository, task, "dispatch_error", false, Exception.message(error))
      )
      |> Map.put(:last_error, %{
        "at" => now(),
        "repo" => repository["key"],
        "task" => task["key"],
        "message" => Exception.message(error)
      })
  end

  defp decision(repository, task, code, dispatched?, reason) do
    %{
      "at" => now(),
      "repo" => repository["key"],
      "task" => task["key"],
      "code" => code,
      "dispatched" => dispatched?,
      "reason" => reason
    }
  end

  defp take_recent(decisions) do
    decisions
    |> List.wrap()
    |> Enum.take(@max_recent_decisions)
  end

  defp add_decision(context, decision) do
    Map.update!(context, :decisions, &(&1 ++ [decision]))
  end

  defp active_run_count do
    RunStore.list()
    |> Enum.count(&RunEvents.active?/1)
  rescue
    _error -> 0
  end

  defp public_limits(limits) do
    %{
      "maxClaimsPerTick" => limits.max_claims_per_tick,
      "maxClaimsPerRepo" => limits.max_claims_per_repo,
      "maxConcurrentRuns" => limits.max_concurrent_runs
    }
  end

  defp status_payload(state) do
    %{
      "running" => true,
      "online" => true,
      "mode" => "local_service",
      "intervalMs" => state.interval_ms,
      "limits" => public_limits(state.limits),
      "providerReadiness" => ProviderCatalog.harness_status(),
      "lastHeartbeatAt" => state.last_heartbeat_at,
      "lastDispatch" => state.last_dispatch,
      "lastError" => state.last_error,
      "recentDecisions" => Enum.reverse(state.recent_decisions)
    }
  end

  defp schedule_tick(interval_ms), do: Process.send_after(self(), :tick, interval_ms)

  defp interval_ms do
    case Integer.parse(System.get_env("SYMPHONIA_HARNESS_DAEMON_INTERVAL_MS") || "") do
      {value, ""} when value > 0 -> value
      _ -> 15_000
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
