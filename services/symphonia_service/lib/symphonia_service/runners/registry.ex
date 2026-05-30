defmodule SymphoniaService.Runners.Registry do
  @moduledoc """
  Private runner registry with public-safe serialization.
  """

  alias SymphoniaService.Runners.{Capabilities, Heartbeat, LocalService}

  def list(registry_path, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    [LocalService.status(registry_path) | remote(registry_path, now: now)]
  end

  def remote(registry_path, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    registry_path
    |> read_remote()
    |> Enum.map(&public(&1, now: now))
  end

  def capacity(registry_path, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    %{
      "localService" => LocalService.status(registry_path),
      "remote" => remote(registry_path, now: now)
    }
  end

  def get(registry_path, runner_id, opts \\ [])

  def get(registry_path, "local-service", _opts), do: {:ok, LocalService.status(registry_path)}

  def get(registry_path, runner_id, opts) when is_binary(runner_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    case Enum.find(read_remote(registry_path), &(&1["id"] == runner_id)) do
      nil -> {:error, :not_found}
      runner -> {:ok, Map.put(runner, "status", Heartbeat.status(runner, now))}
    end
  end

  def get(_registry_path, _runner_id, _opts), do: {:error, :not_found}

  def register(registry_path, actor, attrs) when is_map(attrs) do
    name = normalized_name(attrs["name"] || attrs[:name])
    token = required_token!(attrs["registrationToken"] || attrs["registration_token"])
    now = now()

    runner =
      %{
        "id" => runner_id(),
        "name" => name,
        "mode" => "remote_runner",
        "enabled" => true,
        "trusted" => true,
        "createdAt" => now,
        "registeredAt" => now,
        "lastHeartbeatAt" => now,
        "lastObservedStatus" => "online",
        "capabilities" => Capabilities.sanitize(attrs["capabilities"] || %{}),
        "limits" => sanitize_limits(attrs["limits"] || %{}),
        "currentRuns" => nonnegative_integer(attrs["currentRuns"] || attrs["current_runs"], 0),
        "tokenHash" => token_hash(token),
        "registrationSource" => actor_source(actor)
      }

    update_remote(registry_path, fn runners -> runners ++ [runner] end)
    {:ok, runner}
  end

  def heartbeat(registry_path, runner_id, token, attrs) when is_map(attrs) do
    token = to_string(token || "")

    update_existing(registry_path, runner_id, fn runner ->
      if secure_equal?(runner["tokenHash"], token_hash(token)) do
        before_status = Heartbeat.status(runner)

        updated =
          runner
          |> Map.put("lastHeartbeatAt", now())
          |> Map.put("lastObservedStatus", "online")
          |> Map.put(
            "capabilities",
            Capabilities.sanitize(attrs["capabilities"] || runner["capabilities"] || %{})
          )
          |> Map.put(
            "currentRuns",
            nonnegative_integer(
              attrs["currentRuns"] || attrs["current_runs"],
              runner["currentRuns"] || 0
            )
          )
          |> maybe_update_limits(attrs["limits"])

        after_status = Heartbeat.status(updated)
        {:ok, updated, %{before: before_status, after: after_status}}
      else
        {:error, :invalid_token}
      end
    end)
  end

  def heartbeat(_registry_path, _runner_id, _token, _attrs), do: {:error, :invalid_payload}

  def enable(_registry_path, "local-service"), do: {:error, :local_service_immutable}

  def enable(registry_path, runner_id) do
    update_existing(registry_path, runner_id, fn runner ->
      updated = Map.put(runner, "enabled", true)
      {:ok, updated, %{}}
    end)
  end

  def disable(_registry_path, "local-service"), do: {:error, :local_service_immutable}

  def disable(registry_path, runner_id) do
    update_existing(registry_path, runner_id, fn runner ->
      updated = Map.put(runner, "enabled", false)
      {:ok, updated, %{}}
    end)
  end

  def mark_stale(registry_path, now \\ DateTime.utc_now()) do
    runners = read_remote(registry_path)

    {next_runners, transitions} =
      Enum.map_reduce(runners, [], fn runner, transitions ->
        before_status = runner["lastObservedStatus"] || Heartbeat.status(runner, now)
        after_status = Heartbeat.status(runner, now)
        updated = Map.put(runner, "lastObservedStatus", after_status)

        transition =
          if Heartbeat.transition?(before_status, after_status) and
               after_status in ["stale", "offline"] do
            [
              %{
                "runner" => public(updated, now: now),
                "before" => before_status,
                "after" => after_status
              }
            ]
          else
            []
          end

        {updated, transitions ++ transition}
      end)

    if next_runners != runners, do: write_remote(registry_path, next_runners)
    transitions
  end

  def public(runner, opts \\ [])

  def public(%{"mode" => "local_service"} = runner, _opts), do: runner

  def public(runner, opts) when is_map(runner) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    %{
      "id" => string_or_default(runner["id"], "runner_unknown"),
      "name" => string_or_default(runner["name"], "Remote runner"),
      "mode" => "remote_runner",
      "status" => Heartbeat.status(runner, now),
      "lastHeartbeatAt" => runner["lastHeartbeatAt"],
      "capabilities" => Capabilities.sanitize(runner["capabilities"] || %{}),
      "limits" => sanitize_limits(runner["limits"] || %{}),
      "currentRuns" => nonnegative_integer(runner["currentRuns"], 0)
    }
    |> reject_nil()
  end

  def path(registry_path), do: Path.join([Path.dirname(registry_path), "runners", "runners.json"])

  def token_hash(token) when is_binary(token) do
    :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end

  defp update_existing(registry_path, runner_id, fun) do
    runners = read_remote(registry_path)
    index = Enum.find_index(runners, &(&1["id"] == runner_id))

    case index do
      nil ->
        {:error, :not_found}

      index ->
        runner = Enum.at(runners, index)

        case fun.(runner) do
          {:ok, updated, meta} ->
            next_runners = List.replace_at(runners, index, updated)
            write_remote(registry_path, next_runners)
            {:ok, updated, meta}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp update_remote(registry_path, fun) do
    registry_path
    |> read_remote()
    |> fun.()
    |> then(&write_remote(registry_path, &1))
  end

  defp read_remote(registry_path) do
    case File.read(path(registry_path)) do
      {:ok, body} ->
        case JSON.decode(body) do
          {:ok, %{"runners" => runners}} when is_list(runners) -> Enum.filter(runners, &is_map/1)
          {:ok, runners} when is_list(runners) -> Enum.filter(runners, &is_map/1)
          _ -> []
        end

      {:error, :enoent} ->
        []

      {:error, reason} ->
        raise File.Error, reason: reason, action: "read file", path: path(registry_path)
    end
  end

  defp write_remote(registry_path, runners) do
    file_path = path(registry_path)
    file_path |> Path.dirname() |> File.mkdir_p!()
    temp_path = "#{file_path}.tmp-#{System.unique_integer([:positive])}"
    File.write!(temp_path, JSON.encode!(%{"runners" => runners}))
    File.rename!(temp_path, file_path)
    chmod_private(file_path)
    :ok
  end

  defp maybe_update_limits(runner, nil), do: runner
  defp maybe_update_limits(runner, limits), do: Map.put(runner, "limits", sanitize_limits(limits))

  defp sanitize_limits(limits) when is_map(limits) do
    %{
      "maxConcurrentRuns" =>
        positive_integer(limits["maxConcurrentRuns"] || limits["max_concurrent_runs"], 1)
    }
  end

  defp sanitize_limits(_limits), do: %{"maxConcurrentRuns" => 1}

  defp normalized_name(value) when is_binary(value) do
    case String.trim(value) do
      "" -> "Remote runner"
      name -> String.slice(name, 0, 80)
    end
  end

  defp normalized_name(_value), do: "Remote runner"

  defp required_token!(token) when is_binary(token) do
    case String.trim(token) do
      "" -> raise ArgumentError, "registrationToken is required."
      value -> value
    end
  end

  defp required_token!(_token), do: raise(ArgumentError, "registrationToken is required.")

  defp positive_integer(value, default) do
    case integer(value) do
      nil -> default
      value -> max(1, min(value, 32))
    end
  end

  defp nonnegative_integer(value, default) do
    case integer(value) do
      nil -> default
      value -> max(0, value)
    end
  end

  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp integer(_value), do: nil

  defp secure_equal?(left, right) when is_binary(left) and is_binary(right) do
    byte_size(left) == byte_size(right) and constant_time_compare(left, right) == 0
  end

  defp secure_equal?(_left, _right), do: false

  defp constant_time_compare(left, right) do
    left
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(right))
    |> Enum.reduce(0, fn {a, b}, acc -> Bitwise.bor(acc, Bitwise.bxor(a, b)) end)
  end

  defp actor_source(%{"source" => source}) when is_binary(source), do: String.slice(source, 0, 40)
  defp actor_source(_actor), do: "local"

  defp string_or_default(value, default) when is_binary(value) do
    case String.trim(value) do
      "" -> default
      value -> String.slice(value, 0, 120)
    end
  end

  defp string_or_default(_value, default), do: default

  defp runner_id do
    suffix = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
    "runner_#{suffix}"
  end

  defp reject_nil(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp chmod_private(path) do
    File.chmod(path, 0o600)
  rescue
    _error -> :ok
  end
end
