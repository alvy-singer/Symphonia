defmodule SymphoniaService.Access.Permission do
  @moduledoc """
  Canonical repository-scoped permission keys and V1 role matrix.
  """

  @permissions [
    "repository.view",
    "repository.configure",
    "workspace.initialize",
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
    "workspace_provider.experimental_run",
    "runner.view",
    "runner.register",
    "runner.enable",
    "runner.disable",
    "runner.use_remote"
  ]

  @role_permissions %{
    "owner" => MapSet.new(@permissions),
    "maintainer" =>
      MapSet.new(
        @permissions --
          [
            "workspace_provider.experimental_run",
            "runner.register",
            "runner.enable",
            "runner.disable"
          ]
      ),
    "reviewer" =>
      MapSet.new([
        "repository.view",
        "review.approve",
        "review.request_changes",
        "pull_request.refresh",
        "runner.view"
      ]),
    "operator" =>
      MapSet.new([
        "repository.view",
        "harness.pause",
        "harness.resume",
        "harness.tick",
        "harness.reconcile",
        "task.run_codex",
        "task.cancel_run",
        "pull_request.refresh",
        "runner.view"
      ]),
    "viewer" => MapSet.new(["repository.view", "runner.view"])
  }

  @labels %{
    "repository.view" => "view this repository",
    "repository.configure" => "configure this repository",
    "workspace.initialize" => "initialize workspace files",
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
    "workspace_provider.experimental_run" => "run experimental sandbox workspaces",
    "runner.view" => "view runners",
    "runner.register" => "register runners",
    "runner.enable" => "enable runners",
    "runner.disable" => "disable runners",
    "runner.use_remote" => "use remote runners"
  }

  @denials %{
    "pull_request.open" =>
      "You do not have permission to open pull requests for this repository.",
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
    "runner.register" => "You do not have permission to register runners for this repository.",
    "runner.enable" => "You do not have permission to enable runners for this repository.",
    "runner.disable" => "You do not have permission to disable runners for this repository.",
    "runner.use_remote" => "You do not have permission to use remote runners for this repository."
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
