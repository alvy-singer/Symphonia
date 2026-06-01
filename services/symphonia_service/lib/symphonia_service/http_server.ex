defmodule SymphoniaService.HTTPServer do
  @moduledoc """
  Tiny dependency-free HTTP server for the local Symphonia service API.
  """

  use GenServer

  alias SymphoniaService.{
    CodingAssistant,
    MarkdownPages,
    PrivateWorkspace,
    RepositoryRegistry,
    SpecWorkspace,
    TaskStore,
    Workspace
  }

  alias SymphoniaService.Access.{Actor, AuditLog, Policy}
  alias SymphoniaService.Clarise.{ArtifactExtractor, MilestoneLoop, PlanToTaskCompiler}
  alias SymphoniaService.CodingAssistant.ProviderCatalog
  alias SymphoniaService.GitHub.{Auth, PullRequests, Repositories, RepositoryLink, Sync}
  alias SymphoniaService.Harness.{Automation, Daemon, Eligibility}
  alias SymphoniaService.Readiness.{RepositoryReadiness, RepositoryScanner, SetupActions}

  alias SymphoniaService.Runners.{
    AssignmentStore,
    Assignments,
    Capabilities,
    Pairing,
    Registry,
    RepositoryPolicy,
    SelectionPolicy
  }

  alias SymphoniaService.Sandbox.OpenSandboxSmoke
  alias SymphoniaService.Sandbox.Policy, as: SandboxPolicy
  alias SymphoniaService.Secrets.ReferenceStore, as: SecretReferences

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name))
  end

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, 4057)
    registry_path = Keyword.get(opts, :registry_path, SymphoniaService.default_registry_path())

    {:ok, socket} =
      :gen_tcp.listen(port, [:binary, packet: :raw, active: false, reuseaddr: true])

    send(self(), :accept)
    {:ok, %{socket: socket, registry_path: registry_path, port: port}}
  end

  @impl true
  def handle_info(:accept, state) do
    {:ok, client} = :gen_tcp.accept(state.socket)
    Task.start(fn -> serve(client, state.registry_path) end)
    send(self(), :accept)
    {:noreply, state}
  end

  defp serve(client, registry_path) do
    with {:ok, raw} <- :gen_tcp.recv(client, 0, 5_000),
         {:ok, request} <- parse_request(raw) do
      actor = Actor.from_headers(request.headers)
      {status, payload} = route(request, registry_path, actor)
      send_json(client, status, payload)
    else
      _ -> send_json(client, 400, %{"error" => "Bad request"})
    end

    :gen_tcp.close(client)
  end

  defp parse_request(raw) do
    [head, body] = String.split(raw, "\r\n\r\n", parts: 2)
    [request_line | header_lines] = String.split(head, "\r\n")
    [method, path, _version] = String.split(request_line, " ", parts: 3)

    headers =
      header_lines
      |> Enum.map(fn line -> String.split(line, ":", parts: 2) end)
      |> Enum.filter(&(length(&1) == 2))
      |> Map.new(fn [key, value] -> {String.downcase(key), String.trim(value)} end)

    {:ok, %{method: method, path: path, headers: headers, body: body || ""}}
  rescue
    _ -> {:error, :invalid}
  end

  defp route(%{method: "OPTIONS"}, _registry_path, _actor), do: {204, %{}}

  defp route(%{method: "GET", path: "/healthz"}, _registry_path, _actor) do
    {200, %{"ok" => true}}
  end

  defp route(%{method: "GET", path: "/api/session/actor"}, _registry_path, actor) do
    {200, %{"actor" => actor}}
  end

  defp route(%{method: "GET", path: "/api/repositories"}, registry_path, _actor) do
    repositories =
      registry_path
      |> RepositoryRegistry.list()
      |> Enum.map(&public_repository/1)

    {200, %{"repositories" => repositories}}
  end

  defp route(%{method: "GET", path: "/api/github/connection"}, _registry_path, _actor) do
    {200, %{"connection" => Auth.connection()}}
  end

  defp route(%{method: "GET", path: "/api/coding-assistants/providers"}, _registry_path, _actor) do
    {200, ProviderCatalog.readiness_status(mode: :check_only)}
  end

  defp route(%{method: "GET", path: "/api/github/repositories"}, _registry_path, _actor) do
    {200, RepositoryLink.accessible_repositories()}
  rescue
    error -> {400, %{"error" => Exception.message(error)}}
  end

  defp route(%{method: "POST", path: "/api/repositories", body: body}, registry_path, _actor) do
    repository = registry_path |> RepositoryRegistry.add(decode_json(body)) |> public_repository()
    {201, %{"repository" => repository}}
  rescue
    error -> {400, %{"error" => Exception.message(error)}}
  end

  defp route(%{method: "GET", path: path, headers: headers}, registry_path, actor) do
    case path_parts(path) do
      ["api", "runners"] ->
        guarded_read(registry_path, actor, global_repository(), "runner.view", fn ->
          audit_runner_transitions(registry_path, actor)
          {200, %{"runners" => Registry.list(registry_path)}}
        end)

      ["api", "runners", runner_id, "assignments", "current"] ->
        case Assignments.current(registry_path, runner_id, runner_token(headers, %{})) do
          {:ok, assignment} -> {200, Assignments.runner_response(assignment)}
          {:error, reason} -> runner_assignment_error(reason)
        end

      ["api", "repositories", repo, "access"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded_read(registry_path, actor, repository, "repository.view", fn ->
          {200,
           %{
             "role" => actor["role"],
             "permissions" => Policy.permissions_for(actor)
           }}
        end)

      ["api", "repositories", repo, "audit"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded_read(registry_path, actor, repository, "repository.view", fn ->
          {200,
           %{
             "events" =>
               AuditLog.list(registry_path, repository,
                 limit: Map.get(query_params(path), "limit")
               )
           }}
        end)

      ["api", "repositories", repo, "tasks", task_key, "audit"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded_read(registry_path, actor, repository, "repository.view", fn ->
          {200,
           %{
             "events" =>
               AuditLog.list_for_task(registry_path, repository, task_key,
                 limit: Map.get(query_params(path), "limit")
               )
           }}
        end)

      ["api", "repositories", repo, "workspace"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        {200, %{"repo" => repository["key"], "workspace" => Workspace.state(repository)}}

      ["api", "repositories", repo, "readiness"] ->
        repository =
          private_repository(RepositoryRegistry.get!(registry_path, repo), registry_path)

        {200,
         %{
           "repo" => repository["key"],
           "readiness" => RepositoryReadiness.get(repository, registry_path: registry_path)
         }}

      ["api", "repositories", repo, "spec-workspace"] ->
        repository =
          private_repository(RepositoryRegistry.get!(registry_path, repo), registry_path)

        {200,
         %{"repo" => repository["key"], "specWorkspace" => spec_workspace_payload(repository)}}

      ["api", "repositories", repo, "private-workspace"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded_read(registry_path, actor, repository, "repository.view", fn ->
          private_repository = private_repository(repository, registry_path)

          {200,
           %{
             "repo" => repository["key"],
             "privateWorkspace" => private_workspace_payload(private_repository)
           }}
        end)

      ["api", "repositories", repo, "pages"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        params = query_params(path)
        include_archived? = Map.get(params, "includeArchived") == "true"

        {200,
         %{
           "repo" => repository["key"],
           "pages" => MarkdownPages.list_pages(repository, include_archived: include_archived?)
         }}

      ["api", "repositories", repo, "pages", page_id] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        {200,
         %{"repo" => repository["key"], "page" => MarkdownPages.read_page(repository, page_id)}}

      ["api", "repositories", repo, "spec-workspace", "artifacts"] ->
        repository =
          private_repository(RepositoryRegistry.get!(registry_path, repo), registry_path)

        params = query_params(path)

        case Map.get(params, "type") do
          nil ->
            {200,
             %{"artifacts" => public_spec_artifacts(SpecWorkspace.list_artifacts(repository))}}

          type ->
            artifacts =
              repository
              |> SpecWorkspace.list_artifacts(type)
              |> Enum.map(&public_spec_artifact/1)

            {200, %{"type" => type, "artifacts" => artifacts}}
        end

      ["api", "repositories", repo, "spec-workspace", "artifacts", type] ->
        repository =
          private_repository(RepositoryRegistry.get!(registry_path, repo), registry_path)

        artifacts =
          repository
          |> SpecWorkspace.list_artifacts(type)
          |> Enum.map(&public_spec_artifact/1)

        {200, %{"type" => type, "artifacts" => artifacts}}

      ["api", "repositories", repo, "spec-workspace", "artifacts", type, id] ->
        repository =
          private_repository(RepositoryRegistry.get!(registry_path, repo), registry_path)

        {200, %{"artifact" => SpecWorkspace.read_artifact(repository, type, id)}}

      ["api", "repositories", repo, "private-workspace", "artifacts"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded_read(registry_path, actor, repository, "repository.view", fn ->
          private_repository = private_repository(repository, registry_path)
          params = query_params(path)

          case Map.get(params, "kind") || Map.get(params, "type") do
            nil ->
              {200,
               %{
                 "artifacts" =>
                   public_spec_artifacts(PrivateWorkspace.list_artifacts(private_repository))
               }}

            kind ->
              artifacts =
                private_repository
                |> PrivateWorkspace.list_artifacts(kind)
                |> Enum.map(&public_spec_artifact/1)

              {200, %{"kind" => kind, "type" => kind, "artifacts" => artifacts}}
          end
        end)

      ["api", "repositories", repo, "private-workspace", "artifacts", kind] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded_read(registry_path, actor, repository, "repository.view", fn ->
          private_repository = private_repository(repository, registry_path)

          artifacts =
            private_repository
            |> PrivateWorkspace.list_artifacts(kind)
            |> Enum.map(&public_spec_artifact/1)

          {200, %{"kind" => kind, "type" => kind, "artifacts" => artifacts}}
        end)

      ["api", "repositories", repo, "private-workspace", "artifacts", kind, id] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded_read(registry_path, actor, repository, "repository.view", fn ->
          private_repository = private_repository(repository, registry_path)
          {200, %{"artifact" => PrivateWorkspace.read_artifact(private_repository, kind, id)}}
        end)

      ["api", "repositories", repo, "private-workspace", "legacy"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded_read(registry_path, actor, repository, "repository.view", fn ->
          private_repository = private_repository(repository, registry_path)
          {200, %{"legacy" => PrivateWorkspace.legacy_artifacts(private_repository)}}
        end)

      ["api", "github", "installations", "callback"] ->
        github = Repositories.complete_installation(query_params(path))
        {200, %{"connection" => Auth.connection(), "github" => github}}

      ["api", "repositories", repo, "github"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        {200, %{"repo" => repository["key"], "github" => RepositoryLink.state(repository)}}

      ["api", "repositories", repo, "automation"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        {200, %{"repo" => repository["key"], "automation" => Automation.status(repository)}}

      ["api", "repositories", repo, "coding-assistants", "providers"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        {200,
         ProviderCatalog.readiness_status(
           mode: :check_only,
           repository: repository,
           registry_path: registry_path
         )}

      ["api", "repositories", repo, "remote-execution"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        {200, %{"repo" => repository["key"], "policy" => RepositoryPolicy.public(repository)}}

      ["api", "repositories", repo, "sandbox-policy"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        {200,
         %{
           "repo" => repository["key"],
           "policy" => SandboxPolicy.public(repository, registry_path)
         }}

      ["api", "repositories", repo, "secret-references"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded_read(registry_path, actor, repository, "secret_reference.view", fn ->
          {200,
           %{
             "repo" => repository["key"],
             "secretReferences" => SecretReferences.list(registry_path, repository)
           }}
        end)

      ["api", "harness", "daemon"] ->
        Daemon.ensure_started(registry_path)
        {200, %{"daemon" => Daemon.status()}}

      ["api", "harness", "status"] ->
        Daemon.ensure_started(registry_path)
        {200, %{"harness" => Daemon.status()}}

      ["api", "repositories", repo, "workflow"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        {200, %{"repo" => repository["key"], "workflow" => Workspace.workflow(repository)}}

      ["api", "repositories", repo, "tasks"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        {200, %{"tasks" => public_tasks(TaskStore.list_tasks(repository))}}

      ["api", "repositories", repo, "tasks", task_key] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        case TaskStore.get_task(repository, task_key) do
          nil -> {404, %{"error" => "Task not found"}}
          task -> {200, %{"task" => public_task(task)}}
        end

      ["api", "repositories", repo, "tasks", task_key, "coding-assistant", "runs", run_id] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        run = CodingAssistant.get_run(repository, task_key, run_id)
        {200, %{"run" => run}}

      [
        "api",
        "repositories",
        repo,
        "tasks",
        task_key,
        "coding-assistant",
        "runs",
        run_id,
        "events"
      ] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        events = CodingAssistant.get_run_events(repository, task_key, run_id)
        {200, %{"events" => events}}

      ["api", "repositories", repo, "tasks", task_key, "runs", run_id, "events"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        params = query_params(path)

        events =
          CodingAssistant.get_run_progress_events(repository, task_key, run_id,
            after: Map.get(params, "after")
          )

        {200, %{"events" => events}}

      ["api", "repositories", repo, "tasks", task_key, "harness", "eligibility"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        {200, %{"eligibility" => Eligibility.explain(repository, task_key)}}

      _ ->
        {404, %{"error" => "Not found"}}
    end
  rescue
    error -> {400, %{"error" => Exception.message(error)}}
  end

  defp route(%{method: "PATCH", path: path, body: body}, registry_path, actor) do
    case path_parts(path) do
      ["api", "repositories", repo, "workflow"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(registry_path, actor, repository, "workflow.update", workflow_target(), fn ->
          payload = decode_json(body)
          workflow = Workspace.update_workflow(repository, Map.get(payload, "body", ""))
          {200, %{"repo" => repository["key"], "workflow" => workflow}}
        end)

      ["api", "repositories", repo, "pages", page_id] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        page_target = %{"type" => "repository", "id" => page_id}

        guarded(registry_path, actor, repository, "repository.configure", page_target, fn ->
          page = MarkdownPages.update_page(repository, page_id, decode_json(body))
          {200, %{"repo" => repository["key"], "page" => page}}
        end)

      ["api", "repositories", repo, "spec-workspace", "artifacts", type, id] ->
        repository =
          private_repository(RepositoryRegistry.get!(registry_path, repo), registry_path)

        guarded(
          registry_path,
          actor,
          repository,
          "workspace.initialize",
          workflow_target(id),
          fn ->
            artifact = SpecWorkspace.update_artifact(repository, type, id, decode_json(body))
            {200, %{"artifact" => artifact}}
          end
        )

      ["api", "repositories", repo, "private-workspace", "artifacts", kind, id] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(
          registry_path,
          actor,
          repository,
          "repository.configure",
          private_workspace_target(kind, id),
          fn ->
            private_repository = private_repository(repository, registry_path)

            artifact =
              PrivateWorkspace.update_artifact(private_repository, kind, id, decode_json(body))

            {200, %{"artifact" => artifact}}
          end,
          %{"artifactKind" => kind, "artifactId" => id},
          "private_workspace.artifact_updated"
        )

      ["api", "repositories", repo, "tasks", task_key] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(registry_path, actor, repository, "task.update", task_target(task_key), fn ->
          patch = decode_json(body)
          task = TaskStore.patch_task(repository, task_key, patch)
          {200, %{"task" => public_task(task)}}
        end)

      _ ->
        {404, %{"error" => "Not found"}}
    end
  rescue
    error -> {400, %{"error" => Exception.message(error)}}
  end

  defp route(%{method: "DELETE", path: path}, registry_path, actor) do
    case path_parts(path) do
      ["api", "repositories", repo] ->
        repository = RepositoryRegistry.remove(registry_path, repo)
        {200, %{"repository" => public_repository(repository)}}

      ["api", "repositories", repo, "pages", page_id] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(
          registry_path,
          actor,
          repository,
          "repository.configure",
          workflow_target(page_id),
          fn ->
            params = query_params(path)

            if Map.get(params, "permanent") == "true" do
              {200,
               %{
                 "repo" => repository["key"],
                 "page" => MarkdownPages.delete_page(repository, page_id)
               }}
            else
              {200,
               %{
                 "repo" => repository["key"],
                 "page" => MarkdownPages.archive_page(repository, page_id)
               }}
            end
          end
        )

      ["api", "repositories", repo, "secret-references", secret_ref_id] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(
          registry_path,
          actor,
          repository,
          "secret_reference.delete",
          %{"type" => "secret_reference", "id" => secret_ref_id},
          fn ->
            case SecretReferences.delete(registry_path, repository, secret_ref_id) do
              {:ok, secret_reference} ->
                {200, %{"repo" => repository["key"], "secretReference" => secret_reference}}

              {:error, :not_found} ->
                {404, %{"error" => "Secret reference not found.", "reasonCode" => "not_found"}}
            end
          end,
          %{},
          "secret_reference.deleted"
        )

      _ ->
        {404, %{"error" => "Not found"}}
    end
  rescue
    error -> {400, %{"error" => Exception.message(error)}}
  end

  defp route(%{method: "POST", path: path, body: body, headers: headers}, registry_path, actor) do
    case path_parts(path) do
      ["api", "runners", "pairing-tokens"] ->
        guarded_runner_action(
          registry_path,
          actor,
          "runner.pair",
          runner_target(),
          fn ->
            {:ok, pairing, token} = Pairing.create(registry_path, actor, decode_json(body))

            {201,
             %{
               "pairingToken" => token,
               "expiresAt" => pairing["expiresAt"],
               "runnerName" => pairing["name"],
               "message" => "Copy this token now. It will not be shown again."
             }, runner_target(pairing["id"]), %{"reasonCode" => "pairing_token_created"}}
          end,
          "runner.pairing_token_created"
        )

      ["api", "runners", "register"] ->
        case Registry.register(registry_path, actor, decode_json(body)) do
          {:ok, runner, runner_token} ->
            public = Registry.public(runner)

            AuditLog.record(registry_path, global_repository(), %{
              "actor" => actor,
              "action" => "runner.paired",
              "target" => runner_target(public["id"]),
              "result" => "completed",
              "metadata" => runner_metadata(public)
            })

            {201, %{"runner" => public, "runnerToken" => runner_token}}

          {:error, reason} ->
            {403,
             %{
               "error" => pairing_error_message(reason),
               "reasonCode" => to_string(reason)
             }}
        end

      ["api", "runners", runner_id, "approve"] ->
        guarded_runner_action(
          registry_path,
          actor,
          "runner.approve",
          runner_target(runner_id),
          fn ->
            case Registry.approve(registry_path, runner_id) do
              {:ok, runner, _meta} ->
                public = Registry.public(runner)
                {200, %{"runner" => public}, runner_target(public["id"]), runner_metadata(public)}

              {:error, reason} ->
                runner_lifecycle_error(reason, runner_id)
            end
          end,
          "runner.trust_approved"
        )

      ["api", "runners", runner_id, "revoke"] ->
        guarded_runner_action(
          registry_path,
          actor,
          "runner.revoke",
          runner_target(runner_id),
          fn ->
            case Registry.revoke(registry_path, runner_id) do
              {:ok, runner, _meta} ->
                cancel_assignments_for_runner(registry_path, runner_id)
                public = Registry.public(runner)
                {200, %{"runner" => public}, runner_target(public["id"]), runner_metadata(public)}

              {:error, reason} ->
                runner_lifecycle_error(reason, runner_id)
            end
          end,
          "runner.revoked"
        )

      ["api", "runners", runner_id, "rotate-token"] ->
        guarded_runner_action(
          registry_path,
          actor,
          "runner.rotate_token",
          runner_target(runner_id),
          fn ->
            case Registry.rotate_token(registry_path, runner_id) do
              {:ok, runner, token} ->
                public = Registry.public(runner)

                {200, %{"runner" => public, "runnerToken" => token}, runner_target(public["id"]),
                 runner_metadata(public)}

              {:error, reason} ->
                runner_lifecycle_error(reason, runner_id)
            end
          end,
          "runner.token_rotated"
        )

      ["api", "repositories", repo, "secret-references"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(
          registry_path,
          actor,
          repository,
          "secret_reference.create",
          %{"type" => "secret_reference"},
          fn ->
            {:ok, secret_reference} =
              SecretReferences.create(registry_path, repository, decode_json(body))

            {201,
             %{
               "repo" => repository["key"],
               "secretReference" => secret_reference
             }}
          end,
          secret_reference_metadata(decode_json(body)),
          "secret_reference.created"
        )

      ["api", "runners", runner_id, "heartbeat"] ->
        payload = decode_json(body)

        case Registry.heartbeat(registry_path, runner_id, payload["token"], payload) do
          {:ok, runner, transition} ->
            public = Registry.public(runner)
            audit_heartbeat_transition(registry_path, actor, public, transition)

            {200,
             %{
               "runner" =>
                 %{
                   "id" => public["id"],
                   "status" => public["status"],
                   "lastHeartbeatAt" => public["lastHeartbeatAt"]
                 }
                 |> reject_nil()
             }}

          {:error, :invalid_token} ->
            {403, %{"error" => "Invalid runner token.", "reasonCode" => "invalid_runner_token"}}

          {:error, :runner_revoked} ->
            {403, %{"error" => "Runner is revoked.", "reasonCode" => "runner_revoked"}}

          {:error, :runner_token_rotated} ->
            {403,
             %{
               "error" => "Runner token has been rotated.",
               "reasonCode" => "runner_token_rotated"
             }}

          {:error, :runner_token_revoked} ->
            {403,
             %{"error" => "Runner token is revoked.", "reasonCode" => "runner_token_revoked"}}

          {:error, :not_found} ->
            {404, %{"error" => "Runner not found.", "reasonCode" => "runner_not_found"}}

          {:error, _reason} ->
            {400, %{"error" => "Invalid runner heartbeat.", "reasonCode" => "invalid_heartbeat"}}
        end

      ["api", "runners", runner_id, "assignments", "claim"] ->
        payload = decode_json(body)

        case Assignments.claim(registry_path, runner_id, runner_token(headers, payload)) do
          {:ok, assignment} -> {200, Assignments.runner_response(assignment)}
          {:error, reason} -> runner_assignment_error(reason)
        end

      ["api", "runners", runner_id, "assignments", assignment_id, "events"] ->
        payload = decode_json(body)

        case Assignments.record_event(
               registry_path,
               runner_id,
               assignment_id,
               runner_token(headers, payload),
               payload
             ) do
          {:ok, assignment} -> {200, Assignments.public_response(assignment)}
          {:error, reason} -> runner_assignment_error(reason)
        end

      ["api", "runners", runner_id, "assignments", assignment_id, "result"] ->
        payload = decode_json(body)

        case Assignments.submit_result(
               registry_path,
               runner_id,
               assignment_id,
               runner_token(headers, payload),
               payload
             ) do
          {:ok, assignment, _mode} -> {200, Assignments.public_response(assignment)}
          {:error, reason} -> runner_assignment_error(reason)
        end

      ["api", "runners", runner_id, "assignments", assignment_id, "fail"] ->
        payload = decode_json(body)

        case Assignments.fail(
               registry_path,
               runner_id,
               assignment_id,
               runner_token(headers, payload),
               payload
             ) do
          {:ok, assignment, _mode} -> {200, Assignments.public_response(assignment)}
          {:error, reason} -> runner_assignment_error(reason)
        end

      ["api", "runners", runner_id, "disable"] ->
        guarded_runner_action(
          registry_path,
          actor,
          "runner.disable",
          runner_target(runner_id),
          fn ->
            case Registry.disable(registry_path, runner_id) do
              {:ok, runner, _meta} ->
                public = Registry.public(runner)
                {200, %{"runner" => public}, runner_target(public["id"]), runner_metadata(public)}

              {:error, reason} ->
                runner_lifecycle_error(reason, runner_id)
            end
          end,
          "runner.disabled"
        )

      ["api", "runners", runner_id, "enable"] ->
        guarded_runner_action(
          registry_path,
          actor,
          "runner.enable",
          runner_target(runner_id),
          fn ->
            case Registry.enable(registry_path, runner_id) do
              {:ok, runner, _meta} ->
                public = Registry.public(runner)
                {200, %{"runner" => public}, runner_target(public["id"]), runner_metadata(public)}

              {:error, reason} ->
                runner_lifecycle_error(reason, runner_id)
            end
          end,
          "runner.enabled"
        )

      ["api", "github", "connect", "start"] ->
        case Auth.start_device_flow() do
          {:ok, payload} ->
            {200, payload}

          {:error, payload} ->
            {400,
             %{
               "error" => payload["message"] || "Could not start GitHub connection.",
               "githubError" => payload
             }}
        end

      ["api", "github", "connect", "poll"] ->
        case Auth.poll_device_flow(decode_json(body)) do
          {:ok, connection} ->
            {200, %{"connection" => connection}}

          {:pending, payload} ->
            {202, payload}

          {:error, status, payload} ->
            {status, payload}

          {:error, payload} ->
            {400,
             %{
               "error" => payload["message"] || "Could not connect GitHub.",
               "githubError" => payload
             }}
        end

      ["api", "github", "installations", "complete"] ->
        github = Repositories.complete_installation(decode_json(body))
        {200, %{"connection" => Auth.connection(), "github" => github}}

      ["api", "github", "installations", "refresh"] ->
        github = Repositories.refresh_installations(decode_json(body))
        {200, %{"connection" => Auth.connection(), "github" => github}}

      ["api", "github", "repositories", "workspace"] ->
        repository = RepositoryRegistry.add_github(registry_path, decode_json(body))
        Workspace.initialize(repository)
        ensure_default_workflow(repository)
        {200, %{"repository" => public_repository(repository)}}

      ["api", "repositories", repo, "workspace", "initialize"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(
          registry_path,
          actor,
          repository,
          "workspace.initialize",
          repository_target(),
          fn ->
            workspace = Workspace.initialize(repository)
            {200, %{"repo" => repository["key"], "workspace" => workspace}}
          end
        )

      ["api", "repositories", repo, "readiness", "workspace", "initialize"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(
          registry_path,
          actor,
          repository,
          "workspace.initialize",
          repository_target(),
          fn ->
            readiness =
              SetupActions.initialize_workspace(repository, registry_path: registry_path)

            {200, %{"repo" => repository["key"], "readiness" => readiness}}
          end
        )

      ["api", "repositories", repo, "spec-workspace", "initialize"] ->
        repository =
          private_repository(RepositoryRegistry.get!(registry_path, repo), registry_path)

        guarded(registry_path, actor, repository, "workspace.initialize", workflow_target(), fn ->
          SpecWorkspace.initialize(repository)

          {200,
           %{"repo" => repository["key"], "specWorkspace" => spec_workspace_payload(repository)}}
        end)

      ["api", "repositories", repo, "private-workspace", "initialize"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(
          registry_path,
          actor,
          repository,
          "repository.configure",
          private_workspace_target(),
          fn ->
            private_repository = private_repository(repository, registry_path)
            PrivateWorkspace.initialize(private_repository)

            {200,
             %{
               "repo" => repository["key"],
               "privateWorkspace" => private_workspace_payload(private_repository)
             }}
          end,
          %{},
          "private_workspace.initialized"
        )

      ["api", "repositories", repo, "readiness", "spec-workspace", "initialize"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(registry_path, actor, repository, "workspace.initialize", workflow_target(), fn ->
          readiness =
            SetupActions.initialize_spec_workspace(repository, registry_path: registry_path)

          {200, %{"repo" => repository["key"], "readiness" => readiness}}
        end)

      ["api", "repositories", repo, "spec-workspace", "artifacts", type] ->
        repository =
          private_repository(RepositoryRegistry.get!(registry_path, repo), registry_path)

        guarded(registry_path, actor, repository, "repository.configure", workflow_target(), fn ->
          artifact = SpecWorkspace.create_artifact(repository, type, decode_json(body))
          {201, %{"artifact" => artifact}}
        end)

      ["api", "repositories", repo, "spec-workspace", "milestones"] ->
        repository =
          private_repository(RepositoryRegistry.get!(registry_path, repo), registry_path)

        guarded(registry_path, actor, repository, "repository.configure", workflow_target(), fn ->
          artifact = SpecWorkspace.create_milestone(repository, decode_json(body))
          {201, %{"artifact" => artifact}}
        end)

      ["api", "repositories", repo, "spec-workspace", "requirements"] ->
        repository =
          private_repository(RepositoryRegistry.get!(registry_path, repo), registry_path)

        guarded(registry_path, actor, repository, "repository.configure", workflow_target(), fn ->
          artifact = SpecWorkspace.create_requirement(repository, decode_json(body))
          {201, %{"artifact" => artifact}}
        end)

      ["api", "repositories", repo, "spec-workspace", "plans"] ->
        repository =
          private_repository(RepositoryRegistry.get!(registry_path, repo), registry_path)

        guarded(registry_path, actor, repository, "repository.configure", workflow_target(), fn ->
          artifact = SpecWorkspace.create_plan(repository, decode_json(body))
          {201, %{"artifact" => artifact}}
        end)

      ["api", "repositories", repo, "spec-workspace", "decisions"] ->
        repository =
          private_repository(RepositoryRegistry.get!(registry_path, repo), registry_path)

        guarded(registry_path, actor, repository, "repository.configure", workflow_target(), fn ->
          artifact = SpecWorkspace.create_decision(repository, decode_json(body))
          {201, %{"artifact" => artifact}}
        end)

      ["api", "repositories", repo, "spec-workspace", "task-briefs"] ->
        repository =
          private_repository(RepositoryRegistry.get!(registry_path, repo), registry_path)

        guarded(registry_path, actor, repository, "repository.configure", workflow_target(), fn ->
          artifact = SpecWorkspace.create_task_brief(repository, decode_json(body))
          {201, %{"artifact" => artifact}}
        end)

      ["api", "repositories", repo, "private-workspace", "artifacts", kind] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(
          registry_path,
          actor,
          repository,
          "repository.configure",
          private_workspace_target(kind),
          fn ->
            private_repository = private_repository(repository, registry_path)

            artifact =
              PrivateWorkspace.create_artifact(private_repository, kind, decode_json(body))

            {201, %{"artifact" => artifact}}
          end,
          %{"artifactKind" => kind},
          "private_workspace.artifact_created"
        )

      ["api", "repositories", repo, "private-workspace", "legacy", "import"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(
          registry_path,
          actor,
          repository,
          "repository.configure",
          private_workspace_target("legacy"),
          fn ->
            private_repository = private_repository(repository, registry_path)
            result = PrivateWorkspace.import_legacy(private_repository, decode_json(body))
            {200, result}
          end,
          %{"reasonCode" => "legacy_import"},
          "private_workspace.legacy_imported"
        )

      ["api", "repositories", repo, "private-workspace", "artifacts", kind, id, "export"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(
          registry_path,
          actor,
          repository,
          "repository.configure",
          private_workspace_target(kind, id),
          fn ->
            private_repository = private_repository(repository, registry_path)

            artifact =
              PrivateWorkspace.export_artifact(private_repository, kind, id, decode_json(body))

            {200, %{"artifact" => artifact}}
          end,
          %{"artifactKind" => kind, "artifactId" => id},
          "private_workspace.artifact_exported"
        )

      ["api", "repositories", repo, "pages"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(
          registry_path,
          actor,
          repository,
          "repository.configure",
          repository_target(),
          fn ->
            page = MarkdownPages.create_page(repository, decode_json(body))
            {201, %{"repo" => repository["key"], "page" => page}}
          end
        )

      ["api", "repositories", repo, "clarise", "extract"] ->
        repository =
          private_repository(RepositoryRegistry.get!(registry_path, repo), registry_path)

        {200, ArtifactExtractor.extract(repository, decode_json(body))}

      ["api", "repositories", repo, "clarise", "milestones", "start"] ->
        repository =
          private_repository(RepositoryRegistry.get!(registry_path, repo), registry_path)

        guarded(registry_path, actor, repository, "repository.configure", workflow_target(), fn ->
          {201, MilestoneLoop.start(repository, decode_json(body))}
        end)

      ["api", "repositories", repo, "clarise", "milestones", milestone, "discuss"] ->
        repository =
          private_repository(RepositoryRegistry.get!(registry_path, repo), registry_path)

        guarded(
          registry_path,
          actor,
          repository,
          "repository.configure",
          workflow_target(milestone),
          fn ->
            {200, MilestoneLoop.discuss(repository, milestone, decode_json(body))}
          end
        )

      ["api", "repositories", repo, "clarise", "milestones", milestone, "requirements"] ->
        repository =
          private_repository(RepositoryRegistry.get!(registry_path, repo), registry_path)

        guarded(
          registry_path,
          actor,
          repository,
          "repository.configure",
          workflow_target(milestone),
          fn ->
            {201, MilestoneLoop.requirements(repository, milestone, decode_json(body))}
          end
        )

      ["api", "repositories", repo, "clarise", "milestones", milestone, "plan"] ->
        repository =
          private_repository(RepositoryRegistry.get!(registry_path, repo), registry_path)

        guarded(
          registry_path,
          actor,
          repository,
          "repository.configure",
          workflow_target(milestone),
          fn ->
            {201, MilestoneLoop.plan(repository, milestone, decode_json(body))}
          end
        )

      ["api", "repositories", repo, "clarise", "milestones", milestone, "decisions"] ->
        repository =
          private_repository(RepositoryRegistry.get!(registry_path, repo), registry_path)

        guarded(
          registry_path,
          actor,
          repository,
          "repository.configure",
          workflow_target(milestone),
          fn ->
            {201, MilestoneLoop.decision(repository, milestone, decode_json(body))}
          end
        )

      ["api", "repositories", repo, "clarise", "milestones", milestone, "approve"] ->
        repository =
          private_repository(RepositoryRegistry.get!(registry_path, repo), registry_path)

        guarded(
          registry_path,
          actor,
          repository,
          "repository.configure",
          workflow_target(milestone),
          fn ->
            {200, MilestoneLoop.approve(repository, milestone, decode_json(body))}
          end
        )

      ["api", "repositories", repo, "clarise", "milestones", milestone, "tasks", "propose"] ->
        repository =
          private_repository(RepositoryRegistry.get!(registry_path, repo), registry_path)

        guarded(
          registry_path,
          actor,
          repository,
          "repository.configure",
          workflow_target(milestone),
          fn ->
            {201, PlanToTaskCompiler.propose(repository, milestone, decode_json(body))}
          end
        )

      ["api", "repositories", repo, "clarise", "milestones", milestone, "tasks", "create"] ->
        repository =
          private_repository(RepositoryRegistry.get!(registry_path, repo), registry_path)

        guarded(registry_path, actor, repository, "task.create", workflow_target(milestone), fn ->
          {201,
           PlanToTaskCompiler.create_tasks(
             registry_path,
             repository,
             milestone,
             decode_json(body)
           )}
        end)

      ["api", "repositories", repo, "github", "link"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(registry_path, actor, repository, "provider.configure", repository_target(), fn ->
          github = RepositoryLink.link(registry_path, repository, decode_json(body))
          {200, %{"repo" => repository["key"], "github" => github}}
        end)

      ["api", "repositories", repo, "automation", "enable"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(registry_path, actor, repository, "automation.enable", repository_target(), fn ->
          repository = Automation.enable(registry_path, repo, decode_json(body))
          {200, %{"repo" => repository["key"], "automation" => Automation.status(repository)}}
        end)

      ["api", "repositories", repo, "automation", "disable"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(registry_path, actor, repository, "automation.disable", repository_target(), fn ->
          repository = Automation.disable(registry_path, repo)
          {200, %{"repo" => repository["key"], "automation" => Automation.status(repository)}}
        end)

      ["api", "repositories", repo, "remote-execution"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        payload = decode_json(body)

        guarded(
          registry_path,
          actor,
          repository,
          "repository.configure",
          repository_target(),
          fn ->
            repository = RepositoryPolicy.update_policy(registry_path, repo, payload)
            {200, %{"repo" => repository["key"], "policy" => RepositoryPolicy.public(repository)}}
          end
        )

      ["api", "repositories", repo, "remote-execution", "enable"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(
          registry_path,
          actor,
          repository,
          "repository.configure",
          repository_target(),
          fn ->
            repository = RepositoryPolicy.set_remote_execution(registry_path, repo, true)
            {200, %{"repo" => repository["key"], "policy" => RepositoryPolicy.public(repository)}}
          end
        )

      ["api", "repositories", repo, "remote-execution", "disable"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(
          registry_path,
          actor,
          repository,
          "repository.configure",
          repository_target(),
          fn ->
            repository = RepositoryPolicy.set_remote_execution(registry_path, repo, false)
            {200, %{"repo" => repository["key"], "policy" => RepositoryPolicy.public(repository)}}
          end
        )

      ["api", "repositories", repo, "sandbox-policy"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        payload = decode_json(body)

        allowed? =
          payload["sandboxExecutionAllowed"] == true or
            payload["sandbox_execution_allowed"] == true

        guarded(
          registry_path,
          actor,
          repository,
          "sandbox.configure",
          repository_target(),
          fn ->
            SandboxPolicy.set(registry_path, repo, payload)
            repository = RepositoryPolicy.update_policy(registry_path, repo, payload)

            action =
              if allowed?, do: "sandbox.policy_enabled", else: "sandbox.policy_disabled"

            AuditLog.record(registry_path, repository, %{
              "actor" => actor,
              "action" => action,
              "target" => repository_target(),
              "result" => "completed",
              "metadata" => %{
                "provider" => SandboxPolicy.provider(repository),
                "workspaceProvider" => "cloud_sandbox"
              }
            })

            if SandboxPolicy.provider(repository) == "opensandbox" do
              AuditLog.record(registry_path, repository, %{
                "actor" => actor,
                "action" => "sandbox.provider_configured",
                "target" => repository_target(),
                "result" => "completed",
                "metadata" => %{
                  "provider" => "opensandbox",
                  "workspaceProvider" => "cloud_sandbox"
                }
              })
            end

            {200,
             %{
               "repo" => repository["key"],
               "policy" => SandboxPolicy.public(repository, registry_path)
             }}
          end
        )

      ["api", "repositories", repo, "sandbox", "opensandbox", "smoke"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(
          registry_path,
          actor,
          repository,
          "sandbox.configure",
          repository_target(),
          fn ->
            case OpenSandboxSmoke.run(registry_path, repository, actor, decode_json(body)) do
              {:ok, smoke} -> {200, %{"repo" => repository["key"], "smoke" => smoke}}
              {:error, {status, payload}} -> {status, payload}
            end
          end
        )

      ["api", "harness", "daemon", "tick"] ->
        repository = harness_repository(registry_path, path)

        guarded(registry_path, actor, repository, "harness.tick", harness_target(), fn ->
          Daemon.ensure_started(registry_path)
          {200, Daemon.tick()}
        end)

      ["api", "harness", "pause"] ->
        repository = harness_repository(registry_path, path)

        guarded(registry_path, actor, repository, "harness.pause", harness_target(), fn ->
          Daemon.ensure_started(registry_path)
          {200, Daemon.pause()}
        end)

      ["api", "harness", "resume"] ->
        repository = harness_repository(registry_path, path)

        guarded(registry_path, actor, repository, "harness.resume", harness_target(), fn ->
          Daemon.ensure_started(registry_path)
          {200, Daemon.resume()}
        end)

      ["api", "harness", "tick"] ->
        repository = harness_repository(registry_path, path)

        guarded(registry_path, actor, repository, "harness.tick", harness_target(), fn ->
          Daemon.ensure_started(registry_path)
          {200, Daemon.tick()}
        end)

      ["api", "harness", "reconcile"] ->
        repository = harness_repository(registry_path, path)

        guarded(registry_path, actor, repository, "harness.reconcile", harness_target(), fn ->
          Daemon.ensure_started(registry_path)
          {200, Daemon.reconcile()}
        end)

      ["api", "repositories", repo, "workflow", "from-template"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(registry_path, actor, repository, "workflow.update", workflow_target(), fn ->
          payload = decode_json(body)

          template_id =
            Map.get(payload, "template") || Map.get(payload, "templateId") ||
              Map.get(payload, "id")

          workflow = Workspace.create_workflow_from_template(repository, template_id)
          {201, %{"repo" => repository["key"], "workflow" => workflow}}
        end)

      ["api", "repositories", repo, "readiness", "workflow", "from-template"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(registry_path, actor, repository, "workflow.update", workflow_target(), fn ->
          readiness =
            SetupActions.create_workflow_from_template(repository, decode_json(body),
              registry_path: registry_path
            )

          {201, %{"repo" => repository["key"], "readiness" => readiness}}
        end)

      ["api", "repositories", repo, "readiness", "scan"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        {200, %{"repo" => repository["key"], "scan" => RepositoryScanner.scan(repository)}}

      ["api", "repositories", repo, "tasks"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(registry_path, actor, repository, "task.create", repository_target(), fn ->
          task = TaskStore.create_task(registry_path, repository, decode_json(body))
          {201, %{"task" => public_task(task)}}
        end)

      ["api", "repositories", repo, "tasks", task_key, "events"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        payload = decode_json(body)
        event = Map.fetch!(payload, "event")
        params = Map.get(payload, "params", %{})
        permission = permission_for_task_event(event)

        guarded(registry_path, actor, repository, permission, task_target(task_key), fn ->
          task = TaskStore.apply_event(repository, task_key, event, params)
          {200, %{"task" => public_task(task)}}
        end)

      ["api", "repositories", repo, "tasks", task_key, "coding-assistant", "runs"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        payload = decode_json(body)

        permission =
          cond do
            sandbox_execution_requested?(payload) -> "sandbox.run"
            experimental_run?(payload) -> "workspace_provider.experimental_run"
            true -> "task.run_codex"
          end

        start_coding_assistant_run(
          registry_path,
          actor,
          repository,
          task_key,
          payload,
          permission
        )

      [
        "api",
        "repositories",
        repo,
        "tasks",
        task_key,
        "coding-assistant",
        "runs",
        run_id,
        "cancel"
      ] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(
          registry_path,
          actor,
          repository,
          "task.cancel_run",
          task_target(task_key),
          fn ->
            result = CodingAssistant.cancel_run(repository, task_key, run_id, registry_path)

            {200,
             %{
               "run" => result["run"],
               "task" => result["task"] && public_task(result["task"])
             }}
          end,
          %{"taskKey" => task_key, "runId" => run_id}
        )

      ["api", "repositories", repo, "tasks", task_key, "review", "request-changes"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(
          registry_path,
          actor,
          repository,
          "review.request_changes",
          task_target(task_key),
          fn ->
            result =
              CodingAssistant.continue_from_review_notes(
                registry_path,
                repository,
                task_key,
                decode_json(body)
              )

            {201,
             %{
               "run" => result["run"],
               "review_note" => result["review_note"],
               "task" => public_task(result["task"])
             }}
          end
        )

      ["api", "repositories", repo, "tasks", task_key, "open-pull-request"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(
          registry_path,
          actor,
          repository,
          "pull_request.open",
          task_target(task_key),
          fn ->
            task = PullRequests.open_from_task(repository, task_key)
            {200, %{"task" => public_task(task)}}
          end
        )

      ["api", "repositories", repo, "tasks", task_key, "refresh-pr"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(
          registry_path,
          actor,
          repository,
          "pull_request.refresh",
          task_target(task_key),
          fn ->
            result = Sync.refresh_pull_request(repository, task_key)

            {200,
             %{
               "task" => public_task(result["task"]),
               "refreshResult" => result["refreshResult"]
             }}
          end
        )

      _ ->
        {404, %{"error" => "Not found"}}
    end
  rescue
    error -> {400, %{"error" => Exception.message(error)}}
  end

  defp route(_request, _registry_path, _actor), do: {405, %{"error" => "Method not allowed"}}

  defp start_coding_assistant_run(registry_path, actor, repository, task_key, payload, permission) do
    metadata =
      %{
        "taskKey" => task_key,
        "workspaceProvider" =>
          workspace_provider(payload) || execution_workspace_provider(payload),
        "provider" => "codex_app_server"
      }
      |> reject_nil()

    case authorize_run_start(registry_path, actor, repository, task_key, payload, permission) do
      :ok ->
        with {:ok, runner} <-
               select_runner_for_payload(registry_path, repository, actor, payload) do
          try do
            result =
              CodingAssistant.start_run(
                registry_path,
                repository,
                task_key,
                payload
                |> Map.put("runner", runner)
                |> Map.put("actor", actor)
              )

            AuditLog.record(registry_path, repository, %{
              "actor" => actor,
              "action" => permission,
              "target" => task_target(task_key),
              "result" => "completed",
              "metadata" => metadata
            })

            {201, %{"run" => result["run"], "task" => public_task(result["task"])}}
          rescue
            error ->
              AuditLog.record(registry_path, repository, %{
                "actor" => actor,
                "action" => permission,
                "target" => task_target(task_key),
                "result" => "failed",
                "metadata" => Map.put(metadata, "reasonCode", "exception")
              })

              reraise error, __STACKTRACE__
          end
        else
          {:error, {status, payload}} ->
            {status, payload}
        end

      {:error, {status, payload}} ->
        AuditLog.record(registry_path, repository, %{
          "actor" => actor,
          "action" => permission,
          "target" => task_target(task_key),
          "result" => "denied",
          "metadata" => Map.put(metadata, "reasonCode", payload["reasonCode"] || "denied")
        })

        {status, payload}

      {:error, payload} ->
        AuditLog.record(registry_path, repository, %{
          "actor" => actor,
          "action" => permission,
          "target" => task_target(task_key),
          "result" => "denied",
          "metadata" => Map.put(metadata, "reasonCode", "permission_denied")
        })

        {403, payload}
    end
  end

  defp authorize_run_start(registry_path, actor, repository, task_key, payload, permission) do
    with :ok <- Policy.authorize(actor, permission, repository, task_target(task_key)),
         :ok <- authorize_task_run_codex(actor, repository, task_key, permission),
         :ok <- authorize_sandbox_run(registry_path, actor, repository, task_key, payload) do
      :ok
    end
  end

  defp authorize_task_run_codex(_actor, _repository, _task_key, "task.run_codex"), do: :ok

  defp authorize_task_run_codex(actor, repository, task_key, _permission),
    do: Policy.authorize(actor, "task.run_codex", repository, task_target(task_key))

  defp authorize_sandbox_run(registry_path, actor, repository, task_key, payload) do
    if sandbox_execution_requested?(payload) do
      task = TaskStore.get_task(repository, task_key)
      SandboxPolicy.authorize_run(registry_path, repository, actor, task, payload)
    else
      :ok
    end
  end

  defp select_runner_for_payload(registry_path, repository, actor, payload) do
    if sandbox_execution_requested?(payload) do
      {:ok, SymphoniaService.Runner.CloudSandboxProvider.runner_metadata(repository)}
    else
      SelectionPolicy.select_for_run(registry_path, repository, actor,
        runner_id: runner_id(payload),
        workspace_provider: workspace_provider(payload) || "local_git_worktree",
        allow_remote_execution: remote_execution_requested?(payload),
        remote_execution: remote_execution_requested?(payload)
      )
    end
  end

  defp guarded_runner_action(registry_path, actor, action, target, fun, audit_action)
       when is_function(fun, 0) do
    repository = global_repository()

    case Policy.authorize(actor, action, repository, target) do
      :ok ->
        try do
          {status, payload, event_target, metadata} = fun.()
          result = if status in 200..299, do: "completed", else: "failed"

          AuditLog.record(registry_path, repository, %{
            "actor" => actor,
            "action" => audit_action || action,
            "target" => event_target,
            "result" => result,
            "metadata" => metadata
          })

          {status, payload}
        rescue
          error ->
            AuditLog.record(registry_path, repository, %{
              "actor" => actor,
              "action" => action,
              "target" => target,
              "result" => "failed",
              "metadata" => %{"reasonCode" => "exception"}
            })

            reraise error, __STACKTRACE__
        end

      {:error, payload} ->
        AuditLog.record(registry_path, repository, %{
          "actor" => actor,
          "action" => action,
          "target" => target,
          "result" => "denied",
          "metadata" => %{"reasonCode" => "permission_denied"}
        })

        {403, payload}
    end
  end

  defp guarded(
         registry_path,
         actor,
         repository,
         permission,
         target,
         fun,
         metadata \\ %{},
         audit_action \\ nil
       )
       when is_function(fun, 0) do
    case Policy.authorize(actor, permission, repository, target) do
      :ok ->
        try do
          {status, payload} = fun.()

          AuditLog.record(registry_path, repository, %{
            "actor" => actor,
            "action" => audit_action || permission,
            "target" => target,
            "result" => "completed",
            "metadata" => metadata
          })

          {status, payload}
        rescue
          error ->
            AuditLog.record(registry_path, repository, %{
              "actor" => actor,
              "action" => permission,
              "target" => target,
              "result" => "failed",
              "metadata" => Map.put(metadata, "reasonCode", "exception")
            })

            reraise error, __STACKTRACE__
        end

      {:error, payload} ->
        AuditLog.record(registry_path, repository, %{
          "actor" => actor,
          "action" => permission,
          "target" => target,
          "result" => "denied",
          "metadata" => Map.put(metadata, "reasonCode", "permission_denied")
        })

        {403, payload}
    end
  end

  defp guarded_read(registry_path, actor, repository, permission, fun) when is_function(fun, 0) do
    case Policy.authorize(actor, permission, repository) do
      :ok ->
        fun.()

      {:error, payload} ->
        AuditLog.record(registry_path, repository, %{
          "actor" => actor,
          "action" => permission,
          "target" => repository_target(),
          "result" => "denied",
          "metadata" => %{"reasonCode" => "permission_denied"}
        })

        {403, payload}
    end
  end

  defp audit_runner_transitions(registry_path, actor) do
    registry_path
    |> Registry.mark_stale()
    |> Enum.each(fn %{"runner" => runner, "after" => status} ->
      AuditLog.record(registry_path, global_repository(), %{
        "actor" => actor,
        "action" => "runner.heartbeat_stale",
        "target" => runner_target(runner["id"]),
        "result" => "completed",
        "summary" => "Runner heartbeat status changed to #{status}.",
        "metadata" => Map.put(runner_metadata(runner), "reasonCode", "heartbeat_#{status}")
      })
    end)
  end

  defp audit_heartbeat_transition(registry_path, actor, runner, %{
         before: before,
         after: after_status
       }) do
    if before != after_status and before in ["stale", "offline"] do
      AuditLog.record(registry_path, global_repository(), %{
        "actor" => actor,
        "action" => "runner.heartbeat_stale",
        "target" => runner_target(runner["id"]),
        "result" => "completed",
        "summary" => "Runner heartbeat status changed to #{after_status}.",
        "metadata" => Map.put(runner_metadata(runner), "reasonCode", "heartbeat_#{after_status}")
      })
    end
  end

  defp audit_heartbeat_transition(_registry_path, _actor, _runner, _transition), do: :ok

  defp repository_target, do: %{"type" => "repository"}
  defp private_workspace_target(id \\ nil), do: %{"type" => "private_workspace", "id" => id}

  defp private_workspace_target(kind, id), do: private_workspace_target("#{kind}:#{id}")

  defp workflow_target(id \\ nil), do: %{"type" => "workflow", "id" => id}
  defp harness_target, do: %{"type" => "harness"}
  defp task_target(task_key), do: %{"type" => "task", "id" => task_key}
  defp runner_target(id \\ nil), do: %{"type" => "runner", "id" => id}
  defp global_repository, do: %{"key" => "GLOBAL"}

  defp private_repository(repository, registry_path) do
    Map.put(repository, "_registry_path", registry_path)
  end

  defp runner_metadata(runner) do
    %{
      "runnerId" => runner["id"],
      "runnerMode" => runner["mode"],
      "trustState" => runner["trustState"],
      "healthState" => runner["healthState"] || runner["status"],
      "tokenState" => runner["tokenState"],
      "capabilitySummary" => Capabilities.summary(runner["capabilities"])
    }
    |> reject_nil()
  end

  defp secret_reference_metadata(attrs) when is_map(attrs) do
    %{
      "secretScope" => attrs["scope"],
      "secretSource" => attrs["source"] || "environment"
    }
    |> reject_nil()
  end

  defp secret_reference_metadata(_attrs), do: %{}

  defp runner_lifecycle_error(:local_service_immutable, runner_id) do
    {400,
     %{
       "error" => "Local service runner cannot be changed in V1.",
       "reasonCode" => "local_service_immutable"
     }, runner_target(runner_id), %{"runnerId" => runner_id, "runnerMode" => "local_service"}}
  end

  defp runner_lifecycle_error(:not_found, runner_id) do
    {404, %{"error" => "Runner not found.", "reasonCode" => "runner_not_found"},
     runner_target(runner_id), %{"runnerId" => runner_id, "runnerMode" => "remote_runner"}}
  end

  defp runner_lifecycle_error(reason, runner_id) do
    {409, %{"error" => runner_lifecycle_message(reason), "reasonCode" => to_string(reason)},
     runner_target(runner_id), %{"runnerId" => runner_id, "runnerMode" => "remote_runner"}}
  end

  defp runner_lifecycle_message(:runner_disabled), do: "Runner is disabled."
  defp runner_lifecycle_message(:runner_revoked), do: "Runner is revoked."
  defp runner_lifecycle_message(:invalid_trust_state), do: "Runner trust state cannot be changed."
  defp runner_lifecycle_message(_reason), do: "Runner lifecycle action failed."

  defp pairing_error_message(:pairing_token_expired), do: "Pairing token has expired."
  defp pairing_error_message(:pairing_token_used), do: "Pairing token has already been used."
  defp pairing_error_message(:pairing_token_revoked), do: "Pairing token was revoked."
  defp pairing_error_message(_reason), do: "Pairing token is invalid."

  defp cancel_assignments_for_runner(registry_path, runner_id) do
    registry_path
    |> AssignmentStore.list()
    |> Enum.filter(&(&1["runner_id"] == runner_id and not AssignmentStore.terminal?(&1)))
    |> Enum.each(fn assignment ->
      Assignments.cancel_assignment(registry_path, assignment)
    end)
  end

  defp permission_for_task_event("approve"), do: "review.approve"
  defp permission_for_task_event("request_changes"), do: "review.request_changes"
  defp permission_for_task_event("cancel"), do: "task.cancel"
  defp permission_for_task_event(_event), do: "task.update"

  defp harness_repository(registry_path, path) do
    params = query_params(path)
    repo = params["repoKey"] || params["repo"]

    if repo do
      RepositoryRegistry.get!(registry_path, repo)
    else
      %{"key" => "GLOBAL"}
    end
  end

  defp experimental_run?(payload), do: workspace_provider(payload) == "experimental_sandbox"

  defp sandbox_execution_requested?(payload), do: SandboxPolicy.requested?(payload)

  defp runner_id(payload) when is_map(payload), do: payload["runnerId"] || payload["runner_id"]
  defp runner_id(_payload), do: nil

  defp runner_token(headers, payload) when is_map(headers) and is_map(payload) do
    headers["x-runner-token"] || payload["token"] || payload["runnerToken"] ||
      payload["runner_token"]
  end

  defp runner_assignment_error(:invalid_token),
    do: {403, %{"error" => "Invalid runner token.", "reasonCode" => "invalid_runner_token"}}

  defp runner_assignment_error(:runner_revoked),
    do: {403, %{"error" => "Runner is revoked.", "reasonCode" => "runner_revoked"}}

  defp runner_assignment_error(:runner_token_rotated),
    do:
      {403,
       %{"error" => "Runner token has been rotated.", "reasonCode" => "runner_token_rotated"}}

  defp runner_assignment_error(:runner_token_revoked),
    do: {403, %{"error" => "Runner token is revoked.", "reasonCode" => "runner_token_revoked"}}

  defp runner_assignment_error(:not_found),
    do: {404, %{"error" => "Assignment or runner not found.", "reasonCode" => "not_found"}}

  defp runner_assignment_error(:runner_disabled),
    do: {403, %{"error" => "Runner is disabled.", "reasonCode" => "runner_disabled"}}

  defp runner_assignment_error(:runner_stale),
    do: {403, %{"error" => "Runner heartbeat is stale.", "reasonCode" => "runner_stale"}}

  defp runner_assignment_error(:runner_offline),
    do: {403, %{"error" => "Runner is offline.", "reasonCode" => "runner_offline"}}

  defp runner_assignment_error(:invalid_transition),
    do:
      {409,
       %{"error" => "Invalid assignment state transition.", "reasonCode" => "invalid_transition"}}

  defp runner_assignment_error(:assignment_finalized),
    do:
      {409,
       %{
         "error" => "Assignment is already finalized.",
         "reasonCode" => "assignment_already_finalized"
       }}

  defp runner_assignment_error(reason) when is_binary(reason) do
    status =
      if reason in [
           "assignment_already_finalized",
           "assignment_canceled",
           "import_in_progress"
         ],
         do: 409,
         else: 400

    {status, %{"error" => assignment_error_message(reason), "reasonCode" => reason}}
  end

  defp runner_assignment_error(reason),
    do:
      {400, %{"error" => "Runner assignment request failed.", "reasonCode" => to_string(reason)}}

  defp assignment_error_message("assignment_already_finalized"),
    do: "Assignment is already finalized."

  defp assignment_error_message("assignment_canceled"), do: "Assignment was canceled."
  defp assignment_error_message("import_in_progress"), do: "Assignment import is already running."
  defp assignment_error_message("base_sha_mismatch"), do: "Patch base revision does not match."
  defp assignment_error_message("patch_digest_mismatch"), do: "Patch digest does not match."

  defp assignment_error_message("changed_files_mismatch"),
    do: "Changed files do not match the patch."

  defp assignment_error_message("changed_files_digest_mismatch"),
    do: "Changed-file digest does not match."

  defp assignment_error_message("protected_path_rejected"),
    do: "Patch modifies protected Symphonia metadata."

  defp assignment_error_message("empty_patch"), do: "Patch bundle is empty."
  defp assignment_error_message(reason), do: "Runner assignment failed: #{reason}."

  defp workspace_provider(payload) when is_map(payload) do
    payload["workspace_provider"] || payload["workspaceProvider"]
  end

  defp workspace_provider(_payload), do: nil

  defp execution_workspace_provider(payload) when is_map(payload) do
    if sandbox_execution_requested?(payload), do: "cloud_sandbox", else: nil
  end

  defp execution_workspace_provider(_payload), do: nil

  defp remote_execution_requested?(payload) when is_map(payload) do
    (payload["allowRemoteExecution"] == true or payload["allow_remote_execution"] == true) and
      is_binary(runner_id(payload)) and runner_id(payload) not in ["", "local-service"]
  end

  defp remote_execution_requested?(_payload), do: false

  defp path_parts(path) do
    path
    |> String.split("?", parts: 2)
    |> hd()
    |> String.trim_leading("/")
    |> String.split("/", trim: true)
    |> Enum.map(&URI.decode/1)
  end

  defp query_params(path) do
    case String.split(path, "?", parts: 2) do
      [_path, query] -> URI.decode_query(query)
      _ -> %{}
    end
  end

  defp send_json(client, status, payload) do
    body = JSON.encode!(payload)
    reason = reason(status)

    response = [
      "HTTP/1.1 #{status} #{reason}\r\n",
      "content-type: application/json\r\n",
      "access-control-allow-origin: *\r\n",
      "access-control-allow-methods: GET,POST,PATCH,DELETE,OPTIONS\r\n",
      "access-control-allow-headers: content-type,x-symphonia-actor,x-symphonia-actor-id,x-symphonia-role,x-runner-token\r\n",
      "content-length: #{byte_size(body)}\r\n",
      "\r\n",
      body
    ]

    :gen_tcp.send(client, response)
  end

  defp reason(200), do: "OK"
  defp reason(201), do: "Created"
  defp reason(202), do: "Accepted"
  defp reason(204), do: "No Content"
  defp reason(400), do: "Bad Request"
  defp reason(403), do: "Forbidden"
  defp reason(404), do: "Not Found"
  defp reason(405), do: "Method Not Allowed"
  defp reason(409), do: "Conflict"
  defp reason(429), do: "Too Many Requests"
  defp reason(502), do: "Bad Gateway"
  defp reason(_), do: "OK"

  defp decode_json(""), do: %{}
  defp decode_json(body), do: JSON.decode!(body)

  defp reject_nil(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)

  defp public_tasks(tasks), do: Enum.map(tasks, &public_task/1)

  defp ensure_default_workflow(repository) do
    unless Workspace.workflow(repository)["exists"] do
      Workspace.create_workflow_from_template(repository, "simple-pr")
    end

    :ok
  end

  defp spec_workspace_payload(repository) do
    %{
      "state" => SpecWorkspace.state(repository),
      "sections" => SpecWorkspace.sections(repository)
    }
  end

  defp private_workspace_payload(repository) do
    %{
      "state" => PrivateWorkspace.state(repository),
      "sections" => PrivateWorkspace.sections(repository),
      "legacy" => PrivateWorkspace.legacy_artifacts(repository),
      "evidence" => PrivateWorkspace.list_evidence(repository)
    }
  end

  defp public_spec_artifacts(artifacts_by_type) do
    artifacts_by_type
    |> Enum.map(fn {type, artifacts} ->
      {type, Enum.map(artifacts, &public_spec_artifact/1)}
    end)
    |> Map.new()
  end

  defp public_spec_artifact(artifact), do: Map.drop(artifact, ["body"])

  defp public_repository(repository) do
    workspace = Workspace.state(repository)
    task_count = repository |> TaskStore.list_tasks() |> length()

    repository
    |> Map.merge(%{
      "workspace" => workspace,
      "taskCount" => task_count,
      "github" => RepositoryLink.link(repository),
      "automation" => Automation.status(repository),
      "remoteExecutionAllowed" => RepositoryPolicy.remote_execution_allowed?(repository),
      "sandboxExecutionAllowed" => SandboxPolicy.allowed?(repository),
      "sandboxProvider" => SandboxPolicy.provider(repository),
      "sandboxProviderReadiness" => SymphoniaService.Sandbox.Registry.readiness(repository, nil),
      "allowedRunnerIds" => RepositoryPolicy.allowed_runner_ids(repository),
      "allowedSandboxProviders" => RepositoryPolicy.allowed_sandbox_providers(repository),
      "allowedCodingAssistantProviders" =>
        RepositoryPolicy.allowed_coding_assistant_providers(repository),
      "requireTrustedRunner" => true,
      "secretScopesAllowed" => RepositoryPolicy.secret_scopes_allowed(repository)
    })
  end

  defp public_task(task) do
    task
    |> Map.drop([:repository, :file_path, :frontmatter, :body])
  end
end
