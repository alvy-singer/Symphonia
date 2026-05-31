defmodule SymphoniaService.Sandbox.Session do
  @moduledoc """
  Private sandbox session state helpers.
  """

  @states ~w(created prepared running released release_failed)

  def states, do: @states

  def new(provider, attrs \\ %{}) do
    now = now()

    attrs
    |> Map.merge(%{
      "provider" => provider,
      "state" => "created",
      "created_at" => now,
      "updated_at" => now,
      "release_required" => true,
      "persistent" => false,
      "workspace_kind" => "cloud_sandbox"
    })
    |> reject_nil()
  end

  def mark(session, state) when state in @states do
    session
    |> Map.put("state", state)
    |> Map.put("updated_at", now())
  end

  def cleanup_warning do
    %{
      "code" => "sandbox_release_failed",
      "message" => "Sandbox cleanup needs attention."
    }
  end

  def public_context(session) when is_map(session) do
    %{
      "workspaceProvider" => "cloud_sandbox",
      "sandboxProvider" => label(session["provider"]),
      "persistent" => false,
      "releaseRequired" => session["release_required"] == true
    }
    |> reject_nil()
  end

  def label("fake_sandbox"), do: "Fake sandbox"
  def label("opensandbox"), do: "OpenSandbox"
  def label(value) when is_binary(value) and value != "", do: value
  def label(_value), do: "Sandbox provider"

  defp reject_nil(map), do: map |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new()
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
