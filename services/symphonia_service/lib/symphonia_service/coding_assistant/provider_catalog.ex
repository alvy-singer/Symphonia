defmodule SymphoniaService.CodingAssistant.ProviderCatalog do
  @moduledoc """
  Public provider readiness for the Harness surface.

  Harness V1 can execute only Codex App Server. Other assistants may be shown in
  product surfaces, but they are intentionally not runnable by the always-on
  daemon until they satisfy the full execution contract.
  """

  alias SymphoniaService.CodingAssistant.AppServerClient

  @disabled_reason "Not runnable by Harness V1."

  def harness_status(opts \\ []) do
    mode = Keyword.get(opts, :mode, :normal)

    %{
      "defaultProvider" => "codex_app_server",
      "runnableProvider" => "codex_app_server",
      "providers" => [
        codex_app_server_status(mode),
        disabled_provider("claude_code", "Claude Code"),
        disabled_provider("gemini", "Gemini"),
        disabled_provider("cursor", "Cursor")
      ]
    }
  end

  def readiness_status(opts \\ []), do: harness_status(opts)

  defp codex_app_server_status(:check_only) do
    readiness = AppServerClient.check_ready(start?: false)

    %{
      "id" => "codex_app_server",
      "label" => "Codex App Server",
      "configured" => readiness["configured"],
      "ready" => readiness["ready"],
      "runnable" => true,
      "schemaAvailable" => readiness["schemaAvailable"],
      "binaryAvailable" => readiness["binaryAvailable"],
      "daemonReachable" => readiness["daemonReachable"],
      "reason" => safe_reason(readiness["reason"])
    }
  end

  defp codex_app_server_status(_mode) do
    case codex_app_server_ready?() do
      :ok ->
        %{
          "id" => "codex_app_server",
          "label" => "Codex App Server",
          "configured" => true,
          "ready" => true,
          "runnable" => true,
          "reason" => "Ready for local Codex runs."
        }

      {:error, reason} ->
        %{
          "id" => "codex_app_server",
          "label" => "Codex App Server",
          "configured" => configured?(),
          "ready" => false,
          "runnable" => true,
          "reason" => reason
        }
    end
  end

  defp codex_app_server_ready? do
    with :ok <- AppServerClient.ensure_schema_bundle!(),
         :ok <- AppServerClient.ensure_daemon_ready!() do
      :ok
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp configured? do
    truthy?(System.get_env("SYMPHONIA_CODEX_APP_SERVER_SKIP_DAEMON")) ||
      nonblank?(System.get_env("SYMPHONIA_CODEX_APP_SERVER_COMMAND")) ||
      nonblank?(System.get_env("SYMPHONIA_CODEX_BIN")) ||
      nonblank?(System.get_env("SYMPHONIA_CODEX_APP_SERVER_BIN")) ||
      nonblank?(System.get_env("SYMPHONIA_CODEX_APP_SERVER_STANDALONE_BIN"))
  end

  defp disabled_provider(id, label) do
    %{
      "id" => id,
      "label" => label,
      "configured" => false,
      "ready" => false,
      "runnable" => false,
      "reason" => @disabled_reason
    }
  end

  defp nonblank?(value) when is_binary(value), do: String.trim(value) != ""
  defp nonblank?(_value), do: false
  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?("1"), do: true
  defp truthy?(_value), do: false

  defp safe_reason(reason) when is_binary(reason) do
    reason
    |> String.replace(~r/[A-Z_]{3,}[A-Z0-9_]*=/, "setting=")
    |> String.replace(~r/(\/[A-Za-z0-9._@%+~:-]+)+/, "[local path]")
  end

  defp safe_reason(_reason), do: "Codex readiness could not be confirmed."
end
