defmodule SymphoniaService.CodingAssistant.RunStore do
  @moduledoc """
  Local private store for Coding Assistant run records.
  """

  @states ~w(queued running completed failed)

  def states, do: @states

  def create(attrs, opts \\ []) when is_map(attrs) do
    now = now()

    run =
      %{
        "id" => run_id(),
        "state" => "queued",
        "provider" => Map.get(attrs, "provider", "local_demo"),
        "repository" => Map.fetch!(attrs, "repository"),
        "task" => Map.fetch!(attrs, "task"),
        "created_at" => now,
        "updated_at" => now,
        "started_at" => nil,
        "completed_at" => nil,
        "raw_log" => []
      }
      |> Map.merge(optional_attrs(attrs))
      |> reject_nil()

    save(run, opts)
  end

  def mark_running(run, opts \\ []) do
    now = now()

    run
    |> Map.merge(%{"state" => "running", "started_at" => now, "updated_at" => now})
    |> append_log("Coding Assistant run started.")
    |> save(opts)
  end

  def mark_completed(run, handoff, opts \\ []) do
    now = now()

    run
    |> Map.merge(%{
      "state" => "completed",
      "completed_at" => now,
      "updated_at" => now,
      "handoff" => handoff
    })
    |> append_log("Coding Assistant run completed.")
    |> save(opts)
  end

  def mark_failed(run, reason, opts \\ []) do
    now = now()

    run
    |> Map.merge(%{
      "state" => "failed",
      "completed_at" => now,
      "updated_at" => now,
      "error" => reason
    })
    |> append_log("Coding Assistant run failed: #{reason}")
    |> save(opts)
  end

  def public(run) do
    %{
      "id" => run["id"],
      "state" => run["state"],
      "startedAt" => run["started_at"],
      "completedAt" => run["completed_at"]
    }
    |> reject_nil()
  end

  def path(run, opts \\ []) do
    Path.join(root(opts), "#{run["id"]}.json")
  end

  def root(opts \\ []) do
    Keyword.get(opts, :root) ||
      System.get_env("SYMPHONIA_RUNS_ROOT") ||
      Path.join([System.user_home!(), ".symphonia", "runs"])
  end

  defp save(run, opts) do
    path = path(run, opts)
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, JSON.encode!(run))
    chmod_private(path)
    run
  end

  defp append_log(run, message) do
    Map.update(run, "raw_log", [message], &(List.wrap(&1) ++ [message]))
  end

  defp optional_attrs(attrs) do
    Map.take(attrs, [
      "kind",
      "input",
      "review_note_id",
      "attempt",
      "max_attempts"
    ])
  end

  defp run_id do
    suffix = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
    "run_#{System.system_time(:millisecond)}_#{suffix}"
  end

  defp reject_nil(map), do: map |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new()
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp chmod_private(path) do
    File.chmod(path, 0o600)
    :ok
  rescue
    _ -> :ok
  end
end
