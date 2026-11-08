#!/system/bin/sh
# USB 스크립트(NEMESIS.sh, type=execute): korea.projection 1.5.3로 업데이트하고, 스토어 제출 조건인
# "설치 → 사용 → 삭제 → 원래 상태 복구"를 차에서 확인한다. USB를 꽂을 때마다 한 단계씩 진행한다.
# 단계는 /data/local/tmp/kp-test7/step, 기록은 USB의 kp7/.
#   (처음) U: 1.5.3로 업데이트 → 버전과 핫스팟 확인                    → 카플레이 써 보고 다시 꽂기
#   R: 삭제 → 바로 남은 것이 없는지 확인                               → 내비 재부팅 후 다시 꽂기
#   R2: 재시작 뒤 일반 Wi-Fi·HMG-API 파일이 원래대로인지 확인 → 다시 설치 → 확인
#   그 뒤: 로그와 상태 수집
# 비밀번호, SSID, 휴대폰 이름은 어디에도 쓰지 않는다.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin:/data/nemesis/bin
BB=${BB:-/system/bin/busybox}
[ -x "$BB" ] || BB=${APPS:-/data/nemesis/apps}/korea.projection/bin/busybox
U=${U:-/storage/usb0}
D=${D:-/data/local/tmp/kp-test7}
# 스크립트도 헤드유닛에 복사해서 거기서 돈다: 도중에 USB가 떨어져도 셸이 스크립트를 계속 읽을 수 있게
if [ "$KP_FROM_DATA" != 1 ]; then
  export KP_FROM_DATA=1
  $BB mkdir -p $D && $BB cp "$0" $D/run.sh && exec sh $D/run.sh
fi
APPS=${APPS:-/data/nemesis/apps}
PERMS=${PERMS:-/system/etc/permissions}
PKG=korea.projection
ZIP=$U/packages/$PKG.zip
# 업데이트가 실패해 아무것도 남지 않으면 되돌릴 이전 버전 (2026-11-06: 1.4 업데이트 실패로 핫스팟이 없어졌다)
PREV=$U/packages/$PKG-prev.zip
CONF=${CONF:-/data/misc/wifi/hostapd-kp.conf}
WD=${WD:-/data/local/tmp/$PKG}
BK=${BK:-/data/nemesis/backup/$PKG}
# 기록은 먼저 헤드유닛($D/out)에 쓰고 끝날 때 USB로 복사한다. 11-06 차에서: 패키지 삭제가 Wi-Fi를
# 껐다 켜는 동안 USB가 잠깐 떨어졌다 다시 붙는 것으로 보이고, 그 뒤 USB에 쓴 기록이 사라졌다.
O=$D/out
UO=$U/kp7
WANT=1.5.5
# USB가 실제로 붙어 있을 때만 복사 (빈 마운트 지점 폴더에 쓰지 않게)
copy_out() {
  $BB grep -q " $U " ${MOUNTS:-/proc/mounts} 2>/dev/null || return 0
  $BB mkdir -p $UO 2>/dev/null && $BB cp $O/* $UO/ 2>/dev/null; sync
}
trap 'copy_out' EXIT
umask 077
$BB mkdir -p $D $O
# 지난번에 USB로 못 옮긴 기록부터 옮긴다
copy_out

toast() {
  echo "$1"
  am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "$1" \
    --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1
}

# 우리 프로세스가 떠 있는가 (busybox ps는 약 80칸에서 자르므로 앞부분으로 찾는다)
ours_up() { $BB ps | $BB grep -v grep | $BB grep -q "hostapd $CONF"; }
dhcp_up() { $BB ps | $BB grep -v grep | $BB grep -q "dnsmasq --keep-in-foreground"; }
# 목록이 제대로 나오는가 (usb-handler는 항상 있다) — 목록을 못 읽는 것을 "삭제됨"으로 착각하지 않게
list_ok() { nemesis pkg-list 2>/dev/null | $BB grep -q "^usb-handler|"; }
listed() { nemesis pkg-list 2>/dev/null | $BB grep -q "^$PKG|"; }
# KitKat의 pm은 실패해도 종료 코드 0일 수 있어 출력으로 본다
app_installed() { pm path korea.projection.app 2>/dev/null | $BB grep -q "^package:"; }
installed_ver() {
  nemesis pkg-list 2>/dev/null | while IFS='|' read -r _id _n _l _t _v _r; do
    [ "$_id" = $PKG ] && echo "$_v"
  done
}

state() {
  echo "=== $1 $(date) === (부팅 뒤 $(cut_up)초)"
  echo "-- 패키지 --"; nemesis pkg-list 2>&1
  echo "-- 무선 기능 --"; pm list features 2>/dev/null | $BB grep -iE "carplay|androidauto|hardware.wifi"
  echo "-- 권한 파일 --"; $BB ls -la $PERMS/ | $BB grep -iE "carplay|androidauto"
  echo "-- Wi-Fi 설정 wifi_on=$(settings get global wifi_on 2>/dev/null) persist.wifi.state=$(getprop persist.wifi.state)"
  echo "-- 프로세스 --"; $BB ps | $BB grep -E "hostapd|dnsmasq|wpa_supp|hotspot.sh" | $BB grep -v grep
  echo "-- HMG-API --"; hmgapid engine status 2>&1 | $BB grep -E "^(ok|CHANGED|problem)"
}

# 부팅 뒤 지난 초 (/proc/uptime 첫 값의 정수 부분): 재시작했는지 기록으로 알 수 있게
cut_up() { read _u _r < /proc/uptime 2>/dev/null; echo "${_u%%.*}"; }

# 결과 한 줄: "통과"/"실패"와 설명. 실패 수는 $D/fails에 센다.
res() {
  if eval "$2"; then echo "통과 $1"; else echo "실패 $1"; echo x >> $D/fails; fi
}

[ -s $ZIP ] || { toast "Korea Projection 테스트: USB에 packages/$PKG.zip이 없어 시작하지 않았습니다."; exit 0; }
[ -s $PREV ] || { toast "Korea Projection 테스트: USB에 되돌리기용 packages/$PKG-prev.zip이 없어 시작하지 않았습니다."; exit 0; }

STEP=$(cat $D/step 2>/dev/null)
case "$STEP" in
"")
  {
    state "U: 업데이트 전"
    echo "=== nemesis install --update ==="
    nemesis install --update $ZIP 2>&1
    echo "install exit $?"
    sleep 25
    if [ -z "$(installed_ver)" ]; then
      # 예전 것은 지워졌는데 새 것이 안 깔린 경우: 그냥 설치
      echo "=== 패키지가 없음: nemesis install ==="
      nemesis install $ZIP 2>&1
      sleep 25
    fi
    if [ -z "$(installed_ver)" ]; then
      # 그래도 없으면 이전 버전으로 되돌린다: 핫스팟(무선 카플레이)이 없는 상태로 두지 않는다
      echo "=== 새 버전 설치 실패: 이전 버전으로 되돌림 ==="
      nemesis install $PREV 2>&1
      sleep 25
      echo PREV > $D/restored
    fi
    state "U: 업데이트 후"
  } > $O/U.txt 2>&1
  v=$(installed_ver)
  if [ "$v" = $WANT ] && ours_up; then
    # USB에 kp-only-update 파일이 있으면 업데이트만 하고 끝낸다 (삭제·복구 확인은 건너뜀)
    if [ -f $U/kp-only-update ]; then
      echo DONE > $D/step
      toast "Korea Projection $WANT 업데이트 완료. NEMESIS Manager에서 Launch를 눌러 상태 화면과 QR을 확인해 주세요."
      sync
      exit 0
    fi
    echo R > $D/step
    toast "Korea Projection $WANT 업데이트 완료. NEMESIS Manager에서 Korea Projection의 Launch를 눌러 상태 화면과 QR을 확인한 뒤 USB를 다시 꽂아 주세요."
  else
    echo "=== 업데이트 확인 실패: 버전 '$v', 핫스팟 $(ours_up && echo 켜짐 || echo 꺼짐) ===" >> $O/U.txt
    if [ -f $D/restored ]; then
      rm -f $D/restored
      toast "Korea Projection: 새 버전 설치에 실패해 이전 버전($v)으로 되돌렸습니다. 무선 카플레이는 그대로 쓰실 수 있습니다. USB를 가져와 주세요."
    else
      toast "Korea Projection 테스트: 업데이트 확인에 실패했습니다(버전 '$v'). USB를 가져와 주세요."
    fi
  fi
  ;;
R)
  # 1단계: 삭제하고 바로 확인. 일반 Wi-Fi는 내비를 재부팅한 뒤에 돌아오므로 R2에서 본다.
  rm -f $D/fails
  # 다시 설치할 zip을 헤드유닛에 먼저 복사해 둔다
  $BB cp $ZIP $D/pkg.zip
  # 설치 전 Wi-Fi 값은 post.sh가 적어 둔 $BK/wifi_on (설치 뒤에는 서비스가 Wi-Fi를 켜 두므로 지금 값은 항상 1)
  wifi_before=$(cat $BK/wifi_on 2>/dev/null)
  [ -n "$wifi_before" ] || wifi_before=$(settings get global wifi_on 2>/dev/null)
  echo "$wifi_before" > $D/wifi_before
  $BB ls $PERMS 2>/dev/null | $BB grep -c "_wireless.xml" > $D/perms_before
  {
    state "R: 삭제 전"
    echo "=== nemesis uninstall $PKG ==="
    nemesis uninstall $PKG 2>&1
    echo "uninstall exit $?"
    sleep 10
    state "R: 삭제 직후"
    echo "=== 삭제 직후 확인 ==="
    res "패키지 목록에서 빠짐" 'list_ok && ! listed && [ ! -d $APPS/$PKG ]'
    res "우리 hostapd 멈춤" '! ours_up'
    res "우리 dnsmasq 멈춤" '! dhcp_up'
    res "hostapd 설정 파일 지워짐" '[ ! -f $CONF ]'
    res "작업 폴더 지워짐" '[ ! -d $WD ]'
    res "백업 폴더 지워짐" '[ ! -d $BK ]'
    res "상태 화면 앱 지워짐" '! app_installed'
  } > $O/R.txt 2>&1
  echo R2 > $D/step
  toast "Korea Projection 삭제 확인 1단계 끝. 내비를 재부팅한 뒤(RESET 버튼 또는 NEMESIS 재부팅) USB를 다시 꽂아 주세요. 그동안 무선 카플레이는 안 됩니다."
  ;;
R2)
  # 2단계: 재시작 뒤 원래대로 돌아왔는지 확인하고 다시 설치한다
  ZIP=$D/pkg.zip
  [ -s $ZIP ] || ZIP=$U/packages/$PKG.zip
  wifi_before=$(cat $D/wifi_before 2>/dev/null)
  perms_before=$(cat $D/perms_before 2>/dev/null)
  {
    state "R2: 재시작 뒤"
    echo "=== 재시작 뒤 확인 ==="
    res "패키지가 다시 생기지 않음" 'list_ok && ! listed'
    res "우리 hostapd 없음" '! ours_up'
    res "Wi-Fi 설정이 설치 전과 같음 ($wifi_before)" '[ "$(settings get global wifi_on 2>/dev/null)" = "$wifi_before" ]'
    # 일반 Wi-Fi(wpa_supplicant)는 확인하지 않는다: 2026-11-06 니로에서 패키지가 없는 깨끗한 부팅에서도
    # wifi_on=1인데 wpa_supplicant가 뜨지 않았다(현대 Wi-Fi 클라이언트는 자체 스위치로 켠다). 기록만 남긴다.
    echo "참고 wpa_supplicant $($BB ps | $BB grep -v grep | $BB grep -c wpa_supplicant)개 (확인 항목 아님)"
    res "HMG-API 무선 기능 파일 그대로 ($perms_before개)" '[ "$($BB ls $PERMS 2>/dev/null | $BB grep -c "_wireless.xml")" = "$perms_before" ]'
    res "무선 카플레이 기능 켜져 있음" 'pm list features 2>/dev/null | $BB grep -q carplay_wireless'
    echo "=== 다시 설치 ==="
    nemesis install $ZIP 2>&1
    echo "install exit $?"
    sleep 25
    state "R2: 다시 설치 후"
    res "다시 설치됨 ($WANT)" '[ "$(installed_ver)" = $WANT ]'
    res "다시 설치 뒤 핫스팟 켜짐" 'ours_up'
    res "다시 설치 뒤 상태 화면 앱 있음" 'app_installed'
  } >> $O/R.txt 2>&1
  n=0; [ -f $D/fails ] && n=$(( $($BB wc -l < $D/fails) ))
  if [ "$(installed_ver)" = $WANT ] && ours_up; then
    echo DONE > $D/step
    if [ "$n" -eq 0 ]; then
      toast "Korea Projection 삭제·복구 확인: 모두 통과. 다시 설치했습니다. 무선 카플레이를 연결해 보세요."
    else
      toast "Korea Projection 삭제·복구 확인: 실패 ${n}건(kp7/R.txt). 다시 설치는 됐습니다. USB를 가져와 주세요."
    fi
  else
    echo REINSTALL > $D/step
    toast "Korea Projection: 다시 설치가 확인되지 않았습니다. USB를 다시 꽂으면 다시 설치합니다."
  fi
  ;;
REINSTALL)
  [ -s $D/pkg.zip ] && ZIP=$D/pkg.zip
  {
    state "다시 설치 재시도 전"
    nemesis install $ZIP 2>&1 || nemesis install --update $ZIP 2>&1
    sleep 25
    state "다시 설치 재시도 후"
  } >> $O/R.txt 2>&1
  if [ "$(installed_ver)" = $WANT ] && ours_up; then
    echo DONE > $D/step
    toast "Korea Projection: 다시 설치했습니다. 핫스팟이 켜졌습니다."
  else
    toast "Korea Projection: 다시 설치에 또 실패했습니다. USB를 가져와 주세요(다시 꽂으면 또 시도합니다)."
  fi
  ;;
*)
  for f in /data/nemesis/logs/$PKG/*.log $WD/cp.log*; do [ -f "$f" ] && $BB cp "$f" $O/${f##*/}.txt; done
  for f in /data/hmgapi/logs/hmgapi/log.log*; do [ -f "$f" ] && $BB cp "$f" $O/hmgapi-${f##*/}.txt; done
  state "로그 수집" > $O/C-$(date +%H%M).txt 2>&1
  # MAC 주소는 남기지 않는다 (inet 줄만)
  { echo "-- wpa_supplicant: $($BB ps | $BB grep -v grep | $BB grep -c wpa_supplicant)개"; $BB ifconfig wlan0 2>&1 | $BB grep "inet addr"
    echo "-- 남은 공간 (/data) --"; $BB df /data 2>&1 || df /data 2>&1; } >> $O/C-$(date +%H%M).txt
  toast "Korea Projection 테스트: 로그를 USB에 복사했습니다."
  ;;
esac
sync
echo "STEP $(cat $D/step 2>/dev/null)"
