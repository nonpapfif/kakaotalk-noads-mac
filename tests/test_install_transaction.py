"""Exercise the real install helper in disposable directories, without touching /Applications."""
import hashlib
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

APP = os.environ.get('KAKAO_TEST_APP')
SCRIPT = Path(__file__).resolve().parents[1] / 'installer/install-app.sh'


@unittest.skipUnless(APP, 'Set KAKAO_TEST_APP to a signed reconnect app')
class InstallTransactionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="kakao install ' spaces ")
        self.parent = Path(self.temporary.name)
        self.target = self.parent / 'KakaoTalk.app'
        contents = self.target / 'Contents'
        contents.mkdir(parents=True)
        (contents / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'com.kakao.KakaoTalkMac'}))
        (contents / 'preserve.txt').write_text('original app sentinel')
        self.chat_data = self.parent / 'Library/chat-data'
        self.chat_data.parent.mkdir()
        self.chat_data.write_text('do not touch')
        self.source = Path(APP)
        info = plistlib.loads((self.source / 'Contents/Info.plist').read_bytes())
        self.version, self.build = info['CFBundleShortVersionString'], info['CFBundleVersion']
        self.exe = hashlib.sha256((self.source / 'Contents/MacOS/KakaoTalk').read_bytes()).hexdigest()
        self.helper = hashlib.sha256((self.source / 'Contents/Frameworks/SessionReconnect.dylib').read_bytes()).hexdigest()

    def tearDown(self):
        self.temporary.cleanup()

    def run_install(self, executable=None, version=None):
        return subprocess.run(['/bin/sh', str(SCRIPT), str(self.source), str(self.target),
                               executable or self.exe, self.helper, version or self.version, self.build], capture_output=True, text=True)

    def test_backup_install_and_idempotence(self):
        result = self.run_install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        backups = list((self.parent / 'KakaoTalk Backups').glob('*.app'))
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / 'Contents/preserve.txt').read_text(), 'original app sentinel')
        self.assertEqual(self.chat_data.read_text(), 'do not touch')
        self.assertEqual(hashlib.sha256((self.target / 'Contents/MacOS/KakaoTalk').read_bytes()).hexdigest(), self.exe)
        result = self.run_install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(list((self.parent / 'KakaoTalk Backups').glob('*.app'))), 1)

    def test_wrong_payload_hash_does_not_replace_app(self):
        result = self.run_install(executable='0' * 64)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.target / 'Contents/preserve.txt').read_text(), 'original app sentinel')
        self.assertFalse((self.parent / 'KakaoTalk Backups').exists())

    def test_wrong_payload_version_does_not_replace_app(self):
        result = self.run_install(version='99.0.0')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.target / 'Contents/preserve.txt').read_text(), 'original app sentinel')
        self.assertFalse((self.parent / 'KakaoTalk Backups').exists())

    def test_unexpected_target_is_preserved(self):
        (self.target / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'example.other'}))
        result = self.run_install()
        self.assertEqual(result.returncode, 2)
        self.assertEqual((self.target / 'Contents/preserve.txt').read_text(), 'original app sentinel')


if __name__ == '__main__':
    unittest.main()
