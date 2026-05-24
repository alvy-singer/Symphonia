defmodule SymphoniaService.GitHub.InstallationToken do
  @moduledoc """
  Short-lived GitHub App installation token cache.
  """

  alias SymphoniaService.GitHub.{AppAuth, Client, Home}

  @refresh_window_seconds 300

  def token_for_installation!(installation_id, opts \\ []) do
    case load_cached(installation_id, opts) do
      {:ok, token} ->
        token

      :miss ->
        refresh!(installation_id, opts)["token"]
    end
  end

  def refresh!(installation_id, opts \\ []) do
    jwt = AppAuth.jwt()

    case client().create_installation_token(jwt, installation_id) do
      {:ok, %{"token" => token} = payload} when is_binary(token) ->
        token_state =
          %{
            "token" => token,
            "expires_at" => payload["expires_at"],
            "permissions" => payload["permissions"],
            "repository_selection" => payload["repository_selection"],
            "updated_at" => now()
          }
          |> reject_nil()

        save(installation_id, token_state, opts)

      {:error, payload} ->
        raise ArgumentError,
              Map.get(payload, "message", "Could not create GitHub installation token.")
    end
  end

  defp load_cached(installation_id, opts) do
    path = token_path(installation_id, opts)

    case File.read(path) do
      {:ok, body} ->
        token = JSON.decode!(body)

        if expired_or_near?(token["expires_at"]) do
          :miss
        else
          {:ok, Map.fetch!(token, "token")}
        end

      {:error, :enoent} ->
        :miss

      {:error, reason} ->
        raise File.Error, reason: reason, action: "read file", path: path
    end
  end

  defp save(installation_id, token_state, opts) do
    path = token_path(installation_id, opts)
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, JSON.encode!(token_state))
    chmod_private(path)
    token_state
  end

  defp expired_or_near?(nil), do: true

  defp expired_or_near?(iso8601) do
    case DateTime.from_iso8601(iso8601) do
      {:ok, expires_at, _offset} ->
        DateTime.compare(
          expires_at,
          DateTime.utc_now() |> DateTime.add(@refresh_window_seconds, :second)
        ) != :gt

      _ ->
        true
    end
  end

  defp token_path(installation_id, opts) do
    safe_id = installation_id |> to_string() |> String.replace(~r/[^0-9A-Za-z_-]/, "")
    Path.join([Home.path(opts), "cache", "installation-#{safe_id}.json"])
  end

  defp client do
    Application.get_env(:symphonia_service, :github_client, Client)
  end

  defp reject_nil(map), do: map |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new()
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp chmod_private(path) do
    File.chmod(path, 0o600)
    :ok
  rescue
    _ -> :ok
  end
end
