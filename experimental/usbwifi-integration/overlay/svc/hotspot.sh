#!/system/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
export PATH=${KP_PERSONAL_TEST_PATH:-/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin}
_kp_root=${G70_DIAG_TEST_ROOT:-${KP_PERSONAL_TEST_ROOT:-}}
_kp_app=${KP_PERSONAL_APP:-$_kp_root/data/nemesis/apps/korea.projection}
[ -d "$_kp_app" ] || _kp_app=$_kp_root/data/nemesis/packages/korea.projection
. "$_kp_app/usb/profiles.sh"
APP=$KP_APP
case "$KP_PROFILE" in
    g70|generic-usb|nx4|ev6) _kp_core=$APP/svc/core-g70.sh ;;
    *) _kp_core=$APP/svc/core-native.sh ;;
esac
kp_select_software_mode() {
    if [ "$KP_HMG_PROFILE" = nx4 ]; then
        KP_MODE_ZIP=$APP/hmgapi/profiles/nx4hev/wireless-carplay-aa.zip
        MOD_MD5=e1e8cf9df6ac659586309cf305e56ab3
        MOD_VER=2.4.6
        KP_HT_CAPS='[SHORT-GI-20]'
    fi
}
if [ "$HOTSPOT_LIB" = 1 ]; then
    . "$_kp_core"
    kp_select_software_mode
elif [ "$1" = --core ]; then
    HOTSPOT_LIB=1
    . "$_kp_core"
    kp_select_software_mode
    main
else
    exec sh "$APP/svc/personal.sh"
fi
