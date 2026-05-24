defmodule SymphoniaService.CodingAssistant do
  @moduledoc """
  Facade for assigning tasks to Coding Assistants.
  """

  alias SymphoniaService.CodingAssistant.{HandoffBuilder, LocalDemoProvider, RunStore}
  alias SymphoniaService.TaskStore

  def start_run(_registry_path, repository, task_key, params \\ %{}) do
    task = get_task!(repository, task_key)
    ensure_assignable!(task)

    provider = provider()

    run =
      RunStore.create(%{
        "provider" => "local_demo",
        "repository" => repository["key"],
        "task" => task_key
      })

    running_run = RunStore.mark_running(run)
    TaskStore.apply_event(repository, task_key, "start")

    case provider.run(repository, task, running_run, params) do
      {:ok, handoff} ->
        completed_run = RunStore.mark_completed(running_run, handoff)
        task = HandoffBuilder.apply(repository, task_key, completed_run, handoff)
        %{"run" => RunStore.public(completed_run), "task" => task}

      {:error, reason} ->
        failed_run = RunStore.mark_failed(running_run, reason)

        task =
          TaskStore.apply_event(repository, task_key, "fail_run", %{
            "explanation" => "The Coding Assistant could not produce a reviewable handoff."
          })

        %{"run" => RunStore.public(failed_run), "task" => task}
    end
  end

  defp get_task!(repository, task_key) do
    case TaskStore.get_task(repository, task_key) do
      nil -> raise ArgumentError, "task #{task_key} not found"
      task -> task
    end
  end

  defp ensure_assignable!(%{"status" => "todo"}), do: :ok
  defp ensure_assignable!(%{"status" => "paused", "pausedReason" => "run_failed"}), do: :ok

  defp ensure_assignable!(_task) do
    raise ArgumentError,
          "Assign to Coding Assistant is available for To-do and Paused · Run failed tasks."
  end

  defp provider do
    Application.get_env(:symphonia_service, :coding_assistant_provider, LocalDemoProvider)
  end
end
