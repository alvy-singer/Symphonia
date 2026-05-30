defmodule SymphoniaService.RunnersRegistryTest do
  use ExUnit.Case

  alias SymphoniaService.Access.AuditLog
  alias SymphoniaService.Runners.{FakeRunner, Registry, SelectionPolicy}

  setup do
    root = Path.join(System.tmp_dir!(), "symphonia-runners-#{System.unique_integer([:positive])}")
    registry_path = Path.join(root, "repositories.json")
    runs_root = Path.join(root, "runs")

    previous_runs_root = System.get_env("SYMPHONIA_RUNS_ROOT")
    System.put_env("SYMPHONIA_RUNS_ROOT", runs_root)

    on_exit(fn ->
      restore_env("SYMPHONIA_RUNS_ROOT", previous_runs_root)
      File.rm_rf(root)
    end)

    %{
      registry_path: registry_path,
      repository: %{"key" => "SYM", "remoteExecutionAllowed" => true},
      owner: %{"id" => "owner", "name" => "Owner", "role" => "owner"},
      maintainer: %{"id" => "maintainer", "name" => "Maintainer", "role" => "maintainer"},
      operator: %{"id" => "operator", "name" => "Operator", "role" => "operator"}
    }
  end

  test "local-service is synthesized and remote registration is public-safe", %{
    registry_path: registry_path,
    owner: owner
  } do
    [local] = Registry.list(registry_path)
    assert local["id"] == "local-service"
    assert local["mode"] == "local_service"
    assert local["status"] == "online"

    {:ok, runner} =
      Registry.register(registry_path, owner, %{
        "name" => "runner-mac-mini",
        "registrationToken" => "local-dev-token",
        "capabilities" => %{
          "codexAppServer" => true,
          "localGitWorktree" => false,
          "experimentalSandbox" => false,
          "validation" => true,
          "privateHostPath" => "/Users/example/repo"
        },
        "limits" => %{"maxConcurrentRuns" => 1}
      })

    public = Registry.public(runner)

    assert public["mode"] == "remote_runner"

    assert public["capabilities"] == %{
             "codexAppServer" => true,
             "localGitWorktree" => false,
             "experimentalSandbox" => false,
             "validation" => true
           }

    encoded_public = JSON.encode!(public)
    refute encoded_public =~ "token"
    refute encoded_public =~ "local-dev-token"
    refute encoded_public =~ "/Users/example"

    private_body = File.read!(Registry.path(registry_path))
    assert private_body =~ "tokenHash"
    refute private_body =~ "local-dev-token"
  end

  test "heartbeat, stale, offline, and disabled status are derived safely", %{
    registry_path: registry_path,
    owner: owner
  } do
    {:ok, runner} = Registry.register(registry_path, owner, FakeRunner.registration_attrs())

    assert Registry.heartbeat(registry_path, runner["id"], "bad-token", %{}) ==
             {:error, :invalid_token}

    {:ok, updated, _transition} =
      Registry.heartbeat(registry_path, runner["id"], "fake-runner-token", %{
        "currentRuns" => 0,
        "capabilities" => FakeRunner.capabilities()
      })

    assert Registry.public(updated)["status"] == "online"

    old = DateTime.utc_now() |> DateTime.add(-120, :second) |> DateTime.to_iso8601()

    overwrite_runner(registry_path, runner["id"], %{
      "lastHeartbeatAt" => old,
      "lastObservedStatus" => "online"
    })

    assert [%{"after" => "stale"}] = Registry.mark_stale(registry_path, DateTime.utc_now())
    {:ok, stale} = Registry.get(registry_path, runner["id"])
    assert Registry.public(stale)["status"] == "stale"

    older = DateTime.utc_now() |> DateTime.add(-360, :second) |> DateTime.to_iso8601()

    overwrite_runner(registry_path, runner["id"], %{
      "lastHeartbeatAt" => older,
      "lastObservedStatus" => "stale"
    })

    assert [%{"after" => "offline"}] = Registry.mark_stale(registry_path, DateTime.utc_now())
    {:ok, offline} = Registry.get(registry_path, runner["id"])
    assert Registry.public(offline)["status"] == "offline"

    {:ok, disabled, _meta} = Registry.disable(registry_path, runner["id"])
    assert Registry.public(disabled)["status"] == "disabled"
  end

  test "selection defaults local and rejects remote unless every gate is open", %{
    registry_path: registry_path,
    repository: repository,
    owner: owner,
    maintainer: maintainer,
    operator: operator
  } do
    {:ok, local} = SelectionPolicy.select_for_run(registry_path, repository, owner)
    assert local["id"] == "local-service"

    {:ok, runner} =
      Registry.register(
        registry_path,
        owner,
        FakeRunner.registration_attrs(%{
          "capabilities" => %{
            "codexAppServer" => true,
            "localGitWorktree" => true,
            "experimentalSandbox" => true,
            "validation" => true
          }
        })
      )

    assert {:error, {403, %{"reasonCode" => "remote_execution_disabled"}}} =
             SelectionPolicy.select_for_run(registry_path, repository, maintainer,
               runner_id: runner["id"],
               workspace_provider: "local_git_worktree"
             )

    assert {:error, {403, %{"reasonCode" => "permission_denied"}}} =
             SelectionPolicy.select_for_run(registry_path, repository, operator,
               runner_id: runner["id"],
               workspace_provider: "local_git_worktree",
               allow_remote_execution: true
             )

    {:ok, selected} =
      SelectionPolicy.select_for_run(registry_path, repository, maintainer,
        runner_id: runner["id"],
        workspace_provider: "local_git_worktree",
        allow_remote_execution: true
      )

    assert selected["id"] == runner["id"]

    overwrite_runner(registry_path, runner["id"], %{"currentRuns" => 1})

    assert {:error, {409, %{"reasonCode" => "runner_capacity_full"}}} =
             SelectionPolicy.select_for_run(registry_path, repository, maintainer,
               runner_id: runner["id"],
               workspace_provider: "local_git_worktree",
               allow_remote_execution: true
             )

    actions =
      registry_path
      |> AuditLog.list(repository, limit: :all)
      |> Enum.map(& &1["action"])

    assert "runner.selected_for_run" in actions
    assert "runner.rejected_for_run" in actions
  end

  test "fake runner exposes a future patch-bundle fixture" do
    fixture = FakeRunner.patch_bundle_fixture("fake-runner", "run_123")

    assert fixture["result_type"] == "patch_bundle"
    assert [%{"path" => "app/example.tsx"}] = fixture["files_changed"]
    assert [%{"status" => "passed"}] = fixture["validation"]
  end

  defp overwrite_runner(registry_path, runner_id, attrs) do
    body = JSON.decode!(File.read!(Registry.path(registry_path)))

    runners =
      Enum.map(body["runners"], fn runner ->
        if runner["id"] == runner_id, do: Map.merge(runner, attrs), else: runner
      end)

    File.write!(Registry.path(registry_path), JSON.encode!(%{"runners" => runners}))
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
