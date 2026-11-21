# SPDX-License-Identifier: AGPL-3.0-only
from pathlib import Path
import hashlib
import os
import shutil
import subprocess
import tempfile
import unittest

BASE = Path(__file__).resolve().parent.parent
SHELLS = [s for s in ('bash', 'dash', 'ksh') if shutil.which(s)]
IDS = ['0846:9055','0b05:1841','0b05:184c','0bda:b812','0bda:b82c',
       '13b1:0043','13b1:0045','2001:331c','2001:331e','2001:331f',
       '20f4:808a','2357:0115','2357:012d','2357:012e','2357:0138',
       '7392:b822','7392:c822']


class HeadUnit:
    def __init__(self, work):
        self.root = Path(work)/'car'
        self.tools = Path(work)/'tools'
        self.tools.mkdir()
        self.app = self.root/'data/nemesis/apps/korea.projection'
        shutil.copytree(BASE/'pkg/usb/compat',self.app/'usb/compat')
        for key,val in {'ro.build.product':'NEEV.KOR.0000.V039.001.260902',
                        'ro.board.platform':'tcc803x',
                        'ro.build.version.release':'4.4.2'}.items():
            self.put('props/'+key,val+'\n')
        for path,val in {'proc/sys/kernel/osrelease':'3.18.24-tcc\n',
                         'proc/sys/kernel/modules_disabled':'0\n',
                         'proc/config.gz':'config fixture',
                         'system/wifi/bcmdhd.ko':'stock module fixture',
                         'data/nemesis/apps/korea.projection/usb/g70/modules/88x2bu.ko':'driver fixture'}.items():
            self.put(path,val)
        self.put('proc/kallsyms',''.join('00000000 r __ksymtab_'+n+'\n'
                 for n in (BASE/'pkg/usb/compat/required-symbols.txt').read_text().splitlines()))
        self.stub('getprop','cat "$KP_ROOT/props/$1" 2>/dev/null\n')
        self.stub('md5','''case "$1" in
*/proc/config.gz) echo "${TEST_CONFIG_HASH:-1fd51a10a44ae9ff77fa9ecc94192026}" ;;
*/system/wifi/bcmdhd.ko) echo "${TEST_STOCK_HASH:-7da276f0d683eecc6c302068331ef274}" ;;
*/usb/g70/modules/88x2bu.ko) echo "${TEST_DRIVER_HASH:-36f26af089959fa547b7cc30aff445b9}" ;;
*) exit 1 ;;
esac
''')
        for command in ('insmod','rmmod','modprobe','ip','iptables','svc','settings',
                        'hmgapid','setprop','nemesis','hostapd','dnsmasq','mount'):
            self.stub(command,'echo '+command+' >> "$KP_ROOT/forbidden"\nexit 99\n')
        self.env = dict(os.environ,KP_ROOT=str(self.root),KP_APP=str(self.app),
                        PATH=str(self.tools)+':/usr/bin:/bin:/sbin')

    def put(self,path,value):
        p=self.root/path;p.parent.mkdir(parents=True,exist_ok=True)
        p.write_text(value)

    def stub(self,name,body):
        p=self.tools/name;p.write_text('#!/bin/sh\n'+body);p.chmod(0o755)

    def usb(self,ident='0bda:b812',slot='4-1',klass=('ff','ff','ff')):
        v,p=ident.split(':')
        self.put('sys/bus/usb/devices/'+slot+'/idVendor',v+'\n')
        self.put('sys/bus/usb/devices/'+slot+'/idProduct',p+'\n')
        for name,val in zip(('bInterfaceClass','bInterfaceSubClass','bInterfaceProtocol'),klass):
            self.put('sys/bus/usb/devices/'+slot+':1.0/'+name,val+'\n')

    def native(self):
        p=self.root/'sys/class/net/wlan0/device/driver';p.mkdir(parents=True)
        (p/'module').symlink_to('/sys/module/bcmdhd')

    def run(self,shell='dash',**extra):
        before={str(p.relative_to(self.root)):hashlib.sha256(p.read_bytes()).hexdigest()
                for p in self.root.rglob('*') if p.is_file() and not p.is_symlink()}
        command='. "$KP_APP/usb/compat/select.sh"; kp_cap_detect; kp_cap_print'
        r=subprocess.run([shell,'-c',command],env=dict(self.env,**extra),
                         capture_output=True,text=True,timeout=4)
        assert r.returncode==0,(r.stdout,r.stderr)
        assert not r.stderr,r.stderr
        after={str(p.relative_to(self.root)):hashlib.sha256(p.read_bytes()).hexdigest()
               for p in self.root.rglob('*') if p.is_file() and not p.is_symlink()}
        assert before==after,'Inspection changed vehicle files'
        assert not (self.root/'forbidden').exists()
        return dict(line.split('=',1) for line in r.stdout.splitlines())


class CompatibilityTests(unittest.TestCase):
    def test_other_models_are_selected_by_fingerprints_on_all_shells(self):
        for shell in SHELLS:
            for model in ('NEEV','GL3HEV','CN7','SG2EV','UNKNOWN123'):
                with self.subTest(shell=shell,model=model), tempfile.TemporaryDirectory() as t:
                    car=HeadUnit(t);car.usb()
                    car.put('props/ro.build.product',model+'.KOR.0000.V039.001.260902\n')
                    self.assertEqual(car.run(shell)['compat_route'],'generic-usb')

    def test_new_firmware_name_with_same_hardware_fingerprints_is_not_name_blocked(self):
        with tempfile.TemporaryDirectory() as t:
            c=HeadUnit(t);c.usb();c.put('props/ro.build.product','UNLISTED.KOR.0000.V999.001.261001\n')
            self.assertEqual(c.run()['compat_route'],'generic-usb')

    def test_all_seventeen_ac_ids_with_correct_interface(self):
        for ident in IDS:
            with self.subTest(ident=ident),tempfile.TemporaryDirectory() as t:
                car=HeadUnit(t);car.usb(ident)
                self.assertEqual(car.run()['compat_route'],'generic-usb')

    def test_pre_registration_candidate_needs_matching_cohort_even_without_dongle(self):
        with tempfile.TemporaryDirectory() as t:
            car=HeadUnit(t)
            self.assertEqual(car.run()['compatible_usb_count'],'0')
            self.assertEqual(car.run()['compat_route'],'generic-usb')

    def test_native_radio_wins_over_supported_or_ax_dongle(self):
        for ident in ('0bda:b812','0bda:b851'):
            with self.subTest(ident=ident),tempfile.TemporaryDirectory() as t:
                car=HeadUnit(t);car.native();car.usb(ident)
                self.assertEqual(car.run()['compat_route'],'native')

    def test_mismatched_or_unknown_fingerprints_never_select_generic(self):
        for env,reason in [('TEST_CONFIG_HASH','kernel_config_not_in_cohort'),
                           ('TEST_STOCK_HASH','stock_module_not_in_cohort'),
                           ('TEST_DRIVER_HASH','bundled_driver_changed')]:
            with self.subTest(env=env),tempfile.TemporaryDirectory() as t:
                car=HeadUnit(t);car.usb()
                result=car.run(**{env:'0'*32})
                self.assertEqual(result['compat_route'],'probe-only')
                self.assertEqual(result['compat_reason'],reason)

    def test_same_kernel_release_on_tcc897x_is_insufficient(self):
        with tempfile.TemporaryDirectory() as t:
            car=HeadUnit(t);car.usb();car.put('props/ro.board.platform','tcc897x\n')
            self.assertEqual(car.run()['compat_reason'],'platform_cohort_unknown')

    def test_missing_export_or_missing_export_file_are_not_success(self):
        for missing_file in (False,True):
            with self.subTest(missing_file=missing_file),tempfile.TemporaryDirectory() as t:
                car=HeadUnit(t);car.usb()
                p=car.root/'proc/kallsyms'
                if missing_file:p.unlink()
                else:p.write_text('\n'.join(p.read_text().splitlines()[1:])+'\n')
                self.assertEqual(car.run()['compat_route'],'probe-only')

    def test_two_dongles_wrong_usb_class_and_ax_are_rejected(self):
        for scenario,reason in [('multi','multiple_supported_adapters'),
                                ('class','usb_interface_mismatch'),
                                ('ax','usb_id_not_in_compiled_driver'),('cd','usb_cdrom_mode')]:
            with self.subTest(scenario=scenario),tempfile.TemporaryDirectory() as t:
                car=HeadUnit(t)
                if scenario=='multi':car.usb();car.usb('2357:012e','4-2')
                elif scenario=='class':car.usb(klass=('08','06','50'))
                elif scenario=='ax':car.usb('0bda:b832')
                else:car.usb('0bda:1a2b')
                self.assertEqual(car.run()['compat_reason'],reason)

    def test_conflicting_package_and_foreign_wlan_are_preserved(self):
        for conflict in (False,True):
            with self.subTest(conflict=conflict),tempfile.TemporaryDirectory() as t:
                car=HeadUnit(t);car.usb()
                if conflict:car.put('data/nemesis/apps/jmk-wifi/NEMESIS.data','id=jmk-wifi\n')
                else:car.put('sys/class/net/wlan0/ifindex','5\n')
                self.assertEqual(car.run()['compat_route'],'probe-only')

    def test_other_os_region_kernel_and_disabled_modules_are_rejected(self):
        for path,val in [('props/ro.build.product','NEEV.USA.S5W_M.V016.010.260903'),
                         ('props/ro.build.version.release','10'),
                         ('proc/sys/kernel/osrelease','3.10.0'),
                         ('proc/sys/kernel/modules_disabled','1')]:
            with self.subTest(path=path,val=val),tempfile.TemporaryDirectory() as t:
                car=HeadUnit(t);car.usb();car.put(path,val+'\n')
                self.assertEqual(car.run()['compat_route'],'probe-only')

    def test_output_cannot_claim_a_vehicle_or_projection_pass(self):
        with tempfile.TemporaryDirectory() as t:
            car=HeadUnit(t);car.usb();r=car.run()
            self.assertEqual(r['vehicle_validation'],'not_performed')
            self.assertEqual(r['hmg_map_validation'],'still_required')


if __name__=='__main__':unittest.main()
