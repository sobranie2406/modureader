"""Universal installers must preserve native payloads and old updater contracts."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts/release'))
from universal_desktop import combined_windows_script, compatibility_copies, merge_native_assets
from validate_assets import validate
from update_manifest import create_manifest


class UniversalDesktopTest(unittest.TestCase):
    def test_windows_chooses_exactly_one_native_payload_without_changing_app_identity(self):
        script = combined_windows_script(Path('arm-payload'), Path('intel-payload'), '1.3.6', Path('out'))
        self.assertIn('AppId=ModuReader', script)
        self.assertIn('ArchitecturesAllowed=x64os or arm64', script)
        lines = [line for line in script.splitlines() if line.startswith('Source:')]
        self.assertEqual(len(lines), 2)
        self.assertIn('Check: IsArm64', lines[0])
        self.assertIn('Check: not IsArm64', lines[1])
        self.assertIn('windows-universal-setup', script)
        self.assertIn('CloseApplications=yes', script)
        self.assertNotIn('[InstallDelete]', script)

    def test_native_assets_keep_both_runtime_architectures_and_reject_mixed_dependencies(self):
        def manifest(arch, path='tokenizers.framework/tokenizers'):
            return json.dumps({'format-version':[1,0,0], 'native-assets':{arch:{'tokenizers':['absolute',path]}}})
        merged = json.loads(merge_native_assets(manifest('macos_arm64'), manifest('macos_x64')))
        self.assertEqual(set(merged['native-assets']), {'macos_arm64','macos_x64'})
        with self.assertRaises(ValueError):
            merge_native_assets(manifest('macos_arm64'), manifest('macos_x64','wrong/path'))
        with self.assertRaises(ValueError):
            merge_native_assets(manifest('macos_arm64'), manifest('macos_arm64'))

    def test_new_release_requires_identical_legacy_copies_and_keeps_old_manifest_schema(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            for platform,suffix in [('macos','.dmg'),('windows','-setup.exe')]:
                installer=root/f'Modu-1.3.6-{platform}-universal{suffix}'
                installer.write_bytes(platform.encode())
                compatibility_copies(installer,platform,'1.3.6')
            for name in ['android-arm64.apk','ios-arm64.ipa','linux-arm64.deb','linux-x64.deb','harmony-arm64.hap']:
                p=root/f'Modu-1.3.6-{name}';p.write_bytes(name.encode())
                p.with_name(p.name+'.sha256').write_text(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n')
            self.assertEqual(validate(root,'v1.3.6',True),11)
            release={'tag_name':'v1.3.6','draft':False,'prerelease':False,'assets':[]}
            for p in root.iterdir():
                if p.suffix=='.sha256':continue
                release['assets'].append({'name':p.name,'size':p.stat().st_size,'state':'uploaded',
                    'digest':'sha256:'+hashlib.sha256(p.read_bytes()).hexdigest(),
                    'browser_download_url':'https://github.com/sobranie2406/modureader/releases/download/v1.3.6/'+p.name})
            manifest=create_manifest(release)
            self.assertEqual(manifest['modu_update_schema'],1)
            self.assertEqual(len(manifest['assets']),10)
            for platform,suffix in [('macos','.dmg'),('windows','-setup.exe')]:
                canonical=next(a for a in manifest['assets'] if a['name']==f'Modu-1.3.6-{platform}-universal{suffix}')
                for arch in ['arm64','x64']:
                    legacy=next(a for a in manifest['assets'] if a['name']==f'Modu-1.3.6-{platform}-{arch}{suffix}')
                    self.assertEqual(legacy['digest'],canonical['digest'])
            next(a for a in release['assets'] if a['name']=='Modu-1.3.6-macos-x64.dmg')['digest']='sha256:'+'0'*64
            with self.assertRaises(ValueError):create_manifest(release)
            (root/'Modu-1.3.6-macos-x64.dmg').write_bytes(b'wrong payload')
            with self.assertRaises(ValueError):validate(root,'v1.3.6',True)

if __name__=='__main__':unittest.main()
