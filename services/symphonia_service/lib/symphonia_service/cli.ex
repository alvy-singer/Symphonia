defmodule SymphoniaService.CLI do
  @moduledoc false

  def main(["serve" | args]) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [port: :integer, root: :string],
        aliases: [p: :port, r: :root]
      )

    port = Keyword.get(opts, :port, 4057)
    root = Keyword.get(opts, :root, SymphoniaService.default_repositories_root())

    {:ok, _pid} = SymphoniaService.HTTPServer.start_link(port: port, root: root)
    IO.puts("Symphonia service listening on http://localhost:#{port}")
    Process.sleep(:infinity)
  end

  def main(["tasks", repo]) do
    root = SymphoniaService.default_repositories_root()
    root |> SymphoniaService.TaskStore.list_tasks(repo) |> JSON.encode!() |> IO.puts()
  end

  def main(_args) do
    IO.puts("""
    Usage:
      symphonia_service serve [--port 4057] [--root fixtures/repositories]
      symphonia_service tasks <repo-key>
    """)
  end
end
