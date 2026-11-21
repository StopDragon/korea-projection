# SPDX-License-Identifier: AGPL-3.0-only
# Hardware selection is independent of product names. HMG helpers remain specific.
KP_ROOT=${G70_DIAG_TEST_ROOT:-${KP_PERSONAL_TEST_ROOT:-}}
KP_APP=${KP_PERSONAL_APP:-$KP_ROOT/data/nemesis/apps/korea.projection}
[ -d "$KP_APP" ] || KP_APP=$KP_ROOT/data/nemesis/packages/korea.projection
KP_PRODUCT=$(getprop ro.build.product 2>/dev/null)
. "$KP_APP/usb/compat/select.sh"
kp_cap_detect
KP_PROFILE=$KPC_ROUTE
KP_PROFILE_REASON=$KPC_REASON
KP_DRIVER_FAMILY=${KPC_FAMILY:-88x2bu}
KP_HMG_PROFILE=default
# These names only select the signed software mode/helper and retain old state paths.
# Every USB branch above must have passed the same hardware checks first.
if [ "$KP_PROFILE" = generic-usb ]; then
    case "$KP_PRODUCT" in
        IKFL.KOR.0000.V039.001.260902) KP_PROFILE=g70 ;;
        NX4HEV.KOR.*.260902) KP_PROFILE=nx4; KP_HMG_PROFILE=nx4 ;;
        CVEV.KOR.0000.V039.001.260902) KP_PROFILE=ev6; KP_HMG_PROFILE=ev6 ;;
    esac
fi
KP_USB_STATE=$KP_ROOT/data/nemesis/backup/korea.projection/usb-$KP_PROFILE
