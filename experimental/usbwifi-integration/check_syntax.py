#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
from pathlib import Path
import shutil
import subprocess

base=Path(__file__).resolve().parent
files=[p for p in (base/'pkg').rglob('*.sh') if 'source' not in p.relative_to(base/'pkg').parts]
if not files:
    raise SystemExit('Run prepare.py first.')
count=0
for shell in ('bash','dash','ksh'):
    if not shutil.which(shell):
        raise SystemExit('Missing syntax-check shell: '+shell)
    for path in files:
        subprocess.run([shell,'-n',str(path)],check=True)
        count+=1
print(str(count)+' shell syntax checks passed')
