defmodule SymphoniaService.Runner.WorkspaceProvider do
  @moduledoc """
  Behaviour for preparing and releasing Coding Assistant workspaces.

  V1 uses the local Git worktree provider. Remote or cloud sandbox providers can
  implement this interface later, but they are not runnable by Harness V1.
  """

  @callback prepare(map(), map(), map(), map()) :: {:ok, map()} | {:error, String.t()}
  @callback release(map(), map()) :: :ok
end
