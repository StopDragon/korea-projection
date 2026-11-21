#!/system/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
R=${G70_DIAG_TEST_ROOT:-${KP_PERSONAL_TEST_ROOT:-}}
P=${KP_PERSONAL_APP:-$R/data/nemesis/apps/korea.projection}
[ -d "$P" ] || P=$R/data/nemesis/packages/korea.projection
exec sh "$P/usb/logs.sh"
