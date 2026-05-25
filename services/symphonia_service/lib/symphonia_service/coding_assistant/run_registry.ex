defmodule SymphoniaService.CodingAssistant.RunRegistry do
  @moduledoc """
  Registry for active Coding Assistant run workers.
  """

  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: __MODULE__)
  end

  def ensure_started do
    case Process.whereis(__MODULE__) do
      nil ->
        case Registry.start_link(keys: :unique, name: __MODULE__) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, {:already_registered, _pid}} -> :ok
        end

      _pid ->
        :ok
    end
  end

  def via(run_id), do: {:via, Registry, {__MODULE__, run_id}}

  def lookup(run_id) do
    case Registry.lookup(__MODULE__, run_id) do
      [{pid, _value}] -> {:ok, pid}
      [] -> :error
    end
  end
end
