#!/usr/bin/env python3
"""Remove stale completed GitHub Actions runs, never published GitHub Releases.

Keep the most recent N runs per workflow, and only remove completed runs
that are older than the configured retention window. The current job is
always protected. Requires GH_TOKEN and Actions:write permission.
"""
import argparse
from datetime import datetime, timedelta, timezone
import json
import os
import subprocess
import sys
from urllib.parse import quote


def gh_api(path: str, delete: bool = False):
    cmd = ["gh", "api"]
    if delete:
        cmd += ["--method", "DELETE"]
    cmd.append(path)
    result = subprocess.run(cmd, check=True, capture_output=True, text=True)
    return None if delete else json.loads(result.stdout)


def prune(days: int, keep: int, dry_run: bool = False):
    repository = os.environ["GITHUB_REPOSITORY"]
    current_id = int(os.environ.get("GITHUB_RUN_ID", "0"))
    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    all_runs = []
    for page in range(1, 11):
        result = gh_api(
            f"repos/{repository}/actions/runs?per_page=100&page={page}"
        )
        page_runs = result.get("workflow_runs", [])
        all_runs.extend(page_runs)
        if len(page_runs) < 100:
            break
    all_runs.sort(key=lambda run: run.get("created_at", ""), reverse=True)
    seen = {}
    removed = 0
    for run in all_runs:
        workflow = run.get("workflow_id")
        seen[workflow] = seen.get(workflow, 0) + 1
        run_id = run["id"]
        created = datetime.fromisoformat(
            run["created_at"].replace("Z", "+00:00")
        )
        if (run_id == current_id or run.get("status") != "completed"
                or seen[workflow] <= keep or created >= cutoff):
            continue
        print(f"{'Would remove' if dry_run else 'Removing'} completed "
              f"workflow run {run_id} ({run.get('name')})", flush=True)
        if not dry_run:
            gh_api(f"repos/{repository}/actions/runs/{run_id}", delete=True)
        removed += 1
    print(f"Processed {len(all_runs)} runs; "
          f"{removed} old completed runs {'eligible' if dry_run else 'removed'}.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--days", type=int, default=7)
    parser.add_argument("--keep", type=int, default=5)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if args.days < 1 or args.keep < 1:
        parser.error("--days and --keep must be positive")
    if not os.getenv("GH_TOKEN") or not os.getenv("GITHUB_REPOSITORY"):
        sys.exit("GH_TOKEN and GITHUB_REPOSITORY are required")
    prune(args.days, args.keep, args.dry_run)
