defmodule SymphoniaService.Secrets.ReferenceStore do
  @moduledoc """
  Repository-scoped secret references.

  V1 references environment variables by name only. Values are never stored or
  returned.
  """

  @scopes ~w(repo.checkout provider.codex_app_server provider.gemini_cli sandbox.provider validation.env)
  @sources ~w(environment)

  def scopes, do: @scopes

  def path(registry_path) do
    Path.join([Path.dirname(registry_path), "secrets", "secret_references.json"])
  end

  def list(registry_path, repository) do
    repo_key = repo_key(repository)

    registry_path
    |> read()
    |> Enum.filter(&(&1["repoKey"] == repo_key))
    |> Enum.map(&public/1)
  end

  def create(registry_path, repository, attrs) when is_map(attrs) do
    reference =
      %{
        "id" => secret_ref_id(),
        "repoKey" => repo_key(repository),
        "label" => normalized_label(attrs["label"]),
        "scope" => normalized_scope(attrs["scope"]),
        "source" => normalized_source(attrs["source"]),
        "envName" => normalized_env_name(attrs["envName"] || attrs["env_name"]),
        "createdAt" => now(),
        "lastCheckedAt" => now()
      }

    update_all(registry_path, fn refs -> refs ++ [reference] end)
    {:ok, public(reference)}
  end

  def delete(registry_path, repository, secret_ref_id) when is_binary(secret_ref_id) do
    refs = read(registry_path)
    repo_key = repo_key(repository)

    case Enum.find(refs, &(&1["repoKey"] == repo_key and &1["id"] == secret_ref_id)) do
      nil ->
        {:error, :not_found}

      ref ->
        write(
          registry_path,
          Enum.reject(refs, &(&1["id"] == secret_ref_id and &1["repoKey"] == repo_key))
        )

        {:ok, public(ref)}
    end
  end

  def configured?(%{"source" => "environment", "envName" => env_name}) when is_binary(env_name) do
    case System.get_env(env_name) do
      value when is_binary(value) -> String.trim(value) != ""
      _ -> false
    end
  end

  def configured?(_reference), do: false

  def public(reference) when is_map(reference) do
    reference
    |> Map.take(["id", "label", "scope", "source", "envName", "createdAt", "lastCheckedAt"])
    |> Map.put("configured", configured?(reference))
  end

  defp update_all(registry_path, fun) do
    registry_path
    |> read()
    |> fun.()
    |> then(&write(registry_path, &1))
  end

  defp read(registry_path) do
    case File.read(path(registry_path)) do
      {:ok, body} ->
        case JSON.decode(body) do
          {:ok, %{"secretReferences" => refs}} when is_list(refs) -> Enum.filter(refs, &is_map/1)
          {:ok, refs} when is_list(refs) -> Enum.filter(refs, &is_map/1)
          _ -> []
        end

      {:error, :enoent} ->
        []

      {:error, reason} ->
        raise File.Error, reason: reason, action: "read file", path: path(registry_path)
    end
  end

  defp write(registry_path, refs) do
    file_path = path(registry_path)
    file_path |> Path.dirname() |> File.mkdir_p!()
    temp_path = "#{file_path}.tmp-#{System.unique_integer([:positive])}"
    File.write!(temp_path, JSON.encode!(%{"secretReferences" => refs}))
    File.rename!(temp_path, file_path)
    chmod_private(file_path)
    :ok
  end

  defp normalized_label(value) when is_binary(value) do
    case String.trim(value) do
      "" -> "Secret reference"
      label -> String.slice(label, 0, 80)
    end
  end

  defp normalized_label(_value), do: "Secret reference"

  defp normalized_scope(scope) when scope in @scopes, do: scope
  defp normalized_scope(_scope), do: raise(ArgumentError, "Unsupported secret reference scope.")

  defp normalized_source(source) when source in @sources, do: source
  defp normalized_source(_source), do: "environment"

  defp normalized_env_name(value) when is_binary(value) do
    value = String.trim(value)

    if Regex.match?(~r/^[A-Z_][A-Z0-9_]{0,120}$/, value) do
      value
    else
      raise ArgumentError, "envName must be an uppercase environment variable name."
    end
  end

  defp normalized_env_name(_value), do: raise(ArgumentError, "envName is required.")

  defp repo_key(%{"key" => key}) when is_binary(key), do: key
  defp repo_key(key) when is_binary(key), do: key

  defp secret_ref_id do
    suffix = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
    "secret_ref_#{suffix}"
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp chmod_private(path) do
    File.chmod(path, 0o600)
  rescue
    _error -> :ok
  end
end
