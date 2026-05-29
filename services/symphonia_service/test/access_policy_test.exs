defmodule SymphoniaService.AccessPolicyTest do
  use ExUnit.Case

  alias SymphoniaService.Access.{Actor, Policy}

  test "default local actor is owner" do
    assert Actor.from_headers(%{}) == %{
             "id" => "local-user",
             "name" => "Local user",
             "role" => "owner",
             "source" => "local"
           }
  end

  test "test headers can set actor role name and id" do
    actor =
      Actor.from_headers(%{
        "x-symphonia-actor" => "Ava",
        "x-symphonia-actor-id" => "user:ava",
        "x-symphonia-role" => "reviewer"
      })

    assert actor["id"] == "user:ava"
    assert actor["name"] == "Ava"
    assert actor["role"] == "reviewer"
    assert actor["source"] == "session"
  end

  test "policy matrix covers V1 role boundaries" do
    refute allowed?("viewer", "task.run_codex")
    assert allowed?("reviewer", "review.approve")
    refute allowed?("reviewer", "pull_request.open")
    assert allowed?("operator", "harness.pause")
    refute allowed?("operator", "review.approve")
    assert allowed?("maintainer", "pull_request.open")
    assert allowed?("owner", "workspace_provider.experimental_run")
    refute allowed?("maintainer", "workspace_provider.experimental_run")
  end

  defp allowed?(role, permission) do
    Policy.allowed?(%{"role" => role}, permission)
  end
end
