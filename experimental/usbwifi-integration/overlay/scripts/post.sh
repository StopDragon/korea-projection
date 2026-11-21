#!/system/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
export PATH=${KP_PERSONAL_TEST_PATH:-/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin}
R=${G70_DIAG_TEST_ROOT:-${KP_PERSONAL_TEST_ROOT:-}}
P=${KP_PERSONAL_APP:-$R/data/nemesis/apps/korea.projection}
[ -d "$P" ] || P=$R/data/nemesis/packages/korea.projection
. "$P/usb/profiles.sh"
KP_PERSONAL_APP=$KP_APP APP=$KP_APP sh "$KP_APP/scripts/post-native.sh" || exit $?
chmod 755 "$KP_APP/usb/g70/bin/ctrl-status" "$KP_APP/usb/g70/bin/ap-capabilities" || exit 1
mkdir -p "$KP_APP/usb/g70/ctrl" || exit 1
chown 0:1010 "$KP_APP/usb/g70/ctrl" && chmod 770 "$KP_APP/usb/g70/ctrl" || exit 1
case "$KP_PROFILE" in
    g70|generic-usb|nx4|ev6)
        mkdir -p "$KP_USB_STATE" || exit 1
        _choice=
        for u in /storage/usb0 /storage/usb1 /storage/usb2; do
            if [ -f "$R$u/KP_G70_BASELINE_DRIVER.txt" ]; then _choice=baseline; break; fi
            [ ! -f "$R$u/KP_G70_RXCHECK_DRIVER.txt" ] || _choice=rxcheck
        done
        if [ -n "$_choice" ]; then echo "$_choice" > "$KP_USB_STATE/driver-profile"
        elif [ ! -f "$KP_USB_STATE/driver-profile" ]; then echo rxcheck > "$KP_USB_STATE/driver-profile"; fi
        for u in /storage/usb0 /storage/usb1 /storage/usb2; do
            [ -f "$R$u/KP_USB_RETRY_DRIVER.txt" ] || continue
            if grep -q -e '^88x2bu ' -e '^8851bu ' "$R/proc/modules" 2>/dev/null; then
                echo 'Retry guard retained: restart in Logs export mode before retry installation.'
            else
                rm -f "$KP_USB_STATE/blocked" "$KP_USB_STATE/load-pending" "$KP_USB_STATE/ap-failed-boots" "$KP_USB_STATE/ap-failed-boot"
                echo 'Explicit USB retry requested. Hardware/ownership checks remain required next boot.'
            fi
        done
        echo 'USB hardware selector prepared. Restart the head unit with the dongle attached.'
        ;;

esac
if [ "$KP_HMG_PROFILE" = ev6 ]; then
    sh "$KP_APP/usb/ev6-mod.sh" install || echo 'EV6 optional helper not applied; see HMG-API and install output.'
fi
exit 0
