#!/usr/bin/env python3
"""Generate the mirror update manifest from public GitHub release metadata.

Prints JSON only. Upload and verify mirrored installers BEFORE publishing it.
"""
import json
import re
import sys
from pathlib import Path


def create_manifest(release):
    tag = release.get("tag_name")
    if (not isinstance(tag, str) or not re.fullmatch(r"v\d+\.\d+\.\d+", tag)
            or release.get("draft") is not False
            or release.get("prerelease") is not False):
        raise ValueError("Expected a stable published Modu release")
    version = tag[1:]
    names = {
        f"Modu-{version}-{platform}-{arch}{suffix}"
        for platform, suffix in [("android", ".apk"), ("macos", ".dmg"),
                                 ("linux", ".deb"), ("windows", "-setup.exe")]
        for arch in ("arm64", "x64")
    } | {f"Modu-{version}-ios-arm64.ipa"}
    assets = []
    seen = set()
    for asset in release.get("assets", []):
        name = asset.get("name")
        if name not in names:
            continue
        url = f"https://github.com/sobranie2406/modureader/releases/download/{tag}/{name}"
        digest = asset.get("digest")
        size = asset.get("size")
        if (name in seen or asset.get("state") != "uploaded"
                or asset.get("browser_download_url") != url
                or type(size) is not int or not 0 < size <= 2 * 1024**3
                or not isinstance(digest, str)
                or not re.fullmatch(r"sha256:[a-fA-F0-9]{64}", digest)):
            raise ValueError("Invalid or duplicate release installer")
        seen.add(name)
        assets.append(dict(name=name, state="uploaded", size=size,
                           digest=digest.lower(), browser_download_url=url))
    if seen != names:
        raise ValueError("All nine verified platform installers are required")
    return dict(modu_update_schema=1, tag_name=tag, draft=False,
                prerelease=False,
                body=release.get("body") if isinstance(release.get("body"), str) else "",
                assets=sorted(assets, key=lambda a: a["name"]))


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: update_manifest.py github-release.json")
    result = create_manifest(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")))
    output = json.dumps(result, ensure_ascii=False, indent=2)
    if len(output.encode("utf-8")) > 1024 * 1024:
        raise ValueError("Update manifest exceeds client metadata limit")
    print(output)


if __name__ == "__main__":
    main()
