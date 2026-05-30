defmodule SymphoniaService.Runners.FakeRunner do
  @moduledoc """
  Test-only fake runner contract fixture.
  """

  def capabilities do
    %{
      "codexAppServer" => true,
      "localGitWorktree" => false,
      "experimentalSandbox" => true,
      "validation" => true
    }
  end

  def registration_attrs(attrs \\ %{}) do
    Map.merge(
      %{
        "name" => "fake-runner",
        "registrationToken" => "fake-runner-token",
        "capabilities" => capabilities(),
        "limits" => %{"maxConcurrentRuns" => 1}
      },
      attrs
    )
  end

  def patch_bundle_fixture(runner_id \\ "fake-runner", run_id \\ "run_123") do
    %{
      "runner_id" => runner_id,
      "run_id" => run_id,
      "result_type" => "patch_bundle",
      "files_changed" => [
        %{
          "path" => "app/example.tsx",
          "patch" => "diff --git a/app/example.tsx b/app/example.tsx"
        }
      ],
      "validation" => [
        %{"label" => "Tests", "status" => "passed", "detail" => "Fake validation passed."}
      ],
      "public_summary" => "Fake runner produced a fixture patch."
    }
  end
end
