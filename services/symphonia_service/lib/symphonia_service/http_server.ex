defmodule SymphoniaService.HTTPServer do
  @moduledoc """
  Tiny dependency-free HTTP server for the local Symphonia service API.
  """

  use GenServer

  alias SymphoniaService.TaskStore

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name))
  end

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, 4057)
    root = Keyword.get(opts, :root, SymphoniaService.default_repositories_root())

    {:ok, socket} =
      :gen_tcp.listen(port, [:binary, packet: :raw, active: false, reuseaddr: true])

    send(self(), :accept)
    {:ok, %{socket: socket, root: root, port: port}}
  end

  @impl true
  def handle_info(:accept, state) do
    {:ok, client} = :gen_tcp.accept(state.socket)
    Task.start(fn -> serve(client, state.root) end)
    send(self(), :accept)
    {:noreply, state}
  end

  defp serve(client, root) do
    with {:ok, raw} <- :gen_tcp.recv(client, 0, 5_000),
         {:ok, request} <- parse_request(raw) do
      {status, payload} = route(request, root)
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

  defp route(%{method: "OPTIONS"}, _root), do: {204, %{}}

  defp route(%{method: "GET", path: "/api/repositories"}, root) do
    {200, %{"repositories" => TaskStore.list_repositories(root)}}
  end

  defp route(%{method: "GET", path: path}, root) do
    case path_parts(path) do
      ["api", "repositories", repo, "tasks"] ->
        {200, %{"tasks" => public_tasks(TaskStore.list_tasks(root, repo))}}

      ["api", "repositories", repo, "tasks", task_key] ->
        case TaskStore.get_task(root, repo, task_key) do
          nil -> {404, %{"error" => "Task not found"}}
          task -> {200, %{"task" => public_task(task)}}
        end

      _ ->
        {404, %{"error" => "Not found"}}
    end
  end

  defp route(%{method: "PATCH", path: path, body: body}, root) do
    case path_parts(path) do
      ["api", "repositories", repo, "tasks", task_key] ->
        patch = decode_json(body)
        task = TaskStore.patch_task(root, repo, task_key, patch)
        {200, %{"task" => public_task(task)}}

      _ ->
        {404, %{"error" => "Not found"}}
    end
  rescue
    error -> {400, %{"error" => Exception.message(error)}}
  end

  defp route(%{method: "POST", path: path, body: body}, root) do
    case path_parts(path) do
      ["api", "repositories", repo, "tasks", task_key, "events"] ->
        payload = decode_json(body)
        event = Map.fetch!(payload, "event")
        params = Map.get(payload, "params", %{})
        task = TaskStore.apply_event(root, repo, task_key, event, params)
        {200, %{"task" => public_task(task)}}

      _ ->
        {404, %{"error" => "Not found"}}
    end
  rescue
    error -> {400, %{"error" => Exception.message(error)}}
  end

  defp route(_request, _root), do: {405, %{"error" => "Method not allowed"}}

  defp path_parts(path) do
    path
    |> String.split("?", parts: 2)
    |> hd()
    |> String.trim_leading("/")
    |> String.split("/", trim: true)
    |> Enum.map(&URI.decode/1)
  end

  defp send_json(client, status, payload) do
    body = JSON.encode!(payload)
    reason = reason(status)

    response = [
      "HTTP/1.1 #{status} #{reason}\r\n",
      "content-type: application/json\r\n",
      "access-control-allow-origin: *\r\n",
      "access-control-allow-methods: GET,POST,PATCH,OPTIONS\r\n",
      "access-control-allow-headers: content-type\r\n",
      "content-length: #{byte_size(body)}\r\n",
      "\r\n",
      body
    ]

    :gen_tcp.send(client, response)
  end

  defp reason(200), do: "OK"
  defp reason(204), do: "No Content"
  defp reason(400), do: "Bad Request"
  defp reason(404), do: "Not Found"
  defp reason(405), do: "Method Not Allowed"
  defp reason(_), do: "OK"

  defp decode_json(""), do: %{}
  defp decode_json(body), do: JSON.decode!(body)

  defp public_tasks(tasks), do: Enum.map(tasks, &public_task/1)

  defp public_task(task) do
    task
    |> Map.drop([:repositories_root, :file_path, :frontmatter, :body])
  end
end
