defmodule SymphoniaService.Sandbox.ProviderRunnerScript do
  @moduledoc """
  Controlled sandbox provider runner script.

  The script is uploaded as private runtime material. It keeps Gemini CLI behind
  Symphonia's patch-bundle contract and does not create a terminal surface.
  """

  def path, do: "/workspace/.symphonia/bin/symphonia-provider-runner"

  def content do
    """
    #!/usr/bin/env python3
    import argparse
    import hashlib
    import json
    import os
    import subprocess
    import sys

    def sha256(value):
        return hashlib.sha256(value.encode("utf-8")).hexdigest()

    def write_json(path, payload):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle)

    def changed_files():
        proc = subprocess.run(
            ["git", "diff", "--name-status", "--", ".", ":(exclude).symphonia"],
            cwd="/workspace",
            text=True,
            capture_output=True,
            check=False,
        )
        files = []
        for line in proc.stdout.splitlines():
            parts = line.split("\\t")
            if len(parts) >= 2:
                status = parts[0]
                path = parts[-1]
                files.append({"path": path, "status": status.lower()})
        return files

    def git_diff():
        subprocess.run(
            ["git", "add", "-N", "--", ".", ":(exclude).symphonia"],
            cwd="/workspace",
            text=True,
            capture_output=True,
            check=False,
        )
        proc = subprocess.run(
            ["git", "diff", "--", ".", ":(exclude).symphonia"],
            cwd="/workspace",
            text=True,
            capture_output=True,
            check=False,
        )
        return proc.stdout

    def failure(args, context, failure_class, summary):
        write_json(args.result, {
            "assignmentId": context.get("assignmentId"),
            "runId": context.get("runId"),
            "runnerId": context.get("runnerId", "cloud-sandbox"),
            "provider": args.provider,
            "status": "failed",
            "baseSha": context.get("baseSha"),
            "failureClass": failure_class,
            "publicSummary": summary,
        })
        return 0

    def main():
        parser = argparse.ArgumentParser()
        parser.add_argument("--provider", required=True)
        parser.add_argument("--context", required=True)
        parser.add_argument("--result", required=True)
        args = parser.parse_args()

        with open(args.context, "r", encoding="utf-8") as handle:
            context = json.load(handle)

        if args.provider != "gemini_cli":
            return failure(args, context, "setup_blocked", "Provider runner is not configured.")

        env = os.environ.copy()
        env_path = "/workspace/.symphonia/provider-env.json"
        if os.path.exists(env_path):
            with open(env_path, "r", encoding="utf-8") as handle:
                env.update(json.load(handle))

        prompt = context.get("renderedPrompt", "")
        if not prompt.strip():
            return failure(args, context, "setup_blocked", "Gemini prompt is missing.")

        try:
            completed = subprocess.run(
                ["gemini", "--prompt", prompt, "--output-format", "json"],
                cwd="/workspace",
                text=True,
                capture_output=True,
                timeout=900,
                env=env,
                check=False,
            )
        except FileNotFoundError:
            return failure(args, context, "setup_blocked", "Gemini CLI is not installed.")
        except subprocess.TimeoutExpired:
            return failure(args, context, "transient_provider", "Gemini CLI timed out.")

        if completed.returncode != 0:
            return failure(args, context, "transient_provider", "Gemini CLI did not complete.")

        diff = git_diff()
        files = changed_files()

        if not diff.strip() or not files:
            return failure(args, context, "no_reviewable_files", "Gemini CLI did not produce reviewable changes.")

        changed_paths = sorted([item["path"] for item in files])
        write_json(args.result, {
            "assignmentId": context.get("assignmentId"),
            "runId": context.get("runId"),
            "runnerId": context.get("runnerId", "cloud-sandbox"),
            "provider": "gemini_cli",
            "status": "completed",
            "baseSha": context.get("baseSha"),
            "patchBundle": {
                "format": "git_diff",
                "encoding": "utf8",
                "sha256": sha256(diff),
                "diff": diff,
            },
            "changedFiles": files,
            "changedFilesDigest": sha256("\\n".join(changed_paths)),
            "publicSummary": "Gemini CLI produced a reviewable patch.",
        })
        return 0

    sys.exit(main())
    """
  end
end
