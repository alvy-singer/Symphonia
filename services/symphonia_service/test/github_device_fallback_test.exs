defmodule SymphoniaService.GitHub.DeviceFallbackTest do
  use ExUnit.Case

  alias SymphoniaService.GitHub.Auth

  setup do
    previous = System.get_env("SYMPHONIA_GITHUB_ALLOW_DEVICE_FALLBACK")
    System.delete_env("SYMPHONIA_GITHUB_ALLOW_DEVICE_FALLBACK")
    Application.delete_env(:symphonia_service, :github_allow_device_fallback)

    on_exit(fn ->
      if previous,
        do: System.put_env("SYMPHONIA_GITHUB_ALLOW_DEVICE_FALLBACK", previous),
        else: System.delete_env("SYMPHONIA_GITHUB_ALLOW_DEVICE_FALLBACK")

      Application.delete_env(:symphonia_service, :github_allow_device_fallback)
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
end
