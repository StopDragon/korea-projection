# SPDX-License-Identifier: AGPL-3.0-only
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import unittest

BASE = Path(__file__).resolve().parent.parent


class ControlClientTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build_dir = tempfile.TemporaryDirectory(prefix='g70c-build-', dir='/tmp')
        cls.binary = Path(cls.build_dir.name) / 'ctrl-status'
        subprocess.run(['clang', '-std=c11', '-D_POSIX_C_SOURCE=200809L', '-O2',
                        '-Wall', '-Wextra', '-Werror', str(BASE / 'pkg/source/ctrl-status.c'),
                        '-o', str(cls.binary)], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.build_dir.cleanup()

    def request(self, reply):
        with tempfile.TemporaryDirectory(prefix='g70c-', dir='/tmp') as work:
            path = str(Path(work) / 'wlan0')
            server = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
            server.bind(path)
            server.settimeout(2)
            commands = []

            def serve():
                command, address = server.recvfrom(512)
                commands.append(command)
                if reply is not None:
                    server.sendto(reply, address)

            thread = threading.Thread(target=serve)
            thread.start()
            try:
                result = subprocess.run([str(self.binary), path, work],
                                        capture_output=True, text=True, timeout=3)
                thread.join(2)
                self.assertFalse(thread.is_alive())
                self.assertEqual(commands, [b'STATUS'])
                self.assertEqual(list(Path(work).glob('g70c-*')), [])
                return result
            finally:
                server.close()

    def test_status_reply_omits_all_secrets(self):
        result = self.request(b'state=ENABLED\nfreq=5745\nchannel=149\nnum_sta[0]=1\n'
                              b'ssid=PRIVATE_SSID\nbssid[0]=01:02:03:04:05:06\n'
                              b'wpa_passphrase=PRIVATE_PASSWORD\n')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(set(result.stdout.splitlines()), {
            'ctrl.state=ENABLED', 'ctrl.freq=5745', 'ctrl.channel=149', 'ctrl.stations=1'})

    def test_non_numeric_values_are_ignored(self):
        result = self.request(b'state=ENABLED\nfreq=PRIVATE_NAME\nnum_sta[0]=01:02:03:04:05:06\n')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, 'ctrl.state=ENABLED\n')

    def test_unsupported_status_is_explicit(self):
        result = self.request(b'FAIL\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('ctrl.error=no_state_in_reply', result.stdout)

    def test_timeout_is_bounded(self):
        result = self.request(None)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('ctrl.error=timeout', result.stdout)

    def test_long_path_is_rejected(self):
        result = subprocess.run([str(self.binary), '/' + 'x' * 200, '/tmp'], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('ctrl.error=path_too_long', result.stdout)


if __name__ == '__main__':
    unittest.main()
