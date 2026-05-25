defmodule SymphoniaService.CodingAssistant.Cancellation do
  @moduledoc """
  Cancel active Coding Assistant runs without canceling the task.
  """

  alias SymphoniaService.CodingAssistant.{RunEvents, RunRegistry, RunStore, RunWorker}

  def cancel(run_id) when is_binary(run_id) do
    case RunRegistry.lookup(run_id) do
      {:ok, pid} ->
        RunWorker.cancel(pid)

      :error ->
        case RunStore.get(run_id) do
          nil ->
            {:error, "Run #{run_id} not found."}

          run ->
            if RunEvents.terminal?(run) do
              {:ok, %{"run" => RunStore.public(run), "task" => nil}}
            else
              {:error, "The run is no longer active."}
            end
        end
    end
  end
end
