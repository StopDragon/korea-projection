#!/system/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# One NEMESIS service. G70's proven radio/DHCP worker is internal to KP.
export PATH=${KP_PERSONAL_TEST_PATH:-/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin}
_root=${G70_DIAG_TEST_ROOT:-${KP_PERSONAL_TEST_ROOT:-}}
_app=${KP_PERSONAL_APP:-$_root/data/nemesis/apps/korea.projection}
[ -d "$_app" ] || _app=$_root/data/nemesis/packages/korea.projection
. "$_app/usb/profiles.sh"
umask 077
core_pid=; radio_pid=
stop_children() {
    [ -z "$radio_pid" ] || { kill "$radio_pid" 2>/dev/null; wait "$radio_pid" 2>/dev/null; radio_pid=; }
    [ -z "$core_pid" ] || { kill "$core_pid" 2>/dev/null; wait "$core_pid" 2>/dev/null; core_pid=; }
    return 0
}
trap 'stop_children; exit 0' TERM INT HUP
idle() { while true; do sleep 30 & wait $!; done; }
publish_problem() {
    _stage='USB Wi-Fi 호환 확인이 필요합니다. KP USB Wi-Fi Logs로 기록을 저장해 주세요.'
    case "$1" in
        *reboot*|resident_driver*) _stage='동글을 꽂은 상태에서 내비를 재부팅해 주세요. 반복되면 KP USB Wi-Fi Logs로 기록을 저장해 주세요.' ;;
        *blocked*|*unfinished*) _stage='USB Wi-Fi 드라이버 보호 상태입니다. KP USB Wi-Fi Logs로 기록을 저장해 주세요.' ;;
    esac
    _pg=$_root/data/local/tmp/korea-projection-progress.txt
    mkdir -p "${_pg%/*}" || return 0
    ( umask 022
      printf 'pct=100\nstate=fail\nstage=%s\nboot=%s\nt=%s\nstep=failed\n' "$_stage" "$(cat "$_root/proc/sys/kernel/random/boot_id" 2>/dev/null)" "$(date +%s)" > "$_pg.tmp.$$" &&
        chmod 644 "$_pg.tmp.$$" && mv -f "$_pg.tmp.$$" "$_pg"
    )
}
case "$KP_PROFILE" in

    probe-only)
        mkdir -p "$KP_USB_STATE"
        sh "$KP_APP/usb/compat/probe.sh" > "$KP_USB_STATE/compatibility.txt"
        publish_problem "$KP_PROFILE_REASON"
        echo 'KP USB: untested compatibility; diagnostic mode.'; idle ;;
esac
mkdir -p "$KP_USB_STATE" || exit 1
if [ -f "$KP_USB_STATE/maintenance" ]; then
    echo 'KP USB: log-export boot; driver and AP paused.'
    idle
fi
if [ "$KP_PROFILE" != native ]; then
    # An old external bridge must be removed first; never run two controllers.
    for _root_apps in "$_root/data/nemesis/apps" "$_root/data/nemesis/packages"; do
        for _pkg in g70.usbwifi.bridge g70.wifi.probe jmk-wifi jmk.usbwifi usbwifi.hotspot stock.hotspot; do
            if [ -f "$_root_apps/$_pkg/NEMESIS.data" ]; then
                echo "KP USB: conflicting package $_pkg; remove it and reboot."
                idle
            fi
        done
    done
    G70_DIAG_TEST_ROOT=$_root KP_USB_BACKEND_PROFILE=$KP_PROFILE sh "$KP_APP/usb/g70/bin/wifi.sh" & radio_pid=$!
    _boot=$(cat "$_root/proc/sys/kernel/random/boot_id" 2>/dev/null)
    while true; do
        kill -0 "$radio_pid" 2>/dev/null || { wait "$radio_pid"; exit 1; }
        _state=; _readyboot=
        [ ! -r "$KP_USB_STATE/state.txt" ] || read -r _state < "$KP_USB_STATE/state.txt"
        [ ! -r "$KP_USB_STATE/runtime.boot" ] || read -r _readyboot < "$KP_USB_STATE/runtime.boot"
        [ "$_state" = wifi_ready ] && [ -n "$_boot" ] && [ "$_readyboot" = "$_boot" ] && break
        case "$_state" in *blocked*|*failed*|*incompatible*|*unsupported*|*unfinished*|*requires_reboot*|*reboot_required*|*file_changed*|cannot_*) sh "$KP_APP/usb/cache.sh" --observe >/dev/null 2>&1; stop_children; publish_problem "$_state"; idle ;; esac
        if [ -f "$KP_USB_STATE/maintenance" ]; then stop_children; idle; fi
        sleep 2 & wait $!
    done
fi
sh "$KP_APP/svc/hotspot.sh" --core & core_pid=$!
_cache_tick=0
while kill -0 "$core_pid" 2>/dev/null; do
    if [ -f "$KP_USB_STATE/maintenance" ]; then
        stop_children
        echo 'KP USB: snapshot saved; restart for USB-stick export.'
        idle
    fi
    if [ -n "$radio_pid" ]; then
        _state=$(cat "$KP_USB_STATE/state.txt" 2>/dev/null)
        case "$_state" in *blocked*|*failed*|*unsupported*|*reboot_required*) sh "$KP_APP/usb/cache.sh" --observe >/dev/null 2>&1; stop_children; publish_problem "$_state"; idle ;; esac
    fi
    if [ -n "$radio_pid" ] && ! kill -0 "$radio_pid" 2>/dev/null; then
        stop_children
        exit 1
    fi
    if [ "$_cache_tick" = 0 ]; then sh "$KP_APP/usb/cache.sh" --observe >/dev/null 2>&1; fi
    _cache_tick=$(( (_cache_tick+1) % 12 ))
    sleep 5 & wait $!
done
wait "$core_pid"; _rc=$?
core_pid=
stop_children
exit "$_rc"
