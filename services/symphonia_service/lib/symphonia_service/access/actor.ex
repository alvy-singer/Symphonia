defmodule SymphoniaService.Access.Actor do
  @moduledoc """
  Lightweight local actor extraction for access checks and audit attribution.
  """

  @roles ~w(owner maintainer reviewer operator viewer)

  def harness do
    %{
      "id" => "harness",
      "name" => "Harness",
      "role" => "operator",
      "source" => "local"
    }
  end

  def default do
    %{
      "id" => "local-user",
      "name" => "Local user",
      "role" => "owner",
      "source" => "local"
    }
  end

  def from_headers(headers) when is_map(headers) do
    role =
      headers
      |> Map.get("x-symphonia-role")
      |> normalize_role()

    name =
      headers
      |> Map.get("x-symphonia-actor")
      |> normalize_name()

    id =
      headers
      |> Map.get("x-symphonia-actor-id")
      |> normalize_id(name)

    %{
      "id" => id,
      "name" => name,
      "role" => role,
      "source" => if(headers["x-symphonia-role"], do: "session", else: "local")
    }
  end

  def from_headers(_headers), do: default()

  def roles, do: @roles

  defp normalize_role(role) when is_binary(role) do
    role = role |> String.trim() |> String.downcase()
    if role in @roles, do: role, else: "owner"
  end

  defp normalize_role(_role), do: "owner"

  defp normalize_name(name) when is_binary(name) do
    case String.trim(name) do
      "" -> "Local user"
      value -> String.slice(value, 0, 80)
    end
  end

  defp normalize_name(_name), do: "Local user"

  defp normalize_id(id, _name) when is_binary(id) do
    case id |> String.trim() |> String.replace(~r/[^a-zA-Z0-9._:-]/, "-") do
      "" -> "local-user"
      value -> String.slice(value, 0, 100)
    end
  end

  defp normalize_id(_id, "Local user"), do: "local-user"

  defp normalize_id(_id, name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "local-user"
      value -> String.slice(value, 0, 100)
    end
  end
end
