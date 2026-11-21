#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Package the optional G70 experiment; never modifies the default KP bundle."""
from pathlib import Path
import configparser
import hashlib
import shutil
import zipfile

BASE = Path(__file__).resolve().parent
DRIVER_SHA256 = '3e78ee38942e08667f68c287f0576ac21855c34cc516710de27cd49fa6137110'


def build():
    pkg = BASE / 'pkg'
    if hashlib.sha256((pkg/'modules/88x2bu.ko').read_bytes()).hexdigest() != DRIVER_SHA256:
        raise SystemExit('Driver checksum differs from the vehicle-tested build.')
    for required in ('COPYING', 'source/driver/COPYING', 'source/driver/SOURCE.txt',
                     'source/ctrl-status.c', 'source/CTRL-STATUS-LICENSE.txt',
                     'source/MUSL-COPYRIGHT', 'source/ZIG-LICENSE'):
        if not (pkg/required).is_file():
            raise SystemExit('Missing corresponding source/license: ' + required)
    descriptor = configparser.ConfigParser(interpolation=None)
    descriptor.read(pkg/'NEMESIS.data')
    version = descriptor['nemesis']['package-version']
    logs_descriptor = configparser.ConfigParser(interpolation=None)
    logs_descriptor.read(BASE/'logs-pkg/NEMESIS.data')
    if logs_descriptor['nemesis']['package-version'] != version:
        raise SystemExit('Bridge and Logs versions must match.')
    usb = BASE/'dist/usb'
    (usb/'packages').mkdir(parents=True, exist_ok=True)
    for name in ('NEMESIS.data','G70_BRIDGE_EXPORT.txt','README.txt'):
        shutil.copyfile(BASE/'usb'/name, usb/name)
    shutil.copyfile(BASE/'NOTICE.txt', pkg/'NOTICE.txt')
    shutil.copyfile(BASE/'NOTICE.txt', usb/'NOTICE.txt')
    for folder, name in (('pkg','g70.usbwifi.bridge.zip'), ('logs-pkg','g70.usbwifi.logs.zip')):
        with zipfile.ZipFile(usb/'packages'/name,'w',zipfile.ZIP_DEFLATED) as archive:
            for path in sorted((BASE/folder).rglob('*')):
                if path.is_file() and path.name != '.DS_Store':
                    archive.write(path, str(path.relative_to(BASE/folder)))
    output = BASE/'dist'/f'G70-A3000mini-CarPlay-bridge-USB-v{version}.zip'
    with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as archive:
        for name in ('NEMESIS.data','G70_BRIDGE_EXPORT.txt','README.txt','NOTICE.txt',
                     'packages/g70.usbwifi.bridge.zip','packages/g70.usbwifi.logs.zip'):
            archive.write(usb/name,name)
    print(output)
    print('sha256=' + hashlib.sha256(output.read_bytes()).hexdigest())
    return output


if __name__ == '__main__':
    build()
