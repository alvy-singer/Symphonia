defmodule SymphoniaService.CodingAssistant.RunEvents do
  @moduledoc """
  Curated public labels and steps for Coding Assistant runs.
  """

  @labels %{
    "queued" => "Queued",
    "running" => "Working",
    "completed" => "Ready for review",
    "failed" => "Run failed",
    "canceled" => "Canceled"
  }

  @default_steps %{
    "queued" => "Preparing workspace",
    "running" => "Starting Codex",
    "completed" => "Ready for review",
    "failed" => "Run failed",
    "canceled" => "Canceled"
  }

  @display_steps %{
    "Preparing repository" => "Preparing workspace",
    "Starting Codex App Server" => "Starting Codex App Server",
    "Preparing Codex App Server thread" => "Starting Codex thread",
    "Starting Codex thread" => "Starting Codex thread",
    "Starting Codex turn" => "Starting Codex turn",
    "Codex is working" => "Codex is working",
    "Running Coding Assistant" => "Starting Codex",
    "Detecting changed files" => "Checking changes",
    "Creating branch" => "Checking changes",
    "Creating review branch" => "Checking changes",
    "Writing handoff" => "Writing handoff"
  }

  @active_states ~w(queued running)
  @terminal_states ~w(completed failed canceled)

  def active_states, do: @active_states
  def terminal_states, do: @terminal_states

  def active?(%{"state" => state}), do: state in @active_states
  def active?(_run), do: false

  def terminal?(%{"state" => state}), do: state in @terminal_states
  def terminal?(_run), do: false

  def label(state), do: Map.get(@labels, state, state)
  def default_step(state), do: Map.get(@default_steps, state, label(state))

  def display_step(%{"state" => "completed"}), do: "Ready for review"
  def display_step(%{"state" => "failed"}), do: "Run failed"
  def display_step(%{"state" => "canceled"}), do: "Canceled"

  def display_step(run) when is_map(run) do
    run
    |> Map.get("current_step")
    |> case do
      step when is_binary(step) -> Map.get(@display_steps, step, step)
      _ -> default_step(run["state"])
    end
  end

  def display_step(_run), do: nil

  def display_message(%{"state" => "queued"}) do
    "Codex is preparing a clean workspace for this task."
  end

  def display_message(%{"state" => "running"} = run) do
    case display_step(run) do
      "Preparing workspace" -> "Codex is preparing a clean workspace for this task."
      "Starting Codex App Server" -> "Symphonia is starting Codex App Server."
      "Starting Codex thread" -> "Symphonia is preparing the Codex thread for this task."
      "Starting Codex turn" -> "Symphonia is starting the Codex turn."
      "Codex is working" -> "Codex is working from the task brief."
      "Starting Codex" -> "Codex is working from the task brief."
      "Checking changes" -> "Codex finished its turn and Symphonia is checking the changed files."
      "Writing handoff" -> "Symphonia is writing a review handoff."
      _ -> "Codex is working on this task."
    end
  end

  def display_message(%{"state" => "completed"}) do
    "Codex produced a handoff that is ready for review."
  end

  def display_message(%{"state" => "failed"} = run), do: public_message(run)
  def display_message(%{"state" => "canceled"} = run), do: public_message(run)
  def display_message(_run), do: nil

  def public_message(%{"state" => "canceled"} = run) do
    run["message"] || "Run canceled. The task is paused. You can retry when ready."
  end

  def public_message(%{"state" => "failed"} = run) do
    run["message"] || "The Coding Assistant run failed."
  end

  def public_message(_run), do: nil
end
