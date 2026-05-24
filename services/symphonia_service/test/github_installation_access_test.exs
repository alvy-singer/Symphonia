defmodule SymphoniaService.GitHub.InstallationAccessTest do
  use ExUnit.Case

  alias SymphoniaService.GitHub.{AppAuth, Auth, InstallationStore, Repositories}

  defmodule StubClient do
    def get_app_installation(jwt, "123") do
      assert String.split(jwt, ".") |> length() == 3

      {:ok,
       %{
         "id" => 123,
         "account" => %{"login" => "agora-creations", "type" => "Organization"},
         "repository_selection" => "selected"
       }}
    end

    def create_installation_token(jwt, "123") do
      assert String.split(jwt, ".") |> length() == 3

      {:ok,
       %{
         "token" => "installation-token",
         "expires_at" =>
           DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()
       }}
    end

    def list_installation_repositories("installation-token", 1, 100) do
      repos =
        Enum.map(1..100, fn n ->
          %{
            "id" => n,
            "name" => "repo-#{n}",
            "full_name" => "agora-creations/repo-#{n}",
            "owner" => %{"login" => "agora-creations"},
            "html_url" => "https://github.com/agora-creations/repo-#{n}",
            "clone_url" => "https://github.com/agora-creations/repo-#{n}.git",
            "default_branch" => "main"
          }
        end)

      {:ok, %{"total_count" => 101, "repositories" => repos}}
    end

    def list_installation_repositories("installation-token", 2, 100) do
      {:ok,
       %{
         "total_count" => 101,
         "repositories" => [
           %{
             "id" => 101,
             "name" => "repo-101",
             "full_name" => "agora-creations/repo-101",
             "owner" => %{"login" => "agora-creations"},
             "html_url" => "https://github.com/agora-creations/repo-101",
             "clone_url" => "https://github.com/agora-creations/repo-101.git",
             "default_branch" => "main"
           }
         ]
       }}
    end
  end

  setup do
    root =
      Path.join(System.tmp_dir!(), "symphonia-install-test-#{System.unique_integer([:positive])}")

    github_home = Path.join(root, "github")
    private_key_path = Path.join(root, "github-app.pem")
    File.mkdir_p!(root)
    write_private_key!(private_key_path)

    previous_app_id = System.get_env("SYMPHONIA_GITHUB_APP_ID")
    previous_private_key = System.get_env("SYMPHONIA_GITHUB_APP_PRIVATE_KEY_PATH")
    previous_app_name = System.get_env("SYMPHONIA_GITHUB_APP_NAME")

    System.put_env("SYMPHONIA_GITHUB_APP_ID", "42")
    System.put_env("SYMPHONIA_GITHUB_APP_PRIVATE_KEY_PATH", private_key_path)
    System.put_env("SYMPHONIA_GITHUB_APP_NAME", "symphonia-test")
    Application.put_env(:symphonia_service, :github_client, StubClient)
    Application.put_env(:symphonia_service, :github_home, github_home)

    on_exit(fn ->
      restore_env("SYMPHONIA_GITHUB_APP_ID", previous_app_id)
      restore_env("SYMPHONIA_GITHUB_APP_PRIVATE_KEY_PATH", previous_private_key)
      restore_env("SYMPHONIA_GITHUB_APP_NAME", previous_app_name)
      Application.delete_env(:symphonia_service, :github_client)
      Application.delete_env(:symphonia_service, :github_home)
      File.rm_rf(root)
    end)

    %{github_home: github_home}
  end

  test "GitHub App JWT contains app claims and install URL is app based" do
    [_header, claims, _signature] = String.split(AppAuth.jwt(), ".")

    decoded_claims =
      claims
      |> Base.url_decode64!(padding: false)
      |> JSON.decode!()

    assert decoded_claims["iss"] == "42"
    assert decoded_claims["exp"] > decoded_claims["iat"]
    assert AppAuth.install_url() == "https://github.com/apps/symphonia-test/installations/new"
  end

  test "installation completion stores paginated installed repositories", %{
    github_home: github_home
  } do
    state = Repositories.complete_installation(%{"installation_id" => "123"})

    assert state["installedRepositoriesCount"] == 101

    assert InstallationStore.find_repository("agora-creations", "repo-101")["installationId"] ==
             "123"

    stored = File.read!(Path.join(github_home, "installations.json"))
    assert stored =~ "repo-101"
    refute stored =~ "installation-token"
  end

  test "token resolver prefers installation access for installed repositories" do
    Repositories.complete_installation(%{"installation_id" => "123"})

    assert Auth.token_for_repository("agora-creations", "repo-1") == "installation-token"
  end

  defp write_private_key!(path) do
    key = :public_key.generate_key({:rsa, 1024, 65_537})
    entry = :public_key.pem_entry_encode(:RSAPrivateKey, key)
    File.write!(path, :public_key.pem_encode([entry]))
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
