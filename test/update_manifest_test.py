"""The mirror manifest preserves release integrity metadata, not API secrets."""
import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts/release"))
from update_manifest import create_manifest


class UpdateManifestTest(unittest.TestCase):
    def fixture(self):
        tag = "v1.0.9"
        names = [f"Modu-1.0.9-{platform}-{arch}{suffix}"
                 for platform, suffix in [("android", ".apk"), ("macos", ".dmg"),
                                          ("linux", ".deb"), ("windows", "-setup.exe")]
                 for arch in ("arm64", "x64")]
        names.append("Modu-1.0.9-ios-arm64.ipa")
        return dict(tag_name=tag, draft=False, prerelease=False, body="Changes",
                    upload_url="must not be copied", private_field="must not be copied",
                    assets=[dict(name=name, size=1234, state="uploaded",
                                 digest="sha256:" + "A" * 64,
                                 browser_download_url=f"https://github.com/sobranie2406/modureader/releases/download/{tag}/{name}",
                                 uploader={"private_field": "must not be copied"})
                            for name in names])

    def test_preserves_only_public_required_metadata_and_all_architectures(self):
        manifest = create_manifest(self.fixture())
        self.assertEqual(manifest["modu_update_schema"], 1)
        self.assertEqual(len(manifest["assets"]), 9)
        self.assertEqual(manifest["assets"][0]["digest"], "sha256:" + "a" * 64)
        self.assertNotIn("must not be copied", str(manifest))
        self.assertEqual(manifest["tag_name"], "v1.0.9")

    def test_missing_and_duplicate_packages_are_rejected(self):
        release = self.fixture()
        release["assets"].pop()
        with self.assertRaises(ValueError):
            create_manifest(release)
        release = self.fixture()
        release["assets"].append(copy.deepcopy(release["assets"][0]))
        with self.assertRaises(ValueError):
            create_manifest(release)

    def test_invalid_or_untrusted_assets_are_rejected(self):
        for mutation in [dict(size=0), dict(size=True), dict(size=2**32),
                         dict(state="uploading"), dict(digest="sha256:wrong"),
                         dict(browser_download_url="https://example.com/installer")]:
            with self.subTest(mutation=mutation):
                release = self.fixture()
                release["assets"][0].update(mutation)
                with self.assertRaises(ValueError):
                    create_manifest(release)

    def test_nonstable_releases_are_rejected(self):
        for mutation in [dict(draft=True), dict(prerelease=True),
                         dict(tag_name="v1.0.9-beta.1"), dict(tag_name="../file")]:
            with self.subTest(mutation=mutation):
                release = self.fixture()
                release.update(mutation)
                with self.assertRaises(ValueError):
                    create_manifest(release)


if __name__ == "__main__":
    unittest.main()
