defmodule SymphoniaService.WorkspaceProvidersTest do
  use ExUnit.Case

  alias SymphoniaService.Runner.{
    ChangeApplier,
    ExperimentalSandboxProvider,
    LocalGitWorktreeProvider,
    WorkspaceProviders
  }

  import Bitwise

  setup do
    previous_provider = System.get_env("SYMPHONIA_WORKSPACE_PROVIDER")
    previous_sandbox = System.get_env("SYMPHONIA_EXPERIMENTAL_SANDBOX_PROVIDER")

    System.delete_env("SYMPHONIA_WORKSPACE_PROVIDER")
    System.delete_env("SYMPHONIA_EXPERIMENTAL_SANDBOX_PROVIDER")

    on_exit(fn ->
      restore_env("SYMPHONIA_WORKSPACE_PROVIDER", previous_provider)
      restore_env("SYMPHONIA_EXPERIMENTAL_SANDBOX_PROVIDER", previous_sandbox)
    end)

    :ok
  end

  test "local workspace provider is selected by default" do
    assert {:ok, LocalGitWorktreeProvider} =
             WorkspaceProviders.resolve(%{}, %{}, %{"kind" => "assignment"}, %{})
  end

  test "experimental sandbox is unavailable unless the feature flag is enabled" do
    assert {:error, reason} =
             WorkspaceProviders.resolve(%{}, %{}, %{"kind" => "assignment"}, %{
               "workspace_provider" => "experimental_sandbox"
             })

    assert reason =~ "experimental sandbox workspace provider is disabled"

    System.put_env("SYMPHONIA_EXPERIMENTAL_SANDBOX_PROVIDER", "1")

    assert {:ok, ExperimentalSandboxProvider} =
             WorkspaceProviders.resolve(%{}, %{}, %{"kind" => "assignment"}, %{
               "workspaceProvider" => "experimental_sandbox"
             })
  end

  test "unsupported workspace provider params are rejected safely" do
    assert {:error, reason} =
             WorkspaceProviders.resolve(%{}, %{}, %{"kind" => "assignment"}, %{
               "workspace_provider" => "cloud_fleet"
             })

    assert reason ==
             "The Coding Assistant can't start because the workspace provider is not supported."
  end

  test "Harness daemon assignments always resolve to the local provider" do
    System.put_env("SYMPHONIA_EXPERIMENTAL_SANDBOX_PROVIDER", "1")
    System.put_env("SYMPHONIA_WORKSPACE_PROVIDER", "experimental_sandbox")

    assert {:ok, LocalGitWorktreeProvider} =
             WorkspaceProviders.resolve(%{}, %{}, %{"kind" => "daemon_assignment"}, %{
               "workspace_provider" => "experimental_sandbox"
             })
  end

  test "review_context returns the local review context for sandbox mode" do
    review_context = %{repo_path: "/review", workspace_provider: "local_git_worktree"}

    sandbox_context = %{
      repo_path: "/sandbox",
      workspace_provider: "experimental_sandbox",
      review_context: review_context
    }

    assert WorkspaceProviders.review_context(sandbox_context) == review_context
    assert WorkspaceProviders.review_context(review_context) == review_context
  end

  test "ChangeApplier applies allowed source changes and deletions" do
    root = temp_root("change-applier-allowed")
    on_exit(fn -> File.rm_rf(root) end)

    source = Path.join(root, "source")
    review = Path.join(root, "review")
    File.mkdir_p!(Path.join(source, "lib"))
    File.mkdir_p!(Path.join(review, "lib"))

    File.write!(Path.join(source, "lib/app.ex"), "defmodule App do\nend\n")
    File.write!(Path.join(review, "lib/remove.ex"), "old\n")

    assert {:ok, ["lib/app.ex", "lib/remove.ex"]} =
             ChangeApplier.apply(source, review, ["lib/app.ex", "lib/remove.ex"])

    assert File.read!(Path.join(review, "lib/app.ex")) =~ "defmodule App"
    refute File.exists?(Path.join(review, "lib/remove.ex"))
    assert (File.stat!(Path.join(review, "lib/app.ex")).mode &&& 0o777) == 0o644
  end

  test "ChangeApplier rejects unsafe and protected paths" do
    root = temp_root("change-applier-rejects")
    on_exit(fn -> File.rm_rf(root) end)

    source = Path.join(root, "source")
    review = Path.join(root, "review")
    File.mkdir_p!(source)
    File.mkdir_p!(review)

    rejected_paths = [
      "/tmp/secret.txt",
      "../secret.txt",
      ".",
      ".git",
      ".git/config",
      ".symphonia",
      ".symphonia/state.json",
      "symphonia/tasks",
      "symphonia/tasks/SYM-1.md",
      "symphonia/run-summaries",
      "symphonia/run-summaries/sym-1.md",
      "WORKFLOW.md",
      "registry.json",
      "symphonia/repositories.json"
    ]

    for path <- rejected_paths do
      assert {:error, _reason} = ChangeApplier.apply(source, review, [path])
    end
  end

  test "ChangeApplier rejects symlink escapes when the filesystem supports them" do
    root = temp_root("change-applier-symlink")
    on_exit(fn -> File.rm_rf(root) end)

    source = Path.join(root, "source")
    review = Path.join(root, "review")
    outside = Path.join(root, "outside")
    File.mkdir_p!(Path.join(source, "lib"))
    File.mkdir_p!(review)
    File.mkdir_p!(outside)
    File.write!(Path.join(source, "lib/app.ex"), "safe\n")

    case File.ln_s(outside, Path.join(review, "lib")) do
      :ok ->
        assert {:error, reason} = ChangeApplier.apply(source, review, ["lib/app.ex"])
        assert reason =~ "symlink"

      {:error, _reason} ->
        :ok
    end
  end

  defp temp_root(slug) do
    Path.join(System.tmp_dir!(), "symphonia-#{slug}-#{System.unique_integer([:positive])}")
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
