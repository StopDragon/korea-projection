#!/system/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
R=${G70_DIAG_TEST_ROOT:-}
P="$R/data/nemesis/apps/g70.usbwifi.bridge"
[ -d "$P" ] || P="$R/data/nemesis/packages/g70.usbwifi.bridge"
. "$P/bin/common.sh"
stop_owned_dhcp
projection_routes_off
STAGE="$R/data/local/tmp/nemesis/stage/g70.usbwifi.bridge"
_parent=$(cat "$PROC/$PPID/cmdline" 2>/dev/null)
case "$_parent" in *uninstall*) ;; *)
    if [ -f "$STAGE/NEMESIS.data" ] && grep -q '^id=g70.usbwifi.bridge$' "$STAGE/NEMESIS.data"; then
        echo "Updating: bridge state and owned Wi-Fi marker retained."
        exit 0
    fi ;;
esac
if [ -f "$BK/chip-owned" ] && [ "$(md5_of "$CHIP")" = d41d8cd98f00b204e9800998ecf8427e ]; then
    rm -f "$CHIP"
fi
rm -rf "$BK"
echo "Bridge removed. Restart the head unit to unload the driver. Korea Projection owns its wireless mode."
exit 0
