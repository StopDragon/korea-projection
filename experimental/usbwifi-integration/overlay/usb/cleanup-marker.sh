#!/system/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Called only after the original true-uninstall path removed/handled its modes.
R=${G70_DIAG_TEST_ROOT:-${KP_PERSONAL_TEST_ROOT:-}}
B=$R/data/nemesis/backup/korea.projection
owned=0
for p in g70 generic-ac generic-usb nx4 ev6; do [ ! -f "$B/usb-$p/chip-owned" ] || owned=1; done
[ ! -f "$B/usb.chip.ours" ] || owned=1
C=$R/data/hmgapi/public/wifi-chip
if [ "$owned" = 1 ] && [ -f "$C" ] && [ ! -s "$C" ]; then rm -f "$C"; fi
exit 0
