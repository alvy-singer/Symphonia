defmodule SymphoniaService.PrivacyInventoryTest do
  use ExUnit.Case

  alias SymphoniaService.Privacy.Inventory
  alias SymphoniaService.Secrets.Redactor

  @required_surface_ids ~w(
    private_workspace_artifacts
    private_workspace_evidence
    raw_run_records
    public_run_events
    task_markdown
    handoffs
    run_summaries
    pr_bodies
    audit_events
    provider_context_packs
    clarise_chat_derived_artifacts
    workflow_files
    github_export_snapshots
    review_notes
  )

  test "inventory classifies every required surface for every destination" do
    destinations = MapSet.new(Inventory.destinations())
    surface_ids = Inventory.surfaces() |> Enum.map(& &1["id"]) |> MapSet.new()

    assert MapSet.subset?(MapSet.new(@required_surface_ids), surface_ids)

    for surface <- Inventory.surfaces() do
      assert is_binary(surface["owner"])
      assert is_binary(surface["storage"])
      assert is_binary(surface["sensitivity"])
      assert surface["tests"] != []

      allowed = MapSet.new(surface["allowed_destinations"])
      conditional = MapSet.new(surface["conditional_destinations"])
      blocked = MapSet.new(surface["blocked_destinations"])

      assert MapSet.disjoint?(allowed, conditional)
      assert MapSet.disjoint?(allowed, blocked)
      assert MapSet.disjoint?(conditional, blocked)
      assert MapSet.union(MapSet.union(allowed, conditional), blocked) == destinations
    end
  end

  test "key destination rules match the V1 privacy boundary" do
    assert Inventory.allowed?("private_workspace_artifacts", "local_private_storage")
    assert Inventory.allowed?("private_workspace_artifacts", "providers")
    assert Inventory.allowed?("private_workspace_artifacts", "github")
    assert Inventory.blocked?("private_workspace_artifacts", "audit_logs")
    assert Inventory.blocked?("private_workspace_artifacts", "managed_repository")

    assert Inventory.allowed?("private_workspace_evidence", "local_private_storage")
    assert Inventory.blocked?("private_workspace_evidence", "providers")
    assert Inventory.blocked?("private_workspace_evidence", "github")

    assert Inventory.allowed?("raw_run_records", "local_private_storage")
    refute Inventory.allowed?("raw_run_records", "browser_ui")
    refute Inventory.allowed?("raw_run_records", "providers")
    refute Inventory.allowed?("raw_run_records", "github")
    refute Inventory.allowed?("raw_run_records", "audit_logs")

    assert Inventory.allowed?("public_run_events", "browser_ui")
    assert Inventory.allowed?("provider_context_packs", "providers")
    assert Inventory.blocked?("provider_context_packs", "browser_ui")
    assert Inventory.blocked?("provider_context_packs", "audit_logs")

    assert Inventory.allowed?("workflow_files", "providers")
    assert Inventory.allowed?("workflow_files", "github")
  end

  test "developer inventory document stays in sync with surface and destination ids" do
    document =
      __DIR__
      |> Path.join("../PRIVACY_INVENTORY.md")
      |> Path.expand()
      |> File.read!()

    assert document =~ "not zero-knowledge"
    assert document =~ "not end-to-end encrypted"

    for destination <- Inventory.destinations() do
      assert document =~ "`#{destination}`"
    end

    for surface <- Inventory.surfaces() do
      assert document =~ "`#{surface["id"]}`"
    end
  end

  test "risky fixture values are redacted by the shared public sanitizer" do
    for value <- Inventory.risky_values() do
      sanitized = Redactor.sanitize_value(value)
      encoded = JSON.encode!(sanitized)

      assert sanitized != value
      refute encoded =~ value
    end
  end
end
