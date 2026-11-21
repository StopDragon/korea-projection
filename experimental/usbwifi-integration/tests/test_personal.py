# SPDX-License-Identifier: AGPL-3.0-only
from pathlib import Path
import configparser
import hashlib
import json
import os
import shutil
import signal
import subprocess
import tempfile
import time
import unittest
import zipfile

from car_fixture import Car

BASE = Path(__file__).resolve().parent.parent
PRODUCTS = {'g70': 'IKFL.KOR.0000.V039.001.260902',
            'nx4': 'NX4HEV.KOR.0000.V039.001.260902',
            'ev6': 'CVEV.KOR.0000.V039.001.260902'}
IDS = json.loads((BASE/'ORIGINS.json').read_text())['allowed_usb_ids']


class PersonalCar(Car):
    def __init__(self, work, profile='g70'):
        super().__init__(work)
        self.app = self.root/'data/nemesis/apps/korea.projection'
        shutil.copytree(BASE/'pkg', self.app,
                        ignore=shutil.ignore_patterns('source', 'COPYING', 'licenses', '*.tar.gz'))
        self.put('props/ro.build.product', PRODUCTS.get(profile, profile)+'\n')
        self.put('proc/kallsyms', ''.join('00000000 r __ksymtab_'+n+'\n' for f in (BASE/'pkg/usb/compat').glob('required-symbols*.txt') for n in f.read_text().splitlines()))
        self.put('props/sys.boot_completed', '1\n')
        self.put('props/persist.sys.iap2.wifi', 't\n')
        self.put('proc/sys/kernel/random/boot_id', 'boot-1\n')
        self.put('proc/uptime', '500.00 200.00\n')
        self.put('proc/net/tcp', '')
        self.put('proc/net/tcp6', '')
        self.put('proc/net/if_inet6', '')
        self.put('data/hmgapi/maps/test/car.json', '{"model":"fixture"}\n')
        self.put('data/hmgapi/mods/wireless-carplay-aa/mod.json', '{"version":"2.4.5"}\n')
        self.put('data/hmgapi/installed', 'version 1.1.0-rc.7\n')
        self.stub('logcat', "echo '11-21 16:00:00.000 E/CarPlay( 44): socket error PRIVATE_PHONE ssid=SECRET'\n")
        self.stub('chown', 'exit 0\n')
        self.stub('sleep', '/bin/sleep 0.02\n')
        bb = self.app/'bin/busybox'
        bb.write_text('''#!/usr/bin/python3
import os,sys,hashlib,shutil
from pathlib import Path
a=sys.argv[1:];c=a.pop(0)
if c=='md5sum':
 if not a:a=['-']
 for p in a:
  try:d=sys.stdin.buffer.read() if p=='-' else Path(p).read_bytes()
  except OSError:sys.exit(1)
  print(hashlib.md5(d).hexdigest()+'  '+p)
elif c=='ps':
 p=Path(os.environ['G70_DIAG_TEST_ROOT'])/'ps';print(p.read_text() if p.exists() else '',end='')
elif c=='ifconfig':
 if len(a)==1:print('wlan0 Link encap:Ethernet\\n  inet addr:192.168.43.1  Bcast:192.168.43.255  Mask:255.255.255.0')
 else:sys.exit(97)
else:
 executable=shutil.which(c)
 if not executable:sys.exit(127)
 os.execv(executable,[c]+a)
''')
        bb.chmod(0o755)
        ctrl = self.app/'usb/g70/bin/ctrl-status'
        ctrl.write_text('#!/bin/sh\necho ctrl.state=ENABLED\necho ctrl.stations=1\n')
        ctrl.chmod(0o755)
        (self.app/'usb/g70/ctrl').mkdir()
        self.env.update(KP_PERSONAL_TEST_PATH=str(self.tools)+':/usr/bin:/bin:/sbin',
                        KP_PERSONAL_APP=str(self.app), APP=str(self.app), BB=str(bb),
                        PROC=str(self.root/'proc'), PROCNET=str(self.root/'proc/net'), BOOT_ID=str(self.root/'proc/sys/kernel/random/boot_id'),
                        UPTIME=str(self.root/'proc/uptime'), W=str(self.root/'data/local/tmp/korea.projection'),
                        BK=str(self.root/'data/nemesis/backup/korea.projection'),
                        HMGDATA=str(self.root/'data/hmgapi'),
                        USB_SYS=str(self.root/'sys/bus/usb/devices'),
                        USB_NET=str(self.root/'sys/class/net'),
                        USB_MODULES=str(self.root/'proc/modules'),
                        USB_MODULE_DIR=str(self.app/'modules'),
                        USB_SRCVERSION_FILE=str(self.root/'sys/module/88x2bu/srcversion'),
                        USB_KALLSYMS=str(self.root/'proc/kallsyms'),
                        USB_OSRELEASE=str(self.root/'proc/sys/kernel/osrelease'),
                        USB_APPS_ROOT=str(self.root/'data/nemesis/apps'),
                        USB_PACKAGES_ROOT=str(self.root/'data/nemesis/packages'))

    def run(self, relative, *args, shell='dash', **extra):
        return subprocess.run([shell, str(self.app/relative), *args],
                              env=dict(self.env, **extra), capture_output=True, text=True, timeout=20)

    def lib(self, command, shell='dash'):
        return subprocess.run([shell, '-c', 'HOTSPOT_LIB=1 . "$APP/svc/hotspot.sh"; '+command],
                              env=self.env, capture_output=True, text=True, timeout=12)

    def usb(self, ident='0bda:b812', slot='4-1', family='88x2bu', bind=True):
        v,p=ident.split(':')
        self.put(f'sys/bus/usb/devices/{slot}/idVendor',v+'\n')
        self.put(f'sys/bus/usb/devices/{slot}/idProduct',p+'\n')
        for attr in ('bInterfaceClass','bInterfaceSubClass','bInterfaceProtocol'):
            self.put(f'sys/bus/usb/devices/{slot}:1.0/{attr}','ff\n')
        if not bind:return
        self.put('proc/modules',family+' 42 0 - Live 0x0\n')
        self.put(f'sys/module/{family}/srcversion',
                 ('533BB7E5866E52F63B9ACCB' if family=='8851bu' else '46A9CFB83C8F6E0C09E8AAC')+'\n')
        self.put('sys/class/net/wlan0/ifindex','9\n')
        self.put('sys/class/net/wlan0/device/modalias',f'usb:v{v.upper()}p{p.upper()}d0210dc00dsc00dp00icFFiscFFipFFin00\n')
        d=self.root/'sys/class/net/wlan0/device/driver';d.mkdir(parents=True)
        (d/'module').symlink_to(self.root/f'sys/module/{family}')
        module=self.app/('usb/g70/modules/'+family+'.ko')
        h=hashlib.md5(module.read_bytes()).hexdigest()
        self.put('data/nemesis/backup/korea.projection/usb-'+self.profile+'/loaded-boot','boot-1:'+h+'\n')
        self.put('data/hmgapi/public/wifi-chip','')

    @property
    def profile(self):
        product=(self.root/'props/ro.build.product').read_text().strip()
        return next((k for k,v in PRODUCTS.items() if v==product),'generic-usb')

    def observe(self):
        r=self.run('usb/cache.sh','--observe')
        if r.returncode:raise AssertionError(r.stdout+r.stderr)
        p=self.root/'data/nemesis/backup/korea.projection/compatibility-memory/last.ini'
        return dict(line.split('=',1) for line in p.read_text().splitlines())


class PersonalTests(unittest.TestCase):
    def test_ev6_helper_applies_only_its_own_plan_after_exact_stock_gate(self):
        for pending in (False,True):
            with self.subTest(pending=pending),tempfile.TemporaryDirectory() as work:
                c=PersonalCar(work,'ev6');c.put('props/ro.product.opt.stepofspec','110\n')
                c.stub('md5','''case "$1" in
*/HKMC_GPM.odex) echo c060a43d7a9234acf3319fa05dd263b1 ;;
*/services.odex) echo 140e54564b0934258cbfa89fa3fa5b98 ;;
*/system/wifi/bcmdhd.ko) echo 7da276f0d683eecc6c302068331ef274 ;;
*) /usr/bin/python3 -c 'import hashlib,sys; print(hashlib.md5(open(sys.argv[1],"rb").read()).hexdigest())' "$1" ;;
esac
''')
                h=c.root/'system/bin/hmgapid';h.parent.mkdir(parents=True)
                other='other-module' if pending else 'ev6-kr-aa-keep'
                h.write_text('#!/bin/sh\necho "$*" >> "$G70_DIAG_TEST_ROOT/hmg-calls"\n'
                             'if [ "$1 $2" = "engine plan" ]; then echo "change   /data/fixture ['+other+']"; fi\nexit 0\n')
                h.chmod(0o755)
                r=c.run('usb/ev6-mod.sh','install')
                self.assertEqual(r.returncode,1 if pending else 0,r.stdout+r.stderr)
                calls=(c.root/'hmg-calls').read_text()
                self.assertEqual('engine apply' in calls,not pending)
                self.assertEqual((c.app/'mod/id').read_text().strip(),'ev6-kr-aa-keep')
    def test_profile_dispatch_and_signed_modes_on_all_shells_are_read_only(self):
        for profile in PRODUCTS:
            with self.subTest(profile=profile), tempfile.TemporaryDirectory() as work:
                c=PersonalCar(work,profile)
                for shell in ('bash','dash','ksh'):
                    r=c.lib('echo "$KP_PROFILE|$MOD_VER|$MOD_MD5"',shell)
                    self.assertEqual(r.returncode,0,r.stderr)
                    expected='2.4.6' if profile=='nx4' else '2.4.5'
                    self.assertEqual(r.stdout.strip().split('|')[:2],[profile,expected])
                self.assertFalse(Path(c.env['G70_TEST_DENIED']).exists())
                self.assertFalse(Path(c.env['G70_TEST_CALLS']).exists())

    def test_actual_native_radio_takes_priority_even_on_named_vehicle(self):
        with tempfile.TemporaryDirectory() as work:
            c=PersonalCar(work)
            d=c.root/'sys/class/net/wlan0/device/driver';d.mkdir(parents=True)
            (d/'module').symlink_to('/sys/module/bcmdhd')
            r=c.lib('echo "$KP_PROFILE"')
            self.assertEqual(r.stdout.strip(),'native')

    def test_non_gen5w_android_goes_to_diagnostics_without_driver_actions(self):
        with tempfile.TemporaryDirectory() as work:
            c=PersonalCar(work);c.put('props/ro.build.version.release','10\n')
            self.assertEqual(c.lib('echo "$KP_PROFILE"').stdout.strip(),'probe-only')
            self.assertFalse(Path(c.env['G70_TEST_CALLS']).exists())

    def test_all_models_use_common_hardware_selection_and_multi_guard(self):
        for profile in ('g70','nx4','ev6','OTHER.KOR.0000.V039.001.261001'):
            with self.subTest(profile=profile),tempfile.TemporaryDirectory() as work:
                c=PersonalCar(work,profile)
                for ident in IDS:
                    self.assertEqual(c.lib('kp_cap_ac_id '+ident).returncode,0)
                c.usb('0bda:b832',bind=False)
                self.assertEqual(c.lib('echo "$KP_PROFILE"').stdout.strip(),'probe-only')
                shutil.rmtree(c.root/'sys/bus/usb/devices')
                c.usb(bind=False);c.usb('2357:012e',slot='4-2',bind=False)
                self.assertEqual(c.lib('echo "$KP_PROFILE"').stdout.strip(),'probe-only')

    def test_nx4_897x_and_wrong_kernel_cannot_preload(self):
        for prop,value in [('props/ro.board.platform','tcc897x'),('proc/sys/kernel/osrelease','4.14.0')]:
            with self.subTest(prop=prop),tempfile.TemporaryDirectory() as work:
                c=PersonalCar(work,'nx4');c.put(prop,value+'\n')
                self.assertEqual(c.lib('echo "$KP_PROFILE"').stdout.strip(),'probe-only')
                self.assertFalse(Path(c.env['G70_TEST_CALLS']).exists())

    def test_common_cache_rejects_unowned_resident_module(self):
        for profile in ('g70','nx4','ev6'):
            with self.subTest(profile=profile),tempfile.TemporaryDirectory() as work:
                c=PersonalCar(work,profile);c.usb();c.observe()
                (c.root/('data/nemesis/backup/korea.projection/usb-'+profile+'/loaded-boot')).unlink()
                self.assertEqual(c.observe()['cache_reused'],'no')

    def test_ev6_helper_is_never_installed_on_g70_or_mismatched_stock_files(self):
        for profile in ('g70','ev6'):
            with self.subTest(profile=profile),tempfile.TemporaryDirectory() as work:
                c=PersonalCar(work,profile)
                h=c.root/'system/bin/hmgapid';h.parent.mkdir(parents=True)
                h.write_text('#!/bin/sh\necho "$*" >> "$G70_DIAG_TEST_ROOT/hmg-calls"\n');h.chmod(0o755)
                self.assertNotEqual(c.run('usb/ev6-mod.sh','install').returncode,0)
                self.assertFalse((c.root/'hmg-calls').exists())

    def test_new_checksum_driver_keeps_the_required_abi_and_baseline(self):
        new=(BASE/'pkg/usb/g70/modules/88x2bu.ko').read_bytes()
        old=(BASE/'pkg/usb/g70/modules/88x2bu-baseline.ko').read_bytes()
        self.assertNotEqual(hashlib.sha256(new).digest(),hashlib.sha256(old).digest())
        for blob in (new,old):
            self.assertIn(b'vermagic=3.18.24-tcc SMP preempt mod_unload ARMv7 p2v8 ',blob)
            self.assertIn(b'srcversion=46A9CFB83C8F6E0C09E8AAC',blob)
        self.assertTrue((BASE/'pkg/usb/g70/source/driver/patches/0004-rx-checksum-offload-off.patch').is_file())

    def test_package_versions_preserved_binaries_and_licenses(self):
        import build
        for name,expected in build.PINNED.items():
            self.assertEqual(hashlib.sha256((BASE/'pkg'/name).read_bytes()).hexdigest(),expected,name)
        for folder in ('pkg','logs-pkg'):
            cfg=configparser.ConfigParser(interpolation=None);cfg.read(BASE/folder/'NEMESIS.data')
            self.assertEqual(cfg['nemesis']['package-version'],'1.7.4.2')
        self.assertTrue((BASE/'pkg/usb/ev6/ADDITIONAL-TERMS.md').is_file())
        self.assertFalse((BASE/'pkg/modules/88x2bu.ko').exists())


class CacheTests(unittest.TestCase):
    def test_reported_screen_freeze_remains_unvalidated_until_positive_user_retest(self):
        with tempfile.TemporaryDirectory() as work:
            c=PersonalCar(work);c.usb();info=c.observe()
            report=c.root/'report.txt'
            report.write_text('fingerprint='+info['fingerprint']+'\ndisplay_confirmed=no\nstable_minutes=0\nproblem=screen_freeze\n')
            self.assertEqual(c.run('usb/cache.sh','--import',str(report)).returncode,0)
            c.observe();again=c.observe()
            self.assertEqual(again['user_reported_failure'],'screen_freeze')
            self.assertEqual(again['cache_reused'],'no')
            self.assertEqual(again['highest_observed'],'invalidated')
            report.write_text('fingerprint='+again['fingerprint']+'\ndisplay_confirmed=yes\nstable_minutes=15\nproblem=none\n')
            self.assertEqual(c.run('usb/cache.sh','--import',str(report)).returncode,0)
            self.assertEqual(c.observe()['user_reported_display'],'yes')
    def test_remembers_profile_without_claiming_screen_or_stability(self):
        with tempfile.TemporaryDirectory() as work:
            c=PersonalCar(work);c.usb()
            c.put('proc/net/tcp','0: 012BA8C0:1B58 0200000A:4444 01 rest\n')
            first=c.observe();second=c.observe()
            self.assertEqual(second['cache_reused'],'yes')
            self.assertEqual(second['highest_observed'],'projection_control_observed')
            self.assertEqual(second['user_reported_display'],'unconfirmed')
            self.assertEqual(second['user_reported_stable_minutes'],'0')
            self.assertEqual(second['automatic_screen_verification'],'no')
            self.assertEqual(first['fingerprint'],second['fingerprint'])

    def test_any_relevant_software_or_hardware_change_invalidates_memory(self):
        changes=[('props/ro.build.product','IKFL.KOR.0000.V039.001.260903\n'),
                 ('props/ro.board.platform','tcc897x\n'),('proc/config.gz','new config'),
                 ('system/wifi/bcmdhd.ko','new stock'),
                 ('data/hmgapi/maps/test/car.json','{"model":"new"}'),
                 ('data/hmgapi/mods/wireless-carplay-aa/mod.json','{"version":"new"}'),
                 ('data/nemesis/apps/korea.projection/CODE_FINGERPRINT','new build')]
        for path,value in changes:
            with self.subTest(path=path),tempfile.TemporaryDirectory() as work:
                c=PersonalCar(work);c.usb();c.observe();c.put(path,value)
                c.run('usb/cache.sh','--observe')
                cached=c.root/'data/nemesis/backup/korea.projection/compatibility-memory/last.ini'
                current=dict(line.split('=',1) for line in cached.read_text().splitlines())
                if current['fingerprint']!=c.observe()['fingerprint']:self.fail('Unstable fingerprint')
                # A now-unsupported route may preserve the old record, but cannot mark a new reuse.
                if path.startswith('props/ro.build.product'):continue
                self.assertEqual(current['cache_reused'],'no')

    def test_no_dongle_never_reuses_or_overwrites_saved_vehicle_record(self):
        with tempfile.TemporaryDirectory() as work:
            c=PersonalCar(work);c.usb();c.observe()
            f=c.root/'data/nemesis/backup/korea.projection/compatibility-memory/last.ini';before=f.read_bytes()
            shutil.rmtree(c.root/'sys/bus/usb/devices')
            self.assertEqual(c.run('usb/cache.sh','--observe').returncode,0)
            self.assertEqual(f.read_bytes(),before)

    def test_loader_failure_invalidates_reported_success_and_counts_once_per_boot(self):
        with tempfile.TemporaryDirectory() as work:
            c=PersonalCar(work);c.usb();c.observe()
            c.put('data/nemesis/backup/korea.projection/usb-g70/state.txt','driver_load_failed\n')
            one=c.observe();two=c.observe()
            self.assertEqual(one['failure_state'],'controller_protected')
            self.assertEqual(one['failure_boots'],two['failure_boots'])
            self.assertEqual(two['highest_observed'],'invalidated')
            self.assertEqual(two['cache_reused'],'no')

    def test_user_confirmation_requires_matching_fingerprint_and_live_revalidation(self):
        with tempfile.TemporaryDirectory() as work:
            c=PersonalCar(work);c.usb();info=c.observe()
            report=c.root/'report.txt';report.write_text('fingerprint='+info['fingerprint']+'\ndisplay_confirmed=yes\nstable_minutes=15\n')
            self.assertEqual(c.run('usb/cache.sh','--import',str(report)).returncode,0)
            info=c.observe()
            self.assertEqual(info['user_reported_display'],'yes')
            self.assertEqual(info['user_reported_stable_minutes'],'15')
            report.write_text('fingerprint=wrong\ndisplay_confirmed=yes\nstable_minutes=999\n')
            self.assertNotEqual(c.run('usb/cache.sh','--import',str(report)).returncode,0)

    def test_memory_exports_contain_no_phone_or_network_identifiers(self):
        with tempfile.TemporaryDirectory() as work:
            c=PersonalCar(work);c.usb();c.observe()
            out=c.run('usb/cache.sh','--print')
            self.assertEqual(out.returncode,0)
            for secret in ('PRIVATE_PHONE','192.168.43.1','ssid','password','VIN','MAC'):
                self.assertNotIn(secret,out.stdout)
            self.assertIn('automatic_screen_verification=no',out.stdout)

    def test_disabled_mode_is_not_reused_as_a_successful_setup(self):
        with tempfile.TemporaryDirectory() as work:
            c=PersonalCar(work);c.usb();c.observe()
            c.put('data/hmgapi/mods/wireless-carplay-aa/.disabled','')
            self.assertEqual(c.observe()['cache_reused'],'no')
            self.assertEqual(c.observe()['cache_reused'],'no')


class LifecycleTests(unittest.TestCase):
    def test_postinstall_prepares_control_socket_and_explicit_driver_preference(self):
        with tempfile.TemporaryDirectory() as work:
            c=PersonalCar(work)
            (c.app/'scripts/post-native.sh').write_text('#!/bin/sh\nexit 0\n')
            c.put('storage/usb0/KP_G70_BASELINE_DRIVER.txt','')
            r=c.run('scripts/post.sh')
            self.assertEqual(r.returncode,0,r.stderr)
            self.assertEqual((c.root/'data/nemesis/backup/korea.projection/usb-g70/driver-profile').read_text().strip(),'baseline')
            self.assertTrue((c.app/'usb/g70/ctrl').is_dir())

    def test_uninstall_keeps_preexisting_or_replaced_marker_and_updates_keep_owned_marker(self):
        for scenario in ('owned','preexisting','replaced','update'):
            with self.subTest(scenario=scenario),tempfile.TemporaryDirectory() as work:
                c=PersonalCar(work)
                (c.app/'scripts/preun-native.sh').write_text('#!/bin/sh\n[ -f "$G70_DIAG_TEST_ROOT/data/local/tmp/nemesis/stage/korea.projection/NEMESIS.data" ] || sh "$APP/usb/cleanup-marker.sh"\nexit 0\n')
                c.put('data/hmgapi/public/wifi-chip','changed' if scenario=='replaced' else '')
                if scenario!='preexisting':c.put('data/nemesis/backup/korea.projection/usb-g70/chip-owned','')
                if scenario=='update':c.put('data/local/tmp/nemesis/stage/korea.projection/NEMESIS.data','id=korea.projection\n')
                r=c.run('scripts/preun.sh')
                self.assertEqual(r.returncode,0,r.stderr)
                self.assertEqual((c.root/'data/hmgapi/public/wifi-chip').exists(),scenario!='owned')

    def test_g70_supervisor_waits_for_radio_and_stops_children_for_single_port_export(self):
        with tempfile.TemporaryDirectory() as work:
            c=PersonalCar(work)
            state=c.root/'data/nemesis/backup/korea.projection/usb-g70';state.mkdir(parents=True)
            calls=c.root/'order'
            radio=c.app/'usb/g70/bin/wifi.sh'
            radio.write_text('''#!/bin/sh
S="$G70_DIAG_TEST_ROOT/data/nemesis/backup/korea.projection/usb-g70"
echo radio-ready >> "$G70_DIAG_TEST_ROOT/order"
echo boot-1 > "$S/runtime.boot"; echo wifi_ready > "$S/state.txt"
trap 'echo radio-stop >> "$G70_DIAG_TEST_ROOT/order"; exit 0' TERM INT
while true; do /bin/sleep 0.02 & wait $!; done
''')
            core=c.app/'svc/core-g70.sh'
            core.write_text('''main() {
echo core-start >> "$G70_DIAG_TEST_ROOT/order"
trap 'echo core-stop >> "$G70_DIAG_TEST_ROOT/order"; exit 0' TERM INT
while true; do /bin/sleep 0.02 & wait $!; done
}
''')
            process=subprocess.Popen(['dash',str(c.app/'svc/personal.sh')],env=c.env,
                                     stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
            try:
                deadline=time.monotonic()+5
                while time.monotonic()<deadline:
                    if calls.exists() and 'core-start' in calls.read_text():break
                    time.sleep(.02)
                self.assertIn('core-start',calls.read_text())
                self.assertLess(calls.read_text().index('radio-ready'),calls.read_text().index('core-start'))
                (state/'maintenance').write_text('requested\n')
                deadline=time.monotonic()+4
                while time.monotonic()<deadline and 'core-stop' not in calls.read_text():time.sleep(.02)
                self.assertIn('core-stop',calls.read_text())
                self.assertIn('radio-stop',calls.read_text())
            finally:
                try:os.killpg(process.pid,signal.SIGTERM)
                except ProcessLookupError:pass
                process.wait(timeout=4)

    def test_nx4_single_port_capture_pause_export_resume_is_private(self):
        with tempfile.TemporaryDirectory() as work:
            c=PersonalCar(work,'nx4');c.usb()
            r=c.run('usb/logs.sh')
            self.assertEqual(r.returncode,0,r.stderr)
            state=c.root/'data/nemesis/backup/korea.projection/usb-nx4'
            self.assertTrue((state/'maintenance').is_file())
            c.put('proc/modules','')
            c.put('proc/mounts','/dev/sda1 /storage/usb0 vfat rw 0 0\n')
            c.put('storage/usb0/KP_USB_EXPORT.txt','korea.projection export v1\n')
            r=c.run('usb/logs.sh')
            self.assertEqual(r.returncode,0,r.stderr)
            self.assertFalse((state/'maintenance').exists())
            exported=next(p for p in (c.root/'storage/usb0').glob('KP_USB_*') if p.is_dir())
            self.assertTrue((exported/'EXPORT_COMPLETE.txt').is_file())
            for f in exported.rglob('*'):
                if f.is_file():
                    self.assertNotIn(b'PRIVATE_PHONE',f.read_bytes())
                    self.assertNotIn(b'SECRET',f.read_bytes())


if __name__ == '__main__':
    unittest.main()
