#!/system/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
R=${G70_DIAG_TEST_ROOT:-}
P="$R/data/nemesis/apps/g70.usbwifi.bridge"
[ -d "$P" ] || P="$R/data/nemesis/packages/g70.usbwifi.bridge"
sh "$P/bin/logs.sh"
