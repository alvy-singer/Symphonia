defmodule SymphoniaService.LocalEnv do
  @moduledoc """
  Loads ignored local environment files for development runs.

  This keeps machine-local credentials and switches out of repository artifacts
  while still making `mix run` behave like the Next app's local environment.
  """

  @candidate_files [".env.local", ".env"]

  def load do
    []
    |> Kernel.++(roots_from_cwd())
    |> Enum.uniq()
    |> Enum.flat_map(fn root ->
      Enum.map(@candidate_files, &Path.join(root, &1))
    end)
    |> Enum.each(&load_file/1)

    :ok
  end

  defp roots_from_cwd do
    cwd = File.cwd!()

    [
      cwd,
      Path.expand("..", cwd),
      Path.expand("../..", cwd)
    ]
  end

  defp load_file(path) do
    case File.read(path) do
      {:ok, body} ->
        body
        |> String.split("\n")
        |> Enum.each(&put_line/1)

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        raise File.Error, reason: reason, action: "read file", path: path
    end
  end

  defp put_line(line) do
    line = String.trim(line)

    cond do
      line == "" or String.starts_with?(line, "#") ->
        :ok

      not String.contains?(line, "=") ->
        :ok

      true ->
        [key, value] = String.split(line, "=", parts: 2)
        key = key |> String.trim() |> String.trim_leading("export ") |> String.trim()

        if valid_key?(key) and blank?(System.get_env(key)) do
          System.put_env(key, clean_value(value))
        end
    end
  end

  defp clean_value(value) do
    value = String.trim(value)

    cond do
      String.starts_with?(value, "\"") and String.ends_with?(value, "\"") ->
        value |> String.trim_leading("\"") |> String.trim_trailing("\"")

      String.starts_with?(value, "'") and String.ends_with?(value, "'") ->
        value |> String.trim_leading("'") |> String.trim_trailing("'")

      true ->
        value
    end
  end

  defp valid_key?(key), do: Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, key)
  defp blank?(nil), do: true
  defp blank?(value), do: String.trim(value) == ""
end
