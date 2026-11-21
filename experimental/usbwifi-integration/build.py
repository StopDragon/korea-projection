#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Build the opt-in 1.7.4.2 integration from pinned original signed inputs."""
from pathlib import Path
import configparser
import hashlib
import json
import shutil
import stat
import zipfile

BASE = Path(__file__).resolve().parent
VERSION = '1.7.4.2'
PINNED = {
    'usb/g70/modules/8851bu.ko': '10cc0f42f1e3f7b7884d526b92673a1aead52e3e60f1153db4aa734cfbac2006',
    'usb/g70/bin/ap-capabilities': 'c6b5637a4a001c42026a2e8f00da81ff40c743bc2a3716912ba27d010a47384f',
    'usb/g70/modules/88x2bu.ko': 'e83a259541547acafe0899a84f5e36ca15f9def6f1f8c7c88c6227e2d1f8a89d',
    'usb/g70/modules/88x2bu-baseline.ko': '3e78ee38942e08667f68c287f0576ac21855c34cc516710de27cd49fa6137110',
    'usb/ev6/mod/package.zip': '65832f04bca9f016fff237383231cfea94dce51b3b7b22b62bb8cf686c73da9f',
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pack(source, output):
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for path in sorted(source.rglob('*')):
            if not path.is_file() or path.name == '.DS_Store':
                continue
            name = path.relative_to(source).as_posix()
            item = zipfile.ZipInfo(name, (2026, 11, 21, 0, 0, 0))
            executable = path.suffix == '.sh' or path.name in ('busybox', 'ctrl-status', 'ap-capabilities')
            item.external_attr = (stat.S_IFREG | (0o755 if executable else 0o644)) << 16
            item.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(item, path.read_bytes(), compresslevel=9)


EXTERNAL_PINS = {
    'hmgapi/wireless-carplay-aa.zip': 'e6e448b679eff79dc489c41c13b112d73f2a4f966bf72058b88f449068399445',
    'hmgapi/profiles/nx4hev/wireless-carplay-aa.zip': '2e480483d109016cb20a207cff7da438ce8f9e4266008e6f63290ec4d4dba7bf',
    'app/KoreaProjection.apk': '6894d60400e69359747f858a5f82110dd5d5c287c15a5ec437fd5615c20e21b9',
    'bin/busybox': '3d31efecd4d09625a5d04597ad857f3475d35e6d63a3365912a7edd4c60770a5',
}


def verify_corresponding_sources():
    for folder, module in [('driver', '88x2bu.ko'), ('driver-baseline', '88x2bu-baseline.ko'), ('driver8851', '8851bu.ko')]:
        root = BASE/'pkg/usb/g70/source'/folder
        for name in ['COPYING', 'SOURCE.txt', 'config_tcc803x.txt', 'build.sh', 'inner-build.sh']:
            if not (root/name).is_file():
                raise SystemExit('Missing corresponding source/license: '+str(root/name))
        if not list(root.glob('upstream-*.tar.gz')) or not list((root/'patches').glob('*.patch')):
            raise SystemExit('Missing complete upstream source/patches: '+str(root))
        provenance = (root/'SOURCE.txt').read_text()
        if PINNED['usb/g70/modules/'+module] not in provenance:
            raise SystemExit('Driver/source provenance differs: '+folder)
    for name in ['ctrl-status.c', 'ap-capabilities.c', 'CTRL-STATUS-LICENSE.txt', 'MUSL-COPYRIGHT', 'ZIG-LICENSE']:
        if not (BASE/'pkg/usb/g70/source'/name).is_file():
            raise SystemExit('Missing helper source/license: '+name)
    for name in ['LICENSE', 'NOTICE.md', 'DISCLAIMER.md', 'ADDITIONAL-TERMS.md', 'source/ev6-helper/src/hmgapi/mods/aakeep/AaKeep.java']:
        if not (BASE/'pkg/usb/ev6'/name).is_file():
            raise SystemExit('Missing EV6 helper source/notice: '+name)


def build():
    for name, expected in {**PINNED, **EXTERNAL_PINS}.items():
        if not (BASE/'pkg'/name).is_file():
            raise SystemExit('Missing pinned input: '+name+'. Run prepare.py with --base-package and --nx4-package first.')
        if digest(BASE/'pkg'/name) != expected:
            raise SystemExit('Pinned component differs: ' + name)
    verify_corresponding_sources()
    for folder in ('pkg', 'logs-pkg'):
        cfg = configparser.ConfigParser(interpolation=None)
        cfg.read(BASE/folder/'NEMESIS.data')
        if cfg['nemesis']['package-version'] != VERSION:
            raise SystemExit('Version mismatch: ' + folder)
    dist = BASE/'dist'
    usb = dist/'usb'
    (usb/'packages').mkdir(parents=True, exist_ok=True)
    for name in ('README.txt', 'CHANGES-1.7.4.2.txt', 'NEMESIS.data', 'KP_USB_EXPORT.txt', 'THIRD-PARTY.txt'):
        shutil.copyfile(BASE/'usb'/name, usb/name)
    shutil.copyfile(BASE/'ORIGINS.json', BASE/'pkg/ORIGINS.json')
    shutil.copyfile(BASE/'usb/THIRD-PARTY.txt', BASE/'pkg/THIRD-PARTY.txt')
    code_hash = hashlib.sha256()
    for path in sorted((BASE/'pkg').rglob('*')):
        if path.is_file() and path.name != 'CODE_FINGERPRINT':
            code_hash.update(path.relative_to(BASE/'pkg').as_posix().encode()+b'\0')
            code_hash.update(path.read_bytes())
    (BASE/'pkg/CODE_FINGERPRINT').write_text(code_hash.hexdigest()+'\n')
    shutil.copyfile(BASE/'pkg/bin/busybox-LICENSE.txt', usb/'BUSYBOX-LICENSE.txt')
    pack(BASE/'pkg', usb/'packages/korea.projection.zip')
    pack(BASE/'logs-pkg', usb/'packages/korea.projection.usblogs.zip')
    manifest = {
        'version': VERSION, 'distribution': 'private user modification',
        'selection': 'native radio or actual USB ID/class plus kernel/config/stock/export cohort',
        'software_profiles': ['default signed mode 2.4.5', 'NX4HEV signed mode 2.4.6', 'gated EV6 AA helper'],
        'ac_usb_ids': json.loads((BASE/'ORIGINS.json').read_text())['allowed_usb_ids'],
        'experimental_ax_ids': ['0bda:b831', '0bda:b851', '2001:332a', '2c4e:0128', '3625:010b', '7392:e611'],
        'ax_g70_vehicle_verified': False,
        'unknown_kernel_abi': 'diagnostic only',
        'persistent_validation_history': True,
        'automatic_screen_verification': False,
        'vehicle_test_of_integrated_release': False,
        'g70_display_freeze_fix_verified': False,
        'active_usb_backend': 'usb/g70/bin/wifi.sh (common for eligible hardware)',
        'unused_reference_binaries_included': False,
        'pinned_components_sha256': {**PINNED, **EXTERNAL_PINS},
    }
    (usb/'RELEASE.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n')
    sums = []
    for path in sorted(usb.rglob('*')):
        if path.is_file() and path.name != 'SHA256SUMS':
            sums.append(digest(path)+'  '+path.relative_to(usb).as_posix())
    (usb/'SHA256SUMS').write_text('\n'.join(sums)+'\n')
    out = dist/f'KoreaProjection-{VERSION}-Auto-USB.zip'
    pack(usb, out)
    print(out)
    print('sha256='+digest(out))
    return out


if __name__ == '__main__':
    build()
