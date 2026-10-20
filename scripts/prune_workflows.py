#!/usr/bin/env python3
"""Prune Siftidy Actions history without losing its last passing build.

Run after the build/publish job has finished. GitHub does not permit deleting
an in-progress run, so the currently executing run cannot delete itself.
Published releases, assets, and Git tags are never removed by this script.
"""
import argparse
from datetime import datetime, timedelta, timezone
import json
import os
import subprocess

CURRENT = "Siftidy - Build, Release & Maintenance"


def api(path, method="GET"):
    process = subprocess.run(
        ["gh", "api", "--method", method, path],
        capture_output=True, text=True, check=True,
    )
    return json.loads(process.stdout) if process.stdout.strip() else {}


def list_all(endpoint, key):
    result = []
    for page in range(1, 21):
        items = api(
            f"repos/{os.environ['GITHUB_REPOSITORY']}/{endpoint}"
            f"?per_page=100&page={page}"
        ).get(key, [])
        result.extend(items)
        if len(items) < 100:
            break
    return result


def cleanup_candidates(runs, *, current_run_id, current_build_passed):
    """Select only completed runs, protecting the latest passing build.

    On a successful new release, retain the current in-progress run and remove
    all earlier completed runs. If the new build fails (or this is a manual
    cleanup-only run), preserve the last completed successful build instead.
    """
    ordered = sorted(runs, key=lambda r: r.get("created_at", ""), reverse=True)
    protected = {current_run_id} if current_run_id else set()
    if not current_build_passed:
        previous_success = next(
            (
                run["id"] for run in ordered
                if run.get("name") == CURRENT
                and run.get("status") == "completed"
                and run.get("conclusion") == "success"
                and run.get("event") != "schedule"
            ),
            None,
        )
        if previous_success is not None:
            protected.add(previous_success)
    return [
        run for run in ordered
        if run.get("status") == "completed" and run["id"] not in protected
    ]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact-days", type=int, default=2)
    args = parser.parse_args()
    if args.artifact_days < 0:
        parser.error("artifact-days must be >= 0")
    cutoff = datetime.now(timezone.utc) - timedelta(days=args.artifact_days)
    current_run = int(os.environ.get("GITHUB_RUN_ID", "0"))
    current_build_passed = os.environ.get("SIFTIDY_BUILD_PASSED", "").lower() == "true"
    runs = list_all("actions/runs", "workflow_runs")
    targets = cleanup_candidates(
        runs,
        current_run_id=current_run,
        current_build_passed=current_build_passed,
    )
    for run in targets:
        api(f"repos/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{run['id']}", "DELETE")

    removed_artifacts = 0
    for artifact in list_all("actions/artifacts", "artifacts"):
        created = datetime.fromisoformat(artifact["created_at"].replace("Z", "+00:00"))
        if artifact.get("expired") or created < cutoff:
            api(
                f"repos/{os.environ['GITHUB_REPOSITORY']}/actions/artifacts/{artifact['id']}",
                "DELETE",
            )
            removed_artifacts += 1
    print(
        f"Deleted {len(targets)} older completed workflow runs and "
        f"{removed_artifacts} aged temporary artifacts. "
        "Protected the current run and, if needed, the last passing build. "
        "Published releases and tags were not touched."
    )


if __name__ == "__main__":
    main()