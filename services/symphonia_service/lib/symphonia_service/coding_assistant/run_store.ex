defmodule SymphoniaService.CodingAssistant.RunStore do
  @moduledoc """
  Local private store for Coding Assistant run records.
  """

  alias SymphoniaService.CodingAssistant.RunEvents

  @states ~w(queued running completed failed canceled)

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
        "current_step" => RunEvents.default_step("queued"),
        "raw_log" => []
      }
      |> Map.merge(optional_attrs(attrs))
      |> reject_nil()

    save(run, opts)
  end

  def mark_running(run, opts \\ []) do
    now = now()

    run
    |> Map.merge(%{
      "state" => "running",
      "started_at" => now,
      "updated_at" => now,
      "current_step" => RunEvents.default_step("running")
    })
    |> append_timeline_entry(%{"label" => RunEvents.default_step("running"), "at" => now})
    |> append_log("Coding Assistant run started.")
    |> save(opts)
  end

  def mark_step(run, step, opts \\ []) when is_binary(step) do
    run
    |> reload(opts)
    |> Map.merge(%{"current_step" => step, "updated_at" => now()})
    |> append_timeline_entry(%{"label" => step})
    |> append_log(step)
    |> save(opts)
  end

  def mark_completed(run, handoff, opts \\ []) do
    now = now()

    run
    |> reload(opts)
    |> Map.merge(%{
      "state" => "completed",
      "completed_at" => now,
      "updated_at" => now,
      "current_step" => RunEvents.default_step("completed"),
      "handoff" => handoff
    })
    |> append_timeline_entry(%{"label" => RunEvents.default_step("completed"), "at" => now})
    |> append_log("Coding Assistant run completed.")
    |> save(opts)
  end

  def mark_failed(run, reason, public_message \\ nil, opts \\ []) do
    now = now()

    run
    |> reload(opts)
    |> Map.merge(%{
      "state" => "failed",
      "completed_at" => now,
      "updated_at" => now,
      "current_step" => RunEvents.default_step("failed"),
      "message" => public_message,
      "error" => reason
    })
    |> reject_nil()
    |> append_timeline_entry(%{"label" => RunEvents.default_step("failed"), "at" => now})
    |> append_log("Coding Assistant run failed: #{reason}")
    |> save(opts)
  end

  def mark_canceled(run, reason \\ "waiting_for_user", opts \\ []) do
    now = now()

    run
    |> reload(opts)
    |> Map.merge(%{
      "state" => "canceled",
      "completed_at" => now,
      "updated_at" => now,
      "current_step" => RunEvents.default_step("canceled"),
      "message" => "Run canceled. The task is paused. You can retry when ready.",
      "canceled_reason" => reason
    })
    |> append_timeline_entry(%{"label" => RunEvents.default_step("canceled"), "at" => now})
    |> append_log("Coding Assistant run canceled.")
    |> save(opts)
  end

  def record_provider_output(run, attrs, opts \\ []) when is_map(attrs) do
    latest = reload(run, opts)
    existing = Map.get(latest, "provider_output", %{})

    latest
    |> Map.put("provider_output", Map.merge(existing, attrs))
    |> save(opts)
  end

  def update_metadata(run, attrs, opts \\ []) when is_map(attrs) do
    run
    |> reload(opts)
    |> Map.merge(attrs)
    |> Map.put("updated_at", now())
    |> reject_nil()
    |> save(opts)
  end

  def append_timeline(run, attrs, opts \\ []) when is_map(attrs) do
    run
    |> reload(opts)
    |> append_timeline_entry(attrs)
    |> save(opts)
  end

  def public(run) do
    %{
      "id" => run["id"],
      "kind" => run["kind"],
      "state" => run["state"],
      "provider" => run["provider"],
      "label" => RunEvents.label(run["state"]),
      "currentStep" => run["current_step"] || RunEvents.default_step(run["state"]),
      "message" => RunEvents.public_message(run),
      "displayStep" => RunEvents.display_step(run),
      "displayMessage" => RunEvents.display_message(run),
      "eligibilityReason" => run["eligibility_reason"],
      "runner" => public_runner(run["runner"]),
      "workspaceProvider" => run["workspace_provider"],
      "reviewBranch" => run["review_branch"],
      "curatedSummaryPath" => run["curated_summary_path"],
      "retryAt" => run["retry_at"],
      "failureClass" => run["failure_class"],
      "attempt" => run["attempt"],
      "maxAttempts" => run["max_attempts"],
      "timeline" => public_events(run),
      "startedAt" => run["started_at"],
      "completedAt" => run["completed_at"]
    }
    |> reject_nil()
  end

  def public_events(run) do
    run
    |> Map.get("timeline", [])
    |> List.wrap()
    |> Enum.filter(&is_map/1)
    |> Enum.with_index(1)
    |> Enum.map(fn {event, index} ->
      %{
        "id" => progress_event_id(run, index),
        "event" => "run-progress",
        "at" => event["at"],
        "label" => event["label"]
      }
      |> reject_nil()
    end)
  end

  def public_progress_events(run, opts \\ []) do
    after_id = Keyword.get(opts, :after)

    events =
      run
      |> progress_source_events()
      |> Enum.with_index()
      |> Enum.map(fn {event, index} -> public_progress_event(run, event, index) end)

    case after_id do
      value when is_binary(value) and value != "" ->
        case Enum.find_index(events, &(&1["id"] == value)) do
          nil -> events
          index -> Enum.drop(events, index + 1)
        end

      _ ->
        events
    end
  end

  def get(id, opts \\ []) when is_binary(id) do
    path = Path.join(root(opts), "#{id}.json")

    case File.read(path) do
      {:ok, body} -> JSON.decode!(body)
      {:error, :enoent} -> nil
      {:error, reason} -> raise File.Error, reason: reason, action: "read file", path: path
    end
  end

  def get!(id, opts \\ []) do
    get(id, opts) || raise ArgumentError, "Run #{id} not found."
  end

  def list(opts \\ []) do
    opts
    |> root()
    |> Path.join("run_*.json")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(&JSON.decode!(File.read!(&1)))
  end

  def path(run, opts \\ []) do
    Path.join(root(opts), "#{run["id"]}.json")
  end

  def root(opts \\ []) do
    Keyword.get(opts, :root) ||
      System.get_env("SYMPHONIA_RUNS_ROOT") ||
      Path.join([System.user_home!(), ".symphonia", "runs"])
  end

  defp reload(run, opts) do
    path = path(run, opts)

    case File.read(path) do
      {:ok, body} -> JSON.decode!(body)
      {:error, _reason} -> run
    end
  end

  defp save(run, opts) do
    path = path(run, opts)
    path |> Path.dirname() |> File.mkdir_p!()
    temp_path = "#{path}.tmp-#{System.unique_integer([:positive])}"
    File.write!(temp_path, JSON.encode!(run))
    File.rename!(temp_path, path)
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
      "max_attempts",
      "message",
      "current_step",
      "workspace_path",
      "workspace_provider",
      "runner",
      "codex_thread_id",
      "turn_id",
      "eligibility_reason",
      "review_branch",
      "curated_summary_path",
      "failure_class",
      "retry_at",
      "retry_of",
      "retry_reason",
      "retry_dispatched_at"
    ])
  end

  defp append_timeline_entry(run, attrs) do
    event =
      attrs
      |> Map.put_new("at", now())
      |> reject_nil()

    Map.update(run, "timeline", [event], &(List.wrap(&1) ++ [event]))
  end

  defp public_runner(%{"id" => id, "mode" => mode, "name" => name})
       when is_binary(id) and is_binary(mode) and is_binary(name) do
    %{
      "id" => String.slice(id, 0, 120),
      "mode" => String.slice(mode, 0, 80),
      "name" => String.slice(name, 0, 120)
    }
  end

  defp public_runner(_runner), do: nil

  defp progress_source_events(run) do
    queued = %{
      "at" => run["created_at"],
      "label" => RunEvents.default_step("queued"),
      "state" => "queued"
    }

    timeline =
      run
      |> Map.get("timeline", [])
      |> List.wrap()
      |> Enum.filter(&is_map/1)

    [queued | timeline]
  end

  defp public_progress_event(run, event, index) do
    event_run = %{
      "state" => progress_event_state(run, event),
      "current_step" => event["label"] || run["current_step"],
      "message" => run["message"]
    }

    %{
      "id" => progress_event_id(run, index),
      "event" => "run-progress",
      "runId" => run["id"],
      "taskKey" => run["task"],
      "state" => event_run["state"],
      "displayStep" => RunEvents.display_step(event_run),
      "displayMessage" => RunEvents.display_message(event_run),
      "reviewBranch" => run["review_branch"],
      "curatedSummaryPath" => run["curated_summary_path"],
      "updatedAt" => event["at"] || run["updated_at"]
    }
    |> reject_nil()
  end

  defp progress_event_state(_run, %{"state" => state}) when is_binary(state), do: state

  defp progress_event_state(_run, %{"label" => "Ready for review"}), do: "completed"
  defp progress_event_state(_run, %{"label" => "Run failed"}), do: "failed"
  defp progress_event_state(_run, %{"label" => "Canceled"}), do: "canceled"

  defp progress_event_state(%{"state" => state}, _event)
       when state in ["completed", "failed", "canceled"],
       do: "running"

  defp progress_event_state(%{"state" => state}, _event), do: state || "running"

  defp progress_event_id(run, index), do: "#{run["id"]}:#{index}"

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
