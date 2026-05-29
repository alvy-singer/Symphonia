defmodule SymphoniaService.Readiness.RepositoryReadiness do
  @moduledoc """
  Canonical repository-level readiness model.

  The checks in this module are intentionally passive. They read repository,
  workspace, provider, Harness, validation, GitHub, and task state but do not
  start execution, open pull requests, create branches, or mutate task/run
  records.
  """

  alias SymphoniaService.CodingAssistant.ProviderCatalog
  alias SymphoniaService.Harness.{Automation, Daemon}
  alias SymphoniaService.Readiness.RepositoryScanner
  alias SymphoniaService.Runner.WorkspaceProviders
  alias SymphoniaService.Validation.Policy
  alias SymphoniaService.{SpecWorkspace, TaskStore, Workspace}

  @categories ~w(workspace planning automation provider validation github review)

  def get(repository, opts \\ []) do
    registry_path = Keyword.get(opts, :registry_path, SymphoniaService.default_registry_path())

    checks =
      []
      |> Kernel.++(workspace_checks(repository))
      |> Kernel.++(planning_checks(repository))
      |> Kernel.++(automation_checks(repository, registry_path))
      |> Kernel.++(provider_checks())
      |> Kernel.++(validation_checks(repository))
      |> Kernel.++(github_checks(repository))
      |> Kernel.++(review_checks(repository))

    state = state_for(checks)

    %{
      "state" => state,
      "summary" => summary_for(state, checks),
      "checks" => checks,
      "nextActions" => next_actions(checks),
      "scan" => RepositoryScanner.scan(repository)
    }
  end

  def compiler_readiness(repository) do
    readiness = get(repository)
    failed = Enum.filter(readiness["checks"], &(&1["status"] == "failed"))
    warnings = Enum.filter(readiness["checks"], &(&1["status"] == "warning"))

    %{
      "ready" => failed == [],
      "blockers" => Enum.map(failed, & &1["detail"]) |> Enum.uniq(),
      "warnings" => Enum.map(warnings, & &1["detail"]) |> Enum.uniq(),
      "labels" => %{
        "repositoryReady" => failed == [],
        "githubLinked" => check_passed?(readiness["checks"], "github_linked"),
        "automationEnabled" => check_passed?(readiness["checks"], "automation_enabled"),
        "validationConfigured" =>
          Enum.any?(readiness["checks"], fn check ->
            check["id"] == "validation_policy" and check["status"] in ["passed", "warning"]
          end),
        "harnessPaused" =>
          Enum.any?(readiness["checks"], fn check ->
            check["id"] == "harness_paused" and check["status"] == "warning"
          end)
      }
    }
  end

  defp workspace_checks(repository) do
    repo_path = repository["path"] || ""
    path_exists? = File.dir?(repo_path)
    workspace_state = if path_exists?, do: Workspace.state(repository), else: %{}

    workflow =
      if path_exists?,
        do: Workspace.workflow(repository),
        else: %{"exists" => false, "body" => ""}

    missing_directories = workspace_state["missingDirectories"] || []
    task_dir? = path_exists? and File.dir?(Path.join([repo_path, "symphonia", "tasks"]))

    [
      check(
        "repository_path",
        "Repository path",
        if(path_exists?, do: "passed", else: "failed"),
        "workspace",
        if(path_exists?,
          do: "Repository folder is available.",
          else: "Repository folder is unavailable."
        )
      ),
      check(
        "workspace_directories",
        "Workspace folders",
        if(missing_directories == [], do: "passed", else: "failed"),
        "workspace",
        if(missing_directories == [],
          do: "Symphonia workspace folders are present.",
          else: "Symphonia workspace folders are missing."
        ),
        if(missing_directories == [], do: nil, else: action("initialize_workspace"))
      ),
      check(
        "task_directory",
        "Task directory",
        if(task_dir?, do: "passed", else: "failed"),
        "workspace",
        if(task_dir?, do: "Task directory is present.", else: "Task directory is missing."),
        if(task_dir?, do: nil, else: action("initialize_workspace"))
      ),
      check(
        "workflow_exists",
        "WORKFLOW.md exists",
        if(workflow["exists"] == true, do: "passed", else: "failed"),
        "workspace",
        if(workflow["exists"] == true,
          do: "Repository workflow rules are present.",
          else: "WORKFLOW.md is missing."
        ),
        if(workflow["exists"] == true, do: nil, else: action("create_workflow"))
      ),
      check(
        "workflow_non_empty",
        "WORKFLOW.md content",
        cond do
          workflow["exists"] != true -> "not_checked"
          String.trim(workflow["body"] || "") == "" -> "failed"
          true -> "passed"
        end,
        "workspace",
        cond do
          workflow["exists"] != true -> "Create WORKFLOW.md before checking its rules."
          String.trim(workflow["body"] || "") == "" -> "WORKFLOW.md is empty."
          true -> "WORKFLOW.md has repository rules."
        end,
        if(workflow["exists"] == true and String.trim(workflow["body"] || "") == "",
          do: action("edit_workflow"),
          else: nil
        )
      ),
      workspace_isolation_check()
    ]
  end

  defp workspace_isolation_check do
    status = WorkspaceProviders.workspace_isolation_status()
    sandbox = status["experimentalSandbox"] || %{}

    detail =
      if sandbox["enabled"] == true do
        "Local workspace is ready. Experimental sandbox is enabled for manual developer runs."
      else
        "Local workspace is ready. Experimental sandbox is disabled."
      end

    check(
      "workspace_isolation",
      "Workspace isolation",
      "passed",
      "workspace",
      detail
    )
  end

  defp planning_checks(repository) do
    state = SpecWorkspace.state(repository)
    approved_milestones = approved_milestones(repository)
    invalid_links = invalid_milestone_links(repository, approved_milestones)

    [
      check(
        "spec_workspace",
        "Spec workspace",
        if(state["initialized"] == true, do: "passed", else: "failed"),
        "planning",
        if(state["initialized"] == true,
          do: "Planning workspace is initialized.",
          else: "Planning workspace is missing."
        ),
        if(state["initialized"] == true, do: nil, else: action("initialize_spec_workspace"))
      ),
      check(
        "codebase_map",
        "Codebase map",
        if("codebase_map" in (state["missingDefaultArtifacts"] || []),
          do: "failed",
          else: "passed"
        ),
        "planning",
        if("codebase_map" in (state["missingDefaultArtifacts"] || []),
          do: "Codebase map is missing.",
          else: "Codebase map is present."
        ),
        if("codebase_map" in (state["missingDefaultArtifacts"] || []),
          do: action("initialize_spec_workspace"),
          else: nil
        )
      ),
      check(
        "approved_milestone",
        "Approved milestone",
        if(approved_milestones == [], do: "warning", else: "passed"),
        "planning",
        if(approved_milestones == [],
          do: "No approved milestone is available for task compilation.",
          else: "At least one milestone is approved."
        ),
        if(approved_milestones == [], do: action("open_milestone_loop"), else: nil)
      ),
      check(
        "milestone_links",
        "Milestone source links",
        cond do
          approved_milestones == [] -> "not_checked"
          invalid_links == [] -> "passed"
          true -> "warning"
        end,
        "planning",
        cond do
          approved_milestones == [] -> "Approve a milestone before checking source links."
          invalid_links == [] -> "Approved milestone links resolve."
          true -> "Some approved milestone links need review."
        end,
        if(invalid_links == [], do: nil, else: action("open_workspace"))
      )
    ]
  end

  defp automation_checks(repository, registry_path) do
    automation = Automation.status(repository)
    harness = Daemon.peek_status(registry_path)

    [
      check(
        "automation_configured",
        "Automation provider",
        if(automation["provider"] == "codex_app_server", do: "passed", else: "failed"),
        "automation",
        if(automation["provider"] == "codex_app_server",
          do: "Automation is configured for Codex App Server.",
          else: "Harness V1 can only run Codex App Server."
        ),
        if(automation["provider"] == "codex_app_server", do: nil, else: action("setup_codex"))
      ),
      check(
        "automation_enabled",
        "Automation",
        if(automation["enabled"] == true, do: "passed", else: "warning"),
        "automation",
        if(automation["enabled"] == true,
          do: "Repository automation is enabled.",
          else: "Repository automation is disabled."
        ),
        if(automation["enabled"] == true, do: nil, else: action("enable_automation"))
      ),
      check(
        "harness_online",
        "Harness online",
        if(harness["online"] == true and harness["running"] == true,
          do: "passed",
          else: "failed"
        ),
        "automation",
        if(harness["online"] == true and harness["running"] == true,
          do: "Harness is online.",
          else: "Harness is offline."
        ),
        if(harness["online"] == true and harness["running"] == true,
          do: nil,
          else: action("open_automation_settings")
        )
      ),
      check(
        "harness_paused",
        "Harness paused",
        cond do
          harness["online"] != true -> "not_checked"
          harness["paused"] == true -> "warning"
          true -> "passed"
        end,
        "automation",
        cond do
          harness["online"] != true -> "Start the Harness before checking pause state."
          harness["paused"] == true -> "Harness is paused."
          true -> "Harness is running."
        end,
        if(harness["online"] == true and harness["paused"] == true,
          do: action("resume_harness"),
          else: nil
        )
      ),
      check(
        "harness_limits",
        "Harness limits",
        if(is_map(harness["limits"]), do: "passed", else: "not_checked"),
        "automation",
        if(is_map(harness["limits"]),
          do: "Harness claim limits are visible.",
          else: "Harness limits are not available."
        )
      )
    ]
  end

  defp provider_checks do
    status = ProviderCatalog.readiness_status(mode: :check_only)
    providers = Map.new(status["providers"] || [], &{&1["id"], &1})
    codex = providers["codex_app_server"] || %{}
    codex_contract? = codex["runnableByHarness"] == true and codex["missingCapabilities"] == []

    non_codex_disabled? =
      providers
      |> Enum.reject(fn {id, _provider} -> id == "codex_app_server" end)
      |> Enum.all?(fn {_id, provider} -> provider["runnableByHarness"] == false end)

    [
      check(
        "codex_configured",
        "Codex configured",
        if(codex["configured"] == true, do: "passed", else: "failed"),
        "provider",
        if(codex["configured"] == true,
          do: "Codex App Server is configured.",
          else: "Codex App Server needs setup."
        ),
        if(codex["configured"] == true, do: nil, else: action("setup_codex"))
      ),
      check(
        "codex_schema",
        "Codex schema",
        if(codex["schemaAvailable"] == true, do: "passed", else: "failed"),
        "provider",
        if(codex["schemaAvailable"] == true,
          do: "Codex App Server schema is available.",
          else: "Codex App Server schema is missing."
        ),
        if(codex["schemaAvailable"] == true, do: nil, else: action("setup_codex"))
      ),
      check(
        "codex_binary",
        "Codex binary",
        if(codex["binaryAvailable"] == true, do: "passed", else: "failed"),
        "provider",
        if(codex["binaryAvailable"] == true,
          do: "Codex binary is available.",
          else: safe_detail(codex["reason"] || "Codex binary is unavailable.")
        ),
        if(codex["binaryAvailable"] == true, do: nil, else: action("setup_codex"))
      ),
      check(
        "codex_daemon_reachable",
        "Codex daemon",
        if(is_boolean(codex["daemonReachable"]), do: "passed", else: "not_checked"),
        "provider",
        "Codex daemon reachability is not checked unless it can be observed without starting Codex."
      ),
      check(
        "codex_provider_contract",
        "Codex provider contract",
        if(codex_contract?, do: "passed", else: "failed"),
        "provider",
        if(codex_contract?,
          do: "Codex App Server satisfies the Harness provider contract.",
          else: "Codex App Server is missing required Harness provider capabilities."
        ),
        if(codex_contract?, do: nil, else: action("setup_codex"))
      ),
      check(
        "harness_provider_contract",
        "Harness provider contract",
        if(non_codex_disabled?, do: "passed", else: "failed"),
        "provider",
        if(non_codex_disabled?,
          do: "Only Codex App Server is runnable by Harness V2.",
          else: "Non-Codex providers must remain disabled for Harness V2."
        )
      )
    ]
  end

  defp validation_checks(repository) do
    policy = Policy.load(repository["path"] || "")

    [
      check(
        "validation_policy",
        "Validation",
        case policy["source"] do
          "workflow" -> "passed"
          "inferred" -> "warning"
          _ -> "warning"
        end,
        "validation",
        case policy["source"] do
          "workflow" -> "Validation is configured in WORKFLOW.md."
          "inferred" -> "Validation is inferred from project files."
          _ -> "No validation command is configured."
        end,
        if(policy["source"] == "not_configured", do: action("configure_validation"), else: nil)
      )
    ]
  end

  defp github_checks(repository) do
    linked? = github_linked?(repository)

    access? =
      linked? and
        available?(
          get_in(repository, ["github", "installation_id"]) ||
            get_in(repository, ["github", "auth_mode"])
        )

    [
      check(
        "github_linked",
        "GitHub linked",
        if(linked?, do: "passed", else: "failed"),
        "github",
        if(linked?,
          do: "Repository is linked to GitHub.",
          else: "Repository is not linked to GitHub."
        ),
        if(linked?, do: nil, else: action("connect_github"))
      ),
      check(
        "github_access",
        "GitHub issue and PR access",
        cond do
          !linked? -> "not_checked"
          access? -> "passed"
          true -> "warning"
        end,
        "github",
        cond do
          !linked? -> "Link GitHub before checking issue and PR access."
          access? -> "GitHub access metadata is available."
          true -> "GitHub access should be confirmed before PR creation."
        end,
        if(linked? and !access?, do: action("connect_github"), else: nil)
      ),
      check(
        "pr_creation",
        "PR creation",
        cond do
          !linked? -> "failed"
          access? -> "passed"
          true -> "warning"
        end,
        "github",
        cond do
          !linked? -> "GitHub must be linked before pull requests can be created."
          access? -> "Pull request creation is likely available."
          true -> "Pull request creation needs GitHub access confirmation."
        end,
        if(linked? and access?, do: nil, else: action("connect_github"))
      )
    ]
  end

  defp review_checks(repository) do
    tasks = safe_tasks(repository)
    runnable = Enum.filter(tasks, &currently_runnable_candidate?(repository, &1))

    blocked =
      Enum.filter(
        runnable,
        &(present?(&1["handoff"]) or active_run?(&1) or review_branch_recorded?(&1))
      )

    [
      check(
        "review_branch_conflicts",
        "Review branch conflicts",
        cond do
          runnable == [] -> "not_checked"
          blocked == [] -> "passed"
          true -> "warning"
        end,
        "review",
        cond do
          runnable == [] -> "No currently runnable tasks are available for review branch checks."
          blocked == [] -> "No local review handoff or branch conflicts were found."
          true -> "Some currently runnable tasks already have run or review state."
        end,
        if(blocked == [], do: nil, else: action("open_tasks"))
      )
    ]
  end

  defp approved_milestones(repository) do
    repository
    |> SpecWorkspace.list_artifacts("milestone")
    |> Enum.filter(fn artifact ->
      artifact["status"] == "approved" or get_in(artifact, ["metadata", "status"]) == "approved"
    end)
  rescue
    _error -> []
  end

  defp invalid_milestone_links(repository, milestones) do
    milestones
    |> Enum.flat_map(fn milestone ->
      metadata = milestone["metadata"] || %{}

      [
        {"discussion", metadata["discussion"]},
        {"requirements", metadata["requirements"]},
        {"plan", metadata["plan"]}
      ]
      |> Enum.reject(fn {_type, id} -> blank?(id) end)
      |> Enum.reject(fn {type, id} -> artifact_exists?(repository, type, id) end)
    end)
  end

  defp artifact_exists?(repository, type, id) do
    SpecWorkspace.read_artifact(repository, type, id)
    true
  rescue
    _error -> false
  end

  defp currently_runnable_candidate?(repository, task) do
    task["status"] == "todo" and dependencies_complete?(repository, task)
  end

  defp dependencies_complete?(repository, task) do
    task
    |> Map.get("dependsOn", [])
    |> List.wrap()
    |> Enum.reject(&blank?/1)
    |> Enum.all?(fn key ->
      case TaskStore.get_task(repository, key) do
        %{"status" => "completed"} -> true
        _ -> false
      end
    end)
  end

  defp safe_tasks(repository) do
    TaskStore.list_tasks(repository)
  rescue
    _error -> []
  end

  defp active_run?(%{"run" => %{"state" => state}}), do: state in ["queued", "running"]
  defp active_run?(_task), do: false

  defp review_branch_recorded?(task) do
    present?(get_in(task, ["run", "reviewBranch"])) or
      present?(get_in(task, ["handoff", "headBranch"])) or
      present?(get_in(task, ["github", "pull_request", "head_branch"]))
  end

  defp check_passed?(checks, id) do
    Enum.any?(checks, &(&1["id"] == id and &1["status"] == "passed"))
  end

  defp state_for(checks) do
    failed = Enum.filter(checks, &(&1["status"] == "failed"))
    warnings = Enum.filter(checks, &(&1["status"] == "warning"))

    cond do
      failed == [] and warnings == [] -> "ready"
      failed == [] -> "warning"
      Enum.all?(failed, &is_map(&1["action"])) -> "needs_setup"
      Enum.any?(failed, &is_nil(&1["action"])) -> "blocked"
      true -> "needs_setup"
    end
  end

  defp summary_for("ready", checks), do: "#{passed_count(checks)} checks ready."

  defp summary_for("warning", checks),
    do: "#{passed_count(checks)} ready with #{warning_count(checks)} warnings."

  defp summary_for("needs_setup", checks),
    do: "#{failed_count(checks)} setup checks need attention."

  defp summary_for("blocked", checks), do: "#{failed_count(checks)} checks block safe automation."

  defp next_actions(checks) do
    checks
    |> Enum.filter(&(&1["status"] in ["failed", "warning"]))
    |> Enum.reject(&is_nil(&1["action"]))
    |> Enum.sort_by(fn check ->
      {status_priority(check["status"]), action_priority(check["action"]["id"])}
    end)
    |> Enum.map(& &1["action"])
    |> Enum.uniq_by(& &1["id"])
  end

  defp action("create_workflow") do
    %{
      "id" => "create_workflow",
      "label" => "Create WORKFLOW.md",
      "href" => "/readiness/workflow/from-template",
      "kind" => "create_file"
    }
  end

  defp action("edit_workflow") do
    %{
      "id" => "edit_workflow",
      "label" => "Edit WORKFLOW.md",
      "href" => "/workflow",
      "kind" => "navigate"
    }
  end

  defp action("initialize_workspace") do
    %{
      "id" => "initialize_workspace",
      "label" => "Initialize workspace",
      "href" => "/readiness/workspace/initialize",
      "kind" => "create_file"
    }
  end

  defp action("initialize_spec_workspace") do
    %{
      "id" => "initialize_spec_workspace",
      "label" => "Initialize planning workspace",
      "href" => "/spec-workspace/initialize",
      "kind" => "create_file"
    }
  end

  defp action("connect_github") do
    %{
      "id" => "connect_github",
      "label" => "Connect GitHub",
      "href" => "/settings",
      "kind" => "connect"
    }
  end

  defp action("setup_codex") do
    %{
      "id" => "setup_codex",
      "label" => "Set up Codex",
      "href" => "/settings",
      "kind" => "navigate"
    }
  end

  defp action("enable_automation") do
    %{
      "id" => "enable_automation",
      "label" => "Enable automation",
      "href" => "/automation/enable",
      "kind" => "enable"
    }
  end

  defp action("resume_harness") do
    %{
      "id" => "resume_harness",
      "label" => "Resume Harness",
      "href" => "/api/harness/resume",
      "kind" => "enable"
    }
  end

  defp action("configure_validation") do
    %{
      "id" => "configure_validation",
      "label" => "Configure validation",
      "href" => "/workflow",
      "kind" => "navigate"
    }
  end

  defp action("open_milestone_loop") do
    %{
      "id" => "open_milestone_loop",
      "label" => "Open milestone loop",
      "href" => "/workspace/milestone-loop",
      "kind" => "navigate"
    }
  end

  defp action("open_workspace") do
    %{
      "id" => "open_workspace",
      "label" => "Open workspace",
      "href" => "/workspace",
      "kind" => "navigate"
    }
  end

  defp action("open_tasks") do
    %{"id" => "open_tasks", "label" => "Open tasks", "href" => "/tasks", "kind" => "navigate"}
  end

  defp action("open_automation_settings") do
    %{
      "id" => "open_automation_settings",
      "label" => "Open automation settings",
      "href" => "/settings",
      "kind" => "navigate"
    }
  end

  defp action_priority("create_workflow"), do: 10
  defp action_priority("initialize_workspace"), do: 20
  defp action_priority("initialize_spec_workspace"), do: 30
  defp action_priority("connect_github"), do: 40
  defp action_priority("setup_codex"), do: 50
  defp action_priority("enable_automation"), do: 60
  defp action_priority("resume_harness"), do: 70
  defp action_priority("configure_validation"), do: 80
  defp action_priority(_id), do: 100

  defp status_priority("failed"), do: 0
  defp status_priority("warning"), do: 1
  defp status_priority(_status), do: 2

  defp check(id, label, status, category, detail, action \\ nil) do
    unless category in @categories, do: raise(ArgumentError, "Unknown readiness category.")

    %{
      "id" => id,
      "label" => label,
      "status" => status,
      "category" => category,
      "detail" => safe_detail(detail),
      "action" => action
    }
    |> reject_nil()
  end

  defp github_linked?(repository) do
    case repository["github"] do
      %{"owner" => owner, "name" => name} -> present?(owner) and present?(name)
      _ -> false
    end
  end

  defp passed_count(checks), do: Enum.count(checks, &(&1["status"] == "passed"))
  defp warning_count(checks), do: Enum.count(checks, &(&1["status"] == "warning"))
  defp failed_count(checks), do: Enum.count(checks, &(&1["status"] == "failed"))

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value) when is_map(value), do: map_size(value) > 0
  defp present?(_value), do: false
  defp available?(value) when is_binary(value), do: String.trim(value) != ""
  defp available?(nil), do: false
  defp available?(_value), do: true
  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")

  defp safe_detail(detail) when is_binary(detail) do
    detail
    |> String.replace(~r/[A-Z_]{3,}[A-Z0-9_]*=/, "setting=")
    |> String.replace(~r/(\/[A-Za-z0-9._@%+~:-]+)+/, "[local path]")
  end

  defp safe_detail(_detail), do: "Readiness detail is unavailable."
  defp reject_nil(map), do: map |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new()
end
