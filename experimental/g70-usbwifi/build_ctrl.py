#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Optional rebuild of the MIT-0 ARMv7 STATUS helper using Zig 0.13.0."""
from pathlib import Path
import os
import shutil
import subprocess

BASE = Path(__file__).resolve().parent

if __name__ == '__main__':
    compiler = os.environ.get('G70_ZIG') or shutil.which('zig')
    if not compiler:
        raise SystemExit('Set G70_ZIG to a Zig 0.13.0 executable.')
    if subprocess.check_output([compiler,'version'],text=True).strip() != '0.13.0':
        raise SystemExit('This helper build is pinned to Zig 0.13.0.')
    env = dict(os.environ, ZIG_GLOBAL_CACHE_DIR=str(BASE/'.build-tools/cache'))
    subprocess.run([compiler,'cc','-target','arm-linux-musleabi','-mcpu=cortex_a7',
                    '-static','-Os','-s','-Wall','-Wextra','-Werror',
                    str(BASE/'pkg/source/ctrl-status.c'),'-o',str(BASE/'pkg/bin/ctrl-status')],
                   env=env,check=True)
    (BASE/'pkg/bin/ctrl-status').chmod(0o755)
