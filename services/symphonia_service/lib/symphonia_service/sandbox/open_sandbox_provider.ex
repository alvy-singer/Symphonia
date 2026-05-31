defmodule SymphoniaService.Sandbox.OpenSandboxProvider do
  @moduledoc """
  OpenSandbox-backed disposable workspace provider.

  This adapter keeps OpenSandbox behind Symphonia's provider boundary. It uploads
  a source bundle, runs a controlled sandbox runner command, collects a patch
  result, and lets the existing local patch importer own review state.
  """

  @behaviour SymphoniaService.Sandbox.Provider

  alias SymphoniaService.Runners.PatchBundle

  alias SymphoniaService.Sandbox.{
    OpenSandboxConfig,
    OpenSandboxError,
    ProviderRunnerScript,
    Session,
    SourceBundle
  }

  @execd_port 44_772

  @impl true
  def create(opts) do
    config = OpenSandboxConfig.load(opts)

    with :ok <- require_ready(config),
         {:ok, sandbox} <- client().create(config, create_request(config, opts)),
         {:ok, sandbox} <- wait_until_running(config, sandbox),
         {:ok, execd} <- resolve_execd(config, sandbox) do
      session =
        Session.new(OpenSandboxConfig.provider_id(), %{
          "sandbox_id" => sandbox_id(sandbox),
          "provider_label" => OpenSandboxConfig.label(),
          "execd" => execd,
          "config" => OpenSandboxConfig.private_session(config),
          "params" => sandbox_params(opts)
        })

      {:ok, session}
    else
      {:error, reason} -> {:error, safe_reason(reason)}
    end
  end

  @impl true
  def prepare(session, repository, assignment) do
    config = session["config"] || %{}
    execd = session["execd"] || %{}

    with {:ok, archive} <- SourceBundle.archive(repository, assignment),
         :ok <- client().upload_file(execd, config["sourceBundlePath"], archive),
         {:ok, _output} <- run_command(execd, prepare_command(config), config["timeoutSeconds"]),
         :ok <-
           client().upload_file(
             execd,
             config["contextPath"],
             JSON.encode!(assignment["context_pack"] || %{})
           ),
         :ok <- maybe_upload_provider_runtime(execd, config) do
      {:ok,
       session
       |> Session.mark("prepared")
       |> Map.merge(%{
         "base_branch" => assignment["base_branch"],
         "base_sha" => assignment["base_sha"],
         "repo_key" => assignment["repo_key"],
         "workspace_mode" => "source_bundle",
         "result_path" => config["resultPath"]
       })}
    else
      {:error, reason} -> {:error, safe_reason(reason)}
    end
  end

  @impl true
  def run(session, _context, assignment) do
    config = session["config"] || %{}
    execd = session["execd"] || %{}

    with {:ok, _output} <- run_command(execd, config["runnerCommand"], config["timeoutSeconds"]),
         {:ok, body} <- client().download_file(execd, config["resultPath"]),
         {:ok, result} <- decode_result(body, assignment) do
      {:ok, Map.put(result, "sandboxSession", Session.public_context(session))}
    else
      {:error, reason} -> {:error, safe_reason(reason)}
    end
  end

  @impl true
  def release(session) do
    sandbox_id = session["sandbox_id"]
    config = get_in(session, ["config"]) || %{}

    if is_binary(sandbox_id) and sandbox_id != "" do
      case client().delete(config, sandbox_id) do
        :ok -> :ok
        {:error, reason} -> {:error, safe_reason(reason)}
      end
    else
      :ok
    end
  rescue
    _error -> {:error, "sandbox_release_failed"}
  end

  @impl true
  def readiness(opts) do
    OpenSandboxConfig.readiness(opts)
  end

  defp client do
    Application.get_env(
      :symphonia_service,
      :opensandbox_client,
      SymphoniaService.Sandbox.OpenSandboxClient
    )
  end

  defp require_ready(config) do
    readiness = OpenSandboxConfig.readiness(%{repository: %{}, registry_path: nil})

    cond do
      not present?(config["lifecycleUrl"]) ->
        {:error, "opensandbox_endpoint_missing"}

      not present?(config["apiKey"]) ->
        {:error, "opensandbox_api_key_missing"}

      readiness["provider"] == OpenSandboxConfig.provider_id() ->
        :ok
    end
  end

  defp create_request(config, opts) do
    assignment = opts["assignment"] || %{}

    %{
      "image" => %{"uri" => config["image"]},
      "timeout" => config["ttlSeconds"],
      "resourceLimits" => config["resourceLimits"],
      "entrypoint" => ["tail", "-f", "/dev/null"],
      "metadata" =>
        %{
          "symphonia_repo" => safe_metadata(assignment["repo_key"]),
          "symphonia_task" => safe_metadata(assignment["task_key"]),
          "symphonia_run" => safe_metadata(assignment["run_id"])
        }
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()
    }
  end

  defp wait_until_running(config, sandbox) do
    case sandbox_state(sandbox) do
      "Running" ->
        {:ok, sandbox}

      "Failed" ->
        {:error, "sandbox_create_failed"}

      _other ->
        wait_until_running(config, sandbox_id(sandbox), 20)
    end
  end

  defp wait_until_running(_config, sandbox_id, 0) when is_binary(sandbox_id),
    do: {:error, "sandbox_create_timeout"}

  defp wait_until_running(config, sandbox_id, attempts) when is_binary(sandbox_id) do
    Process.sleep(250)

    case client().get(config, sandbox_id) do
      {:ok, sandbox} ->
        case sandbox_state(sandbox) do
          "Running" -> {:ok, sandbox}
          "Failed" -> {:error, "sandbox_create_failed"}
          _other -> wait_until_running(config, sandbox_id, attempts - 1)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp wait_until_running(_config, _sandbox_id, _attempts), do: {:error, "sandbox_create_failed"}

  defp resolve_execd(%{"execdUrl" => execd_url} = config, sandbox)
       when is_binary(execd_url) and execd_url != "" do
    {:ok,
     %{
       "url" => execd_url,
       "headers" => %{},
       "accessToken" => config["execdAccessToken"],
       "sandboxId" => sandbox_id(sandbox)
     }}
  end

  defp resolve_execd(config, sandbox) do
    with {:ok, endpoint} <- client().endpoint(config, sandbox_id(sandbox), @execd_port),
         url when is_binary(url) <- endpoint_url(endpoint) do
      {:ok,
       %{
         "url" => url,
         "headers" => endpoint_headers(endpoint),
         "accessToken" => endpoint_access_token(endpoint),
         "sandboxId" => sandbox_id(sandbox)
       }}
    else
      _other -> {:error, "opensandbox_execd_endpoint_missing"}
    end
  end

  defp prepare_command(config) do
    source_path = shell_escape(config["sourceBundlePath"])

    [
      "mkdir -p /workspace/.symphonia",
      "tar -xf #{source_path} -C /workspace",
      "cd /workspace",
      "git init -q",
      "git config user.name Symphonia",
      "git config user.email symphonia@sandbox.local",
      "git add -A",
      "git commit --allow-empty -m symphonia-baseline -q"
    ]
    |> Enum.join(" && ")
  end

  defp run_command(execd, command, timeout_seconds) do
    client().run_command(execd, command,
      cwd: "/workspace",
      timeout_ms: max(to_integer(timeout_seconds, 900), 1) * 1_000
    )
  end

  defp maybe_upload_provider_runtime(execd, %{
         "assignmentProvider" => "gemini_cli",
         "providerApiKey" => api_key,
         "providerEnvPath" => path
       })
       when is_binary(api_key) and api_key != "" do
    with :ok <-
           client().upload_file(
             execd,
             ProviderRunnerScript.path(),
             ProviderRunnerScript.content()
           ),
         :ok <- client().upload_file(execd, path, JSON.encode!(%{"GEMINI_API_KEY" => api_key})),
         {:ok, _output} <-
           run_command(
             execd,
             "chmod 700 #{shell_escape(ProviderRunnerScript.path())} && chmod 600 #{shell_escape(path)}",
             30
           ) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_upload_provider_runtime(_execd, %{"assignmentProvider" => "gemini_cli"}),
    do: {:error, "gemini_api_key_missing"}

  defp maybe_upload_provider_runtime(_execd, _config), do: :ok

  defp decode_result(body, assignment) do
    with {:ok, decoded} <- JSON.decode(to_string(body)),
         result when is_map(result) <- decoded["result"] || decoded do
      {:ok, normalize_result(result, assignment)}
    else
      _other -> {:error, "sandbox_result_invalid"}
    end
  end

  defp normalize_result(result, assignment) do
    bundle = result["patchBundle"] || result["patch_bundle"] || %{}
    diff = bundle["diff"] || ""
    changed_files = result["changedFiles"] || result["changed_files"] || []
    changed_paths = Enum.map(changed_files, &changed_file_path/1) |> Enum.reject(&(&1 == ""))

    result
    |> Map.put(
      "assignmentId",
      result["assignmentId"] || result["assignment_id"] || assignment["id"]
    )
    |> Map.put("runId", result["runId"] || result["run_id"] || assignment["run_id"])
    |> Map.put("runnerId", result["runnerId"] || result["runner_id"] || assignment["runner_id"])
    |> Map.put("status", result["status"] || "completed")
    |> Map.put("baseSha", result["baseSha"] || result["base_sha"] || assignment["base_sha"])
    |> Map.put(
      "patchBundle",
      bundle
      |> Map.put_new("format", "git_diff")
      |> Map.put_new("encoding", "utf8")
      |> Map.put_new("sha256", PatchBundle.sha256(diff))
    )
    |> Map.put("changedFiles", changed_files)
    |> Map.put_new("changedFilesDigest", PatchBundle.changed_files_digest(changed_paths))
    |> Map.put_new("publicSummary", public_summary(assignment))
    |> Map.put_new("publicTimeline", [
      %{
        "step" => "running_in_sandbox",
        "message" => public_timeline_message(assignment)
      }
    ])
  end

  defp public_summary(%{"provider" => "gemini_cli"}),
    do: "Gemini CLI produced a reviewable patch."

  defp public_summary(_assignment), do: "OpenSandbox produced a reviewable patch."

  defp public_timeline_message(%{"provider" => "gemini_cli"}),
    do: "Gemini CLI completed the sandbox turn."

  defp public_timeline_message(_assignment),
    do: "OpenSandbox completed the Coding Assistant turn."

  defp changed_file_path(%{"path" => path}) when is_binary(path), do: path
  defp changed_file_path(path) when is_binary(path), do: path
  defp changed_file_path(_value), do: ""

  defp sandbox_id(%{"id" => id}) when is_binary(id), do: id
  defp sandbox_id(%{"sandboxId" => id}) when is_binary(id), do: id
  defp sandbox_id(%{"sandbox_id" => id}) when is_binary(id), do: id
  defp sandbox_id(_sandbox), do: nil

  defp sandbox_state(%{"status" => %{"state" => state}}) when is_binary(state), do: state
  defp sandbox_state(%{"state" => state}) when is_binary(state), do: state
  defp sandbox_state(_sandbox), do: "Running"

  defp endpoint_url(%{"url" => url}) when is_binary(url), do: url
  defp endpoint_url(%{"endpoint" => url}) when is_binary(url), do: url
  defp endpoint_url(%{"publicUrl" => url}) when is_binary(url), do: url
  defp endpoint_url(%{"public_url" => url}) when is_binary(url), do: url
  defp endpoint_url(_endpoint), do: nil

  defp endpoint_headers(%{"headers" => headers}) when is_map(headers), do: headers
  defp endpoint_headers(_endpoint), do: %{}

  defp endpoint_access_token(endpoint) when is_map(endpoint) do
    headers = endpoint_headers(endpoint)

    endpoint["accessToken"] || endpoint["access_token"] ||
      headers["X-EXECD-ACCESS-TOKEN"] || headers["x-execd-access-token"]
  end

  defp sandbox_params(opts) do
    opts
    |> Map.take(["assignment", "registry_path"])
    |> Map.keys()
    |> Enum.reduce(opts, &Map.delete(&2, &1))
  end

  defp safe_metadata(value) when is_binary(value) do
    value
    |> String.replace(~r/[^a-zA-Z0-9_.-]/, "_")
    |> String.slice(0, 63)
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp safe_metadata(_value), do: nil

  defp shell_escape(value) do
    "'" <> String.replace(to_string(value), "'", "'\"'\"'") <> "'"
  end

  defp safe_reason(reason) do
    reason
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9._-]/, "_")
    |> String.slice(0, 80)
    |> case do
      "" -> "sandbox_run_failed"
      value -> OpenSandboxError.normalize(value)
    end
  end

  defp to_integer(value, _default) when is_integer(value), do: value

  defp to_integer(value, default) do
    case Integer.parse(to_string(value || "")) do
      {integer, ""} -> integer
      _other -> default
    end
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
