#!/system/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# One data port: capture with dongle, pause next boot, swap stick, export.
export PATH=${KP_PERSONAL_TEST_PATH:-/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin}
R=${G70_DIAG_TEST_ROOT:-${KP_PERSONAL_TEST_ROOT:-}}
P=${KP_PERSONAL_APP:-$R/data/nemesis/apps/korea.projection}
[ -d "$P" ] || P=$R/data/nemesis/packages/korea.projection
. "$P/usb/profiles.sh"
tell() {
    echo "$2"
    am start -n com.nemesis.manager/.DialogActivity -f 0x10000000 \
        --es nemesis_mode "$1" --es nemesis_message "$2" >/dev/null 2>&1
}
case "$KP_PROFILE" in g70|generic-usb|nx4|ev6|probe-only|native) ;; *) tell result_fail 'USB 구성 상태를 확인할 수 없습니다.'; exit 1 ;; esac
if [ "$KP_PROFILE" = probe-only ] || [ "$KP_PROFILE" = native ]; then
    U=
    for u in /storage/usb0 /storage/usb1 /storage/usb2; do
        _mounted=0
        while read -r _d _m _rest; do [ "$_m" != "$u" ] || _mounted=1; done < "$R/proc/mounts"
        [ "$_mounted" = 1 ] || continue
        _mark=; [ ! -r "$R$u/KP_USB_EXPORT.txt" ] || read -r _mark < "$R$u/KP_USB_EXPORT.txt"
        [ "$_mark" != 'korea.projection export v1' ] || { U=$R$u; break; }
    done
    [ -n "$U" ] || { tell result_ok '호환성 진단은 이 설치 USB를 꽂은 상태에서 Logs를 실행해 주세요.'; exit 0; }
    O=$U/KP_COMPAT_$(date +%Y%m%d-%H%M%S)_$$
    mkdir "$O" || exit 1
    sh "$KP_APP/usb/compat/probe.sh" > "$O/compatibility.txt" || exit 1
    G70_DIAG_TEST_ROOT=$R G70_DIAG_OUTPUT_DIR=$O/hardware sh "$KP_APP/usb/g70/bin/collect.sh" >/dev/null 2>&1 || exit 1
    sh "$KP_APP/usb/cache.sh" --print > "$O/compatibility-memory.txt"
    : > "$O/EXPORT_COMPLETE.txt"
    sync || exit 1
    tell result_ok '호환성 진단 복사 완료. 내장 Wi-Fi 동작과 미확인 USB는 변경하지 않았습니다.'
    exit 0
fi
# Never interrupt HMG-API setup while changing to a log-export boot.
_fp=; _fb=; _bid=$(cat "$R/proc/sys/kernel/random/boot_id" 2>/dev/null)
if [ -r "$R/data/local/tmp/korea.projection/fix.pid" ]; then
    read -r _fp _fb < "$R/data/local/tmp/korea.projection/fix.pid"
    case "$_fp" in ''|*[!0-9]*) ;; *)
        if [ "$_fb" = "$_bid" ] && [ -d "$R/proc/$_fp" ]; then
            tell result_ok '무선 설정이 진행 중입니다. 설정이 끝난 뒤 기록을 저장해 주세요.'
            exit 0
        fi ;;
    esac
fi
sh "$KP_APP/usb/cache.sh" --observe >/dev/null 2>&1
export KP_USB_BACKEND_PROFILE=$KP_PROFILE
exec sh "$KP_APP/usb/g70/bin/logs.sh"
