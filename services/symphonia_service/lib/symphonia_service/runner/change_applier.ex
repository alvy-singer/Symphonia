defmodule SymphoniaService.Runner.ChangeApplier do
  @moduledoc """
  Imports selected files from an execution workspace into the review workspace.

  This module is intentionally small and strict. It rejects metadata and escape
  paths instead of trying to act as a general synchronization engine.
  """

  import Kernel, except: [apply: 3]

  @protected_files MapSet.new([
                     ".git",
                     ".symphonia",
                     "WORKFLOW.md",
                     "registry.json",
                     "repositories.json",
                     "symphonia/registry.json",
                     "symphonia/repositories.json",
                     "symphonia/run-summaries",
                     "symphonia/tasks"
                   ])

  @protected_prefixes [
    ".git/",
    ".symphonia/",
    "symphonia/tasks/",
    "symphonia/run-summaries/"
  ]

  def apply(source_repo_path, review_repo_path, paths) when is_list(paths) do
    source_root = Path.expand(source_repo_path)
    review_root = Path.expand(review_repo_path)
    paths = paths |> Enum.reject(&blank?/1) |> Enum.uniq() |> Enum.sort()

    with :ok <- validate_paths(source_root, review_root, paths) do
      Enum.each(paths, &apply_path(source_root, review_root, &1))
      {:ok, paths}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  def apply(_source_repo_path, _review_repo_path, _paths),
    do: {:error, "Sandbox output did not include a valid changed-file list."}

  defp validate_paths(source_root, review_root, paths) do
    Enum.reduce_while(paths, :ok, fn path, :ok ->
      case validate_path(source_root, review_root, path) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_path(source_root, review_root, path) do
    cond do
      Path.type(path) == :absolute ->
        {:error, "Sandbox output included an absolute path."}

      path in [".", ""] ->
        {:error, "Sandbox output included an invalid path."}

      ".." in Path.split(path) ->
        {:error, "Sandbox output included a path traversal."}

      protected_path?(path) ->
        {:error, "Sandbox output included a protected path: #{path}."}

      true ->
        with {:ok, source_path} <- safe_join(source_root, path),
             {:ok, review_path} <- safe_join(review_root, path),
             :ok <- reject_symlink(source_path),
             :ok <- reject_symlink(review_path),
             :ok <- reject_symlink_parent(review_root, review_path) do
          :ok
        end
    end
  end

  defp apply_path(source_root, review_root, path) do
    source_path = Path.join(source_root, path)
    review_path = Path.join(review_root, path)

    if File.exists?(source_path) do
      review_path |> Path.dirname() |> File.mkdir_p!()
      File.cp!(source_path, review_path)
      File.chmod(review_path, 0o644)
    else
      File.rm(review_path)
    end
  end

  defp safe_join(root, path) do
    full_path = Path.expand(path, root)

    if full_path == root or String.starts_with?(full_path, root <> "/") do
      {:ok, full_path}
    else
      {:error, "Sandbox output included a path outside the repository."}
    end
  end

  defp reject_symlink(path) do
    case File.lstat(path) do
      {:ok, %{type: :symlink}} -> {:error, "Sandbox output included a symlink path."}
      _other -> :ok
    end
  end

  defp reject_symlink_parent(root, path) do
    path
    |> Path.dirname()
    |> parent_components(root)
    |> Enum.reduce_while(:ok, fn parent, :ok ->
      case File.lstat(parent) do
        {:ok, %{type: :symlink}} -> {:halt, {:error, "Sandbox output targeted a symlink path."}}
        _other -> {:cont, :ok}
      end
    end)
  end

  defp parent_components(path, root) do
    path = Path.expand(path)
    root = Path.expand(root)

    path
    |> Path.relative_to(root)
    |> Path.split()
    |> Enum.reject(&(&1 in [".", ""]))
    |> Enum.scan(root, &Path.join(&2, &1))
  end

  defp protected_path?(path) do
    normalized = Path.join(Path.split(path))

    MapSet.member?(@protected_files, normalized) or
      Enum.any?(@protected_prefixes, &String.starts_with?(normalized, &1))
  end

  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")
end
