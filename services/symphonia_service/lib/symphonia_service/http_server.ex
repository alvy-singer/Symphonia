defmodule SymphoniaService.HTTPServer do
  @moduledoc """
  Tiny dependency-free HTTP server for the local Symphonia service API.
  """

  use GenServer

  alias SymphoniaService.{
    CodingAssistant,
    MarkdownPages,
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
  alias SymphoniaService.Runners.{Capabilities, Registry, SelectionPolicy}

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

  defp route(%{method: "GET", path: path}, registry_path, actor) do
    case path_parts(path) do
      ["api", "runners"] ->
        guarded_read(registry_path, actor, global_repository(), "runner.view", fn ->
          audit_runner_transitions(registry_path, actor)
          {200, %{"runners" => Registry.list(registry_path)}}
        end)

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
        repository = RepositoryRegistry.get!(registry_path, repo)

        {200,
         %{
           "repo" => repository["key"],
           "readiness" => RepositoryReadiness.get(repository, registry_path: registry_path)
         }}

      ["api", "repositories", repo, "spec-workspace"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        {200,
         %{"repo" => repository["key"], "specWorkspace" => spec_workspace_payload(repository)}}

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
        repository = RepositoryRegistry.get!(registry_path, repo)
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
        repository = RepositoryRegistry.get!(registry_path, repo)

        artifacts =
          repository
          |> SpecWorkspace.list_artifacts(type)
          |> Enum.map(&public_spec_artifact/1)

        {200, %{"type" => type, "artifacts" => artifacts}}

      ["api", "repositories", repo, "spec-workspace", "artifacts", type, id] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        {200, %{"artifact" => SpecWorkspace.read_artifact(repository, type, id)}}

      ["api", "github", "installations", "callback"] ->
        github = Repositories.complete_installation(query_params(path))
        {200, %{"connection" => Auth.connection(), "github" => github}}

      ["api", "repositories", repo, "github"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        {200, %{"repo" => repository["key"], "github" => RepositoryLink.state(repository)}}

      ["api", "repositories", repo, "automation"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        {200, %{"repo" => repository["key"], "automation" => Automation.status(repository)}}

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
        repository = RepositoryRegistry.get!(registry_path, repo)

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

      _ ->
        {404, %{"error" => "Not found"}}
    end
  rescue
    error -> {400, %{"error" => Exception.message(error)}}
  end

  defp route(%{method: "POST", path: path, body: body}, registry_path, actor) do
    case path_parts(path) do
      ["api", "runners", "register"] ->
        guarded_runner_action(registry_path, actor, "runner.register", runner_target(), fn ->
          {:ok, runner} = Registry.register(registry_path, actor, decode_json(body))
          public = Registry.public(runner)

          {201, %{"runner" => public}, runner_target(public["id"]), runner_metadata(public)}
        end)

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

          {:error, :not_found} ->
            {404, %{"error" => "Runner not found.", "reasonCode" => "runner_not_found"}}

          {:error, _reason} ->
            {400, %{"error" => "Invalid runner heartbeat.", "reasonCode" => "invalid_heartbeat"}}
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

              {:error, :local_service_immutable} ->
                {400,
                 %{
                   "error" => "Local service runner cannot be disabled in V1.",
                   "reasonCode" => "local_service_immutable"
                 }, runner_target(runner_id),
                 %{"runnerId" => runner_id, "runnerMode" => "local_service"}}

              {:error, :not_found} ->
                {404, %{"error" => "Runner not found.", "reasonCode" => "runner_not_found"},
                 runner_target(runner_id),
                 %{"runnerId" => runner_id, "runnerMode" => "remote_runner"}}
            end
          end
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

              {:error, :local_service_immutable} ->
                {400,
                 %{
                   "error" => "Local service runner cannot be enabled in V1.",
                   "reasonCode" => "local_service_immutable"
                 }, runner_target(runner_id),
                 %{"runnerId" => runner_id, "runnerMode" => "local_service"}}

              {:error, :not_found} ->
                {404, %{"error" => "Runner not found.", "reasonCode" => "runner_not_found"},
                 runner_target(runner_id),
                 %{"runnerId" => runner_id, "runnerMode" => "remote_runner"}}
            end
          end
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
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(registry_path, actor, repository, "workspace.initialize", workflow_target(), fn ->
          SpecWorkspace.initialize(repository)

          {200,
           %{"repo" => repository["key"], "specWorkspace" => spec_workspace_payload(repository)}}
        end)

      ["api", "repositories", repo, "readiness", "spec-workspace", "initialize"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(registry_path, actor, repository, "workspace.initialize", workflow_target(), fn ->
          readiness =
            SetupActions.initialize_spec_workspace(repository, registry_path: registry_path)

          {200, %{"repo" => repository["key"], "readiness" => readiness}}
        end)

      ["api", "repositories", repo, "spec-workspace", "artifacts", type] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(registry_path, actor, repository, "repository.configure", workflow_target(), fn ->
          artifact = SpecWorkspace.create_artifact(repository, type, decode_json(body))
          {201, %{"artifact" => artifact}}
        end)

      ["api", "repositories", repo, "spec-workspace", "milestones"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(registry_path, actor, repository, "repository.configure", workflow_target(), fn ->
          artifact = SpecWorkspace.create_milestone(repository, decode_json(body))
          {201, %{"artifact" => artifact}}
        end)

      ["api", "repositories", repo, "spec-workspace", "requirements"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(registry_path, actor, repository, "repository.configure", workflow_target(), fn ->
          artifact = SpecWorkspace.create_requirement(repository, decode_json(body))
          {201, %{"artifact" => artifact}}
        end)

      ["api", "repositories", repo, "spec-workspace", "plans"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(registry_path, actor, repository, "repository.configure", workflow_target(), fn ->
          artifact = SpecWorkspace.create_plan(repository, decode_json(body))
          {201, %{"artifact" => artifact}}
        end)

      ["api", "repositories", repo, "spec-workspace", "decisions"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(registry_path, actor, repository, "repository.configure", workflow_target(), fn ->
          artifact = SpecWorkspace.create_decision(repository, decode_json(body))
          {201, %{"artifact" => artifact}}
        end)

      ["api", "repositories", repo, "spec-workspace", "task-briefs"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(registry_path, actor, repository, "repository.configure", workflow_target(), fn ->
          artifact = SpecWorkspace.create_task_brief(repository, decode_json(body))
          {201, %{"artifact" => artifact}}
        end)

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
        repository = RepositoryRegistry.get!(registry_path, repo)
        {200, ArtifactExtractor.extract(repository, decode_json(body))}

      ["api", "repositories", repo, "clarise", "milestones", "start"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        guarded(registry_path, actor, repository, "repository.configure", workflow_target(), fn ->
          {201, MilestoneLoop.start(repository, decode_json(body))}
        end)

      ["api", "repositories", repo, "clarise", "milestones", milestone, "discuss"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

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
        repository = RepositoryRegistry.get!(registry_path, repo)

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
        repository = RepositoryRegistry.get!(registry_path, repo)

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
        repository = RepositoryRegistry.get!(registry_path, repo)

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
        repository = RepositoryRegistry.get!(registry_path, repo)

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
        repository = RepositoryRegistry.get!(registry_path, repo)

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
        repository = RepositoryRegistry.get!(registry_path, repo)

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
          if experimental_run?(payload),
            do: "workspace_provider.experimental_run",
            else: "task.run_codex"

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
            result = CodingAssistant.cancel_run(repository, task_key, run_id)

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
    metadata = %{"taskKey" => task_key, "workspaceProvider" => workspace_provider(payload)}

    case Policy.authorize(actor, permission, repository, task_target(task_key)) do
      :ok ->
        with {:ok, runner} <-
               SelectionPolicy.select_for_run(registry_path, repository, actor,
                 runner_id: runner_id(payload),
                 workspace_provider: workspace_provider(payload) || "local_git_worktree",
                 allow_remote_execution: false
               ) do
          try do
            result =
              CodingAssistant.start_run(
                registry_path,
                repository,
                task_key,
                Map.put(payload, "runner", runner)
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

  defp guarded_runner_action(registry_path, actor, action, target, fun)
       when is_function(fun, 0) do
    repository = global_repository()

    case Policy.authorize(actor, action, repository, target) do
      :ok ->
        try do
          {status, payload, event_target, metadata} = fun.()
          result = if status in 200..299, do: "completed", else: "failed"

          AuditLog.record(registry_path, repository, %{
            "actor" => actor,
            "action" => action,
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

  defp guarded(registry_path, actor, repository, permission, target, fun, metadata \\ %{})
       when is_function(fun, 0) do
    case Policy.authorize(actor, permission, repository, target) do
      :ok ->
        try do
          {status, payload} = fun.()

          AuditLog.record(registry_path, repository, %{
            "actor" => actor,
            "action" => permission,
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
  defp workflow_target(id \\ nil), do: %{"type" => "workflow", "id" => id}
  defp harness_target, do: %{"type" => "harness"}
  defp task_target(task_key), do: %{"type" => "task", "id" => task_key}
  defp runner_target(id \\ nil), do: %{"type" => "runner", "id" => id}
  defp global_repository, do: %{"key" => "GLOBAL"}

  defp runner_metadata(runner) do
    %{
      "runnerId" => runner["id"],
      "runnerMode" => runner["mode"],
      "capabilitySummary" => Capabilities.summary(runner["capabilities"])
    }
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

  defp runner_id(payload) when is_map(payload), do: payload["runnerId"] || payload["runner_id"]
  defp runner_id(_payload), do: nil

  defp workspace_provider(payload) when is_map(payload) do
    payload["workspace_provider"] || payload["workspaceProvider"]
  end

  defp workspace_provider(_payload), do: nil

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
      "access-control-allow-headers: content-type,x-symphonia-actor,x-symphonia-actor-id,x-symphonia-role\r\n",
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
      "automation" => Automation.status(repository)
    })
  end

  defp public_task(task) do
    task
    |> Map.drop([:repository, :file_path, :frontmatter, :body])
  end
end
