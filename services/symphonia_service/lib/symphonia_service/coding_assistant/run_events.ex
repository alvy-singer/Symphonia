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
    "queued" => "Preparing repository",
    "running" => "Running Coding Assistant",
    "completed" => "Writing handoff",
    "failed" => "Run failed",
    "canceled" => "Canceled"
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

  def public_message(%{"state" => "canceled"} = run) do
    run["message"] || "Run canceled. The task is paused. You can retry when ready."
  end

  def public_message(%{"state" => "failed"} = run) do
    run["message"] || "The Coding Assistant run failed."
  end

  def public_message(_run), do: nil
end
