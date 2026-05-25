defmodule SymphoniaService.CodingAssistant.LocalDemoProvider do
  @moduledoc """
  Deterministic local provider that exercises the Coding Assistant contract.
  """

  @behaviour SymphoniaService.CodingAssistant.Provider

  alias SymphoniaService.CodingAssistant.{BranchManager, HandoffBuilder, RunStore}

  @impl true
  def id, do: "local_demo"

  @impl true
  def run(repository, task, run, params) do
    if force_failure?(params) do
      {:error, "The Coding Assistant could not produce a reviewable handoff."}
    else
      RunStore.mark_step(run, "Creating branch")
      file = HandoffBuilder.demo_file(task)
      body = HandoffBuilder.demo_body(task, Map.get(params, "assistant_input"))
      branch = BranchManager.create_and_push_demo_change(repository, task, file, body)
      {:ok, HandoffBuilder.build(task, branch)}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp force_failure?(params) do
    Map.get(params, "forceFailure") == true or Map.get(params, "force_failure") == true
  end
end
