"""Local book import must not register Modu as a web browser/downloader."""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ANDROID = '{http://schemas.android.com/apk/res/android}'


class AndroidLinkAssociationsTest(unittest.TestCase):
    def setUp(self):
        self.root = ET.parse(ROOT / 'android/app/src/main/AndroidManifest.xml').getroot()
        self.activity = self.root.find("application/activity[@" + ANDROID + "name='.MainActivity']")

    def filters(self, action):
        return [f for f in self.activity.findall('intent-filter') if any(
            a.get(ANDROID + 'name') == 'android.intent.action.' + action
            for a in f.findall('action'))]

    def test_view_accepts_only_local_uris_not_web_links(self):
        views = self.filters('VIEW')
        self.assertTrue(views)
        for f in views:
            schemes = {d.get(ANDROID + 'scheme') for d in f.findall('data')
                       if d.get(ANDROID + 'scheme')}
            # Explicit schemes also prevent a MIME-only wildcard from
            # accidentally claiming nonlocal links with a supplied MIME type.
            self.assertEqual(schemes, {'file', 'content'})
            self.assertNotIn('android.intent.category.BROWSABLE',
                             {c.get(ANDROID + 'name') for c in f.findall('category')})
            self.assertTrue(any(d.get(ANDROID + 'mimeType') == '*/*'
                                for d in f.findall('data')))

    def test_explicit_single_and_multiple_file_sharing_remains(self):
        for action in ('SEND', 'SEND_MULTIPLE'):
            with self.subTest(action=action):
                self.assertTrue(any(d.get(ANDROID + 'mimeType') == '*/*'
                                    for f in self.filters(action) for d in f.findall('data')))

    def test_network_permission_remains_for_webdav_ai_and_downloads(self):
        self.assertIn('android.permission.INTERNET',
                      {p.get(ANDROID + 'name') for p in self.root.findall('uses-permission')})


if __name__ == '__main__':
    unittest.main()
