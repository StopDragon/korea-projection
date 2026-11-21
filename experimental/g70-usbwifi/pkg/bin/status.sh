#!/system/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
R=${G70_DIAG_TEST_ROOT:-}
P="$R/data/nemesis/apps/g70.usbwifi.bridge"
[ -d "$P" ] || P="$R/data/nemesis/packages/g70.usbwifi.bridge"
. "$P/bin/common.sh"
_text=$(status_text)
_state=$(value "$BK/state.txt")
_driver=no; _wlan=no; _mod=no; _disabled=no; _ap=UNKNOWN; _dhcp=no; _source=none; _ip=no; _leases=0; _kp=unavailable; _current=no
while IFS= read -r _line; do
    case "$_line" in
        driver_loaded=*) _driver=${_line#*=} ;;
        wlan0_ours=*) _wlan=${_line#*=} ;;
        wireless_mod=*) _mod=${_line#*=} ;;
        wireless_mod_disabled=*) _disabled=${_line#*=} ;;
        ctrl.state=*) _ap=${_line#*=} ;;
        dhcp_running=*) _dhcp=${_line#*=} ;;
        dhcp_source=*) _source=${_line#*=} ;;
        ap_ipv4=*) _ip=${_line#*=} ;;
        bridge_dhcp_lease_count=*) _leases=${_line#*=} ;;
        kp_state=*) _kp=${_line#*=} ;;
        kp_progress_current_boot=*) _current=${_line#*=} ;;
    esac
done <<STATE
$_text
STATE
_driver_label="동글 대기 중"
[ "$_driver" != yes ] || _driver_label="드라이버 준비됨"
[ "$_wlan" != yes ] || _driver_label="동글 Wi-Fi 장치 확인됨"
_mod_label="Korea Projection 설정 대기/진행 중"
[ "$_mod" != yes ] || _mod_label="무선 모드 설치됨"
[ "$_disabled" != yes ] || _mod_label="무선 모드가 꺼져 있습니다. HMG-API에서 확인해 주세요."
_ap_label="Korea Projection에서 핫스팟 상태를 확인해 주세요."
if [ "$_ap" = ENABLED ]; then
    _ap_label="차량 Wi-Fi 신호 켜짐 · 주소 할당 준비 중"
    if [ "$_dhcp:$_ip" = yes:yes ]; then
        _ap_label="차량 Wi-Fi/DHCP 실행 중 · 휴대폰 주소 할당 기록 없음"
        case "$_leases" in ''|*[!0-9]*) ;; *)
            [ "$_leases" -le 0 ] || _ap_label="차량 Wi-Fi/DHCP 실행 중 · 주소 임대 기록 ${_leases}개" ;;
        esac
        [ "$_source" != korea_projection ] || _ap_label="차량 Wi-Fi 켜짐 · Korea Projection 주소 할당 서비스 사용 중"
    fi
fi
_next="설치 후에는 5분 기다리고 Korea Projection의 Launch 화면을 확인해 주세요."
if [ "$_current" = yes ] && [ "$_kp" = reboot ]; then _next="Korea Projection이 재부팅을 요청했습니다. 내비를 재부팅해 주세요."; fi
if [ "$_current" = yes ] && [ "$_kp" = fail ]; then _next="Korea Projection에서 오류 문구를 확인하고 필요하면 G70 Wi-Fi Logs로 기록을 저장해 주세요."; fi
if [ -f "$BK/maintenance" ]; then
    message result_ok "로그 저장 모드입니다. 내비를 재부팅한 뒤 G70 Wi-Fi Logs에서 기록 복사를 진행해 주세요."
elif [ "$_state" = wifi_ready ]; then
    message result_ok "$_driver_label
$_mod_label
$_ap_label
$_next"
else
    message result_ok "$_driver_label
준비가 계속 끝나지 않으면 동글 연결을 확인하고 G70 Wi-Fi Logs로 기록을 저장해 주세요."
fi
exit 0
