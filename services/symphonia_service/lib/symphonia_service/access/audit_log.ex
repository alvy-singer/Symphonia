defmodule SymphoniaService.Access.AuditLog do
  @moduledoc """
  Public-safe append-only audit log for repository activity.
  """

  alias SymphoniaService.Secrets.Redactor

  @metadata_allowlist ~w(
    runId
    taskKey
    provider
    workspaceProvider
    reviewBranch
    githubPrUrl
    reasonCode
    assignmentId
    changedFileCount
    runnerId
    runnerMode
    trustState
    tokenState
    healthState
    capabilitySummary
    secretScope
    secretSource
    artifactKind
    artifactId
    revisionId
    exportStatus
    exportId
    targetPath
    pullRequestNumber
    pullRequestState
    legacyRepoPath
    evidenceKind
    evidenceId
  )

  @target_types ~w(repository task run review pull_request harness workflow runner secret_reference private_workspace)

  def path(registry_path) do
    Path.join([Path.dirname(registry_path), "audit", "events.jsonl"])
  end

  def record(registry_path, repository, attrs) when is_map(attrs) do
    event =
      %{
        "id" => event_id(),
        "at" => now(),
        "actor" => public_actor(Map.get(attrs, "actor")),
        "repo" => repo_key(repository),
        "action" => Map.fetch!(attrs, "action"),
        "target" => sanitize_target(Map.get(attrs, "target")),
        "result" => result(Map.get(attrs, "result")),
        "summary" => summary(attrs, repository),
        "metadata" => sanitize_metadata(Map.get(attrs, "metadata", %{}))
      }
      |> reject_empty()

    write_event(registry_path, event)
    event
  end

  def list(registry_path, repository, opts \\ []) do
    repo = repo_key(repository)

    registry_path
    |> read_events()
    |> Enum.filter(&(&1["repo"] == repo))
    |> Enum.reverse()
    |> Enum.take(limit(opts))
  end

  def list_for_task(registry_path, repository, task_key, opts \\ []) do
    registry_path
    |> list(repository, limit: :all)
    |> Enum.filter(fn event ->
      get_in(event, ["target", "type"]) == "task" and get_in(event, ["target", "id"]) == task_key
    end)
    |> Enum.take(limit(opts))
  end

  def sanitize_metadata(metadata) when is_map(metadata) do
    metadata
    |> Enum.flat_map(fn {key, value} ->
      key = to_string(key)

      if key in @metadata_allowlist do
        case Redactor.sanitize_value(value) do
          :drop -> []
          value -> [{key, value}]
        end
      else
        []
      end
    end)
    |> Map.new()
  end

  def sanitize_metadata(_metadata), do: %{}

  defp write_event(registry_path, event) do
    event_path = path(registry_path)
    event_path |> Path.dirname() |> File.mkdir_p!()
    File.write!(event_path, JSON.encode!(event) <> "\n", [:append])
    chmod_private(event_path)
    :ok
  end

  defp read_events(registry_path) do
    case File.read(path(registry_path)) do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.flat_map(fn line ->
          case JSON.decode(line) do
            {:ok, event} when is_map(event) -> [event]
            _ -> []
          end
        end)

      {:error, :enoent} ->
        []

      {:error, reason} ->
        raise File.Error, reason: reason, action: "read file", path: path(registry_path)
    end
  end

  defp public_actor(%{"id" => id, "name" => name, "role" => role}) do
    %{
      "id" => string_or_default(id, "unknown"),
      "name" => string_or_default(name, "Unknown"),
      "role" => string_or_default(role, "viewer")
    }
  end

  defp public_actor(_actor), do: %{"id" => "unknown", "name" => "Unknown", "role" => "viewer"}

  defp sanitize_target(%{"type" => type} = target) when type in @target_types do
    %{
      "type" => type,
      "id" => sanitize_target_id(target["id"])
    }
    |> reject_empty()
  end

  defp sanitize_target(%{type: type} = target) when type in @target_types do
    sanitize_target(%{"type" => type, "id" => Map.get(target, :id)})
  end

  defp sanitize_target(_target), do: nil

  defp sanitize_target_id(id) when is_binary(id) do
    id
    |> String.trim()
    |> case do
      "" -> nil
      value -> redact_string(value) |> String.slice(0, 120)
    end
  end

  defp sanitize_target_id(_id), do: nil

  defp result(result) when result in ["allowed", "denied", "completed", "failed"], do: result
  defp result(_result), do: "completed"

  defp summary(%{"summary" => summary}, _repository) when is_binary(summary) do
    sanitize_summary(summary)
  end

  defp summary(%{summary: summary}, _repository) when is_binary(summary) do
    sanitize_summary(summary)
  end

  defp summary(attrs, repository) do
    actor_name = get_in(attrs, ["actor", "name"]) || get_in(attrs, [:actor, "name"]) || "Someone"
    action = Map.get(attrs, "action") || Map.get(attrs, :action) || "repository.update"
    result = Map.get(attrs, "result") || Map.get(attrs, :result) || "completed"
    target = Map.get(attrs, "target") || Map.get(attrs, :target) || %{}
    target_id = target["id"] || target[:id] || repo_key(repository)

    "#{actor_name} #{verb_for(result)} #{human_action(action)}#{target_suffix(target_id)}."
    |> sanitize_summary()
  end

  defp verb_for("denied"), do: "was denied"
  defp verb_for("failed"), do: "failed"
  defp verb_for(_result), do: "completed"

  defp human_action(action) do
    action
    |> to_string()
    |> String.replace(".", " ")
    |> String.replace("_", " ")
  end

  defp target_suffix(nil), do: ""
  defp target_suffix(""), do: ""
  defp target_suffix(id), do: " for #{id}"

  defp sanitize_summary(summary) do
    summary
    |> String.trim()
    |> String.slice(0, 240)
    |> redact_string()
  end

  defp redact_string(value) do
    case Redactor.sanitize_value(value) do
      :drop -> ""
      value -> value
    end
  end

  defp repo_key(%{"key" => key}) when is_binary(key), do: key
  defp repo_key(%{key: key}) when is_binary(key), do: key
  defp repo_key(key) when is_binary(key), do: key
  defp repo_key(_repository), do: "GLOBAL"

  defp limit(opts) do
    case Keyword.get(opts, :limit, 50) do
      :all ->
        1_000_000

      value when is_integer(value) ->
        max(1, min(value, 200))

      value when is_binary(value) ->
        case Integer.parse(value) do
          {number, _rest} -> max(1, min(number, 200))
          :error -> 50
        end

      _ ->
        50
    end
  end

  defp reject_empty(map) do
    map
    |> Enum.reject(fn
      {_key, nil} -> true
      {_key, value} when value == %{} -> true
      _entry -> false
    end)
    |> Map.new()
  end

  defp string_or_default(value, default) when is_binary(value) do
    case String.trim(value) do
      "" -> default
      value -> String.slice(value, 0, 120)
    end
  end

  defp string_or_default(_value, default), do: default

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond) |> DateTime.to_iso8601()

  defp event_id do
    timestamp =
      now()
      |> String.replace(":", "-")
      |> String.replace(".", "-")

    sequence =
      System.unique_integer([:positive, :monotonic])
      |> Integer.to_string()
      |> String.pad_leading(12, "0")

    "audit_#{timestamp}_#{sequence}"
  end

  defp chmod_private(path) do
    File.chmod(path, 0o600)
    :ok
  rescue
    _ -> :ok
  end
end
