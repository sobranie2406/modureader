"""Keep product docs distinct from upstream provenance and internal namespaces."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ProjectIdentityTest(unittest.TestCase):
    def test_only_current_chinese_and_english_homepages(self):
        self.assertEqual(
            {p.name for p in ROOT.glob("README*.md")},
            {"README.md", "README_EN.md"},
        )
        for name in ("README.md", "README_EN.md"):
            text = (ROOT / name).read_text()
            self.assertIn("sobranie2406/modureader/releases", text)
            self.assertIn("Anx Reader", text)  # attribution is not stale branding
            self.assertIn("ReadAny", text)

    def test_product_docs_do_not_send_users_to_upstream_services(self):
        paths = [ROOT / name for name in (
            "README.md", "README_EN.md", "SECURITY.md", "PRIVACY.md",
            "CONTRIBUTING.md", "docs/RELEASING.md", "docs/SETTINGS.md",
            "docs/troubleshooting.md", "docs/issue-triage.md",
        )]
        paths += list((ROOT / "fastlane/metadata/android").glob("*/*.txt"))
        prohibited = re.compile(
            r"github\.com/anxcye/anx-reader/(?:releases|issues)"
            r"|anx\.anxcye\.com|t\.me/AnxReader|id6743196413"
            r"|f-droid\.org/packages/com\.anxcye"
            r"|README_(?:RU|tr|zh)\.md",
            re.IGNORECASE,
        )
        for path in paths:
            with self.subTest(path=path.relative_to(ROOT)):
                self.assertIsNone(prohibited.search(path.read_text()))
        privacy = (ROOT / "PRIVACY.md").read_text()
        self.assertNotIn("不进入设置导出或同步", privacy)
        self.assertIn("默认也包含密码", privacy)
        self.assertIn("代码和二维码未加密", privacy)

    def test_current_changelog_is_modu_not_upstream_version_history(self):
        version = re.search(r"^version:\s*(\S+)", (ROOT / "pubspec.yaml").read_text(),
                            re.MULTILINE).group(1).split("+")[0]
        text = (ROOT / "assets/CHANGELOG.md").read_text()
        self.assertIn("## " + version, text)
        self.assertNotIn("## 1.15.0", text)
        self.assertNotIn("Anx-Reader has changed", text)
        # Current reader splits English and Chinese bullet lists into two halves.
        bullets = [line for line in text.splitlines() if line.startswith("- ")]
        self.assertGreater(len(bullets), 0)
        self.assertEqual(len(bullets) % 2, 0)
        half = len(bullets) // 2
        self.assertTrue(all(not re.search(r"[\u4e00-\u9fff]", b) for b in bullets[:half]))
        self.assertTrue(all(re.search(r"[\u4e00-\u9fff]", b) for b in bullets[half:]))
        archive = (ROOT / "docs/upstream/anx-reader-changelog.md").read_text()
        self.assertIn("not Modu version history", archive)
        self.assertIn("## 1.15.0", archive)

    def test_unused_purchase_path_and_plugins_are_removed(self):
        for name in ("lib/page/iap_page.dart", "lib/providers/iap.dart",
                     "lib/service/iap/app_store_iap_service.dart",
                     "lib/service/iap/play_store_iap_service.dart"):
            self.assertFalse((ROOT / name).exists(), name)
        for name in ("pubspec.yaml", "pubspec.lock", "lib/page/home_page.dart",
                     "lib/service/book.dart", "macos/Flutter/GeneratedPluginRegistrant.swift"):
            text = (ROOT / name).read_text()
            self.assertNotIn("in_app_purchase", text, name)
            self.assertNotIn("iapProvider", text, name)

    def test_no_legacy_release_workflows_or_broken_local_calls(self):
        folder = ROOT / ".github/workflows"
        for name in ("setup.yaml", "release.yaml", "build-windows-manual.yaml",
                     "build-appstore.yaml", "build-playstore.yaml"):
            self.assertFalse((folder / name).exists())
        self.assertTrue((folder / "build.yaml").is_file())
        for path in folder.iterdir():
            for call in re.findall(r"uses:\s*(\./\.github/workflows/[^\s]+)", path.read_text()):
                self.assertTrue((ROOT / call).is_file(), (path.name, call))

    def test_upstream_licenses_are_preserved(self):
        for name in ("LICENSE", "NOTICE", "LICENSES/Anx-Reader-MIT.txt",
                     "LICENSES/ReadAny-GPL-3.0-or-later.txt"):
            self.assertTrue((ROOT / name).is_file())
        self.assertIn("fonts.anxcye.com", (ROOT / "lib/providers/fonts.dart").read_text())


if __name__ == "__main__":
    unittest.main()
