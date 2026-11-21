# SPDX-License-Identifier: AGPL-3.0-only
import configparser
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

BASE = Path(__file__).resolve().parent.parent
from car_fixture import Car

SHELLS = [name for name in ('bash', 'dash', 'ksh') if shutil.which(name)]


class BridgeCar:
    def __init__(self, work):
        self.car = Car(work)
        self.work, self.root, self.env = self.car.work, self.car.root, self.car.env
        self.pkg = self.root / 'data/nemesis/apps/g70.usbwifi.bridge'
        self.state = self.root / 'data/nemesis/backup/g70.usbwifi.bridge'
        for directory in ('bin', 'scripts', 'modules'):
            shutil.copytree(BASE / 'pkg' / directory, self.pkg / directory)
        shutil.copy(BASE / 'pkg/NEMESIS.data', self.pkg)
        self.put('props/sys.boot_completed', '1\n')
        self.put('proc/sys/kernel/random/boot_id', 'boot-1\n')
        self.put('data/nemesis/apps/korea.projection/NEMESIS.data', '[nemesis]\npackage-version=1.7.4\n')
        self.put('data/nemesis/apps/korea.projection/bin/busybox', '#!/bin/sh\nexec "$@"\n')
        (self.root / 'data/nemesis/apps/korea.projection/bin/busybox').chmod(0o755)
        (self.root / 'data/hmgapi/public').mkdir(parents=True)
        self.car.stub('chown', 'exit 0\n')
        self.car.stub('nemesis', 'echo "$*" >> "$G70_BRIDGE_CALLS"\n[ "$G70_KP_STOP_FAIL" != 1 ]\n')
        self.env['G70_BRIDGE_CALLS'] = str(self.work / 'nemesis.calls')
        helper = self.pkg / 'bin/ctrl-status'
        helper.write_text('#!/bin/sh\necho ctrl.state=ENABLED\necho ctrl.stations=1\n')
        helper.chmod(0o755)
        ip = self.car.tools / 'ip'
        ip.write_text('''#!/usr/bin/python3
import os,sys
from pathlib import Path
r=Path(os.environ['G70_DIAG_TEST_ROOT']);a=sys.argv[1:]
assert a[:2]==['link','set']
if len(a)==5 and a[3]=='name': (r/'sys/class/net'/a[2]).rename(r/'sys/class/net'/a[4])
''')
        ip.chmod(0o755)
        loader = self.car.tools / 'insmod'
        loader.write_text('''#!/usr/bin/python3
import os,sys
from pathlib import Path
r=Path(os.environ['G70_DIAG_TEST_ROOT']);state=r/'data/nemesis/backup/g70.usbwifi.bridge'
assert (state/'load-pending').exists()
with open(os.environ['G70_TEST_CALLS'],'a') as f:f.write(' '.join(sys.argv[1:])+'\\n')
if os.environ.get('G70_TEST_INSMOD_FAIL'):sys.exit(1)
(r/'proc/modules').write_text('88x2bu 2069644 0 - Live 0xdeadbeef\\n')
m=r/'sys/module/88x2bu';m.mkdir(parents=True,exist_ok=True)
(m/'srcversion').write_text('46A9CFB83C8F6E0C09E8AAC\\n')
d=r/'sys/bus/usb/drivers/rtl88x2bu';d.mkdir(parents=True,exist_ok=True)
if not (d/'module').exists():(d/'module').symlink_to(m,target_is_directory=True)
if os.environ.get('G70_TEST_ATTACHED'):
 u=r/'sys/bus/usb/devices/4-1';u.mkdir(parents=True,exist_ok=True)
 (u/'idVendor').write_text('0bda\\n');(u/'idProduct').write_text('b812\\n')
 for i in range(2):
  n=r/('sys/class/net/rtwlan'+str(i));(n/'device').mkdir(parents=True,exist_ok=True)
  (n/'ifindex').write_text(str(10+i)+'\\n')
  (n/'device/modalias').write_text('usb:v0BDApB812d0210dc00dsc00dp00icFFiscFFipFFin00\\n')
  if not (n/'device/driver').exists():(n/'device/driver').symlink_to(d,target_is_directory=True)
''')
        loader.chmod(0o755)

    def put(self, path, value):
        self.car.put(path, value)

    def run(self, path, shell='sh', **extra):
        return subprocess.run([shell, str(self.pkg / path)],
                              env=dict(self.env, **extra), capture_output=True,
                              text=True, timeout=30)

    def service(self, shell='sh', **extra):
        return self.run('bin/wifi.sh', shell, G70_BRIDGE_ONCE='1', **extra)

    def loader_calls(self):
        return self.car.calls()

    def kp_calls(self):
        path = self.work / 'nemesis.calls'
        return path.read_text().splitlines() if path.exists() else []


class BridgeTests(unittest.TestCase):
    def test_early_load_rename_marker_and_one_kp_restart(self):
        for shell in SHELLS:
            with self.subTest(shell=shell), tempfile.TemporaryDirectory() as work:
                car = BridgeCar(work)
                self.assertEqual(car.run('scripts/post.sh', shell).returncode, 0)
                result = car.service(shell, G70_TEST_ATTACHED='1')
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual((car.state / 'state.txt').read_text().strip(), 'wifi_ready')
                self.assertTrue((car.root / 'sys/class/net/wlan0').exists())
                self.assertTrue((car.root / 'data/hmgapi/public/wifi-chip').exists())
                self.assertTrue((car.state / 'chip-owned').exists())
                self.assertFalse((car.state / 'load-pending').exists())
                self.assertEqual(car.kp_calls(), ['service stop korea.projection/ap', 'service start korea.projection/ap'])
                self.assertEqual(car.service(shell).returncode, 0)
                self.assertEqual(len(car.loader_calls()), 1)
                self.assertEqual(len(car.kp_calls()), 2)
                self.assertEqual(car.run('bin/status.sh', shell).returncode, 0)
                self.assertFalse((car.state / 'maintenance').exists())
                self.assertFalse((Path(work) / 'denied').exists())

    def test_no_dongle_never_creates_wifi_marker(self):
        with tempfile.TemporaryDirectory() as work:
            car = BridgeCar(work)
            self.assertEqual(car.service().returncode, 0)
            self.assertEqual(len(car.loader_calls()), 1)
            self.assertFalse((car.root / 'data/hmgapi/public/wifi-chip').exists())
            self.assertEqual(car.kp_calls(), [])

    def test_failed_or_unfinished_load_never_retries(self):
        for unfinished in (False, True):
            with self.subTest(unfinished=unfinished), tempfile.TemporaryDirectory() as work:
                car = BridgeCar(work)
                if unfinished:
                    car.state.mkdir(parents=True)
                    (car.state / 'load-pending').write_text('old-boot')
                self.assertNotEqual(car.service(G70_TEST_INSMOD_FAIL='1').returncode, 0)
                self.assertNotEqual(car.service().returncode, 0)
                self.assertEqual(len(car.loader_calls()), 0 if unfinished else 1)

    def test_config_mismatch_and_foreign_wlan_block_marker(self):
        for mismatch in (True, False):
            with self.subTest(mismatch=mismatch), tempfile.TemporaryDirectory() as work:
                car = BridgeCar(work)
                if mismatch:
                    car.put('proc/config.gz', b'different')
                else:
                    (car.root / 'sys/class/net/wlan0').mkdir(parents=True)
                result = car.service(G70_TEST_ATTACHED='1')
                self.assertEqual(result.returncode, 1 if mismatch else 0)
                self.assertFalse((car.root / 'data/hmgapi/public/wifi-chip').exists())

    def test_active_kp_setup_is_not_interrupted(self):
        with tempfile.TemporaryDirectory() as work:
            car = BridgeCar(work)
            car.put('data/local/tmp/korea.projection/fix.pid', '123 boot-1\n')
            (car.root / 'proc/123').mkdir(parents=True)
            self.assertEqual(car.service(G70_TEST_ATTACHED='1').returncode, 0)
            self.assertEqual(car.kp_calls(), [])
            car.put('data/hmgapi/mods/wireless-carplay-aa/mod.json', '{}')
            self.assertEqual(car.service().returncode, 0)
            self.assertEqual(car.kp_calls(), [])

    def test_kp_restart_failure_is_not_repeated(self):
        with tempfile.TemporaryDirectory() as work:
            car = BridgeCar(work)
            self.assertEqual(car.service(G70_TEST_ATTACHED='1', G70_KP_STOP_FAIL='1').returncode, 0)
            self.assertEqual(car.service().returncode, 0)
            self.assertEqual(car.kp_calls(), ['service stop korea.projection/ap'])

    def test_owned_marker_cleanup_and_upgrade_preservation(self):
        for upgrading, preexisting in [(False, False), (True, False), (False, True)]:
            with self.subTest(upgrading=upgrading, preexisting=preexisting), tempfile.TemporaryDirectory() as work:
                car = BridgeCar(work)
                chip = car.root / 'data/hmgapi/public/wifi-chip'
                if preexisting: chip.write_text('')
                self.assertEqual(car.service(G70_TEST_ATTACHED='1').returncode, 0)
                if upgrading:
                    car.put('data/local/tmp/nemesis/stage/g70.usbwifi.bridge/NEMESIS.data', 'id=g70.usbwifi.bridge\n')
                car.put('data/hmgapi/mods/wireless-carplay-aa/mod.json', '{}')
                self.assertEqual(car.run('scripts/preun.sh').returncode, 0)
                self.assertEqual(chip.exists(), upgrading or preexisting)
                self.assertTrue((car.root / 'data/hmgapi/mods/wireless-carplay-aa/mod.json').exists())

    def test_single_port_capture_pause_export_resume_and_privacy(self):
        with tempfile.TemporaryDirectory() as work:
            car = BridgeCar(work)
            self.assertEqual(car.run('scripts/post.sh').returncode, 0)
            self.assertEqual(car.service(G70_TEST_ATTACHED='1').returncode, 0)
            car.put('data/local/tmp/korea-projection-progress.txt', 'pct=100\nstate=done\nboot=boot-1\n')
            car.put('proc/net/tcp', '0: 012BA8C0:1B58 0200000A:1234 01 rest\n')
            car.put('data/nemesis/logs/korea.projection/ap.log',
                    'AP running channel 149\nSTA aa:bb:cc:dd:ee:ff at 192.168.43.10\n'
                    'ssid=PRIVATE_SSID\npassword=PRIVATE_PASSWORD\nConnectedName=PRIVATE_PHONE\n')
            car.put('data/nemesis/backup/g70.usbwifi.bridge/dhcp.raw', 'PRIVATE_PHONE aa:bb:cc:dd:ee:ff 192.168.43.10\n')
            car.put('data/nemesis/apps/g70.usbwifi.bridge/dhcp-runtime/leases', '100 aa:bb:cc:dd:ee:ff 192.168.43.10 PRIVATE_PHONE *\n')
            capture = car.run('bin/logs.sh')
            self.assertEqual(capture.returncode, 0, capture.stdout + capture.stderr)
            self.assertTrue((car.state / 'maintenance').exists())
            saved = next(car.state.glob('capture_*'))
            self.assertIn('carplay_port7000_ipv4_sessions=1', (saved / 'bridge-status.txt').read_text())
            car.put('proc/modules', '')  # following reboot
            self.assertEqual(car.service().returncode, 0)
            self.assertEqual(len(car.loader_calls()), 1)
            self.assertEqual(car.run('bin/logs.sh').returncode, 0)
            self.assertEqual(len(list(car.state.glob('capture_*'))), 1)
            car.put('proc/mounts', '/dev/sda1 /storage/usb0 vfat rw 0 0\n')
            car.put('storage/usb0/G70_BRIDGE_EXPORT.txt', 'g70.usbwifi.bridge export v1\n')
            exported = car.run('bin/logs.sh')
            self.assertEqual(exported.returncode, 0, exported.stdout + exported.stderr)
            self.assertFalse((car.state / 'maintenance').exists())
            output = next((car.root / 'storage/usb0').glob('G70_BRIDGE_*'))
            if not output.is_dir():
                output = next(p for p in (car.root / 'storage/usb0').glob('G70_BRIDGE_*') if p.is_dir())
            self.assertTrue((output / 'EXPORT_COMPLETE.txt').exists())
            for path in output.rglob('*'):
                if path.is_file():
                    for secret in (b'PRIVATE_SSID', b'PRIVATE_PASSWORD', b'PRIVATE_PHONE', b'aa:bb:cc:dd:ee:ff', b'192.168.43.10'):
                        self.assertNotIn(secret, path.read_bytes())
            self.assertEqual(len(car.loader_calls()), 1)  # exporting never reloads

    def test_other_kp_version_is_blocked_before_driver_loading(self):
        with tempfile.TemporaryDirectory() as work:
            car = BridgeCar(work)
            car.put('data/nemesis/apps/korea.projection/NEMESIS.data', '[nemesis]\npackage-version=1.7.4.1\n')
            result = car.service(G70_TEST_ATTACHED='1')
            self.assertEqual(result.returncode, 1)
            self.assertEqual(car.loader_calls(), [])
            self.assertEqual((car.state / 'state.txt').read_text().strip(), 'unsupported_korea_projection_version')

    def test_usb_selection_refuses_foreign_interfaces_and_duplicate_targets(self):
        for scenario in ('other_id','other_interface','duplicate'):
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as work:
                car = BridgeCar(work)
                self.assertEqual(car.service(G70_TEST_ATTACHED='1').returncode,0)
                (car.root/'sys/class/net/wlan0').rename(car.root/'sys/class/net/rtwlan1')
                (car.root/'data/hmgapi/public/wifi-chip').unlink()
                if scenario=='duplicate':
                    car.put('sys/bus/usb/devices/4-2/idVendor','0bda\n')
                    car.put('sys/bus/usb/devices/4-2/idProduct','b812\n')
                else:
                    alias=('usb:v0BDApB831d0210dc00dsc00dp00icFFiscFFipFFin00' if scenario=='other_id'
                           else 'usb:v0BDApB812d0210dc00dsc00dp00ic08isc06ip50in00')
                    for net in ('rtwlan0','rtwlan1'):
                        car.put('sys/class/net/'+net+'/device/modalias',alias+'\n')
                self.assertEqual(car.service().returncode,0)
                self.assertFalse((car.root/'sys/class/net/wlan0').exists())
                self.assertFalse((car.root/'data/hmgapi/public/wifi-chip').exists())

    def test_early_first_log_capture_waits_but_prior_automatic_evidence_allows_capture(self):
        with tempfile.TemporaryDirectory() as work:
            car = BridgeCar(work)
            self.assertEqual(car.service(G70_TEST_ATTACHED='1').returncode, 0)
            car.put('proc/uptime', '100.0 50.0\n')
            self.assertEqual(car.run('bin/logs.sh').returncode, 0)
            self.assertFalse((car.state / 'maintenance').exists())
            self.assertFalse(list(car.state.glob('capture_*')))
            car.put('data/nemesis/backup/g70.usbwifi.bridge/auto-previous/after-300s.txt', 'boot_uptime_seconds=305\n')
            self.assertEqual(car.run('bin/logs.sh').returncode, 0)
            self.assertTrue((car.state / 'maintenance').exists())
            self.assertEqual(len(list(car.state.glob('capture_*'))), 1)

    def test_metadata_and_pinned_binary(self):
        import hashlib
        for folder in ('pkg', 'logs-pkg'):
            cfg = configparser.ConfigParser(interpolation=None)
            cfg.read(BASE / folder / 'NEMESIS.data')
            for key, limit in [('short-desc', 64), ('detailed-desc', 256)]:
                self.assertLessEqual(len(cfg['nemesis'][key]), limit)
        with zipfile.ZipFile(BASE / 'dist/usb/packages/g70.usbwifi.bridge.zip') as archive:
            self.assertIsNone(archive.testzip())
            self.assertEqual(hashlib.sha256(archive.read('modules/88x2bu.ko')).hexdigest(),
                             '3e78ee38942e08667f68c287f0576ac21855c34cc516710de27cd49fa6137110')
            self.assertIn('source/ctrl-status.c', archive.namelist())
            for required in ('COPYING', 'NOTICE.txt', 'source/driver/COPYING',
                             'source/driver/upstream-fc158d1f71b9e5dfcd1fccaf4d28725b65086e3b.tar.gz'):
                self.assertIn(required, archive.namelist())
        with zipfile.ZipFile(BASE / 'dist/usb/packages/g70.usbwifi.logs.zip') as archive:
            self.assertIn('COPYING', archive.namelist())


if __name__ == '__main__':
    unittest.main()
