defmodule SymphoniaService.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    SymphoniaService.LocalEnv.load()

    registry_path = SymphoniaService.default_registry_path()

    service_port = System.get_env("SYMPHONIA_SERVICE_PORT")

    service_children =
      case service_port do
        nil ->
          []

        port ->
          [
            {SymphoniaService.HTTPServer,
             port: String.to_integer(port), registry_path: registry_path}
          ]
      end

    children =
      [
        SymphoniaService.CodingAssistant.RunRegistry,
        {SymphoniaService.CodingAssistant.RunSupervisor,
         registry_path: registry_path, recover: not is_nil(service_port)}
      ] ++ harness_children(registry_path, service_port) ++ service_children

    Supervisor.start_link(children, strategy: :one_for_one, name: SymphoniaService.Supervisor)
  end

  defp harness_children(registry_path, service_port) do
    setting = System.get_env("SYMPHONIA_HARNESS_DAEMON")

    enabled? =
      cond do
        setting in ["0", "false"] -> false
        setting in ["1", "true"] -> true
        true -> not is_nil(service_port)
      end

    if enabled? do
      [{SymphoniaService.Harness.Daemon, registry_path: registry_path}]
    else
      []
    end
  end
end
