"""Read-only SDK metadata preflight for pinned Flutter OH 3.41.9+ohos-1.0.2.

CI only, after verified tools extraction and before flutter pub get:
    python3 scripts/harmony/check_sdk.py "$DEVECO_SDK_HOME"

The argument is the SDK root (command-line-tools/sdk), not sdk/default or
sdk/default/openharmony. Only default/sdk-pkg.json is inspected. This does not
verify SDK integrity, public API declarations, or runtime compatibility, and
never installs, executes, or rewrites SDK files.
"""

import argparse
import json
import os
from pathlib import Path
import re
import sys


MIN_API_VERSION = 26


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate JSON key {key!r} in SDK metadata")
        result[key] = value
    return result


def check_sdk(sdk_root: Path) -> int:
    """Return the validated API level; refuse unsupported metadata unchanged."""
    if (os.environ.get("GITHUB_ACTIONS") != "true" or sys.platform != "linux"
            or os.environ.get("RUNNER_OS") != "Linux"
            or os.environ.get("RUNNER_ARCH") != "X64"):
        raise ValueError("Run only on a Linux X64 GitHub Actions runner; no local SDK access.")

    sdk_root = Path(sdk_root)
    if not sdk_root.is_absolute() or not sdk_root.is_dir():
        raise ValueError("SDK root must be an existing absolute directory: "
                         "pass DEVECO_SDK_HOME (command-line-tools/sdk).")
    metadata = sdk_root / "default" / "sdk-pkg.json"
    if not metadata.is_file():
        raise ValueError(f"Missing SDK metadata file: {metadata}. "
                         "Pass command-line-tools/sdk, not sdk/default or "
                         "sdk/default/openharmony; verify the extracted archive layout.")
    try:
        document = json.loads(metadata.read_text(encoding="utf-8"),
                              object_pairs_hook=_unique_object)
    except (UnicodeError, ValueError) as error:
        raise ValueError(f"Invalid SDK metadata at {metadata}: {error}") from error
    if not isinstance(document, dict) or not isinstance(document.get("data"), dict):
        raise ValueError(f"SDK metadata must contain a data object: {metadata}")
    data = document["data"]
    if "apiVersion" not in data:
        raise ValueError(f"Missing data.apiVersion in SDK metadata: {metadata}")
    value = data["apiVersion"]
    if not isinstance(value, str) or re.fullmatch(r"[0-9]+", value) is None:
        raise ValueError(
            f"Unsupported data.apiVersion format: {value!r}. Pinned Flutter OH "
            'requires a string integer such as "26", not a JSON number or '
            'a dotted version such as "26.0.0". platformVersion is a separate '
            "field and cannot substitute for apiVersion. Stop and review SDK/Flutter "
            "compatibility; do not rewrite official SDK metadata."
        )
    api_version = int(value)
    if api_version < MIN_API_VERSION:
        raise ValueError(
            f"SDK API {api_version} is too old: pinned Flutter OH autofill requires "
            "the public APIs introduced in API 26. Use a verified API >=26 SDK; "
            "do not stub autofill, bypass SystemAPI restrictions, or rewrite metadata."
        )
    return api_version


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sdk_root", type=Path, help="DEVECO_SDK_HOME: command-line-tools/sdk")
    args = parser.parse_args()
    try:
        api_version = check_sdk(args.sdk_root)
    except (OSError, ValueError) as error:
        parser.exit(1, f"check_sdk: {error}\n")
    print(f"SDK metadata OK: data.apiVersion={api_version!s} (string integer, >=26). "
          "Metadata check only; public API declarations and runtime compatibility are not verified.")


if __name__ == "__main__":
    main()
