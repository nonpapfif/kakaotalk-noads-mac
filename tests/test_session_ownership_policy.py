"""Compile and execute the standalone offline ownership policy fixture."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SessionOwnershipPolicyTests(unittest.TestCase):
    def test_native_session_ownership_policy_cases(self):
        with tempfile.TemporaryDirectory(prefix='kakao-session-ownership-policy-') as temporary:
            binary = Path(temporary) / 'policy'
            subprocess.run(
                ['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror',
                 '-arch', 'arm64', '-arch', 'x86_64', '-mmacosx-version-min=13.0',
                 '-framework', 'Foundation', '-I', str(ROOT / 'reconnect'),
                 str(ROOT / 'tests/session_ownership_policy.m'), '-o', str(binary)],
                check=True, capture_output=True, text=True,
            )
            architectures = subprocess.run(
                ['xcrun', 'lipo', '-archs', str(binary)],
                check=True, capture_output=True, text=True,
            )
            self.assertEqual(set(architectures.stdout.split()), {'arm64', 'x86_64'})
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
            self.assertIn('Session ownership policy cases passed.', result.stdout)


if __name__ == '__main__':
    unittest.main()
