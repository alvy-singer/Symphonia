defmodule SymphoniaService.MixProject do
  use Mix.Project

  def project do
    [
      app: :symphonia_service,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: SymphoniaService.CLI],
      deps: []
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :inets, :ssl],
      mod: {SymphoniaService.Application, []}
    ]
  end
end
