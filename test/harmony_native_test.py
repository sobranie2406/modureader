"""Local: python3 -B -m unittest discover -s test -p harmony_native_test.py -v

Local tests use temporary fixtures only, never a Dart/OHOS SDK. Optional hook
execution tests run ONLY on Linux GitHub Actions when HARMONY_NATIVE_TEST_DART
is explicitly set to an already provisioned Dart executable, after pub get.
Those tests invoke the real Dart hook with fake cargo/readelf (no native build).
"""

import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts/harmony"))
from configure_native import configure, native_defines

HOOK = ROOT / "third_party/hf_tokenizers/hook/build.dart"


def executable(path, body="exit 0\n", interpreter="/bin/sh"):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"#!{interpreter}\n{body}", encoding="utf-8")
    path.chmod(0o755)
    return str(path)


class NativeFixture(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / "checkout"
        self.root.mkdir()
        self.pubspec = self.root / "pubspec.yaml"
        self.original = "name: app\ndependencies:\n  hf_tokenizers: any\n"
        self.pubspec.write_text(self.original)
        sdk = self.base / "sdk with spaces"
        (sdk / "native/sysroot").mkdir(parents=True)
        for tool in ("clang", "llvm-ar", "llvm-readelf"):
            executable(sdk / "native/llvm/bin" / tool)
        self.home = self.base / "home"
        for name in (".cargo", ".rustup"):
            (self.home / name).mkdir(parents=True)
        self.env = {
            "GITHUB_ACTIONS": "true", "RUNNER_OS": "Linux", "RUNNER_ARCH": "X64",
            "GITHUB_WORKSPACE": str(self.root), "HOME": str(self.home),
            "PATH": "/usr/bin:/bin", "OHOS_SDK_HOME": str(sdk),
            "MODU_OHOS_CLANG": executable(self.base / "ohos-clang"),
            "CARGO": executable(self.home / ".cargo/bin/cargo"),
            "RUSTUP_TOOLCHAIN": "1.94.0",
        }

    def apply_config(self):
        with patch.dict(os.environ, self.env, clear=True), patch("sys.platform", "linux"):
            return configure(self.root)


class ConfigureNativeTest(NativeFixture):
    def test_root_pubspec_schema_preserves_other_settings_and_is_idempotent(self):
        initial = yaml.safe_load(self.original)
        initial["hooks"] = {"user_defines": {"other_package": {"enabled": True}}}
        initial["dependency_overrides"] = {"example": {"path": "third_party/example"}}
        self.pubspec.write_text(yaml.safe_dump(initial))
        self.pubspec.chmod(0o640)
        overrides = self.root / "pubspec_overrides.yaml"
        overrides.write_text("# untouched\ndependency_overrides: {}\n")
        self.assertTrue(self.apply_config())
        result = yaml.safe_load(self.pubspec.read_text())
        defines = result["hooks"]["user_defines"].pop("hf_tokenizers")
        self.assertEqual(result, initial)
        self.assertEqual(defines, native_defines(self.env))
        self.assertEqual(defines["rustup_toolchain"], "1.94.0")
        self.assertEqual(defines["target_os"], "ohos")
        self.assertEqual(defines["rust_target"], "aarch64-unknown-linux-ohos")
        self.assertEqual(self.pubspec.stat().st_mode & 0o777, 0o640)
        before = self.pubspec.read_bytes()
        self.assertFalse(self.apply_config())
        self.assertEqual(self.pubspec.read_bytes(), before)
        self.assertEqual(overrides.read_text(), "# untouched\ndependency_overrides: {}\n")
        self.assertEqual(sorted(p.name for p in self.root.iterdir()),
                         ["pubspec.yaml", "pubspec_overrides.yaml"])

    def test_ci_guard_rejects_local_mac_windows_and_arm_runner_without_write(self):
        for field, value in (("GITHUB_ACTIONS", "false"), ("RUNNER_OS", "Windows"),
                             ("RUNNER_ARCH", "ARM64")):
            with self.subTest(field=field), patch.dict(self.env, {field: value}):
                with self.assertRaisesRegex(ValueError, "GitHub Actions"):
                    self.apply_config()
        with patch.dict(os.environ, self.env, clear=True), patch("sys.platform", "darwin"):
            with self.assertRaisesRegex(ValueError, "GitHub Actions"):
                configure(self.root)
        self.assertEqual(self.pubspec.read_text(), self.original)

    def test_outside_checkout_and_symlink_pubspec_rejected(self):
        with patch.dict(self.env, {"GITHUB_WORKSPACE": str(self.home)}):
            with self.assertRaisesRegex(ValueError, "inside GITHUB_WORKSPACE"):
                self.apply_config()
        real = self.root / "real.yaml"
        self.pubspec.rename(real)
        self.pubspec.symlink_to(real)
        with self.assertRaisesRegex(ValueError, "non-symlink"):
            self.apply_config()
        self.assertEqual(real.read_text(), self.original)

    def test_missing_relative_and_control_character_parameters_rejected(self):
        for field in ("OHOS_SDK_HOME", "MODU_OHOS_CLANG", "CARGO"):
            for bad in ("missing", "/missing", "\n/bad", "/bad\x00", " /bad"):
                with self.subTest(field=field, bad=bad), patch.dict(self.env, {field: bad}):
                    with self.assertRaises(ValueError):
                        self.apply_config()
        self.assertEqual(self.pubspec.read_text(), self.original)

    def test_required_environment_and_unpinned_rust_rejected(self):
        for field in ("OHOS_SDK_HOME", "MODU_OHOS_CLANG", "RUSTUP_TOOLCHAIN"):
            with self.subTest(field=field), patch.dict(self.env):
                del self.env[field]
                with self.assertRaises(ValueError):
                    self.apply_config()
        for version in ("stable", "1.94", "nightly", "1.94.0\n", "1.94.0;echo bad"):
            with self.subTest(version=version), patch.dict(self.env, {"RUSTUP_TOOLCHAIN": version}):
                with self.assertRaises(ValueError):
                    self.apply_config()
        self.assertEqual(self.pubspec.read_text(), self.original)

    def test_all_sdk_tools_and_sysroot_required(self):
        sdk = Path(self.env["OHOS_SDK_HOME"])
        for tool in ("clang", "llvm-ar", "llvm-readelf"):
            path = sdk / "native/llvm/bin" / tool
            path.chmod(0o644)
            with self.subTest(tool=tool), self.assertRaisesRegex(ValueError, "executable"):
                self.apply_config()
            path.chmod(0o755)
        (sdk / "native/sysroot").rmdir()
        with self.assertRaisesRegex(ValueError, "sysroot"):
            self.apply_config()

    def test_cargo_symlink_keeps_proxy_name_and_can_be_found_on_path(self):
        cargo = Path(self.env["CARGO"])
        cargo.unlink()
        rustup = Path(executable(cargo.parent / "rustup"))
        cargo.symlink_to(rustup)
        del self.env["CARGO"]
        self.env["PATH"] = str(cargo.parent)
        result = native_defines(self.env)
        self.assertEqual(result["cargo"], str(cargo))
        self.assertNotEqual(result["cargo"], str(rustup))

    def test_explicit_rust_homes_are_used_and_must_exist(self):
        for variable, key in (("CARGO_HOME", "cargo_home"), ("RUSTUP_HOME", "rustup_home")):
            directory = self.base / variable
            directory.mkdir()
            self.env[variable] = str(directory)
            self.assertEqual(native_defines(self.env)[key], str(directory))
            directory.rmdir()
            with self.assertRaisesRegex(ValueError, variable):
                native_defines(self.env)
            del self.env[variable]

    def test_conflicting_unknown_duplicate_and_malformed_yaml_refused(self):
        for content in (
            "name: one\nname: two\n", "[]\n", "hooks: null\n",
            "hooks:\n  user_defines: []\n",
            "hooks:\n  user_defines:\n    hf_tokenizers: {unknown: bad}\n",
            "hooks:\n  user_defines:\n    hf_tokenizers: {target_os: linux}\n",
        ):
            with self.subTest(content=content):
                self.pubspec.write_text(content)
                with self.assertRaises(ValueError):
                    self.apply_config()
                self.assertEqual(self.pubspec.read_text(), content)

    def test_atomic_failure_preserves_original(self):
        with patch("configure_native.os.replace", side_effect=OSError("simulated failure")):
            with self.assertRaises(OSError):
                self.apply_config()
        self.assertEqual(self.pubspec.read_text(), self.original)
        self.assertEqual([p.name for p in self.root.iterdir()], ["pubspec.yaml"])

    def test_configure_never_executes_sdk_or_rust(self):
        with patch("subprocess.Popen", side_effect=AssertionError("must not execute tools")):
            self.assertTrue(self.apply_config())

    def test_actual_project_pubspec_can_be_configured_in_temporary_copy(self):
        # Read the real manifest but only ever write the temporary CI fixture.
        original = (ROOT / "pubspec.yaml").read_bytes()
        self.pubspec.write_bytes(original)
        before = yaml.safe_load(original)
        self.assertNotIn("hf_tokenizers", before.get("hooks", {}).get("user_defines", {}))
        self.assertTrue(self.apply_config())
        expected = yaml.safe_load(original)
        expected.setdefault("hooks", {}).setdefault("user_defines", {})["hf_tokenizers"] = native_defines(self.env)
        self.assertEqual(yaml.safe_load(self.pubspec.read_bytes()), expected)
        self.assertEqual((ROOT / "pubspec.yaml").read_bytes(), original)

    def test_hook_config_contract_matches_configurator(self):
        source = HOOK.read_text()
        keys = re.search(r"const _ohosKeys = \{(.*?)\};", source, re.S).group(1)
        self.assertEqual(set(re.findall(r"'([^']+)'", keys)), set(native_defines(self.env)))
        self.assertIn("input.userDefines[key]", source)
        self.assertIn("..['RUSTUP_TOOLCHAIN'] = config['rustup_toolchain']!", source)
        self.assertIn("['--dynamic', '--version-info', library.path]", source)
        self.assertIn("includeParentEnvironment: false", source)


RUN_HOOK = (sys.platform == "linux" and os.environ.get("GITHUB_ACTIONS") == "true"
            and bool(os.environ.get("HARMONY_NATIVE_TEST_DART")))


@unittest.skipUnless(RUN_HOOK, "CI-only opt-in Dart hook tests; local checks never run SDKs")
class HookExecutionTest(NativeFixture):
    def setUp(self):
        super().setUp()
        self.dart = os.environ["HARMONY_NATIVE_TEST_DART"]
        self.assertTrue(Path(self.dart).is_absolute() and Path(self.dart).is_file())
        self.defines = native_defines(self.env)
        self.log = self.base / "cargo.json"
        # Deliberately no shell or network: emulate cargo's target output.
        executable(Path(self.env["CARGO"]), f"""import json, os, pathlib, sys
pathlib.Path({str(self.log)!r}).write_text(json.dumps({{'argv': sys.argv[1:], 'env': dict(os.environ)}}))
target = sys.argv[sys.argv.index('--target') + 1]
out = pathlib.Path(os.environ['CARGO_TARGET_DIR']) / target / 'release/libtokenizers_ffi.so'
out.parent.mkdir(parents=True, exist_ok=True)
out.write_bytes(bytes.fromhex('7f454c460201010000000000000000000300b700') + bytes(44))
""", sys.executable)
        self.report = "Dynamic section at offset 0x100 contains 1 entries:\n  0x1 (NEEDED) Shared library: [libc.so]\n"
        self.readelf_log = self.base / "readelf.json"

    def run_hook(self, *, defines=None, os_name="linux", arch="arm64", report=None,
                 readelf_exit=0, build_code=True):
        executable(Path(self.env["OHOS_SDK_HOME"]) / "native/llvm/bin/llvm-readelf",
                   f"import json, pathlib, sys\n"
                   f"pathlib.Path({str(self.readelf_log)!r}).write_text(json.dumps(sys.argv[1:]))\n"
                   f"print({(self.report if report is None else report)!r})\n"
                   f"sys.exit({readelf_exit})\n", sys.executable)
        with tempfile.TemporaryDirectory(dir=self.base) as temporary:
            directory = Path(temporary)
            config = {
                "package_name": "hf_tokenizers",
                "package_root": str(ROOT / "third_party/hf_tokenizers") + "/",
                "out_dir_shared": str(directory / "shared") + "/",
                "out_file": str(directory / "output.json"),
                "config": {"build_asset_types": ["code_assets/code"] if build_code else [],
                           "linking_enabled": False,
                           "extensions": {"code_assets": {"target_os": os_name,
                              "target_architecture": arch, "link_mode_preference": "dynamic"}}},
                "user_defines": {"workspace_pubspec": {"base_path": str(self.root) + "/",
                    "defines": self.defines if defines is None else defines}},
            }
            input_file = directory / "input.json"
            input_file.write_text(json.dumps(config))
            result = subprocess.run(
                [self.dart, f"--packages={ROOT / '.dart_tool/package_config.json'}",
                 str(HOOK), f"--config={input_file}"],
                cwd=directory, capture_output=True, text=True, timeout=45,
                # Reproduce hooks_runner's filtering: no OHOS or Rust env.
                env={"HOME": str(self.home), "PATH": "/usr/bin:/bin"},
            )
            output = directory / "output.json"
            return result, json.loads(output.read_text()) if output.exists() else None

    def test_linux_shim_selects_ohos_and_passes_explicit_rust_environment(self):
        result, output = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIsNotNone(output)
        cargo = json.loads(self.log.read_text())
        self.assertEqual(cargo["argv"], ["build", "--release", "--locked", "--target",
                                        "aarch64-unknown-linux-ohos"])
        for key in ("RUSTUP_TOOLCHAIN", "OHOS_SDK_HOME", "MODU_OHOS_CLANG"):
            self.assertEqual(cargo["env"][key], self.env[key])
        self.assertEqual(cargo["env"]["CARGO_HOME"], str(self.home / ".cargo"))
        self.assertEqual(cargo["env"]["RUSTUP_HOME"], str(self.home / ".rustup"))
        self.assertEqual(cargo["env"]["CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER"],
                         self.env["MODU_OHOS_CLANG"])
        self.assertEqual(json.loads(self.readelf_log.read_text())[:2], ["--dynamic", "--version-info"])

    def test_unknown_missing_or_wrong_input_fails_before_cargo(self):
        variants = [dict(self.defines, unknown="value"), dict(self.defines, target_os="linux"),
                    dict(self.defines, rust_target="aarch64-unknown-linux-gnu"),
                    dict(self.defines, rustup_toolchain="stable"),
                    dict(self.defines, sdk_root="relative"),
                    dict(self.defines, target_architecture="x64"),
                    {"target_oss": "ohos"}]
        variants.extend({k: v for k, v in self.defines.items() if k != omitted}
                        for omitted in self.defines)
        for defines in variants:
            with self.subTest(defines=defines):
                result, _ = self.run_hook(defines=defines)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.log.exists())
        for target, arch in (("android", "arm64"), ("linux", "x64")):
            result, _ = self.run_hook(os_name=target, arch=arch)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(self.log.exists())

    def test_glibc_needed_and_version_information_rejected(self):
        for name in ("libc.so.6", "libm.so.6", "ld-linux-aarch64.so.1", "libstdc++.so.6"):
            with self.subTest(name=name):
                result, _ = self.run_hook(report=self.report.replace("libc.so", name))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Invalid OHOS dynamic dependencies", result.stderr)
        result, _ = self.run_hook(report=self.report + "Version needs: GLIBC_2.17\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Invalid OHOS dynamic dependencies", result.stderr)

    def test_bad_readelf_metadata_and_failure_rejected(self):
        for report in ("", "There is no dynamic section in this file.",
                       "Dynamic section\n(NEEDED) malformed\n",
                       self.report.replace("libc.so", "/usr/lib/libc.so")):
            with self.subTest(report=report):
                result, _ = self.run_hook(report=report)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Invalid OHOS dynamic dependencies", result.stderr)
        result, _ = self.run_hook(readelf_exit=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("OHOS readelf failed", result.stderr)

    def test_wrong_elf_architecture_rejected_before_readelf(self):
        cargo = Path(self.env["CARGO"])
        cargo.write_text(cargo.read_text().replace("0300b700", "03003e00"))
        result, _ = self.run_hook()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not an AArch64 ELF library", result.stderr)
        self.assertFalse(self.readelf_log.exists())

    def test_no_code_assets_retains_noop_behavior(self):
        result, _ = self.run_hook(defines={}, build_code=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.log.exists())


if __name__ == "__main__":
    unittest.main()
