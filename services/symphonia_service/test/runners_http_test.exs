defmodule SymphoniaService.RunnersHTTPTest do
  use ExUnit.Case

  alias SymphoniaService.Access.AuditLog
  alias SymphoniaService.CodingAssistant.RunStore
  alias SymphoniaService.Runners.Registry
  alias SymphoniaService.{HTTPServer, RepositoryRegistry, TaskStore, Workspace}

  setup do
    root =
      Path.join(System.tmp_dir!(), "symphonia-runners-http-#{System.unique_integer([:positive])}")

    repo_path = Path.join(root, "repo")
    registry_path = Path.join(root, "repositories.json")
    runs_root = Path.join(root, "runs")
    File.mkdir_p!(Path.join(repo_path, ".git"))

    previous_runs_root = System.get_env("SYMPHONIA_RUNS_ROOT")
    System.put_env("SYMPHONIA_RUNS_ROOT", runs_root)

    repository = RepositoryRegistry.add(registry_path, %{"path" => repo_path, "key" => "SYM"})
    Workspace.initialize(repository)
    task = TaskStore.create_task(registry_path, repository, %{"title" => "Remote runner task"})

    port = free_port()

    {:ok, pid} =
      HTTPServer.start_link(
        port: port,
        registry_path: registry_path,
        name: :"runners_http_#{System.unique_integer([:positive])}"
      )

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
      restore_env("SYMPHONIA_RUNS_ROOT", previous_runs_root)
      File.rm_rf(root)
    end)

    %{port: port, registry_path: registry_path, repository: repository, task: task}
  end

  test "runner routes enforce permissions and never serialize tokens", %{
    port: port,
    registry_path: registry_path
  } do
    assert http_json(port, "GET", "/api/runners", "", [{"x-symphonia-role", "viewer"}]).status ==
             200

    denied =
      http_json(
        port,
        "POST",
        "/api/runners/register",
        registration_body(),
        [{"x-symphonia-role", "viewer"}]
      )

    assert denied.status == 403
    refute File.exists?(Registry.path(registry_path))

    registered =
      http_json(
        port,
        "POST",
        "/api/runners/register",
        registration_body(),
        [{"x-symphonia-role", "owner"}]
      )

    assert registered.status == 201
    runner = registered.body["runner"]
    assert runner["mode"] == "remote_runner"
    refute JSON.encode!(runner) =~ "local-dev-token"
    refute JSON.encode!(runner) =~ "token"

    bad_heartbeat =
      http_json(
        port,
        "POST",
        "/api/runners/#{runner["id"]}/heartbeat",
        ~s({"token":"wrong"}),
        []
      )

    assert bad_heartbeat.status == 403

    heartbeat =
      http_json(
        port,
        "POST",
        "/api/runners/#{runner["id"]}/heartbeat",
        ~s({"token":"local-dev-token","currentRuns":0,"capabilities":{"codexAppServer":true,"validation":true}}),
        []
      )

    assert heartbeat.status == 200
    assert heartbeat.body["runner"]["status"] == "online"

    disabled =
      http_json(
        port,
        "POST",
        "/api/runners/#{runner["id"]}/disable",
        "",
        [{"x-symphonia-role", "owner"}]
      )

    assert disabled.status == 200
    assert disabled.body["runner"]["status"] == "disabled"

    enabled =
      http_json(
        port,
        "POST",
        "/api/runners/#{runner["id"]}/enable",
        "",
        [{"x-symphonia-role", "owner"}]
      )

    assert enabled.status == 200

    actions =
      registry_path
      |> AuditLog.list(%{"key" => "GLOBAL"}, limit: :all)
      |> Enum.map(& &1["action"])

    assert "runner.register" in actions
    assert "runner.disable" in actions
    assert "runner.enable" in actions
  end

  test "manual remote runner selection is rejected before a run starts", %{
    port: port,
    registry_path: registry_path,
    task: task
  } do
    registered =
      http_json(
        port,
        "POST",
        "/api/runners/register",
        registration_body(%{"localGitWorktree" => true}),
        [{"x-symphonia-role", "owner"}]
      )

    runner_id = registered.body["runner"]["id"]

    rejected =
      http_json(
        port,
        "POST",
        "/api/repositories/SYM/tasks/#{task["key"]}/coding-assistant/runs",
        JSON.encode!(%{"runnerId" => runner_id}),
        [{"x-symphonia-role", "maintainer"}]
      )

    assert rejected.status == 403
    assert rejected.body["reasonCode"] == "remote_execution_disabled"
    assert RunStore.list() == []

    assert [%{"action" => "runner.rejected_for_run"} | _rest] =
             AuditLog.list(registry_path, %{"key" => "SYM"}, limit: :all)
  end

  defp registration_body(extra_capabilities \\ %{}) do
    JSON.encode!(%{
      "name" => "runner-mac-mini",
      "registrationToken" => "local-dev-token",
      "capabilities" =>
        Map.merge(
          %{
            "codexAppServer" => true,
            "localGitWorktree" => false,
            "experimentalSandbox" => false,
            "validation" => true
          },
          extra_capabilities
        ),
      "limits" => %{"maxConcurrentRuns" => 1}
    })
  end

  defp http_json(port, method, path, body, headers) do
    {:ok, socket} = :gen_tcp.connect(~c"localhost", port, [:binary, active: false], 5_000)

    header_lines =
      [{"host", "localhost"}, {"content-length", byte_size(body)} | headers]
      |> Enum.map(fn {key, value} -> "#{key}: #{value}\r\n" end)
      |> Enum.join()

    :ok = :gen_tcp.send(socket, "#{method} #{path} HTTP/1.1\r\n#{header_lines}\r\n#{body}")
    {:ok, raw} = :gen_tcp.recv(socket, 0, 5_000)
    :gen_tcp.close(socket)

    [head, response_body] = String.split(raw, "\r\n\r\n", parts: 2)
    [status_line | _headers] = String.split(head, "\r\n")
    ["HTTP/1.1", status, reason] = String.split(status_line, " ", parts: 3)

    %{
      status: String.to_integer(status),
      reason: reason,
      body: if(response_body == "", do: %{}, else: JSON.decode!(response_body))
    }
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, {_address, port}} = :inet.sockname(socket)
    :gen_tcp.close(socket)
    port
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
