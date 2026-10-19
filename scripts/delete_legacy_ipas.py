#!/usr/bin/env python3
"""Remove iOS/IPA downloads from previous Siftidy GitHub Releases.

Retain historical releases, tags and all macOS ZIP/DMG packages.
"""
import json
import os
import subprocess


def api(path: str, method: str = "GET"):
    process = subprocess.run(
        ["gh", "api", "--method", method, path],
        capture_output=True, text=True, check=True,
    )
    return json.loads(process.stdout) if process.stdout.strip() else {}


def main():
    repository = os.environ["GITHUB_REPOSITORY"]
    removed = 0
    for page in range(1, 11):
        releases = api(f"repos/{repository}/releases?per_page=100&page={page}")
        if not releases:
            break
        for release in releases:
            for asset in release.get("assets", []):
                if asset["name"].lower().endswith(".ipa"):
                    api(f"repos/{repository}/releases/assets/{asset['id']}", "DELETE")
                    print(f"Deleted retired iPhone IPA: {asset['name']}")
                    removed += 1
        if len(releases) < 100:
            break
    print(f"Removed {removed} retired IPA release assets. macOS packages retained.")


if __name__ == "__main__":
    main()
