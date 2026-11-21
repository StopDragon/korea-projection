#!/system/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Read-only classification; stdout contains fixed reasons/counts, no secrets.
export PATH=${KP_PERSONAL_TEST_PATH:-/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin}
KP_ROOT=${KP_ROOT:-${G70_DIAG_TEST_ROOT:-${KP_PERSONAL_TEST_ROOT:-}}}
KP_APP=${KP_PERSONAL_APP:-$KP_ROOT/data/nemesis/apps/korea.projection}
[ -d "$KP_APP" ] || KP_APP=$KP_ROOT/data/nemesis/packages/korea.projection
. "$KP_APP/usb/compat/select.sh"
kp_cap_detect
kp_cap_print
