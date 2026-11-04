"""Verify socket interposition and URLSession suspension using a local HTTP server."""
from pathlib import Path
import subprocess
import plistlib
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import unittest

ROOT = Path(__file__).resolve().parents[1]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'loopback test')

    def log_message(self, format, *args):
        pass


class NetworkGateTests(unittest.TestCase):
    def test_socket_and_urlsession_gate(self):
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory(prefix='kakao-network-gate-') as temporary:
                library = Path(temporary) / 'gate.dylib'
                binary = Path(temporary) / 'client'
                common = ['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror',
                          '-framework', 'Foundation']
                subprocess.run(common + ['-dynamiclib', str(ROOT / 'reconnect/SessionNetworkGate.m'),
                                         '-o', str(library)], check=True, capture_output=True)
                subprocess.run(common + [str(ROOT / 'tests/network_gate_runtime.m'),
                                         str(library), '-o', str(binary)],
                               check=True, capture_output=True)
                entitlements = Path(temporary) / 'entitlements.plist'
                entitlements.write_bytes(plistlib.dumps({
                    'com.apple.security.cs.disable-library-validation': True,
                }))
                for target in (library, binary):
                    subprocess.run(['codesign', '--force', '--sign', '-', '--options', 'runtime',
                                    '--entitlements', str(entitlements), str(target)],
                                   check=True, capture_output=True)
                result = subprocess.run([str(binary), str(server.server_port)],
                                        capture_output=True, text=True, timeout=20)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('Network gate loopback checks passed.', result.stdout)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
