#!/system/bin/sh
# NEMESIS Manager > Korea Projection > Launch: 상태 토스트와 차량 제보용 리포트
# (USB가 꽂혀 있으면 USB의 KoreaProjection-report 폴더에 1-report.md, 3-log.txt로, 그리고 $W에 저장).
# 리포트에는 이름, 버전, 예/아니요, 개수만 넣는다. SSID, 비밀번호, 휴대폰 이름, MAC, IP는
# 넣지 않는다. 차 주인이 읽어 본 뒤 첨부한다.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
# busybox는 hotspot.sh가 고른다(내비의 것, 없으면 패키지에 함께 넣은 것: 1.6.x 알파)
APP=${APP:-/data/nemesis/apps/korea.projection}
HOTSPOT_LIB=1 . $APP/svc/hotspot.sh
ISSUES=https://github.com/StopDragon/korea-projection/issues/new?template=car-report.yml
umask 077
bbx mkdir -p $W 2>/dev/null
# --wait(1.5.5): Launch를 설치 중에 누르면 뒤에서 한 번 더 돈다. 설치가 끝날 때까지(최대 15분) 기다렸다가 아래 보통
# 흐름으로 상태 파일·USB 제보 파일을 다시 만든다(그때 USB가 꽂혀 있으면). 상태 화면 앱은 진행 막대를 보여 주다가
# 상태 파일이 새로 쓰이면 결과 화면으로 바뀐다.
WAITED=0
if [ "$1" = --wait ]; then
  _i=0
  while $BB grep -q '^state=run$' $PROG 2>/dev/null && [ $_i -lt 180 ]; do sleep 5; _i=$((_i+1)); done
  rm -f $W/wait.pid
  WAITED=1
fi

yn() { if "$@" >/dev/null 2>&1; then echo 예; else echo 아니요; fi; }
# 1.6.2: 무선 카플레이 AP를 누가 띄웠는가. ours: 우리 hostapd, stock: 순정이 카플레이 SSID로 띄움(hotspot.sh stock_ssid),
# none: 둘 다 아님. parse_conf를 먼저 부른다. 첫 인자로 이미 구한 stock_ssid 값을 받을 수 있다.
ap_mode() {
  if running "hostapd $CONF"; then echo ours
  elif [ "${1:-$(stock_ssid)}" = carplay ]; then echo stock
  else echo none; fi
}
# USB가 마운트돼 있는가 (마운트 지점 폴더는 USB가 없어도 있을 수 있어 /proc/mounts로 본다)
USBS="/storage/usb0 /storage/usb1"
usb_in() {
  for _u in $USBS; do bbx grep -q " $_u " /proc/mounts 2>/dev/null && return 0; done
  return 1
}
# 순정 파일 위치 (테스트에서 바꿀 수 있게)
SYSAPP=${SYSAPP:-/system/app}
SYSLIB=${SYSLIB:-/system/lib}
SYSONE=${SYSONE:-/system/onebin}
HMGSTOCK=${HMGSTOCK:-/data/hmgapi/stock}
# NEMESIS.data의 값 하나 (이 헤드유닛에는 sed/cut/tr이 없다)
pver() { _v=$($BB grep '^package-version=' "$1" 2>/dev/null); echo "${_v#package-version=}"; }
# USB 제보 폴더 이름. 사용자가 찾기 쉽게 고정한다(안내문과 같아야 한다).
# 안의 파일: 1-report.md(이 스크립트), 2-car-report.json(carreport.sh), 3-log.txt(이 스크립트)
RDIR=${RDIR:-KoreaProjection-report}
# 1.7.2: 비공개 디버그 로그는 제보 폴더 밖의 다른 폴더에 둔다. 제보 폴더를 "모두 선택"해 올려도 섞이지 않게(#56).
PDIR=${PDIR:-KoreaProjection-private}
# NEMESIS가 정한 위치(hotspot.sh에도 같은 기본값이 있다). 여기서는 그대로 다시 정한다(PC 테스트가 이 줄의 경로를 바꾼다)
APLOG=/data/nemesis/logs/korea.projection/ap.log
# busybox가 없는 내비(K3 BDPE·K8 GL3HEV, tcc803x, #15·#19): 보통 리포트는 못 만든다. 셸 기본 명령(grep, mkdir, ls)만으로
# USB에 짧은 리포트를 남긴다(제품, 플랫폼, 이 내비에 있는 명령 목록: busybox 없이 다시 만들 때 참고). 개인정보는 없다.
# 1.5.5: 상태 화면 앱도 쓴다. 앱이 없으면 다시 설치하고(설치 때 실패했을 수 있음), 앱이 읽을 짧은 상태 파일
# (support=nobb)을 쓴다. 앱은 오류 대신 "아직 동작하지 않음(조사 중)" 화면을 보인다. 이 셸에는 printf가 없어 echo만 쓴다.
if ! has_bb; then
  install_app_once
  _nbw=0
  for u in /storage/usb0 /storage/usb1; do
    grep -q " $u " /proc/mounts 2>/dev/null || continue
    mkdir -p "$u/$RDIR" 2>/dev/null || continue
    {
      echo "# Korea Projection 리포트 (busybox 없는 내비)"
      echo "- 펌웨어: $(getprop ro.build.product)"
      echo "- 플랫폼: $(getprop ro.board.platform)"
      echo "- 이 패키지: $(grep '^package-version=' $APP/NEMESIS.data 2>/dev/null)"
      echo "- NEMESIS: $(nemesis version 2>/dev/null)"
      echo; echo "## /system/bin"; ls /system/bin
      echo; echo "## /system/xbin"; ls /system/xbin
    } > "$u/$RDIR/1-report.md" 2>/dev/null
    # 성공은 파일로 판단한다(묶음의 마지막 명령 ls의 종료 코드로 보지 않음)
    [ -s "$u/$RDIR/1-report.md" ] && sync && _nbw=1 && break
  done
  _st=${STATUS:-/data/local/tmp/korea-projection-status.txt}
  _pv=$(grep '^package-version=' $APP/NEMESIS.data 2>/dev/null)
  if [ "$_nbw" = 1 ]; then _us=saved; elif usb_in; then _us=fail; else _us=none; fi
  # .tmp에 쓴 뒤 바꾼다(열려 있는 화면이 반쯤 쓴 파일을 읽지 않게). toolbox mv는 -f 없이 같은 장치에서 덮어쓴다.
  ( umask 022
    { echo "support=nobb"
      echo "product=$(getprop ro.build.product)"
      echo "platform=$(getprop ro.board.platform)"
      echo "pkgver=${_pv#package-version=}"
      echo "usb=$_us"
      echo "made=$(date '+%m-%d %H:%M')"
    } > $_st.tmp 2>/dev/null && chmod 644 $_st.tmp 2>/dev/null && mv $_st.tmp $_st 2>/dev/null )
  # 1.7.1: 토스트는 쓰지 않는다. 앱이 있으면 화면이 안내하고, USB 저장은 알림 기록으로 화면에 보인다.
  if ! app_installed; then
    notice "Korea Projection: 이 내비에서는 아직 동작하지 않습니다(지원 조사 중). 무선 설정은 하지 않았습니다."
  elif [ "$_nbw" = 1 ]; then
    notice "Korea Projection: 제보 파일을 USB의 KoreaProjection-report 폴더에 저장했습니다."
  fi
  exit 0
fi
# 1.7.0 무선 안드로이드 오토(기본 켜짐) · 와이드스크린(1920x720, IGPE.KOR.*.260902 기본 켜짐) 끄기·켜기:
# Launch 때 마운트된 USB 맨 위의 kp-aa-off/kp-aa-on, kp-wide-off/kp-wide-on을 서로 독립적으로 처리한다(어느 USB든 끄기 우선).
_aao=0; _aaon=0; _wo=0; _won=0
for u in $USBS; do
  bbx grep -q " $u " /proc/mounts 2>/dev/null || continue
  [ -f $u/kp-aa-off ] && _aao=1
  [ -f $u/kp-aa-on ] && _aaon=1
  [ -f $u/kp-wide-off ] && _wo=1
  [ -f $u/kp-wide-on ] && _won=1
done
if [ $_aao = 1 ]; then
  bbx mkdir -p $BK 2>/dev/null; : > $AAOFF; aa_sig 0 off
elif [ $_aaon = 1 ]; then
  rm -f $AAOFF
fi
_wmsg=
if [ $_wo = 1 ] || [ $_won = 1 ]; then
  if wide_supported || { [ ! -L "$SYSORIG" ] && [ -d "$SYSORIG" ]; } || { [ ! -L "$WIDEOFF" ] && [ -f "$WIDEOFF" ]; }; then
    if [ $_wo = 1 ]; then
      [ -L "$WIDEOFF" ] && rm -f "$WIDEOFF"
      _wchg=0; [ -f "$WIDEOFF" ] || _wchg=1
      [ "${WIDEOFF%/*}" != "$WIDEOFF" ] && [ -n "${WIDEOFF%/*}" ] && bbx mkdir -p "${WIDEOFF%/*}" 2>/dev/null
      : > "$WIDEOFF"
      if wide_restore; then _wmsg="와이드스크린(1920x720) 끔"
      else _wmsg="와이드스크린(1920x720) 끔(일부 설정 되돌리지 못함)"; fi
      [ $_wchg = 1 ] && notice "Korea Projection: $_wmsg"
    elif [ $_won = 1 ]; then
      _wchg=0; [ -f "$WIDEOFF" ] && _wchg=1
      rm -f "$WIDEOFF"
      if wide_apply; then _wmsg="와이드스크린(1920x720) 켬"
      else _wmsg="와이드스크린(1920x720) 켬(일부 설정 적용 실패)"; fi
      [ $_wchg = 1 ] && notice "Korea Projection: $_wmsg"
    fi
  fi
fi
# 표준입력의 마지막 $1줄만 내면서 휴대폰 블루투스 주소(MAC)와 IP 주소를 x로 지운다(busybox tail 대신 awk)
lastmask() {
  # n = n + 0: 오래된 busybox awk에서 -v 값이 문자열로 비교되지 않게 숫자로 만든다
  $BB awk -v n="$1" 'BEGIN { n = n + 0 } { a[NR % n] = $0 }
    END { s = NR > n ? NR - n + 1 : 1
      for (i = s; i <= NR; i++) { l = a[i % n]
        gsub(/[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]/, "xx:xx:xx:xx:xx:xx", l)
        gsub(/[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*/, "x.x.x.x", l)
        gsub(/[Ff][Ee]80:[0-9A-Fa-f:]*/, "fe80:x", l)
        print l } }'
}
# 분석용 로그(3-log.txt): 서비스 로그, 자동 설정 기록, HMG-API 로그.
# 1.7.0: 폰 프로젝션·카플레이·계기판·음악 logcat과 디버그 로그(cp.log, 켜져 있을 때만)도 넣는다. 이 칸들은 KPMASK로
# 폰 이름·MAC·IP·전화번호를 가린다. 가리기 awk가 안 되는 busybox면 넣지 않는다.
logs() {
  echo "# Korea Projection 로그 ($(date '+%Y-%m-%d %H:%M'))"
  echo "제품: $(getprop ro.build.product), 패키지 $(pver $APP/NEMESIS.data)"
  echo "휴대폰 이름, 블루투스 주소, IP 주소, 전화번호는 가렸습니다. 첨부하기 전에 한 번 읽어 보시고, 내 정보(폰 이름, 연락처 이름 등)가 보이면 그 줄을 지워 주세요."
  # 1.7.2(P-15): ap.log는 크기 제한으로 ap.log.1에 앞부분이 있을 수 있다: 둘을 이어 마지막 400줄
  echo; echo "== ${APLOG##*/}"
  if [ -f $APLOG ]; then $BB cat $APLOG.1 $APLOG 2>/dev/null | lastmask 400; else echo "(없음)"; fi
  for _f in $NOWLAN_LOG $NOCHIP_LOG $W/map-car.txt $W/plan.txt $W/verify-map.txt $W/verify-map2.txt $W/mod-install.txt $W/mod-apply.txt $W/carreport.txt $W/app-install.log; do
    echo; echo "== ${_f##*/}"
    if [ -f $_f ]; then lastmask 400 < $_f; else echo "(없음)"; fi
  done
  rprog 20 run "로그를 모으는 중입니다(HMG-API 로그)"
  echo; echo "== HMG-API 로그 (마지막 800줄)"
  $BB cat $HMGLOG/log.log.1 $HMGLOG/log.log 2>/dev/null | lastmask 800
  rprog 30 run "로그를 모으는 중입니다(Wi-Fi)"
  echo; echo "== Wi-Fi 로그 (logcat, 마지막 300줄)"
  wifilog
  echo; echo "== 폰 프로젝션 로그 (안드로이드 오토·무선 폰 프로젝션·블루투스, logcat, 마지막 400줄)"
  echo "폰 이름·MAC·IP는 가렸습니다. 첨부하기 전에 한 번 읽어 보시고, 폰 이름이 보이면 그 줄을 지워 주세요."
  rprog 40 run "로그를 모으는 중입니다(폰 프로젝션)"
  pplog
  rprog 55 run "로그를 모으는 중입니다(카플레이·길안내·차량 데이터, 시간이 조금 걸립니다)"
  echo; echo "== 연결·차량 데이터 로그 (카플레이·계기판 길안내·차량 속도·기어·전화·음악, logcat, 마지막 3000줄)"
  echo "같은 내용이 연달아 나오면 한 줄로 줄이고 앞에 [xN](N번 반복)을 붙였습니다. 위치(좌표·교차로·목적지 이름)는 [가림: 위치]로 바꿨습니다."
  cplog
}
# 1.7.0: 디버그 로그(cp.log, 차주가 켰을 때만)는 운행 기록이라 공개 이슈에 붙는 3-log.txt에 넣지 않는다(CLAUDE.md 5장,
# 리뷰 H1). USB에 따로 4-debug-private.txt로 두고 "공개 첨부 금지"를 맨 위에 적는다. 마지막 8000줄만 먼저 자른 뒤
# KPMASK로 가린다(리뷰 M2: 6MB 전체를 가리면 오래 걸린다). 가리기 awk가 안 되면 만들지 않는다.
privlog() {
  echo "# Korea Projection 디버그 로그 (비공개)"
  echo
  echo "**이 파일(KoreaProjection-private 폴더)은 GitHub 이슈에 올리지 마세요.** 운행 기록(길안내·음악 등)이 들어 있습니다."
  echo "필요할 때 개발자에게 따로(카톡·메일) 보내 주세요. 폰 이름·MAC·IP·전화번호는 가렸지만, 모든 꼴을 장담하지는 못합니다."
  echo
  $BB cat $W/cp.log.1 $W/cp.log 2>/dev/null | $BB awk -v n=8000 'BEGIN { n = n + 0 } { a[NR % n] = $0 } END { s = NR > n ? NR - n + 1 : 1; for (i = s; i <= NR; i++) print a[i % n] }' | $BB awk "$KPMASK"
}
# 1.7.0(소유자 결정 2026-11-08): Launch는 폰 프로젝션과 관련된 기록을 가능한 모두 모은다. 카플레이(iAP2·DiPO·CarPlay),
# 계기판·HUD 길안내(NavigationCluster·ClusterService·Navi), 폰에 보내는 차량 데이터(속도 VehicleInfoManager·SystemService,
# 기어 PgsService·LocationInfoManager, 조향 후보 vhandler), 전화(BluetoothHfDevice·BTCMListenerManager·Telecom 쪽),
# 음악(MediaStatus·MusicStreaming·AVRCP·A2DP). 태그는 니로 logcat에서 실제로 나온 이름이다.
# 잡음(DROP, pcm_write, getCANStatus)은 버리고, 같은 내용(앞 두 칸 시각 제외)이 연달아 나오면 한 줄과 [xN]으로 줄인다(괄호 안을 ASCII 한 낱말로: KPMASK가 이름으로 보지 않게).
# KPMASK로 가린다: 폰·연락처 이름, 번호, MAC, IP, 그리고 위치는 줄을 남긴 채 [가림: 위치]·[가림: 좌표]로 바꾼다(소유자 결정).
CPTAGS=' [VDIWEF]/(iAP2|Iap2Service|CarPlay_|CarPlayService|TccCarPlay|DiPOManager|DiPOService|NavigationCluster|ClusterService|ClusterManager|Navi|NaviPopupService|VehicleInfoManager|SystemService|PgsService|vhandler|BCMService|MicomAudioService|MediaStatus|MusicStreaming|MediaGate|MediaFocusControl|SplitScreenViewMedia|SplitBtAudioManager|AvrcpControllerService|MobisAvrcpControllerService|BluetoothAvrcpCT|BluetoothA2dp|A2dpStateMachine|BTA_BT_PLAYER_MANAGER|BluetoothHfDevice|HfDeviceBTCMSppApi|BTCMListenerManager|BTCMService|CallManager|InCallService|Telecom|TelephonyManager) *\('
# 연달아 같은 내용(시각 두 칸을 뺀 나머지)이면 한 줄로: 마지막 것과 횟수를 남긴다
cpdedup() {
  $BB awk '{ k = $0; sub(/^[^ ]+ [^ ]+ /, "", k)
    if (k == pk) { c++; last = $0; next }
    if (NR > 1) print (c > 1 ? "[x" c "] " : "") last
    pk = k; c = 1; last = $0 }
    END { if (NR > 0) print (c > 1 ? "[x" c "] " : "") last }'
}
cplog() {
  echo "x" | $BB awk "$KPMASK" >/dev/null 2>&1 || { echo "(이 내비의 busybox로는 가릴 수 없어 넣지 않음)"; return 0; }
  # 디버그 로그의 DROP과 달리 교차로 이름 줄은 버리지 않는다(위치는 KPMASK가 가린다, 반복은 cpdedup이 줄인다)
  _cd='iAPSendMessage\(\) : done with \(0x00\)|iAPSendMessage Command Received|getCANSTatus = true|getCANStatus|pcm_write failed'
  echo x | $BB grep -E "$_cd" >/dev/null 2>&1; [ $? -le 1 ] || _cd='^$'
  logcat -d -v time 2>/dev/null | $BB grep -E "$CPTAGS" | $BB grep -v -E "$_cd" \
    | cpdedup | $BB awk -v n=3000 'BEGIN { n = n + 0 } { a[NR % n] = $0 } END { s = NR > n ? NR - n + 1 : 1; for (i = s; i <= NR; i++) print a[i % n] }' \
    | $BB awk "$KPMASK" | lastmask 3000
}
# 1.7.0: 폰 프로젝션 전체 기록. AA를 시도한 직후(2분 안에) Launch를 눌러야 버퍼에 남아 있다.
# 태그 + 메시지 낱말로 고르고, KPMASK로 가린다. 가리기 awk가 안 되는 busybox면 아무 줄도 내지 않는다.
# 1.7.1: ModeManagerService는 경고·오류(W/E)만 넣는다. V·I·D(isForegroundPackage 등 반복)가 400줄의 80% 넘게 차지해
# 이 칸이 1분도 못 덮었다(#23·#15 1.7.0 리포트). "phoneprojection" 낱말로 PPKEYS에도 걸리므로 따로 뺀다.
# AA 단계 자체는 서비스가 ap.log에 계속 남긴다(aa_events).
PPTAGS=' [VDIWEF]/(AAProjection|PhoneProjection|WifiP2pService|BluetoothSocket|BluetoothServerSocket|bt-rfcomm|HfDeviceBTCMSppApi|BTCMService) *\(| [WE]/ModeManagerService *\('
PPNOISE=' [VDI]/ModeManagerService *\('
PPKEYS='[Pp]rojection|[Aa]ndroid ?[Aa]uto|[Rr][Ff][Cc][Oo][Mm][Mm]|WifiStart|WifiInfo|Already AA'
pplog() {
  echo "x" | $BB awk "$KPMASK" >/dev/null 2>&1 || { echo "(이 내비의 busybox로는 가릴 수 없어 넣지 않음)"; return 0; }
  logcat -d -v time 2>/dev/null | $BB grep -E "$PPTAGS|$PPKEYS" | $BB grep -v -E "$PPNOISE" | $BB awk "$KPMASK" | lastmask 400
}
# Wi-Fi 서비스·드라이버·핫스팟 쪽 logcat(1.5.4: 그랜저 하이브리드 #12에서 핫스팟이 30초마다 끊긴 원인을 보려고).
# 지금 logcat 버퍼에 남은 것만 본다(-d). Wi-Fi 이름·비밀번호·주변 네트워크·기기 이름이 나올 수 있는 줄은
# 통째로 버린다(ssid, psk, pass, name, bssid, extra:가 들어간 줄. NetworkInfo의 extra:에는 SSID가 들어간다).
# key는 버리지 않는다: hostapd의 "pairwise key handshake completed"가 연결 성공을 보여 준다. MAC·IP는 lastmask가 지운다.
# 전역 IPv6 주소는 지우지 못한다(이 차의 핫스팟은 IPv4만 쓴다). 첨부 전에 차주가 읽어 보도록 안내문이 있다.
WIFITAGS=' [VDIWEF]/(WifiStateMachine|WifiService|WifiController|WifiHW|WifiNative[^ (]*|SoftapController|SoftApController|wpa_supplicant|hostapd|Tethering|NetworkManagementService|CommandListener|bcmdhd|dhd) *\('
WIFIDROP='ssid|psk|pass|name|bssid|extra:'
wifilog() {
  logcat -d -v time 2>/dev/null | $BB grep -E "$WIFITAGS" | $BB grep -v -i -E "$WIFIDROP" | lastmask 300
}

# 1.7.2(P-8·P-12): 연결 진단 줄. 숫자·짧은 영문 값만 넣는다(SSID·비밀번호·폰 이름·MAC·IP 없음).
# logcat은 한 번만 읽어(-d) 순정 WifiService의 "Last mode:"·"[Feature]" 줄(마지막 것, 영문·괄호만 남김)과 계기판 곡 제목 확인
# 줄의 개수만 센다(줄 내용은 넣지 않는다). 부팅 로그는 버퍼가 짧아 대개 남지 않는다("버퍼에 없음").
diag() {
  echo "## 연결 진단 (숫자·짧은 값만)"
  logcat -d -v time 2>/dev/null | $BB awk '
    function clean(s) { gsub(/[^A-Za-z0-9 (),.\/-]/, "", s); return substr(s, 1, 120) }
    / [VDIWEF]\/WifiService *\(/ && index($0, "Last mode: ") > 0 { lm = clean(substr($0, index($0, "Last mode: ") + 11)) }
    / [VDIWEF]\/WifiService *\(/ && index($0, "[Feature] ") > 0 { ft = clean(substr($0, index($0, "[Feature] ") + 10)) }
    index($0, "getOpState::mode = DIPO") > 0 { c1++ }
    index($0, "updateClusterInfo::mode = DIPO") > 0 { c2++ }
    index($0, "updateClusterWithArtistInfo") > 0 { c3++ }
    index($0, "updateFilename") > 0 { c4++ }
    index($0, "PIO / OPIO model doesn") > 0 { c5++ }
    index($0, "Cluster New Protocol") > 0 { c6++ }
    index($0, "Ignore invalid TP Mode") > 0 { c7++ }
    END {
      print "- 순정 부팅 AP 복구(WifiService Last mode): " (lm == "" ? "버퍼에 없음" : lm)
      print "- 순정 Wi-Fi 기능 판정(WifiService [Feature]): " (ft == "" ? "버퍼에 없음" : ft)
      print "- 계기판 곡 제목 확인 줄 수(logcat): getOpState DIPO " c1 + 0 ", updateClusterInfo DIPO " c2 + 0 ", updateClusterWithArtistInfo " c3 + 0 ", updateFilename " c4 + 0 ", PIO/OPIO TP 안 보냄 " c5 + 0 ", Cluster New Protocol " c6 + 0 ", invalid TP Mode " c7 + 0
    }'
  _ss=; _su=
  [ -f $W/svc.start ] && read _ss _su < $W/svc.start
  if [ -n "$_ss" ] && [ "$_ss" = "$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)" ]; then
    echo "- 우리 서비스 시작: 부팅 뒤 ${_su}초(이번 부팅 처음 시작)"
  else
    echo "- 우리 서비스 시작: 이번 부팅 기록 없음"
  fi
  # HMG-API 로그(두 파일)에서: 브리지가 순정 AP가 이미 켜져 있다고 본 횟수, 모드의 AA 훅 "N of M"(프로세스별 마지막 것)
  # 1.7.2(P-7): 우리 AP가 돌고 있어 브리지가 순정 AP 켜기를 건너뛴 횟수(새 모드의 줄, 개수만)도 따로 센다
  $BB cat $HMGLOG/log.log.1 $HMGLOG/log.log 2>/dev/null | $BB awk '
    index($0, "hotspot already up (mode 2)") > 0 { up++ }
    index($0, "our hotspot already up, stock AP-on skipped") > 0 { sk++ }
    index($0, "Android Auto AP hooks in ") > 0 {
      s = substr($0, index($0, "Android Auto AP hooks in ") + 25); i = index(s, ": "); if (i == 0) next
      p = substr(s, 1, i - 1); gsub(/[^A-Za-z0-9._]/, "", p); v = substr(s, i + 2); sub(/ *\(.*/, "", v); gsub(/[^0-9a-z ]/, "", v)
      if (!(p in h)) o[++k] = p; h[p] = substr(v, 1, 12) }
    END {
      print "- HMG-API hotspot already up (mode 2): " up + 0 "번(HMG-API 로그 전체)"
      print "- HMG-API 순정 AP 켜기 건너뜀(our hotspot already up, stock AP-on skipped): " sk + 0 "번(HMG-API 로그 전체)"
      r = ""; for (j = 1; j <= k; j++) r = r (j > 1 ? ", " : "") o[j] " " h[o[j]]
      print "- HMG-API Android Auto AP 훅: " (r == "" ? "기록 없음" : r) }'
  _au=$(conf_auth $SRC)
  echo "- softap.conf 인증 종류 값(카플레이 SSID 다음 정수, 니로 4): ${_au:-읽지 못함}"
  echo "- 무선 모드 기록: mod.ours $(yn [ -f $BK/mod.ours ]), mod.pin $(yn [ -f $BK/mod.pin ])"
  # AA 문 3(canStartConnection) 진단: Settings.System androidauto_information(_dr1·_dr2). 값은 영문·숫자 8자까지만 (-1 부호 유지)
  _zwarn=
  _sys3() {
    _r3=
    for _k in "$1" "${1}_dr1" "${1}_dr2"; do
      _v=$(settings get system "$_k" 2>/dev/null | $BB awk '{ gsub(/[^0-9A-Za-z-]/, ""); print substr($0, 1, 8); exit }')
      [ "$2" = warn ] && [ "$_v" = 0 ] && _zwarn="$_zwarn${_zwarn:+, }$_k=0"
      _r3="$_r3${_r3:+ / }${_v:-없음}"
    done
  }
  _sys3 androidauto_information warn
  echo "- AA 설정값(androidauto_information / _dr1 / _dr2): $_r3"
  _dp=${prod:-$(getprop ro.build.product 2>/dev/null)}
  # 비대상 차종(CARS_WIDE 외)은 추가 settings 호출과 와이드 진단 줄을 내지 않는다(기존 동작·속도 유지)
  if car_in "$_dp" "$CARS_WIDE" || { [ ! -L "$SYSORIG" ] && [ -d "$SYSORIG" ]; } || { [ ! -L "$WIDEOFF" ] && [ -f "$WIDEOFF" ]; }; then
    _sys3 carplay_information warn
    echo "- 카플레이 설정값(carplay_information / _dr1 / _dr2): $_r3"
    _ds=$(getprop ro.device.splitscreen 2>/dev/null | $BB awk '{ gsub(/[^0-9A-Za-z._-]/, ""); print substr($0, 1, 24); exit }')
    _st=$(getprop ro.product.opt.stepofspec 2>/dev/null | $BB awk '{ gsub(/[^0-9A-Za-z._-]/, ""); print substr($0, 1, 24); exit }')
    _up=$(getprop ro.product.opt.useppsettings 2>/dev/null | $BB awk '{ gsub(/[^0-9A-Za-z._-]/, ""); print substr($0, 1, 24); exit }')
    _wide_off() { [ ! -L "$WIDEOFF" ] && [ -f "$WIDEOFF" ]; }
    echo "- 와이드스크린 설정: 끄기 파일(kp-wide-off) $(yn _wide_off), ro.device.splitscreen=${_ds:-없음}, ro.product.opt.stepofspec=${_st:-없음}, ro.product.opt.useppsettings=${_up:-없음}"
    _sys3 carplay_ss_osd
    echo "- 카플레이 분할화면(carplay_ss_osd / _dr1 / _dr2): $_r3"
    _sys3 androidauto_ss_osd
    echo "- AA 분할화면(androidauto_ss_osd / _dr1 / _dr2): $_r3"
    _sys3 phoneprojection_setting_enable_usb_cable
    echo "- 통합 유선 설정(phoneprojection_setting_enable_usb_cable / _dr1 / _dr2): $_r3"
    _sys3 phoneprojection_setting_use_split_screen
    echo "- 통합 분할화면(phoneprojection_setting_use_split_screen / _dr1 / _dr2): $_r3"
    _so_list=
    if [ ! -L "$SYSORIG" ] && [ -d "$SYSORIG" ]; then
      case $- in *f*) _sdf=1; set +f ;; *) _sdf=0 ;; esac
      for _sf in "$SYSORIG"/*; do
        [ ! -L "$_sf" ] && [ -f "$_sf" ] || continue
        _sk=$($BB printf '%s\n' "${_sf##*/}" | $BB awk '{ gsub(/[^0-9A-Za-z_]/, ""); print substr($0, 1, 64); exit }')
        [ -n "$_sk" ] || continue
        _so=; _sa=
        read _so _sa < "$_sf" 2>/dev/null
        _so=$($BB printf '%s\n' "$_so" | $BB awk '{ gsub(/[^0-9A-Za-z-]/, ""); print substr($0, 1, 8); exit }')
        _sa=$($BB printf '%s\n' "$_sa" | $BB awk '{ gsub(/[^0-9A-Za-z-]/, ""); print substr($0, 1, 8); exit }')
        _so_list="$_so_list${_so_list:+, }$_sk=${_so:-?}->${_sa:-?}"
      done
      [ $_sdf = 1 ] && set -f
    fi
    echo "- 시스템 설정 백업(sys.orig): ${_so_list:-없음}"
  fi
  [ -n "$_zwarn" ] && echo "- **주의: 헤드유닛 프로젝션 설정이 꺼져 있습니다($_zwarn). 유선·무선 연결이 모두 막히므로 내비 설정에서 켜 주세요(kp-aa-off와 다름).**"
  # P-12: Wi-Fi 칩 없음 판정과 순정 기준(module_version 3 = 하드웨어 없음) 근거 한 줄(hotspot.sh wifi_record가 남김)
  _nr=$($BB grep '^판정 근거: ' $NOCHIP_LOG $BK/nochip-wifi.txt 2>/dev/null | $BB awk '{ sub(/^[^:]*nochip-wifi\.txt:/, ""); l = $0 } END { print l }')
  echo "- Wi-Fi 칩 없음 기록(wifi.nochip): $(yn [ -f $BK/wifi.nochip ]), 다시 확인함(nochip.rechk): $(yn [ -f $BK/nochip.rechk ]), ${_nr:-판정 근거: 기록 없음}"
}

report() {
  prod=$(getprop ro.build.product)
  echo "# Korea Projection 리포트"
  echo
  # 1.7.0: 설치는 끝났지만 재부팅 전에 만든 리포트(#41·#48)는 맨 위에 알린다
  if $BB grep -q '^state=reboot$' $PROG 2>/dev/null \
    && [ "$($BB awk -F= '$1 == "boot" { print $2 }' $PROG 2>/dev/null)" = "$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)" ]; then
    echo "**아직 재부팅하지 않았습니다. 내비를 재부팅한 뒤 리포트를 다시 만들어 주세요.**"
    echo
  fi
  echo "첨부하기 전에 읽어 보세요. 이름, 버전, 예/아니요, 개수만 들어 있습니다"
  echo "(SSID, 비밀번호, 휴대폰 이름, MAC, IP 주소는 없습니다)."
  echo "제보: $ISSUES"
  echo
  echo "## 내비(헤드유닛)"
  echo "- 펌웨어 (NEMESIS os): $prod"
  echo "- targetdir (NEMESIS models): $(getprop ro.mobis.targetdir)"
  echo "- onebin: $(getprop ro.mobis.onebindir)"
  echo "- 이 패키지 버전: $(pver $APP/NEMESIS.data)"
  echo "- 설치 진행: $($BB awk -F= '$1 == "state" || $1 == "pct" || $1 == "stage" { printf "%s=%s  ", $1, $2 }' $PROG 2>/dev/null)"
  if car_in "$prod" "$CARS_OK"; then echo "- 확인된 차: 예"
  elif car_in "$prod" "$CARS_TRY"; then echo "- 확인된 차: 시험 지원 (이 차용 설정이 패키지에 있음, 결과를 알려 주세요)"
  elif car_in "$prod" "$CARS_AUTO"; then echo "- 확인된 차: 자동 설정 (HMG-API가 차에서 지도를 만들어 설정, 결과를 알려 주세요)"
    for _f in automap.bad automap.checked automap.foreign; do [ -f $BK/$_f ] && echo "  - 기록: $_f"; done
  else echo "- 확인된 차: 아니요 (서비스가 대기만 함, 지원 차: $CARS)"; fi
  echo "- NEMESIS: $(nemesis version 2>/dev/null)"
  # 따옴표 없이: 두 줄이 한 줄로 합쳐진다
  echo "- HMG-API:" $($BB grep -E '^(version|build) ' /data/hmgapi/installed.txt 2>/dev/null)
  echo "- wireless.projection 설치: $(yn [ -d /data/nemesis/apps/wireless.projection ])"
  echo "- HMG-API 무선 모드: 설치 $(mod_state) / 켜짐 $(mod_on_state) / 무선 카플레이 설정(bridge) $(bridge_state)"
  echo "- 무선 모드 판: 차 $(mod_ver) / 패키지 $MOD_VER"
  _mh=$(modhooks_state)
  case "$_mh" in
    on) echo "- 무선 모드 훅(마지막 부팅 기록): 켜짐" ;;
    off*) echo "- 무선 모드 훅(마지막 부팅 기록): **안 켜짐** (HMG-API: ${_mh#off })" ;;
    *) echo "- 무선 모드 훅(마지막 부팅 기록): 기록 없음" ;;
  esac
  if mod_pending; then
    echo ""
    # 1.7.2(P-18): 할 일로 쓴다. 바꾸기는 부팅 2분 뒤(서비스가 다시 시작돼도 부팅 기준)에 돈다(#60 K3).
    echo "**할 일: 내비를 재부팅하고 3분 기다린 뒤 한 번 더 재부팅해 주세요.** 그러면 무선 모드가 새 판($MOD_VER)으로 바뀌니, 리포트를 다시 만들어 주세요."
    echo ""
  fi
  mod_foreign && echo "  - 이 모드는 한국 차용이 아닙니다(Korea Projection이 넣은 것 아님). HMG-API 앱에서 지우고 적용·재부팅하면 한국 차용 모드 설치를 시도합니다"
  echo "- HMG-API 훅(마지막 부팅 기록): $(hooks_state)"
  echo
  echo "## 무선 기능 (pm list features)"
  # 이름 뒤에 줄바꿈을 붙여 android.hardware.wifi가 ...wifi.direct와 섞이지 않게 한다
  feats="$(pm list features 2>/dev/null)
"
  for f in com.hkmc.software.connectivity.carplay_wireless com.hkmc.software.connectivity.androidauto_wireless \
           com.hkmc.software.wifihotspot android.hardware.wifi; do
    case "$feats" in *"feature:$f
"*) echo "- $f: 예" ;; *) echo "- $f: 아니요" ;; esac
  done
  for p in persist.ium.support persist.wifi.state persist.sys.iap2.wifi persist.iap2.iden.wireless persist.service.adb.tcp.enable; do
    echo "- $p=$(getprop $p)"
  done
  echo
  echo "## Wi-Fi"
  echo "- Wi-Fi 장치(wlan0): $(yn [ -d /sys/class/net/wlan0 ])"
  echo "- 순정 hostapd: $(yn [ -x /system/bin/hostapd ]), dnsmasq: $(yn [ -x /system/bin/dnsmasq ])"
  echo "- Wi-Fi 설정(wifi_on): $(settings get global wifi_on 2>/dev/null), 순정 AP 저장값(wifi_ap_on): $(settings get global wifi_ap_on 2>/dev/null)"
  # 1.7.2(P-7): 서비스가 wifi_ap_on을 1에서 0으로 바꾼 기록(원래 값, 숫자만). 없으면 바꾼 적 없음(또는 되돌림)
  _apo=$(cat $APON_ORIG 2>/dev/null); case "$_apo" in ''|*[!0-9]*) _apo=없음 ;; esac
  echo "- 순정 AP 저장값을 우리가 바꿈(wifi_ap_on.orig): $(if [ "$_apo" = 없음 ]; then echo 아니요; else echo "예, 원래 값 $_apo"; fi)"
  parse_conf $SRC
  echo "- softap.conf: $(yn [ -s $SRC ]), 찾은 문자열 ${NS:-0}개, 카플레이 SSID 길이 ${#S2}, 비밀번호 길이 ${#S4}"
  echo "- 우리 hostapd: $(yn running "hostapd $CONF"), 우리 DHCP: $(yn our_dhcp_on)"
  echo "- 다른 hostapd (순정 핫스팟): $(yn stock_ap_on)"
  # 1.6.2: 순정 hostapd의 SSID가 카플레이용(carplay)인지 일반 핫스팟(hotspot)인지. 값은 비교만 한다.
  _rs=$(stock_ssid)
  echo "- 무선 카플레이 AP: ap_mode=$(ap_mode $_rs) (순정 hostapd 판정: $_rs, 순정 카플레이 AP 기록: $(yn [ -f $BK/stockap.seen ]))"
  echo "- wpa_supplicant: $(yn running wpa_supplicant)"
  echo "- 지금 카플레이 연결 수: $(cp_count)"
  if [ -f $AAOFF ]; then _aas="꺼짐(USB kp-aa-off로 끔)"; else _aas="켜짐(기본)"; fi
  echo "- 무선 안드로이드 오토: $_aas, 모드에 알린 신호 $(getprop $AAPROP 2>/dev/null) (이유: $(_aw=$(cat $AAWHY 2>/dev/null); if [ -n "$_aw" ]; then aa_why_text $_aw; else echo 기록 없음; fi))"
  echo
  diag
  echo
  echo "## 순정 파일 체크섬 (새 차 추가용)"
  echo "무선 모드의 패치 세트(patches/<차>/stock)를 만드는 데 씁니다. 차종·펌웨어마다 같은 값이라 개인정보가 아닙니다."
  echo '```'
  # 큰 apk의 md5는 몇 초 걸린다: 리포트를 USB에 남길 때만 계산해 화면이 늦게 뜨지 않게 한다
  usb_in || echo "(USB를 꽂은 채 Launch를 누르면 채워집니다)"
  usb_in && for f in $SYSAPP/HKMC_DiPO.apk $SYSAPP/HKMC_DiPO.odex $SYSAPP/HKMC_GPM.apk $SYSAPP/HKMC_GPM.odex \
           $SYSAPP/HKMC_Navi_ExSL.apk $SYSAPP/HKMC_Navi_ExSL.odex $SYSAPP/Iap2ServerApp.apk $SYSAPP/Iap2ServerApp.odex \
           $SYSLIB/libautoreceiver_infobank.so $SYSLIB/libCarPlayCore.so $SYSLIB/libCarPlayAudio.so \
           $SYSLIB/libCarPlayUtils.so $SYSAPP/HKMC_BtSettings.apk; do
    # 모드가 바꾼 파일은 HMG-API가 순정 원본을 /data/hmgapi/stock<경로>에 둔다(CarMap과 같은 방식): 그것을 쓴다
    if [ -f $HMGSTOCK$f ]; then set -- $($BB md5sum < $HMGSTOCK$f); echo "${f##*/} $1 (HMG-API 순정 백업)"
    elif [ -f $f ]; then set -- $($BB md5sum < $f); echo "${f##*/} $1"; else echo "${f##*/} 없음"; fi
  done
  _fx=$SYSONE/$(getprop ro.mobis.onebindir)/featurexml.cfg
  if ! usb_in; then :
  elif [ -f $HMGSTOCK$_fx ]; then set -- $($BB md5sum < $HMGSTOCK$_fx); echo "featurexml.cfg $1 (HMG-API 순정 백업)"
  elif [ -f $_fx ]; then set -- $($BB md5sum < $_fx); echo "featurexml.cfg $1 (모드가 바꿨을 수 있음)"; else echo "featurexml.cfg 없음"; fi
  echo '```'
  echo
  L=$APLOG
  # 1.5.6: 5GHz 연결이 얼마나 유지되는지 보려고 Wi-Fi·카플레이 연결 기록만 따로 모아 보인다(기기 주소 없음)
  # 1.7.2(P-17): 이번 부팅(또는 이번 설치) 뒤의 줄만: 서비스가 첫 시작 때 남기는 "$SVC_MARK" 줄 뒤만 본다.
  # 그 줄이 없으면(업데이트 전 기록뿐) 아무 줄도 보이지 않는다. ap.log.1(크기 제한으로 민 앞부분)도 이어서 본다.
  echo "## Wi-Fi·카플레이 연결 기록 (ap.log에서, 이번 부팅·설치 뒤, 마지막 40줄)"
  echo "- 지금 핫스팟 채널: $($BB awk -F= '$1 == "channel" { c = $2 } $1 == "hw_mode" { m = $2 } END { print (c == "" ? "알 수 없음" : c " (hw_mode=" m ")") }' $CONF 2>/dev/null || echo 알 수 없음) (설정 파일 값, 실제 채널은 아래 'AP 채널' 줄)"
  echo '```'
  [ -f $L ] && $BB cat $L.1 $L 2>/dev/null | $BB grep -E "Wi-Fi: |카플레이 연결 [0-9]|hostapd 시작|$SVC_MARK" \
    | $BB awk -v m="$SVC_MARK" -v r="$([ -f $L.1 ] && echo 1)" 'index($0, m) > 0 { n = 0; f = 1; next } { n++; l[n % 40] = $0 } END { if (!f) { if (r == 1 && n > 0) print "(이번 부팅 표시 줄이 기록 회전으로 밀려남: 마지막 줄들)"; else exit } s = n > 40 ? n - 39 : 1; for (i = s; i <= n; i++) print l[i % 40] }'
  echo '```'
  echo
  echo "## 서비스 로그 (ap.log 마지막 20줄)"
  echo '```'
  [ -f $L ] && { $BB tail -n 20 $L 2>/dev/null || cat $L; }
  echo '```'
  echo
  echo "_만든 시각 $(date '+%Y-%m-%d %H:%M')_"
}

# 상태 화면 앱(StatusActivity)이 읽는 key=value 파일. 앱은 root가 아니므로 누구나 읽을 수 있게(644)
# /data/local/tmp 바로 아래에 둔다. 값은 예/아니요·버전·개수·길이뿐이다 (SSID, 비밀번호, 휴대폰 이름, MAC, IP 없음).
STATUS=${STATUS:-/data/local/tmp/korea-projection-status.txt}
yesno() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }
# HMG-API 무선 모드의 상태는 HMG-API 자기 파일로 본다(NEMESIS 목록은 wireless.projection과 충돌하면 등록되지 않고,
# 모드를 꺼도 남는다). /data/hmgapi/mods/<id>/mod.json: 설치, .disabled: 꺼짐,
# /data/hmgapi/settings/<id>.json의 "bridge":false: 무선 카플레이(블루투스 브리지) 설정 꺼짐 (Mods.java, settings.json)
HMGMOD=${HMGMOD:-/data/hmgapi/mods/wireless-carplay-aa}
HMGSET=${HMGSET:-/data/hmgapi/settings/wireless-carplay-aa.json}
mod_state() { yesno [ -f $HMGMOD/mod.json ]; }
# mod_on은 "꺼 두지 않았다"는 뜻일 뿐이다. HMG-API가 충돌·미지원으로 건너뛴 경우는 훅·무선 기능 값으로 드러난다.
# bridge는 저장된 설정 값이라 Apply changes 전에는 실제 동작과 다를 수 있다.
mod_on_state() { if [ -f $HMGMOD/mod.json ] && [ ! -f $HMGMOD/.disabled ]; then echo yes; else echo no; fi; }
bridge_state() { if $BB grep -q '"bridge" *: *false' $HMGSET 2>/dev/null; then echo off; else echo on; fi; }
# HMG-API가 부팅 때마다 남기는 "hook map: <상태> for …, hooks on|off" 줄 중 마지막 것 (log.log.1이 더 오래됨).
# 출력: "on|off <상태>" (상태: none, mismatch, mapped, verified 등). 줄이 없으면 빈 값.
# 이번 부팅의 줄을 놓치면 지난 부팅 기록일 수 있다(HMG-API 로그는 logcat에서 옮겨 적는다).
# map-check.json은 HMG-API 업데이트로 지도가 바뀌어도 ok로 남을 수 있어 로그를 본다.
HMGLOG=${HMGLOG:-/data/hmgapi/logs/hmgapi}
# 1.7.2: 무선 모드의 훅이 실제로 켜졌는가. HMG-API는 모드가 선언한 훅 지점이 하나라도 그 차 지도에 없으면 그 모드의 훅을
# 통째로 끄고 "mods: wireless-carplay-aa not loaded: <이유>"를 남긴다(스포티지 NQ5 260604 #46: 메뉴용 지점이 없어 무선
# 카플레이까지 꺼짐). 켜지면 "mods: loaded wireless-carplay-aa <판>". 두 로그 파일에서 마지막 줄로 판단한다.
# 출력: "on", "off <이유>", 또는 빈 값(기록 없음). 이유는 HMG-API가 남긴 영문 그대로(지점 이름뿐, 개인정보 없음), 200자까지.
modhooks_state() {
  $BB cat $HMGLOG/log.log.1 $HMGLOG/log.log 2>/dev/null | $BB awk -v id="$MOD_ID" '
    index($0, "mods: loaded " id " ") > 0 { s = "on"; w = "" }
    index($0, "mods: " id " not loaded") > 0 { s = "off"; w = $0; if (index(w, "not loaded: ") > 0 || index(w, "not loaded live: ") > 0) sub(/.*not loaded( live)?: */, "", w); else w = "(예외, 자세한 이유는 HMG-API 로그)" }
    END { if (s == "off") print "off " substr(w, 1, 200); else print s }'
}
hooks_state() {
  $BB cat $HMGLOG/log.log.1 $HMGLOG/log.log 2>/dev/null | $BB awk '
    /hook map: .*, hooks on/ { s = "on"; i = index($0, "hook map: "); w = substr($0, i + 10); sub(/[ ,].*/, "", w) }
    /hook map: .*, hooks off/ { s = "off"; i = index($0, "hook map: "); w = substr($0, i + 10); sub(/[ ,].*/, "", w) }
    END { if (s != "") print s " " w }'
}
status_kv() {
  _prod=$(getprop ro.build.product)
  _feats="$(pm list features 2>/dev/null)
"
  _has() { case "$_feats" in *"feature:$1
"*) echo yes ;; *) echo no ;; esac; }
  parse_conf $SRC
  echo "product=$_prod"
  echo "targetdir=$(getprop ro.mobis.targetdir)"
  echo "pkgver=$(pver $APP/NEMESIS.data)"
  # tested: 서비스가 동작하는 차인가 (앱은 no면 "대기 중"으로 보인다). 시험 지원 차도 yes다.
  car_in "$_prod" "$CARS" && echo "tested=yes" || echo "tested=no"
  echo "hmgapi="$($BB grep -E '^(version|build) ' /data/hmgapi/installed.txt 2>/dev/null)
  echo "nemesis=$(nemesis version 2>/dev/null)"
  echo "wp=$(yesno [ -d /data/nemesis/apps/wireless.projection ])"
  echo "mod=$(mod_state)"
  echo "modver=$(mod_ver)"
  echo "mod_pending=$(yesno mod_pending)"
  _mh=$(modhooks_state); echo "mod_hooks=${_mh%% *}"
  echo "mod_foreign=$(yesno mod_foreign)"
  echo "mod_on=$(mod_on_state)"
  echo "bridge=$(bridge_state)"
  _hk=$(hooks_state)
  echo "hooks=${_hk%% *}"
  echo "hookmap=${_hk#* }"
  echo "feat_carplay=$(_has com.hkmc.software.connectivity.carplay_wireless)"
  echo "feat_aa=$(_has com.hkmc.software.connectivity.androidauto_wireless)"
  echo "feat_wifi=$(_has android.hardware.wifi)"
  echo "wlan0=$(yesno [ -d /sys/class/net/wlan0 ])"
  echo "softap_strings=${NS:-0}"
  echo "ssid_len=${#S2}"
  echo "pass_len=${#S4}"
  echo "our_ap=$(yesno running "hostapd $CONF")"
  echo "our_dhcp=$(yesno our_dhcp_on)"
  echo "other_ap=$(yesno stock_ap_on)"
  _ks=$(stock_ssid)
  echo "stock_ssid=$_ks"
  echo "ap_mode=$(ap_mode $_ks)"
  # 이 차에서 순정 카플레이 AP를 본 적이 있는가(서비스는 그 차에서 우리 핫스팟을 켜지 않는다)
  echo "stock_seen=$(yesno [ -f $BK/stockap.seen ])"
  echo "wpa=$(yesno running wpa_supplicant)"
  echo "cp_conn=$(cp_count)"
  # 1.7.0: 설치 진행 상태(run·done·reboot·fail, 없으면 none)와 무선 안드로이드 오토(시험) 켜짐
  _ps=$($BB awk -F= '$1 == "state" { print $2 }' $PROG 2>/dev/null); echo "state=${_ps:-none}"
  echo "aa=$(yesno [ ! -f $AAOFF ])"
  # 1.7.0: 이번 부팅에 Wi-Fi 장치(wlan0)가 생기지 않아 핫스팟을 못 켠 기록(hotspot.sh wlan_fail)
  echo "nowlan=$(yesno nowlan_now)"
  echo "made=$(date '+%Y-%m-%d %H:%M')"
}
( umask 022; status_kv > $STATUS.tmp 2>/dev/null && $BB chmod 644 $STATUS.tmp && $BB mv -f $STATUS.tmp $STATUS )

# 상태 화면 앱이 없으면(설치 때 실패) 여기서 다시 설치해 본다. 이어서 NEMESIS가 화면을 연다.
# 한 부팅에 한 번만 (sys.boot_completed를 바꿀 때마다 init의 부팅 완료 트리거가 다시 돌기 때문)
install_app_once

R=$W/korea-projection-report.md
G=$W/korea-projection-log.txt
# --- 1.7.0 Launch 진행 표시(소유자 결정 2026-11-08): 토스트를 쓰지 않는다 ---
# 빠른 부분(상태 파일, 1-report.md)은 여기서 바로 하고 화면을 연다. 오래 걸리는 부분(3-log.txt 로그 모으기, USB 복사,
# 비공개 디버그 로그, HMG-API Car Report)은 뒤에서(status.sh --collect) 하며 진행을 RPROG(644)에 쓴다.
# 상태 화면 앱이 1초마다 읽어 "제보 자료 저장 중 N%" 막대와 끝나면 "완료: USB를 빼셔도 됩니다"를 보인다.
RPROG=${RPROG:-/data/local/tmp/korea-projection-report-progress.txt}
RSTART=${RSTART:-$(date +%s)}
rprog() {
  ( umask 022
    $BB printf 'pct=%s\nstate=%s\nstage=%s\nstart=%s\nt=%s\nboot=%s\n' "$1" "$2" "$3" "$RSTART" "$(date +%s)" \
      "$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)" > $RPROG.tmp \
      && $BB chmod 644 $RPROG.tmp && $BB mv -f $RPROG.tmp $RPROG ) 2>/dev/null
  return 0
}
# 뒤에서 도는 로그 모으기: 끝나는 조건은 각 단계 자체(logcat -d, 파일 복사, carreport.sh의 제한 시간)다. 반복 없음.
# 이번 부팅에 살아 있는 다른 로그 모으기(status.sh --collect·--wait)가 있는가(리뷰 M1: 둘이 겹쳐 같은 파일을 쓰지 않게)
collect_alive() {
  _cp=$(cat $W/collect.pid 2>/dev/null); set -- $_cp
  [ -n "$1" ] && [ "$1" != "$$" ] && [ "$2" = "$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)" ] && [ -d /proc/$1 ] \
    && $BB grep -q status.sh /proc/$1/cmdline 2>/dev/null
}
collect() {
  collect_alive && return 0
  echo "$$ $(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)" > $W/collect.pid
  _collect
  rm -f $W/collect.pid
}
_collect() {
  rprog 10 run "로그를 모으는 중입니다(서비스·HMG-API 로그)"
  logs > $G 2>/dev/null; $BB chmod 600 $G
  rprog 75 run "USB에 저장하는 중입니다"
  where=""
  for u in $USBS; do
    # 마운트 지점 폴더는 USB가 없어도 있을 수 있다: /proc/mounts로 확인
    # 제보 자료는 USB의 한 폴더($RDIR)에 정해진 이름으로 둔다: 1-report.md, 2-car-report.json(carreport.sh), 3-log.txt
    # 예전 Launch의 2-car-report.json·4번은 지운다(새 파일과 섞이지 않게)
    # 1.7.1까지 제보 폴더에 두던 4-debug-private.txt도 지운다(1.7.2부터는 $PDIR에 둔다)
    $BB grep -q " $u " /proc/mounts 2>/dev/null && $BB mkdir -p "$u/$RDIR" && $BB rm -f "$u/$RDIR/2-car-report.json" "$u/$RDIR/4-debug-private.txt" "$u/$PDIR/4-debug-private.txt" \
      && $BB cp $R "$u/$RDIR/1-report.md" 2>/dev/null && $BB cp $G "$u/$RDIR/3-log.txt" 2>/dev/null && sync && where=$u && break
  done
  if [ -z "$where" ]; then
    rprog 100 fail "USB에 저장하지 못했습니다(USB가 빠졌거나 쓸 수 없음). USB를 다시 꽂고 Launch를 눌러 주세요."
    return 0
  fi
  # 1.7.0: 디버그 로그를 켠 차만 4-debug-private.txt(비공개)를 따로 둔다. 1.7.2: 제보 폴더가 아닌 $PDIR에.
  if [ -f $W/cp.log ] && echo "x" | $BB awk "$KPMASK" >/dev/null 2>&1; then
    rprog 80 run "디버그 로그를 저장하는 중입니다"
    $BB mkdir -p "$where/$PDIR" && privlog > "$where/$PDIR/4-debug-private.txt" 2>/dev/null; sync
  fi
  # HMG-API Car Report도 같은 폴더에 저장한다(1분쯤). 1.7.0: 늘 만든다(#41). 결과(완료·실패)는 carreport.sh가 RPROG에 쓴다.
  if command -v hmgapid >/dev/null 2>&1 && [ -f $APP/bin/carreport.sh ]; then
    rprog 85 run "HMG-API Car Report를 만드는 중입니다(약 1분). USB를 빼지 마세요."
    BB=$BB W=$W RDIR=$RDIR RPROG=$RPROG RSTART=$RSTART sh $APP/bin/carreport.sh </dev/null >/dev/null 2>&1
    $BB grep -q -E '^state=(done|fail)$' $RPROG 2>/dev/null && return 0
    # 다른 carreport.sh가 아직 USB에 쓰는 중이라(잠금) 이것이 바로 끝났다: 잠금이 풀릴 때까지(최대 약 7분) 기다린 뒤 완료라고 쓴다
    # (리뷰 M1: 쓰는 중에 "USB를 빼셔도 됩니다"가 뜨지 않게). 끝나는 조건: 잠금이 사라짐 또는 시간.
    _lw=0
    while [ -d $W/carreport.lock ] && [ $_lw -lt 210 ]; do sleep 2; _lw=$((_lw+1)); done
  fi
  rprog 100 done "완료: 제보 자료를 USB의 $RDIR 폴더에 저장했습니다. 이제 USB를 빼셔도 됩니다."
}
if [ "$1" = --collect ]; then
  collect
  exit 0
fi

report > $R 2>/dev/null
$BB chmod 600 $R
usb_in || rm -f $RPROG
# 로그 모으기는 시간이 걸려 USB가 있을 때만, 뒤에서 한다(한 번에 하나만). RPT_SYNC=1이면 여기서 바로(설치 대기 --wait, 테스트).
if usb_in; then
  if [ "${RPT_SYNC:-0}" = 1 ] || [ $WAITED = 1 ]; then
    collect
  else
    if collect_alive; then
      :   # 이미 모으는 중
    else
      rprog 5 run "제보 자료를 모으기 시작했습니다"
      BB=$BB RSTART=$RSTART $BB setsid sh $APP/bin/status.sh --collect </dev/null >/dev/null 2>&1 &
    fi
  fi
fi

# 설치가 아직 진행 중이면 끝난 뒤에 한 번 더 돌도록 뒤에 남긴다(한 번에 하나만, 이번 부팅의 것만)
if [ $WAITED = 0 ] && $BB grep -q '^state=run$' $PROG 2>/dev/null; then
  _wp=$(cat $W/wait.pid 2>/dev/null)
  if [ -z "$_wp" ] || [ ! -d /proc/$_wp ] || ! $BB grep -q status.sh /proc/$_wp/cmdline 2>/dev/null; then
    BB=$BB $BB setsid sh $APP/bin/status.sh --wait </dev/null >/dev/null 2>&1 &
    echo $! > $W/wait.pid
  fi
fi
# 상태와 저장 진행은 이어서 열리는 화면(StatusActivity)이 보여 준다. 토스트는 쓰지 않는다(1.7.0 소유자 결정).
# 표준출력에는 한 줄 요약을 남긴다(NEMESIS 기록·테스트용).
c=$(cp_count)
parse_conf $SRC
if [ "$(ap_mode)" = stock ]; then m="Korea Projection: 무선 카플레이 준비됨(내비 Wi-Fi 사용), 카플레이 연결 $c개"
else
  a=꺼짐; running "hostapd $CONF" && a=켜짐
  d=꺼짐; our_dhcp_on && d=켜짐
  m="Korea Projection: 핫스팟 $a, DHCP $d, 카플레이 연결 $c개"
fi
[ -n "$_wmsg" ] && m="$m. $_wmsg"
usb_in && m="$m. 제보 자료를 USB의 $RDIR 폴더에 저장하는 중입니다(화면에 진행이 보입니다)."
echo "$m"
exit 0
