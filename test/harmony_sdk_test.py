"""Temporary metadata fixtures only; no real SDK is read, installed, or executed.

Run locally: python3 -B -m unittest discover -s test -p harmony_sdk_test.py -v
"""

from contextlib import redirect_stderr, redirect_stdout
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts/harmony"))
import check_sdk


class HarmonySdkTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.sdk = Path(temporary.name) / "command-line-tools" / "sdk"
        self.metadata = self.sdk / "default" / "sdk-pkg.json"
        self.metadata.parent.mkdir(parents=True)
        self.env = {"GITHUB_ACTIONS": "true", "RUNNER_OS": "Linux", "RUNNER_ARCH": "X64"}

    def write_metadata(self, api_version="26", **extra):
        self.metadata.write_text(json.dumps({"data": {"apiVersion": api_version, **extra}}),
                                 encoding="utf-8")

    def check(self, root=None):
        with patch("check_sdk.os.environ", self.env), patch("check_sdk.sys.platform", "linux"):
            return check_sdk.check_sdk(self.sdk if root is None else root)

    def test_accepts_api26_and_newer_without_inspecting_or_executing_tools(self):
        for version in ("26", "27", "30"):
            with self.subTest(version=version):
                self.write_metadata(version, platformVersion="26.0.0")
                before = self.metadata.read_bytes()
                with patch("subprocess.Popen", side_effect=AssertionError("No SDK execution")):
                    self.assertEqual(self.check(), int(version))
                self.assertEqual(self.metadata.read_bytes(), before)
        self.assertEqual(list(self.sdk.rglob("*")), [self.metadata.parent, self.metadata])

    def test_api24_and_other_old_versions_fail_without_rewriting(self):
        for version in ("0", "17", "24", "25"):
            with self.subTest(version=version):
                self.write_metadata(version)
                before = self.metadata.read_bytes()
                with self.assertRaisesRegex(ValueError, "public APIs introduced in API 26"):
                    self.check()
                self.assertEqual(self.metadata.read_bytes(), before)

    def test_rejects_unsupported_formats_with_actionable_message(self):
        for value in (26, 26.0, True, None, [], {}, "", "26.0.0", "26.0", "26\n",
                      " 26", "26 ", "+26", "-26", "2e1", "２６"):
            with self.subTest(value=value):
                self.write_metadata(value)
                before = self.metadata.read_bytes()
                with self.assertRaises(ValueError) as error:
                    self.check()
                self.assertIn("Unsupported data.apiVersion format", str(error.exception))
                self.assertIn("string integer", str(error.exception))
                self.assertIn("do not rewrite official SDK metadata", str(error.exception))
                self.assertEqual(self.metadata.read_bytes(), before)

    def test_platform_version_cannot_replace_api_version(self):
        self.metadata.write_text('{"data":{"platformVersion":"26.0.0"}}')
        with self.assertRaisesRegex(ValueError, "Missing data.apiVersion"):
            self.check()

    def test_root_and_data_must_be_objects(self):
        for document in (None, [], 26, {}, {"data": None}, {"data": []}, {"data": "26"}):
            with self.subTest(document=document):
                self.metadata.write_text(json.dumps(document))
                with self.assertRaisesRegex(ValueError, "data object"):
                    self.check()

    def test_malformed_json_utf8_and_duplicate_fields_fail(self):
        for content in (b"not json", b'{"data":', b"\xff",
                        b'{"data":{"apiVersion":"24","apiVersion":"26"}}',
                        b'{"data":{"apiVersion":"24"},"data":{"apiVersion":"26"}}'):
            with self.subTest(content=content):
                self.metadata.write_bytes(content)
                with self.assertRaisesRegex(ValueError, "Invalid SDK metadata"):
                    self.check()
                self.assertEqual(self.metadata.read_bytes(), content)

    def test_missing_metadata_and_directory_instead_of_file_fail(self):
        with self.assertRaisesRegex(ValueError, "Missing SDK metadata file"):
            self.check()
        self.metadata.mkdir()
        with self.assertRaisesRegex(ValueError, "Missing SDK metadata file"):
            self.check()

    def test_wrong_root_depth_relative_root_and_nonexistent_root_fail(self):
        self.write_metadata()
        for root in (self.sdk.parent, self.sdk / "default"):
            with self.subTest(root=root):
                with self.assertRaisesRegex(ValueError, "not sdk/default"):
                    self.check(root)
        for root in (Path("sdk"), self.sdk / "missing", self.metadata):
            with self.subTest(root=root):
                with self.assertRaisesRegex(ValueError, "existing absolute directory"):
                    self.check(root)

    def test_ci_guard_runs_before_any_metadata_access(self):
        for key, value in (("GITHUB_ACTIONS", "false"), ("RUNNER_OS", "Windows"),
                           ("RUNNER_ARCH", "ARM64")):
            with self.subTest(key=key), patch.dict(self.env, {key: value}):
                with patch.object(Path, "is_dir", side_effect=AssertionError("No local access")):
                    with self.assertRaisesRegex(ValueError, "GitHub Actions"):
                        self.check()
        with patch("check_sdk.os.environ", self.env), patch("check_sdk.sys.platform", "darwin"):
            with self.assertRaisesRegex(ValueError, "no local SDK access"):
                check_sdk.check_sdk(self.sdk)

    def test_cli_success_reports_metadata_scope_and_failure_has_no_traceback(self):
        for version, expected_exit in (("26", None), ("24", 1), ("26.0.0", 1)):
            with self.subTest(version=version):
                self.write_metadata(version)
                stdout, stderr = io.StringIO(), io.StringIO()
                with patch("check_sdk.os.environ", self.env), patch("check_sdk.sys.platform", "linux"), \
                     patch("sys.argv", ["check_sdk.py", str(self.sdk)]), \
                     redirect_stdout(stdout), redirect_stderr(stderr):
                    if expected_exit is None:
                        check_sdk.main()
                    else:
                        with self.assertRaises(SystemExit) as error:
                            check_sdk.main()
                        self.assertEqual(error.exception.code, expected_exit)
                if expected_exit is None:
                    self.assertIn("SDK metadata OK", stdout.getvalue())
                    self.assertIn("are not verified", stdout.getvalue())
                    self.assertEqual(stderr.getvalue(), "")
                else:
                    self.assertIn("check_sdk:", stderr.getvalue())
                    self.assertNotIn("Traceback", stderr.getvalue())
                    self.assertEqual(stdout.getvalue(), "")


if __name__ == "__main__":
    unittest.main()
