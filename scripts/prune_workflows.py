#!/usr/bin/env python3
"""Prune completed legacy Siftidy Actions runs, and expired temporary artifacts.

Never remove GitHub Releases, release assets, or tags.
"""
from datetime import datetime, timedelta, timezone
import argparse
import json
import os
import subprocess

CURRENT = "Siftidy - Build, Release & Maintenance"
LEGACY = {"Validate Siftidy", "Build and publish Siftidy",
          "Prune old Actions runs", "Publish AltStore source"}

def api(path, method="GET"):
    p = subprocess.run(["gh", "api", "--method", method, path],
                       capture_output=True, text=True, check=True)
    return json.loads(p.stdout) if p.stdout.strip() else {}

def list_all(endpoint, key):
    result = []
    for page in range(1, 21):
        items = api(f"repos/{os.environ['GITHUB_REPOSITORY']}/{endpoint}?per_page=100&page={page}").get(key, [])
        result.extend(items)
        if len(items) < 100:
            break
    return result

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--days", type=int, default=7)
    parser.add_argument("--keep", type=int, default=3)
    args = parser.parse_args()
    if args.days < 0 or args.keep < 1:
        parser.error("days >= 0 and keep >= 1 required")
    cutoff = datetime.now(timezone.utc) - timedelta(days=args.days)
    this_run = int(os.environ.get("GITHUB_RUN_ID", "0"))
    runs = list_all("actions/runs", "workflow_runs")
    runs.sort(key=lambda r: r.get("created_at", ""), reverse=True)
    seen = {}
    deleted = 0
    for run in runs:
        name = run.get("name", "")
        seen[name] = seen.get(name, 0) + 1
        created = datetime.fromisoformat(run["created_at"].replace("Z", "+00:00"))
        if run.get("status") != "completed" or run["id"] == this_run:
            continue
        if name in LEGACY or (name == CURRENT and seen[name] > args.keep and created < cutoff):
            api(f"repos/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{run['id']}", "DELETE")
            deleted += 1
    gone = 0
    for artifact in list_all("actions/artifacts", "artifacts"):
        created = datetime.fromisoformat(artifact["created_at"].replace("Z", "+00:00"))
        if artifact.get("expired") or created < cutoff:
            api(f"repos/{os.environ['GITHUB_REPOSITORY']}/actions/artifacts/{artifact['id']}", "DELETE")
            gone += 1
    print(f"Cleaned {deleted} old completed runs and {gone} temporary artifacts. "
          "Release assets and tags were kept.")

if __name__ == "__main__":
    main()
