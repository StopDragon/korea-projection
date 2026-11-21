# SPDX-License-Identifier: AGPL-3.0-only
"""Missing-prefix repair, conservative cleanup, and private event filtering."""
import json
from pathlib import Path
import tempfile
import unittest

from test_ap_support import SupportCar
from test_bridge import SHELLS


class ProjectionCar(SupportCar):
    def __init__(self, work):
        super().__init__(work)
        self.put('ipv4', '192.168.43.1\n')
        self.put('proc/uptime', '200.0 100.0\n')
        self.put('proc/net/tcp', '')
        self.process(600102, 'dnsmasq', ['dnsmasq', '--interface=wlan0',
                     '--dhcp-range=192.168.43.10,192.168.43.50,255.255.255.0,1h'])
        self.put('data/local/tmp/korea.projection/dnsmasq.pid', '600102 boot-1\n')
        self.env['G70_ROUTE_MODEL'] = str(self.work / 'route-model.py')
        self.env['G70_ROUTE_STATE'] = str(self.work / 'routes.json')
        (self.work / 'route-model.py').write_text('''import json,os,sys
from pathlib import Path
p=Path(os.environ['G70_ROUTE_STATE']);s=json.loads(p.read_text());a=sys.argv[1:]
s['calls'].append(a)
def end(code=0):p.write_text(json.dumps(s));sys.exit(code)
assert a[0]=='route'
op=a[1];table=a[a.index('table')+1];rows=s['tables'].setdefault(table,[])
if op=='show':
 s['queries'][table]=s['queries'].get(table,0)+1
 if os.environ.get('G70_ROUTE_QUERY_FAIL')==table:end(2)
 if os.environ.get('G70_ROUTE_CONFIRM_FAIL')==table and s['queries'][table]==2:end(2)
 print('\\n'.join(rows));end()
assert a[2:5]==['192.168.43.0/24','dev','wlan0']
if op=='add':
 if os.environ.get('G70_ROUTE_ADD_FAIL')==table:end(2)
 if any(r.startswith('192.168.43.0/24 ') for r in rows):end(2)
 rows.append('192.168.43.0/24 dev wlan0 scope link')
elif op=='del':
 row=next((r for r in rows if r.startswith('192.168.43.0/24 dev wlan0 ')),None)
 if row is None:end(2)
 rows.remove(row)
else:end(2)
end()
''')
        self.car.stub('ip', 'exec /usr/bin/python3 "$G70_ROUTE_MODEL" "$@"\n')
        self.car.stub('logcat', '''cat <<'LOG'
11-21 14:46:02.250 E/CarPlay_( 123): RTSP socket failed PRIVATE_PHONE 192.168.43.10 aa:bb:cc:dd:ee:ff
11-21 14:46:02.251 F/libc( 123): Fatal signal 11 in CarPlay PRIVATE_PHONE
11-21 14:46:02.252 E/TccCarPlay( 123): video decoder failed PRIVATE_PHONE
11-21 14:46:02.253 I/ActivityManager( 123): Process com.hkmc.GPM has died PRIVATE_PHONE
11-21 14:46:02.254 E/OtherApp( 999): Fatal exception PRIVATE_PHONE
11-21 14:46:02.255 I/WifiHW( 123): wifi_unload_driver PRIVATE_PHONE ssid=PRIVATE_PHONE
11-21 14:46:02.256 I/SoftapController( 123): softap stop PRIVATE_PHONE 192.168.43.10
LOG
''')
        self.car.stub('dmesg', '''cat <<'LOG'
[ 13.100000] usb 4-1: new high-speed USB device PRIVATE_PHONE
[ 231.100000] usb 4-1: reset high-speed USB device PRIVATE_PHONE 192.168.43.10
[ 232.200000] usb 4-1: USB disconnect, device number 3 aa:bb:cc:dd:ee:ff
[ 233.100000] usb 4-2: USB disconnect PRIVATE_PHONE
LOG
''')
        self.initial = {'main': ['192.168.43.0/24 dev wlan0 scope link'],
                        '60': ['default via 10.99.0.1 dev rmnet0'],
                        '61': ['default via 10.99.0.1 dev rmnet0']}
        self.write_routes(self.initial)

    def routes(self):
        return json.loads((self.work / 'routes.json').read_text())

    def write_routes(self, tables):
        (self.work / 'routes.json').write_text(json.dumps({'tables': tables, 'queries': {}, 'calls': []}))


class ProjectionTests(unittest.TestCase):
    def test_missing_routes_are_added_once_and_only_owned_routes_are_removed(self):
        for shell in SHELLS:
            with self.subTest(shell=shell), tempfile.TemporaryDirectory() as work:
                c = ProjectionCar(work)
                result = c.support('''
projection_routes_tick
projection_routes_tick
projection_route_diagnostics
projection_routes_off
''', shell)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('projection_route_table_60=wlan0', result.stdout)
                self.assertIn('projection_route_table_61=wlan0', result.stdout)
                state = c.routes()
                self.assertEqual(state['tables'], c.initial)
                self.assertEqual(len([a for a in state['calls'] if a[1]=='add']), 2)
                for a in state['calls']:
                    if a[1] != 'show':
                        self.assertEqual(a[2:5], ['192.168.43.0/24','dev','wlan0'])
                        self.assertIn(a[-1], ('60','61'))

    def test_preexisting_correct_and_foreign_prefixes_are_preserved(self):
        with tempfile.TemporaryDirectory() as work:
            c = ProjectionCar(work)
            initial = c.routes()['tables']
            initial['60'].append('192.168.43.0/24 dev wlan0 scope link')
            initial['61'].append('192.168.43.0/24 dev eth0 scope link')
            c.write_routes(initial)
            result = c.support('projection_routes_tick\nprojection_routes_off\n')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(c.routes()['tables'], initial)
            self.assertFalse(any(a[1] in ('add','del','replace') for a in c.routes()['calls']))

    def test_query_and_add_errors_do_not_change_existing_network(self):
        with tempfile.TemporaryDirectory() as work:
            c = ProjectionCar(work)
            result = c.support('projection_routes_tick\nprojection_routes_off\n',
                               G70_ROUTE_QUERY_FAIL='60', G70_ROUTE_ADD_FAIL='61')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(c.routes()['tables'], c.initial)
            self.assertIn('query_failed', (c.state/'route-60.state').read_text())
            self.assertIn('add_failed', (c.state/'route-61.state').read_text())

    def test_unconfirmed_add_is_rolled_back(self):
        with tempfile.TemporaryDirectory() as work:
            c = ProjectionCar(work)
            result = c.support('ensure_projection_route 60\n', G70_ROUTE_CONFIRM_FAIL='60')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(c.routes()['tables'], c.initial)
            self.assertFalse((c.state/'route-60.owner').exists())

    def test_changed_or_old_boot_route_is_not_deleted(self):
        for changed in (True, False):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as work:
                c = ProjectionCar(work)
                self.assertEqual(c.support('projection_routes_tick\n').returncode, 0)
                state = c.routes()
                if changed:
                    state['tables']['60'][-1] = '192.168.43.0/24 dev eth0 scope link'
                    (c.work/'routes.json').write_text(json.dumps(state))
                else:
                    (c.state/'route-60.owner').write_text('old-boot 11\n')
                result = c.support('projection_routes_off\n')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(c.routes()['tables']['60'], state['tables']['60'])
                self.assertEqual(c.routes()['tables']['61'], c.initial['61'])

    def test_maintenance_cleans_owned_routes_and_disabled_mode_never_adds(self):
        with tempfile.TemporaryDirectory() as work:
            c = ProjectionCar(work)
            result = c.support('''
projection_routes_tick
touch "$BK/maintenance"
projection_routes_tick
''')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(c.routes()['tables'], c.initial)
            (c.state/'maintenance').unlink()
            c.put('data/hmgapi/mods/wireless-carplay-aa/.disabled', '')
            before = len(c.routes()['calls'])
            self.assertEqual(c.support('projection_routes_tick\n').returncode, 0)
            self.assertEqual(len(c.routes()['calls']), before)

    def test_connection_and_interface_loss_snapshots_keep_only_fixed_facts(self):
        with tempfile.TemporaryDirectory() as work:
            c = ProjectionCar(work)
            for name, value in [('idVendor','0bda'),('idProduct','b812'),('busnum','4'),('devnum','3'),
                                ('authorized','1'),('power/control','auto'),('power/runtime_status','active')]:
                c.put('sys/bus/usb/devices/4-1/'+name, value+'\n')
            result = c.support('''
echo 0 > "$KPW/cpn"
monitor_projection
echo 1 > "$KPW/cpn"
echo '0: 012BA8C0:1B58 0A2BA8C0:ABCD 01 rest' > "$PROC/net/tcp"
monitor_projection
echo 0 > "$KPW/cpn"
echo '' > "$PROC/net/tcp"
monitor_projection
mv "$NET/wlan0" "$NET/disconnected"
interface_generation
''')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            for name in ('connection-up-1.txt','connection-down-1.txt','interface-loss-1.txt'):
                content = (c.state/'auto-current'/name).read_text()
                self.assertIn('code=transport_error', content)
                self.assertIn('code=fatal', content)
                self.assertIn('code=video_error', content)
                self.assertIn('code=process_exit_or_anr', content)
                self.assertIn('code=wifi_driver_unload', content)
                self.assertIn('code=wifi_ap_transition', content)
                self.assertIn('usb_event_uptime=232.200000 code=disconnect', content)
                self.assertIn('dongle_devnum=3', content)
                for secret in ('PRIVATE_PHONE','192.168.43.10','aa:bb:cc:dd:ee:ff','10.99.0.1'):
                    self.assertNotIn(secret, content)
            self.assertEqual(c.run('bin/logs.sh').returncode, 0)
            c.put('proc/modules','')
            c.put('proc/mounts','/dev/sda1 /storage/usb0 vfat rw 0 0\n')
            c.put('storage/usb0/G70_BRIDGE_EXPORT.txt','g70.usbwifi.bridge export v1\n')
            self.assertEqual(c.run('bin/logs.sh').returncode, 0)
            out = next(p for p in (c.root/'storage/usb0').glob('G70_BRIDGE_*') if p.is_dir())
            self.assertTrue((out/'auto-current/connection-down-1.txt').exists())
            for p in out.rglob('*'):
                if p.is_file():
                    for secret in (b'PRIVATE_PHONE',b'192.168.43.10',b'aa:bb:cc:dd:ee:ff',b'10.99.0.1'):
                        self.assertNotIn(secret,p.read_bytes())

    def test_native_kp_lease_count_is_not_presented_as_bridge_failure(self):
        with tempfile.TemporaryDirectory() as work:
            c = ProjectionCar(work)
            self.assertEqual(c.run('scripts/post.sh').returncode,0)
            result = c.run('bin/status.sh')
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertIn('Korea Projection 주소 할당 서비스 사용 중',result.stdout)
            self.assertNotIn('주소 할당 기록 없음',result.stdout)

    def test_ipv6_counter_uses_only_ap_addresses_and_avoids_ipv4_mapped_double_count(self):
        with tempfile.TemporaryDirectory() as work:
            c = ProjectionCar(work)
            c.put('proc/net/if_inet6',
                  'fe800000000000000000000000000001 02 40 20 80 wlan0\n'
                  'fe800000000000000000000000000002 03 40 20 80 ncm0\n')
            c.put('proc/net/tcp6',
                  '0: 000080FE000000000000000001000000:1B58 remote 01 rest\n'
                  '1: 000080FE000000000000000002000000:1B58 remote 01 rest\n'
                  '2: 0000000000000000FFFF0000012BA8C0:1B58 remote 01 rest\n')
            result = c.support('echo cp4=$(carplay_ipv4_count) cp6=$(carplay_ipv6_count)\n')
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertIn('cp4=1 cp6=1',result.stdout)


if __name__ == '__main__':
    unittest.main()
