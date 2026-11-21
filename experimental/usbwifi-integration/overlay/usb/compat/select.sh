# SPDX-License-Identifier: AGPL-3.0-only
# Pure inspection. Sourcing/calling this file never changes the vehicle.
# A match permits an EXPERIMENTAL backend; it is not a vehicle success verdict.
kp_cap_read() { [ ! -r "$1" ] || cat "$1" 2>/dev/null; }
kp_cap_hash() {
    _kpc_sum=$(md5 "$1" 2>/dev/null)
    if [ -z "$_kpc_sum" ] && [ -x "$KP_APP/bin/busybox" ]; then
        _kpc_sum=$("$KP_APP/bin/busybox" md5sum "$1" 2>/dev/null)
    fi
    set -- $_kpc_sum
    case "$1" in ''|*[!0-9a-f]*) return 1 ;; esac
    [ "${#1}" = 32 ] || return 1
    echo "$1"
}
kp_cap_props() {
    KPC_ROOT=${KP_ROOT:-}
    KPC_DATA=${KP_COMPAT_DATA:-$KP_APP/usb/compat}
    KPC_PRODUCT=$(getprop ro.build.product 2>/dev/null)
    KPC_PLATFORM=$(getprop ro.board.platform 2>/dev/null)
    KPC_ANDROID=$(getprop ro.build.version.release 2>/dev/null)
}
kp_cap_gen5w() {
    case "$KPC_PRODUCT" in *.KOR.*) ;; *) KPC_REASON=non_korean_firmware; return 1 ;; esac
    [ "$KPC_ANDROID" = 4.4.2 ] || { KPC_REASON=unsupported_android; return 1; }
}
kp_cap_native_available() {
    _kpc_link=$(readlink "$KPC_ROOT/sys/class/net/wlan0/device/driver/module" 2>/dev/null)
    _kpc_driver=$(readlink "$KPC_ROOT/sys/class/net/wlan0/device/driver" 2>/dev/null)
    case "${_kpc_link##*/}:${_kpc_driver##*/}" in
        bcmdhd:*|dhd:*|brcmfmac:*|*:bcmdhd|*:dhd|*:brcmfmac) return 0 ;;
    esac
    for _kpc_sdio in "$KPC_ROOT"/sys/bus/sdio/devices/*; do
        _kpc_link=$(readlink "$_kpc_sdio/driver/module" 2>/dev/null)
        case "${_kpc_link##*/}" in bcmdhd|dhd|brcmfmac) return 0 ;; esac
    done
    return 1
}
kp_cap_ac_id() {
    case "$1" in
        0846:9055|0b05:1841|0b05:184c|0bda:b812|0bda:b82c|13b1:0043|13b1:0045|2001:331c|2001:331e|2001:331f|20f4:808a|2357:0115|2357:012d|2357:012e|2357:0138|7392:b822|7392:c822) return 0 ;;
    esac
    return 1
}
kp_cap_ax_id() {
    case "$1" in
        0bda:b831|0bda:b851|2001:332a|2c4e:0128|3625:010b|7392:e611) return 0 ;;
    esac
    return 1
}
kp_cap_usb_scan() {
    KPC_USB_COUNT=0; KPC_USB_PORT=; KPC_USB_ID=; KPC_USB_DEFER=; KPC_FAMILY=88x2bu
    for _kpc_dev in "$KPC_ROOT"/sys/bus/usb/devices/*; do
        [ -r "$_kpc_dev/idVendor" ] && [ -r "$_kpc_dev/idProduct" ] || continue
        _kpc_id=$(kp_cap_read "$_kpc_dev/idVendor"):$(kp_cap_read "$_kpc_dev/idProduct")
        if kp_cap_ac_id "$_kpc_id" || kp_cap_ax_id "$_kpc_id"; then
            if kp_cap_ax_id "$_kpc_id"; then KPC_FAMILY=8851bu; else KPC_FAMILY=88x2bu; fi
            KPC_USB_COUNT=$((KPC_USB_COUNT+1)); KPC_USB_ID=$_kpc_id; KPC_USB_PORT=${_kpc_dev##*/}
            _kpc_class_ok=0
            for _kpc_intf in "$_kpc_dev":*; do
                _kpc_class=$(kp_cap_read "$_kpc_intf/bInterfaceClass"):$(kp_cap_read "$_kpc_intf/bInterfaceSubClass"):$(kp_cap_read "$_kpc_intf/bInterfaceProtocol")
                [ "$_kpc_class" != ff:ff:ff ] || _kpc_class_ok=1
            done
            [ "$_kpc_class_ok" = 1 ] || KPC_USB_DEFER=usb_interface_mismatch
        else
            case "$_kpc_id" in
                0bda:b832|056e:4027|056e:4028|2357:0142|0411:03ed) KPC_USB_DEFER=usb_id_not_in_compiled_driver ;;
                0bda:1a2b|0bda:1a2c) KPC_USB_DEFER=usb_cdrom_mode ;;
            esac
        fi
    done
    [ "$KPC_USB_COUNT" -le 1 ] || KPC_USB_DEFER=multiple_supported_adapters
    [ -z "$KPC_USB_DEFER" ]
}
kp_cap_abi_matches() {
    kp_cap_props
    kp_cap_gen5w || return 1
    [ "$KPC_PLATFORM" = tcc803x ] || { KPC_REASON=platform_cohort_unknown; return 1; }
    [ "$(kp_cap_read "$KPC_ROOT/proc/sys/kernel/osrelease")" = 3.18.24-tcc ] || { KPC_REASON=kernel_release_mismatch; return 1; }
    [ "$(kp_cap_read "$KPC_ROOT/proc/sys/kernel/modules_disabled")" = 0 ] || { KPC_REASON=module_loading_disabled_or_unknown; return 1; }
    [ "$(kp_cap_hash "$KPC_ROOT/proc/config.gz")" = 1fd51a10a44ae9ff77fa9ecc94192026 ] || { KPC_REASON=kernel_config_not_in_cohort; return 1; }
    [ "$(kp_cap_hash "$KPC_ROOT/system/wifi/bcmdhd.ko")" = 7da276f0d683eecc6c302068331ef274 ] || { KPC_REASON=stock_module_not_in_cohort; return 1; }
    [ "$(kp_cap_hash "$KP_APP/usb/g70/modules/88x2bu.ko")" = 36f26af089959fa547b7cc30aff445b9 ] || { KPC_REASON=bundled_driver_changed; return 1; }
    _kpc_symbols=$KPC_DATA/required-symbols.txt
    if [ "${KPC_FAMILY:-88x2bu}" = 8851bu ]; then
        [ "$(kp_cap_hash "$KP_APP/usb/g70/modules/8851bu.ko")" = 240bd8f68869d02aed7cfbd2ff76c805 ] || { KPC_REASON=ax_bundled_driver_changed; return 1; }
        _kpc_symbols=$KPC_DATA/required-symbols-8851bu.txt
    fi
    # Missing export information is inconclusive: it must never mean success.
    [ -s "$_kpc_symbols" ] && [ -r "$KPC_ROOT/proc/kallsyms" ] || { KPC_REASON=kernel_exports_unavailable; return 1; }
    _kpc_awk="awk"
    command -v awk >/dev/null 2>&1 || _kpc_awk="$KP_APP/bin/busybox awk"
    KPC_MISSING_SYMBOLS=$($_kpc_awk '
        NR==FNR { required[$1]=1; n++; next }
        $3 ~ /^__ksymtab_/ { s=$3; sub(/^__ksymtab_/, "", s); delete required[s] }
        END { left=0; for(s in required) left++; if(n==0) left=1; print left }
        ' "$_kpc_symbols" "$KPC_ROOT/proc/kallsyms" 2>/dev/null)
    [ "$KPC_MISSING_SYMBOLS" = 0 ] || { KPC_REASON=required_kernel_exports_missing; return 1; }
    KPC_COHORT=tcc803x-kor-config1-stock1-${KPC_FAMILY:-88x2bu}-v2
    KPC_REASON=matching_fingerprints_not_vehicle_verified
    return 0
}
kp_cap_detect() {
    KPC_ROUTE=probe-only; KPC_REASON=not_evaluated; KPC_COHORT=
    KPC_USB_COUNT=0; KPC_USB_PORT=; KPC_USB_ID=; KPC_USB_DEFER=; KPC_FAMILY=88x2bu; KPC_MISSING_SYMBOLS=
    kp_cap_props
    kp_cap_gen5w || return 0
    if kp_cap_native_available; then KPC_ROUTE=native; KPC_REASON=existing_native_radio; return 0; fi
    for _kpc_dir in "$KPC_ROOT/data/nemesis/apps" "$KPC_ROOT/data/nemesis/packages"; do
        for _kpc_pkg in g70.usbwifi.bridge g70.wifi.probe jmk-wifi jmk.usbwifi usbwifi.hotspot stock.hotspot wireless.projection.usbwifi; do
            if [ -f "$_kpc_dir/$_kpc_pkg/NEMESIS.data" ]; then KPC_REASON=conflicting_radio_package; return 0; fi
        done
    done
    kp_cap_usb_scan || { KPC_REASON=$KPC_USB_DEFER; return 0; }
    # Leave a foreign USB/native wlan0 untouched. The existing backend still
    # validates the selected USB interface and resident module before use.
    if [ -d "$KPC_ROOT/sys/class/net/wlan0" ]; then
        _kpc_link=$(readlink "$KPC_ROOT/sys/class/net/wlan0/device/driver/module" 2>/dev/null)
        [ "${_kpc_link##*/}" = "$KPC_FAMILY" ] || { KPC_REASON=unidentified_wlan0_owner; return 0; }
        [ "$(kp_cap_read "$KPC_ROOT/sys/module/$KPC_FAMILY/srcversion")" = "$( [ "$KPC_FAMILY" = 8851bu ] && echo 533BB7E5866E52F63B9ACCB || echo 46A9CFB83C8F6E0C09E8AAC)" ] || { KPC_REASON=foreign_resident_driver; return 0; }
    fi
    kp_cap_abi_matches || return 0
    KPC_ROUTE=generic-usb
}
kp_cap_profile_fallback() {
    kp_cap_detect
    KP_PROFILE=$KPC_ROUTE
    KP_PROFILE_REASON=$KPC_REASON
}
kp_cap_print() {
    echo "compat_route=$KPC_ROUTE"
    echo "compat_reason=$KPC_REASON"
    echo "compat_cohort=$KPC_COHORT"
    echo "compatible_usb_count=$KPC_USB_COUNT"
    echo "selected_driver=${KPC_FAMILY:-unknown}"
    echo "kernel_missing_exports=$KPC_MISSING_SYMBOLS"
    echo 'vehicle_validation=not_performed'
    echo 'hmg_map_validation=still_required'
}
