#!/usr/bin/env python3
"""Publish an actual GitHub Release IPA to the AltStore Classic source.

Runs on a macOS release runner so codesign can inspect the IPA entitlements.
Never inserts a speculative download URL or simulator-only build.
"""
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path
from urllib.parse import quote

BUNDLE_ID = "com.siftidy.siftidy"
SOURCE = Path("altstore.json")
AGENT = "Siftidy-AltStoreReleaseSync"
VERSION = re.compile(r"^v?([0-9]+(?:\.[0-9]+){2})$")


def request(url):
    headers = {"Accept": "application/vnd.github+json", "User-Agent": AGENT}
    token = os.environ.get("GH_TOKEN")
    if token:
        headers["Authorization"] = "Bearer " + token
    return urllib.request.Request(url, headers=headers)


def read_release(repository, tag):
    url = (
        "https://api.github.com/repos/"
        + repository
        + "/releases/tags/"
        + quote(tag, safe="")
    )
    with urllib.request.urlopen(request(url), timeout=25) as response:
        return json.load(response)


def examine_ipa(path, workdir):
    with zipfile.ZipFile(path) as archive:
        plist_names = [
            name for name in archive.namelist()
            if name.startswith("Payload/")
            and name.endswith(".app/Info.plist")
            and name.count("/") == 2
        ]
        if len(plist_names) != 1:
            raise ValueError("Expected one iPhone app Info.plist in Payload.")
        plist_name = plist_names[0]
        info = plistlib.loads(archive.read(plist_name))
        # Only one signed application from an authenticated GitHub Release.
        archive.extractall(workdir)
    app_dir = Path(workdir) / Path(plist_name).parent
    result = subprocess.run(
        ["codesign", "-d", "--entitlements", "-", str(app_dir)],
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise ValueError(
            "iOS IPA code signature could not be inspected; "
            "upload a signed device IPA."
        )
    try:
        entitlements = plistlib.loads(result.stdout)
    except (ValueError, TypeError, plistlib.InvalidFileException) as exc:
        raise ValueError("Could not read code signing entitlements.") from exc
    if not isinstance(entitlements, dict):
        raise ValueError("Expected a signing entitlements dictionary.")
    excluded = {"application-identifier", "com.apple.developer.team-identifier"}
    permissions = {
        "entitlements": sorted(key for key in entitlements if key not in excluded),
        "privacy": {
            key: value for key, value in info.items()
            if key.endswith("UsageDescription") and isinstance(value, str)
        },
    }
    return info, permissions


def main():
    if len(sys.argv) != 3:
        raise SystemExit("Usage: sync_altstore.py <owner/repo> <release_tag>")
    repository, tag = sys.argv[1:]
    tag_match = VERSION.fullmatch(tag)
    if not tag_match:
        raise ValueError("Release tag must be vMAJOR.MINOR.PATCH.")
    release = read_release(repository, tag)
    assets = [
        item for item in release.get("assets", [])
        if item.get("name", "").lower().endswith(".ipa")
        and "siftidy" in item.get("name", "").lower()
        and "simulator" not in item.get("name", "").lower()
    ]
    if not assets:
        print("No iPhone IPA attached; keeping the AltStore source unchanged.")
        return
    if len(assets) != 1:
        raise ValueError("Expected exactly one Siftidy iPhone IPA asset.")
    asset = assets[0]
    with tempfile.TemporaryDirectory(prefix="siftidy-ipa-") as workdir:
        ipa_path = Path(workdir) / "Siftidy.ipa"
        with urllib.request.urlopen(
            urllib.request.Request(asset["browser_download_url"], headers={"User-Agent": AGENT}), timeout=60
        ) as response, ipa_path.open("wb") as output:
            shutil.copyfileobj(response, output)
        info, permissions = examine_ipa(ipa_path, workdir)

    bundle = str(info.get("CFBundleIdentifier", ""))
    app_version = str(info.get("CFBundleShortVersionString", ""))
    build = str(info.get("CFBundleVersion", ""))
    if bundle != BUNDLE_ID:
        raise ValueError("IPA bundle ID differs from Siftidy's iOS ID.")
    if app_version != tag_match.group(1):
        raise ValueError("IPA version must exactly match the release tag.")
    if not build:
        raise ValueError("IPA is missing its build number.")
    source = json.loads(SOURCE.read_text(encoding="utf-8"))
    apps = source.setdefault("apps", [])
    existing = next((app for app in apps if app["bundleIdentifier"] == BUNDLE_ID), None)
    if existing is None:
        existing = {
            "name": "Siftidy",
            "bundleIdentifier": BUNDLE_ID,
            "developerName": "Siftidy",
            "subtitle": "Review and clean your Photos library privately",
            "localizedDescription": (
                "Review images and videos, select what to delete, "
                "and keep your photos on your own device."
            ),
            "iconURL": "https://github.com/ssnanda.png",
            "tintColor": "#087E83",
            "category": "photo-video",
            "versions": [],
        }
        apps.append(existing)
    existing["appPermissions"] = permissions
    new_version = {
        "version": app_version,
        "buildVersion": build,
        "date": release["published_at"],
        "localizedDescription": (release.get("body") or "Siftidy update.")[:1800],
        "downloadURL": asset["browser_download_url"],
        "size": asset["size"],
    }
    if info.get("MinimumOSVersion"):
        new_version["minOSVersion"] = str(info["MinimumOSVersion"])
    existing["versions"] = [
        v for v in existing["versions"] if v.get("version") != app_version
    ] + [new_version]
    existing["versions"].sort(
        key=lambda item: tuple(int(x) for x in item["version"].split(".")),
        reverse=True,
    )
    SOURCE.write_text(json.dumps(source, indent=2) + "\n", encoding="utf-8")
    print("Updated AltStore source for signed Siftidy IPA " + app_version)


if __name__ == "__main__":
    main()
