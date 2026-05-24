defmodule SymphoniaService.GitHub.TokenStore do
  @moduledoc """
  Encrypted local storage for GitHub App user tokens.

  Files live under `~/.symphonia` by default and are never written inside a
  managed repository.
  """

  @key_file "github.key"
  @token_file "github_tokens.enc"
  @version 1

  def public_connection(opts \\ []) do
    case load(opts) do
      {:ok, connection} ->
        %{
          "connected" => true,
          "user" => Map.get(connection, "user"),
          "connectedAt" => Map.get(connection, "connected_at"),
          "accessTokenExpiresAt" => get_in(connection, ["token", "access_token_expires_at"]),
          "refreshTokenExpiresAt" => get_in(connection, ["token", "refresh_token_expires_at"]),
          "installationUrl" => System.get_env("SYMPHONIA_GITHUB_INSTALL_URL")
        }

      :none ->
        %{
          "connected" => false,
          "installationUrl" => System.get_env("SYMPHONIA_GITHUB_INSTALL_URL")
        }
    end
  end

  def load(opts \\ []) do
    path = token_path(opts)

    case File.read(path) do
      {:ok, encrypted} ->
        {:ok, decrypt(encrypted, key(opts))}

      {:error, :enoent} ->
        :none

      {:error, reason} ->
        raise File.Error, reason: reason, action: "read file", path: path
    end
  end

  def save_token_response(token_response, user, opts \\ []) do
    token = token_from_response(token_response)

    connection = %{
      "user" => public_user(user),
      "token" => token,
      "connected_at" => now_iso()
    }

    save(connection, opts)
    connection
  end

  def replace_token(existing_connection, token_response, opts \\ []) do
    connection =
      existing_connection
      |> Map.put("token", token_from_response(token_response))
      |> Map.put("updated_at", now_iso())

    save(connection, opts)
    connection
  end

  def save(connection, opts \\ []) when is_map(connection) do
    path = token_path(opts)
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, encrypt(connection, key(opts)))
    chmod_private(path)
    connection
  end

  defp token_from_response(response) do
    now = DateTime.utc_now()

    %{
      "access_token" => Map.fetch!(response, "access_token"),
      "refresh_token" => Map.get(response, "refresh_token"),
      "token_type" => Map.get(response, "token_type"),
      "scope" => Map.get(response, "scope"),
      "access_token_expires_at" => expires_at(now, Map.get(response, "expires_in")),
      "refresh_token_expires_at" => expires_at(now, Map.get(response, "refresh_token_expires_in"))
    }
  end

  defp public_user(user) do
    %{
      "id" => Map.get(user, "id"),
      "login" => Map.get(user, "login"),
      "avatarUrl" => Map.get(user, "avatar_url"),
      "url" => Map.get(user, "html_url")
    }
  end

  defp expires_at(_now, nil), do: nil

  defp expires_at(now, seconds) when is_integer(seconds) do
    now |> DateTime.add(seconds, :second) |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end

  defp expires_at(now, seconds) when is_binary(seconds) do
    case Integer.parse(seconds) do
      {value, ""} -> expires_at(now, value)
      _ -> nil
    end
  end

  defp encrypt(connection, key) do
    plaintext = JSON.encode!(connection)
    iv = :crypto.strong_rand_bytes(12)
    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, "", true)

    JSON.encode!(%{
      "version" => @version,
      "iv" => Base.encode64(iv),
      "tag" => Base.encode64(tag),
      "ciphertext" => Base.encode64(ciphertext)
    })
  end

  defp decrypt(encrypted, key) do
    payload = JSON.decode!(encrypted)

    if payload["version"] != @version do
      raise ArgumentError, "Unsupported GitHub token store version."
    end

    iv = Base.decode64!(payload["iv"])
    tag = Base.decode64!(payload["tag"])
    ciphertext = Base.decode64!(payload["ciphertext"])
    plaintext = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, "", tag, false)
    JSON.decode!(plaintext)
  end

  defp key(opts) do
    path = key_path(opts)

    case File.read(path) do
      {:ok, encoded} ->
        Base.decode64!(String.trim(encoded))

      {:error, :enoent} ->
        generated = :crypto.strong_rand_bytes(32)
        path |> Path.dirname() |> File.mkdir_p!()
        File.write!(path, Base.encode64(generated))
        chmod_private(path)
        generated

      {:error, reason} ->
        raise File.Error, reason: reason, action: "read file", path: path
    end
  end

  defp token_path(opts), do: Path.join(home(opts), @token_file)
  defp key_path(opts), do: Path.join(home(opts), @key_file)

  defp home(opts) do
    opts[:home] ||
      Application.get_env(:symphonia_service, :github_home) ||
      System.get_env("SYMPHONIA_HOME") ||
      Path.join(System.user_home!(), ".symphonia")
  end

  defp chmod_private(path) do
    File.chmod(path, 0o600)
    :ok
  rescue
    _ -> :ok
  end

  defp now_iso, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
