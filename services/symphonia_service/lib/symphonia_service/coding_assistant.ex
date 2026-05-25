defmodule SymphoniaService.CodingAssistant do
  @moduledoc """
  Facade for assigning tasks to Coding Assistants.
  """

  alias SymphoniaService.Clarise.{ChecklistSerializer, FeedbackStructurer, ReviewNotesBuilder}
  alias SymphoniaService.CodingAssistant.{HandoffBuilder, LocalDemoProvider, RunStore}
  alias SymphoniaService.TaskStore

  @continuation_max_attempts 2

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

  def continue_from_review_notes(_registry_path, repository, task_key, params \\ %{}) do
    task = get_task!(repository, task_key)
    ensure_reviewable!(task)

    feedback = required_feedback!(params)
    requested_changes = FeedbackStructurer.structure(feedback)

    if requested_changes == [] do
      raise ArgumentError, "Feedback must describe at least one requested change."
    end

    review_note = ReviewNotesBuilder.build(feedback, requested_changes)
    assistant_input = ChecklistSerializer.serialize(requested_changes)

    continuation = continuation_state(review_note["id"], 1)
    ReviewNotesBuilder.apply(repository, task_key, review_note, continuation)

    {run, task} =
      run_continuation_attempt(repository, task_key, review_note, assistant_input, params, 1)

    %{"review_note" => review_note, "run" => RunStore.public(run), "task" => task}
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

  defp ensure_reviewable!(%{"status" => "in_review"}), do: :ok

  defp ensure_reviewable!(_task) do
    raise ArgumentError, "Request changes is available for In Review tasks."
  end

  defp run_continuation_attempt(repository, task_key, review_note, assistant_input, params, attempt) do
    provider = provider()
    task = get_task!(repository, task_key)

    run =
      RunStore.create(%{
        "provider" => "local_demo",
        "repository" => repository["key"],
        "task" => task_key,
        "kind" => "review_continuation",
        "input" => assistant_input,
        "review_note_id" => review_note["id"],
        "attempt" => attempt,
        "max_attempts" => @continuation_max_attempts
      })

    running_run = RunStore.mark_running(run)
    provider_params = provider_params(params, assistant_input, review_note, attempt)

    case provider.run(repository, task, running_run, provider_params) do
      {:ok, handoff} ->
        completed_run = RunStore.mark_completed(running_run, handoff)
        task = HandoffBuilder.apply(repository, task_key, completed_run, handoff)
        {completed_run, task}

      {:error, reason} ->
        failed_run = RunStore.mark_failed(running_run, reason)

        if attempt < @continuation_max_attempts do
          TaskStore.patch_task(repository, task_key, %{
            "frontmatter" => %{
              "review_continuation" => continuation_state(review_note["id"], attempt + 1)
            }
          })

          run_continuation_attempt(
            repository,
            task_key,
            review_note,
            assistant_input,
            params,
            attempt + 1
          )
        else
          TaskStore.apply_event(repository, task_key, "fail_run", %{
            "explanation" =>
              "The Coding Assistant could not produce a new handoff after your requested changes."
          })

          task =
            TaskStore.patch_task(repository, task_key, %{
              "frontmatter" => %{
                "run" => run_frontmatter(failed_run),
                "review_continuation" => continuation_state(review_note["id"], attempt)
              }
            })

          {failed_run, task}
        end
    end
  end

  defp provider_params(params, assistant_input, review_note, attempt) do
    %{
      "assistant_input" => assistant_input,
      "review_note_id" => review_note["id"],
      "continuation" => true,
      "forceFailure" => force_failure?(params, attempt)
    }
  end

  defp force_failure?(params, attempt) do
    cond do
      Map.get(params, "forceFailure") == true or Map.get(params, "force_failure") == true ->
        true

      Map.get(params, "forceFailureOnce") == true or Map.get(params, "force_failure_once") == true ->
        attempt == 1

      is_integer(Map.get(params, "forceFailureAttempts")) ->
        attempt <= Map.get(params, "forceFailureAttempts")

      is_integer(Map.get(params, "force_failure_attempts")) ->
        attempt <= Map.get(params, "force_failure_attempts")

      true ->
        false
    end
  end

  defp required_feedback!(params) do
    case Map.get(params, "feedback") do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: raise(ArgumentError, "Feedback is required."), else: value

      _ ->
        raise ArgumentError, "Feedback is required."
    end
  end

  defp continuation_state(review_note_id, attempt) do
    %{
      "attempt" => attempt,
      "max_attempts" => @continuation_max_attempts,
      "source_review_note_id" => review_note_id
    }
  end

  defp run_frontmatter(run) do
    %{
      "id" => run["id"],
      "state" => run["state"],
      "started_at" => run["started_at"],
      "completed_at" => run["completed_at"]
    }
  end

  defp provider do
    Application.get_env(:symphonia_service, :coding_assistant_provider, LocalDemoProvider)
  end
end
