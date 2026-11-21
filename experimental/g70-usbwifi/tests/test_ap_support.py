# SPDX-License-Identifier: AGPL-3.0-only
"""Exercise the DHCP subprocess/FIFO, KP adoption and interface replacement."""
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import unittest

from test_bridge import BridgeCar, SHELLS


class SupportCar(BridgeCar):
    def __init__(self, work):
        super().__init__(work)
        assert self.service(G70_TEST_ATTACHED='1').returncode == 0
        self.put('props/persist.sys.iap2.wifi', 't\n')
        self.put('data/hmgapi/mods/wireless-carplay-aa/mod.json', '{}')
        self.put('proc/uptime', '100.00 90.00\n')
        (self.root / 'data/local/tmp/korea.projection').mkdir(parents=True, exist_ok=True)
        self.env['G70_TEST_KILLS'] = str(self.work / 'kills')
        self.env['G70_DHCP_ACTUAL_PID'] = str(self.work / 'actual-pid')
        self.env['G70_DHCP_ARGS'] = str(self.work / 'dhcp-args.json')
        self.env['G70_IP_CALLS'] = str(self.work / 'ifconfig-calls')
        self.car.stub('ifconfig', '''if [ "$#" -gt 1 ]; then
 echo "$*" >> "$G70_IP_CALLS"
 echo "$2" > "$G70_DIAG_TEST_ROOT/ipv4"
fi
if [ -f "$G70_DIAG_TEST_ROOT/ipv4" ]; then
 echo "wlan0 inet addr:$(cat "$G70_DIAG_TEST_ROOT/ipv4") Bcast:192.168.43.255 Mask:255.255.255.0"
fi
''')
        self.process(600101, 'hostapd', [str(self.root / 'system/bin/hostapd'),
                                      str(self.root / 'data/misc/wifi/hostapd-kp.conf')])
        self.put('system/bin/dnsmasq', '''#!/usr/bin/python3
import fcntl,json,os,signal,stat,sys,time
from pathlib import Path
r=Path(os.environ['G70_DIAG_TEST_ROOT']);pid=os.getpid()
Path(os.environ['G70_DHCP_ACTUAL_PID']).write_text(str(pid))
if os.environ.get('G70_DHCP_ATTEMPTS'):
 with open(os.environ['G70_DHCP_ATTEMPTS'],'a') as log:log.write(json.dumps(sys.argv[1:])+'\\n')
mode=os.environ.get('G70_DHCP_MODE','')
alternate='--dhcp-alternate-port=1067,68' in sys.argv
if mode=='both_conflict' or (mode=='67_conflict' and not alternate):
 print('dnsmasq: failed to bind DHCP server socket: Address already in use PRIVATE_PHONE aa:bb:cc:dd:ee:ff',flush=True)
 sys.exit(2)
if mode in ('dns_conflict','netlink_conflict'):
 stage='create listening socket' if mode=='dns_conflict' else 'create netlink socket'
 print('dnsmasq: failed to '+stage+': Address already in use PRIVATE_PHONE',flush=True)
 sys.exit(2)
if os.environ.get('G70_DHCP_FAIL'):
 print('dnsmasq: failed to create socket: Address already in use PRIVATE_PHONE aa:bb:cc:dd:ee:ff',flush=True)
 sys.exit(2)
p=r/'proc'/str(pid);p.mkdir(parents=True)
(p/'stat').write_text(f'{pid} (dnsmasq) S 1 0 0\\n')
(p/'cmdline').write_bytes(b'\\0'.join(a.encode() for a in sys.argv)+b'\\0')
Path(os.environ['G70_DHCP_ARGS']).write_text(json.dumps(dict(args=sys.argv[1:],
 fifo=stat.S_ISFIFO(os.fstat(0).st_mode),rdwr=fcntl.fcntl(0,fcntl.F_GETFL)&os.O_ACCMODE==os.O_RDWR)))
if os.environ.get('G70_DHCP_RACE'):
 (r/'data/local/tmp/korea.projection/dnsmasq.pid').write_text('600102 boot-1\\n')
def done(*_):
 for n in ('stat','cmdline'):(p/n).unlink(missing_ok=True)
 sys.exit(0)
signal.signal(signal.SIGTERM,done)
while True:time.sleep(1)
''')
        (self.root / 'system/bin/dnsmasq').chmod(0o755)

    def process(self, pid, name, args, state='S'):
        self.put(f'proc/{pid}/stat', f'{pid} ({name}) {state} 1 0 0\n')
        self.put(f'proc/{pid}/cmdline', b'\0'.join(s.encode() for s in args) + b'\0')

    def support(self, script, shell='sh', **extra):
        preamble = '''
. "$1"
kill() {
 echo "$1" >> "$G70_TEST_KILLS"
 if [ -r "$G70_DHCP_ACTUAL_PID" ] && [ "$(cat "$G70_DHCP_ACTUAL_PID")" = "$1" ]; then
   /bin/kill "$1" 2>/dev/null || :
 fi
 return 0
}
sleep() { /bin/sleep "$@"; }
trap 'stop_owned_dhcp' EXIT
'''
        try:
            return subprocess.run([shell, '-c', preamble + script, 'test', str(self.pkg / 'bin/common.sh')],
                                  env=dict(self.env, **extra), text=True, capture_output=True, timeout=30)
        finally:
            pidfile = self.work / 'actual-pid'
            if pidfile.exists():
                try:
                    os.kill(int(pidfile.read_text()), signal.SIGTERM)
                except ProcessLookupError:
                    pass

    def kills(self):
        p = self.work / 'kills'
        return p.read_text().splitlines() if p.exists() else []


class ApSupportTests(unittest.TestCase):
    def test_fallback_restores_ip_starts_once_and_kp_can_adopt(self):
        for shell in SHELLS:
            with self.subTest(shell=shell), tempfile.TemporaryDirectory() as work:
                car = SupportCar(work)
                result = car.support('''
maintain_kp_ap
[ ! -e "$BK/bridge-dhcp.pid" ] || exit 11
echo '111.0 90.0' > "$PROC/uptime"
maintain_kp_ap
first=$(kp_dhcp_pid)
[ -n "$first" ] && [ "$first" = "$(owned_dhcp_pid)" ] || exit 12
maintain_kp_ap
[ "$first" = "$(kp_dhcp_pid)" ] || exit 13
echo '600199 boot-1' > "$KPW/dnsmasq.pid"
maintain_kp_ap
echo '122.0 90.0' > "$PROC/uptime"
maintain_kp_ap
[ "$first" = "$(kp_dhcp_pid)" ] || exit 15
ap_diagnostics
''', shell)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('dhcp_running=yes', result.stdout)
                self.assertIn('dhcp_source=bridge', result.stdout)
                self.assertIn('ap_ipv4=yes', result.stdout)
                args = json.loads((Path(work) / 'dhcp-args.json').read_text())
                self.assertTrue(args['fifo'])
                self.assertTrue(args['rdwr'])
                for flag in ('--port=0', '--user=system', '--group=wifi', '--dhcp-option=3', '--dhcp-option=6'):
                    self.assertIn(flag, args['args'])
                self.assertTrue(any(a.startswith('--dhcp-leasefile=') for a in args['args']))
                self.assertFalse(any('1067' in a for a in args['args']))
                self.assertEqual(len((Path(work) / 'ifconfig-calls').read_text().splitlines()), 1)
                self.assertEqual((car.state / 'events.txt').read_text().count('bridge_dhcp_started'), 1)
                self.assertEqual((car.state / 'events.txt').read_text().count('bridge_dhcp_readopted'), 1)

    def test_generation_change_retires_only_verified_kp_processes(self):
        with tempfile.TemporaryDirectory() as work:
            car = SupportCar(work)
            car.process(600102, 'dnsmasq', ['dnsmasq', '--interface=wlan0',
                        '--dhcp-range=192.168.43.10,192.168.43.50,255.255.255.0,1h'])
            car.put('data/local/tmp/korea.projection/dnsmasq.pid', '600102 boot-1\n')
            car.process(600103, 'hostapd', ['hostapd', '/data/misc/wifi/stock.conf'])
            result = car.support('''
interface_generation
echo 99 > "$NET/wlan0/ifindex"
interface_generation
interface_generation
''')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(car.kills(), ['600101', '600102'])
            self.assertEqual((car.state / 'events.txt').read_text().count('wlan0_generation_changed'), 1)
            self.assertEqual(len(car.kp_calls()), 2)  # no full KP service restart

    def test_detach_then_attach_and_old_boot_do_not_kill_unrelated_pid(self):
        for record in ('600102 old-boot\n', '600102 boot-1\n'):
            with self.subTest(record=record), tempfile.TemporaryDirectory() as work:
                car = SupportCar(work)
                car.process(600102, 'dnsmasq', ['dnsmasq', '--interface=eth0'])
                car.put('data/local/tmp/korea.projection/dnsmasq.pid', record)
                result = car.support('''
interface_generation
mv "$NET/wlan0" "$NET/disconnected"
interface_generation
interface_generation
mv "$NET/disconnected" "$NET/wlan0"
interface_generation
''')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(car.kills(), ['600101'])

    def test_native_dhcp_and_other_hotspot_are_respected(self):
        for mode in ('existing_dhcp', 'foreign_ap', 'disabled', 'no_kp_host', 'maintenance'):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as work:
                car = SupportCar(work)
                if mode == 'existing_dhcp':
                    car.process(600102, 'dnsmasq', ['dnsmasq', '--interface=wlan0',
                                '--dhcp-range=192.168.43.10,192.168.43.50,255.255.255.0,1h'])
                    car.put('data/local/tmp/korea.projection/dnsmasq.pid', '600102 boot-1\n')
                elif mode == 'foreign_ap':
                    car.process(600103, 'hostapd', ['hostapd', '/data/misc/wifi/stock.conf'])
                elif mode == 'disabled':
                    car.put('data/hmgapi/mods/wireless-carplay-aa/.disabled', '')
                elif mode == 'no_kp_host':
                    (car.root / 'proc/600101/stat').unlink()
                else:
                    (car.state / 'maintenance').touch()
                result = car.support('''
maintain_kp_ap
echo '111.0 90.0' > "$PROC/uptime"
maintain_kp_ap
''')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse((Path(work) / 'dhcp-args.json').exists())
                if mode != 'existing_dhcp':
                    self.assertFalse((Path(work) / 'ifconfig-calls').exists())

    def test_failed_dhcp_is_classified_private_and_backed_off(self):
        with tempfile.TemporaryDirectory() as work:
            car = SupportCar(work)
            result = car.support('''
maintain_kp_ap
echo '111.0 90.0' > "$PROC/uptime"
maintain_kp_ap
echo '116.0 90.0' > "$PROC/uptime"
maintain_kp_ap
ap_diagnostics
''', G70_DHCP_FAIL='1')
            self.assertEqual(result.returncode, 0, result.stderr)
            events = (car.state / 'events.txt').read_text()
            self.assertEqual(events.count('bridge_dhcp_start_failed'), 1)
            self.assertIn('bridge_dhcp_error=address_in_use', result.stdout)
            self.assertNotIn('PRIVATE_PHONE', events + result.stdout)
            self.assertNotIn('aa:bb:cc:dd:ee:ff', events + result.stdout)

    def test_concurrent_kp_dhcp_is_adopted_without_overwriting_it(self):
        with tempfile.TemporaryDirectory() as work:
            car = SupportCar(work)
            car.process(600102, 'dnsmasq', ['dnsmasq', '--interface=wlan0',
                        '--dhcp-range=192.168.43.10,192.168.43.50,255.255.255.0,1h'])
            result = car.support('''
maintain_kp_ap
echo '111.0 90.0' > "$PROC/uptime"
maintain_kp_ap
[ "$(kp_dhcp_pid)" = 600102 ] || exit 14
''', G70_DHCP_RACE='1')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn('600102', car.kills())
            self.assertIn('bridge_dhcp_yielded', (car.state / 'events.txt').read_text())


if __name__ == '__main__':
    unittest.main()
