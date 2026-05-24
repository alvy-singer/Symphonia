defmodule SymphoniaService.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      case System.get_env("SYMPHONIA_SERVICE_PORT") do
        nil ->
          []

        port ->
          [
            {SymphoniaService.HTTPServer,
             port: String.to_integer(port), root: SymphoniaService.default_repositories_root()}
          ]
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: SymphoniaService.Supervisor)
  end
end
