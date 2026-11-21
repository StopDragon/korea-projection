#!/system/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
export PATH=${KP_PERSONAL_TEST_PATH:-/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin}
_root=${G70_DIAG_TEST_ROOT:-${KP_PERSONAL_TEST_ROOT:-}}
_app=${KP_PERSONAL_APP:-$_root/data/nemesis/apps/korea.projection}
[ -d "$_app" ] || _app=$_root/data/nemesis/packages/korea.projection
. "$_app/usb/profiles.sh"
APP=$KP_APP
. "$KP_APP/bin/status-native.sh"
