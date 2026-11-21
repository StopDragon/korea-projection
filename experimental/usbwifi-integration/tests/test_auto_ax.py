# SPDX-License-Identifier: AGPL-3.0-only
from pathlib import Path
import re
import tempfile
import unittest
from test_personal import BASE, PersonalCar

AX_IDS=['0bda:b831','0bda:b851','2001:332a','2c4e:0128','3625:010b','7392:e611']

class AutoAxTests(unittest.TestCase):
    def prepare_loader(self,c):
        c.stub('insmod','''/usr/bin/python3 - "$@" <<'STUB'
import os,sys
from pathlib import Path
r=Path(os.environ['G70_DIAG_TEST_ROOT'])
a=sys.argv[1:]
assert a[0].endswith('/8851bu.ko'),a
assert not any(x.startswith(('rtw_power_mgnt=','rtw_ips_mode=','rtw_enusbss=')) for x in a),a
with (r/'insmod-called').open('a') as f:f.write('one\\n')
(r/'proc/modules').write_text('8851bu 42 0 - Live 0x0\\n')
m=r/'sys/module/8851bu';m.mkdir(parents=True,exist_ok=True);(m/'srcversion').write_text('533BB7E5866E52F63B9ACCB\\n')
u=r/'sys/bus/usb/devices/4-1'
v=(u/'idVendor').read_text().strip().upper();p=(u/'idProduct').read_text().strip().upper()
for i in range(2):
 n=r/('sys/class/net/rtwlan'+str(i));d=n/'device/driver';d.mkdir(parents=True,exist_ok=True)
 (d/'module').symlink_to(m);(n/'ifindex').write_text(str(10+i)+'\\n')
 (n/'device/modalias').write_text('usb:v'+v+'p'+p+'d0200dc00dsc00dp00icFFiscFFipFFin00\\n')
STUB
''')
        c.stub('ip','''/usr/bin/python3 - "$@" <<'STUB'
import os,sys
from pathlib import Path
a=sys.argv[1:];r=Path(os.environ['G70_DIAG_TEST_ROOT'])/'sys/class/net'
assert a[:2]==['link','set'],a
if a[3]=='name':(r/a[2]).rename(r/a[4])
STUB
''')
        cap=c.app/'usb/g70/bin/ap-capabilities'
        cap.write_text('#!/bin/sh\necho ap_capable=yes\necho channel149_allowed=yes\n');cap.chmod(0o755)

    def test_b831_load_bind_ap_query_and_cache_on_g70_nx4_ev6_and_unknown_model(self):
        for model in ['g70','nx4','ev6','NEWCAR.KOR.0000.V039.001.261001']:
            with self.subTest(model=model),tempfile.TemporaryDirectory() as t:
                c=PersonalCar(t,model);c.usb('0bda:b831',family='8851bu',bind=False);self.prepare_loader(c)
                self.assertEqual(c.lib('echo "$KP_DRIVER_FAMILY"').stdout.strip(),'8851bu')
                for repeat in range(2):
                    r=c.run('usb/g70/bin/wifi.sh',G70_BRIDGE_ONCE='1',KP_USB_BACKEND_PROFILE=c.profile)
                    self.assertEqual(r.returncode,0,r.stdout+r.stderr)
                self.assertEqual((c.root/'insmod-called').read_text().count('one'),1)
                self.assertEqual((c.root/'sys/class/net/wlan0/ifindex').read_text().strip(),'11')
                self.assertTrue((c.root/'data/hmgapi/public/wifi-chip').exists())
                a=c.observe();b=c.observe()
                self.assertEqual(b['failure_state'],'none')
                self.assertEqual(b['cache_reused'],'yes')
                self.assertEqual(b['user_reported_display'],'unconfirmed')
                self.assertEqual(b['user_reported_stable_minutes'],'0')

    def test_all_six_ax_ids_have_compiled_alias_and_all_models_select_them(self):
        blob=(BASE/'pkg/usb/g70/modules/8851bu.ko').read_bytes()
        self.assertEqual(int.from_bytes(blob[18:20],'little'),40) # ARM
        aliases=set(re.findall(rb'alias=usb:v([0-9A-F]{4})p([0-9A-F]{4})d[^\x00]*icFFiscFFipFF',blob))
        self.assertEqual({(v+ b':'+p).decode().lower() for v,p in aliases},set(AX_IDS))
        self.assertNotIn(b'alias=usb:v0BDApB832',blob)
        for ident in AX_IDS:
            with self.subTest(ident=ident),tempfile.TemporaryDirectory() as t:
                c=PersonalCar(t,'g70');c.usb(ident,family='8851bu',bind=False)
                self.assertEqual(c.lib('echo "$KP_PROFILE:$KP_DRIVER_FAMILY"').stdout.strip(),'g70:8851bu')

    def test_ap_definitively_unsupported_does_not_publish_ready_marker(self):
        with tempfile.TemporaryDirectory() as t:
            c=PersonalCar(t);c.usb('0bda:b831',family='8851bu',bind=False);self.prepare_loader(c)
            cap=c.app/'usb/g70/bin/ap-capabilities';cap.write_text('#!/bin/sh\necho ap_capable=no\nexit 1\n')
            r=c.run('usb/g70/bin/wifi.sh',G70_BRIDGE_ONCE='1')
            self.assertEqual(r.returncode,1)
            self.assertFalse((c.root/'data/hmgapi/public/wifi-chip').exists())
            self.assertEqual((c.root/'data/nemesis/backup/korea.projection/usb-g70/state.txt').read_text().strip(),'ap_or_channel149_unsupported')

    def test_missing_ax_export_never_authorizes_driver_load(self):
        with tempfile.TemporaryDirectory() as t:
            c=PersonalCar(t);c.usb('0bda:b831',family='8851bu',bind=False)
            c.put('proc/kallsyms','00000000 r __ksymtab_usb_register_driver\n')
            self.assertEqual(c.lib('echo "$KP_PROFILE_REASON"').stdout.strip(),'required_kernel_exports_missing')
            self.assertFalse((c.root/'insmod-called').exists())

    def test_live_family_change_requests_reboot_without_loading_second_driver(self):
        import subprocess,time
        with tempfile.TemporaryDirectory() as t:
            c=PersonalCar(t);c.usb()
            p=subprocess.Popen(['dash',str(c.app/'usb/g70/bin/wifi.sh')],env=c.env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            state=c.root/'data/nemesis/backup/korea.projection/usb-g70/state.txt'
            try:
                until=time.monotonic()+8
                while time.monotonic()<until:
                    if state.exists() and state.read_text().strip()=='wifi_ready':break
                    time.sleep(.03)
                self.assertEqual(state.read_text().strip(),'wifi_ready')
                c.put('sys/bus/usb/devices/4-1/idProduct','b831\n')
                until=time.monotonic()+5
                while time.monotonic()<until:
                    if state.read_text().strip()=='adapter_family_changed_reboot_required':break
                    time.sleep(.03)
                self.assertEqual(state.read_text().strip(),'adapter_family_changed_reboot_required')
                self.assertFalse((c.root/'insmod-called').exists())
            finally:
                p.terminate();p.wait(timeout=5)
