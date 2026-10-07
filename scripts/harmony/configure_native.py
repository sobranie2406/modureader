"""Configure hf_tokenizers only in a disposable Linux GitHub Actions checkout.

Run after the verified OHOS SDK and pinned Rust toolchain have been provisioned.
CI ordering is mandatory:
    1. flutter pub get
    2. dart run scripts/dev/check_harmony.dart and dart run build_runner ...
    3. configure_native.py (command below)
    4. flutter build hap ...

Do NOT configure before host code generation: its Linux x64 hooks must not see
the explicit OHOS arm64 target. No user-defines are needed before pub get;
hooks read these from the root pubspec at build time. Do not run further host
Dart generators in this configured checkout. Use a fresh checkout for them.

Immediately before flutter build hap:
    python3 scripts/harmony/configure_native.py --root "$GITHUB_WORKSPACE"

Required environment: OHOS_SDK_HOME, MODU_OHOS_CLANG, RUSTUP_TOOLCHAIN (x.y.z).
CARGO may name the cargo executable; otherwise PATH is searched. CARGO_HOME and
RUSTUP_HOME default to ~/.cargo and ~/.rustup. No tools are installed or executed.
Only the runner's root pubspec.yaml is written, not pubspec_overrides.yaml.
The root pubspec is semantically preserved (YAML comments are not retained).
"""

import argparse
import os
from pathlib import Path
import re
import shutil
import stat
import sys
import tempfile

import yaml


class UniqueLoader(yaml.SafeLoader):
    """Refuse ambiguous YAML rather than silently discard duplicate keys."""


def _mapping(loader, node, deep=False):
    result = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if not isinstance(key, str) or key in result:
            raise ValueError(f"Non-string or duplicate YAML key: {key!r}")
        result[key] = loader.construct_object(value_node, deep=deep)
    return result


UniqueLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _mapping)


def _text(value, label):
    if (not isinstance(value, str) or not value or value != value.strip()
            or re.search(r"[\x00-\x1f\x7f]", value)):
        raise ValueError(f"Invalid or missing {label}")
    return value


def _path(value, label, *, executable=False):
    value = _text(value, label)
    path = Path(value)
    if not path.is_absolute():
        raise ValueError(f"{label} must be absolute")
    if executable:
        if not path.is_file() or not os.access(path, os.X_OK):
            raise ValueError(f"Missing executable {label}: {path}")
    elif not path.is_dir():
        raise ValueError(f"Missing directory {label}: {path}")
    # Do not resolve cargo symlinks: rustup dispatches on the argv[0] basename.
    return value


def native_defines(env):
    """Validate explicitly selected SDK/Rust tools without executing them."""
    sdk = _path(env.get("OHOS_SDK_HOME"), "OHOS_SDK_HOME")
    _path(f"{sdk}/native/sysroot", "OHOS sysroot")
    for tool in ("clang", "llvm-ar", "llvm-readelf"):
        _path(f"{sdk}/native/llvm/bin/{tool}", tool, executable=True)
    linker = _path(env.get("MODU_OHOS_CLANG"), "MODU_OHOS_CLANG", executable=True)
    cargo = _path(env.get("CARGO") or shutil.which("cargo", path=env.get("PATH", "")),
                  "cargo", executable=True)
    home = env.get("HOME", "")
    cargo_home = _path(env.get("CARGO_HOME", f"{home}/.cargo"), "CARGO_HOME")
    rustup_home = _path(env.get("RUSTUP_HOME", f"{home}/.rustup"), "RUSTUP_HOME")
    toolchain = _text(env.get("RUSTUP_TOOLCHAIN"), "RUSTUP_TOOLCHAIN")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", toolchain):
        raise ValueError("RUSTUP_TOOLCHAIN must be a pinned x.y.z version")
    return {
        "target_os": "ohos",
        "target_architecture": "arm64",
        "rust_target": "aarch64-unknown-linux-ohos",
        "sdk_root": sdk,
        "clang_wrapper": linker,
        "cargo": cargo,
        "cargo_home": cargo_home,
        "rustup_home": rustup_home,
        "rustup_toolchain": toolchain,
    }


def _child_mapping(parent, key):
    if key not in parent:
        parent[key] = {}
    child = parent[key]
    if not isinstance(child, dict):
        raise ValueError(f"{key} must be a YAML mapping")
    return child


def configure(root):
    env = os.environ
    if (env.get("GITHUB_ACTIONS") != "true" or sys.platform != "linux"
            or env.get("RUNNER_OS") != "Linux" or env.get("RUNNER_ARCH") != "X64"):
        raise ValueError("Run only on a Linux X64 GitHub Actions runner")
    workspace = Path(_path(env.get("GITHUB_WORKSPACE"), "GITHUB_WORKSPACE")).resolve()
    root = Path(root).resolve()
    if not root.is_relative_to(workspace):
        raise ValueError("Root must be inside GITHUB_WORKSPACE")
    pubspec = root / "pubspec.yaml"
    if pubspec.is_symlink() or not pubspec.is_file():
        raise ValueError("Root pubspec.yaml must be a regular non-symlink file")
    defines = native_defines(env)
    original = pubspec.read_bytes()
    document = yaml.load(original, Loader=UniqueLoader)
    if not isinstance(document, dict):
        raise ValueError("Root pubspec.yaml must be a YAML mapping")
    hooks = _child_mapping(document, "hooks")
    packages = _child_mapping(hooks, "user_defines")
    if "hf_tokenizers" in packages:
        if packages["hf_tokenizers"] == defines:
            return False
        raise ValueError("Conflicting hf_tokenizers user-defines; use a fresh CI checkout")
    packages["hf_tokenizers"] = defines
    rendered = yaml.safe_dump(document, sort_keys=False, allow_unicode=True)
    # Validate first, then replace atomically; preserve permissions. Never leave
    # a partially written pubspec if validation or serialization fails.
    if yaml.safe_load(rendered) != document:
        raise ValueError("Cannot losslessly serialize pubspec.yaml")
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=root,
                                         prefix=".pubspec-native-", delete=False) as handle:
            temporary = Path(handle.name)
            handle.write(rendered)
        temporary.chmod(stat.S_IMODE(pubspec.stat().st_mode))
        if pubspec.read_bytes() != original:
            raise ValueError("pubspec.yaml changed during configuration")
        os.replace(temporary, pubspec)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    args = parser.parse_args()
    try:
        changed = configure(args.root)
    except (OSError, ValueError, yaml.YAMLError) as error:
        parser.exit(1, f"configure_native: {error}\n")
    print("hf_tokenizers OHOS hook configured" if changed else "OHOS hook already configured")


if __name__ == "__main__":
    main()
