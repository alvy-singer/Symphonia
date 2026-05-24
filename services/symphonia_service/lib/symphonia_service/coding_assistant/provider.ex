defmodule SymphoniaService.CodingAssistant.Provider do
  @moduledoc """
  Behaviour for Coding Assistant providers.

  Providers receive a repository, task, and run record and return a curated
  handoff. Raw provider logs stay in the run store, not in repository files.
  """

  @callback run(map(), map(), map(), map()) :: {:ok, map()} | {:error, String.t()}
end
