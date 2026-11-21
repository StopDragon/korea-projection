#!/system/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# One-shot hardware inspection. Default output is beside this script on USB.
# The installed single-port launcher supplies its own diagnostic output folder.
# Does not load drivers, change settings, create a Wi-Fi marker, or restart anything.
export PATH=${G70_DIAG_TEST_PATH:-/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin}
export LD_LIBRARY_PATH=/vendor/lib:/system/lib
g70_root=${G70_DIAG_TEST_ROOT:-}
case "$0" in */*) cd "${0%/*}" || exit 1 ;; esac
g70_out=${G70_DIAG_OUTPUT_DIR:-"$PWD/G70_WIFI_CHECK_$(date +%Y%m%d-%H%M%S)_$$"}
mkdir "$g70_out" || exit 1

g70_value() {
    if [ -r "$g70_root$2" ]; then
        echo "$1=$(cat "$g70_root$2" 2>/dev/null)"
    else
        echo "$1=unavailable"
    fi
}
g70_present() {
    if [ -e "$g70_root$2" ]; then echo "$1=yes"; else echo "$1=no"; fi
}
g70_bb=
for g70_candidate in /system/bin/busybox /data/nemesis/apps/korea.projection/bin/busybox /data/nemesis/packages/korea.projection/bin/busybox; do
    if [ -x "$g70_root$g70_candidate" ]; then
        g70_bb="$g70_root$g70_candidate"
        break
    fi
done
g70_md5() {
    if [ ! -r "$g70_root$1" ]; then echo "$1 md5=unavailable"; return; fi
    g70_sum=$(md5 "$g70_root$1" 2>/dev/null)
    if [ -z "$g70_sum" ] && [ -n "$g70_bb" ]; then
        g70_sum=$("$g70_bb" md5sum "$g70_root$1" 2>/dev/null)
    fi
    set -- $g70_sum
    echo "md5=${1:-unavailable}"
}

echo "Collecting hardware information. Wait for the completion message."
{
    echo "G70 USB Wi-Fi inspection v1.1"
    echo "No drivers, vehicle settings or system files are changed."
    echo ""
    echo "[head unit]"
    for g70_prop in ro.build.product ro.board.platform ro.product.board ro.hardware ro.build.version.release ro.mobis.targetdir ro.mobis.onebindir ro.product.opt.stepofspec wifi.interface wlan.driver.status sys.kp.aa_ap; do
        echo "$g70_prop=$(getprop "$g70_prop" 2>/dev/null)"
    done
    g70_value kernel.release /proc/sys/kernel/osrelease
    g70_value kernel.version /proc/version
    g70_value modules.disabled /proc/sys/kernel/modules_disabled
    g70_value modules.sig_enforce /sys/module/module/parameters/sig_enforce
    g70_value kptr_restrict /proc/sys/kernel/kptr_restrict
    echo ""
    echo "[loaded modules: names, size and reference count only]"
    if [ -r "$g70_root/proc/modules" ]; then
        while read -r g70_mod g70_size g70_refs g70_rest; do
            echo "$g70_mod size=$g70_size refs=$g70_refs"
        done < "$g70_root/proc/modules"
    fi
    echo ""
    echo "[network interface names: no addresses]"
    for g70_net in "$g70_root"/sys/class/net/*; do
        [ -d "$g70_net" ] || continue
        echo "interface=${g70_net##*/}"
    done
    echo ""
    echo "[presence of existing state files]"
    g70_present hmgapi.wifi_chip /data/hmgapi/public/wifi-chip
    g70_present kp.wifi_nopart /data/nemesis/backup/korea.projection/wifi.nopart
    g70_present kp.wifi_nochip /data/nemesis/backup/korea.projection/wifi.nochip
    g70_present wireless_mod /data/hmgapi/mods/wireless-carplay-aa/mod.json
    g70_present hostapd /system/bin/hostapd
    g70_present dnsmasq /system/bin/dnsmasq
    g70_present softap_config /data/misc/wifi/softap.conf
    g70_value kp.saved_module_version /data/nemesis/backup/korea.projection/wifi.modver
    echo ""
    echo "[stock file fingerprints]"
    for g70_file in /system/wifi/bcmdhd.ko /system/app/HKMC_GPM.odex /system/framework/services.odex; do
        echo "file=$g70_file"
        g70_md5 "$g70_file"
    done
    echo ""
    echo "[USB: IDs, classes and speed only; no names or serial numbers]"
    for g70_dev in "$g70_root"/sys/bus/usb/devices/*; do
        [ -r "$g70_dev/idVendor" ] && [ -r "$g70_dev/idProduct" ] || continue
        echo "device=${g70_dev##*/}"
        echo "id=$(cat "$g70_dev/idVendor"):$(cat "$g70_dev/idProduct")"
        for g70_attr in bDeviceClass speed bMaxPower; do
            if [ -r "$g70_dev/$g70_attr" ]; then
                echo "$g70_attr=$(cat "$g70_dev/$g70_attr")"
            fi
        done
    done
} > "$g70_out/report.txt" || exit 1

# Raw USB interface modalias strings can be compared with the driver's compiled
# aliases on the computer, without loading the driver into the car's kernel.
{
    for g70_dev in "$g70_root"/sys/bus/usb/devices/*; do
        [ -r "$g70_dev/modalias" ] || continue
        g70_alias=$(cat "$g70_dev/modalias" 2>/dev/null)
        case "$g70_alias" in usb:*) echo "${g70_dev##*/} $g70_alias" ;; esac
    done
} > "$g70_out/usb-modaliases.txt" || exit 1

# Read the kernel configuration as-is; no tools need to be installed on the car.
if [ -r "$g70_root/proc/config.gz" ]; then
    cat "$g70_root/proc/config.gz" > "$g70_out/kernel-config.gz" || exit 1
fi
# Exported symbol names only: discard kernel addresses, module names and all logs.
{
    if [ -r "$g70_root/proc/kallsyms" ]; then
        while read -r g70_addr g70_type g70_symbol g70_rest; do
            case "$g70_symbol" in __ksymtab_*) echo "${g70_symbol#__ksymtab_}" ;; esac
        done < "$g70_root/proc/kallsyms"
    fi
} > "$g70_out/kernel-exports.txt" || exit 1
echo "Collection finished. See this G70_WIFI_CHECK folder." >> "$g70_out/report.txt"
sync || exit 1
: > "$g70_out/COMPLETE" || exit 1
sync || { rm -f "$g70_out/COMPLETE"; exit 1; }
echo "G70 hardware inspection completed: $g70_out"
exit 0
