defmodule SymphoniaService.GitHub.Client do
  @moduledoc """
  Thin dependency-free GitHub HTTP client.

  Supports GitHub App installation tokens as the primary access model and
  device-flow user tokens as a development fallback.
  """

  @api_version "2022-11-28"
  @device_code_url "https://github.com/login/device/code"
  @oauth_token_url "https://github.com/login/oauth/access_token"

  def request_device_code(client_id) do
    post_form(@device_code_url, %{"client_id" => client_id})
  end

  def poll_device_code(client_id, device_code) do
    post_form(@oauth_token_url, %{
      "client_id" => client_id,
      "device_code" => device_code,
      "grant_type" => "urn:ietf:params:oauth:grant-type:device_code"
    })
  end

  def refresh_user_token(client_id, client_secret, refresh_token) do
    post_form(@oauth_token_url, %{
      "client_id" => client_id,
      "client_secret" => client_secret,
      "grant_type" => "refresh_token",
      "refresh_token" => refresh_token
    })
  end

  def get_user(token), do: api(:get, "/user", token)

  def list_installations(token), do: api(:get, "/user/installations", token)

  def list_user_installation_repositories(token, installation_id) do
    api(:get, "/user/installations/#{installation_id}/repositories", token)
  end

  def get_app_installation(jwt, installation_id) do
    api(:get, "/app/installations/#{encode(installation_id)}", jwt)
  end

  def create_installation_token(jwt, installation_id) do
    api(:post, "/app/installations/#{encode(installation_id)}/access_tokens", jwt, %{})
  end

  def list_installation_repositories(token, page \\ 1, per_page \\ 100) do
    api(:get, "/installation/repositories?per_page=#{per_page}&page=#{page}", token)
  end

  def get_repository(token, owner, repo) do
    api(:get, "/repos/#{encode(owner)}/#{encode(repo)}", token)
  end

  def get_branch(token, owner, repo, branch) do
    api(:get, "/repos/#{encode(owner)}/#{encode(repo)}/branches/#{encode(branch)}", token)
  end

  def create_pull_request(token, owner, repo, payload) do
    api(:post, "/repos/#{encode(owner)}/#{encode(repo)}/pulls", token, payload)
  end

  def get_pull_request(token, owner, repo, number) do
    api(:get, "/repos/#{encode(owner)}/#{encode(repo)}/pulls/#{number}", token)
  end

  def update_issue(token, owner, repo, number, payload) do
    api(:patch, "/repos/#{encode(owner)}/#{encode(repo)}/issues/#{number}", token, payload)
  end

  defp api(method, path, token, payload \\ nil) do
    url = api_base() <> path

    headers = [
      {~c"accept", ~c"application/vnd.github+json"},
      {~c"authorization", to_charlist("Bearer #{token}")},
      {~c"user-agent", ~c"Symphonia"},
      {~c"x-github-api-version", to_charlist(@api_version)}
    ]

    request =
      if is_nil(payload) do
        {to_charlist(url), headers}
      else
        body = JSON.encode!(payload)

        {to_charlist(url), [{~c"content-type", ~c"application/json"} | headers],
         ~c"application/json", body}
      end

    http_request(method, request)
  end

  defp post_form(url, params) do
    headers = [
      {~c"accept", ~c"application/json"},
      {~c"user-agent", ~c"Symphonia"},
      {~c"content-type", ~c"application/x-www-form-urlencoded"}
    ]

    http_request(
      :post,
      {to_charlist(url), headers, ~c"application/x-www-form-urlencoded", URI.encode_query(params)}
    )
  end

  defp http_request(method, request) do
    ensure_started()

    case :httpc.request(method, request, [], body_format: :binary) do
      {:ok, {{_version, status, _reason}, _headers, body}} ->
        decode_response(status, body)

      {:error, reason} ->
        {:error, %{"message" => "GitHub is unavailable.", "reason" => inspect(reason)}}
    end
  end

  defp decode_response(status, body) when status in 200..299 do
    {:ok, decode_json(body)}
  end

  defp decode_response(status, body) do
    payload =
      body
      |> decode_json()
      |> Map.put_new("message", "GitHub request failed.")
      |> Map.put("status", status)

    {:error, payload}
  end

  defp decode_json(""), do: %{}

  defp decode_json(body) do
    JSON.decode!(body)
  rescue
    _ -> %{"message" => body}
  end

  defp ensure_started do
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)
  end

  defp api_base do
    System.get_env("SYMPHONIA_GITHUB_API_URL") || "https://api.github.com"
  end

  defp encode(value), do: URI.encode(to_string(value), &URI.char_unreserved?/1)
end
