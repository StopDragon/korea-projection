#!/system/bin/sh
# NEMESIS Manager > Korea Projection > Launch: 상태 화면용 상태 파일과 차량 제보용 리포트.
# 1.7.3(소유자 결정 2026-11-09): Launch는 상태 파일만 쓰고 화면을 연다. 제보 파일(USB의 KoreaProjection-report 폴더의
# 1-report.md, 2-car-report.json, 3-log.txt)은 상태 화면의 [제보 파일 만들기] 버튼을 눌렀을 때만 만든다
# (앱이 요청 파일을 쓰고, 이 스크립트의 감시자(--watch)나 서비스 점검(--report)이 받아 만든다).
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
# 흐름으로 상태 파일을 다시 쓴다. 1.7.3(R-1): USB에는 쓰지 않는다(제보 파일은 버튼으로만). 상태 화면 앱은 진행 막대를
# 보여 주다가 상태 파일이 새로 쓰이면 결과 화면으로 바뀐다.
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
    } 2>/dev/null > "$u/$RDIR/1-report.md"
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
    } 2>/dev/null > $_st.tmp && chmod 644 $_st.tmp 2>/dev/null && mv $_st.tmp $_st 2>/dev/null )
  # 1.7.1: 토스트는 쓰지 않는다. 앱이 있으면 화면이 안내하고, USB 저장은 알림 기록으로 화면에 보인다.
  if ! app_installed; then
    notice "Korea Projection: 이 내비에서는 아직 동작하지 않습니다(지원 조사 중). 무선 설정은 하지 않았습니다."
  elif [ "$_nbw" = 1 ]; then
    notice "Korea Projection: 제보 파일을 USB의 KoreaProjection-report 폴더에 저장했습니다."
  fi
  exit 0
fi
# 1.7.0 무선 안드로이드 오토(기본 켜짐) 끄기·켜기: Launch 때 USB 맨 위의 kp-aa-off(끔, 먼저 봄) 또는 kp-aa-on(다시 켬).
# 끌 때는 신호를 여기서 바로 내린다(켤 때는 서비스가 30초 안에 맞춘다). 토스트는 쓰지 않는다(소유자 결정): 상태 화면·리포트에 보인다.
# 1.7.3(R-9): Launch 때만 읽는다(감시자·서비스가 띄운 제보 만들기(--watch·--report)에서는 읽지 않는다).
case "$1" in --watch|--report) USBS_AA= ;; *) USBS_AA=$USBS ;; esac
for u in $USBS_AA; do
  bbx grep -q " $u " /proc/mounts 2>/dev/null || continue
  if [ -f $u/kp-aa-off ]; then
    bbx mkdir -p $BK 2>/dev/null; : > $AAOFF; aa_sig 0 off
  elif [ -f $u/kp-aa-on ]; then
    rm -f $AAOFF
  fi
  break
done
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
  for _f in $NOWLAN_LOG $NOCHIP_LOG $W/map-car.txt $W/plan.txt $W/verify-map.txt $W/verify-map2.txt $W/mod-install.txt $W/mod-apply.txt $W/mod-update.txt $W/carreport.txt $W/app-install.log; do
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
    echo "- 우리 서비스 시작: 부팅 뒤 ${_su}초(이번 부팅 처음 시작, 재부팅 없이 설치·업데이트했으면 그 뒤 첫 시작)"
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
  # AA 문 3(canStartConnection) 진단: Settings.System androidauto_information(_dr1·_dr2). 값은 영문·숫자 8자까지만
  _ai=; for _k in androidauto_information androidauto_information_dr1 androidauto_information_dr2; do
    _v=$(settings get system $_k 2>/dev/null | $BB awk '{ gsub(/[^0-9A-Za-z]/, ""); print substr($0, 1, 8); exit }')
    _ai="$_ai${_ai:+ / }${_v:-없음}"
  done
  echo "- AA 설정값(androidauto_information / _dr1 / _dr2): $_ai"
  # P-12: Wi-Fi 칩 없음 판정과 순정 기준(module_version 3 = 하드웨어 없음) 근거 한 줄(hotspot.sh wifi_record가 남김)
  _nr=$($BB grep '^판정 근거: ' $NOCHIP_LOG $BK/nochip-wifi.txt 2>/dev/null | $BB awk '{ sub(/^[^:]*nochip-wifi\.txt:/, ""); l = $0 } END { print l }')
  # 1.7.3(리뷰 L-5): 부품 없음·깨우기 횟수·순정 module_version 기록·wlan0이 안 생긴 부팅 수(숫자만)
  echo "- Wi-Fi 부품 없음 기록(wifi.nopart): $(yn [ -f $BK/wifi.nopart ]), 칩 깨우기 횟수(wifi.wake): $(set -- $(cat $BK/wifi.wake 2>/dev/null); echo ${1:-0})/$WAKE_BOOTS, 순정 module_version 기록: $(cat $BK/wifi.modver 2>/dev/null || echo 없음), wlan0 안 생긴 부팅 수: $(set -- $(cat $BK/nowlan.boots 2>/dev/null); echo ${1:-0})"
  echo "- Wi-Fi 칩 없음 기록(wifi.nochip): $(yn [ -f $BK/wifi.nochip ]), 다시 확인함(nochip.rechk): $(yn [ -f $BK/nochip.rechk ]), ${_nr:-판정 근거: 기록 없음}"
}

report() {
  prod=$(getprop ro.build.product)
  # 1.7.3(R-2): 설치 진행 중(이번 부팅 PROG state=run)에 만든 리포트는 첫 줄에 알린다. 그때는 Wi-Fi가 꺼져 있거나 wlan0이
  # 아직 없어 판정이 틀릴 수 있다(#114·#115). 앱은 설치 중에 버튼을 막지만, 서비스 백업 경로 등으로 만들어질 수 있다.
  if $BB grep -q '^state=run$' $PROG 2>/dev/null \
    && [ "$($BB awk -F= '$1 == "boot" { print $2 }' $PROG 2>/dev/null)" = "$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)" ]; then
    echo "**설치 진행 중에 만든 리포트입니다. 설치가 끝난 뒤 [제보 파일 만들기]로 다시 만들어 주세요.**"
    echo
  fi
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
  # 1.7.3(K-5): 상태 화면·QR과 같은 판정(status.sh kp_verdict)
  kp_verdict
  echo "## 판정"
  echo "- 판정: $V_CODE (수준 $V_LV) $V_MSG"
  [ -n "$V_FIRST" ] && echo "- $V_FIRST"
  echo "- $V_S1 / $V_S2 / $V_S3"
  echo
  echo "## 내비(헤드유닛)"
  echo "- 펌웨어 (NEMESIS os): $prod"
  echo "- targetdir (NEMESIS models): $(getprop ro.mobis.targetdir)"
  echo "- onebin: $(getprop ro.mobis.onebindir)"
  echo "- 이 패키지 버전: $(pver $APP/NEMESIS.data)"
  echo "- 설치 진행: $($BB awk -F= '$1 == "state" || $1 == "pct" || $1 == "stage" { printf "%s=%s  ", $1, $2 }' $PROG 2>/dev/null)"
  # 1.7.3(D-6): "확인된 차"는 공개 README 지원 표의 ✅(CARS_SEEN)로 본다
  if car_in "$prod" "$CARS_SEEN"; then echo "- 확인된 차: 예"
  elif car_in "$prod" "$CARS_TRY"; then echo "- 확인된 차: 시험 지원 (이 차용 설정이 패키지에 있음, 결과를 알려 주세요)"
  elif car_in "$prod" "$CARS_AUTO"; then echo "- 확인된 차: 자동 설정 (HMG-API가 차에서 지도를 만들어 설정, 결과를 알려 주세요)"
    for _f in automap.bad automap.checked automap.foreign; do [ -f $BK/$_f ] && echo "  - 기록: $_f"; done
  else echo "- 확인된 차: 아니요 (서비스가 대기만 함, 지원 차: $CARS)"; fi
  echo "- NEMESIS: $(nemesis version 2>/dev/null)"
  # 따옴표 없이: 두 줄이 한 줄로 합쳐진다
  echo "- HMG-API:" $($BB grep -E '^(version|build) ' ${HMGINST:-/data/hmgapi/installed.txt} 2>/dev/null)
  echo "- wireless.projection 설치: $(yn [ -d /data/nemesis/apps/wireless.projection ])"
  echo "- HMG-API 무선 모드: 설치 $(mod_state) / 켜짐 $(mod_on_state) / 무선 카플레이 설정(bridge) $(bridge_state)"
  echo "- 무선 모드 판: 차 $(mod_ver) / 패키지 $MOD_VER"
  _mh=$(modhooks_state)
  # 베타 2 #64: HMG-API 로그의 훅 줄은 마지막으로 기록이 남은 부팅 것이다(부팅 보호로 훅이 꺼진 부팅에는 새 줄이 없음).
  # 이번 부팅 zygote 커널 줄로 이번 부팅 것인지 붙인다
  case "$K_ZHOOK" in
    on) _hb="(이번 부팅 훅 켜짐)" ;;
    guard) _hb="(이번 부팅 기록 없음: 이번 부팅은 부팅 보호로 훅 꺼짐)" ;;
    off) _hb="(이번 부팅 기록 없음: 이번 부팅은 훅 꺼짐)" ;;
    *) _hb="(이번 부팅인지 모름: 커널 로그에 줄 없음)" ;;
  esac
  case "$_mh" in
    on) echo "- 무선 모드 훅(마지막 부팅 기록): 켜짐 $_hb" ;;
    off*) echo "- 무선 모드 훅(마지막 부팅 기록): **안 켜짐** (HMG-API: ${_mh#off }) $_hb" ;;
    *) echo "- 무선 모드 훅(마지막 부팅 기록): 기록 없음 $_hb" ;;
  esac
  case "$K_ZHOOK" in guard) _gl=있음 ;; on|off) _gl=없음 ;; *) _gl="모름(커널 로그에 HMG-API 줄 없음)" ;; esac
  echo "- HMG-API 부팅 보호: starts=${K_STARTS:-읽지 못함}(3 이상이면 다음 부팅 훅 꺼짐), 이번 부팅 boot guard 줄 $_gl"
  if mod_pending; then
    echo ""
    # 1.7.2(P-18): 할 일로 쓴다. 바꾸기는 부팅 2분 뒤(서비스가 다시 시작돼도 부팅 기준)에 돈다(#60 K3).
    echo "**할 일: 내비를 재부팅하고 3분 기다린 뒤 한 번 더 재부팅해 주세요.** 그러면 무선 모드가 새 판($MOD_VER)으로 바뀌니, 리포트를 다시 만들어 주세요."
    echo ""
  fi
  mod_foreign && echo "  - 이 모드는 한국 차용이 아닙니다(Korea Projection이 넣은 것 아님). HMG-API 앱에서 지우고 적용·재부팅하면 한국 차용 모드 설치를 시도합니다"
  echo "- HMG-API 훅(마지막 부팅 기록): $(hooks_state) $_hb"
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
  # 1.7.3(K-3): softap.conf·AP 판정·연결 수는 위 kp_verdict(kp_collect)가 구한 값을 다시 쓴다(두 번 읽지 않음)
  _kyn() { if [ "$1" = yes ]; then echo 예; else echo 아니요; fi; }
  echo "- softap.conf: $(yn [ -s $SRC ]), 찾은 문자열 ${NS:-0}개, 카플레이 SSID 길이 ${#S2}, 비밀번호 길이 ${#S4}"
  echo "- 우리 hostapd: $(_kyn $K_OURAP), 우리 DHCP: $(_kyn $K_DHCP)"
  echo "- 다른 hostapd (순정 핫스팟): $(_kyn $K_OTHER)"
  # 1.6.2: 순정 hostapd의 SSID가 카플레이용(carplay)인지 일반 핫스팟(hotspot)인지. 값은 비교만 한다.
  echo "- 무선 카플레이 AP: ap_mode=$K_APMODE (순정 hostapd 판정: $K_SSID, 순정 카플레이 AP 기록: $(yn [ -f $BK/stockap.seen ]))"
  echo "- wpa_supplicant: $(yn running wpa_supplicant)"
  echo "- 지금 카플레이 연결 수: $K_CP"
  if [ -f $AAOFF ]; then _aas="꺼짐(USB kp-aa-off로 끔)"; else _aas="켜짐(기본)"; fi
  echo "- 무선 안드로이드 오토: $_aas, 모드에 알린 신호 $(getprop $AAPROP 2>/dev/null) (이유: $(_aw=$(cat $AAWHY 2>/dev/null); if [ -n "$_aw" ]; then aa_why_text $_aw; else echo 기록 없음; fi))"
  echo
  diag
  # 1.7.3(H-1): HMG-API가 적용을 거절했을 때 그 이유 줄(우리 계획 기록 plan.txt의 problem 줄, 숫자·영문·경로만)
  if plan_problems | $BB grep -q .; then
    echo
    echo "## HMG-API 계획의 문제 줄 (plan.txt, 숫자·경로만)"
    echo '```'
    plan_problems
    echo '```'
  fi
  echo
  echo "## 순정 파일 체크섬 (새 차 추가용)"
  echo "무선 모드의 패치 세트(patches/<차>/stock)를 만드는 데 씁니다. 차종·펌웨어마다 같은 값이라 개인정보가 아닙니다."
  echo '```'
  # 큰 apk의 md5는 몇 초 걸린다: 리포트를 USB에 남길 때만 계산해 화면이 늦게 뜨지 않게 한다
  usb_in || echo "(USB를 꽂은 채 [제보 파일 만들기]를 누르면 채워집니다)"
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
  [ -f $L ] && $BB cat $L.1 $L 2>/dev/null | $BB grep -E "Wi-Fi: |카플레이 연결 [0-9]|hostapd 시작|이 기록을 더 남기지 않음|$SVC_MARK" \
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
# 1.7.3(K-5): 무선 모드 훅(modhooks)과 HMG-API 훅(hooks) 기록을 HMG-API 로그를 한 번만 읽어 함께 구한다(예전에는 두 번 끝까지 읽음).
# _MH: "on", "off <이유>"(200자까지) 또는 빈 값. _HK: "on|off <상태>" 또는 빈 값.
hmg_hooks_load() {
  [ "$HK_LOADED" = 1 ] && return 0
  HK_LOADED=1
  _hh=$($BB cat $HMGLOG/log.log.1 $HMGLOG/log.log 2>/dev/null | $BB awk -v id="$MOD_ID" '
    index($0, "mods: loaded " id " ") > 0 { s = "on"; w = "" }
    index($0, "mods: " id " not loaded") > 0 { s = "off"; w = $0; if (index(w, "not loaded: ") > 0 || index(w, "not loaded live: ") > 0) sub(/.*not loaded( live)?: */, "", w); else w = "(예외, 자세한 이유는 HMG-API 로그)" }
    /hook map: .*, hooks on/ { h = "on"; i = index($0, "hook map: "); m = substr($0, i + 10); sub(/[ ,].*/, "", m) }
    /hook map: .*, hooks off/ { h = "off"; i = index($0, "hook map: "); m = substr($0, i + 10); sub(/[ ,].*/, "", m) }
    END { if (s == "off") print "MH off " substr(w, 1, 200); else print "MH " s
          if (h != "") print "HK " h " " m; else print "HK " }')
  _MH=; _HK=
  while IFS= read -r _hl; do
    case "$_hl" in "MH "*) _MH=${_hl#MH } ;; "HK "*) _HK=${_hl#HK } ;; esac
  done <<HKE
$_hh
HKE
}
modhooks_state() { hmg_hooks_load; echo "$_MH"; }
# --- 베타 2 #64: HMG-API 부팅 보호(boot guard) 알리기(읽기만, 값을 되돌리거나 HMG-API 파일을 쓰지 않음) ---
# 근거(HMG-API 포크 core/zygote/zygote.c): zygote가 시작할 때마다 /data/hmgapi/hook/starts를 1 올리고(bump_starts, 올리기 전 값을
# 돌려줌) 그 값이 MAXSTARTS(3) 이상이면 그 시작의 훅을 모두 끄고 커널 로그에 "hmgapi-hook: zygote, hooks off (boot guard, starts=N)"을
# 남긴다. 훅이 켜지면 "…, hooks on, start N"이고, GUARD_DELAY(120)초 뒤 zygote가 살아 있으면 watcher가 0으로 되돌린다.
# 그래서 지금 읽은 값(올린 뒤 값)이 4 이상이면 이번 시작은 훅이 꺼진 것이다(3이면 아직 켜진 시작 3번째: 2분 안에 또 재부팅하면 꺼짐).
# 0으로 되돌리는 것은 훅이 켜진 부팅의 watcher와 HMG-API 설치(install.sh: echo 0 > hook/starts)뿐이다.
HOOKSTARTS=${HOOKSTARTS:-/data/hmgapi/hook/starts}
# starts 값(숫자). 못 읽으면 빈 값
hook_starts() { _hs=; { read _hs < $HOOKSTARTS; } 2>/dev/null; case "$_hs" in ''|*[!0-9]*) _hs= ;; esac; echo "$_hs"; }
# 10장 확인 리뷰 2: zygote.c는 hook/enable이 있고 hook/disable이 없을 때만 훅을 켜고 starts를 올린다. 둘 중 하나라도 어긋나면 starts는
# 멈춘 옛 값이라 판정·거절에 쓰지 않는다. HOOKDIR는 starts 파일이 있는 폴더(PC 시험은 HOOKSTARTS로 바꿈)
HOOKDIR=${HOOKDIR:-${HOOKSTARTS%/*}}
hook_armed() { [ -f $HOOKDIR/enable ] && [ ! -f $HOOKDIR/disable ]; }
# HMG-API 설치 판(installed.txt의 version). 설치돼 있지 않으면 빈 값
hmg_ver() { $BB awk '$1 == "version" { print $2; exit }' ${HMGINST:-/data/hmgapi/installed.txt} 2>/dev/null; }
# 이번 부팅 zygote의 훅 줄(커널 로그)을 읽어 ZH(마지막 줄: on·guard·off·빈 값 = 이번 부팅 줄 없음)와 ZON(마지막 "hooks on" 줄의
# 커널 시각, 정수 초, 없으면 빈 값)에 둔다. zygote가 같은 부팅에 다시 시작하면 줄이 여럿이다(마지막 것이 지금). KP_DMESG는 PC 시험용
zygote_info() {
  ZH=; ZON=
  set -- $({ if [ -n "$KP_DMESG" ]; then cat $KP_DMESG; else dmesg; fi; } 2>/dev/null | $BB grep 'hmgapi-hook: zygote,' 2>/dev/null \
    | $BB awk '{ i = index($0, "["); j = index($0, "]"); t = ""; if (i > 0 && j > i) { t = substr($0, i + 1, j - i - 1); gsub(/ /, "", t); t = int(t + 0) } }
      index($0, "hooks on") > 0 { h = "on"; on = t; next } index($0, "hooks off (boot guard") > 0 { h = "guard"; next } index($0, "hooks off") > 0 { h = "off" }
      END { print (h == "" ? "-" : h), (on == "" ? "-" : on) }')
  [ "$1" = - ] || ZH=$1
  [ "$2" = - ] || ZON=$2
  return 0
}
hooks_state() { hmg_hooks_load; echo "$_HK"; }

# --- 1.7.3(K-5): 판정은 한 곳에서 ---
# kp_collect가 판정에 쓰는 값을 한 번만 구하고(K_*), kp_verdict가 차례대로 판정해 V_*에 둔다. 상태 파일(status_kv)·리포트(report)가
# 같은 결과를 쓰고, 상태 화면 앱은 상태 파일의 verdict·verdict_lv·verdict_msg를 그대로 보인다(없는 옛 상태 파일이면 앱이 예전처럼 판정).
# QR 요약에도 verdict가 들어간다. 판정 순서: 설치 중 → 확인 안 된 차 → HMG-API → Wi-Fi 부품·칩(근거 있는 끝) → Wi-Fi 확인 중 →
# 다른 Wi-Fi 패키지 → 재부팅 필요 → 모드 새 판 대기 → 적용 거절·설치 실패 → 모드 상태 → 무선 기능 → Wi-Fi·핫스팟 → NEMESIS → 연결·준비됨.
kp_collect() {
  [ "$KC_DONE" = 1 ] && return 0
  KC_DONE=1
  K_PROD=$(getprop ro.build.product)
  K_FEATS="$(pm list features 2>/dev/null)
"
  parse_conf $SRC
  K_HMG=$(echo $($BB grep -E '^(version|build) ' ${HMGINST:-/data/hmgapi/installed.txt} 2>/dev/null))
  _kv=${K_HMG#*version }; [ "$_kv" = "$K_HMG" ] && _kv=; K_HMGV=${_kv%% *}
  K_NEM=$(nemesis version 2>/dev/null)
  K_MOD=$(mod_state); K_MODON=$(mod_on_state); K_BRIDGE=$(bridge_state)
  hmg_hooks_load; K_MH=${_MH%% *}; K_HK=${_HK%% *}; K_HKMAP=${_HK#* }
  K_OURAP=$(yesno running "hostapd $CONF"); K_DHCP=$(yesno our_dhcp_on)
  K_OTHER=$(yesno stock_ap_on); K_SSID=$(stock_ssid); K_APMODE=$(ap_mode $K_SSID)
  K_CP=$(cp_count); K_NOWLAN=$(yesno nowlan_now)
  K_FOREIGN=$(yesno mod_foreign); K_PENDING=$(yesno mod_pending)
  # 리뷰 L-6: 이번 부팅에 무선 안드로이드 오토가 연결됐는가(서비스 상태 안내 파일의 aa=ok, 이번 부팅 것만)
  # 베타 2 #64·8~9장 리뷰 M2: HMG-API 부팅 보호. HMG-API가 설치돼 있을 때만 본다(지운 차·disable로 끈 차는 starts가 남아도 아님).
  # 이번 부팅 커널 로그에 zygote 줄이 있으면 그것을 따른다(마지막 줄: guard면 맞음, on·다른 off면 아님). 줄이 없을 때만 starts≥4를 쓴다
  K_STARTS=$(hook_starts); zygote_info; K_ZHOOK=$ZH; K_GUARD=no
  if [ -n "$K_HMGV" ]; then
    case "$K_ZHOOK" in
      guard) K_GUARD=yes ;;
      on|off) ;;
      *) hook_armed && [ -n "$K_STARTS" ] && [ "$K_STARTS" -ge 4 ] && K_GUARD=yes ;;
    esac
  fi
  K_AAOK=no; K_AARDY=no; K_AAWAIT=no
  if [ "$($BB awk -F= '$1 == "boot" { print $2 }' $HINT 2>/dev/null)" = "$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)" ]; then
    # 베타 1 리뷰 4: AA를 끈 차(AAOFF)는 남은 aa=ok를 연결로 보지 않는다
    [ ! -f $AAOFF ] && $BB grep -qx 'aa=ok' $HINT 2>/dev/null && K_AAOK=yes
    # 베타 1 리뷰 5: 카플레이가 연결되어 있어 AA가 기다리는 중(aa=cpwait, 상태 화면 노란 줄)
    $BB grep -qx 'aa=cpwait' $HINT 2>/dev/null && K_AAWAIT=yes
    # 베타 1: 무선 안드로이드 오토 신호가 켜졌는가(서비스가 aa_ready에 켠 시각을 씀, 이번 부팅 것만). 판정 줄을 한 줄로 만들 때 쓴다
    $BB grep -q '^aa_ready=[0-9][0-9]*$' $HINT 2>/dev/null && K_AARDY=yes
  fi
  # 리뷰 M-3: wlan0이 안 생긴 부팅 수(hotspot.sh nowlan_boot_count)
  K_NLB=0; [ -f $BK/nowlan.boots ] && read K_NLB _x < $BK/nowlan.boots; case "$K_NLB" in ''|*[!0-9]*) K_NLB=0 ;; esac
  # 이번 부팅의 설치 진행 기록(지난 부팅 것은 빈 값)
  K_PST=; K_PSTAGE=
  if [ "$($BB awk -F= '$1 == "boot" { print $2 }' $PROG 2>/dev/null)" = "$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)" ]; then
    K_PST=$($BB awk -F= '$1 == "state" { print $2 }' $PROG 2>/dev/null)
    K_PSTAGE=$($BB awk -F= '$1 == "stage" { sub(/^stage=/, ""); print; exit }' $PROG 2>/dev/null)
  fi
}
k_feat() { case "$K_FEATS" in *"feature:$1
"*) return 0 ;; esac; return 1; }
# 판정 결과: V_CODE(영문 낱말), V_LV(0 좋음·1 확인 필요·2 문제), V_MSG(한국어 한두 문장), V_END(yes면 "이 차는 안 됨"으로 끝나 지우는 법을
# 함께 보임, U-6), V_FIRST(G-4 "먼저 할 일", 없으면 빈 값), V_S1~3(U-9 차주용 요약 3줄: 설치·무선 Wi-Fi·폰 연결)
kp_verdict() {
  kp_collect
  V_CODE=; V_LV=1; V_MSG=; V_END=no; V_FIRST=
  # 재리뷰 L-3: 지금 폰이 연결돼 있는가(카플레이 연결 수 또는 이번 부팅 무선 AA 연결). 연결 중이면 핫스팟·Wi-Fi 꺼짐 판정을 내지 않는다
  _vconn=no; { [ "${K_CP:-0}" != 0 ] || [ "$K_AAOK" = yes ]; } && _vconn=yes
  _vs() { V_CODE=$1; V_LV=$2; V_MSG=$3; }
  # 베타 2 #64: HMG-API 부팅 보호에 걸려 이번 부팅 훅이 꺼짐. 연결 중이 아니면 다른 판정보다 앞에(이것을 풀지 않으면 다른 것은 의미 없음).
  # HMG-API를 지우면(uninstall.sh) 모드가 바꾼 파일이 순정으로 돌아가 다시 적용해야 하므로, 지우지 말고 다시 설치(업데이트)하라고 쓴다
  # 8~9장 리뷰 L1: 이번 부팅은 부팅 보호로 시작했는데 지금 starts가 4보다 작으면(걸린 부팅에서는 4 이상이 남는다) 그 사이 HMG-API를
  # 다시 설치해 0이 된 것이다. 같은 일을 또 시키지 않고 재부팅만 안내한다
  if [ "$K_GUARD" = yes ] && [ "$_vconn" = no ] && [ "$K_ZHOOK" = guard ] && [ -n "$K_STARTS" ] && [ "$K_STARTS" -lt 4 ]; then
    _vs bootguard 1 "HMG-API를 다시 설치한 것으로 보입니다. 내비를 재부팅하고 2분 넘게 켜 두세요."
  elif [ "$K_GUARD" = yes ] && [ "$_vconn" = no ]; then
    _vs bootguard 2 "HMG-API가 재부팅이 너무 잦은 것으로 보고 무선 기능을 껐습니다. HMG-API를 지우지 말고 NEMESIS에서 다시 설치(업데이트)한 뒤 재부팅하고, 2분 넘게 켜 두세요."
  elif [ "$K_PST" = run ]; then _vs installing 1 "설치 중입니다. 끝날 때까지 기다려 주세요."
  elif ! car_in "$K_PROD" "$CARS"; then _vs untested 1 "확인되지 않은 차입니다. 핫스팟은 켜지 않고 대기 중입니다. QR로 제보해 주세요."
  elif [ -z "$K_HMGV" ]; then _vs nohmgapi 2 "HMG-API가 없습니다. HMG-API 1.0.2 이상을 설치해 주세요."
  elif ver_lt "$K_HMGV" 1.0.2; then _vs oldhmgapi 2 "지원하지 않는 HMG-API 버전입니다. 1.0.2 이상으로 업데이트해 주세요."
  # 리뷰 H-1: 기록이 있어도 지금 칩이 보이거나 모드가 이미 있으면(다른 앱으로 Wi-Fi를 켠 차 등) "안 됨"으로 보지 않는다
  elif [ -f $BK/wifi.nopart ] && [ "$K_MOD" = no ] && ! wifi_chip_seen; then _vs nopart 2 "$NOPART_MSG"; V_END=yes
  elif [ -f $BK/wifi.nochip ] && [ "$K_MOD" = no ] && ! wifi_chip_seen; then _vs nochip 2 "$NOCHIP_MSG"; V_END=yes
  elif [ "$K_MOD" = no ] && [ -f $BK/wifi.wake ] && [ ! -f $BK/wifi.woke ] && [ ! -f $BK/mod.tried ] && ! wifi_chip_seen \
      && wake_count && [ "$_wbad" = 0 ] && [ "$_wc" -lt "$WAKE_BOOTS" ]; then
    # 재리뷰 중간 1: 아직 깨울 횟수가 남았을 때만(칩을 한 번 본 차·모드를 지운 차·횟수를 다 쓴 차는 원래 판정으로)
    _vs wificheck 1 "$WIFI_CHECK_MSG (확인 $_wc/$WAKE_BOOTS)"
  elif [ -d /data/nemesis/apps/wireless.projection ] && [ "$K_MOD" = no ]; then
    _vs otherpkg 2 "wireless.projection이 설치되어 있어 무선 카플레이를 설정하지 않았습니다. wireless.projection을 삭제한 뒤 내비를 재부팅해 주세요."
  elif [ "$K_OURAP" = no ] && [ "${K_CP:-0}" = 0 ] && [ "$K_AAOK" = no ] && foreign_hostapd; then
    # 1.7.3(G-3): 우리 것도 순정(netd)도 아닌 hostapd(USB 동글 패키지 등)가 실제로 돌고, 연결도 없음. 리뷰 H-2: 순정 설정을
    # 못 읽어 stock_ssid가 unknown인 경우(순정 카플레이 AP 차 등)는 여기로 오지 않는다. 지우는 법(U-6)은 붙이지 않는다
    _vs otherwifi 2 "다른 Wi-Fi 패키지가 핫스팟을 쓰고 있어 함께 쓸 수 없습니다. 그 패키지를 지운 뒤 내비를 재부팅해 주세요."
  elif [ "$K_PST" = reboot ]; then
    # 1.7.3(U-8): 남은 재부팅 횟수. 모드를 새 판으로 바꾸는 중이면 재부팅이 두 번 필요하다(G-2①)
    # 리뷰 L-3: 두 번 재부팅이 필요할 때는 진행 기록 문구 대신 한두 문장으로
    # 리뷰 L10: 모드는 아직 옛 판이다(재부팅 뒤 서비스가 바꾼다). "바꿨습니다"라고 쓰지 않는다
    if [ "$K_PENDING" = yes ]; then _vs reboot 1 "재부팅하면 무선 모드를 새 판으로 바꿉니다. 재부팅하고 3분 뒤 한 번 더 재부팅해 주세요(남은 재부팅 2번)."
    else
      # 재리뷰 L-5: 진행 기록의 첫 문장 + "내비를 재부팅해 주세요(재부팅 1번이면 끝납니다)." 두 문장으로
      _s1=${K_PSTAGE%%. *}; _s1=${_s1%.}
      if [ -n "$_s1" ]; then _vs reboot 1 "$_s1. 내비를 재부팅해 주세요(재부팅 1번이면 끝납니다)."
      else _vs reboot 1 "내비를 재부팅해 주세요(재부팅 1번이면 끝납니다)."; fi
    fi
  elif [ "$K_PENDING" = yes ] && [ "$(cat $BK/mod.try 2>/dev/null)" = "$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)" ]; then
    # 리뷰 L10: 이번 부팅에 이미 시도했는데 아직 옛 판이면 이번에는 못 바꾼 것이다(일시 실패, 다음 부팅에 다시 시도)
    _vs modwait 1 "무선 모드를 이번에는 새 판으로 바꾸지 못했습니다. 재부팅하면 다시 시도합니다."
  elif [ "$K_PENDING" = yes ]; then
    _vs modwait 1 "무선 모드를 새 판으로 바꾸는 중입니다. 3분 뒤 한 번 더 재부팅해 주세요(남은 재부팅 1번)."
  elif [ "$K_PST" = fail ] && plan_this_boot && plan_problems | $BB grep -q .; then
    # 1.7.3(H-1): HMG-API가 적용을 거절함(계획에 problem 줄). 우리가 넣지 않은 파일은 고치지 않는다(D-5)
    _vs hmgrefuse 2 "HMG-API가 적용을 거절했습니다. HMG-API 앱의 'Can't apply' 창 아래쪽을 확인해 주세요."
  elif [ "$K_PST" = fail ] && [ -n "$K_PSTAGE" ]; then _vs failed 2 "$K_PSTAGE"
  elif [ "$K_FOREIGN" = yes ] && [ "${K_CP:-0}" = 0 ]; then
    # 1.7.3(G-2③): 외국·공식 모드. HMG-API를 통째로 지우면 권한 파일이 남아 거절될 수 있다(#94·#130)
    _vs foreign 2 "차에 있는 HMG-API 무선 모드가 한국 차용이 아닙니다. HMG-API 앱에서 그 모드만 지우고(HMG-API는 지우지 말고) 적용한 뒤 재부팅해 주세요."
  elif [ "$K_MOD" = no ] && [ -f $BK/mod.tried ]; then
    # 1.7.3(G-2②): 차주가 지운 상태(지운 기록)와 넣지 못한 상태를 다른 문구로
    _vs modgone 2 "무선 모드를 지운 기록이 있어 다시 넣지 않습니다. 다시 쓰려면 Korea Projection을 지우고 다시 설치한 뒤 재부팅해 주세요."
  elif [ "$K_MOD" = no ]; then
    _vs nomod 2 "무선 모드를 넣지 못했습니다. USB를 꽂고 Launch 화면의 [제보 파일 만들기]를 눌러 보내 주세요."
  elif [ "$K_MODON" = no ]; then _vs modoff 2 "HMG-API 무선 모드가 꺼져 있습니다. HMG-API 앱에서 켜고 Apply changes 후 다시 시작해 주세요."
  elif [ "$K_BRIDGE" = off ]; then _vs bridgeoff 2 "무선 모드의 'Wireless CarPlay' 설정이 꺼져 있습니다. HMG-API 앱에서 켜고 Apply changes 후 다시 시작해 주세요."
  elif [ "$K_HK" = off ]; then
    case "$K_HKMAP" in
      mapped) _vs hooksoff 1 "HMG-API 훅이 꺼져 있습니다. HMG-API 앱 Settings에서 'Check the map on this car'를 누른 뒤 내비를 재부팅해 주세요." ;;
      none) _vs hooksoff 1 "HMG-API에 이 차의 지도가 없어 훅이 꺼져 있습니다. QR로 제보해 주세요." ;;
      mismatch) _vs hooksoff 1 "HMG-API 지도가 이 차의 소프트웨어와 맞지 않아 훅이 꺼져 있습니다. QR로 제보해 주세요." ;;
      *) _vs hooksoff 1 "HMG-API 훅이 꺼져 있습니다(마지막 부팅 기록). 내비를 재부팅(RESET 버튼 또는 NEMESIS 재부팅)한 뒤 다시 확인해 주세요." ;;
    esac
  elif [ "$K_MH" = off ]; then _vs modhooksoff 2 "HMG-API가 이 차에서 무선 모드를 켜지 못했습니다(이 차와 맞지 않는 부분이 있음). 내비를 재부팅해 보시고, 그래도 같으면 USB를 꽂고 [제보 파일 만들기]로 리포트를 보내 주세요."
  elif ! k_feat com.hkmc.software.connectivity.carplay_wireless; then _vs nofeat 2 "무선 카플레이 기능이 꺼져 있습니다. HMG-API 무선 모드를 확인해 주세요."
  elif [ "$K_APMODE" != stock ] && [ -f $BK/stockap.seen ] && [ "$K_OURAP" = no ] && [ "$_vconn" = no ]; then
    _vs stockoff 1 "내비 Wi-Fi(무선 카플레이용)가 지금 꺼져 있습니다. 아이폰을 연결해 보고, 안 되면 내비를 재부팅해 주세요."
  elif [ "$K_APMODE" != stock ] && [ "$K_NOWLAN" = yes ] && [ "$K_OURAP" = no ] && [ "$_vconn" = no ] && [ "$K_NLB" -ge 3 ]; then
    # 리뷰 M-3: 모드가 있는데 wlan0이 3번 넘는 부팅 동안 안 생김(그랜저 IG #55 꼴). 재리뷰 중간 3②: 칩 실패(W-2·W-6, 안 됨으로 끝남)는
    # 근거(커널 칩 실패 줄·module_version 3)가 있을 때만. 근거가 없으면 제보를 부탁한다(지우는 법 없음)
    if chip_fail_evidence; then _vs nowlanfail 2 "$NOCHIP_MSG"; V_END=yes
    else _vs nowlanrepeat 2 "Wi-Fi 장치가 계속 켜지지 않습니다. 재부팅해도 같으면 USB를 꽂고 [제보 파일 만들기]로 알려 주세요."; fi
  elif [ "$K_APMODE" != stock ] && [ "$K_NOWLAN" = yes ] && [ "$K_OURAP" = no ] && [ "$_vconn" = no ]; then
    # 1.7.3(W-4·G-1): wlan0이 이번 부팅에 생기지 않음 = Wi-Fi가 꺼져 있거나 늦게 켜짐. 서비스가 다시 켜므로 재부팅 뒤 다시 확인
    _nl=$K_NLB; [ "$_nl" -ge 1 ] || _nl=1
    _vs wifioff 1 "$WIFI_CHECK_MSG (확인 $_nl/3)"
  elif [ "$K_APMODE" != stock ] && { [ "$K_OURAP" = no ] || [ "$K_DHCP" = no ]; } && [ "$_vconn" = no ]; then
    _vs apoff 1 "핫스팟이 꺼져 있습니다. 내비를 재부팅(RESET 버튼 또는 NEMESIS 재부팅)한 뒤 다시 확인해 주세요."
  elif ver_lt "${K_NEM:-0}" 1.16; then _vs oldnemesis 1 "NEMESIS를 1.16 이상으로 업데이트해 주세요."
  elif [ "${K_CP:-0}" != 0 ] || [ "$K_AAOK" = yes ]; then
    # 1.7.3(U-10): 확인 안 된 차(README ✅ 아님)가 연결되면 제보를 부탁한다(QR 요약 맨 앞 result: connected).
    # 리뷰 L-6: 무선 안드로이드 오토 연결도 연결로 본다(CLAUDE.md 2장 ✅ 기준)
    # 베타 1(소유자 요청): 카플레이와 안드로이드 오토를 한 줄로(상태 화면은 AA 준비됨·연결됨 줄을 따로 두지 않음)
    if car_in "$K_PROD" "$CARS_SEEN"; then
      if [ "${K_CP:-0}" != 0 ] && [ "$K_AAOK" = yes ]; then _vs connected 0 "무선 카플레이·안드로이드 오토 연결됨"
      # 리뷰 5: AA가 카플레이 때문에 기다리는 중(cpwait)이면 "준비됨"이라 하지 않는다(노란 안내 줄과 어긋나지 않게)
      elif [ "${K_CP:-0}" != 0 ] && [ ! -f $AAOFF ] && [ "$K_AARDY" = yes ] && [ "$K_AAWAIT" = no ]; then _vs connected 0 "무선 카플레이 연결됨, 안드로이드 오토 준비됨"
      elif [ "${K_CP:-0}" != 0 ]; then _vs connected 0 "무선 카플레이 연결됨"
      # 리뷰 4: "카플레이 준비됨"은 우리 핫스팟이 켜져 있을 때만
      elif [ "$K_OURAP" = yes ]; then _vs connected 0 "무선 안드로이드 오토 연결됨, 카플레이 준비됨"
      else _vs connected 0 "무선 안드로이드 오토 연결됨"; fi
    else _vs newconnected 0 "연결됐습니다! QR로 '연결됨'을 알려 주시면 지원 목록에 올립니다."; fi
  elif [ "$K_APMODE" = stock ]; then _vs ready 0 "무선 카플레이 준비됨(내비 Wi-Fi 사용). 아이폰은 설정 → 일반 → CarPlay에서 연결하세요."
  elif [ ! -f $AAOFF ] && [ "$K_AARDY" = yes ]; then _vs ready 0 "무선 카플레이·안드로이드 오토 준비됨. 아이폰은 설정 → 일반 → CarPlay, 안드로이드는 블루투스 연결 뒤 '무선 Android Auto 사용'을 누르세요."
  elif [ ! -f $AAOFF ]; then _vs ready 0 "무선 카플레이 준비됨(안드로이드 오토는 준비 중). 아이폰은 설정 → 일반 → CarPlay에서 연결하세요."
  else _vs ready 0 "무선 카플레이 준비됨. 아이폰은 설정 → 일반 → CarPlay에서 연결하세요."
  fi
  # 1.7.3(G-4): README ✅ 차종인데 문제가 있으면 "먼저 할 일". 근거 있는 끝(부품 없음·칩)·설치 중·재부팅 필요·확인 안 된 차는 빼고,
  # 내비 버전(펌웨어 끝 6자리 날짜)이 확인된 차(260902)보다 옛것이면 내비 업데이트를 맨 앞에(같은 차종, 다른 버전은 같은 차로 보지 않음)
  # 리뷰 L-1: 원인이 분명한 판정과 부팅 직후(5분 안)의 핫스팟 꺼짐에는 붙이지 않는다
  _vup=$(up_s); case "$_vup" in ''|*[!0-9]*) _vup=9999 ;; esac
  _g4=
  case "$V_CODE" in installing|untested|nopart|nochip|nowlanfail|nowlanrepeat|reboot|modwait|wificheck|wifioff|failed|ready|connected|newconnected|nohmgapi|oldhmgapi|otherpkg|otherwifi|foreign|modgone|hmgrefuse|oldnemesis|bootguard) ;;
    apoff) [ "$_vup" -lt 300 ] || _g4=1 ;;
    *) _g4=1 ;;
  esac
  if [ "$_g4" = 1 ]; then
       if car_model_seen "$K_PROD"; then
         _fd=$(fw_date "$K_PROD")
         if [ -n "$_fd" ] && [ "$_fd" -lt 260902 ] && [ "${K_PROD%%.*}" != BDPE ]; then
           V_FIRST="먼저 할 일: 내비 버전이 확인된 차(260902)보다 옛것입니다. 내비를 업데이트한 뒤 NEMESIS·HMG-API·Korea Projection을 다시 설치해 주세요."
         elif car_in "$K_PROD" "$CARS_SEEN"; then
           V_FIRST="먼저 할 일: 같은 차에서 된 분이 있습니다. 재부팅 2번, 최신 판 설치, 폰의 옛 등록 지우기를 먼저 해 주세요."
         fi
       fi
  fi
  # 1.7.3(U-9): 차주용 요약 3줄
  case "$V_CODE" in
    installing) V_S1="설치: 진행 중" ;;
    reboot|modwait|wificheck) V_S1="설치: 재부팅 필요" ;;
    untested) V_S1="설치: 이 차는 대기 중" ;;
    bootguard) V_S1="설치: HMG-API 훅 꺼짐(부팅 보호)" ;;
    ready|connected|newconnected|stockoff|wifioff|nowlanrepeat|apoff|oldnemesis|hooksoff) V_S1="설치: 끝남" ;;
    *) V_S1="설치: 안 됨(위 안내를 보세요)" ;;
  esac
  if [ "$K_OURAP" = yes ]; then V_S2="무선 Wi-Fi: 켜짐"
  elif [ "$K_APMODE" = stock ]; then V_S2="무선 Wi-Fi: 켜짐(내비 순정)"
  elif [ "$V_CODE" = nopart ]; then V_S2="무선 Wi-Fi: 부품 없음"
  elif [ "$V_CODE" = nochip ] || [ "$V_CODE" = nowlanfail ]; then V_S2="무선 Wi-Fi: 칩이 켜지지 않음"
  elif [ "$V_CODE" = nowlanrepeat ]; then V_S2="무선 Wi-Fi: 장치가 켜지지 않음(확인 중)"
  elif [ "$V_CODE" = wificheck ] || [ "$V_CODE" = wifioff ]; then V_S2="무선 Wi-Fi: 켜는 중(재부팅 뒤 확인)"
  else V_S2="무선 Wi-Fi: 꺼짐"; fi
  if [ "${K_CP:-0}" != 0 ]; then V_S3="폰 연결: 카플레이 ${K_CP}대 연결됨"
  elif [ "$K_AAOK" = yes ]; then V_S3="폰 연결: 무선 안드로이드 오토 연결됨"
  else V_S3="폰 연결: 지금 연결된 폰 없음"; fi
  return 0
}
# 리뷰 L-2: plan.txt가 이번 부팅에 쓰였는가(서비스가 이번 부팅 처음 시작할 때 쓰는 svc.start보다 새것이고, svc.start가 이번 부팅 것)
plan_this_boot() {
  [ -f $W/plan.txt ] && [ -f $W/svc.start ] || return 1
  read _sb _sx < $W/svc.start
  [ "$_sb" = "$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)" ] && [ $W/plan.txt -nt $W/svc.start ]
}
# 1.7.3(H-1): HMG-API 계획(plan.txt)의 problem 줄(최대 10줄, 160자). 숫자·영문·경로 글자(쉼표·괄호 포함)만 남긴다(이름 등이 섞이지 않게)
plan_problems() {
  $BB grep '^problem' $W/plan.txt 2>/dev/null | $BB awk 'NR <= 10 { gsub(/[^A-Za-z0-9 ,()\/._:\[\]-]/, ""); print substr($0, 1, 160) }'
}
status_kv() {
  kp_collect
  kp_verdict
  echo "product=$K_PROD"
  echo "targetdir=$(getprop ro.mobis.targetdir)"
  echo "pkgver=$(pver $APP/NEMESIS.data)"
  # tested: 서비스가 동작하는 차인가 (앱은 no면 "대기 중"으로 보인다). 시험 지원 차도 yes다.
  car_in "$K_PROD" "$CARS" && echo "tested=yes" || echo "tested=no"
  echo "hmgapi=$K_HMG"
  echo "nemesis=$K_NEM"
  echo "wp=$(yesno [ -d /data/nemesis/apps/wireless.projection ])"
  echo "mod=$K_MOD"
  echo "modver=$(mod_ver)"
  echo "mod_pending=$K_PENDING"
  echo "mod_hooks=$K_MH"
  echo "mod_foreign=$K_FOREIGN"
  echo "mod_on=$K_MODON"
  echo "bridge=$K_BRIDGE"
  echo "hooks=$K_HK"
  echo "hookmap=$K_HKMAP"
  echo "feat_carplay=$(yesno k_feat com.hkmc.software.connectivity.carplay_wireless)"
  echo "feat_aa=$(yesno k_feat com.hkmc.software.connectivity.androidauto_wireless)"
  echo "feat_wifi=$(yesno k_feat android.hardware.wifi)"
  echo "wlan0=$(yesno [ -d /sys/class/net/wlan0 ])"
  echo "softap_strings=${NS:-0}"
  echo "ssid_len=${#S2}"
  echo "pass_len=${#S4}"
  echo "our_ap=$K_OURAP"
  echo "our_dhcp=$K_DHCP"
  echo "other_ap=$K_OTHER"
  echo "stock_ssid=$K_SSID"
  echo "ap_mode=$K_APMODE"
  # 이 차에서 순정 카플레이 AP를 본 적이 있는가(서비스는 그 차에서 우리 핫스팟을 켜지 않는다)
  echo "stock_seen=$(yesno [ -f $BK/stockap.seen ])"
  echo "wpa=$(yesno running wpa_supplicant)"
  echo "cp_conn=$K_CP"
  # 1.7.0: 설치 진행 상태(run·done·reboot·fail, 없으면 none)와 무선 안드로이드 오토(시험) 켜짐
  _ps=$($BB awk -F= '$1 == "state" { print $2 }' $PROG 2>/dev/null); echo "state=${_ps:-none}"
  echo "aa=$(yesno [ ! -f $AAOFF ])"
  # 1.7.0: 이번 부팅에 Wi-Fi 장치(wlan0)가 생기지 않아 핫스팟을 못 켠 기록(hotspot.sh wlan_fail)
  echo "nowlan=$K_NOWLAN"
  echo "made=$(date '+%Y-%m-%d %H:%M')"
  # 1.7.3(K-5): 판정 결과(앱·리포트·QR이 같은 값을 쓴다)
  echo "verdict=$V_CODE"
  echo "verdict_lv=$V_LV"
  echo "verdict_msg=$V_MSG"
  echo "verdict_end=$V_END"
  echo "first=$V_FIRST"
  echo "s1=$V_S1"
  echo "s2=$V_S2"
  echo "s3=$V_S3"
}
R=$W/korea-projection-report.md
G=$W/korea-projection-log.txt
# --- 제보 파일 진행 표시(1.7.0 소유자 결정 2026-11-08): 토스트를 쓰지 않는다 ---
# 제보 파일 만들기(1-report.md, 3-log.txt 로그 모으기, USB 복사, 비공개 디버그 로그, HMG-API Car Report)는 진행을 RPROG(644)에
# 쓴다. 상태 화면 앱이 1초마다 읽어 "제보 자료 저장 중 N%" 막대와 끝나면 "완료: USB를 빼셔도 됩니다"를 보인다.
# 1.7.3(R-1·R-4): Launch는 만들지 않는다. 버튼 요청을 감시자(--watch)나 서비스 점검(--report)이 받아 make_report를 부른다.
RPROG=${RPROG:-/data/local/tmp/korea-projection-report-progress.txt}
RSTART=${RSTART:-$(date +%s)}
# 1.7.3(리뷰 중간 2): req=<지금 만드는 요청 id>, req2=<만드는 중에 들어온 요청 id(req.join)>. 앱은 시각이 아니라 이 id로
# 자기 요청의 진행을 찾는다(시계가 바뀌어도 맞게). carreport.sh도 같은 두 줄을 쓴다.
REQID=
rprog() {
  ( umask 022
    $BB printf 'pct=%s\nstate=%s\nstage=%s\nstart=%s\nt=%s\nboot=%s\nreq=%s\nreq2=%s\n' "$1" "$2" "$3" "$RSTART" "$(date +%s)" \
      "$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)" "$REQID" "$(cat $W/req.join 2>/dev/null)" > $RPROG.tmp \
      && $BB chmod 644 $RPROG.tmp && $BB mv -f $RPROG.tmp $RPROG ) 2>/dev/null
  return 0
}
# 이번 부팅에 살아 있는 다른 제보 만들기(감시자·서비스가 띄운 status.sh)가 있는가(리뷰 M1: 둘이 겹쳐 같은 파일을 쓰지 않게)
collect_alive() { st_alive $W/collect.pid; }
# 제보 파일 만들기 한 번: 끝나는 조건은 각 단계 자체(logcat -d, 파일 복사, carreport.sh의 제한 시간)다. 반복 없음.
# 한 번에 하나만(collect.pid "<pid> <boot_id>"). USB가 없으면 만들지 않고 실패 문구를 쓴다.
# 다른 제보 만들기가 돌고 있으면 이 요청 id를 req.join에 남긴다: 돌고 있는 쪽이 진행 기록 req2에 적어, 앱이 그 진행을
# 이어 보인다(요청이 말없이 사라지지 않게, 리뷰 낮음).
make_report() {
  if collect_alive; then
    [ -n "$REQID" ] && echo "$REQID" > $W/req.join
    return 0
  fi
  rm -f $W/req.join
  # 리뷰 M-4: 감시자 하나가 제보를 여러 번 만들 수 있다. 판정에 쓰는 값(kp_collect·HMG-API 로그)을 매번 새로 구한다
  KC_DONE=0; HK_LOADED=0
  echo "$$ $(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)" > $W/collect.pid
  RSTART=$(date +%s)
  if usb_in; then
    rprog 5 run "제보 파일을 만드는 중입니다(내비 상태)"
    report 2>/dev/null > $R; $BB chmod 600 $R
    _collect
  else
    rprog 100 fail "USB가 없습니다. USB를 꽂은 뒤 [제보 파일 만들기]를 다시 눌러 주세요."
  fi
  rm -f $W/collect.pid
}
_collect() {
  rprog 10 run "로그를 모으는 중입니다(서비스·HMG-API 로그)"
  logs 2>/dev/null > $G; $BB chmod 600 $G
  rprog 75 run "USB에 저장하는 중입니다"
  where=""
  for u in $USBS; do
    # 마운트 지점 폴더는 USB가 없어도 있을 수 있다: /proc/mounts로 확인
    # 제보 자료는 USB의 한 폴더($RDIR)에 정해진 이름으로 둔다: 1-report.md, 2-car-report.json(carreport.sh), 3-log.txt
    # 예전 제보의 2-car-report.json·4번은 지운다(새 파일과 섞이지 않게)
    # 1.7.1까지 제보 폴더에 두던 4-debug-private.txt도 지운다(1.7.2부터는 $PDIR에 둔다)
    $BB grep -q " $u " /proc/mounts 2>/dev/null && $BB mkdir -p "$u/$RDIR" && $BB rm -f "$u/$RDIR/2-car-report.json" "$u/$RDIR/4-debug-private.txt" "$u/$PDIR/4-debug-private.txt" \
      && $BB cp $R "$u/$RDIR/1-report.md" 2>/dev/null && $BB cp $G "$u/$RDIR/3-log.txt" 2>/dev/null && sync && where=$u && break
  done
  if [ -z "$where" ]; then
    rprog 100 fail "USB에 저장하지 못했습니다(USB가 빠졌거나 쓸 수 없음). USB를 다시 꽂고 [제보 파일 만들기]를 눌러 주세요."
    return 0
  fi
  # 1.7.0: 디버그 로그를 켠 차만 4-debug-private.txt(비공개)를 따로 둔다. 1.7.2: 제보 폴더가 아닌 $PDIR에.
  if [ -f $W/cp.log ] && echo "x" | $BB awk "$KPMASK" >/dev/null 2>&1; then
    rprog 80 run "디버그 로그를 저장하는 중입니다"
    $BB mkdir -p "$where/$PDIR" && privlog 2>/dev/null > "$where/$PDIR/4-debug-private.txt"; sync
  fi
  # HMG-API Car Report도 같은 폴더에 저장한다(1분쯤). 1.7.0: 늘 만든다(#41). 결과(완료·실패)는 carreport.sh가 RPROG에 쓴다.
  if command -v hmgapid >/dev/null 2>&1 && [ -f $APP/bin/carreport.sh ]; then
    rprog 85 run "HMG-API Car Report를 만드는 중입니다(약 1분). USB를 빼지 마세요."
    BB=$BB W=$W RDIR=$RDIR RPROG=$RPROG RSTART=$RSTART REQID=$REQID sh $APP/bin/carreport.sh </dev/null >/dev/null 2>&1
    $BB grep -q -E '^state=(done|fail)$' $RPROG 2>/dev/null && return 0
    # 다른 carreport.sh가 아직 USB에 쓰는 중이라(잠금) 이것이 바로 끝났다: 잠금이 풀릴 때까지(최대 약 7분) 기다린 뒤 완료라고 쓴다
    # (리뷰 M1: 쓰는 중에 "USB를 빼셔도 됩니다"가 뜨지 않게). 끝나는 조건: 잠금이 사라짐 또는 시간.
    _lw=0
    while [ -d $W/carreport.lock ] && [ $_lw -lt 210 ]; do sleep 2; _lw=$((_lw+1)); done
  fi
  rprog 100 done "완료: 제보 자료를 USB의 $RDIR 폴더에 저장했습니다. 이제 USB를 빼셔도 됩니다."
}
# 1.7.3(R-4): 요청 파일($REQ, hotspot.sh)을 하나 받는다. 받을 요청이면 0이고 REQID를 정한다. 받으면 바로 지운다.
# - 이전 부팅의 요청, 이미 받은 요청(지우지 못해 남은 것, req.last의 id)은 받지 않고 지워 본다(req_peek).
# - 2분(REQ_MAX초)이 넘은 요청은 버린다(부팅 뒤 초 기준. 앱이 이미 실패를 보였다).
take_req() {
  REQID=
  if ! req_peek; then
    # req_peek이 읽은 내용만 지운다(그 뒤 막 들어온 새 요청을 지우지 않게, req_drop)
    req_drop $REQ
    return 1
  fi
  req_drop $REQ
  echo "$RQ_ID" > $W/req.last
  _un=$(up_s)
  case "$_un" in ''|*[!0-9]*) : ;; *) [ $((_un - RQ_EL)) -le ${REQ_MAX:-120} ] || return 1 ;; esac
  REQID=$RQ_ID
  return 0
}
# 부팅 뒤 초(시계가 바뀌어도 거꾸로 가지 않는다). 읽지 못하면 빈 값
up_s() { $BB awk '{ print int($1) }' $UPTIME 2>/dev/null; }
# ap.log에 한 줄(서비스 로그와 같은 꼴). Launch·감시자에서 쓴다
# 베타 1 리뷰 B: 시계가 맞기 전이면 시각 대신 "부팅 직후"(hotspot.sh log_ts)
aplog() { log_ts; echo "$_LT $*" 2>/dev/null >> $APLOG; }
# 1.7.3(U-3): [지금 재부팅] 요청($RBREQ, hotspot.sh)을 하나 받는다. 재부팅해도 되면 0. 받으면 바로 지운다.
# 하지 않는 경우(모두 ap.log에 이유 한 줄): 이전 부팅·이미 받은 요청(reboot.last)·깨진 값, 40초(KP_RB_MAX)보다 오래됨·나이를 모름,
# 이번 부팅 설치 진행 기록이 설치 중(state=run), 설치 마무리(fix_perms: /system remount·
# 권한 파일·HMG-API 지도·무선 모드 설치·apply를 모두 이 안에서 함)가 돌고 있음, 제보 만들기가 돌고 있음.
# 감시자만 부른다: 서비스 점검(req_tick)이 늦게 받아 갑자기 재부팅하지 않게.
# 1.7.3(리뷰 M2): 받지 않은 재부팅 요청·돌아온 재부팅 명령의 결과를 앱이 읽게 남긴다(644, 비밀값 없음, 요청 id를 읽었을 때만).
# 앱은 RB_WAIT(80초)를 다 기다리지 않고 이유에 맞는 문구를 보인다. RESET 안내는 명령이 돌아왔을 때(cmd)·모르는 코드·아무도 답하지
# 않을 때(감시자 없음), 그리고 설치 중·바깥 작업(install·sysw) 거절이 RB_STUCK_MAX(3)번 넘게 이어질 때(앱이 셈).
# 1.7.3 베타 1(차 확인 2026-11-11): 버튼은 늘 보이므로 "재부팅 필요"(state=reboot)일 때만 받던 조건과, /system이 rw면 거절하던
# 조건을 뺐다. NEMESIS로 설치·업데이트하면 /system이 다음 재부팅까지 rw로 남아 업데이트 직후 늘 거절됐다(니로, 3번).
# 우리 쪽 쓰기는 설치 중(run)·설치 마무리(fix.pid)·제보 만들기(collect.pid)로 막는다.
# code: install 설치 중 · fix 설치 마무리 중 · collect 제보 만드는 중 · sysw 바깥 /system 작업 · guard HMG-API 부팅 보호(2분 전) ·
#       old 오래됐거나 나이를 모름 · bad 이번 부팅의 새 요청이 아님 · cmd 재부팅 명령이 돌아왔거나 끝나지 않음
RBRES=${RBRES:-/data/local/tmp/korea-projection-reboot-result.txt}
rb_result() {
  [ -n "$RQ_ID" ] || return 0
  umask 022
  { echo "id=$RQ_ID"; echo "boot=$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)"; echo "code=$1"; } 2>/dev/null > $RBRES.tmp \
    && $BB chmod 644 $RBRES.tmp 2>/dev/null && $BB mv -f $RBRES.tmp $RBRES 2>/dev/null
  umask 077
  return 0
}
take_rbreq() {
  if ! req_peek $RBREQ $W/reboot.last; then
    # req_peek이 읽은 내용만 다룬다(그 뒤 막 들어온 새 요청을 지우지 않게, req_drop). 못 읽었으면(파일 없음) 할 일 없음.
    if [ -n "$RQ_RAW" ]; then
      # 지우지 못해 같은 파일이 남아도 1초마다 줄을 쌓지 않게, 같은 내용은 한 번만 기록한다(리뷰 M2)
      if [ "$RQ_RAW" != "$(cat $W/reboot.bad 2>/dev/null)" ]; then
        echo "$RQ_RAW" > $W/reboot.bad
        aplog "재부팅 요청 거절: 이번 부팅의 새 요청이 아님(이전 부팅·이미 받은 요청·깨진 값)"
        rb_result bad
      fi
      req_drop $RBREQ
    fi
    return 1
  fi
  req_drop $RBREQ
  echo "$RQ_ID" > $W/reboot.last
  _un=$(up_s)
  case "$_un" in ''|*[!0-9]*) aplog "재부팅 요청 거절: 요청 나이를 알 수 없음"; rb_result old; return 1 ;; esac
  # 재리뷰(낮음): 한도 40초. 앱의 실패 판정(RB_WAIT 80초)은 이 40초 + sync + 재부팅 명령 기다림 30초보다 길다(재리뷰 L2). 나이가 음수(앞으로 온 요청)도 받지 않는다
  _ra=$((_un - RQ_EL))
  [ $_ra -ge 0 ] || { aplog "재부팅 요청 거절: 요청 시각이 지금보다 뒤임($_ra초)"; rb_result old; return 1; }
  [ $_ra -le ${KP_RB_MAX:-40} ] || { aplog "재부팅 요청 거절: 오래된 요청(${_ra}초)"; rb_result old; return 1; }
  # 베타 1 리뷰 2: 이번 부팅 설치 진행 기록이 run이어도, 마지막으로 쓴 지(ut, 부팅 뒤 초) RB_STALE초(900, 앱의 STALE과 같음)가
  # 넘었으면 멈춘 기록으로 보고 이 이유로는 막지 않는다(설치 마무리가 아직 돌면 아래 fix로 막는다). ut가 없거나 숫자가 아니어도
  # 멈춘 기록으로 본다(버튼이 끝없이 "잠시 뒤 다시"만 내지 않게)
  if $BB grep -q '^state=run$' $PROG 2>/dev/null \
      && [ "$($BB awk -F= '$1 == "boot" { print $2 }' $PROG 2>/dev/null)" = "$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)" ]; then
    _put=$($BB awk -F= '$1 == "ut" { print $2 }' $PROG 2>/dev/null)
    case "$_put" in
      ''|*[!0-9]*) aplog "설치 진행 기록이 run인데 마지막 시각을 모름: 멈춘 기록으로 보고 설치 중으로는 막지 않음" ;;
      *) if [ $((_un - _put)) -le ${RB_STALE:-900} ]; then
           aplog "재부팅 요청 거절: 설치가 아직 진행 중(이번 부팅 설치 진행 기록 run)"
           rb_result install
           return 1
         fi
         aplog "설치 진행 기록이 run인 채 $((_un - _put))초 그대로: 멈춘 기록으로 보고 설치 중으로는 막지 않음" ;;
    esac
  fi
  # 재리뷰 중간 1: 프로세스 확인을 못 하면(명령줄을 못 읽음) 돌고 있는 것으로 본다(pid_busy, 막는 쪽으로)
  pid_busy $W/fix.pid hotspot.sh && { aplog "재부팅 요청 거절: 설치 마무리(시스템 파일·HMG-API 적용)가 아직 도는 중"; rb_result fix; return 1; }
  pid_busy $W/collect.pid status.sh && { aplog "재부팅 요청 거절: 제보 파일을 만드는 중"; rb_result collect; return 1; }
  # 베타 2 #64: HMG-API watcher가 starts를 0으로 되돌리기 전에 다시 부팅하면 쌓여, 지금 값이 2·3이면 다음(또는 그다음) 시작에 훅이
  # 꺼진다. 앱은 root 파일 starts를 읽을 수 없어 root가 거절한다(code=guard, 앱은 "2~5분 뒤에"). 4 이상(이미 꺼짐)·못 읽음이면 막지 않는다.
  # 8~9장 리뷰 M1: watcher는 커널 부팅이 아니라 zygote 시작 뒤 GUARD_DELAY(120)초에 돈다(zygote.c start_watcher). 그래서 이번 부팅의
  # 마지막 "hooks on" 줄 커널 시각 + 120 + 여유 15초까지 막고, 그 줄이 없으면 부팅 뒤 300초까지 막는다(늘 끝이 있다). watcher가
  # 돌아 starts가 0·1이 되면 바로 풀린다
  # 10장 확인 리뷰 1: HMG-API가 설치돼 있지 않거나(--purge 없이 지워 starts가 남은 차) 이번 부팅 zygote 줄이 off·guard(disable 파일,
  # 이미 꺼짐)면 막지 않는다. 줄이 없으면 enable이 있고 disable이 없을 때만 본다(그래야 starts가 실제로 올라간다)
  _gst=$(hook_starts); zygote_info; _garm=no
  if [ -n "$(hmg_ver)" ]; then
    case "$ZH" in
      on) _garm=yes ;;
      '') hook_armed && _garm=yes ;;
    esac
  fi
  if [ -n "$ZON" ]; then _gend=$((ZON + ${KP_GUARD_DELAY:-120} + 15)); else _gend=300; fi
  if [ $_garm = yes ] && [ -n "$_gst" ] && [ "$_gst" -ge 2 ] && [ "$_gst" -le 3 ] && [ "$_un" -lt $_gend ]; then
    aplog "재부팅 요청 거절: 부팅 뒤 ${_un}초(HMG-API 시작 확인 시각 ${_gend}초 전)이고 HMG-API 부팅 보호 횟수 starts=$_gst(2분 안에 재부팅을 반복하면 훅이 꺼짐)"
    rb_result guard
    return 1
  fi
  # 베타 1 리뷰 1: 우리 밖에서 /system을 바꾸는 작업이 돌면 막는다(앱 문구는 "설정을 마무리하는 중"과 같은 fix)
  # 재리뷰 M2: 외부 작업 거절은 code=sysw(앱은 "마무리하는 중", 같은 이유가 이어지면 RESET 안내로 넘김)
  if sys_writer_busy; then aplog "재부팅 요청 거절: 시스템 영역을 바꾸는 작업이 도는 중($SYSW)"; rb_result sysw; return 1; fi
  return 0
}
# 베타 1 리뷰 1: rw 확인을 뺀 대신, /system을 바꾸는 우리 밖의 프로세스가 지금 도는지 /proc/<pid>/cmdline으로 본다(ps는 80칸에서 잘림).
# 이름의 근거:
#   - HMG-API 엔진은 데몬이 "app_process /system/bin hmgapi.engine.Engine <op>"로 띄운다(HMG-API 포크 core/hmgapid/hmgapid.c
#     op_engine). 앱의 Apply changes도 데몬을 거친다(README의 hmgapi.app ops). /system을 바꾸는 op는 apply·restore·recover.
#   - /system remount는 "hmgapid remount rw|ro"(같은 파일 op_remount, FINDINGS "nemesis install은 먼저 hmgapid remount rw").
#   - NEMESIS 패키지 설치·삭제 명령 "nemesis install"·"nemesis uninstall"(FINDINGS 23·519·606행). NEMESIS 앱이 이 명령을
#     프로세스로 돌리는지는 확인하지 못했다(차 로그에 프로세스 목록 없음). "nemesis remount"는 아래 hook-check가 쓴다.
#   - 재리뷰 M1: HMG-API 부팅 스크립트(포크 install/common/boot.sh)가 부팅마다 "sh /data/hmgapi/hook-check.sh"를 돌린다.
#     NEMESIS 설치 뒤 첫 부팅에 /system/etc/install-recovery.sh·qb_runtime.sh를 remount rw → 쓰기 → ro 한다. 엔진 update-hmgapi
#     (포크 Engine.java 284행)도 HMG-API 파일을 바꾼다.
# 빈 명령줄(커널 스레드)은 건너뛴다. 재리뷰 M2: 명령줄을 하나도 못 읽으면(busybox 1.8.1 tr이 NUL을 못 다루는 등) $PS로 한 번 더
# 본다(엔진 apply 명령줄은 약 60자라 ps의 80칸 안). 그래도 판단이 안 되면 막지 않고 로그만 남긴다(우리 쪽 쓰기는 fix.pid·run 기록이
# 따로 막는다. 막는 쪽으로 두면 버튼이 영영 "마무리하는 중"만 보인다). SYSW에 찾은 것을 둔다.
sys_writer_busy() {
  SYSW=; _sn=0
  # 확인 리뷰 M1: pcmd를 믿을 수 없으면(명령줄이 잘리거나 붙음) /proc 판정을 쓰지 않고 바로 ps로 본다
  pcmd_ok || aplog "재부팅 요청: 프로세스 명령줄이 잘려 읽힘(tr). ps로 확인함"
  pcmd_ok && for _sd in $PROC/[0-9]*; do
    [ -d "$_sd" ] || continue
    _sp=${_sd##*/}
    [ "$_sp" = "$$" ] && continue
    _sc=" $(pcmd $_sp) "
    [ "$_sc" = "  " ] && continue
    _sn=$((_sn + 1))
    sysw_match "$_sc" && return 0
  done
  [ $_sn -gt 0 ] && return 1
  # 명령줄을 하나도 못 읽음: ps로 한 번 더(한 줄씩, 줄 끝에 빈칸을 붙여 같은 꼴로 비교)
  # (here-doc은 mksh가 임시 파일을 써야 해서 피하고, 줄바꿈으로 나눈다. ps 줄에 * 가 있어도 펼치지 않게 set -f)
  _sn=0; _pso=$($PS 2>/dev/null); _ifs=$IFS; IFS='
'; set -f
  for _sl in $_pso; do
    _sn=$((_sn + 1))
    if sysw_match " $_sl "; then IFS=$_ifs; set +f; return 0; fi
  done
  IFS=$_ifs; set +f
  [ $_sn -gt 1 ] && return 1
  aplog "재부팅 요청: 프로세스 명령줄을 읽지 못함(/proc·ps 모두). 막지 않음(우리 쪽 쓰기는 설치 기록·마무리 확인으로 막음)"
  return 1
}
# 명령줄 하나($1, 앞뒤 빈칸)가 /system을 바꾸는 작업인가. 찾으면 SYSW에 이름
sysw_match() {
  case "$1" in
    *" hmgapi.engine.Engine apply "*|*" hmgapi.engine.Engine restore "*|*" hmgapi.engine.Engine recover "*|*" hmgapi.engine.Engine update-hmgapi "*) SYSW="HMG-API 적용"; return 0 ;;
    *"hmgapid remount "*|*"nemesis remount "*) SYSW="remount"; return 0 ;;
    *"hook-check.sh "*) SYSW="HMG-API 부팅 훅 확인"; return 0 ;;
    *"nemesis install "*|*"nemesis uninstall "*) SYSW="NEMESIS 설치·삭제"; return 0 ;;
  esac
  return 1
}
# 감시자(R-4, D-1): Launch가 띄운다. 1초마다 요청을 보고, 받으면 make_report를 그 자리에서 돈다(여러 번 받을 수 있다).
# 끝나는 조건: watch.until(부팅 뒤 초, Launch가 "지금+WATCH_SECS"로 씀)이 지남. Launch를 다시 누르면 늘어난다.
# 그 값을 읽지 못하거나 숫자가 아니면 바로 끝난다.
# 한 번에 하나만: watch.lock 폴더(mkdir은 한 번에 하나만 성공)와 watch.pid "<pid> <boot_id>". 잠금이 있는데 1초 뒤에도
# 살아 있는 감시자가 없으면(지난 부팅·죽은 감시자) 지우고 다시 잡는다. 상태 파일·앱 설치보다 먼저 돈다(시작이 늦지 않게).
# 베타 1 리뷰 3: 감시자가 끝나는 시각(부팅 뒤 초)을 앱이 읽는 파일로 남긴다(644, 부팅 id·초뿐). 버튼은 늘 보이지만 감시자는
# Launch 뒤 10분만 산다: 그 뒤 누르면 앱이 요청을 보내지 않고 "Launch를 다시 누른 뒤"라고 바로 알린다. 감시자가 끝날 때도 그 시각으로 씀
WATCHF=${WATCHF:-/data/local/tmp/korea-projection-watch.txt}
watch_pub() {
  ( umask 022
    { echo "boot=$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)"; echo "until=$1"; } > $WATCHF.tmp \
      && $BB chmod 644 $WATCHF.tmp && $BB mv -f $WATCHF.tmp $WATCHF ) 2>/dev/null
  return 0
}
if [ "$1" = --watch ]; then
  if ! $BB mkdir $W/watch.lock 2>/dev/null; then
    sleep 1
    st_alive $W/watch.pid --watch && exit 0
    rm -rf $W/watch.lock
    $BB mkdir $W/watch.lock 2>/dev/null || exit 0
  fi
  # 1.7.3(K-7): 1초 반복에서 하위 셸을 줄인다. 끝 시각·부팅 뒤 초는 read로 읽고(up_s의 awk와 같은 정수 초), 요청 파일은
  # 있을 때만 본다(없으면 받는 함수가 할 일이 없다). 부팅 id는 요청을 받을 때마다 그대로 읽는다(못 읽으면 거절, 재리뷰)
  _me="$$ $(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)"
  echo "$_me" > $W/watch.pid
  # 재리뷰 L1: 새 감시자는 시작할 때 지금 끝 시각을 다시 쓴다(옛 감시자가 끝나며 덮었더라도 바로 맞게)
  _wu=; { read _wu < $W/watch.until; } 2>/dev/null; case "$_wu" in ''|*[!0-9]*) : ;; *) watch_pub $_wu ;; esac
  while :; do
    _wu=; _wn=
    { read _wu < $W/watch.until; } 2>/dev/null
    { read _wn _wx < $UPTIME; } 2>/dev/null; _wn=${_wn%%.*}
    case "$_wu" in ''|*[!0-9]*) break ;; esac
    case "$_wn" in ''|*[!0-9]*) break ;; esac
    if [ "$_wn" -ge "$_wu" ]; then
      # 베타 1 리뷰 7: 끝내기 전에 1초 뒤 한 번 더 읽는다. Launch가 막 늘렸으면(이 감시자가 살아 있다고 보고 새로 띄우지 않음) 계속
      sleep 1
      _wu=; { read _wu < $W/watch.until; } 2>/dev/null; { read _wn _wx < $UPTIME; } 2>/dev/null; _wn=${_wn%%.*}
      case "$_wu" in ''|*[!0-9]*) break ;; esac
      case "$_wn" in ''|*[!0-9]*) break ;; esac
      [ "$_wn" -lt "$_wu" ] || break
    fi
    # 1.7.3(U-3): 재부팅 요청을 먼저 본다(순정 nemesis 재부팅 메뉴와 같은 명령). 재부팅이 되면 이 셸도 함께 끝난다.
    # 남는 잠금(watch.lock)은 다음 부팅의 감시자가 "지난 부팅 것"으로 보고 지운다. 명령이 돌아오면(실패) 기록하고 계속 감시한다.
    if [ -f $RBREQ ] && take_rbreq; then
      aplog "상태 화면에서 재부팅 요청: 지금 재부팅함(sync 뒤 reboot)"
      # KP_SYNC는 PC 시험용(KP_REBOOT처럼). 차에서는 sync
      ${KP_SYNC:-sync}
      # 재리뷰 L2: 검사와 재부팅 사이(특히 sync가 길 때) 바깥 작업·설치 마무리·제보 만들기가 새로 시작했으면 지금 거절한다
      if sys_writer_busy || pid_busy $W/fix.pid hotspot.sh || pid_busy $W/collect.pid status.sh; then
        aplog "재부팅 요청 거절: sync 뒤 다시 보니 시스템 영역·설치 마무리·제보 작업이 시작됨(${SYSW:-우리 작업})"
        rb_result sysw
      else
      # 재리뷰(낮음): reboot 명령이 돌아오지 않을 수 있다(4.4 toolbox reboot은 sys.powerctl 뒤 기다릴 수 있음). 뒤에서 띄우고
      # KP_RB_WAIT초(기본 30)만 기다린다. 끝나는 조건: 명령이 끝남 또는 시간. 그 뒤 기록하고 감시를 계속한다.
      # 끝났는지는 하위 셸이 남기는 reboot.rc(종료 코드)로 본다. kill -0은 끝난 자식(좀비)에도 성공해 쓸 수 없다(PC 시험에서 확인).
      rm -f $W/reboot.rc
      ( ${KP_REBOOT:-/system/bin/reboot} </dev/null >/dev/null 2>&1; echo $? > $W/reboot.rc ) &
      _rw=0
      while [ ! -s $W/reboot.rc ] && [ $_rw -lt ${KP_RB_WAIT:-30} ]; do sleep 1; _rw=$((_rw+1)); done
      if [ -s $W/reboot.rc ]; then
        aplog "재부팅 명령이 끝났지만 재부팅되지 않음(종료 코드 $(cat $W/reboot.rc 2>/dev/null))"
      else
        aplog "재부팅 명령이 ${KP_RB_WAIT:-30}초 안에 끝나지 않음(아직 재부팅되지 않음)"
      fi
      rb_result cmd
      fi
    fi
    if [ -f $REQ ] && take_req; then
      make_report
      # 만드는 동안 쌓인 요청은 버린다(그동안 앱이 버튼을 막으므로 겹쳐 누른 것)
      rm -f $REQ 2>/dev/null
    fi
    sleep 1
  done
  [ "$(cat $W/watch.pid 2>/dev/null)" = "$_me" ] && rm -f $W/watch.pid
  rm -rf $W/watch.lock
  # 앱이 "감시자 끝남"을 알게 지금 시각으로 쓴다(못 읽으면 0). 재리뷰 L1: 그 사이 Launch가 새 끝 시각을 썼으면(이 감시자가 본 마지막
  # 값과 다름: 새 감시자가 뜸) 덮지 않는다
  _wn=; { read _wn _wx < $UPTIME; } 2>/dev/null; _wn=${_wn%%.*}; case "$_wn" in ''|*[!0-9]*) _wn=0 ;; esac
  _wf=; [ -f $WATCHF ] && _wf=$($BB awk -F= '$1 == "until" { print $2 }' $WATCHF 2>/dev/null)
  [ -z "$_wf" ] || [ "$_wf" = "$_wu" ] && watch_pub $_wn
  exit 0
fi
# 서비스 점검(hotspot.sh req_tick)이 띄운다: 요청 하나를 받아 만든다. 감시자가 살아 있으면 맡긴다.
if [ "$1" = --report ]; then
  st_alive $W/watch.pid --watch && exit 0
  if take_req; then make_report; rm -f $REQ 2>/dev/null; fi
  exit 0
fi

# 1.7.3(K-3): 하위 셸 없이 이 셸에서 쓴다(그래야 끝의 한 줄 요약이 방금 구한 값 K_*를 다시 쓸 수 있다: softap.conf·연결 수·AP 판정을
# 두 번 구하지 않음). 상태 파일만 644로 만들고 umask는 되돌린다. parse_conf가 위치 인자를 바꾸지만 이 뒤에는 $1을 쓰지 않는다.
# 리뷰 L-4: 이 셸에서 바로 돈다. status_kv 안에 $(( ))를 넣을 때는 값이 숫자인지 먼저 확인하세요(틀린 산술은 Launch 전체를 끝냄)
umask 022
status_kv 2>/dev/null > $STATUS.tmp && $BB chmod 644 $STATUS.tmp && $BB mv -f $STATUS.tmp $STATUS
umask 077

# 상태 화면 앱이 없으면(설치 때 실패) 여기서 다시 설치해 본다. 이어서 NEMESIS가 화면을 연다.
# 한 부팅에 한 번만 (sys.boot_completed를 바꿀 때마다 init의 부팅 완료 트리거가 다시 돌기 때문)
install_app_once

# 보통 Launch(1.7.3 R-1): 제보 파일을 만들지 않는다. USB가 없으면 지난 저장 기록을 지운다(화면에 지난 "완료"가 다시
# 안 보이게, 리뷰 L1). 만드는 중이면 그대로 둔다(화면이 막대를 이어 보인다).
usb_in || collect_alive || rm -f $RPROG
# 감시자를 띄운다. 이미 살아 있으면 끝나는 시각만 늘린다. 설치 대기(--wait)가 끝났을 때도 지금부터 10분 동안 띄운다
# (베타 1: [지금 재부팅]·[제보 파일 만들기]가 늘 보이므로, 설치 중 Launch 뒤 10분이 지나 버튼이 안 듣는 일이 없게).
# RPT_SYNC=1(PC 테스트)이면 띄우지 않는다(테스트가 --watch·--report를 직접 부른다).
if [ "${RPT_SYNC:-0}" != 1 ]; then
  _wn=$(up_s)
  case "$_wn" in
    ''|*[!0-9]*) : ;;
    # 임시 파일에 쓴 뒤 이름을 바꾼다: 감시자가 1초마다 읽으므로 ">"로 바로 쓰면 비운 순간을 읽고 "값 없음"으로 끝날 수 있다
    # (PC 시험에서 Launch를 다시 누를 때 재현, 2026-11-10)
    *) echo $((_wn + ${WATCH_SECS:-600})) > $W/watch.until.tmp && $BB mv -f $W/watch.until.tmp $W/watch.until
       watch_pub $((_wn + ${WATCH_SECS:-600}))
       st_alive $W/watch.pid --watch || BB=$BB $BB setsid sh $APP/bin/status.sh --watch </dev/null >/dev/null 2>&1 & ;;
  esac
fi

# 설치가 아직 진행 중이면 끝난 뒤에 한 번 더 돌도록 뒤에 남긴다(한 번에 하나만, 이번 부팅의 것만)
if [ $WAITED = 0 ] && $BB grep -q '^state=run$' $PROG 2>/dev/null; then
  # 1.7.3(K-7): wait.pid도 "<pid> <boot_id>"로 쓰고 st_alive로 본다(지난 부팅의 같은 pid를 살아 있는 것으로 보지 않게)
  if ! st_alive $W/wait.pid --wait; then
    BB=$BB $BB setsid sh $APP/bin/status.sh --wait </dev/null >/dev/null 2>&1 &
    echo "$! ${BID:-$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)}" > $W/wait.pid
  fi
fi
# 상태와 저장 진행은 이어서 열리는 화면(StatusActivity)이 보여 준다. 토스트는 쓰지 않는다(1.7.0 소유자 결정).
# 표준출력에는 한 줄 요약을 남긴다(NEMESIS 기록·테스트용).
# 1.7.3(K-3): 상태 파일을 쓸 때 구한 값(kp_collect)을 다시 쓴다
c=$K_CP
if [ "$K_APMODE" = stock ]; then m="Korea Projection: 무선 카플레이 준비됨(내비 Wi-Fi 사용), 카플레이 연결 $c개"
else
  a=꺼짐; [ "$K_OURAP" = yes ] && a=켜짐
  d=꺼짐; [ "$K_DHCP" = yes ] && d=켜짐
  m="Korea Projection: 핫스팟 $a, DHCP $d, 카플레이 연결 $c개"
fi
echo "$m"
exit 0
