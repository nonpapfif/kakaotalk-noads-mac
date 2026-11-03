"""Keep idle disconnects separate from explicit authentication and logout failures."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DisconnectPolicyTests(unittest.TestCase):
    def test_native_disconnect_policy_cases(self):
        with tempfile.TemporaryDirectory(prefix='kakao-disconnect-policy-') as temporary:
            binary = Path(temporary) / 'policy'
            subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror',
                            '-framework', 'Foundation', '-I', str(ROOT / 'reconnect'),
                            str(ROOT / 'tests/disconnect_policy.m'), '-o', str(binary)],
                           check=True, capture_output=True)
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
            self.assertIn('Twelve disconnect and hold policy cases passed.', result.stdout)
