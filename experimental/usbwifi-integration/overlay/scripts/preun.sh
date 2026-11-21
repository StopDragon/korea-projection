#!/system/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
export PATH=${KP_PERSONAL_TEST_PATH:-/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin}
_root=${G70_DIAG_TEST_ROOT:-${KP_PERSONAL_TEST_ROOT:-}}
_app=${KP_PERSONAL_APP:-$_root/data/nemesis/apps/korea.projection}
[ -d "$_app" ] || _app=$_root/data/nemesis/packages/korea.projection
. "$_app/usb/profiles.sh"
_updating=0
case "$(cat "$_root/proc/$PPID/cmdline" 2>/dev/null)" in
    *uninstall*) ;;
    *) grep -q '^id=korea\.projection$' "$_root/data/local/tmp/nemesis/stage/korea.projection/NEMESIS.data" 2>/dev/null && _updating=1 ;;
esac
if [ -f "$_root/data/nemesis/backup/korea.projection/usb-ev6/helper-owned" ] && [ "$_updating" = 0 ]; then
    sh "$KP_APP/usb/ev6-mod.sh" remove || echo 'EV6 helper removal needs review in HMG-API.'
fi
_usb_only=1; [ "$KP_PROFILE" != native ] || _usb_only=0
# exec preserves the NEMESIS parent PID for the original upgrade/uninstall check.
KP_PERSONAL_USB_ONLY=$_usb_only KP_PERSONAL_APP=$KP_APP APP=$KP_APP exec sh "$KP_APP/scripts/preun-native.sh"
