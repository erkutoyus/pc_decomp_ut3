"""IPA contract: device target, Payload layout, private-data exclusion and permissions."""
from pathlib import Path
import plistlib
import stat
import struct
import tempfile
import unittest
import zipfile
from tools.package_ipa import package, clone_app


class IpaTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root/'Unreal Tournament 3.app'
        self.app.mkdir()
        info = {'CFBundleExecutable':'Unreal Tournament 3','CFBundleIdentifier':'org.ut3.port.ios',
                'CFBundlePackageType':'APPL','CFBundleDisplayName':'Unreal Tournament 3',
                'UIDeviceFamily':[1,2]}
        (self.app/'Info.plist').write_bytes(plistlib.dumps(info))
        executable = self.app/info['CFBundleExecutable']
        executable.write_bytes(struct.pack('<8I',0xfeedfacf,0x0100000c,0,2,1,24,0,0)+struct.pack('<6I',0x32,24,2,0,0,0))
        executable.chmod(0o755)
        (self.app/'embedded.mobileprovision').write_bytes(b'private provisioning')
        (self.app/'_CodeSignature').mkdir()
        (self.app/'_CodeSignature/CodeResources').write_text('obsolete signature')
        self.output = self.root/'out/test.ipa'

    def test_payload_identity_permissions_and_no_signing_credentials(self):
        receipt = package(self.app,self.output,strip_signature=False)
        with zipfile.ZipFile(self.output) as z:
            self.assertIsNone(z.testzip())
            names = z.namelist()
            self.assertIn('Payload/Unreal Tournament 3.app/Info.plist',names)
            self.assertFalse(any('_CodeSignature' in n or 'mobileprovision' in n for n in names))
            info = plistlib.loads(z.read('Payload/Unreal Tournament 3.app/Info.plist'))
            self.assertEqual(info['CFBundleIdentifier'],'org.ut3.port.ios')
            self.assertEqual(info['UIDeviceFamily'],[1,2])
            mode = z.getinfo('Payload/Unreal Tournament 3.app/Unreal Tournament 3').external_attr >> 16
            self.assertTrue(mode & stat.S_IXUSR)
        self.assertFalse(receipt['game_assets_bundled'])
        self.assertTrue((self.app/'embedded.mobileprovision').exists()) # Source app never stripped.

    def test_original_inputs_and_keys_are_refused(self):
        for name in ['cdkey.txt','UT3.exe','Player.ue3profile','msvcr80.dll']:
            path = self.app/name
            path.write_bytes(b'private')
            with self.assertRaisesRegex(ValueError,'must not contain'):
                package(self.app,self.output,strip_signature=False)
            path.unlink()
        (self.app/'Game').mkdir()
        with self.assertRaises(ValueError):package(self.app,self.output,strip_signature=False)

    def test_iphone_compatibility_metadata_is_refused(self):
        path = self.app/'Info.plist'
        info = plistlib.loads(path.read_bytes())
        for families in (None, [1], [2]):
            if families is None:
                info.pop('UIDeviceFamily', None)
            else:
                info['UIDeviceFamily'] = families
            path.write_bytes(plistlib.dumps(info))
            with self.assertRaisesRegex(ValueError, 'universal iPhone/iPad'):
                package(self.app,self.output,strip_signature=False)

    def test_macos_and_simulator_are_refused(self):
        executable = self.app/'Unreal Tournament 3'
        original = executable.read_bytes()
        for platform in [1,7]:
            changed = bytearray(original)
            struct.pack_into('<I',changed,40,platform)
            executable.write_bytes(changed)
            with self.assertRaisesRegex(ValueError,'physical-device'):
                package(self.app,self.output,strip_signature=False)

    def test_external_symlinks_and_nested_staging_are_refused(self):
        (self.root/'outside').write_bytes(b'private')
        (self.app/'leak').symlink_to(self.root/'outside')
        with self.assertRaisesRegex(ValueError,'symbolic link'):
            package(self.app,self.output,strip_signature=False)
        with self.assertRaises(ValueError):clone_app(self.app,self.app)
        with self.assertRaises(ValueError):clone_app(self.app,self.app/'nested.app')


if __name__ == '__main__':unittest.main()
