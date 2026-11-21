#!/system/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
R=${G70_DIAG_TEST_ROOT:-}
P="$R/data/nemesis/apps/korea.projection/usb/g70"
[ -d "$P" ] || P="$R/data/nemesis/packages/korea.projection/usb/g70"
. "$P/bin/common.sh"
U=; _storage=no
for _mountpoint in /storage/usb0 /storage/usb1 /storage/usb2 /mnt/media_rw/usb0 /mnt/media_rw/usb1 /mnt/media_rw/usb2; do
    mounted "$_mountpoint" || continue
    _storage=yes
    _mark=; [ ! -r "$R$_mountpoint/KP_USB_EXPORT.txt" ] || read -r _mark < "$R$_mountpoint/KP_USB_EXPORT.txt"
    [ "$_mark" = 'korea.projection export v1' ] || continue
    U="$R$_mountpoint"; break
done
if [ -n "$U" ]; then
    if loaded; then
        message result_fail "아직 드라이버가 올라와 있습니다. 로그 저장 모드에서 내비를 재부팅한 뒤 다시 실행해 주세요."
        exit 1
    fi
    [ -f "$BK/maintenance" ] || { message result_fail "먼저 동글로 동작을 확인한 뒤 KP USB Wi-Fi Logs를 실행해 현재 기록을 저장해 주세요."; exit 1; }
    O="$U/KP_USB_G70_$(date +%Y%m%d-%H%M%S)_$$"
    mkdir "$O" || exit 1
    message progress "Korea Projection USB 기록을 복사하는 중입니다. USB를 빼지 마세요."
    _copied=0
    for _capture in "$BK"/capture_*; do
        [ -f "$_capture/COMPLETE" ] || continue
        _dest="$O/${_capture##*/}"
        mkdir "$_dest" || exit 1
        for _name in bridge-status.txt korea-projection-ap.txt; do
            [ -f "$_capture/$_name" ] || continue
            cat "$_capture/$_name" > "$_dest/$_name" || exit 1
        done
        for _hardware in "$_capture"/G70_WIFI_CHECK_*; do
            [ -f "$_hardware/COMPLETE" ] || continue
            mkdir "$_dest/${_hardware##*/}" || exit 1
            for _name in report.txt usb-modaliases.txt kernel-config.gz kernel-exports.txt; do
                [ -f "$_hardware/$_name" ] || continue
                cat "$_hardware/$_name" > "$_dest/${_hardware##*/}/$_name" || exit 1
            done
        done
        _copied=$((_copied+1))
    done
    [ "$_copied" -gt 0 ] || { message result_fail "완료된 기록이 없습니다. 동글 상태에서 기록을 다시 저장해 주세요."; exit 1; }
    for _name in events.txt insmod.txt state.txt ap-capabilities.txt ap-failed-boots; do
        [ ! -f "$BK/$_name" ] || cat "$BK/$_name" > "$O/$_name" || exit 1
    done
    for _auto in auto-current auto-previous; do
        [ -d "$BK/$_auto" ] || continue
        mkdir "$O/$_auto" || exit 1
        for _fact in "$BK/$_auto"/*.txt; do
            [ ! -f "$_fact" ] || cat "$_fact" > "$O/$_auto/${_fact##*/}" || exit 1
        done
    done
    if [ -f "$KP/usb/cache.sh" ]; then
        sh "$KP/usb/cache.sh" --print > "$O/compatibility-memory.txt"
        sh "$KP/usb/cache.sh" --template > "$O/RESULT_CONFIRMATION.txt"
        [ ! -f "$U/KP_RESULT_CONFIRMATION.txt" ] || sh "$KP/usb/cache.sh" --import "$U/KP_RESULT_CONFIRMATION.txt"
    fi
    sync || exit 1
    echo 'Export complete.' > "$O/EXPORT_COMPLETE.txt" || exit 1
    sync || { rm -f "$O/EXPORT_COMPLETE.txt"; exit 1; }
    rm -f "$BK/maintenance"
    event export_complete_resume_on_next_boot
    message result_ok "기록 복사를 마쳤습니다. USB를 빼고 동글을 꽂은 뒤 내비를 재부팅하면 브리지가 다시 동작합니다."
    exit 0
fi
[ "$_storage" = no ] || { message result_fail "브리지 설치 USB의 KP_USB_EXPORT.txt 표시 파일을 확인해 주세요."; exit 1; }
if [ -f "$BK/maintenance" ]; then
    if loaded; then
        message result_ok "현재 기록은 저장돼 있습니다. 동글을 꽂아 둔 채 내비를 재부팅해 주세요."
    else
        message result_ok "드라이버가 내려가 있습니다. 동글을 빼고 브리지 설치 USB를 꽂은 뒤 KP USB Wi-Fi Logs의 Launch를 다시 눌러 주세요."
    fi
    exit 0
fi
# A first, very early capture stops the bridge before KP's initial grace
# period ends. Existing automatic evidence still permits immediate export.
_capture_age=$(up_seconds)
_auto_fact=no
for _fact in "$BK"/auto-current/*.txt "$BK"/auto-previous/*.txt; do
    [ ! -f "$_fact" ] || { _auto_fact=yes; break; }
done
case "$_capture_age" in ''|*[!0-9]*) ;; *)
    if [ "$_capture_age" -lt 150 ] && [ "$_auto_fact" = no ] && our_wlan &&
        [ "$(value "$BK/state.txt")" = wifi_ready ]; then
        message result_ok "아직 핫스팟 초기 대기 시간입니다. 동글을 꽂아 둔 채 부팅 후 5분이 지난 다음 KP USB Wi-Fi Logs의 Launch를 다시 눌러 주세요."
        exit 0
    fi ;;
esac
C="$BK/capture_$(date +%Y%m%d-%H%M%S)_$$"
mkdir "$C" || exit 1
message progress "현재 무선 상태를 저장하는 중입니다. 동글을 빼지 마세요."
evidence_snapshot > "$C/bridge-status.txt" || exit 1
G70_DIAG_OUTPUT_DIR="$C/G70_WIFI_CHECK_$(date +%Y%m%d-%H%M%S)_$$" \
    sh "$APP/bin/collect.sh" >/dev/null 2>&1 || exit 1
BB=
for _bb in "$KP/bin/busybox" "$R/system/bin/busybox"; do [ ! -x "$_bb" ] || { BB=$_bb; break; }; done
if [ -n "$BB" ] && [ -r "$R/data/nemesis/logs/korea.projection/ap.log" ]; then
    "$BB" awk -f "$APP/bin/filter-log.awk" "$R/data/nemesis/logs/korea.projection/ap.log" > "$C/korea-projection-ap.txt" || exit 1
fi
: > "$C/COMPLETE" || exit 1
echo requested > "$BK/maintenance" || exit 1
sync || exit 1
message result_ok "현재 기록을 저장했습니다. 동글을 유지한 채 내비를 재부팅하고 KP USB Wi-Fi Logs를 다시 눌러 주세요. 다음 부팅에서는 드라이버를 올리지 않아 USB로 기록을 복사할 수 있습니다."
exit 0
