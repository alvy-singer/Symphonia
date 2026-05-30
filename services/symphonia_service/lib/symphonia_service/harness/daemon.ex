defmodule SymphoniaService.Harness.Daemon do
  @moduledoc """
  Always-on scheduler for enabled repositories.
  """

  use GenServer

  alias SymphoniaService.{CodingAssistant, RepositoryRegistry, TaskStore}
  alias SymphoniaService.Access.{Actor, AuditLog}
  alias SymphoniaService.CodingAssistant.{BranchManager, ProviderCatalog, RunEvents, RunStore}
  alias SymphoniaService.Runners.Registry, as: RunnerRegistry

  alias SymphoniaService.Harness.{
    Automation,
    DecisionLog,
    Eligibility,
    LocalState,
    Reconciler,
    RetryPolicy
  }

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
  def pause(name \\ __MODULE__), do: GenServer.call(name, :pause)
  def resume(name \\ __MODULE__), do: GenServer.call(name, :resume)
  def reconcile(name \\ __MODULE__), do: GenServer.call(name, :reconcile, 30_000)
  def status(name \\ __MODULE__), do: GenServer.call(name, :status)

  def peek_status(registry_path \\ SymphoniaService.default_registry_path(), name \\ __MODULE__) do
    case Process.whereis(name) do
      nil -> offline_status(registry_path)
      _pid -> GenServer.call(name, :peek_status)
    end
  end

  @impl true
  def init(opts) do
    registry_path = Keyword.get(opts, :registry_path, SymphoniaService.default_registry_path())
    reliability_opts = reliability_opts(opts)
    local_state = LocalState.load(registry_path)
    reconciliation = reconcile_once(registry_path, reliability_opts)

    state = %{
      registry_path: registry_path,
      interval_ms: Keyword.get(opts, :interval_ms, interval_ms()),
      limits: %{
        max_claims_per_tick: Keyword.get(opts, :max_claims_per_tick, @max_claims_per_tick),
        max_claims_per_repo: Keyword.get(opts, :max_claims_per_repo, @max_claims_per_repo),
        max_concurrent_runs: Keyword.get(opts, :max_concurrent_runs, @max_concurrent_runs)
      },
      reliability_opts: reliability_opts,
      local_state: local_state,
      last_reconciliation: reconciliation.summary,
      last_heartbeat_at: nil,
      last_dispatch: nil,
      last_error: nil,
      recent_decisions: take_recent(reconciliation.decisions),
      claimed: MapSet.new(),
      timer?: Keyword.get(opts, :timer?, true)
    }

    if state.timer?, do: schedule_tick(state.interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    state = refresh_local_state(state)
    {:reply, status_payload(state), state}
  end

  def handle_call(:peek_status, _from, state) do
    state = refresh_local_state(state)
    {:reply, status_payload(state, :check_only), state}
  end

  def handle_call(:pause, _from, state) do
    local_state = LocalState.pause(state.registry_path)

    decision =
      DecisionLog.pause("harness_paused", "Harness paused. No new tasks will be claimed.")

    state = record_decisions(%{state | local_state: local_state}, [decision])
    {:reply, Map.merge(status_payload(state), %{"decisions" => [decision]}), state}
  end

  def handle_call(:resume, _from, state) do
    local_state = LocalState.resume(state.registry_path)

    decision =
      DecisionLog.pause("harness_resumed", "Harness resumed. Eligible tasks may be claimed.")

    state = record_decisions(%{state | local_state: local_state}, [decision])
    {:reply, Map.merge(status_payload(state), %{"decisions" => [decision]}), state}
  end

  def handle_call(:reconcile, _from, state) do
    reconciliation = reconcile_once(state.registry_path, state.reliability_opts)

    state =
      state
      |> refresh_local_state()
      |> Map.put(:last_reconciliation, reconciliation.summary)
      |> record_decisions(reconciliation.decisions)

    {:reply, Map.merge(status_payload(state), %{"decisions" => reconciliation.decisions}), state}
  end

  def handle_call(:tick, _from, state) do
    local_state = LocalState.mark_manual_tick(state.registry_path)
    {decisions, state} = dispatch_once(%{state | local_state: local_state}, manual?: true)
    {:reply, Map.merge(status_payload(state), %{"decisions" => decisions}), state}
  end

  @impl true
  def handle_info(:tick, state) do
    {_decisions, state} = dispatch_once(state, manual?: false)
    if state.timer?, do: schedule_tick(state.interval_ms)
    {:noreply, state}
  end

  defp dispatch_once(state, opts) do
    heartbeat_at = now()
    reconciliation = reconcile_once(state.registry_path, state.reliability_opts)

    state =
      state
      |> refresh_local_state()
      |> Map.put(:last_heartbeat_at, heartbeat_at)
      |> Map.put(:last_reconciliation, reconciliation.summary)

    pause_decisions =
      if paused?(state) do
        [
          DecisionLog.pause(
            "harness_paused",
            "Harness is paused. Manual checks and reconciliation ran, but no task was claimed."
          )
        ]
      else
        []
      end

    {dispatch_decisions, state} =
      if paused?(state) do
        {[], state}
      else
        dispatch_unpaused(state, opts)
      end

    decisions = reconciliation.decisions ++ pause_decisions ++ dispatch_decisions
    state = record_decisions(state, decisions)
    {decisions, state}
  end

  defp dispatch_unpaused(state, _opts) do
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
      state
      |> dispatch_due_retries(dispatch_context)
      |> maybe_dispatch_eligible_tasks(state)

    state = %{
      state
      | claimed: context.claimed,
        last_dispatch: context.last_dispatch,
        last_error: context.last_error
    }

    {context.decisions, state}
  end

  defp maybe_dispatch_eligible_tasks(%{halted?: true} = context, _state), do: context

  defp maybe_dispatch_eligible_tasks(context, state) do
    state.registry_path
    |> RepositoryRegistry.list()
    |> Enum.filter(&Automation.enabled?/1)
    |> Enum.reduce_while(context, fn repository, context ->
      context = dispatch_repository(state, repository, context)

      if context.halted? do
        {:halt, context}
      else
        {:cont, context}
      end
    end)
  end

  defp dispatch_due_retries(state, context) do
    RunStore.list()
    |> Enum.filter(&RetryPolicy.due?/1)
    |> Enum.sort_by(&(&1["retry_at"] || ""))
    |> Enum.reduce_while(context, fn run, context ->
      context = dispatch_retry(state, run, context)

      if context.halted? do
        {:halt, context}
      else
        {:cont, context}
      end
    end)
  end

  defp dispatch_retry(state, run, context) do
    repository = RepositoryRegistry.get(state.registry_path, run["repository"])
    task = if repository, do: TaskStore.get_task(repository, run["task"])
    claim_key = "#{run["repository"]}:#{run["task"]}"

    cond do
      repository == nil ->
        add_decision(
          context,
          DecisionLog.retry(
            run["repository"],
            run["task"],
            "retry_repository_missing",
            "Retry skipped because the repository is no longer registered.",
            run_id: run["id"],
            dispatched: false
          )
        )

      task == nil ->
        add_decision(
          context,
          DecisionLog.retry(
            repository,
            run["task"],
            "retry_task_missing",
            "Retry skipped because the task is missing.",
            run_id: run["id"],
            dispatched: false
          )
        )

      retry_blocked_by_task?(task) ->
        RunStore.update_metadata(run, %{"retry_at" => nil})

        add_decision(
          context,
          DecisionLog.retry(
            repository,
            task,
            "retry_no_longer_allowed",
            "Retry skipped because the task now has a handoff, pull request, or terminal state.",
            run_id: run["id"],
            dispatched: false
          )
        )

      task["pausedReason"] != "waiting_for_sync" ->
        add_decision(
          context,
          DecisionLog.retry(
            repository,
            task,
            "retry_not_waiting_for_sync",
            "Retry skipped because the task is not paused for a transient Harness retry.",
            run_id: run["id"],
            dispatched: false
          )
        )

      context.active_run_count >= state.limits.max_concurrent_runs ->
        context
        |> add_decision(
          DecisionLog.skip(
            repository,
            task,
            "max_concurrent_runs_reached",
            "The daemon is already running the maximum number of Coding Assistant runs."
          )
        )
        |> Map.put(:halted?, true)

      context.claims_this_tick >= state.limits.max_claims_per_tick ->
        context
        |> add_decision(
          DecisionLog.skip(
            repository,
            task,
            "max_claims_per_tick_reached",
            "The daemon already claimed the maximum number of tasks for this tick."
          )
        )
        |> Map.put(:halted?, true)

      Map.get(context.repo_claims, repository["key"], 0) >= state.limits.max_claims_per_repo ->
        add_decision(
          context,
          DecisionLog.skip(
            repository,
            task,
            "max_claims_per_repo_reached",
            "The daemon already claimed a task for this repository in this tick."
          )
        )

      MapSet.member?(context.claimed, claim_key) ->
        add_decision(
          context,
          DecisionLog.skip(
            repository,
            task,
            "already_claimed",
            "Task is already claimed by this daemon process."
          )
        )

      true ->
        claim_retry(state, repository, task, run, claim_key, context)
    end
  rescue
    error ->
      context
      |> add_decision(
        DecisionLog.error(run["repository"], run["task"], "retry_error", Exception.message(error))
      )
      |> Map.put(:last_error, %{
        "at" => now(),
        "repo" => run["repository"],
        "task" => run["task"],
        "message" => Exception.message(error)
      })
  end

  defp claim_retry(state, repository, task, run, claim_key, context) do
    claimed = MapSet.put(context.claimed, claim_key)
    retry_reason = run["retry_reason"] || "Retrying transient Harness failure."

    RunStore.update_metadata(run, %{"retry_at" => nil, "retry_dispatched_at" => now()})

    result =
      CodingAssistant.start_harness_run(state.registry_path, repository, task["key"], %{
        "eligibility_reason" => retry_reason,
        "attempt" => RetryPolicy.next_attempt(run),
        "max_attempts" => run["max_attempts"] || RetryPolicy.max_attempts(),
        "retry_of" => run["id"],
        "retry_reason" => retry_reason
      })

    run_id = result["run"]["id"]
    audit_dispatch(state.registry_path, repository, task, result["run"], "harness.retry_dispatch")

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
    |> add_decision(
      DecisionLog.retry(
        repository,
        task,
        "retry_dispatched",
        "Retrying transient Harness failure.",
        run_id: run_id,
        dispatched: true
      )
    )
  rescue
    error ->
      context
      |> Map.put(:claimed, MapSet.delete(context.claimed, claim_key))
      |> add_decision(
        DecisionLog.error(repository, task, "retry_error", Exception.message(error))
      )
      |> Map.put(:last_error, %{
        "at" => now(),
        "repo" => repository["key"],
        "task" => task["key"],
        "message" => Exception.message(error)
      })
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
          DecisionLog.skip(
            repository,
            task,
            "max_concurrent_runs_reached",
            "The daemon is already running the maximum number of Coding Assistant runs."
          )
        )
        |> Map.put(:halted?, true)

      not eligibility["eligible"] ->
        add_decision(
          context,
          DecisionLog.skip(repository, task, eligibility["code"], eligibility["reason"])
        )

      MapSet.member?(context.claimed, claim_key) ->
        add_decision(
          context,
          DecisionLog.skip(
            repository,
            task,
            "already_claimed",
            "Task is already claimed by this daemon process."
          )
        )

      context.claims_this_tick >= state.limits.max_claims_per_tick ->
        context
        |> add_decision(
          DecisionLog.skip(
            repository,
            task,
            "max_claims_per_tick_reached",
            "The daemon already claimed the maximum number of tasks for this tick."
          )
        )
        |> Map.put(:halted?, true)

      Map.get(context.repo_claims, repository["key"], 0) >= state.limits.max_claims_per_repo ->
        add_decision(
          context,
          DecisionLog.skip(
            repository,
            task,
            "max_claims_per_repo_reached",
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
        DecisionLog.error(repository, task, "dispatch_error", Exception.message(error))
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
    audit_dispatch(state.registry_path, repository, task, result["run"], "harness.dispatch")

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
    |> add_decision(
      DecisionLog.dispatch(repository, task, "dispatched", "Dispatched run #{run_id}.",
        run_id: run_id
      )
    )
  rescue
    error ->
      context
      |> Map.put(:claimed, MapSet.delete(context.claimed, claim_key))
      |> add_decision(
        DecisionLog.error(repository, task, "dispatch_error", Exception.message(error))
      )
      |> Map.put(:last_error, %{
        "at" => now(),
        "repo" => repository["key"],
        "task" => task["key"],
        "message" => Exception.message(error)
      })
  end

  defp audit_dispatch(registry_path, repository, task, run, action) do
    AuditLog.record(registry_path, repository, %{
      "actor" => Actor.harness(),
      "action" => action,
      "target" => %{"type" => "task", "id" => task["key"]},
      "result" => "completed",
      "metadata" => %{
        "runId" => run["id"],
        "taskKey" => task["key"],
        "provider" => run["provider"],
        "workspaceProvider" => run["workspaceProvider"] || run["workspace_provider"]
      }
    })
  rescue
    _error -> :ok
  end

  defp retry_blocked_by_task?(task) do
    task["status"] in ["completed", "canceled", "in_review"] or present?(task["handoff"]) or
      present?(task["githubPr"]) or task["githubPrState"] in ["open", "merged"] or
      review_branch_exists?(task)
  end

  defp review_branch_exists?(task) do
    repository = task[:repository]
    repository && BranchManager.review_branch_exists?(repository, task)
  rescue
    _error -> false
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value) when is_map(value), do: map_size(value) > 0
  defp present?(_value), do: false

  defp take_recent(decisions) do
    decisions
    |> List.wrap()
    |> Enum.take(@max_recent_decisions)
  end

  defp add_decision(context, decision) do
    Map.update!(context, :decisions, &(&1 ++ [decision]))
  end

  defp record_decisions(state, []), do: state

  defp record_decisions(state, decisions) do
    %{state | recent_decisions: take_recent(decisions ++ state.recent_decisions)}
  end

  defp reconcile_once(registry_path, reliability_opts) do
    result = Reconciler.reconcile(registry_path, reliability_opts)
    LocalState.mark_reconciliation(registry_path, result.summary)
    result
  end

  defp refresh_local_state(state) do
    %{state | local_state: LocalState.load(state.registry_path)}
  end

  defp paused?(state), do: state.local_state["paused"] == true

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

  defp status_payload(state, provider_mode \\ :normal) do
    counts = Reconciler.counts(state.registry_path, state.reliability_opts)

    %{
      "running" => true,
      "online" => true,
      "paused" => paused?(state),
      "mode" => "local_service",
      "intervalMs" => state.interval_ms,
      "limits" => public_limits(state.limits),
      "activeRuns" => counts["activeRuns"],
      "staleRuns" => counts["staleRuns"],
      "retryScheduled" => counts["retryScheduled"],
      "runners" => RunnerRegistry.capacity(state.registry_path),
      "providerReadiness" => ProviderCatalog.harness_status(mode: provider_mode),
      "lastHeartbeatAt" => state.last_heartbeat_at,
      "lastDispatch" => state.last_dispatch,
      "lastError" => state.last_error,
      "lastReconciliation" =>
        state.last_reconciliation || state.local_state["lastReconciliation"],
      "recentDecisions" => Enum.reverse(state.recent_decisions)
    }
  end

  defp reliability_opts(opts) do
    [
      queued_stale_after_ms: Keyword.get(opts, :queued_stale_after_ms, 10 * 60 * 1_000),
      running_stale_after_ms: Keyword.get(opts, :running_stale_after_ms, 60 * 60 * 1_000),
      heartbeat_stale_after_ms: Keyword.get(opts, :heartbeat_stale_after_ms, 10 * 60 * 1_000)
    ]
  end

  defp schedule_tick(interval_ms), do: Process.send_after(self(), :tick, interval_ms)

  defp offline_status(registry_path) do
    local_state = LocalState.load(registry_path)
    counts = Reconciler.counts(registry_path, reliability_opts([]))

    %{
      "running" => false,
      "online" => false,
      "paused" => local_state["paused"] == true,
      "mode" => "local_service",
      "intervalMs" => interval_ms(),
      "limits" =>
        public_limits(%{
          max_claims_per_tick: @max_claims_per_tick,
          max_claims_per_repo: @max_claims_per_repo,
          max_concurrent_runs: @max_concurrent_runs
        }),
      "activeRuns" => counts["activeRuns"],
      "staleRuns" => counts["staleRuns"],
      "retryScheduled" => counts["retryScheduled"],
      "runners" => RunnerRegistry.capacity(registry_path),
      "providerReadiness" => ProviderCatalog.readiness_status(mode: :check_only),
      "lastHeartbeatAt" => nil,
      "lastDispatch" => nil,
      "lastError" => nil,
      "lastReconciliation" => local_state["lastReconciliation"],
      "recentDecisions" => []
    }
  end

  defp interval_ms do
    case Integer.parse(System.get_env("SYMPHONIA_HARNESS_DAEMON_INTERVAL_MS") || "") do
      {value, ""} when value > 0 -> value
      _ -> 15_000
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
