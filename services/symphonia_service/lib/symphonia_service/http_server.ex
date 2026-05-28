defmodule SymphoniaService.HTTPServer do
  @moduledoc """
  Tiny dependency-free HTTP server for the local Symphonia service API.
  """

  use GenServer

  alias SymphoniaService.{
    CodingAssistant,
    RepositoryRegistry,
    SpecWorkspace,
    TaskStore,
    Workspace
  }

  alias SymphoniaService.Clarise.{ArtifactExtractor, MilestoneLoop, PlanToTaskCompiler}
  alias SymphoniaService.GitHub.{Auth, PullRequests, Repositories, RepositoryLink, Sync}
  alias SymphoniaService.Harness.{Automation, Daemon, Eligibility}

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
      {status, payload} = route(request, registry_path)
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

  defp route(%{method: "OPTIONS"}, _registry_path), do: {204, %{}}

  defp route(%{method: "GET", path: "/healthz"}, _registry_path) do
    {200, %{"ok" => true}}
  end

  defp route(%{method: "GET", path: "/api/repositories"}, registry_path) do
    repositories =
      registry_path
      |> RepositoryRegistry.list()
      |> Enum.map(&public_repository/1)

    {200, %{"repositories" => repositories}}
  end

  defp route(%{method: "GET", path: "/api/github/connection"}, _registry_path) do
    {200, %{"connection" => Auth.connection()}}
  end

  defp route(%{method: "GET", path: "/api/github/repositories"}, _registry_path) do
    {200, RepositoryLink.accessible_repositories()}
  rescue
    error -> {400, %{"error" => Exception.message(error)}}
  end

  defp route(%{method: "POST", path: "/api/repositories", body: body}, registry_path) do
    repository = registry_path |> RepositoryRegistry.add(decode_json(body)) |> public_repository()
    {201, %{"repository" => repository}}
  rescue
    error -> {400, %{"error" => Exception.message(error)}}
  end

  defp route(%{method: "GET", path: path}, registry_path) do
    case path_parts(path) do
      ["api", "repositories", repo, "workspace"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        {200, %{"repo" => repository["key"], "workspace" => Workspace.state(repository)}}

      ["api", "repositories", repo, "spec-workspace"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        {200,
         %{"repo" => repository["key"], "specWorkspace" => spec_workspace_payload(repository)}}

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

  defp route(%{method: "PATCH", path: path, body: body}, registry_path) do
    case path_parts(path) do
      ["api", "repositories", repo, "workflow"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        payload = decode_json(body)
        workflow = Workspace.update_workflow(repository, Map.get(payload, "body", ""))
        {200, %{"repo" => repository["key"], "workflow" => workflow}}

      ["api", "repositories", repo, "spec-workspace", "artifacts", type, id] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        artifact = SpecWorkspace.update_artifact(repository, type, id, decode_json(body))
        {200, %{"artifact" => artifact}}

      ["api", "repositories", repo, "tasks", task_key] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        patch = decode_json(body)
        task = TaskStore.patch_task(repository, task_key, patch)
        {200, %{"task" => public_task(task)}}

      _ ->
        {404, %{"error" => "Not found"}}
    end
  rescue
    error -> {400, %{"error" => Exception.message(error)}}
  end

  defp route(%{method: "DELETE", path: path}, registry_path) do
    case path_parts(path) do
      ["api", "repositories", repo] ->
        repository = RepositoryRegistry.remove(registry_path, repo)
        {200, %{"repository" => public_repository(repository)}}

      _ ->
        {404, %{"error" => "Not found"}}
    end
  rescue
    error -> {400, %{"error" => Exception.message(error)}}
  end

  defp route(%{method: "POST", path: path, body: body}, registry_path) do
    case path_parts(path) do
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
        workspace = Workspace.initialize(repository)
        {200, %{"repo" => repository["key"], "workspace" => workspace}}

      ["api", "repositories", repo, "spec-workspace", "initialize"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        SpecWorkspace.initialize(repository)

        {200,
         %{"repo" => repository["key"], "specWorkspace" => spec_workspace_payload(repository)}}

      ["api", "repositories", repo, "spec-workspace", "milestones"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        artifact = SpecWorkspace.create_milestone(repository, decode_json(body))
        {201, %{"artifact" => artifact}}

      ["api", "repositories", repo, "spec-workspace", "requirements"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        artifact = SpecWorkspace.create_requirement(repository, decode_json(body))
        {201, %{"artifact" => artifact}}

      ["api", "repositories", repo, "spec-workspace", "plans"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        artifact = SpecWorkspace.create_plan(repository, decode_json(body))
        {201, %{"artifact" => artifact}}

      ["api", "repositories", repo, "spec-workspace", "decisions"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        artifact = SpecWorkspace.create_decision(repository, decode_json(body))
        {201, %{"artifact" => artifact}}

      ["api", "repositories", repo, "spec-workspace", "task-briefs"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        artifact = SpecWorkspace.create_task_brief(repository, decode_json(body))
        {201, %{"artifact" => artifact}}

      ["api", "repositories", repo, "clarise", "extract"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        {200, ArtifactExtractor.extract(repository, decode_json(body))}

      ["api", "repositories", repo, "clarise", "milestones", "start"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        {201, MilestoneLoop.start(repository, decode_json(body))}

      ["api", "repositories", repo, "clarise", "milestones", milestone, "discuss"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        {200, MilestoneLoop.discuss(repository, milestone, decode_json(body))}

      ["api", "repositories", repo, "clarise", "milestones", milestone, "requirements"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        {201, MilestoneLoop.requirements(repository, milestone, decode_json(body))}

      ["api", "repositories", repo, "clarise", "milestones", milestone, "plan"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        {201, MilestoneLoop.plan(repository, milestone, decode_json(body))}

      ["api", "repositories", repo, "clarise", "milestones", milestone, "decisions"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        {201, MilestoneLoop.decision(repository, milestone, decode_json(body))}

      ["api", "repositories", repo, "clarise", "milestones", milestone, "approve"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        {200, MilestoneLoop.approve(repository, milestone, decode_json(body))}

      ["api", "repositories", repo, "clarise", "milestones", milestone, "tasks", "propose"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        {201, PlanToTaskCompiler.propose(repository, milestone, decode_json(body))}

      ["api", "repositories", repo, "clarise", "milestones", milestone, "tasks", "create"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

        {201,
         PlanToTaskCompiler.create_tasks(registry_path, repository, milestone, decode_json(body))}

      ["api", "repositories", repo, "github", "link"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        github = RepositoryLink.link(registry_path, repository, decode_json(body))
        {200, %{"repo" => repository["key"], "github" => github}}

      ["api", "repositories", repo, "automation", "enable"] ->
        repository = Automation.enable(registry_path, repo, decode_json(body))
        {200, %{"repo" => repository["key"], "automation" => Automation.status(repository)}}

      ["api", "repositories", repo, "automation", "disable"] ->
        repository = Automation.disable(registry_path, repo)
        {200, %{"repo" => repository["key"], "automation" => Automation.status(repository)}}

      ["api", "harness", "daemon", "tick"] ->
        Daemon.ensure_started(registry_path)
        {200, Daemon.tick()}

      ["api", "repositories", repo, "workflow", "from-template"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        payload = decode_json(body)

        template_id =
          Map.get(payload, "template") || Map.get(payload, "templateId") || Map.get(payload, "id")

        workflow = Workspace.create_workflow_from_template(repository, template_id)
        {201, %{"repo" => repository["key"], "workflow" => workflow}}

      ["api", "repositories", repo, "tasks"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        task = TaskStore.create_task(registry_path, repository, decode_json(body))
        {201, %{"task" => public_task(task)}}

      ["api", "repositories", repo, "tasks", task_key, "events"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        payload = decode_json(body)
        event = Map.fetch!(payload, "event")
        params = Map.get(payload, "params", %{})
        task = TaskStore.apply_event(repository, task_key, event, params)
        {200, %{"task" => public_task(task)}}

      ["api", "repositories", repo, "tasks", task_key, "coding-assistant", "runs"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        result = CodingAssistant.start_run(registry_path, repository, task_key, decode_json(body))
        {201, %{"run" => result["run"], "task" => public_task(result["task"])}}

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
        result = CodingAssistant.cancel_run(repository, task_key, run_id)

        {200,
         %{
           "run" => result["run"],
           "task" => result["task"] && public_task(result["task"])
         }}

      ["api", "repositories", repo, "tasks", task_key, "review", "request-changes"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)

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

      ["api", "repositories", repo, "tasks", task_key, "open-pull-request"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        task = PullRequests.open_from_task(repository, task_key)
        {200, %{"task" => public_task(task)}}

      ["api", "repositories", repo, "tasks", task_key, "refresh-pr"] ->
        repository = RepositoryRegistry.get!(registry_path, repo)
        task = Sync.refresh_pull_request(repository, task_key)
        {200, %{"task" => public_task(task)}}

      _ ->
        {404, %{"error" => "Not found"}}
    end
  rescue
    error -> {400, %{"error" => Exception.message(error)}}
  end

  defp route(_request, _registry_path), do: {405, %{"error" => "Method not allowed"}}

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
      "access-control-allow-headers: content-type\r\n",
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
  defp reason(404), do: "Not Found"
  defp reason(405), do: "Method Not Allowed"
  defp reason(429), do: "Too Many Requests"
  defp reason(502), do: "Bad Gateway"
  defp reason(_), do: "OK"

  defp decode_json(""), do: %{}
  defp decode_json(body), do: JSON.decode!(body)

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
