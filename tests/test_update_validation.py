"""Check the external updater's real validation against isolated app fixtures."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

APP = os.environ.get('KAKAO_TEST_APP')
ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(APP, 'Set KAKAO_TEST_APP to a signed reconnect.4 app')
class UpdateValidationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build_dir = tempfile.TemporaryDirectory(prefix='kakao-validation-compiler-')
        cls.executable = Path(cls.build_dir.name) / 'validate'
        subprocess.run(['xcrun', 'swiftc', '-module-cache-path',
                        str(Path(cls.build_dir.name) / 'modules'),
                        str(ROOT / 'updater/UpdateValidation.swift'),
                        str(ROOT / 'tests/UpdateValidationTests.swift'),
                        '-o', str(cls.executable)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.build_dir.cleanup()

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='kakao update validation ')
        self.root = Path(self.temporary.name)
        self.staged = self.root / 'staged'
        self.staged.mkdir()
        self.app = self.staged / 'KakaoTalk.app'
        shutil.copytree(APP, self.app, symlinks=True)
        self.target = self.root / 'installed/KakaoTalk.app'
        (self.target / 'Contents').mkdir(parents=True)
        self.info = plistlib.loads((self.app / 'Contents/Info.plist').read_bytes())
        previous = dict(self.info, KakaoTalkPatchRelease='v26.9.0-reconnect.3')
        (self.target / 'Contents/Info.plist').write_bytes(plistlib.dumps(previous))
        self.sentinel = self.root / 'chat-data'
        self.sentinel.write_text('preserve')
        self.archive = self.staged / 'Payload.zip'
        self.archive.write_bytes(b'archive digest fixture')
        digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
        self.manifest = {
            'release_tag': self.info['KakaoTalkPatchRelease'],
            'app_version': self.info['CFBundleShortVersionString'],
            'app_build': self.info['CFBundleVersion'],
            'archive_sha256': digest(self.archive),
            'executable_sha256': digest(self.app / 'Contents/MacOS/KakaoTalk'),
            'helper_sha256': digest(self.app / 'Contents/Frameworks/SessionReconnect.dylib'),
        }

    def tearDown(self):
        self.assertEqual(self.sentinel.read_text(), 'preserve')
        self.temporary.cleanup()

    def validate(self):
        (self.staged / 'Ready.json').write_text(json.dumps(self.manifest))
        return subprocess.run([str(self.executable), str(self.staged), str(self.target)],
                              text=True, capture_output=True)

    def test_app_is_sandboxed_but_external_updater_is_not(self):
        for app, sandboxed in [(Path(APP), True),
                               (Path(APP) / 'Contents/Helpers/KakaoTalkUpdater.app', False)]:
            result = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(app)],
                                    check=True, capture_output=True)
            entitlements = plistlib.loads(result.stdout) if result.stdout.strip() else {}
            self.assertEqual(bool(entitlements.get('com.apple.security.app-sandbox')), sandboxed)

    def test_new_patch_is_accepted(self):
        result = self.validate()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_corrupt_archive_is_rejected(self):
        self.archive.write_bytes(b'corrupt')
        self.assertNotEqual(self.validate().returncode, 0)

    def test_corrupt_helper_is_rejected(self):
        (self.app / 'Contents/Frameworks/SessionReconnect.dylib').write_bytes(b'corrupt')
        self.assertNotEqual(self.validate().returncode, 0)

    def test_changed_destination_identity_is_rejected(self):
        info = dict(self.info, CFBundleIdentifier='example.other')
        (self.target / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        self.assertNotEqual(self.validate().returncode, 0)

    def test_already_installed_patch_is_rejected(self):
        (self.target / 'Contents/Info.plist').write_bytes(plistlib.dumps(self.info))
        self.assertNotEqual(self.validate().returncode, 0)

    def test_base_version_downgrade_is_rejected(self):
        info = dict(self.info, CFBundleShortVersionString='99.0.0',
                    KakaoTalkPatchRelease='v26.9.0-reconnect.3')
        (self.target / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        self.assertNotEqual(self.validate().returncode, 0)

    def test_missing_manifest_field_is_rejected(self):
        self.manifest.pop('release_tag')
        self.assertNotEqual(self.validate().returncode, 0)
