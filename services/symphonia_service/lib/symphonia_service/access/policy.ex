defmodule SymphoniaService.Access.Policy do
  @moduledoc """
  Repository-scoped V1 authorization policy.
  """

  alias SymphoniaService.Access.Permission

  def allowed?(actor, permission, _repository \\ nil, _target \\ nil) do
    actor
    |> role()
    |> Permission.allowed?(permission)
  end

  def authorize(actor, permission, repository \\ nil, target \\ nil) do
    if allowed?(actor, permission, repository, target) do
      :ok
    else
      {:error,
       %{
         "error" => Permission.denial_message(permission),
         "permission" => permission
       }}
    end
  end

  def permissions_for(actor) do
    actor
    |> role()
    |> Permission.permissions_for_role()
  end

  defp role(%{"role" => role}) when is_binary(role), do: role
  defp role(%{role: role}) when is_binary(role), do: role
  defp role(_actor), do: "viewer"
end
