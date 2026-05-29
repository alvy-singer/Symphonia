defmodule SymphoniaService.CodingAssistant.AppServerClient do
  @moduledoc """
  Minimal JSON-RPC client for Codex App Server task turns.

  Request shapes are kept aligned with the generated schema bundle in
  `priv/codex_app_server_schema`.
  """

  @default_startup_timeout_ms 20_000
  @default_turn_timeout_ms 900_000
  @startup_timeout_message "Codex App Server did not respond during startup."
  @managed_standalone_relative_path Path.join([
                                      ".codex",
                                      "packages",
                                      "standalone",
                                      "current",
                                      "codex"
                                    ])
  @setup_blocker_message "Codex is not ready on this machine. Symphonia could not find the managed Codex standalone binary needed to start Codex App Server. Install or repair Codex locally, then retry. No changes were made."
  @schema_files [
    "ClientRequest.json",
    "v2/ThreadStartParams.json",
    "v2/ThreadResumeParams.json",
    "v2/TurnStartParams.json",
    "v2/TurnCompletedNotification.json"
  ]

  def ensure_schema_bundle! do
    for file <- @schema_files do
      path = Path.join(schema_root(), file)

      unless File.exists?(path) do
        raise ArgumentError,
              "Codex App Server schema is missing at #{path}. Regenerate with `codex app-server generate-json-schema --experimental --out services/symphonia_service/priv/codex_app_server_schema`."
      end
    end

    :ok
  end

  def setup_blocker_message, do: @setup_blocker_message

  def setup_blocker?(reason) when is_binary(reason) do
    String.trim(reason) == @setup_blocker_message
  end

  def setup_blocker?(_reason), do: false

  def check_ready(opts \\ []) do
    schema_available? = schema_available?()
    binary_status = binary_status(opts)
    command_override? = app_server_command_override?(opts)
    binary_available? = command_override? or binary_status["available"]
    configured? = command_override? or configured_bin?(opts) or binary_status["available"]
    ready? = schema_available? and binary_available?

    %{
      "configured" => configured?,
      "schemaAvailable" => schema_available?,
      "binaryAvailable" => binary_available?,
      "daemonReachable" => nil,
      "ready" => ready?,
      "reason" => check_ready_reason(ready?, schema_available?, binary_available?, binary_status)
    }
  end

  def ensure_daemon_ready!(opts \\ []) do
    cond do
      truthy?(System.get_env("SYMPHONIA_CODEX_APP_SERVER_SKIP_DAEMON")) ->
        :ok

      app_server_command_override?(opts) ->
        :ok

      true ->
        daemon_bin!(opts)
        :ok
    end
  end

  def ensure_daemon!(opts \\ []) do
    cond do
      truthy?(System.get_env("SYMPHONIA_CODEX_APP_SERVER_SKIP_DAEMON")) ->
        :ok

      app_server_command_override?(opts) ->
        :ok

      true ->
        daemon_bin!(opts)
        :ok
    end
  end

  def run_turn(workspace_path, prompt, opts \\ []) do
    ensure_schema_bundle!()
    ensure_daemon!(opts)

    port = open_port(opts)

    try do
      events = []
      notify_step(opts, "Starting Codex App Server")
      {_result, events} = initialize!(port, events, opts)
      notify_step(opts, "Starting Codex thread")

      {thread_id, events} =
        case Keyword.get(opts, :thread_id) do
          value when is_binary(value) and value != "" ->
            resume_thread!(port, value, workspace_path, events, opts)

          _ ->
            start_thread!(port, workspace_path, events, opts)
        end

      notify_thread_id(opts, thread_id)
      notify_step(opts, "Starting Codex turn")
      {turn_id, events} = start_turn!(port, thread_id, workspace_path, prompt, events, opts)
      notify_turn_id(opts, turn_id)
      notify_step(opts, "Codex is working")
      {events, completed} = wait_for_turn_completed(port, thread_id, turn_id, events, opts)

      {:ok,
       %{
         "thread_id" => thread_id,
         "turn_id" => turn_id,
         "events" => events,
         "last_message" => last_message(events),
         "turn" => completed
       }}
    catch
      {:app_server_error, reason, events} ->
        {:error, reason, events}
    after
      close_port(port)
    end
  end

  defp initialize!(port, events, opts) do
    request!(
      port,
      "initialize",
      %{
        "clientInfo" => %{"name" => "symphonia", "title" => "Symphonía", "version" => "0.1.0"},
        "capabilities" => %{"experimentalApi" => true}
      },
      events,
      opts
    )
  end

  defp start_thread!(port, workspace_path, events, opts) do
    params =
      %{
        "approvalPolicy" => "never",
        "approvalsReviewer" => "auto_review",
        "cwd" => workspace_path,
        "runtimeWorkspaceRoots" => [workspace_path],
        "sandbox" => sandbox(opts),
        "serviceName" => "symphonia",
        "threadSource" => "subagent"
      }
      |> maybe_put("model", configured_model())

    {result, events} = request!(port, "thread/start", params, events, opts)

    thread_id =
      get_in(result, ["thread", "id"]) || get_in(result, ["thread", "threadId"]) ||
        result["threadId"]

    if blank?(thread_id) do
      throw({:app_server_error, "Codex App Server did not return a thread id.", events})
    end

    {thread_id, events}
  end

  defp resume_thread!(port, thread_id, workspace_path, events, opts) do
    params =
      %{
        "approvalPolicy" => "never",
        "approvalsReviewer" => "auto_review",
        "cwd" => workspace_path,
        "excludeTurns" => true,
        "runtimeWorkspaceRoots" => [workspace_path],
        "sandbox" => sandbox(opts),
        "threadId" => thread_id
      }
      |> maybe_put("model", configured_model())

    {_result, events} = request!(port, "thread/resume", params, events, opts)
    {thread_id, events}
  end

  defp start_turn!(port, thread_id, workspace_path, prompt, events, opts) do
    params = %{
      "approvalPolicy" => "never",
      "approvalsReviewer" => "auto_review",
      "cwd" => workspace_path,
      "input" => [%{"type" => "text", "text" => prompt}],
      "runtimeWorkspaceRoots" => [workspace_path],
      "threadId" => thread_id
    }

    {result, events} = request!(port, "turn/start", params, events, opts)

    turn_id =
      get_in(result, ["turn", "id"]) || get_in(result, ["turn", "turnId"]) || result["turnId"]

    if blank?(turn_id) do
      throw({:app_server_error, "Codex App Server did not return a turn id.", events})
    end

    {turn_id, events}
  end

  defp request!(port, method, params, events, opts) do
    id = next_request_id()
    send_request(port, id, method, params)
    wait_for_response(port, id, events, startup_timeout_ms(opts), @startup_timeout_message)
  end

  defp wait_for_response(port, id, events, timeout_ms, timeout_message) do
    {message, events} = receive_message(port, events, timeout_ms, timeout_message)

    cond do
      message["id"] == id and is_map(message["result"]) ->
        {message["result"], events}

      message["id"] == id and is_map(message["error"]) ->
        throw({:app_server_error, jsonrpc_error(message["error"]), events})

      true ->
        wait_for_response(port, id, events, timeout_ms, timeout_message)
    end
  end

  defp wait_for_turn_completed(port, thread_id, turn_id, events, opts) do
    {message, events} =
      receive_message(
        port,
        events,
        turn_timeout_ms(opts),
        "Codex App Server did not complete before the run timed out."
      )

    case message do
      %{"method" => "turn/completed", "params" => params} ->
        completed_turn = params["turn"] || %{}

        if params["threadId"] == thread_id and turn_matches?(completed_turn, turn_id) do
          case turn_error(completed_turn) do
            nil -> {events, completed_turn}
            reason -> throw({:app_server_error, reason, events})
          end
        else
          wait_for_turn_completed(port, thread_id, turn_id, events, opts)
        end

      %{"method" => "error", "params" => params} ->
        throw(
          {:app_server_error, params["message"] || "Codex App Server reported an error.", events}
        )

      _ ->
        wait_for_turn_completed(port, thread_id, turn_id, events, opts)
    end
  end

  defp receive_message(port, events, timeout_ms, timeout_message) do
    receive do
      {^port, {:data, data}} ->
        data
        |> data_lines()
        |> Enum.reduce({nil, events}, fn line, {_message, acc_events} ->
          message = JSON.decode!(line)
          {message, append_event(acc_events, message)}
        end)
        |> case do
          {nil, acc_events} -> receive_message(port, acc_events, timeout_ms, timeout_message)
          {message, acc_events} -> {message, acc_events}
        end

      {^port, {:exit_status, status}} ->
        throw(
          {:app_server_error, "Codex App Server process exited with status #{status}.", events}
        )
    after
      timeout_ms ->
        throw({:app_server_error, timeout_message, events})
    end
  rescue
    error -> throw({:app_server_error, Exception.message(error), events})
  end

  defp append_event(events, message) do
    event =
      %{
        "received_at" => now(),
        "method" => message["method"],
        "id" => message["id"],
        "params" => message["params"],
        "result" => message["result"],
        "error" => message["error"]
      }
      |> reject_nil()

    events ++ [event]
  end

  defp send_request(port, id, method, params) do
    Port.command(
      port,
      JSON.encode!(%{"id" => id, "method" => method, "params" => params}) <> "\n"
    )
  end

  defp open_port(opts) do
    {command, args} = app_server_command(opts)

    Port.open({:spawn_executable, command}, [
      :binary,
      :exit_status,
      :use_stdio,
      {:args, args},
      {:line, 65_536}
    ])
  end

  defp app_server_command(opts) do
    cond do
      command = nonblank(Keyword.get(opts, :command)) ->
        {command, Keyword.get(opts, :args, [])}

      command = nonblank(System.get_env("SYMPHONIA_CODEX_APP_SERVER_COMMAND")) ->
        {command, split_args(System.get_env("SYMPHONIA_CODEX_APP_SERVER_ARGS") || "")}

      true ->
        {daemon_bin!(opts), ["app-server", "--listen", "stdio://"]}
    end
  end

  defp split_args(""), do: []
  defp split_args(value), do: String.split(value, " ", trim: true)

  defp daemon_bin!(opts) do
    case configured_codex_bin(opts) do
      value when is_binary(value) and value != "" -> executable_bin!(value)
      _ -> managed_standalone_bin!()
    end
  end

  defp configured_codex_bin(opts) do
    Keyword.get(opts, :codex_bin) ||
      System.get_env("SYMPHONIA_CODEX_BIN") ||
      System.get_env("SYMPHONIA_CODEX_APP_SERVER_BIN")
  end

  defp executable_bin!(configured) do
    cond do
      Path.type(configured) == :absolute and executable_file?(configured) ->
        configured

      executable = System.find_executable(configured) ->
        executable

      true ->
        raise ArgumentError,
              "The Coding Assistant can't start because Codex is not available on this computer."
    end
  end

  defp managed_standalone_bin! do
    path = managed_standalone_path()

    if executable_file?(path) do
      path
    else
      raise ArgumentError, @setup_blocker_message
    end
  end

  defp managed_standalone_path do
    case System.get_env("SYMPHONIA_CODEX_APP_SERVER_STANDALONE_BIN") do
      value when is_binary(value) and value != "" ->
        Path.expand(value)

      _ ->
        Path.join(System.user_home!(), @managed_standalone_relative_path)
    end
  end

  defp executable_file?(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular, mode: mode}} -> Bitwise.band(mode, 0o111) != 0
      _ -> false
    end
  end

  defp app_server_command_override?(opts) do
    command = Keyword.get(opts, :command) || System.get_env("SYMPHONIA_CODEX_APP_SERVER_COMMAND")
    not is_nil(nonblank(command))
  end

  defp schema_available? do
    Enum.all?(@schema_files, fn file ->
      schema_root() |> Path.join(file) |> File.exists?()
    end)
  end

  defp binary_status(opts) do
    cond do
      truthy?(System.get_env("SYMPHONIA_CODEX_APP_SERVER_SKIP_DAEMON")) ->
        %{"available" => true, "reason" => "Codex App Server daemon check is skipped."}

      configured = configured_codex_bin(opts) ->
        case executable_bin(configured) do
          {:ok, _path} ->
            %{"available" => true, "reason" => "Codex binary is available."}

          {:error, reason} ->
            %{"available" => false, "reason" => reason}
        end

      executable_file?(managed_standalone_path()) ->
        %{"available" => true, "reason" => "Managed Codex standalone is available."}

      true ->
        %{"available" => false, "reason" => @setup_blocker_message}
    end
  end

  defp configured_bin?(opts), do: not is_nil(nonblank(configured_codex_bin(opts)))

  defp executable_bin(configured) do
    cond do
      Path.type(configured) == :absolute and executable_file?(configured) ->
        {:ok, configured}

      executable = System.find_executable(configured) ->
        {:ok, executable}

      true ->
        {:error, "Codex is not available on this computer."}
    end
  end

  defp check_ready_reason(true, _schema_available?, _binary_available?, _binary_status) do
    "Ready for local Codex runs."
  end

  defp check_ready_reason(_ready?, false, _binary_available?, _binary_status) do
    "Codex App Server schema is missing. Regenerate the schema bundle before running Codex."
  end

  defp check_ready_reason(_ready?, _schema_available?, false, binary_status) do
    binary_status["reason"] || @setup_blocker_message
  end

  defp nonblank(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp nonblank(_value), do: nil

  defp schema_root do
    Path.expand(Path.join([__DIR__, "..", "..", "..", "priv", "codex_app_server_schema"]))
  end

  defp turn_matches?(turn, turn_id) do
    turn["id"] == turn_id or turn["turnId"] == turn_id
  end

  defp turn_error(turn) do
    cond do
      is_binary(turn["error"]) and String.trim(turn["error"]) != "" ->
        turn["error"]

      is_map(turn["error"]) ->
        JSON.encode!(turn["error"])

      turn["status"] in ["failed", "interrupted", "canceled"] ->
        "Codex App Server turn ended with status #{turn["status"]}."

      true ->
        nil
    end
  end

  defp last_message(events) do
    events
    |> Enum.map(fn event ->
      params = event["params"] || %{}
      text = params["text"] || params["message"] || delta_text(params["delta"])

      if is_binary(text) and String.trim(text) != "" do
        text
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("")
    |> String.trim()
    |> case do
      "" -> ""
      value -> value
    end
  end

  defp delta_text(%{"text" => text}), do: text
  defp delta_text(text) when is_binary(text), do: text
  defp delta_text(_delta), do: nil

  defp jsonrpc_error(error) do
    error["message"] || JSON.encode!(error)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp configured_model do
    case System.get_env("SYMPHONIA_CODEX_MODEL") do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp sandbox(opts) do
    case Keyword.get(opts, :sandbox) do
      value when is_binary(value) and value != "" -> value
      _ -> "workspace-write"
    end
  end

  defp startup_timeout_ms(opts) do
    timeout_value(
      Keyword.get(opts, :startup_timeout_ms) ||
        System.get_env("SYMPHONIA_CODEX_STARTUP_TIMEOUT_MS") ||
        Keyword.get(opts, :timeout_ms),
      @default_startup_timeout_ms
    )
  end

  defp turn_timeout_ms(opts) do
    timeout_value(
      Keyword.get(opts, :timeout_ms) || System.get_env("SYMPHONIA_CODEX_TIMEOUT_MS"),
      @default_turn_timeout_ms
    )
  end

  defp timeout_value(value, default) do
    case value do
      value when is_integer(value) and value > 0 ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} when int > 0 -> int
          _ -> default
        end

      _ ->
        default
    end
  end

  defp notify_step(opts, step), do: notify(opts, :on_step, step)
  defp notify_thread_id(opts, thread_id), do: notify(opts, :on_thread_id, thread_id)
  defp notify_turn_id(opts, turn_id), do: notify(opts, :on_turn_id, turn_id)

  defp notify(opts, key, value) do
    case Keyword.get(opts, key) do
      fun when is_function(fun, 1) -> fun.(value)
      _ -> :ok
    end
  end

  defp next_request_id, do: System.unique_integer([:positive])
  defp data_lines({:eol, line}), do: [to_string(line)]
  defp data_lines({:noeol, ""}), do: []
  defp data_lines({:noeol, line}), do: [to_string(line)]
  defp data_lines(data), do: data |> to_string() |> String.split("\n", trim: true)
  defp reject_nil(map), do: map |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new()
  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(_), do: false
  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp close_port(port) do
    Port.close(port)
  rescue
    _ -> :ok
  end
end
