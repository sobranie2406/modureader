"""Read real resolved sources; all writes are confined to disposable fixtures.

Run: python3 -B test/harmony_ui_test.py (requires PyYAML, no SDK/network).
Missing real source is a test failure, not a silent skip.
"""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
PROJECT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('patch_ui', PROJECT / 'scripts/harmony/patch_ui.py')
ui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ui)


class HarmonyUiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.real_roots = ui.package_roots(PROJECT)
        cls.sources = {}
        for name in ui.PATCHES:
            package, relative = name.split('/', 1)
            cls.sources[name] = (cls.real_roots[package] / relative).read_bytes()
        cls.manifests = {p: (cls.real_roots[p] / 'pubspec.yaml').read_bytes() for p in ui.PACKAGES}

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='harmony-ui-test-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.root = self.base / 'checkout'
        self.cache = self.base / 'cache'
        self.root.mkdir()
        (self.root / '.dart_tool').mkdir()
        self.lock = {'packages': {}}
        self.config = {'configVersion': 2, 'packages': []}
        for package, (version, sha) in ui.PACKAGES.items():
            source = self.cache / 'hosted/pub.dev' / f'{package}-{version}'
            source.mkdir(parents=True)
            (source / 'pubspec.yaml').write_bytes(self.manifests[package])
            (source / 'untouched.txt').write_bytes(b'fixture: preserve non-patched files\n')
            self.lock['packages'][package] = {
                'source': 'hosted', 'version': version,
                'description': {'name': package, 'url': 'https://pub.dev', 'sha256': sha},
            }
            self.config['packages'].append({'name': package, 'rootUri': source.as_uri(), 'packageUri': 'lib/'})
        for name, content in self.sources.items():
            package, relative = name.split('/', 1)
            file = self.source(package) / relative
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(content)
        self.overlay = {'dependency_overrides': {
            'flutter_inappwebview': {'path': 'build/harmony-adapters/flutter_inappwebview'},
            'flutter_inappwebview_platform_interface': {'path': 'build/harmony-adapters/flutter_inappwebview_platform_interface'},
            'flutter_inappwebview_ohos': {'path': 'build/harmony-adapters/flutter_inappwebview_ohos'},
            'other': {'git': {'url': 'https://example.invalid/dependency', 'ref': 'pinned'}},
        }, 'resolution': 'workspace'}
        self.write_yaml('pubspec.yaml', {'name': 'fixture', 'dependency_overrides': {'root_only': '1.0.0'}})
        self.write_yaml('pubspec_overrides.yaml', self.overlay)
        self.save_lock()
        self.save_config()
        self.sdk = self.base / 'sdk'
        (self.sdk / 'bin').mkdir(parents=True)
        (self.sdk / 'bin/flutter').write_text('NOT EXECUTABLE: tests must mock subprocess.run\n')
        env = patch.dict(os.environ, {
            'PUB_CACHE': str(self.cache), 'GITHUB_ACTIONS': 'true', 'RUNNER_OS': 'Linux',
            'GITHUB_WORKSPACE': str(self.root), 'MODU_OHOS_FLUTTER': str(self.sdk),
        })
        env.start()
        self.addCleanup(env.stop)
        # An unexpected external command must fail every test, never launch an SDK.
        self.process = patch.object(ui.subprocess, 'run', side_effect=AssertionError('Unexpected subprocess'))
        self.process.start()
        self.addCleanup(self.process.stop)

    def source(self, package='mongol'):
        return self.cache / 'hosted/pub.dev' / f'{package}-{ui.PACKAGES[package][0]}'

    def write_yaml(self, name, data):
        (self.root / name).write_text(ui.yaml.safe_dump(data))

    def save_lock(self):
        self.write_yaml('pubspec.lock', self.lock)

    def save_config(self):
        (self.root / '.dart_tool/package_config.json').write_text(json.dumps(self.config))

    def snapshot(self):
        return {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob('*') if p.is_file()}

    def pub_success(self, command, *, cwd, check):
        self.assertEqual(command, [str(self.sdk / 'bin/flutter'), 'pub', 'get'])
        self.assertEqual(cwd, self.root)
        self.assertTrue(check)
        for entry in self.config['packages']:
            entry['rootUri'] = (self.root / ui.DESTINATION / entry['name']).as_uri()
            self.lock['packages'][entry['name']]['source'] = 'path'
        self.save_lock()
        self.save_config()

    def run_install(self, effect=None):
        with patch.object(ui.sys, 'platform', 'linux'), patch.object(ui.subprocess, 'run', side_effect=effect or self.pub_success) as run:
            ui.install(self.root)
            return run

    def test_01_exact_real_source_patch_only_40_case_labels(self):
        self.assertEqual(len(ui.PATCHES), 11)
        total = 0
        for name, original in self.sources.items():
            with self.subTest(name=name):
                result = ui.transform(name, original)
                lines = result.splitlines(keepends=True)
                inserted = [i for i, line in enumerate(lines) if line.strip() == b'case TargetPlatform.ohos:']
                self.assertEqual(len(inserted), len(ui.PATCHES[name][1]))
                for i in inserted:
                    self.assertEqual(lines[i + 1], lines[i].replace(b'.ohos:', b'.android:'))
                self.assertEqual(b''.join(line for line in lines if line.strip() != b'case TargetPlatform.ohos:'), original)
                total += len(inserted)
        self.assertEqual(total, 40)

    def test_02_commented_math_switch_untouched(self):
        name = 'flutter_math_fork/lib/src/render/layout/line_editable.dart'
        comments = lambda data: [l for l in data.splitlines() if l.lstrip().startswith(b'//')]
        self.assertEqual(comments(self.sources[name]), comments(ui.transform(name, self.sources[name])))

    def test_03_plan_readonly_and_preserves_overrides(self):
        before = self.snapshot()
        files, overlay = ui.plan(self.root)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(overlay['resolution'], 'workspace')
        for key, value in self.overlay['dependency_overrides'].items():
            self.assertEqual(overlay['dependency_overrides'][key], value)
        self.assertEqual(overlay['dependency_overrides']['root_only'], '1.0.0')
        for package in ui.PACKAGES:
            self.assertIn(f'{package}/untouched.txt', files)
            self.assertEqual(files[f'{package}/pubspec.yaml'][0], self.manifests[package])

    def test_04_versions_fail_closed(self):
        for package in ui.PACKAGES:
            with self.subTest(package=package):
                original = self.lock['packages'][package]['version']
                self.lock['packages'][package]['version'] = '999.0.0'
                self.save_lock()
                with self.assertRaisesRegex(ValueError, 'hosted pub.dev'):
                    ui.plan(self.root)
                self.lock['packages'][package]['version'] = original

    def test_05_lock_identity_fail_closed(self):
        entry = self.lock['packages']['mongol']
        original = copy.deepcopy(entry)
        for field, value in [('source', 'git'), ('url', 'https://mirror.invalid'), ('name', 'other'), ('sha256', '0' * 64)]:
            with self.subTest(field=field):
                entry.clear()
                entry.update(copy.deepcopy(original))
                (entry if field == 'source' else entry['description'])[field] = value
                self.save_lock()
                with self.assertRaises(ValueError):
                    ui.plan(self.root)

    def test_06_manifest_name_version(self):
        for field in ('name', 'version'):
            manifest = ui.load_yaml(self.manifests['mongol'])
            manifest[field] = 'wrong'
            (self.source() / 'pubspec.yaml').write_text(ui.yaml.safe_dump(manifest))
            with self.assertRaisesRegex(ValueError, 'manifest name/version'):
                ui.plan(self.root)

    def test_07_wrong_package_config_path(self):
        self.config['packages'][0]['rootUri'] = self.source('mongol').as_uri()
        self.save_config()
        with self.assertRaisesRegex(ValueError, 'cache path'):
            ui.plan(self.root)

    def test_08_config_uri_and_package_uri(self):
        original = copy.deepcopy(self.config)
        for field, value in [('rootUri', 'https://pub.dev/package'), ('rootUri', 'file://evil.invalid/source'), ('packageUri', 'other/')]:
            self.config = copy.deepcopy(original)
            self.config['packages'][0][field] = value
            self.save_config()
            with self.assertRaises(ValueError):
                ui.plan(self.root)

    def test_09_duplicate_config_name(self):
        self.config['packages'].append(self.config['packages'][0])
        self.save_config()
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            ui.plan(self.root)

    def test_10_duplicate_yaml_override(self):
        (self.root / 'pubspec_overrides.yaml').write_text('dependency_overrides:\n  x: 1\n  x: 2\n')
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            ui.plan(self.root)

    def test_11_source_file_symlink(self):
        (self.source() / 'linked').symlink_to(self.source() / 'pubspec.yaml')
        with self.assertRaisesRegex(ValueError, 'symlink'):
            ui.plan(self.root)

    def test_12_source_directory_symlink(self):
        (self.source() / 'linked-dir').symlink_to(self.source() / 'lib', target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'symlink'):
            ui.plan(self.root)

    def test_13_package_root_symlink(self):
        source = self.source()
        moved = source.with_name('moved')
        source.rename(moved)
        source.symlink_to(moved, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'symlink'):
            ui.plan(self.root)

    def test_14_build_overlay_and_metadata_symlinks(self):
        for relative in ('build', 'pubspec_overrides.yaml', '.dart_tool/package_config.json'):
            with self.subTest(relative=relative):
                target = self.root / relative
                original = target.read_bytes() if target.is_file() else None
                if target.exists():
                    target.unlink()
                target.symlink_to(self.base / 'missing')
                with self.assertRaisesRegex(ValueError, 'symlink'):
                    ui.plan(self.root)
                target.unlink()
                if original is not None:
                    target.write_bytes(original)

    def test_15_source_drift_and_double_patch(self):
        for name, original in self.sources.items():
            for content in (original + b'\n', ui.transform(name, original)):
                with self.assertRaisesRegex(ValueError, 'SHA256 mismatch'):
                    ui.transform(name, content)

    def test_16_runner_guard(self):
        with patch.object(ui.sys, 'platform', 'linux'):
            self.assertEqual(ui.assert_runner(self.root), self.sdk / 'bin/flutter')
            for key, value in [('GITHUB_ACTIONS', 'false'), ('RUNNER_OS', 'macOS'), ('GITHUB_WORKSPACE', str(self.base)), ('MODU_OHOS_FLUTTER', '')]:
                with patch.dict(os.environ, {key: value}), self.assertRaises(ValueError):
                    ui.assert_runner(self.root)
        with patch.object(ui.sys, 'platform', 'darwin'), self.assertRaises(ValueError):
            ui.assert_runner(self.root)

    def test_17_install_pub_get_verified_and_only_expected_writes(self):
        before = self.snapshot()
        run = self.run_install()
        run.assert_called_once()
        after = self.snapshot()
        self.assertEqual(after['pubspec.yaml'], before['pubspec.yaml'])
        allowed = {'pubspec_overrides.yaml', 'pubspec.lock', '.dart_tool/package_config.json'}
        self.assertTrue(all(name in allowed or name.startswith(str(ui.DESTINATION) + '/') for name in after if after[name] != before.get(name)))
        provenance = json.loads((self.root / ui.DESTINATION / 'PROVENANCE.json').read_text())
        for name, digest in provenance['files'].items():
            self.assertEqual(hashlib.sha256((self.root / ui.DESTINATION / name).read_bytes()).hexdigest(), digest)
        overlay = ui.load_yaml((self.root / 'pubspec_overrides.yaml').read_bytes())
        for name, value in self.overlay['dependency_overrides'].items():
            self.assertEqual(overlay['dependency_overrides'][name], value)

    def test_18_pub_failure_restores_resolution(self):
        before = self.snapshot()
        def failure(*args, **kwargs):
            (self.root / 'pubspec.lock').write_text('partially changed')
            raise subprocess.CalledProcessError(1, args[0])
        with self.assertRaises(subprocess.CalledProcessError):
            self.run_install(failure)
        for name, data in before.items():
            self.assertEqual((self.root / name).read_bytes(), data)
        self.assertTrue((self.root / ui.DESTINATION / 'PROVENANCE.json').is_file())

    def test_19_pub_success_wrong_resolution_still_fails(self):
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, 'exact patched adapter'):
            self.run_install(lambda *args, **kwargs: None)
        for name, data in before.items():
            self.assertEqual((self.root / name).read_bytes(), data)

    def test_20_existing_destination_refused(self):
        (self.root / ui.DESTINATION).mkdir(parents=True)
        with self.assertRaisesRegex(ValueError, 'already exist'):
            self.run_install()

    def test_21_missing_overlay_created_and_failure_removes_it(self):
        overlay = self.root / 'pubspec_overrides.yaml'
        overlay.unlink()
        _, planned = ui.plan(self.root)
        self.assertIn('root_only', planned['dependency_overrides'])
        with self.assertRaises(subprocess.CalledProcessError):
            self.run_install(lambda *a, **k: (_ for _ in ()).throw(subprocess.CalledProcessError(1, a[0])))
        self.assertFalse(overlay.exists())

    def test_22_full_real_cache_plan_readonly(self):
        caches = {self.real_roots[name].parents[2] for name in ui.PACKAGES}
        self.assertEqual(len(caches), 1)
        for entry in self.config['packages']:
            entry['rootUri'] = self.real_roots[entry['name']].as_uri()
        self.save_config()
        with patch.dict(os.environ, {'PUB_CACHE': str(caches.pop())}):
            files, _ = ui.plan(self.root)
        self.assertGreater(len(files), len(ui.PATCHES) + len(ui.PACKAGES))
        for name, original in self.sources.items():
            package, relative = name.split('/', 1)
            self.assertEqual((self.real_roots[package] / relative).read_bytes(), original)
            self.assertEqual(files[name][0], ui.transform(name, original))

    def test_23_manifest_symlink_rejected_before_read(self):
        manifest = self.source() / 'pubspec.yaml'
        manifest.unlink()
        manifest.symlink_to(self.base / 'absent-manifest')
        with self.assertRaisesRegex(ValueError, 'symlink/special manifest'):
            ui.plan(self.root)

    def test_24_drift_install_does_not_publish_or_run_pub(self):
        target = self.source() / 'lib/src/menu/mongol_popup_menu.dart'
        target.write_bytes(target.read_bytes() + b'\n')
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, 'SHA256 mismatch'):
            self.run_install()
        self.assertEqual(self.snapshot(), before)
        self.assertFalse((self.root / 'build').exists())

    def test_25_pub_overlay_mutation_rolls_back(self):
        before = self.snapshot()
        def changed(command, **kwargs):
            self.pub_success(command, **kwargs)
            self.write_yaml('pubspec_overrides.yaml', {'dependency_overrides': {}})
        with self.assertRaisesRegex(ValueError, 'changed the dependency overlay'):
            self.run_install(changed)
        for name, data in before.items():
            self.assertEqual((self.root / name).read_bytes(), data)


if __name__ == '__main__':
    unittest.main(verbosity=2)
