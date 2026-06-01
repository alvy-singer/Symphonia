defmodule SymphoniaService.Access.Permission do
  @moduledoc """
  Canonical repository-scoped permission keys and V1 role matrix.
  """

  @permissions [
    "repository.view",
    "repository.configure",
    "workspace.initialize",
    "private_workspace.read",
    "private_workspace.export",
    "workflow.update",
    "automation.enable",
    "automation.disable",
    "harness.pause",
    "harness.resume",
    "harness.tick",
    "harness.reconcile",
    "task.create",
    "task.update",
    "task.cancel",
    "task.run_codex",
    "task.cancel_run",
    "review.approve",
    "review.request_changes",
    "pull_request.open",
    "pull_request.refresh",
    "provider.configure",
    "sandbox.configure",
    "sandbox.run",
    "workspace_provider.experimental_run",
    "runner.view",
    "runner.register",
    "runner.pair",
    "runner.approve",
    "runner.enable",
    "runner.disable",
    "runner.revoke",
    "runner.rotate_token",
    "runner.use_remote",
    "secret_reference.view",
    "secret_reference.create",
    "secret_reference.delete",
    "secret_scope.configure"
  ]

  @role_permissions %{
    "owner" => MapSet.new(@permissions),
    "maintainer" =>
      MapSet.new(
        @permissions --
          [
            "workspace_provider.experimental_run",
            "sandbox.configure",
            "runner.register",
            "runner.pair",
            "runner.approve",
            "runner.enable",
            "runner.disable",
            "runner.revoke",
            "runner.rotate_token",
            "secret_reference.create",
            "secret_reference.delete",
            "secret_scope.configure"
          ]
      ),
    "reviewer" =>
      MapSet.new([
        "repository.view",
        "private_workspace.read",
        "review.approve",
        "review.request_changes",
        "pull_request.refresh",
        "runner.view",
        "secret_reference.view"
      ]),
    "operator" =>
      MapSet.new([
        "repository.view",
        "private_workspace.read",
        "harness.pause",
        "harness.resume",
        "harness.tick",
        "harness.reconcile",
        "task.run_codex",
        "task.cancel_run",
        "pull_request.refresh",
        "runner.view"
      ]),
    "viewer" =>
      MapSet.new([
        "repository.view",
        "private_workspace.read",
        "runner.view",
        "secret_reference.view"
      ])
  }

  @labels %{
    "repository.view" => "view this repository",
    "repository.configure" => "configure this repository",
    "workspace.initialize" => "initialize workspace files",
    "private_workspace.read" => "read private workspace artifacts",
    "private_workspace.export" => "export private workspace artifacts",
    "workflow.update" => "update workflow settings",
    "automation.enable" => "enable automation",
    "automation.disable" => "disable automation",
    "harness.pause" => "pause automation",
    "harness.resume" => "resume automation",
    "harness.tick" => "run Harness checks",
    "harness.reconcile" => "reconcile Harness runs",
    "task.create" => "create tasks",
    "task.update" => "update tasks",
    "task.cancel" => "cancel tasks",
    "task.run_codex" => "start Coding Assistant runs",
    "task.cancel_run" => "cancel Coding Assistant runs",
    "review.approve" => "approve handoffs",
    "review.request_changes" => "request changes",
    "pull_request.open" => "open pull requests",
    "pull_request.refresh" => "refresh pull request status",
    "provider.configure" => "configure providers",
    "sandbox.configure" => "configure sandbox execution",
    "sandbox.run" => "run sandbox execution",
    "workspace_provider.experimental_run" => "run experimental sandbox workspaces",
    "runner.view" => "view runners",
    "runner.register" => "register runners",
    "runner.pair" => "pair runners",
    "runner.approve" => "approve runners",
    "runner.enable" => "enable runners",
    "runner.disable" => "disable runners",
    "runner.revoke" => "revoke runners",
    "runner.rotate_token" => "rotate runner tokens",
    "runner.use_remote" => "use remote runners",
    "secret_reference.view" => "view secret references",
    "secret_reference.create" => "create secret references",
    "secret_reference.delete" => "delete secret references",
    "secret_scope.configure" => "configure secret scopes"
  }

  @denials %{
    "pull_request.open" =>
      "You do not have permission to open pull requests for this repository.",
    "private_workspace.export" =>
      "You do not have permission to export private workspace artifacts for this repository.",
    "review.approve" => "You do not have permission to approve handoffs for this repository.",
    "review.request_changes" =>
      "You do not have permission to request changes for this repository.",
    "task.run_codex" =>
      "You do not have permission to start Coding Assistant runs for this repository.",
    "task.cancel_run" =>
      "You do not have permission to cancel Coding Assistant runs for this repository.",
    "harness.pause" => "You do not have permission to pause automation for this repository.",
    "harness.resume" => "You do not have permission to resume automation for this repository.",
    "harness.tick" => "You do not have permission to run Harness checks for this repository.",
    "harness.reconcile" =>
      "You do not have permission to reconcile Harness runs for this repository.",
    "automation.enable" => "You do not have permission to enable automation for this repository.",
    "automation.disable" =>
      "You do not have permission to disable automation for this repository.",
    "workspace_provider.experimental_run" =>
      "You do not have permission to run experimental sandbox workspaces for this repository.",
    "sandbox.configure" =>
      "You do not have permission to configure sandbox execution for this repository.",
    "sandbox.run" => "You do not have permission to run sandbox execution for this repository.",
    "runner.register" => "You do not have permission to register runners for this repository.",
    "runner.pair" => "You do not have permission to pair runners for this repository.",
    "runner.approve" => "You do not have permission to approve runners for this repository.",
    "runner.enable" => "You do not have permission to enable runners for this repository.",
    "runner.disable" => "You do not have permission to disable runners for this repository.",
    "runner.revoke" => "You do not have permission to revoke runners for this repository.",
    "runner.rotate_token" =>
      "You do not have permission to rotate runner tokens for this repository.",
    "runner.use_remote" =>
      "You do not have permission to use remote runners for this repository.",
    "secret_reference.create" =>
      "You do not have permission to create secret references for this repository.",
    "secret_reference.delete" =>
      "You do not have permission to delete secret references for this repository.",
    "secret_scope.configure" =>
      "You do not have permission to configure secret scopes for this repository."
  }

  def all, do: @permissions

  def allowed?(role, permission) when is_binary(role) and is_binary(permission) do
    role
    |> permission_set_for_role()
    |> MapSet.member?(permission)
  end

  def allowed?(_role, _permission), do: false

  def permissions_for_role(role) when is_binary(role) do
    allowed = permission_set_for_role(role)

    then(allowed, fn allowed ->
      @permissions
      |> Enum.map(&{&1, MapSet.member?(allowed, &1)})
      |> Map.new()
    end)
  end

  def permissions_for_role(_role), do: permissions_for_role("viewer")

  defp permission_set_for_role(role), do: Map.get(@role_permissions, role, MapSet.new())

  def label(permission), do: Map.get(@labels, permission, permission)

  def denial_message(permission) do
    Map.get(@denials, permission, "You do not have permission to #{label(permission)}.")
  end
end
