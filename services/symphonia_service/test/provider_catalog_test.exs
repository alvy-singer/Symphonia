defmodule SymphoniaService.ProviderCatalogTest do
  use ExUnit.Case

  alias SymphoniaService.CodingAssistant.ProviderCatalog

  test "Harness V1 exposes only Codex App Server as runnable" do
    status = ProviderCatalog.harness_status()
    providers = Map.new(status["providers"], &{&1["id"], &1})

    assert status["defaultProvider"] == "codex_app_server"
    assert status["runnableProvider"] == "codex_app_server"
    assert providers["codex_app_server"]["runnable"] == true

    for disabled <- ["claude_code", "gemini", "cursor"] do
      assert providers[disabled]["runnable"] == false
      assert providers[disabled]["reason"] == "Not runnable by Harness V1."
    end

    refute Map.has_key?(providers, "codex")
    refute Map.has_key?(providers, "cloud_sandbox")
    refute Code.ensure_loaded?(SymphoniaService.Runner.CloudSandboxProvider)
  end
end
