defmodule SymphoniaService.GitHub.Auth do
  @moduledoc """
  GitHub auth facade.

  GitHub App installation tokens are the primary access model. Device-flow
  user tokens are available only as an explicit development fallback.
  """

  alias SymphoniaService.GitHub.{
    AppAuth,
    DeviceAuth,
    InstallationStore,
    InstallationToken
  }

  @install_error "Install the Symphonía GitHub App on this repository to open pull requests."

  def install_error, do: @install_error

  def connection do
    installation = InstallationStore.public_state()
    device = DeviceAuth.public_connection()
    installed? = installation["installed"] == true
    device_connected? = device["connected"] == true

    %{
      "connected" => installed? or device_connected?,
      "authMode" => auth_mode(installed?, device_connected?),
      "installationUrl" => AppAuth.install_url(),
      "manageUrl" => AppAuth.manage_url(),
      "appConfigured" => AppAuth.configured?(),
      "deviceFallbackEnabled" => DeviceAuth.enabled?(),
      "installed" => installed?,
      "installedRepositoriesCount" => installation["installedRepositoriesCount"],
      "installations" => installation["installations"],
      "user" => if(DeviceAuth.enabled?(), do: device["user"], else: nil),
      "connectedAt" => if(DeviceAuth.enabled?(), do: device["connectedAt"], else: nil)
    }
    |> reject_nil()
  end

  def start_device_flow, do: DeviceAuth.start_device_flow()
  def poll_device_flow(params), do: DeviceAuth.poll_device_flow(params)
  def user_token!, do: DeviceAuth.user_token!()

  def token_for_repository(owner, repo) do
    case InstallationStore.find_repository(owner, repo) do
      %{"installationId" => installation_id} ->
        InstallationToken.token_for_installation!(installation_id)

      %{"installation_id" => installation_id} ->
        InstallationToken.token_for_installation!(installation_id)

      _ ->
        if DeviceAuth.enabled?() do
          DeviceAuth.user_token!()
        else
          raise ArgumentError, @install_error
        end
    end
  end

  defp auth_mode(true, _device_connected?), do: "app_installation"
  defp auth_mode(false, true), do: "device_user_token"
  defp auth_mode(false, false), do: nil

  defp reject_nil(map), do: map |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new()
end
