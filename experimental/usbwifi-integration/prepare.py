#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Assemble ignored pkg/ from pinned release inputs and the reviewed source overlay."""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import shutil
import subprocess
import zipfile

BASE = Path(__file__).resolve().parent
BASE_SHA256 = 'd33dae33b27cad30d82b47dda557732780b4813c5d0815ed6f22b21c4d0a4315'
NX4_SHA256 = '81b6c37aac3fba261be4576c01be6c286363b5aa2c5669d1e82b2b3427af435b'
NX4_MODE_SHA256 = '2e480483d109016cb20a207cff7da438ce8f9e4266008e6f63290ec4d4dba7bf'


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def prepare(base_package, nx4_package=None):
    if digest(base_package) != BASE_SHA256:
        raise ValueError('Expected the exact official Korea Projection 1.7.4 package ZIP.')
    if nx4_package is not None and digest(nx4_package) != NX4_SHA256:
        raise ValueError('NX4 input differs from the user-tested 1.7.4.1 input.')
    stage = BASE/'pkg.preparing'
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir()
    try:
        with zipfile.ZipFile(base_package) as z:
            for entry in z.infolist():
                name = PurePosixPath(entry.filename)
                if name.is_absolute() or '..' in name.parts or '\\' in entry.filename:
                    raise ValueError('Unsafe input archive entry.')
                if entry.is_dir():
                    continue
                path = stage.joinpath(*name.parts)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(z.read(entry))
        for target, original in [
            ('svc/core-native.sh', 'svc/hotspot.sh'),
            ('svc/core-g70.sh', 'svc/hotspot.sh'),
            ('scripts/post-native.sh', 'scripts/post.sh'),
            ('scripts/preun-native.sh', 'scripts/preun.sh'),
            ('bin/status-native.sh', 'bin/status.sh'),
        ]:
            shutil.copyfile(stage/original, stage/target)
        subprocess.run(['patch', '-p1', '--batch', '--forward', '-i', str(BASE/'runtime.patch')],
                       cwd=stage, check=True, capture_output=True, text=True)
        shutil.copytree(BASE/'overlay', stage, dirs_exist_ok=True)
        if nx4_package is not None:
            with zipfile.ZipFile(nx4_package) as z:
                mode = z.read('hmgapi/wireless-carplay-aa.zip')
            if hashlib.sha256(mode).hexdigest() != NX4_MODE_SHA256:
                raise ValueError('NX4 signed mode checksum differs.')
            target = stage/'hmgapi/profiles/nx4hev/wireless-carplay-aa.zip'
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(mode)
        # Original APK/BusyBox/signed modes are build inputs, never a new signature.
        for path in stage.rglob('*'):
            if path.is_file() and (path.suffix == '.sh' or path.name in ('busybox', 'ctrl-status', 'ap-capabilities')):
                path.chmod(0o755)
        if (BASE/'pkg').exists():
            shutil.rmtree(BASE/'pkg')
        stage.rename(BASE/'pkg')
    except BaseException:
        if stage.exists():
            shutil.rmtree(stage)
        raise
    return BASE/'pkg'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-package', required=True, type=Path)
    parser.add_argument('--nx4-package', type=Path,
                        help='Required to build the full installation bundle; optional for host tests.')
    args = parser.parse_args()
    print(prepare(args.base_package, args.nx4_package))
