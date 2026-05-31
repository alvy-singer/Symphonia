defmodule SymphoniaService.ProviderCatalogTest do
  use ExUnit.Case

  alias SymphoniaService.CodingAssistant.{
    AppServerProvider,
    CodexProvider,
    FailureClass,
    LocalDemoProvider,
    ProviderCatalog
  }

  alias SymphoniaService.{Harness.Automation, RepositoryRegistry}

  test "Harness V2 exposes only Codex App Server as Harness runnable" do
    status = ProviderCatalog.harness_status(mode: :check_only)
    providers = Map.new(status["providers"], &{&1["id"], &1})

    assert status["defaultProvider"] == "codex_app_server"
    assert status["runnableProvider"] == "codex_app_server"
    assert ProviderCatalog.harness_runnable_provider().id() == "codex_app_server"
    assert providers["codex_app_server"]["runnableByHarness"] == true

    gemini = providers["gemini_cli"]
    assert gemini["runnableByHarness"] == false
    assert gemini["manualOnly"] == true
    assert gemini["executionMode"] == "cloud_sandbox"

    for disabled <- ["claude_code", "cursor", "codex"] do
      assert providers[disabled]["runnableByHarness"] == false
      assert providers[disabled]["runnable"] == false
      assert is_binary(providers[disabled]["reason"])
    end

    refute Map.has_key?(providers, "cloud_sandbox")
    assert Code.ensure_loaded?(SymphoniaService.Runner.CloudSandboxProvider)
  end

  test "provider rows expose deterministic contract fields" do
    status = ProviderCatalog.harness_status(mode: :check_only)
    providers = Map.new(status["providers"], &{&1["id"], &1})
    codex = providers["codex_app_server"]
    claude = providers["claude_code"]

    assert codex["label"] == "Codex App Server"
    assert codex["capabilities"]["context_pack"] == true
    assert codex["capabilities"]["validation_pipeline"] == true
    assert codex["capabilities"]["handoff"] == true
    assert codex["missingCapabilities"] == []

    assert claude["status"] == "experimental"
    assert claude["missingCapabilities"] == Enum.sort(claude["missingCapabilities"])
    assert "handoff" in claude["missingCapabilities"]
    assert "review_branch" in claude["missingCapabilities"]
    assert "validation_pipeline" in claude["missingCapabilities"]
  end

  test "public provider reasons are sanitized" do
    status = ProviderCatalog.harness_status(mode: :check_only)
    encoded = JSON.encode!(status)

    refute encoded =~ "/Users/"
    refute encoded =~ "SYMPHONIA_"
    refute encoded =~ "thread-"
    refute encoded =~ "turn-"
    refute encoded =~ "provider_output"
    refute encoded =~ "raw_log"
  end

  test "existing provider modules implement the required contract callbacks" do
    for provider <- [
          AppServerProvider,
          CodexProvider,
          SymphoniaService.CodingAssistant.GeminiCliProvider,
          LocalDemoProvider
        ] do
      assert Code.ensure_loaded?(provider)
      assert function_exported?(provider, :id, 0)
      assert function_exported?(provider, :label, 0)
      assert function_exported?(provider, :capabilities, 0)
      assert function_exported?(provider, :readiness, 1)
      assert function_exported?(provider, :preflight, 3)
      assert function_exported?(provider, :run, 4)
      assert function_exported?(provider, :classify_failure, 2)
    end
  end

  test "failure classes normalize through one contract module" do
    assert FailureClass.all() == ~w(
             setup_blocked
             transient_provider
             transient_workspace
             validation_failed
             no_reviewable_files
             user_blocked
             unknown
           )

    assert FailureClass.classify("Validation failed.", %{}) == "validation_failed"

    assert FailureClass.classify("The workspace lock is temporarily unavailable.", %{}) ==
             "transient_workspace"

    assert FailureClass.classify("The Coding Assistant did not produce any files.", %{}) ==
             "no_reviewable_files"

    assert FailureClass.normalize("provider_specific_value") == "unknown"
  end

  test "automation enable coerces unknown providers to Codex App Server" do
    root =
      Path.join(
        System.tmp_dir!(),
        "symphonia-provider-catalog-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    System.cmd("git", ["init", "-b", "main", root])
    registry_path = Path.join(root, "registry.json")

    on_exit(fn -> File.rm_rf(root) end)

    RepositoryRegistry.add(registry_path, %{"key" => "SYM", "path" => root})

    repository = Automation.enable(registry_path, "SYM", %{"provider" => "claude_code"})

    assert Automation.status(repository)["enabled"] == true
    assert Automation.status(repository)["provider"] == "codex_app_server"
  end
end
