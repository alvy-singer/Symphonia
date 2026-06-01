defmodule SymphoniaService.Privacy.Inventory do
  @moduledoc """
  Canonical V1 privacy inventory for Symphonia data surfaces.

  This module is intentionally static and small. It gives tests and future
  editor/provider work one source of truth for what may cross each boundary.
  V1 private storage is service-readable local state, not zero-knowledge or
  end-to-end encrypted storage.
  """

  @destinations ~w(local_private_storage managed_repository browser_ui providers github audit_logs)

  @destination_rules %{
    "local_private_storage" =>
      "Service-readable state beside the registry, including private workspace blobs, run records, audit files, and export metadata.",
    "managed_repository" =>
      "Files inside the user repository worktree, such as WORKFLOW.md and task Markdown.",
    "browser_ui" => "Rendered through repository access checks and public payload shapers.",
    "providers" =>
      "Provider-scoped context only: task brief, WORKFLOW.md, explicitly linked artifacts, review notes, and handoff summaries.",
    "github" =>
      "Repository code, WORKFLOW.md, task Markdown, PR bodies, and explicit PR-based private workspace export snapshots.",
    "audit_logs" =>
      "Allowlisted metadata only; no raw bodies, logs, transcripts, provider output, paths, env values, thread ids, or turn ids."
  }

  @surfaces [
    %{
      "id" => "private_workspace_artifacts",
      "label" => "Private workspace artifacts",
      "owner" => "SymphoniaService.PrivateWorkspace",
      "storage" => "<registry_dir>/workspace/<repo_key>/index.json and blobs/artifacts",
      "sensitivity" => "private_content",
      "allowed_destinations" => ["local_private_storage"],
      "conditional_destinations" => ["browser_ui", "providers", "github"],
      "blocked_destinations" => ["managed_repository", "audit_logs"],
      "rules" => %{
        "browser_ui" => "repository.view can read artifact bodies.",
        "providers" => "Only linked task-relevant artifacts selected by ContextPack.",
        "github" => "Only selected revisions through explicit export PRs.",
        "audit_logs" =>
          "Only artifact kind/id, revision id, export status, and repo-relative legacy/export metadata."
      },
      "tests" =>
        ~w(private_workspace_test private_workspace_export_test context_pack_test access_http_test)
    },
    %{
      "id" => "private_workspace_evidence",
      "label" => "Private workspace evidence",
      "owner" => "SymphoniaService.PrivateWorkspace",
      "storage" => "<registry_dir>/workspace/<repo_key>/index.json and blobs/evidence",
      "sensitivity" => "private_evidence",
      "allowed_destinations" => ["local_private_storage"],
      "conditional_destinations" => ["browser_ui"],
      "blocked_destinations" => ["managed_repository", "providers", "github", "audit_logs"],
      "rules" => %{
        "browser_ui" => "Safe excerpts and refs only behind repository.view.",
        "audit_logs" => "Only evidence kind/id metadata.",
        "github" => "No automatic evidence publication in V1."
      },
      "tests" => ~w(private_workspace_test codex_app_server_provider_test)
    },
    %{
      "id" => "raw_run_records",
      "label" => "Raw run records and provider output",
      "owner" => "SymphoniaService.CodingAssistant.RunStore",
      "storage" => "$SYMPHONIA_RUNS_ROOT or ~/.symphonia/runs",
      "sensitivity" => "private_runtime_material",
      "allowed_destinations" => ["local_private_storage"],
      "conditional_destinations" => [],
      "blocked_destinations" => [
        "managed_repository",
        "browser_ui",
        "providers",
        "github",
        "audit_logs"
      ],
      "rules" => %{
        "browser_ui" => "Only public run payloads derived from these records may render.",
        "providers" => "Never send raw prior logs or provider output.",
        "audit_logs" => "Only run ids, task keys, provider ids, and safe branch/summary refs."
      },
      "tests" => ~w(run_store_test context_pack_test)
    },
    %{
      "id" => "public_run_events",
      "label" => "Public run events",
      "owner" => "SymphoniaService.CodingAssistant.RunStore",
      "storage" => "Derived from private run records",
      "sensitivity" => "public_safe_status",
      "allowed_destinations" => ["browser_ui"],
      "conditional_destinations" => ["local_private_storage"],
      "blocked_destinations" => ["managed_repository", "providers", "github", "audit_logs"],
      "rules" => %{
        "browser_ui" => "Curated labels/messages and safe refs only.",
        "github" => "Not published directly."
      },
      "tests" => ~w(run_store_test coding_assistant_test)
    },
    %{
      "id" => "task_markdown",
      "label" => "Task Markdown and frontmatter",
      "owner" => "SymphoniaService.TaskStore",
      "storage" => "symphonia/tasks/*.md in the managed repository",
      "sensitivity" => "repo_visible_workflow",
      "allowed_destinations" => ["managed_repository", "browser_ui", "github"],
      "conditional_destinations" => ["providers"],
      "blocked_destinations" => ["local_private_storage", "audit_logs"],
      "rules" => %{
        "providers" => "Task brief and selected review sections only.",
        "audit_logs" => "Only taskKey metadata.",
        "github" => "Repo-backed task Markdown may be committed by existing task workflows."
      },
      "tests" => ~w(task_store_test context_pack_test github_pull_requests_test)
    },
    %{
      "id" => "handoffs",
      "label" => "Review handoffs",
      "owner" => "SymphoniaService.CodingAssistant.HandoffBuilder",
      "storage" => "Task frontmatter plus private run records",
      "sensitivity" => "review_safe_summary",
      "allowed_destinations" => ["local_private_storage", "managed_repository", "browser_ui"],
      "conditional_destinations" => ["providers", "github"],
      "blocked_destinations" => ["audit_logs"],
      "rules" => %{
        "providers" => "Previous handoff summary, changed files, and safe summary refs only.",
        "github" => "Only through task Markdown or PR body summaries.",
        "audit_logs" => "Only ids and safe refs."
      },
      "tests" => ~w(context_pack_test task_store_test)
    },
    %{
      "id" => "run_summaries",
      "label" => "Curated run summaries",
      "owner" => "SymphoniaService.CodingAssistant.CuratedSummary",
      "storage" => "Private workspace run_summary artifacts",
      "sensitivity" => "private_review_summary",
      "allowed_destinations" => ["local_private_storage", "browser_ui"],
      "conditional_destinations" => ["github", "providers"],
      "blocked_destinations" => ["managed_repository", "audit_logs"],
      "rules" => %{
        "github" => "Only selected private artifact revisions through explicit export PRs.",
        "providers" => "References or summaries only when task-relevant.",
        "audit_logs" => "Only run summary artifact ids."
      },
      "tests" => ~w(codex_app_server_provider_test private_workspace_export_test)
    },
    %{
      "id" => "pr_bodies",
      "label" => "Pull request bodies",
      "owner" => "SymphoniaService.GitHub.PullRequests",
      "storage" => "GitHub pull request text",
      "sensitivity" => "public_review_text",
      "allowed_destinations" => ["github", "browser_ui"],
      "conditional_destinations" => ["local_private_storage"],
      "blocked_destinations" => ["managed_repository", "providers", "audit_logs"],
      "rules" => %{
        "github" =>
          "Public-safe summaries, changed files, validation summaries, and explicit export details only.",
        "audit_logs" => "Only PR URL/number/state metadata."
      },
      "tests" => ~w(github_pull_requests_test private_workspace_export_test)
    },
    %{
      "id" => "audit_events",
      "label" => "Audit events",
      "owner" => "SymphoniaService.Access.AuditLog",
      "storage" => "<registry_dir>/audit/events.jsonl",
      "sensitivity" => "public_safe_metadata",
      "allowed_destinations" => ["local_private_storage", "browser_ui", "audit_logs"],
      "conditional_destinations" => [],
      "blocked_destinations" => ["managed_repository", "providers", "github"],
      "rules" => %{
        "browser_ui" => "Allowlisted metadata and sanitized summaries only.",
        "audit_logs" => "Append-only public-safe metadata, never raw bodies or runtime material."
      },
      "tests" => ~w(audit_log_test access_http_test runners_http_test)
    },
    %{
      "id" => "provider_context_packs",
      "label" => "Provider context packs",
      "owner" => "SymphoniaService.CodingAssistant.ContextPack",
      "storage" => "Constructed in memory for provider calls",
      "sensitivity" => "provider_scoped_private_context",
      "allowed_destinations" => ["providers"],
      "conditional_destinations" => [],
      "blocked_destinations" => [
        "local_private_storage",
        "managed_repository",
        "browser_ui",
        "github",
        "audit_logs"
      ],
      "rules" => %{
        "providers" =>
          "Only task brief, WORKFLOW.md, linked artifacts, review notes, and handoff summaries.",
        "browser_ui" => "Do not render full provider prompts or context packs.",
        "audit_logs" => "Never audit prompt bodies or provider context bodies."
      },
      "tests" => ~w(context_pack_test provider_contract_test)
    },
    %{
      "id" => "clarise_chat_derived_artifacts",
      "label" => "Clarise chat-derived artifacts",
      "owner" => "SymphoniaService.Clarise.ArtifactExtractor",
      "storage" => "Private workspace artifacts created from chat outputs",
      "sensitivity" => "private_content",
      "allowed_destinations" => ["local_private_storage", "browser_ui"],
      "conditional_destinations" => ["providers", "github"],
      "blocked_destinations" => ["managed_repository", "audit_logs"],
      "rules" => %{
        "providers" => "Only when later linked into task context.",
        "github" => "Only through explicit private workspace export.",
        "audit_logs" => "Only artifact ids and safe action metadata."
      },
      "tests" => ~w(clarise_test private_workspace_test)
    },
    %{
      "id" => "workflow_files",
      "label" => "WORKFLOW.md",
      "owner" => "SymphoniaService.Workspace",
      "storage" => "WORKFLOW.md in the managed repository",
      "sensitivity" => "repo_visible_execution_contract",
      "allowed_destinations" => ["managed_repository", "browser_ui", "providers", "github"],
      "conditional_destinations" => ["audit_logs"],
      "blocked_destinations" => ["local_private_storage"],
      "rules" => %{
        "providers" => "Always included as the execution contract.",
        "audit_logs" => "Workflow action metadata only, not full body."
      },
      "tests" => ~w(workspace_test context_pack_test harness_eligibility_test)
    },
    %{
      "id" => "github_export_snapshots",
      "label" => "GitHub export snapshots",
      "owner" => "SymphoniaService.PrivateWorkspace.GitHubExporter",
      "storage" => "GitHub review branches and private export metadata",
      "sensitivity" => "public_snapshot",
      "allowed_destinations" => ["github", "browser_ui", "local_private_storage"],
      "conditional_destinations" => [],
      "blocked_destinations" => ["managed_repository", "providers", "audit_logs"],
      "rules" => %{
        "github" => "Sanitized selected revision only, through a review branch and PR.",
        "local_private_storage" => "Export metadata only, not a second source of truth.",
        "audit_logs" => "Only export id/status/revision/target path/PR metadata."
      },
      "tests" => ~w(private_workspace_export_test access_http_test)
    },
    %{
      "id" => "review_notes",
      "label" => "Review notes",
      "owner" => "SymphoniaService.Clarise.ReviewNotesBuilder",
      "storage" => "Task Markdown review sections",
      "sensitivity" => "repo_visible_review_text",
      "allowed_destinations" => ["managed_repository", "browser_ui", "github"],
      "conditional_destinations" => ["providers"],
      "blocked_destinations" => ["local_private_storage", "audit_logs"],
      "rules" => %{
        "providers" => "Requested changes only; original raw feedback is stripped.",
        "audit_logs" => "Only review action metadata."
      },
      "tests" => ~w(context_pack_test task_store_test)
    }
  ]

  @risky_fixtures [
    %{"id" => "local_path", "value" => "/Users/example/private/repo"},
    %{"id" => "env_value", "value" => "SECRET_TOKEN=value"},
    %{"id" => "tokenized_url", "value" => "https://ghp_secret@example.invalid/repo.git"},
    %{"id" => "token_like", "value" => "ghp_abcdef1234567890"},
    %{"id" => "provider_output", "value" => "provider output: raw assistant chunk"},
    %{"id" => "raw_log", "value" => "raw logs: private command output"},
    %{"id" => "transcript", "value" => "transcript: private turn text"},
    %{"id" => "thread_id", "value" => "thread_id: thread-private"},
    %{"id" => "turn_id", "value" => "turn_id: turn-private"},
    %{"id" => "evidence_blob", "value" => "evidence_blob: private payload"}
  ]

  def destinations, do: @destinations
  def destination_rules, do: @destination_rules
  def surfaces, do: @surfaces
  def risky_fixtures, do: @risky_fixtures
  def risky_values, do: Enum.map(@risky_fixtures, & &1["value"])

  def surface(id) when is_binary(id) do
    Enum.find(@surfaces, &(&1["id"] == id))
  end

  def destination_status(surface_id, destination) do
    surface = surface!(surface_id)
    destination = to_string(destination)

    cond do
      destination in surface["allowed_destinations"] -> "allowed"
      destination in surface["conditional_destinations"] -> "conditional"
      destination in surface["blocked_destinations"] -> "blocked"
      true -> "unclassified"
    end
  end

  def allowed?(surface_id, destination) do
    destination_status(surface_id, destination) in ["allowed", "conditional"]
  end

  def blocked?(surface_id, destination) do
    destination_status(surface_id, destination) == "blocked"
  end

  def to_markdown do
    """
    # Privacy Threat Model + Data Inventory V1

    V1 private storage is service-readable local state beside the registry. It is not zero-knowledge and it is not end-to-end encrypted. The current boundary is repo-private, provider-scoped, browser-access-controlled, audit-sanitized, and GitHub-export-explicit.

    ## Destinations

    #{destination_markdown()}

    ## Data Surfaces

    #{surfaces_markdown()}

    ## Leak Fixtures

    #{fixtures_markdown()}
    """
    |> String.trim()
    |> Kernel.<>("\n")
  end

  defp surface!(id) do
    surface(id) || raise ArgumentError, "Unknown privacy surface: #{id}"
  end

  defp destination_markdown do
    Enum.map_join(@destinations, "\n", fn destination ->
      "- `#{destination}`: #{@destination_rules[destination]}"
    end)
  end

  defp surfaces_markdown do
    header =
      "| Surface | Sensitivity | Local private | Managed repo | Browser UI | Providers | GitHub | Audit logs |\n" <>
        "| --- | --- | --- | --- | --- | --- | --- | --- |"

    rows =
      Enum.map_join(@surfaces, "\n", fn surface ->
        [
          "`#{surface["id"]}`",
          surface["sensitivity"],
          destination_status(surface["id"], "local_private_storage"),
          destination_status(surface["id"], "managed_repository"),
          destination_status(surface["id"], "browser_ui"),
          destination_status(surface["id"], "providers"),
          destination_status(surface["id"], "github"),
          destination_status(surface["id"], "audit_logs")
        ]
        |> Enum.join(" | ")
        |> then(&"| #{&1} |")
      end)

    header <> "\n" <> rows
  end

  defp fixtures_markdown do
    Enum.map_join(@risky_fixtures, "\n", fn fixture ->
      "- `#{fixture["id"]}`"
    end)
  end
end
