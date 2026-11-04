"""Compile and execute the standalone offline ownership policy fixture."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SessionOwnershipPolicyTests(unittest.TestCase):
    def run_recorded(self, label, command):
        result = subprocess.run(command, capture_output=True, text=True, check=False)
        print(json.dumps({
            'label': label,
            'command': command,
            'stdout': result.stdout,
            'stderr': result.stderr,
            'returncode': result.returncode,
        }), flush=True)
        return result

    def compile_fixture(self, source, binary, headers, label):
        return self.run_recorded(
            label,
            ['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror',
             '-arch', 'arm64', '-arch', 'x86_64', '-mmacosx-version-min=13.0',
             '-framework', 'Foundation', '-I', str(headers),
             str(source), '-o', str(binary)],
        )

    def copy_fixture(self, directory):
        source = directory / 'session_ownership_policy.m'
        shutil.copy2(ROOT / 'tests/session_ownership_policy.m', source)
        shutil.copy2(ROOT / 'reconnect/SessionOwnershipPolicy.h', directory)
        return source

    def test_native_session_ownership_policy_cases(self):
        with tempfile.TemporaryDirectory(prefix='kakao-session-ownership-policy-') as temporary:
            binary = Path(temporary) / 'policy'
            build = self.compile_fixture(
                ROOT / 'tests/session_ownership_policy.m', binary, ROOT / 'reconnect',
                'normal compile',
            )
            self.assertEqual(build.returncode, 0, build.stderr)
            architectures = self.run_recorded(
                'normal architectures', ['xcrun', 'lipo', '-archs', str(binary)],
            )
            self.assertEqual(architectures.returncode, 0, architectures.stderr)
            self.assertEqual(set(architectures.stdout.split()), {'arm64', 'x86_64'})
            result = self.run_recorded('normal fixture', [str(binary)])
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('Session ownership policy cases passed.', result.stdout)

    def test_compile_failure_diagnostics_are_recorded(self):
        with tempfile.TemporaryDirectory(prefix='kakao-session-compile-failure-') as temporary:
            directory = Path(temporary)
            source = self.copy_fixture(directory)
            with source.open('a', encoding='utf-8') as fixture:
                fixture.write('\n#error injected ownership compile failure\n')
            result = self.compile_fixture(
                source, directory / 'policy', directory, 'injected compile failure',
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('error:', result.stderr)
            self.assertIn('injected ownership compile failure', result.stderr)

    def test_fixture_failure_diagnostics_are_recorded(self):
        with tempfile.TemporaryDirectory(prefix='kakao-session-fixture-failure-') as temporary:
            directory = Path(temporary)
            source = self.copy_fixture(directory)
            contents = source.read_text(encoding='utf-8')
            contents = contents.replace(
                'Expect(input, SOPKeepConnection, SOPHold, SOPHold, "idle Open home owner");',
                'Expect(input, SOPHold, SOPHold, SOPHold, "injected fixture mismatch");',
                1,
            )
            source.write_text(contents, encoding='utf-8')
            binary = directory / 'policy'
            build = self.compile_fixture(
                source, binary, directory, 'fixture mismatch compile',
            )
            self.assertEqual(build.returncode, 0, build.stderr)
            result = self.run_recorded('injected fixture mismatch', [str(binary)])
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(
                'injected fixture mismatch: Mac 0 expected 0, got 1', result.stderr,
            )
            self.assertNotIn('Session ownership policy cases passed.', result.stdout)


if __name__ == '__main__':
    unittest.main()
