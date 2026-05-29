defmodule SymphoniaService.Readiness.RepositoryScanner do
  @moduledoc """
  Read-only project scanner for repository setup guidance.
  """

  @node_script_order ["build", "typecheck", "test", "test:harness-ui", "lint"]

  def scan(repository) do
    repo_path = repository["path"] || ""

    empty()
    |> scan_package_json(repo_path)
    |> scan_file(repo_path, "mix.exs", "elixir", [
      %{"label" => "Elixir tests", "command" => "mix test"}
    ])
    |> scan_python(repo_path)
    |> scan_file(repo_path, "Cargo.toml", "rust", [
      %{"label" => "Cargo tests", "command" => "cargo test"}
    ])
    |> scan_file(repo_path, "go.mod", "go", [
      %{"label" => "Go tests", "command" => "go test ./..."}
    ])
    |> normalize()
  end

  defp empty do
    %{
      "detected" => [],
      "files" => [],
      "scripts" => [],
      "suggestedValidation" => []
    }
  end

  defp scan_package_json(result, repo_path) do
    path = Path.join(repo_path, "package.json")

    with {:ok, body} <- File.read(path),
         {:ok, package} <- JSON.decode(body),
         scripts when is_map(scripts) <- package["scripts"] || %{} do
      detected =
        ["node"]
        |> maybe_add_detected(next_project?(package, scripts), "nextjs")
        |> maybe_add_detected(react_project?(package), "react")

      suggestions =
        @node_script_order
        |> Enum.filter(&Map.has_key?(scripts, &1))
        |> Enum.map(fn script ->
          %{
            "label" => node_script_label(script),
            "command" => node_script_command(script)
          }
        end)

      result
      |> add_file("package.json")
      |> add_detected(detected)
      |> add_scripts(Map.keys(scripts))
      |> add_suggestions(suggestions)
    else
      _ -> result
    end
  end

  defp scan_python(result, repo_path) do
    path = Path.join(repo_path, "pyproject.toml")

    case File.read(path) do
      {:ok, body} ->
        suggestions =
          if String.contains?(body, "pytest") or File.dir?(Path.join(repo_path, "tests")) do
            [%{"label" => "Python tests", "command" => "pytest"}]
          else
            []
          end

        result
        |> add_file("pyproject.toml")
        |> add_detected(["python"])
        |> add_suggestions(suggestions)

      {:error, _reason} ->
        result
    end
  end

  defp scan_file(result, repo_path, file, detected, suggestions) do
    if File.exists?(Path.join(repo_path, file)) do
      result
      |> add_file(file)
      |> add_detected([detected])
      |> add_suggestions(suggestions)
    else
      result
    end
  end

  defp next_project?(package, scripts) do
    dependency?(package, "next") or
      Enum.any?(Map.values(scripts), &String.contains?("#{&1}", "next"))
  end

  defp react_project?(package), do: dependency?(package, "react")

  defp dependency?(package, name) do
    dependencies = package["dependencies"] || %{}
    dev_dependencies = package["devDependencies"] || %{}

    (is_map(dependencies) and Map.has_key?(dependencies, name)) or
      (is_map(dev_dependencies) and Map.has_key?(dev_dependencies, name))
  end

  defp maybe_add_detected(values, true, value), do: values ++ [value]
  defp maybe_add_detected(values, false, _value), do: values

  defp node_script_label("build"), do: "Build"
  defp node_script_label("typecheck"), do: "Typecheck"
  defp node_script_label("test"), do: "Tests"
  defp node_script_label("test:harness-ui"), do: "Harness UI tests"
  defp node_script_label("lint"), do: "Lint"
  defp node_script_label(script), do: script

  defp node_script_command("test"), do: "npm test"
  defp node_script_command(script), do: "npm run #{script}"

  defp add_file(result, file), do: Map.update!(result, "files", &(&1 ++ [file]))
  defp add_detected(result, detected), do: Map.update!(result, "detected", &(&1 ++ detected))
  defp add_scripts(result, scripts), do: Map.update!(result, "scripts", &(&1 ++ scripts))

  defp add_suggestions(result, suggestions) do
    Map.update!(result, "suggestedValidation", &(&1 ++ suggestions))
  end

  defp normalize(result) do
    result
    |> Map.update!("detected", &(&1 |> Enum.uniq() |> Enum.sort()))
    |> Map.update!("files", &(&1 |> Enum.uniq() |> Enum.sort()))
    |> Map.update!("scripts", &(&1 |> Enum.uniq() |> Enum.sort()))
    |> Map.update!("suggestedValidation", &dedupe_suggestions/1)
  end

  defp dedupe_suggestions(suggestions) do
    suggestions
    |> Enum.uniq_by(& &1["command"])
    |> Enum.sort_by(& &1["label"])
  end
end
