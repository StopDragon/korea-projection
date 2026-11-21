# SPDX-License-Identifier: AGPL-3.0-only
# G70 bridge common paths and read-only checks. No system file patches here.
export PATH=${G70_DIAG_TEST_PATH:-/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin}
export LD_LIBRARY_PATH=/vendor/lib:/system/lib
umask 077
R=${G70_DIAG_TEST_ROOT:-}
ID=g70.usbwifi.bridge
APP="$R/data/nemesis/apps/$ID"
[ -d "$APP" ] || APP="$R/data/nemesis/packages/$ID"
BK="$R/data/nemesis/backup/$ID"
CHIP="$R/data/hmgapi/public/wifi-chip"
KP="$R/data/nemesis/apps/korea.projection"
[ -d "$KP" ] || KP="$R/data/nemesis/packages/korea.projection"
PROC="$R/proc"
NET="$R/sys/class/net"
MODS="$PROC/modules"
PROGRESS="$R/data/local/tmp/korea-projection-progress.txt"
SRCVERSION=46A9CFB83C8F6E0C09E8AAC
mkdir -p "$BK" 2>/dev/null
value() { if [ -r "$1" ]; then cat "$1" 2>/dev/null; else echo unavailable; fi; }
md5_of() {
    _sum=$(md5 "$1" 2>/dev/null)
    if [ -z "$_sum" ]; then
        for _bb in "$R/system/bin/busybox" "$KP/bin/busybox"; do
            [ -x "$_bb" ] || continue
            _sum=$("$_bb" md5sum "$1" 2>/dev/null)
            [ -n "$_sum" ] && break
        done
    fi
    set -- $_sum
    case "$1" in ''|*[!0-9a-f]*) echo unavailable ;; *)
        if [ "${#1}" = 32 ]; then echo "$1"; else echo unavailable; fi ;;
    esac
}
loaded() { grep -q '^88x2bu ' "$MODS" 2>/dev/null; }
supported_kp() { grep -q '^package-version=1.7.4$' "$KP/NEMESIS.data" 2>/dev/null; }
tested_usb_net() {
    [ -d "$1" ] || return 1
    _m=$(readlink "$1/device/driver/module" 2>/dev/null)
    [ "${_m##*/}" = 88x2bu ] || return 1
    # This driver's SET_NETDEV_DEV points at its USB interface. The modalias
    # checks the tested ID and ff/ff/ff interface, not just a module name.
    case "$(value "$1/device/modalias")" in
        usb:v0BDApB812*icFFiscFFipFF*) return 0 ;; *) return 1 ;;
    esac
}
our_wlan() { tested_usb_net "$NET/wlan0"; }
single_tested_dongle() {
    _count=0
    for _d in "$R"/sys/bus/usb/devices/*; do
        [ "$(value "$_d/idVendor"):$(value "$_d/idProduct")" != 0bda:b812 ] || _count=$((_count+1))
    done
    [ "$_count" = 1 ]
}
compatible() {
    [ "$(getprop ro.build.product 2>/dev/null)" = IKFL.KOR.0000.V039.001.260902 ] &&
    [ "$(getprop ro.board.platform 2>/dev/null)" = tcc803x ] &&
    [ "$(value "$PROC/sys/kernel/osrelease")" = 3.18.24-tcc ] &&
    [ "$(value "$PROC/sys/kernel/modules_disabled")" = 0 ] &&
    [ "$(md5_of "$PROC/config.gz")" = 1fd51a10a44ae9ff77fa9ecc94192026 ] &&
    [ "$(md5_of "$R/system/wifi/bcmdhd.ko")" = 7da276f0d683eecc6c302068331ef274 ]
}
event() {
    _up=unavailable; [ ! -r "$PROC/uptime" ] || read -r _up _unused < "$PROC/uptime"
    echo "$(date +%Y%m%d-%H%M%S) up=$_up $*" >> "$BK/events.txt"
}
state() { echo "$1" > "$BK/state.txt"; }
message() {
    echo "$2"
    am start -n com.nemesis.manager/.DialogActivity -f 0x10000000 \
        --es nemesis_mode "$1" --es nemesis_message "$2" >/dev/null 2>&1
    return 0
}
mounted() {
    [ -r "$PROC/mounts" ] || return 1
    while read -r _device _mount _rest; do [ "$_mount" = "$1" ] && return 0; done < "$PROC/mounts"
    return 1
}
kp_state() {
    _pct=unavailable; _state=unavailable; _boot=
    if [ -r "$PROGRESS" ]; then
        while IFS= read -r _line; do
            case "$_line" in
                pct=*) _v=${_line#pct=}; case "$_v" in ''|*[!0-9]*) ;; *) _pct=$_v ;; esac ;;
                state=*) _v=${_line#state=}; case "$_v" in run|done|reboot|fail) _state=$_v ;; esac ;;
                boot=*) _boot=${_line#boot=} ;;
            esac
        done < "$PROGRESS"
    fi
    echo "kp_progress=$_pct"
    echo "kp_state=$_state"
    if [ -n "$_boot" ] && [ "$_boot" = "$(value "$PROC/sys/kernel/random/boot_id")" ]; then
        echo kp_progress_current_boot=yes
    else
        echo kp_progress_current_boot=no
    fi
}
carplay_ipv4_count() {
    _cp=0
    for _table in "$PROC/net/tcp" "$PROC/net/tcp6"; do
        [ -r "$_table" ] || continue
        while read -r _slot _local _remote _tcp_state _rest; do
            [ "$_tcp_state" = 01 ] || continue
            case "$_local" in *012BA8C0:1B58) _cp=$((_cp+1)) ;; esac
        done < "$_table"
    done
    echo "$_cp"
}
status_text() {
    echo bridge_version=0.4.1
    echo "boot_uptime_seconds=$(up_seconds || echo unavailable)"
    echo "bridge_state=$(value "$BK/state.txt")"
    echo "driver_loaded=$(loaded && echo yes || echo no)"
    echo "driver_srcversion=$(value "$R/sys/module/88x2bu/srcversion")"
    echo "wlan0_ours=$(our_wlan && echo yes || echo no)"
    echo "wifi_marker=$([ -f "$CHIP" ] && echo yes || echo no)"
    echo "wireless_mod=$([ -f "$R/data/hmgapi/mods/wireless-carplay-aa/mod.json" ] && echo yes || echo no)"
    echo "wireless_mod_disabled=$([ -f "$R/data/hmgapi/mods/wireless-carplay-aa/.disabled" ] && echo yes || echo no)"
    echo "bridge_property=$(getprop persist.sys.iap2.wifi 2>/dev/null)"
    echo "kp_ap_signal=$(getprop sys.kp.aa_ap 2>/dev/null)"
    kp_state
    ap_diagnostics
    echo "carplay_port7000_ipv4_sessions=$(carplay_ipv4_count)"
    echo "carplay_port7000_ipv6_sessions=$(carplay_ipv6_count)"
    for _usb in "$R"/sys/bus/usb/devices/*; do
        [ -r "$_usb/idVendor" ] && [ -r "$_usb/idProduct" ] || continue
        _v=; _p=; read -r _v < "$_usb/idVendor"; read -r _p < "$_usb/idProduct"
        [ "$_v:$_p" = 0bda:b812 ] || continue
        _name=${_usb##*/}
        for _interface in "$R/sys/bus/usb/devices/$_name":*; do
            [ -d "$_interface" ] || continue
            _owner=$(readlink "$_interface/driver" 2>/dev/null)
            echo "usb_interface=${_interface##*/} owner=${_owner##*/}"
        done
    done
    if [ -x "$APP/bin/ctrl-status" ] && [ -d "$APP/ctrl" ]; then
        "$APP/bin/ctrl-status" "$R/data/misc/wifi/hostapd/wlan0" "$APP/ctrl" 2>/dev/null
    fi
    return 0
}
prepare_ctrl() {
    mkdir -p "$APP/ctrl" && chown 1000:1010 "$APP/ctrl" && chmod 770 "$APP/ctrl"
    chmod 755 "$APP/bin/ctrl-status" 2>/dev/null
}
. "$APP/bin/dhcp-port.sh"
. "$APP/bin/ap-support.sh"
. "$APP/bin/projection-routes.sh"
. "$APP/bin/evidence.sh"
. "$APP/bin/projection-evidence.sh"
