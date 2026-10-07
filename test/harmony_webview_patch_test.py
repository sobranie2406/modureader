"""No SDK or network required. Set HARMONY_WEBVIEW_UPSTREAM to the pinned Git
checkout to enable the real-source integration and native control-flow tests.
All generated files live in temporary test directories, never the application.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/harmony'))
import patch_webview as installer
from webview_615_patch import PIN, PACKAGES, replacements, transform


def cached_dart():
    """Bypass Flutter's shell wrapper: tests must not update/install any SDK."""
    explicit = os.environ.get('HARMONY_TEST_DART')
    if explicit:
        return explicit
    command = shutil.which('dart')
    if command:
        binary = Path(command).resolve().parent / 'cache/dart-sdk/bin/dart'
        if binary.is_file():
            return str(binary)
    return None


class WebViewSafetyTest(unittest.TestCase):
    def test_refuses_local_workspace_before_writing(self):
        with patch.dict(os.environ, {'GITHUB_ACTIONS': 'false'}):
            with self.assertRaisesRegex(ValueError, 'Linux GitHub Actions'):
                installer.install(ROOT)

    def test_refuses_wrong_workspace(self):
        with patch.dict(os.environ, {'GITHUB_ACTIONS': 'true', 'RUNNER_OS': 'Linux',
                                    'GITHUB_WORKSPACE': '/not-the-workspace'}):
            with self.assertRaises(ValueError):
                installer.assert_runner(ROOT)

    def test_rejects_wrong_lock_before_reading_checkout(self):
        with self.assertRaisesRegex(ValueError, 'exact approved'):
            installer.verified_files(Path('/missing'), PACKAGES[0], {'resolved-ref': 'bad'})

    def test_missing_anchor_fails_closed(self):
        sources = {path: '' for path, *_ in replacements()}
        with self.assertRaisesRegex(ValueError, 'anchor count'):
            transform(sources)


@unittest.skipUnless(os.environ.get('HARMONY_WEBVIEW_UPSTREAM'), 'supply the pinned upstream checkout')
class WebViewRealSourceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.upstream = Path(os.environ['HARMONY_WEBVIEW_UPSTREAM']).resolve()
        if installer.git(cls.upstream, 'rev-parse', 'HEAD') != PIN:
            raise ValueError('Integration tests require the exact upstream pin')
        cls.sources = {path: (cls.upstream / path).read_text() for path, *_ in replacements()}
        cls.patched = transform(cls.sources)

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        (self.root / '.dart_tool').mkdir()
        roots = []
        for manifest in self.upstream.glob('*/pubspec.yaml'):
            roots.append({'name': manifest.parent.name, 'rootUri': manifest.parent.as_uri()})
        roots.append({'name': 'flutter_inappwebview_internal_annotations',
                      'rootUri': (self.upstream / 'dev_packages/flutter_inappwebview_internal_annotations').as_uri()})
        (self.root / '.dart_tool/package_config.json').write_text(json.dumps({'packages': roots}))
        self.overlay = {'dependency_overrides': {
            'hf_tokenizers': {'path': 'third_party/hf_tokenizers'},
            'unrelated': {'git': {'url': 'https://example.invalid/keep', 'ref': 'keep'}},
            **{name: {'git': {'url': installer.REPOSITORY, 'ref': PIN, 'path': name}} for name in PACKAGES},
        }, 'unrelated_top_level': 'keep'}
        (self.root / 'pubspec_overrides.yaml').write_text(yaml.safe_dump(self.overlay))
        lock = {'packages': {name: {'source': 'git', 'description': {
            'url': installer.REPOSITORY, 'ref': PIN, 'resolved-ref': PIN, 'path': name,
        }} for name in PACKAGES}}
        (self.root / 'pubspec.lock').write_text(yaml.safe_dump(lock))
        (self.root / 'pubspec.yaml').write_text('name: unchanged_app\n')
        (self.root / 'lib').mkdir()
        (self.root / 'lib/main.dart').write_text('// must not change\n')

    def test_patches_apply_once_and_drift_is_rejected(self):
        self.assertEqual(len(self.patched), 12)
        with self.assertRaises(ValueError):
            transform(self.patched)
        changed = dict(self.sources)
        path, old, *_ = replacements()[0]
        changed[path] = changed[path].replace(old, old + old)
        with self.assertRaises(ValueError):
            transform(changed)

    def test_merge_and_external_sibling_paths(self):
        before = {name: (self.root / name).read_bytes() for name in
                  ('pubspec.yaml', 'pubspec.lock', 'pubspec_overrides.yaml', 'lib/main.dart')}
        files, overlay = installer.plan(self.root)
        self.assertEqual(overlay['unrelated_top_level'], 'keep')
        for name in ('unrelated', 'hf_tokenizers'):
            self.assertEqual(overlay['dependency_overrides'][name], self.overlay['dependency_overrides'][name])
        for name in PACKAGES:
            self.assertEqual(overlay['dependency_overrides'][name], {'path': f'build/harmony-adapters/{name}'})
        manifest = yaml.safe_load(files[PACKAGES[0] + '/pubspec.yaml'][0])
        self.assertEqual(manifest['dependencies'][PACKAGES[1]], {'path': '../' + PACKAGES[1]})
        self.assertEqual(manifest['dependencies']['flutter_inappwebview_android'],
                         {'path': str(self.upstream / 'flutter_inappwebview_android')})
        for name, content in before.items():
            self.assertEqual((self.root / name).read_bytes(), content)

    def test_lock_pin_mismatch_is_rejected(self):
        lock = yaml.safe_load((self.root / 'pubspec.lock').read_text())
        lock['packages'][PACKAGES[2]]['description']['resolved-ref'] = '0' * 40
        (self.root / 'pubspec.lock').write_text(yaml.safe_dump(lock))
        with self.assertRaisesRegex(ValueError, 'exact approved'):
            installer.plan(self.root)
        self.assertFalse((self.root / 'build').exists())

    def test_install_only_copies_three_packages_and_re_resolves(self):
        real_roots = installer.package_roots
        calls = []

        def fake_pub_get(command, **kwargs):
            calls.append(command)
            data = json.loads((self.root / '.dart_tool/package_config.json').read_text())
            for package in data['packages']:
                if package['name'] in PACKAGES:
                    package['rootUri'] = (self.root / installer.DESTINATION / package['name']).as_uri()
            (self.root / '.dart_tool/package_config.json').write_text(json.dumps(data))

        # Source Git commands use check_output -> subprocess.run too. Preflight
        # before mocking run to make the mock cover only the second pub get.
        write_plan = installer.plan(self.root)
        with patch.object(installer, 'assert_runner', return_value=Path('/isolated/flutter/bin/flutter')), \
                patch.object(installer, 'plan', return_value=write_plan), \
                patch.object(installer.subprocess, 'run', side_effect=fake_pub_get):
            installer.install(self.root)
        self.assertEqual(calls, [['/isolated/flutter/bin/flutter', 'pub', 'get']])
        self.assertEqual({p.name for p in (self.root / installer.DESTINATION).iterdir()},
                         set(PACKAGES) | {'PROVENANCE.json'})
        self.assertEqual((self.root / 'pubspec.yaml').read_text(), 'name: unchanged_app\n')
        self.assertEqual((self.root / 'lib/main.dart').read_text(), '// must not change\n')
        for name in PACKAGES:
            self.assertEqual(real_roots(self.root)[name], self.root / installer.DESTINATION / name)
        with patch.object(installer, 'assert_runner', return_value=Path('/isolated/flutter/bin/flutter')):
            with self.assertRaisesRegex(ValueError, 'Refusing to overwrite'):
                installer.install(self.root)

    def test_pub_failure_restores_resolution_inputs(self):
        names = ('pubspec_overrides.yaml', 'pubspec.lock', '.dart_tool/package_config.json')
        before = {name: (self.root / name).read_bytes() for name in names}
        write_plan = installer.plan(self.root)
        with patch.object(installer, 'assert_runner', return_value=Path('/isolated/flutter/bin/flutter')), \
                patch.object(installer, 'plan', return_value=write_plan), \
                patch.object(installer.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'flutter')):
            with self.assertRaises(subprocess.CalledProcessError):
                installer.install(self.root)
        for name, content in before.items():
            self.assertEqual((self.root / name).read_bytes(), content)

    def test_native_guard_focus_and_zoom_control_flow(self):
        result = subprocess.run(['node', str(ROOT / 'test/harmony_webview_runtime_test.cjs')],
                                input=json.dumps(self.patched), text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('checks passed', result.stdout)

    @unittest.skipUnless(cached_dart(), 'Set HARMONY_TEST_DART to an existing SDK binary')
    def test_dart_syntax(self):
        paths = []
        for name, source in self.patched.items():
            if name.endswith('.dart'):
                target = self.root / 'syntax' / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(source)
                paths.append(str(target))
        result = subprocess.run([cached_dart(), 'format', '--output=none', *paths], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
