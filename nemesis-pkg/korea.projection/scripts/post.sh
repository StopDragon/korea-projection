#!/system/bin/sh
# postinstall (cwd /data/nemesis/apps/korea.projection): note Wi-Fi's setting for the
# uninstall, and stop the stick script's access point (cp-drive.sh) if one is running, so only
# this package's hostapd has wlan0. NEMESIS starts the service after this.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
# busybox는 아래 hotspot.sh가 고른다(내비의 것, 없으면 패키지에 함께 넣은 것: 1.6.x 알파). 비워 두면 고른다.
BB=
BK=${BK:-/data/nemesis/backup/korea.projection}
umask 077
mkdir -p $BK
[ -f $BK/wifi_on ] || settings get global wifi_on > $BK/wifi_on 2>/dev/null
# opt-in CarPlay log (svc/hotspot.sh, off by default): a file korea-projection-debug on the stick
W=/data/local/tmp/korea.projection
for u in /storage/usb0 /storage/usb1; do
  [ -f $u/korea-projection-debug ] && mkdir -p $W && : > $W/debug && echo "카플레이 디버그 로그 켬 ($W/cp.log)"
done
# 1.7.0 무선 안드로이드 오토(기본 켜짐): USB 맨 위의 kp-aa-off로 끄고 kp-aa-on으로 다시 켠다. 어느 USB든 끄기를 먼저 본다(리뷰 L3).
# $BK에 남아 업데이트해도 유지된다(삭제하면 지워짐)
if [ -f /storage/usb0/kp-aa-off ] || [ -f /storage/usb1/kp-aa-off ]; then : > $BK/aa-off; echo "무선 안드로이드 오토 끔"
elif [ -f /storage/usb0/kp-aa-on ] || [ -f /storage/usb1/kp-aa-on ]; then rm -f $BK/aa-off; echo "무선 안드로이드 오토 켬"; fi
HOTSPOT_LIB=1 . /data/nemesis/apps/korea.projection/svc/hotspot.sh
OLD=/data/local/tmp/cpdrive
P=$(cat $OLD/watchdog.pid 2>/dev/null)
if [ -n "$P" ] && $PS | $BB grep -v grep | $BB grep -q "^ *$P .*cpdrive/watchdog.sh"; then
  kill $P 2>/dev/null
  [ -f $OLD/log.pid ] && kill $(cat $OLD/log.pid) 2>/dev/null
  for p in $($PS | $BB grep -v grep | $BB grep "hostapd /data/misc/wifi/hostapd-cp.conf" | $BB awk '{print $1}'); do kill $p; done
  # cp-drive의 dnsmasq도 (우리 것과 명령 앞부분이 같아서 남겨 두면 우리 dnsmasq가 시작되지 않는다)
  for p in $($PS | $BB grep -v grep | $BB grep "dnsmasq --keep-in-foreground" | $BB awk '{print $1}'); do kill $p; done
  echo "USB 스크립트(cp-drive.sh)의 핫스팟을 멈춤"
fi
# busybox가 없는 내비(K3 BDPE·K8 GL3HEV, #15·#19): 무선 설정은 하지 않는다(서비스도 대기만 함). 한 번 알린다
# (1.7.1: 토스트 대신 notice: 설치 출력·ap.log·상태 화면 알림 기록).
# 상태 화면 앱만 설치한다(1.5.5): 앱이 없으면 Launch 때 NEMESIS가 "Error type 3 … does not exist"를 띄워 안내를 가린다.
# 앱 설치가 실패해도 패키지 설치는 성공으로 둔다(Launch 때 다시 시도). 결과는 $W/app-install.log에 남는다.
if ! has_bb; then
  install_app >/dev/null 2>&1
  m="Korea Projection: 이 내비에서는 아직 동작하지 않습니다(지원 조사 중). 무선 설정은 하지 않았습니다."
  notice "$m"
  exit 0
fi
# 상태 화면 앱: 실패해도 패키지 설치는 성공으로 둔다 (Launch를 누를 때 다시 시도)
# 문구에 핫스팟 상태를 쓰지 않는다: 여기서는 앱만 본다(1.5.3까지 "핫스팟은 정상"이라 써서 #9·#15가 오해함)
if ! install_app; then
  m="Korea Projection: 상태 화면 앱을 설치하지 못했습니다(Launch를 누르면 다시 시도). 무선 카플레이 설정은 따로 진행됩니다."
  notice "$m"
fi
if [ -d /data/nemesis/apps/niro.carplay.hotspot ]; then
  m="Korea Projection: 이전 패키지 niro.carplay.hotspot을 삭제하면 시작합니다."
  notice "$m"
fi
# 그랜저 IG(IGPE.KOR.*.260902): 와이드스크린(1920x720) 및 유선 보호 (비대상 차는 건드리지 않음, toolbox 전용)
if wide_supported || { [ ! -L "$SYSORIG" ] && [ -d "$SYSORIG" ]; } || { [ ! -L "$WIDEOFF" ] && [ -f "$WIDEOFF" ]; }; then
  USBS=${USBS:-"/storage/usb0 /storage/usb1"}
  _wo=0; _won=0
  for _u in $USBS; do
    [ -f "$_u/kp-wide-off" ] && _wo=1
    [ -f "$_u/kp-wide-on" ] && _won=1
  done
  _wf=${WIDEOFF:-$BK/wide-off}
  if [ $_wo = 1 ]; then
    [ "${_wf%/*}" != "$_wf" ] && [ -n "${_wf%/*}" ] && mkdir -p "${_wf%/*}" 2>/dev/null
    [ -L "$_wf" ] && rm -f "$_wf"
    : > "$_wf"; echo "와이드스크린(1920x720) 끔"
  elif [ $_won = 1 ]; then rm -f "$_wf"; echo "와이드스크린(1920x720) 켬"; fi
  if [ ! -L "$_wf" ] && [ -f "$_wf" ]; then
    wide_restore || echo "와이드스크린 설정 되돌리기 건너뜀"
  else
    wide_apply || echo "와이드스크린 설정 적용 건너뜀(서비스 시작 후 다시 시도)"
  fi
fi
usb_guard || echo "유선 프로젝션 설정 보호 건너뜀(서비스 시작 후 다시 시도)"
exit 0
