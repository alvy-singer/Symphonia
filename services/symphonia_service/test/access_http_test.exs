defmodule SymphoniaService.AccessHTTPTest do
  use ExUnit.Case

  alias SymphoniaService.Access.AuditLog
  alias SymphoniaService.CodingAssistant.RunStore
  alias SymphoniaService.Harness.{Daemon, LocalState}
  alias SymphoniaService.{HTTPServer, RepositoryRegistry, TaskStore, Workspace}

  setup do
    root =
      Path.join(System.tmp_dir!(), "symphonia-access-http-#{System.unique_integer([:positive])}")

    repo_path = Path.join(root, "repo")
    registry_path = Path.join(root, "repositories.json")
    runs_root = Path.join(root, "runs")
    File.mkdir_p!(Path.join(repo_path, ".git"))

    previous_runs_root = System.get_env("SYMPHONIA_RUNS_ROOT")
    System.put_env("SYMPHONIA_RUNS_ROOT", runs_root)
    stop_daemon()

    repository = RepositoryRegistry.add(registry_path, %{"path" => repo_path, "key" => "SYM"})
    Workspace.initialize(repository)
    task = TaskStore.create_task(registry_path, repository, %{"title" => "Access task"})

    port = free_port()

    {:ok, pid} =
      HTTPServer.start_link(
        port: port,
        registry_path: registry_path,
        name: :"access_http_#{System.unique_integer([:positive])}"
      )

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
      stop_daemon()
      restore_env("SYMPHONIA_RUNS_ROOT", previous_runs_root)
      File.rm_rf(root)
    end)

    %{registry_path: registry_path, repository: repository, task: task, port: port}
  end

  test "unauthorized Codex run returns 403 and creates no run", %{port: port, task: task} do
    response =
      http_json(
        port,
        "POST",
        "/api/repositories/SYM/tasks/#{task["key"]}/coding-assistant/runs",
        "{}",
        [{"x-symphonia-role", "viewer"}]
      )

    assert response.status == 403
    assert response.reason == "Forbidden"
    assert response.body["permission"] == "task.run_codex"
    assert RunStore.list() == []
  end

  test "unauthorized approve leaves task unchanged and records denied audit", %{
    port: port,
    registry_path: registry_path,
    repository: repository,
    task: task
  } do
    TaskStore.patch_task(repository, task["key"], %{
      "frontmatter" => %{
        "status" => "in_review",
        "handoff" => %{"summary" => "Ready", "files_changed" => ["lib/example.ex"]}
      }
    })

    response =
      http_json(
        port,
        "POST",
        "/api/repositories/SYM/tasks/#{task["key"]}/events",
        ~s({"event":"approve"}),
        [{"x-symphonia-role", "operator"}]
      )

    assert response.status == 403
    refute TaskStore.get_task(repository, task["key"])["reviewApproved"]

    assert [event] = AuditLog.list_for_task(registry_path, repository, task["key"])
    assert event["action"] == "review.approve"
    assert event["result"] == "denied"
  end

  test "unauthorized Harness pause leaves local state unchanged", %{
    port: port,
    registry_path: registry_path
  } do
    response =
      http_json(port, "POST", "/api/harness/pause?repoKey=SYM", "", [
        {"x-symphonia-role", "reviewer"}
      ])

    assert response.status == 403
    refute LocalState.load(registry_path)["paused"]
    assert Process.whereis(Daemon) == nil
  end

  test "failed authorized action records failed audit", %{
    port: port,
    registry_path: registry_path,
    repository: repository,
    task: task
  } do
    response =
      http_json(
        port,
        "POST",
        "/api/repositories/SYM/tasks/#{task["key"]}/open-pull-request",
        "",
        [{"x-symphonia-role", "maintainer"}]
      )

    assert response.status == 400
    assert [event] = AuditLog.list_for_task(registry_path, repository, task["key"])
    assert event["action"] == "pull_request.open"
    assert event["result"] == "failed"
  end

  test "actor headers are accepted by service access endpoint", %{port: port} do
    response =
      http_json(port, "GET", "/api/repositories/SYM/access", "", [
        {"x-symphonia-role", "reviewer"},
        {"x-symphonia-actor", "Ava"},
        {"x-symphonia-actor-id", "user:ava"}
      ])

    assert response.status == 200
    assert response.body["role"] == "reviewer"
    assert response.body["permissions"]["review.approve"] == true
    assert response.body["permissions"]["pull_request.open"] == false
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

  defp stop_daemon do
    try do
      case Process.whereis(Daemon) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end
    catch
      :exit, _ -> :ok
    end
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
