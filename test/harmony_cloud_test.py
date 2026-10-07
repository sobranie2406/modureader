"""Cloud packaging must be separate from existing release/signing workflows."""
import hashlib
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/harmony'))
from collect_unsigned import collect
from verify_tools import verify
from prepare import overrides, prepare


def fixture(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, 'w') as archive:
        archive.writestr('module.json', '{"module":{"name":"entry"}}')


class HarmonyCloudTest(unittest.TestCase):
    def test_overlay_keeps_other_clients_manifest_and_local_adapters(self):
        original = (ROOT / 'pubspec.yaml').read_bytes()
        data = overrides(ROOT)['dependency_overrides']
        self.assertEqual((ROOT / 'pubspec.yaml').read_bytes(), original)
        self.assertEqual(data['hf_tokenizers'], {'path': 'third_party/hf_tokenizers'})
        self.assertEqual(data['icons_plus'], {'path': 'third_party/icons_plus'})
        self.assertIn('git', data['flutter_inappwebview_windows'])
        for name in ('sqflite_ohos', 'path_provider_ohos', 'shared_preferences_ohos',
                     'flutter_inappwebview_ohos', 'audioplayers_ohos'):
            self.assertRegex(data[name]['git']['ref'], r'^[0-9a-f]{40}$')

    def test_overlay_refuses_local_workspace(self):
        with patch.dict('os.environ', {'GITHUB_ACTIONS': 'false'}):
            with self.assertRaisesRegex(ValueError, 'Run only on GitHub Actions'):
                prepare(ROOT)

    def test_runner_adds_missing_federated_dependency_without_changing_original(self):
        import yaml
        original = (ROOT / 'pubspec.yaml').read_bytes()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'pubspec.yaml').write_bytes(original)
            shutil.copytree(ROOT / 'scripts/harmony', root / 'scripts/harmony')
            with patch.dict('os.environ', {'GITHUB_ACTIONS': 'true'}):
                prepare(root)
                with self.assertRaisesRegex(ValueError, 'existing dependency overlay'):
                    prepare(root)
            manifest = yaml.safe_load((root / 'pubspec.yaml').read_text())
            self.assertIn('flutter_inappwebview_windows', manifest['dependencies'])
            expected = yaml.safe_load(original)
            manifest['dependencies'].pop('flutter_inappwebview_windows')
            self.assertEqual(manifest, expected)
        self.assertEqual((ROOT / 'pubspec.yaml').read_bytes(), original)

    def test_profiles_remain_unsigned(self):
        import json
        profile = json.loads((ROOT / 'ohos/build-profile.json5').read_text())
        self.assertEqual(profile['app']['signingConfigs'], [])
        for product in profile['app']['products']:
            self.assertNotIn('signingConfig', product)
            self.assertEqual(product['targetSdkVersion'], '6.1.1(24)')

    def test_tools_download_validation(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'tools.zip.part'
            path.write_bytes(b'<html>Please log in</html>')
            with self.assertRaisesRegex(ValueError, 'not a ZIP'):
                verify(path, hashlib.sha256(path.read_bytes()).hexdigest())
            fixture(path)
            with self.assertRaisesRegex(ValueError, 'SHA-256 mismatch'):
                verify(path, '0' * 64)
            verify(path, hashlib.sha256(path.read_bytes()).hexdigest())
            path.write_bytes(path.read_bytes()[:-20])
            with self.assertRaisesRegex(ValueError, 'invalid ZIP'):
                verify(path, hashlib.sha256(path.read_bytes()).hexdigest())

    def test_tools_archive_rejects_traversal(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'tools.zip'
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr('../outside', 'invalid')
            with self.assertRaisesRegex(ValueError, 'Unsafe ZIP'):
                verify(path, hashlib.sha256(path.read_bytes()).hexdigest())

    def test_only_unsigned_hap_and_checksum_collected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root / 'ohos/entry/build/entry-unsigned.hap')
            fixture(root / 'ohos/entry/build/entry-signed.hap')
            (root / 'ohos/private.p12').write_bytes(b'private fixture')
            self.assertEqual(len(collect(root)), 1)
            output = root / 'build/harmony-unsigned'
            self.assertEqual({p.name for p in output.iterdir()}, {'SHA256SUMS', 'entry-unsigned.hap'})
            digest = hashlib.sha256((output / 'entry-unsigned.hap').read_bytes()).hexdigest()
            self.assertEqual((output / 'SHA256SUMS').read_text(), f'{digest}  entry-unsigned.hap\n')

    def test_no_output_is_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, 'No unsigned HAP'):
                collect(Path(tmp))

    def test_prefers_flutter_final_output_over_hvigor_copy(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root / 'ohos/entry/build/entry-unsigned.hap')
            final = root / 'build/ohos/hap/entry-unsigned.hap'
            fixture(final)
            self.assertEqual(collect(root), [final.resolve()])

    def test_duplicate_names_fail_without_overwriting(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root / 'ohos/a/entry-unsigned.hap')
            fixture(root / 'ohos/b/entry-unsigned.hap')
            with self.assertRaisesRegex(ValueError, 'duplicate'):
                collect(root)
            self.assertFalse((root / 'build/harmony-unsigned').exists())

    def test_invalid_archive_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / 'ohos/a-unsigned.hap'
            path.parent.mkdir()
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr('readme.txt', 'not an app')
            with self.assertRaisesRegex(ValueError, 'module.json'):
                collect(root)

    def test_external_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            fixture(base / 'outside-unsigned.hap')
            root = base / 'workspace'
            (root / 'ohos').mkdir(parents=True)
            (root / 'ohos/entry-unsigned.hap').symlink_to(base / 'outside-unsigned.hap')
            with self.assertRaisesRegex(ValueError, 'outside'):
                collect(root)

    def test_tools_script_refuses_local_install(self):
        result = subprocess.run(['bash', str(ROOT / 'scripts/harmony/cloud-tools.sh')],
                                env={'PATH': '/usr/bin:/bin', 'GITHUB_ACTIONS': 'false'},
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Run only on GitHub Actions', result.stderr)

    def test_tools_script_supports_verified_node_layout(self):
        script = (ROOT / 'scripts/harmony/cloud-tools.sh').read_text()
        self.assertIn('"$tool_root/tool/node/bin/node"', script)
        self.assertIn('"$tool_root/node/bin/node"', script)
        self.assertIn("printf 'DEVECO_NODE_HOME=%s", script)
        self.assertIn('"$node_home/bin"', script)
        self.assertIn('HOS_SDK_HOME=%s', script)

    def test_cloud_workflow_has_no_release_or_signing_secret(self):
        workflow = (ROOT / '.github/workflows/harmony-cloud.yml').read_text()
        self.assertIn('workflow_dispatch:', workflow)
        self.assertIn("branches: ['codex/harmony-cloud']", workflow)
        self.assertNotIn('tags:', workflow)
        self.assertIn('contents: read', workflow)
        self.assertNotIn('${{ runner.temp }}', workflow)
        self.assertNotIn('contents: write', workflow)
        self.assertNotIn('gh release', workflow)
        self.assertNotIn('continue-on-error', workflow)
        self.assertIn('62357a93d653bf844f730bb1f4b7cc9e2139d14e', workflow)
        self.assertNotIn('secrets.HARMONY_SIGN', workflow)
        self.assertIn('build hap --release --no-codesign --no-pub', workflow)
        self.assertIn('GIT_CONFIG_KEY_0=lfs.fetchexclude', workflow)
        self.assertNotIn('GIT_LFS_SKIP_SMUDGE', workflow)
        self.assertLess(workflow.index('- name: Resolve dependencies'),
                        workflow.index('- name: Install verified Huawei'))
        self.assertLess(workflow.index('- name: Install verified Huawei'),
                        workflow.index('- name: Generate Flutter plugin metadata'))
        self.assertIn('export FLUTTER_ROOT="$MODU_OHOS_FLUTTER"', workflow)


if __name__ == '__main__':
    unittest.main()
