defmodule SymphoniaService.Sandbox.OpenSandboxClient do
  @moduledoc """
  Minimal dependency-free OpenSandbox HTTP client.

  The provider uses this through an Application env override in tests. Public
  callers should not consume this module directly.
  """

  @json_headers [{"content-type", "application/json"}, {"accept", "application/json"}]

  def create(config, body) do
    request(:post, url(config, "/sandboxes"), lifecycle_headers(config), JSON.encode!(body))
  end

  def get(config, sandbox_id) do
    request(:get, url(config, "/sandboxes/#{URI.encode(sandbox_id)}"), lifecycle_headers(config))
  end

  def delete(config, sandbox_id) do
    case request(:delete, url(config, "/sandboxes/#{URI.encode(sandbox_id)}"), lifecycle_headers(config)) do
      {:ok, _body} -> :ok
      {:error, :not_found} -> :ok
      error -> error
    end
  end

  def endpoint(config, sandbox_id, port \\ 44_772) do
    request(
      :get,
      url(config, "/sandboxes/#{URI.encode(sandbox_id)}/endpoints/#{port}"),
      lifecycle_headers(config)
    )
  end

  def upload_file(execd, path, content) when is_binary(path) and is_binary(content) do
    boundary = "symphonia-opensandbox-#{System.unique_integer([:positive])}"

    body =
      [
        "--#{boundary}\r\n",
        "content-disposition: form-data; name=\"metadata\"\r\n",
        "content-type: application/json\r\n\r\n",
        JSON.encode!(%{"path" => path, "mode" => 420}),
        "\r\n--#{boundary}\r\n",
        "content-disposition: form-data; name=\"file\"; filename=\"#{Path.basename(path)}\"\r\n",
        "content-type: application/octet-stream\r\n\r\n",
        content,
        "\r\n--#{boundary}--\r\n"
      ]
      |> IO.iodata_to_binary()

    headers =
      execd_headers(execd) ++
        [{"content-type", "multipart/form-data; boundary=#{boundary}"}]

    case request(:post, execd_url(execd, "/files/upload"), headers, body, decode: false) do
      {:ok, _body} -> :ok
      error -> error
    end
  end

  def run_command(execd, command, opts \\ []) do
    body =
      %{
        "command" => command,
        "cwd" => Keyword.get(opts, :cwd, "/workspace"),
        "background" => false,
        "timeout" => Keyword.get(opts, :timeout_ms, 900_000)
      }
      |> JSON.encode!()

    request(:post, execd_url(execd, "/command"), execd_headers(execd) ++ @json_headers, body,
      decode: false,
      timeout: Keyword.get(opts, :timeout_ms, 900_000) + 5_000
    )
  end

  def download_file(execd, path) when is_binary(path) do
    query = URI.encode_query(%{"path" => path})
    request(:get, execd_url(execd, "/files/download?#{query}"), execd_headers(execd), decode: false)
  end

  defp request(method, url, headers, body \\ "", opts \\ []) do
    :inets.start()
    :ssl.start()

    timeout = Keyword.get(opts, :timeout, 30_000)
    decode? = Keyword.get(opts, :decode, true)

    request =
      case method do
        :get -> {String.to_charlist(url), normalize_headers(headers)}
        :delete -> {String.to_charlist(url), normalize_headers(headers)}
        :post -> {String.to_charlist(url), normalize_headers(headers), content_type(headers), body}
      end

    case :httpc.request(method, request, [timeout: timeout, connect_timeout: 5_000], body_format: :binary) do
      {:ok, {{_version, status, _reason}, _headers, response_body}} when status in 200..299 ->
        decode_body(response_body, decode?)

      {:ok, {{_version, 404, _reason}, _headers, _response_body}} ->
        {:error, :not_found}

      {:ok, {{_version, status, _reason}, _headers, _response_body}} ->
        {:error, http_reason(status)}

      {:error, _reason} ->
        {:error, "opensandbox_request_failed"}
    end
  rescue
    _error -> {:error, "opensandbox_request_failed"}
  end

  defp decode_body(body, false), do: {:ok, body}

  defp decode_body(body, true) do
    case JSON.decode(body || "") do
      {:ok, value} -> {:ok, value}
      _other -> {:ok, %{}}
    end
  end

  defp lifecycle_headers(config) do
    [{"OPEN-SANDBOX-API-KEY", config["apiKey"] || ""}] ++ @json_headers
  end

  defp execd_headers(execd) do
    token = execd["accessToken"] || execd["access_token"]
    base = execd["headers"] || %{}

    base
    |> Enum.map(fn {key, value} -> {to_string(key), to_string(value)} end)
    |> maybe_put_execd_token(token)
  end

  defp maybe_put_execd_token(headers, token) when is_binary(token) and token != "" do
    if Enum.any?(headers, fn {key, _value} -> String.downcase(key) == "x-execd-access-token" end) do
      headers
    else
      [{"X-EXECD-ACCESS-TOKEN", token} | headers]
    end
  end

  defp maybe_put_execd_token(headers, _token), do: headers

  defp content_type(headers) do
    headers
    |> Enum.find_value("application/json", fn {key, value} ->
      if String.downcase(to_string(key)) == "content-type", do: value
    end)
  end

  defp normalize_headers(headers) do
    Enum.map(headers, fn {key, value} -> {String.to_charlist(key), String.to_charlist(value)} end)
  end

  defp url(config, path), do: config["lifecycleUrl"] <> path

  defp execd_url(execd, path) do
    execd["url"]
    |> String.trim_trailing("/")
    |> Kernel.<>(path)
  end

  defp http_reason(400), do: "opensandbox_bad_request"
  defp http_reason(401), do: "opensandbox_unauthorized"
  defp http_reason(403), do: "opensandbox_forbidden"
  defp http_reason(409), do: "opensandbox_conflict"
  defp http_reason(_status), do: "opensandbox_request_failed"
end
