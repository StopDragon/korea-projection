# SPDX-License-Identifier: AGPL-3.0-only
"""Conditional alternate DHCP port, scoped rule rollback and boot evidence."""
import json
from pathlib import Path
import tempfile
import unittest

from test_ap_support import SupportCar
from test_bridge import SHELLS


class PortCar(SupportCar):
    def __init__(self, work):
        super().__init__(work)
        self.env['G70_DHCP_ATTEMPTS'] = str(self.work / 'attempts.jsonl')
        self.env['G70_IPTABLES_STATE'] = str(self.work / 'iptables.json')
        self.car.stub('iptables', '''exec /usr/bin/python3 "$G70_IPTABLES_MODEL" "$@"
''')
        model = self.work / 'iptables-model.py'
        self.env['G70_IPTABLES_MODEL'] = str(model)
        model.write_text('''import json,os,sys
from pathlib import Path
p=Path(os.environ['G70_IPTABLES_STATE']);state=json.loads(p.read_text())
a=sys.argv[1:];state['calls'].append(a)
def end(code=0):
 p.write_text(json.dumps(state));sys.exit(code)
if len(state['calls'])==int(os.environ.get('G70_IPTABLES_FAIL_AT','0')):end(1)
t='filter'
if a[:1]==['-t']:t=a[1];a=a[2:]
op,c=a[:2];rules=state['tables'][t]
if op=='-N':
 if c in rules:end(1)
 rules[c]=[]
elif c not in rules:end(1)
elif op in ('-A','-I'):
 args=a[2:]
 if op=='-I' and args and args[0].isdigit():args=args[1:]
 if op=='-A':rules[c].append(args)
 else:rules[c].insert(0,args)
elif op=='-D':
 try:rules[c].remove(a[2:])
 except ValueError:end(1)
elif op=='-F':rules[c]=[]
elif op=='-X':
 if c in ('INPUT','OUTPUT','FORWARD','PREROUTING','POSTROUTING'):end(2)
 if rules[c] or any(['-j',c]==r[i:i+2] for rows in rules.values() for r in rows for i in range(len(r))):end(1)
 del rules[c]
elif op=='-L':
 print('Chain '+c)
 print(' pkts bytes target prot opt in out source destination')
 for r in rules[c]:
  target=r[r.index('-j')+1] if '-j' in r else 'UNKNOWN'
  print('7 900 '+target+' udp -- * * 192.168.43.10 255.255.255.255 PRIVATE_PHONE')
else:end(2)
end()
''')
        self.initial = {
            'filter': {'INPUT': [['-j', 'NATIVE_INPUT']], 'OUTPUT': [['-j', 'NATIVE_OUTPUT']], 'FORWARD': []},
            'nat': {'PREROUTING': [['-j', 'NATIVE_IN']], 'POSTROUTING': [['-j', 'NATIVE_OUT']]},
        }
        (self.work / 'iptables.json').write_text(json.dumps({'calls': [], 'tables': self.initial}))

    def iptables(self):
        return json.loads((self.work / 'iptables.json').read_text())

    def attempts(self):
        p = self.work / 'attempts.jsonl'
        return [json.loads(line) for line in p.read_text().splitlines()] if p.exists() else []


class DhcpPortTests(unittest.TestCase):
    def test_only_exact_dhcp_bind_conflict_enables_alternate_and_kp_adopts(self):
        for shell in SHELLS:
            with self.subTest(shell=shell), tempfile.TemporaryDirectory() as work:
                car = PortCar(work)
                result = car.support('''
maintain_kp_ap
echo '111.0 90.0' > "$PROC/uptime"
maintain_kp_ap
[ -n "$(kp_dhcp_pid)" ] || exit 41
ap_diagnostics
''', shell, G70_DHCP_MODE='67_conflict')
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('dhcp_running=yes', result.stdout)
                self.assertIn('dhcp_server_port=1067', result.stdout)
                self.assertIn('dhcp_port_translation=yes', result.stdout)
                self.assertIn('dhcp_translation_mode=port_only_dnat', result.stdout)
                self.assertIn('dhcp_redirect_packets=7', result.stdout)
                self.assertIn('dhcp_input_packets=7', result.stdout)
                self.assertIn('dhcp_output_packets=7', result.stdout)
                attempts = car.attempts()
                self.assertEqual(len(attempts), 2)
                self.assertNotIn('--dhcp-alternate-port=1067,68', attempts[0])
                self.assertIn('--dhcp-alternate-port=1067,68', attempts[1])
                self.assertNotIn('--dhcp-broadcast', attempts[1])
                self.assertEqual(car.iptables()['tables'], car.initial)
                failure = (car.state / 'auto-current/dhcp-67-failure-1.txt').read_text()
                self.assertIn('last_dhcp_stage=dhcp_bind', failure)
                for secret in ('PRIVATE_PHONE', 'aa:bb:cc:dd:ee:ff', '192.168.43.10'):
                    self.assertNotIn(secret, failure + result.stdout)
                self.assertNotIn('600101', car.kills())

    def test_dns_netlink_and_unknown_errors_never_enable_translation(self):
        for mode in ('dns_conflict', 'netlink_conflict', 'unknown'):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as work:
                car = PortCar(work)
                result = car.support('''
maintain_kp_ap
echo '111.0 90.0' > "$PROC/uptime"
maintain_kp_ap
ap_diagnostics
''', G70_DHCP_MODE=mode, G70_DHCP_FAIL='1' if mode == 'unknown' else '')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(len(car.attempts()), 1)
                self.assertEqual(car.iptables()['calls'], [])
                self.assertIn('dhcp_port_translation=no', result.stdout)

    def test_rule_transaction_rolls_back_each_failure_without_changing_native_rules(self):
        for step in range(1, 11):
            with self.subTest(step=step), tempfile.TemporaryDirectory() as work:
                car = PortCar(work)
                result = car.support('dhcp_nat_on\nexit $?\n', G70_IPTABLES_FAIL_AT=str(step))
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertEqual(car.iptables()['tables'], car.initial)
                self.assertFalse((car.state / 'nat-active').exists())

    def test_existing_unowned_chain_is_preserved_and_setup_is_idempotent(self):
        for occupied in (False, True):
            with self.subTest(occupied=occupied), tempfile.TemporaryDirectory() as work:
                car = PortCar(work)
                if occupied:
                    state = car.iptables()
                    state['tables']['nat']['G70BR_DHCP_IN'] = [['-j', 'KEEP_OTHER_OWNER']]
                    (car.work / 'iptables.json').write_text(json.dumps(state))
                    expected = state['tables']
                else:
                    expected = car.initial
                result = car.support('dhcp_nat_on\nrc=$?\n[ "$rc" != 0 ] || dhcp_nat_on\nexit "$rc"\n')
                self.assertEqual(result.returncode, 1 if occupied else 0, result.stderr)
                self.assertEqual(car.iptables()['tables'], expected)
                creations = [a for a in car.iptables()['calls'] if '-N' in a]
                self.assertEqual(len(creations), 1 if occupied else 3)

    def test_port_translation_preserves_broadcast_discover_and_unicast_renewal(self):
        # Linux 3.18 ip_route_input_slow accepts source 0 only for limited
        # broadcast. An initial DHCPDISCOVER must retain 255.255.255.255.
        # This checks the packet contract of the emitted rule, not a live
        # kernel/NAT stack. It fails for v0.3.0's REDIRECT rule.
        with tempfile.TemporaryDirectory() as work:
            car = PortCar(work)
            result = car.support('''
dhcp_nat_on || exit 44
cp "$G70_IPTABLES_STATE" "$G70_IPTABLES_STATE.active"
''')
            self.assertEqual(result.returncode, 0, result.stderr)
            active = json.loads((car.work / 'iptables.json.active').read_text())
            rule = active['tables']['nat']['G70BR_DHCP_IN'][0]
            target = rule[rule.index('-j') + 1]

            def apply_destination(dst, port):
                if port != int(rule[rule.index('--dport') + 1]):
                    return dst, port
                if target == 'REDIRECT':
                    return '192.168.43.1', int(rule[rule.index('--to-ports') + 1])
                self.assertEqual(target, 'DNAT')
                value = rule[rule.index('--to-destination') + 1]
                new_address, new_port = value.rsplit(':', 1)
                return new_address or dst, int(new_port)

            dst, port = apply_destination('255.255.255.255', 67)
            self.assertEqual((dst, port), ('255.255.255.255', 1067))
            self.assertEqual(apply_destination('192.168.43.1', 67), ('192.168.43.1', 1067))
            self.assertEqual(apply_destination('255.255.255.255', 68), ('255.255.255.255', 68))
            self.assertEqual(car.iptables()['tables'], car.initial)

    def test_legacy_owned_translation_is_replaced_before_reusing_it(self):
        with tempfile.TemporaryDirectory() as work:
            car = PortCar(work)
            result = car.support('''
dhcp_nat_on || exit 45
iptables -t nat -F "$NAT_IN"
iptables -t nat -A "$NAT_IN" -p udp --dport 67 -j REDIRECT --to-ports 1067
rm -f "$BK/nat-policy"
dhcp_nat_on || exit 46
cp "$G70_IPTABLES_STATE" "$G70_IPTABLES_STATE.active"
''')
            self.assertEqual(result.returncode, 0, result.stderr)
            active = json.loads((car.work / 'iptables.json.active').read_text())
            rules = active['tables']['nat']['G70BR_DHCP_IN']
            self.assertEqual(len(rules), 1)
            self.assertIn('DNAT', rules[0])
            self.assertIn(':1067', rules[0])
            self.assertNotIn('REDIRECT', rules[0])
            self.assertEqual(len([a for a in active['calls'] if '-N' in a]), 6)
            self.assertEqual(car.iptables()['tables'], car.initial)

    def test_alternate_failure_removes_rules_and_native_replacement_is_respected(self):
        for replacement in (False, True):
            with self.subTest(replacement=replacement), tempfile.TemporaryDirectory() as work:
                car = PortCar(work)
                car.process(600102, 'dnsmasq', ['dnsmasq', '--interface=wlan0',
                            '--dhcp-range=192.168.43.10,192.168.43.50,255.255.255.0,1h'])
                script = '''
maintain_kp_ap
echo '111.0 90.0' > "$PROC/uptime"
maintain_kp_ap
'''
                if replacement:
                    script += '''
echo '600102 boot-1' > "$KPW/dnsmasq.pid"
maintain_kp_ap
[ "$(kp_dhcp_pid)" = 600102 ] || exit 42
[ ! -f "$BK/nat-active" ] || exit 43
'''
                result = car.support(script + '\nap_diagnostics\n', G70_DHCP_MODE='67_conflict' if replacement else 'both_conflict')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(car.iptables()['tables'], car.initial)
                self.assertNotIn('600102', car.kills())
                if not replacement:
                    self.assertTrue((car.state / 'auto-current/dhcp-1067-failure-1.txt').exists())

    def test_automatic_checkpoints_rotate_and_export_only_filtered_facts(self):
        with tempfile.TemporaryDirectory() as work:
            car = PortCar(work)
            car.put('data/nemesis/backup/korea.projection/usb-g70/dhcp.raw',
                    'failed to bind DHCP server socket: Address already in use PRIVATE_PHONE 192.168.43.10\n')
            car.car.stub('netstat', 'echo "udp 0 0 192.168.43.10:67 0.0.0.0:* 999/PRIVATE_PHONE"\n')
            result = car.support('''
periodic_evidence
echo '185.0 90.0' > "$PROC/uptime"
periodic_evidence
echo '305.0 90.0' > "$PROC/uptime"
periodic_evidence
record_dhcp_failure 67
echo boot-2 > "$PROC/sys/kernel/random/boot_id"
echo '185.0 90.0' > "$PROC/uptime"
periodic_evidence
''')
            self.assertEqual(result.returncode, 0, result.stderr)
            old = car.state / 'auto-previous'
            self.assertTrue((old / 'after-180s.txt').exists())
            self.assertTrue((old / 'after-300s.txt').exists())
            self.assertIn('boot_uptime_seconds=305', (old / 'after-300s.txt').read_text())
            self.assertIn('socket_port=67 owner=other_or_unavailable', (old / 'after-300s.txt').read_text())
            self.assertEqual(car.run('bin/logs.sh').returncode, 0)
            car.put('proc/modules', '')
            car.put('proc/mounts', '/dev/sda1 /storage/usb0 vfat rw 0 0\n')
            car.put('storage/usb0/KP_USB_EXPORT.txt', 'korea.projection export v1\n')
            self.assertEqual(car.run('bin/logs.sh').returncode, 0)
            out = next(p for p in (car.root / 'storage/usb0').glob('KP_USB_G70_*') if p.is_dir())
            self.assertTrue((out / 'auto-previous/after-300s.txt').exists())
            for p in out.rglob('*'):
                if p.is_file():
                    for secret in (b'PRIVATE_PHONE', b'192.168.43.10', b'aa:bb:cc:dd:ee:ff'):
                        self.assertNotIn(secret, p.read_bytes())
                    self.assertNotEqual(p.name, 'boot.private')


if __name__ == '__main__':
    unittest.main()
