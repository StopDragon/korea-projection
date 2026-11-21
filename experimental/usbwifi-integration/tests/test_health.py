# SPDX-License-Identifier: AGPL-3.0-only
from pathlib import Path
import tempfile
import unittest
from test_bridge import BridgeCar, SHELLS

class HealthTests(unittest.TestCase):
    def test_ap_failure_is_counted_once_per_boot_and_protected_after_three(self):
        for shell in SHELLS:
            with self.subTest(shell=shell),tempfile.TemporaryDirectory() as work:
                c=BridgeCar(work);self.assertEqual(c.service(G70_TEST_ATTACHED='1').returncode,0)
                c.put('props/persist.sys.iap2.wifi','t\n')
                c.put('data/hmgapi/mods/wireless-carplay-aa/mod.json','{}')
                c.put('data/misc/wifi/hostapd-kp.conf','interface=wlan0\n')
                ctrl=c.pkg/'bin/ctrl-status';ctrl.write_text('#!/bin/sh\necho ctrl.state=UNINITIALIZED\n');ctrl.chmod(0o755)
                p=c.work/'health.sh';p.write_text('. "'+str(c.pkg/'bin/common.sh')+'"\nblocked() { state "$1"; return 1; }\nup_seconds() { echo 400; }\nAP_WAIT_AT=0\nap_health_tick\n')
                import subprocess
                for i in range(1,4):
                    c.put('proc/sys/kernel/random/boot_id','boot-'+str(i)+'\n')
                    for repeat in range(2):
                        r=subprocess.run([shell,str(p)],env=c.env,capture_output=True,text=True)
                        self.assertEqual(r.returncode,1,r.stderr)
                        self.assertEqual((c.state/'ap-failed-boots').read_text().strip(),str(i))
                self.assertEqual((c.state/'blocked').read_text().strip(),'repeated_ap_validation_failure')
                self.assertEqual((c.state/'state.txt').read_text().strip(),'ap_validation_failed_reboot_required')

    def test_hmg_work_in_progress_is_not_counted_as_ap_failure(self):
        with tempfile.TemporaryDirectory() as work:
            c=BridgeCar(work);c.service(G70_TEST_ATTACHED='1')
            c.put('props/persist.sys.iap2.wifi','t\n')
            c.put('data/hmgapi/mods/wireless-carplay-aa/mod.json','{}')
            c.put('data/misc/wifi/hostapd-kp.conf','interface=wlan0\n')
            c.put('data/local/tmp/korea-projection-progress.txt','boot=boot-1\nstate=run\npct=70\n')
            ctrl=c.pkg/'bin/ctrl-status';ctrl.write_text('#!/bin/sh\necho ctrl.state=UNINITIALIZED\n');ctrl.chmod(0o755)
            p=c.work/'health.sh';p.write_text('. "'+str(c.pkg/'bin/common.sh')+'"\nup_seconds() { echo 400; }\nAP_WAIT_AT=0\nap_health_tick\n')
            import subprocess
            r=subprocess.run(['dash',str(p)],env=c.env,capture_output=True,text=True)
            self.assertEqual(r.returncode,0,r.stderr)
            self.assertFalse((c.state/'ap-failed-boot').exists())
