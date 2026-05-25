defmodule SymphoniaService.CodingAssistant.RunSupervisor do
  @moduledoc """
  Dynamic supervisor for background Coding Assistant runs.
  """

  use DynamicSupervisor

  alias SymphoniaService.{RepositoryRegistry, TaskStore}

  alias SymphoniaService.CodingAssistant.{
    RunEvents,
    RunRegistry,
    RunStore,
    RunWorker
  }

  @interrupted_message "The Coding Assistant stopped because Symphonía restarted during the run."

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def ensure_started(registry_path \\ SymphoniaService.default_registry_path()) do
    RunRegistry.ensure_started()

    case Process.whereis(__MODULE__) do
      nil ->
        case DynamicSupervisor.start_link(
               __MODULE__,
               [registry_path: registry_path, recover: false],
               name: __MODULE__
             ) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, {:already_registered, _pid}} -> :ok
        end

      _pid ->
        :ok
    end
  end

  def start_run(attrs) when is_map(attrs) do
    ensure_started(attrs["registry_path"] || SymphoniaService.default_registry_path())

    case DynamicSupervisor.start_child(__MODULE__, {RunWorker, attrs}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end

  def recover_interrupted_runs(registry_path, opts \\ []) do
    for run <- RunStore.list(opts), RunEvents.active?(run) do
      failed_run = RunStore.mark_failed(run, @interrupted_message, @interrupted_message, opts)

      case RepositoryRegistry.get(registry_path, failed_run["repository"]) do
        nil ->
          :ok

        repository ->
          task =
            TaskStore.apply_event(repository, failed_run["task"], "fail_run", %{
              "explanation" => @interrupted_message
            })

          TaskStore.patch_task(repository, task["key"], %{
            "frontmatter" => %{"run" => run_frontmatter(failed_run)}
          })

          :ok
      end
    end

    :ok
  end

  @impl true
  def init(opts) do
    registry_path = Keyword.get(opts, :registry_path, SymphoniaService.default_registry_path())
    if Keyword.get(opts, :recover, true), do: recover_interrupted_runs(registry_path)
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  defp run_frontmatter(run) do
    %{
      "id" => run["id"],
      "state" => run["state"],
      "current_step" => run["current_step"],
      "message" => RunEvents.public_message(run),
      "started_at" => run["started_at"],
      "completed_at" => run["completed_at"]
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
