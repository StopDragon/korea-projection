#!/system/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
export PATH=${G70_DIAG_TEST_PATH:-/data/nemesis/bin:/system/bin:/system/xbin:/sbin:/vendor/bin}
R=${G70_DIAG_TEST_ROOT:-}
[ "$(getprop ro.build.product)" = IKFL.KOR.0000.V039.001.260902 ] || { echo "This build requires the checked G70 260902 firmware."; exit 1; }
for _p in "$R/data/nemesis/apps/korea.projection" "$R/data/nemesis/packages/korea.projection"; do
    if [ -f "$_p/NEMESIS.data" ] && grep -q '^package-version=1.7.4$' "$_p/NEMESIS.data"; then exit 0; fi
done
echo "Korea Projection 1.7.4 is required."
exit 1
