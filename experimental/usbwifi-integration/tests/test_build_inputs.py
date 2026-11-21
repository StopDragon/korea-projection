# SPDX-License-Identifier: AGPL-3.0-only
from pathlib import Path
import tempfile
import unittest
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent.parent))
import build
import prepare

class BuildInputTests(unittest.TestCase):
    def test_unpinned_base_input_is_rejected_before_staging(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'package.zip';p.write_bytes(b'not an authorized base package')
            with self.assertRaisesRegex(ValueError,'exact official'):
                prepare.prepare(p)

    def test_full_build_requires_all_original_signed_assets(self):
        # Public-input CI deliberately has no user-private NX4 signed mode.
        if (build.BASE/'pkg/hmgapi/profiles/nx4hev/wireless-carplay-aa.zip').exists():
            self.skipTest('Full input reproduction is validated separately with the provided NX4 input.')
        with self.assertRaisesRegex(SystemExit,'Missing pinned input'):
            build.build()
