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
    |> append_log("Coding Assistant run started.")
    |> save(opts)
  end

  def mark_step(run, step, opts \\ []) when is_binary(step) do
    run
    |> reload(opts)
    |> Map.merge(%{"current_step" => step, "updated_at" => now()})
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

  def public(run) do
    %{
      "id" => run["id"],
      "state" => run["state"],
      "label" => RunEvents.label(run["state"]),
      "currentStep" => run["current_step"] || RunEvents.default_step(run["state"]),
      "message" => RunEvents.public_message(run),
      "startedAt" => run["started_at"],
      "completedAt" => run["completed_at"]
    }
    |> reject_nil()
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
      "max_attempts",
      "message",
      "current_step"
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
