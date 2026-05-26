defmodule SymphoniaService.GitHub.DeviceAuth do
  @moduledoc """
  GitHub device-flow user-token authentication.

  This is kept as an explicit local-development fallback, not the primary
  product access model.
  """

  alias SymphoniaService.GitHub.{Client, DeviceFlowLimiter, TokenStore}

  @refresh_window_seconds 300

  def enabled? do
    Application.get_env(:symphonia_service, :github_allow_device_fallback) == true or
      System.get_env("SYMPHONIA_GITHUB_ALLOW_DEVICE_FALLBACK") == "true"
  end

  def public_connection do
    public =
      case TokenStore.public_connection() do
        %{"connected" => false} = connection ->
          if enabled?() and env_token_present?() do
            %{
              connection
              | "connected" => true
            }
            |> Map.put("user", %{"login" => "Environment token"})
            |> Map.put("connectedAt", nil)
            |> Map.put("tokenSource", env_token_source())
          else
            connection
          end

        connection ->
          connection
      end

    public
    |> Map.put("deviceFallbackEnabled", enabled?())
  end

  def start_device_flow do
    ensure_enabled!()
    client_id = client_id!()

    with {:ok, payload} <- client().request_device_code(client_id) do
      DeviceFlowLimiter.record(payload["device_code"], payload["interval"])

      {:ok,
       %{
         "deviceCode" => payload["device_code"],
         "userCode" => payload["user_code"],
         "verificationUri" => payload["verification_uri"],
         "expiresIn" => payload["expires_in"],
         "interval" => payload["interval"]
       }}
    end
  end

  def poll_device_flow(params) do
    ensure_enabled!()
    client_id = client_id!()
    device_code = Map.get(params, "deviceCode") || Map.get(params, "device_code")
    interval = Map.get(params, "interval") || 5

    cond do
      not is_binary(device_code) or String.trim(device_code) == "" ->
        {:error, 400, %{"error" => "GitHub device code is missing."}}

      true ->
        case DeviceFlowLimiter.allow_poll(device_code, interval) do
          :ok ->
            poll_github(client_id, device_code)

          {:error, retry_after} ->
            {:error, 429,
             %{"error" => "Wait before checking GitHub again.", "retryAfter" => retry_after}}
        end
    end
  end

  def user_token! do
    ensure_enabled!()

    case env_token() do
      token when is_binary(token) ->
        token

      nil ->
        stored_user_token!()
    end
  end

  defp stored_user_token! do
    case TokenStore.load() do
      {:ok, connection} ->
        token = Map.fetch!(connection, "token")

        if expires_soon?(token["access_token_expires_at"]) do
          refresh_user_token!(connection)
        else
          Map.fetch!(token, "access_token")
        end

      :none ->
        raise ArgumentError,
              "Connect GitHub with device flow for local testing or set GITHUB_TOKEN."
    end
  end

  defp env_token_present?, do: not is_nil(env_token())

  defp env_token do
    ["GITHUB_TOKEN", "GH_TOKEN"]
    |> Enum.find_value(fn key ->
      case System.get_env(key) do
        value when is_binary(value) and value != "" -> value
        _ -> nil
      end
    end)
  end

  defp env_token_source do
    cond do
      present?(System.get_env("GITHUB_TOKEN")) -> "env:GITHUB_TOKEN"
      present?(System.get_env("GH_TOKEN")) -> "env:GH_TOKEN"
      true -> nil
    end
  end

  defp poll_github(client_id, device_code) do
    case client().poll_device_code(client_id, device_code) do
      {:ok, %{"error" => "authorization_pending"} = payload} ->
        {:pending,
         %{"status" => "authorization_pending", "interval" => Map.get(payload, "interval")}}

      {:ok, %{"error" => "slow_down"} = payload} ->
        interval = DeviceFlowLimiter.slow_down(device_code)

        {:pending,
         %{"status" => "slow_down", "interval" => Map.get(payload, "interval", interval)}}

      {:ok, %{"error" => error} = payload}
      when error in ["expired_token", "access_denied", "device_flow_disabled"] ->
        DeviceFlowLimiter.clear(device_code)
        {:error, 400, %{"error" => device_flow_error(error), "githubError" => payload}}

      {:ok, %{"access_token" => access_token} = token_response} when is_binary(access_token) ->
        DeviceFlowLimiter.clear(device_code)

        with {:ok, user} <- client().get_user(access_token) do
          connection = TokenStore.save_token_response(token_response, user)
          {:ok, TokenStore.public_connection() |> Map.put("user", connection["user"])}
        end

      {:ok, payload} ->
        {:error, 400, %{"error" => "GitHub authorization failed.", "githubError" => payload}}

      {:error, payload} ->
        {:error, Map.get(payload, "status", 502),
         %{
           "error" => Map.get(payload, "message", "GitHub authorization failed."),
           "githubError" => payload
         }}
    end
  end

  defp refresh_user_token!(connection) do
    token = Map.fetch!(connection, "token")
    refresh_token = token["refresh_token"]

    cond do
      not is_binary(refresh_token) or refresh_token == "" ->
        raise ArgumentError, "Connect GitHub with device flow for local testing."

      expires_soon?(token["refresh_token_expires_at"]) ->
        raise ArgumentError, "Connect GitHub with device flow for local testing."

      true ->
        case client().refresh_user_token(client_id!(), client_secret!(), refresh_token) do
          {:ok, response} ->
            connection
            |> TokenStore.replace_token(response)
            |> get_in(["token", "access_token"])

          {:error, payload} ->
            raise ArgumentError,
                  Map.get(
                    payload,
                    "message",
                    "Connect GitHub with device flow for local testing."
                  )
        end
    end
  end

  defp ensure_enabled! do
    unless enabled?() do
      raise ArgumentError, "GitHub device flow fallback is disabled."
    end
  end

  defp expires_soon?(nil), do: false

  defp expires_soon?(iso8601) do
    case DateTime.from_iso8601(iso8601) do
      {:ok, expires_at, _offset} ->
        DateTime.compare(
          expires_at,
          DateTime.utc_now() |> DateTime.add(@refresh_window_seconds, :second)
        ) != :gt

      _ ->
        false
    end
  end

  defp client_id! do
    case System.get_env("SYMPHONIA_GITHUB_CLIENT_ID") do
      value when is_binary(value) and value != "" -> value
      _ -> raise ArgumentError, "Set SYMPHONIA_GITHUB_CLIENT_ID to connect GitHub."
    end
  end

  defp client_secret! do
    case System.get_env("SYMPHONIA_GITHUB_CLIENT_SECRET") do
      value when is_binary(value) and value != "" -> value
      _ -> raise ArgumentError, "Set SYMPHONIA_GITHUB_CLIENT_SECRET to refresh GitHub access."
    end
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp device_flow_error("expired_token"), do: "GitHub authorization expired. Start again."
  defp device_flow_error("access_denied"), do: "GitHub authorization was denied."

  defp device_flow_error("device_flow_disabled"),
    do: "GitHub device flow is disabled for this app."

  defp client do
    Application.get_env(:symphonia_service, :github_client, Client)
  end
end
