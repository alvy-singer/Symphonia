defmodule SymphoniaService.ProviderContractTest do
  use ExUnit.Case

  alias SymphoniaService.CodingAssistant.{
    AppServerProvider,
    FailureClass,
    ProviderCatalog,
    RunStore
  }

  test "AppServerProvider declares the full review-first capability contract" do
    capabilities = AppServerProvider.capabilities()

    for capability <- ProviderCatalog.required_capabilities() do
      assert capabilities[capability] == true
    end

    status = ProviderCatalog.harness_status(mode: :check_only)
    codex = Enum.find(status["providers"], &(&1["id"] == "codex_app_server"))

    assert codex["runnableByHarness"] == true
    assert codex["missingCapabilities"] == []
  end

  test "AppServerProvider source stays on the review-first path" do
    source =
      File.read!(
        Path.expand(
          "../lib/symphonia_service/coding_assistant/app_server_provider.ex",
          __DIR__
        )
      )

    assert source =~ "ContextPack.render_prompt"
    assert source =~ "WorkspaceProviders.prepare"
    assert source =~ "WorkspaceProviders.review_context"
    assert source =~ "ChangeApplier.apply"
    assert source =~ "RunStore.record_provider_output"
    assert source =~ "run_validation"
    assert source =~ "CuratedSummary.write!"
    assert source =~ "HandoffBuilder.build_from_changes"
    assert source =~ "BranchManager.commit_files!"
    refute source =~ "PullRequests.open_from_task"
    refute source =~ "auto_merge"
  end

  test "check-only provider readiness does not create run records" do
    root =
      Path.join(
        System.tmp_dir!(),
        "symphonia-provider-contract-#{System.unique_integer([:positive])}"
      )

    previous_runs_root = System.get_env("SYMPHONIA_RUNS_ROOT")
    System.put_env("SYMPHONIA_RUNS_ROOT", root)

    on_exit(fn ->
      restore_env("SYMPHONIA_RUNS_ROOT", previous_runs_root)
      File.rm_rf(root)
    end)

    assert RunStore.list() == []

    _status = AppServerProvider.readiness(mode: :check_only)

    assert RunStore.list() == []
  end

  test "AppServerProvider classifies failures into allowed classes" do
    for {reason, expected} <- [
          {"Validation failed.", "validation_failed"},
          {"The workspace lock is temporarily unavailable.", "transient_workspace"},
          {"The Coding Assistant did not produce any files.", "no_reviewable_files"},
          {"Codex App Server did not respond during startup.", "transient_provider"}
        ] do
      failure_class = AppServerProvider.classify_failure(reason, %{})
      assert failure_class == expected
      assert failure_class in FailureClass.all()
    end
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
