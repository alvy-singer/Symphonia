defmodule SymphoniaService.CLI do
  @moduledoc false

  def main(["serve" | args]) do
    SymphoniaService.LocalEnv.load()

    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [port: :integer, registry: :string],
        aliases: [p: :port]
      )

    port = Keyword.get(opts, :port, 4057)
    registry_path = Keyword.get(opts, :registry, SymphoniaService.default_registry_path())

    {:ok, _pid} = SymphoniaService.HTTPServer.start_link(port: port, registry_path: registry_path)
    IO.puts("Symphonia service listening on http://localhost:#{port}")
    Process.sleep(:infinity)
  end

  def main(["tasks", repo]) do
    registry_path = SymphoniaService.default_registry_path()
    repository = SymphoniaService.RepositoryRegistry.get!(registry_path, repo)
    repository |> SymphoniaService.TaskStore.list_tasks() |> JSON.encode!() |> IO.puts()
  end

  def main(_args) do
    IO.puts("""
    Usage:
      symphonia_service serve [--port 4057] [--registry ~/.symphonia/repositories.json]
      symphonia_service tasks <repo-key>
    """)
  end
end
