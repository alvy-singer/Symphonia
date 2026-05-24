defmodule SymphoniaService.GitHub.AuthTest do
  use ExUnit.Case

  alias SymphoniaService.GitHub.Auth

  defmodule StubClient do
    def request_device_code("client-id") do
      {:ok,
       %{
         "device_code" => "device-code",
         "user_code" => "ABCD-EFGH",
         "verification_uri" => "https://github.com/login/device",
         "expires_in" => 900,
         "interval" => 5
       }}
    end

    def poll_device_code(_client_id, _device_code) do
      flunk("poll_device_code should not be called before the returned interval elapses")
    end
  end

  setup do
    previous_client_id = System.get_env("SYMPHONIA_GITHUB_CLIENT_ID")
    System.put_env("SYMPHONIA_GITHUB_CLIENT_ID", "client-id")
    Application.put_env(:symphonia_service, :github_client, StubClient)

    on_exit(fn ->
      if previous_client_id,
        do: System.put_env("SYMPHONIA_GITHUB_CLIENT_ID", previous_client_id),
        else: System.delete_env("SYMPHONIA_GITHUB_CLIENT_ID")

      Application.delete_env(:symphonia_service, :github_client)
    end)
  end

  test "device-flow polling respects the returned interval" do
    assert {:ok, device} = Auth.start_device_flow()

    assert {:error, 429,
            %{"error" => "Wait before checking GitHub again.", "retryAfter" => retry_after}} =
             Auth.poll_device_flow(device)

    assert retry_after > 0
  end
end
