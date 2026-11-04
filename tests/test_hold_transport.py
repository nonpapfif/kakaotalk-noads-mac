"""Exercise production Hold hooks against disposable native runtime objects."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HoldTransportTests(unittest.TestCase):
    def test_native_hold_transport_lifecycle(self):
        with tempfile.TemporaryDirectory(prefix='kakao-hold-runtime-') as temporary:
            binary = Path(temporary) / 'hold-runtime'
            subprocess.run(
                ['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror',
                 '-framework', 'Cocoa', str(ROOT / 'tests/hold_transport_runtime.m'),
                 str(ROOT / 'reconnect/AppUpdater.m'),
                 str(ROOT / 'reconnect/SessionNetworkGate.m'), '-o', str(binary)],
                check=True, capture_output=True,
            )
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
            self.assertIn('Hold transport runtime checks passed.', result.stdout)
