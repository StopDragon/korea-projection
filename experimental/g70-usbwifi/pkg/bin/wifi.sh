#!/system/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
R=${G70_DIAG_TEST_ROOT:-}
P="$R/data/nemesis/apps/g70.usbwifi.bridge"
[ -d "$P" ] || P="$R/data/nemesis/packages/g70.usbwifi.bridge"
. "$P/bin/common.sh"
idle() { while true; do sleep 30 & wait $!; done; }
blocked() { state "$1"; event "$1"; [ "${G70_BRIDGE_ONCE:-0}" = 1 ] && exit 1; idle; }
trap 'stop_owned_dhcp; projection_routes_off; event service_stopped; exit 0' TERM INT HUP
if [ -f "$BK/maintenance" ]; then
    state maintenance
    [ "${G70_BRIDGE_ONCE:-0}" = 1 ] && exit 0
    idle
fi
compatible || blocked incompatible_firmware_or_kernel
supported_kp || blocked unsupported_korea_projection_version
[ "$(md5_of "$APP/modules/88x2bu.ko")" = 539ea4caef039f9cd0a7dedaa6ff9e20 ] || blocked driver_file_changed
[ ! -f "$BK/blocked" ] || blocked previous_attempt_blocked
[ ! -f "$BK/load-pending" ] || { echo unfinished_load > "$BK/blocked"; blocked unfinished_previous_load; }
if loaded; then
    [ "$(value "$R/sys/module/88x2bu/srcversion")" = "$SRCVERSION" ] || blocked other_driver_loaded_reboot_required
else
    echo "$(value "$PROC/sys/kernel/random/boot_id")" > "$BK/load-pending" || blocked cannot_write_load_guard
    sync || blocked cannot_sync_load_guard
    event driver_load_started
    insmod "$APP/modules/88x2bu.ko" ifname=rtwlan%d if2name=rtwlan%d \
        rtw_country_code=KR rtw_power_mgnt=0 rtw_ips_mode=0 rtw_enusbss=0 \
        rtw_en_napi=0 rtw_en_gro=0 rtw_usbfs_block=1 > "$BK/insmod.txt" 2>&1
    _rc=$?
    if [ "$_rc" != 0 ] || ! loaded; then
        echo "load_failed_rc=$_rc" > "$BK/blocked"; sync
        blocked driver_load_failed
    fi
    rm -f "$BK/load-pending"
    event driver_loaded
fi

name_wlan() {
    single_tested_dongle || return 1
    if [ -d "$NET/wlan0" ]; then our_wlan; return $?; fi
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
    event interface_named_wlan0
}
publish_wifi() {
    our_wlan || return 1
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
    if name_wlan && publish_wifi; then
        interface_generation
        state wifi_ready
        [ "$_last" = ready ] || event wifi_ready
        _last=ready
        maintain_kp_ap
        projection_routes_tick
        # KP's previous no-chip setup thread has already finished on this car.
        # Restart its own service once so its normal checked setup runs again.
        if [ ! -f "$BK/kp-restarted" ] && [ "$(getprop sys.boot_completed 2>/dev/null)" = 1 ]; then
            _fixpid=; _fixboot=
            [ ! -r "$R/data/local/tmp/korea.projection/fix.pid" ] || \
                read -r _fixpid _fixboot < "$R/data/local/tmp/korea.projection/fix.pid"
            _busy=no
            case "$_fixpid" in ''|*[!0-9]*) ;; *)
                if [ "$_fixboot" = "$(value "$PROC/sys/kernel/random/boot_id")" ] && [ -d "$PROC/$_fixpid" ]; then _busy=yes; fi ;;
            esac
            if [ -f "$R/data/hmgapi/mods/wireless-carplay-aa/mod.json" ]; then
                echo not_needed > "$BK/kp-restarted"
            elif [ "$_busy" = yes ]; then
                : # Let KP finish its own checked setup; never interrupt apply.
            else
                echo attempted > "$BK/kp-restarted"
                if nemesis service stop korea.projection/ap && nemesis service start korea.projection/ap; then
                    echo done > "$BK/kp-restarted"; event korea_projection_service_restarted
                else
                    event korea_projection_service_restart_failed
                fi
            fi
        fi
    else
        interface_generation
        state waiting_for_dongle
        [ "$_last" = waiting ] || event waiting_for_dongle
        _last=waiting
    fi
    periodic_evidence
    monitor_projection
    [ "${G70_BRIDGE_ONCE:-0}" = 1 ] && exit 0
    sleep 5 & wait $!
done
