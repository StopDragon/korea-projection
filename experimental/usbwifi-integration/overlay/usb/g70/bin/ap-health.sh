# SPDX-License-Identifier: AGPL-3.0-only
# Bounded AP validation, separate from USB binding and projection/video success.
ap_health_tick() {
    our_wlan || { AP_WAIT_AT=; return 0; }
    _health=$("$APP/bin/ctrl-status" "$R/data/misc/wifi/hostapd/wlan0" "$APP/ctrl" 2>/dev/null)
    case "$_health" in *ctrl.state=ENABLED*)
        echo "$(boot_id):$G70_KO_MD5" > "$BK/ap-observed"
        echo 0 > "$BK/ap-failed-boots"
        AP_WAIT_AT=
        return 0 ;;
    esac
    [ -s "$APCONF" ] && [ "$(getprop persist.sys.iap2.wifi 2>/dev/null)" = t ] &&
        [ -s "$R/data/hmgapi/mods/wireless-carplay-aa/mod.json" ] &&
        [ ! -f "$R/data/hmgapi/mods/wireless-carplay-aa/.disabled" ] || return 0
    # HMG installation/reboot requests are not radio failures.
    _progress=$(kp_state)
    case "$_progress" in *kp_progress_current_boot=yes*)
        case "$_progress" in *kp_state=run*|*kp_state=reboot*|*kp_state=fail*) AP_WAIT_AT=; return 0 ;; esac ;;
    esac
    _now=$(up_seconds) || return 0
    [ -n "$AP_WAIT_AT" ] || AP_WAIT_AT=$_now
    [ "$((_now-AP_WAIT_AT))" -ge 300 ] || return 0
    if [ "$(value "$BK/ap-failed-boot")" != "$(boot_id)" ]; then
        _n=$(value "$BK/ap-failed-boots")
        case "$_n" in ''|*[!0-9]*) _n=0 ;; esac
        [ "${#_n}" -le 2 ] || _n=99
        echo "$((_n+1))" > "$BK/ap-failed-boots"
        boot_id > "$BK/ap-failed-boot"
    fi
    # No AP restart storm. Two later boots can revalidate, then installation
    # must explicitly clear the guard before any additional load attempt.
    if [ "$(value "$BK/ap-failed-boots")" -ge 3 ]; then
        echo repeated_ap_validation_failure > "$BK/blocked"
        sync
    fi
    stop_owned_dhcp
    blocked ap_validation_failed_reboot_required
}
