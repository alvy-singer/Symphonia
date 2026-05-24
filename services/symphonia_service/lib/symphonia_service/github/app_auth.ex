defmodule SymphoniaService.GitHub.AppAuth do
  @moduledoc """
  GitHub App JWT signing for installation-token access.

  The private key is loaded from the configured path at runtime and is never
  copied into repository files, task Markdown, registry entries, or API
  responses.

  This self-hosted mode is for local development. A hosted production broker
  should own the GitHub App private key and return short-lived installation
  tokens or proxy GitHub requests for the local app.
  """

  @jwt_ttl_seconds 540

  def jwt do
    now = System.system_time(:second)

    header = %{"alg" => "RS256", "typ" => "JWT"}
    claims = %{"iat" => now - 60, "exp" => now + @jwt_ttl_seconds, "iss" => app_id!()}
    signing_input = "#{encode_json(header)}.#{encode_json(claims)}"
    signature = :public_key.sign(signing_input, :sha256, private_key!())

    signing_input <> "." <> base64url(signature)
  end

  def configured? do
    present?(System.get_env("SYMPHONIA_GITHUB_APP_ID")) and
      present?(System.get_env("SYMPHONIA_GITHUB_APP_PRIVATE_KEY_PATH"))
  end

  def install_url do
    case System.get_env("SYMPHONIA_GITHUB_INSTALL_URL") do
      value when is_binary(value) and value != "" ->
        value

      _ ->
        case System.get_env("SYMPHONIA_GITHUB_APP_NAME") do
          name when is_binary(name) and name != "" ->
            "https://github.com/apps/#{name}/installations/new"

          _ ->
            nil
        end
    end
  end

  def manage_url do
    case System.get_env("SYMPHONIA_GITHUB_MANAGE_URL") do
      value when is_binary(value) and value != "" -> value
      _ -> "https://github.com/settings/installations"
    end
  end

  defp app_id! do
    case System.get_env("SYMPHONIA_GITHUB_APP_ID") do
      value when is_binary(value) and value != "" -> value
      _ -> raise ArgumentError, "Set SYMPHONIA_GITHUB_APP_ID to use GitHub App access."
    end
  end

  defp private_key! do
    path =
      case System.get_env("SYMPHONIA_GITHUB_APP_PRIVATE_KEY_PATH") do
        value when is_binary(value) and value != "" ->
          value

        _ ->
          raise ArgumentError,
                "Set SYMPHONIA_GITHUB_APP_PRIVATE_KEY_PATH to use GitHub App access."
      end

    path
    |> File.read!()
    |> :public_key.pem_decode()
    |> case do
      [entry | _] -> :public_key.pem_entry_decode(entry)
      [] -> raise ArgumentError, "GitHub App private key file is empty."
    end
  end

  defp encode_json(value), do: value |> JSON.encode!() |> base64url()
  defp base64url(value), do: Base.url_encode64(value, padding: false)
  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
