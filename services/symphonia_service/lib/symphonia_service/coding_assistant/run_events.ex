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
    "Queued for runner" => "Queued for runner",
    "Claimed by runner" => "Claimed by runner",
    "Running on runner" => "Running on runner",
    "Receiving remote result" => "Receiving result",
    "Importing returned patch" => "Importing returned patch",
    "Checking imported changes" => "Importing returned patch",
    "Validating imported changes" => "Validating imported changes",
    "Creating sandbox" => "Creating sandbox",
    "Preparing sandbox workspace" => "Preparing sandbox workspace",
    "Running Codex in sandbox" => "Running Codex in sandbox",
    "Running Gemini in sandbox" => "Running Gemini in sandbox",
    "Receiving sandbox changes" => "Receiving sandbox changes",
    "Releasing sandbox" => "Releasing sandbox",
    "Sandbox released" => "Sandbox released",
    "Sandbox cleanup needs attention" => "Sandbox cleanup needs attention",
    "Running Coding Assistant" => "Starting Codex",
    "Detecting changed files" => "Checking changes",
    "Running validation" => "Running validation",
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
      "Queued for runner" -> "Symphonia queued this run for the selected runner."
      "Claimed by runner" -> "The selected runner claimed this assignment."
      "Running on runner" -> "The selected runner is working on this task."
      "Receiving result" -> "Symphonia is receiving the runner's patch result."
      "Importing returned patch" -> "Symphonia is importing the returned patch locally."
      "Validating imported changes" -> "Symphonia is validating imported changes locally."
      "Creating sandbox" -> "Symphonia is creating an isolated sandbox workspace."
      "Preparing sandbox workspace" -> "Symphonia is preparing the sandbox workspace."
      "Running Codex in sandbox" -> "Codex is working inside the sandbox."
      "Running Gemini in sandbox" -> "Gemini CLI is working inside the sandbox."
      "Receiving sandbox changes" -> "Symphonia is receiving the sandbox patch result."
      "Releasing sandbox" -> "Symphonia is releasing the sandbox workspace."
      "Sandbox released" -> "Sandbox workspace released."
      "Sandbox cleanup needs attention" -> "Sandbox cleanup needs attention."
      "Starting Codex" -> "Codex is working from the task brief."
      "Checking changes" -> "Codex finished its turn and Symphonia is checking the changed files."
      "Running validation" -> "Symphonia is running local validation for the handoff."
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
