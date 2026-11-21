#!/system/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
R=${G70_DIAG_TEST_ROOT:-}
P="$R/data/nemesis/apps/g70.usbwifi.bridge"
[ -d "$P" ] || P="$R/data/nemesis/packages/g70.usbwifi.bridge"
. "$P/bin/common.sh"
chmod 700 "$BK"
prepare_ctrl || exit 1
echo "Bridge installed. Replace USB stick with A3000mini and wait for Korea Projection setup."
exit 0
