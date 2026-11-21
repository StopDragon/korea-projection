#!/system/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
R=${G70_DIAG_TEST_ROOT:-}
P="$R/data/nemesis/apps/korea.projection/usb/g70"
[ -d "$P" ] || P="$R/data/nemesis/packages/korea.projection/usb/g70"
. "$P/bin/common.sh"
state starting
value "$PROC/sys/kernel/random/boot_id" > "$BK/runtime.boot"
idle() { while true; do sleep 30 & wait $!; done; }
blocked() { state "$1"; event "$1"; [ "${G70_BRIDGE_ONCE:-0}" = 1 ] && exit 1; idle; }
trap 'stop_owned_dhcp; projection_routes_off; event service_stopped; exit 0' TERM INT HUP
if [ -f "$BK/maintenance" ]; then
    state maintenance
    [ "${G70_BRIDGE_ONCE:-0}" = 1 ] && exit 0
    idle
fi
kp_cap_usb_scan || blocked usb_identity_or_interface_unsupported
compatible || blocked incompatible_firmware_or_kernel
supported_kp || blocked unsupported_korea_projection_version
[ "$(md5_of "$APP/modules/$G70_KO")" = "$G70_KO_MD5" ] || blocked driver_file_changed
[ ! -f "$BK/blocked" ] || blocked previous_attempt_blocked
[ ! -f "$BK/load-pending" ] || { echo unfinished_load > "$BK/blocked"; blocked unfinished_previous_load; }
for _family in 88x2bu 8851bu; do
    [ "$_family" = "$G70_FAMILY" ] || ! grep -q "^$_family " "$MODS" 2>/dev/null || blocked other_driver_family_loaded_reboot_required
done
if loaded; then
    [ "$(value "$BK/loaded-boot")" = "$(value "$PROC/sys/kernel/random/boot_id"):$G70_KO_MD5" ] || blocked resident_driver_requires_reboot
    [ "$(value "$R/sys/module/$G70_FAMILY/srcversion")" = "$SRCVERSION" ] || blocked other_driver_loaded_reboot_required
else
    echo "$(value "$PROC/sys/kernel/random/boot_id")" > "$BK/load-pending" || blocked cannot_write_load_guard
    sync || blocked cannot_sync_load_guard
    event driver_load_started
    _power_args=
    [ "$G70_FAMILY" != 88x2bu ] || _power_args='rtw_power_mgnt=0 rtw_ips_mode=0 rtw_enusbss=0'
    insmod "$APP/modules/$G70_KO" ifname=rtwlan%d if2name=rtwlan%d \
        rtw_country_code=KR $_power_args \
        rtw_en_napi=0 rtw_en_gro=0 rtw_usbfs_block=1 > "$BK/insmod.txt" 2>&1
    _rc=$?
    if [ "$_rc" != 0 ] || ! loaded; then
        echo "load_failed_rc=$_rc" > "$BK/blocked"; sync
        blocked driver_load_failed
    fi
    echo "$(value "$PROC/sys/kernel/random/boot_id"):$G70_KO_MD5" > "$BK/loaded-boot"
    rm -f "$BK/load-pending"
    event driver_loaded
fi

name_wlan() {
    single_tested_dongle || return 1
    if [ -d "$NET/wlan0" ]; then
        our_wlan || return 1
        echo "$KPC_USB_PORT" > "$BK/selected-usb-port"
        return 0
    fi
    _best=; _highest=-1
    for _net in "$NET"/rtwlan*; do
        [ -d "$_net" ] || continue
        tested_usb_net "$_net" || continue
        _index=; read -r _index < "$_net/ifindex" 2>/dev/null
        case "$_index" in ''|*[!0-9]*) continue ;; esac
        [ "$_index" -le "$_highest" ] || { _highest=$_index; _best=${_net##*/}; }
    done
    [ -n "$_best" ] || return 1
    ip link set "$_best" down >/dev/null 2>&1 && ip link set "$_best" name wlan0 >/dev/null 2>&1 || return 1
    our_wlan || return 1
    echo "$KPC_USB_PORT" > "$BK/selected-usb-port"
    event interface_named_wlan0
}
publish_wifi() {
    our_wlan || return 1
    # Query only this owned interface. A definitive unsupported AP/channel
    # stops here. Missing query data permits an actual hostapd validation,
    # never an automatic AP/screen success assertion.
    _apgen="$(value "$PROC/sys/kernel/random/boot_id"):$(value "$NET/wlan0/ifindex")"
    if [ "$_apgen" != "$(value "$BK/ap-capabilities-generation")" ]; then
        "$APP/bin/ap-capabilities" wlan0 > "$BK/ap-capabilities.txt" 2>/dev/null
        _aprc=$?
        if [ "$_aprc" = 1 ]; then
            echo ap_or_channel149_unsupported > "$BK/blocked"
            sync
            blocked ap_or_channel149_unsupported
        fi
        echo "$_apgen" > "$BK/ap-capabilities-generation"
    fi
    if [ ! -f "$CHIP" ]; then
        if [ ! -d "${CHIP%/*}" ]; then
            mkdir -p "${CHIP%/*}" && chmod 755 "${CHIP%/*}" || return 1
        fi
        if ( set -C; : > "$CHIP" ) 2>/dev/null; then
            chmod 644 "$CHIP" || return 1
            : > "$BK/chip-owned"
            event wifi_marker_created
        fi
    fi
    [ -f "$CHIP" ]
}
_last=
while true; do
    if [ -f "$BK/maintenance" ]; then
        state maintenance_reboot_required
        stop_owned_dhcp
        projection_routes_off
        [ "${G70_BRIDGE_ONCE:-0}" = 1 ] && exit 0
        idle
    fi
    if kp_cap_usb_scan && [ "$KPC_USB_COUNT" = 1 ] && [ "$KPC_FAMILY" != "$G70_FAMILY" ]; then
        stop_owned_dhcp
        projection_routes_off
        blocked adapter_family_changed_reboot_required
    fi
    if name_wlan && publish_wifi; then
        interface_generation
        state wifi_ready
        [ "$_last" = ready ] || event wifi_ready
        _last=ready
        maintain_kp_ap
        ap_health_tick
        projection_routes_tick
    else
        interface_generation
        state waiting_for_dongle
        [ "$_last" = waiting ] || event waiting_for_dongle
        _last=waiting
    fi
    periodic_evidence
    monitor_projection
    [ "${G70_BRIDGE_ONCE:-0}" = 1 ] && exit 0
    sleep 15 & wait $!
done
