"""OS registration contracts: local books are imports, never web navigation."""
from pathlib import Path
import plistlib
import re
import importlib.util
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXTENSIONS = {'epub', 'mobi', 'azw3', 'fb2', 'txt', 'pdf', 'md', 'markdown', 'umd'}

class ExternalBookAssociationsTest(unittest.TestCase):
    def test_apple_declares_every_book_extension_without_forcing_defaults(self):
        for platform in ('ios', 'macos'):
            with self.subTest(platform=platform):
                data = plistlib.loads((ROOT / platform / 'Runner/Info.plist').read_bytes())
                docs = data['CFBundleDocumentTypes']
                self.assertEqual({e for d in docs for e in d['CFBundleTypeExtensions']}, EXTENSIONS)
                self.assertTrue(all(d['LSHandlerRank'] == 'Alternate' for d in docs))
                source = (ROOT / platform / 'Runner/AppDelegate.swift').read_text()
                self.assertIn('startAccessingSecurityScopedResource()', source)
                self.assertIn('stopAccessingSecurityScopedResource()', source)
                self.assertIn('NSFileCoordinator()', source)

    def test_windows_open_with_keeps_user_defaults(self):
        sys.path.insert(0, str(ROOT / 'scripts/release'))
        spec = importlib.util.spec_from_file_location('native_installers', ROOT / 'scripts/release/native_installers.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        generated = module.windows_script(Path('bundle'), 'x64', '1.3.4-beta.1', Path('output'))
        self.assertEqual(set(re.findall(r'Classes\\\.([a-z0-9]+)\\OpenWithProgids', generated)), EXTENSIONS)
        self.assertNotIn('UserChoice', generated)
        self.assertIn('Modu.Book\\shell\\open\\command', generated)

    def test_linux_and_harmony_cover_all_formats(self):
        linux = (ROOT / 'scripts/release/native_installers.py').read_text()
        harmony = (ROOT / 'ohos/entry/src/main/ets/plugins/ExternalBookFilesPlugin.ets').read_text()
        for extension in EXTENSIONS:
            self.assertIn("'" + extension + "':", linux)
            self.assertIn(extension, harmony)
        self.assertIn("ability.params.stream", harmony)
        self.assertIn('fs.copyFile(source.fd, target)', harmony)

    def test_native_boundary_uses_resolver_not_guessed_paths(self):
        source = (ROOT / 'third_party/share_handler_android/android/src/main/kotlin/com/shoutsocial/share_handler/ShareHandlerPlugin.kt').read_text()
        self.assertNotIn('FileDirectory', source)
        self.assertIn('resolver.openInputStream(uri)', source)
        self.assertIn('linkedSetOf<Uri>()', source)

if __name__ == '__main__':
    unittest.main()
