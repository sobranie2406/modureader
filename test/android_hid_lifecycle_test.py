"""Source contracts for Bluetooth HID reconnect; not a GPU/device test."""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ANDROID = '{http://schemas.android.com/apk/res/android}'


class HidLifecycleTest(unittest.TestCase):
    def test_hid_configuration_does_not_require_activity_recreation(self):
        manifest = ET.parse(ROOT / 'android/app/src/main/AndroidManifest.xml')
        activity = next(a for a in manifest.findall('application/activity')
                        if a.get(ANDROID + 'name') == '.MainActivity')
        changes = set(activity.get(ANDROID + 'configChanges').split('|'))
        self.assertTrue({'keyboard', 'keyboardHidden', 'navigation'} <= changes)
        self.assertEqual(activity.get(ANDROID + 'hardwareAccelerated'), 'true')
        self.assertFalse(any(m.get(ANDROID + 'name') ==
                             'io.flutter.embedding.android.EnableImpeller' and
                             m.get(ANDROID + 'value') == 'false'
                             for m in manifest.findall('.//meta-data')))

    def test_configuration_retains_embedding_and_releases_key_latch(self):
        source = (ROOT / 'android/app/src/main/kotlin/com/modu/reader/MainActivity.kt').read_text()
        config = source.split('override fun onConfigurationChanged', 1)[1].split(
            'override fun onPostResume', 1)[0]
        self.assertIn('super.onConfigurationChanged(newConfig)', config)
        self.assertIn('readerKeys.reset()', config)
        self.assertIn('refreshReaderHostState()', config)
        self.assertNotIn('recreate(', source)
        self.assertNotRegex(source, r'(?<![A-Za-z])FlutterEngine\(')
        self.assertIn('super.onPostResume()', source)
        self.assertIn('invokeMethod("hostStateChanged", null)', source)

    def test_reader_restores_ui_only_when_current_and_unobstructed(self):
        source = (ROOT / 'lib/page/reading_page.dart').read_text()
        restore = source.split('void _restoreReaderSystemUi()', 1)[1].split(
            '@override', 1)[0]
        for guard in ('!AnxPlatform.isAndroid', '!mounted', '!_canUsePageKeys',
                      '!Prefs().hideStatusBar', 'viewInsets.bottom > 0'):
            self.assertIn(guard, restore)
        self.assertIn('ensureVisualUpdate()', restore)
        self.assertNotIn('Timer', restore)
        self.assertNotIn('setSystemUIChangeCallback', source)
        policy = source.split('bool get _canUsePageKeys', 1)[1].split(
            'void _updatePageKeys', 1)[0]
        for guard in ('!_readingRouteVisible', '!bottomBarOffstage',
                      '_readerDrawerOpen', '_searchDialogOpen', '_aiChat != null',
                      'AppLifecycleState.resumed', 'readerFocusBlocksPageKeys'):
            self.assertIn(guard, policy)


if __name__ == '__main__':
    unittest.main()
