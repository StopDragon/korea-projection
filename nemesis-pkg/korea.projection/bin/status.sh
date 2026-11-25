#!/system/bin/sh
# 이 파일을 고친 버전은 Korea Projection 지원 대상이 아닙니다. 공식 버전: https://github.com/StopDragon/korea-projection
# NEMESIS Manager > Korea Projection > Launch: 상태 화면용 상태 파일과 차량 제보용 리포트.
# 1.7.3(소유자 결정 2026-11-09): Launch는 상태 파일만 쓰고 화면을 연다. 제보 파일(USB의 KoreaProjection-report 폴더의
# 1-report.md, 2-car-report.json, 3-log.txt)은 상태 화면의 [제보 파일 만들기] 버튼을 눌렀을 때만 만든다
# (앱이 요청 파일을 쓰고, 이 스크립트의 감시자(--watch)나 서비스 점검(--report)이 받아 만든다).
# 리포트에는 이름, 버전, 예/아니요, 개수만 넣는다. SSID, 비밀번호, 휴대폰 이름, MAC, IP는
# 넣지 않는다. 차 주인이 읽어 본 뒤 첨부한다.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
# busybox는 hotspot.sh가 고른다(내비의 것, 없으면 패키지에 함께 넣은 것: 1.6.x 알파)
APP=${APP:-/data/nemesis/apps/korea.projection}
# 1.7.4(Q-1): Wi-Fi 장치 이름(hotspot.sh와 같은 기본값). 문구 속 "wlan0" 글자는 그대로 둔다
WIF=${WIF:-wlan0}
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
# 1.7.4(L-9, 소유자 결정): 무선 안드로이드 오토를 USB 파일(kp-aa-off·kp-aa-on)로 끄고 켜던 기능을 없앴다. Launch는 그 파일을
# 읽지 않는다(늘 켜짐). 1.7.3 이하가 남긴 끄기 표시는 서비스가 시작할 때 지운다(hotspot.sh main)
# 표준입력의 마지막 $1줄만 내면서 휴대폰 블루투스 주소(MAC)와 IP 주소를 x로 지운다(busybox tail 대신 awk)
lastmask() {
  # n = n + 0: 오래된 busybox awk에서 -v 값이 문자열로 비교되지 않게 숫자로 만든다
  $BB awk -v n="$1" 'BEGIN { n = n + 0 } { a[NR % n] = $0 }
    END { s = NR > n ? NR - n + 1 : 1
      for (i = s; i <= NR; i++) { l = a[i % n]
        gsub(/[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]/, "xx:xx:xx:xx:xx:xx", l)
        # 정식(beta3-reports 8-4): 순정 BT 로그의 반쪽 주소(XX:XX:XX:**:**:**)도 가린다(KPMASK와 같은 규칙)
        gsub(/[0-9A-Fa-f][0-9A-Fa-f][:-][0-9A-Fa-f][0-9A-Fa-f][:-][0-9A-Fa-f][0-9A-Fa-f][:-][*][*][:-][*][*][:-][*][*]/, "xx:xx:xx:**:**:**", l)
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
    if [ -f $_f ]; then lastmask 400 < $_f
    # 1.7.4(P-3, #228): 칩 실패 근거는 재설치·업데이트로 $W가 지워져도 $BK 사본(hotspot.sh가 남김)이 있다. 읽기만 하고 같은 가리기로 싣는다
    elif [ "$_f" = "$NOCHIP_LOG" ] && [ -f $BK/nochip-wifi.txt ]; then
      echo "(지금 기록 폴더에는 없어 백업 폴더의 사본을 싣습니다)"; lastmask 400 < $BK/nochip-wifi.txt
    else echo "(없음)"; fi
  done
  # 1.7.4 베타 2(측정): 서비스의 30초 측정 기록(숫자만, hotspot.sh perf_tick). 앞부분(perf.log.1)과 이어서 마지막 480줄
  echo; echo "== perf.log (30초 측정 기록)"
  if [ -f $PERF ] || [ -f $PERF.1 ]; then $BB cat $PERF.1 $PERF 2>/dev/null | lastmask 480; else echo "(없음)"; fi
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
# 리뷰 H1). USB에 따로 4-debug-private.txt로 둔다(베타 3부터 제보 폴더, 동글 허용 판단 정보만 $PDIR/5-dongle-private.txt). 마지막 8000줄만 먼저 자른 뒤
# KPMASK로 가린다(리뷰 M2: 6MB 전체를 가리면 오래 걸린다). 가리기 awk가 안 되면 만들지 않는다.
# 베타 3(소유자 결정 11-23 "핸드폰 이름 들어가도 된다. 우리가 어차피 지워주잖아. 개인정보 공개는 본인 책임"): 디버그 로그는 제보 폴더($RDIR)의
# 4-debug-private.txt로(이름은 도구와 맞춰 그대로). 공개로 올라오면 받아 두고 링크를 내린다(docs/issue-reply-guide.md 5장).
# 예외: 동글 판정 정보(dongle_info 절)와 무선 모드 작성자 키는 공개 저장소·답글에 나가면 안 되므로
# 따로 $PDIR의 5-dongle-private.txt(dgprivlog)에 둔다
debuglog() {
  echo "# Korea Projection 디버그 로그"
  echo
  echo "휴대폰 이름 등 개인정보가 들어 있을 수 있습니다."
  echo
  # 베타 3(B3-12): softap.conf 위치·형식 버전·문자열별 길이(내용 없음)
  [ -s $SOFTAP_DIAGF ] && { echo "- softap.conf 형식(위치·버전·문자열 수·문자열별 길이·고른 비밀번호 길이): $(cat $SOFTAP_DIAGF 2>/dev/null)"; echo; }
  if [ -s $BK/debug.why ]; then echo "## 디버그 로그 자동 켜짐 이유(최근 8번: epoch, 부팅 뒤 초, 코드, 시각)"; $BB cat $BK/debug.why 2>/dev/null; echo; fi
  [ -f $W/cp.log ] || return 0
  echo "## 디버그 로그"
  $BB cat $W/cp.log.1 $W/cp.log 2>/dev/null | $BB awk -v n=8000 'BEGIN { n = n + 0 } { a[NR % n] = $0 } END { s = NR > n ? NR - n + 1 : 1; for (i = s; i <= NR; i++) print a[i % n] }' | $BB awk "$KPMASK"
}
dgprivlog() {
  echo "# Korea Projection 동글·무선 모드 비공개 기록"
  echo
  echo "**이 파일(KoreaProjection-private 폴더)은 GitHub 이슈에 올리지 마세요.** 필요할 때 개발자에게 따로(메일) 보내 주세요."
  echo "동글을 쓰는 차는 동글 MAC 앞 3바이트(제조사 부분)와 USB 번호가 들어 있습니다(지원 동글 확인용)."
  echo
  # 배포판: 동글 조사 정보는 공개 리포트가 아니라 여기에 둔다
  # 디버그 로그를 켠 차도 동글 조사 정보(커널·모듈·USB 장치)를 남긴다(동글 지원 준비용, 1.7.4 Q-2)
  if [ -s $DINFO ]; then $BB cat $DINFO; echo; elif [ -f $DG_ON ] || [ -f $BK/dongle.used ] || [ -f $W/cp.log ]; then dongle_info 2>/dev/null; echo; fi
  # 베타 3(B3-10): 무선 모드 작성자 키(다른 사람 모드면 어느 키인지 가르려고, 비공개에만)
  [ -f $HMGDATA/mods/$MOD_ID/mod.json ] && { echo "- 무선 모드 작성자 키(uuid): $(mod_uuid)$([ -f $BK/mod.otherkey ] && echo ", 다른 키 기록: $(cat $BK/mod.otherkey 2>/dev/null)")"; echo; }
  return 0
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
# 1.8.0 PF-4: 제보 한 번에 logcat -d를 다섯 번 읽던 것을 한 번만 읽는다(니로 2026-11-15: 제보 중 CPU 81~99%, 소리 버퍼 1100ms).
# make_report가 $LCTMP에 한 번 받아 두고(umask 077이라 600, 폰 이름이 들어갈 수 있는 원본이라 $W 안에만) 끝나면 지운다.
# 받아 둔 것이 없으면(리포트만 따로 부를 때·PC 시험) 예전처럼 바로 읽는다.
LCTMP=${LCTMP:-$W/logcat.tmp}
# 배포판: 비공개 파일에 넣을 동글 조사 칸(make_report가 logcat을 받아 둔 동안 만듦)
DINFO=${DINFO:-$W/dinfo.tmp}
lcd() { if [ "$LC_ON" = 1 ] && [ -f $LCTMP ]; then $BB cat $LCTMP; else logcat -d -v time 2>/dev/null; fi; }
cplog() {
  echo "x" | $BB awk "$KPMASK" >/dev/null 2>&1 || { echo "(이 내비의 busybox로는 가릴 수 없어 넣지 않음)"; return 0; }
  # 디버그 로그의 DROP과 달리 교차로 이름 줄은 버리지 않는다(위치는 KPMASK가 가린다, 반복은 cpdedup이 줄인다)
  _cd='iAPSendMessage\(\) : done with \(0x00\)|iAPSendMessage Command Received|getCANSTatus = true|getCANStatus|pcm_write failed'
  echo x | $BB grep -E "$_cd" >/dev/null 2>&1; [ $? -le 1 ] || _cd='^$'
  lcd | $BB grep -E "$CPTAGS" | $BB grep -v -E "$_cd" \
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
  lcd | $BB grep -E "$PPTAGS|$PPKEYS" | $BB grep -v -E "$PPNOISE" | $BB awk "$KPMASK" | lastmask 400
}
# Wi-Fi 서비스·드라이버·핫스팟 쪽 logcat(1.5.4: 그랜저 하이브리드 #12에서 핫스팟이 30초마다 끊긴 원인을 보려고).
# 지금 logcat 버퍼에 남은 것만 본다(-d). Wi-Fi 이름·비밀번호·주변 네트워크·기기 이름이 나올 수 있는 줄은
# 통째로 버린다(ssid, psk, pass, name, bssid, extra:가 들어간 줄. NetworkInfo의 extra:에는 SSID가 들어간다).
# key는 버리지 않는다: hostapd의 "pairwise key handshake completed"가 연결 성공을 보여 준다. MAC·IP는 lastmask가 지운다.
# 전역 IPv6 주소는 지우지 못한다(이 차의 핫스팟은 IPv4만 쓴다). 첨부 전에 차주가 읽어 보도록 안내문이 있다.
WIFITAGS=' [VDIWEF]/(WifiStateMachine|WifiService|WifiController|WifiHW|WifiNative[^ (]*|SoftapController|SoftApController|wpa_supplicant|hostapd|Tethering|NetworkManagementService|CommandListener|bcmdhd|dhd) *\('
WIFIDROP='ssid|psk|pass|name|bssid|extra:'
wifilog() {
  lcd | $BB grep -E "$WIFITAGS" | $BB grep -v -i -E "$WIFIDROP" | lastmask 300
}

# 1.7.2(P-8·P-12): 연결 진단 줄. 숫자·짧은 영문 값만 넣는다(SSID·비밀번호·폰 이름·MAC·IP 없음).
# logcat은 한 번만 읽어(-d) 순정 WifiService의 "Last mode:"·"[Feature]" 줄(마지막 것, 영문·괄호만 남김)과 계기판 곡 제목 확인
# 줄의 개수만 센다(줄 내용은 넣지 않는다). 부팅 로그는 버퍼가 짧아 대개 남지 않는다("버퍼에 없음").
diag() {
  echo "## 연결 진단 (숫자·짧은 값만)"
  lcd | $BB awk '
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
  # 리뷰 반영: 고정한 판과 지금 모드 판이 다르면(설치 중 전원이 꺼져 고정만 남은 차 등) 지금 판을 덧붙인다
  _pin=$(mod_pin_ver); _pcur=$(mod_ver)
  case "$_pin" in ''|old) echo "- 무선 모드 고정: $(mod_pin_text "$_pin")" ;;
    *) if [ -n "$_pcur" ] && [ "$_pcur" != "$_pin" ]; then echo "- 무선 모드 고정: $_pin (지금 $_pcur)"; else echo "- 무선 모드 고정: $_pin"; fi ;;
  esac
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
  # 1.7.4(묶음 C 리뷰 중간 2): 1.7.2 이하에서 바로 올린 칩 실패 상태인가(화면의 "옛 판에서 바로 올린 차" 줄과 같은 조건)
  echo "- 옛 판(1.7.2 이하) Wi-Fi 기록이 남음: $(if kp_legacy_nochip; then echo 예; else echo 아니요; fi)"
  # 1.7.4(Q-3): 부품 없음(module_version 3)·칩 실패로 끝난 차는 1.8.0 조사용으로 한 줄 남긴다(상태 화면 문구는 1.7.3 그대로).
  # 리뷰 반영: 공개 이슈에 올라가는 파일이라 아직 없는 기능을 약속하는 말("동글 대상")은 쓰지 않는다. 해당 없는 차는 줄을 쓰지 않음
  if [ -f $BK/wifi.nopart ]; then echo "- 참고(1.8.0 조사용): 내장 Wi-Fi를 쓸 수 없는 차로 판정됨(Wi-Fi 부품 없음)"
  elif [ -f $BK/wifi.nochip ]; then echo "- 참고(1.8.0 조사용): 내장 Wi-Fi를 쓸 수 없는 차로 판정됨(Wi-Fi 칩이 켜지지 않음)"; fi
}

# 1.7.4(Q-2): 1.8.0 USB Wi-Fi 동글 준비 정보. 읽기만 한다(내비에 아무것도 쓰지 않음). 차마다 커널·모듈 조건이 달라
# 1.8.0에서 드라이버를 몇 벌 만들지(또는 못 만드는 차가 어디인지) 정하는 데 쓴다.
# 남기지 않는 것: USB 일련번호(serial·iSerial), MAC(어떤 address 파일도 읽지 않음, wifi.info.macaddress 읽지 않음), IP, SSID,
# 장치·제품 이름 문자열(manufacturer·product: 폰·사람 이름이 들 수 있음), 커널 명령줄(/proc/cmdline은 읽지 않음).
# USB는 제조사·제품 ID(16진 4자리 둘)·클래스·속도만 남긴다. 값은 모두 dn_safe로 거른다(허용 글자·길이 제한).
# 줄마다 실패해도 "확인 안 됨"으로 넘어가고 끝까지 간다. 큰 파일(kallsyms·config.gz)은 grep 결과 몇 줄·개수만.
KPROC=${KPROC:-/proc}
KSYS=${KSYS:-/sys}
NAPPS=${NAPPS:-/data/nemesis/apps}
# 묶음 I: 순정 bcmdhd.ko는 /system/wifi에 있다(니로 리포트가 이 폴더를 보지 않아 "bcmdhd.ko: 아니요"로 틀리게 나왔음)
KMODDIRS=${KMODDIRS:-/system/wifi /system/lib/modules /vendor/lib/modules /system/vendor/lib/modules /lib/modules}
# 묶음 I: 설계 5장의 유무만 보는 경로(내용은 읽지 않음). 시험이 바꾼다
MISCWIFI=${MISCWIFI:-/data/misc/wifi}
SECSOFTAP=${SECSOFTAP:-/securedata/wifi/softap.conf}
INSMOD_SYS=${INSMOD_SYS:-/system/bin/insmod}
# 묶음 J(1.8.0 동글 드라이버 빌드 조사용): 모듈 파일은 40개까지, 8MB가 넘으면 크기만 적고 읽지 않는다(제보 만들기는 이미 CPU를 꽉 씀).
# 펌웨어 폴더·마운트 표는 시험이 바꾼다
KO_MAX=${KO_MAX:-40}
KO_BIG=${KO_BIG:-8388608}
FWDIRS=${FWDIRS:-/system/etc/firmware /vendor/firmware}
KMOUNTS=${KMOUNTS:-/proc/mounts}
# 리뷰 반영: 순정 hostapd는 실행하지 않고 파일에서 판 문자열만 읽는다(실행하면 서비스가 그 짧은 프로세스를 "우리 것이 아닌 hostapd"로 보고
# 우리 AP를 멈출 수 있음). 이 칸은 어떤 바이너리도 실행하지 않는다
STOCK_HOSTAPD=${STOCK_HOSTAPD:-/system/bin/hostapd}
# 허용 글자(영문·숫자·빈칸·. _ : / ( ) + = , # -)만 남기고 80자로 자른다(하위 셸 하나: busybox 1.8.1 awk)
# 베타 2(조사 문서 9-3 진단, 소유자 승인 11-20): 순정 방화벽이 wlan0을 막는가. iptables -S를 awk로 읽어 예/아니요만 낸다
# (규칙 줄 내용·주소는 셸 변수에도 담지 않음). 순정 체인 WL_WLAN0_IN이 있는가, 거기에 카플레이 포트 7000(또는 모든 입력)이 열려 있는가.
# 명령이 없거나 권한이 없어 아무 줄도 못 읽으면 "확인 못 함"
# iptables 읽기는 이 한 곳(-S로 읽기만). 아래 판정 함수들이 쓴다(1.8.1 I-1: 쓰기는 서비스 hotspot.sh fw_aa_sync·fw_aa_down에만 있다)
fw_ipt() { ${IPTABLES:-iptables} -S 2>/dev/null; }
fw_wlan0() {
  _fwo=$(fw_ipt | $BB awk '
    { n++ }
    $1 == "-N" && $2 == "WL_WLAN0_IN" { ch = 1 }
    $1 == "-A" && $2 == "WL_WLAN0_IN" && / -j ACCEPT/ {
      if ($0 ~ /(^|[ ,:])7000([ ,:]|$)/) p = 1
      else if ($0 !~ / --dport| --sport| --dports| --sports| -p /) p = 1 }
    END { if (n == 0) print "x"; else print (ch ? "y" : "n") (p ? "y" : "n") }' 2>/dev/null)
  case "$_fwo" in
    yy) echo "순정 체인(WL_WLAN0_IN) 예, 카플레이 포트(7000) 열림 예" ;;
    yn) echo "순정 체인(WL_WLAN0_IN) 예, 카플레이 포트(7000) 열림 아니요(무선 카플레이를 막을 수 있음)" ;;
    n?) echo "순정 체인(WL_WLAN0_IN) 아니요" ;;
    *) echo "확인 못 함" ;;
  esac
}
# 정식 F6(beta3-reports 11장): 순정 방화벽이 무선 안드로이드 오토 포트(40515, 순정 GPM이 휴대폰에 알리는 TCP 포트)를 막는가.
# 순정 체인 WL_WLAN0_IN에 40515(또는 포트 없는 모두 허용)가 열려 있는가, 무선 모드 2.4.9의 HMG-API 규칙(HMGAPI_IN, aa_firewall)이 들어갔는가.
# 예/아니요만 낸다(규칙 줄·주소는 남기지 않음)
fw_aa() {
  _fwa=$(fw_ipt | $BB awk '
    { n++ }
    $1 == "-N" && $2 == "WL_WLAN0_IN" { ch = 1 }
    # 정식 2차 리뷰 L6: 상태 조건(--state·--ctstate, 예: ESTABLISHED만)이 붙은 줄은 새 연결을 열지 않으므로 40515 열림으로 세지 않는다
    $1 == "-A" && $2 == "WL_WLAN0_IN" && / -j ACCEPT/ && $0 !~ / --(ct)?state / {
      if ($0 ~ /(^|[ ,:])40515([ ,:]|$)/) p = 1
      else if ($0 !~ / --dport| --sport| --dports| --sports| -p /) p = 1 }
    $1 == "-A" && $2 == "HMGAPI_IN" && / -j ACCEPT/ && $0 ~ /--dport 40515( |$)/ { h = 1 }
    END { if (n == 0) print "x"; else print (ch ? "y" : "n") (p ? "y" : "n") (h ? "y" : "n") }' 2>/dev/null)
  case "$_fwa" in
    yy?) echo "순정 체인 예, 순정이 40515를 열어 둠" ;;
    yny) echo "순정 체인 예, 순정은 40515를 막음, 무선 모드 규칙 있음(순정 AP 주소만)" ;;
    ynn) echo "순정 체인 예, 40515 막힘(무선 안드로이드 오토를 막을 수 있음)" ;;
    n??) echo "순정 체인 아니요" ;;
    *) echo "확인 못 함" ;;
  esac
}
# 1.8.1 I-1: 서비스가 넣는 우리 체인(KP_AA_IN) 상태. 예/아니요 꼴만(규칙 줄·주소는 남기지 않음)
fw_kp() {
  _fwk=$(fw_ipt | $BB awk -v ch=KP_AA_IN '
    { n++ }
    $1 == "-P" && $2 == "INPUT" && $3 == "DROP" { d = 1 }
    $1 == "-N" && $2 == ch { c = 1 }
    $1 == "-A" && $2 == "INPUT" && $(NF - 1) == "-j" && $NF == ch { j = 1 }
    $1 == "-A" && $2 == ch { k++; if ($0 ~ / --dport 40515 / && $0 ~ / -j ACCEPT$/) r++ }
    END { if (n == 0) print "x"; else print (d ? "d" : "-") (c ? "c" : "-") (j ? "j" : "-") ((k == 1 && r == 1) ? "r" : "-") }' 2>/dev/null)
  case "$_fwk" in
    ?cjr) echo "있음(우리 AP 대역의 무선 안드로이드 오토 포트만 허용)" ;;
    d---) echo "없음(우리 핫스팟이 꺼져 있거나 아직 넣기 전)" ;;
    ----) echo "없음(방화벽 없는 차라 넣지 않음)" ;;
    x) echo "확인 못 함" ;;
    *) echo "일부만 있음(다음 점검에 다시 맞춤)" ;;
  esac
}
dn_safe() { $BB awk '{ gsub(/[^A-Za-z0-9 ._:\/()+=,#-]/, ""); print substr($0, 1, 80) }' 2>/dev/null; }
# 16진 4자리만 받는다(USB ID). 아니면 빈 값
dn_hex4() { case "$1" in [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) echo "$1" ;; esac; }
# 1.7.4(B-8 ②): 되돌리기 USB가 고정한 판(mod.pin 내용). 고정 없음이면 빈 값, 판 번호면 그 값, 비었거나 숫자·점이 아니면
# "old"(1.7.3 USB가 만든 빈 파일, 2.4.0 고정). 보여 주기만 한다: 고정 여부 판단(mod_pending)은 지금처럼 파일이 있는지만 본다
mod_pin_ver() {
  [ -f $BK/mod.pin ] || return 0
  # 첫 줄만 판 번호로 본다. 둘째 줄에 글자가 있거나(여러 줄), 글자·CR(윈도 줄끝)·빈 값이면 "old"(판 모름)
  _mp=; _mp2=; { { IFS= read -r _mp; IFS= read -r _mp2; } < $BK/mod.pin; } 2>/dev/null
  [ -n "$_mp2" ] && _mp=
  case "$_mp" in ''|*[!0-9.]*|.*) echo old ;; *) echo "$_mp" ;; esac
}
mod_pin_text() { case "$1" in '') echo 없음 ;; old) echo "고정됨(판 모름)" ;; *) echo "$1" ;; esac; }
# 1.7.4: 옛 판(1.7.2 이하)의 칩 실패 기록이 남은 상태(wifi.nochip 있음, wifi.wake 없음). 1.7.3이 새로 쓰는 wifi.nochip은 늘
# wifi.wake와 함께 생기지만, 1.7.2 → 1.7.3 → 1.7.4로 올린 차는 1.7.3이 옛 기록을 그대로 남길 수 있다(리뷰 반영)
# 1.7.4(B-15 가-2): 안내 파일 요약 "부팅 일치 예/아니요, aa=<코드 또는 없음>, aa_ready 있음/없음". 파일이 없으면 "없음".
# aa 값은 영문 소문자만 옮기고(bt·cpwait·ok), 그 밖이면 "기타". 셸만 쓴다(busybox grep 옵션에 기대지 않음)
hint_summary() {
  [ -f $HINT ] || { echo 없음; return 0; }
  _hb=; _ha=; _hr=없음
  while IFS= read -r _hl; do
    case "$_hl" in
      boot=*) _hb=${_hl#boot=} ;;
      aa=*) _ha=${_hl#aa=} ;;
      aa_ready=?*) _hr=있음 ;;
    esac
  done < $HINT
  case "$_ha" in '') _ha=없음 ;; *[!a-z]*) _ha=기타 ;; esac
  if [ -n "$_hb" ] && [ "$_hb" = "$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)" ]; then _hm=예; else _hm=아니요; fi
  echo "부팅 일치 $_hm, aa=$_ha, aa_ready $_hr"
}
kp_legacy_nochip() { [ -f $BK/wifi.nochip ] && [ ! -f $BK/wifi.wake ]; }
dn_first() { _df=; [ -r "$1" ] && { read _df < "$1"; } 2>/dev/null; echo "$_df"; }
# USB 장치 폴더 $1의 "제조사:제품" ID(16진 4자리만, 못 읽으면 없음). 리뷰 반영: USB로 꽂아 둔 폰의 회사·모델이 드러나지 않게,
# 폰 회사 제조사 ID면 제품 ID 대신 "(폰)". 애플 05ac, 삼성 04e8, 구글 18d1, 모토로라 22b8, 샤오미 2717, 화웨이 12d1, LG 1004,
# 오포 22d9, 원플러스 2a70, 소니 0fce, 비보 2d95, HTC 0bb4, 레노버 17ef, 팬택 10a9, ZTE 19d2(에이수스 0b05는 동글 회사라 넣지 않음).
# 동글 진단 USB(usb-donglediag/NEMESIS.sh)에도 같은 함수가 있다(stub-test가 두 곳이 같은지 본다)
# 리뷰 반영(묶음 D 중간 2): 소문자 바꾸기(awk) 없이 셸 case에 대소문자 패턴을 함께 적는다(busybox가 없어도 폰이 가려지게)
dn_is_phone() {
  case "$1" in
    05[aA][cC]|04[eE]8|18[dD]1|22[bB]8|2717|12[dD]1|1004|22[dD]9|2[aA]70|0[fF][cC][eE]|2[dD]95|0[bB][bB]4|17[eE][fF]|10[aA]9|19[dD]2) return 0 ;;
  esac
  return 1
}
dn_usb_id() {
  _iv=$(dn_hex4 "$(dn_first $1/idVendor)"); _ip=$(dn_hex4 "$(dn_first $1/idProduct)")
  dn_is_phone "$_iv" && _ip="(폰)"
  echo "${_iv:-없음}:${_ip:-없음}"
}
# 묶음 I: 링크 폴더(driver)의 실제 이름. cd -P·pwd -P가 안 되는 셸이면 ls -l의 링크 대상(" -> …/이름")으로 내려가고, 그래도 못 읽으면
# "읽지 못함". 링크가 없으면 빈 값(붙은 드라이버 없음). 동글 진단 USB에도 같은 함수가 있다(stub-test가 대조)
dn_link_name() {
  [ -e "$1" ] || return 0
  _ln=$(cd -P "$1" 2>/dev/null && pwd -P)
  if [ -z "$_ln" ]; then
    _ln=$($BB ls -l "$1" 2>/dev/null)
    case "$_ln" in *" -> "*) ;; *) echo "읽지 못함"; return 0 ;; esac
  fi
  echo "${_ln##*/}" | dn_safe
}
# 묶음 I: USB ID 표시(제조사 $1, 제품 $2, 16진). 지원을 약속하는 말이 아니라 "드라이버 표에 있는 ID"인지와 "가상 CD 모드일 수 있음"만.
# 표에 없는 ID를 "지원 안 됨"이라 하지 않는다(A3000MINI·NX-AC1300의 실제 ID는 아직 모름). 동글 진단 USB에도 같은 함수가 있다
dn_id_note() {
  case "$1:$2" in
    0[bB][dD][aA]:[bB]812|0[bB][dD][aA]:[bB]82[cC]|0[bB][dD][aA]:[bB]81[aA]|2357:012[dD]|2357:0138|2357:012[eE]) echo " (RTL88x2BU 드라이버 표에 있는 ID)" ;;
    0[bB][dD][aA]:1[aA]2[bB]|0[bB][dD][aA]:[aA]192) echo " (가상 CD 모드의 동글일 수 있음)" ;;
  esac
}
# 묶음 I: busybox에 그 애플릿이 있는가(인자 없이 부르면 나오는 기능 목록에서 찾음). 예·아니요, 목록이 안 나오면 "확인 안 됨"
dn_bb_has() {
  $BB 2>&1 | $BB awk -v w="$1" '{ n = split($0, a, /[ ,\t]+/); for (i = 1; i <= n; i++) if (a[i] == w) f = 1 } END { if (NR == 0) print "확인 안 됨"; else if (f) print "예"; else print "아니요" }' 2>/dev/null
}
# 베타 2(니로 시험판): 동글 뽑기 기록(서비스가 $BK/dongle.pulls에 남김, dongle.md 4-22). 최근 10회, 숫자·낱말만.
# 결과: 다음 부팅 판정(end 줄) — 뽑기 직후 재부팅 의심 / 견딤 / 붙은 채 끝남(판단 못 함), 이번 부팅이면 20초 기록으로 살아 있음·기록 중
dg_pull_report() {
  echo "- 동글 뽑기 기록(최근 10회, 붙은 채 뽑기 시험):"
  if [ ! -s $DG_PULLF ]; then echo "  - 없음"; return 0; fi
  _dgpcb=; read _dgpcb < ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null
  $BB awk -v cb="$_dgpcb" '
    function num(s) { return (s ~ /^-?[0-9]+$/) ? s : "?" }
    function yn(s) { return s == "y" ? "예" : s == "n" ? "아니요" : "?" }
    function word(s) { return (s ~ /^[a-z]+$/) ? s : "?" }
    function val(k,   i) { for (i = 4; i <= NF; i++) if (index($i, k "=") == 1) return substr($i, length(k) + 2); return "" }
    $3 == "pull" { n++; k = $1 " " $2; idx[k] = n; cur[n] = ($1 == cb); up[n] = num(val("up")); ap[n] = val("ap"); cp[n] = num(val("cp")); sa[n] = num(val("snap_age")); ha[n] = num(val("hapd_ago")); op[n] = word(val("wlan0")); next }
    { k = $1 " " $2; if (!(k in idx)) { if ($3 == "end" && $4 == "att_end") attend = 1; next }; m = idx[k] }
    $3 == "ok20" { ok[m] = 1; at[m] = num(val("attached")); dm[m] = num(val("done_ms")); ng[m] = val("ndev"); ul[m] = val("unload"); pa[m] = num(val("probe_ago")); ao[m] = num(val("aoa")); next }
    $3 == "back" { bk[m] = num(val("up")); next }
    $3 == "other" { ot[m] = 1; next }
    $3 == "back10" { br[m] = num(val("probe_ret")); bs[m] = num(val("probe_step")); bw[m] = val("wlan0"); next }
    $3 == "end" { en[m] = $4; if ($4 == "att_end") attend = 1; next }
    END {
      if (n == 0) { print "  - 없음"; exit }
      s = n > 10 ? n - 9 : 1
      for (i = s; i <= n; i++) {
        if (en[i] == "reboot") r = "뽑기 직후 재부팅 의심(3초 안에 기록 끊김)"
        else if (en[i] == "survived") r = "견딤(뽑은 뒤 60초 넘게 기록 이어짐)"
        else if (en[i] == "cut") r = "판단 못 함(뽑은 뒤 4~59초에 기록 끊김)"
        else if (en[i] == "watcher_end") r = "판단 못 함(감시가 먼저 끝남)"
        else if (ok[i]) r = "살아 있음(20초)"
        else if (cur[i]) r = "기록 중"
        else r = "판단 못 함(20초 기록 없음)"
        print "  - " i ". " (cur[i] ? "이번" : "지난") " 부팅: uptime " up[i] "초, AP " yn(ap[i]) "·카플레이 " cp[i] "(" sa[i] "초 전 점검), AP 시작 뒤 " ha[i] "초, wlan0 " op[i] \
          ", attached " (ok[i] ? at[i] : "-") ", done " (ok[i] ? dm[i] : "-") " ms, 중간 표시 ndev " (ok[i] ? yn(ng[i]) : "-") "·unload " (ok[i] ? yn(ul[i]) : "-") \
          ", 프로브 뒤 " (ok[i] ? pa[i] : "-") "초, 순정 AOA 줄 " (ok[i] ? ao[i] : "-") ", 다시 꽂음 " (bk[i] != "" ? "uptime " bk[i] "초" : (ot[i] ? "다른 장치를 꽂음" : "안 함")) \
          "(probe ret " (br[i] != "" ? br[i] : "-") " step " (bs[i] != "" ? bs[i] : "-") ", wlan0 다시 " (bw[i] != "" ? yn(bw[i]) : "-") "), " r }
      if (attend) print "  - 지난 부팅이 동글이 붙은 채 끝남: 판단 못 함(시동을 끈 것일 수 있음)" }' $DG_PULLF 2>/dev/null
}
# 니로 시험판 4(설계 변경): 순정 Wi-Fi 저장값(지금·원래)·드라이버 상태·순정 HAL이 bcmdhd를 올린 logcat 줄 시각. 숫자·낱말만
dg_wifi_report() {
  _dwr1=$(dg_sget wifi_on); _dwr2=$(dg_sget wifi_scan_always_enabled); _dwr3=$(apon_get)
  _dwo1=-; [ -f $DG_WIFI_ORIG ] && read _dwo1 < $DG_WIFI_ORIG 2>/dev/null
  _dwo2=-; [ -f $DG_SCAN_ORIG ] && read _dwo2 < $DG_SCAN_ORIG 2>/dev/null
  _dwo3=-; [ -f $APON_ORIG ] && read _dwo3 < $APON_ORIG 2>/dev/null
  _dwds=$(getprop wlan.driver.status 2>/dev/null | $BB awk '{ gsub(/[^a-z0-9_]/, ""); print; exit }')
  _dwbm=아니요; $BB grep -q "^$DG_BUILTIN_MOD " /proc/modules 2>/dev/null && _dwbm=예
  # WifiHW 등 순정 HAL의 insmod 줄 시각(이번 부팅 logcat, 끝 3개)
  _dwins=$(lcd | $BB awk '/WifiHW|wifi_load_driver/ && /insmod/ { t[++n] = $1 " " $2 } END { s = n > 3 ? n - 3 : 0; for (i = s + 1; i <= n; i++) o = o (o == "" ? "" : ", ") t[i]; print (n ? o : "없음") }' 2>/dev/null)
  echo "- 순정 Wi-Fi 저장값(시험판 4, 동글 사용 중 0으로 둠): wifi_on ${_dwr1:-?}(원래 ${_dwo1:--}), 스캔 항상 ${_dwr2:-?}(원래 ${_dwo2:--}), wifi_ap_on ${_dwr3:-?}(원래 ${_dwo3:--}), wlan.driver.status ${_dwds:-없음}, bcmdhd 올라옴 $_dwbm, 순정 HAL insmod 줄 ${_dwins:-확인 못 함}"
}
# 니로 시험판 4: 동글 단계 기록(서비스가 $BK/dongle.steps·.prev, dmesg 사본 dongle.kmsg·.prev, 판정 dongle.stepv에 남김).
# 부팅 id는 싣지 않는다(이번·지난 부팅으로만 적음). 줄은 숫자·우리 낱말·가린 dmesg뿐
dg_step_report() {
  echo "- 동글 단계 기록(시험판 4, 내장 Wi-Fi 내리기 직전 ~ 동글이 붙은 뒤 ${DG_STEP_AFTER:-120}초, 1초마다):"
  _dgsr_cb=; read _dgsr_cb < ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null
  if [ -s $DG_STEPV ]; then
    $BB awk '{ v = ($2 == "cut") ? "기록 중에 끊김(그때 재부팅·전원 꺼짐)" : "끝 표시까지 남음"; $1 = ""; $2 = ""; sub(/^ +/, ""); print "  - 지난 판정: " v ", " $0; exit }' $DG_STEPV 2>/dev/null
  fi
  _dgsr_n=0
  # 시험판 6(F9): 네 세대(.prev3 = 세 번째 앞 기록)
  for _dgsr_f in $DG_STEPF.prev3 $DG_STEPF.prev2 $DG_STEPF.prev $DG_STEPF; do
    [ -s $_dgsr_f ] || continue
    _dgsr_n=$((_dgsr_n + 1))
    _dgsr_old=0; [ "$_dgsr_f" = "$DG_STEPF.prev" ] && _dgsr_old=1; [ "$_dgsr_f" = "$DG_STEPF.prev2" ] && _dgsr_old=2; [ "$_dgsr_f" = "$DG_STEPF.prev3" ] && _dgsr_old=3
    $BB awk -v cb="$_dgsr_cb" -v old=$_dgsr_old '
      NR == 1 { w = old == 3 ? "세 번째 앞 기록" : old == 2 ? "두 번째 앞 기록" : old ? "그 앞 기록" : ($1 == "B" && $2 == cb) ? "이번 부팅 기록" : "최근 기록(지난 부팅)"; next }
      $2 == "M" { m[++nm] = $0 } { l[++nl] = $0 }
      END {
        print "  - " w " 표시 줄(uptime초 M 단계):"
        s = nm > 25 ? nm - 25 : 0; for (i = s + 1; i <= nm; i++) print "    " m[i]
        print "  - " w " 끝 12줄(uptime초 S 단계 m순정모듈 d동글모듈 w wlan0 u동글USB s붙음 h hostapd p wpa f설치확인):"
        s = nl > 12 ? nl - 12 : 0; for (i = s + 1; i <= nl; i++) print "    " l[i] }' $_dgsr_f 2>/dev/null
  done
  [ $_dgsr_n = 0 ] && echo "  - 없음"
  # 시험판 5: 부팅 기록(부팅 번호별 early·start·pre-ins 줄, 최근 40줄 중 끝 30줄). 숫자·낱말만
  if [ -s $DG_BOOT0F ]; then
    echo "  - 부팅 기록(#부팅 번호 uptime 때 bcmdhd·88x2bu·wlan0·속성, 부팅 뒤에는 순정 저장값·드라이버 상태·순정 HAL insmod 수와 끝 시각):"
    $BB awk '{ a[NR] = $0 } END { s = NR > 30 ? NR - 30 : 0; for (i = s + 1; i <= NR; i++) print "    " a[i] }' $DG_BOOT0F 2>/dev/null
  fi
  # 베타 3(B3-1·B3-9): 시동 → insmod → 붙음 → AP → 카플레이 시각(부팅 뒤 초, 최근 3부팅)과 가드·버스·순정 AOA·vbus 진단(비공개 파일만)
  if [ -s $DG_TLF ]; then
    echo "  - 시각 기록(#부팅 번호, 부팅 뒤 초: start 서비스 시작·ins 드라이버 올림·probe 동글 붙음·ap 핫스팟·cp 카플레이, way 길):"
    $BB awk '{ a[NR] = $0 } END { s = NR > 3 ? NR - 3 : 0; for (i = s + 1; i <= NR; i++) print "    " a[i] }' $DG_TLF 2>/dev/null
  fi
  # 베타 3(B3-9b): 다시 붙이기 사다리 기록(단계별 ok·no·skip·err, 최근 20번)
  if [ -s $BK/dongle.ladlog ]; then
    echo "  - 다시 붙이기 기록(1 authorized·2 unbind/bind·3 USB 리셋·4 포트 전원, 최근 20번):"
    $BB awk '{ print "    " $0 }' $BK/dongle.ladlog 2>/dev/null
  fi
  # 베타 3(B3-9 기록 3): 서비스 시작 때 복사한 커널 USB 줄(버스 등록·장치 번호·떼어짐·kp-protect 프로브만, 비공개)
  if [ -s $DG_KUSBF ]; then
    echo "  - 커널 USB 줄(서비스 시작 때, 끝 40줄):"
    $BB awk '{ print "    " $0 }' $DG_KUSBF 2>/dev/null
  fi
  for _dgsr_f in $DG_KMSGF.prev3 $DG_KMSGF.prev2 $DG_KMSGF.prev $DG_KMSGF; do
    [ -s $_dgsr_f ] || continue
    echo "  - 커널 줄 사본 끝 30줄(${_dgsr_f##*/}, 드라이버·USB·Wi-Fi·오류 줄만, MAC·번호 가림):"
    $BB awk '{ a[NR] = $0 } END { s = NR > 30 ? NR - 30 : 0; for (i = s + 1; i <= NR; i++) print "    " a[i] }' $_dgsr_f 2>/dev/null
  done
  return 0
}
# 베타 2(니로 시험판): 동글별 기록(서비스가 $BK/dongle.models에 남김). 모델 이름·판정 결과·무선 카플레이 연결만, 최근 부팅
dg_model_report() {
  echo "- 동글별 기록(동글이 붙은 최근 4부팅):"
  if [ ! -s $DG_MODELF ]; then echo "  - 없음"; return 0; fi
  _dgmcb=; read _dgmcb < ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null
  $BB awk -v cb="$_dgmcb" '
    function mname(m) { return m == "A3000MINI" ? "ipTIME A3000MINI" : m == "NX-AC1300" ? "NEXI NX-AC1300" : m == "ArcherT3U" ? "TP-Link Archer T3U" : "목록 밖 동글" }
    # 배포판(소유자 지시 11-23): 판단 결과만(지원 동글 예·아니요)
    function otext(o) { return (o == "ok" || o == "id" || o == "lax") ? "예" : o == "no" ? "아니요" : o == "unk" ? "확인 못 함" : "?" }
    function v(k,   i) { for (i = 3; i <= NF; i++) if (index($i, k "=") == 1) return substr($i, length(k) + 2); return "" }
    { if (!($1 in bseen)) { bseen[$1] = ++nb; border[nb] = $1 } }
    $2 == "seen" { k = $1 SUBSEP v("model"); if (!(k in oui)) { nk++; key[nk] = k; kb[nk] = $1; km[nk] = v("model") } oui[k] = v("oui") }
    $2 == "conn" { conn[$1 SUBSEP v("model")] = 1 }
    END {
      # 시험판 5(메인 11-23, 운행마다 다른 동글): 기록이 있는 최근 4부팅. 이번 부팅이 아니면 "N번째 앞 부팅"(1이 바로 앞)
      for (i = 1; i <= nk; i++) {
        for (j = 1; j <= nb; j++) if (border[j] == kb[i]) bi = j
        if (nb - bi >= 4) continue
        lab = (kb[i] == cb) ? "이번 부팅" : ((nb - bi + (border[nb] == cb ? 0 : 1)) "번째 앞 부팅")
        print "  - " lab ": " mname(km[i]) ", 지원 동글 " otext(oui[key[i]]) ", 무선 카플레이 연결 " (conn[key[i]] ? "예" : "아니요") }
    }' $DG_MODELF 2>/dev/null
}
# 배포판(소유자 지시 11-23): 공개 리포트(1-report.md)에는 동글의 판단 결과만 싣는다.
# 자세한 동글 기록은 dongle_info(비공개 파일, 베타 3부터 $PDIR/5-dongle-private.txt)에만 둔다
dongle_pub() {
  echo "## USB Wi-Fi 동글"
  if [ ! -f $DG_ON ] && [ ! -f $BK/dongle.used ]; then echo "- 동글 사용: 꺼짐"; return 0; fi
  _dps=기록없음; [ -f $W/dongle.state ] && { read _dps1 _dps2 < $W/dongle.state; _dps=$(echo "$_dps1" | dn_safe); }
  _dpo=; _dpo3=; [ -f $DG_OUIF ] && read _dpo _dpox _dpo3 < $DG_OUIF 2>/dev/null; [ "$_dpo3" = "$(dg_kv_bid)" ] || _dpo=
  echo "- 동글 사용: $([ -f $DG_ON ] && echo 켜짐 || echo 꺼짐), 이번 부팅 상태 ${_dps:-기록없음}, 지원 동글 $(dg_oui_text "$_dpo")"
  dg_model_report
  echo "- 동글 자세한 기록은 비공개 파일(KoreaProjection-private)에 있습니다. 공개 이슈에 올리지 말고 요청이 있을 때만 따로 보내 주세요."
  # 베타 3(B3-11·B2-8): 마지막 동글 상태(동글을 빼고 제보를 만들어도 직전 상태가 남음)
  if [ -s $DG_LASTF ]; then
    $BB awk '{ for (i = 1; i <= NF; i++) { split($i, kv, "="); v[kv[1]] = kv[2] }
      s = (v["sup"] == "yes") ? "예" : (v["sup"] == "no") ? "아니요" : "확인 못 함"; c = (v["conn"] == "yes") ? "예" : "아니요"
      print "- 마지막 동글 상태: " v["model"] ", 지원 동글 " s ", 무선 연결 " c " (" v["t"] ")" }' $DG_LASTF 2>/dev/null
  fi
  # 베타 3(B3-9b): 다시 붙이기 사다리의 마지막 결과(몇 단계에서 됐는지만, 방법·경로는 비공개 파일)
  if [ -s $BK/dongle.ladres ]; then
    _dlp1=; _dlp2=; read _dlp1 _dlp2 < $BK/dongle.ladres 2>/dev/null
    case "$_dlp2" in 0) echo "- 동글 다시 붙이기(마지막 시도): 안 됨" ;; [1-4]) echo "- 동글 다시 붙이기(마지막 시도): ${_dlp2}단계에서 됨" ;; esac
  fi
}
dongle_info() {
  # 묶음 J 리뷰(낮음 7): 제목을 "조사"로(지원을 약속하는 말로 읽히지 않게)
  echo "## 동글 조사 정보 (1.8.0 USB Wi-Fi 동글 조사용, 읽기만)"
  # ① 커널 판과 빌드 줄: 판(3번째 낱말)·컴파일러·빌드 표시(# 뒤). 빌드한 사람@호스트 칸은 남기지 않는다
  # 리뷰 반영: 칸마다 따로 구하고 빈 값은 셸에서 "없음"으로 채운다(dn_safe가 한글·?를 지우므로 awk 안에서 채우지 않음)
  if [ -r $KPROC/version ]; then
    _kr=$($BB awk 'NR == 1 { print $3; exit }' $KPROC/version 2>/dev/null | dn_safe)
    _kg=$($BB awk 'NR == 1 { g = $0; if (sub(/.*\(gcc version /, "", g)) { split(g, gg, " "); print gg[1] } exit }' $KPROC/version 2>/dev/null | dn_safe)
    _kb=$($BB awk 'NR == 1 { b = $0; if (sub(/.*\) #/, "#", b)) print b; exit }' $KPROC/version 2>/dev/null | dn_safe)
    echo "- 커널: ${_kr:-없음} / gcc ${_kg:-없음} / 빌드 ${_kb:-없음}"
  else echo "- 커널: 확인 안 됨"; fi
  # 1.8.0 DG-4: 동글 드라이버를 고르는 근거 한 줄(칩·커널 빌드 시각·순정 bcmdhd md5)과 이번 결과. 제보로 칩별 드라이버가 맞는지 확인한다
  _dgc=$(getprop ro.board.platform 2>/dev/null | dn_safe)
  _dgk=; for _d in $KMODDIRS; do [ -f $_d/bcmdhd.ko ] && { _dgk=$_d/bcmdhd.ko; break; }; done
  _dgm=; [ -n "$_dgk" ] && { set -- $($BB md5sum < $_dgk 2>/dev/null); _dgm=$1; }
  case "$_dgm" in [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) ;; *) _dgm= ;; esac
  _dgs=없음; [ -f $W/dongle.state ] && { read _dgs1 _dgs2 < $W/dongle.state; _dgs=$(echo "$_dgs1 $_dgs2" | dn_safe); }
  _dgb=없음; [ -f $DG_BLOCK ] && { read _dgb1 _dgb2 _dgb3 < $DG_BLOCK; _dgb="있음($(echo "$_dgb2 $_dgb3" | dn_safe))"; }
  # 베타 2: 이 부팅에 동글을 wlan0으로 쓰려고 순정 Wi-Fi 드라이버를 내렸는가(이번 부팅 기록만)
  _dgrby=아니요; dg_rm_now && { _dgrby=예; _dgrx2=; read _dgrx1 _dgrx2 < $DG_RMF 2>/dev/null; [ "$_dgrx2" = clean ] && _dgrby="아니요(처음부터 없음, 동글 길 표시만)"; }
  echo "- 동글 드라이버(DG-4): 칩 ${_dgc:-없음}, 커널 빌드 ${_kb:-확인 안 됨}, 순정 bcmdhd md5 ${_dgm:-없음}, 상태 ${_dgs:-없음}, 막힘 기록 $_dgb, 이 부팅 순정 드라이버 내림 $_dgrby, 내린 뒤 다시 올라옴 $([ -f $W/dongle.bcmback ] && echo 예 || echo 아니요)"
  # 베타 2: 동글 판정(DG-3, 결과 낱말만)과 동글 wlan0 위 우리 AP(DG-5)가 이어서 꺼진 횟수·이유 분류
  _dgo=; [ -f $DG_OUIF ] && read _dgo _dgox _dgoy < $DG_OUIF 2>/dev/null
  _dgnp=없음; if [ -f $W/dongle.noap ]; then _dgn1=; _dgn2=; _dgn3=; read _dgn1 _dgn2 _dgn3 < $W/dongle.noap 2>/dev/null; case "$_dgn2" in ''|*[!0-9]*) _dgn2=? ;; esac
    # 이유는 서비스가 정한 분류 낱말만 그대로 둔다(그 밖의 글자는 "모름")
    case "$_dgn3" in "채널 149를 쓸 수 없음(나라 규칙)"|"40MHz 설정을 받지 않음"|"드라이버가 AP 모드를 받지 않음"|"인터페이스를 시작하지 못함") ;; *) _dgn3=모름 ;; esac
    _dgnp="이어서 꺼짐 ${_dgn2}번(이유 $_dgn3)"; fi
  # 배포판: 이 칸(dongle_info)은 비공개 파일에만 들어간다. 판정 결과를 그대로 남긴다
  _dgox=$(echo "${_dgox:-}" | dn_safe)
  # 동글 판정(DG-3) 비공개 기록. 꼴이 맞는 값만 옮긴다
  _dgov=; _dgov1=; [ -f ${DG_OUIVF:-$BK/dongle.ouiv} ] && read _dgov1 _dgov2 _dgov < ${DG_OUIVF:-$BK/dongle.ouiv} 2>/dev/null
  case "$_dgov" in [0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]) ;; *) _dgov= ;; esac
  [ -n "$_dgov" ] && { [ "$_dgov1" = "$(dg_kv_bid)" ] && _dgov="$_dgov(이번 부팅)" || _dgov="$_dgov(지난 부팅)"; }
  echo "- 동글 확인(비공개): 결과 ${_dgo:-기록없음}(ok 앞자리 맞음·no 아님·id 번호로·lax 기록만 받음·unk 못 읽음), USB 번호 ${_dgox:-없음}, 동글 MAC 앞 3바이트 ${_dgov:-기록없음}, 막기 $([ "$DG_OUI_ENFORCE" = 1 ] && echo 켜짐 || echo "꺼짐(기록만)"); 동글 AP(DG-5): $_dgnp"
  # 베타 2 AOA 가드: 켬/꺼짐, 동글이 막힌 자리에 붙었는가, 지금 남은 우리 빈 폴더 수(번호·이름 없이 숫자만)
  _dga=; _dgas=; [ -f $W/aoa.state ] && read _dga1 _dga _dgas < $W/aoa.state 2>/dev/null
  case "$_dga" in blocked) _dga="동글 자리 막힘" ;; open) _dga="동글 자리에 노드가 있음(막지 못함)" ;; none) _dga="동글 자리 없음" ;; *) _dga="동글 자리 기록 없음" ;; esac
  case "$_dgas" in yes) _dgas=예 ;; no) _dgas=아니요 ;; *) _dgas="확인 못 함" ;; esac
  _dgan=0; [ -f $DG_AOAF ] && _dgan=$($BB awk 'NR > 1 { n++ } END { print n + 0 }' $DG_AOAF 2>/dev/null)
  # 순정 AOA 시도 줄 수(logcat, 수만)
  # 시험판 6(F7): 순정 AA의 USB 길 시작·결과 줄도 센다(hotspot.sh dg_aoa_count와 같은 꼴)
  _dgaa=$(lcd | $BB awk '/startAccessory|locateGoogleDevice|UsbAccesory|UsbTransport : init|mUsbTransport\.init\(\) ret/ { n++ } END { print n + 0 }' 2>/dev/null)
  # 베타 2(R7, 여섯 번째 차): 가드 전 순정 AOA 줄은 서비스 시작 때 센 값($W/dg.eaoa, 이번 부팅)을 따로 보인다. 제보 때 logcat 버퍼는
  # 디버그 로그로 돌아 부팅 앞부분이 지워졌을 수 있다(17줄 → 0)
  _dgae=기록없음; _dgae1=; _dgae2=; [ -f $W/dg.eaoa ] && read _dgae1 _dgae2 < $W/dg.eaoa 2>/dev/null
  [ "$_dgae1" = "$(dg_kv_bid)" ] && case "$_dgae2" in ''|*[!0-9]*) ;; *) _dgae=$_dgae2 ;; esac
  _dgee=기록없음; _dgee1=; _dgee2=; [ -f $W/dg.early ] && read _dgee1 _dgee2 _dgee3 < $W/dg.early 2>/dev/null
  [ "$_dgee1" = "$(dg_kv_bid)" ] && case "$_dgee2" in blocked) _dgee="동글 자리 막힘(가드가 먼저)" ;; swapped) _dgee="가드 전 노드를 빈 폴더로 바꿈" ;; keep) _dgee="가드 전 노드를 못 바꿈" ;; none) _dgee="가드가 먼저 걸림(그때 동글 없음)" ;; esac
  echo "- AOA 가드: $([ -f $BK/dongle.noguard ] && echo "꺼짐(noguard)" || echo 켬), $_dga, 동글 버스와 같음 $_dgas, 막은 빈 폴더 ${_dgan:-0}개"
  echo "  - 이번 부팅 가드 시작: $_dgee, 서비스 시작 때 센 순정 AOA 줄 $_dgae, 지금 logcat 버퍼의 순정 AOA 줄 ${_dgaa:-?}"
  dg_pull_report
  dg_model_report
  dg_step_report
  dg_wifi_report
  # 1.8.0 SC-5: 토글과 자동 판단 근거 한 줄
  _dgw0=; [ -f $DG_AUTO ] && read _dgw1 _dgw0 _dgw2 < $DG_AUTO 2>/dev/null
  _dgt=$( { if [ -f $DG_ON ]; then echo "t=on"; else echo "t=off"; fi; dg_toggle_kv; echo "raw=$_dgw0"; } | $BB awk -F= '{ v[$1] = $2 } END { t = v["t"] == "on" ? "켜짐" : "꺼짐"; s = v["dongle_set"]; w = v["dongle_why"]; r = v["raw"]
    if (s == "on" || s == "off") print t "(차주 선택)"
    else if (w == "nochip" || w == "builtin_bad") print t "(자동, 근거 " (r == "nopart" ? "부품 없음" : r == "nochip" ? "칩이 켜지지 않음" : r == "nowlan" ? "여러 부팅 wlan0 없음" : "모름") ")"
    else if (w == "nodongle") print t "(자동 대기: 근거는 있으나 허용 동글·드라이버 없음)"
    else print t "(기본값, 내장 Wi-Fi 사용)" }')
  echo "- 동글 토글(SC-5): ${_dgt:-확인 안 됨}"
  # ② 올라온 모듈(이름만)과 Wi-Fi 모듈의 판 정보
  # 묶음 I: 80자에서 잘리지 않게 이름을 10개씩 한 줄로, 20줄(200개)까지(니로 리포트가 "vpu_d6_"에서 끊겼음). 이름 글자는 영문·숫자·_-만, 40자까지
  if [ -r $KPROC/modules ]; then
    _mods=$($BB awk '{ m = $1; gsub(/[^A-Za-z0-9_-]/, "", m); m = substr(m, 1, 40); if (m == "") next; n++
        if (n > 200) next; l = l (l == "" ? "" : " ") m; if (n % 10 == 0) { print "  - " l; l = "" } }
      END { if (l != "") print "  - " l; print "#" n + 0 }' $KPROC/modules 2>/dev/null)
    _mn=${_mods##*#}; _mods=${_mods%#*}
    case "$_mn" in ''|*[!0-9]*) echo "- 올라온 모듈: 확인 안 됨" ;;
      0) echo "- 올라온 모듈: 없음" ;;
      *) if [ "$_mn" -gt 200 ]; then echo "- 올라온 모듈(${_mn}개, 앞 200개만):"; else echo "- 올라온 모듈(${_mn}개):"; fi
         $BB printf '%s' "$_mods" ;;
    esac
  else echo "- 올라온 모듈: 확인 안 됨"; fi
  # 묶음 I: cfg80211·bcmdhd·mac80211은 커널 내장인지 올린 모듈인지(/sys/module/<이름>/initstate가 있으면 올린 모듈, 폴더만 있으면 내장)
  for _m in bcmdhd dhd cfg80211 mac80211; do
    if [ ! -d $KSYS/module/$_m ]; then
      [ $_m = dhd ] || echo "- 모듈 $_m: 없음 (/sys/module에 없음)"
      continue
    fi
    if [ -e $KSYS/module/$_m/initstate ]; then _mk="올린 모듈"; else _mk="커널 내장"; fi
    _mv=$(dn_first $KSYS/module/$_m/version | dn_safe); _ms=$(dn_first $KSYS/module/$_m/srcversion | dn_safe)
    echo "- 모듈 $_m: 있음 ($_mk, version ${_mv:-없음}, srcversion ${_ms:-없음})"
  done
  # ③ 모듈을 받는 조건: 서명 강제·모듈 금지·config.gz의 관련 줄(있으면)
  # 묶음 I: sig_enforce 파일이 없으면 "파일 없음"(서명 강제 기능이 커널에 없을 수 있음)
  if [ -e $KSYS/module/module/parameters/sig_enforce ]; then _se=$(dn_first $KSYS/module/module/parameters/sig_enforce | dn_safe); _se=${_se:-확인 안 됨}; else _se="파일 없음(서명 기능 없음으로 봄)"; fi
  _md=$(dn_first $KPROC/sys/kernel/modules_disabled | dn_safe)
  echo "- 모듈 서명 강제(sig_enforce): $_se, 모듈 금지(modules_disabled): ${_md:-확인 안 됨}"
  # 묶음 I: 모듈을 올리는 도구가 있는가(실행하지 않음. busybox는 기능 목록만 봄)
  echo "- insmod: $INSMOD_SYS $(yn [ -f $INSMOD_SYS ]), busybox 애플릿 $(dn_bb_has insmod)"
  if [ -r $KPROC/config.gz ]; then
    _cf=$($BB gunzip -c $KPROC/config.gz 2>/dev/null | $BB grep -E '^(# )?CONFIG_(MODULES|MODULE_SIG[A-Z_]*|MODVERSIONS|MODULE_FORCE_LOAD|MODULE_UNLOAD|CFG80211|MAC80211|WIRELESS|USB_EHCI_HCD|USB_XHCI_HCD|USB_DWC[0-9]?|RTL[0-9A-Z_]*)[ =]' | $BB awk 'NR <= 30' | dn_safe)
    if [ -n "$_cf" ]; then echo "- 커널 설정(config.gz, 관련 줄만):"; echo "$_cf" | $BB awk '{ print "  - " $0 }'; else echo "- 커널 설정(config.gz): 읽지 못함"; fi
  else echo "- 커널 설정(config.gz): 없음"; fi
  # ④ 무선 틀(cfg80211)이 커널에 있는가: kallsyms 기호 수(개수만), ieee80211 클래스
  # 묶음 J: /proc/kallsyms는 한 번만 읽는다(awk 하나). 주소는 쓰지 않고, 기호 이름 셋째 칸만 본다. cfg80211이 든 줄 수(예전 칸)와
  # 접두사별 개수, 그 이름들만 정렬한 목록의 md5 한 줄(차끼리 같은 커널인지 묶는 용도). 이름 목록 자체는 적지 않는다
  _ks=; _ksum=; _kcnt=
  if [ -r $KPROC/kallsyms ]; then
    _kx=$($BB awk '{ n = $3; if (index($0, "cfg80211") > 0) c++
        k = ""; if (index(n, "cfg80211_") == 1) k = "a"; else if (index(n, "ieee80211_") == 1) k = "b"; else if (index(n, "usb_") == 1) k = "c"
        else if (index(n, "netif_") == 1) k = "d"
        else if (n == "register_netdev" || n == "unregister_netdev" || n == "register_netdevice" || n == "unregister_netdevice" || index(n, "alloc_netdev") == 1 || index(n, "alloc_etherdev") == 1) k = "e"
        if (k != "") { m[k]++; gsub(/[^A-Za-z0-9_.]/, "", n); print n } }
      END { print "~" c + 0 " " m["a"] + 0 " " m["b"] + 0 " " m["c"] + 0 " " m["d"] + 0 " " m["e"] + 0 }' $KPROC/kallsyms 2>/dev/null)
    _kcnt=${_kx##*~}
    case "$_kcnt" in [0-9]*" "[0-9]*" "[0-9]*" "[0-9]*" "[0-9]*" "[0-9]*) ;; *) _kcnt= ;; esac
    if [ -n "$_kcnt" ]; then
      set -- $_kcnt; _ks=$1
      _ksum=$(echo "$_kx" | $BB awk 'substr($0, 1, 1) != "~"' | LC_ALL=C $BB sort | $BB md5sum 2>/dev/null); set -- $_ksum; _ksum=$1
      case "$_ksum" in [0-9a-f]*) ;; *) _ksum= ;; esac
      set -- $_kcnt
      _kcnt="cfg80211_ $2, ieee80211_ $3, usb_ $4, netif_ $5, netdev 등록·할당 $6"
    fi
  fi
  case "$_ks" in ''|*[!0-9]*) _ks="kallsyms 확인 안 됨" ;; *) _ks="kallsyms 기호 ${_ks}개" ;; esac
  echo "- cfg80211: ${_ks}, /sys/class/ieee80211: $(yn [ -d $KSYS/class/ieee80211 ])"
  echo "- 커널 기호 수(1.8.0 조사용, 이름은 적지 않음): ${_kcnt:-읽지 못함}"
  echo "- 위 기호 이름 목록(정렬)의 md5: ${_ksum:-읽지 못함}"
  # 묶음 J: 커널 주소 가리기(kptr_restrict)와 커널 오염 표시(tainted)
  _kp=$(dn_first $KPROC/sys/kernel/kptr_restrict | dn_safe); _kt=$(dn_first $KPROC/sys/kernel/tainted | dn_safe)
  echo "- kptr_restrict: ${_kp:-읽지 못함}, tainted: ${_kt:-읽지 못함}"
  # 묶음 I: 무선 규제 국가(cfg80211 파라미터, 두 글자 국가 코드)
  _rd=$(dn_first $KSYS/module/cfg80211/parameters/ieee80211_regdom | dn_safe)
  echo "- cfg80211 규제 국가(ieee80211_regdom): ${_rd:-없음}"
  # ⑤ SoC·보드 이름(속성과 cpuinfo의 Hardware 줄)
  _hw=$($BB awk -F: '/^Hardware/ { sub(/^[ \t]+/, "", $2); print $2; exit }' $KPROC/cpuinfo 2>/dev/null | dn_safe)
  echo "- SoC·보드: platform $(getprop ro.board.platform 2>/dev/null | dn_safe), board $(getprop ro.product.board 2>/dev/null | dn_safe), hardware $(getprop ro.hardware 2>/dev/null | dn_safe), cpuinfo ${_hw:-확인 안 됨}"
  # ⑥ SELinux 상태(1 강제, 0 허용, 없으면 꺼짐)
  if [ -r $KSYS/fs/selinux/enforce ]; then _sl=$(dn_first $KSYS/fs/selinux/enforce | dn_safe); else _sl=없음; fi
  echo "- SELinux enforce: ${_sl:-확인 안 됨}"
  # ⑦ 순정 hostapd 판(첫 줄의 "hostapd v…"만)
  # 리뷰 반영(묶음 C 중간 1): 명령줄 어디에도 "hostapd" 글자가 남지 않게 한다. 서비스의 stock_ap_on·other_hostapd_pids가 ps에서
  # "hostapd"를 찾으므로, 리포트를 만드는 동안 그 글자가 든 명령이 돌면 우리 AP를 비켜 줄 수 있다(ap_yield).
  # 파일은 표준입력으로 넘기고(strings 인자에 경로 없음), awk 찾을 말은 두 조각(-v a=hos b=tapd)으로 넘겨 이어 붙인다.
  # busybox 1.8.1 strings가 표준입력을 받지 못하면 빈 값 → "확인 안 됨" [차에서 확인]
  _hv=; [ -f "$STOCK_HOSTAPD" ] && _hv=$($BB strings < "$STOCK_HOSTAPD" 2>/dev/null | $BB awk -v a=hos -v b=tapd '{ w = a b " v"; if (index($0, w) == 1 && substr($0, length(w) + 1, 1) ~ /[0-9]/) { print $1 " " $2; exit } }' | dn_safe)
  echo "- 순정 hostapd 판: ${_hv:-확인 안 됨}"
  # 내장 Wi-Fi .ko: 이름(bcmdhd 등)과 vermagic(strings가 되면). 파일 이름만 남긴다
  _kn=0; _kseen=" "; _kdirs=
  for _d in $KMODDIRS; do
    # 리뷰 반영: /vendor가 /system/vendor 링크인 차에서 같은 .ko를 두 번 쓰지 않게 실제 경로로 한 번만 본다
    _kr2=$(cd "$_d" 2>/dev/null && pwd -P) || continue
    case "$_kseen" in *" $_kr2 "*) continue ;; esac; _kseen="$_kseen$_kr2 "
    _kdirs="$_kdirs $_d"
    for _k in $_d/*.ko; do
      [ -f "$_k" ] || continue; _kn=$((_kn+1))
      # 묶음 J: 40개까지. 실제 경로(어느 폴더에서 찾았는지)·크기·md5·디버그 정보 유무를 더한다. strings는 한 번만 읽고 그 출력에서
      # vermagic과 .debug_info를 함께 찾는다(파일을 두 번 훑지 않음). md5는 따로 한 번. 8MB가 넘으면 크기만 적고 읽지 않는다
      if [ $_kn -gt $KO_MAX ]; then [ $_kn = $((KO_MAX+1)) ] && echo "- 모듈 파일: ${KO_MAX}개가 넘어 나머지는 적지 않음"; continue; fi
      _kz=$($BB ls -ln "$_k" 2>/dev/null | $BB awk '{ print $5; exit }')
      case "$_kz" in ''|*[!0-9]*) _kz= ;; esac
      _kpath=$(echo "$_kr2/${_k##*/}" | dn_safe)
      # 묶음 J 리뷰(낮음 4): 심볼릭 링크이거나 크기를 못 읽으면 읽지 않는다(8MB 상한을 피해 가지 않게)
      if [ -L "$_k" ] || [ -z "$_kz" ]; then echo "- 모듈 파일: $_kpath 크기 읽지 못함, 건너뜀"; continue; fi
      if [ "$_kz" -gt $KO_BIG ]; then
        echo "- 모듈 파일: $_kpath 크기 $_kz (큼, md5·vermagic·디버그 정보는 건너뜀)"; continue
      fi
      if [ ! -r "$_k" ]; then echo "- 모듈 파일: $_kpath 크기 ${_kz:-읽지 못함} (읽지 못함)"; continue; fi
      # 묶음 J 리뷰(중간): 순정 .ko(니로 8개 모두)는 strings에 섹션 이름이 .rel.debug_info로만 나온다. 셋 다 본다.
      # strings가 아무것도 내지 않으면(실패·글자 없음) "아니요"가 아니라 "읽지 못함"
      _vd=$($BB strings "$_k" 2>/dev/null | $BB awk '/^vermagic=/ && v == "" { v = $0 } $0 == ".debug_info" || $0 == ".rel.debug_info" || $0 == ".rela.debug_info" { d = 1 }
        END { if (NR == 0) print "읽지 못함@"; else print (d ? "예" : "아니요") "@" v }')
      _kd=${_vd%%@*}; _vm=$(echo "${_vd#*@}" | dn_safe); [ -n "$_vd" ] || _kd="읽지 못함"
      set -- $($BB md5sum < "$_k" 2>/dev/null); _k5=$1; case "$_k5" in [0-9a-f]*) ;; *) _k5="읽지 못함" ;; esac
      echo "- 모듈 파일: $_kpath 크기 ${_kz:-읽지 못함} md5 $_k5 디버그 정보 $_kd (${_vm:-vermagic 확인 안 됨})"
    done
  done
  [ $_kn = 0 ] && echo "- 모듈 파일(.ko): 없음"
  echo "- bcmdhd.ko: $(_b=아니요; for _d in $KMODDIRS; do [ -f $_d/bcmdhd.ko ] && _b=예; done; echo $_b)"
  # 묶음 I: 펌웨어 파일(.bin)은 있는지만(경로·이름). 내용은 읽지 않는다. 10개까지, 같은 실제 폴더는 한 번(위 .ko와 같은 목록)
  _fn=0
  for _d in $_kdirs; do
    for _f in $_d/*.bin; do
      [ -f "$_f" ] || continue; _fn=$((_fn+1)); [ $_fn -le 10 ] || continue
      echo "- 펌웨어 파일: $(echo "$_f" | dn_safe) 있음"
    done
  done
  [ $_fn = 0 ] && echo "- 펌웨어 파일(.bin): 없음"
  # SDIO·MMC 장치: SDIO는 vendor·device(16진)·class, MMC는 type만(이름·cid·serial은 남기지 않음)
  _sn=0
  for _s in $KSYS/bus/sdio/devices/*; do
    [ -d "$_s" ] || continue; _sn=$((_sn+1))
    echo "- SDIO 장치: vendor $(dn_first $_s/vendor | dn_safe) device $(dn_first $_s/device | dn_safe) class $(dn_first $_s/class | dn_safe)"
  done
  [ $_sn = 0 ] && echo "- SDIO 장치: 없음"
  _mn=0
  for _s in $KSYS/bus/mmc/devices/*; do
    [ -d "$_s" ] || continue; _mn=$((_mn+1))
    echo "- MMC 장치: $(echo "${_s##*/}" | dn_safe) type $(dn_first $_s/type | dn_safe)"
  done
  [ $_mn = 0 ] && echo "- MMC 장치: 없음"
  # softap.conf 위치(경로만, 내용은 읽지 않음)
  echo "- softap.conf 위치: $SRC ($(yn [ -f $SRC ]))"
  # 묶음 I(설계 5장): 순정이 쓰는 장치 이름 속성, hostapd 폴더·/securedata의 softap.conf 유무(내용은 읽지 않음)
  _wi=$(getprop wifi.interface 2>/dev/null | dn_safe); _ws=$(getprop wlan.driver.status 2>/dev/null | dn_safe)
  echo "- Wi-Fi 속성: wifi.interface ${_wi:-없음}, wlan.driver.status ${_ws:-없음}"
  echo "- $MISCWIFI/hostapd 폴더: $(yn [ -d $MISCWIFI/hostapd ]), $SECSOFTAP: $(if [ -e $SECSOFTAP ]; then echo 있음; else echo 없음; fi)"
  # ⑧⑨ USB: 루트 허브와 장치마다 제조사·제품 ID·클래스·속도(일련번호·이름 문자열은 읽지 않음)
  # 묶음 I: 장치마다 인터페이스 수(bNumInterfaces)·인터페이스 class·붙은 드라이버 이름·전류(bMaxPower), 허브는 포트 수(maxchild).
  # ID가 드라이버 표에 있거나 가상 CD 모드일 수 있으면 표시(dn_id_note). 폰은 dn_usb_id가 제품 ID를 가린다
  _un=0
  for _u in $KSYS/bus/usb/devices/*; do
    [ -r "$_u/idVendor" ] || continue; _un=$((_un+1))
    _ic=$(dn_first $_u/bDeviceClass | dn_safe); _isp=$(dn_first $_u/speed | dn_safe)
    _ni=$(dn_first $_u/bNumInterfaces | dn_safe); _ni=${_ni# }; _mp=$(dn_first $_u/bMaxPower | dn_safe)
    _ifc=; _drv=
    for _i in $_u/*:*; do
      [ -d "$_i" ] || continue
      _c2=$(dn_first $_i/bInterfaceClass | dn_safe); _ifc="$_ifc${_ifc:+ }${_c2:-?}"
      _d2=$(dn_link_name $_i/driver); [ -n "$_d2" ] && _drv="$_drv${_drv:+ }$_d2"
    done
    _ex=; [ "$_ic" = 09 ] && { _mc=$(dn_first $_u/maxchild | dn_safe); _ex=", 포트 ${_mc:-없음}"; }
    _id=$(dn_usb_id $_u)
    echo "- USB $(echo "${_u##*/}" | dn_safe): $_id class ${_ic:-없음} speed ${_isp:-없음}, 인터페이스 ${_ni:-?}개(${_ifc:-없음}), 드라이버 ${_drv:-없음}, 전류 ${_mp:-없음}$_ex$(dn_id_note ${_id%%:*} ${_id#*:})"
  done
  [ $_un = 0 ] && echo "- USB 장치: 확인 안 됨"
  # 묶음 I: 지난 부팅들에 꽂혀 있던 USB 장치(서비스가 부팅마다 한 번 남긴 $USBSEEN, 최근 3부팅). 포트가 하나뿐인 차에서
  # "동글을 꽂고 시동 → 동글을 빼고 USB를 꽂아 제보"로 동글 정보를 얻는 길. 파일 값은 서비스가 이미 걸렀고, 여기서도 dn_safe를 거친다
  if [ -f "$USBSEEN" ]; then
    echo "- 지난 부팅들에 꽂혀 있던 USB 장치(서비스 시작 때 기록, 허브 빼고, 오래된 부팅부터):"
    _ubn=0; _ubl=0
    while IFS= read -r _l; do
      _ubl=$((_ubl+1)); [ $_ubl -le 70 ] || break
      case "$_l" in
        "boot "*) _ubn=$((_ubn+1)); echo "  - 부팅 $_ubn" ;;
        none) echo "    - 꽂힌 장치 없음" ;;
        *) _uid=${_l%% *}; echo "    - $(echo "$_l" | dn_safe)$(dn_id_note ${_uid%%:*} ${_uid#*:})" ;;
      esac
    done < "$USBSEEN"
  else echo "- 지난 부팅들에 꽂혀 있던 USB 장치: 기록 없음"; fi
  # 묶음 I·묶음 J 리뷰(중간): USB를 꽂을 때의 커널 줄. **허용한 꼴만** 통과시키고 나머지는 버린다(금지 줄만 버리면 HID 줄의
  # "[Apple Inc. iPhone]"·폰 제품 ID 같은 예상 못 한 글자가 남음). 통과한 줄도 원문을 내보내지 않고, 정해진 낱말과 숫자·16진·
  # 정해진 글자의 값만으로 다시 조립한다. 폰 회사 제조사 ID면 제품 ID를 가린다(dn_is_phone과 같은 목록). 마지막 20줄까지
  _dm=$({ if [ -n "$KP_DMESG" ]; then cat $KP_DMESG; else dmesg; fi; } 2>/dev/null | $BB awk '
    function num(s, k,   i, r) { i = index(s, k); if (i == 0) return ""; r = substr(s, i + length(k)); sub(/[^-0-9].*/, "", r)
      if (r !~ /^-?[0-9]+$/) return ""; return substr(r, 1, 6) }
    function hx(s, k,   i, r) { i = index(s, k); if (i == 0) return ""; r = substr(s, i + length(k), 4); if (r !~ /^[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$/) return ""; return tolower(r) }
    function wd(s, k,   i, r) { i = index(s, k); if (i == 0) return ""; r = substr(s, i + length(k)); sub(/[ ,].*/, "", r)
      if (r !~ /^[a-z0-9_-]+$/) return ""; return substr(r, 1, 24) }
    { r = $0; ts = ""
      if (substr(r, 1, 1) == "<") { i = index(r, ">"); if (i < 2 || i > 5 || substr(r, 2, i - 2) !~ /^[0-9]+$/) next; r = substr(r, i + 1) }
      if (substr(r, 1, 1) == "[") { i = index(r, "]"); if (i == 0) next; ts = substr(r, 2, i - 2); gsub(/ /, "", ts); if (ts !~ /^[0-9]+\.[0-9]+$/) ts = ""; r = substr(r, i + 1); sub(/^ +/, "", r) }
      n = split(r, w, " "); if (n < 3) next
      if (w[1] != "usb" && w[1] != "hub") next
      p = w[2]; if (p !~ /^[0-9]+-[0-9.:]+:$/) next; p = substr(p, 1, length(p) - 1)
      b = substr(r, index(r, w[2]) + length(w[2]) + 1); o = ""
      if (index(b, "over-current") == 1) { o = "over-current" (index(b, "change") > 0 ? " change" : ""); q = num(b, "port "); if (q != "") o = o " on port " q }
      else if (w[1] != "usb") next
      else if (index(b, "new ") == 1 && index(b, " USB device number ") > 0) {
        sp = w[4]; if (tolower(sp) !~ /^(low|full|high|super|wireless)(-?speed(-plus)?)?$/) sp = "?"; q = num(b, "number "); d = wd(b, "using "); if (q == "") next
        o = "new " sp " USB device number " q (d != "" ? " using " d : "") }
      else if (index(b, "New USB device found,") == 1) {
        v = hx(b, "idVendor="); pr = hx(b, "idProduct="); if (v == "") next
        if (index(" 05ac 04e8 18d1 22b8 2717 12d1 1004 22d9 2a70 0fce 2d95 0bb4 17ef 10a9 19d2 ", " " v " ") > 0) pr = "phone"
        o = "New USB device found, idVendor=" v ", idProduct=" (pr != "" ? pr : "?") }
      else if (index(b, "USB disconnect, device number ") == 1) { q = num(b, "number "); if (q == "") next; o = "USB disconnect, device number " q }
      else if (index(b, "device descriptor read/") == 1) { k = wd(b, "read/"); e = num(b, "error "); if (k == "" || e == "") next; o = "device descriptor read/" k ", error " e }
      else if (index(b, "device not accepting address ") == 1) { q = num(b, "address "); e = num(b, "error "); if (q == "" || e == "") next; o = "device not accepting address " q ", error " e }
      else if (index(b, "can") == 1 && index(b, "t set config") == 5) { q = num(b, "#"); e = num(b, "error "); o = "can not set config" (q != "" ? " #" q : "") (e != "" ? ", error " e : "") }
      else if (index(b, "rejected") > 0 && index(b, "power") > 0) { o = "configuration rejected (insufficient bus power)" }
      else next
      a[++m] = (ts != "" ? "[" ts "] " : "") w[1] " " p ": " o }
    END { s = m > 20 ? m - 19 : 1; for (i = s; i <= m; i++) print a[i] }' 2>/dev/null | lastmask 20)
  if [ -n "$_dm" ]; then echo "- USB를 꽂을 때의 커널 줄(dmesg, 정해 둔 꼴만 다시 적음, 마지막 20줄까지):"; echo "$_dm" | $BB awk '{ print "  - " $0 }'
  else echo "- USB를 꽂을 때의 커널 줄(dmesg): 없음"; fi
  # ⑩ 네트워크 장치 이름 목록(무선인지 표시). 이름은 커널이 붙인 것(wlan0·rtwlan0 등)
  _nl=
  for _n in $KSYS/class/net/*; do
    [ -e "$_n" ] || continue
    _nm=$(echo "${_n##*/}" | dn_safe)
    if [ -d "$_n/wireless" ] || [ -e "$_n/phy80211" ]; then _nl="$_nl $_nm(무선)"; else _nl="$_nl $_nm"; fi
  done
  echo "- 네트워크 장치:${_nl:- 확인 안 됨}"
  # 묶음 J(1.8.0 조사용): USB 드라이버 이름 목록(/sys/bus/usb/drivers 아래 이름만, 영문·숫자·_- 만, 10개씩 4줄까지)
  _ud=$(for _x in $KSYS/bus/usb/drivers/*; do [ -d "$_x" ] && echo "${_x##*/}"; done | $BB awk '{ gsub(/[^A-Za-z0-9_-]/, ""); if ($0 == "") next; n++; if (n > 40) next
      l = l (l == "" ? "" : " ") substr($0, 1, 30); if (n % 10 == 0) { print "  - " l; l = "" } } END { if (l != "") print "  - " l }' 2>/dev/null)
  if [ -n "$_ud" ]; then echo "- USB 드라이버(/sys/bus/usb/drivers, 이름만):"; echo "$_ud"; else echo "- USB 드라이버(/sys/bus/usb/drivers): 없음"; fi
  # 묶음 J: bcmdhd 모듈 파라미터 이름과 값(펌웨어·보정 파일 경로 등). 영문·숫자·/._- 만, 값 80자, 60개까지(넘으면 "나머지 N개 생략").
  # 묶음 J 리뷰(낮음 1·2): 이름에 mac·addr·serial이 들면 값을 적지 않고 "가림". 값의 MAC 꼴(:·- 로 이음, 12자리 16진 한 덩어리)은 가린다.
  # 점 넷 숫자는 IP 꼴로 가리되, 이름이 info_string이거나 version이 들었거나 값이 version·ver로 시작하면 판 번호로 보고 둔다(헷갈리면 가림)
  _bpn=0
  for _x in $KSYS/module/bcmdhd/parameters/*; do
    [ -f "$_x" ] || continue; _bpn=$((_bpn+1)); [ $_bpn -le 60 ] || continue
    [ $_bpn = 1 ] && echo "- bcmdhd 파라미터(1.8.0 조사용, MAC·IP·일련번호 꼴은 가림):"
    _bn=$(echo "${_x##*/}" | dn_safe)
    case "$_bn" in *[mM][aA][cC]*|*[aA][dD][dD][rR]*|*[sS][eE][rR][iI][aA][lL]*) echo "  - $_bn = 가림"; continue ;; esac
    _bv=; [ -r "$_x" ] && { read -r _bv < "$_x"; } 2>/dev/null
    _bv=$(echo "$_bv" | $BB awk -v nm="$_bn" '{ v = $0; l = tolower(v); sub(/^ +/, "", l)
      gsub(/[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]/, "mac-masked", v); gsub(/[0-9A-Fa-f][0-9A-Fa-f]-[0-9A-Fa-f][0-9A-Fa-f]-[0-9A-Fa-f][0-9A-Fa-f]-[0-9A-Fa-f][0-9A-Fa-f]-[0-9A-Fa-f][0-9A-Fa-f]-[0-9A-Fa-f][0-9A-Fa-f]/, "mac-masked", v)
      t = v; gsub(/^ +| +$/, "", t); if (t ~ /^[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$/) v = "mac-masked"
      keep = (nm == "info_string" || index(tolower(nm), "version") > 0 || index(l, "version") == 1 || index(l, "ver ") == 1 || index(l, "ver:") == 1 || index(l, "ver=") == 1)
      if (!keep) gsub(/[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*/, "ip-masked", v)
      gsub(/[^A-Za-z0-9\/._-]/, "", v); print substr(v, 1, 80) }' 2>/dev/null)
    echo "  - $_bn = ${_bv:-읽지 못함 또는 빈 값}"
  done
  [ $_bpn -gt 60 ] && echo "  - 나머지 $((_bpn - 60))개 생략"
  [ $_bpn = 0 ] && echo "- bcmdhd 파라미터: 없음"
  _fp=$(dn_first $KSYS/module/firmware_class/parameters/path | $BB awk '{ gsub(/[^A-Za-z0-9\/._-]/, ""); print substr($0, 1, 80) }' 2>/dev/null)
  echo "- 펌웨어 찾는 경로(firmware_class path): ${_fp:-없음}"
  _fd=; for _x in $FWDIRS; do _fd="$_fd${_fd:+, }$_x $(yn [ -d $_x ])"; done
  echo "- 펌웨어 폴더: $_fd"
  # 묶음 J: /data·/system 마운트 옵션(noexec·ro가 보이게). 장치 이름은 숫자를 N으로 바꾼 꼴만
  _mt=$($BB awk '$2 == "/data" || $2 == "/system" { d = $1; gsub(/[0-9]+/, "N", d); gsub(/[^A-Za-z0-9\/._-]/, "", d); f = $3; gsub(/[^A-Za-z0-9_-]/, "", f)
      p = $4; gsub(/[^A-Za-z0-9_,=-]/, "", p); o = "," p ","
      print "  - " $2 ": " substr(d, 1, 40) " " substr(f, 1, 20) ", ro " (index(o, ",ro,") ? "예" : "아니요") ", noexec " (index(o, ",noexec,") ? "예" : "아니요") ", 옵션 " substr(p, 1, 120) }' $KMOUNTS 2>/dev/null | $BB awk 'NR <= 4')
  if [ -n "$_mt" ]; then echo "- 마운트(/data·/system):"; echo "$_mt"; else echo "- 마운트(/data·/system): 읽지 못함"; fi
  # 묶음 J: vmalloc(드라이버를 올릴 때 쓰는 커널 가상 메모리). MemFree는 "부하·소리 지연 측정" 칸에 있어 겹쳐 적지 않는다
  _vmi=$($BB awk '$1 == "VmallocTotal:" { t = $2 } $1 == "VmallocUsed:" { u = $2 } $1 == "VmallocChunk:" { c = $2 }
      END { if (t != "") print "전체 " t " kB, 사용 " u + 0 " kB, 가장 큰 빈 덩어리 " c + 0 " kB" }' ${MEMINFO:-/proc/meminfo} 2>/dev/null)
  echo "- vmalloc: ${_vmi:-읽지 못함} (MemFree는 부하·소리 지연 측정 칸)"
  echo "- 코어 수: 부하·소리 지연 측정 칸의 '코어 수' 줄을 보세요"
  # ⑪ 다른 동글 패키지
  echo "- 다른 동글 패키지: usbwifi.hotspot $(yn [ -d $NAPPS/usbwifi.hotspot ]), stock.hotspot $(yn [ -d $NAPPS/stock.hotspot ])"
}
# --- 1.7.4 베타 2(측정, 소유자 지시 2026-11-14): 부하·소리 지연 측정 칸 ---
# 내비가 버벅이거나 무선 카플레이의 통화·음악 소리가 늦을 때 원인을 가르는 숫자를 1-report.md에 싣는다. 제보 파일을 만들 때만 돈다
# (Launch를 누를 때는 돌지 않는다). 숫자와 프로세스 이름(영문·숫자)만 쓴다: SSID·비밀번호·폰 이름·MAC·IP 없음.
#  - 지금: 부하 평균, 메모리, PERF_SAMPLE초 동안의 CPU 사용률과 CPU를 많이 쓴 프로세스
#  - 지난 운행: 서비스가 30초마다 남긴 측정 기록(hotspot.sh perf_tick, $PERF)의 요약. 전체와 카플레이 연결 중을 나눠 본다
#  - Wi-Fi: 핫스팟 채널 설정, 패킷 오류·버림, UDP 받기 오류, TCP 재전송(부팅 뒤 누적)
#  - 소리: 순정 카플레이가 스스로 남기는 끊김·패킷·버퍼 통계(지금 logcat 버퍼, 그리고 서비스가 ap.log에 옮겨 둔 줄)
# 끝나는 조건: 표본을 한 번 뜨고 끝난다(sleep PERF_SAMPLE초 한 번). 임시 파일($W/perf.s1·s2)은 끝에 지운다.
PERF_SAMPLE=${PERF_SAMPLE:-3}
# 모든 프로세스의 "pid 이름 쓴CPU(1/100초) 메모리(쪽)". /proc/<pid>/stat을 셸 read로 읽어 awk에 넘긴다(awk에 파일 이름을 넘기면
# 그사이 끝난 프로세스에서 멈출 수 있다). 이름은 괄호 안(마지막 ")"까지)이고 영문·숫자·몇 기호만 남긴다
proc_snap() {
  for _pf in $PROC/[0-9]*/stat; do
    { IFS= read -r _pl < $_pf; } 2>/dev/null && echo "$_pl"
  done | $BB awk '{ j = 0; for (i = length($0); i > 0; i--) if (substr($0, i, 1) == ")") { j = i; break }
    i = index($0, "("); if (j == 0 || i == 0 || j < i) next
    nm = substr($0, i + 1, j - i - 1); gsub(/[^A-Za-z0-9._:\/-]/, "", nm)
    n = split(substr($0, j + 2), f, " "); if (n < 22) next
    print $1, (nm == "" ? "?" : nm), f[12] + f[13], f[22] + 0 }'
}
perf_report() {
  echo "## 부하·소리 지연 측정 (숫자만)"
  echo "내비가 버벅이거나 무선 카플레이의 통화·음악 소리가 늦을 때 원인을 가르는 칸입니다. 문제가 난 직후(2분 안)에 만들면 가장 정확합니다."
  _pl=; { read -r _pl < $LOADAVG; } 2>/dev/null; set -- $_pl
  _pu=$(up_s)
  echo "- 부하 평균(1·5·15분): ${1:--} ${2:--} ${3:--}, 부팅 뒤 ${_pu:--}초"
  # 1.8.0 PF-4: 이 제보를 만들기 시작한 시각(perf.log에서 그 뒤의 부하는 제보 만들기 몫)
  [ -n "$RSTART_T" ] && echo "- 제보 만들기 시작: $RSTART_T (낮은 우선순위로 만듦, logcat은 한 번만 읽음)"
  echo "- 메모리(MB): $($BB awk '$1 == "MemTotal:" { t = $2 } $1 == "MemFree:" { f = $2 } $1 == "Buffers:" { b = $2 } $1 == "Cached:" { c = $2 } $1 == "SwapTotal:" { st = $2 } $1 == "SwapFree:" { sf = $2 }
    END { if (t == "") { print "읽지 못함"; exit }
      print sprintf("전체 %d, 비어 있음 %d, 캐시 %d, 스왑 %d 중 %d 비어 있음", t / 1024, f / 1024, (b + c) / 1024, st / 1024, sf / 1024) }' $MEMINFO 2>/dev/null || echo 읽지 못함)"
  # PF-6: 코어 수(/proc/cpuinfo의 processor 줄 수). CPU %를 코어 하나 기준으로 바꿔 읽을 때 쓴다
  # 묶음 H(리뷰 낮음 3): ARM 커널의 cpuinfo는 켜져 있는 코어만 보일 수 있어(추측) 커널이 아는 코어 범위(present, 예 0-3)를 함께 적는다.
  # 셸 read로만 읽는다(프로세스를 더 띄우지 않음). 숫자·쉼표·빼기만 받고, 읽지 못하면 그 칸만 "읽지 못함"
  _cpr=; { read -r _cpr < ${CPUPRESENT:-/sys/devices/system/cpu/present}; } 2>/dev/null
  case "$_cpr" in ''|*[!0-9,-]*) _cpr="읽지 못함" ;; esac
  echo "- 코어 수: $($BB awk '/^processor[ \t]*:/ { n++ } END { print (n ? n : "읽지 못함") }' ${CPUINFO:-/proc/cpuinfo} 2>/dev/null || echo 읽지 못함) (cpuinfo), 커널 코어 범위(present): $_cpr"
  # PF-1: 우리 dnsmasq의 표준입력이 무엇인가(FIFO면 고친 방식, /dev/null이면 예전 방식: 쉬지 않고 돈다). 종류만 쓴다
  _dk=없음
  if our_dhcp_on; then
    if [ -p $PROC/$_dp/fd/0 ]; then _dk="FIFO(고친 방식)"
    elif [ -c $PROC/$_dp/fd/0 ]; then _dk="문자 장치(/dev/null 등, 예전 방식)"
    elif [ -e $PROC/$_dp/fd/0 ]; then _dk="그 밖"
    else _dk="읽지 못함"; fi
  fi
  echo "- 우리 dnsmasq의 표준입력: $_dk"
  echo "- 디버그 로그: 켜기 파일 $(yn [ -f $W/debug ]), 기록 중 $(yn [ -f $W/log.pid ]) (기록 중이면 logcat → awk → uniq 프로세스 3개가 쉬지 않고 돕니다), 자동 켜짐: $(dbg_auto_state)"
  aa_stream_line
  # 베타 3(B3-3): 마지막으로 켠 이유와 시각(코드·숫자만). 자세한 8줄은 비공개 파일
  [ -s $BK/debug.why ] && $BB awk '{ l = $0 } END { if (!NR) exit; split(l, f, " "); t = f[4]; if (t == "" || t == "-") t = "시각 모름"; print "- 디버그 로그 마지막 자동 켜짐 이유: " f[3] " (" t ", 부팅 뒤 " f[2] "초)" }' $BK/debug.why 2>/dev/null
  # CPU 표본: /proc/stat 첫 줄과 프로세스별 CPU를 두 번 읽어 그 사이의 변화량을 본다
  _k1=; _k2=
  # 리뷰 L5: 지난 제보 만들기가 표본 사이에 끝났으면 남았을 수 있는 임시 파일을 먼저 지운다
  rm -f $W/perf.s1 $W/perf.s2
  { read -r _k1 < $KSTAT; } 2>/dev/null; proc_snap 2>/dev/null > $W/perf.s1
  sleep $PERF_SAMPLE
  { read -r _k2 < $KSTAT; } 2>/dev/null; proc_snap 2>/dev/null > $W/perf.s2
  echo "- CPU 표본(${PERF_SAMPLE}초, 코어 전체를 100%로): $($BB awk -v a="$_k1" -v b="$_k2" 'BEGIN {
      na = split(a, x, " "); nb = split(b, y, " "); if (na < 8 || nb < 8) { print "읽지 못함"; exit }
      for (i = 2; i <= 8; i++) { ta += x[i]; tb += y[i] }
      d = tb - ta; if (d <= 0) { print "읽지 못함"; exit }
      print sprintf("사용 %d%%, 입출력 대기 %d%%, 쉼 %d%%", (d - (y[5] - x[5]) - (y[6] - x[6])) * 100 / d, (y[6] - x[6]) * 100 / d, (y[5] - x[5]) * 100 / d) }' 2>/dev/null || echo 읽지 못함)"
  echo "- CPU를 많이 쓴 프로세스(위 표본, 많이 쓴 순서 12개와 우리 것). 칸: CPU% · 메모리 MB · 이름(pid)"
  echo '```'
  $BB awk -v a="$_k1" -v b="$_k2" 'BEGIN { split(a, x, " "); split(b, y, " "); for (i = 2; i <= 8; i++) d += y[i] - x[i] }
    FNR == NR { c1[$1 " " $2] = $3; next }
    { k = $1 " " $2; if (!(k in c1)) next; n++; key[n] = k; dc[n] = $3 - c1[k]; rss[n] = $4; nm[n] = $2; pid[n] = $1 }
    END { if (n == 0 || d <= 0) { print "(읽지 못함)"; exit }
      for (r = 1; r <= 12; r++) { m = 0; for (i = 1; i <= n; i++) if (!done[i] && (m == 0 || dc[i] > dc[m])) m = i
        if (m == 0 || dc[m] <= 0) break
        done[m] = 1; printf "%5.1f%% %5d MB  %s(%s)\n", dc[m] * 100 / d, rss[m] * 4 / 1024, nm[m], pid[m] }
      for (i = 1; i <= n; i++) if (!done[i] && (nm[i] == "hostapd" || nm[i] == "dnsmasq" || nm[i] == "logcat" || nm[i] == "hmgapid"))
        printf "%5.1f%% %5d MB  %s(%s)\n", dc[i] * 100 / d, rss[i] * 4 / 1024, nm[i], pid[i] }' $W/perf.s1 $W/perf.s2 2>/dev/null || echo "(읽지 못함)"
  echo '```'
  rm -f $W/perf.s1 $W/perf.s2
  # 서비스의 30초 측정 기록 요약(전체 / 카플레이 연결 중). "-"(못 읽음·처음)는 세지 않는다
  if [ -f $PERF ] || [ -f $PERF.1 ]; then
    $BB cat $PERF.1 $PERF 2>/dev/null | $BB awk '
      function add(g) { n[g]++
        if (v["cpu"] != "-") { cn[g]++; cs[g] += v["cpu"]; if (v["cpu"] + 0 > cm[g] + 0) cm[g] = v["cpu"] }
        if (v["io"] != "-" && v["io"] + 0 > im[g] + 0) im[g] = v["io"]
        if (v["tick"] != "-") { tn[g]++; ts[g] += v["tick"]; if (v["tick"] + 0 > tm[g] + 0) tm[g] = v["tick"] }
        if (v["svc"] != "-" && dt > 0) { ss[g] += v["svc"]; sd[g] += dt }
        # 리뷰 L1: 걸린 시간은 줄 수가 아니라 줄 사이 간격의 합으로(순정 AP 차는 60초 간격). 간격을 모르는 줄은 30초로 본다
        el[g] += (dt > 0 ? dt : 30)
        if (v["free"] != "-" && (fm[g] == "" || v["free"] + 0 < fm[g] + 0)) fm[g] = v["free"]
        if (v["load"] != "-" && v["load"] + 0 > lm[g] + 0) lm[g] = v["load"]
        # 정식(H-1): Wi-Fi 칸(rxe·rxd·txe·txd)은 칸 수가 맞은 서비스 실행(첫 줄 wn=16)의 줄만 센다(UDP·TCP는 그대로)
        for (q = 1; q <= 7; q++) { w = nk[q]; if (v[w] != "-" && (q > 4 || wok)) sum[g " " w] += v[w] } }
      function out(g, t) { if (n[g] == 0) { print "  - " t ": 기록 없음"; return }
        print sprintf("  - %s(%d줄, 약 %d분): 내비 CPU 평균 %s%%·최대 %s%%, 입출력 대기 최대 %s%%, 부하 최대 %s, 점검 한 번 평균 %s초·최대 %s초, 우리 서비스 셸과 점검 명령의 CPU 평균 %s%%(코어 하나를 100%%로, 계속 도는 hostapd·디버그 로그 줄은 빼고), 빈 메모리 최소 %s MB", t, n[g], el[g] / 60,
          (cn[g] ? int(cs[g] / cn[g]) : "-"), (cn[g] ? cm[g] + 0 : "-"), im[g] + 0, lm[g] + 0,
          (tn[g] ? sprintf("%.2f", ts[g] / tn[g] / 100) : "-"), (tn[g] ? sprintf("%.2f", tm[g] / 100) : "-"),
          (sd[g] > 0 ? sprintf("%.1f", ss[g] / sd[g]) : "-"), (fm[g] == "" ? "-" : int(fm[g] / 1024)))
        print sprintf("    Wi-Fi 받기 오류 %d·버림 %d, 보내기 오류 %d·버림 %d, UDP 받기 오류 %d·버퍼 넘침 %d, TCP 재전송 %d",
          sum[g " " "rxe"], sum[g " " "rxd"], sum[g " " "txe"], sum[g " " "txd"], sum[g " " "udpe"], sum[g " " "udpb"], sum[g " " "retr"]) }
      BEGIN { split("rxe rxd txe txd udpe udpb retr", nk, " "); nq = split("up load cpu io svc tick free cp dbg rxe rxd txe txd udpe udpb retr wn", ak, " "); wok = 1 }
      /^#/ { pu = ""; next }
      { # 리뷰 L4: 줄마다 쓰는 키를 "-"로 되돌린 뒤 읽는다(이 busybox awk에서 써 보지 않은 delete를 피함)
        for (q = 1; q <= nq; q++) v[ak[q]] = "-"
        for (i = 2; i <= NF; i++) { j = index($i, "="); if (j > 0) v[substr($i, 1, j - 1)] = substr($i, j + 1) }
        if (index($0, " cpu=") == 0 || index($0, " tick=") == 0) next
        # 서비스 시작 뒤 첫 줄에만 wn이 있다: 그 값으로 이 실행의 Wi-Fi 칸을 믿을지 정한다(wn이 없던 예전 기록은 그대로 셈)
        if (v["wn"] != "-") wok = (v["wn"] == "16")
        # 지난 줄과의 간격(초): 서비스 CPU를 시간으로 나눌 때 쓴다(서비스가 다시 시작했거나 간격이 이상하면 쓰지 않음)
        dt = 0; if (pu != "" && v["up"] != "-" && v["up"] - pu > 0 && v["up"] - pu < 300) dt = v["up"] - pu
        pu = (v["up"] == "-" ? "" : v["up"])
        add("a"); if (v["cp"] + 0 > 0) add("c"); if (v["dbg"] + 0 > 0) dbg++ }
      END { print "- 30초 측정 기록 요약(서비스가 남긴 것, 디버그 로그가 켜져 있던 줄 " dbg + 0 "개)"
        out("a", "전체"); out("c", "카플레이 연결 중") }' 2>/dev/null
  else
    echo "- 30초 측정 기록: 없음(이 판에서 서비스가 아직 점검을 돌지 않음)"
  fi
  # Wi-Fi: 설정 파일의 채널 쪽 값(이름·비밀번호 줄은 읽지 않는다)과 부팅 뒤 누적 숫자
  echo "- 핫스팟 설정(채널 쪽만): $($BB awk -F= '$1 == "channel" || $1 == "hw_mode" || $1 == "ieee80211n" || $1 == "ieee80211ac" || $1 == "ht_capab" || $1 == "wmm_enabled" || $1 == "beacon_int" || $1 == "dtim_period" { gsub(/[^][A-Za-z0-9+_-]/, "", $2); o = o (o == "" ? "" : ", ") $1 "=" $2 } END { print (o == "" ? "읽지 못함" : o) }' $CONF 2>/dev/null || echo 읽지 못함)"
  echo "- Wi-Fi 장치(wlan0) 부팅 뒤 누적: $($BB awk -v w="$WIF:" '{ i = index($0, w); if (i == 0) next; n = split(substr($0, i + length(w)), f, " "); if (n < 12) next
      print "받은 패킷 " f[2] "(오류 " f[3] "·버림 " f[4] "), 보낸 패킷 " f[10] "(오류 " f[11] "·버림 " f[12] ")"; ok = 1; exit } END { if (!ok) print "읽지 못함" }' $PROCNET/dev 2>/dev/null || echo 읽지 못함)"
  # PF-5: 측정 기록의 Wi-Fi 칸이 차에서 비었다. 줄 꼴을 보려고 /proc/net/dev를 그대로 싣는다(장치 이름과 숫자뿐, 30줄까지)
  echo "- 네트워크 장치 표(/proc/net/dev 그대로)"
  echo '```'
  $BB awk 'NR <= 30 { print } END { if (NR == 0) print "(읽지 못함)" }' $PROCNET/dev 2>/dev/null || echo "(읽지 못함)"
  echo '```'
  echo "- 네트워크 부팅 뒤 누적: $($BB awk '$1 == "Udp:" || $1 == "Tcp:" { if (h[$1] == "") { h[$1] = $0; next }
        n = split(h[$1], nm, " "); for (i = 2; i <= n; i++) val[$1 nm[i]] = $i }
      END { if (val["Udp:InDatagrams"] == "") { print "읽지 못함"; exit }
        print "UDP 받음 " val["Udp:InDatagrams"] "(오류 " val["Udp:InErrors"] "·버퍼 넘침 " val["Udp:RcvbufErrors"] + 0 "), TCP 보냄 " val["Tcp:OutSegs"] "(재전송 " val["Tcp:RetransSegs"] ")" }' $PROCNET/snmp 2>/dev/null || echo 읽지 못함)"
  # 소리·화면: 지금 logcat 버퍼에 남은 줄의 개수만(줄 내용은 넣지 않는다). 마지막 소리 설정은 형식 이름만(영문·숫자)
  lcd | $BB awk '
    / [VDIWEF]\/TccCarPlay *\(/ {
      if (index($0, "glitches in the last minute") > 0) { g++; s = substr($0, index($0, "### ") + 4); gs += s + 0 }
      else if (index($0, "### Lost packets") > 0) lp++
      else if (index($0, "### Unrecovered packets") > 0) up++
      else if (index($0, "Jitter Buffer Discard") > 0) jb++
      else if (index($0, "Buffering issues during session") > 0) bi++
      else if (index($0, "NTP send request failed") > 0) nt++
      else if (index($0, "Main audio setting up ") > 0) { s = substr($0, index($0, "setting up ") + 11); k = s; sub(/ .*/, "", s); sub(/.* for /, "", k); sub(/,.*/, "", k)
        # 리뷰 M3: 형식이 "AAC-LC/44100/2" 꼴이고 용도가 영문 소문자 한 낱말일 때만(이름이 섞인 줄은 쓰지 않는다)
        if (s ~ /^[A-Z0-9-]+\/[0-9]+\/[0-9]+$/ && k ~ /^[a-z]+$/) ma = substr(s, 1, 24) " " substr(k, 1, 12) }
      next }
    index($0, "render and Drop") > 0 { vd++ }
    index($0, "Frame is dropped") > 0 { fd++ }
    index($0, "STREAM UNDERRUN") > 0 { ur++ }
    index($0, "socket underrun") > 0 { su++ }
    END {
      print "- 카플레이 소리 통계(지금 logcat 버퍼): 1분 끊김 알림 " g + 0 "줄(끊김 합 " gs + 0 "번), 패킷 잃음 " lp + 0 "줄, 되살리지 못한 패킷 " up + 0 "줄, 지터 버퍼 넘침 " jb + 0 "줄, 세션 버퍼 문제 " bi + 0 "줄, 시각 맞춤 요청 실패 " nt + 0 "줄, 마지막 소리 설정 " (ma == "" ? "버퍼에 없음" : ma)
      print "- 화면·소리 출력(지금 logcat 버퍼): 카플레이 화면 프레임 버림 " vd + 0 "줄, 화면 큐 넘침 " fd + 0 "줄, 소리 출력 끊김(AudioMixer underrun) " ur + 0 "줄, 블루투스 소리 소켓 비었음 " su + 0 "줄"
    }'
  echo "- 카플레이 소리 기록(서비스가 ap.log에 옮겨 둔 줄, 마지막 30줄)"
  echo '```'
  $BB cat $APLOG.1 $APLOG 2>/dev/null | $BB grep "카플레이 소리: " | lastmask 30 | $BB awk '{ print } END { if (NR == 0) print "(없음)" }'
  echo '```'
}
# 1.7.4(O-5): 화면 해상도·밀도를 적는다(1.8.0 Launch 화면 배치를 정할 근거, 개인정보 없음).
# dumpsys window displays의 첫 "init=1920x720 160dpi cur=… app=… rng=…" 줄에서 init·cur·app·dpi만 고른다(app = 순정 막대를 뺀 영역).
# fb0 virtual_size는 버퍼 크기라 세로가 화면의 두 배일 수 있다. 읽기만 하고 아무것도 바꾸지 않는다.
screen_info() {
  _sd=$(dumpsys window displays 2>/dev/null | $BB awk '!d && /init=/ { d = 1
    for (i = 1; i <= NF; i++) if ($i ~ /^(init|cur|app)=[0-9]+x[0-9]+$/ || $i ~ /^[0-9]+dpi$/) o = o (o == "" ? "" : " ") $i }
    END { print o }' 2>/dev/null | dn_safe)
  _sl=$(getprop ro.sf.lcd_density 2>/dev/null); case "$_sl" in ''|*[!0-9]*) _sl= ;; esac
  _sf=$(dn_first $KSYS/class/graphics/fb0/virtual_size | dn_safe)
  echo "- 화면: ${_sd:-읽지 못함}, 밀도 속성 ${_sl:-없음}, fb0 ${_sf:-없음}"
}
report() {
  prod=$(getprop ro.build.product)
  # 베타 3(B3-6, 소유자 결정 11-23 "변조된 이라고 하자"): 변조 검사에 걸린 버전이면 맨 위 첫 줄에 크게 알린다
  if kp_tampered; then
    echo "## ⚠ 변조된 버전입니다. 공식 GitHub에서 다운로드한 버전이 아닙니다."
    echo
  fi
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
  screen_info
  # 베타 3(B3-8, 제보 분석 B2-7): 어느 빌드인지. 빌드 = 변조 검사 목록(bin/kp-files.md5)의 md5 앞 8자리(패키지 안에서 정해지는 값,
  # NEMESIS.data를 뺀 모든 파일이 바뀌면 바뀜). zip 해시는 zip 안에서 알 수 없어 쓰지 않는다
  echo "- 이 패키지 버전: $(pver $APP/NEMESIS.data) · 빌드 $(kp_build)"
  # 베타 3(B3-13): 이 빌드의 공식 버전·목록 줄 수와 다르면 표시(막지 않음). 고친 사람이 목록까지 새로 만들어 변조 검사를 통과한 경우(#509)
  kp_official_line
  # 1.8.0 변조 검사: 리포트를 만들 때마다 패키지 파일을 목록(bin/kp-files.md5)과 다시 맞춰 본다(서비스 스크립트가 바뀌어 서비스 쪽 검사가
  # 빠진 개조판도 여기서 드러나게). 다른 파일은 우리 패키지 안의 상대 경로만 적는다
  if kp_verify; then echo "- 패키지 파일 확인: 목록과 같음 ($($BB awk 'END { print NR }' ${KPLIST:-$APP/bin/kp-files.md5})개)"
  elif [ "$KP_BADN" = -1 ]; then echo "- 패키지 파일 확인: **목록 파일 없음** (변조된 패키지일 수 있음)"
  else echo "- 패키지 파일 확인: **목록과 다른 파일 $KP_BADN개** (변조된 패키지일 수 있음):$KP_BADL"; fi
  echo "- 서비스의 변조 검사(이번 시작): $(cat $W/kp.tamper 2>/dev/null || echo 기록 없음)"
  echo "- 설치 진행: $($BB awk -F= '$1 == "state" || $1 == "pct" || $1 == "stage" { printf "%s=%s  ", $1, $2 }' $PROG 2>/dev/null)"
  # 1.7.3(D-6): "확인된 차"는 공개 README 지원 표의 ✅(CARS_SEEN)로 본다
  if car_in "$prod" "$CARS_SEEN"; then echo "- 확인된 차: 예"
  elif car_in "$prod" "$CARS_TRY"; then echo "- 확인된 차: 시험 지원 (이 차용 설정이 패키지에 있음, 결과를 알려 주세요)"
  elif car_in "$prod" "$CARS_AUTO"; then echo "- 확인된 차: 자동 설정 (HMG-API가 차에서 지도를 만들어 설정, 결과를 알려 주세요)"
    for _f in automap.bad automap.checked automap.foreign; do [ -f $BK/$_f ] && echo "  - 기록: $_f"; done
  else echo "- 확인된 차: 아니요 (서비스가 대기만 함, 지원 차: $CARS)"; fi
  echo "- NEMESIS: $(nemesis version 2>/dev/null)"
  echo "- NEMESIS LivePatch: $(lp_state s) ($(lp_state t))"
  # 따옴표 없이: 두 줄이 한 줄로 합쳐진다
  echo "- HMG-API:" $($BB grep -E '^(version|build) ' ${HMGINST:-/data/hmgapi/installed.txt} 2>/dev/null)
  echo "- wireless.projection 설치: $(yn [ -d /data/nemesis/apps/wireless.projection ])"
  echo "- 예전 wireless.projection 흔적(백업 폴더만 남음): $(yn wp_trace)"
  if tbt_other; then echo "- 같은 기능의 다른 패키지·모드: **$TBT_OTHER** ($TBT_CONFLICT_MSG)"; else echo "- 같은 기능의 다른 패키지·모드: 없음"; fi
  echo "- HMG-API 무선 모드: 설치 $(mod_state) / 켜짐 $(mod_on_state) / 무선 카플레이 설정(bridge) $(bridge_state)"
  echo "- 무선 모드 판: 차 $(mod_ver) / 패키지 $MOD_VER"
  # 1.8.0 정식(P2): 우리가 설치·업데이트할 때 남긴 mod.json 기록과 지금이 같은가(기록만, 판정에는 쓰지 않음). 버전 숫자만
  mod_sig_note; _msd=없음; [ -f $BK/mod.sig ] && _msd=같음
  [ -f $BK/mod.sigdiff ] && _msd="다름($($BB awk '{ gsub(/[^0-9.]/, "", $1); gsub(/[^0-9.]/, "", $2); print $1 " → " $2; exit }' $BK/mod.sigdiff 2>/dev/null))"
  echo "- 무선 모드 설치 기록과 비교: $_msd"
  # 베타 3(B3-10): 작성자가 우리인지만(키 값은 비공개 파일)
  case "$(mod_key)" in ours) echo "- 무선 모드 작성자: 우리" ;; other) echo "- 무선 모드 작성자: 다른 사람" ;; *) [ -f $HMGDATA/mods/$MOD_ID/mod.json ] && echo "- 무선 모드 작성자: 모름(키 기록 없음)" ;; esac
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
    echo "**할 일: 재부팅하고 3분 기다린 뒤 한 번 더 재부팅해 주세요.** 그러면 무선 모드가 새 버전($MOD_VER)으로 바뀌니, 리포트를 다시 만들어 주세요."
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
  # 1.8.0 베타 2 NM-1(NEMESIS 1.16.8 ADB 타일): USB 모드·무선 ADB 포트 값(영문·숫자만, 40자), NEMESIS 표시 파일은 있는지만
  for p in sys.usb.config persist.sys.usb.config service.adb.tcp.port; do
    echo "- $p=$(getprop $p 2>/dev/null | $BB awk '{ gsub(/[^A-Za-z0-9,._-]/, ""); print substr($0, 1, 40); exit }')"
  done
  echo "- NEMESIS 표시 파일: adb_usb_prev $(yn [ -e ${NEMDATA:-/data/nemesis}/adb_usb_prev ]), adb_tcp_prev $(yn [ -e ${NEMDATA:-/data/nemesis}/adb_tcp_prev ]), ota_blocked $(yn [ -e ${NEMDATA:-/data/nemesis}/ota_blocked ])"
  echo
  echo "## Wi-Fi"
  echo "- Wi-Fi 장치(wlan0): $(yn [ -d /sys/class/net/$WIF ])"
  echo "- 순정 hostapd: $(yn [ -x /system/bin/hostapd ]), dnsmasq: $(yn [ -x /system/bin/dnsmasq ])"
  echo "- 순정 방화벽(wlan0): $(fw_wlan0)"
  echo "- 순정 방화벽 무선 안드로이드 오토 포트(40515): $(fw_aa)"
  echo "- 우리 AA 방화벽 규칙(KP_AA_IN): $(fw_kp)"
  echo "- Wi-Fi 설정(wifi_on): $(settings get global wifi_on 2>/dev/null), 순정 AP 저장값(wifi_ap_on): $(settings get global wifi_ap_on 2>/dev/null)"
  # 1.7.2(P-7): 서비스가 wifi_ap_on을 1에서 0으로 바꾼 기록(원래 값, 숫자만). 없으면 바꾼 적 없음(또는 되돌림)
  _apo=$(cat $APON_ORIG 2>/dev/null); case "$_apo" in ''|*[!0-9]*) _apo=없음 ;; esac
  echo "- 순정 AP 저장값을 우리가 바꿈(wifi_ap_on.orig): $(if [ "$_apo" = 없음 ]; then echo 아니요; else echo "예, 원래 값 $_apo"; fi)"
  # 1.7.3(K-3): softap.conf·AP 판정·연결 수는 위 kp_verdict(kp_collect)가 구한 값을 다시 쓴다(두 번 읽지 않음)
  _kyn() { if [ "$1" = yes ]; then echo 예; else echo 아니요; fi; }
  echo "- softap.conf: $(yn [ -s $SRC ]), 찾은 문자열 ${NS:-0}개, 카플레이 SSID 길이 ${#S2}, 비밀번호 길이 ${#S4}"
  # 베타 3(B3-12): 상태 화면 앱이 순정과 같은 API(WifiManager.getWifiApConfiguration)로 읽은 길이(값은 없음)와 파일 값 길이를 나란히
  ap_len_line
  ap_src_line
  echo "- 우리 hostapd: $(_kyn $K_OURAP), 우리 DHCP: $(_kyn $K_DHCP)"
  echo "- 다른 hostapd (순정 핫스팟): $(_kyn $K_OTHER)"
  # 1.6.2: 순정 hostapd의 SSID가 카플레이용(carplay)인지 일반 핫스팟(hotspot)인지. 값은 비교만 한다.
  echo "- 무선 카플레이 AP: ap_mode=$K_APMODE (순정 hostapd 판정: $K_SSID, 순정 카플레이 AP 기록: $(yn [ -f $BK/stockap.seen ]))"
  echo "- wpa_supplicant: $(yn running wpa_supplicant)"
  echo "- 지금 카플레이 연결 수: $K_CP"
  # 1.7.4(B-15 가-2): 상태 화면 안내 파일(서비스가 씀)의 요약. 코드·예/아니요만(다른 줄은 옮기지 않음)
  echo "- 안내 파일: $(hint_summary)"
  echo "- 무선 안드로이드 오토: 모드에 알린 신호 $(getprop $AAPROP 2>/dev/null) (이유: $(_aw=$(cat $AAWHY 2>/dev/null); if [ -n "$_aw" ]; then aa_why_text $_aw; else echo 기록 없음; fi))"
  echo
  diag
  echo
  perf_report
  echo
  dongle_pub
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
  # 1.7.4(B-15 가-2): 초까지(안내 파일·ap.log 줄과 순서를 맞춰 보게)
  echo "_만든 시각 $(date '+%Y-%m-%d %H:%M:%S')_"
}

# 상태 화면 앱(StatusActivity)이 읽는 key=value 파일. 앱은 root가 아니므로 누구나 읽을 수 있게(644)
# /data/local/tmp 바로 아래에 둔다. 값은 예/아니요·버전·개수·길이뿐이다 (SSID, 비밀번호, 휴대폰 이름, MAC, IP 없음).
STATUS=${STATUS:-/data/local/tmp/korea-projection-status.txt}
yesno() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }
# 1.8.0 변조 검사: 상태 화면 판정용(빠르게). 서비스가 남긴 결과가 bad이거나 목록 파일이 없으면 변조로 본다
# 베타 3(B3-13, 메인 결정 11-23): 이 빌드가 실제로 쓰는 package-version 하나와 변조 검사 목록 줄 수. 승격 빌드 때 그 빌드 값으로 바꾼다
# (stub가 NEMESIS.data·목록과 같은지 본다). 다르면 리포트에 "공식 버전 아님"(설치·동작은 막지 않음, 표시만)
KP_OFFICIAL_VERS="1.8.1"
KP_OFFICIAL_FILES=73
kp_official_line() {
  _kov=$(pver $APP/NEMESIS.data); _kof=$($BB awk 'END { print NR + 0 }' ${KPLIST:-$APP/bin/kp-files.md5} 2>/dev/null)
  case " $KP_OFFICIAL_VERS " in *" $_kov "*) [ "$_kof" = "$KP_OFFICIAL_FILES" ] && return 0 ;; esac
  echo "- **공식 버전 아님**(버전 ${_kov:-?}, 파일 ${_kof:-?}개 / 공식 $KP_OFFICIAL_VERS, ${KP_OFFICIAL_FILES}개)"
}
# 베타 3(B3-12): 앱이 남기는 길이 기록(키=값, 값은 숫자·짧은 낱말만 받음). ap_ssid_len_svc·ap_psk_len_svc(서비스 값 길이),
# ap_psk_svc_err(빈 값 = 성공, 아니면 짧은 이유: perm·nomethod·null·err), ap_svc_boot(그 부팅 id), ap_svc_t(그때 epoch)
KP_APLEN=${KP_APLEN:-/data/data/korea.projection.app/files/apcfg.len}
ap_len_line() {
  if [ ! -s $KP_APLEN ]; then echo "- 카플레이 비밀번호 길이(Wi-Fi 서비스, 앱이 읽음): 기록 없음"; return 0; fi
  $BB awk -F= -v fl="${#S4}" -v bid="$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)" '
    $1 ~ /^ap_(ssid_len_svc|psk_len_svc|psk_svc_err|svc_boot|svc_t)$/ && $2 ~ /^[0-9A-Za-z_-]*$/ && length($2) <= 40 { v[$1] = $2 }
    END {
      w = (v["ap_svc_boot"] != "" && v["ap_svc_boot"] == bid) ? "이번 부팅" : "지난 부팅"
      if (v["ap_psk_svc_err"] != "") { print "- 카플레이 비밀번호 길이(Wi-Fi 서비스, 앱이 읽음): 읽지 못함(" v["ap_psk_svc_err"] ", " w "), 파일 " fl; exit }
      m = (v["ap_psk_len_svc"] == fl) ? "같음" : "다름"
      print "- 카플레이 비밀번호 길이(Wi-Fi 서비스, 앱이 읽음): " v["ap_psk_len_svc"] " / 파일 " fl " (" m ", SSID 길이 서비스 " v["ap_ssid_len_svc"] ", " w ")" }' $KP_APLEN 2>/dev/null
}
# 1.8.0 정식 C4: 서비스가 우리 핫스팟에 쓴 AP 값의 출처(hotspot.sh ap_src_apply가 남긴 $APSRC 한 줄, 값 없음).
# 칸: <부팅 id> <svc|file|def> <이유 또는 -> <SSID 길이> <비밀번호 길이> <파일 비밀번호 길이>. 숫자·짧은 낱말만 받는다
ap_src_line() {
  [ -s $APSRC ] || { echo "- 핫스팟에 쓴 AP 값: 기록 없음"; return 0; }
  $BB awk -v bid="$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)" '
    NR == 1 && NF == 6 && $2 ~ /^(svc|file|def)$/ && $3 ~ /^(-|noapp|timeout|oldboot|noval|badchar|badlen)$/ && $4 ~ /^[0-9]+$/ && $5 ~ /^[0-9]+$/ && $6 ~ /^[0-9]+$/ {
      w = ($1 != "" && $1 != "none" && $1 == bid) ? "이번 부팅" : "지난 부팅"
      if ($2 == "svc") print "- 핫스팟에 쓴 AP 값: 서비스(SSID " $4 "자·비밀번호 " $5 "자, 파일 비밀번호 " $6 "자, " w ")"
      else if ($2 == "file") print "- 핫스팟에 쓴 AP 값: 파일(" $3 ", 비밀번호 " $5 "자, " w ")"
      else print "- 핫스팟에 쓴 AP 값: 파일(기본 위치, " w ")"
      ok = 1 }
    END { if (!ok) print "- 핫스팟에 쓴 AP 값: 기록을 읽지 못함" }' $APSRC 2>/dev/null
}
# 니로 정식 1차(11-25): AA 기록을 어떻게 읽는가(hotspot.sh aa_events). 숫자·상태만(줄 내용·태그 없음).
# 계속 받기면 logcat이 살아 있는지·받는 파일 크기·.1 유무·지금 파일에서 읽은 줄 수(돌리면 0부터), 예전 방식이면 그 까닭(nofile·died)
aa_stream_line() {
  aa_bid
  _asm=계속받기; _asr=; _aso=; [ -f $W/aa.old ] && read _aso < $W/aa.old 2>/dev/null
  if [ -n "$_aso" ] && [ "$_aso" = "$_aabid" ]; then
    _asm=예전방식; _asw1=; _asw2=; [ -f $W/aa.why ] && read _asw1 _asw2 < $W/aa.why 2>/dev/null
    [ "$_asw1" = "$_aabid" ] && case "$_asw2" in nofile|died) _asr=$_asw2 ;; esac
  fi
  _asa=아니요; aalog_alive && _asa=예
  _asz=없음; [ -f $AASTREAM ] && { _asz=$($BB wc -c < $AASTREAM 2>/dev/null); case "$_asz" in *[!0-9\ ]*|'') _asz=? ;; *) _asz="$(echo $_asz)바이트" ;; esac; }
  _as1=없음; [ -f $AASTREAM.1 ] && _as1=있음
  _asn=0; _asb=; [ -f $AASTREAM.pos ] && read _asb _asn _asx < $AASTREAM.pos 2>/dev/null
  [ "$_asb" = "$_aabid" ] || _asn=0; case "$_asn" in ''|*[!0-9]*) _asn=0 ;; esac
  case "$_asm" in
    예전방식) echo "- AA 기록 받기: 예전 방식(까닭 ${_asr:-모름}), 계속 받는 logcat 살아 있음 $_asa" ;;
    *) echo "- AA 기록 받기: 계속 받기, logcat 살아 있음 $_asa, 받는 파일 $_asz(.1 $_as1), 지금 파일에서 읽은 줄 $_asn" ;;
  esac
}
# 빌드 표시: 변조 검사 목록의 md5 앞 8자리(목록이 없거나 md5를 못 쓰면 "모름")
kp_build() {
  _kbh=$($BB md5sum < ${KPLIST:-$APP/bin/kp-files.md5} 2>/dev/null | $BB awk '{ print substr($1, 1, 8) }')
  case "$_kbh" in [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) echo "$_kbh" ;; *) echo "모름" ;; esac
}
kp_tampered() {
  [ -s ${KPLIST:-$APP/bin/kp-files.md5} ] || return 0
  case "$(cat $W/kp.tamper 2>/dev/null)" in bad*) return 0 ;; esac
  return 1
}
# HMG-API 무선 모드의 상태는 HMG-API 자기 파일로 본다(NEMESIS 목록은 wireless.projection과 충돌하면 등록되지 않고,
# 모드를 꺼도 남는다). /data/hmgapi/mods/<id>/mod.json: 설치, .disabled: 꺼짐,
# /data/hmgapi/settings/<id>.json의 "bridge":false: 무선 카플레이(블루투스 브리지) 설정 꺼짐 (Mods.java, settings.json)
HMGMOD=${HMGMOD:-/data/hmgapi/mods/wireless-carplay-aa}
HMGSET=${HMGSET:-/data/hmgapi/settings/wireless-carplay-aa.json}
mod_state() { yesno [ -f $HMGMOD/mod.json ]; }
# 1.8.1 T1-2(#613 NEEV·#616 CN7NPE): 우리와 같은 기능(계기판 길안내 등)을 하는 다른 것이 켜져 있으면 상태 화면 "먼저 할 일"과 리포트에 한 줄.
# 감지는 알려진 id 목록으로만 한다(소유자 결정 Y-2): HMG-API 모드는 mod.json이 있고 꺼 두지 않음(.disabled 없음), NEMESIS 패키지는 폴더가 있음.
# NEMESIS 패키지 둘은 NEMESIS.data depends로도 막는다(W-1). 이 줄은 우리를 먼저 깔고 그 패키지를 나중에 깐 차를 위한 것이다.
# 끄거나 지우는 도구는 만들지 않는다. wireless.projection은 따로 판정(otherpkg)이 있어 여기에 넣지 않는다
TBT_OTHER_MODS='wired-carplay-tbt-lx2pe'
TBT_OTHER_PKGS='projection.tbt enhanced.projection'
TBT_CONFLICT_MSG="타 패키지와 기능이 충돌됩니다. 기능이 똑같은 패키지를 삭제하십시오."
# 찾으면 TBT_OTHER에 id(공백으로 나눔)를 두고 0
tbt_other() {
  TBT_OTHER=
  for _to in $TBT_OTHER_MODS; do
    [ -f ${HMGDATA:-/data/hmgapi}/mods/$_to/mod.json ] && [ ! -f ${HMGDATA:-/data/hmgapi}/mods/$_to/.disabled ] && TBT_OTHER="$TBT_OTHER $_to"
  done
  for _to in $TBT_OTHER_PKGS; do [ -d ${NEMESIS_APPS:-/data/nemesis/apps}/$_to ] && TBT_OTHER="$TBT_OTHER $_to"; done
  TBT_OTHER=${TBT_OTHER# }
  [ -n "$TBT_OTHER" ]
}
# 1.8.1 W-2(리뷰 1 H1로 바꿈): 예전 무선 패키지 wireless.projection(1.x, /system을 직접 고침)을 지운 흔적(백업 폴더)이 남았는가.
# NEMESIS는 업데이트 때 옛 판의 preuninstall·폴더 삭제를 새 판의 preinstall보다 먼저 한다(pkg.c, 1.16.9·1.17 같음). 그래서 설치 전 검사로
# 막으면 업데이트가 옛 판만 지운 채 끝나 무선 프로젝션이 다 안 되는 차가 생긴다. 막지 않고 상태 화면·리포트에 이유만 보인다.
# 그 패키지가 아직 깔려 있으면 NEMESIS.data depends(!wireless.projection)가 설치·업데이트를 처음에 막는다(옛 판을 지우기 전)
WP_TRACE=${WP_TRACE:-/data/nemesis/backup/wireless.projection}
WP_TRACE_MSG="예전 wireless.projection의 흔적이 남아 있습니다. 그 패키지 안내대로 정리해 주세요."
wp_trace() { [ -d $WP_TRACE ] && [ ! -d ${NEMESIS_APPS:-/data/nemesis/apps}/wireless.projection ]; }
# 1.8.1 W-8: NEMESIS LivePatch 상태 한 줄. 서비스(hotspot.sh lp_probe)가 시작할 때 한 번 읽어 $LPF에 둔 두 줄(화면 문구·리포트 태그)을 옮긴다.
# 여기서는 nemesis를 부르지 않는다(상태 화면을 열 때 다시 읽지 않음). 정한 꼴이 아니면 옮기지 않는다. $1=s(화면 문구) 또는 t(리포트 태그)
lp_state() {
  _lps=; _lpt=; [ -s $LPF ] && { read -r _lps; read -r _lpt; } < $LPF 2>/dev/null
  # 태그: 정한 낱말로 시작하고 영문 소문자·숫자·=·쉼표·빈칸만
  case "$_lpt" in livepatch=na|livepatch=err|"livepatch=safe wrapper="*|"livepatch=on wrapper="*) ;; *) _lpt= ;; esac
  case "$_lpt" in *[!a-z0-9=,\ ]*) _lpt= ;; esac
  # 문구: 서비스가 쓰는 꼴로 시작할 때만(busybox 1.8.1 awk에 한글 범위를 맡기지 않고 셸 case로 본다), 120자까지
  case "$_lps" in "해당 없음"|"읽지 못함"|"안전 모드(순정으로 시작함)"*|"쓰는 패키지 없음"*|"적용된 곳 없음(안전 모드나 손상)"*|"사용 중(적용 "*) ;; *) _lps= ;; esac
  [ ${#_lps} -le 120 ] || _lps=
  if [ ! -s $LPF ]; then _lps="기록 없음(서비스 시작 전)"; _lpt="livepatch=-"
  elif [ -z "$_lps" ] || [ -z "$_lpt" ]; then _lps="읽지 못함"; _lpt="livepatch=-"; fi
  if [ "$1" = t ]; then echo "$_lpt"; else echo "$_lps"; fi
}
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
  # 베타 3(B3-7): 서비스와 같은 위치 고르기(읽히는 쪽, hotspot.sh src_pick)
  src_pick
  K_HMG=$(echo $($BB grep -E '^(version|build) ' ${HMGINST:-/data/hmgapi/installed.txt} 2>/dev/null))
  _kv=${K_HMG#*version }; [ "$_kv" = "$K_HMG" ] && _kv=; K_HMGV=${_kv%% *}
  K_NEM=$(nemesis version 2>/dev/null)
  K_MOD=$(mod_state); K_MODON=$(mod_on_state); K_BRIDGE=$(bridge_state)
  # 베타 3(B3-10): 우리 이름의 모드인데 작성자 키가 다름(다른 사람이 고친 수정판의 모드)
  K_FAKEKEY=no; mod_fakekey && K_FAKEKEY=yes
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
    # 1.7.4(B-15): 차의 busybox 1.8.1 grep에는 -x가 없어 예전 "grep -qx"가 늘 실패했다(차에서 K_AAOK가 늘 no, AA가 붙어도
    # "지금 연결된 폰 없음"). 줄 전체 비교는 셸로 한다(hotspot.sh has_line: 파일이 없으면 1, 줄이 정확히 같으면 0).
    # 안내 파일은 서비스 hint_write가 $BB printf '…\n'으로 써 줄 끝에 CR이 생기지 않는다
    # 리뷰 반영(B-15 뒤 중간): 무선 AA 연결은 우리 hostapd가 돌 때만 연결로 본다. 서비스가 trap 없이 죽거나 끊김 줄을 놓쳐 aa=ok가
    # 남아도, 핫스팟이 꺼져 있으면 apoff 등 원래 판정이 가려지지 않게. aa=ok는 우리 AP 경로에서만 생긴다(aa_flag는 AA 신호
    # sys.kp.aa_ap=1일 때만 안내를 쓰고, 그 신호는 aa_sig가 우리 hostapd가 돌 때만 켬): 순정 Wi-Fi 차에는 영향이 없다
    [ "$K_OURAP" = yes ] && has_line 'aa=ok' $HINT && K_AAOK=yes
    # 베타 1 리뷰 5: 카플레이가 연결되어 있어 AA가 기다리는 중(aa=cpwait, 상태 화면 노란 줄)
    has_line 'aa=cpwait' $HINT && K_AAWAIT=yes
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
# 베타 2 RS-15 리뷰: 서비스가 남긴 동글 상태가 쓰는 중(wait·up·ok)인가(busybox grep의 \| 대신 read로)
# 시험판 4(리뷰 낮음 2): 동글 길을 기다리는 중(settle·replug)도 동글을 쓰는 중으로 본다(그동안 부품 없음 판정을 내지 않게)
dg_state_inuse() { _dgu1=; [ -f $W/dongle.state ] && read _dgu1 _dgu2 < $W/dongle.state 2>/dev/null; case "$_dgu1" in wait|up|ok|bootwait|noap|nodevstuck|nobind|reupmax) return 0 ;; esac; return 1; }
# 시험판 5: 동글 길 판정. 동글 사용이 켜져 있고 동글 상태가 기다림·올리는 중·꽂기 전·동글 AP 띄우는 중이거나,
# 이번 부팅 무선이 없는 동글 실패(noap·nodevstuck·목록 밖)면 0과 DGV_LV·DGV_MSG(상태 키 dongle_lv·dongle_msg와 같은 문구)
DG_APUP_MSG="동글로 핫스팟을 띄우는 중입니다. 재부팅하지 마세요."
dg_verdict() {
  # 리뷰 낮음 1: 꽂기 전에 동글 사용을 껐으면 다음 점검(30초)에 내비 Wi-Fi로 바뀌는 중이다(재부팅 안내를 내지 않음)
  # 베타 3(B3-4·B2-5, 제보 #498): 이번 부팅 설치가 실패했으면 동글 단계 문구("띄우는 중입니다" 등)보다 실패 판정을 먼저 보인다
  [ "$K_PST" = fail ] && return 1
  if [ ! -f $DG_ON ]; then
    _dgvs=; [ -f $W/dongle.state ] && read _dgvs _dgvx < $W/dongle.state 2>/dev/null
    _dgv1=; [ -f $W/dongle.seen1 ] && read _dgv1 _dgvy < $W/dongle.seen1 2>/dev/null
    # 재리뷰 낮음: 허용 동글이 꽂혀 있는데 아직 안 붙었으면 바로 바꾸지 않는다(프로브 중) → 다음 시동부터라고 알림
    # 베타 3(B3-2): 부품 없는 차에서 꽂기 전에 끈 부팅(plugoffnw)은 유선 프로젝션을 쓸 수 있다고 알린다(상태 키 dongle은 앱 결정대로 off)
    [ "$_dgvs" = plugoffnw ] && { DGV_LV=1; DGV_MSG=$DG_PLUGOFFNW_MSG; return 0; }
    case "$_dgvs" in bootwait|wait|up) [ "$_dgv1" != "$(dg_kv_bid)" ] || return 1; DGV_LV=1
      dg_usb; if [ "$DG_USB" = ok ]; then DGV_MSG="동글 사용을 껐습니다. 다음 시동부터 내비 Wi-Fi로 돌아갑니다."; else DGV_MSG="내비 Wi-Fi로 바꾸는 중입니다. 재부팅하지 마세요."; fi
      return 0 ;; esac
    return 1
  fi
  _dgvs=; [ -f $W/dongle.state ] && read _dgvs _dgvx < $W/dongle.state 2>/dev/null
  case "$_dgvs" in
    bootwait|wait|noap|nodevstuck|nobind|notours|reupmax) ;;
    up|ok) [ "$K_OURAP" = no ] && [ "$_vconn" = no ] || return 1 ;;
    # 1.8.1 I-7·I-8: 다른 동글 패키지·드라이버(otherpkg·other), 내비 Wi-Fi가 먼저 켜짐(bcmup)인데 우리 핫스팟이 없고 연결도 없으면
    # 부품 없음(nopart)·핫스팟 꺼짐(apoff, "3분 후 재부팅")보다 동글 문구를 먼저 보인다. 핫스팟이 떠 있거나 연결 중이거나
    # 순정 Wi-Fi 차(ap_mode=stock, 우리 핫스팟을 띄우지 않음)면 예전 판정 그대로
    other|otherpkg|bcmup) [ "$K_OURAP" = no ] && [ "$_vconn" = no ] && [ "$K_APMODE" != stock ] || return 1 ;;
    *) return 1 ;;
  esac
  _dgvk=$(dg_kv)
  DGV_LV=$(echo "$_dgvk" | $BB awk -F= '$1 == "dongle_lv" { print $2; exit }')
  DGV_MSG=$(echo "$_dgvk" | $BB awk '/^dongle_msg=/ { sub(/^dongle_msg=/, ""); print; exit }')
  case "$DGV_LV" in 0|1|2) ;; *) DGV_LV=1 ;; esac
  # 1.8.1 I-8: bcmup 문구("다음 시동 때 다시 시도")는 내비 Wi-Fi가 되는 차의 말이다. 여기 온 차는 핫스팟도 꺼져 있다
  # (이 부팅에 순정 드라이버를 내린 차는 dg_kv가 이미 재부팅 문구를 줬으므로 그대로 둔다)
  [ "$_dgvs" = bcmup ] && [ "$DGV_MSG" = "$DG_BCMUP_MSG" ] && DGV_MSG=$DG_BCMUP_NOAP_MSG
  [ -n "$DGV_MSG" ] || { DGV_MSG=$DG_APUP_MSG; DGV_LV=1; }
  return 0
}
kp_verdict() {
  kp_collect
  V_CODE=; V_LV=1; V_MSG=; V_END=no; V_FIRST=; V_FIRST_LV=
  # 재리뷰 L-3: 지금 폰이 연결돼 있는가(카플레이 연결 수 또는 이번 부팅 무선 AA 연결). 연결 중이면 핫스팟·Wi-Fi 꺼짐 판정을 내지 않는다
  _vconn=no; { [ "${K_CP:-0}" != 0 ] || [ "$K_AAOK" = yes ]; } && _vconn=yes
  _vs() { V_CODE=$1; V_LV=$2; V_MSG=$3; }
  # 베타 2 #64: HMG-API 부팅 보호에 걸려 이번 부팅 훅이 꺼짐. 연결 중이 아니면 다른 판정보다 앞에(이것을 풀지 않으면 다른 것은 의미 없음).
  # HMG-API를 지우면(uninstall.sh) 모드가 바꾼 파일이 순정으로 돌아가 다시 적용해야 하므로, 지우지 말고 다시 설치(업데이트)하라고 쓴다
  # 8~9장 리뷰 L1: 이번 부팅은 부팅 보호로 시작했는데 지금 starts가 4보다 작으면(걸린 부팅에서는 4 이상이 남는다) 그 사이 HMG-API를
  # 다시 설치해 0이 된 것이다. 같은 일을 또 시키지 않고 재부팅만 안내한다
  # 1.8.0 변조 검사(소유자 결정 11-18): 서비스가 패키지 파일이 목록과 다르다고 남겼거나($W/kp.tamper "bad"), 목록 파일이 없으면
  # 다른 무엇보다 앞에 "변조된 Korea Projection"을 보인다(서비스는 아무것도 하지 않고 멈춰 있음). 빠르게 판정하려고 여기서는 다시 해시하지 않는다
  if kp_tampered; then
    _vs tampered 2 "$TAMPER_MSG"; V_END=yes
  elif [ "$K_GUARD" = yes ] && [ "$_vconn" = no ] && [ "$K_ZHOOK" = guard ] && [ -n "$K_STARTS" ] && [ "$K_STARTS" -lt 4 ]; then
    _vs bootguard 1 "HMG-API를 다시 설치한 것으로 보입니다. 재부팅하고 3분 넘게 켜 두세요."
  elif [ "$K_GUARD" = yes ] && [ "$_vconn" = no ]; then
    _vs bootguard 2 "HMG-API가 재부팅이 너무 잦은 것으로 보고 무선 기능을 껐습니다. HMG-API를 지우지 말고 NEMESIS에서 다시 설치(업데이트)한 뒤 재부팅하고, 3분 넘게 켜 두세요."
  # 베타 3(B3-7): softap.conf를 다시 읽는 처음 3분은 그 안내(실패 문구 대신)
  elif [ "$K_PST" = run ] && [ "$K_PSTAGE" = "$SOFTAP_RETRY_MSG" ]; then _vs installing 1 "$SOFTAP_RETRY_MSG"
  elif [ "$K_PST" = run ]; then _vs installing 1 "설치 중입니다. 끝날 때까지 기다려 주세요."
  elif ! car_in "$K_PROD" "$CARS"; then _vs untested 1 "확인되지 않은 차입니다. QR로 제보해 주세요."
  elif [ -z "$K_HMGV" ]; then _vs nohmgapi 2 "HMG-API가 없습니다. HMG-API 1.0.2 이상을 설치해 주세요."
  elif ver_lt "$K_HMGV" 1.0.2; then _vs oldhmgapi 2 "지원하지 않는 HMG-API 버전입니다. 1.0.2 이상으로 업데이트해 주세요."
  # 리뷰 H-1: 기록이 있어도 지금 칩이 보이거나 모드가 이미 있으면(다른 앱으로 Wi-Fi를 켠 차 등) "안 됨"으로 보지 않는다
  # 시험판 5 리뷰 중간 5: 동글을 쓰는 중(기다림·꽂기 전·동글 AP 띄우는 중·무선 없는 실패)이면 부품 없음·칩 판정보다 먼저 동글 문구
  elif dg_verdict; then _vs dongle "$DGV_LV" "$DGV_MSG"
  elif [ -f $BK/wifi.nopart ] && [ "$K_MOD" = no ] && ! wifi_chip_seen; then _vs nopart 2 "$NOPART_MSG"; V_END=yes
  # 베타 2 RS-15(#425): 우리가 넣지 않은 다른 무선 모드(예: 2.3.0)가 깔린 부품 없는 차는 "무선 모드가 꺼짐·적용 안 됨"보다
  # 부품 없음이 먼저다. 지금 연결이 없고, 다른 Wi-Fi 패키지의 hostapd도 돌지 않을 때만(동글 패키지 등으로 무선이 되는 차를 덮지 않게)
  # 리뷰 중간: 우리 AP가 떠 있거나(동글 차는 내장 칩이 없어 nopart 기록이 남음) 동글 길을 쓰는 중이면 여기로 오지 않는다
  elif [ -f $BK/wifi.nopart ] && [ "$K_MOD" != no ] && [ ! -f $BK/mod.ours ] && ! wifi_chip_seen && [ "$_vconn" = no ] && [ "$K_OURAP" = no ] \
      && ! foreign_hostapd && ! dg_state_inuse; then _vs nopart 2 "$NOPART_MSG"; V_END=yes
  elif [ -f $BK/wifi.nochip ] && [ "$K_MOD" = no ] && ! wifi_chip_seen; then _vs nochip 2 "$NOCHIP_MSG"; V_END=yes
  elif [ "$K_MOD" = no ] && [ -f $BK/wifi.wake ] && [ ! -f $BK/wifi.woke ] && [ ! -f $BK/mod.tried ] && ! wifi_chip_seen \
      && wake_count && [ "$_wbad" = 0 ] && [ "$_wc" -lt "$WAKE_BOOTS" ]; then
    # 재리뷰 중간 1: 아직 깨울 횟수가 남았을 때만(칩을 한 번 본 차·모드를 지운 차·횟수를 다 쓴 차는 원래 판정으로)
    _vs wificheck 1 "$WIFI_CHECK_MSG (확인 $_wc/$WAKE_BOOTS)"
  elif [ -d /data/nemesis/apps/wireless.projection ] && [ "$K_MOD" = no ]; then
    _vs otherpkg 2 "다른 패키지인 wireless.projection이 설치되어 있어 충돌할 수 있습니다. wireless.projection을 삭제한 뒤 재부팅해 주세요."
  elif [ "$K_OURAP" = no ] && [ "${K_CP:-0}" = 0 ] && [ "$K_AAOK" = no ] && foreign_hostapd; then
    # 1.7.3(G-3): 우리 것도 순정(netd)도 아닌 hostapd(USB 동글 패키지 등)가 실제로 돌고, 연결도 없음. 리뷰 H-2: 순정 설정을
    # 못 읽어 stock_ssid가 unknown인 경우(순정 카플레이 AP 차 등)는 여기로 오지 않는다. 지우는 법(U-6)은 붙이지 않는다
    # 1.7.4(Q-8): 1.8.0(USB Wi-Fi 동글)에서 바뀔 곳. 동글 차는 우리 hostapd가 동글 장치(WIF)를 쓰게 되므로, 이 판정·문구(G-3)와
    # 다른 동글 패키지(usbwifi.hotspot·stock.hotspot)와의 관계를 그때 다시 정한다. 1.7.4에서는 문구·조건을 바꾸지 않는다
    _vs otherwifi 2 "다른 Wi-Fi 패키지가 핫스팟을 쓰고 있어 함께 쓸 수 없습니다. 그 패키지를 지운 뒤 재부팅해 주세요."
  elif [ "$K_PST" = reboot ]; then
    # 1.7.3(U-8): 남은 재부팅 횟수. 모드를 새 판으로 바꾸는 중이면 재부팅이 두 번 필요하다(G-2①)
    # 리뷰 L-3: 두 번 재부팅이 필요할 때는 진행 기록 문구 대신 한두 문장으로
    # 리뷰 L10: 모드는 아직 옛 판이다(재부팅 뒤 서비스가 바꾼다). "바꿨습니다"라고 쓰지 않는다
    if [ "$K_PENDING" = yes ]; then _vs reboot 1 "재부팅하면 무선 모드를 새 버전으로 바꿉니다. 재부팅하고 3분 뒤 한 번 더 재부팅해 주세요(남은 재부팅 2번)."
    else
      # 1.7.4(소유자 문구, 1.7.3 재리뷰 L-5의 "진행 기록 첫 문장 + 재부팅 1번" 두 문장을 바꿈): 진행 기록 첫 문장을 앞에 붙이지 않는다(K_PSTAGE는 실패 판정 failed에서만 씀)
      # 1.8.0 정식(A4·H-5): 업데이트로 무선 모드를 바꾼 재부팅이면 소유자 문구. 옛 버전 진행 기록 문장도 같은 경우로 본다(업데이트 직후 부팅)
      case "$K_PSTAGE" in
        "$MODUPD_MSG"|"무선 모드를 새 버전("*")으로 바꿨습니다. 3분 후 재부팅해 주세요.") _vs reboot 1 "$MODUPD_MSG" ;;
        *) _vs reboot 1 "3분 후 재부팅해 주세요." ;;
      esac
    fi
  elif [ "$K_PENDING" = yes ] && [ "$(cat $BK/mod.try 2>/dev/null)" = "$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)" ]; then
    # 리뷰 L10: 이번 부팅에 이미 시도했는데 아직 옛 판이면 이번에는 못 바꾼 것이다(일시 실패, 다음 부팅에 다시 시도)
    _vs modwait 1 "무선 모드를 이번에는 새 버전으로 바꾸지 못했습니다. 재부팅하면 다시 시도합니다."
  elif [ "$K_PENDING" = yes ]; then
    _vs modwait 1 "무선 모드를 새 버전으로 바꾸는 중입니다. 3분 뒤 한 번 더 재부팅해 주세요(남은 재부팅 1번)."
  elif [ "$K_PST" = fail ] && plan_this_boot && plan_problems | $BB grep -q .; then
    # 1.7.3(H-1): HMG-API가 적용을 거절함(계획에 problem 줄). 우리가 넣지 않은 파일은 고치지 않는다(D-5)
    _vs hmgrefuse 2 "HMG-API가 적용을 거절했습니다. HMG-API 앱의 'Can't apply' 창 아래쪽을 확인해 주세요."
  elif [ "$K_PST" = fail ] && [ -n "$K_PSTAGE" ]; then
    # 1.7.4(P-4, #277): 서비스가 진행 기록에 남긴 이유 문장(hotspot.sh)으로 판정 코드를 가른다(QR의 verdict로 이유를 알 수 있게)
    case "$K_PSTAGE" in
      # 배포판(문구 수정 11-23): 업데이트한 부팅에는 옛 버전이 쓴 옛 문장이 진행 기록에 남을 수 있어 옛 문장도 받고, 보이는 문장은 새 것으로
      "$MAPFAIL_MSG"|"$MAPFAIL_MSG_OLD") _vs mapfail 2 "$MAPFAIL_MSG" ;;
      "$NOMAP_MSG"|"$NOMAP_MSG_OLD") _vs nomap 2 "$NOMAP_MSG" ;;
      # 리뷰: 다시 깨우지 않는 상태라 재부팅으로 안 바뀔 수 있다(문제, 빨강)
      "$WIFIGONE_MSG") _vs wifigone 2 "$K_PSTAGE" ;;
      *) _vs failed 2 "$K_PSTAGE" ;;
    esac
  elif [ "$K_FAKEKEY" = yes ]; then
    # 베타 3(B3-10): HMG-API가 우리 새 버전 설치를 거부한다(키가 다름). 연결이 되고 있으면 노랑, 아니면 빨강
    if [ "${K_CP:-0}" = 0 ]; then _vs modkey 2 "$MODKEY_MSG"; else _vs modkey 1 "$MODKEY_MSG"; fi
  elif [ "$K_FOREIGN" = yes ] && [ "${K_CP:-0}" = 0 ]; then
    # 1.7.3(G-2③): 외국·공식 모드. HMG-API를 통째로 지우면 권한 파일이 남아 거절될 수 있다(#94·#130)
    _vs foreign 2 "차에 있는 HMG-API 무선 모드가 국내용이 아닙니다. HMG-API 앱에서 그 모드만 지우고(HMG-API는 지우지 말고) 적용한 뒤 재부팅해 주세요."
  elif [ "$K_MOD" = no ] && [ -f $BK/mod.tried ]; then
    # 1.7.3(G-2②): 차주가 지운 상태(지운 기록)와 넣지 못한 상태를 다른 문구로
    _vs modgone 2 "무선 모드를 지운 기록이 있어 다시 넣지 않습니다. 다시 쓰려면 Korea Projection을 지우고 다시 설치한 뒤 재부팅해 주세요."
  elif [ "$K_MOD" = no ]; then
    _vs nomod 2 "무선 모드를 넣지 못했습니다. USB를 꽂고 상태 화면의 [제보 파일 만들기]를 눌러 보내 주세요."
  elif [ "$K_MODON" = no ]; then _vs modoff 2 "HMG-API 무선 모드가 꺼져 있습니다. HMG-API 앱에서 켜고 Apply changes 후 다시 시작해 주세요."
  elif [ "$K_BRIDGE" = off ]; then _vs bridgeoff 2 "무선 모드의 'Wireless CarPlay' 설정이 꺼져 있습니다. HMG-API 앱에서 켜고 Apply changes 후 다시 시작해 주세요."
  elif [ "$K_HK" = off ]; then
    case "$K_HKMAP" in
      mapped) _vs hooksoff 1 "HMG-API 훅이 꺼져 있습니다. HMG-API 앱 Settings에서 'Check the map on this car'를 누른 뒤 재부팅해 주세요." ;;
      none) _vs hooksoff 1 "HMG-API에 이 차의 MAP이 없어 훅이 꺼져 있습니다. QR로 제보해 주세요." ;;
      mismatch) _vs hooksoff 1 "HMG-API MAP이 이 차의 소프트웨어와 맞지 않아 훅이 꺼져 있습니다. QR로 제보해 주세요." ;;
      *) _vs hooksoff 1 "HMG-API 훅이 꺼져 있습니다(마지막 부팅 기록). 3분 후 재부팅(RESET 버튼 또는 NEMESIS 재부팅)한 뒤 다시 확인해 주세요." ;;
    esac
  elif [ "$K_MH" = off ]; then _vs modhooksoff 2 "HMG-API가 이 차에서 무선 모드를 켜지 못했습니다(이 차와 맞지 않는 부분이 있음). 재부팅해 보시고, 그래도 같으면 USB를 꽂고 [제보 파일 만들기]로 제보 파일을 보내 주세요."
  elif ! k_feat com.hkmc.software.connectivity.carplay_wireless; then _vs nofeat 2 "무선 프로젝션 기능이 꺼져 있습니다. HMG-API 무선 모드를 확인해 주세요."
  elif [ "$K_APMODE" != stock ] && [ -f $BK/stockap.seen ] && [ "$K_OURAP" = no ] && [ "$_vconn" = no ]; then
    _vs stockoff 1 "Wi-Fi가 지금 꺼져 있습니다. 휴대폰을 연결해 보고, 안 되면 3분 후 재부팅해 주세요."
  elif [ "$K_APMODE" != stock ] && [ "$K_NOWLAN" = yes ] && [ "$K_OURAP" = no ] && [ "$_vconn" = no ] && [ "$K_NLB" -ge 3 ]; then
    # 리뷰 M-3: 모드가 있는데 wlan0이 3번 넘는 부팅 동안 안 생김(그랜저 IG #55 꼴). 재리뷰 중간 3②: 칩 실패(W-2·W-6, 안 됨으로 끝남)는
    # 근거(커널 칩 실패 줄·module_version 3)가 있을 때만. 근거가 없으면 제보를 부탁한다(지우는 법 없음)
    if chip_fail_evidence; then _vs nowlanfail 2 "$NOCHIP_MSG"; V_END=yes
    else _vs nowlanrepeat 2 "Wi-Fi 장치가 계속 켜지지 않습니다. 3분 후 재부팅해도 같으면 USB를 꽂고 [제보 파일 만들기]로 알려 주세요."; fi
  elif [ "$K_APMODE" != stock ] && [ "$K_NOWLAN" = yes ] && [ "$K_OURAP" = no ] && [ "$_vconn" = no ]; then
    # 1.7.3(W-4·G-1): wlan0이 이번 부팅에 생기지 않음 = Wi-Fi가 꺼져 있거나 늦게 켜짐. 서비스가 다시 켜므로 재부팅 뒤 다시 확인
    _nl=$K_NLB; [ "$_nl" -ge 1 ] || _nl=1
    _vs wifioff 1 "$WIFI_CHECK_MSG (확인 $_nl/3)"
  elif [ "$K_APMODE" != stock ] && { [ "$K_OURAP" = no ] || [ "$K_DHCP" = no ]; } && [ "$_vconn" = no ]; then
    _vs apoff 1 "핫스팟이 꺼져 있습니다. 3분 후 재부팅(RESET 버튼 또는 NEMESIS 재부팅)한 뒤 다시 확인해 주세요."
  elif ver_lt "${K_NEM:-0}" 1.16; then _vs oldnemesis 1 "NEMESIS를 1.16 이상으로 업데이트해 주세요."
  elif [ "${K_CP:-0}" != 0 ] || [ "$K_AAOK" = yes ]; then
    # 1.7.3(U-10): 확인 안 된 차(README ✅ 아님)가 연결되면 제보를 부탁한다(QR 요약 맨 앞 result: connected).
    # 리뷰 L-6: 무선 안드로이드 오토 연결도 연결로 본다(CLAUDE.md 2장 ✅ 기준)
    # 베타 1(소유자 요청): 카플레이와 안드로이드 오토를 한 줄로(상태 화면은 AA 준비됨·연결됨 줄을 따로 두지 않음)
    if car_in "$K_PROD" "$CARS_SEEN"; then
      if [ "${K_CP:-0}" != 0 ] && [ "$K_AAOK" = yes ]; then _vs connected 0 "무선 프로젝션 연결됨"
      # 리뷰 5: AA가 카플레이 때문에 기다리는 중(cpwait)이면 "준비됨"이라 하지 않는다(노란 안내 줄과 어긋나지 않게)
      elif [ "${K_CP:-0}" != 0 ] && [ "$K_AARDY" = yes ] && [ "$K_AAWAIT" = no ]; then _vs connected 0 "무선 카플레이 연결됨, 안드로이드 오토 준비됨"
      elif [ "${K_CP:-0}" != 0 ]; then _vs connected 0 "무선 카플레이 연결됨"
      # 리뷰 4: "카플레이 준비됨"은 우리 핫스팟이 켜져 있을 때만
      # 1.7.4(소유자 지시): Wi-Fi는 하나이고 카플레이·AA가 같은 Wi-Fi를 쓰므로 AA가 붙었으면 카플레이도 준비된 것으로 늘 보인다
      else _vs connected 0 "무선 안드로이드 오토 연결됨"; fi
    else _vs newconnected 0 "연결됐습니다! QR로 '연결됨'을 알려 주시면 지원 목록에 올립니다."; fi
  # 1.7.4(소유자 지시): 순정 Wi-Fi 차도 둘 다 준비됨으로 보인다(같은 Wi-Fi, 근거 #101 캐스퍼 AX1).
  # 순정 Wi-Fi 차에서 우리 AA 신호(aa_sig)를 켜지 않는 동작은 그대로다(순정이 자기 AP를 이미 앎)
  # 1.7.4(L-9): AA 끄기 기능을 없애 "AA를 끈 차"(카플레이만 준비됨) 갈래를 뺐다
  elif [ "$K_APMODE" = stock ]; then _vs ready 0 "무선 프로젝션 준비됨."
  elif [ "$K_AARDY" = yes ]; then _vs ready 0 "무선 프로젝션 준비됨."
  else _vs ready 0 "무선 카플레이 준비됨(안드로이드 오토는 준비 중)."
  fi
  # 1.7.3(G-4): README ✅ 차종인데 문제가 있으면 "먼저 할 일". 근거 있는 끝(부품 없음·칩)·설치 중·재부팅 필요·확인 안 된 차는 빼고,
  # 내비 버전(펌웨어 끝 6자리 날짜)이 확인된 차(260902)보다 옛것이면 내비 업데이트를 맨 앞에(같은 차종, 다른 버전은 같은 차로 보지 않음)
  # 1.7.4(B-5): 기준은 그 차종이 확인된 버전(car_model_seen의 _CMD, 레이 TAM22는 260604). 버전 없이 적힌 차종(BDPE)은 비교하지 않음
  # 리뷰 L-1: 원인이 분명한 판정과 부팅 직후(5분 안)의 핫스팟 꺼짐에는 붙이지 않는다
  _vup=$(up_s); case "$_vup" in ''|*[!0-9]*) _vup=9999 ;; esac
  _g4=
  case "$V_CODE" in dongle|installing|untested|nopart|nochip|nowlanfail|nowlanrepeat|reboot|modwait|wificheck|wifioff|failed|mapfail|nomap|wifigone|ready|connected|newconnected|nohmgapi|oldhmgapi|otherpkg|otherwifi|foreign|modgone|modkey|hmgrefuse|oldnemesis|bootguard) ;;
    apoff) [ "$_vup" -lt 300 ] || _g4=1 ;;
    *) _g4=1 ;;
  esac
  if [ "$_g4" = 1 ]; then
       if car_model_seen "$K_PROD"; then
         _fd=$(fw_date "$K_PROD")
         if [ -n "$_fd" ] && [ -n "$_CMD" ] && [ "$_fd" -lt "$_CMD" ] && [ "${K_PROD%%.*}" != BDPE ]; then
           V_FIRST="먼저 할 일: 내비 버전이 확인된 차($_CMD)보다 구버전입니다. 내비를 업데이트한 뒤 NEMESIS·HMG-API·Korea Projection을 다시 설치해 주세요."; V_FIRST_LV=1
         elif car_in "$K_PROD" "$CARS_SEEN"; then
           V_FIRST="먼저 할 일: 같은 차에서 된 분이 있습니다. 3분 후 재부팅 2번, 최신 버전 설치, 등록된 휴대폰을 모두 지운 후 다시 설정해 주세요."
         fi
       fi
  fi
  # 1.8.0 K-5(#259·#260·#266): 목록에 없는 차종이라도 내비가 확인된 판(260902)보다 옛것이면 내비 업데이트를 먼저 권한다(CLAUDE.md 2장).
  # 지도 만들기·확인 실패(mapfail·nomap·failed), 모드 훅이 안 켜짐(modhooksoff, #259가 이 경우), 부팅 5분 뒤에도 핫스팟 꺼짐(apoff)에만 붙인다. 연결된 차·설치 중·
  # 근거 있는 끝(부품 없음 등)·차주가 끈 것(모드 끔 등)에는 붙이지 않는다
  if [ -z "$V_FIRST" ] && ! car_model_seen "$K_PROD" && [ "${K_PROD%%.*}" != BDPE ]; then
    _fd=$(fw_date "$K_PROD")
    if [ -n "$_fd" ] && [ "$_fd" -lt 260902 ]; then
      # 리뷰 중간 1: G-4의 _g4를 이어 쓰지 않는다(그러면 모드를 끈 차 등에도 재설치를 권했다). 이 경우만 따로 고른다
      _k5=
      case "$V_CODE" in mapfail|nomap|failed|modhooksoff|apoff) _k5=1 ;; esac
      [ "$V_CODE" = apoff ] && [ "$_vup" -lt 300 ] && _k5=
      # 소유자 결정(11-18): 옛 내비에서도 잘 될 수 있으므로 오류가 아니라 주의(first_lv=1, 노랑)로 넘긴다
      [ "$_k5" = 1 ] && { V_FIRST="먼저 할 일: 내비 버전이 확인된 차(260902)보다 구버전입니다. 내비를 업데이트한 뒤 NEMESIS·HMG-API·Korea Projection을 다시 설치해 주세요."; V_FIRST_LV=1; }
    fi
  fi
  # 1.8.0 K-6(#128): 순정 Wi-Fi 차(ap_mode=stock)에 ADB TCP 스위치가 켜져 있으면 eth0 주소가 순정 대역과 겹칠 수 있다(추정, 차에서 확인 안 함).
  # 연결된 차·설치 중에는 보이지 않는다. 다른 "먼저 할 일"(내비 업데이트 등)이 있으면 덮지 않는다. 판정·동작은 그대로(문구만)
  if [ -z "$V_FIRST" ] && [ "$K_APMODE" = stock ] && [ "$(getprop persist.service.adb.tcp.enable 2>/dev/null)" = 1 ]; then
    case "$V_CODE" in connected|newconnected|installing) ;;
      *) V_FIRST="먼저 할 일: ADB TCP가 켜져 있습니다. ADB TCP를 끄고 재부팅해 주세요." ;;
    esac
  fi
  # 1.8.0 베타 2 NM-2(NEMESIS 1.16.8): 무선 ADB 타일(service.adb.tcp.port=5555). K-6과 같은 조건(순정 Wi-Fi 차, 연결 안 됨·설치 중 아님).
  # 리뷰 중간: 5555는 build.prop 등 다른 데서도 올 수 있어 NEMESIS가 켰다는 표시(adb_tcp_prev)가 있을 때만
  if [ -z "$V_FIRST" ] && [ "$K_APMODE" = stock ] && [ -e ${NEMDATA:-/data/nemesis}/adb_tcp_prev ] && [ "$(getprop service.adb.tcp.port 2>/dev/null)" = 5555 ]; then
    case "$V_CODE" in connected|newconnected|installing) ;;
      *) V_FIRST="먼저 할 일: NEMESIS의 무선 ADB를 꺼 주세요."; V_FIRST_LV=1 ;;
    esac
  fi
  # 1.8.1 W-2(리뷰 1 H1): 예전 wireless.projection 흔적은 막지 않고 "먼저 할 일"로만(다른 먼저 할 일이 없고, 연결·설치 중이 아닐 때)
  if [ -z "$V_FIRST" ] && wp_trace; then
    case "$V_CODE" in connected|newconnected|installing|tampered) ;; *) V_FIRST="먼저 할 일: $WP_TRACE_MSG"; V_FIRST_LV=1 ;; esac
  fi
  # 1.8.1 T1-2: 같은 기능의 다른 패키지·모드가 켜져 있으면 다른 "먼저 할 일"보다 앞에(연결 중에도 보임: 연결돼도 계기판 길안내가 다툼).
  # 아래 USB ADB 안내만 이보다 앞선다(USB가 막히면 다른 것을 확인할 수 없음). 문구는 소유자 결정(Y-1) 그대로
  if tbt_other; then V_FIRST=$TBT_CONFLICT_MSG; V_FIRST_LV=1; fi
  # NM-2: USB ADB가 켜져 있으면(USB 포트가 기기 모드라 USB·유선 카플레이·동글을 못 씀) 다른 "먼저 할 일"보다 앞에 둔다. 연결 중·설치 중에도
  # 보인다(USB 리포트·유선 카플레이를 못 쓰므로). NEMESIS가 켰다는 표시(adb_usb_prev)가 있을 때만 "NEMESIS의"라고 쓴다. 판정·동작은 그대로(문구만)
  if usb_adb_on; then
    if [ -e ${NEMDATA:-/data/nemesis}/adb_usb_prev ]; then V_FIRST="먼저 할 일: NEMESIS의 USB ADB를 끄고 재부팅해 주세요."
    else V_FIRST="먼저 할 일: USB ADB가 켜져 있습니다. USB ADB를 끄고 재부팅해 주세요."; fi
    V_FIRST_LV=1
  fi
  # 1.7.4(묶음 C 리뷰 중간 2): 옛 판의 칩 실패 기록이 남은 차(kp_legacy_nochip). D-1(1.7.3 이상만 지원)대로 다시 깨우지 않으므로,
  # 그 상태일 때만 상태 화면에 한 줄을 더 보인다. 판정·동작은 그대로(문구만). 리뷰 반영: 다른 "먼저 할 일"이 있으면 덮지 않는다
  if [ -z "$V_FIRST" ] && kp_legacy_nochip; then V_FIRST="구버전의 기록이 남은 차입니다. 삭제 → 재부팅 → 다시 설치해 주세요."; fi
  # 1.8.0: 변조된 패키지에는 "먼저 할 일"을 붙이지 않는다(판정 문구 하나만)
  [ "$V_CODE" = tampered ] && { V_FIRST=; V_FIRST_LV=; }
  # 베타 3(B3-3 b_red): 운행·설정 중 실패인 빨강이면 서비스에 디버그 로그 켜기를 요청한다(목록은 hotspot.sh DBG_RED)
  [ "$V_LV" = 2 ] && dbg_red "$V_CODE"
  # 1.7.3(U-9): 차주용 요약 3줄
  case "$V_CODE" in
    installing) V_S1="설치: 진행 중" ;;
    reboot|modwait|wificheck) V_S1="설치: 재부팅 필요" ;;
    untested) V_S1="설치: 이 차는 대기 중" ;;
    bootguard) V_S1="설치: HMG-API 훅 꺼짐(부팅 보호)" ;;
    dongle|ready|connected|newconnected|stockoff|wifioff|nowlanrepeat|apoff|oldnemesis|hooksoff) V_S1="설치: 끝남" ;;
    *) V_S1="설치: 안 됨(위 안내를 보세요)" ;;
  esac
  if [ "$K_OURAP" = yes ]; then V_S2="무선 Wi-Fi: 켜짐"
  elif [ "$K_APMODE" = stock ]; then V_S2="무선 Wi-Fi: 켜짐(내비 순정)"
  elif [ "$V_CODE" = nopart ]; then V_S2="무선 Wi-Fi: 부품 없음"
  elif [ "$V_CODE" = nochip ] || [ "$V_CODE" = nowlanfail ]; then V_S2="무선 Wi-Fi: 칩이 켜지지 않음"
  elif [ "$V_CODE" = nowlanrepeat ]; then V_S2="무선 Wi-Fi: 장치가 켜지지 않음(확인 중)"
  elif [ "$V_CODE" = wificheck ] || [ "$V_CODE" = wifioff ]; then V_S2="무선 Wi-Fi: 켜는 중(재부팅 뒤 확인)"
  elif [ "$V_CODE" = wifigone ]; then V_S2="무선 Wi-Fi: 칩이 지금 안 보임(전에는 보임)"
  else V_S2="무선 Wi-Fi: 꺼짐"; fi
  if [ "${K_CP:-0}" != 0 ]; then V_S3="휴대폰 연결: 카플레이 ${K_CP}대 연결됨"
  elif [ "$K_AAOK" = yes ]; then V_S3="휴대폰 연결: 안드로이드 오토 연결됨"
  else V_S3="휴대폰 연결: 지금 연결된 휴대폰 없음"; fi
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
  # 1.8.1 W-8: NEMESIS LivePatch 한 줄(서비스가 시작할 때 읽은 것, 앱이 그대로 보임)
  echo "lp=$(lp_state s)"
  echo "wp=$(yesno [ -d /data/nemesis/apps/wireless.projection ])"
  echo "mod=$K_MOD"
  echo "modver=$(mod_ver)"
  echo "mod_pending=$K_PENDING"
  echo "mod_pin=$(mod_pin_ver)"
  echo "mod_hooks=$K_MH"
  echo "mod_foreign=$K_FOREIGN"
  echo "mod_on=$K_MODON"
  echo "bridge=$K_BRIDGE"
  echo "hooks=$K_HK"
  echo "hookmap=$K_HKMAP"
  echo "feat_carplay=$(yesno k_feat com.hkmc.software.connectivity.carplay_wireless)"
  echo "feat_aa=$(yesno k_feat com.hkmc.software.connectivity.androidauto_wireless)"
  echo "feat_wifi=$(yesno k_feat android.hardware.wifi)"
  echo "wlan0=$(yesno [ -d /sys/class/net/$WIF ])"
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
  # 1.8.0 X-9: 디버그 로그(앱의 "고급" 토글이 읽음). debug=yes|no 지금 켜기 표시, debug_auto=none|on|wait|done|off
  dbg_kv
  # 1.8.0 DG-4: 동글 드라이버 상태(dongle·dongle_lv·dongle_msg). 판정 줄과 따로 둔다
  dg_kv
  # 1.8.0 SC-5: 동글 토글(켜짐·누가 정했나·자동 근거)
  dg_toggle_kv
  # 1.7.0: 설치 진행 상태(run·done·reboot·fail, 없으면 none). 1.7.4(L-9): 무선 안드로이드 오토 켜짐 키(aa)는 뺐다(늘 켜짐)
  _ps=$($BB awk -F= '$1 == "state" { print $2 }' $PROG 2>/dev/null); echo "state=${_ps:-none}"
  # 1.7.0: 이번 부팅에 Wi-Fi 장치(wlan0)가 생기지 않아 핫스팟을 못 켠 기록(hotspot.sh wlan_fail)
  echo "nowlan=$K_NOWLAN"
  echo "made=$(date '+%Y-%m-%d %H:%M')"
  # 1.7.3(K-5): 판정 결과(앱·리포트·QR이 같은 값을 쓴다)
  echo "verdict=$V_CODE"
  echo "verdict_lv=$V_LV"
  echo "verdict_msg=$V_MSG"
  echo "verdict_end=$V_END"
  echo "first=$V_FIRST"
  # 1.8.0: "먼저 할 일"의 수준(앱이 색을 고름). 1 = 주의(노랑, 옛 내비 업데이트 권유). 빈 값 = 앱의 지금 동작 그대로
  echo "first_lv=$V_FIRST_LV"
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
    # 1.8.0 PF-4: 제보 만들기는 낮은 우선순위로 돈다(뒤에서 부르는 carreport.sh도 물려받음). renice가 없거나 실패해도 그대로 진행.
    # 시작 시각은 리포트 부하 칸에 한 줄로 남긴다(그 뒤 perf.log의 부하는 제보 만들기 몫으로 읽게)
    renice 10 $$ >/dev/null 2>&1
    RSTART_T=$(date '+%m-%d %H:%M:%S' 2>/dev/null)
    # 리뷰 중간 2: 도중에 끝나도(TERM·HUP·INT) 임시 파일을 지운다. 끝나면 trap을 되돌린다(감시자는 이어서 돈다)
    trap '$BB rm -f $LCTMP $DINFO; exit 1' TERM HUP INT
    $BB rm -f $LCTMP; logcat -d -v time 2>/dev/null > $LCTMP; LC_ON=1
    rprog 5 run "제보 파일을 만드는 중입니다(내비 상태)"
    report 2>/dev/null > $R; $BB chmod 600 $R
    # 배포판: 비공개 파일의 동글 조사 칸은 logcat을 한 번만 읽게(PF-4) 받아 둔 동안 미리 만든다(600, $W 안, 비공개 파일을 쓰면 지움)
    $BB rm -f $DINFO; { [ -f $W/cp.log ] || [ -f $DG_ON ] || [ -f $BK/dongle.used ]; } && { dongle_info 2>/dev/null > $DINFO; $BB chmod 600 $DINFO; }
    _collect
    LC_ON=; $BB rm -f $LCTMP
    trap - TERM HUP INT
    # 리뷰 낮음 1: 감시자(--watch)가 만들었으면 감시자 자신이 낮아진 채로 남지 않게 되돌린다(root라 올릴 수 있음)
    renice 0 $$ >/dev/null 2>&1
  else
    rprog 100 fail "USB가 없습니다. USB를 꽂은 뒤 [제보 파일 만들기]를 다시 눌러 주세요."
  fi
  rm -f $W/collect.pid
}
_collect() {
  rprog 10 run "로그를 모으는 중입니다(서비스·HMG-API 로그)"
  logs 2>/dev/null > $G; $BB chmod 600 $G
  # 1.8.0 PF-4(리뷰 중간 2): 받아 둔 logcat 원본(폰 이름이 들어갈 수 있음)은 쓰는 곳(report·logs)이 끝나면 바로 지운다
  LC_ON=; $BB rm -f $LCTMP
  rprog 75 run "USB에 저장하는 중입니다"
  where=""
  for u in $USBS; do
    # 마운트 지점 폴더는 USB가 없어도 있을 수 있다: /proc/mounts로 확인
    # 제보 자료는 USB의 한 폴더($RDIR)에 정해진 이름으로 둔다: 1-report.md, 2-car-report.json(carreport.sh), 3-log.txt
    # 예전 제보의 2-car-report.json·4번은 지운다(새 파일과 섞이지 않게)
    # 1.7.1까지 제보 폴더에 두던 4-debug-private.txt도 지운다(1.7.2부터는 $PDIR에 둔다)
    # 베타 3: 옛 위치($PDIR)의 4-debug-private.txt와 지난 5-dongle-private.txt도 지운다(두 곳에 같은 파일이 남지 않게)
    $BB grep -q " $u " /proc/mounts 2>/dev/null && $BB mkdir -p "$u/$RDIR" && $BB rm -f "$u/$RDIR/2-car-report.json" "$u/$RDIR/4-debug-private.txt" "$u/$PDIR/4-debug-private.txt" "$u/$PDIR/5-dongle-private.txt" \
      && $BB cp $R "$u/$RDIR/1-report.md" 2>/dev/null && $BB cp $G "$u/$RDIR/3-log.txt" 2>/dev/null && sync && where=$u && break
  done
  if [ -z "$where" ]; then
    rprog 100 fail "USB에 저장하지 못했습니다(USB가 빠졌거나 쓸 수 없음). USB를 다시 꽂고 [제보 파일 만들기]를 눌러 주세요."
    return 0
  fi
  # 1.7.0: 디버그 로그를 켠 차만 4-debug-private.txt를 둔다. 베타 3(소유자 결정 11-23): 제보 폴더($RDIR)에 함께(디버그 로그가 있을 때만,
  # 꺼진 차에는 빈 파일을 만들지 않음). 동글 허용 판단 정보·무선 모드 작성자 키는 $PDIR/5-dongle-private.txt에 따로
  if [ -f $W/cp.log ] && echo "x" | $BB awk "$KPMASK" >/dev/null 2>&1; then
    rprog 80 run "디버그 로그를 저장하는 중입니다"
    debuglog 2>/dev/null > "$where/$RDIR/4-debug-private.txt"; sync
  fi
  if [ -f $DG_ON ] || [ -f $BK/dongle.used ] || [ -f $W/cp.log ] || [ "$(mod_key)" = other ]; then
    $BB mkdir -p "$where/$PDIR" && dgprivlog 2>/dev/null > "$where/$PDIR/5-dongle-private.txt"; sync
  fi
  # 비공개 폴더가 비면 지운다(옛 파일만 있던 폴더가 남지 않게)
  $BB rmdir "$where/$PDIR" 2>/dev/null
  $BB rm -f $DINFO
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
    aplog "재부팅 요청 거절: 부팅 뒤 ${_un}초(HMG-API 시작 확인 시각 ${_gend}초 전)이고 HMG-API 부팅 보호 횟수 starts=$_gst(3분 안에 재부팅을 반복하면 훅이 꺼짐)"
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
    # 1.8.0: 설정 요청(토글). 감시자는 1초마다 보므로 앱이 바로 답을 받는다(hotspot.sh set_take)
    [ -f $SETREQ ] && SET_LOG=aplog set_take
    if [ -f $RBREQ ] && take_rbreq; then
      aplog "상태 화면에서 재부팅 요청: 지금 재부팅함(sync 뒤 reboot)"
      # 시험판 4: 동글 사용이 켜져 있으면 재부팅 직전에 순정 Wi-Fi 저장값을 한 번 더 맞춘다(토글 직후 재부팅해도 다음 부팅에 bcmdhd가 없게)
      dg_wifi_want && SET_LOG=aplog dg_wifi_sync >/dev/null 2>&1
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
      # 시험판 6(F2): 차주가 요청한 재부팅이다(내비가 살아 있음). 이번 부팅 동글 단계 기록에 표시해 다음 부팅이 hang으로 막지 않게(sync)
      dg_step_rbmark 2>/dev/null
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
  # 1.7.4(B-7, 리뷰 반영): 끝내기로 정한 뒤 Launch가 끝 시각을 늘렸으면, 그 Launch는 이 감시자가 살아 있다고 보고 새로 띄우지
  # 않았다. 그래서 끝 시각을 watch.pid를 지우기 전과 잠금을 푼 뒤 두 번 보고, 어느 쪽이든 늘어났으면 새 감시자를 **한 번만** 띄운다
  # (띄우는 곳은 아래 한 줄뿐). 부팅 뒤 초를 못 읽으면 띄우지 않는다(못 읽어 0으로 보면 끝 시각이 늘 커 보여 끝없이 띄우게 됨).
  # 새 감시자는 그 끝 시각에 끝나고, 그때 다시 볼 때는 늘어나지 않았으므로 또 띄우지 않는다
  _again=0
  watch_more() {
    _wu2=; _wn2=
    { read _wu2 < $W/watch.until; } 2>/dev/null
    { read _wn2 _wx < $UPTIME; } 2>/dev/null; _wn2=${_wn2%%.*}
    case "$_wu2" in ''|*[!0-9]*) return 1 ;; esac
    case "$_wn2" in ''|*[!0-9]*) return 1 ;; esac
    [ "$_wu2" -gt "$_wn2" ]
  }
  watch_more && _again=1
  [ "$(cat $W/watch.pid 2>/dev/null)" = "$_me" ] && rm -f $W/watch.pid
  rm -rf $W/watch.lock
  # 앱이 "감시자 끝남"을 알게 지금 시각으로 쓴다(못 읽으면 0). 재리뷰 L1: 그 사이 Launch가 새 끝 시각을 썼으면(이 감시자가 본 마지막
  # 값과 다름: 새 감시자가 뜸) 덮지 않는다
  _wn=; { read _wn _wx < $UPTIME; } 2>/dev/null; _wn=${_wn%%.*}; case "$_wn" in ''|*[!0-9]*) _wn=0 ;; esac
  _wf=; [ -f $WATCHF ] && _wf=$($BB awk -F= '$1 == "until" { print $2 }' $WATCHF 2>/dev/null)
  [ -z "$_wf" ] || [ "$_wf" = "$_wu" ] && watch_pub $_wn
  [ $_again = 1 ] || { watch_more && _again=1; }
  [ $_again = 1 ] && { BB=$BB $BB setsid sh $APP/bin/status.sh --watch </dev/null >/dev/null 2>&1 & }
  exit 0
fi
# 서비스 점검(hotspot.sh req_tick)이 띄운다: 요청 하나를 받아 만든다. 감시자가 살아 있으면 맡긴다.
if [ "$1" = --report ]; then
  st_alive $W/watch.pid --watch && exit 0
  if take_req; then make_report; rm -f $REQ 2>/dev/null; fi
  exit 0
fi

# 시험판 6(F8): 서비스(hotspot.sh dg_status_push)가 동글 단계가 바뀔 때 띄운다. 상태 파일만 다시 쓴다(앱 설치·감시자·제보는 하지 않음).
# 상태 파일이 없으면(Launch를 한 번도 누르지 않음) 아무것도 하지 않는다. Launch와 임시 파일 이름이 겹치지 않게 .push를 붙인다
if [ "$1" = --push ]; then
  [ -f $STATUS ] || exit 0
  umask 022
  # 리뷰 중간 4: 임시 파일은 이 프로세스 것($$)만 쓴다. 다 쓴 뒤 같은 폴더에서 mv로 바꿔 앱이 반쯤 쓰인 파일을 읽지 않게 한다
  _sp=$STATUS.push.$$
  status_kv 2>/dev/null > $_sp && { $BB awk -F= '$1 != "debug" && $1 != "debug_auto" && $1 != "debug_left" && $1 != "debug_rec" && $1 != "debug_why" && $1 != "debug_src"' $_sp > $_sp.2 && dbg_kv >> $_sp.2 && $BB mv -f $_sp.2 $_sp; } 2>/dev/null; rm -f $_sp.2
  [ -s $_sp ] && $BB chmod 644 $_sp && $BB mv -f $_sp $STATUS
  rm -f $_sp
  exit 0
fi
# 1.7.3(K-3): 하위 셸 없이 이 셸에서 쓴다(그래야 끝의 한 줄 요약이 방금 구한 값 K_*를 다시 쓸 수 있다: softap.conf·연결 수·AP 판정을
# 두 번 구하지 않음). 상태 파일만 644로 만들고 umask는 되돌린다. parse_conf가 위치 인자를 바꾸지만 이 뒤에는 $1을 쓰지 않는다.
# 리뷰 L-4: 이 셸에서 바로 돈다. status_kv 안에 $(( ))를 넣을 때는 값이 숫자인지 먼저 확인하세요(틀린 산술은 Launch 전체를 끝냄)
umask 022
# 1.8.0(리뷰 중간 2): 계산하는 몇 초 사이 설정 요청(토글)이 처리됐을 수 있으므로, 옮기기 직전에 디버그 줄 넷을 지금 값으로 다시 쓴다
status_kv 2>/dev/null > $STATUS.tmp && { $BB awk -F= '$1 != "debug" && $1 != "debug_auto" && $1 != "debug_left" && $1 != "debug_rec" && $1 != "debug_why" && $1 != "debug_src"' $STATUS.tmp > $STATUS.tmp2 && dbg_kv >> $STATUS.tmp2 && $BB mv -f $STATUS.tmp2 $STATUS.tmp; } 2>/dev/null; rm -f $STATUS.tmp2
[ -s $STATUS.tmp ] && $BB chmod 644 $STATUS.tmp && $BB mv -f $STATUS.tmp $STATUS
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
# 1.7.4(소유자 문구, 리뷰 반영): 순정 Wi-Fi 차는 판정 문구와 같은 뜻으로(L-9부터 AA는 늘 켜짐)
if [ "$K_APMODE" = stock ]; then m="Korea Projection: 무선 프로젝션 준비됨, 카플레이 연결 $c개"
else
  a=꺼짐; [ "$K_OURAP" = yes ] && a=켜짐
  d=꺼짐; [ "$K_DHCP" = yes ] && d=켜짐
  m="Korea Projection: 핫스팟 $a, DHCP $d, 카플레이 연결 $c개"
fi
echo "$m"
exit 0
