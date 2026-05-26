defmodule SymphoniaService.GitHub.DeviceFallbackTest do
  use ExUnit.Case

  alias SymphoniaService.GitHub.{Auth, InstallationStore}

  setup do
    previous = System.get_env("SYMPHONIA_GITHUB_ALLOW_DEVICE_FALLBACK")
    previous_github_token = System.get_env("GITHUB_TOKEN")
    previous_gh_token = System.get_env("GH_TOKEN")
    System.delete_env("SYMPHONIA_GITHUB_ALLOW_DEVICE_FALLBACK")
    System.delete_env("GITHUB_TOKEN")
    System.delete_env("GH_TOKEN")
    Application.delete_env(:symphonia_service, :github_allow_device_fallback)

    on_exit(fn ->
      if previous,
        do: System.put_env("SYMPHONIA_GITHUB_ALLOW_DEVICE_FALLBACK", previous),
        else: System.delete_env("SYMPHONIA_GITHUB_ALLOW_DEVICE_FALLBACK")

      Application.delete_env(:symphonia_service, :github_allow_device_fallback)
      restore_env("GITHUB_TOKEN", previous_github_token)
      restore_env("GH_TOKEN", previous_gh_token)
    end)
  end

  test "device flow fallback is hidden and disabled unless explicitly configured" do
    connection = Auth.connection()

    refute connection["deviceFallbackEnabled"]

    assert_raise ArgumentError, "GitHub device flow fallback is disabled.", fn ->
      Auth.start_device_flow()
    end
  end

  test "missing installation returns plain product setup error" do
    assert_raise ArgumentError, Auth.install_error(), fn ->
      Auth.token_for_repository("agora-creations", "symphonia")
    end
  end

  test "explicit local fallback can use environment GitHub token" do
    System.put_env("SYMPHONIA_GITHUB_ALLOW_DEVICE_FALLBACK", "true")
    System.put_env("GITHUB_TOKEN", "ghp_local_token")

    assert Auth.connection()["connected"] == true
    assert Auth.connection()["deviceFallbackEnabled"] == true
    assert Auth.token_for_repository("agora-creations", "symphonia") == "ghp_local_token"
  end

  test "installed repository falls back to environment token when app config is absent" do
    root =
      Path.join(
        System.tmp_dir!(),
        "symphonia-device-fallback-#{System.unique_integer([:positive])}"
      )

    Application.put_env(:symphonia_service, :github_home, root)
    System.put_env("SYMPHONIA_GITHUB_ALLOW_DEVICE_FALLBACK", "true")
    System.put_env("GITHUB_TOKEN", "ghp_local_token")

    InstallationStore.upsert_installation(%{
      "id" => "123",
      "account" => %{"login" => "agora-creations", "type" => "Organization"},
      "repositories" => [
        %{
          "id" => 1,
          "owner" => "agora-creations",
          "name" => "symphonia",
          "fullName" => "agora-creations/symphonia"
        }
      ]
    })

    assert Auth.token_for_repository("agora-creations", "symphonia") == "ghp_local_token"

    on_exit(fn ->
      Application.delete_env(:symphonia_service, :github_home)
      File.rm_rf(root)
    end)
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
