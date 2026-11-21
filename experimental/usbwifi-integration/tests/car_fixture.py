# SPDX-License-Identifier: AGPL-3.0-only
import os
from pathlib import Path

CONFIG_FIXTURE = Path(__file__).resolve().parent / 'fixtures/kernel-config.gz'


class Car:
    def __init__(self, work):
        self.work = Path(work)
        self.root = self.work / 'car'
        self.tools = self.work / 'tools'
        self.tools.mkdir()
        self.put('proc/mounts', '')
        self.put('proc/modules', '')
        self.put('proc/sys/kernel/osrelease', '3.18.24-tcc\n')
        self.put('proc/sys/kernel/modules_disabled', '0\n')
        self.put('proc/kallsyms', '00000000 r __ksymtab_usb_register_driver\n')
        self.put('proc/config.gz', CONFIG_FIXTURE.read_bytes())
        self.put('props/ro.build.product', 'IKFL.KOR.0000.V039.001.260902\n')
        self.put('props/ro.board.platform', 'tcc803x\n')
        self.put('props/ro.build.version.release', '4.4.2\n')
        self.put('system/wifi/bcmdhd.ko', b'proprietary stock file represented by a fingerprint fixture')
        self.put('data/misc/wifi/softap.conf', 'DO_NOT_EXPORT_PASSWORD\n')
        self.stub('getprop', 'cat "$G70_DIAG_TEST_ROOT/props/$1" 2>/dev/null\n')
        self.stub('am', 'echo "$*" >> "$G70_TEST_MESSAGES"\n')
        self.stub('dmesg', "echo '88x2bu: device 01:02:03:04:05:06 DO_NOT_EXPORT_NAME'\n"
                  "echo '88x2bu: Unknown symbol fake_missing_symbol (err 0)'\n"
                  "echo 'usbcore: registered new interface driver rtl88x2bu'\n"
                  "echo 'RTW: rtw_usb_primary_adapter_init Failed! MAC=01:02:03:04:05:06'\n")
        md5 = self.tools / 'md5'
        md5.write_text('''#!/usr/bin/python3
import hashlib,os,sys
p=sys.argv[1]
if p.endswith('/system/wifi/bcmdhd.ko'):
 print('00000000000000000000000000000000' if os.environ.get('G70_TEST_BAD_STOCK') else '7da276f0d683eecc6c302068331ef274')
else:
 try: print(hashlib.md5(open(p,'rb').read()).hexdigest())
 except OSError: sys.exit(1)
''')
        md5.chmod(0o755)
        # Keep the no-interface branch fast while still exercising its bounded wait.
        self.stub('sleep', 'exit 0\n')
        for command in ('rmmod', 'setprop', 'settings', 'svc', 'ip', 'hmgapid'):
            self.stub(command, 'echo forbidden >> "$G70_TEST_DENIED"\nexit 98\n')
        self.env = dict(os.environ, G70_DIAG_TEST_ROOT=str(self.root),
                        G70_DIAG_TEST_PATH=f'{self.tools}:/usr/bin:/bin',
                        G70_TEST_CALLS=str(self.work / 'insmod-calls'),
                        G70_TEST_MESSAGES=str(self.work / 'messages'),
                        G70_TEST_DENIED=str(self.work / 'denied'))

    def put(self, path, value):
        path = self.root / path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(value if isinstance(value, bytes) else value.encode())

    def stub(self, name, body):
        path = self.tools / name
        path.write_text('#!/bin/sh\n' + body)
        path.chmod(0o755)

    def calls(self):
        path = self.work / 'insmod-calls'
        return path.read_text().splitlines() if path.exists() else []
