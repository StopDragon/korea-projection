#!/system/bin/sh
# 이 파일을 고친 버전은 Korea Projection 지원 대상이 아닙니다. 공식 버전: https://github.com/StopDragon/korea-projection
# korea.projection: the wireless CarPlay access point on Korean head units (tested: Niro DEPEHEV.KOR 260902;
# 시험 지원: 쏘나타 DN8 DN822HEV, 그랜저 하이브리드 IGPEHEV, 벨로스터 N JSN .KOR 260902).
# There the stock hotspot call (setWifiApEnabledForConnectivity) does nothing, but the stock
# hostapd on wlan0 (nl80211) works. NEMESIS's svcmgr starts this at boot (mode=restart); it
# waits for Android, starts hostapd + dnsmasq with the CarPlay network from softap.conf, then
# keeps them up. Output goes to /data/nemesis/logs/korea.projection/ap.log; the passphrase
# is never written there.
# Test hooks: HOTSPOT_LIB=1 only defines the functions; BB, SRC, CONF, W, PROP override paths.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
APP=${APP:-/data/nemesis/apps/korea.projection}
# busybox 고르기(1.6.0). 내비에 busybox(1.8.1)가 있으면 지금처럼 그것을 쓴다(니로 등 확인된 차는 바뀌지 않음).
# 없는 내비(K3 BDPE·K8 GL3HEV, tcc803x, #15·#19)는 패키지에 함께 넣은 busybox(1.36.1, bin/busybox)를 쓴다.
# (1.5.6은 bin/busybox를 뺐고, 1.6.2 알파에서 다시 넣었다.)
# BB를 미리 정해 두면(테스트, 예전 호출) 그대로 쓴다. 쓸 수 있는지는 한 번 실행해 보고 BB_OK에 남긴다.
BB_SYS=${BB_SYS:-/system/bin/busybox}
BB_OWN=${BB_OWN:-$APP/bin/busybox}
if [ -z "$BB" ]; then
  if [ -x $BB_SYS ]; then BB=$BB_SYS
  else
    # zip에서 풀 때 실행 권한이 빠질 수 있다: 우리 파일이므로 한 번 준다(toolbox chmod)
    [ -f $BB_OWN ] && [ ! -x $BB_OWN ] && chmod 755 $BB_OWN 2>/dev/null
    BB=$BB_OWN
  fi
fi
# 내비의 busybox는 예전처럼 실행 파일인지만 본다(1.8.1에 true가 있는지 모른다: 확인된 차가 멈추지 않게).
# 함께 넣은 busybox는 실제로 실행해 본다(/data가 noexec이거나 CPU가 맞지 않으면 쓰지 않는다).
BB_OK=0
if [ "$BB" = "$BB_OWN" ]; then "$BB" true >/dev/null 2>&1 && BB_OK=1
else [ -x "$BB" ] && BB_OK=1; fi
# 프로세스 목록. 1.36.1은 기본 출력에 상태 칸이 없어 좀비([hostapd])를 " Z "로 거르지 못한다: 함께 넣은
# busybox일 때만 상태 칸을 달라고 한다(PID STAT COMMAND, 첫 칸 PID는 1.8.1과 같다). 1.8.1의 -o 지원은 확인 안 함.
# 경로 문자열로 판단한다: 같은 파일을 다른 경로로 BB에 넘기면 기본 ps가 되어 좀비를 거르지 못한다.
if [ "$BB" = "$BB_OWN" ]; then PS="$BB ps -o pid,stat,args"; else PS="$BB ps"; fi
SRC=${SRC:-/data/misc/wifi/softap.conf}
# 1.8.0 RS-2(#338 캐스퍼 EV AX1EV, tcc803x): 순정 카플레이 Wi-Fi 설정이 /data/misc/wifi에 없고 /securedata/wifi/softap.conf에만 있는 차가 있다
# (리포트: 앞의 것 없음, 뒤의 것 있음, 순정 hostapd 2.6 돎). 그때 "softap.conf를 읽지 못했습니다"로 멈춰 순정 카플레이 AP 판정까지 가지 못했다.
# 기본 위치에 파일이 없을 때만 그 위치를 쓴다(기본 위치가 있는 차는 그대로). 꼴이 같은지는 추정이다: 읽지 못하면 예전처럼 같은 문구로 멈춘다
SRC_ALT=${SRC_ALT:-/securedata/wifi/softap.conf}
# 리뷰 중간 3: 기본 위치에 파일이 "없을 때"만(비어 있는 순간은 순정이 다시 쓰는 중일 수 있어 대체하지 않음). 쓰면 서비스가 ap.log에 한 줄 남긴다
SRC_USED_ALT=0
SRC_DEF=$SRC
[ ! -e "$SRC" ] && [ -s "$SRC_ALT" ] && { SRC=$SRC_ALT; SRC_USED_ALT=1; }
# 짧게 유지: busybox ps가 명령줄을 약 80칸에서 잘라 "hostapd <경로>"가 약 50자를 넘으면 찾지 못한다
CONF=${CONF:-/data/misc/wifi/hostapd-kp.conf}
# 1.7.4(Q-1): Wi-Fi 장치 이름은 여기 한 곳에서 정한다(1.8.0 USB 동글 준비). 기본값 wlan0, 동작은 그대로다.
# 밖에서 바꾸는 길(설정 파일·prop)은 두지 않는다. 주석·로그·화면·리포트 문구 속 "wlan0" 글자는 그대로 둔다(차주·제보 양식이 그 글자를 봄)
WIF=${WIF:-wlan0}
W=${W:-/data/local/tmp/korea.projection}
AP_IP=192.168.43.1
# 1.7.0 무선 안드로이드 오토: 우리 hostapd가 도는 동안 시스템 속성 AAPROP=1을 건다(기본 켜짐, 2026-11-08 소유자 결정:
# 니로에서 첫·두 번째 연결과 카플레이 복귀를 확인함). HMG-API 모드(2.2.0, AaWifi)가 이 값이 1일 때만 GPM·PhoneProjection
# 안에서 "AP 켜짐, 모드 2"로 답한다. 속성은 재부팅하면 사라진다.
# 1.7.4(L-9, 소유자 결정): USB 파일(kp-aa-off·kp-aa-on)로 끄고 켜던 기능을 없앴다. 늘 켜짐이다.
# 1.7.4(B-7): 백업 폴더(BK) 기본값은 여기 한 곳에 둔다. 예전에는 AAOFF·APON_ORIG·KTB가 같은 경로 문자열을 따로 적고
# BK는 아래(1600행 근처)에서 정해, 한쪽만 바뀔 위험이 있었다. 맨 위 대입이 이 값을 쓰므로 그보다 앞에 둔다
BK=${BK:-/data/nemesis/backup/korea.projection}
# 1.7.3 이하가 남긴 끄기 표시. 서비스가 시작할 때 지운다(main). 그 밖에는 읽지 않는다
AAOFF=${AAOFF:-$BK/aa-off}
AAPROP=sys.kp.aa_ap
# busybox ps cuts command lines near 80 columns: match the start of dnsmasq's (netd starts it the
# same way, but the stock hotspot never runs on this car)
DNSMASQ='dnsmasq --keep-in-foreground --no-resolv --no-poll'
# 1.6.2: 순정 dnsmasq(netd)도 명령 앞부분이 같아서 위 패턴으로는 우리 것을 가릴 수 없다(K3 #15: 순정 AP의 dnsmasq를
# 우리 DHCP로 셈). 그래서 우리 dnsmasq는 띄울 때 "<pid> <부팅 id>"를 이 파일에 남기고, 그 pid로만 보고 멈춘다.
DNSPID=${DNSPID:-$W/dnsmasq.pid}
PROC=${PROC:-/proc}
# 순정 카플레이 AP를 기다리는 시간(초). 함께 넣은 busybox를 쓰는 내비(tcc803x)에서만 쓴다(아래 main).
STOCK_GRACE=${STOCK_GRACE:-90}
# 베타 3(B3-7): softap.conf 읽기 판정·실패 문구·크기와 수정 시각(내용 없음)
SOFTAP_FAIL_MSG="순정 카플레이 Wi-Fi 설정(softap.conf)을 읽지 못했습니다. 제보해 주세요."
SOFTAP_RETRY_MSG="Wi-Fi 설정을 다시 읽는 중입니다."
# 1.8.0 정식(A4·H-5, 소유자 문구 11-24): 업데이트로 무선 모드를 새 버전으로 바꾼 뒤의 재부팅 안내(진행 기록·알림·상태 화면 판정이 같은 문장).
# 이미 옛 무선 모드로 연결돼 있어도 재부팅해야 새 버전이 적용된다(제보 #533)
MODUPD_MSG="업데이트를 마치려면 3분 후 재부팅해 주세요."
CONF_FAST_S=${CONF_FAST_S:-180}
CONF_FAST_GAP=${CONF_FAST_GAP:-5}
conf_ok() { [ "${NS:-0}" -ge 4 ] && [ ${#S2} -ge 1 ] && [ ${#S4} -ge 8 ]; }
# 베타 3(B3-7 바로잡음, 제보 #499 아이오닉 6·#498): 서비스가 부팅 4초에 위치를 한 번만 골라, 그때 대체 위치(/securedata)를 고르지 못한 차는
# 기본 위치만 되풀이해 읽었다(status.sh는 나중에 대체 위치에서 정상으로 읽음). 읽을 때마다 위치 고르기부터 다시 한다:
# 기본 위치가 읽히면 기본, 아니면 대체 위치가 읽히면 대체. 둘 다 못 읽으면 처음 규칙(기본에 파일이 없고 대체가 있으면 대체)대로 두고 1.
# 상태 화면(status.sh)도 같은 함수를 써서 서비스와 다른 위치를 고르지 않는다. S1~S4·NS는 고른 위치의 값
# 리뷰 M1(베타 2 리뷰 "중간 3" 보호를 되살림): 고르는 규칙은 예전과 같다 — 기본 위치에 파일이 있으면 기본(비어 있거나 못 읽어도: 순정이 다시
# 쓰는 중일 수 있음), 기본 위치에 파일이 없을 때만 대체 위치. 바뀐 것은 "읽을 때마다 다시 고른다"는 것뿐이다(B3-7, 부팅 직후 /securedata를
# 아직 못 읽은 차 #499·#501). 고른 이유는 SRC_WHY(def | alt-nodef)로 기록한다
src_pick() {
  if [ -e "$SRC_DEF" ] || [ ! -s "$SRC_ALT" ]; then SRC=$SRC_DEF; SRC_USED_ALT=0; SRC_WHY=def
  else SRC=$SRC_ALT; SRC_USED_ALT=1; SRC_WHY=alt-nodef; fi
  parse_conf $SRC
  conf_ok
}
# 베타 3(B3-12, 메인 결정 11-23: 동작은 바꾸지 않고 근거만): 고른 softap.conf의 위치·형식 버전·문자열별 길이를 비공개 기록에
# ($BK/softap.diag, 한 줄, 내용 없음). 고른 비밀번호(S4)가 순정 ConnectivityPSK 길이(12, LENGTH_CONNECTIVITY_PSK)와 다르면 경고 한 줄.
# 아이폰은 Wi-Fi 서비스의 ConnectivityPSK를 받는다(stock-re 3.4). #509(/securedata 차): 파일 S4 32자 / 서비스 12자
SOFTAP_DIAGF=${SOFTAP_DIAGF:-$BK/softap.diag}
conf_diag() {
  _cdl=; _cdi=1
  while [ $_cdi -le ${NS:-0} ]; do eval "_cdl=\"\$_cdl,\${#S$_cdi}\""; _cdi=$((_cdi + 1)); done
  _cdw=def; [ "$SRC" = "$SRC_DEF" ] || _cdw=alt
  echo "$(date '+%m-%d_%H:%M' 2>/dev/null) src=$_cdw why=${SRC_WHY:--} ver=${SVER:--} n=${NS:-0} lens=${_cdl#,} psk=${#S4}" 2>/dev/null > $SOFTAP_DIAGF.tmp && $BB mv -f $SOFTAP_DIAGF.tmp $SOFTAP_DIAGF 2>/dev/null
  if conf_ok && [ ${#S4} != 12 ] && [ -z "$CONF_PSKWARN" ]; then
    CONF_PSKWARN=1
    log "카플레이 비밀번호 길이가 순정 기준(12)과 다름(길이 ${#S4}, $_cdw 위치, 문자열 ${NS}개) — 아이폰이 받는 값과 다를 수 있음(기록만)"
  fi
  return 0
}
# 기록용: 두 위치의 크기·수정 시각(내용 없음)
conf_meta() {
  # 리뷰 L1: toolbox ls는 칸이 달라 busybox ls를 쓴다(conf_sig와 같음)
  _cmd=$($BB ls -ln "$SRC_DEF" 2>/dev/null | $BB awk '{ print "크기 " $5 ", 수정 " $6 " " $7 " " $8 }')
  _cma=$($BB ls -ln "$SRC_ALT" 2>/dev/null | $BB awk '{ print "크기 " $5 ", 수정 " $6 " " $7 " " $8 }')
  echo "기본 위치 ${_cmd:-파일 없음}, 대체 위치 ${_cma:-파일 없음}"
}
# 이 패키지가 동작하는 차. 목록에 없는 차(해외 차)는 로그만 남기고 대기한다.
# - CARS_OK: 차에서 동작을 확인한 차 (니로 하이브리드)
# - CARS_TRY: 제보(Car Report, 순정 체크섬)로 지도를 만들어 패키지에 넣었고, 차에서는 아직 확인하지 않은 차
#   (쏘나타 하이브리드 DN8 HMG-API #91, 그랜저 하이브리드 IG #7, 벨로스터 N #8). 확인되면 CARS_OK로 옮긴다.
# - CARS_AUTO: 그 밖의 모든 한국 차(자동 시험, 1.5.2 소유자 결정). 패키지에 지도가 없으면 HMG-API가 그 차의
#   파일로 지도를 만들고(engine map-car --write) 그 차에서 확인(verify-map)한 뒤에만 무선 모드를 적용한다.
#   무선 모드(한국 차 빌드)도 Wi-Fi 칩이 있는 한국 차만 받는다. 결과는 제보 파일(3-log.txt)로 본다.
CARS_OK='DEPEHEV.KOR.*.260902'
CARS_TRY='DN822HEV.KOR.*.260902 IGPEHEV.KOR.*.260902 JSN.KOR.*.260902 IGPE.KOR.*.260902'
CARS_AUTO='*.KOR.*'
# 재리뷰 중간 3②: Wi-Fi 칩 실패의 근거(CLAUDE.md 2장 "근거 있을 때만")가 남아 있는가. 순정 Wi-Fi 기록(nowlan·nochip 기록, $BK 사본)에
# 커널 칩 실패 줄(si_attach failed, SDIO -84, failed to power up DHD)이 있거나 순정 module_version 기록이 3이면 0.
# 리뷰 L5·마지막 묶음: "-84"(EILSEQ)는 Wi-Fi와 상관없는 mmc(eMMC·SD) 줄에도, 신호 세기(rssi -84)에도 나온다.
# 오류 꼴(ERR=-84, error -84, err -84)이고 Wi-Fi 줄(dhd·bcmdhd·sdio·wlan·bcm)일 때만 근거로 본다.
# 펌웨어를 칩에 올리지 못함(dhd_bus_start: failed to download firmware)도 칩 실패 근거다.
chip_fail_evidence() {
  [ "$(cat $BK/wifi.modver 2>/dev/null)" = 3 ] && return 0
  $BB grep -q -E 'si_attach failed|failed to power up DHD|failed to download firmware' $NOWLAN_LOG $NOCHIP_LOG $BK/nochip-wifi.txt 2>/dev/null && return 0
  $BB cat $NOWLAN_LOG $NOCHIP_LOG $BK/nochip-wifi.txt 2>/dev/null | $BB grep -i -E '(err|error)[ =:]*-84' | $BB grep -q -i -E 'dhd|sdio|wlan|bcm'
}
# 1.7.3(D-6): 공개 README 지원 표에서 ✅(무선 카플레이·AA 연결이 확인된 차)인 차종. 상태 화면·리포트의 "확인된 차"와
# G-4("같은 차에서 된 분이 있습니다")·U-10(확인 안 된 차가 연결되면 제보 부탁)에만 쓴다. 새 ✅ 차종이 생기면 README와 함께 고친다.
# 동작을 가르는 CARS_OK·CARS_TRY는 바꾸지 않았다: CARS_OK에 넣으면 순정 카플레이 AP 확인·순정 핫스팟 비켜 주기를 건너뛰어
# NX4·SG2EV(순정 무선 카플레이 차) 등이 달라진다(s3-impl.md "결정 필요"). BDPE는 내비 버전이 260902가 아니다(NEMESIS os).
# 묶음 G 후속(2026-11-15): 소유자가 README에 ✅로 올린 9종(CKPE22·CN7N·DE22EV·HM21·KA4·MQ4·NEEV·SG2HEV·SP222)을 더했다.
# 버전은 차종 이슈(#228·#299·#309·#308·#302·#300·#301·#78·#305)의 차주 제보에서 연결된 판 260902를 읽어 확인했다.
# 1.8.0 P-10(2026-11-18): README ✅ 4종(DL3 #130·GL3 #68·IGPE21HEV #324·NQ5HEV #379)을 더했다(47종). 판 260902는 차주 리포트·이슈 글에서 읽음.
# 1.8.0 베타 1(11-18 저녁): README ✅ 2종(DN8HEV #404 쏘나타 DN8 하이브리드·OSHEV #399)을 더했다(49종). 판 260902는 이슈 글·리포트에서 읽음.
# 1.8.0 베타 3(11-24 소유자 결정): README ✅ 2종(NQ5 #484 스포티지 2022 가솔린·SP2PE #518 셀토스 2023 PE)을 더했다(55종). 판 260902는 이슈 글에서 읽음.
# 1.8.0 정식(11-24 메인): README ✅ LX2PE(#554 더 뉴 팰리세이드, 동글로 무선 AA)를 더했다(56종). 판 260902는 리포트에서 읽음.
# 1.8.0 정식(11-24 메인): README ✅ TAMPE(#306 레이 2023, 동글로 무선 카플레이)를 더했다(57종).
# 1.8.1(11-25 메인): README ✅ 4종(AEPEHEV #303·CN7HEVPE #520·CN7PE #519·HREV24 #230)을 더했다(61종). AEPEHEV는 내비 V038 260404에서 확인됨.
CARS_SEEN='IGPE.KOR.*.260902 IGPE21.KOR.*.260902 IGPEHEV.KOR.*.260902 DN822HEV.KOR.*.260902 JSN.KOR.*.260902 LX2.KOR.*.260902 CN7.KOR.*.260902 CN7HEV.KOR.*.260902 TMFL.KOR.*.260902 AX1.KOR.*.260902 DN8.KOR.*.260902 NX4HEV.KOR.*.260902 NX4.KOR.*.260902 DEPEHEV.KOR.*.260902 DEPEPHEV.KOR.*.260902 SG2EV.KOR.*.260902 DL3HEV.KOR.*.260902 DL3HEV22.KOR.*.260902 YGPE.KOR.*.260902 YGPEHEV.KOR.*.260902 MQ422HEV.KOR.*.260902 MQ422.KOR.*.260902 MQ4HEV.KOR.*.260902 BDPE.KOR.* GL3HEV.KOR.*.260902 OSEV.KOR.*.260902 CKPE.KOR.*.260902 SK3EV.KOR.*.260902 SP221.KOR.*.260902 IKFL.KOR.*.260902 DL322.KOR.*.260902 KA422.KOR.*.260902 CVEV.KOR.*.260902 TAM22.KOR.*.260604 CKPE22.KOR.*.260902 CN7N.KOR.*.260902 DE22EV.KOR.*.260902 HM21.KOR.*.260902 KA4.KOR.*.260902 MQ4.KOR.*.260902 NEEV.KOR.*.260902 SG2HEV.KOR.*.260902 SP222.KOR.*.260902 DL3.KOR.*.260902 GL3.KOR.*.260902 IGPE21HEV.KOR.*.260902 NQ5HEV.KOR.*.260902 DN8HEV.KOR.*.260902 OSHEV.KOR.*.260902 CN7HEV22.KOR.*.260902 HREV22.KOR.*.260902 DE_E_22.KOR.*.260902 TMHEV.KOR.*.260902 NQ5.KOR.*.260902 SP2PE.KOR.*.260902 LX2PE.KOR.*.260902 TAMPE.KOR.*.260902 AEPEHEV.KOR.*.260404 CN7HEVPE.KOR.*.260902 CN7PE.KOR.*.260902 HREV24.KOR.*.260902'
# 1.7.3(G-4): 차종 코드만 같고 내비 버전(펌웨어 끝 6자리 날짜)이 다를 때를 보려고, 버전을 빼고 차종 코드만 본다
# 1.7.4(B-5): 그 차종이 확인된 내비 버전(목록 끝 6자리)을 _CMD에 둔다. 레이 TAM22는 260604에서 확인돼 260902가 기준이 아니다.
# 버전 없이 적힌 차종(BDPE.KOR.*)은 빈 값. 하위 셸 없이 값만 넣는다
# 리뷰 반영: car_in처럼 목록을 나눌 때 '*'가 파일 이름으로 풀리지 않게 잠시 set -f 하고, 원래 상태로 되돌린다
car_model_seen() {
  _cm=${1%%.*}; _CMD=; _cmr=1
  case $- in *f*) _cmf=0 ;; *) _cmf=1; set -f ;; esac
  for _cs in $CARS_SEEN; do
    if [ "${_cs%%.*}" = "$_cm" ]; then
      _CMD=${_cs##*.}; case "$_CMD" in [0-9][0-9][0-9][0-9][0-9][0-9]) ;; *) _CMD= ;; esac
      _cmr=0; break
    fi
  done
  [ $_cmf = 1 ] && set +f
  return $_cmr
}
# 펌웨어 문자열 끝 6자리(내비 버전 날짜, 예 260902). 숫자 6자리가 아니면 빈 값
fw_date() { _fd6=${1##*.}; case "$_fd6" in [0-9][0-9][0-9][0-9][0-9][0-9]) echo "$_fd6" ;; esac; }
CARS="$CARS_OK $CARS_TRY $CARS_AUTO"
# $1(제품명)이 $2(공백으로 나눈 패턴 목록)의 하나와 맞는가.
# case 패턴에는 변수로 '|'를 넘길 수 없어 하나씩 본다. 목록을 나눌 때 '*'가 파일 이름으로 풀리지 않게
# 잠시 set -f 한다(이미 -f면 그대로 둔다).
car_in() {
  _cr=1; _ci=$IFS; IFS=' '
  case $- in *f*) _cf=0 ;; *) _cf=1; set -f ;; esac
  for _ck in $2; do case "$1" in $_ck) _cr=0; break ;; esac; done
  [ $_cf = 1 ] && set +f
  IFS=$_ci
  return $_cr
}
# 확인된 차가 아니면(시험 지원·자동 시험) HMG-API 무선 모드가 설치·켜짐이고 **적용까지 된** 뒤에만 핫스팟을 켠다
# (wlan0을 가져간다). 모드 없이는 무선 카플레이가 시작되지 않고 순정 Wi-Fi만 끊기기 때문이다(2026-11-06 니로에서 확인).
# 적용됐는지는 모드가 적용할 때 거는 속성 persist.sys.iap2.wifi=t로 본다(차주가 앱에서 적용한 경우도 잡힌다).
# 확인된 차는 예전처럼 바로 켠다. 모드 위치: /data/hmgapi/mods/<id>/mod.json, 꺼짐 표시 .disabled
# 1.7.3(K-7): 모드 조건은 setup_done 한 곳에 둔다
try_ready() {
  car_in "$1" "$CARS_OK" && return 0
  setup_done
}
WPDIR=${WPDIR:-/data/nemesis/apps/wireless.projection}

# 베타 1 리뷰 B: 부팅 직후 시계가 맞기 전에는 날짜가 "01-01 18:30:0x"처럼 찍혀 헷갈렸다(니로 차 로그). 연도가 이 패키지를
# 만든 해(KP_YEAR0)보다 이전이면 시각 대신 "부팅 직후"라고 쓴다. 하위 셸을 늘리지 않게 값은 _LT에 둔다(date 한 번)
KP_YEAR0=${KP_YEAR0:-2026}
# 재리뷰 L6: 시계가 맞기 전이면 "부팅 직후(+N초)"(N = 부팅 뒤 초, 줄 순서를 알 수 있게). 두 칸(빈칸 하나)이라 예전 "MM-DD HH:MM:SS"와
# 칸 수가 같다(리포트는 ap.log 줄의 칸 위치를 읽지 않지만 맞춰 둠)
log_ts() {
  _LT=$(date '+%Y %m-%d %H:%M:%S' 2>/dev/null); _ly=${_LT%% *}; _LT=${_LT#* }
  case "$_ly" in [0-9][0-9][0-9][0-9]) [ "$_ly" -lt $KP_YEAR0 ] && { kp_up; _LT="부팅 직후(+${_U:-?}초)"; } ;; esac
  return 0
}
# 부팅 뒤 초(정수)를 _U에. 하위 셸 없이 read로. 못 읽으면 빈 값
kp_up() { _U=; { read _U _ux < ${UPTIME:-/proc/uptime}; } 2>/dev/null; _U=${_U%%.*}; case "$_U" in ''|*[!0-9]*) _U= ;; esac; return 0; }
log() { log_ts; echo "$_LT $*"; }

# 헤드유닛 busybox(1.8.1)의 od는 -b만 안다: 바이트가 8진 3자리로 나온다. decode는 8진 바이트들 → 문자열
# 1.7.3(K-3): 바이트마다 하위 셸로 printf를 부르던 것을 printf 한 번으로. 형식 문자열은 "\NNN"(8진 이스케이프)만으로 만들어
# % 나 \ 같은 글자도 이스케이프로만 들어간다(형식 지시자로 읽히지 않음). 결과는 예전과 바이트까지 같다(stub-test 비교)
decode() {
  _f=""
  for _b in "$@"; do _f="$_f\\$_b"; done
  $BB printf "$_f\n"
}

# 8진 3자리 바이트 하나 → 10진(자리마다 계산: 앞의 0을 8진으로 잘못 읽지 않게)
# 1.7.3(K-3): 결과를 echo로 내지 않고 _d에 넣는다(바이트마다 $(…) 하위 셸이 생기지 않게)
o2d() {
  _r=${1#?}
  _d=$(( ${1%??}*64 + ${_r%?}*8 + ${_r#?} ))
}

# 이 내비의 softap.conf(형식 3)는 순정 안드로이드 WifiApConfigStore 꼴이 아니다: 자바 writeUTF 문자열(2바이트 길이 + 바이트)로
# S1 일반 핫스팟 SSID, S2 카플레이 SSID, S3, S4 카플레이 비밀번호가 들어 있다.
# 산술 전에 길이를 먼저 확인한다: 틀린 $(( ))는 스크립트 전체를 끝낸다.
# 1.7.4(B-6): 순정 일반 핫스팟 이름(S1)·비밀번호(S3)가 한글이면 예전에는 그 문자열을 건너뛰어 개수가 밀렸다(S2가 S1 자리로,
# NS=3이라 서비스가 "문자열 4개를 찾지 못함"으로 시작하지 않음, 1.7.2부터). 그래서 1번째·3번째 문자열에서만 올바른 UTF-8
# 여러 바이트 글자(앞 바이트 C2~F4 + 이어지는 바이트 80~BF)를 받는다. hostapd 설정에 들어가는 S2·S4는 예전처럼 32~126만 받는다
# (줄바꿈·제어 문자가 설정 파일에 들어가지 않게). 영문 이름만 있는 파일의 결과는 예전과 바이트까지 같다(stub-test 비교).
parse_conf() {
  NS=0
  [ -s "$1" ] || return 1
  # od -b 줄: 7자리 위치 다음에 3자리 바이트들. 바이트만 남긴다
  set -- $(for _t in $($BB od -b -v "$1"); do [ ${#_t} -eq 3 ] && echo $_t; done)
  N=$#
  [ $N -ge 4 ] || return 1
  i=0
  for _t in "$@"; do o2d $_t; eval "o$i=$_t; b$i=$_d"; i=$((i+1)); done
  # 베타 3(B3-12): 첫 4바이트 = 형식 버전(int, 니로 3). 기록용
  SVER=$(( b0 * 16777216 + b1 * 65536 + b2 * 256 + b3 ))
  i=0
  while [ $((i+2)) -lt $N ]; do
    eval "_L=\$(( b$i*256 + b$((i+1)) ))"
    if [ $_L -ge 1 ] && [ $_L -le 63 ] && [ $((i+2+_L)) -le $N ]; then
      _ok=1; j=$((i+2)); _e=$((i+2+_L))
      # 이번 문자열이 몇 번째가 되는가: 1·3번째(S1·S3)만 UTF-8 글자를 받는다
      case $NS in 0|2) _u8=1 ;; *) _u8=0 ;; esac
      while [ $j -lt $_e ]; do
        eval "_v=\$b$j"
        if [ $_v -ge 32 ] && [ $_v -le 126 ]; then j=$((j+1)); continue; fi
        if [ $_u8 = 1 ] && [ $_v -ge 194 ] && [ $_v -le 244 ]; then
          # 이어지는 바이트 수: C2~DF 1개, E0~EF 2개, F0~F4 3개. 모두 80~BF이고 문자열 안에 있어야 한다
          if [ $_v -le 223 ]; then _n=1; elif [ $_v -le 239 ]; then _n=2; else _n=3; fi
          [ $((j+_n)) -lt $_e ] || { _ok=0; break; }
          _k=1
          while [ $_k -le $_n ]; do
            eval "_w=\$b$((j+_k))"
            if [ $_w -lt 128 ] || [ $_w -gt 191 ]; then _ok=0; break; fi
            _k=$((_k+1))
          done
          [ $_ok = 1 ] || break
          j=$((j+1+_n)); continue
        fi
        _ok=0; break
      done
      if [ $_ok -eq 1 ]; then
        B=""; j=$((i+2))
        while [ $j -lt $((i+2+_L)) ]; do eval "B=\"\$B \$o$j\""; j=$((j+1)); done
        NS=$((NS+1))
        eval "S$NS=\$(decode \$B)"
        i=$((i+2+_L)); continue
      fi
    fi
    i=$((i+1))
  done
}

# 1.5.6: 5GHz 149번으로 띄운다. 순정 핫스팟 기본값(softap.conf)도 5GHz 149번이다.
# 폭은 순정 netd의 149번 설정과 같은 40MHz(HT40+). 20MHz로는 재부팅 뒤 아이폰이 스스로 붙지 않았다(2026-11-07 니로).
# 니로에서 이 설정으로 AP가 뜨고 아이폰 카플레이가 연결됨을 확인했다(2026-11-07 5GHz 시험 USB, 국가 설정 없이).
# 순정처럼 2.4GHz로 되돌아가는 경로는 두지 않는다(소유자 결정). 대신 Wi-Fi 연결·끊김을 ap.log에 남긴다(wifi_events).
# 베타 2 DG-5(동글 7차 결과, 11-20 메인): 동글 wlan0에서는 이 설정(5GHz 149·HT40+)으로 hostapd가 매번 4초 안에 꺼졌다.
# 그래서 동글 길(드라이버를 올림·올라옴: wait·up·ok)일 때만 채널·대역·폭·나라를 아래 DG_HA_* 값으로 바꿔 쓴다.
# 지금 값은 내장과 같다(2h 차 결과로 정함). DG_HA_HTCAP이 비면 ht_capab 줄을 쓰지 않고(20MHz), DG_HA_COUNTRY가 있으면
# country_code·ieee80211d 줄을 더한다. 내장 Wi-Fi 길의 설정은 예전과 한 글자도 같다.
DG_HA_CHANNEL=${DG_HA_CHANNEL:-149}
DG_HA_HWMODE=${DG_HA_HWMODE:-a}
DG_HA_HTCAP=${DG_HA_HTCAP-[HT40+][SHORT-GI-20][SHORT-GI-40]}
DG_HA_COUNTRY=${DG_HA_COUNTRY:-}
dg_ha_path() { [ "$DG_RUN" = 1 ] && case "$DG_ST" in wait|up|ok) true ;; *) false ;; esac; }
write_conf() {
  _hch=149; _hhm=a; _hht='[HT40+][SHORT-GI-20][SHORT-GI-40]'; _hcc=
  if dg_ha_path; then _hch=$DG_HA_CHANNEL; _hhm=$DG_HA_HWMODE; _hht=$DG_HA_HTCAP; _hcc=$DG_HA_COUNTRY; fi
  $BB cat > $CONF <<CONFEOF
interface=$WIF
driver=nl80211
ctrl_interface=/data/misc/wifi/hostapd
ssid=$S2
channel=$_hch
hw_mode=$_hhm
CONFEOF
  [ -n "$_hht" ] && echo "ht_capab=$_hht" >> $CONF
  [ -n "$_hcc" ] && { echo "country_code=$_hcc"; echo "ieee80211d=1"; } >> $CONF
  $BB cat >> $CONF <<CONFEOF
ieee80211n=1
max_num_sta=5
ignore_broadcast_ssid=0
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_passphrase=$S4
CONFEOF
  # hostapd는 wifi 사용자(1010)로 내려가 돈다: 순정 hostapd.conf처럼 그 사용자가 읽을 수 있게
  $BB chown 1000:1010 $CONF; $BB chmod 660 $CONF
}

# --- 1.8.0 정식 C4(소유자 승인 11-24): 대체 위치(/securedata) 차는 Wi-Fi 서비스 값을 먼저 쓴다 ---
# 근거(beta3-reports 2-4절): /securedata 두 차는 파일 비밀번호가 32자, 서비스(WifiManager.getWifiApConfiguration) 값이 10·12자였고
# 둘 다 휴대폰이 붙지 않았다. 아이폰은 서비스 값을 받는다(stock-re 3.4).
# 1.8.1 I-2(#615 CN7NPE: 기본 위치, 파일 비밀번호 32자·서비스 12자, 아이폰 접속 3번·키 교환 0번): 기본 위치 차(니로 등)도 묻는다.
# 서비스 값을 받았고 파일 값과 다르면 서비스 값을 쓰고, 같으면 예전처럼 def(파일, 기본 위치)다. 못 받으면 파일 값 그대로(file)이고 30초 점검에서 다시 묻는다.
# 리뷰 1 L3: 기본 위치 차는 시작 때 기다리지 않는다. 파일 값으로 바로 띄우고 첫 30초 점검에서 묻는다(같으면 그대로, 다르면 그때 다시 띄움).
# 흐름: 남은 파일 지움 → 앱 receiver(명시적 컴포넌트, 화면 없음)에 broadcast 한 번 → 최대 APCFG_WAIT초 동안 1초마다 apcfg.val 확인 →
# 같은 부팅 id만 → busybox awk로 16진을 되돌리며 0x20~0x7e, SSID 1~32자, 비밀번호 8~63자 확인 → 읽은 즉시 지움.
# 실패하면 파일 값을 그대로 쓴다(베타 3와 같은 동작). 값은 셸 변수로만 들고 eval하지 않는다.
# 로그·리포트·상태 파일($APSRC)에는 출처와 길이만 남긴다
APCFG=${KP_APCFG:-/data/data/korea.projection.app/files/apcfg.val}
APCFG_APPDIR=${KP_APCFG_APPDIR:-/data/data/korea.projection.app}
APCFG_RCV=${KP_APCFG_RCV:-korea.projection.app/.ApCfgReceiver}
# 앱(vc45)은 이 액션일 때만 응답한다. -f 32(FLAG_INCLUDE_STOPPED_PACKAGES)는 앱을 한 번도 열지 않은 부팅(4.4 차)을 위한 것
APCFG_ACT=korea.projection.app.action.APCFG
APCFG_WAIT=${APCFG_WAIT:-10}
APSRC=${APSRC:-$W/apsrc}
# 앱은 $APCFG.tmp에 쓴 뒤 이름을 바꾼다. 둘 다 값이 들어 있을 수 있어 함께 지운다
apcfg_rm() { [ -e $APCFG ] && rm -f $APCFG 2>/dev/null; [ -e $APCFG.tmp ] && rm -f $APCFG.tmp 2>/dev/null; return 0; }
# apcfg.val(boot=·ssid_hex=·psk_hex= 줄)을 읽는다. $1: c(판정만: ok·oldboot·noval·badchar·badlen), s(SSID), p(비밀번호).
# 정식 2차 리뷰 L2: 앱이 값을 못 읽으면 "boot=<id>"와 "err=noval"만 쓴다(같은 부팅이면 noval, 기다림 없이 바로 파일 값).
# 판정이 ok가 아니면 s·p는 아무것도 내지 않는다. 16진은 awk가 파일에서 직접 읽는다(명령줄·-v에 값을 넣지 않음)
apcfg_awk() {
  $BB awk -v want="$1" -v bid="$2" '
    function dec(h,   i, a, b, v, o) {
      if (length(h) % 2) { bad = 1; return "" }
      o = ""
      for (i = 1; i < length(h); i += 2) {
        a = index(X, substr(h, i, 1)) - 1; b = index(X, substr(h, i + 1, 1)) - 1
        if (a < 0 || b < 0) { bad = 1; return "" }
        v = a * 16 + b
        if (v < 32 || v > 126) { bad = 1; return "" }
        o = o sprintf("%c", v)
      }
      return o
    }
    BEGIN { X = "0123456789abcdef"; bad = 0 }
    { sub(/\r$/, ""); i = index($0, "="); if (i < 2) next; k = substr($0, 1, i - 1); v = substr($0, i + 1)
      if (k == "boot") bt = v; else if (k == "ssid_hex") sh = tolower(v); else if (k == "psk_hex") ph = tolower(v); else if (k == "err") er = v }
    END {
      if (bt == "" || bt != bid) r = "oldboot"
      else if (er != "") r = "noval"
      else {
        s = dec(sh); p = dec(ph)
        if (bad) r = "badchar"
        else if (length(s) < 1 || length(s) > 32 || length(p) < 8 || length(p) > 63) r = "badlen"
        else r = "ok"
      }
      if (want == "c") print r
      else if (r == "ok") { if (want == "s") print s; else if (want == "p") print p }
    }' $APCFG 2>/dev/null
}
# 앱에 서비스 값을 물어 받는다. 성공: 0, AC_S2·AC_S4. 실패: 1, AC_WHY(noapp·timeout·oldboot·noval·badchar·badlen)
# 끝나는 조건: 기다림은 APCFG_WAIT번(1초씩)까지, 남은 am은 그 뒤 멈춘다
apcfg_get() {
  AC_S2=; AC_S4=; AC_WHY=
  # 지난 요청의 늦은 응답을 새 값으로 읽지 않게 먼저 지운다
  apcfg_rm
  [ -d $APCFG_APPDIR ] || { AC_WHY=noapp; return 1; }
  _acb=${BID:-$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)}
  am broadcast -a $APCFG_ACT -n $APCFG_RCV -f 32 >/dev/null 2>&1 &
  _acp=$!; _acw=0
  while [ ! -s $APCFG ] && [ $_acw -lt $APCFG_WAIT ]; do sleep 1 & wait $!; _acw=$((_acw + 1)); done
  kill $_acp 2>/dev/null
  if [ ! -s $APCFG ]; then apcfg_rm; AC_WHY=timeout; return 1; fi
  # 부팅 id를 못 읽었으면(빈 값·none) 어떤 파일도 같은 부팅으로 보지 않는다
  case "$_acb" in ''|none) apcfg_rm; AC_WHY=oldboot; return 1 ;; esac
  AC_WHY=$(apcfg_awk c "$_acb")
  [ "$AC_WHY" = ok ] && { AC_S2=$(apcfg_awk s "$_acb"); AC_S4=$(apcfg_awk p "$_acb"); }
  apcfg_rm
  # awk가 중간에 실패한 경우를 위해 셸에서도 길이를 한 번 더 본다
  if [ "$AC_WHY" = ok ] && [ ${#AC_S2} -ge 1 ] && [ ${#AC_S2} -le 32 ] && [ ${#AC_S4} -ge 8 ] && [ ${#AC_S4} -le 63 ]; then AC_WHY=; return 0; fi
  case "$AC_WHY" in oldboot|noval|badchar|badlen) ;; *) AC_WHY=badlen ;; esac
  AC_S2=; AC_S4=; return 1
}
# write_conf 앞에서 부른다(main 시작, 30초 점검에서 파일 값이 실제로 바뀌었을 때). 파일에서 읽은 S2·S4는 FS2·FS4로 기억하고
# (30초 점검은 파일 값끼리 비교), 서비스 값을 받으면 S2·S4를 그 값으로 바꾼다(1.8.1 I-2: 기본 위치 차는 파일 값과 다를 때만, 같으면 def).
# 상태 파일 $APSRC 한 줄: "<부팅 id> <svc|file|def> <이유 또는 -> <SSID 길이> <비밀번호 길이> <파일 비밀번호 길이>"(값 없음)
# $1이 q면 묻기만 하고 기록(로그·$APSRC)은 부르는 쪽이 ap_src_note로 한다(30초 점검이 결과를 보고 정할 때)
ap_src_apply() {
  FS2=$S2; FS4=$S4; AC_WHY=
  # 리뷰 1 L3: 기본 위치 차(니로 등)는 서비스 시작 때 묻지 않는다(앱 응답을 기다리느라 핫스팟이 늦게 뜨지 않게). 파일 값으로 바로 띄우고
  # 첫 30초 점검(ap_src_retry)에서 한 번 묻는다. 값이 같으면 아무것도 바꾸지 않고, 다르면(#615 꼴) 그때 우리 hostapd만 다시 띄운다
  if [ "$SRC_USED_ALT" != 1 ] && [ "$1" != q ]; then
    AP_SRC=def; DEF_ASK=1
  elif apcfg_get; then
    ap_src_take
  else
    AP_SRC=file
  fi
  [ "$1" = q ] || ap_src_note
  return 0
}
# 1.8.1 I-2: 받은 서비스 값(AC_S2·AC_S4)을 쓸지 정한다. 대체 위치 차는 늘 서비스 값(1.8.0 C4 그대로), 기본 위치 차는 파일 값과 다를 때만.
# 같으면 AP_SRC=def(파일 값이 곧 서비스 값). AC_S2·AC_S4·AC_WHY는 지운다
ap_src_take() {
  if [ "$SRC_USED_ALT" = 1 ] || [ "$AC_S2" != "$S2" ] || [ "$AC_S4" != "$S4" ]; then
    S2=$AC_S2; S4=$AC_S4; AP_SRC=svc
  else
    AP_SRC=def
  fi
  AC_S2=; AC_S4=; AC_WHY=
  return 0
}
# 상태 파일 한 줄만(값 없음)
ap_src_file() {
  _asb=${BID:-$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)}
  echo "${_asb:-none} $AP_SRC ${AC_WHY:--} ${#S2} ${#S4} ${#FS4}" 2>/dev/null > $APSRC.tmp && $BB mv -f $APSRC.tmp $APSRC 2>/dev/null
  return 0
}
# 로그 한 줄(기본 위치 차는 로그 없음)과 상태 파일. $1: 로그 끝에 붙일 말
ap_src_note() {
  case "$AP_SRC" in
    svc) log "AP 값 출처: 서비스(SSID ${#S2}자·비밀번호 ${#S4}자)$1" ;;
    file) log "AP 값 출처: 파일($AC_WHY)$1" ;;
    # 1.8.1 I-2: 기본 위치 차는 다시 물어 받았을 때만 한 줄(시작 때 같은 값이면 예전처럼 로그 없음)
    def) [ -n "$1" ] && log "AP 값 출처: 파일(기본 위치, 서비스 값과 같음)$1" ;;
  esac
  ap_src_file
}
# 정식 2차 리뷰 M1: 서비스 시작 때 앱이 답하지 않아(timeout·noapp·oldboot·noval) 파일 값으로 띄운 차는 30초 점검에서
# AP_RETRY_MAX번까지 다시 묻는다(1.8.1 I-2: 기본 위치 차도). 받으면 그 값으로 hostapd를 다시 띄운다(기본 위치 차는 파일 값과 다를 때만).
# 카플레이가 연결되어 있거나 무선 AA가 연결되어 있으면(HA=ok, 지금 값으로 붙음) 미룬다.
# 글자·길이가 틀린 값(badchar·badlen)은 다시 물어도 같아 묻지 않는다. 한 번에 최대 APCFG_WAIT초 걸린다
AP_RETRY_MAX=${AP_RETRY_MAX:-3}
ap_src_retry() {
  if [ "$DEF_ASK" != 1 ]; then
    [ "$AP_SRC" = file ] || return 0
    case "$AC_WHY" in timeout|noapp|oldboot|noval) ;; *) return 0 ;; esac
  fi
  [ "${AP_RETRY:-0}" -lt $AP_RETRY_MAX ] || return 0
  [ "$(cp_count)" = 0 ] || return 0
  [ "$HA" = ok ] && return 0
  # 리뷰 1 L4: 우리 AP에 붙은 기기가 있으면(AA가 TCP 전이거나 방화벽에 막혀 HA가 ok가 아니어도) 지금 값으로 붙어 있으니 미룬다
  [ "${WSTA:-0}" -gt 0 ] && return 0
  if [ "$DEF_ASK" = 1 ]; then
    # 기본 위치 차의 첫 묻기(횟수는 세지 않음). 같으면 조용히 def, 다르면 아래와 같이 다시 띄움, 못 받으면 file로 두고 그 뒤로는 다시 묻기 규칙대로
    DEF_ASK=
    if ! apcfg_get; then AP_SRC=file; log "AP 값 서비스 묻기(기본 위치): 받지 못함($AC_WHY), 파일 값 그대로"; ap_src_file; return 0; fi
    if [ "$AC_S2" = "$S2" ] && [ "$AC_S4" = "$S4" ]; then ap_src_take; ap_src_file; return 0; fi
    ap_src_take
    ap_src_note " — 기본 위치 파일 값과 달라 핫스팟을 서비스 값으로 다시 시작"
    write_conf
    restart_hostapd
    return 0
  fi
  AP_RETRY=$((${AP_RETRY:-0} + 1))
  if ! apcfg_get; then
    log "AP 값 서비스 다시 묻기 ${AP_RETRY}/${AP_RETRY_MAX}번: 받지 못함($AC_WHY), 파일 값 그대로"
    ap_src_file; return 0
  fi
  if [ "$AC_S2" = "$S2" ] && [ "$AC_S4" = "$S4" ]; then
    ap_src_take; ap_src_note " — 다시 물어 받음, 파일 값과 같아 핫스팟은 그대로"; return 0
  fi
  ap_src_take
  ap_src_note " — 다시 물어 받음(${AP_RETRY}번째), 핫스팟을 새 값으로 다시 시작"
  write_conf
  restart_hostapd
  return 0
}

# --- 1.7.2(P-3): softap.conf가 바뀌면 hostapd를 새 값으로 다시 띄운다 ---
# 순정 "키 생성"(PhoneProjection 무선 설정 화면, WifiApConfigStore.renewPasskey)은 카플레이 SSID와 비밀번호를 둘 다 새로 만든다.
# 그 뒤 아이폰·안드로이드 폰은 새 값을 받는데 우리 hostapd는 옛 값을 써서 붙지 못한다. 그래서 30초 점검에서 파일 서명(md5,
# 못 구하면 크기·시각)을 보고, 카플레이 SSID·비밀번호가 실제로 바뀌었을 때만 다시 띄운다(다시 띄우면 약 20초 끊김).
# 카플레이가 연결되어 있으면(cp_count>0) 끊지 않고 미룬다: 상태 화면에 짧게 알리고, 연결이 끝난 뒤 첫 점검에서 다시 띄운다.
# 순정 AP 경로(stock_ap_mode)는 부르지 않는다. 로그에는 길이만 남긴다. 끝나는 조건: 30초 점검 안에서만 돈다(반복 작업 없음).
# 알려진 한계: 안드로이드 오토 연결은 세지 않는다(cp_count는 카플레이 포트만 본다).
conf_sig() {
  _cs=$($BB md5sum < "$1" 2>/dev/null) && [ -n "$_cs" ] && { echo "${_cs%% *}"; return 0; }
  $BB ls -ln "$1" 2>/dev/null | $BB awk '{ print $5, $6, $7, $8 }'
}
# 우리 hostapd만 멈추고(최대 약 5초 기다림) up이 새 설정으로 다시 띄우게 한다
restart_hostapd() {
  for p in $($PS | $BB grep -v grep | $BB grep "hostapd $CONF" | $BB awk '{print $1}'); do kill $p 2>/dev/null; done
  _rw=0
  while running "hostapd $CONF" && [ $_rw -lt 5 ]; do sleep 1; _rw=$((_rw+1)); done
  up
}
conf_tick() {
  # C4: 기다림이 끝난 뒤 늦게 온 앱 응답이 남아 있으면 지운다(파일이 있을 때만 rm)
  apcfg_rm
  _ns=$(conf_sig $SRC)
  [ -n "$_ns" ] && [ "$_ns" != "$CONF_SIG" ] || return 0
  # 리뷰 M-4: 이미 미뤄 둔 같은 변경이면 연결이 끝날 때까지 다시 읽지 않는다(parse_conf는 바이트마다 셸 반복을 돈다.
  # 1.7.3 K-3 전에는 바이트마다 프로세스도 띄웠다)
  [ "$HC" = wait ] && [ "$_ns" = "$CONF_WAIT_SIG" ] && [ "$(cp_count)" != 0 ] && return 0
  _o1=$S1; _o2=$S2; _o3=$S3; _o4=$S4; _on=$NS
  parse_conf $SRC
  # 리뷰 L-1: hostapd SSID는 32바이트, WPA 비밀번호는 63자까지다. 넘으면 띄울 수 없으므로 읽지 못한 것과 같이 다룬다
  if [ "${NS:-0}" -lt 4 ] || [ ${#S2} -lt 1 ] || [ ${#S2} -gt 32 ] || [ ${#S4} -lt 8 ] || [ ${#S4} -gt 63 ]; then
    # 쓰는 중이었거나 형식이 다르면 지금 설정을 그대로 둔다. 같은 서명은 다시 보지 않는다(다음에 바뀌면 다시 읽음)
    S1=$_o1; S2=$_o2; S3=$_o3; S4=$_o4; NS=$_on; CONF_SIG=$_ns
    log "softap.conf가 바뀌었지만 문자열 4개를 읽지 못함: 지금 핫스팟 설정을 그대로 둠"
    return 0
  fi
  # C4: 파일 값끼리 비교한다(FS2·FS4: 지난번 적용 때 파일에서 읽은 값). 대체 위치 차는 지금 쓰는 S2·S4가 서비스 값일 수 있어
  # 그대로 비교하면 파일 서명만 바뀌어도 파일 값으로 되돌아간다. FS2·FS4가 없으면(시작 전 시험) 예전처럼 지금 값과 비교
  if [ "$S2" = "${FS2-$_o2}" ] && [ "$S4" = "${FS4-$_o4}" ]; then
    S2=$_o2; S4=$_o4
    CONF_SIG=$_ns
    [ -n "$HC" ] && { HC=; HC_T=; hint_write; }
    return 0
  fi
  if [ "$(cp_count)" != 0 ]; then
    # 연결 중: 새 값은 기억만 하고 지금 설정은 그대로(다음 점검에서 다시 비교). 안내·로그는 한 번만
    S1=$_o1; S2=$_o2; S3=$_o3; S4=$_o4; NS=$_on; CONF_WAIT_SIG=$_ns
    if [ "$HC" != wait ]; then
      HC=wait; HC_T=$(date +%s); hint_write
      log "softap.conf의 카플레이 Wi-Fi 설정이 바뀜: 카플레이가 연결되어 있어 연결이 끝나면 핫스팟을 다시 시작함"
    fi
    return 0
  fi
  # C4: 파일 값이 실제로 바뀐 때만 여기 온다(서명만 바뀐 것·연결 중 미룸은 위에서 끝남). 대체 위치 차는 서비스 값을 다시 묻는다
  _ofs2=$FS2; _ofs4=$FS4; _oas=$AP_SRC
  ap_src_apply q
  # 정식 2차 리뷰 M2: 서비스 값으로 잘 되던 차가 이번에 묻지 못하면 파일 값(틀릴 수 있음)으로 다시 띄우지 않는다. 지금 값을 두고,
  # CONF_SIG·파일 값 기억(FS2·FS4)을 되돌려 다음 점검에 다시 묻는다(AP_RETRY_MAX번까지, 그 뒤에는 지금 값 그대로 두고 묻기를 멈춤)
  if [ "$_oas" = svc ] && [ "$AP_SRC" = file ]; then
    CF_RETRY=$((${CF_RETRY:-0} + 1))
    S1=$_o1; S2=$_o2; S3=$_o3; S4=$_o4; NS=$_on; AP_SRC=svc
    if [ $CF_RETRY -lt $AP_RETRY_MAX ]; then
      FS2=$_ofs2; FS4=$_ofs4
      log "softap.conf가 바뀌었지만 서비스 값을 묻지 못함($AC_WHY, ${CF_RETRY}/${AP_RETRY_MAX}번): 지금 핫스팟 그대로, 다음 점검에 다시 물음"
    else
      CONF_SIG=$_ns; CF_RETRY=0
      log "softap.conf가 바뀌었지만 서비스 값을 ${AP_RETRY_MAX}번 묻지 못함($AC_WHY): 지금 핫스팟(서비스 값) 그대로 둠"
    fi
    return 0
  fi
  CF_RETRY=0; CONF_SIG=$_ns
  ap_src_note
  if [ "$S2" = "$_o2" ] && [ "$S4" = "$_o4" ]; then
    log "softap.conf의 카플레이 Wi-Fi 설정이 바뀌었지만 쓸 값은 그대로: 핫스팟을 다시 시작하지 않음"
    [ -n "$HC" ] && { HC=; HC_T=; hint_write; }
    return 0
  fi
  log "softap.conf의 카플레이 Wi-Fi 설정이 바뀜(SSID 길이 ${#_o2}→${#S2}, 비밀번호 길이 ${#_o4}→${#S4}): 핫스팟을 새 설정으로 다시 시작"
  write_conf
  restart_hostapd
  [ -n "$HC" ] && { HC=; HC_T=; hint_write; }
  return 0
}
# 1.7.2(P-8): softap.conf에서 카플레이 SSID 뒤의 정수(키 관리 값으로 보임, 니로 4=WPA2_PSK)만 숫자로 낸다. 문자열은 내지 않는다.
# 형식 3: int 버전, UTF S1, UTF S2, int(이 값), … (drafts/stock-re/carplay-connection.md 3.2). 못 읽으면 빈 값.
conf_auth() {
  [ -s "$1" ] || return 0
  set -- $(for _t in $($BB od -b -v "$1"); do [ ${#_t} -eq 3 ] && echo $_t; done)
  _cn=$#; _ci=0
  for _t in "$@"; do o2d $_t; eval "_cb$_ci=$_d"; _ci=$((_ci+1)); [ $_ci -ge 200 ] && break; done
  _ci=4
  for _k in 1 2; do
    [ $((_ci+1)) -lt $_cn ] || return 0
    eval "_L=\$(( _cb$_ci*256 + _cb$((_ci+1)) ))"
    [ $_L -le 63 ] || return 0
    _ci=$((_ci+2+_L))
  done
  [ $((_ci+3)) -lt $_cn ] && [ $((_ci+3)) -lt 200 ] || return 0
  eval "_h=\$_cb$_ci"
  [ $_h -le 127 ] || return 0
  eval "echo \$(( _cb$_ci*16777216 + _cb$((_ci+1))*65536 + _cb$((_ci+2))*256 + _cb$((_ci+3)) ))"
}

# 정식 2차 리뷰 H1: hostapd는 명령 이름 자리에서만 찾는다(앞이 줄 처음·빈칸·"/", 뒤가 빈칸·줄 끝).
# 디버그 로그 파이프 "logcat -v time -s hostapd:V …"·F5의 "logcat -d -s hostapd:V"처럼 인자에 "hostapd:"가 든 프로세스를
# hostapd로 보지 않게(그러면 ap_yield가 "다른 hostapd"로 우리 AP를 끄고, softap 다시 읽기 길이 대기에서 못 나왔다)
HAPD_RE='(^|[ /])hostapd( |$)'
# a live process by name; a zombie ([hostapd], state Z) doesn't count. "hostapd" 하나만 물으면 명령 이름 자리만 본다(H1)
running() {
  if [ "$1" = hostapd ]; then $PS | $BB grep -v grep | $BB grep -v " Z " | $BB grep -q -E "$HAPD_RE"
  else $PS | $BB grep -v grep | $BB grep -v " Z " | $BB grep -q "$1"; fi
}
# 우리 것이 아닌 hostapd(순정 핫스팟)가 살아 있는가: 우리 것은 설정 파일 경로($CONF)로 가린다
stock_ap_on() { $PS | $BB grep -v grep | $BB grep -v " Z " | $BB grep -v "$CONF" | $BB grep -q -E "$HAPD_RE"; }

# --- 1.6.2: 순정 hostapd가 띄운 Wi-Fi가 카플레이용인가 ---
# softap.conf에는 SSID가 둘 있다: S1 일반 핫스팟, S2 카플레이용(ConnectivitySSID). 순정 hostapd 설정의 ssid=가
# S2와 같으면 순정이 카플레이 AP를 직접 띄운 것이다(K3 BDPE: 모드 적용·재부팅 뒤, #15). S1과 같으면 일반 핫스팟
# (벨로스터 N 등, 지금처럼 비켜 준다). 값은 비교만 하고 어디에도 남기지 않는다.
# 설정 파일 경로는 ps가 아니라 /proc/<pid>/cmdline에서 읽는다(netd의 "hostapd -e <entropy> <conf>"는 ps가 80칸에서 자른다).
# 순정 것으로 보는 hostapd는 부모가 netd인 것뿐이다: 우리 USB 스크립트(cp-ap.sh·cp-drive.sh, hostapd-cp.conf)나
# 다른 패키지가 같은 카플레이 SSID로 띄운 hostapd를 순정으로 보지 않게(리뷰 H2).
# $1(pid)의 부모가 netd인가. /proc/<pid>/stat의 4번째 칸이 부모 pid다(이름 칸에 공백이 없는 프로그램만 본다).
by_netd() {
  [ -r $PROC/$1/stat ] || return 1
  read _n1 _n2 _n3 _pp _nr < $PROC/$1/stat
  case "$_pp" in ''|*[!0-9]*) return 1 ;; esac
  [ -r $PROC/$_pp/stat ] || return 1
  read _n1 _n2 _nr < $PROC/$_pp/stat
  [ "$_n2" = "(netd)" ]
}
# 우리 것이 아닌 hostapd의 pid들
other_hostapd_pids() { $PS | $BB grep -v grep | $BB grep -v " Z " | $BB grep -v "$CONF" | $BB grep -E "$HAPD_RE" | $BB awk '{print $1}'; }
# 1.7.3(리뷰 H-2): 우리 것도 순정(netd가 띄움)도 아닌 hostapd가 실제로 돌고 있는가(USB 동글 패키지 등, G-3).
# 부모를 읽지 못하면(stat 없음) 순정일 수 있으므로 세지 않는다(그때는 "다른 Wi-Fi 패키지"로 판정하지 않음)
foreign_hostapd() {
  for _fh in $(other_hostapd_pids); do
    [ -r $PROC/$_fh/stat ] || continue
    # 재리뷰 L-6: 부모의 stat까지 읽을 수 있을 때만 판단한다(부모를 못 읽으면 순정일 수 있어 세지 않음)
    read _f1 _f2 _f3 _fpp _fr < $PROC/$_fh/stat
    case "$_fpp" in ''|*[!0-9]*) continue ;; esac
    [ -r $PROC/$_fpp/stat ] || continue
    by_netd $_fh && continue
    return 0
  done
  return 1
}
# 순정(netd가 띄운) hostapd의 설정 파일(마지막 .conf 인자). 못 찾으면 1.
stock_conf() {
  for _hp in $(other_hostapd_pids); do
    [ -r $PROC/$_hp/cmdline ] && by_netd $_hp || continue
    _sc=
    for _a in $($BB tr '\0' ' ' < $PROC/$_hp/cmdline 2>/dev/null); do case "$_a" in *.conf) _sc=$_a ;; esac; done
    case "$_sc" in *hostapd-cp.conf) continue ;; esac
    [ -n "$_sc" ] && [ -r "$_sc" ] && { echo "$_sc"; return 0; }
  done
  return 1
}
# 출력: none(우리 것이 아닌 hostapd 없음) | carplay | hotspot | other | unknown(netd가 띄운 것이 아님, 설정을 못 읽음,
# ssid 줄이 없거나 여럿, ssid2= 16진 형식, softap.conf를 못 읽음, 두 SSID가 같음). parse_conf가 먼저 돌아 S1·S2·NS가 있어야 한다.
stock_ssid() {
  stock_ap_on || { echo none; return 0; }
  _sf=$(stock_conf) || { echo unknown; return 0; }
  _ss=; _sn=0
  while IFS= read -r _l || [ -n "$_l" ]; do
    case "$_l" in ssid=*) _ss=${_l#ssid=}; _sn=$((_sn+1)) ;; esac
  done < "$_sf"
  # 정식 2차 리뷰 L1: 순정 hostapd는 파일 값으로 띄우므로 파일에서 읽은 카플레이 SSID(FS2)와 견준다(대체 위치 차의 S2는 서비스 값일 수 있음)
  _fs2=${FS2-$S2}
  if [ $_sn -ne 1 ] || [ -z "$_ss" ] || [ "${NS:-0}" -lt 4 ] || [ ${#_fs2} -lt 1 ] || [ "$S1" = "$_fs2" ]; then echo unknown
  elif [ "$_ss" = "$_fs2" ]; then echo carplay
  elif [ "$_ss" = "$S1" ]; then echo hotspot
  else echo other; fi
  return 0
}
# 우리 dnsmasq가 살아 있는가: DNSPID의 pid가 이번 부팅의 것이고 이름이 dnsmasq일 때만(/data/local/tmp는 재부팅 뒤에도
# 남아 예전 pid가 순정 dnsmasq를 가리킬 수 있다)
our_dhcp_on() {
  [ -f $DNSPID ] || return 1
  # 묶음 H 재리뷰(낮음 2): 읽기 전에 비워 지난 값으로 판단하지 않고, 그 사이 파일이 사라져도 오류 줄이 새지 않게
  _dp=; _db=; { read _dp _db < $DNSPID; } 2>/dev/null
  case "$_dp" in ''|*[!0-9]*) return 1 ;; esac
  [ "$_db" = "${BID:-$(cat $BOOT_ID 2>/dev/null)}" ] && [ -r $PROC/$_dp/stat ] || return 1
  _dc=; _ds=; { read _dx _dc _ds _dr < $PROC/$_dp/stat; } 2>/dev/null
  # 묶음 H 최종(리뷰 낮음 2): 끝났지만 아직 거두지 않은 좀비(상태 Z)는 살아 있다고 보지 않는다(그러면 다시 띄우지 않아 DHCP가 빔)
  [ "$_dc" = "(dnsmasq)" ] && [ "$_ds" != Z ]
}

# 1.7.0: Wi-Fi 장치(wlan0)가 없어 hostapd가 바로 꺼지는 차(그랜저 IG #52·#53, 칩은 있음: 드라이버가 올라오지 않음).
# 이번 부팅에 처음 볼 때만 한 번 남기고, 그때의 순정 Wi-Fi 기록(WifiHW·WifiStateMachine 등 logcat, 드라이버 상태)을
# $NOWLAN_LOG에 남긴다(리포트 3-log.txt에 들어감, 가림). 그 뒤로는 34초마다 "hostapd 시작·꺼짐"을 다시 쓰지 않는다.
# 상태 파일 nowlan=yes로 상태 화면이 "Wi-Fi 드라이버가 올라오지 않음"을 보인다. 끝나는 조건: wlan0가 생기면 지움.
NOWLAN=${NOWLAN:-$W/nowlan}
NOWLAN_LOG=${NOWLAN_LOG:-$W/nowlan-wifi.txt}
NOCHIP_LOG=${NOCHIP_LOG:-$W/nochip-wifi.txt}
WLTAGS=' [VDIWEF]/(WifiHW|WifiStateMachine|WifiController|WifiService|WifiNative[^ (]*|SoftapController|wpa_supplicant|NetworkManagementService|CommandListener|bcmdhd|dhd) *\('
nowlan_now() { [ -s $NOWLAN ] && [ "$(cat $NOWLAN 2>/dev/null)" = "${BID:-$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)}" ]; }
# 1.7.3(리뷰 M-3): wlan0이 안 생긴 부팅 수($BK/nowlan.boots "<횟수> <boot_id>", 부팅마다 한 번 늘림, wlan0이 생기면 지움).
# 모드가 설치된 뒤 매 부팅 wlan0이 안 올라오는 차(그랜저 IG #55 꼴)를 3번째 부팅부터 "칩 실패"로 판정한다(status.sh kp_verdict)
nowlan_boot_count() {
  _nc=; _nb2=; [ -f $BK/nowlan.boots ] && read _nc _nb2 < $BK/nowlan.boots
  case "$_nc" in ''|*[!0-9]*) _nc=0 ;; esac
  _nb3=$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)
  [ -n "$_nb3" ] && [ "$_nb2" != "$_nb3" ] && [ -d $BK ] && echo "$((_nc + 1)) $_nb3" > $BK/nowlan.boots
  return 0
}
wlan_fail() {
  nowlan_now && return 0
  # DG-12·DG-3: 동글 사용이 켜진 부팅에 wlan0이 없는 것은 동글 쪽 문제다. 내장 칩 실패로 세지 않는다(nowlan.boots·근거 기록 안 함)
  # 5차 결과 반영: 이 부팅에 우리가 순정 드라이버를 내렸으면(막힘·끄기 뒤 포함) wlan0 없음은 칩 실패가 아니다
  if dg_dongle_on || dg_rm_now; then
    [ "$(cat $W/dg.nowlan 2>/dev/null)" = "${BID:-x}" ] || { log "동글 사용: wlan0이 아직 없음(동글·드라이버 확인, 내장 칩 실패로 세지 않음)"; echo "${BID:-x}" 2>/dev/null > $W/dg.nowlan; }
    return 0
  fi
  cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null > $NOWLAN
  nowlan_boot_count
  log "Wi-Fi 장치(wlan0)가 없음: Wi-Fi 드라이버가 올라오지 않아 핫스팟을 켜지 못함(Wi-Fi 설정 $(settings get global wifi_on 2>/dev/null), 드라이버 상태 $(getprop wlan.driver.status 2>/dev/null)). 계속 다시 시도함"
  wifi_record "wlan0 없음" $NOWLAN_LOG
  return 0
}
# 1.7.1: 순정 Wi-Fi 기록(설정·드라이버 상태, WifiHW 등 logcat 200줄, 커널 Wi-Fi 줄 60줄, 모두 KPMASK)을 파일 $2에 남긴다.
# wlan0 없음(wlan_fail)과 칩 깨우기 실패(wake_wifi)가 쓴다. 칩 깨우기 실패 때는 WifiHW의 insmod 시간과
# module_version으로 "부품 없음"(#50: insmod 8초, 버전 3)과 "드라이버가 내려감"을 리포트만 보고 나눌 수 있다.
wifi_record() {
  {
    echo "# $1 기록 $(date '+%m-%d %H:%M:%S') (부팅 뒤 $($BB awk '{ print int($1) }' /proc/uptime 2>/dev/null)초)"
    echo "wifi_on=$(settings get global wifi_on 2>/dev/null) wlan.driver.status=$(getprop wlan.driver.status 2>/dev/null) init.svc.wpa_supplicant=$(getprop init.svc.wpa_supplicant 2>/dev/null)"
    echo "wpa_supplicant.conf: $($BB ls -ln /data/misc/wifi/wpa_supplicant.conf 2>/dev/null | $BB awk '{ print $1, $3 ":" $4 }')"
    echo "net: $($BB ls /sys/class/net 2>/dev/null | $BB awk '{ printf "%s ", $0 }')"
    # 1.7.2(P-12): 순정 판정 기준 한 줄. 순정 WifiService.checkAndStartWifi는 module_version이 3이면 Wi-Fi 하드웨어가 없다고 본다
    # (#50 부품 없음 3, #48·니로 부품 있음 1). 숫자만 꺼낸다. 리포트(status.sh)가 이 줄을 "판정 근거"로 옮긴다.
    # 1.8.0 RS-14(#405): 판정(wifi_modver)은 이번 부팅 logcat에 값이 없으면 지난 기록($BK/wifi.modver)을 쓴다. 근거 줄도 같은 값을
    # 앞에 두고(판정과 어긋나지 않게), 두 출처를 괄호에 함께 적는다. 판정·동작은 바꾸지 않는다(이 줄은 리포트만 읽음)
    _mvl=$(logcat -d -v time 2>/dev/null | $BB grep 'wifi_get_module_version:' | $BB awk '{ v = $NF } END { gsub(/[^0-9]/, "", v); print v }')
    _mvf=$($BB awk '{ gsub(/[^0-9]/, ""); print; exit }' $BK/wifi.modver 2>/dev/null)
    _wrmv=${_mvl:-$_mvf}
    echo "판정 근거: 순정 module_version=${_wrmv:-없음} (이번 부팅 logcat ${_mvl:-없음}, 지난 기록 ${_mvf:-없음}; 3이면 순정 Wi-Fi 서비스도 Wi-Fi 하드웨어가 없다고 봄, 1이면 부품 있음)"
    echo "## logcat (순정 Wi-Fi, 마지막 200줄)"
    if echo x | $BB awk "$KPMASK" >/dev/null 2>&1; then
      logcat -d -v time 2>/dev/null | $BB grep -E "$WLTAGS" | $BB awk -v n=200 'BEGIN { n = n + 0 } { a[NR % n] = $0 } END { s = NR > n ? NR - n + 1 : 1; for (i = s; i <= NR; i++) print a[i % n] }' | $BB awk "$KPMASK"
    fi
    echo "## 커널 (Wi-Fi 드라이버, 마지막 60줄)"
    dmesg 2>/dev/null | $BB grep -i -E "dhd|bcmdhd|wlan|sdio|mmc" | $BB awk -v n=60 'BEGIN { n = n + 0 } { a[NR % n] = $0 } END { s = NR > n ? NR - n + 1 : 1; for (i = s; i <= NR; i++) print a[i % n] }' \
      | $BB awk "$KPMASK"
  } 2>/dev/null > $2
  return 0
}
# PF-1: 우리 dnsmasq의 표준입력으로 줄 FIFO. 삭제할 때는 preun이 $W째 지운다($W는 업데이트 때도 지워진다).
# 묶음 H(리뷰 낮음 2): 띄울 때마다 지우고 새로 만든다. $W는 /data/local/tmp 아래라 남이 미리 넣은 FIFO·링크를 쓰지 않게,
# 이 서비스(root, umask 077)가 만든 0600 FIFO만 쓴다. 만들기가 실패하면(그 사이 누가 같은 이름을 만든 경우 포함) 있는 것을 쓰지 않는다.
# up()은 우리 dnsmasq가 살아 있으면 이 함수를 부르지 않으므로, 살아 있는 우리 dnsmasq가 쥔 FIFO를 지우지 않는다. 만들었으면 0
DNSIN=${DNSIN:-$W/dnsmasq.in}
# 묶음 H 최종(리뷰 중간 2): 내비 busybox에 mkfifo·mknod가 없으면 함께 넣은 busybox(BB_OWN)로도 해 본다. 그 파일이 실행되는지는
# BB=BB_OWN일 때만 확인되므로 실패는 조용히 넘기고, 끝내 못 만들면 예전 방식이다
dns_stdin() {
  rm -f $DNSIN 2>/dev/null
  $BB mkfifo $DNSIN 2>/dev/null || $BB mknod $DNSIN p 2>/dev/null \
    || { [ "$BB" != "$BB_OWN" ] && { $BB_OWN mkfifo $DNSIN || $BB_OWN mknod $DNSIN p; } 2>/dev/null; } || return 1
  [ -p $DNSIN ]
}
# PF-1 리뷰·묶음 H 재리뷰(중간 1): pid 파일의 pid가 이번 부팅의 것이고 부모가 이 서비스 셸이면 **이름과 상관없이** 끝내고 거둔다
# (wait: 끝난 것을 확인하고 좀비도 남기지 않음). 막 띄워 아직 dnsmasq로 바뀌기 전의 하위 셸이 "떠 있지 않음"으로 보인 사이
# dnsmasq가 되면, 그대로 두고 새로 띄울 때 dnsmasq가 둘이 되고 하나는 pid 파일에 없어 stop_ours·삭제로도 멈추지 않는다.
# 부모가 이 셸이 아니거나(다시 쓰인 pid, 서비스가 다시 시작함) 다른 부팅의 pid는 건드리지 않는다(순정 dnsmasq를 죽이지 않음).
# 리눅스에서 FIFO를 읽기·쓰기로 여는 것은 막히지 않으므로 "열기에서 멈춤"을 잡는 함수가 아니다. 끝냈으면 0
dns_stuck() {
  [ -f $DNSPID ] || return 1
  _kp=; _kb=; { read _kp _kb < $DNSPID; } 2>/dev/null
  case "$_kp" in ''|*[!0-9]*) return 1 ;; esac
  [ "$_kb" = "${BID:-$(cat $BOOT_ID 2>/dev/null)}" ] && [ -r $PROC/$_kp/stat ] || return 1
  _kpp=; { read _k1 _kc _k3 _kpp _kr < $PROC/$_kp/stat; } 2>/dev/null
  [ "$_kpp" = "$$" ] || return 1
  kill $_kp 2>/dev/null
  # 묶음 J 리뷰(낮음): 끝났는지(/proc에서 사라짐 또는 좀비 Z) 1초 간격으로 세 번까지만 본다. 끝났으면 wait로 거두고(좀비를 남기지 않음),
  # TERM을 무시해 끝나지 않으면 기다리지 않고 넘어간다(서비스의 30초 반복이 멈추지 않게)
  _kw=0
  while :; do
    _ks=; [ -r $PROC/$_kp/stat ] && { read _k1 _kc _ks _kr < $PROC/$_kp/stat; } 2>/dev/null
    if [ -z "$_ks" ] || [ "$_ks" = Z ]; then wait $_kp 2>/dev/null; break; fi
    # 묶음 J 리뷰(낮음 6): 세 번 본 뒤에도 끝나지 않았으면 kill -9를 한 번 보내고 넘어간다(대상 조건은 위와 같음: 이번 부팅·부모가 $$)
    [ $_kw -lt 3 ] || { kill -9 $_kp 2>/dev/null; break; }
    _kw=$((_kw+1)); sleep 1
  done
  return 0
}
# 묶음 H 최종(리뷰 중간 3): 이 내비의 셸이 읽기·쓰기 열기(<>)를 받는가. 받지 못하는 셸에서 이 문법이 파일 본문에 그대로 있으면
# 함수 정의에서 구문 오류가 나 이 파일을 읽는 서비스·preun·status가 모두 선다. 그래서 문법은 eval 작은따옴표 문자열 안에만 두고,
# 하위 셸에서 한 번 해 본다(이번 실행에 한 번, 결과는 DNS_RW 1·0). 받으면 0
dns_rw_ok() { ( eval 'true <> /dev/null' ) 2>/dev/null; }
# 묶음 H 최종(리뷰 낮음 4): FIFO로 막 띄운 dnsmasq가 1초 뒤에 떠 있지 않은가(떠 있지 않으면 0). 시험이 바꿔 친다
dns_fifo_died() { sleep 1; ! our_dhcp_on; }
# 우리 dnsmasq를 띄우고 pid 파일을 쓴다. $1: fifo(표준입력 FIFO) 또는 old(예전 방식). DNS_FIFO에 1·0을 남긴다.
# FIFO 쪽은 eval 문자열 안에서 변수가 펼쳐지게 한다(값이 명령 글자로 섞이지 않음). 둘 다 $!가 dnsmasq 자신이다(파이프·하위 셸 없음)
dns_launch() {
  if [ "$1" = fifo ]; then
    DNS_FIFO=1; DNS_FIFO_AT=${TICK_N:-0}
    eval 'dnsmasq --keep-in-foreground --no-resolv --no-poll --dhcp-authoritative --pid-file --interface="$WIF" --bind-interfaces --dhcp-range=192.168.43.10,192.168.43.50,255.255.255.0,1h --dhcp-option=3 --dhcp-option=6 >/dev/null 2>&1 <> "$DNSIN" &'
  else
    DNS_FIFO=0
    dnsmasq --keep-in-foreground --no-resolv --no-poll --dhcp-authoritative --pid-file \
      --interface=$WIF --bind-interfaces \
      --dhcp-range=192.168.43.10,192.168.43.50,255.255.255.0,1h --dhcp-option=3 --dhcp-option=6 >/dev/null 2>&1 &
  fi
  echo "$! ${BID:-$(cat $BOOT_ID 2>/dev/null)}" > $DNSPID
  kp_up; DNS_UP_AT=$_U
}
# 베타 3(B3-11, 다른 사람 제안 아이디어를 우리 코드로): dnsmasq 출력은 /dev/null이라 왜 꺼졌는지 남지 않았다. 이 셸의 자식이면 wait로
# 종료 코드를 거둔다(자식이 아니거나 못 거두면 "모름"). 살아 있으면 아무것도 하지 않는다. 같은 실행에 5번까지만 남긴다
dns_exit_note() {
  _dep=; _deb=; [ -f $DNSPID ] && read _dep _deb < $DNSPID 2>/dev/null
  case "$_dep" in ''|*[!0-9]*) return 0 ;; esac
  [ "$_deb" = "${BID:-$(cat $BOOT_ID 2>/dev/null)}" ] || return 0
  [ -d $PROC/$_dep ] && return 0
  # 정말 끝난 프로세스일 때만 거둔다(살아 있으면 wait가 멈춤). 셸 함수로 바뀐 kill·wait(시험)를 건너뛰려고 command로 부른다
  command kill -0 $_dep 2>/dev/null && return 0
  command wait $_dep 2>/dev/null; _der=$?
  case "$_der" in 127) _der=모름 ;; esac
  kp_up; _dea=?; [ -n "$_U" ] && [ -n "$DNS_UP_AT" ] && _dea=$((_U - DNS_UP_AT))
  DNS_EXITN=$((${DNS_EXITN:-0} + 1))
  [ $DNS_EXITN -le 5 ] && log "dnsmasq가 꺼짐: 종료 코드 $_der, 띄운 뒤 ${_dea}초(이번 실행 ${DNS_EXITN}번째)"
  return 0
}
# FIFO로 띄운 것이 떠 있지 않아 예전 방식으로 내림(이유는 이어진 실패 3번까지, log_cap)
dns_fallback() {
  DNSIN_OFF=1
  log_cap DNS_FB "dnsmasq를 FIFO 표준입력으로 띄웠지만 떠 있지 않음: 예전 방식으로 띄움(CPU를 더 씀)" "dnsmasq를 FIFO로 띄우지 못해 예전 방식으로 내림"
}
# 1.7.3(K-4): **이어진 실패**로 되풀이되는 줄은 3번까지만 남기고, 4번째에 "더 남기지 않음" 한 줄을 남긴다.
# 횟수는 성공하면(hostapd가 살아 있음, wpa_supplicant가 없음) 부르는 쪽이 0으로 되돌린다(리뷰 M-1: 정상 다시 시작은 늘 남김).
# 기록만 줄이고 다시 시도하는 동작은 그대로다. $1 횟수 변수, $2 줄, $3 그만 쓸 때 앞말
log_cap() {
  eval "_lc=\$((\${$1:-0}+1)); $1=\$_lc"
  if [ $_lc -le 3 ]; then log "$2"
  elif [ $_lc = 4 ]; then log "$3: 이번 실행에서는 이 기록을 더 남기지 않음"; fi
}
up() {
  # 동글 판정(DG-3): 지원 동글이 아니면 이 부팅은 동글 wlan0에 우리 AP를 띄우지 않는다
  [ "$DG_ST" = notours ] && return 0
  # 리뷰 낮음 5: 순정 드라이버를 내린 부팅에 동글 길이 막혔으면(막힘·내리다 멈춤) 30초마다 다시 띄우지 않는다(재부팅 안내만)
  case "$DG_ST" in blocked|rmstuck) dg_rm_now && return 0 ;; esac
  # 시험판 5: 동글이 wlan0을 잡은 채 이번 부팅 동글 AP를 그만둔 상태(noap)·동글 드라이버를 못 내린 상태(nodevstuck)는 띄우지 않는다
  case "$DG_ST" in noap|nodevstuck|nobind|reupmax|bcmlate) return 0 ;; esac
  # 시험판 6(F1): 동글 길에서 wlan0이 아직 없으면(꽂기 전·뽑힌 사이) hostapd·dnsmasq를 띄우지 않는다. 띄워도 장치가 없어 바로 끝나고,
  # 그때마다 남긴 "AP 시작" 표시가 다음 부팅의 hang 판정에서 위험 단계로 잡혔다(다섯 번째 A). wlan0이 생기면 다음 점검(또는 깨우기)이 띄운다
  if dg_using && [ ! -d $WLAN ]; then return 0; fi
  # 시험판 6(F3): 동글이 다시 잡혀(순정 resetUSB·바꿔 꽂기) wlan0이 새로 생겼는데 우리 hostapd가 옛 장치를 잡고 있으면 다시 띄운다
  dg_using && { dg_reup_check; [ "$DG_ST" = reupmax ] && return 0; }
  # 배포판(DG-3, 소유자 결정): 지원 동글로 확인되기 전에는(바꿔 꽂은 동글 포함) 동글 wlan0에 우리 AP를 띄우지 않는다
  dg_using && ! dg_oui_gate && return 0
  $BB ifconfig $WIF $AP_IP netmask 255.255.255.0 up 2>/dev/null
  if ! running "hostapd $CONF"; then
    # 베타 3(B3-3 b_reup): 이 부팅에 우리 hostapd가 한 번 뜬 뒤 다시 띄우는 것만 센다(설정 바뀜·동글 다시 잡힘·죽음 모두 여기로 옴)
    _hpa=; [ -f $W/hapd.any ] && read _hpa < $W/hapd.any 2>/dev/null
    [ -n "$_hpa" ] && [ "$_hpa" = "$(dg_kv_bid)" ] && dbg_cnt reup $DBG_REUP_N b_reup
    # 베타 2 DG-5: 동글 길(dg_using)이면 hostapd 출력에서 실패 분류 낱말만 남긴다($W/ha.why, SSID·MAC 등 원문은 남기지 않음).
    # 내장 Wi-Fi 길은 예전 그대로
    if dg_using; then
      rm -f $W/ha.why
      # 시험판 4: 동글 wlan0에 AP를 띄우기 전 표시(sync, 단계 기록 중일 때만)
      # 시험판 6(리뷰 높음 1 뒤): 위험한 AP 시작이면 시도 기록을 열고(다음 부팅 hang 판정) 시작 시각($W/hapd.st)을 남긴다(60초 뒤
      # dg_reup_close가 닫음). 위험한 시작 = 처음 길(up)이거나, 이 부팅에 동글이 다시 잡힌 뒤 아직 AP가 한 번도 뜨지 않음.
      # 이미 버틴 장치에서의 되풀이 다시 시작(꺼졌다 다시 켬·설정 바뀜)은 열지 않는다(재리뷰 중간 R1: 기록이 끝없이 열려 있지 않게)
      if dg_ap_risky; then
        dg_try_open
        dg_up_s; echo "$_dgu ${BID:-none}" 2>/dev/null > $W/hapd.st
      fi
      dg_stage ap; dg_step hapd-start; echo "${BID:-none}" 2>/dev/null > $W/hapd.try
      # 정식 2차 리뷰 L4: 이번 시작 시각(logcat -v time과 같은 "MM-DD HH:MM:SS" 꼴). 실패 이유는 이 뒤 줄에서만 고른다
      HAPD_T0=$(date '+%m-%d %H:%M:%S' 2>/dev/null)
      { hostapd $CONF 2>&1 | $BB awk "$DG_HAWHY_AWK" 2>/dev/null > $W/ha.why; } &
    else
      hostapd $CONF >/dev/null 2>&1 &
    fi
    sleep 4
    $BB ifconfig $WIF $AP_IP netmask 255.255.255.0 up 2>/dev/null
    # wlan0가 없다고 이미 남긴 부팅에는 34초마다 같은 줄을 쓰지 않는다.
    # 1.7.3(K-4, 리뷰 M-1): 시작 줄은 정상 시작이면 늘 남기고, 4초 안에 꺼진 시작(이어진 실패)만 3번까지 남긴다
    if ! running "hostapd $CONF"; then
      nowlan_now || log_cap HA_STARTS "hostapd 시작" "hostapd를 자꾸 다시 켬"
      if [ ! -d $WLAN ]; then
        wlan_fail
      else
        # 1.5.6: 5GHz를 받지 않는 차라면 hostapd가 바로 끝난다. 2.4GHz로 되돌리지는 않고(소유자 결정) 기록만 남긴다.
        # 리뷰 L-5: 남기지 않을 줄(4번째부터)을 위해 awk를 띄우지 않는다
        _hch=; [ ${HA_DIES:-0} -lt 3 ] && _hch=$($BB awk -F= '$1 == "channel" { print $2 }' $CONF 2>/dev/null)
        log_cap HA_DIES "hostapd가 4초 안에 꺼짐(5GHz ${_hch}번을 못 띄웠을 수 있음)" "hostapd가 자꾸 4초 안에 꺼짐"
        # 베타 2 DG-5: 동글 wlan0에서 hostapd가 이어서 꺼지면 세고, DG_NOAP_MAX번이면 막는다(다음 부팅부터 동글을 쓰지 않음)
        dg_using && { dg_step hapd-die; dg_ap_died; }
      fi
    else
      nowlan_now || log "hostapd 시작"
      HA_STARTS=0; HA_DIES=0; DG_NOAP=0
      dg_kv_bid 2>/dev/null > $W/hapd.any
      # 베타 2 뽑기 기록: 동글 길이면 우리 hostapd를 띄운 uptime(뽑힌 때 "hostapd 시작 뒤 초")
      [ "$DG_RUN" = 1 ] && { dg_up_s; echo "$_dgu ${BID:-none}" 2>/dev/null > $W/hapd.up; dg_using && { dg_step hapd-up; dg_tl ap $_dgu; dg_fast_ok_mark; dg_gbus_save; dg_ifx_save; rm -f $W/dg.plugagain; dg_status_push; }; }
      # 시험판 5: 동글을 켠 차가 이번 부팅만 내장 AP를 띄웠으면, 뜬 뒤 한 번만(뒤에서) 순정 저장값을 다시 0으로(다음 시동은 bcmdhd 없이)
      if [ "$DG_RUN" = 1 ] && ! dg_using && dg_wifi_want; then
        _dgz=; [ -f $W/dgwz ] && read _dgz < $W/dgwz 2>/dev/null
        [ "$_dgz" = "${BID:-none}" ] || { echo "${BID:-none}" 2>/dev/null > $W/dgwz; ( dg_wifi_sync ) </dev/null 2>/dev/null & }
      fi
      [ -f $NOWLAN ] && { rm -f $NOWLAN; log "Wi-Fi 장치(wlan0)가 생겨 hostapd가 켜짐"; }
      # 재리뷰 중간 3①: 우리 hostapd가 켜지면 wlan0이 안 생긴 부팅 수를 지운다($BK는 업데이트에도 남고 $W의 NOWLAN은 지워지므로 따로)
      rm -f $BK/nowlan.boots
    fi
  fi
  if our_dhcp_on; then
    # 묶음 H 최종(리뷰 중간 1): FIFO로 띄운 것이 점검에서 살아 있는 것을 한 번이라도 보면, 이 차에서는 FIFO가 된다(DNS_FIFO_OK).
    # 그 뒤의 죽음은 FIFO 탓으로 보지 않고 다시 FIFO로 띄운다. 그동안 쌓인 "이어진 실패" 횟수도 비운다
    # 묶음 H 재리뷰(중간 2): 띄운 회차(DNS_FIFO_AT)와 같은 회차에서 본 것은 치지 않는다(conf_tick → restart_hostapd → up 직후의
    # main up()이 1초 산 것을 성공으로 치지 않게). 다음 30초 회차(TICK_N, 메인 반복이 올림)에서 살아 있어야 OK
    [ "$DNS_FIFO" = 1 ] && [ "${TICK_N:-0}" != "$DNS_FIFO_AT" ] && { DNS_FIFO_OK=1; DNS_FB=0; }
  else
    # netd와 같은 꼴: 값 없는 --pid-file(이 내비에는 /var/run이 없다)
    # PF-1(니로 2026-11-15, dnsmasq가 CPU 26.2%): 순정 dnsmasq(Android 판)는 표준입력에서 명령을 읽는다. 뒤에서 그냥 띄우면
    # 표준입력이 /dev/null이라 읽을 때마다 끝이 바로 돌아와 쉬지 않고 돈다(추정). FIFO를 읽기·쓰기로 열어 준다: 쓰는 쪽도
    # dnsmasq가 쥐어 끝이 오지 않고, 아무도 쓰지 않아 읽을 것도 없다(netd의 파이프와 같은 상태). 프로세스를 더 띄우지 않는다.
    # 지키는 성질: 어떤 실패에서도 hostapd만 있고 DHCP가 없는 상태를 남기지 않는다. 예전 방식(표준입력 리다이렉션 없음)은
    # 동작은 하고 CPU만 더 쓴다. 예전 방식으로 띄우는 경우:
    # ① 셸이 읽기·쓰기 열기를 받지 않음(dns_rw_ok, 이번 실행 내내, 로그 한 번) ② FIFO를 만들지 못함(로그 한 번)
    # ③ FIFO가 된다고 아직 모르는데(DNS_FIFO_OK 없음) FIFO로 띄운 것이 떠 있지 않음: 띄운 직후 1초 확인 또는 다음 점검
    #    (FIFO를 열지 못함, FIFO에서만 바로 끝남, 그 밖의 이유를 가리지 않음). 이번 실행에서는 DNSIN_OFF=1로 예전 방식.
    # 예전 방식으로 내린 뒤 예전 방식도 떠 있지 않으면 원인이 FIFO가 아니었으므로 DNSIN_OFF를 비우고 다시 FIFO를 시도한다
    # (FIFO→예전→FIFO…가 되풀이되어도 점검마다 dnsmasq는 늘 띄운다, 로그는 log_cap 3번 한도). 일부러 끈 것(stop_ours)은 DNS_FIFO가 비어 여기에 걸리지 않는다
    # 직전에 띄운 pid가 살아 있는데 dnsmasq가 아니면(아직 dnsmasq로 바뀌기 전의 하위 셸 등) 먼저 끝낸다: 둘이 뜨지 않게
    # 베타 3(B3-11): 우리가 띄운 dnsmasq가 꺼졌으면 종료 코드와 띄운 뒤 시간을 한 줄(같은 실행 5번까지)
    [ -n "$DNS_FIFO" ] && dns_exit_note
    [ -n "$DNS_FIFO" ] && dns_stuck
    if [ "$DNS_FIFO" = 1 ]; then
      [ "$DNS_FIFO_OK" = 1 ] || dns_fallback
    elif [ "$DNS_FIFO" = 0 ] && [ "$DNSIN_OFF" = 1 ]; then
      DNSIN_OFF=
    fi
    if [ -z "$DNS_RW" ]; then
      if dns_rw_ok; then DNS_RW=1
      else DNS_RW=0; log "이 내비의 셸이 FIFO 표준입력 열기를 받지 않음: dnsmasq를 예전 방식으로 띄움(CPU를 더 씀)"; fi
    fi
    if [ "$DNS_RW" = 1 ] && [ -z "$DNSIN_OFF" ] && dns_stdin; then
      dns_launch fifo
      # 낮음 4: FIFO가 된다고 아직 모르면 1초 뒤 한 번 보고, 떠 있지 않으면 같은 점검에서 바로 예전 방식으로(부팅 직후 DHCP 공백을 줄임).
      # 1초 뒤 살아 있는 것은 "된다"로 치지 않는다(다음 점검에서 살아 있어야 DNS_FIFO_OK)
      if [ "$DNS_FIFO_OK" != 1 ] && dns_fifo_died; then
        dns_stuck
        dns_fallback
        dns_launch old
      fi
    else
      if [ "$DNS_RW" = 1 ] && [ -z "$DNSIN_OFF" ] && [ -z "$DNSIN_TOLD" ]; then
        log "dnsmasq 표준입력용 FIFO를 만들지 못함: 예전 방식으로 띄움(CPU를 더 씀)"
        DNSIN_TOLD=1
      fi
      dns_launch old
    fi
    # 바로 꺼지는 dnsmasq(포트를 못 잡음 등)를 30초마다 다시 띄워도 기록은 이번 실행에 3번까지만(리뷰 L1)
    DN_STARTS=$((${DN_STARTS:-0}+1))
    if [ $DN_STARTS -le 3 ]; then log "dnsmasq 시작"
    elif [ $DN_STARTS = 4 ]; then log "dnsmasq가 자꾸 꺼짐: 이번 실행에서는 시작 기록을 더 남기지 않음"; fi
  fi
}

# 우리 hostapd(설정 파일 경로로 가림)와 우리 dnsmasq(DNSPID)만 멈춘다. 순정 dnsmasq는 건드리지 않는다(1.6.2).
# 예전 판(1.6.1까지)이 pid 없이 띄운 우리 dnsmasq는, pid 파일이 없고 다른 hostapd가 없고 순정 AP 경로가 아닐 때만
# 예전처럼 명령으로 찾는다. 그때도 부모가 netd인 dnsmasq(순정)는 멈추지 않는다(리뷰 M1).
stop_ours() {
  for p in $($PS | $BB grep -v grep | $BB grep "hostapd $CONF" | $BB awk '{print $1}'); do
    kill $p 2>/dev/null
  done
  # 묶음 H: 일부러 끄는 것이므로 다음 up()이 "FIFO로 띄웠는데 떠 있지 않음"으로 보지 않게 한다
  DNS_FIFO=
  # 묶음 H 재리뷰(중간 1): 우리 자식이면(이번 부팅, 부모가 이 셸) 이름이 아직 dnsmasq가 아니어도 끝내고 거둔다(dns_stuck).
  # 그 밖에 살아 있는 우리 dnsmasq(서비스가 다시 시작해 부모가 다름)는 예전처럼 pid로 끈다
  if dns_stuck; then :
  elif our_dhcp_on; then
    kill $_dp 2>/dev/null
  elif [ ! -f $DNSPID ] && [ "${STOCK_MODE:-0}" != 1 ] && ! stock_ap_on; then
    for p in $($PS | $BB grep -v grep | $BB grep "$DNSMASQ" | $BB awk '{print $1}'); do
      by_netd $p || kill $p 2>/dev/null
    done
  fi
  rm -f $DNSPID
  return 0
}
stop_ap() {
  aa_sig 0 stop
  fw_aa_down
  stop_ours
  killlog
}
# --- 1.8.1 I-1(소유자 승인 11-25: "패키지는 iptables를 읽기만" 원칙을 좁혀 바꿈, 설계 drafts/1.8.1-work/design-i1-i3.md 1장) ---
# 순정 방화벽 차(INPUT 정책 DROP, #520 CN7HEVPE·#522 CEEV 등)는 우리 AP(192.168.43.x)로 오는 무선 AA(TCP 40515) 첫 SYN을 버린다.
# 무선 모드 2.4.9의 규칙은 HMG-API 엔진이 순정 AP 대역(192.168.0.0/24)에만 걸어 우리 대역에 맞지 않는다.
# 그래서 우리 AP가 떠 있고 AA 신호가 1인 동안만 우리 체인 하나(KP_AA_IN, ACCEPT 한 줄)를 두고 INPUT 맨 앞에서 그리로 보낸다.
# - 체인 안에는 -j ACCEPT 줄만 둔다: HMG-API 네트워크 관리자(state/net.sh)는 자기 점프 앞의 "막지 않는 줄"(ACCEPT만 든 체인 점프)을
#   그대로 두므로 다투지 않는다. HMGAPI_IN·순정 체인(WL_WLAN0_IN)은 건드리지 않는다.
# - 방화벽 없는 차(INPUT 정책 DROP이 아님)는 넣지 않는다(니로 등은 iptables 읽기 한 번만 는다). 순정 방화벽을 다시 읽는 중
#   (init.svc.iptrules running·restarting)이면 그 회차는 건너뛴다. IPv4만(ip6tables·카플레이 규칙은 그대로).
# - 있는지는 -S 출력을 필드로 본다(-d …/32, -m tcp, --syn → --tcp-flags … SYN 꼴). 점프는 자리 말고 있는지만 본다.
# - 빼기는 조건 없이, awk 없이 -D(5번까지)·-F·-X만 쓴다(busybox 없는 삭제 길에서도 부를 수 있게). 재부팅하면 규칙은 어차피 사라진다.
IPTABLES=${IPTABLES:-iptables}
FWAA_CH=KP_AA_IN
fw_aa_down() {
  _fwd=0
  while [ $_fwd -lt 5 ] && $IPTABLES -D INPUT -i $WIF -j $FWAA_CH 2>/dev/null; do _fwd=$((_fwd + 1)); done
  if $IPTABLES -F $FWAA_CH 2>/dev/null; then
    # 리뷰 1 L8: 다른 인터페이스 이름으로 남은 점프가 있으면 -X가 실패한다(빈 체인·점프만 남음, 패킷에는 영향 없음, 재부팅하면 사라짐)
    if $IPTABLES -X $FWAA_CH 2>/dev/null; then log "AA 방화벽 규칙 뺌(우리 체인)"
    else log "AA 방화벽 규칙을 비웠지만 체인을 지우지 못함(다른 점프가 남음, 재부팅하면 사라짐)"; fi
  elif [ $_fwd -gt 0 ]; then log "AA 방화벽 규칙 뺌(점프만 남아 있었음)"; fi
  FWAA_ON=
  return 0
}
# aa_sig 바로 뒤에 부른다. AA 신호가 켜진 때($AAWHY = on: 우리 hostapd 돎·wlan0에 우리 주소·순정 AP 기록 없음)만 넣거나 맞추고, 아니면 뺀다
fw_aa_sync() {
  [ "$(cat $AAWHY 2>/dev/null)" = on ] || { [ -n "$FWAA_ON" ] && fw_aa_down; return 0; }
  case "$(getprop init.svc.iptrules 2>/dev/null)" in running|restarting) return 0 ;; esac
  # d: INPUT 정책 DROP, c: 우리 체인 있음, j: INPUT에서 우리 체인으로 가는 점프 있음, r: 체인 안이 맞는 규칙 한 줄뿐
  _fws=$($IPTABLES -S 2>/dev/null | $BB awk -v ch=$FWAA_CH -v ifn=$WIF '
    $1 == "-P" && $2 == "INPUT" && $3 == "DROP" { d = 1 }
    $1 == "-N" && $2 == ch { c = 1 }
    $1 == "-A" && $2 == "INPUT" && $(NF - 1) == "-j" && $NF == ch && index($0, " -i " ifn " ") > 0 { j = 1 }
    $1 == "-A" && $2 == ch { n++
      if ($0 ~ / -s 192\.168\.43\.0\/24 / && $0 ~ / -d 192\.168\.43\.1(\/32)? / && $0 ~ / -p tcp / && $0 ~ / --dport 40515 / && $0 ~ / --tcp-flags [A-Z,]+ SYN / && $0 ~ / -j ACCEPT$/) r++ }
    END { print (d ? "d" : "-") (c ? "c" : "-") (j ? "j" : "-") ((n == 1 && r == 1) ? "r" : "-") }' 2>/dev/null)
  case "$_fws" in
    dcjr) FWAA_ON=1; return 0 ;;
    d???) ;;
    # 방화벽 없는 차: 넣지 않는다. 지난 실행이 남긴 것이 있으면 뺀다
    -c??|--j?) fw_aa_down; return 0 ;;
    *) return 0 ;;
  esac
  _fwf=0
  case "$_fws" in ?c??) ;; *) $IPTABLES -N $FWAA_CH 2>/dev/null || _fwf=1 ;; esac
  case "$_fws" in ???r) ;; *)
    $IPTABLES -F $FWAA_CH 2>/dev/null
    $IPTABLES -A $FWAA_CH -s 192.168.43.0/24 -d $AP_IP -p tcp --syn --dport 40515 -j ACCEPT 2>/dev/null || _fwf=1 ;;
  esac
  case "$_fws" in ??j?) ;; *) $IPTABLES -I INPUT 1 -i $WIF -j $FWAA_CH 2>/dev/null || _fwf=1 ;; esac
  if [ $_fwf = 1 ]; then log_cap FWAA_FAIL "AA 방화벽 규칙을 넣지 못함(다음 점검에 다시)" "AA 방화벽 규칙 넣기 실패가 이어짐"
  elif [ -z "$FWAA_SEEN" ]; then FWAA_SEEN=1; FWAA_ON=1; log "AA 방화벽 규칙 넣음(우리 AP 대역의 무선 AA 포트만, 순정 방화벽 차)"
  else FWAA_ON=1; log_cap FWAA_RE "AA 방화벽 규칙 다시 넣음(순정 방화벽이 다시 읽혀 지워졌을 수 있음)" "AA 방화벽 규칙을 자꾸 다시 넣음"; fi
  return 0
}
# AA 신호를 맞춘다. 인자가 있으면 그 값(0)으로, 없으면 우리 hostapd·wlan0 주소·순정 AP 기록으로 정한다.
# 바뀔 때만 setprop·로그. 값만 쓰고 SSID·비밀번호는 쓰지 않는다. 순정 AP 경로(tcc803x)는 이 함수를 부르지 않는다(순정이 이미 AP를 안다).
# 1.7.2(P-6): 예전의 "함께 넣은 busybox(BB_OWN)면 끔" 조건을 뺐다. 실제 뜻은 "busybox 없는 차 전부"라, 순정 AP를 쓰지 않는
# 그런 차에서 AA가 늘 막혔다. 원래 의도(tcc803x에서 순정이 AP를 켜고 끌 때 훅이 막지 않게)는 이렇게 지킨다:
# - 순정 카플레이 AP를 본 차($BK/stockap.seen)는 그대로 0(순정 AP 경로 차는 신호를 켜지 않음)
# - 다른 hostapd가 돌면 ap_yield가 0으로 내림(다음 30초 점검 전까지 1로 남는 틈은 있음, 보고서 참고)
# - 새 조건: wlan0에 우리 AP 주소가 있어야 1(GPM은 wlan0의 사설 IPv4를 못 찾으면 그 시도를 재시도 없이 끝낸다)
# 이유는 $W/aa.why에 두고(리포트가 읽음), 신호가 바뀔 때만 이유와 함께 로그 한 줄을 남긴다. $2: 0으로 둘 때의 이유.
AAWHY=${AAWHY:-$W/aa.why}
aa_why_text() {
  case "$1" in
    on) echo "켜짐" ;; stockap) echo "순정 카플레이 AP 기록(stockap.seen)" ;;
    nohostapd) echo "우리 hostapd 없음" ;; noaddr) echo "wlan0에 우리 AP 주소 없음" ;; yield) echo "다른 hostapd에 비켜 줌" ;;
    *) echo "핫스팟 멈춤" ;;
  esac
}
# wlan0에 우리 AP 주소($AP_IP)가 있는가(ifconfig의 inet addr)
wlan_has_ip() {
  [ "$($BB ifconfig $WIF 2>/dev/null | $BB awk '/inet addr:/ { a = $0; sub(/.*inet addr:/, "", a); sub(/ .*/, "", a); print a; exit }')" = "$AP_IP" ]
}
aa_sig() {
  _a=${1:-}; _why=${2:-stop}
  if [ -z "$_a" ]; then
    _a=0
    if [ -f $BK/stockap.seen ]; then _why=stockap
    elif ! running "hostapd $CONF"; then _why=nohostapd
    elif ! wlan_has_ip; then _why=noaddr
    else _a=1; _why=on; fi
  fi
  [ "$_why" = "$(cat $AAWHY 2>/dev/null)" ] || echo "$_why" 2>/dev/null > $AAWHY
  if [ "$_a" = "$(getprop $AAPROP 2>/dev/null)" ]; then
    # 리뷰 M-2: 신호가 이미 0이면(다른 곳에서 먼저 내림) 서비스에 남은 "준비됨" 안내도 지운다.
    if [ "$_a" = 0 ] && [ -n "$HA_READY$HA" ]; then AA_ON_TM=; HA_READY=; HA=; HA_T=; hint_write; fi
    return 0
  fi
  # 처음(속성 없음)에 0이면 조용히 둔다
  [ "$_a" = 0 ] && [ -z "$(getprop $AAPROP 2>/dev/null)" ] && return 0
  setprop $AAPROP $_a 2>/dev/null
  if [ $_a = 1 ]; then
    log "무선 안드로이드 오토(시험) 켜짐: 모드에 우리 AP를 알림"
    # P-4: 상태 화면 "준비됨" 시각과, logcat의 "AP 모드 모름"이 신호보다 먼저였는지 가르는 기준 시각
    AA_ON_TM=$(date '+%m-%d %H:%M:%S'); HA_READY=$(date +%s)
  else
    log "무선 안드로이드 오토(시험) 신호 끔: 이유 $(aa_why_text $_why)"
    AA_ON_TM=; HA_READY=; HA=; HA_T=
  fi
  hint_write
  return 0
}

# --- 1.7.2 상태 화면 안내(P-3·P-4·P-5) ---
# 서비스가 30초 점검에서 정한 짧은 안내를 상태 화면 앱(QR 화면)이 읽는 파일에 둔다(644, key=value, 비밀값 없음).
# 토스트는 쓰지 않는다(CLAUDE.md). 값은 코드와 시각(초)뿐이고 문구는 앱이 정한다.
#   boot: 이번 부팅 id(앱은 지난 부팅 것을 보이지 않음)
#   aa_ready: 무선 AA 신호가 켜진 시각 / aa: bt(폰 블루투스를 껐다 켜기)·cpwait(카플레이가 연결되어 AA는 기다림)·ok(AA 연결됨), aa_t
#   iph: wifi(아이폰이 Wi-Fi에 오지 않음), iph_t / conf: wait(softap.conf가 바뀌어 카플레이 연결이 끝나면 다시 시작), conf_t
# 쓰는 곳은 서비스(main)뿐이다(HINT_ON=1). Launch(status.sh)가 aa_sig 0을 불러도 이 파일을 비우지 않는다.
# 끝나는 조건: aa·iph는 HINT_MAX초(10분) 뒤 또는 해소 줄을 보면 지움(hint_tick), conf는 다시 시작하면 지움.
HINT=${HINT:-/data/local/tmp/korea-projection-hint.txt}
HINT_MAX=${HINT_MAX:-600}
hint_write() {
  [ "$HINT_ON" = 1 ] || return 0
  ( umask 022
    $BB printf 'boot=%s\naa_ready=%s\naa=%s\naa_t=%s\niph=%s\niph_t=%s\nconf=%s\nconf_t=%s\n' \
      "${BID:-$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)}" "$HA_READY" "$HA" "$HA_T" "$HI" "$HI_T" "$HC" "$HC_T" > $HINT.tmp \
      && $BB chmod 644 $HINT.tmp && $BB mv -f $HINT.tmp $HINT ) 2>/dev/null
  st_push
  return 0
}
# AA 안내 바꾸기: $1 코드(bt|cpwait|ok|빈 값), $2 ap.log에 남길 이유. 같은 값이면 아무것도 하지 않는다.
aa_hint() {
  # 재리뷰 M3: 연결됨(ok)을 새로 받으면 그 전의 "0대가 됨"은 지난 일이다. 확인 리뷰 M2: 단, 지금 붙은 기기가 있을 때만
  # (한 회차 안에 붙었다 끊긴 뒤 늦게 온 ok가 0대 기록을 지워 ok가 남는 것을 막음)
  [ "$1" = ok ] && [ "${WSTA:-0}" -gt 0 ] && WGONE=
  # 1.7.4(B-2): AP 올라옴(L)만으로 0대가 된 것이면, 지금 받은 연결됨은 그 뒤의 연결이다(AP가 있어야 붙는다)
  [ "$1" = ok ] && [ "$WGONE" = L ] && WGONE=
  [ "$1" = "$HA" ] && return 0
  HA=$1
  # HA_T는 안내 파일(aa_t, 앱이 시계로 비교)용, HA_U는 서비스 안 10분 지우기용(부팅 뒤 초, 확인 리뷰 L3)
  if [ -n "$1" ]; then HA_T=$(date +%s); kp_up; HA_U=$_U; else HA_T=; HA_U=; fi
  case "$1" in
    bt) log "안내(상태 화면): 안드로이드 폰의 블루투스를 껐다 켜 주세요 ($2)" ;;
    cpwait) log "안내(상태 화면): 카플레이가 연결되어 있어 안드로이드 오토는 기다림" ;;
    ok) log "안내(상태 화면): 무선 안드로이드 오토 연결됨" ;;
    *) log "안내(상태 화면): 안드로이드 오토 안내 지움 ($2)" ;;
  esac
  hint_write
}
# aa_events가 넘긴 판정(F 줄) 하나를 처리한다. iap·iapd(아이폰)는 신호와 상관없이, AA 안내는 신호가 1인 차만.
aa_flag() {
  case "$1" in
    # 리뷰 M-3: 유선(USB, 구성요소 1) 카플레이 중에도 블루투스 iAP2(구성요소 4)가 붙는다(wired3 로그).
    # 유선이 붙어 있는 동안에는 아이폰 Wi-Fi 안내를 내지 않는다.
    iap) [ "$IPH_USB" = 1 ] && return 0
      # 재리뷰 L4: 부팅 뒤 초 기준(못 읽으면 판정하지 않음)
      case "$2" in ''|*[!0-9]*) ;; *) kp_up; [ -n "$_U" ] && IPH_AT=$((_U - $2)) ;; esac; return 0 ;;
    iapd) IPH_AT=; return 0 ;;
    usbon) IPH_USB=1; IPH_AT=
      if [ -n "$HI" ]; then HI=; HI_T=; HI_U=; log "안내(상태 화면) 지움: 아이폰 유선 연결"; hint_write; fi
      return 0 ;;
    usboff) IPH_USB=; return 0 ;;
    # 1.8.1 S-3: 이번 점검에 화면 시간 초과가 있었음(perf_tick이 그 회차 줄에 붙이고 지움)
    scrto) PF_SCRTO=1; return 0 ;;
    # 베타 3(B3-3 b_audio): 10분 안 DBG_AU_N줄, 또는 한 줄의 N이 DBG_AU_1 이상
    glitch) case "$2" in ''|*[!0-9]*) return 0 ;; esac
      [ "$2" -ge $DBG_AU_1 ] && dbg_trig b b_audio
      dbg_cnt audio $DBG_AU_N b_audio; return 0 ;;
  esac
  [ "$(getprop $AAPROP 2>/dev/null)" = 1 ] || return 0
  case "$1" in
    unkpre) aa_hint bt "신호보다 먼저 AP 모드를 물음" ;;
    sppfail) aa_hint bt "헤드유닛 쪽 블루투스 다시 연결 거절" ;;
    giveup) aa_hint bt "폰 프로젝션이 다시 시도를 포기함" ;;
    cpwait) aa_hint cpwait ;;
    ok) aa_hint ok ;;
    clr) case "$HA" in bt|cpwait) aa_hint "" "AP 켜짐 확인" ;; esac ;;
    # 1.8.1 I-9: 휴대폰 Wi-Fi 접속(TCP 전)은 기다림 안내만 지운다(연결됨은 TCP 뒤 ok)
    wjoin) case "$HA" in bt|cpwait) aa_hint "" "휴대폰 Wi-Fi 접속(TCP 전)" ;; esac ;;
  esac
  return 0
}
# 30초마다: 오래된 안내를 지우고(10분), 아이폰 Wi-Fi 미접속을 판정한다(P-5, 우리 AP 경로에서만 부름).
# 아이폰 판정: iAP2(블루투스, 구성요소 4)가 붙은 뒤 IPH_WAIT초(60초) 동안 카플레이 연결이 없으면, 우리 AP에 붙은 기기가
# 없을 때 "Wi-Fi에 오지 않음"(wifi), 있을 때 "연결됐지만 카플레이가 시작되지 않음"(nocp)을 안내한다(베타 1 리뷰 A).
IPH_WAIT=${IPH_WAIT:-60}
hint_tick() {
  _hn=$(date +%s); _hc=$(cat $CPN 2>/dev/null); _hc=${_hc:-0}
  # 재리뷰 L4: 서비스 안의 기다림(아이폰 60초·안내 10분)은 부팅 뒤 초로 잰다(부팅 직후 시계를 맞출 때 흔들리지 않게).
  # 안내 파일에 쓰는 시각(aa_t·iph_t)은 앱이 시계로 비교하므로 그대로 date +%s다. 부팅 뒤 초를 못 읽으면 아이폰 판정은 쉰다
  kp_up; _hu=$_U
  # 재리뷰 M3: 무선 AA "연결됨"(ok)은 10분으로 지우지 않는다(AA를 계속 쓰는데 Launch하면 "연결된 폰 없음"이 되던 것).
  # ok는 우리 AP에 붙은 기기가 0대가 되거나(아래) AA 신호가 꺼지면(aa_sig) 지운다. 기다림 안내(bt·cpwait)만 10분으로 지운다
  if [ -n "$HA_T" ] && [ "$HA" != ok ]; then
    if [ -n "$_hu" ] && [ -n "$HA_U" ]; then [ $((_hu - HA_U)) -ge $HINT_MAX ] && aa_hint "" "10분 지남"
    elif [ $((_hn - HA_T)) -ge $HINT_MAX ]; then aa_hint "" "10분 지남"; fi
  fi
  # SPP 닫힘·rfcommDisconnect는 정상 연결 과정에서도 나와(drafts/stock-re/connection-timeline-aa.md +58.7) 끊김 근거로 쓰지 않는다
  # 커널 줄을 놓쳐 0으로 세는 경우에 지우지 않게, 끊김·AP 다시 올라옴으로 0대가 됐을 때(WGONE)만 지운다
  if [ "$HA" = ok ] && [ -n "$WGONE" ] && [ "${WSTA:-0}" = 0 ]; then aa_hint "" "우리 Wi-Fi에 붙은 기기가 0대가 됨(무선 AA 끊김으로 봄)"; fi
  WGONE=
  # 확인 리뷰 M2: ok인데 기기 0대가 두 회차(약 60초) 이어지면 지운다(끊김 줄을 놓쳤거나 늦은 ok가 남은 경우)
  if [ "$HA" = ok ] && [ "${WSTA:-0}" = 0 ]; then
    AA0N=$((${AA0N:-0} + 1))
    [ $AA0N -ge 2 ] && { AA0N=0; aa_hint "" "무선 AA 연결됨인데 우리 Wi-Fi 기기 0대가 두 회차 이어짐"; }
  else
    AA0N=0
  fi
  # 아이폰 안내: 카플레이가 연결되면 지우고, 10분 지나도 지운다. "Wi-Fi에 오지 않음"(wifi)은 기기가 Wi-Fi에 붙어도 지운다.
  # 재리뷰 M3: 무선 AA가 연결된 동안은 아이폰 안내를 두지 않는다(쓰는 AA를 끊으라고 하지 않게)
  if [ -n "$HI" ]; then
    if [ "$_hc" != 0 ] || [ "$HA" = ok ] || { [ "$HI" = wifi ] && [ -n "$_hu" ] && [ "${WCONN_AT:-0}" -ge "${HI_U:-0}" ]; }; then
      if [ "$_hc" != 0 ]; then log "안내(상태 화면) 지움: 카플레이 연결됨"
      elif [ "$HA" = ok ]; then log "안내(상태 화면) 지움: 무선 안드로이드 오토 연결됨"
      else log "안내(상태 화면) 지움: 아이폰이 Wi-Fi에 연결됨"; fi
      HI=; HI_T=; HI_U=; hint_write
    elif [ -n "$_hu" ] && [ $((_hu - ${HI_U:-0})) -ge $HINT_MAX ]; then
      HI=; HI_T=; HI_U=; hint_write
    fi
  fi
  # 베타 1 리뷰 A(니로 차 로그): 니로의 아이폰은 iAP2보다 먼저 Wi-Fi에 붙는다. iAP2 뒤 60초 동안 카플레이가 없으면 지금 우리 AP에
  # 붙은 기기 수(WSTA, 커널 연결·끊김 줄로 셈)로 가른다. 기기가 붙어 있으면 아이폰인지 가릴 수 없으므로 "폰이 Wi-Fi에 연결됐지만"이라고 쓴다.
  # 재리뷰 M3: 무선 AA가 연결된 동안(HA=ok)은 두 안내 모두 내지 않는다
  if [ -n "$IPH_AT" ]; then
    if [ "$_hc" != 0 ] || [ "$HA" = ok ] || [ -z "$_hu" ]; then
      IPH_AT=
    elif [ $((_hu - IPH_AT)) -ge $IPH_WAIT ]; then
      IPH_AT=
      if running "hostapd $CONF"; then
        if [ "${WSTA:-0}" -gt 0 ]; then
          HI=nocp; HI_T=$_hn; HI_U=$_hu
          log "안내(상태 화면): 아이폰이 블루투스로 붙은 뒤 ${IPH_WAIT}초 동안 카플레이가 시작되지 않음(우리 Wi-Fi에 붙은 기기 ${WSTA}대: 내비 재부팅 안내)"
        else
          HI=wifi; HI_T=$_hn; HI_U=$_hu
          dbg_trig b b_iph
          log "안내(상태 화면): 아이폰이 블루투스로 붙은 뒤 ${IPH_WAIT}초 동안 Wi-Fi에 오지 않음(우리 Wi-Fi에 붙은 기기 0대: 아이폰 Wi-Fi에서 차 네트워크를 지우고 다시 연결)"
        fi
        hint_write
      fi
    fi
  fi
  return 0
}

# 확인된 차가 아니면, 다른 hostapd(순정 핫스팟 등)가 돌 때 우리 핫스팟을 멈추고 비켜 준다(wlan0을 다투지 않게).
# 0: 비켜 줌(이번 회차는 아무것도 하지 않음), 1: 우리 핫스팟을 돌려도 됨. 로그는 상태가 바뀔 때만 남긴다($W/ap.yield).
# 모드가 적용되면 순정 핫스팟 메뉴가 꺼지므로(featurexml) 보통은 일어나지 않지만, 적용 직후 재부팅 전에는 있을 수 있다.
ap_yield() {
  if ! car_in "$prod" "$CARS_OK" && stock_ap_on; then
    # 1.7.0: 다른 hostapd가 도는 동안은 우리 AP가 아니므로 AA 신호를 끈다(리뷰 M1, 바뀔 때만 setprop)
    aa_sig 0 yield
    # 1.8.1 I-1(설계 리뷰 1): 비키는 동안은 우리 AP가 아니므로 우리 방화벽 규칙도 뺀다(stop_ours만 부르는 갈래가 있음)
    [ -n "$FWAA_ON" ] && fw_aa_down
    # 1.6.2: 순정이 카플레이 AP를 띄웠으면 우리 것을 멈추고 순정 AP 경로로 간다(돌아오지 않음)
    if [ "$(stock_ssid)" = carplay ]; then
      stop_ap; rm -f $W/ap.yield
      log "우리 핫스팟을 켠 뒤 순정 카플레이 AP가 켜짐: 우리 핫스팟을 멈춤(Wi-Fi 잠금은 삭제할 때 되돌림)"
      stock_ap_mode
    fi
    if [ ! -f $W/ap.yield ]; then
      : > $W/ap.yield; stop_ours
      log "다른 hostapd가 돌고 있음(순정 핫스팟 등): 우리 핫스팟을 멈추고 기다림"
    fi
    return 0
  fi
  if [ -f $W/ap.yield ]; then
    rm -f $W/ap.yield; log "다른 hostapd가 멈춤: 우리 핫스팟을 다시 켬"
  fi
  return 1
}

# 1.6.2: 순정 카플레이 AP로 준비됨. 순정이 카플레이 AP를 직접 띄우는 차(K3 BDPE, 1.6.1 알파에서 세션 확인 #15)에서는
# 우리 hostapd·dnsmasq·Wi-Fi 잠금·svc wifi를 하나도 하지 않는다(wlan0을 다투지 않게).
# 이 차에서 한 번 보면 $BK/stockap.seen을 남긴다: 다음 부팅에 순정 AP가 우리보다 늦게 떠도 우리 AP를 켜지 않는다.
# 기록이 낡지 않게, 순정 카플레이 AP를 한 번도 못 본 부팅이 STOCK_MISS_MAX번 이어지면 다음 부팅에 기록을 지우고
# 보통 흐름으로 돌아간다($BK/stockap.miss "<횟수> <부팅 id>", 리뷰 H2). 패키지를 지우면 $BK와 함께 지워진다.
# 순정 AP가 사라지면 우리 AP로 바꾸지 않고 순정이 다시 켤 때까지 기다린다(순정이 언제 켜고 끄는지 모르고, 바꾸면
# wlan0을 다툰다). 60초마다 ps만 보고 바뀔 때만 로그를 남긴다. 끝나는 조건: TERM(서비스 멈춤·패키지 삭제).
# mode=restart라 끝내지 않는다(끝내면 다시 시작되고 5번 죽으면 꺼진다). 돌아오지 않는다.
STOCK_MISS_MAX=${STOCK_MISS_MAX:-3}
stock_ap_ready() {
  # 리뷰 L4: 설치 마무리가 진행 중(run, 95% 보류 포함)이면 "준비됨"으로 덮지 않는다(fix_perms가 끝을 쓴다)
  if setup_done && ! prog_final_this_boot && ! fix_busy; then
    # 1.7.4(소유자 문구, 리뷰 반영): 상태 화면 판정 문구와 같은 뜻으로(L-9부터 AA는 늘 켜짐)
    prog 100 done "무선 프로젝션 준비됨."
  fi
  return 0
}
# 이번 부팅에 순정 카플레이 AP를 봄(0으로) / 못 봄(이번 부팅에서 한 번만 하나 올림)
stock_seen_now() { echo "0 ${BID:-$(cat $BOOT_ID 2>/dev/null)}" > $BK/stockap.miss; }
stock_miss_boot() {
  _mc=0; _mb=
  [ -f $BK/stockap.miss ] && read _mc _mb < $BK/stockap.miss
  case "$_mc" in ''|*[!0-9]*) _mc=0 ;; esac
  [ "$_mb" = "${BID:-$(cat $BOOT_ID 2>/dev/null)}" ] || echo "$((_mc+1)) ${BID:-$(cat $BOOT_ID 2>/dev/null)}" > $BK/stockap.miss
}
# 순정 AP 기록이 낡았는가(못 본 부팅이 STOCK_MISS_MAX번 이상, 이번 부팅은 세지 않음)
stock_seen_stale() {
  _mc=0; _mb=
  [ -f $BK/stockap.miss ] && read _mc _mb < $BK/stockap.miss
  case "$_mc" in ''|*[!0-9]*) _mc=0 ;; esac
  [ $_mc -ge $STOCK_MISS_MAX ]
}
stock_ap_mode() {
  STOCK_MODE=1
  $BB mkdir -p $BK; : > $BK/stockap.seen
  _k=$(stock_ssid)
  if [ "$_k" = carplay ]; then
    _on=1; stock_seen_now
    log "순정 카플레이 AP 사용: 우리 핫스팟을 켜지 않음 (카플레이 SSID 길이 ${#S2} 일치)"
    stock_ap_ready
  else
    _on=0; stock_miss_boot
    log "순정 카플레이 AP를 기다림: 이 차는 순정이 카플레이 AP를 켬(기록 stockap.seen, 지금 판정 $_k), 우리 핫스팟을 켜지 않음"
  fi
  # 디버그 로그(차주가 켰거나 처음 설치 뒤 48시간)는 순정 AP 차에서도 남긴다(리뷰 L2)
  debug_auto start
  logstart
  rm -f $CPN
  wifi_events; aa_events; cp_watch
  while true; do
    # 1.7.3(R-4): 이 회차는 60초지만 제보 요청은 30초마다 본다(앱의 기다림 표시와 맞게)
    sleep 30 & wait $!
    req_tick
    sleep 30 &
    wait $!
    perf_begin
    logrotate
    _k=$(stock_ssid)
    if [ "$_k" = carplay ]; then
      if [ $_on = 0 ]; then
        _on=1; stock_seen_now
        log "순정 카플레이 AP가 켜짐"
        stock_ap_ready
      fi
    elif [ $_on = 1 ]; then
      _on=0
      log "순정 카플레이 AP가 꺼짐: 순정이 다시 켤 때까지 기다림(우리 핫스팟은 켜지 않음, 지금 판정 $_k)"
    fi
    pf_mark; wifi_events; pf_lap TW; aa_events; pf_lap TA; cp_watch
    req_tick
    perf_tick
  done
}

# --- Wi-Fi 잠금 (1.5.5) ---
# 우리가 wpa_supplicant를 멈추면 Android Wi-Fi 서비스가 "Connection lost, restart supplicant"로 드라이버(bcmdhd)를
# 내렸다 올리고 wpa_supplicant를 다시 띄운다. 그때 우리 hostapd가 죽어 30초마다 반복된다(그랜저 #12·#17·#18,
# 쏘렌토 #16, 순정으로 되돌린 니로 2026-11-07에서 같은 로그로 확인).
# 니로가 11-03~11-06 무선 카플레이를 쓸 수 있었던 것은 11-02 실험이 남긴 root 소유 Wi-Fi 설정 파일 때문이었다:
# Wi-Fi HAL이 그 파일 권한을 못 바꿔 "Cannot set RW … Wi-Fi will not be enabled"로 wpa_supplicant를 띄우지 못하고,
# 드라이버만 올린 채 멈춘다. 그래서 우리 hostapd를 방해하지 않는다.
# 1.5.5는 그 상태를 의도적으로 만든다: 설정 파일을 root:root 660으로 두고 crc32 파일을 치운다(니로에서 검증된 그대로).
# 원래 소유자·권한과 crc32 파일은 $BK에 남겨 두고, 패키지를 지울 때(preun) 그대로 되돌린다.
# 영향: 일반 Wi-Fi 접속(클라이언트)을 쓸 수 없다. 한국 내수 펌웨어에는 그 메뉴가 없다.
WCONF=${WCONF:-/data/misc/wifi/wpa_supplicant.conf}
WCRC=${WCRC:-${WCONF%/*}/wpa_supplicant_crc32.conf}
WLAN=${WLAN:-/sys/class/net/$WIF}
WIFI_WAIT=${WIFI_WAIT:-9}
# 연달아 wpa_supplicant가 다시 뜬 회차가 이것을 넘으면 잠금이 듣지 않는 것: 한 번 알린다(핫스팟은 계속 지킨다)
SUPP_MAX=${SUPP_MAX:-3}
ns=0
f_owner() { $BB ls -ln "$1" 2>/dev/null | $BB awk '{ print $3 ":" $4 }'; }
f_perm() { $BB ls -ln "$1" 2>/dev/null | $BB awk '{ p = 0; s = substr($1, 2, 9)
  for (i = 0; i < 3; i++) { d = 0; if (substr(s, i*3+1, 1) == "r") d += 4; if (substr(s, i*3+2, 1) == "w") d += 2; if (substr(s, i*3+3, 1) != "-") d += 1; p = p * 10 + d }
  printf "%03d\n", p }'; }
# 잠금. 0: 잠겨 있음(이번에 잠갔거나 원래 잠김), 1: 설정 파일이 아직 없음(Wi-Fi 서비스가 처음 켤 때 만든다), 2: 실패
# 원래 상태 기록은 한 번만($BK/wpaconf.orig: "<소유자> <권한>"), crc32 파일은 $BK/wpacrc.bak + .orig로.
wifi_lock() {
  [ -f $WCONF ] || return 1
  _o=$(f_owner $WCONF)
  if [ "$_o" = 0:0 ] && [ ! -e $WCRC ]; then return 0; fi
  $BB mkdir -p $BK
  if [ ! -f $BK/wpaconf.orig ]; then
    _p=$(f_perm $WCONF)
    case "$_o $_p" in [0-9]*:[0-9]*" "[0-7][0-7][0-7]) ;; *) lock_fail "설정 파일 소유자·권한을 읽지 못함 ($_o $_p)"; return 2 ;; esac
    echo "$_o $_p" > $BK/wpaconf.orig
  fi
  if [ -e $WCRC ] && [ ! -f $BK/wpacrc.orig ]; then
    $BB cp -f $WCRC $BK/wpacrc.bak && echo "$(f_owner $WCRC) $(f_perm $WCRC)" > $BK/wpacrc.orig || { lock_fail "crc32 파일 백업 실패"; return 2; }
  fi
  # 소유자를 먼저 바꾸고 확인한 뒤에 crc32를 치운다(바꾸지 못했는데 crc32만 없으면 HAL이 파일을 지운다: A/B 시험)
  $BB chown 0:0 $WCONF && $BB chmod 660 $WCONF
  [ "$(f_owner $WCONF)" = 0:0 ] && rm -f $WCRC
  if [ "$(f_owner $WCONF)" = 0:0 ] && [ ! -e $WCRC ]; then log "Wi-Fi 잠금: 설정 파일을 root 소유로(원래 $(cat $BK/wpaconf.orig))"; return 0; fi
  lock_fail "지금 소유자 $(f_owner $WCONF)"; return 2
}
# 잠금 실패는 부팅마다 한 번만 기록한다(30초마다 ap.log가 쌓이지 않게)
lock_fail() {
  [ -f $W/wifilock.fail ] && [ "$(cat $W/wifilock.fail 2>/dev/null)" = "${BID:-$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)}" ] && return 0
  cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null > $W/wifilock.fail
  log "Wi-Fi 잠금 실패: $1"
}
# 잠금 되돌리기(preun): 원래 소유자·권한, crc32 파일. 설정 파일 내용은 바꾸지 않았다.
wifi_unlock() {
  if [ -f $BK/wpaconf.orig ] && [ -f $WCONF ]; then
    read _o _p < $BK/wpaconf.orig
    $BB chown $_o $WCONF; $BB chmod $_p $WCONF
  fi
  if [ -f $BK/wpacrc.orig ] && [ -f $BK/wpacrc.bak ]; then
    read _o _p < $BK/wpacrc.orig
    $BB cp -f $BK/wpacrc.bak $WCRC && $BB chown $_o $WCRC && $BB chmod $_p $WCRC
  fi
}

# --- 1.7.2(P-7): 순정 AP 저장값(Settings.Global wifi_ap_on) 맞추기 ---
# 순정 WifiService는 system_server가 뜰 때 wifi_ap_on을 한 번 읽고, BOOT_COMPLETED 뒤(부팅 약 40~46초) 값이 1이면 AP를 켠다.
# "이미 켜짐" 검사는 프레임워크 자기 상태만 보고 우리 hostapd는 모른다: 니로에서 이 부팅 복구가 우리 핫스팟과 부딪혔다
# (FINDINGS "연결 장면 로그 분석", V-3, 11-06 10:33·13:25). ACC를 끄면 AP는 꺼지지만 값은 1로 남는다.
# 순정 쪽에서 막을 수단은 이 값을 0으로 두는 것뿐이고 다음 부팅부터 듣는다(2026-11-09 소유자 결정).
# 우리 hostapd를 돌리는 차에서만 바꾼다. 바꾸지 않는 차:
#  - wireless.projection이 설치된 차(그 패키지가 AP를 다룬다)
#  - 함께 넣은 busybox를 쓰는 내비(tcc803x, K3·K8): 순정이 카플레이 AP를 직접 켤 수 있다(K3 #15). 그 경로가 이 값에
#    기대는지 모르므로 건드리지 않는다
#  - 순정 카플레이 AP를 본 차(stockap.seen), Wi-Fi 칩이 없는 차(wifi.nochip)
#  - 우리 hostapd가 지금 돌지 않을 때(켜지 못한 회차)
# 원래 값(1)은 한 번만 $BK/wifi_ap_on.orig에 적는다(이미 있으면 덮지 않음: 다시 시작해도 0으로 바뀌지 않게).
# 서비스가 핫스팟을 켠 뒤 한 번, 그 뒤 10분마다 다시 본다(세션 중 순정 AP 켜기가 1을 다시 쓰면 다음 부팅 전에 0으로).
# 삭제할 때(preun, 업데이트 때는 아님)만 apon_restore가 되돌린다. 순정 카플레이 AP 경로(stock_ap_mode)로 바꿀 때는 되돌리지
# 않는다(리뷰 M1): 우리가 0으로 바꾼 뒤 이번 부팅의 순정 복구 AP를 "순정 카플레이 AP"로 본 것일 수 있다. 되돌리면 매 부팅
# 순정 복구가 AP를 켜 stockap.seen이 낡지 않는다. 그대로 두면 순정 AP를 못 본 부팅이 쌓여 보통 흐름(우리 AP)으로 돌아온다.
# settings가 없거나 실패하면 로그 한 줄만 남기고 넘어간다(핫스팟 시작을 막지 않음, 같은 실행에서는 한 번만). 로그에는 값(숫자)만 쓴다.
APON_ORIG=${APON_ORIG:-$BK/wifi_ap_on.orig}
# 지금 값(숫자일 때만, 아니면 빈 값: null·오류 줄은 내지 않는다)
apon_get() { _ag=$(settings get global wifi_ap_on 2>/dev/null); case "$_ag" in ''|*[!0-9]*) ;; *) echo "$_ag" ;; esac; }
apon_off() {
  [ -d $WPDIR ] && return 0
  [ "$BB" = "$BB_OWN" ] && return 0
  [ -f $BK/stockap.seen ] && return 0
  [ -f $BK/wifi.nochip ] && return 0
  running "hostapd $CONF" || return 0
  if ! command -v settings >/dev/null 2>&1; then
    [ -z "$APON_TOLD" ] && log "순정 AP 저장값(wifi_ap_on) 맞추기 건너뜀: settings 명령 없음"
    APON_TOLD=1; return 0
  fi
  _av=$(apon_get)
  case "$_av" in
    0) return 0 ;;
    1) ;;
    # null(한 번도 안 씀)·읽지 못함 등: 순정이 부팅 때 AP를 켜지 않는 값이거나 알 수 없으므로 그대로 둔다
    *) [ -z "$APON_TOLD" ] && log "순정 AP 저장값(wifi_ap_on) 그대로 둠: 값 ${_av:-없음·읽지 못함}"
       APON_TOLD=1; return 0 ;;
  esac
  $BB mkdir -p ${APON_ORIG%/*}
  [ -f $APON_ORIG ] || echo 1 > $APON_ORIG
  # 시험판 5(네 번째 시험판 04:35:26 "바꾸지 못함(지금 값 1)"): 부팅 40~46초에 순정이 AP를 복구하며 1을 다시 쓸 수 있다(추정).
  # 5초 간격으로 세 번까지 쓰고 읽는다. 그래도 1이면 다음 30초 점검에 다시 한다(APON_AGAIN, 예전에는 10분 뒤)
  _ari=0; _arv=
  while [ $_ari -lt 3 ]; do
    settings put global wifi_ap_on 0 >/dev/null 2>&1
    _arv=$(apon_get); [ "$_arv" = 0 ] && break
    _ari=$((_ari + 1)); [ $_ari -lt 3 ] && sleep 5
  done
  if [ "$_arv" = 0 ]; then
    APON_AGAIN=
    log "순정 AP 저장값(wifi_ap_on) 1 → 0: 다음 부팅부터 순정이 AP를 켜지 않음(원래 값 $(cat $APON_ORIG 2>/dev/null), 삭제할 때 되돌림$([ $_ari -gt 0 ] && echo ", 순정이 다시 1을 써 ${_ari}번 다시 씀"))"
  else
    # 리뷰 낮음 2: 다음 점검 다시 하기는 10번까지(그 뒤로는 예전처럼 10분마다)
    APON_TRIES=$((${APON_TRIES:-0} + 1)); APON_AGAIN=; [ $APON_TRIES -lt 10 ] && APON_AGAIN=1
    [ -z "$APON_FAIL" ] && log "순정 AP 저장값(wifi_ap_on)을 0으로 바꾸지 못함(지금 값 ${_arv:-?}) — 세 번 써도 순정이 다시 1을 씀, 다음 점검에 다시"
    APON_FAIL=1
  fi
  return 0
}
# 되돌리기(preun): 기록이 있고 지금 값이 아직 0일 때만(다른 곳에서 바꿨으면 그대로) 원래 값으로. 되돌렸거나 다른 값이면 기록을 지운다.
# settings가 없거나 실패하면 1(preun이 삭제 출력에 안내하고, 기록은 $BK와 함께 지워진다). busybox 없이 돈다(busybox 없는 내비도 부름).
apon_restore() {
  [ -f $APON_ORIG ] || return 0
  _ao=; read _ao < $APON_ORIG
  case "$_ao" in 1) ;; *) rm -f $APON_ORIG; return 0 ;; esac
  if ! command -v settings >/dev/null 2>&1; then
    log "순정 AP 저장값(wifi_ap_on) 되돌리기 건너뜀: settings 명령 없음"; return 1
  fi
  _av=$(apon_get)
  if [ "$_av" = 0 ]; then
    settings put global wifi_ap_on $_ao >/dev/null 2>&1
    if [ "$(apon_get)" = "$_ao" ]; then
      log "순정 AP 저장값(wifi_ap_on) 되돌림: 0 → $_ao"
    else
      log "순정 AP 저장값(wifi_ap_on)을 되돌리지 못함"; return 1
    fi
  elif [ -z "$_av" ]; then
    log "순정 AP 저장값(wifi_ap_on) 되돌리기 건너뜀: 값을 읽지 못함"; return 1
  else
    log "순정 AP 저장값(wifi_ap_on) 그대로 둠: 우리가 바꾼 뒤 다른 곳에서 바뀜(지금 값 $_av)"
  fi
  rm -f $APON_ORIG
  return 0
}
# 대기만 한다. sleep을 뒤에서 돌리고 wait로 기다려야 TERM이 오면 바로 trap이 돈다(앞에서 돌리면 최대 1시간 늦음).
# mode=restart: 끝내지 않는다(svcmgr가 죽은 횟수를 세지 않게)
idle_forever() { while true; do sleep 3600 & wait $!; done; }
# 1.7.3(리뷰 L1): 무선 설정을 하지 않고 대기하는 차(지원 안 됨·softap.conf 못 읽음)도 제보 요청은 30초마다 본다.
# idle_forever처럼 끝나지 않는 대기이고, sleep을 뒤에서 돌리고 wait하므로 TERM에 바로 끝난다
idle_req() { while true; do sleep 30 & wait $!; req_tick; done; }
# 시작할 때 wlan0을 hostapd에 넘긴다: 드라이버는 Wi-Fi를 켜야 올라온다. 설정 파일이 없던 차는 켜는 동안 Wi-Fi
# 서비스가 만들므로 그 뒤에 잠근다. 잠근 뒤 wpa_supplicant를 멈추면 Wi-Fi 서비스가 한 번 다시 시작하려다 실패하고
# 드라이버만 남는다(약 6초). 그래서 wlan0이 다시 생길 때까지 최대 20초 기다린다.
take_wlan0() {
  # DG-12: 동글 사용이 켜진 부팅은 내장 Wi-Fi를 켜지도 잠그지도 않는다(동글 쪽 wlan0을 쓴다)
  # 베타 3(B3-2): 부품 없는 차에서 꽂기 전에 끈 부팅(plugoffnw)도 켜지 않는다(켤 내장이 없음)
  if [ "$DG_ST" = plugoffnw ]; then log "동글 사용 끔(내장 Wi-Fi 부품 없음): 내장 Wi-Fi를 켜지 않음"; return 0; fi
  if dg_builtin_off; then log "동글 사용: 내장 Wi-Fi를 켜지 않음(svc wifi enable·Wi-Fi 잠금 안 함)"; return 0; fi
  wifi_lock; _lk=$?
  # 1.7.2(P-11): 같은 부팅에서 서비스만 다시 시작했고(SVC_FIRST=0) 드라이버(wlan0)가 이미 있고 wpa_supplicant가 없고 Wi-Fi 설정이
  # 켜져 있으면 Wi-Fi 켜기와 대기(약 9초)를 건너뛴다. 설정 파일이 아직 없으면(_lk=1) 예전처럼 켠다(Wi-Fi 서비스가 만들게).
  # 부팅 뒤 처음 시작·업데이트 뒤 첫 시작($W가 지워짐)은 늘 예전처럼 한다.
  if [ "${SVC_FIRST:-1}" = 0 ] && [ $_lk != 1 ] && [ -d $WLAN ] && ! running wpa_supplicant \
      && [ "$(settings get global wifi_on 2>/dev/null)" = 1 ]; then
    log "같은 부팅에서 다시 시작: Wi-Fi 드라이버(wlan0)가 이미 있어 Wi-Fi 켜기·대기를 건너뜀"
    return 0
  fi
  svc wifi enable; sleep $WIFI_WAIT
  [ $_lk = 1 ] && { wifi_lock; _lk=$?; }
  if running wpa_supplicant; then
    $BB killall wpa_supplicant 2>/dev/null
    _i=0
    while [ $_i -lt 10 ]; do sleep 2; _i=$((_i+1)); [ -d $WLAN ] && ! running wpa_supplicant && [ $_i -ge 4 ] && break; done
  fi
  return 0
}
# 자동 설정(fix_perms → setup_hmgapi, 부팅 120초 뒤)이 아직 할 일이 있는가: 무선 모드가 없고, 다시 하지 않기로 한
# 기록(mod.tried, automap.bad, wifi.nochip)도 없고, wireless.projection도 없을 때. 1.5.3 그랜저IG 2.5(#2)는 서비스가
# 2분 간격으로 다시 시작돼 자동 설정이 한 번도 돌지 못했다(재부팅 반복 추정). 그래서 설정 중임을 알린다.
# 안내는 설치마다 한 번만($BK/setup.told): 설정이 조용히 끝나는 경로(지도 실패 기록, 순정 핫스팟 켜짐 등)에서
# 부팅마다 뜨지 않게.
setup_pending() {
  [ ! -f $BK/setup.told ] && [ ! -f $HMGDATA/mods/$MOD_ID/mod.json ] && [ ! -f $BK/mod.tried ] \
    && [ ! -f $BK/automap.bad ] && [ ! -f $BK/wifi.nochip ] && [ ! -s $BK/map.bad ] && [ ! -d $WPDIR ] \
    && [ -d $HMGDATA/maps ] && command -v hmgapid >/dev/null 2>&1
}
# --- Wi-Fi 연결 기록 (1.5.6) ---
# 5GHz로 바꾼 뒤 연결이 얼마나 자주·언제 끊기는지 보려고, 30초마다 커널 로그에서 새로 생긴 일만 ap.log에 남긴다.
# 남기는 것: AP 채널, AP 올라옴, 기기 연결(Wi-Fi 인증 끝)·끊김, 칩 응답 없음. 기기 주소(MAC)는 남기지 않는다.
# 어디까지 남겼는지는 $W/ktime("<부팅 id> <커널 초>")에 둔다: 재부팅하면 커널 시각이 0부터라 부팅 id가 다르면 처음부터.
# 베타 1 리뷰 C: 재부팅 없이 업데이트하면 $W가 지워져 새 서비스가 옛 "AP 채널"·"AP 올라옴" 줄을 다시 옮겼다(니로 01:09:49).
# 그래서 업데이트에도 남는 $BK에 사본(KTB)을 두고, $W 것이 없으면 그것을 읽는다.
# 베타 1 리뷰 A: 지금 우리 AP에 붙은 기기 수(WSTA)도 같은 커널 줄로 센다(기기 연결 +1, 끊김 -1, AP 올라옴 0). 이 값도 함께 둔다
# ("<부팅 id> <커널 초> <기기 수>"). 한계: Wi-Fi 키를 다시 맞추는 4-way가 연결로 세일 수 있고, 커널 버퍼에서 밀린 줄은 못 센다.
KT=${KT:-$W/ktime}
# 베타 2 차주 제보(#64): 예전 "${KTB:-$BK/ktime}"은 BK가 아래에서 정해져 차에서 /ktime이 되어
# "can't create /ktime: Read-only file system"을 남겼다. 1.7.4(B-7): BK를 맨 위(AAOFF 앞)에서 정하므로 그 값을 쓴다
KTB=${KTB:-$BK/ktime}
UPTIME=${UPTIME:-/proc/uptime}
CPN=${CPN:-$W/cpn}
wifi_events() {
  # 1.7.4(L-4): 부팅 id는 서비스가 시작할 때 읽어 둔 BID를 쓴다(30초 회차마다 cat을 띄우지 않게, K-7과 같은 방식). BID가 비면 예전처럼 읽음
  _bid=${BID:-$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)}; _bid=${_bid:-none}
  _last=0; _kf=$KT; [ -f $_kf ] || _kf=$KTB
  _kb=; _kl=; _ks=; _kt=
  if [ -f $_kf ]; then read _kb _kl _ks < $_kf; [ "$_kb" = "$_bid" ] && _last=${_kl:-0}; fi
  # 서비스가 다시 시작했으면 기기 수를 기록에서 이어 받는다(이번 부팅 것만)
  if [ -z "$WSTA" ]; then
    WSTA=0; [ "$_kb" = "$_bid" ] && case "$_ks" in ''|*[!0-9]*) ;; *) WSTA=$_ks ;; esac
  fi
  # 먼저 관심 있는 줄만 거른다(버퍼 약 130KB를 30초마다 awk로 다 보지 않게). 시각은 정규식 없이 [ ] 사이를 꺼낸다.
  # HANG: 대문자 HANG이 든 줄 중 "NETDEV_CHANGE"(유선 카플레이 ncm0 등)는 뺀다.
  dmesg 2>/dev/null | $BB grep -E 'target channel\(|AP/GO Link up|M4 of 4way|Disconnect STA|HANG' | $BB awk -v last="$_last" '
    { i = index($0, "["); j = index($0, "]"); if (i == 0 || j <= i) next
      s = substr($0, i + 1, j - i - 1); while (substr(s, 1, 1) == " ") s = substr(s, 2); tm = s + 0
      if (tm <= last + 0) next
      e = ""
      if (index($0, "target channel(") > 0) { c = $0; sub(/.*target channel\(/, "", c); sub(/\).*/, "", c); e = "AP 채널 " c }
      else if (index($0, "AP/GO Link up") > 0) { e = "AP 올라옴"; print "L" }
      else if (index($0, "M4 of 4way") > 0 && index($0, "[RX]") > 0) { e = "기기 연결(Wi-Fi 인증 끝)"; print "C " int(tm) }
      # hostapd가 시작할 때 모든 기기를 비우는 줄(브로드캐스트 주소)은 끊김으로 세지 않는다
      else if (index($0, "Disconnect STA") > 0) { if (index(tolower($0), "ff:ff:ff:ff:ff:ff") == 0) { e = "기기 연결 끊김"; print "D" } }
      else if (index($0, "HANG") > 0 && index($0, "CHANGE") == 0) e = "Wi-Fi 칩 응답 없음(HANG)"
      if (e != "") print "E Wi-Fi: " e " (커널 " int(tm) "초)"
      # 기억할 시각은 숫자로 바꾸지 않고 글자 그대로(awk가 773.805023을 773.805로 줄여 같은 줄을 다시 남기지 않게)
      if (tm > mxn) { mxn = tm; mx = s } }
    END { if (mxn > 0) print "T " mx }' 2>/dev/null > $W/kev
  [ -f $W/kev ] || return 0
  while IFS= read -r _l; do
    case "$_l" in
      "E "*) log "${_l#E }" ;;
      # 1.7.2(P-5): 마지막 기기 연결의 실제 시각(초). 커널 시각을 지금 시각으로 옮긴다(부팅 뒤 초를 못 읽으면 지금으로 봄)
      # 마지막 기기 연결의 부팅 뒤 초(커널 시각이 부팅 뒤 초다, 재리뷰 L4: 시계가 아니라 부팅 뒤 초로 비교)
      "C "*) _kc=${_l#C }; WSTA=$((WSTA + 1))
        case "$_kc" in ''|*[!0-9]*) ;; *) WCONN_AT=$_kc ;; esac ;;
      # 재리뷰 M3: 끊김·AP 다시 올라옴으로 0대가 되면 WGONE을 세운다(무선 AA "연결됨"을 지우는 근거, hint_tick)
      # 1.7.4(B-2): AP 올라옴은 L로 따로 적는다. 같은 회차에 뒤에 읽는 logcat(aa_events)의 연결됨은 AP가 올라온 뒤의 연결이므로
      # L을 지운다(aa_hint). #64: 서비스 시작 회차에 dmesg를 먼저 읽어 폰의 Wi-Fi 인증 줄이 아직 없고(WSTA=0) AA는 연결됨이라
      # "연결됨"이 바로 지워졌다
      "D") [ "$WSTA" -gt 0 ] && WSTA=$((WSTA - 1)); [ "$WSTA" = 0 ] && WGONE=1 ;;
      # 리뷰 반영: 같은 회차에 L 앞에 끊김(D)으로 0대가 된 기록(1)이 있으면 L로 덮지 않는다(그 끊김은 연결됨을 지우는 근거)
      "L") WSTA=0; [ "$WGONE" = 1 ] || WGONE=L ;;
      "T "*) _kt=${_l#T } ;;
    esac
  done < $W/kev
  rm -f $W/kev
  # 베타 2 DG-6: 동글 길이면 붙은 기기 수를 ARP로 센다(브로드컴 줄이 없어 늘 0이 되지 않게)
  dg_using && dg_sta
  # 어디까지 남겼는지·기기 수를 $W와 $BK에 둔다(새 줄이 있었을 때만 씀)
  if [ -n "$_kt" ]; then
    # 베타 2 차주 제보: 2>/dev/null을 먼저 둔다(셸은 리다이렉션을 왼쪽부터 처리해, "> 파일 2>/dev/null"이면 파일을 못 열 때의
    # 오류가 ap.log로 간다). $KTB 폴더도 만든 뒤 쓴다
    echo "$_bid $_kt $WSTA" 2>/dev/null > $KT; $BB mkdir -p ${KTB%/*} 2>/dev/null; echo "$_bid $_kt $WSTA" 2>/dev/null > $KTB
  fi
  return 0
}
# --- 무선 안드로이드 오토 단계 기록 (1.7.1) ---
# 리포트의 logcat 칸은 2~3분만 덮어서, AA가 붙은 순간이 리포트에 남지 않았다(#23 성공 리포트, 2026-11-08).
# 그래서 wifi_events처럼 30초마다 logcat 버퍼에서 새로 생긴 AA 단계 줄만 골라 ap.log에 짧게 남긴다.
# 남기는 것은 단계 이름과 숫자·참거짓뿐이다(폰 이름·주소는 줄에서 꺼내지 않는다). 뒤에서 도는 작업은 없다.
# 어디까지 남겼는지는 $AAT("<부팅 id> <logcat 시각>")에 둔다. 한 번에 최대 AAEV_MAX줄(재시도가 몰려도 ap.log가 넘치지 않게).
# 시계가 거꾸로 맞춰지면 그 사이 줄은 건너뛸 수 있다(진단용이라 감수).
AAT=${AAT:-$W/aatime}
AAEV_MAX=${AAEV_MAX:-20}
# 정식 F7: 30초 회차마다 남기는 화면 줄(카플레이 화면·AA 화면) 상한. 같은 줄이 연달아 오면 한 줄로 묶고, 넘는 줄은 개수만 남긴다.
# #580의 한 번 멈춤·복구(4초)가 17줄이라 그 한 번은 다 남게 30으로 둔다(ap.log 크기 상한은 aplog_rotate가 따로 지킴)
SCRMAX=${SCRMAX:-30}
aa_events() {
  # 1.7.4(L-4): 부팅 id는 서비스가 시작할 때 읽어 둔 BID를 쓴다(30초 회차마다 cat을 띄우지 않게, K-7과 같은 방식). BID가 비면 예전처럼 읽음
  _bid=${BID:-$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)}; _bid=${_bid:-none}
  _last=
  if [ -f $AAT ]; then read _ab _al _am < $AAT; [ "$_ab" = "$_bid" ] && _last="$_al $_am"; fi
  # 1.7.2(P-4·P-5): 자동 연결 실패 신호와 해소 줄(connection-timeline-aa.md 0장 9번, 문 3), 아이폰 iAP2 연결(HMG-API 브리지)도 본다.
  # 판정(F 줄)은 aa_flag가 처리한다. 판정에 쓰는 앞선 줄(isCheckReady false)은 이미 남긴 줄이어도 시각만 기억한다.
  #   unkpre: 신호(sys.kp.aa_ap)가 켜진 시각(on)보다 먼저 온 "AP 모드 모름"
  #   sppfail: isCheckReady ret = false 뒤 30초 안의 onSppConnect() ret = false(헤드유닛 쪽 SPP 거절)
  #   giveup: PhoneProjection 연결 시간 초과 tryCount 2 이상(재시도 포기) / cpwait: 카플레이가 연결되어 AA 갈래로 안 감
  #   ok: 폰 Wi-Fi 접속 성공·TCP 연결 / clr: AP 켜짐 true·Wi-Fi 연결 준비 0 / iap <몇 초 전>: 아이폰 iAP2 연결 / iapd: 끊김
  # 1.7.2(M-8 대신 진단): GPM이 보낸 "준비(1)"가 PP에 닿는지 본다(drafts/stock-re/bt-aa-autoconnect.md 1-4).
  #   GPM 준비 N 보냄·PP 준비 N 받음·PP 서비스 시작·GPM SPP 상태 N. 값은 줄 끝의 숫자만 남긴다(이름·주소는 꺼내지 않는다).
  #   "준비 1 보냄"이 "서비스 시작"보다 먼저이고 "준비 1 받음"이 없으면 그 가설이 맞다. 판정(F 줄)은 만들지 않는다(기록만).
  _ns=$(date '+%H %M %S' | $BB awk '{ print $1 * 3600 + $2 * 60 + $3 }')
  # 1.7.4 베타 2(측정): 측정 기록(perf_tick)이 같은 시각을 쓴다(date를 또 띄우지 않게)
  AA_SOD=$_ns
  # 1.8.0 베타 2(PF-2, 니로 베타 1 측정: 30초 점검의 85~90%가 여기): 예전에는 logcat 버퍼 전체를 글로 꺼내 셸 grep으로 걸렀다.
  # 이제 logcat이 태그로 먼저 거른다(-s 태그:V, 꺼내는 줄은 이 네 태그뿐). 아래 grep·awk와 지난 시각(_last)으로 이미 본 줄을 거르는 것은 그대로.
  # 새로 도는 반복·뒤의 프로세스는 없다(한 번 읽고 끝남)
  # 1.8.0 정식(P3·P4): 이 서비스의 첫 점검에서 같은 부팅의 이전 받기를 정리하고, 이어서 계속 받는 파일의 새 줄만 읽는다(aa_src)
  [ "$AAS_INIT" = 1 ] || { aalog_reset; AAS_INIT=1; }
  AAS_USE=0; [ "$AAS_ON" = 1 ] && aalog_start && AAS_USE=1
  # 니로 정식 1차 안전망: 받는 파일이 이어서 없으면 이 부팅은 예전 방식(위 AAS_NOF_MAX 설명). 이번 회차부터 바로 logcat -d로 읽는다
  if [ "$AAS_USE" = 1 ]; then
    if [ -f $AASTREAM ]; then AAS_NOF=0
    else
      AAS_NOF=$((${AAS_NOF:-0} + 1))
      if [ $AAS_NOF -ge $AAS_NOF_MAX ]; then
        aalog_kill; aa_bid
        echo "$_aabid" 2>/dev/null > $W/aa.old; echo "$_aabid nofile" 2>/dev/null > $W/aa.why
        log "AA 기록: 계속 받는 logcat이 ${AAS_NOF_MAX}번 점검 동안 받는 파일을 만들지 않아 이 부팅은 예전 방식(30초마다 logcat -d)으로 읽음"
        AAS_USE=0; AAS_NOF=0
      fi
    fi
  fi
  aa_src | $BB grep -E ' [VDIWEF]/(AAProjection|PhoneProjection|HMG-API|TccCarPlay|CarPlay_) *\(' \
    | $BB grep -E 'START_SPP_CONNECT_FOR_CONNECTIVITY|Sent WifiVersionRequest|wirelessSupported = |getWiFiApMode|isWifiApEnable = |Sent start request|MSG_WIFI_TRANSPORT_INIT retu|ACTION_WIRELESS_SPP_CONNECT_TIMEOUT|==> rfcommDisconnect|Already AA|isCheckReady ret = false|onSppConnect.. ret = false|connectivityConnectionTimeout|isConnectivityActivated return true|Connection status STATUS_|WifiTransport : .*onConnected|retry Wireless connection|canStartConnection = false|getWirelessConnection = false|bridge: iAP2 (dis)?connected comp=[14]|send requestWLDeviceReadyStatusUpdate|requestWLDeviceReadyStatusUpdate \[|PP Service is Running|onBTCMSppStatusChanged|AA 준비 다시 보냄|ready resend hook in |AA: timer error |glitches in the last|Lost packets|Unrecovered packets|Buffering issues|Jitter Buffer Discard|Main audio setting up|AirPlay session ended|[)]: (Glitches|Retransmits|Packets|Time Sync):|Modes changed: screen |DipoService ] (takeScreen|untakeScreen|onScreenStarted|onScreenStopped|onActivityResume|onActivityPause)|_ScreenTearDown.. : wait done|Screen stream (started|stopped)|screen stream timeout|CarPlaySessionScreenTimeout|DipoService ] onScreenTimeout|Sender went dead|isPopupType = |WirelessPhoneProjectionReceiver Action is: |displayInitPopup mAgreeScreen = |isAgreementScreen[(][)] = true|deviceID is null|_SetUpStreams|DipoActivity ] on(Pause|Resume) setPPFullscreenMode|getKeyAction.*= |dispatchKeyEvent.. ACTION_DOWN keyCode|untakeScreen Invalid|onVideoFocusModeChange|VideoFocusHandler VIDEO_FOCUS_|GalReceiverService : SURFACE_VIEW_|MainActivity : on(Start|Stop|Resume|Pause)$|VideoSink : init' \
    | $BB awk -v last="$_last" -v max="$AAEV_MAX" -v smax="$SCRMAX" -v on="$AA_ON_TM" -v now="${_ns:-0}" '
    # 찾는 글이 없으면 빈 값(줄 앞의 시각을 값으로 잘라 오지 않게, 리뷰 M2)
    function after(s,   i) { i = index($0, s); if (i == 0) return ""; return substr($0, i + length(s)) }
    # 값은 영문·숫자만, 8자까지(다른 글자는 지움: 이름 등이 섞여 나오지 않게)
    function word(s) { sub("^ +", "", s); sub("[ ,\t].*", "", s); gsub("[^0-9A-Za-z]", "", s); return substr(s, 1, 8) }
    # logcat 시각("MM-DD HH:MM:SS.mmm")의 하루 안 초
    function sod(t) { return substr(t, 7, 2) * 3600 + substr(t, 10, 2) * 60 + substr(t, 13) }
    # 상태 숫자만: 칸 전체가 숫자("1")나 괄호 친 숫자("(1)")일 때만 그 숫자(3자까지), 아니면 "?"(이름 조각이 섞여 나오지 않게)
    function num(s) { if (s !~ /^[(]?[0-9]+[)]?$/) return "?"; gsub("[^0-9]", "", s); return substr(s, 1, 3) }
    # 1.7.4 베타 2(측정): 순정 카플레이(TccCarPlay)가 스스로 남기는 소리 통계 줄. 숫자·영문 기호만 옮긴다(90자까지, 이름이 섞여 나오지 않게)
    # 리뷰 M3: 주소 꼴(MAC·IP)은 먼저 지우고, 영문자가 들어갈 자리는 줄마다 정해진 낱말만 받는다(cpa)
    function nums(s) { gsub("[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f:]+", "x", s); gsub("[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+", "x", s)
      gsub("[^0-9A-Za-z/%=,.:()+ -]", "", s); gsub("  +", " ", s); sub("^ +", "", s); sub(" +$", "", s); return substr(s, 1, 90) }
    # 숫자와 기호만(영문자 없음). 영문 낱말은 "min/max/avg"처럼 빗금으로 이은 것까지 통째로 지운다
    function digs(s) { gsub("[A-Za-z/]*[A-Za-z][A-Za-z/]*", "", s); gsub("[^0-9/%=,.:()+ -]", "", s); gsub("  +", " ", s); sub("^ +", "", s); sub(" +$", "", s); return substr(s, 1, 60) }
    # 정식 F7: 화면 줄은 정해진 낱말과 숫자만 남긴다(휴대폰·앱 이름, 패키지, 주소는 옮기지 않음)
    # AirPlay 주인 낱말: controller = 휴대폰, accessory = 내비
    function own(s) { sub("^ +", "", s); sub("[ ,(].*", "", s); if (s == "controller") return "휴대폰"; if (s == "accessory") return "내비"; if (s == "n/a") return "없음"; return "?" }
    function scr(   v, w, k) {
      if (index($0, "Modes changed: screen ") > 0) { v = after("speech "); w = v; sub("[^(]*[(]", "", w); sub("[)].*", "", w); if (w !~ /^[a-z]+$/ || length(w) > 12) w = "?"
        return "주인 바뀜 화면 " own(after("Modes changed: screen ")) ", 소리 " own(after("mainAudio ")) ", 음성 " own(v) "(" w ")" }
      if (index($0, "untakeScreen Invalid") > 0) return "내비가 화면 돌려주기 못 함(상태가 맞지 않음)"
      if ($0 ~ /DipoService ] takeScreen[(][)] *$/) return "내비가 화면 가져옴(takeScreen)"
      if (index($0, "DipoService ] onActivityResume() takeScreen force") > 0) return "카플레이 화면으로 돌아와 화면 가져옴(takeScreen force)"
      if ($0 ~ /DipoService ] untakeScreen[(][)] *$/) return "내비가 화면 돌려줌(untakeScreen)"
      if (index($0, "DipoService ] onScreenStarted()") > 0) return "화면 시작(onScreenStarted)"
      # 1.8.1 I-5(#306 08:11:01): 순정이 영상 시간 초과로 스스로 화면을 닫은 줄. 일반 onScreenStopped보다 먼저 본다
      if (index($0, "DipoService ] onScreenStopped() mScreenTimeout = true") > 0) return "화면 멈춤(onScreenStopped, 시간 초과)"
      if (index($0, "DipoService ] onScreenStopped()") > 0) return "화면 멈춤(onScreenStopped)"
      # 1.8.1 S-1(freeze-popups 3-1): 꼬리 "- len"은 프레임 머리, "- body"는 몸통을 받다 끊긴 것(받는 도중 200ms 공백). 휴대폰이 아예 안 보내면 Sender went dead
      if (index($0, "screen stream timeout") > 0) { v = "?"; if ($0 ~ /screen stream timeout - len *$/) v = "머리"; else if ($0 ~ /screen stream timeout - body *$/) v = "몸통"
        return "화면 스트림 시간 초과(" v ", screen stream timeout)" }
      if (index($0, "Sender went dead") > 0) return "휴대폰이 영상을 보내지 않아 멈춤(Sender went dead)"
      # 1.8.1 S-5(R-5 #578): DiPO 동의 화면. 참거짓 낱말만, 기기 ID 값은 옮기지 않는다(있었는지만).
      # isAgreementScreen 줄은 정상 차(니로)에서 몇 백 번 "= false"로 나와 그 꼴은 받지 않고 "= true"만 받는다(위 grep)
      if (index($0, "displayInitPopup mAgreeScreen = ") > 0) { v = word(after("mAgreeScreen = ")); if (v != "true" && v != "false") v = "?"; return "동의 화면 표시(mAgreeScreen " v ")" }
      if (index($0, "isAgreementScreen() = true") > 0) return "동의 화면 판단 true(isAgreementScreen)"
      if (index($0, "deviceID is null") > 0) return "저장된 기기 ID 없음(deviceID is null)"
      if (index($0, "CarPlaySessionScreenTimeout") > 0) return "화면 시간 초과로 세션이 닫음(CarPlaySessionScreenTimeout)"
      if (index($0, "DipoService ] onScreenTimeout()") > 0) return "화면 시간 초과(onScreenTimeout)"
      if (index($0, "_ScreenTearDown() : wait done") > 0) return "화면 스트림 내림(_ScreenTearDown)"
      if (index($0, "Screen stream stopped") > 0) return "화면 스트림 멈춤"
      if (index($0, "Screen stream started") > 0) return "화면 스트림 시작"
      if (index($0, "_SetUpStreams()") > 0) return "스트림 다시 세움(_SetUpStreams)"
      if (index($0, "DipoActivity ] onPause setPPFullscreenMode") > 0) return "카플레이 화면 가려짐(onPause)"
      if (index($0, "DipoActivity ] onResume setPPFullscreenMode") > 0) return "카플레이 화면 보임(onResume)"
      if (index($0, "WirelessAlertDialogActivity") > 0 && index($0, "DipoService ] onActivityResume()") > 0) return "휴대폰 연결 안내 창 뜸"
      if (index($0, "WirelessAlertDialogActivity") > 0 && index($0, "DipoService ] onActivityPause()") > 0) return "휴대폰 연결 안내 창 닫힘"
      if (index($0, "getKeyAction") > 0) { v = $NF; if (v !~ /^[a-z]+$/ || length(v) > 12) return ""; return "★키 동작 " v }
      if (index($0, "ACTION_DOWN keyCode") > 0) return "키 " num($NF) " 누름"
      return ""
    }
    function pop(   v) {
      if (index($0, "isPopupType = ") > 0) { v = after("isPopupType = "); sub("[^0-9].*", "", v); if (v == "") return ""; return "팝업 종류 " substr(v, 1, 3) }
      if (index($0, "Action is: com.daudio.app.PhoneProjection.Wireless.") > 0) { v = after("PhoneProjection.Wireless."); sub("[^A-Z_].*", "", v); if (v == "") return ""; return "방송 " substr(v, 1, 30) }
      return ""
    }
    function aas(   v, w) {
      if (index($0, "onVideoFocusModeChange focusMode = ") > 0) { v = after("focusMode = "); sub(",.*", "", v); w = after("reason = ")
        sub(" .*", "", w); if (v !~ /^[0-9]+$/) v = "?"; if (w !~ /^-?[0-9]+$/) w = "?"; return "영상 포커스 " substr(v, 1, 3) "(이유 " substr(w, 1, 4) ")" }
      if (index($0, "VideoFocusHandler VIDEO_FOCUS_") > 0) { v = after("VIDEO_FOCUS_"); sub("[^A-Z_].*", "", v); return "영상 포커스 " substr(v, 1, 20) }
      if (index($0, "GalReceiverService : SURFACE_VIEW_") > 0) { v = after("SURFACE_VIEW_"); sub("[^A-Z].*", "", v)
        if (v == "CREATE") return "화면 면 만듦"; if (v == "DESTROY") return "화면 면 없앰"; if (v == "CHANGED") return "화면 면 바뀜"; return "" }
      if ($0 ~ /MainActivity : onResume$/) return "AA 화면 보임(onResume)"
      if ($0 ~ /MainActivity : onPause$/) return "AA 화면 가려짐(onPause)"
      if ($0 ~ /MainActivity : onStart$/) return "AA 화면 시작(onStart)"
      if ($0 ~ /MainActivity : onStop$/) return "AA 화면 멈춤(onStop)"
      if (index($0, "VideoSink : init") > 0) return "영상 받기 시작(VideoSink)"
      return ""
    }
    function cpa(   v, k) {
      # 리뷰 M3: 순정이 통계를 남기는 두 꼴만 받는다("[AirPlay] …" 또는 태그 바로 뒤에서 시작하는 세션 요약 줄)
      if (index($0, "):  [AirPlay] ") == 0 && $0 !~ /[)]: (AirPlay session ended|Glitches|Retransmits|Packets|Time Sync):/) return ""
      if (index($0, "glitches in the last minute") > 0) return "지난 1분에 끊김 " (after("### ") + 0) "번(" (after("minute of ") + 0) "분 중 " (after("minute(s) (") + 0) "%)"
      if (index($0, "### Lost packets") > 0) return "패킷 잃음 +" (after("(+") + 0) "(모두 " ($(NF - 1) + 0) ")"
      if (index($0, "### Unrecovered packets") > 0) return "되살리지 못한 패킷 " (after(" (") + 0) "(모두 " ($(NF - 1) + 0) ")"
      if (index($0, "Buffering issues during session") > 0) { k = index($0, "### Main:") > 0 ? "주 소리" : "보조 소리"; v = after("session: "); if (v !~ /^Late=[0-9]+ Missing=[0-9]+ Gaps=[0-9]+ Rebuffers=[0-9]+ *$/) return ""; return "세션 버퍼 문제(" k ") " nums(v) }
      if (index($0, "Jitter Buffer Discard") > 0) { v = after("Excess, "); if (v !~ /^prevSize=[0-9]+[(][0-9]+ms[)] newSize=[0-9]+[(][0-9]+ms[)] *$/) return ""; return "지터 버퍼가 넘쳐 버림 " nums(v) }
      if (index($0, "Main audio setting up ") > 0) { v = after("setting up "); k = after(" for "); sub(" .*", "", v); sub(",.*", "", k)
        # 형식은 "AAC-LC/44100/2" 꼴, 용도는 영문 소문자 한 낱말일 때만(이름이 섞인 줄은 버린다)
        if (v !~ /^[A-Z0-9-]+\/[0-9]+\/[0-9]+$/ || k !~ /^[a-z]+$/) return ""
        return "소리 설정 " substr(v, 1, 24) " " substr(k, 1, 12) }
      if (index($0, "AirPlay session ended") > 0) { v = after("ended: "); if (v !~ /^Dur=[0-9]+ seconds Reason=-?[0-9]+\/0x[0-9A-Fa-f]+ *$/) return ""; return "세션 끝 " nums(v) }
      if (index($0, "): Glitches:") > 0) { v = after("Glitches:"); sub("[(]s[)]", "", v); return "세션 요약 끊김 " digs(v) " (% · 모두 · 끊긴 분)" }
      if (index($0, "): Retransmits:") > 0) return "세션 요약 재전송 " digs(after("Retransmits:")) " (보냄 · 받음 · 헛됨 · 못 찾음 · 최소/최대/평균 ms · 재시도 최소/최대 ms)"
      if (index($0, "): Packets:") > 0) return "세션 요약 패킷 " digs(after("Packets:")) " (잃음 · 못 되살림 · 늦음 · 최대 연속 · 큰 손실 · 압축 %)"
      if (index($0, "): Time Sync:") > 0) { v = after("Time Sync:"); sub(" RTT.*", "", v); return "세션 요약 Wi-Fi 왕복 시간 " digs(v) " ms (최소/최대/평균)" }
      return ""
    }
    { tm = $1 " " $2; nw = (last == "" || tm > last)
      if (index($0, "isCheckReady ret = false") > 0) ck = sod(tm)
      if (!nw) next
      e = ""; f = ""; p = "안드로이드 오토: "; cp = 0
      sc = 0
      # 정식 F7: 화면 줄(카플레이·AA)은 따로 센다. 소리·AA 단계 줄 한도를 밀어내지 않게
      if (index($0, "/CarPlay_") > 0 || (index($0, "/TccCarPlay") > 0 && $0 ~ /Modes changed: screen |_ScreenTearDown|Screen stream (started|stopped)|screen stream timeout|CarPlaySessionScreenTimeout|Sender went dead|_SetUpStreams/) || (index($0, "/PhoneProjection") > 0 && index($0, "getKeyAction") > 0)) { p = "카플레이 화면: "; e = scr(); sc = 1 }
      # 1.8.1 S-4(R-3 B2-20): 순정 팝업 종류 번호와 방송 이름(화면 줄과 같은 한도로 셈). 숫자 3자리·대문자 밑줄 낱말 30자까지만
      else if (index($0, "/PhoneProjection") > 0 && $0 ~ /isPopupType = |WirelessPhoneProjectionReceiver Action is: /) { p = "순정 팝업: "; e = pop(); sc = 1 }
      else if (index($0, "/AAProjection") > 0 && $0 ~ /onVideoFocusModeChange|VideoFocusHandler VIDEO_FOCUS_|GalReceiverService : SURFACE_VIEW_|MainActivity : on(Start|Stop|Resume|Pause)$|VideoSink : init/) { p = "AA 화면: "; e = aas(); sc = 1 }
      else if (index($0, "/TccCarPlay") > 0) { p = "카플레이 소리: "; e = cpa(); cp = 1 }
      else if (index($0, "START_SPP_CONNECT_FOR_CONNECTIVITY") > 0) e = "블루투스로 연결 시작(SPP)"
      else if (index($0, "Sent WifiVersionRequest") > 0) e = "폰에 Wi-Fi 버전 요청"
      else if (index($0, "wirelessSupported = ") > 0) e = "폰 무선 지원 " word(after("wirelessSupported = "))
      else if (index($0, "return APMode.UNKNOWN") > 0) { e = "AP 모드 모름(AP 꺼짐으로 봄)"; if (on != "" && tm < on) { e = e ", 신호보다 먼저"; f = "unkpre" } }
      else if (index($0, "getWiFiApMode wifiMode = ") > 0) e = "AP 모드 " word(after("wifiMode = "))
      else if (index($0, "isWifiApEnable = ") > 0) { v = word(after("isWifiApEnable = ")); e = "AP 켜짐 " v; m = word(after("mode = ")); if (m != "") e = e " 모드 " m; if (v == "true") f = "clr" }
      else if (index($0, "Sent start request") > 0) e = "폰에 Wi-Fi 연결 요청"
      else if (index($0, "MSG_WIFI_TRANSPORT_INIT retu") > 0) { v = word(after("retu = ")); e = "Wi-Fi 연결 준비 결과 " v; if (v == "0") f = "clr" }
      else if (index($0, "ACTION_WIRELESS_SPP_CONNECT_TIMEOUT") > 0) e = "SPP 연결 시간 초과"
      else if (index($0, "==> rfcommDisconnect") > 0) e = "블루투스 RFCOMM 끊김"
      else if (index($0, "Already AA") > 0) e = "이미 다른 AA 시도 중(유선 USB 등)"
      else if (index($0, "isCheckReady ret = false") > 0) e = "폰 프로젝션 준비 확인 false"
      else if (index($0, "ret = false") > 0 && index($0, "onSppConnect") > 0) {
        e = "헤드유닛 쪽 블루투스(SPP) 다시 연결 거절"; d = sod(tm) - ck; if (ck != "" && d >= 0 && d <= 30) f = "sppfail" }
      else if (index($0, "connectivityConnectionTimeout") > 0) { v = word(after("tryCount[")); e = "폰 프로젝션 연결 시간 초과(시도 " v ")"; if (v + 0 >= 2) f = "giveup" }
      else if (index($0, "isConnectivityActivated return true") > 0) { e = "카플레이 연결 중이라 건너뜀"; f = "cpwait" }
      # 1.8.1 I-9(#522): 휴대폰이 Wi-Fi에 붙은 것만으로는 "연결됨"(ok)을 내지 않는다(그 뒤 TCP가 막힌 차가 있음). 기다림 안내만 지우고(wjoin),
      # "AA 연결됨"은 아래 TCP 연결(WifiTransport onConnected) 줄에서만 낸다
      else if (index($0, "Connection status STATUS_") > 0) { v = word(after("STATUS_")); e = "폰 Wi-Fi 접속 " v; if (v == "SUCCESS") f = "wjoin" }
      else if (index($0, "WifiTransport") > 0 && index($0, "onConnected") > 0) { e = "TCP 연결됨"; f = "ok" }
      else if (index($0, "retry Wireless connection") > 0) e = "Wi-Fi 세션 오류로 한 번 다시 시도"
      else if (index($0, "canStartConnection = false") > 0) e = "연결 시작 막힘(canStartConnection false)"
      else if (index($0, "getWirelessConnection = false") > 0) e = "AA 무선 설정 꺼짐(getWirelessConnection false)"
      else if (index($0, "iAP2 connected comp=4") > 0) { p = "카플레이: "; e = "아이폰 블루투스 연결(iAP2)"; a = now - int(sod(tm)); if (a < 0) a += 86400; f = "iap " a }
      else if (index($0, "iAP2 disconnected comp=4") > 0) { p = "카플레이: "; e = "아이폰 블루투스 iAP2 끊김"; f = "iapd" }
      else if (index($0, "iAP2 connected comp=1") > 0) { p = "카플레이: "; e = "아이폰 USB(유선) iAP2 연결"; f = "usbon" }
      else if (index($0, "iAP2 disconnected comp=1") > 0) { p = "카플레이: "; e = "아이폰 USB(유선) iAP2 끊김"; f = "usboff" }
      # 진단 4줄(M-8 대신). 숫자는 늘 줄의 마지막 칸이다: "…:  [Ready] 1"(펌웨어에 따라 [ ] 안이 폰 이름), "…[이름], Ready (1)",
      # "…device: 이름 status: 2"
      else if (index($0, "send requestWLDeviceReadyStatusUpdate") > 0) e = "AA 앱(GPM)이 폰 프로젝션에 준비 " num($NF) " 보냄"
      else if (index($0, "requestWLDeviceReadyStatusUpdate [") > 0 && index($0, "Ready (") > 0) e = "폰 프로젝션이 준비 " num($NF) " 받음"
      else if (index($0, "PP Service is Running") > 0) e = "폰 프로젝션 서비스 시작(AA 앱이 확인)"
      else if (index($0, "onBTCMSppStatusChanged") > 0) { v = "?"; if ($(NF - 1) == "status:") v = num($NF); e = "AA 앱(GPM)이 블루투스 SPP 상태 " v " 받음" }
      # 1.7.3(모드 2.4.1, A-1): 모드가 폰 프로젝션이 뜬 뒤 준비(1)를 다시 보낸 결과. 모드가 숫자·이유만 쓴다(주소·이름 없음).
      # 혹시 섞여도 남지 않게 MAC 꼴은 지우고, 뒤쪽 글은 그대로 옮긴다(예: "2대", "0대 (이미 연결됨)", "훅 없음 (…)")
      # 1.7.4(모드 2.4.2): "0대 (신호 없음 60초)"는 AA를 쓰지 않는 차에서도 나오는 정상 줄이라 실패처럼 읽히지 않게 따로 쓴다.
      # "신호 기다림 N초"는 신호를 기다린 뒤 다시 보냈다는 뜻이다. 판정(연결됨·안 됨)에는 쓰지 않는다(f 없음)
      else if (index($0, "AA 준비 다시 보냄") > 0) { v = after("AA 준비 다시 보냄"); gsub("[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]", "x", v); sub("^ +", "", v)
        if (index(v, "(신호 없음") > 0) { w = v; sub(".*신호 없음 *", "", w); sub("[)].*", "", w); e = "모드: " w " 동안 AA 신호가 없어 준비 다시 보내기를 하지 않음(정상: AA를 쓰지 않아도 나옴)" }
        else if (index(v, "신호 기다림") == 1) { w = v; sub("^신호 기다림 *", "", w); e = "모드가 AA 신호를 " w " 기다린 뒤 준비 다시 보냄" }
        else e = "모드가 준비 다시 보냄 " v }
      else if (index($0, "ready resend hook in ") > 0) { v = after("ready resend hook in "); sub(" .*", "", v); gsub("[^A-Za-z0-9._]", "", v); e = "모드의 준비 다시 보내기 훅 걸림(" substr(v, 1, 60) ")" }
      # 확정 2.4.1: 모드의 타이머(계기판 이름 붙잡기 nameDue·tick)가 예외로 넘어감(연결마다 한 번). 종류(예외 이름)만 영문·숫자·점으로
      else if (index($0, "AA: timer error ") > 0) { v = after("AA: timer error "); sub(" .*", "", v); gsub("[^A-Za-z0-9._]", "", v); e = "모드 타이머 오류(" substr(v, 1, 60) ")" }
      # 리뷰 M2: 소리 줄은 따로 센다(한 번에 16줄: 세션이 끝날 때 요약이 5줄 나온다). Wi-Fi가 나빠 소리 줄이 몰려도 AA 단계 줄을 한도에서 밀어내지 않게
      # 정식 F7: 화면 줄은 바로 앞 화면 줄과 같으면 세기만 하고(쏟아짐 묶기), 한 회차 SCRMAX줄까지. 넘거나 묶은 줄 수는 끝에 한 줄
      # 1.8.1 S-3: 화면 시간 초과가 있은 회차는 30초 측정 줄에 scrto=1(perf_tick)
      if (sc && $0 ~ /screen stream timeout|Sender went dead/) f = "scrto"
      if (e != "" && sc) { if (p e == sl) sd++; else if (ns < smax + 0) { print "E " p e " (" $2 ")"; ns++; sl = p e } else so++ }
      else if (e != "" && cp) { if (nc < 16) { print "E " p e " (" $2 ")"; nc++ } }
      else if (e != "" && n < max + 0) { print "E " p e " (" $2 ")"; n++ }
      if (f != "") print "F " f
      # 베타 3(B3-3 b_audio): 순정의 "지난 1분에 끊김 N번" 줄 수와 N
      if (cp && index($0, "glitches in the last minute") > 0) print "F glitch " (after("### ") + 0)
      if (mx == "" || tm > mx) mx = tm }
    END { if (sd + so > 0) print "E 화면 줄 줄임: 같은 줄 연달아 " sd + 0 "줄, 한도 넘어 " so + 0 "줄 안 남김"
      if (mx != "") print "T " mx }' 2>/dev/null > $W/aaev
  [ -f $W/aaev ] || return 0
  while IFS= read -r _l; do
    case "$_l" in
      "E "*) log "${_l#E }" ;;
      "F "*) aa_flag ${_l#F } ;;
      "T "*) echo "$_bid ${_l#T }" > $AAT ;;
    esac
  done < $W/aaev
  rm -f $W/aaev
  return 0
}
# 카플레이 연결 수(ESTABLISHED)가 바뀌면 남긴다
# 지금 무선 카플레이 연결 수: 로컬 포트 7000(DiPO, 16진 1B58)의 ESTABLISHED(01) 연결 중 로컬 주소가 wlan0의 주소인 것.
# 1.7.0: 예전에는 netstat에서 우리 AP 주소 $AP_IP:7000만 세서 순정 AP 차(K3, 주소가 다름)에서 늘 0이었다.
# netstat은 긴 IPv6 주소를 자를 수 있어(리뷰 M1) /proc/net/tcp·tcp6을 직접 읽는다. 주소는 32비트 단위로 바이트가 뒤집혀
# 있다(리틀 엔디언). wlan0의 IPv6는 /proc/net/if_inet6(네트워크 순서), IPv4는 ifconfig wlan0의 inet addr로 맞춘다.
# 유선 카플레이(USB 네트워크 ncm0)는 wlan0 주소가 아니라 세지 않는다(리뷰 M2). IPv4가 IPv6 꼴(::ffff:)이어도 맞춘다.
PROCNET=${PROCNET:-/proc/net}
# 1.7.1: 순정 AP가 wlan0가 아닌 인터페이스(ap0·softap0·swlan0 등)에 뜨는 차도 센다(리뷰에서 나온 경우, 차에서 본 적은 없음).
# /sys/class/net에 있는 그 이름들과 wlan0의 주소를 모두 본다. 유선(ncm0 등)은 여전히 세지 않는다.
SYSNET=${SYSNET:-/sys/class/net}
cp_ifs() {
  _ci=$WIF
  for _x in $SYSNET/ap* $SYSNET/softap* $SYSNET/swlan*; do [ -e "$_x" ] && _ci="$_ci ${_x##*/}"; done
  echo $_ci
}
cp_count() {
  _ifl=$(cp_ifs)
  _v4=; for _x in $_ifl; do
    _a=$($BB ifconfig $_x 2>/dev/null | $BB awk '/inet addr:/ { a = $0; sub(/.*inet addr:/, "", a); sub(/ .*/, "", a); print a; exit }')
    [ -n "$_a" ] && _v4="$_v4 $_a"
  done
  # 있는 파일만 넘긴다(IPv6가 꺼진 커널에는 if_inet6·tcp6이 없다. 하나도 없으면 awk가 표준입력을 기다리므로 0)
  _pf=; for _x in if_inet6 tcp tcp6; do [ -r $PROCNET/$_x ] && _pf="$_pf $PROCNET/$_x"; done
  [ -n "$_pf" ] || { echo 0; return 0; }
  $BB awk -v v4="$_v4" -v ifl=" $_ifl " '
    function le(w) { return substr(w, 7, 2) substr(w, 5, 2) substr(w, 3, 2) substr(w, 1, 2) }
    BEGIN { k = split(v4, vs, " "); for (i = 1; i <= k; i++) if (split(vs[i], o, ".") == 4) ok4[sprintf("%02X%02X%02X%02X", o[1], o[2], o[3], o[4])] = 1 }
    FILENAME ~ /if_inet6$/ { if (index(ifl, " " $6 " ") > 0) ok6[toupper($1)] = 1; next }
    $4 == "01" && split($2, p, ":") == 2 && p[2] == "1B58" {
      a = toupper(p[1])
      # busybox 1.8.1 awk가 함수 호출 결과로 in을 못 쓸 수 있어 변수에 담아 본다
      if (length(a) == 8) { k = le(a); if (k in ok4) n++; next }
      if (length(a) != 32) next
      f = le(substr(a, 1, 8)) le(substr(a, 9, 8)) le(substr(a, 17, 8)) le(substr(a, 25, 8))
      if (f in ok6) n++
      else if (substr(f, 1, 24) == "00000000000000000000FFFF") { k = substr(f, 25, 8); if (k in ok4) n++ }
    }
    END { print n + 0 }' $_pf 2>/dev/null || echo 0
}
cp_watch() {
  _n=$(cp_count)
  _o=$(cat $CPN 2>/dev/null)
  if [ "${_n:-0}" != "${_o:-0}" ]; then
    log "카플레이 연결 ${_o:-0} → ${_n:-0}"; echo "${_n:-0}" > $CPN; st_push
    # 베타 3(B3-1): 동글 길 부팅의 첫 카플레이 시각
    [ "${_n:-0}" -gt 0 ] && dg_using && { kp_up; dg_tl cp "${_U:-}"; }
    # 베타 3(B3-3 b_cpdrop): 줄어들면 센다(10분 안 DBG_CP_N번)
    [ "${_n:-0}" -lt "${_o:-0}" ] && dbg_cnt cpdrop $DBG_CP_N b_cpdrop
  fi
  return 0
}

# --- 1.7.4 베타 2(측정, 소유자 지시 2026-11-14): 30초 측정 기록 ---
# 내비가 버벅이거나 무선 카플레이의 통화·음악 소리가 늦을 때 원인을 가르려고, 30초 점검마다 숫자 한 줄을 $PERF에 남긴다.
# 제보 파일(3-log.txt)이 이 기록을 싣고, 1-report.md가 요약한다(status.sh perf_report).
# 측정이 부하를 늘리지 않게 프로세스를 띄우지 않는다: /proc 파일을 read로만 읽고 셸 산술로 계산한다
# (기록을 밀 때만 PERF_MAX줄마다 한 번 mv). 숫자만 쓴다(이름·주소 없음).
# 한 줄: "<시:분:초> up=<부팅 뒤 초> load=<1분 부하> cpu=<내비 전체 CPU 사용 %> io=<입출력 대기 %> svc=<우리 서비스 셸과 끝난 자식이 쓴 CPU,
#   1/100초. 계속 도는 hostapd·dnsmasq·디버그 로그 줄은 들어가지 않는다(리뷰 M4): 그것은 제보 파일의 프로세스 표로 본다> tick=<이번 점검에 걸린 시간, 1/100초> free=<빈 메모리 kB> cache=<캐시 kB> cp=<카플레이 연결 수> sta=<우리 Wi-Fi에 붙은 기기 수>
#   rx= tx=<Wi-Fi 패킷 수> rxe= rxd= txe= txd=<Wi-Fi 오류·버림> udpe= udpb=<UDP 받기 오류·버퍼 넘침> retr=<TCP 재전송> dbg=<디버그 로그 0|1>
#   tick_wifi= tick_aa= tick_rest=<1.8.0 PF-2: 이번 점검 안 wifi_events·aa_events·나머지에 걸린 시간, 1/100초>"
# cpu·io·svc·rx…retr는 지난 점검부터의 변화량이다. 처음이거나 읽지 못한 값은 "-".
# 끝나는 조건: 반복 없음(점검마다 한 번). 크기: PERF_MAX줄을 넘으면 $PERF.1로 밀어 최대 2개(약 2~4시간 치, 100KB 안쪽).
PERF=${PERF:-$W/perf.log}
PERF_MAX=${PERF_MAX:-240}
KSTAT=${KSTAT:-/proc/stat}
LOADAVG=${LOADAVG:-/proc/loadavg}
MEMINFO=${MEMINFO:-/proc/meminfo}
# 부팅 뒤 시간을 1/100초 단위 정수로 _pc에("123.45" → 12345). 못 읽으면 빈 값
perf_cs() {
  _pc=; { read _pc _px < ${UPTIME:-/proc/uptime}; } 2>/dev/null
  case "$_pc" in *.[0-9][0-9]) _pc=${_pc%.*}${_pc#*.} ;; *) _pc= ;; esac
  case "$_pc" in ''|*[!0-9]*|0*) _pc= ;; esac
  return 0
}
# 점검을 시작한 시각을 기억한다(30초 대기가 끝난 바로 뒤에 부른다)
perf_begin() { perf_cs; PF_T0=$_pc; PF_TW=-; PF_TA=-; PF_L=; return 0; }
# 1.8.0 PF-2: 점검 안 단계별 시간(1/100초). 무엇을 줄일지 고르기 전에 잰다(1.8.0-perf-fix.md, 점검 한 번 평균 7.75초).
# pf_mark로 시작점을 두고 pf_lap <이름>이 그때부터 지금까지를 PF_<이름>에 둔다. /proc/uptime만 읽는다(프로세스를 띄우지 않음).
# perf_tick이 tick_wifi(wifi_events)·tick_aa(aa_events)·tick_rest(나머지 = tick - 둘)로 한 줄에 붙인다. 못 재면 "-"
pf_mark() { perf_cs; PF_L=$_pc; return 0; }
pf_lap() {
  perf_cs
  if [ -n "$_pc" ] && [ -n "$PF_L" ] && [ "$_pc" -ge "$PF_L" ]; then eval "PF_$1=$((_pc - PF_L))"; else eval "PF_$1=-"; fi
  PF_L=$_pc
  return 0
}
# $1 이름, $2 지금 값: 지난 값과의 차를 _d에 두고(처음·숫자 아님·줄어듦이면 "-") 지금 값을 PF_$1에 기억한다
# 1.8.1 I-10(#306: 누적 1GB를 넘은 24분 동안 rx=-): 차의 셸(mksh)은 산술도 [ -ge ]도 32비트라 10자리 값은 그대로 다룰 수 없다.
# 값을 "앞부분 + 끝 9자리"로 나눠 셸에서만 뺀다(awk·프로세스를 띄우지 않음). 끝 9자리 앞에 1을 붙여(1xxxxxxxxx, 2^31보다 작음)
# 0으로 시작하는 수가 8진으로 읽히지 않게 한다(끝 9자리는 0으로 채워 9자리로 맞춘 뒤 붙임). 앞부분이 2 이상 차이 나면(30초에 1GB 넘게 늘어남) 차를 내지 않는다("-").
# 앞부분은 9자리까지만 받는다(그 이상은 숫자 아님과 같이 다룸). 줄어들면 "-"
pf_split() {
  _ph=0; _pl=$1
  if [ ${#1} -gt 9 ]; then
    _pl=${1#${1%?????????}}; _ph=${1%?????????}
    while :; do case "$_ph" in 0?*) _ph=${_ph#0} ;; *) break ;; esac; done
  fi
  while [ ${#_pl} -lt 9 ]; do _pl=0$_pl; done
  _pl=1$_pl
  [ ${#_ph} -le 9 ]
}
pf_delta() {
  _d=-
  case "$2" in ''|*[!0-9]*) return 0 ;; esac
  eval "_o=\$PF_$1"
  eval "PF_$1=$2"
  [ -n "$_o" ] || return 0
  pf_split "$_o" || return 0; _oh=$_ph; _ol=$_pl
  pf_split "$2" || return 0
  if [ "$_ph" = "$_oh" ]; then
    [ "$_pl" -ge "$_ol" ] && _d=$((_pl - _ol))
  elif [ "$_ph" -gt "$_oh" ] && [ $((_ph - _oh)) = 1 ]; then
    _d=$((_pl - _ol + 1000000000))
  fi
  return 0
}
# 서비스가 시작할 때 한 번: 표시 줄을 남긴다(지난 부팅·지난 실행의 줄과 구분, 날짜는 여기에만 있다)
perf_start() {
  # 리뷰 M1: $W는 재부팅해도 남는다. 이미 쌓인 줄 수를 세어 이어 가고(read로만), 한도를 넘었으면 지금 민다
  PF_N=0
  if [ -f $PERF ]; then
    while IFS= read -r _pl0; do PF_N=$((PF_N + 1)); done < $PERF
    if [ $PF_N -ge $PERF_MAX ]; then $BB mv -f $PERF $PERF.1 2>/dev/null || : > $PERF; PF_N=0; fi
  fi
  log_ts; kp_up
  echo "# 서비스 시작 $_LT up=${_U:--}" 2>/dev/null >> $PERF
  PF_N=$((PF_N + 1))
  return 0
}
perf_tick() {
  perf_cs; _pe=$_pc
  _tk=-; [ -n "$_pe" ] && [ -n "$PF_T0" ] && [ "$_pe" -ge "$PF_T0" ] && _tk=$((_pe - PF_T0))
  # 내비 전체 CPU: /proc/stat 첫 줄(user nice system idle iowait irq softirq)의 변화량에서 사용·입출력 대기 비율
  _cpu=-; _io=-; _cu=; _cn=; _cs=; _ci=; _cw=; _cq=; _csq=
  { read _cx _cu _cn _cs _ci _cw _cq _csq _cr < $KSTAT; } 2>/dev/null
  case "$_cu$_cn$_cs$_ci$_cw$_cq$_csq" in ''|*[!0-9]*) ;; *)
    if [ -n "$_cu" ] && [ -n "$_cn" ] && [ -n "$_cs" ] && [ -n "$_ci" ] && [ -n "$_cw" ] && [ -n "$_cq" ] && [ -n "$_csq" ]; then
      _ct=$((_cu + _cn + _cs + _ci + _cw + _cq + _csq)); _cb=$((_ct - _ci - _cw))
      if [ -n "$PF_CT" ] && [ $((_ct - PF_CT)) -gt 0 ] && [ $_cb -ge $PF_CB ] && [ $_cw -ge $PF_CW ]; then
        _cpu=$(( (_cb - PF_CB) * 100 / (_ct - PF_CT) )); _io=$(( (_cw - PF_CW) * 100 / (_ct - PF_CT) ))
      fi
      PF_CT=$_ct; PF_CB=$_cb; PF_CW=$_cw
    fi ;;
  esac
  # 우리 서비스: 이 셸과 끝난 자식들이 쓴 CPU. 점검마다 띄우는 logcat·ps·grep은 잡히고, 계속 도는 hostapd 등은 잡히지 않는다(/proc/<pid>/stat 14~17번째 칸: utime stime cutime cstime, 1/100초)
  _s14=; _s15=; _s16=; _s17=
  { read _s1 _s2 _s3 _s4 _s5 _s6 _s7 _s8 _s9 _s10 _s11 _s12 _s13 _s14 _s15 _s16 _s17 _sr < $PROC/$$/stat; } 2>/dev/null
  _sv=
  case "$_s14$_s15$_s16$_s17" in ''|*[!0-9]*) ;; *)
    [ -n "$_s14" ] && [ -n "$_s15" ] && [ -n "$_s16" ] && [ -n "$_s17" ] && _sv=$((_s14 + _s15 + _s16 + _s17)) ;;
  esac
  pf_delta ST "$_sv"; _sv=$_d
  _ld=; { read _ld _lx < $LOADAVG; } 2>/dev/null
  case "$_ld" in ''|*[!0-9.]*) _ld=- ;; esac
  _mf=-; _mc=-
  if [ -r $MEMINFO ]; then
    while read _mk _mv _mu; do
      case "$_mk" in MemFree:) _mf=$_mv ;; Cached:) _mc=$_mv; break ;; esac
    done < $MEMINFO
    case "$_mf" in ''|*[!0-9]*) _mf=- ;; esac
    case "$_mc" in ''|*[!0-9]*) _mc=- ;; esac
  fi
  # Wi-Fi 장치의 패킷·오류·버림(/proc/net/dev: 받은 바이트 패킷 오류 버림 … 보낸 바이트 패킷 오류 버림). 바이트는 32비트를 넘어 쓰지 않는다
  _rp=; _re=; _rd=; _tp=; _te=; _td=; _wm=0; _wn=0
  if [ -r $PROCNET/dev ]; then
    while IFS= read -r _nl; do
      # 리뷰 L2: 이름이 정확히 같은 줄만(swlan0 같은 다른 장치에 걸리지 않게): 줄이 이름으로 시작하거나 이름 앞이 빈칸·탭일 때.
      # PF-5(니로 2026-11-15): 예전 꼴(continue, 중간 set --)은 차의 셸에서 값이 비었다(원인 모름). case 하나로 고르고,
      # 두 자리 위치 인자(${10}) 대신 shift로 읽는다
      # 정식(H-1, 베타 2 제보 #79·#530): 차의 셸에서 ${_nl#*:}가 "wlan0:"를 떼지 못해 칸이 하나씩 밀렸다(wn=17, 받기 오류 칸에 패킷 수).
      # 패턴 지우기 대신 IFS에 콜론을 넣어 나누고 첫 칸(장치 이름)을 버린다. 숫자 칸이 정확히 16이 아니면 Wi-Fi 칸은 비운다(기록에는 "-")
      case "$_nl" in
        "$WIF:"*|*" $WIF:"*|*"	$WIF:"*)
          _wm=1
          case $- in *f*) _wff=0 ;; *) _wff=1; set -f ;; esac
          _wifs=$IFS; IFS=" 	:"; set -- $_nl; IFS=$_wifs
          [ $_wff = 1 ] && set +f
          [ $# -ge 1 ] && shift
          _wn=$#
          if [ $_wn = 16 ]; then
            _rp=$2; _re=$3; _rd=$4
            shift 8; _tp=$2; _te=$3; _td=$4
          fi
          break ;;
      esac
    done < $PROCNET/dev
  fi
  # UDP 받기 오류·버퍼 넘침(카플레이 소리는 UDP), TCP 재전송(/proc/net/snmp: 이름 줄 다음에 값 줄)
  # 1.8.1 S-2(freeze-popups 3-1): 영상은 TCP다. 받은 TCP 조각 수(Tcp: InSegs)와 순서 어긋남·중복(TcpExt: TCPOFOQueue·TCPDSACKOldSent·TCPDSACKOfoSent,
  # /proc/net/netstat)의 변화량으로 Wi-Fi 손실과 휴대폰 멈춤을 가른다. 이름이 없는 커널이면 "-"
  _ue=; _ub=; _rt=; _ti=; _ph=; _hn=
  if [ -r $PROCNET/snmp ]; then
    while read -r _sk _srest; do
      case "$_sk" in Udp:|Tcp:)
        if [ "$_ph" = "$_sk" ]; then
          set -- $_srest
          for _n in $_hn; do
            case "$_sk $_n" in "Udp: InErrors") _ue=$1 ;; "Udp: RcvbufErrors") _ub=$1 ;; "Tcp: RetransSegs") _rt=$1 ;; "Tcp: InSegs") _ti=$1 ;; esac
            [ $# -gt 0 ] && shift
          done
          _ph=
        else _ph=$_sk; _hn=$_srest; fi ;;
      esac
    done < $PROCNET/snmp
  fi
  pf_delta RP "$_rp"; _rp=$_d; pf_delta RE "$_re"; _re=$_d; pf_delta RD "$_rd"; _rd=$_d
  pf_delta TP "$_tp"; _tp=$_d; pf_delta TE "$_te"; _te=$_d; pf_delta TD "$_td"; _td=$_d
  _xo=; _xd=; _xf=; _ph=; _hn=
  if [ -r $PROCNET/netstat ]; then
    while read -r _sk _srest; do
      case "$_sk" in TcpExt:)
        if [ "$_ph" = "$_sk" ]; then
          set -- $_srest
          for _n in $_hn; do
            case "$_n" in TCPOFOQueue) _xo=$1 ;; TCPDSACKOldSent) _xd=$1 ;; TCPDSACKOfoSent) _xf=$1 ;; esac
            [ $# -gt 0 ] && shift
          done
          _ph=
        else _ph=$_sk; _hn=$_srest; fi ;;
      esac
    done < $PROCNET/netstat
  fi
  pf_delta UE "$_ue"; _ue=$_d; pf_delta UB "$_ub"; _ub=$_d; pf_delta RT "$_rt"; _rt=$_d
  pf_delta TI "$_ti"; _ti=$_d; pf_delta XO "$_xo"; _xo=$_d; pf_delta XD "$_xd"; _xd=$_d; pf_delta XF "$_xf"; _xf=$_d
  # 1.8.1 S-3: 이 회차에 화면 시간 초과가 있었으면 줄 끝에 scrto=1(aa_flag가 세운 표시, 붙인 뒤 지움)
  _pst=; [ "$PF_SCRTO" = 1 ] && { _pst=" scrto=1"; PF_SCRTO=; }
  _pcp=; { read _pcp < $CPN; } 2>/dev/null; case "$_pcp" in ''|*[!0-9]*) _pcp=0 ;; esac
  _pdb=0; [ -f $W/log.pid ] && _pdb=1
  # 시각: aa_events가 이번 점검에서 구한 "하루 안 초"(AA_SOD)를 시:분:초로 바꾼다(date를 또 띄우지 않게). 없으면 "--:--:--"
  _ptm="--:--:--"
  case "$AA_SOD" in ''|*[!0-9]*) ;; *)
    _ph2=$((AA_SOD / 3600)); _pm2=$((AA_SOD % 3600 / 60)); _ps2=$((AA_SOD % 60))
    [ $_ph2 -lt 10 ] && _ph2=0$_ph2; [ $_pm2 -lt 10 ] && _pm2=0$_pm2; [ $_ps2 -lt 10 ] && _ps2=0$_ps2
    _ptm=$_ph2:$_pm2:$_ps2 ;;
  esac
  _pup=-; [ -n "$_pe" ] && _pup=$((_pe / 100))
  # PF-5 리뷰 M1: 서비스 시작 뒤 첫 줄에만 Wi-Fi 줄 고르기 결과를 붙인다(wm=장치 줄을 찾았는가 0|1, wn=그 줄의 칸 수).
  # 차에서 Wi-Fi 칸이 또 비면 어디서 어긋나는지 이 두 값으로 가른다
  _pwd=; [ -z "$PF_WD" ] && { _pwd=" wm=$_wm wn=$_wn"; PF_WD=1; }
  # 1.8.0 PF-2: 단계별 시간. 셋 다 숫자이고 나머지가 0 이상일 때만 나머지를 낸다
  _ptr=-
  case "$_tk$PF_TW$PF_TA" in ''|*[!0-9]*) ;; *) [ $((_tk - PF_TW - PF_TA)) -ge 0 ] && _ptr=$((_tk - PF_TW - PF_TA)) ;; esac
  echo "$_ptm up=$_pup load=$_ld cpu=$_cpu io=$_io svc=$_sv tick=$_tk free=$_mf cache=$_mc cp=$_pcp sta=${WSTA:-0} rx=$_rp tx=$_tp rxe=$_re rxd=$_rd txe=$_te txd=$_td udpe=$_ue udpb=$_ub retr=$_rt tin=$_ti ofo=$_xo dsold=$_xd dsofo=$_xf dbg=$_pdb tick_wifi=${PF_TW:--} tick_aa=${PF_TA:--} tick_rest=$_ptr$_pwd$_pst" 2>/dev/null >> $PERF
  PF_N=$((${PF_N:-0} + 1))
  if [ $PF_N -ge $PERF_MAX ]; then
    $BB mv -f $PERF $PERF.1 2>/dev/null || : > $PERF
    PF_N=0
  fi
  return 0
}

# 30초마다 한 번: 잠금을 지키고(Wi-Fi 서비스가 설정 파일을 새로 만들었으면 다시 잠금), wpa_supplicant가 다시 떴으면
# 멈춘다. 연달아 SUPP_MAX번을 넘으면 잠금이 듣지 않는 것이라 한 번 알린다($BK/wifilock.told).
ap_tick() {
  # 바꿀 때만 로그를 남긴다(Wi-Fi 서비스가 파일을 다시 만들어 다시 잠근 일을 기록으로 남기려고)
  # DG-12: 동글 사용이 켜진 부팅은 내장 Wi-Fi를 잠그지 않는다
  dg_builtin_off || wifi_lock
  # 리뷰 중간 1: 동글 길에서는 순정 Wi-Fi(wpa_supplicant)와 다투지 않는다(잠그지도 멈추지도 않음)
  if ! dg_builtin_off && running wpa_supplicant; then
    log_cap SUPP_LOGS "wpa_supplicant가 다시 켜져서 멈춤" "wpa_supplicant가 자꾸 다시 켜짐"
    $BB killall wpa_supplicant 2>/dev/null
    ns=$((ns+1))
    if [ $ns -gt $SUPP_MAX ] && [ ! -f $BK/wifilock.told ]; then
      $BB mkdir -p $BK; : > $BK/wifilock.told
      log "Wi-Fi 잠금이 듣지 않음: wpa_supplicant가 ${SUPP_MAX}번 넘게 이어서 다시 뜸"
      notice "Korea Projection: 무선 프로젝션 핫스팟이 자꾸 끊깁니다. USB를 꽂고 상태 화면의 [제보 파일 만들기]를 눌러 보내 주세요."
    fi
  else
    ns=0; SUPP_LOGS=0
  fi
  return 0
}

# --- 설치 진행 기록 (1.5.5): 상태 화면 앱이 1초마다 읽어 진행 막대로 보여 준다 ---
# key=value 줄, 누구나 읽을 수 있게(644). 비밀값 없음. printf는 busybox로만 있다(셸·toolbox에 없음).
#   pct: 0~100, state: run(진행 중)|done(준비됨)|reboot(재부팅 필요)|fail(실패), stage: 지금 단계(한국어),
#   start: 이번 진행을 시작한 시각(초), t: 마지막으로 쓴 시각(초), boot: 이번 부팅 id(앱이 지난 부팅 기록을 가려낸다)
PROG=${PROG:-/data/local/tmp/korea-projection-progress.txt}
PSTART=${PSTART:-$(date +%s 2>/dev/null)}
# 1.7.3(U-7): 진행 중(run)이면 step=<단계>/<전체>도 쓴다(앱이 "단계 N/M"로 보임). 단계는 진행률로 정한다:
#   1 시작·HMG-API 준비 기다림(3·5~25) · 2 HMG-API·지도 확인(27·30) · 3 이 차 지도 만들기·확인(40·55) · 4 Wi-Fi 칩(62)
#   · 5 무선 모드 설치·적용·새 판·마무리(70·85·95). 차에 따라 건너뛰는 단계가 있다(지도가 있는 차는 3을 건너뜀).
# 모드를 새 판으로 바꾸기만 하는 경로(MOD_WAIT=1)는 3단계로 센다(기다림 1 → 확인 2 → 바꾸기·마무리 3, 리뷰 L5: 5/5로 뛰지 않게).
# 진행률을 바꾸면 여기도 같이 고친다. 옛 앱은 모르는 줄을 무시한다.
prog_step() {
  [ "$1" = run ] || return 0
  case "$2" in ''|*[!0-9]*) return 0 ;; esac
  if [ "$MOD_WAIT" = 1 ]; then
    if [ "$2" -le 25 ]; then echo 1/3; elif [ "$2" -le 30 ]; then echo 2/3; else echo 3/3; fi
    return 0
  fi
  if [ "$2" -le 25 ]; then echo 1/5; elif [ "$2" -le 30 ]; then echo 2/5; elif [ "$2" -le 55 ]; then echo 3/5
  elif [ "$2" -le 62 ]; then echo 4/5; else echo 5/5; fi
}
# 1.7.3(리뷰 L6): 부팅 뒤 초. 진행 기록에 시작(ust)·지금(ut)을 같이 써서 앱이 시계가 바뀌어도 경과를 바르게 잰다
prog_up() { $BB awk '{ print int($1) }' ${UPTIME:-/proc/uptime} 2>/dev/null; }
PUSTART=${PUSTART:-$(prog_up)}
prog() {
  ( umask 022
    $BB printf 'pct=%s\nstate=%s\nstage=%s\nstart=%s\nt=%s\nboot=%s\nstep=%s\nust=%s\nut=%s\n' "$1" "$2" "$3" "$PSTART" "$(date +%s)" \
      "${BID:-$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)}" "$(prog_step "$2" "$1")" "$PUSTART" "$(prog_up)" > $PROG.tmp \
      && $BB chmod 644 $PROG.tmp && $BB mv -f $PROG.tmp $PROG ) 2>/dev/null
  # 베타 3(B3-3·B2-6): 설치 실패도 디버그 자동 켜기 B(변조·해외 차처럼 계속 이어지는 것은 빼고)
  [ "$2" = fail ] && case "$3" in "$TAMPER_MSG"|"지원하지 않는 차"*) ;; *) dbg_trig b b_red ;; esac
  # 베타 3(B3-4): 진행 상태(run·reboot·fail·done)가 바뀌면 상태 화면 파일도
  [ "$2" = "$PROG_LST" ] || { PROG_LST=$2; st_push; }
  return 0
}
# 이번 부팅에 "재부팅 필요"나 "실패"를 이미 썼는가
prog_final_this_boot() {
  $BB grep -q -E '^state=(reboot|fail)$' $PROG 2>/dev/null \
    && [ "$($BB awk -F= '$1 == "boot" { print $2 }' $PROG 2>/dev/null)" = "${BID:-$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)}" ]
}
# 진행 기록이 지금 "진행 중"인가(설정 중인 fix_perms가 쓰는 중)
fix_busy() { $BB grep -q '^state=run$' $PROG 2>/dev/null; }
# 무선 설정이 이미 끝난 상태인가: 무선 모드가 있고 켜져 있고 적용됐다(persist.sys.iap2.wifi=t)
setup_done() {
  [ -f $HMGDATA/mods/$MOD_ID/mod.json ] && [ ! -f $HMGDATA/mods/$MOD_ID/.disabled ] \
    && [ "$(getprop persist.sys.iap2.wifi 2>/dev/null)" = t ]
}

# 서비스가 끝날 때(TERM)와 패키지를 지울 때만: 핫스팟에 더해 뒤에서 도는 권한 파일 확인(fix_perms)도 멈춘다.
# 시작할 때 부르는 stop_ap는 이것을 건드리지 않는다 (방금 띄운 확인 작업을 죽이지 않게)
stop_all() {
  # 리뷰 L3: 끝나는 중에는 디버그 자동 켜기가 logcat 파이프를 새로 띄우지 않게 요청만 남긴다(다음 서비스 시작이 받음)
  DBG_SVC=0
  # 정식 2차 리뷰 L3: 앱 응답 파일(값이 들어 있을 수 있음)을 남기지 않는다
  apcfg_rm
  stop_ap
  # 베타 2 뽑기 기록(리뷰 중간 5): 이번 부팅 감시를 멈추고 그렇게 적는다(다음 부팅이 재부팅으로 오판하지 않게)
  _dgw1=; _dgw2=; [ -f $W/dgpull.pid ] && read _dgw1 _dgw2 < $W/dgpull.pid 2>/dev/null
  if [ -n "$_dgw1" ] && [ "$_dgw2" = "$BID" ] && kill -0 $_dgw1 2>/dev/null; then kill $_dgw1 2>/dev/null; dg_up_s; dg_beat "${BID:-none} stop 0 $_dgu -"; fi
  rm -f $W/dgpull.pid
  # 시험판 4: 단계 기록도 멈추고 끝 표시를 남긴다(다음 부팅이 "기록 중 끊김"으로 오판하지 않게)
  _dgw1=; _dgw2=; [ -f $W/dgstep.pid ] && read _dgw1 _dgw2 < $W/dgstep.pid 2>/dev/null
  if [ -n "$_dgw1" ] && [ "$_dgw2" = "$BID" ] && kill -0 $_dgw1 2>/dev/null; then
    kill $_dgw1 2>/dev/null; dg_up_s; echo "$_dgu M end stop" 2>/dev/null >> $DG_STEPF; rm -f $W/dgstep.on; $BB sync
  fi
  rm -f $W/dgstep.pid
  # 1.8.0 정식(P3·P4): 계속 받던 AA 로그(logcat)도 끈다
  aalog_kill
  if fix_running; then set -- $(cat $W/fix.pid); kill $1 2>/dev/null; fi
  rm -f $W/fix.pid
  # 설치 중에 서비스가 멈추면 진행 기록이 "진행 중"으로 남지 않게(설치 작업을 멈춘 뒤에 쓴다)
  # 리뷰 L2: softap.conf를 다시 읽는 중(설치 작업이 아님)이면 "설치가 멈췄습니다"로 쓰지 않는다
  fix_busy && ! $BB awk -v a="stage=$SOFTAP_RETRY_MSG" '$0 == a { f = 1 } END { exit !f }' $PROG 2>/dev/null && prog 100 fail "설치가 중간에 멈췄습니다. 재부팅하면 다시 진행합니다."
  # 리뷰 M2·M3: 다시 붙이기 도중이면 그 단계를 되돌리고(authorized 1, bind, 포트 전원 켬) 화면 문구가 굳지 않게 실패로 바꾼다
  dg_ladder_restore stop
  return 0
}

# log.pid의 프로세스가 우리 로그 파이프의 마지막 단계일 때만 죽인다. 마지막 단계가 죽으면 앞의 awk·grep·logcat은 SIGPIPE로 끝난다.
# log.pid에는 logstart의 $!가 들어간다: 뒤에서 돌린 파이프라인의 $!는 마지막 명령($_u: "$BB uniq -c -f 2" 또는 "$BB grep .")의 pid다.
# 1.7.2(P-16): 예전에는 /proc/<pid>/cmdline을 grep으로 봤는데, cmdline은 인자를 NUL로 나누고 busybox 1.8.1 grep은 첫 NUL에서
# 줄을 끊는다. 첫 인자가 "/system/bin/busybox"라 logcat|grep|uniq에 맞지 않아 로거를 멈추지 못했다(FINDINGS 2748행).
# 이제는 NUL이 없는 /proc/<pid>/stat의 이름 칸(busybox 애플릿이면 "(busybox)", toolbox면 "(grep)" 등)을 보고, pid와 함께
# 적어 둔 부팅 id가 이번 부팅과 같을 때만 죽인다(/data/local/tmp는 재부팅 뒤에도 남아 예전 pid가 다른 프로세스를 가리킬 수 있다).
# 부팅 id가 없는 예전 형식(1.7.1까지)은 죽이지 않는다(예전과 같은 결과).
# --- 1.8.0 정식(P3·P4, H-2·H-4): AA 로그를 계속 받기 ---
# 베타 2 리포트 30초 기록에서 점검 시간의 70~95%가 aa_events였다(#538 6.47초, #60 순정 AP 차 5.09초). 30초마다
# logcat -d가 로그 버퍼 전체를 다시 훑기 때문이다. 이제 logcat 하나를 뒤에 띄워 네 태그만 파일로 바로 쓰게 하고(-f, 줄마다 write라
# 블록 버퍼가 없음), 점검은 지난번 뒤의 새 줄만 읽는다. 무늬 거름(grep)과 판정 awk는 예전 그대로 점검에서 한다.
# - 정식 리뷰 M1: 받는 줄은 가리지 않은 원문(폰 이름·BT MAC이 들어갈 수 있음)이라 플래시($W)가 아닌 tmpfs(/dev, AOA 가드 기록과 같은 곳)에
#   둔다(재부팅하면 사라짐). 끌 때(aalog_kill: stop_all·preun·서비스 시작)는 받은 파일·읽은 곳도 지운다. 리포트·USB는 이 파일을 모으지 않는다
# - 크기: logcat이 AAS_KB(128KB)마다 받는 파일 → .1로 돌린다(-r, -n 1). 최대 약 256KB(메모리)
# - 읽은 곳: <받는 파일>.pos "<부팅 id> <읽은 줄 수> <첫 줄 시각>". 첫 줄 시각이 바뀌었거나 줄 수가 줄었으면 돌린 것: .1의 나머지부터 읽는다
# - 끝나는 조건: stop_all(TERM·업데이트·삭제)에서 끔. 같은 부팅에 서비스가 다시 시작하면 이전 것을 끄고 새로 띄움(횟수에 넣지 않음).
#   띄운 logcat이 죽었으면 다시 띄우되 한 부팅 AAS_MAX(5)번까지, 그 뒤는 이 부팅 예전 방식(logcat -d, 아래 aa_src).
#   끌 때는 pid가 이번 부팅 것이고(부팅 id를 모르면 끄지 않음) 이름이 logcat이고 좀비가 아닐 때만
# - 이 logcat은 로그를 읽기만 한다. 핫스팟·DHCP·카플레이 판단과 상관없다(죽어도 무선 프로젝션은 그대로, 진단 기록만 늦음)
AASTREAM=${AASTREAM:-/dev/.kp-aa.stream}
AAS_KB=${AAS_KB:-128}
AAS_MAX=${AAS_MAX:-5}
# 니로 정식 1차(11-25) 안전망: 받는 logcat이 살아 있는데 받는 파일이 AAS_NOF_MAX회차 이어서 없으면(logcat은 시작할 때 파일을 만든다)
# 그 logcat을 끄고 이 부팅은 예전 방식으로 읽는다. 끝나는 조건: $W/aa.old에 이 부팅 id가 적히면 aalog_start가 이 부팅에 다시 띄우지 않는다
# (서비스가 다시 시작해도 aa.old는 지우지 않음 → 띄움·끔을 되풀이하지 않음). 까닭은 $W/aa.why("<부팅 id> nofile|died", 리포트 칸)
AAS_NOF_MAX=${AAS_NOF_MAX:-2}
# 정식 F7(beta3-reports 12-1·12-4, 화면 멈춤 조사용 기록): 순정 카플레이 앱(CarPlay_: DipoActivity·DipoService)도 같은 logcat이 받는다(새 프로세스 없음)
AAS_TAGS='AAProjection:V PhoneProjection:V HMG-API:V TccCarPlay:V CarPlay_:V'
# 부팅 id(서비스는 BID, preun 등 BID가 없는 셸은 boot_id 파일). 계속 받기의 모든 기록이 같은 값을 쓴다
aa_bid() { _aabid=${BID:-$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)}; _aabid=${_aabid:-none}; }
# 이번 부팅에 띄운 logcat이 살아 있는가(이름 logcat, 상태가 좀비 Z가 아님). 부팅 id를 모르면(none) 남의 것일 수 있어 아니라고 본다
aalog_alive() {
  _aap=; _aab=; [ -f $W/aalog.pid ] && read _aap _aab < $W/aalog.pid 2>/dev/null
  case "$_aap" in ''|*[!0-9]*) return 1 ;; esac
  aa_bid; [ "$_aabid" != none ] && [ "$_aab" = "$_aabid" ] && [ -r ${PROC:-/proc}/$_aap/stat ] || return 1
  _aak3=; read _aak1 _aak2 _aak3 _aakr < ${PROC:-/proc}/$_aap/stat 2>/dev/null
  [ "$_aak2" = "(logcat)" ] && [ "$_aak3" != Z ]
}
aalog_kill() {
  aalog_alive && kill $_aap 2>/dev/null
  rm -f $W/aalog.pid $AASTREAM $AASTREAM.1 $AASTREAM.pos $AASTREAM.pos.tmp
}
# 서비스가 시작할 때 한 번: 같은 부팅의 이전 것을 끄고 받은 파일·읽은 곳을 지운다(다시 띄운 횟수는 부팅 단위로 남김)
aalog_reset() { aalog_kill; }
# 0: 받는 중(또는 지금 띄움), 1: 이 부팅은 예전 방식
aalog_start() {
  aa_bid
  _aao=; [ -f $W/aa.old ] && read _aao < $W/aa.old 2>/dev/null
  [ "$_aao" = "$_aabid" ] && return 1
  aalog_alive && return 0
  # 정식 리뷰 L3: 다시 띄운 횟수는 "이번 부팅에 띄운 logcat이 죽은" 때만 센다(pid 기록이 남아 있음). 서비스 시작(aalog_reset이 기록을 지움)은 세지 않는다
  _aasb=; _aasn=0; [ -f $W/aa.starts ] && read _aasb _aasn < $W/aa.starts 2>/dev/null
  [ "$_aasb" = "$_aabid" ] || _aasn=0
  case "$_aasn" in ''|*[!0-9]*) _aasn=0 ;; esac
  _aadied=0; [ -f $W/aalog.pid ] && _aadied=1
  if [ $_aadied = 1 ]; then
    if [ $_aasn -ge $AAS_MAX ]; then
      echo "$_aabid" 2>/dev/null > $W/aa.old; echo "$_aabid died" 2>/dev/null > $W/aa.why
      log "AA 기록: 계속 받던 logcat이 ${AAS_MAX}번 죽어 이 부팅은 예전 방식(30초마다 logcat -d)으로 읽음"
      rm -f $W/aalog.pid
      return 1
    fi
    _aasn=$((_aasn + 1)); echo "$_aabid $_aasn" 2>/dev/null > $W/aa.starts
    log "AA 기록: 계속 받던 logcat이 죽어 다시 띄움($_aasn/$AAS_MAX)"
  fi
  rm -f $W/aalog.pid
  # 니로 정식 1차(11-25): 내비 logcat(bionic getopt)은 인자 순서를 바꾸지 않아 첫 태그 필터에서 옵션 읽기를 멈춘다.
  # 옵션(-f·-r·-n)은 반드시 -s와 태그 필터 앞에 둔다(뒤에 두면 태그로 읽혀 받는 파일이 생기지 않았다).
  # 순정 logcat의 옵션 문자열은 "cdt:gsQf:r::n:v:b:B"라 -r의 값은 붙여 써야 받는다(-r128). 띄어 쓰면 "128"에서 옵션 읽기가 멈춘다
  logcat -v time -f $AASTREAM -r$AAS_KB -n 1 -s $AAS_TAGS </dev/null >/dev/null 2>&1 &
  _aanp=$!
  # 정식 리뷰 L4: pid를 남기지 못하면(공간 없음 등) 끌 수 없으므로 방금 띄운 것을 끄고 이번 점검은 예전 방식
  echo "$_aanp $_aabid" 2>/dev/null > $W/aalog.pid
  _aachk=; [ -f $W/aalog.pid ] && read _aachk _aachx < $W/aalog.pid 2>/dev/null
  if [ "$_aachk" != "$_aanp" ]; then kill $_aanp 2>/dev/null; rm -f $W/aalog.pid; return 1; fi
  # 정식 리뷰 L2: 처음 띄운 회차도 읽게, logcat이 버퍼에 남은 줄을 쓸 때까지 최대 2초 기다린다
  _aaw=0; while [ $_aaw -lt 2 ] && [ ! -s $AASTREAM ]; do sleep 1 & wait $!; _aaw=$((_aaw + 1)); done
  return 0
}
# 지난번 뒤의 새 줄만 표준출력으로(돌렸으면 .1의 나머지부터). 읽은 곳을 갱신한다
aa_read_new() {
  aa_bid
  _apb=; _apn=0; _aps=; [ -f $AASTREAM.pos ] && read _apb _apn _aps < $AASTREAM.pos 2>/dev/null
  [ "$_apb" = "$_aabid" ] || { _apn=0; _aps=; }
  case "$_apn" in ''|*[!0-9]*) _apn=0 ;; esac
  [ -f $AASTREAM ] || return 0
  # 첫 줄의 시각(18자, 빈칸은 _)과 줄 수만 본다(줄 내용은 남기지 않음). 정식 리뷰 L5: 빈 파일(돌린 직후)이면 읽은 곳을 그대로 둔다
  _acs=; _acn=0
  eval "$($BB awk 'NR == 1 { s = substr($0, 1, 18); gsub(/[^0-9:.-]/, "_", s) } END { print "_acs=" s "; _acn=" NR + 0 }' $AASTREAM 2>/dev/null)"
  case "$_acn" in ''|*[!0-9]*) _acn=0 ;; esac
  [ $_acn -gt 0 ] && [ -n "$_acs" ] || return 0
  if [ -n "$_aps" ] && { [ "$_acs" != "$_aps" ] || [ $_acn -lt $_apn ]; }; then
    [ -f $AASTREAM.1 ] && $BB awk -v n=$_apn 'NR > n' $AASTREAM.1 2>/dev/null
    _apn=0
  elif [ -z "$_aps" ] && [ -f $AASTREAM.1 ]; then
    # 아직 한 번도 읽지 못한 채 돌렸으면(첫 점검 전에 크게 쌓임) .1 전부부터. 서비스 시작(aalog_reset)이 .1을 지우므로 이번 받기의 것뿐
    $BB awk '1' $AASTREAM.1 2>/dev/null
  fi
  $BB awk -v n=$_apn -v b="$_aabid" -v s="$_acs" -v pf=$AASTREAM.pos.tmp 'NR > n { print } END { m = (NR > n ? NR : n); print b, m, s > pf; close(pf) }' $AASTREAM 2>/dev/null
  [ -s $AASTREAM.pos.tmp ] && $BB mv -f $AASTREAM.pos.tmp $AASTREAM.pos 2>/dev/null
  return 0
}
# aa_events가 거를 줄의 출처: 계속 받는 파일의 새 줄(AAS_USE=1), 안 되면 예전처럼 로그 버퍼 전체(logcat -d).
# AAS_USE는 aa_events가 파이프 밖에서 정한다(aalog_start의 로그가 파이프로 들어가 걸러지지 않고 ap.log에 남게)
# AAS_ON=0이면 계속 받기를 쓰지 않고 예전 방식만(PC 시험의 옛 기대값용, 차에서는 늘 1)
AAS_ON=${AAS_ON:-1}
aa_src() {
  if [ "$AAS_USE" = 1 ]; then aa_read_new; else logcat -d -v time -s $AAS_TAGS 2>/dev/null; fi
}
killlog() {
  _p=; _pb=
  [ -f $W/log.pid ] && read _p _pb < $W/log.pid
  case "$_p" in ''|*[!0-9]*) _p= ;; esac
  if [ -n "$_p" ] && [ -n "$_pb" ] && [ "$_pb" = "${BID:-$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)}" ] && [ -r $PROC/$_p/stat ]; then
    read _k1 _k2 _kr < $PROC/$_p/stat
    case "$_k2" in "(busybox)"|"(uniq)"|"(grep)") kill $_p 2>/dev/null ;; esac
    # 정식 리뷰 L6: 앞의 logcat·awk도 함께 끈다(태그로 거른 logcat은 다음 줄이 늦게 와 SIGPIPE로 바로 끝나지 않음).
    # 명령줄에 디버그 파이프에만 있는 낱말이 든 것만(logcat: BluetoothServerSocket:V, awk: 비밀 줄 무늬). [B]·[p]는 grep 자신을 빼려는 것
    for _kf in $($BB grep -l "[B]luetoothServerSocket:V" $PROC/[0-9]*/cmdline 2>/dev/null) $($BB grep -l "[p]assphrase|password" $PROC/[0-9]*/cmdline 2>/dev/null); do
      _kq=${_kf%/cmdline}; _kq=${_kq##*/}; case "$_kq" in ''|*[!0-9]*) ;; *) kill $_kq 2>/dev/null ;; esac
    done
  fi
  rm -f $W/log.pid
}
# --- 1.7.2(P-15): ap.log 크기 제한 ---
# ap.log는 NEMESIS svcmgr가 이 스크립트의 출력을 받아 쓰는 파일이다(/data/nemesis/logs/<id>/<name>.log, 재부팅해도 남음).
# 크기 제한이 없어 aa_events·wifi_events 줄이 계속 쌓였다. APMAX(512KB)를 넘으면 ap.log.1로 복사하고 ap.log를 비운다(최대 2개).
# 비워도 이어서 쓰려면 출력이 덧붙이기(O_APPEND)로 열려 있어야 한다. 그래서 시작할 때 표준출력이 정말 ap.log 파일이면 그 파일을
# 덧붙이기로 다시 연다(aplog_open). 표준출력이 파일이 아니면(파이프 등) 밀지 않는다(APROT=0, 예전과 같음).
APLOG=${APLOG:-/data/nemesis/logs/korea.projection/ap.log}
APMAX=${APMAX:-524288}
APROT=0
# fd $1이 가리키는 경로(/proc/<pid>/fd). readlink가 없으면 ls -l의 마지막 칸
fd_target() {
  $BB readlink $PROC/$$/fd/$1 2>/dev/null || ls -l $PROC/$$/fd/$1 2>/dev/null | $BB awk '{ print $NF }'
}
aplog_open() {
  [ "$(fd_target 1)" = "$APLOG" ] || return 0
  if [ "$(fd_target 2)" = "$APLOG" ]; then exec >> "$APLOG" 2>&1; else exec >> "$APLOG"; fi
  APROT=1
}
aplog_rotate() {
  [ "$APROT" = 1 ] || return 0
  _asz=$( { $BB wc -c < $APLOG; } 2>/dev/null); _asz=$(echo $_asz)
  case "$_asz" in ''|*[!0-9]*) return 0 ;; esac
  [ $_asz -lt $APMAX ] && return 0
  # 복사가 실패해도(공간 부족 등) 비운다: 그러지 않으면 ap.log가 끝없이 커진다
  $BB cp -f $APLOG $APLOG.1 2>/dev/null || $BB rm -f $APLOG.1
  : > $APLOG
  log "ap.log가 ${APMAX}바이트를 넘어 앞부분을 ap.log.1로 옮김"
}
# P-17: 이번 부팅 첫 시작 줄(리포트 "연결 기록" 칸은 이 줄 뒤만 보인다). 바꾸면 status.sh도 같이 바뀐다(같은 변수).
SVC_MARK="서비스 시작: 이번 부팅 처음"

# $W/debug가 있을 때만: 카플레이 관련 logcat을 $W/cp.log에 남긴다(폰 이름이 들어가므로 기본은 꺼짐).
# 이 헤드유닛의 logcat은 -f와 함께 태그 필터를 무시하므로 grep으로 거른다.
# 길안내 중에는 분당 약 500KB가 쌓여(2026-11-06 run3) 쓸모없는 줄을 버린다:
#  - iAPSendMessage의 "done with"와 "Command Received": 보낸 줄마다 따라붙는 확인 줄
#  - getCANSTatus = true(ClusterService)와 getCANStatus(NavigationCluster): 몇 초마다 같은 줄
#  - updateTPCrossroadName(ClusterService): 교차로 이름. 지나간 경로가 드러나고, 이름이 번갈아 나와 uniq로
#    줄지도 않는다(2026-11-06 운행 46분에 1만 줄, 로그 크기의 약 15%).
# 보낸 줄 "iAPSendMessage() : data(…) size(N)"은 남긴다: 정상 세션에서는 차 위치(크기 57/84/100)가
# 1초마다 나가므로, 위치가 아이폰에 가는지 이것으로 본다(2026-11-06, 1.4.2는 이 줄까지 버렸다).
# iAP2(순정 iAP2 라이브러리)는 아이폰의 위치 요청(LocationInformationStart)을 남긴다. 분당 수십 줄 이하.
# 같은 줄이 연달아 나오면(pcm_write failed가 1초에 수천 줄) uniq -c가 한 줄과 횟수로 줄인다
# (앞의 날짜·시간 두 칸은 비교하지 않는다). 그래서 각 줄 앞에 반복 횟수가 붙는다.
# 1.5.6: 안드로이드 오토 쪽(GPM·GalReceiver로 시작하는 태그)도 남긴다(로드맵 1.5.6 2번, 1.5.7의 근거 자료)
# 1.7.0: 폰 프로젝션 전체(안드로이드 오토 AAProjection, 무선 폰 프로젝션 PhoneProjection, 블루투스 RFCOMM·SPP, Wi-Fi P2P).
# 예전 GPM*·GalReceiver*는 실제 태그가 아니라 아무것도 잡지 못했다(니로 logcat: AA 태그는 AAProjection).
TAGS=' [VDIWEF]/(hostapd|dnsmasq|HMG-API|iAP2|Iap2Service|CarPlay_|TccCarPlay|WifiService|BTCMService|NavigationCluster|ClusterService|AAProjection|PhoneProjection|WifiP2pService|BluetoothSocket|BluetoothServerSocket|bt-rfcomm|HfDeviceBTCMSppApi) *\('
DROP='iAPSendMessage\(\) : done with \(0x00\)|iAPSendMessage Command Received|getCANSTatus = true|\): getCANStatus$|updateTPCrossroadName'
# 1.8.0 정식(P6, H-3): 디버그 로그 파이프를 6개 프로세스(logcat 전체 → grep TAGS → grep -v DROP → grep -v 비밀 → awk 가리기 → uniq)에서
# 3개(logcat -s 태그 → awk → uniq)로 줄인다. TAGS 정규식은 태그 바로 뒤에 빈칸과 "("만 받으므로 아래 이름은 정확한 태그다
# (니로·차주 디버그 로그 37개에서 실제로 걸린 태그 17개 + BluetoothServerSocket, CarPlay_도 그 이름 그대로인 태그. pkg.md "정식 P6").
LOGTAGS='hostapd dnsmasq HMG-API iAP2 Iap2Service CarPlay_ TccCarPlay WifiService BTCMService NavigationCluster ClusterService AAProjection PhoneProjection WifiP2pService BluetoothSocket BluetoothServerSocket bt-rfcomm HfDeviceBTCMSppApi'
# 버리기(DROP·비밀 줄)가 가리기(KPMASK)보다 먼저다. 비밀 줄은 예전 grep -v -i -E와 같은 무늬를 소문자로 바꾼 줄에 견준다.
# $1이 있으면 DROP 규칙을 프로그램 안 정규식 글자로 넣는다(-v로 넘기면 \( 같은 이스케이프가 바뀌어 맞지 않음. DROP에는 /가 없다)
# 정식 리뷰 L1: 결과는 변수 _lfp에 둔다(echo로 넘기면 차의 mksh echo가 KPMASK의 백슬래시를 바꿀 수 있음)
logfilter_prog() {
  _lfp='{ _s = tolower($0); if (_s ~ /ssid|psk *[=:]|passphrase|password|bssid|key=/) next }'
  [ -n "$1" ] && _lfp="{ if (\$0 ~ /$1/) next } $_lfp"
  _lfp="$_lfp
$KPMASK"
}
# --- 1.7.0 로그 가리기(KPMASK): 리포트의 폰 프로젝션 기록과 디버그 로그(cp.log)에 쓴다 ---
# AA 진단 USB(usb-aadiag/NEMESIS.sh MASK, 니로 busybox 1.8.1 awk에서 2026-11-08 동작 확인)를 옮기고, 한 낱말 폰 이름 규칙(nmk)을 더했다.
#  - Wi-Fi 이름·비밀번호 낱말이 나오면 그 뒤를 지운다("BSSID" 낱말은 남김: "Failed to find host IP/BSSID"가 원인 자료)
#  - 이름(name=, Name :, Device:, DIRECT- 등)·괄호 안 이름(brk, nmk)을 가린다(#47 사고: PhoneProjection 줄의 폰 이름)
#  - MAC, IP(192.168.43.1·0.0.0.0·127.0.0.1은 남김), IPv6, VIN 꼴, 휴대전화 번호
KPMASK='
function keepip(s) { return s == "192.168.43.1" || s == "0.0.0.0" || s == "127.0.0.1" }
function keepmac(s) { s = tolower(s); return s ~ /^[0:]+$/ || s ~ /^[f:]+$/ }
function ips(l,   o, m) {
  o = ""
  while (match(l, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {
    m = substr(l, RSTART, RLENGTH)
    o = o substr(l, 1, RSTART - 1) (keepip(m) ? m : "x.x.x.x")
    l = substr(l, RSTART + RLENGTH)
  }
  return o l
}
function macs(l,   o, m) {
  o = ""
  while (match(l, H ":" H ":" H ":" H ":" H ":" H)) {
    m = substr(l, RSTART, RLENGTH)
    o = o substr(l, 1, RSTART - 1) (keepmac(m) ? m : "xx:xx:xx:xx:xx:xx")
    l = substr(l, RSTART + RLENGTH)
  }
  return o l
}
# logcat 줄의 괄호·대괄호 안이 이름처럼 보이면 가린다: 한글 등 ASCII가 아닌 글자가 있거나, 띄어쓰기와 영문자가 함께 있을 때.
# K7(YGPE) 제보(2026-11-07)에서 PhoneProjection이 "addDeviceStatusInfo (<폰 이름>)", "[<폰 이름>]" 꼴로 이름을 남겼다.
# "[ b ]", "( 1610)"(pid), "[WPA2-PSK-CCMP]"처럼 띄어쓰기가 없는 한 낱말은 남는다.
function brk(l,   o, m, c, n) {
  o = ""
  while (match(l, /[[(][^][()]*[])]/)) {
    m = substr(l, RSTART, RLENGTH); n = RLENGTH
    c = substr(m, 2, n - 2); gsub(/^ +/, "", c); gsub(/ +$/, "", c)
    if (c ~ /[^ -~]/ || (c ~ / / && c ~ /[A-Za-z]/)) m = substr(m, 1, 1) "가림: 이름" substr(m, n, 1)
    o = o substr(l, 1, RSTART - 1) m
    l = substr(l, RSTART + n)
  }
  return o l
}
# 1.7.0: 좌표 꼴(정수부 1~3자리, 소수점 아래 4자리 이상, 앞에 숫자·점·영문자가 없음)만 가린다(리뷰 L1: V039.001.260902 같은
# 펌웨어 문자열은 앞에 점이 있어 남는다)
function crd(l,   o, m, p) {
  o = ""
  while (match(l, /-?[0-9][0-9]?[0-9]?\.[0-9][0-9][0-9][0-9][0-9]*/)) {
    m = substr(l, RSTART, RLENGTH); p = RSTART > 1 ? substr(l, RSTART - 1, 1) : ""
    # 커널 시각([   12.345678])은 좌표가 아니다(리뷰 L2: wlan0 없음 기록의 dmesg)
    o = o substr(l, 1, RSTART - 1) (p ~ /[0-9.A-Za-z]/ || (o substr(l, 1, RSTART - 1)) ~ /\[ *$/ ? m : "[가림: 좌표]")
    l = substr(l, RSTART + RLENGTH)
  }
  return o l
}
# 1.7.0: 폰 이름이 들어가는 메서드 줄(addDeviceStatusInfo (<이름>), …StatusUpdate [<이름>], connectivityConnectPP …[<이름>])은
# 괄호 안이 한 낱말(ASCII)이어도 가린다. "[ b ]"처럼 앞뒤가 띄어진 클래스 표시와 숫자만 있는 것([1], (4))은 남긴다.
function nmk(l,   o, m, c, n) {
  o = ""
  while (match(l, /[[(][^][()]*[])]/)) {
    m = substr(l, RSTART, RLENGTH); n = RLENGTH
    c = substr(m, 2, n - 2)
    # true·false·null은 이름이 아니다(진단 값: Init[false], Auto[true])
    if (c ~ /[A-Za-z]/ && c !~ /^ .* $/ && c !~ /^ *$/ && c !~ /^(true|false|null|TRUE|FALSE|NULL)$/) m = substr(m, 1, 1) "가림: 이름" substr(m, n, 1)
    o = o substr(l, 1, RSTART - 1) m
    l = substr(l, RSTART + n)
  }
  return o l
}
# 1.7.1: 따옴표 안 문자열은 가린다(Wi-Fi 서비스 줄의 extra: "<SSID>" 등, wlan0 진단 USB와 같은 규칙).
# "/"로 시작하는 경로와 빈 문자열("")은 남긴다(원인 자료).
function qmask(l,   o, m) {
  o = ""
  while (match(l, /"[^"]*"/)) {
    m = substr(l, RSTART, RLENGTH)
    o = o substr(l, 1, RSTART - 1) (m ~ /^"(\/|")/ ? m : "\"[가림]\"")
    l = substr(l, RSTART + RLENGTH)
  }
  return o l
}
# 1.7.1: 커널 명령줄의 기기 고유값(btaddr·wifimac·serialno 등)은 값 전체를 가린다(#55: 구분자 없는 BT MAC이 그대로 나감).
# 리포트의 wlan0 없음 기록(dmesg)에 이 줄이 들어갈 수 있다.
function kvid(l,   o, k) {
  o = ""
  while (match(l, "(btaddr|bt_addr|wifimac|wifi_mac|macaddr|mac_addr|serialno|serial_no)=[^ \t]+")) {
    k = substr(l, RSTART, RLENGTH); sub(/=.*/, "=", k)
    o = o substr(l, 1, RSTART - 1) k "[가림]"
    l = substr(l, RSTART + RLENGTH)
  }
  return o l
}
# 1.7.1: 구분자 없는 12자리 MAC. 앞뒤가 16진수가 아니고 숫자와 A~F가 함께 있을 때만 가린다(wlan0 진단 USB와 같음)
function mac12(l,   o, m, p, a, b) {
  o = ""
  while (match(l, H H H H H H)) {
    m = substr(l, RSTART, RLENGTH); p = RSTART
    a = (p > 1) ? substr(l, p - 1, 1) : substr(o, length(o), 1); b = substr(l, p + 12, 1)
    if (a ~ /[0-9A-Fa-f]/ || b ~ /[0-9A-Fa-f]/ || m !~ /[0-9]/ || m !~ /[A-Fa-f]/) {
      o = o substr(l, 1, p); l = substr(l, p + 1); continue
    }
    o = o substr(l, 1, p - 1) "xxxxxxxxxxxx"
    l = substr(l, p + 12)
  }
  return o l
}
BEGIN {
  H = "[0-9A-Fa-f][0-9A-Fa-f]"
  V = ""; for (i = 0; i < 17; i++) V = V "[A-HJ-NPR-Z0-9]"
}
{
  l = kvid($0)
  if (l ~ / [VDIWEF]\/[^ ]/) l = brk(l)
  l = qmask(l)
  if (l ~ / [VDIWEF]\/(BluetoothHfDevice|HfDevice[A-Za-z]*|BTCM[A-Za-z]*|CallManager|BluetoothPbap[A-Za-z]*|Pbap[A-Za-z]*|Navi|NaviPopupService|NavigationCluster|ClusterService|ClusterManager) *\(/) {
    gsub(/"[^"]*"/, "\"[가림]\"", l)
    gsub(/[^ -~]+/, "[가림]", l)
    gsub(/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*/, "[가림: 번호]", l)
    if (match(l, /(FN|N|TEL|EMAIL)[;:][^ ]*/)) l = substr(l, 1, RSTART - 1) "[가림: 연락처]"
  }
  if (l ~ /(DeviceStatusInfo|StatusUpdate|DeviceInfoAdd|ConnectPP|connectPP|DeviceAddress|[Dd]eviceName|Explorer : \[|Service : \[|[Ss]tatus \[)/) l = nmk(l)
  if (match(l, /DeviceStatusInfo: */)) l = substr(l, 1, RSTART + RLENGTH - 1) "[이하 가림: 이름]"
  if (match(l, "^[ \t]*" H ":" H ":" H ":" H ":" H ":" H "[ \t]+[0-9]+[ \t]+-?[0-9]+")) l = "[가림: 주변 Wi-Fi 목록 줄]"
  t = tolower(l); gsub(/bssid/, "b_sid", t)
  if (match(t, /ssid|psk *[=:]|connectivitypsk|presharedkey|passphrase|password|passwd|wpa_key|key *[=:]|secret/))
    l = substr(l, 1, RSTART - 1) "[이하 가림: Wi-Fi 정보]"
  t = tolower(l); gsub(/classname/, "classnXme", t); gsub(/packagename/, "packagenXme", t); gsub(/filename/, "filenXme", t); gsub(/interfacename/, "interfacenXme", t)
  # 1.7.0: "Device info name <이름>"(Iap2Service, 니로 2026-11-08)처럼 name 뒤가 띄어쓰기뿐인 꼴도 가린다
  if (match(t, /name *[=:]|alias *[=:]|device *name|friendly *name|phone *name|remote *name|info *name +|init *name +|device *[=:]|direct-/))
    l = substr(l, 1, RSTART + RLENGTH - 1) " [이하 가림: 이름]"
  # 1.7.0 위치 모자이크(소유자 결정 2026-11-08): 줄은 남기고 위치만 가린다. 교차로·목적지·도로·주소 이름은 그 뒤를,
  # 좌표(소수점 아래 4자리 넘는 수, lat·lon 뒤의 수)와 NMEA 문장은 그 값만 바꾼다
  t = tolower(l)
  if (match(t, /(crossroad|destination|dest|goal|waypoint|roadname|road name|address|addr|poiname|poi name|poi|목적지|경유지|주소)[a-z]*( is |\(\) *: *| *[:=] *| +)/))
    l = substr(l, 1, RSTART + RLENGTH - 1) "[가림: 위치]"
  if (match(l, /\$G[PNL][A-Z][A-Z][A-Z],/)) l = substr(l, 1, RSTART - 1) "[가림: NMEA]"
  l = crd(l)
  gsub(/([Ll]atitude|[Ll]ongitude|[Ll]at|[Ll]on|[Ll]ng)[ :=]+-?[0-9]+/, "위치값 [가림: 좌표]", l)
  # 정식(beta3-reports 8-4): 순정 블루투스 로그(BTCMService·AvrcpControllerService 등)는 휴대폰 BT 주소를 앞 3바이트만 찍는다
  # (XX:XX:XX:**:**:**). 이 반쪽 꼴도 가린다(대소문자, : 또는 - 구분). "**"가 없는 3바이트(동글 OUI 기록 등)는 건드리지 않는다
  gsub(H "[:-]" H "[:-]" H "[:-][*][*][:-][*][*][:-][*][*]", "xx:xx:xx:**:**:**", l)
  l = macs(l)
  l = mac12(l)
  l = ips(l)
  gsub(/[Ff][Ee]80:[0-9A-Fa-f:]*/, "fe80:x", l)
  gsub(/[23][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f]*:[0-9A-Fa-f:]*/, "v6:x", l)
  gsub(V, "[VIN 가림]", l)
  gsub(H "-" H "-" H "-" H "-" H "-" H, "xx-xx-xx-xx-xx-xx", l)
  gsub(/01[016789] [0-9][0-9][0-9][0-9]? [0-9][0-9][0-9][0-9]/, "01x xxxx xxxx", l)
  gsub(/\+82[- ]?1[016789][- ]?[0-9][0-9][0-9][0-9]?[- ]?[0-9][0-9][0-9][0-9]/, "+82-xx-xxxx-xxxx", l)
  gsub(/01[016789]-?[0-9][0-9][0-9][0-9]?-?[0-9][0-9][0-9][0-9]/, "01x-xxxx-xxxx", l)
  gsub(/0[2-6][0-9]?-[0-9][0-9][0-9][0-9]?-[0-9][0-9][0-9][0-9]/, "0x-xxxx-xxxx", l)
  gsub(/1[5-9][0-9][0-9]-[0-9][0-9][0-9][0-9]/, "1xxx-xxxx", l)
  print l
}'
# 보관: cp.log가 LOGMAX를 넘으면 cp.log.1~3으로 밀어 최대 4개(기본 3MB씩, 12MB)
LOGMAX=${LOGMAX:-3145728}
logstart() {
  [ -f $W/debug ] || return 0
  # 베타 3(B3-3): 이번 부팅에 이미 도는 로그 파이프가 있으면 또 띄우지 않는다(문제가 보여 켠 뒤 서비스 시작이 또 부르는 등)
  _lsp=; _lsb=; [ -f $W/log.pid ] && read _lsp _lsb < $W/log.pid 2>/dev/null
  [ -n "$_lsp" ] && [ "$_lsb" = "$(dg_kv_bid)" ] && [ -d ${PROC:-/proc}/$_lsp ] && return 0
  # busybox에 uniq가 없거나 -f를 모르면 줄이지 않고 그대로 남긴다 (로그가 아예 끊기지 않게)
  if echo x | $BB uniq -c -f 2 >/dev/null 2>&1; then _u="$BB uniq -c -f 2"; else _u="$BB grep ."; fi
  # 1.5.6: 안드로이드 오토는 폰에 Wi-Fi 이름·비밀번호를 보낸다. 그런 값이 나올 수 있는 줄은 태그와 상관없이 버린다.
  # "psk"는 값이 붙는 꼴(psk=, psk:)만 버린다: 보안 방식 줄("Auth Type : WPA2_PSK")은 원인을 찾는 데 필요하다(2026-11-07).
  # 1.7.0: 폰 이름·MAC·IP·VIN·전화번호를 가린다(KPMASK).
  # 1.8.0 정식(P6): 버리기·가리기를 awk 하나로. 띄우기 전에 돌려 본다: DROP 정규식 때문에 안 되면 DROP만 빼고(예전처럼 아무 줄도
  # 버리지 않음, 비밀 줄 버리기·가리기는 그대로), 그래도 안 되면(가리기 awk가 이 busybox에서 안 됨) 디버그 로그를 남기지 않는다
  logfilter_prog "$DROP"; _lprog=$_lfp
  if ! echo x | $BB awk "$_lprog" >/dev/null 2>&1; then
    logfilter_prog; _lprog=$_lfp
    echo "x" | $BB awk "$_lprog" >/dev/null 2>&1 || { log "디버그 로그 안 남김: 가리기(awk)가 이 busybox에서 안 됨"; return 0; }
  fi
  _lst=; for _lt in $LOGTAGS; do _lst="$_lst $_lt:V"; done
  # 출력 버퍼: awk·uniq가 파일·파이프에 쓰는 방식은 예전 파이프와 같다(uniq가 파일 쪽을 모아 쓰므로 awk에 fflush를 넣어도 빨라지지 않음)
  logcat -v time -s $_lst 2>/dev/null | $BB awk "$_lprog" | $_u >> $W/cp.log &
  # 1.7.2(P-16): pid와 부팅 id를 함께(killlog가 이번 부팅의 것인지 본다)
  echo "$! ${BID:-$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)}" > $W/log.pid
}
# --- 디버그 로그 자동 켜기 (1.8.0 X-9 → 베타 3 B3-3, 소유자 결정 11-23 "a,b 둘 다", CLAUDE.md 5장) ---
# 바뀌었을 때(A)와 문제가 보였을 때(B) 디버그 로그를 48시간 켠다. 켜진 동안 새 조건이 생기면 48시간을 다시 센다.
# 차주가 끄면(debug.off) A로는 다시 켜지 않고, B로만 하루(KST 날짜) 한 번까지 다시 켠다. 기록은 모두 $BK(업데이트에도 남음, 숫자·코드만):
#  debug.auto   "<시작 시각 epoch 또는 new> <조건 코드>" 지금 자동 구간(없으면 자동 구간 없음). 시계가 맞지 않을 때 켜면 new로 두고
#               시계가 맞은 뒤 첫 확인에서 시작 시각을 적는다(리뷰 높음 1, 부팅 직후 2016년 시계)
#  debug.boots  자동 구간 동안 서비스가 시작한 횟수(시계가 끝내 맞지 않는 차: 시작 시각이 없으면 30번, 있으면 100번에 끝). 구간마다 0부터
#  debug.off    차주가 껐다(debug_set off). 그 뒤로 A는 켜지 않음
#  debug.bday   차주가 끈 뒤 B로 마지막에 켠 날짜(YYYYMMDD). 하루 한 번 제한
#  debug.pend   post.sh가 설치·업데이트마다 남기는 "a_install"(서비스 시작이 받음)
#  debug.seen   "fw=… hmg=… nem=… mod=… car=…" A의 바뀜 비교용(내비 버전·HMG-API·NEMESIS·무선 모드 버전, 확인된 차 여부)
#  debug.why    켠 이유 마지막 8줄 "<epoch 또는 -> <부팅 뒤 초> <코드> <MM-DD_HH:MM 또는 ->"(리포트 한 줄·비공개 파일 8줄)
# 자동으로 켠 것은 $W/debug.byauto로 표시하고, 끝날 때 그것만 끈다(차주가 USB 파일·토글로 켠 것은 그대로 둔다).
# 조건 코드: a_install a_dongle a_fw a_hmg a_nem a_mod a_car / b_red b_reup b_cpdrop b_audio b_rb b_iph
DBG_AUTO_S=${DBG_AUTO_S:-172800}
DBG_AUTO_BOOTS=${DBG_AUTO_BOOTS:-30}
DBG_AUTO_BOOTS2=${DBG_AUTO_BOOTS2:-100}
# 문턱(기존 로그 근거 pkg.md "디버그 자동 켜기 A·B 설계" 5장): 10분 창
DBG_WIN=${DBG_WIN:-600}
DBG_CP_N=${DBG_CP_N:-3}
DBG_REUP_N=${DBG_REUP_N:-3}
DBG_AU_N=${DBG_AU_N:-4}
DBG_AU_1=${DBG_AU_1:-3}
# 빨강 판정 중 켤 것(운행·설정 중 실패만, 메인 결정 11-23). 계속 이어지는 빨강(변조·다른 패키지·부품 없음 등)은 매일 켜지므로 뺀다
DBG_RED=${DBG_RED:-' failed mapfail bridgeoff modhooksoff modgone wifigone nowlanfail nowlanrepeat bootguard '}
# 시계가 맞으면 _dbn에 epoch, 아니면 빈 값
dbg_now() {
  _dbn=; _dbt=$(date '+%Y %s' 2>/dev/null); _dby=${_dbt%% *}; _dbs=${_dbt#* }
  # 함께 비는 값이라 붙여 봄(date 한 번의 출력을 나눈 두 칸)
  case "$_dby$_dbs" in ''|*[!0-9]*) return 0 ;; esac
  [ "$_dby" -ge $KP_YEAR0 ] && _dbn=$_dbs
  return 0
}
dbg_why() {
  dbg_now; kp_up
  # 시각(MM-DD_HH:MM)은 시계가 맞을 때만(내비 시계, KST)
  _dbd=-; [ -n "$_dbn" ] && _dbd=$(date '+%m-%d_%H:%M' 2>/dev/null)
  { $BB tail -n 7 $BK/debug.why 2>/dev/null; echo "${_dbn:--} ${_U:--} $1 ${_dbd:--}"; } 2>/dev/null > $BK/debug.why.tmp && $BB mv -f $BK/debug.why.tmp $BK/debug.why 2>/dev/null
  return 0
}
# 켜기 입구 하나. $1 a|b, $2 코드. 같은 코드는 한 부팅에 한 번만 받는다($W/dbgtrig.<코드>에 부팅 id).
# 서비스 밖(상태 화면 감시자 등, DBG_SVC가 아님)에서는 요청 파일($W/dbgtrig.req)에 남기고 서비스 30초 점검(dbg_req_tick)이 받는다
dbg_trig() {
  case "$1" in a|b) ;; *) return 0 ;; esac
  case "$2" in ''|*[!a-z_]*) return 0 ;; esac
  if [ "$DBG_SVC" != 1 ]; then
    $BB mkdir -p $W 2>/dev/null; echo "$1 $2" 2>/dev/null >> $W/dbgtrig.req; return 0
  fi
  _dtb=$(dg_kv_bid); _dto=; [ -f $W/dbgtrig.$2 ] && read _dto < $W/dbgtrig.$2 2>/dev/null
  [ "$_dto" = "$_dtb" ] && return 0
  # 차주가 직접 켠 상태: 이유만 적고 자동 표시는 만들지 않는다(48시간이 지나도 끄지 않음)
  if [ -f $W/debug ] && [ ! -f $W/debug.byauto ]; then
    dbg_why "$2"; echo "$_dtb" 2>/dev/null > $W/dbgtrig.$2; return 0
  fi
  dbg_now
  if [ -f $BK/debug.off ]; then
    [ "$1" = a ] && return 0
    # 끈 뒤 B: 하루 한 번. 시계가 맞지 않으면 미룬다(리뷰 낮음 7: 요청 파일에 다시 넣어 30초 뒤 다시 봄, 같은 코드는 한 줄만)
    if [ -z "$_dbn" ]; then
      $BB awk -v l="$1 $2" '$0 == l { f = 1 } END { exit !f }' $W/dbgtrig.req 2>/dev/null || echo "$1 $2" 2>/dev/null >> $W/dbgtrig.req
      return 0
    fi
    _dtd=$(date '+%Y%m%d' 2>/dev/null); _dtl=; [ -f $BK/debug.bday ] && read _dtl < $BK/debug.bday 2>/dev/null
    if [ "$_dtl" = "$_dtd" ]; then echo "$_dtb" 2>/dev/null > $W/dbgtrig.$2; return 0; fi
    echo "$_dtd" 2>/dev/null > $BK/debug.bday
  fi
  { $BB mkdir -p $BK && echo "${_dbn:-new} $2" > $BK/debug.auto; } 2>/dev/null || return 0
  rm -f $BK/debug.boots $BK/debug.done
  $BB mkdir -p $W && : > $W/debug.byauto && : > $W/debug
  echo "$_dtb" 2>/dev/null > $W/dbgtrig.$2
  dbg_why "$2"
  log "디버그 로그 자동 켬($2, 48시간)"
  # 문제가 보인 그때부터 남긴다(logcat이 버퍼에 남은 몇 분 전 줄부터 씀). 이미 돌면 logstart가 건너뜀
  [ -f $W/debug ] && logstart
  st_push
  return 0
}
# 10분 창 셈. $1 이름, $2 문턱, $3 코드. 이번 부팅·창 안의 부팅 뒤 초만 남긴다($W/dbgc.<이름>)
dbg_cnt() {
  kp_up; [ -n "$_U" ] || return 0
  _dcb=$(dg_kv_bid); _dcf=$W/dbgc.$1
  { $BB awk -v b="$_dcb" -v u="$_U" -v w="$DBG_WIN" '$1 == b && u - $2 < w + 0' $_dcf 2>/dev/null; echo "$_dcb $_U"; } 2>/dev/null > $_dcf.tmp && $BB mv -f $_dcf.tmp $_dcf 2>/dev/null
  _dcn=$($BB awk 'END { print NR + 0 }' $_dcf 2>/dev/null)
  case "$_dcn" in ''|*[!0-9]*) return 0 ;; esac
  [ $_dcn -ge $2 ] && dbg_trig b $3
  return 0
}
# 서비스 밖에서 남긴 요청을 받는다(한 번에 20줄까지, a|b와 영문 소문자 코드만)
dbg_req_tick() {
  [ -s $W/dbgtrig.req ] || return 0
  $BB mv -f $W/dbgtrig.req $W/dbgtrig.work 2>/dev/null || return 0
  _drn=0
  while read -r _drk _drc _drx; do
    _drn=$((_drn + 1)); [ $_drn -le 20 ] || break
    [ -z "$_drx" ] && dbg_trig "$_drk" "$_drc"
  done < $W/dbgtrig.work
  rm -f $W/dbgtrig.work
  return 0
}
# 상태 화면 판정(status.sh)이 빨강이면 부름: 목록 안 코드만 요청
dbg_red() { case "$DBG_RED" in *" $1 "*) dbg_trig b b_red ;; esac; return 0; }
# 서비스 시작: A의 바뀜(내비 버전·HMG-API·NEMESIS·무선 모드)과 확인되지 않은 차(CARS_SEEN 밖, 처음 한 번만)
dbg_seen_check() {
  _dsf=$(getprop ro.build.product 2>/dev/null | $BB awk '{ gsub(/[^A-Za-z0-9._-]/, ""); print; exit }')
  _dsh=$($BB awk '$1 == "version" { gsub(/[^A-Za-z0-9._-]/, "", $2); print $2; exit }' ${HMGINST:-/data/hmgapi/installed.txt} 2>/dev/null)
  _dsn=$(nemesis version 2>/dev/null | $BB awk '{ gsub(/[^A-Za-z0-9._-]/, ""); print; exit }')
  _mv=; [ -f $HMGDATA/mods/$MOD_ID/mod.json ] && mod_ver >/dev/null; _dsm=$(echo "$_mv" | $BB awk '{ gsub(/[^A-Za-z0-9._-]/, ""); print; exit }')
  _dsc=no; car_in "$_dsf" "$CARS_SEEN" && _dsc=yes
  _dso=; [ -f $BK/debug.seen ] && read -r _dso < $BK/debug.seen 2>/dev/null
  _dsl="fw=${_dsf:--} hmg=${_dsh:--} nem=${_dsn:--} mod=${_dsm:--}"
  _dsn2=
  for _dsk in fw hmg nem mod; do
    _dsa=$(echo " $_dso " | $BB awk -v k="$_dsk" '{ for (i = 1; i <= NF; i++) if (index($i, k "=") == 1) { print substr($i, length(k) + 2); exit } }')
    _dsb=$(echo " $_dsl " | $BB awk -v k="$_dsk" '{ for (i = 1; i <= NF; i++) if (index($i, k "=") == 1) { print substr($i, length(k) + 2); exit } }')
    # 못 읽은 값(-)은 바뀜으로 보지 않고, 리뷰 낮음 3: 옛 값을 그대로 남긴다(다음 부팅에 "-→값"으로 켜지지 않게)
    if [ "$_dsb" = - ] && [ -n "$_dsa" ]; then _dsb=$_dsa
    elif [ -n "$_dso" ] && [ -n "$_dsa" ] && [ "$_dsa" != "$_dsb" ]; then dbg_trig a a_$_dsk; fi
    _dsn2="$_dsn2 $_dsk=$_dsb"
  done
  _dsl="${_dsn2# } car=$_dsc"
  # 확인되지 않은 차: debug.seen에 car= 기록이 아직 없을 때만(처음 한 번)
  case " $_dso " in *" car="*) ;; *) [ $_dsc = no ] && dbg_trig a a_car ;; esac
  echo "$_dsl" 2>/dev/null > $BK/debug.seen.tmp && $BB mv -f $BK/debug.seen.tmp $BK/debug.seen 2>/dev/null
  return 0
}
# 자동 구간 관리: 서비스 시작마다 한 번(인자 start: 시작 횟수를 셈, 설치 표시를 받음) + 자동으로 켜져 있을 때 logrotate에서 점검 20번마다
debug_auto() {
  # 베타 3(B3-7): 한 서비스 실행에서 시작 처리(횟수 세기·설치 표시)는 한 번만(softap.conf를 기다리는 길이 먼저 부를 수 있음)
  if [ "$1" = start ] && [ "$DBG_STARTED" = 1 ]; then set --; fi
  [ "$1" = start ] && DBG_STARTED=1
  if [ "$1" = start ]; then
    # 옛 판(1.8.0 베타 2) 기록 옮기기: 48시간이 끝난 표시(debug.done)·차주가 끈 뒤 남은 옛 형식 기록은 자동 구간이 아니다
    if [ -f $BK/debug.done ]; then rm -f $BK/debug.done $BK/debug.auto $BK/debug.boots; fi
    if [ -f $BK/debug.off ] && [ -f $BK/debug.auto ]; then
      _dao=; _dac=; { read _dao _dac < $BK/debug.auto; } 2>/dev/null; [ -n "$_dac" ] || rm -f $BK/debug.auto $BK/debug.boots
    fi
    if [ -f $BK/debug.pend ]; then rm -f $BK/debug.pend; dbg_trig a a_install; fi
    dbg_seen_check
  fi
  [ -f $BK/debug.auto ] || return 0
  _das=; _dac=; { read _das _dac < $BK/debug.auto; } 2>/dev/null; _dac=${_dac:-a_install}
  _dat=$(date '+%Y %s' 2>/dev/null); _day=${_dat%% *}; _dan=${_dat#* }
  _dal=-1
  if [ "$1" = start ]; then
    _dab=; { read _dab < $BK/debug.boots; } 2>/dev/null; case "$_dab" in ''|*[!0-9]*) _dab=0 ;; esac
    _dab=$((_dab + 1)); echo $_dab > $BK/debug.boots
    # 시작 시각을 아직 못 적었으면(시계가 한 번도 맞지 않음) 30번, 적었으면 100번(운행이 늘 짧아 시계가 맞은 확인을 못 하는 차).
    # 시작 시각이 있는 차를 30번으로 끝내지 않는다: 서비스가 자주 다시 시작하는 차일수록 로그가 필요하다(advisor 지적)
    case "$_das" in ''|*[!0-9]*) _dam=$DBG_AUTO_BOOTS ;; *) _dam=$DBG_AUTO_BOOTS2 ;; esac
    [ $_dab -gt $_dam ] && _dal=-2
  fi
  if [ $_dal = -2 ]; then :
  # 함께 비는 값이라 붙여 봄(_day·_dan은 위 date 한 번의 출력을 나눈 두 칸)
  elif case "$_day$_dan" in ''|*[!0-9]*) true ;; *) [ "$_day" -lt $KP_YEAR0 ] ;; esac; then
    # 시계가 아직 맞지 않음(또는 못 읽음): 판단 보류. 켠 채로 둔다
    _dal=1
  else
    case "$_das" in ''|*[!0-9]*) _das=$_dan; echo "$_dan $_dac" > $BK/debug.auto ;; esac
    [ $_dan -ge $((_das - 86400)) ] && _dal=$((_das + DBG_AUTO_S - _dan))
  fi
  if [ $_dal -gt 0 ]; then
    if [ ! -f $W/debug ]; then
      # 리뷰 낮음 3: 자동 표시를 먼저 만든다(켜기만 되고 표시가 없으면 차주가 켠 것으로 보여 끝나지 않으므로)
      $BB mkdir -p $W && : > $W/debug.byauto && : > $W/debug && log "디버그 로그 자동 켬($_dac, 48시간)"
    fi
    return 0
  fi
  rm -f $BK/debug.auto $BK/debug.boots
  log "디버그 로그 자동 켜짐 끝남(48시간, $_dac)"
  if [ -f $W/debug.byauto ]; then $BB rm -f $W/debug $W/debug.byauto; killlog; fi
  return 0
}
# 차주가 디버그 로그를 켜고 끈다(상태 화면 토글 요청 처리 set_take가 부름).
# on: 켜짐 표시를 두고 자동 표시를 지워 48시간이 지나도 그대로 둔다(로그 파이프는 다음 서비스 시작부터)
# off: 끄고 A로 다시 켜지 않게 기록, 지금 자동 구간을 끝내고 로그 파이프를 멈추고 남은 cp.log를 지운다(소유자 결정 11-18)
debug_set() {
  case "$1" in
    on) $BB mkdir -p $W && : > $W/debug && $BB rm -f $W/debug.byauto $BK/debug.off ;;
    # 리뷰 낮음 4: 끈 기록을 못 쓰면 실패로 돌려준다(그대로 두면 다음 시작에 다시 자동으로 켜짐)
    off) { $BB mkdir -p $BK && : > $BK/debug.off; } 2>/dev/null || return 1
         $BB rm -f $W/debug $W/debug.byauto $BK/debug.auto $BK/debug.boots; killlog
         # 소유자 결정(11-18): 차주가 끄면 남은 디버그 로그(폰 이름이 들어 있음)도 지운다
         $BB rm -f $W/cp.log $W/cp.log.1 $W/cp.log.2 $W/cp.log.3 ;;
    *) return 1 ;;
  esac
}
# 자동 켜짐 상태(기록을 읽기만 함). 상태 화면·설정 요청 처리가 같이 쓴다.
# user: 차주가 직접 켬, on: 자동으로 켜져 있음, wait: 자동 구간인데 서비스가 아직 켜지 않음, off: 차주가 끔(자동 구간 없음),
# none: 자동 구간 없음(예전 done도 여기로)
dbg_auto_state() {
  if [ -f $W/debug ] && [ ! -f $W/debug.byauto ]; then echo user
  elif [ -f $BK/debug.auto ] && [ -f $W/debug.byauto ]; then echo on
  elif [ -f $BK/debug.auto ]; then echo wait
  elif [ -f $BK/debug.off ]; then echo off
  else echo none; fi
}
# 자동 켜짐이 끝나기까지 남은 시간(시간 단위, 올림). 자동으로 켜져 있고, 시작 시각이 적혀 있고, 시계가 맞을 때(연도 KP_YEAR0 이상)만.
# 그 밖에는 빈 값(앱은 "자동으로 켜짐"만 보임: 부팅 직후 시계가 2016년이라 앱이 직접 계산하지 않는다)
dbg_left() {
  [ "$(dbg_auto_state)" = on ] || return 0
  _dls=; { read _dls _dlx < $BK/debug.auto; } 2>/dev/null
  case "$_dls" in ''|*[!0-9]*) return 0 ;; esac
  _dlt=$(date '+%Y %s' 2>/dev/null); _dly=${_dlt%% *}; _dln=${_dlt#* }
  # 함께 비는 값이라 붙여 봄(date 한 번의 출력을 나눈 두 칸)
  case "$_dly$_dln" in ''|*[!0-9]*) return 0 ;; esac
  [ "$_dly" -ge $KP_YEAR0 ] || return 0
  _dlr=$((_dls + DBG_AUTO_S - _dln))
  [ $_dlr -gt 0 ] && echo $(( (_dlr + 3599) / 3600 ))
  return 0
}
# 마지막으로 켠 이유 코드(debug.why 끝 줄)
dbg_why_last() { $BB awk '{ l = $0 } END { if (NR) { split(l, f, " "); print f[3] } }' $BK/debug.why 2>/dev/null; }
# 상태 파일의 디버그 줄. debug=yes|no(켜기 표시), debug_auto(위), debug_left(위), debug_rec=yes|no(지금 로그 파이프가 도는가, log.pid),
# 베타 3: debug_why=<마지막 이유 코드>, debug_src=a|b|user|(빈 값)
dbg_kv() {
  if [ -f $W/debug ]; then echo "debug=yes"; else echo "debug=no"; fi
  _dks=$(dbg_auto_state)
  echo "debug_auto=$_dks"
  echo "debug_left=$(dbg_left)"
  if [ -f $W/log.pid ]; then echo "debug_rec=yes"; else echo "debug_rec=no"; fi
  _dkw=; _dkc=; [ -f $BK/debug.auto ] && { read _dkx _dkc < $BK/debug.auto; } 2>/dev/null
  case "$_dks" in on|wait) _dkw=${_dkc:-a_install} ;; *) _dkw=$(dbg_why_last) ;; esac
  echo "debug_why=$_dkw"
  case "$_dks" in user) echo "debug_src=user" ;; on|wait) echo "debug_src=${_dkw%%_*}" ;; *) echo "debug_src=" ;; esac
}
# 파이프를 다시 시작하지 않고 파일만 밀어낸다: 다시 시작하면 logcat이 버퍼 전체를 다시 써서
# 몇 분 치가 겹쳐 쌓였다(run3). uniq는 >>(O_APPEND)로 열었으므로 cp.log를 비우면 처음부터 다시 쓴다.
# 복사와 비우기 사이에 들어온 몇 줄은 잃을 수 있다(디버그용이라 감수).
logrotate() {
  aplog_rotate
  # 1.8.0 X-9: 자동으로 켠 디버그 로그는 점검 20번(우리 핫스팟 10분, 순정 AP 차 20분)마다 48시간이 지났는지 본다
  DBG_N=$((${DBG_N:-0} + 1))
  [ -f $W/debug.byauto ] && [ $((DBG_N % 20)) -eq 0 ] && debug_auto
  [ -f $W/log.pid ] || return 0
  _sz=$( { $BB wc -c < $W/cp.log; } 2>/dev/null)
  [ ${_sz:-0} -lt $LOGMAX ] && return 0
  $BB mv -f $W/cp.log.2 $W/cp.log.3 2>/dev/null
  $BB mv -f $W/cp.log.1 $W/cp.log.2 2>/dev/null
  # 복사가 실패해도(공간 부족 등) cp.log는 비운다: 그러지 않으면 cp.log가 끝없이 커져 /data를 채운다
  $BB cp -f $W/cp.log $W/cp.log.1 2>/dev/null || $BB rm -f $W/cp.log.1
  : > $W/cp.log
}

# HMG-API가 자기 것으로 기록한 기능 권한 파일이 사라졌을 때 되돌린다 (2026-11-06 니로에서 확인한 문제:
# wireless.projection을 지우면 무선 기능 파일 2개가 함께 지워지고, HMG-API 1.0.2의 apply는
# "changed outside HMG-API"로 멈추며 --force로도 다시 쓰지 않는다).
# `hmgapid engine status`에서 "CHANGED <권한 파일> … expected <md5>, found absent" 줄만 골라,
# HMG-API(Engine.features)가 쓰는 것과 같은 텍스트의 md5가 기록과 같을 때만 쓴다. 그 뒤 일반 apply.
# 되돌린 파일 이름은 $PERMS_OURS에 남기고, 패키지를 지울 때 HMG-API가 더 관리하지 않는 것만 perms_revert가 지운다(1.7.2 P-14).
PERMS=${PERMS:-/system/etc/permissions}
perm_text() { $BB printf '<permissions>\n    <feature name="%s" />\n</permissions>\n' "$1"; }
# HMG-API에 남아 있는 다른 변경(앱에서 바꾸고 아직 적용 안 한 모드 등)까지 몰래 적용하지 않도록,
# 계획에 바뀌는 것이 featurexml.cfg와 방금 되돌린 권한 파일뿐일 때만 apply한다.
plan_only_ours() {
  _bad=0
  hmgapid engine plan > $W/plan.txt 2>&1 || _bad=1
  while IFS= read -r _l; do
    case "$_l" in
      "change   "*|"update   "*)
        set -- $_l
        _p=$2; _mods=$3
        case "$_p" in
          # featurexml.cfg는 되돌린 권한 파일을 가진 모드의 변경일 때만 (다른 모드가 앱에서 쌓아 둔 변경은 안 됨)
          /system/onebin/*/featurexml.cfg) has_line "$_mods" $W/perms.mods || _bad=1 ;;
          *) has_line "${_p##*/}" $W/perms.done || _bad=1 ;;
        esac ;;
      # 다른 곳에서 바뀐 파일을 새 기준으로 삼는 rebase는 featurexml.cfg만 (wireless.projection 삭제가 되돌린 파일)
      "rebase   /system/onebin/"*"/featurexml.cfg:"*) ;;
      "rebase   "*|"problem  "*|"restore  "*|"setting  "*|"bind     "*|"unbind   "*) _bad=1 ;;
      # WARNING 줄(예: ADB TCP 스위치 경고)은 정보일 뿐이라 막지 않는다
    esac
  done < $W/plan.txt
  return $_bad
}

# /system이 원래 ro였을 때만 ro로 되돌린다 (NEMESIS·HMG-API가 rw로 쓰는 중일 수 있다)
# /proc/mounts를 못 읽으면 ro였던 것으로 본다 (rw로 남기지 않는 쪽으로)
system_ro() {
  _ml=$($BB grep " /system " ${MOUNTS:-/proc/mounts} 2>/dev/null) || return 0
  case "$_ml" in *" ro,"*|*" ro "*) return 0 ;; *) return 1 ;; esac
}

# 한 번에 하나만: 서비스가 다시 시작돼도 앞의 작업(뒤에서 도는 하위 셸)과 겹치지 않게.
# main이 $!로 하위 셸의 pid를 적는다 (하위 셸 안의 $$는 부모 pid라 쓸 수 없다)
BOOT_ID=${BOOT_ID:-/proc/sys/kernel/random/boot_id}
# fix.pid: "<pid> <boot_id>". /data/local/tmp는 재부팅 뒤에도 남으므로 이번 부팅의 것만 믿는다.
# 1.7.3(리뷰 M3): /proc/<pid>/cmdline은 인자를 NUL로 나눈다. busybox 1.8.1 grep은 첫 NUL 뒤를 못 볼 수 있어(P-16) NUL을 빈칸으로
# 바꾼 한 줄로 본다(stock_ssid가 쓰는 방식과 같음). 읽지 못하면 빈 값.
pcmd() { $BB tr '\0' ' ' < $PROC/$1/cmdline 2>/dev/null; }
# 확인 리뷰 M1: pcmd를 믿을 수 있는가. 차의 busybox 1.8.1 tr이 NUL을 바꾸지 못하면 명령줄이 첫 NUL에서 잘리거나("sh")
# NUL이 빠져 붙는다("sh/data/…status.sh--watch"). 둘 다 낱말이 하나뿐이다. 그래서 자기 명령줄(/proc/$$, 셸 + 스크립트로
# 늘 둘 이상)을 읽어 낱말이 둘 이상이면 믿는다. 자기 것을 읽을 수 없으면(PC 시험의 가짜 /proc 등) 판단할 수 없어 믿는 것으로 둔다
# (차에서는 /proc/$$가 늘 있다). 부를 때마다 본다(하위 셸 하나)
pcmd_ok() {
  [ -r $PROC/$$/cmdline ] || return 0
  set -- $(pcmd $$)
  [ $# -ge 2 ]
}
fix_running() {
  _l=$(cat $W/fix.pid 2>/dev/null) || return 1
  set -- $_l
  [ -n "$1" ] && [ "$1" != $$ ] && [ "$2" = "${BID:-$(cat $BOOT_ID 2>/dev/null)}" ] && [ -d $PROC/$1 ] || return 1
  case " $(pcmd $1) " in *hotspot.sh*) return 0 ;; esac
  return 1
}
# --- 1.7.3(R-3·R-4): 제보 파일 만들기 요청 ---
# 상태 화면 앱의 [제보 파일 만들기] 버튼이 앱 개인 폴더에 요청 파일을 쓴다. 내용은 한 줄 "<요청 id> <boot_id> <부팅 뒤 초>"
# (요청 id는 앱의 부팅 뒤 밀리초, 숫자만). 다른 앱은 이 폴더에 쓸 수 없어 아무나 제보 만들기를 시킬 수 없다.
# root가 이 파일을 읽고 지울 수 있는지(SELinux·권한)는 차에서 확인해야 한다(확인 안 함). 읽지 못하면 요청이 없는 것으로 넘어간다.
REQ=${REQ:-/data/data/korea.projection.app/files/report.req}
# 1.7.3(U-3): [지금 재부팅] 요청. 같은 앱 개인 폴더, 같은 형식. 감시자(status.sh --watch)만 받는다(서비스 점검은 받지 않음).
RBREQ=${KP_RBREQ:-/data/data/korea.projection.app/files/reboot.req}
# 요청 파일($1, 기본 $REQ)을 읽어 RQ_ID·RQ_EL을 정한다. 읽은 내용은 RQ_RAW에 둔다(못 읽으면 빈 값). 이번 부팅의 요청이고, 값이 숫자이고, 이미 받은 요청($2 파일의 id,
# 기본 req.last)이 아니면 0. 받지 않는 요청을 지울 때는 req_drop을 쓴다. 지우지 못해 남은 요청을 다시 받지 않게 하는 판단이 여기 하나뿐이다(서비스 점검과 status.sh가 함께 쓴다).
req_peek() {
  RQ_ID=; RQ_EL=; RQ_RAW=; _rl=${2:-$W/req.last}
  _rq=$(cat ${1:-$REQ} 2>/dev/null) || return 1
  RQ_RAW=$_rq
  set -- $_rq
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  case "$3" in ''|*[!0-9]*) return 1 ;; esac
  RQ_ID=$1; RQ_EL=$3
  [ "$1" != "$(cat $_rl 2>/dev/null)" ] && [ -n "$2" ] && [ "$2" = "${BID:-$(cat $BOOT_ID 2>/dev/null)}" ]
}
# 재부팅을 막는 용도의 "돌고 있는가"(재리뷰 중간 1): "<pid> <boot_id>" 파일의 pid가 이번 부팅에 살아 있고(/proc/<pid> 있음)
# 명령줄에 $2가 있으면 0. 명령줄을 읽지 못하면(빈 값: busybox tr이 NUL을 못 다루거나 읽기 실패) 돌고 있는 것으로 본다(막는 쪽으로).
# 감시자를 하나만 띄우는 st_alive는 반대로 못 읽으면 "없음"으로 본다(그쪽은 막혀 영영 안 뜨는 것이 더 나쁘다).
pid_busy() {
  _pl=$(cat $1 2>/dev/null) || return 1
  _pw=$2
  set -- $_pl
  [ -n "$1" ] && [ "$2" = "${BID:-$(cat $BOOT_ID 2>/dev/null)}" ] && [ -d $PROC/$1 ] || return 1
  # 확인 리뷰 M1: pcmd를 믿을 수 없으면(명령줄이 잘리거나 붙음) 이번 부팅에 살아 있는 pid는 바쁜 것으로 본다(막는 쪽)
  _pp=$1; pcmd_ok || return 0
  _pc=$(pcmd $_pp)
  [ -z "$_pc" ] && return 0
  case " $_pc " in *"$_pw"*) return 0 ;; esac
  return 1
}
# 이번 부팅 설치 진행 기록이 "재부팅 필요"(state=reboot)인가
prog_reboot_this_boot() {
  $BB grep -q '^state=reboot$' $PROG 2>/dev/null \
    && [ "$($BB awk -F= '$1 == "boot" { print $2 }' $PROG 2>/dev/null)" = "${BID:-$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)}" ]
}
# 받지 않는 요청 지우기: req_peek이 읽은 그 내용(RQ_RAW)일 때만 지운다. 파일을 다시 보고 지우면, req_peek이 읽은 뒤(파일 없음)
# 막 들어온 새 요청을 "받지 않는 요청"으로 지울 수 있다(2026-11-10 PC 시험에서 찾은 경쟁, 리뷰 반영). 지웠으면 0.
req_drop() {
  [ -n "$RQ_RAW" ] && [ "$(cat $1 2>/dev/null)" = "$RQ_RAW" ] && rm -f $1 2>/dev/null
}
# "<pid> <boot_id>" 파일의 pid가 이번 부팅에 살아 있는 status.sh인가(자기 자신은 뺀다). $2를 주면 명령줄에 그 인자
# (--watch·--report)도 낱말로 있어야 한다. watch.pid·collect.pid에 쓴다. 명령줄은 pcmd로 읽는다(NUL → 빈칸).
st_alive() {
  _sl=$(cat $1 2>/dev/null) || return 1
  _sa=$2
  set -- $_sl
  [ -n "$1" ] && [ "$1" != "$$" ] && [ "$2" = "${BID:-$(cat $BOOT_ID 2>/dev/null)}" ] && [ -d $PROC/$1 ] || return 1
  _sc=" $(pcmd $1) "
  case "$_sc" in *status.sh*) ;; *) return 1 ;; esac
  [ -z "$_sa" ] && return 0
  case "$_sc" in *" $_sa "*) return 0 ;; esac
  return 1
}
# --- 1.8.0 설정 요청(앱 세션 "제안 A", 오케스트레이터 승인 2026-11-18): 상태 화면의 토글 ---
# 앱이 개인 폴더에 settings.req 한 줄 "<요청 id> <boot_id> <부팅 뒤 초> <키>=<값>"을 쓴다(앞 세 칸은 report.req와 같아 req_peek을 다시 씀).
# 지금 받는 것은 debug=on|off 하나다(허용 목록). 서비스 점검(req_tick, 30초)과 감시자(status.sh --watch, 1초) 둘 다 받는다:
# 감시자가 끝난 뒤(Launch 10분 뒤)에도 48시간 자동 켜짐을 끌 수 있어야 해서다.
# 순서(앱과 맞춤): ① 처리 전에 요청 파일을 가져간다(req_drop) ② 60초(KP_SET_MAX)가 넘었거나 나이를 모르면 답 없이 버린다
# ③ 처리하고 상태 파일의 디버그 줄을 먼저 고쳐 쓴다 ④ 답 파일(SETRES, 644, id·boot·key·code·val)을 임시 파일 → 이름 바꾸기로 쓴다.
# code: ok · bad(허용 목록 밖, 값이 깨짐) · busy(제보를 만드는 중: 끄면 cp.log를 지우므로) · fail(처리 실패). 무엇이 실패해도 0(서비스 반복이 멈추지 않게).
# 앱이 쓰는 파일을 root가 읽는다: 내용은 숫자 세 칸과 debug=on|off 한 칸만 받고, 그 밖은 bad로 답하거나 버린다(경로·명령으로 쓰지 않음).
# 로그는 SET_LOG(기본 log: 서비스 ap.log)로 남긴다. 감시자는 aplog를 준다.
SETREQ=${KP_SETREQ:-/data/data/korea.projection.app/files/settings.req}
SETRES=${SETRES:-/data/local/tmp/korea-projection-settings-result.txt}
set_result() {
  _srb=${BID:-$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)}
  # 리뷰 중간 1: 감시자와 서비스가 같은 때 쓰더라도 서로의 임시 파일을 섞지 않게 pid를 붙인다
  ( umask 022
    { echo "id=$RQ_ID"; echo "boot=$_srb"; echo "key=$2"; echo "code=$1"; echo "val=$3"; } 2>/dev/null > $SETRES.tmp.$$ \
      && $BB chmod 644 $SETRES.tmp.$$ 2>/dev/null && $BB mv -f $SETRES.tmp.$$ $SETRES 2>/dev/null; rm -f $SETRES.tmp.$$ )
  return 0
}
# 상태 파일(status.sh가 쓰는 STATUS)의 디버그 줄만 지금 값으로 바꿔 쓴다(다른 줄은 그대로). 상태 파일이 없으면 하지 않는다(Launch가 만듦)
set_status_fix() {
  _ssf=${STATUS:-/data/local/tmp/korea-projection-status.txt}
  [ -f $_ssf ] || return 0
  # 리뷰 중간 2·낮음 1: 디버그 말고 다른 줄은 읽은 그대로 두되, 옮기기 직전에 상태 파일이 그사이 바뀌었으면(Launch가 새로 씀) 한 번 다시 한다.
  # awk가 실패하거나 빈 결과면 옮기지 않는다(디버그 4줄만 남은 파일이 되지 않게). 임시 파일에는 pid를 붙인다
  for _ssn in 1 2; do
    _sso=$($BB cat $_ssf 2>/dev/null)
    ( umask 022
      $BB awk -F= '$1 != "debug" && $1 != "debug_auto" && $1 != "debug_left" && $1 != "debug_rec" && $1 != "debug_why" && $1 != "debug_src" && $1 != "dongle_set" && $1 != "dongle_why" && $1 != "dongle" && $1 != "dongle_lv" && $1 != "dongle_msg" && $1 != "dongle_note" && $1 != "dongle_oldnav" && $1 != "dongle_sup" && $1 != "dongle_seen" && $1 != "dongle_wait"' $_ssf 2>/dev/null > $_ssf.set.$$ \
        && [ -s $_ssf.set.$$ ] && dbg_kv >> $_ssf.set.$$ && dg_kv >> $_ssf.set.$$ && dg_toggle_kv >> $_ssf.set.$$ && $BB chmod 644 $_ssf.set.$$ 2>/dev/null ) || { rm -f $_ssf.set.$$; return 0; }
    [ "$($BB cat $_ssf 2>/dev/null)" = "$_sso" ] && { $BB mv -f $_ssf.set.$$ $_ssf 2>/dev/null; rm -f $_ssf.set.$$; return 0; }
    rm -f $_ssf.set.$$
  done
  return 0
}
set_take() {
  [ -f $SETREQ ] || return 0
  if ! req_peek $SETREQ $W/set.last; then
    # 이전 부팅·이미 받은 요청·깨진 앞 세 칸: 답 없이 지운다(읽은 그 내용일 때만)
    [ -n "$RQ_RAW" ] && req_drop $SETREQ
    return 0
  fi
  # 리뷰 중간 1: 가져가지 못하면(앱이 45초가 되어 먼저 지움, 다른 쪽이 먼저 가져감) 처리하지 않는다. 앱이 "원래대로 두었습니다"를 보인 뒤 바뀌지 않게
  req_drop $SETREQ || return 0
  echo "$RQ_ID" > $W/set.last
  kp_up
  case "$_U" in ''|*[!0-9]*) ${SET_LOG:-log} "설정 요청 버림: 요청 나이를 알 수 없음"; return 0 ;; esac
  _sa=$((_U - RQ_EL))
  if [ $_sa -lt 0 ] || [ $_sa -gt ${KP_SET_MAX:-60} ]; then ${SET_LOG:-log} "설정 요청 버림: 오래된 요청(${_sa}초)"; return 0; fi
  # 넷째 칸에 *·? 같은 글자가 와도 파일 이름으로 풀리지 않게
  case $- in *f*) _ssf0=0 ;; *) _ssf0=1; set -f ;; esac
  set -- $RQ_RAW
  _skv=$4; [ -n "$5" ] && _skv=
  [ $_ssf0 = 1 ] && set +f
  _sk=${_skv%%=*}; _sv=${_skv#*=}
  case "$_sk" in ''|*[!a-z_]*) _sk=bad ;; esac
  case "$_skv" in
    debug=on|debug=off) ;;
    # 1.8.0 SC-5: 동글 토글(차주 선택). 바꾸면 재부팅 뒤 적용(앱이 안내). 제보 만들기와 상관없어 바쁨을 보지 않는다
    # 소유자 결정 (가)(11-18 밤): 차주 선택에서 자동으로 되돌리기. 선택 기록을 지우고 다음 부팅부터 자동 판단(재부팅 뒤 적용)
    dongle=auto)
      if dg_toggle_auto; then
        ${SET_LOG:-log} "설정 요청 처리: 동글 토글 자동으로 되돌림(다음 부팅에 자동 판단)"
        set_status_fix; set_result ok dongle auto
      else
        set_status_fix; set_result fail dongle ""
      fi
      return 0 ;;
    dongle=on|dongle=off)
      if dg_toggle_set $_sv; then
        # 베타 3(B3-2): 꽂기를 기다리는 중(아직 안 붙음)에 끄면 다음 점검이 그 부팅에 바로 내비 Wi-Fi로 돌린다. 30초 쉬기를 깨운다
        if [ $_sv = off ] && dg_plugwait_now; then
          ${SET_LOG:-log} "설정 요청 처리: 동글 토글 off(차주 선택, 꽂기 기다림 중이라 바로 적용)"; dg_wake
        else
          ${SET_LOG:-log} "설정 요청 처리: 동글 토글 $_sv(차주 선택, 재부팅 뒤 적용)"
        fi
        set_status_fix; set_result ok dongle $_sv
      else
        set_status_fix; set_result fail dongle ""
      fi
      return 0 ;;
    *) ${SET_LOG:-log} "설정 요청 거절: 받지 않는 키·값"; set_result bad "$_sk" ""; return 0 ;;
  esac
  # 리뷰 낮음 2: 명령줄을 못 읽으면 바쁜 것으로 본다(pid_busy, 재부팅 쪽과 같은 막는 쪽). 끄면 제보에 쓰일 cp.log를 지우므로
  if pid_busy $W/collect.pid status.sh; then
    ${SET_LOG:-log} "설정 요청 미룸: 제보 파일을 만드는 중(debug=$_sv)"; set_result busy debug ""; return 0
  fi
  if debug_set $_sv; then
    ${SET_LOG:-log} "설정 요청 처리: 디버그 로그 $_sv$([ $_sv = off ] && echo ', 남은 디버그 기록을 지움')"
    set_status_fix
    if [ -f $W/debug ]; then set_result ok debug on; else set_result ok debug off; fi
  else
    set_status_fix; set_result fail debug ""
  fi
  return 0
}
# 서비스 점검의 백업 경로(D-2): Launch가 띄운 감시자(status.sh --watch, 10분)가 끝난 뒤 눌러도 다음 점검(30초)에서 시작한다.
# 받을 요청(req_peek)이 있고 감시자·다른 제보 만들기가 없을 때만 띄운다. 이전 부팅·이미 받은 요청은 띄우지 않는다
# (root가 요청 파일을 지우지 못해도 30초마다 다시 띄우지 않게, 리뷰 중간 1). 요청을 받고 지우는 일은 status.sh --report가 한다.
# 무엇이 실패해도 0을 돌려준다(서비스 반복이 멈추지 않게, mode=restart).
req_tick() {
  # 1.8.0: 설정 요청(토글)을 먼저 본다(가볍고, 감시자가 없을 때 받는 길이 이것뿐)
  set_take
  dbg_req_tick
  # 1.8.0 DG-4: 동글 드라이버 결과 보기(서비스가 dg_start를 부른 때만 무엇을 함)
  dg_tick
  req_report
  return 0
}
# 제보 파일 만들기 요청(req_tick과 동글 기다림 dg_settle이 부름)
req_report() {
  [ -f $APP/bin/status.sh ] || return 0
  req_peek || return 0
  st_alive $W/watch.pid --watch && return 0
  st_alive $W/collect.pid && return 0
  log "제보 파일 만들기 요청을 받음(서비스 점검): 뒤에서 만듦"
  BB=$BB $BB setsid sh $APP/bin/status.sh --report </dev/null >/dev/null 2>&1 &
  return 0
}
# 파일에 그 줄이 그대로 있는가 (busybox 1.8.1 grep의 -x/-F는 확실하지 않아 셸로 비교)
has_line() {
  [ -f "$2" ] || return 1
  while IFS= read -r _x; do [ "$_x" = "$1" ] && return 0; done < "$2"
  return 1
}
# --- 1.5 자동 설정: HMG-API 무선 모드와 이 차의 지도 (확인된 차에서만) ---
# HMG-API 공식판에 한국 차 지원(지도, 모드의 지원 차·패치 세트)이 아직 없어(니로: PR VysseCodes/HMG-API#22),
# 패키지에 든 한국 차 빌드 모드(hmgapi/wireless-carplay-aa.zip)와 차에서 확인한 지도(hmgapi/maps/<제조사>/<차종>/
# <지역>/<펌웨어>/)를 HMG-API 명령으로 넣는다. 파일을 직접 고치지 않는다.
# - 지도: 패키지에 든 차별 지도 가운데 HMG-API에 없는 것(car.json 없음)만 넣고, 넣었으면 HMG-API의 지도 확인
#   (verify-map, 이 차의 지도를 확인)을 돌린다.
#   HMG-API를 업데이트하면 지도 폴더가 릴리스 것으로 바뀌므로 부팅마다 본다. 공식판에 지도가 생기면 그것을 쓴다.
# - 모드: 설치돼 있지 않을 때 한 번만 설치한다($BK/mod.tried). 차주가 일부러 지우거나 꺼 둔 것은 다시 하지 않는다.
#   설치한 것은 $BK/mod.ours로 남겨 이 패키지를 지울 때 그것만 정리한다(preun.sh).
# - 적용(apply)은 계획이 이 모드의 변경뿐이고 훅이 켜질 때만 한다. 아니면 HMG-API 앱에서 적용하라고 안내한다.
# - 알려진 위험: HMG-API 엔진에는 잠금이 없어, 같은 때 차주가 앱에서 적용하면 서로 겹칠 수 있다(기존
#   권한 파일 복구와 같음). 부팅 뒤 FIX_DELAY(120초)를 기다리고, 앞 적용이 안 끝났으면 엔진이 거부한다.
# - 이 모드 zip은 우리 개발 키로 서명했다. HMG-API는 같은 키의 업데이트만 받으므로, 공식 모드로 바꾸려면
#   이것을 먼저 지워야 한다(hmgapi/README.txt).
KP_HMG=${KP_HMG:-$APP/hmgapi}
HMGDATA=${HMGDATA:-/data/hmgapi}
# HMG-API가 Wi-Fi 칩을 찾는 곳(SystemCheck.java): SDIO 장치, 한 번 본 기록
SDIO=${SDIO:-/sys/bus/sdio/devices}
WIFI_SEEN=${WIFI_SEEN:-$HMGDATA/public/wifi-chip}
# BK(백업 폴더)는 맨 위 AAOFF 앞에서 정한다(1.7.4 B-7)
# 1.7.2(P-14): fix_perms가 새로 쓴 권한 파일 이름(한 줄에 하나). 패키지를 지울 때 perms_revert가 읽는다.
PERMS_OURS=${PERMS_OURS:-$BK/perms.ours}
MOD_ID=wireless-carplay-aa
# 패키지에 든 모드 zip의 md5 (busybox 1.8.1에 sha256sum이 없다). zip을 바꾸면 함께 바꾼다.
MOD_MD5=e19ccea88cf08c0c512d76feaf1711e4
# 패키지에 든 모드의 버전(mod.json "version"). 1.5.7부터 차에 있는 우리 모드가 이것과 다르면 바꾼다(mod_update).
MOD_VER=2.4.10
# 1.7.1: 토스트는 쓰지 않는다(CLAUDE.md 1장, 소유자 결정 2026-11-08: 너무 빨리 사라져 차에서 읽을 수 없다).
# 안내는 ap.log("안내: …")와 상태 화면 앱이 읽는 알림 기록 $NOTICE(644, 비밀값 없음)에 남긴다.
# 알림 기록은 한 줄에 "<시각(초)> <부팅 id> <문구>", 최근 NOTICE_KEEP줄만. 앱은 이번 부팅의 줄만 보인다.
# 마지막 문구는 LAST_MSG로 기억한다(설치 진행 기록의 실패 사유로 쓴다).
NOTICE=${NOTICE:-/data/local/tmp/korea-projection-notice.txt}
NOTICE_KEEP=${NOTICE_KEEP:-5}
notice() {
  LAST_MSG=${1#Korea Projection: }
  log "안내: $LAST_MSG"
  _nb=$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)
  _nl="$(date +%s) ${_nb:-none} $LAST_MSG"
  # 임시 파일은 부르는 쪽마다 다르게(서비스·뒤의 fix_perms·Launch가 겹쳐도 서로 지우지 않게, 리뷰 L1).
  # 차의 toolbox mv는 옵션을 모른다(-f를 파일로 봄): busybox가 없으면 옵션 없이 쓴다(리뷰 H1).
  _nt=$NOTICE.$$.${RANDOM:-0}
  ( umask 022
    if has_bb && [ -f $NOTICE ]; then
      { $BB awk -v k=$((NOTICE_KEEP - 1)) '{ a[NR] = $0 } END { s = NR - k + 1; if (s < 1) s = 1; for (i = s; i <= NR; i++) print a[i] }' $NOTICE
        echo "$_nl"; } > $_nt
    else
      echo "$_nl" > $_nt
    fi
    if has_bb; then $BB chmod 644 $_nt && $BB mv -f $_nt $NOTICE
    else chmod 644 $_nt && mv $_nt $NOTICE; fi
    [ -f $_nt ] && rm $_nt ) 2>/dev/null
  return 0
}
# 계획(engine plan)이 이 모드의 새 변경뿐인가: 다른 모드의 변경, 되돌리기, 문제가 있으면 아니다
plan_only_mod() {
  _bad=0
  hmgapid engine plan > $W/plan.txt 2>&1 || _bad=1
  # "[wireless-carplay-aa]"가 단어 나누기 때 파일 이름 패턴으로 풀리지 않게
  set -f
  while IFS= read -r _l; do
    case "$_l" in
      # 훅이 꺼져 있으면 적용해도 무선 카플레이가 안 된다(기능 파일·속성만 바뀜)
      "hooks are off"*|"hooks "*"won't load"*) _bad=1 ;;
      "change   "*|"update   "*) set -- $_l; [ "$3" = "[$MOD_ID]" ] || _bad=1 ;;
      "setting  "*" back to stock"*) _bad=1 ;;
      "setting  "*"[$MOD_ID]"*) ;;
      "setting  "*|"problem  "*|"restore  "*|"rebase   "*|"bind     "*|"unbind   "*|"nothing changed"*) _bad=1 ;;
    esac
  done < $W/plan.txt
  set +f
  return $_bad
}
# Wi-Fi 칩 깨우기: 한국 내수 펌웨어에는 일반 Wi-Fi를 켜는 메뉴가 없다. 그래서 Wi-Fi를 한 번도 켜지 않은 차는
# 칩이 SDIO에 나타나지 않는다(MAC 00:00:00…, 그랜저 IGPEHEV 제보 #7).
# HMG-API는 칩을 SDIO에서 한 번 봐야(그 기록 $WIFI_SEEN이 있어도 됨) 칩이 있다고 본다(hmgapi.wifi).
# 무선 모드는 칩이 있어야 설치된다. 우리 핫스팟은 모드가 있어야 Wi-Fi를 켜므로, 모드를 넣기 전에 Wi-Fi를 한 번 켠다.
# - 시스템 파일과 속성은 바꾸지 않는다(svc wifi enable만 한다).
#   커뮤니티 "Wi-Fi 모듈 활성화 패치"는 build.prop·featurexml·권한 XML을 고친다. 우리는 그중 Wi-Fi를 켜는 것만 한다.
# - 기능 목록(android.hardware.wifi)으로 거르지 않는다: 니로는 이 기능이 없는데도 svc wifi enable로 Wi-Fi가 켜진다
#   (2026-11-06 차에서 확인). Wi-Fi 서비스가 없는 차는 칩이 안 나타나 wifi.nochip으로 끝난다.
# - Wi-Fi를 켜면 USB·블루투스가 다시 시작된다(유선 카플레이가 끊길 수 있다). 그래서 평생 한 번만 한다.
#   켜기 전에 $BK/wifi.woke를 남긴다. 칩이 잠깐 보였다 사라져(드라이버가 내려감) 설치가 실패해도
#   부팅마다 다시 켜지 않는다. 기록은 패키지를 지우면 같이 지워진다.
#   칩이 안 나타나면 $BK/wifi.nochip을 남기고, 설치 전에 Wi-Fi가 켜져 있지 않았으면 다시 끈다
#   (wifi_on이 1이 아니면 꺼져 있던 것으로 본다: 한 번도 안 켠 차는 값이 null일 수 있다).
# - 차주가 다른 방법으로 Wi-Fi를 켜 칩이 보이면 기록과 상관없이 다음 부팅에 설치를 다시 시도한다.
# 돌려주는 값: 0 칩이 보임(원래 보였거나 이번에 깨움), 1 끝남(부품 없음 wifi.nopart 또는 3번 모두 실패 wifi.nochip),
#   2 이미 끝난 기록이 있음(칩 실패 wifi.nochip 또는 칩을 본 기록 wifi.woke, 다시 깨우지 않음), 3 아직 확인 중(다음 부팅에 다시 깨움, 1.7.3 W-4·G-1)
wifi_chip_seen() {
  [ -f $WIFI_SEEN ] || [ -n "$(ls $SDIO 2>/dev/null)" ]
}
wifi_was_off() {
  [ -f $BK/wifi_on ] && [ "$(cat $BK/wifi_on 2>/dev/null)" != 1 ]
}
# 뒤에서 돌린 svc wifi enable 정리: 아직 돌면 멈추고, 끝났으면 실패한 종료 코드만 기록한다(제보 분석용)
# $2=mv3: 1.7.4(P-1 리뷰 낮음 3) module_version 3을 봐서 일찍 끝내는 경우(멈춘 까닭을 그대로 적는다)
svc_done() {
  if kill -0 $1 2>/dev/null; then
    kill $1 2>/dev/null
    if [ "$2" = mv3 ]; then log "svc wifi enable을 기다리지 않고 멈춤(순정 module_version=3을 봐서 일찍 끝냄)"
    else log "svc wifi enable이 끝나지 않아 멈춤"; fi
  else
    wait $1; _rc=$?
    [ $_rc = 0 ] || log "svc wifi enable 실패 (종료 코드 $_rc)"
  fi
}
# 1.7.3(W-1~W-4·W-6): Wi-Fi 판정 문구. 진행 기록·알림·상태 화면 판정(status.sh kp_verdict)이 같은 문장을 쓴다
WIFI_CHECK_MSG="Wi-Fi를 켜는 중입니다(재부팅 뒤 한 번 더 확인). 3분 후 재부팅해 주세요."
DONGLE_MSG="USB Wi-Fi 동글을 구매하여 사용해 주세요."
NOPART_MSG="이 차에는 Wi-Fi 부품이 없어 무선 프로젝션을 사용할 수 없습니다. $DONGLE_MSG"
NOCHIP_MSG="이 차는 Wi-Fi 칩이 켜지지 않아 지원하기 어렵습니다. $DONGLE_MSG"
# 1.7.4(P-4, #277): "무선 모드를 넣지 못했습니다"로만 보이던 길의 이유. 진행 기록·상태 화면 판정(status.sh가 문구로 판정 코드
# mapfail·nomap·wifigone을 정함, QR의 verdict)이 같은 문장을 쓴다
MAPFAIL_MSG="이 차의 MAP을 확인하지 못해 무선 모드를 넣지 않았습니다. 삭제 후 다시 설치해도 같으면 USB를 꽂고 [제보 파일 만들기]로 알려 주세요."
# 배포판(문구 수정 11-23): 옛 버전이 진행 기록에 남긴 옛 문장(status.sh 판정이 함께 받음)
MAPFAIL_MSG_OLD="이 차의 지도를 확인하지 못해 무선 모드를 넣지 않았습니다. 삭제 후 다시 설치해도 같으면 USB를 꽂고 [제보 파일 만들기]로 알려 주세요."
NOMAP_MSG="HMG-API가 이 차의 MAP을 만들지 않아 무선 모드를 넣지 않았습니다. USB를 꽂고 [제보 파일 만들기]로 알려 주세요."
NOMAP_MSG_OLD="HMG-API가 이 차의 지도를 만들지 않아 무선 모드를 넣지 않았습니다. USB를 꽂고 [제보 파일 만들기]로 알려 주세요."
# 1.8.0 U-1f(B-4): 무선 모드는 이미 있고 HMG-API 업데이트 뒤 지도만 다시 확인한 부팅(다시 시작해야 훅이 켜진다)
REMAP_MSG="HMG-API가 바뀌어 MAP을 다시 확인했습니다. 3분 후 재부팅해 주세요."
WIFIGONE_MSG="전에는 켜지던 Wi-Fi가 지금은 켜지지 않습니다. 3분 후 재부팅해도 같으면 USB를 꽂고 [제보 파일 만들기]로 알려 주세요."
# 1.7.3(W-1·W-4·G-1): 순정 module_version(마지막 값, 숫자만). 찾으면 $BK/wifi.modver에도 남긴다(로그 버퍼가 밀려도 다음 부팅에 쓰게).
# 3이면 순정 Wi-Fi 서비스도 Wi-Fi 하드웨어가 없다고 본다(#50·#58·#99). 모르면 빈 값
wifi_modver() {
  _mv=$(wifi_modver_log)
  if [ -n "$_mv" ]; then echo "$_mv"; else cat $BK/wifi.modver 2>/dev/null; fi
}
# 1.7.4(P-1): logcat에 지금 있는 module_version만(없으면 빈 값, $BK 기록으로 대신하지 않음). 찾으면 $BK/wifi.modver에 남긴다
# (리뷰: 값이 바뀔 때만 씀). 깨우기 반복 안에서 부른다(지난 부팅의 기록을 이번 깨우기의 결과로 잘못 보지 않게)
wifi_modver_log() {
  _mvlog=$(logcat -d -v time 2>/dev/null | $BB grep 'wifi_get_module_version:' | $BB awk '{ v = $NF } END { gsub(/[^0-9]/, "", v); print v }')
  [ -n "$_mvlog" ] && [ -d $BK ] && [ "$_mvlog" != "$(cat $BK/wifi.modver 2>/dev/null)" ] && echo "$_mvlog" > $BK/wifi.modver
  echo "$_mvlog"
}
# 칩 깨우기 횟수 기록($BK/wifi.wake "<횟수> <boot_id>"). 1.7.3(W-4·G-1): 순정 module_version이 3이 아닌데 칩이 안 보이면 바로 굳히지
# 않고 부팅마다 한 번씩, 최대 WAKE_BOOTS(3)번 깨운다. 같은 부팅(서비스 다시 시작)에는 다시 하지 않는다.
WAKE_BOOTS=${WAKE_BOOTS:-3}
# 기록이 없으면 0, 있는데 깨졌으면(숫자 아님) 최대값으로 보고 _wbad=1(리뷰 M-1: 안전 쪽, 더 깨우지 않음. 재리뷰 L-1: 칩 실패로 굳히지도 않음)
wake_count() {
  _wc=0; _wb=; _wbad=0
  [ -f $BK/wifi.wake ] || return 0
  read _wc _wb < $BK/wifi.wake
  case "$_wc" in ''|*[!0-9]*) _wc=$WAKE_BOOTS; _wbad=1 ;; esac
  return 0
}
# 재리뷰 L-8: 설치 전에 꺼져 있던 Wi-Fi를 다시 끈다. svc는 뒤에서 돌리고 최대 SVCOFF_MAX(10)회차만 기다린다(끝났는지는 종료 코드
# 파일로 본다: 끝난 자식에도 kill -0이 성공할 수 있어서). 끝나는 조건: 명령이 끝남 또는 회차.
wifi_restore_off() {
  wifi_was_off || return 0
  rm -f $W/svcoff.rc
  ( svc wifi disable >/dev/null 2>&1; echo $? > $W/svcoff.rc ) &
  _so=0
  while [ ! -s $W/svcoff.rc ] && [ $_so -lt ${SVCOFF_MAX:-10} ]; do sleep 1; _so=$((_so+1)); done
  [ -s $W/svcoff.rc ] || log "svc wifi disable이 끝나지 않음(기다리지 않고 넘어감)"
  rm -f $W/svcoff.rc
  return 0
}
# 1.7.4(L-2a, D-1 = 1.7.3 이상에서 올라오는 차만 지원): 1.7.2까지 굳은 wifi.nochip을 다시 깨우던 legacy_nochip_retry를 지웠다.
# 1.7.3이 만든 wifi.nochip은 늘 wifi.wake와 함께 생긴다. 1.7.2에서 바로 올린 차는 그 기록대로 "칩 실패"로 남는다(유선은 그대로)
wake_wifi() {
  # 리뷰 H-1: 칩이 보이면(다른 앱으로 Wi-Fi를 켠 차 등) 부품 없음·칩 실패 기록을 지운다(근거 기록 nochip-wifi.txt는 둔다).
  # 재리뷰 중간 2: 깨우기 횟수(wifi.wake)는 지우지 않는다. 칩이 보였다 안 보였다 하는 차(#52·#55 계열)에서 횟수가 0으로 돌아가
  # 끝없이 깨우지 않게(깨울 때마다 USB·블루투스가 다시 시작돼 유선 카플레이가 끊긴다)
  if wifi_chip_seen; then
    [ -f $BK/wifi.nopart ] || [ -f $BK/wifi.nochip ] && log "Wi-Fi 칩이 보임: 칩 없음 기록을 지움"
    rm -f $BK/wifi.nopart $BK/wifi.nochip
    return 0
  fi
  # 1.7.3(W-1): 순정 module_version이 3이면 부품이 없는 차다. 깨우지 않고(USB·블루투스가 다시 시작되지 않게) 바로 끝낸다.
  # 재리뷰 중간 4: 칩을 본 적 있는 차(wifi.woke)는 module_version이 3이어도 부품 없음으로 굳히지 않는다(근거 기록에만 남음)
  if [ -f $BK/wifi.nopart ] || { [ ! -f $BK/wifi.woke ] && [ "$(wifi_modver)" = 3 ]; }; then
    [ -f $BK/wifi.nopart ] || { $BB mkdir -p $BK; : > $BK/wifi.nopart; log "Wi-Fi 부품 없음: 순정 module_version=3(깨우지 않음)"; wifi_record "부품 없음 판정" $NOCHIP_LOG; [ -s $NOCHIP_LOG ] && cat $NOCHIP_LOG 2>/dev/null > $BK/nochip-wifi.txt; }
    return 1
  fi
  # 1.7.2(P-12): 칩 없음(wifi.nochip)으로 멈췄는데 그 근거 기록(nochip-wifi.txt, 1.7.1부터)이 없는 차(#58 셀토스 1.7.0)는
  # 한 번만 다시 깨워 근거를 남긴다($BK/nochip.rechk, 패키지를 지우면 같이 지워짐). 칩이 나타나면 기록을 지우고 설치를 이어 간다.
  # 근거 사본은 $BK/nochip-wifi.txt에도 둔다(업데이트로 $W가 지워져도 근거가 있던 차는 다시 깨우지 않음, 리뷰 M-1).
  _rechk=0
  wake_count
  _bid=$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)
  if [ -f $BK/wifi.nochip ] && [ ! -f $BK/nochip.rechk ] && [ ! -s $NOCHIP_LOG ] && [ ! -s $BK/nochip-wifi.txt ]; then
    : > $BK/nochip.rechk; _rechk=1
    log "Wi-Fi 칩 없음 기록이 있지만 근거 기록(nochip-wifi.txt)이 없음: 한 번만 다시 확인"
  elif [ -f $BK/wifi.nochip ] || [ -f $BK/wifi.woke ]; then
    return 2
  elif [ -z "$_bid" ]; then
    # 리뷰 M-1: 부팅 id를 못 읽으면 부팅을 셀 수 없으니 이번 실행은 깨우지 않는다
    log "부팅 id를 읽지 못해 이번에는 Wi-Fi를 깨우지 않음"
    return 3
  elif [ "$_wb" = "$_bid" ]; then
    # 이번 부팅에 이미 깨워 봤다(서비스 다시 시작): 다음 부팅에 다시
    return 3
  elif [ "$_wbad" = 1 ]; then
    # 재리뷰 L-1: 기록이 깨졌으면 깨우지 않기만 한다(칩 실패로 굳히지 않음)
    log "깨우기 횟수 기록을 읽지 못해 Wi-Fi를 깨우지 않음"
    return 2
  elif [ $_wc -ge $WAKE_BOOTS ]; then
    # 리뷰 M-1: 횟수를 다 썼다(지난 깨우기가 끝나기 전에 서비스가 멈춘 경우 등). 깨우지 않고 칩 실패로 끝낸다
    log "Wi-Fi 칩 깨우기를 $WAKE_BOOTS번 다 해 봄: 더 깨우지 않고 칩 실패로 끝냄"
    : > $BK/wifi.nochip
    wifi_restore_off
    return 1
  fi
  _wc=$((_wc + 1))
  # 리뷰 M-1: 횟수를 깨우기 전에 남긴다. 남기지 못하면 깨우지 않는다(셀 수 없으면 끝없이 깨울 수 있어서)
  # 1.7.4(L-6): 쓰지 못할 때 셸 오류 줄이 ap.log에 섞이지 않게 묶음의 오류를 버린다(아래 로그 한 줄이 남음)
  if ! { $BB mkdir -p $BK && echo "$_wc $_bid" > $BK/wifi.wake; } 2>/dev/null; then
    log "깨우기 횟수를 기록하지 못해 Wi-Fi를 깨우지 않음"
    return 2
  fi
  log "Wi-Fi 칩이 아직 안 보임: Wi-Fi를 한 번 켜서 칩을 깨움(부팅 $_wc/$WAKE_BOOTS번째)"
  ptrack 62 run "Wi-Fi 칩을 깨우는 중입니다"
  notice "Korea Projection: 무선 프로젝션 준비로 Wi-Fi를 한 번 켭니다. 카플레이·블루투스가 잠시 끊길 수 있습니다."
  # svc는 뒤에서 돌린다: 시스템 서버가 멈춰 있으면 바인더 호출이 끝나지 않을 수 있어, 아래 대기 시간이 상한이 된다
  svc wifi enable > /dev/null 2>&1 &
  _sp=$!
  _i=0; _mv3=0
  while [ $_i -lt ${WAKE_MAX:-30} ]; do
    sleep 2
    if wifi_chip_seen; then
      svc_done $_sp; log "Wi-Fi 칩이 나타남"
      # 칩이 한 번 보였다: 그 뒤 사라져도 부팅마다 다시 켜지 않는다(예전 wifi.woke 뜻 그대로)
      : > $BK/wifi.woke
      [ $_rechk = 1 ] && rm -f $BK/wifi.nochip
      return 0
    fi
    # 1.7.4(P-1, #276·#252): 순정 module_version은 깨우는 동안 logcat에 잠깐 남았다가 버퍼가 밀려 사라질 수 있다. 대기가 끝난 뒤에만
    # 읽으면 놓치고 다음 부팅에 또 깨운다(그때마다 USB·블루투스가 다시 시작). 리뷰 반영: 3회차(약 6초)마다 한 번 읽고(logcat 전체를
    # 2초마다 읽지 않게), 반복이 끝난 뒤 한 번 더 읽는다(아래 wifi_modver). 3이면 남은 대기를 그만둔다.
    # 칩 확인을 먼저 하므로 같은 회차에 칩이 보이면 칩 쪽이 이긴다
    _i=$((_i+1))
    if [ $((_i % 3)) = 0 ] && [ "$(wifi_modver_log)" = 3 ]; then _mv3=1; break; fi
  done
  if [ $_mv3 = 1 ]; then svc_done $_sp mv3; else svc_done $_sp; fi
  wifi_record "칩 깨우기 실패" $NOCHIP_LOG
  # 1.7.2 리뷰 M-1: $W는 업데이트 때 지워지므로 근거 사본을 $BK에도 둔다(업데이트 뒤 칩 없는 차가 Wi-Fi를 다시 켜지 않게)
  [ -s $NOCHIP_LOG ] && cat $NOCHIP_LOG 2>/dev/null > $BK/nochip-wifi.txt
  wifi_restore_off
  # 깨운 뒤 순정이 module_version 3을 남겼으면 부품 없음(W-1). P-1: 깨우는 중에 3을 봤으면 같은 갈래로 끝낸다
  if [ $_mv3 = 1 ]; then
    : > $BK/wifi.nopart; log "Wi-Fi를 깨우는 중 순정 module_version=3: 남은 대기를 그만두고 부품 없음으로 끝냄"
    return 1
  fi
  if [ "$(wifi_modver)" = 3 ]; then
    : > $BK/wifi.nopart; log "Wi-Fi를 켜도 칩이 나타나지 않음: 순정 module_version=3, 부품 없음으로 끝냄"
    return 1
  fi
  if [ $_rechk = 1 ]; then
    # 재리뷰 L-2: 1.7.0 근거 없던 칩 없음 차(다시 확인)도 새로 남은 module_version이 숫자이고 3이 아니면 D-9처럼 횟수를 남긴다
    _mvr=$(wifi_modver)
    case "$_mvr" in ''|*[!0-9]*) ;; *)
      rm -f $BK/wifi.nochip
      log "다시 확인에서도 칩이 안 보임: 근거 module_version=$_mvr(3 아님), 다음 부팅에 다시 깨움($_wc/$WAKE_BOOTS)"
      return 3 ;;
    esac
  elif [ $_wc -lt $WAKE_BOOTS ]; then
    log "Wi-Fi를 켜도 칩이 나타나지 않음: 다음 부팅에 다시 깨움($_wc/$WAKE_BOOTS, 순정 Wi-Fi 기록은 nochip-wifi.txt)"
    return 3
  fi
  log "Wi-Fi를 켜도 칩이 나타나지 않음 (다음 부팅부터 다시 하지 않음, 순정 Wi-Fi 기록은 nochip-wifi.txt)"
  : > $BK/wifi.nochip
  return 1
}

# 차에 있는 무선 모드가 우리 것이 아니고(mod.ours 없음) 한국 차를 지원하지 않는가(mod.json에 "region": "KOR" 항목이 없음).
# 우리 한국 차 빌드는 KOR 항목이 있다. 0: 그렇다(다른 판), 1: 모드가 없거나 우리 것이거나 한국 차를 지원함.
mod_foreign() {
  [ -s $HMGDATA/mods/$MOD_ID/mod.json ] && [ ! -f $BK/mod.ours ] && ! mod_kor
}
# 무선 모드 mod.json에 한국 차 항목이 있는가: "region": "KOR" 또는 "region": [..., "KOR", ...](공백·탭 무관).
# busybox가 없으면 toolbox grep(-E 됨, K3 탐사)으로 본다. 파일을 못 읽으면 1(한국 차 항목 없음으로 봄).
mod_kor() { bbx grep -q -E '"region"[[:space:]]*:[[:space:]]*(\[[^]]*)?"KOR"' $HMGDATA/mods/$MOD_ID/mod.json 2>/dev/null; }
# 베타 2(UP-2): 차에 있는 무선 모드가 "우리 한국 차 빌드"인가. 업스트림 무선 2.2.0-rc.8부터 mod.json에 KOR 항목이 있어 KOR만으로는
# 가를 수 없다(drafts/1.8.0-upstream-1.1.0.md 12장). 우리 빌드: KOR 항목이 있고, "wifi" 키가 없고(업스트림 rc.9에 생김), 판에 예비판
# 꼬리(-rc 등)가 없고, 이름이 "Korea Projection"으로 시작하거나(2.4.2부터) 이름을 붙이기 전 판(2.4.2 미만)이다.
# 이것으로 우리가 넣었던 모드만 새 판으로 바꾸고(mod_pending) 지운다(dg_off·preun). 차주가 넣은 업스트림 판은 건드리지 않는다
# 베타 3(B3-10, drafts/1.8.0-upstream-1.1.0.md 13장): 다른 사람이 고친 Korea Projection 수정판에 든 무선 모드는 이름·버전이 우리와 같지만
# 다른 키로 서명돼 있다. HMG-API는 키가 다르면 우리 새 버전 설치를 거부한다(signed by a different author, --force로도 안 됨).
# 그래서 "우리 모드"는 작성자 키(META-HMGAPI/manifest.json의 uuid)로 가른다. 키 기록이 없으면(예전 엔진·서명 없는 모드) 예전처럼 이름·버전으로
KP_MOD_UUID=2cc2e759-39f0-8c87-9bbf-8db2d7a811b9
MODKEY_MSG="다른 사람이 만든 무선 모드가 깔려 있습니다. HMG-API 앱에서 무선 모드를 지우고 적용한 뒤 재부팅해 주세요."
# 깔린 무선 모드의 작성자 키(영문 소문자·숫자·-만). 못 읽으면 빈 값
mod_uuid() {
  _mu=
  while IFS= read -r _l; do
    case "$_l" in *'"uuid"'*) _mu=${_l#*\"uuid\"}; _mu=${_mu#*\"}; _mu=${_mu%%\"*}; break ;; esac
  done < $HMGDATA/mods/$MOD_ID/META-HMGAPI/manifest.json 2>/dev/null
  case "$_mu" in *[!0-9a-f-]*) _mu= ;; esac
  echo "$_mu"
}
# ours | other | none(키 기록 없음·못 읽음)
mod_key() { _mk=$(mod_uuid); if [ -z "$_mk" ]; then echo none; elif [ "$_mk" = "$KP_MOD_UUID" ]; then echo ours; else echo other; fi; }
# 우리 모드처럼 보이는데(이름·버전) 다른 키 = 다른 사람이 고친 수정판의 모드. 업스트림 공식 모드(이름이 다름)는 여기에 들지 않는다
mod_fakekey() { [ -s $HMGDATA/mods/$MOD_ID/mod.json ] && [ "$(mod_key)" = other ] && mod_ourkor_name; }
mod_otherkey_tick() {
  if mod_fakekey; then
    [ -f $BK/mod.otherkey ] || { echo "seen $(date '+%m-%d_%H:%M' 2>/dev/null)" 2>/dev/null > $BK/mod.otherkey; log "무선 모드: 다른 키로 서명된 모드(다른 사람이 만든 모드)가 있음 — 바꾸지 않고 지우라고 안내"; }
    LAST_MSG=$MODKEY_MSG
  elif [ ! -f $HMGDATA/mods/$MOD_ID/mod.json ] && [ -f $BK/mod.otherkey ]; then
    rm -f $BK/mod.tried $BK/mod.otherkey $BK/mod.upd $BK/mod.ours $BK/mod.sig $BK/mod.sigdiff
    log "무선 모드: 다른 키 모드가 지워짐 — 차주가 일부러 지운 우리 모드가 아니므로 우리 모드를 새로 넣음(근거: mod.otherkey 기록)"
  fi
  return 0
}
mod_ourkor() {
  # 1.8.0 정식(P2): 설치 때 남긴 기록(mod.sig)과 지금 mod.json이 다르면 그 사실만 남긴다(판정은 아래 그대로)
  mod_sig_note
  [ "$(mod_key)" = other ] && return 1
  mod_ourkor_name
}
# --- 1.8.0 정식(P2, 1.8.1 계획 4장을 당김): 우리가 설치·업데이트한 무선 모드의 mod.json 기록 ---
# 설치·업데이트가 성공한 직후 $BK/mod.sig에 "<버전> <mod.json md5>"를 남긴다. mod_ourkor는 지금 mod.json과 견줘 다르면
# $BK/mod.sigdiff에 "<기록 버전> <지금 버전> md5 다름 <MM-DD_HH:MM>" 한 줄만 남긴다(같은 내용이면 다시 쓰지 않음. 로그는 쓰지 않는다:
# status.sh 리포트·preun도 mod_ourkor를 불러 표준 출력에 섞이면 안 됨).
# 판정에는 쓰지 않는다: HMG-API가 적용할 때 mod.json을 다시 쓰는지 아직 모른다(차 기록으로 본 뒤 1.8.1에서 정함)
mod_sig_write() {
  _msm=$(set -- $($BB md5sum < $HMGDATA/mods/$MOD_ID/mod.json 2>/dev/null); echo "$1")
  case "$_msm" in ''|*[!0-9a-f]*) return 0 ;; esac
  # 버전을 못 읽으면 "-"(칸이 비면 읽을 때 md5가 첫 칸으로 밀림)
  _msvv=$(mod_ver); case "$_msvv" in ''|*[!0-9A-Za-z.-]*) _msvv=- ;; esac
  echo "$_msvv $_msm" 2>/dev/null > $BK/mod.sig
  rm -f $BK/mod.sigdiff $W/mod.sigchk
}
mod_sig_note() {
  [ -f $BK/mod.sig ] && [ -f $HMGDATA/mods/$MOD_ID/mod.json ] || return 0
  # 정식 리뷰 L9: 부팅마다 한 번만 견준다(상태 화면을 새로 고칠 때마다 md5sum을 띄우지 않게). 설치·업데이트(mod_sig_write)가 표시를 지운다
  _mscb=$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null); _msco=; [ -f $W/mod.sigchk ] && read _msco < $W/mod.sigchk 2>/dev/null
  [ -n "$_mscb" ] && [ "$_msco" = "$_mscb" ] && return 0
  [ -n "$_mscb" ] && echo "$_mscb" 2>/dev/null > $W/mod.sigchk
  _msv=; _msh=; read _msv _msh < $BK/mod.sig 2>/dev/null
  _msm=$(set -- $($BB md5sum < $HMGDATA/mods/$MOD_ID/mod.json 2>/dev/null); echo "$1")
  case "$_msm" in ''|*[!0-9a-f]*) return 0 ;; esac
  [ "$_msm" = "$_msh" ] && return 0
  _msnv=$(mod_ver); case "$_msnv" in ''|*[!0-9A-Za-z.-]*) _msnv=- ;; esac
  _msn="${_msv:--} $_msnv md5"
  _mso=; [ -f $BK/mod.sigdiff ] && read _mso1 _mso2 _mso3 _msox < $BK/mod.sigdiff 2>/dev/null && _mso="$_mso1 $_mso2 $_mso3"
  [ "$_mso" = "$_msn" ] && return 0
  echo "$_msn 다름 $(date '+%m-%d_%H:%M' 2>/dev/null)" 2>/dev/null > $BK/mod.sigdiff
  return 0
}
mod_ourkor_name() {
  mod_kor || return 1
  _mof=$HMGDATA/mods/$MOD_ID/mod.json
  bbx grep -q '"wifi"[[:space:]]*:' $_mof 2>/dev/null && return 1
  _mov=$(mod_ver)
  case "$_mov" in ''|*-*) return 1 ;; esac
  bbx grep -q '"name"[[:space:]]*:[[:space:]]*"Korea Projection' $_mof 2>/dev/null && return 0
  ver_lt "$_mov" 2.4.2
}
# 베타 2(R3): 부품 없는 동글 차 첫 설치에서 동글을 기다리던 부팅($W/dg.modwait)에 동글이 붙으면 설치 마무리(fix_perms)를 한 번 더
# 뒤에서 띄운다(무선 모드가 아직 없고, 마무리가 돌고 있지 않을 때만, 한 부팅 한 번)
dg_modwait_tick() {
  [ -f $W/dg.modwait ] || return 0
  _dgmw1=; read _dgmw1 < $W/dg.modwait 2>/dev/null
  [ "$_dgmw1" = "${BID:-none}" ] || { rm -f $W/dg.modwait; return 0; }
  [ -f $HMGDATA/mods/$MOD_ID/mod.json ] && { rm -f $W/dg.modwait; return 0; }
  fix_running && return 0
  dg_car || return 0
  rm -f $W/dg.modwait
  # 리뷰(배포판 중간 2): 동글이 들락거려도 한 부팅 두 번까지만 다시 띄운다
  _dgmw2=; _dgmw3=0; [ -f $W/dg.modwait.n ] && read _dgmw2 _dgmw3 < $W/dg.modwait.n 2>/dev/null
  [ "$_dgmw2" = "${BID:-none}" ] || _dgmw3=0; case "$_dgmw3" in ''|*[!0-9]*) _dgmw3=0 ;; esac
  [ $_dgmw3 -lt 2 ] || { log "동글: 이번 부팅에 설치 마무리를 이미 두 번 다시 띄움 — 다음 시동에 다시 함"; return 0; }
  echo "${BID:-none} $((_dgmw3 + 1))" 2>/dev/null > $W/dg.modwait.n
  log "동글이 붙어 무선 모드 설치를 이어서 함(설치 마무리를 다시 띄움)"
  fix_perms &
  echo "$! ${BID:-$(cat $BOOT_ID 2>/dev/null)}" > $W/fix.pid
  return 0
}
# 차에 있는 무선 모드의 버전(mod.json의 첫 "version" 줄). 셸만 쓴다(sed·cut 없이). 못 읽으면 빈 값.
mod_ver() {
  _mv=
  while IFS= read -r _l; do
    case "$_l" in
      *'"version"'*) _mv=${_l#*\"version\"}; _mv=${_mv#*\"}; _mv=${_mv%%\"*}; break ;;
    esac
  done < $HMGDATA/mods/$MOD_ID/mod.json 2>/dev/null
  echo "$_mv"
}
# 1.5.7: 우리가 넣은 한국 차 빌드 모드를 패키지에 든 새 판으로 바꾼다(계기판 안내 수정 등 hooks.jar가 바뀜).
# 패키지 업데이트(1.5.6 → 1.5.7)는 모드를 건드리지 않으므로 여기서 한다. 하는 조건:
# - 우리가 넣은 모드(mod.ours)이고 지금도 한국 차 빌드(mod_kor)이며, 차에 있는 판이 패키지 것보다 낮을 때만.
#   차주가 넣은 다른 판이나 더 새 판은 건드리지 않는다.
# - 차주가 되돌리기 USB(kp-rollback)로 이전 판을 고정했으면($BK/mod.pin) 하지 않는다.
# - 같은 버전은 3번까지만 시도한다($BK/mod.upd: "<버전> <횟수>"). 일시적인 실패(엔진이 바쁨)는 다음 부팅에
#   다시 하고, 3번째도 실패하면 그때 한 번 알린다.
# - 적용(apply)은 하지 않는다: 이 함수는 부팅 2분 뒤 운행 중에도 돌 수 있고, 적용은 앱을 다시 시작시킬 수 있다.
#   새 판의 계획이 "nothing changed"(hooks.jar만 바뀜)면 재부팅만 안내하고, 아니면 차를 세운 뒤 앱에서
#   적용하라고 안내한다. 새 hooks.jar는 다음 재부팅부터 쓰인다.
# 실패해도 카플레이는 그대로다: 엔진은 설치에 실패하면 모드 폴더를 바꾸지 않는다.
# 돌려주는 값: 0 바꿈(재부팅 필요), 1 할 일 없음(또는 다음 부팅에 다시), 2 안내가 필요함(문구는 LAST_MSG)
mod_update() {
  # 1.7.3(K-7): 바꿀 조건은 mod_pending 한 곳에 둔다(설치된 판 _pv, 이번 판 시도 횟수 _un을 남긴다)
  mod_pending || return 1
  _iv=$_pv
  _un=$((_un + 1))
  echo "$MOD_VER $_un" > $BK/mod.upd
  # 리뷰 L10: 이번 부팅에 시도했는가(상태 화면이 "바꾸는 중"과 "이번에 못 바꿈, 재부팅하면 다시"를 가른다)
  echo "${BID:-$(cat $BOOT_ID 2>/dev/null)}" > $BK/mod.try
  set -- $($BB md5sum < $KP_HMG/$MOD_ID.zip 2>/dev/null)
  if [ "$1" != $MOD_MD5 ]; then
    log "무선 모드 업데이트 안 함: 패키지의 zip md5가 다름 (${1:-없음})"
    return 1
  fi
  ptrack 70 run "무선 모드를 새 버전($MOD_VER)으로 바꾸는 중입니다"
  if ! hmgapid engine install $KP_HMG/$MOD_ID.zip > $W/mod-update.txt 2>&1; then
    # B3-10: 작성자 키가 달라 거부되면 3번 기다리지 않고 바로 안내(키 기록을 못 읽은 차의 대비 길)
    if bbx grep -q "signed by a different author" $W/mod-update.txt 2>/dev/null; then
      echo "updfail $(date '+%m-%d_%H:%M' 2>/dev/null)" 2>/dev/null > $BK/mod.otherkey
      log "무선 모드 업데이트 거부: 차에 있는 무선 모드가 다른 키로 서명됨(다른 사람이 만든 모드) — 지우라고 안내"
      LAST_MSG=$MODKEY_MSG
      return 2
    fi
    log "무선 모드 업데이트 실패($_un/3), 이전 판($_iv) 그대로 ($W/mod-update.txt)"
    [ $_un -lt 3 ] && return 1
    LAST_MSG="무선 모드를 새 버전으로 바꾸지 못했습니다. 무선 프로젝션은 이전 버전으로 계속됩니다."
    return 2
  fi
  log "무선 모드 업데이트함: $_iv → $MOD_VER"; mod_sig_write
  hmgapid engine plan > $W/plan.txt 2>&1
  if plan_nothing; then
    return 0
  fi
  log "무선 모드 적용은 차주에게 맡김: 계획에 변경이 있음 ($W/plan.txt)"
  LAST_MSG="무선 모드를 새 버전으로 바꿨습니다. 차를 세운 뒤 HMG-API 앱에서 변경 사항을 적용하고 재부팅해 주세요."
  return 2
}
# 1.7.1: 우리가 넣은 무선 모드가 패키지에 든 새 판으로 바뀌기를 기다리는 중인가(mod_update와 같은 조건, 리포트·상태 파일이 씀).
# mod_update는 부팅 약 2분 뒤 돌아서, 설치 직후 만든 리포트에는 이전 판이 찍혔다(K3 #15 1.7.0, 2026-11-08).
mod_pending() {
  [ -f $BK/mod.ours ] && [ ! -f $BK/mod.pin ] && [ -f $HMGDATA/mods/$MOD_ID/mod.json ] && mod_ourkor || return 1
  _pv=$(mod_ver)
  [ -n "$_pv" ] && ver_lt "$_pv" $MOD_VER || return 1
  _uv=; _un=0
  [ -f $BK/mod.upd ] && read _uv _un < $BK/mod.upd
  [ "$_uv" = $MOD_VER ] || _un=0
  case "$_un" in ''|*[!0-9]*) _un=0 ;; esac
  [ $_un -lt 3 ]
}
# 계획(engine plan)에 적용할 것이 없는가: 모든 줄이 "same …"(이미 그대로) 또는 "nothing changed"·"hook plan:"
# 안내뿐일 때. 문제(problem)가 있거나 다른 줄이 하나라도 있으면 아니다(차주가 앱에서 보게 둔다).
# 1.5.7 니로(2026-11-07 21:36): 2.1.0→2.1.1 계획은 "same" 7줄뿐이었다("nothing changed" 줄 없음).
plan_nothing() {
  [ -s $W/plan.txt ] || return 1
  while IFS= read -r _l; do
    case "$_l" in
      "same     "*|"hook plan:"*|"note     "*|"") ;;
      # 리뷰 L3: WARNING 줄(예: ADB TCP 스위치 경고)은 정보일 뿐이다(plan_only_ours와 같이). 변경으로 보면 그 차는 업데이트 뒤 "실패"로 보인다
      "WARNING"*) ;;
      "nothing changed"*problem*) return 1 ;;
      "nothing changed"*) ;;
      # 1.8.0 RS-13(리뷰 중간 1): 모드 2.4.7부터 엔진이 켜진 우리 모드의 방화벽 규칙을 계획마다 "network  … [wireless-carplay-aa]"로
      # 보인다(바뀐 것이 없어도). 설치(install)가 이미 규칙을 넣으므로 적용할 것이 아니다. 다른 모드의 network 줄은 그대로 변경으로 본다
      "network  "*"[$MOD_ID]") ;;
      *) return 1 ;;
    esac
  done < $W/plan.txt
  return 0
}
# 버전 비교: $1이 $2보다 낮은가(major.minor.patch, 숫자만 비교하고 "-태그"는 무시). 숫자가 아니면 낮지 않음으로 본다.
ver_lt() {
  _x=${1%%-*}; _y=${2%%-*}; _k=0
  while [ $_k -lt 3 ]; do
    _p=${_x%%.*}; _q=${_y%%.*}
    # 빈 칸은 0으로 보고, 숫자가 아닌 글자가 있으면 비교하지 않는다
    # 붙여 봄: 여기서는 숫자가 아닌 글자만 거른다(한쪽이 빈 것은 바로 아래에서 0으로 보는 것이 뜻한 동작)
    case "$_p$_q" in *[!0-9]*) return 1 ;; esac
    [ "${_p:-0}" -lt "${_q:-0}" ] && return 0
    [ "${_p:-0}" -gt "${_q:-0}" ] && return 1
    case "$_x" in *.*) _x=${_x#*.} ;; *) _x= ;; esac
    case "$_y" in *.*) _y=${_y#*.} ;; *) _y= ;; esac
    _k=$((_k + 1))
  done
  return 1
}
# 1.8.0 U-1a(#246·#378): HMG-API 1.1.0의 state/local-map.json이 이 차의 전체 지도인가. 인자: 제품 첫 칸(차종), 둘째 칸(지역), 펌웨어.
# 판은 installed.txt의 version 줄(status.sh 리포트와 같은 곳). 판을 못 읽거나 1.0.x이면 아니다(1.0.x는 이 파일을 읽지 않음).
# 내용은 1.0.2 car.json과 같은 꼴("products"의 "<차종>.<지역>.", "firmware")이라고 본 추정이다(#246 원문: whole·차종·펌웨어).
# 꼴이 다르면 아니라고 보므로 예전처럼 map-car를 돌릴 뿐 더 나빠지지 않는다.
# 리뷰 중간 1: 꼴 추정에 기대지 않게, 우리가 map-car로 이 파일을 만들게 한 내비 제품 문자열을 $BK/automap.local에 남기고
# 넷째 인자(지금 제품 문자열)와 같으면 내용을 보지 않고 이 차 지도로 본다(내비 업데이트로 제품 문자열이 바뀌면 다시 만듦).
local_map_ok() {
  _lmf=$HMGDATA/state/local-map.json
  [ -f $_lmf ] || return 1
  _lv=$($BB awk '$1 == "version" { print $2; exit }' $HMGDATA/installed.txt 2>/dev/null)
  case "$_lv" in ''|0.*|1.0|1.0.*|1.0-*) return 1 ;; esac
  [ -n "$4" ] && [ "$(cat $BK/automap.local 2>/dev/null)" = "$4" ] && return 0
  $BB grep -q "\"$1\.$2\.\"" $_lmf && $BB grep -q "\"firmware\": *\"$3\"" $_lmf || return 1
  ! $BB grep -q '"whole": *false' $_lmf
}
setup_hmgapi() {
  if ! car_in "$(getprop ro.build.product 2>/dev/null)" "$CARS"; then
    ptrack 100 fail "지원하지 않는 차(한국 내수 펌웨어가 아님)입니다. 아무것도 바꾸지 않았습니다."
    return 0
  fi
  if [ ! -d $HMGDATA/maps ]; then
    log "자동 설정 건너뜀: HMG-API가 없음"
    ptrack 100 fail "HMG-API가 없습니다. HMG-API 1.0.2 이상을 먼저 설치해 주세요."
    return 0
  fi
  ptrack 30 run "MAP과 무선 모드를 확인하는 중입니다"
  $BB mkdir -p $BK
  # 1.6.1: 무선 모드가 없으면 "우리가 넣음"(mod.ours) 기록을 지운다. 남겨 두면 차주가 나중에 넣은 다른 판을
  # 우리 것으로 보고 안내하지 않거나, 패키지를 지울 때 그 모드를 지운다.
  # mod.tried는 남긴다(차주가 일부러 지운 우리 모드는 다시 넣지 않는다).
  [ -f $HMGDATA/mods/$MOD_ID/mod.json ] || rm -f $BK/mod.ours $BK/mod.sig $BK/mod.sigdiff
  # _fail: 안내를 이미 남김(알림 기록 또는 LAST_MSG → 마지막 진행 기록 문구) → "설정을 마쳤습니다"로 덮지 않는다
  _restart=0; _fail=0; _upd=0; _wchk=0; _wstop=0; _remap=0
  # 1.8.0 U-1f: 이번 부팅을 시작할 때 무선 모드가 이미 있었는가(지도만 다시 확인한 부팅의 안내를 고르는 데 씀)
  _modpre=0; [ -f $HMGDATA/mods/$MOD_ID/mod.json ] && _modpre=1
  # 지도: 차마다 임시 폴더에 다 복사한 뒤 한 번에 옮긴다(도중에 전원이 꺼져 반쪽 지도가 남지 않게).
  # 임시 폴더는 maps/.kp-tmp: HMG-API는 maps/<제조사>/<차종>/<지역>/<펌웨어>/만 읽으므로 반쪽 car.json을 보지 않는다.
  # 이 차의 지도만 넣는다: 폴더의 펌웨어가 같고 car.json의 products에 "<모델>.<지역>."이 있는 것.
  #   다른 차 지도는 HMG-API 공유 폴더에 남기지 않는다(복사 실패로 이 차 설정이 막히지도 않게).
  # 지도 확인(verify-map)은 지도를 넣었을 때만 한다. 실패하면 넣은 지도를 다시 빼고(차에 있던 다른 지도를
  #   가리지 않게) $BK/map.bad에 "<폴더> <car.json md5>"를 남긴다. 같은 지도는 다시 넣지 않고 모드도 설치하지
  #   않는다. 지도가 바뀐 새 버전이면(md5 다름) 다시 시도한다.
  # map.ours는 기록용이다: 지도는 HMG-API의 다른 모드도 쓰므로 패키지를 지워도 남긴다.
  _mapbad=0; _mine=0; _myrel=
  _prod=$(getprop ro.build.product 2>/dev/null)
  _pm=${_prod%%.*}; _pr=${_prod#*.}; _pr=${_pr%%.*}
  _tmp=$HMGDATA/maps/.kp-tmp
  # 우리가 무선을 맡지 않는 차(확인된 차가 아니고 무선 모드를 아직 넣지 않았을 때만 본다. 모드가 기능 파일을
  # 바꾸면 결과가 달라지므로). 시험 지원 차(CARS_TRY)와 자동 시험 차 모두 본다. 지도도 넣지 않는다.
  # - wireless.projection이 설치된 차: 같은 파일·속성을 다른 패키지가 관리한다(먼저 지워야 한다)
  # - 순정 핫스팟이 지금 켜져 있는 차(우리 것이 아닌 hostapd가 돎): 순정이 wlan0을 쓰고 있으므로 이번 부팅은
  #   건너뛰고 다음 부팅에 다시 본다. 순정 핫스팟 기능이 있어도 꺼져 있으면 우리 방식으로 한다
  #   (2026-11-06 소유자 결정. 벨로스터 N JSN은 기능이 있지만 순정 무선 카플레이는 없다).
  _skip=0
  if ! car_in "$_prod" "$CARS_OK" && [ ! -f $HMGDATA/mods/$MOD_ID/mod.json ]; then
    if [ -d $WPDIR ]; then
      log "무선 설정 안 함: wireless.projection이 설치되어 있음 (먼저 삭제해 주세요)"; _skip=1
      LAST_MSG="다른 패키지인 wireless.projection이 설치되어 있어 충돌할 수 있습니다. wireless.projection을 삭제한 뒤 재부팅해 주세요."
      if [ ! -f $BK/wp.told ]; then
        : > $BK/wp.told
        pnotice "Korea Projection: 다른 패키지인 wireless.projection이 설치되어 있어 충돌할 수 있습니다. wireless.projection을 삭제한 뒤 재부팅해 주세요."
      fi
    elif stock_ap_on; then
      log "무선 설정 안 함: 다른 hostapd가 돌고 있음(순정 핫스팟 등) (다음 부팅에 다시 봄)"; _skip=1
      LAST_MSG="순정 핫스팟이 켜져 있어 이번에는 설정하지 않았습니다. 순정 핫스팟을 끄고 재부팅해 주세요."
    elif pm list features 2>/dev/null | $BB grep -q '^feature:com\.hkmc\.software\.wifihotspot$'; then
      log "순정 핫스팟 기능이 있지만 꺼져 있음: 우리 방식으로 진행"
    fi
  fi
  [ $_skip = 1 ] && _mapbad=1
  # 1.8.0 U-1i: HMG-API 판(installed.txt의 version·build, 못 읽으면 빈 값)과 지난번에 본 판($BK/hmgapi.seen)
  _hvs=$(echo $($BB grep -E '^(version|build) ' $HMGDATA/installed.txt 2>/dev/null)); _hvold=$(cat $BK/hmgapi.seen 2>/dev/null)
  # U-1i 리뷰 중간 1: 이 HMG-API 판에서 HMG-API 지도(우리 것이 아님)의 확인이 실패한 기록이 있으면, 이 판 동안은 다시 확인·지도 만들기·
  # 모드 설치를 하지 않는다(부팅마다 무거운 verify-map·실패 알림을 되풀이하지 않게). HMG-API 판이 바뀌면 다시 해 본다(그 지도가 고쳐졌을 수 있음)
  _hvbad=0
  if [ $_skip = 0 ] && [ -n "$_hvs" ] && [ "$(cat $BK/map.fail.hv 2>/dev/null)" = "$_hvs" ]; then
    log "이 HMG-API 판($_hvs)에서 HMG-API 지도 확인에 실패한 기록이 있음: HMG-API가 바뀔 때까지 무선 모드를 넣지 않음"
    _hvbad=1; _mapbad=1; LAST_MSG="$MAPFAIL_MSG"
  fi
  for _c in $KP_HMG/maps/*/*/*/*/car.json; do
    [ $_skip = 1 ] && break
    [ -f "$_c" ] || continue
    _d=${_c%/car.json}; _rel=${_d#$KP_HMG/maps/}
    [ "${_rel##*/}" = "${_prod##*.}" ] && $BB grep -q "\"$_pm\.$_pr\.\"" $_c || continue
    # 같은 폴더에 지도가 이미 있으면(공식판 등) 그것을 쓴다: 실패 기록보다 먼저 본다
    [ -f $HMGDATA/maps/$_rel/car.json ] && continue
    set -- $($BB md5sum < $_c); _sum=$1
    if has_line "$_rel $_sum" $BK/map.bad; then
      log "지도 넣지 않음: $_rel (이 차에서 지도 확인에 실패한 지도)"; _mapbad=1; LAST_MSG="$MAPFAIL_MSG"; continue
    fi
    $BB rm -rf $_tmp
    if $BB mkdir -p $_tmp ${HMGDATA}/maps/${_rel%/*} && $BB cp $_d/*.json $_tmp/ && $BB chmod -R 700 $_tmp \
        && $BB rm -rf $HMGDATA/maps/$_rel && $BB mv $_tmp $HMGDATA/maps/$_rel; then
      echo "$_rel" >> $BK/map.ours
      log "지도 넣음: $_rel"
      _mine=1; _myrel=$_rel; _mysum=$_sum
    else
      $BB rm -rf $_tmp
      log "지도 넣기 실패: $_rel"; _fail=1; _mapbad=1
    fi
  done
  # 자동 시험(CARS_OK·CARS_TRY가 아닌 한국 차): 패키지에 이 차 지도가 없으므로, HMG-API에 이 차 지도가 없으면
  # HMG-API가 이 차의 파일로 지도를 만든다(engine map-car --write, 상태 probed). 아래 verify-map이 이 차에서
  # 확인해야 훅이 켜진다. 확인에 실패하면 만든 지도를 지우고 $BK/automap.bad를 남긴다(다시 만들지 않고 모드도
  # 넣지 않음, 패키지를 지우면 같이 지워진다. 업데이트·같은 판 다시 설치·HMG-API 다시 설치로는 지워지지 않는다: 1.7.4 B-9 시험).
  # automap.bad가 없을 때, HMG-API 업데이트로 지도 폴더가 바뀌면 다음 부팅에 다시 만든다.
  # 이미 있는 지도(공식판, 차주가 만든 것)는 건드리지 않고, 확인만 한 번 한다(_myrel 없음 → 지우지 않음).
  _auto=0
  car_in "$_prod" "$CARS_OK $CARS_TRY" || _auto=1
  # 위에서 건너뛰기로 한 차는 자동 시험도 하지 않는다
  [ $_skip = 1 ] && _auto=0
  # 1.8.0(#246 요청 3, 소유자 결정 11-18): 실패 기록(automap.bad)에는 그때의 HMG-API 판을 적는다. 판이 바뀌었으면 한 번만 다시 해 본다
  # (그 판에서 다시 실패하면 새 판을 적어 같은 판에서는 되풀이하지 않음). 1.7.x가 남긴 빈 기록은 지금 판에서 실패한 것으로 적기만 한다
  # (지금 다시 시도하지 않음: 판이 바뀐 것인지 모름). 판을 못 읽으면 예전처럼 그대로 둔다. 업데이트·재설치로는 남고 삭제로 지워지는 것은 그대로(B-9)
  if [ $_auto = 1 ] && [ -f $BK/automap.bad ] && [ -n "$_hvs" ]; then
    _abv=$(cat $BK/automap.bad 2>/dev/null)
    if [ -z "$_abv" ]; then
      echo "$_hvs" > $BK/automap.bad
    elif [ "$_abv" != "$_hvs" ]; then
      log "자동 시험: HMG-API가 바뀌어($_abv → $_hvs) 지도 확인 실패 기록을 한 번 다시 시도함"
      $BB rm -f $BK/automap.bad $BK/automap.checked $BK/automap.foreign
    fi
  fi
  if [ $_auto = 1 ] && [ -f $BK/automap.bad ]; then
    log "자동 시험: 이 차에서 만든 지도가 확인에 실패한 기록이 있어 무선 모드를 넣지 않음"; _mapbad=1; LAST_MSG="$MAPFAIL_MSG"
  elif [ $_auto = 1 ] && [ $_mine = 0 ] && [ $_hvbad = 0 ]; then
    _lm=$(echo "$_pm" | $BB awk '{ print tolower($0) }'); _lr=$(echo "$_pr" | $BB awk '{ print tolower($0) }')
    _have=0
    for _e in $HMGDATA/maps/*/$_lm/$_lr/${_prod##*.}/car.json; do [ -f "$_e" ] && _have=1; done
    # 1.8.0 U-1a(#246·#378): HMG-API 1.1.0은 차에서 만든 지도를 maps/가 아니라 state/local-map.json 한 파일에 둔다.
    # 1.0.x에 남은 그 파일은 HMG-API가 읽지 않으므로 믿지 않는다(1.0.2 동작 그대로)
    [ $_have = 0 ] && local_map_ok "$_pm" "$_pr" "${_prod##*.}" "$_prod" && _have=1
    if [ $_have = 1 ]; then
      [ -f $BK/automap.checked ] || { _mine=1; : > $BK/automap.checked; }
    elif [ -f $BK/automap.foreign ]; then
      # 다른 폴더 이름의 이 차 지도(공식판 등)를 쓰기로 했다: 무거운 map-car를 부팅마다 다시 돌리지 않는다
      :
    elif ptrack 40 run "이 차의 MAP을 만드는 중입니다(1~2분)"; hmgapid engine map-car --write > $W/map-car.txt 2>&1; then
      _nw=0
      while IFS= read -r _l; do
        case "$_l" in
          "written: "*) _r=${_l#written: }; _myrel=${_r%%" ("*} ;;
          "not written: HMG-API has a map"*) _nw=1 ;;
        esac
      done < $W/map-car.txt
      case "$_myrel" in
        /*|*..*)
          # 1.8.0 U-1a: 1.1.0은 "written: /data/hmgapi/state/local-map.json (...)"처럼 절대 경로를 낸다(#378). 확인은 하되
          # map.ours에 적지 않고 _myrel을 비워 확인이 실패해도 지우지 않는다(HMG-API 상태 파일은 HMG-API 몫)
          _mine=1
          if [ "$_myrel" = /data/hmgapi/state/local-map.json ]; then
            echo "$_prod" > $BK/automap.local
            log "자동 시험: 이 차의 파일로 지도를 만듦 (HMG-API state/local-map.json)"
          else
            log "자동 시험: 지도를 만듦, 알 수 없는 위치라 기록하지 않음 ($W/map-car.txt)"
          fi
          _myrel= ;;
        */*/*/*) _mine=1; echo "$_myrel" >> $BK/map.ours; log "자동 시험: 이 차의 파일로 지도를 만듦 ($_myrel)" ;;
        *)
          _myrel=
          if [ $_nw = 1 ]; then
            # 다른 폴더 이름으로 이 차 지도(공식판 등)가 이미 있다: 만들지 않고 그 지도를 한 번 확인한다(지우지 않음)
            log "자동 시험: HMG-API에 이 차 지도가 이미 있음 (그 지도를 씀)"
            : > $BK/automap.foreign
            [ -f $BK/automap.checked ] || { _mine=1; : > $BK/automap.checked; }
          else
            log "자동 시험: 지도를 만들지 않음 ($W/map-car.txt)"; _mapbad=1; LAST_MSG="$NOMAP_MSG"
          fi ;;
      esac
    else
      log "자동 시험: 지도 만들기 실패 ($W/map-car.txt)"; _fail=1; _mapbad=1; echo "$_hvs" > $BK/automap.bad
      notice "Korea Projection: 이 차의 HMG-API MAP을 만들지 못했습니다. USB를 꽂고 상태 화면의 [제보 파일 만들기]를 눌러 보내 주세요."
    fi
  fi
  # 1.8.0 U-1i(B-2, 조사 문서 1.8.0-upstream-1.1.0.md 1-6절): HMG-API를 설치·업데이트하면 maps/가 통째로 바뀐다. 1.1.0은 한국 지도를
  # 다른 폴더 이름(kia/kmc·hyundai/hmc)으로 넣어 1.0.2 때의 확인 기록(map-check.json, 폴더 이름까지 봄)이 맞지 않는다. 그런데 자동 시험을 마친 차는
  # automap.checked가 있어 다시 확인하지 않았다 → 훅이 꺼진 채로 남음. 그래서 HMG-API 판(installed.txt의 version·build)이 지난번에 본 것
  # ($BK/hmgapi.seen)과 다르면 `engine map`을 한 번 보고, HMG-API가 고른 지도가 "isn't checked on a car yet"이면 그 지도로 verify-map을 한 번 돈다
  # (지우지 않음: _myrel 없음). 판을 못 읽으면(installed.txt 없음) 하지 않는다. engine map이 실패하면 기록하지 않아 다음 부팅에 다시 본다.
  _u1i=0
  if [ $_skip = 0 ] && [ $_mine = 0 ] && [ $_mapbad = 0 ] && [ -n "$_hvs" ] && [ "$_hvs" != "$(cat $BK/hmgapi.seen 2>/dev/null)" ]; then
    if hmgapid engine map > $W/engine-map.txt 2>&1; then
      if $BB grep -q "isn't checked on a car yet" $W/engine-map.txt; then
        log "HMG-API가 바뀜($_hvs): HMG-API가 고른 지도가 이 차에서 확인 안 됨, 한 번 다시 확인"
        _mine=1; _myrel=; _u1i=1
      fi
      echo "$_hvs" > $BK/hmgapi.seen
    else
      log "HMG-API가 바뀜: 지도 상태를 읽지 못함, 다음 부팅에 다시 봄 ($W/engine-map.txt)"
    fi
  fi
  if [ $_mine = 1 ] && [ $_mapbad = 0 ]; then
    if ptrack 55 run "MAP을 확인하는 중입니다"; hmgapid engine verify-map > $W/verify-map.txt 2>&1; then
      log "지도 확인 통과 (다음 시작부터 훅 켜짐)"; _restart=1
      # U-1f: 모드는 이미 있고 HMG-API 판이 실제로 바뀐 부팅에만 "HMG-API가 바뀌어 지도를 다시 확인" 안내(리뷰 낮음: 그 밖에는 예전 문구)
      [ $_modpre = 1 ] && [ -n "$_hvold" ] && [ "$_hvold" != "$_hvs" ] && _remap=1
      # U-1i: 이 판에서 HMG-API가 고른 지도가 확인됐다(다음 부팅에 engine map을 또 보지 않게)
      [ -n "$_hvs" ] && { echo "$_hvs" > $BK/hmgapi.seen; $BB rm -f $BK/map.fail.hv; }
      [ $_auto = 1 ] && : > $BK/automap.checked
    else
      log "지도 확인 실패 ($W/verify-map.txt)"; _fail=1; _mapbad=1
      case "$_myrel" in *..*|/*) _myrel= ;; esac
      # 1.8.0 U-1e(B-3): HMG-API는 제품 접두어가 같으면 폴더 이름이 앞서는 지도를 고른다(1.1.0: kia/kmc가 우리 kia/niro를 이김). 실제로 확인된
      # 지도(verify 출력 "map <폴더>: …")가 우리 것이 아니면 우리 지도를 탓하지 않는다(지우지 않고 map.bad에도 안 적음). 그 줄이 없으면 예전처럼
      _vf=$($BB awk '$1 == "map" && $2 ~ /:$/ { f = substr($2, 1, length($2) - 1) } END { print f }' $W/verify-map.txt 2>/dev/null)
      _notours=$_u1i
      if [ -n "$_myrel" ] && [ -n "$_vf" ] && [ "$_vf" != "$_myrel" ]; then
        log "확인에 실패한 지도는 HMG-API의 $_vf (우리 지도 $_myrel 아님): 우리 지도는 그대로 둠"
        _myrel=; _notours=1
      fi
      # U-1i·U-1e 리뷰 중간 1: 우리 것이 아닌 지도(U-1i로 다시 확인한 HMG-API 지도, U-1e)의 실패는 영구 기록(automap.bad·map.bad) 대신
      # "이 HMG-API 판에서 실패"로 남긴다(자동 시험 차·확인된 차 모두 같게). 판을 못 읽으면 예전처럼 automap.bad
      if [ $_notours = 1 ] && [ -n "$_hvs" ]; then
        echo "$_hvs" > $BK/map.fail.hv; echo "$_hvs" > $BK/hmgapi.seen; LAST_MSG="$MAPFAIL_MSG"
        log "이 HMG-API 판에서는 다시 확인하지 않음(HMG-API가 바뀌면 다시 해 봄)"
      else
        [ $_auto = 1 ] && echo "$_hvs" > $BK/automap.bad
      fi
      if [ -n "$_myrel" ]; then
        $BB rm -rf $HMGDATA/maps/$_myrel
        [ $_auto = 1 ] || echo "$_myrel $_mysum" >> $BK/map.bad
        log "지도 뺌: $_myrel (다음 부팅에도 넣지 않음)"
        # 확인 기록(HMG-API state)은 방금 실패로 덮였다. 차에 이 차용 다른 지도(차주가 만든 것 등)가 있으면
        # 그 지도로 다시 확인해 예전처럼 훅이 켜지게 한다. 다른 지도가 없으면 실패하고 끝난다.
        if hmgapid engine verify-map > $W/verify-map2.txt 2>&1; then
          log "차에 있던 다른 지도로 다시 확인 통과"
        else
          log "다른 지도로 다시 확인 안 됨 ($W/verify-map2.txt)"
        fi
      fi
      notice "Korea Projection: HMG-API MAP 확인에 실패했습니다."
    fi
  fi
  # 무선 모드: 지도가 잘못됐으면 하지 않는다(훅 없이 기능 파일·속성만 바뀌므로).
  # mod.tried는 설치에 성공했거나 다시 해도 같은 결과일 때(zip md5 다름)만 남긴다. 일시적인 실패
  # (앞의 apply가 안 끝남, 데몬이 바쁨)는 다음 부팅에 다시 한다.
  # 베타 3(B3-10): 다른 사람이 만든(다른 키) 우리 이름의 모드가 있으면 바꾸지 않고 지우라고 안내한다(기록 mod.otherkey).
  # 그 모드를 차주가 지운 뒤에는 "차주가 일부러 지운 우리 모드"(mod.tried)로 보지 않고 우리 모드를 새로 넣는다(근거를 기록에)
  mod_otherkey_tick
  if [ $_mapbad = 0 ] && [ ! -f $HMGDATA/mods/$MOD_ID/mod.json ] && [ ! -f $BK/mod.tried ]; then
    set -- $($BB md5sum < $KP_HMG/$MOD_ID.zip 2>/dev/null)
    if [ "$1" != $MOD_MD5 ]; then
      : > $BK/mod.tried
      log "무선 모드 설치 안 함: 패키지의 zip md5가 다름 (${1:-없음})"
    # DG-9: 동글 차(동글 드라이버가 올라와 있음)는 내장 Wi-Fi 칩을 보지 않고 설치한다(모드 2.4.6의 동글 차 항목이 받음)
    # 리뷰 중간 1: 동글 사용 표시가 있으면(막힘 없음) 내장 칩을 깨우지 않는다(DG-12: 동글 차는 내장 Wi-Fi를 쓰지 않음, svc wifi enable이
    # USB를 다시 붙이는 일도 없게). 동글이 아직 안 보이면 설치하지 않고 이번 부팅은 기다림(_wk=4, 부품 없음으로 끝내지 않음)
    elif _wk=0; if dg_car; then log "동글 차: Wi-Fi 칩 확인을 건너뛰고 무선 모드를 설치함"; elif dg_builtin_off; then _wk=4; else wake_wifi; _wk=$?; fi; [ $_wk != 0 ]; then
      # 칩이 없으면 HMG-API가 모드를 받지 않는다: 설치를 시도하지 않는다. 안내는 처음 한 번만 한다.
      log "무선 모드 설치 안 함: Wi-Fi 칩을 찾지 못함"
      if [ $_wk = 4 ]; then
        log "동글 사용이 켜졌지만 동글(드라이버·USB)이 보이지 않음: 동글이 붙으면 이번 부팅에 이어서 설치함"
        _wstop=1; LAST_MSG="$DG_WAIT_MSG"
        # 베타 2(R3): 이 부팅에 동글이 붙으면 30초 점검(dg_modwait_tick)이 설치 마무리를 한 번 더 띄운다
        echo "${BID:-none}" 2>/dev/null > $W/dg.modwait
        # 5차 결과 반영: 순정 드라이버를 내린 부팅에 동글 길이 끝났으면(막힘·끄기·내리다 멈춤) 재부팅 안내
        # 리뷰 낮음 3: 이 하위 셸의 DG_ST는 띄울 때 값이라 지금 상태 파일로 본다
        _dgsn=; [ -f $W/dongle.state ] && read _dgsn _dgsx < $W/dongle.state 2>/dev/null
        case "${_dgsn:-$DG_ST}" in wait|up|ok) ;; *) dg_rm_now && LAST_MSG="$DG_REBOOT_MSG" ;; esac
      elif [ $_wk = 3 ]; then
        # 1.7.3(G-1·W-4): 아직 확인 중. 실패로 끝내지 않고 재부팅 뒤 다시 깨운다(진행 기록은 "재부팅 필요", 화면은 판정이 문구를 정함)
        _wchk=1
        LAST_MSG="$WIFI_CHECK_MSG"
      elif [ $_wk = 1 ]; then
        _fail=1
        if [ -f $BK/wifi.nopart ]; then LAST_MSG="$NOPART_MSG"; else LAST_MSG="$NOCHIP_MSG"; fi
        pnotice "Korea Projection: $LAST_MSG"
      elif [ $_wk = 2 ] && [ -f $BK/wifi.nochip ]; then
        # 1.7.4(P-4 리뷰 낮음 1): 칩 실패로 끝난 차. 같은 부팅에 지도 확인이 통과해도(_restart) "설정을 마쳤습니다"가 나가지 않게
        # 이유를 둔다(화면 판정은 status.sh의 nochip이 맡음). 알림은 처음 끝날 때(_wk=1) 한 번만 했으므로 여기서는 하지 않는다
        _wstop=1; LAST_MSG="$NOCHIP_MSG"
      elif [ $_wk = 2 ] && [ -f $BK/wifi.woke ]; then
        # 1.7.4(P-4): 칩을 본 기록(wifi.woke)은 있는데 지금 칩이 없다(다시 깨우지 않음). 예전에는 이유 없이 "넣지 못했습니다"
        _wstop=1; LAST_MSG="$WIFIGONE_MSG"
      fi
    elif ptrack 70 run "무선 모드를 설치하는 중입니다"; ! hmgapid engine install $KP_HMG/$MOD_ID.zip > $W/mod-install.txt 2>&1; then
      log "무선 모드 설치 실패, 다음 부팅에 다시 함 ($W/mod-install.txt, HMG-API 칩 기록 $([ -f $WIFI_SEEN ] && echo 있음 || echo 없음))"; _fail=1
      notice "Korea Projection: HMG-API 무선 모드를 설치하지 못했습니다."
    else
      : > $BK/mod.tried; : > $BK/mod.ours; mod_sig_write
      log "무선 모드 설치함"
      if ! plan_only_mod; then
        log "무선 모드 적용 안 함: 계획에 다른 변경이 있거나 훅이 꺼짐 ($W/plan.txt)"; _fail=1
        notice "Korea Projection: 무선 모드를 설치했습니다. HMG-API 앱에서 변경 사항을 적용한 뒤 재부팅해 주세요(RESET 버튼 또는 NEMESIS 재부팅)."
      elif ptrack 85 run "무선 모드를 적용하는 중입니다"; hmgapid engine apply > $W/mod-apply.txt 2>&1; then
        log "무선 모드 적용함"; _restart=1
      else
        log "무선 모드 적용 실패 ($W/mod-apply.txt)"; _fail=1
        notice "Korea Projection: 무선 모드 적용에 실패했습니다. HMG-API 앱을 확인해 주세요."
      fi
    fi
  fi
  # 1.5.7: 이미 있는 우리 모드를 새 판으로(위에서 막 설치했으면 버전이 같아 할 일 없음)
  if [ $_mapbad = 0 ] && [ $_fail = 0 ]; then
    mod_update; _mu=$?
    if [ $_mu = 0 ]; then
      _restart=1; _upd=1
    elif [ $_mu = 2 ]; then
      _fail=1
      pnotice "Korea Projection: $LAST_MSG"
    fi
  fi
  # 1.6.1: 차에 이미 있는 무선 모드가 우리가 넣은 것이 아니고 한국 차를 지원하지 않는 판이면(예: HMG-API 기본 2.1.0,
  # 북미 EV6·아이오닉5용, #25 팰리세이드) 덮어쓰지 않는다(차주 것). 대신 무엇을 하면 되는지 알린다.
  # 토스트는 띄우지 않는다(금방 사라짐, 소유자 결정). 안내는 Launch 화면에 남긴다: 진행 기록의 실패 문구(이번 부팅)와,
  # 부팅이 지나도 상태 파일의 mod_foreign=yes를 앱이 보고 맨 위 판정 줄에 같은 안내를 보인다(Report.verdict).
  # 차주가 지우면 다음 부팅에 위에서 우리 모드를 넣는다(Wi-Fi 칩·지도 기록 등 다른 이유로 멈출 수 있어 "시도"로 쓴다).
  # 지도가 잘못됐으면 그 사유를 먼저 보인다.
  if [ $_fail = 0 ] && [ $_mapbad = 0 ] && mod_foreign; then
    log "무선 모드 설치 안 함: 한국 차를 지원하지 않는 다른 무선 모드가 이미 있음(덮어쓰지 않음)"
    LAST_MSG="차에 있는 HMG-API 무선 모드가 국내용이 아닙니다. HMG-API 앱에서 그 모드를 지우고 적용한 뒤 재부팅해 주세요."
    _fail=1
  fi
  # 진행 기록의 마지막 결과(상태 화면 앱이 보여 줌)
  # 1.7.4(P-2, #276·#252·#78·#228): Wi-Fi 확인 중(_wchk)이면 지도 확인이 통과했어도(_restart) "설정을 마쳤습니다"가 아니다(모드를 넣지 않음).
  # 새 판으로 바꾼 경우(_upd)는 그대로 먼저 본다
  if [ $_restart = 1 ] && [ $_fail = 0 ] && [ $_upd = 1 ]; then
    ptrack 100 reboot "$MODUPD_MSG"
  elif [ $_wstop = 1 ] && [ $_fail = 0 ]; then
    # 1.7.4(P-4 리뷰 낮음 1): 칩을 다시 깨우지 않는 차(칩 실패·칩이 사라짐). 지도 확인이 통과했어도 무선 모드를 넣지 않았다
    ptrack 100 fail "$LAST_MSG"
  elif [ $_wchk = 1 ] && [ $_fail = 0 ]; then
    ptrack 100 reboot "$WIFI_CHECK_MSG"
  elif [ $_restart = 1 ] && [ $_fail = 0 ] && [ $_remap = 1 ]; then
    # 1.8.0 U-1f(B-4): 모드는 이미 있고 지도만 다시 확인한 부팅(HMG-API 업데이트로 maps/가 바뀜). 다시 시작해야 훅이 켜진다
    ptrack 100 reboot "$REMAP_MSG"
  elif [ $_restart = 1 ] && [ $_fail = 0 ]; then
    ptrack 100 reboot "무선 프로젝션 설정을 마쳤습니다. 3분 후 재부팅해 주세요."
  elif [ $_fail = 1 ]; then
    ptrack 100 fail "${LAST_MSG:-무선 프로젝션 설정에 실패했습니다. USB를 꽂고 상태 화면의 [제보 파일 만들기]를 눌러 보내 주세요.}"
  elif setup_done; then
    ptrack 100 done "무선 프로젝션 설정이 끝나 있습니다."
  elif [ -f $HMGDATA/mods/$MOD_ID/mod.json ] && [ -z "$LAST_MSG" ]; then
    ptrack 100 fail "HMG-API 무선 모드가 있지만 꺼져 있거나 적용되지 않았습니다. HMG-API 앱에서 켜고 변경 사항을 적용한 뒤 재부팅해 주세요."
  elif [ -z "$LAST_MSG" ] && [ -f $BK/mod.tried ] && [ ! -f $HMGDATA/mods/$MOD_ID/mod.json ] \
      && [ "$(set -- $($BB md5sum < $KP_HMG/$MOD_ID.zip 2>/dev/null); echo "$1")" = $MOD_MD5 ]; then
    # 1.7.2(P-13, 이슈 #27 약속): 우리가 넣은 모드를 차주가 HMG-API 앱에서 지운 차. mod.tried가 남아 다시 넣지 않는다(차주 선택 존중).
    # "넣지 못했습니다"로 보이면 실패로 오해하므로 지운 기록과 다시 쓰는 방법을 알린다. (zip md5가 다른 경우는 아래 보통 문구)
    log "무선 모드 안 넣음: 차주가 HMG-API 앱에서 지운 기록(mod.tried)이 있음"
    ptrack 100 fail "무선 모드가 지워진 기록이 있어 다시 넣지 않습니다(HMG-API 앱에서 지웠거나 HMG-API를 다시 설치한 경우). 다시 쓰려면 NEMESIS에서 Korea Projection을 삭제하고 다시 설치한 뒤 재부팅해 주세요."
  else
    ptrack 100 fail "${LAST_MSG:-무선 모드를 넣지 못했습니다. USB를 꽂고 상태 화면의 [제보 파일 만들기]를 눌러 보내 주세요.}"
  fi
  if [ $_restart = 1 ] && [ $_fail = 0 ] && [ $_upd = 1 ]; then
    pnotice "Korea Projection: $MODUPD_MSG"
  elif [ $_restart = 1 ] && [ $_fail = 0 ] && [ $_wstop = 1 ]; then
    # P-4 리뷰 낮음 1: "설정을 마쳤습니다" 대신 그 이유(진행 기록을 쓰는 동안은 ap.log에만)
    pnotice "Korea Projection: $LAST_MSG"
  elif [ $_restart = 1 ] && [ $_fail = 0 ] && [ $_wchk = 1 ]; then
    # P-2: 예전에 "설정을 마쳤습니다"가 나가던 자리에 확인 중 문구를(확인 중만이면 예전처럼 알림 없음)
    pnotice "Korea Projection: $WIFI_CHECK_MSG"
  elif [ $_restart = 1 ] && [ $_fail = 0 ] && [ $_remap = 1 ]; then
    pnotice "Korea Projection: $REMAP_MSG"
  elif [ $_restart = 1 ] && [ $_fail = 0 ]; then
    if car_in "$_prod" "$CARS_OK"; then
      pnotice "Korea Projection: 무선 프로젝션 설정을 마쳤습니다. 3분 후 재부팅해 주세요."
    else
      pnotice "Korea Projection: 무선 프로젝션 설정을 마쳤습니다(자동으로 설정한 차). 3분 후 재부팅한 뒤 결과를 제보해 주시면 지원 목록에 넣습니다."
    fi
  fi
  return 0
}

# 진행 기록은 설정이 아직 끝나지 않았을 때만 남긴다(P_ON=1). 이미 끝난 차는 부팅마다 조용히 확인만 한다.
# 1.7.3(리뷰 H1): fix_perms 안(P_HOLD=1)에서는 "재부팅 필요"(reboot)를 바로 쓰지 않고 P_HELD에 두었다가, 뒤의 권한 파일
# 되돌리기(/system remount·쓰기·HMG-API apply)까지 끝난 뒤 fix_perms가 쓴다. 그동안은 "마무리하는 중"(95%, run)을 보인다.
# 그래야 상태 화면의 [지금 재부팅](reboot일 때만 보임)이 /system을 고치는 도중에 눌리지 않는다.
ptrack() {
  [ "$P_ON" = 1 ] || return 0
  if [ "$P_HOLD" = 1 ] && [ "$2" = reboot ]; then
    P_HELD="$3"
    prog 95 run "설치를 마무리하는 중입니다"
    return 0
  fi
  prog "$@"; return 0
}
# 1.7.3(U-5): 진행 기록을 쓰는 동안(P_ON=1)에는 상태 화면 맨 위 판정 줄이 같은 문장을 보이므로 알림으로 또 쓰지 않는다
# (ap.log에는 남김). 진행 기록을 쓰지 않는 경로(P_ON=0)는 알림으로 남긴다.
pnotice() {
  if [ "$P_ON" = 1 ]; then log "안내(진행 기록에 남김): ${1#Korea Projection: }"; return 0; fi
  notice "$@"
}
fix_perms() {
  # 지원하지 않는 차는 진행 기록을 쓰지 않는다(main이 "지원하지 않는 차"를 쓴다). 권한 파일 확인은 그대로 한다.
  P_ON=0; setup_done || P_ON=1
  # 1.7.2(P-18): 우리 모드를 새 판으로 바꿀 차도 진행 기록을 남긴다(상태 화면에 "기다림 → 재부팅" 할 일을 보이게)
  MOD_WAIT=0; mod_pending && { P_ON=1; MOD_WAIT=1; }
  car_in "$(getprop ro.build.product 2>/dev/null)" "$CARS" || P_ON=0
  # 재리뷰(낮음): 같은 부팅에 서비스가 다시 시작돼도 이미 쓴 "재부팅 필요"를 run(기다림)·fail로 덮지 않는다. 덮으면 [지금 재부팅]
  # 버튼이 사라지고 차주가 할 일(재부팅)이 가려진다. 이번 실행은 진행 기록 없이 확인만 한다(재부팅 뒤 다시 본다).
  if [ "$P_ON" = 1 ] && prog_reboot_this_boot; then
    log "이번 부팅에 이미 '재부팅 필요'를 씀: 진행 기록은 그대로 두고 확인만 함"
    P_ON=0
  fi
  if ! command -v hmgapid >/dev/null 2>&1; then
    ptrack 100 fail "HMG-API가 없습니다. HMG-API 1.0.2 이상을 먼저 설치해 주세요."
    rm -f $W/fix.pid; return 0
  fi
  P_HOLD=1; P_HELD=
  _fix_perms
  P_HOLD=0
  # 1.7.3(리뷰 H1): 미뤄 둔 "재부팅 필요"를 마무리가 끝난 지금 쓴다. 그 사이 다른 결과(실패 등)를 썼으면 덮지 않는다
  if [ -n "$P_HELD" ] && $BB grep -q '^state=run$' $PROG 2>/dev/null; then ptrack 100 reboot "$P_HELD"; fi
  P_HELD=
  rm -f $W/fix.pid
}
_fix_perms() {
  # 1.7.4(L-2b): 1.7.1까지 쓴 권한 파일 이름을 서비스 시작 때 ap.log에서 옮기던 줄(perms_seed 호출)을 지웠다(1.7.2부터 perms.ours가 있음).
  # perms_seed 함수는 삭제 경로(perms_revert)가 계속 쓴다
  # 부팅 직후 HMG-API의 부팅 단계(hook-check: remount rw → 쓰기 → ro)와 겹치지 않게 잠시 기다린다.
  # 10초씩 나눠 기다리며 진행 기록을 5→25%로 올린다(사용자가 멈춘 줄 알고 삭제하지 않게)
  # 1.7.2(P-18): FIX_DELAY는 이번 부팅에서 서비스가 처음 시작한 때($W/svc.start "<부팅 id> <부팅 뒤 초>", main이 씀)부터
  # 센다(리뷰 M1: 커널 부팅부터 세면 보통 부팅에서도 HMG-API 부팅 단계와의 간격이 줄어든다). 같은 부팅에 서비스가 다시
  # 시작돼도(#60 K3 15:56) 처음부터 다시 기다리지 않고, 이미 지났으면 바로 한다. uptime이나 기록을 못 읽으면 예전처럼
  # 지금부터 FIX_DELAY를 다 기다린다.
  _wt=0; _fd=${FIX_DELAY:-120}
  _up=$($BB awk '{ print int($1) }' $UPTIME 2>/dev/null)
  case "$_up" in ''|*[!0-9]*) _up= ;; esac
  _sb0=; _su0=
  [ -f $W/svc.start ] && read _sb0 _su0 < $W/svc.start
  case "$_su0" in ''|*[!0-9]*) _su0= ;; esac
  if [ -n "$_up" ] && [ -n "$_su0" ] && [ -n "$_sb0" ] && [ "$_sb0" = "${BID:-$(cat $BOOT_ID 2>/dev/null)}" ] && [ $_up -ge $_su0 ]; then
    _wt=$((_up - _su0)); [ $_wt -gt $_fd ] && _wt=$_fd
    [ $_wt -gt 0 ] && log "권한 파일 확인 대기: 첫 시작 뒤 $((_up - _su0))초 지남, 남은 대기 $((_fd - _wt))초"
  fi
  while [ $_wt -lt $_fd ]; do
    if [ "$MOD_WAIT" = 1 ]; then
      ptrack $((5 + 20 * _wt / (_fd > 0 ? _fd : 1))) run "무선 모드를 새 버전으로 바꾸기 전에 기다리는 중입니다(약 $((_fd - _wt))초). 재부팅 안내가 나오면 재부팅해 주세요."
    else
      ptrack $((5 + 20 * _wt / (_fd > 0 ? _fd : 1))) run "HMG-API가 준비되기를 기다리는 중입니다(약 $((_fd - _wt))초)"
    fi
    _s=$((_fd - _wt)); [ $_s -gt 10 ] && _s=10
    sleep $_s; _wt=$((_wt + _s))
  done
  # 그사이 패키지가 지워졌으면 그만둔다
  [ -d $W ] || return 0
  # HMG-API 데몬이 뜰 때까지 기다린다 (최대 5분). 이 함수는 뒤에서 돌므로 핫스팟을 늦추지 않는다.
  _i=0
  until hmgapid ping >/dev/null 2>&1; do
    ptrack 27 run "HMG-API 응답을 기다리는 중입니다"
    _i=$((_i+1)); [ $_i -ge 30 ] && { log "권한 파일 확인 건너뜀: HMG-API 데몬 응답 없음"; ptrack 100 fail "HMG-API가 응답하지 않습니다. 재부팅한 뒤 다시 확인해 주세요."; return 0; }
    sleep 10
  done
  # 1.8.0 DG-9 (A)안: 동글을 그만 쓰거나 막힌 차는 우리 모드를 지우고 동글 차 속성 0(설치 판단보다 먼저)
  dg_off_due
  setup_hmgapi
  # 줄에 "[wireless-carplay-aa]"가 있어 단어 나누기 때 파일 이름 패턴으로 풀리지 않게
  set -f
  _todo=$W/perms.todo
  : > $_todo
  : > $W/perms.mods
  hmgapid engine status 2>/dev/null | while IFS= read -r _l; do
    case "$_l" in
      "CHANGED "*"$PERMS/"*".xml "*", found absent"*) ;;
      *) continue ;;
    esac
    set -- $_l
    _p=$2; _m=$3; _n=${_p##*/}; _n=${_n%.xml}
    case "$_n" in com.hkmc.*|android.hardware.*|android.software.*) ;; *) continue ;; esac
    [ "$_p" = "$PERMS/$_n.xml" ] || continue
    _e=${_l#*expected }; _e=${_e%%,*}
    set -- $(perm_text "$_n" | $BB md5sum)
    if [ "$1" = "$_e" ]; then echo "$_n" >> $_todo; echo "$_m" >> $W/perms.mods
    else log "권한 파일 되돌리기 건너뜀: $_n (기록 md5가 HMG-API 형식과 다름)"; fi
  done
  [ -s $_todo ] || { set +f; rm -f $_todo; return 0; }
  _was_ro=0; system_ro && _was_ro=1
  hmgapid remount rw >/dev/null 2>&1
  : > $W/perms.done
  while IFS= read -r _n; do
    [ -f $PERMS/$_n.xml ] && continue
    if perm_text "$_n" > $PERMS/$_n.xml && $BB chmod 644 $PERMS/$_n.xml; then
      echo "$_n.xml" >> $W/perms.done; log "권한 파일 되돌림: $_n"
      # 1.7.2(P-14): 우리가 쓴 파일 이름을 남긴다(삭제할 때 perms_revert가 이것만 되돌린다). 업데이트해도 $BK는 남는다.
      [ -d $BK ] && { has_line "$_n" $PERMS_OURS || echo "$_n" >> $PERMS_OURS; }
    else
      rm -f $PERMS/$_n.xml; log "권한 파일 쓰기 실패: $_n"
    fi
  done < $_todo
  [ $_was_ro = 1 ] && hmgapid remount ro >/dev/null 2>&1
  rm -f $_todo
  if [ ! -s $W/perms.done ]; then set +f; rm -f $W/perms.done; return 0; fi
  if ! plan_only_ours; then
    log "HMG-API apply 안 함: 계획에 다른 변경이 있음 ($W/plan.txt). HMG-API 앱에서 적용해 주세요"
    _m="Korea Projection: 무선 프로젝션 기능 파일을 복구했습니다. HMG-API 앱에서 변경 사항을 적용한 뒤 재부팅해 주세요(RESET 버튼 또는 NEMESIS 재부팅)."
  elif hmgapid engine apply >/dev/null 2>&1; then
    log "HMG-API apply 완료"
    _m="Korea Projection: 무선 프로젝션 기능 파일을 복구했습니다. 재부팅해 주세요(RESET 버튼 또는 NEMESIS 재부팅)."
  else
    log "HMG-API apply 실패"
    _m="Korea Projection: 무선 프로젝션 기능 파일을 복구했지만 HMG-API 적용이 실패했습니다. HMG-API 앱을 확인해 주세요."
  fi
  set +f
  rm -f $W/perms.done
  notice "$_m"
}

# --- 1.7.2(P-14): 패키지를 지울 때 우리가 쓴 무선 권한 파일 되돌리기 (소유자 결정 2026-11-08) ---
# 문제: fix_perms가 쓴 권한 파일이 삭제 뒤에도 남아, HMG-API까지 지우면 유선 카플레이도 안 될 수 있다
# (니로 2026-11-07, FINDINGS "시스템 파일 순정 되돌리기 실행"). 순정은 권한 파일 2개가 없고, featurexml.cfg의
# 해당 줄(니로 17·18번째)이 "-…xml"이다(부팅 때 그 파일을 지움). drafts/stock-re/decision-stock-check.md 4절.
# fix_perms는 파일이 없을 때만 쓰므로 우리가 바꾸기 전 상태는 "파일 없음"이다. 그래서 권한 파일 되돌리기는 지우기다.
# 대상: $PERMS_OURS에 적힌 이름. 1.7.1까지는 이 기록이 없어 ap.log(·ap.log.1)의 "권한 파일 되돌림: <이름>" 줄
# (fix_perms만 쓰는 줄)로도 찾는다. 이름은 com.hkmc.*·android.hardware.*·android.software.* 꼴만 받는다.
# 다음을 모두 만족하는 파일만 지운다(아니면 그대로 두고 기록만):
#  - 파일 내용이 지금도 우리가 쓴 것과 같다(md5). 다르면 다른 쪽이 바꾼 것이다.
#  - wireless.projection이 설치돼 있지 않다(그 패키지도 무선 권한 파일과 featurexml을 바꾼다).
#  - HMG-API가 그 파일을 관리하지 않는다(engine status에 그 경로가 없음). 관리 중이면 HMG-API 모드 것이므로
#    HMG-API의 모드 삭제·되돌리기에 맡긴다. hmgapid가 있는데 응답이 없거나 상태를 못 읽으면 판단할 수 없어 둔다.
# featurexml.cfg: 권한 파일을 지웠거나 이미 없는 이름 가운데 무선 카플레이·AA 2개(com.hkmc.software.connectivity.
# *_wireless)만, 그 줄이 정확히 "#-<권한 폴더>/<이름>.xml"이면 앞의 "#"만 뗀다. 다른 줄(12번째 wifihotspot은
# HMG-API 몫)은 건드리지 않는다. 경로는 HMG-API와 같은 곳(ro.mobis.targetdir)에서 얻는다. HMG-API가 이 파일을
# 관리 중이면 두고, 줄바꿈(CRLF)을 그대로 지키고, 바뀐 줄이 그 줄뿐이고 크기가 정확히 그만큼 줄었는지
# 미리 확인한다. 예상과 다르면 featurexml은 두고 기록만 한다(권한 파일 되돌리기는 그대로 한다).
# /system은 nemesis remount(안 되면 hmgapid remount)로 열고, 실제로 rw가 됐을 때만 바꾼다. 하나라도 실패하면
# 지운 권한 파일은 같은 내용(644)으로 다시 쓰고 featurexml은 원본으로 되돌려 처음 상태로 둔다. 원래 ro였으면 ro로.
# 알려진 한계: HMG-API의 "순정 백업"이 이미 바뀐 판이면(니로 c3fa…) 나중에 HMG-API를 지울 때 "#"이 다시 생길 수 있다.
# 기록: 출력(NEMESIS 삭제 출력)과 ap.log. 파일 이름만 적는다(비밀값 없음).
# 돌려주는 값: 0 할 일 없음·되돌림·남겨야 해서 둠, 1 되돌려야 하는데 못 함(그대로 둠)
FX_PERMS=${FX_PERMS:-/system/etc/permissions}
pr_log() { log "$*"; [ -d "${APLOG%/*}" ] && log "$*" 2>/dev/null >> $APLOG; return 0; }
pr_add() {
  case "$1" in com.hkmc.*|android.hardware.*|android.software.*) ;; *) return 0 ;; esac
  case "$1" in *[!A-Za-z0-9._-]*) return 0 ;; esac
  case " $_prn " in *" $1 "*) ;; *) _prn="$_prn $1" ;; esac
  return 0
}
# remount: nemesis로 하고, 종료 코드와 상관없이 실제 상태를 본 뒤 아니면 hmgapid로 한 번 더(리뷰 M4). 0: 원하는 상태가 됨
sys_remount() {
  nemesis remount $1 >/dev/null 2>&1
  if [ "$1" = rw ]; then system_ro || return 0; else system_ro && return 0; fi
  hmgapid remount $1 >/dev/null 2>&1
  if [ "$1" = rw ]; then ! system_ro; else system_ro; fi
}
# 1.7.1까지는 기록이 없어 ap.log(·ap.log.1)의 "권한 파일 되돌림: <이름>" 줄(fix_perms만 씀)에서 이름을 찾아 기록에 더한다
perms_seed() {
  for _f in $APLOG.1 $APLOG; do
    [ -f "$_f" ] || continue
    for _n in $($BB awk '$3 == "권한" && $4 == "파일" && $5 == "되돌림:" && NF == 6 { print $6 }' "$_f" 2>/dev/null); do
      _prn=; pr_add "$_n"
      [ -n "$_prn" ] && { has_line "$_n" $PERMS_OURS || echo "$_n" >> $PERMS_OURS; }
    done
  done
  return 0
}
# featurexml에서 "#" 뗄 줄을 만든다: $1 원본, $2 결과, $3 이름 목록. 0: 바꿀 줄이 있고 확인 통과, 1: 할 일 없음, 2: 예상과 다름
fx_build() {
  rm -f "$2" "$2.n"
  $BB awk -v names="$3" -v pfx="$FX_PERMS" -v cnt="$2.n" '
    BEGIN { k = split(names, a, " "); for (i = 1; i <= k; i++) want["#-" pfx "/" a[i] ".xml"] = 1; n = 0 }
    { l = $0; if (substr(l, length(l), 1) == "\r") l = substr(l, 1, length(l) - 1)
      if (l in want) { print substr($0, 2); n++ } else print $0 }
    END { print n > cnt }' "$1" 2>/dev/null > "$2" || return 2
  _fn=$(cat "$2.n" 2>/dev/null); rm -f "$2.n"
  case "$_fn" in ''|*[!0-9]*) return 2 ;; 0) rm -f "$2"; return 1 ;; esac
  # 확인 1: 크기가 바꾼 줄 수만큼만 줄었다(끝 줄바꿈이 없던 원본 등은 여기서 걸린다)
  _fo=$($BB wc -c < "$1" 2>/dev/null); _fo=$(echo $_fo); _fw=$($BB wc -c < "$2" 2>/dev/null); _fw=$(echo $_fw)
  # 붙여 봄: 하나만 비면 여기는 지나가도 바로 아래 크기 비교가 맞지 않아 실패(2)로 끝난다(안전한 쪽)
  case "$_fo$_fw" in ''|*[!0-9]*) return 2 ;; esac
  [ $((_fo - _fn)) = "$_fw" ] || return 2
  # 확인 2: 줄 수가 같고, 다른 줄은 모두 앞의 "#"만 빠진 것(CR 포함 나머지는 같음)
  _fc=$($BB awk 'NR == FNR { a[FNR] = $0; m = FNR; next }
    { if ($0 != a[FNR]) { if ("#" $0 != a[FNR]) bad = 1; d++ } c = FNR }
    END { if (bad || c != m) print "bad"; else print d + 0 }' "$1" "$2" 2>/dev/null)
  [ "$_fc" = "$_fn" ] || return 2
  return 0
}
# featurexml.cfg 경로. 차의 ro.mobis.targetdir는 끝에 "/"가 없다(니로 "/system/onebin/depehev_kr", 2026-11-09 차 복사로 확인).
# 끝 "/"가 있든 없든 한 번만 붙인다. 값이 없으면 빈 값을 돌려줘 아래 case에서 건너뛰게 한다.
fx_path() {
  _ftd=$(getprop ro.mobis.targetdir 2>/dev/null)
  [ -n "$_ftd" ] || return 0
  echo "${_ftd%/}/featurexml.cfg"
}
perms_revert() {
  has_bb || return 0
  _prn=
  [ -d $BK ] && perms_seed
  _prn=
  if [ -f $PERMS_OURS ]; then
    while IFS= read -r _n; do pr_add "$_n"; done < $PERMS_OURS
  fi
  [ -n "$_prn" ] || return 0
  if [ -d $WPDIR ]; then
    pr_log "무선 권한 파일 그대로 둠: wireless.projection이 설치돼 있음"
    return 0
  fi
  _hs=
  if command -v hmgapid >/dev/null 2>&1; then
    # 데몬이 멈췄으면 status가 끝나지 않을 수 있어 ping을 먼저 본다(리뷰 M2)
    hmgapid ping >/dev/null 2>&1 && _hs=$(hmgapid engine status 2>/dev/null)
    if [ -z "$_hs" ]; then
      pr_log "무선 권한 파일 되돌리기 못 함: HMG-API 응답 없음(관리 여부를 알 수 없어 그대로 둠)"
      return 1
    fi
  fi
  _del=; _fxn=
  for _n in $_prn; do
    _p=$PERMS/$_n.xml
    if [ -f "$_p" ]; then
      set -- $($BB md5sum < "$_p" 2>/dev/null); _have=$1
      set -- $(perm_text "$_n" | $BB md5sum)
      if [ -z "$_have" ] || [ "$_have" != "$1" ]; then
        pr_log "무선 권한 파일 그대로 둠(내용이 바뀜): $_n"; continue
      fi
      case "$_hs" in
        *" $_p "*) pr_log "무선 권한 파일 그대로 둠(HMG-API 모드가 관리 중): $_n"; continue ;;
      esac
      _del="$_del $_n"
    elif [ -e "$_p" ]; then
      continue
    fi
    case "$_n" in com.hkmc.software.connectivity.*_wireless) _fxn="$_fxn $_n" ;; esac
  done
  # featurexml.cfg 줄(권한 파일을 지우거나 이미 없는 무선 2개만)
  _fx=${FXML:-$(fx_path)}
  _fxdo=0
  case "$_fx" in /system/onebin/*/featurexml.cfg|"$FXML") ;; *) _fxn= ;; esac
  # 리뷰(1.7.2 재리뷰 M): featurexml 줄이 순정에서 "-…"라는 것은 니로(CARS_OK)에서만 확인했다. 다른 차는 줄을 그대로 둔다.
  # 권한 파일은 지웠으므로 "#-" 줄이 남아도 부팅 뒤 그 파일은 없다(순정 "-"와 같은 결과).
  if [ -n "$_fxn" ] && ! car_in "$(getprop ro.build.product 2>/dev/null)" "$CARS_OK"; then
    pr_log "featurexml 그대로 둠(순정 줄을 확인한 차가 아님)"; _fxn=
  fi
  if [ -n "$_fxn" ] && [ -f "$_fx" ]; then
    case "$_hs" in
      *" $_fx "*) pr_log "featurexml 그대로 둠(HMG-API 모드가 관리 중)" ;;
      *)
        fx_build "$_fx" $BK/fx.new "$_fxn"; _fr=$?
        if [ $_fr = 0 ]; then _fxdo=1
        elif [ $_fr = 2 ]; then pr_log "featurexml 그대로 둠(예상과 다름: 무선 줄만 바꿀 수 없음)"; fi ;;
    esac
  fi
  [ -n "$_del" ] || [ $_fxdo = 1 ] || return 0
  _was_ro=0; system_ro && _was_ro=1
  if [ $_was_ro = 1 ]; then
    if ! sys_remount rw; then
      rm -f $BK/fx.new
      # 실제로는 열렸는데 확인만 못 했을 수도 있어 ro로 되돌리기를 한 번 부른다(리뷰 M4)
      sys_remount ro
      pr_log "무선 권한 파일 되돌리기 못 함: /system을 쓰기로 열지 못함(그대로 둠)"
      return 1
    fi
  fi
  _gone=; _bad=0; _why=
  for _n in $_del; do
    if rm -f $PERMS/$_n.xml 2>/dev/null && [ ! -e $PERMS/$_n.xml ]; then _gone="$_gone $_n"
    else _bad=1; _why="권한 파일 지우기 실패"; break; fi
  done
  _fxok=0
  if [ $_bad = 0 ] && [ $_fxdo = 1 ]; then
    _fown=$(f_owner "$_fx"); _fprm=$(f_perm "$_fx")
    set -- $($BB md5sum < $BK/fx.new 2>/dev/null); _fwant=$1
    if $BB cp -f "$_fx" $BK/fx.orig && $BB cp -f $BK/fx.new "$_fx.kp-new" \
        && $BB chown "$_fown" "$_fx.kp-new" && $BB chmod "$_fprm" "$_fx.kp-new" && $BB mv -f "$_fx.kp-new" "$_fx" \
        && set -- $($BB md5sum < "$_fx" 2>/dev/null) && [ -n "$_fwant" ] && [ "$1" = "$_fwant" ]; then
      _fxok=1
    else
      _bad=1; _why="featurexml 쓰기 실패"
      rm -f "$_fx.kp-new"
      # 원본으로(이미 바뀌었으면)
      if [ -f $BK/fx.orig ] && [ "$(set -- $($BB md5sum < $BK/fx.orig 2>/dev/null); echo "$1")" != "$(set -- $($BB md5sum < "$_fx" 2>/dev/null); echo "$1")" ]; then
        $BB cp -f $BK/fx.orig "$_fx.kp-new" && $BB chown "$_fown" "$_fx.kp-new" && $BB chmod "$_fprm" "$_fx.kp-new" \
          && $BB mv -f "$_fx.kp-new" "$_fx"
      fi
    fi
  fi
  if [ $_bad = 1 ]; then
    # 처음 상태로: 지운 권한 파일을 같은 내용으로 다시 쓴다
    for _n in $_gone; do
      if ! { perm_text "$_n" > $PERMS/$_n.xml && $BB chmod 644 $PERMS/$_n.xml; }; then
        _why="$_why, 되돌리기도 실패: $_n"   # 리뷰 L2
      fi
    done
  fi
  rm -f $BK/fx.new $BK/fx.orig
  if [ $_was_ro = 1 ] && ! sys_remount ro; then pr_log "/system을 ro로 되돌리지 못함(재부팅하면 ro)"; fi
  if [ $_bad = 1 ]; then
    pr_log "무선 권한 파일 되돌리기 못 함: $_why(그대로 둠)"
    return 1
  fi
  for _n in $_gone; do pr_log "무선 권한 파일 원래대로(없음): $_n"; done
  [ $_fxok = 1 ] && pr_log "featurexml 무선 줄 원래대로(-):$_fxn"
  return 0
}

# 상태 화면 앱(korea.projection.app). NEMESIS의 kind=apk 설치를 쓰지 않는다: 2026-11-06 니로에서
# /data/nemesis/apps/... 의 apk를 pm이 못 읽어 설치가 실패했고(시스템 사용자가 그 폴더를 못 연다),
# 그 실패가 패키지 설치 전체를 막아 핫스팟까지 없어졌다. 그래서 읽을 수 있는 곳(/data/local/tmp, 644)에
# 복사해 직접 설치하고, 실패해도 패키지는 그대로 둔다 (HMG-API 앱 설치와 같은 방식). APP는 위에서 정한다.
APK_SRC=${APK_SRC:-$APP/app/KoreaProjection.apk}
APK_COPY=${APK_COPY:-/data/local/tmp/korea-projection.apk}
APP_ID=korea.projection.app
# 앱 설치·확인에 쓰는 명령: busybox가 있으면 busybox로, 없는 내비(K3·K8, tcc803x)는 toolbox의 같은 이름으로.
# 1.5.5: busybox 없는 내비에도 상태 화면 앱을 설치한다. 앱이 없으면 Launch 때 NEMESIS가 "Error type 3 …
# StatusActivity does not exist"를 띄워 우리 안내를 가렸다(#15 사진). toolbox에 cp·chmod·mkdir·grep이 있다(K3 탐사).
bbx() { if has_bb; then $BB "$@"; else "$@"; fi; }
# KitKat pm은 실패해도 종료 코드 0일 수 있어 출력으로 본다
app_installed() { pm path $APP_ID 2>/dev/null | bbx grep -q "^package:"; }
# 1.7.3(리뷰 M1): 이 패키지에 든 앱의 versionCode(app-src/AndroidManifest.xml과 같아야 함, stub-test가 확인).
# install_app이 성공하면 $BK/app.vc(업데이트에도 남음)에 이 값을 적는다. 설치된 앱이 이 판인지는 그 기록으로 본다
# (pm·dumpsys 출력 꼴에 기대지 않음). 업데이트 때 pm install -r이 실패해 옛 판이 남으면 기록이 달라 Launch가 다시 설치한다.
APK_VC=46
app_current() { app_installed && [ "$(cat $BK/app.vc 2>/dev/null)" = "$APK_VC" ]; }
# 마지막 묶음 L1: 같은 판 설치 실패 횟수($BK/app.fail "<판> <횟수>"). 서명이 다른 앱이 깔린 차 등에서 부팅마다 되풀이하지 않게
# 옛 앱이 있으면 3번에서 멈춘다(그 뒤에도 상태 화면은 옛 앱으로 열린다). 앱이 아예 없으면 화면이 없으므로 지금처럼 부팅마다 한 번 해 본다
APP_FAIL_MAX=3
app_fail_n() { _af=; _an=0; [ -f $BK/app.fail ] && read _af _an < $BK/app.fail; [ "$_af" = "$APK_VC" ] || _an=0; case "$_an" in ''|*[!0-9]*) _an=0 ;; esac; echo $_an; }
# 1.7.4(B-7): 앱 기록을 쓰지 못했을 때 한 줄. 서비스 로그(log)와 제보에 들어가는 $W/app-install.log 둘 다에
app_note() { log "$1"; echo "$(date '+%m-%d %H:%M:%S') $1" 2>/dev/null >> $W/app-install.log; return 0; }
# 결과(Success/Failure 전체 출력)를 $W/app-install.log에 남긴다. 성공 0, 실패 1.
install_app() {
  [ -f $APK_SRC ] || { log "상태 화면 앱 파일 없음: $APK_SRC"; return 1; }
  bbx cp -f $APK_SRC $APK_COPY && bbx chmod 644 $APK_COPY || { log "상태 화면 앱 복사 실패"; return 1; }
  # 이 헤드유닛은 sys.boot_completed=1일 때 제조사 서명만 받는다: pm 호출 동안만 0으로 둔다
  _b=$(getprop sys.boot_completed)
  if [ "$_b" = 1 ]; then
    # 도중에 이 스크립트가 끝나도 1로 되돌린다 (0으로 남으면 서비스가 부팅 완료를 영원히 기다린다)
    trap 'setprop sys.boot_completed 1' EXIT TERM INT HUP
    setprop sys.boot_completed 0
  fi
  _r=$(pm install -r $APK_COPY 2>&1)
  if [ "$_b" = 1 ]; then
    setprop sys.boot_completed 1
    trap - EXIT TERM INT HUP
  fi
  bbx mkdir -p $W 2>/dev/null
  echo "$(date '+%m-%d %H:%M:%S') pm install: $_r" >> $W/app-install.log
  case "$_r" in
    # 1.7.4(B-7): 판 기록(app.vc)·실패 횟수(app.fail)를 못 쓰면 남긴다. 리다이렉션 오류는 { } 밖에서 버리고(셸 오류 줄이
    # 섞이지 않게) 결과만 본다. Launch는 이 함수의 출력을 버리므로 제보에 들어가는 app-install.log에도 적는다.
    # app.vc를 못 쓰면 Launch마다(한 부팅에 한 번) 다시 설치하게 된다
    *Success*) rm -f $APK_COPY $BK/app.fail; bbx mkdir -p $BK 2>/dev/null
       { echo "$APK_VC" > $BK/app.vc; } 2>/dev/null || app_note "상태 화면 앱 판 기록을 쓰지 못함($BK/app.vc): 다음 Launch에 다시 설치할 수 있음"
       log "상태 화면 앱 설치됨"; return 0 ;;
    *) bbx mkdir -p $BK 2>/dev/null
       { echo "$APK_VC $(( $(app_fail_n) + 1 ))" > $BK/app.fail; } 2>/dev/null || app_note "상태 화면 앱 설치 실패 횟수를 쓰지 못함($BK/app.fail)"
       log "상태 화면 앱 설치 실패 (핫스팟과는 상관없음): $(bbx echo $_r)"; return 1 ;;
  esac
}
# Launch(status.sh)에서 앱이 없거나 이 패키지 판이 아닐 때(리뷰 M1) 다시 설치하기: 한 부팅에 한 번만. sys.boot_completed를 0→1로 바꿀 때마다
# init의 부팅 완료 트리거가 다시 돌기 때문이다(Launch를 여러 번 눌러도 한 번). busybox 없는 내비도 같이 쓴다.
install_app_once() {
  app_current && return 0
  # 마지막 묶음 L1: 옛 앱이 있고 이 판 설치가 이미 APP_FAIL_MAX번 실패했으면 더 하지 않는다(옛 앱으로 화면은 열림)
  app_installed && [ "$(app_fail_n)" -ge $APP_FAIL_MAX ] && return 1
  _bid=$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)
  [ "$(cat $W/app-try 2>/dev/null)" = "$_bid" ] && return 1
  echo "$_bid" > $W/app-try
  install_app >/dev/null 2>&1
}
remove_app() {
  pm uninstall $APP_ID >/dev/null 2>&1
  rm -f $APK_COPY
}

# 쓸 수 있는 busybox가 없을 때(내비에 없고, 함께 넣은 것도 실행되지 않음: 예 /data가 noexec): 이 패키지의 스크립트는
# busybox로 동작하므로 무선 설정은 하지 않는다(상태 화면 앱만 설치). 안내는 설치 때(post.sh)와 Launch 때(status.sh)
# 한다. 서비스는 로그만 남기고 대기한다. 1.6.x 알파는 함께 넣은 busybox로 보통 경로를 탄다(1.5.6은 busybox가 없어 이렇게 대기한다).
has_bb() { [ "$BB_OK" = 1 ]; }

# 묶음 I(1.8.0 동글 준비, 소유자 지시 2026-11-15): USB 포트가 하나뿐인 차에서 "동글을 꽂고 시동 → 동글을 빼고 USB를 꽂아 제보"가
# 되게, 부팅마다 한 번(서비스 시작 때, 반복 없음) 그때 꽂혀 있던 USB 장치(루트 허브·허브 class 09 제외)를 $USBSEEN에 남긴다.
# 리포트(dongle_info)가 최근 3부팅 치를 보인다. 한 줄: "<제조사>:<제품> if=<인터페이스 class,…> drv=<드라이버,…> speed=<속도>".
# 일련번호·제품·제조사 문자열·MAC은 읽지 않는다. 폰 회사 제조사 ID면 제품 ID 대신 phone(리포트 dn_is_phone과 같은 목록).
# 글자는 숫자·영문 소문자·:,=._- 만, 장치 20개, 파일은 3부팅·70줄까지, 0600(main의 umask 077). 셸 read 위주이고
# 프로세스는 드라이버 이름(cd -P 하위 셸)과 마지막 mv뿐. 실패해도 서비스는 계속 간다(늘 0)
USBSEEN=${USBSEEN:-$BK/usb.seen}
USB_SYS=${USB_SYS:-/sys/bus/usb/devices}
us_phone() {
  case "$1" in
    05[aA][cC]|04[eE]8|18[dD]1|22[bB]8|2717|12[dD]1|1004|22[dD]9|2[aA]70|0[fF][cC][eE]|2[dD]95|0[bB][bB]4|17[eE][fF]|10[aA]9|19[dD]2) return 0 ;;
  esac
  return 1
}
# 파일 첫 줄을 셸로 읽는다(없으면 빈 값)
us_rd() { _ur=; { read -r _ur < "$1"; } 2>/dev/null; }
# 드라이버 링크 이름(영문 소문자·숫자·_- 만, 아니면 ?). cd -P가 안 되면 ls -l의 링크 대상, 그래도 못 읽으면 ?
us_drv() {
  _ud=; [ -e "$1" ] || return 0
  _ud=$(cd -P "$1" 2>/dev/null && pwd -P)
  if [ -z "$_ud" ]; then _ud=$($BB ls -l "$1" 2>/dev/null); case "$_ud" in *" -> "*) ;; *) _ud="?"; return 0 ;; esac; fi
  _ud=${_ud##*/}
  case "$_ud" in ''|*[!0-9a-z_-]*) _ud="?" ;; esac
}
usb_seen_write() {
  _ub=${BID:-$(cat $BOOT_ID 2>/dev/null)}; _ub=${_ub%%-*}
  # 묶음 J 리뷰(낮음): 부팅 id를 못 읽으면 이번 부팅은 남기지 않는다("none"으로 고착되어 다음 부팅들을 못 남기는 일이 없게)
  case "$_ub" in ''|*[!0-9a-f]*) return 0 ;; esac
  # 이번 부팅을 이미 남겼으면(같은 부팅에 서비스가 다시 시작함) 하지 않는다. 지난 부팅 머리 줄 수도 센다
  _uo=; _uh=0
  if [ -f $USBSEEN ]; then
    while IFS= read -r _ul; do case "$_ul" in "boot "*) _uo=${_ul#boot }; _uh=$((_uh+1)) ;; esac; done < $USBSEEN
  fi
  [ "$_uo" = "$_ub" ] && return 0
  _new="boot $_ub"; _un=0
  for _u in $USB_SYS/*; do
    [ $_un -lt 20 ] || break
    case "${_u##*/}" in usb*|*:*) continue ;; esac
    us_rd $_u/idVendor; _uv=$_ur; us_rd $_u/idProduct; _up=$_ur; us_rd $_u/bDeviceClass; _uc=$_ur; us_rd $_u/speed; _us=$_ur
    case "$_uv" in [0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;; *) continue ;; esac
    case "$_up" in [0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;; *) _up="?" ;; esac
    [ "$_uc" = 09 ] && continue
    us_phone "$_uv" && _up=phone
    case "$_us" in ''|*[!0-9.]*) _us="?" ;; esac
    _uif=; _udr=
    for _i in $_u/*:*; do
      [ -d "$_i" ] || continue
      us_rd $_i/bInterfaceClass; case "$_ur" in [0-9a-f][0-9a-f]) ;; *) _ur="?" ;; esac; _uif="$_uif${_uif:+,}$_ur"
      us_drv $_i/driver; [ -n "$_ud" ] && _udr="$_udr${_udr:+,}$_ud"
    done
    _new="$_new
$_uv:$_up if=${_uif:--} drv=${_udr:--} speed=$_us"
    _un=$((_un+1))
  done
  [ $_un = 0 ] && _new="$_new
none"
  # 지난 기록은 마지막 2부팅 치만 남긴다(새 것과 합쳐 3부팅). 70줄을 넘게 읽지 않는다
  _ui=0; _uk=$((_uh-2)); _ul2=0
  { if [ -f $USBSEEN ]; then
      while IFS= read -r _ul; do
        _ul2=$((_ul2+1)); [ $_ul2 -le 70 ] || break
        case "$_ul" in "boot "*) _ui=$((_ui+1)) ;; esac
        [ $_ui -gt $_uk ] && echo "$_ul"
      done < $USBSEEN
    fi
    echo "$_new"; } 2>/dev/null > $USBSEEN.tmp && $BB mv -f $USBSEEN.tmp $USBSEEN 2>/dev/null
  rm -f $USBSEEN.tmp 2>/dev/null
  return 0
}

# --- 1.8.0 DG-4 동글 드라이버 올리기와 부팅 보호(소유자 결정 2026-11-18) ---
# 드라이버는 칩(ro.board.platform, 리포트에서 본 값 그대로)으로 고른다: tcc897x → drv/tcc897x, tcc803x → drv/tcc803x-a.
# 커널 빌드·순정 bcmdhd md5 허용 목록은 쓰지 않는다(칩마다 같은 드라이버로 된 근거: drafts/1.8.0-dongle-build-survey.md).
# 내비 버전으로는 막지 않는다(11-18 소유자 정정): 260902(V039 9월 빌드)가 아닌 내비도 칩대로 올린다(부팅 보호는 그대로).
# 상태 파일에 dongle_oldnav=yes만 넘기고, "내비 업데이트를 권합니다" 문구·색은 앱이 정한다.
# 드라이버 파일은 변조 검사(bin/kp-files.md5)가 이미 맞춰 본다(따로 SUMS를 두지 않음).
# 이 길은 동글 사용 표시($BK/dongle.on, 있으면 켜짐, 내용은 보지 않음)가 있을 때만 탄다. 표시는 동글 토글(SC-5·DG-12)이 만들 몫이고,
# 그전에는 어느 차도 이 길을 타지 않는다(내장 Wi-Fi가 되는 차에 드라이버를 올리지 않게).
# 부팅 보호(올리는 순간을 지킨다):
#   - insmod 전에 $BK/dongle.try("<boot_id> <묶음> <부팅 뒤 초>")를 tmp→mv→sync→다시 읽기로 남긴다. 남기지 못하면 올리지 않는다.
#   - insmod가 0을 돌려주고 모듈이 Live이고, 시작부터 DG_OK_SEC(기본 60초: 꽂힌 동글을 붙이는 시간)가 지나면 기록을 지운다.
#     리뷰 높음 1: 오래(10분) 두면 짧은 운행 뒤 시동을 끈 것도 "멈춤"으로 막혀서 짧게 둔다.
#   - 다음 부팅에 그 기록이 남아 있으면(올리다 멈춤·재부팅) $BK/dongle.block으로 옮겨 그 차에서는 다시 올리지 않는다.
#   - 같은 부팅에 서비스만 다시 시작했으면 다시 올리지 않는다(막지도 않음). 이번 부팅에 이미 올렸던 모듈이 없으면 두 번 올리지 않고 막는다.
#   - insmod가 실패를 돌려주거나 지켜보는 동안 모듈이 사라지면 그때도 막는다(부팅마다 되풀이하지 않게).
#   - 한계: 기록을 지운 뒤(동글을 나중에 꽂음, 핫스팟 켜기 등)의 멈춤은 잡지 못한다(니로 단독 시험 DG-2에서 본다).
#   - 풀기: 차주가 풀기 USB로 $BK/dongle.block을 지운다(kp-rollback 방식, USB는 따로). 패키지를 지우면 $BK가 지워져 함께 풀린다.
# 기존 카플레이(내장 Wi-Fi·유선)는 이 결과와 상관없이 그대로 간다. 상태는 $W/dongle.state("<상태> <묶음>")에 남겨 status.sh가 읽는다.
DG_ON=${DG_ON:-$BK/dongle.on}
DG_TRY=${DG_TRY:-$BK/dongle.try}
DG_BLOCK=${DG_BLOCK:-$BK/dongle.block}
DG_DRV=${DG_DRV:-$APP/drv}
# 이번 부팅에 우리가 돌린 insmod의 결과("<boot_id> <값> <묶음>"). 리뷰(DG-7 묶음) 중간 2: $W는 업데이트 때 지워지므로 $BK에 둔다
# (같은 부팅에 업데이트해도 결과를 잃어 영원히 기다리거나 다음 부팅에 hang으로 막히지 않게, 부팅 id로 지난 부팅 것은 가름)
DG_RCF=${DG_RCF:-$BK/dongle.rc}
DG_MOD=88x2bu
DG_MAP='tcc897x:tcc897x tcc803x:tcc803x-a'
DG_FW=260902
INSMOD_SYS=${INSMOD_SYS:-/system/bin/insmod}
DG_BLOCK_MSG="동글을 쓰다 내비가 재부팅되어 동글 사용을 멈췄습니다. 상태 화면에서 동글 사용을 껐다 켜면 다시 시도합니다."
# 칩에 맞는 묶음 이름. 표에 없는 칩이면 빈 값
dg_grp() { for _dgm in $DG_MAP; do [ "${_dgm%%:*}" = "$1" ] && { echo "${_dgm#*:}"; return 0; }; done; return 0; }
# 이 차가 올릴 수 있는가: DG_G(묶음)·DG_WHY(못 올리는 까닭 nosoc). 칩만 본다
dg_pick() {
  DG_G=; DG_WHY=
  _dgs=$(getprop ro.board.platform 2>/dev/null)
  DG_G=$(dg_grp "$_dgs")
  [ -n "$DG_G" ] || { DG_WHY=nosoc; return 1; }
  return 0
}
# 내비가 260902판보다 옛것인가(끝 6자리가 더 작거나 없음). 막지 않고 상태 화면 안내에만 쓴다(리뷰 낮음 7: 더 새 판은 no)
dg_oldnav() {
  _dgf=$(fw_date "$(getprop ro.build.product 2>/dev/null)")
  [ -z "$_dgf" ] || [ "$_dgf" -lt $DG_FW ]
}
# 같은 이름 모듈이 목록에 있는가(상태 무관)와, 다 올라와 Live인가(리뷰 높음 2: 올리다 멈춘 Loading은 올라간 것이 아님)
dg_present() { $BB grep -q "^$DG_MOD " ${PROC:-/proc}/modules 2>/dev/null; }
dg_live() { $BB awk -v m=$DG_MOD '$1 == m && / Live / { f = 1 } END { exit !f }' ${PROC:-/proc}/modules 2>/dev/null; }
# 시험판 6(F8): 상태가 바뀌면 상태 화면 파일도 다시 쓴다(dg_status_push, 동글 차만·3초에 한 번까지)
dg_state() { echo "$1 ${2:--}" 2>/dev/null > $W/dongle.state.tmp && $BB mv -f $W/dongle.state.tmp $W/dongle.state 2>/dev/null; dg_status_push; return 0; }
# 이번 부팅에 우리가 돌린 insmod의 돌려준 값(없으면 빈 값)과 묶음(DG_G가 비었으면 채움). $DG_RCF "<boot_id> <값> <묶음>"
dg_rc() {
  DG_RC=; _dgc=; _dgv=; _dgq=
  [ -f $DG_RCF ] && read _dgc _dgv _dgq < $DG_RCF 2>/dev/null
  [ -n "$BID" ] && [ "$_dgc" = "$BID" ] && case "$_dgv" in ''|*[!0-9]*) ;; *) DG_RC=$_dgv; DG_G=${DG_G:-$_dgq} ;; esac
  return 0
}
# 막는다: "<boot_id> <묶음> <까닭 hang|fail|gone>". 리뷰 중간 4: 막기 기록을 다시 읽어 확인한 뒤에만 시도 기록을 지운다
# (못 쓰면 시도 기록을 남겨 다음 부팅에도 올리지 않게)
dg_block() {
  _dgb=; _dgg=; [ -f $DG_TRY ] && read _dgb _dgg _dgx < $DG_TRY 2>/dev/null
  _dgg=${_dgg:-${DG_G:--}}
  _dgl="${_dgb:-${BID:-none}} $_dgg $1"
  [ "$1" = hang ] && { dg_fast_fail "${_dgb:-none}"; dbg_trig b b_rb; }
  echo "$_dgl" 2>/dev/null > $DG_BLOCK.tmp && $BB mv -f $DG_BLOCK.tmp $DG_BLOCK 2>/dev/null && $BB sync
  _dgr=; [ -f $DG_BLOCK ] && _dgr=$(cat $DG_BLOCK 2>/dev/null)
  if [ "$_dgr" = "$_dgl" ]; then rm -f $DG_TRY
  else rm -f $DG_BLOCK.tmp; log "동글 드라이버: 막기 기록을 쓰지 못함, 시도 기록을 남겨 다음 부팅에도 올리지 않음"; fi
  DG_ST=blocked; dg_state blocked "$_dgg"
  dg_guard_release
  # 시험판 4: 막히면 순정 Wi-Fi 저장값을 되돌린다(다음 부팅부터 내장 Wi-Fi)
  dg_wifi_sync
  log "동글 드라이버를 막음($1): 이 차에서는 다시 올리지 않음(풀기 USB로 풂)"
  # 5차 결과 반영: 이 부팅에 순정 드라이버를 내렸으면 기존 무선 카플레이도 재부팅 전까지 안 된다
  if dg_rm_now; then
    pnotice "Korea Projection: $DG_REBOOT_MSG"
  else
    pnotice "$DG_BLOCK_MSG"
  fi
  return 0
}
# --- 1.8.0 DG-8: 다른 동글 패키지 감지(읽기만). 있으면 우리 동글 길을 시작하지 않는다(같은 wlan0·드라이버를 두 패키지가 다투지 않게) ---
# 보는 것: NEMESIS 패키지 폴더(다른 차주들이 쓰는 동글 핫스팟 패키지 id), 올라온 다른 USB Wi-Fi 드라이버 이름, 그 패키지가 만드는 인터페이스.
# 우리 id를 그대로 쓴 개조판은 여기서 가를 수 없고 변조 검사(kp_verify)가 막는다.
NEMESIS_APPS=${NEMESIS_APPS:-/data/nemesis/apps}
# --- 1.8.1 W-8: NEMESIS LivePatch 상태 한 줄(형식: drafts/1.8.1-work/n17-upstream.md 1-2절) ---
# 서비스(root, 마운트 이름공간이 맞음)가 시작할 때 한 번 "nemesis livepatch status"를 읽어 $LPF에 두 줄을 쓴다:
#   1줄: 상태 화면 문구(상태 파일 lp=, 앱이 그대로 보임), 2줄: 리포트 태그(livepatch=na|err|safe|on …, 영문·숫자만)
# 출력 꼴: 첫 줄 "wrapper=<0|1> safe=<0|1>", 그다음 줄마다 "<대상 경로> <mounted|farmed|unmounted>". 경로는 옮기지 않고 세기·겹침 종류만 남긴다.
# 1.17 미만은 명령이 없어 출력이 비고 종료 코드 1 → 해당 없음(na). 그 밖에 첫 줄이 꼴이 아니거나 LPF_WAIT초 안에 끝나지 않으면 err.
# 셀 때 줄 끝을 고정한다(" mounted$": unmounted가 mounted를 품음). 끝나는 조건: 기다림은 LPF_WAIT번(1초씩)까지, 그 뒤 멈춘다
LPF=${LPF:-$W/lp}
LPF_WAIT=${LPF_WAIT:-5}
lp_probe() {
  rm -f $LPF.out $LPF.rc $LPF.pid
  # 리뷰 1 L2: 1.17 미만(버전을 읽을 수 있을 때)은 부르지 않고 해당 없음(1.16이 모르는 명령에 무엇을 내는지 기대지 않음)
  _lpv=$(nemesis version 2>/dev/null)
  case "$_lpv" in [0-9]*.[0-9]*) ver_lt "$_lpv" 1.17 && { lp_write "해당 없음" "livepatch=na"; return 0; } ;; esac
  # 리뷰 1 L1: nemesis 자체의 pid를 남겨, 시간이 넘으면 기다리는 하위 셸과 nemesis를 둘 다 끈다(nemesis가 띄운 자식은 남을 수 있음)
  ( nemesis livepatch status 2>/dev/null > $LPF.out & echo $! 2>/dev/null > $LPF.pid; wait $!; echo $? 2>/dev/null > $LPF.rc ) &
  _lpp=$!; _lpw=0
  # 기다림은 앞에서 sleep(wait를 쓰지 않음: 30초 점검의 wait와 섞이지 않게). 최대 LPF_WAIT초
  while [ ! -s $LPF.rc ] && [ $_lpw -lt $LPF_WAIT ]; do sleep 1; _lpw=$((_lpw + 1)); done
  _lprc=; [ -s $LPF.rc ] && read _lprc < $LPF.rc
  if [ -z "$_lprc" ]; then
    kill $_lpp 2>/dev/null
    _lpn=; [ -s $LPF.pid ] && read _lpn < $LPF.pid
    case "$_lpn" in ''|*[!0-9]*) ;; *) kill $_lpn 2>/dev/null ;; esac
  fi
  if [ "$_lprc" = 1 ] && [ ! -s $LPF.out ]; then
    _lps="해당 없음"; _lpt="livepatch=na"
  elif [ -z "$_lprc" ]; then
    _lps="읽지 못함"; _lpt="livepatch=err"
  else
    _lpt=$($BB awk '
      NR == 1 { if ($0 !~ /^wrapper=[01] safe=[01]$/) { bad = 1; exit } w = substr($1, 9); sf = substr($2, 6); next }
      { r++; if ($0 ~ / mounted$/) m++; else if ($0 ~ / farmed$/) f++; else if ($0 ~ / unmounted$/) u++
        p = $1
        if (p ~ /^\/system\/onebin\/[^\/]+\/featurexml\.cfg$/) o1 = 1
        else if (p ~ /^\/system\/etc\/permissions\/(com\.hkmc\.software\.connectivity\.|android\.hardware\.)/) o2 = 1
        else if (p ~ /^\/system\/etc\/wifi\/wpa_supplicant[^\/]*\.conf$/) o3 = 1
        else if (p ~ /^\/system\/app\/(HKMC_DiPO|HKMC_GPM|Iap2ServerApp|HKMC_Navi_ExSL|PhoneProjection|Bluetooth)\.odex$/) o4 = 1
        else if (p ~ /^\/system\/lib\/(libautoreceiver_infobank\.so|libCarPlay[^\/]*\.so)$/) o5 = 1 }
      END { if (bad || NR == 0) { print "err"; exit }
        o = ""; if (o1) o = o ",featurexml"; if (o2) o = o ",permissions"; if (o3) o = o ",wpa"; if (o4) o = o ",app"; if (o5) o = o ",lib"
        print (sf == 1 ? "safe" : "on") " wrapper=" w " rows=" r + 0 " mounted=" m + 0 " farmed=" f + 0 " unmounted=" u + 0 (o == "" ? "" : " overlap=" substr(o, 2)) }' $LPF.out 2>/dev/null)
    case "$_lpt" in
      safe\ *|on\ *)
        set -- $_lpt; _lpk=$1; _lpr=${3#rows=}; _lpm=${4#mounted=}; _lpf=${5#farmed=}; _lpo=${7#overlap=}
        if [ "$_lpk" = safe ]; then _lps="안전 모드(순정으로 시작함)"
        elif [ "$_lpr" = 0 ]; then _lps="쓰는 패키지 없음"
        elif [ $((_lpm + _lpf)) = 0 ]; then _lps="적용된 곳 없음(안전 모드나 손상)"
        else _lps="사용 중(적용 $((_lpm + _lpf))곳)"; fi
        if [ -n "$7" ]; then
          _lpn=
          for _lpx in featurexml:"무선 기능 파일" permissions:"권한 파일" wpa:"Wi-Fi 설정 파일" app:"순정 앱" lib:"순정 라이브러리"; do
            case ",$_lpo," in *",${_lpx%%:*},"*) _lpn="$_lpn·${_lpx#*:}" ;; esac
          done
          _lps="$_lps, 겹침: ${_lpn#·}"
        fi
        _lpt="livepatch=$_lpt" ;;
      *) _lps="읽지 못함"; _lpt="livepatch=err" ;;
    esac
  fi
  rm -f $LPF.out $LPF.rc $LPF.pid
  lp_write "$_lps" "$_lpt"
  return 0
}
# 두 줄(화면 문구, 리포트 태그)을 $LPF에
lp_write() { { echo "$1"; echo "$2"; } 2>/dev/null > $LPF.tmp && $BB mv -f $LPF.tmp $LPF 2>/dev/null; return 0; }
DG_OTHER_PKGS='usbwifi.hotspot stock.hotspot'
DG_OTHER_MODS='8812au 88XXau 8821au 8821cu 8814au rtl8812au rtl8821cu rtl88x2bu rtl8xxxu r8188eu 8188eu mt7601u'
DG_OTHER_IFS='rtwlan0'
DG_OTHERPKG_MSG="다른 동글 패키지가 있어 동글을 쓰지 않습니다. 그 패키지를 지운 뒤 재부팅해 주세요."
# 1.8.1 I-7: 우리가 올리지 않은 동글 드라이버(같은 이름)가 이미 올라와 있음(다른 패키지 이름은 못 찾음). 문구는 다른 패키지 안내와 같은 줄기
DG_OTHERMOD_MSG="다른 프로그램이 동글 드라이버를 먼저 올려 동글을 쓰지 않습니다. 그 패키지를 지운 뒤 재부팅해 주세요."
# 찾으면 DG_OTHER에 이름(패키지 id·드라이버·인터페이스 이름)을 두고 0
dg_otherpkg() {
  DG_OTHER=
  for _dgo in $DG_OTHER_PKGS; do [ -d $NEMESIS_APPS/$_dgo ] && { DG_OTHER=$_dgo; return 0; }; done
  for _dgo in $DG_OTHER_MODS; do $BB grep -q "^$_dgo " ${PROC:-/proc}/modules 2>/dev/null && { DG_OTHER=$_dgo; return 0; }; done
  for _dgo in $DG_OTHER_IFS; do [ -e ${SYSNET:-/sys/class/net}/$_dgo ] && { DG_OTHER=$_dgo; return 0; }; done
  return 1
}
# --- 1.8.0 DG-3: 동글 판정(지원 동글 3종: ipTIME A3000MINI, NEXI NX-AC1300, TP-Link Archer T3U) ---
# 사용자에게 보이는 상태·리포트 문구에는 판정 결과만 쓴다.
# 허용 동글이 없을 때: Wi-Fi 칩 회사로 보이는 USB 장치가 있으면 "목록 밖"(notlisted), 없으면 "동글 없음"(nodongle). 문구만 가르는 대략의 판정이다.
# 1.8.0 정식(A2): 허용 값은 해시로만 둔다(배포 파일에 USB 번호·제품 이름·OUI가 그대로 보이지 않게). 해시는 sha1("kp180|" + 값 + 줄바꿈),
# 꽂힌 장치에서 읽은 값을 같은 꼴로 해시해(dg_h) 대조한다. 판단 결과(ok·no·unk·id·lax)는 예전과 같다. 목록은 비공개 원본에서
# sh scripts/dg-hash.sh로 만든다(값은 비공개 문서에만). 입력이 짧아 대입하면 되찾을 수 있다: "그대로 보이지 않게"까지다
DG_HP='kp180|'
DG_USB_OK=${DG_USB_OK:-'a058e11a8b4cb4836e19ff30334e96c8f9f595a5 d9ba2add44d51eb5bde27ff962df62c33c61b3fc'}
DG_NAMES=${DG_NAMES:-'a058e11a8b4cb4836e19ff30334e96c8f9f595a5|a8dad9b07cab37b37f113dd43e1cb5245edc666a
a058e11a8b4cb4836e19ff30334e96c8f9f595a5|bb89c809956bccd6c848a1a347ca4a7109ac94d0'}
DG_OUI=${DG_OUI:-'a058e11a8b4cb4836e19ff30334e96c8f9f595a5|449ea96bb1e67855dd3e38911e14059e061558c2
a058e11a8b4cb4836e19ff30334e96c8f9f595a5|72b4ea244ec324f19b39ee41523867403dd895a1
a058e11a8b4cb4836e19ff30334e96c8f9f595a5|b5a0a38038fd2049cb84c935818186f5c4881842
a058e11a8b4cb4836e19ff30334e96c8f9f595a5|6e2af5a96f970a46f48727b4ed533a205cfb94e6
a058e11a8b4cb4836e19ff30334e96c8f9f595a5|4e3e08a40e466f8d340435f06a51f3a4f5492332
a058e11a8b4cb4836e19ff30334e96c8f9f595a5|1bed37a5cd5d45536674064b438ddb4a23edcc4d
a058e11a8b4cb4836e19ff30334e96c8f9f595a5|5a8ac8ac17032601fdfbe5483afdc548e6db11e5
a058e11a8b4cb4836e19ff30334e96c8f9f595a5|c260feca71759a49d0f75eee4193df4bbbb8d034
a058e11a8b4cb4836e19ff30334e96c8f9f595a5|b2c546e8f7e34a9ad6d9d18c19181e6b1a91f637'}
DG_MODELS=${DG_MODELS:-'d9ba2add44d51eb5bde27ff962df62c33c61b3fc|*|ArcherT3U
a058e11a8b4cb4836e19ff30334e96c8f9f595a5|1828030d1fb1f049101802b6adc78168e9aa72b8|A3000MINI
a058e11a8b4cb4836e19ff30334e96c8f9f595a5|7981d5945859aff5aa8f2539061e06611c887141|NX-AC1300'}
# 동글 판정(DG-3)
DG_OUI_ENFORCE=${DG_OUI_ENFORCE:-1}
DG_OUIF=${DG_OUIF:-$BK/dongle.oui}
# 동글 판정(DG-3) 비공개 기록(공개 리포트·ap.log·상태 화면에는 없음)
DG_OUIVF=${DG_OUIVF:-$BK/dongle.ouiv}
# 동글 판정(DG-3)
# 정식(A2·리뷰 L8): 꼴이 바뀌었다. 예전에는 제품 문자열 그대로, 이제는 해시 H("vid:pid|제품") 한 줄에 하나(기본은 비어 있음)
DG_OUI_LAX=${DG_OUI_LAX-}
DG_NOTOURS_MSG="지원 목록의 동글이 아닙니다. 지원: ipTIME A3000MINI, NEXI NX-AC1300, TP-Link Archer T3U."
DG_WIFI_VENDORS='0bda 2357 7392 2001 0b05 0846 148f 0e8d 13b1 20f4 056e 0df6'
DG_NODONGLE_MSG="USB Wi-Fi 동글이 꽂혀 있지 않습니다. 동글을 꽂고 재부팅해 주세요."
DG_USBADB_MSG="USB ADB가 켜져 있어 동글을 볼 수 없습니다. USB ADB를 끄고 재부팅해 주세요."
# 1.8.0 베타 2 NM-2(NEMESIS 1.16.8 USB ADB 타일): USB 포트가 기기 모드면 USB 장치를 볼 수 없다.
# 이 차들의 평소 값은 host(니로 getprop), HMG-API ADB 모드의 "USB 끔"은 host,adb(포트는 여전히 호스트) — 둘 다 켜짐이 아니다.
# host·mtp가 없고 adb가 있을 때만 켜짐(리뷰 높음: host,adb를 켜짐으로 보던 것 고침)
usb_adb_on() {
  case "$(getprop sys.usb.config 2>/dev/null)" in *host*|*mtp*) return 1 ;; *adb*) return 0 ;; *) return 1 ;; esac
}
DG_NOTLISTED_MSG="지원 목록의 동글을 찾지 못했습니다. 지원: ipTIME A3000MINI, NEXI NX-AC1300, TP-Link Archer T3U."
# 1.8.0 정식(A2): 값 하나의 해시를 _dgh에(40자리 16진수, 못 구하면 빈 값). 차의 셸에는 printf가 없어 here-doc으로 넘긴다
dg_h() {
  _dgh=$($BB sha1sum 2>/dev/null <<DGH
$DG_HP$1
DGH
)
  _dgh=${_dgh%% *}
  case "$_dgh" in *[!0-9a-f]*) _dgh= ;; esac
}
# 장치별 결과 기억(같은 서비스 안, 30초 점검마다 sha1sum을 다시 띄우지 않게). " <종류>:<열쇠>=y|n " 꼴, 길어지면 비움
DG_HC=' '
dg_hc_get() { case "$DG_HC" in *" $1=y "*) return 0 ;; *" $1=n "*) return 1 ;; esac; return 2; }
dg_hc_put() { [ ${#DG_HC} -gt 4000 ] && DG_HC=' '; DG_HC="$DG_HC$1=$2 "; }
# 허용 USB 번호인가(vid:pid)
dg_idok() {
  dg_hc_get "i:$1"; _dgr=$?; [ $_dgr = 2 ] || return $_dgr
  dg_h "$1"
  case " $DG_USB_OK " in *" $_dgh "*) [ -n "$_dgh" ] && { dg_hc_put "i:$1" y; return 0; } ;; esac
  # 해시를 못 구했으면 기억하지 않는다(다음에 다시)
  [ -n "$_dgh" ] && dg_hc_put "i:$1" n
  return 1
}
# 결과: DG_USB = ok | notlisted | none
dg_usb() {
  DG_USB=none; DG_USBDEV=; DG_USBID=
  for _dgu in $USB_SYS/*; do
    case "${_dgu##*/}" in usb*|*:*) continue ;; esac
    us_rd $_dgu/idVendor; _dgv=$_ur; us_rd $_dgu/idProduct; _dgp=$_ur
    case "$_dgv" in [0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;; *) continue ;; esac
    # 리뷰 중간 3: 허브(class 09)는 건너뛴다(내비 안쪽 Realtek 허브 등)
    us_rd $_dgu/bDeviceClass; [ "$_ur" = 09 ] && continue
    if dg_idok "$_dgv:$_dgp"; then
        # 동글 판정(DG-3)
        if ! dg_names_has "$_dgv:$_dgp" || dg_name_ok "$_dgv:$_dgp" "$_dgu"; then DG_USB=ok; DG_USBDEV=$_dgu; DG_USBID=$_dgv:$_dgp; return 0; fi
        DG_USB=notlisted
    else
      case " $DG_WIFI_VENDORS " in *" $_dgv "*) [ $DG_USB = none ] && dg_wifi_like $_dgu && DG_USB=notlisted ;; esac
    fi
  done
  return 0
}
# Wi-Fi 동글처럼 보이는가: 제조사 고유(class ff) 인터페이스가 있고 거기에 붙은 드라이버가 없음(카드 리더·USB 랜처럼 드라이버가 붙은 장치는 아님)
dg_wifi_like() {
  for _dgi2 in $1/*:*; do
    [ -d "$_dgi2" ] || continue
    us_rd $_dgi2/bInterfaceClass
    [ "$_ur" = ff ] && [ ! -e $_dgi2/driver ] && return 0
  done
  return 1
}
# 동글 판정(DG-3)
dg_names_has() {
  dg_hc_get "h:$1"; _dgr=$?; [ $_dgr = 2 ] || return $_dgr
  # 정식 리뷰 M2: 해시를 못 구하면(sha1sum 실패) "이름 목록 있음"으로 본다(기억하지 않음). 그러면 뒤의 이름 대조(dg_name_ok)가
  # 빈 해시로 거절하고(notlisted), dg_oui는 앞자리 대조로 간다. "목록 없음"(1)으로 답하면 이름 대조 없이 통과해 버린다(fail-open)
  dg_h "$1"; [ -n "$_dgh" ] || return 0
  while IFS='|' read -r _dgn1 _dgn2; do [ "$_dgn1" = "$_dgh" ] && { dg_hc_put "h:$1" y; return 0; }; done <<DGNAMES
$DG_NAMES
DGNAMES
  dg_hc_put "h:$1" n
  return 1
}
# 리뷰 높음 1: 차의 셸에는 printf가 없다(busybox에만). here-doc으로 읽고 파이프·하위 셸을 쓰지 않는다
# 정식(A2): 이름 대조는 해시(vid:pid|제조사|제품). 같은 포트에 다른 동글을 바꿔 꽂을 수 있어 기억 열쇠에 장치 번호(devnum)를 넣는다
dg_name_ok() {
  # 정식 리뷰 L7: 장치 번호(devnum)를 못 읽으면 기억하지 않는다(같은 포트에 바꿔 꽂은 다른 동글에 지난 결과를 쓰지 않게)
  us_rd $2/devnum; _dgnk=; [ -n "$_ur" ] && _dgnk="n:${2##*/}:$_ur:$1"
  if [ -n "$_dgnk" ]; then dg_hc_get "$_dgnk"; _dgr=$?; [ $_dgr = 2 ] || return $_dgr; fi
  us_rd $2/manufacturer; _dgmf=$_ur; us_rd $2/product; _dgpr=$_ur
  dg_h "$1|$_dgmf|$_dgpr"; _dgmf=; _dgpr=
  [ -n "$_dgh" ] || return 1
  while IFS='|' read -r _dgn1 _dgn2; do
    [ "$_dgn2" = "$_dgh" ] && { [ -n "$_dgnk" ] && dg_hc_put "$_dgnk" y; return 0; }
  done <<DGNAMES
$DG_NAMES
DGNAMES
  [ -n "$_dgnk" ] && dg_hc_put "$_dgnk" n
  return 1
}
# --- 1.8.0 DG-12: 동글 사용이 켜진 부팅(막힘 없음)은 내장 Wi-Fi를 깨우지 않는다(svc wifi enable·Wi-Fi 잠금·칩 깨우기 안 함) ---
# 둘이 wlan0을 다투지 않게(소유자 결정 2026-11-15). 동글 쪽 wlan0이 없어도 내장 칩 실패로 세지 않는다(nowlan.boots)
# 리뷰 중간 1: 동글 길을 실제로 쓸 수 있을 때만(이 서비스의 dg_start 결과가 wait·up·ok) 내장 Wi-Fi를 쉰다. 동글이 없음·목록 밖·
# 다른 패키지·칩/드라이버 없음·막힘이면 예전처럼 내장 Wi-Fi를 쓴다(내장 칩이 있는 차의 무선이 꺼지지 않게)
# 5차 결과 반영: 이 부팅에 순정 드라이버를 내렸으면(dg_rm_now) 동글 길이 실패·꺼짐이어도 내장 Wi-Fi를 켜지 않는다(재부팅으로만 돌아옴)
dg_builtin_off() { { [ -f $DG_ON ] && [ ! -f $DG_BLOCK ] && case "$DG_ST" in wait|up|ok) true ;; *) false ;; esac; } || dg_rm_now; }
# --- 1.8.0 베타 2 AOA 가드(동글 8차 차 결과 11-21: 가드를 켜자 우리 hostapd가 동글 wlan0에 그대로 뜨고 무선 카플레이 연결) ---
# 순정 USB 호스트 서비스는 새 USB 장치의 usbfs 노드(/dev/bus/usb/BBB/DDD)를 열어 AOA 요청을 보낸다. 동글 칩이 이것을 받으면 먹통이 되어
# hostapd가 4초 안에 꺼졌다(6·7차). 그래서 동글이 붙을 버스의 빈 번호 자리(002~127)에 빈 폴더를 먼저 만들어 ueventd가 노드를 만들지
# 못하게 한다. 커널 드라이버(88x2bu·usb-storage)는 usbfs를 쓰지 않아 상관없다.
# - 거는 곳: 동글을 켠 부팅의 dg_start, 모든 거절 검사 뒤·순정 드라이버를 내리기 전(되돌릴 수 있는 일을 먼저).
# - 대상: 허용 동글이 꽂힌 버스 하나의 빈 자리만. 이미 있는 노드·폴더·링크는 건드리지 않는다(다른 장치는 그대로).
# - 부팅 때 꽂혀 있던 동글은 노드가 이미 있다(순정이 AOA를 보냈을 수 있음): 드라이버를 올리기 전에 "뺐다가 다시 꽂기"를 안내하고,
#   빠지면 그 자리도 막은 뒤 드라이버를 올린다. 다시 꽂으면 막힌 자리로 들어간다(8차와 같은 순서: insmod 뒤 동글 꽂기).
# - 막는 버스: dwc_otg에 달린 루트 허브의 버스(니로 외부 USB, 6~8차 버스 001). 못 찾으면 동글이 꽂힌 버스. 동글 버스와 다르면 기록.
# - 동글 길을 쓰는 동안(wait·up·ok) 30초 점검마다 빈 자리를 다시 막는다(다른 장치가 쓰다 뺀 번호, 동글이 흔들려 다시 잡힌 번호).
#   그동안 같은 버스의 유선 폰·USB 기기는 인식되지 않는다(포트가 하나인 차의 "유선을 함께 못 씀"과 같음). USB 메모리는 블록 장치라 상관없다.
# - 풀기: 동글 길이 끝나면(막힘·끄기·내리다 멈춤·지우기·다시 꽂기 안 함) 기록($W/aoa.dirs)에 있는 빈 폴더만 rmdir. 재부팅하면 /dev가
#   새로 생겨 저절로 없어진다. 폴더는 서비스의 umask 077로 0700.
# - 끄기: $BK/dongle.noguard(대조 시험용)
DG_USBFS=${DG_USBFS:-/dev/bus/usb}
# 리뷰 중간 5: 기록은 폴더와 수명이 같은 /dev(tmpfs)에 둔다($W는 업데이트 때 지워져 기록 없는 폴더가 남음)
DG_AOAF=${DG_AOAF:-/dev/.kp-aoa.dirs}
dg_guard_on() { [ ! -f $BK/dongle.noguard ]; }
dg_gbid() { _dggbid=$BID; [ -n "$_dggbid" ] || { read _dggbid < ${BOOT_ID:-/proc/sys/kernel/random/boot_id}; } 2>/dev/null; _dggbid=${_dggbid:-none}; }
dg_n3() { $BB awk -v n="$1" 'BEGIN { printf "%03d", n }'; }
# 막을 버스(DG_GBUS, 세 자리)와 동글 노드 경로(DG_GNODE)·동글 버스가 같은가(DG_GSAME yes|no|?).
# 버스: dwc_otg에 달린 루트 허브(usbN의 실제 경로에 dwc_otg), 없으면 동글이 꽂힌 버스. 둘 다 없으면 1
dg_guard_paths() {
  DG_GBUS=; DG_GNODE=; DG_GSAME='?'; DG_GDEVN=; _dggb=
  for _dggh in $USB_SYS/usb[0-9]*; do
    [ -d "$_dggh" ] || continue
    _dggr=$(cd -P "$_dggh" 2>/dev/null && pwd -P)
    case "$_dggr" in *dwc_otg*) us_rd $_dggh/busnum; _dggb=$_ur; break ;; esac
  done
  _dgdb=; _dgdd=
  if [ -n "$DG_USBDEV" ]; then us_rd $DG_USBDEV/busnum; _dgdb=$_ur; us_rd $DG_USBDEV/devnum; _dgdd=$_ur; fi
  # 정식(메인 11-24): 붙여서 보면 하나만 비어도 지나간다. 따로 보고, 하나라도 비거나 숫자가 아니면 둘 다 버린다(엉뚱한 노드를 막지 않게)
  case "$_dgdb" in ''|*[!0-9]*) _dgdb=; _dgdd= ;; esac
  case "$_dgdd" in ''|*[!0-9]*) _dgdb=; _dgdd= ;; esac
  [ -n "$_dggb" ] || _dggb=$_dgdb
  # 베타 3(B3-9a, dongle.md 4-27): 외부 포트가 dwc_otg가 아닌 차(tcc803x ehci-platform)는 동글이 잡히기 전에는 버스를 몰라 가드가 늦었다.
  # 지난 부팅에 동글이 붙었던 버스(같은 컨트롤러 경로일 때만)를 쓴다
  [ -n "$_dggb" ] || { dg_gbus_rec && _dggb=$DG_RBUS; }
  case "$_dggb" in ''|*[!0-9]*) return 1 ;; esac
  # 모뎀 등 다른 컨트롤러(tcc-ehci) 버스는 절대 막지 않는다
  dg_bus_modem $_dggb && return 1
  [ "$_dggb" -ge 1 ] && [ "$_dggb" -le 127 ] || return 1
  DG_GBUS=$(dg_n3 $_dggb)
  if [ -n "$_dgdb" ] && [ "$_dgdd" -ge 1 ] && [ "$_dgdd" -le 127 ]; then
    DG_GNODE=$DG_USBFS/$(dg_n3 $_dgdb)/$(dg_n3 $_dgdd); DG_GDEVN=$_dgdd
    if [ "$_dgdb" = "$_dggb" ]; then DG_GSAME=yes; else DG_GSAME=no; fi
  fi
  return 0
}
# 그 버스의 빈 자리(002~127)에 빈 폴더. 기록 첫 줄은 이번 부팅 id(다른 부팅 기록은 버림). 만든 수 DG_GMADE
dg_guard_arm() {
  DG_GMADE=0
  [ -n "$DG_GBUS" ] || return 0
  _dggp=$DG_USBFS/$DG_GBUS
  [ -d $_dggp ] && [ ! -L $_dggp ] || { log "AOA 가드: 버스 폴더가 없어 걸지 않음(버스 $DG_GBUS)"; return 0; }
  dg_gbid; _dgg1=; [ -f $DG_AOAF ] && read _dgg1 < $DG_AOAF 2>/dev/null
  [ "$_dgg1" = "$_dggbid" ] || { echo "$_dggbid" 2>/dev/null > $DG_AOAF || return 0; }
  DG_GOLD=0
  for _dggs in $($BB awk 'BEGIN { for (i = 2; i <= 127; i++) printf "%03d ", i }'); do
    if [ -e $_dggp/$_dggs ] || [ -L $_dggp/$_dggs ]; then [ -d $_dggp/$_dggs ] || DG_GOLD=$((DG_GOLD + 1)); continue; fi
    mkdir $_dggp/$_dggs 2>/dev/null && { echo "$_dggp/$_dggs" >> $DG_AOAF; DG_GMADE=$((DG_GMADE + 1)); }
  done
  DG_GARMED=1
  if [ "$1" = quiet ]; then [ $DG_GMADE -gt 0 ] && log "AOA 가드: 비게 된 자리 ${DG_GMADE}개 다시 막음"
  else log "AOA 가드: 버스 $DG_GBUS 빈 자리 ${DG_GMADE}개 막음, 있던 장치 노드 ${DG_GOLD}개, 동글 버스와 같음 $DG_GSAME"; fi
  return 0
}
# 배포판(리뷰 높음 3): 이른 가드(+4초) 뒤에 붙은 동글이 아닌 장치(유선 폰 등)가 막힌 자리에 들어가 노드가 없으면, 그 자리의 우리 빈 폴더를
# 지우고 장치의 uevent에 add를 써 ueventd가 노드를 다시 만들게 한다(동글 길 전 R6 앞과 같게 유선 카플레이가 되게). 허용 동글은 건드리지 않음.
# 대상: 가드 버스(DG_GBUS)의 장치 폴더(허브 빼고), 그 번호 자리가 기록($DG_AOAF)에 있는 우리 빈 폴더일 때만
dg_guard_unblock_others() {
  [ -n "$DG_GBUS" ] && [ -f $DG_AOAF ] || return 0
  _dgun=0
  # 정식 2차 리뷰 L5: 미리 막은 짝 버스(C1 ⓑ, DG_RPAIR)에 들어간 동글 아닌 장치도 같은 규칙으로 푼다
  _dgubs=$DG_GBUS; case "$DG_RPAIR" in ''|*[!0-9]*) ;; *) [ "$(dg_n3 $DG_RPAIR)" = "$DG_GBUS" ] || _dgubs="$_dgubs $(dg_n3 $DG_RPAIR)" ;; esac
  for _dgubus in $_dgubs; do
  for _dgud in $USB_SYS/*; do
    case "${_dgud##*/}" in usb*|*:*) continue ;; esac
    us_rd $_dgud/busnum; _dgub=$_ur; us_rd $_dgud/devnum; _dgudn=$_ur
    # 정식(메인 11-24): 버스·번호를 따로 본다(하나만 비면 그 장치는 건드리지 않음)
    case "$_dgub" in ''|*[!0-9]*) continue ;; esac
    case "$_dgudn" in ''|*[!0-9]*) continue ;; esac
    [ "$(dg_n3 $_dgub)" = "$_dgubus" ] || continue
    us_rd $_dgud/bDeviceClass; [ "$_ur" = 09 ] && continue
    us_rd $_dgud/idVendor; _dguv=$_ur; us_rd $_dgud/idProduct
    dg_idok "$_dguv:$_ur" && continue
    # 재리뷰 낮음 1: Wi-Fi 칩 회사 장치(드라이버 CD 모드로 먼저 붙는 동글 등)는 풀지 않는다
    case " $DG_WIFI_VENDORS " in *" $_dguv "*) continue ;; esac
    [ "$_dgudn" -ge 2 ] && [ "$_dgudn" -le 127 ] || continue
    _dgup=$DG_USBFS/$_dgubus/$(dg_n3 $_dgudn)
    [ -d "$_dgup" ] && [ ! -L "$_dgup" ] && $BB awk -v p="$_dgup" '$0 == p { f = 1 } END { exit !f }' $DG_AOAF 2>/dev/null || continue
    rmdir "$_dgup" 2>/dev/null || continue
    echo add 2>/dev/null > $_dgud/uevent; _dgun=$((_dgun + 1))
  done
  done
  [ $_dgun -gt 0 ] && log "AOA 가드: 막힌 자리에 들어간 동글 아닌 USB 장치 ${_dgun}개의 자리를 풀고 다시 알림"
  return 0
}
# 기록의 빈 폴더를 모두 지운다. 이번 부팅 기록일 때만, 우리 꼴 경로·링크 아닌 폴더만, rmdir만(노드·내용 든 폴더는 실패해 그대로). 지운 수 DG_GFREED
dg_guard_release() {
  DG_GFREED=0
  [ -f $DG_AOAF ] || return 0
  dg_gbid; _dgg1=; read _dgg1 < $DG_AOAF 2>/dev/null
  if [ "$_dgg1" != "$_dggbid" ]; then rm -f $DG_AOAF; return 0; fi
  # 재리뷰 중간 3: 내비 Wi-Fi로 가는 부팅 등에서 풀 때도, 이른 가드 뒤에 막힌 자리에 들어간 동글 아닌 장치(유선 폰)는 노드를 되살린다
  [ -n "$DG_GBUS" ] || { [ -n "$DG_USBDEV" ] || dg_usb; dg_guard_paths; }
  dg_guard_unblock_others
  _dggk=$DG_AOAF.keep; : 2>/dev/null > $_dggk
  { read _dggx; while read -r _dggl; do
      case "$_dggl" in "$DG_USBFS"/[0-9][0-9][0-9]/[0-9][0-9][0-9]) ;; *) continue ;; esac
      if [ -d "$_dggl" ] && [ ! -L "$_dggl" ] && rmdir "$_dggl" 2>/dev/null; then DG_GFREED=$((DG_GFREED + 1)); fi
      [ -d "$_dggl" ] && [ ! -L "$_dggl" ] && echo "$_dggl" >> $_dggk
    done; } < $DG_AOAF
  if [ -s $_dggk ]; then { echo "$_dggbid"; cat $_dggk; } 2>/dev/null > $DG_AOAF; else rm -f $DG_AOAF; DG_GARMED=; fi
  rm -f $_dggk
  [ $DG_GFREED -gt 0 ] && log "AOA 가드: 빈 자리 ${DG_GFREED}개 풀어 줌"
  return 0
}
# 30초 점검: 동글 길을 쓰는 동안 빈 자리를 다시 막고(조용히), 동글이 처음 보이면 그 자리 상태를 한 번 기록한다.
# 걸렸는지는 이번 부팅 기록 파일로 본다(같은 부팅에 서비스가 다시 시작해도 이어 감)
dg_guard_tick() {
  case "$DG_ST" in wait|up|ok) ;; *) return 0 ;; esac
  [ -f $DG_AOAF ] || return 0
  dg_gbid; _dgg1=; read _dgg1 < $DG_AOAF 2>/dev/null; [ "$_dgg1" = "$_dggbid" ] || return 0
  [ -n "$DG_USBDEV" ] && [ -d "$DG_USBDEV" ] || dg_usb
  dg_guard_paths || return 0
  dg_guard_arm quiet
  if [ "$DG_GDONE" != 1 ] && dg_seen && [ -n "$DG_GNODE" ]; then
    DG_GDONE=1
    if [ -d "$DG_GNODE" ] && [ ! -L "$DG_GNODE" ]; then _dggst=blocked; log "AOA 가드: 동글이 막힌 자리에 붙음(동글 버스와 같음 $DG_GSAME)"
    elif [ -e "$DG_GNODE" ]; then _dggst=open; log "AOA 가드: 동글 자리에 노드가 있음(막지 못함, 순정 AOA가 닿았을 수 있음)"
    else _dggst=none; fi
    echo "${BID:-none} $_dggst $DG_GSAME" 2>/dev/null > $W/aoa.state
  fi
  return 0
}

# --- 1.8.0 베타 2(니로 시험판): 동글 뽑기 기록(dongle.md 4-22, 배포를 막는 조건 "붙은 채 뽑기 재부팅"을 가르는 시험, 메인 11-21) ---
# 동글 길을 쓰는 동안 뒤에서 감시 하나(한 부팅에 하나)가 1초마다 동글 장치 폴더만 본다(프로세스를 띄우지 않음).
# - 뽑힌 순간: $BK/dongle.pulls에 한 줄(sync, 다음 부팅에도 남음) — uptime, 우리 AP(직전 점검)·카플레이 연결 수(직전 점검)·그 점검 나이,
#   우리 hostapd 시작 뒤 초, wlan0 operstate.
# - 20초 뒤: dmesg 숫자만 — kp-protect dev_remove attached 값, start→done 밀리초, ndev gone·unload done 나왔는지, 그 전 마지막 probe 뒤 초,
#   순정 AOA logcat 줄 수.
# - 다시 꽂힌 뒤 10초: probe ret·step, wlan0이 다시 생겼는지.
# - 심장 박동($BK/dongle.beat, 한 줄 덮어쓰기·sync): 동글이 붙은 동안 "att", 뽑힌 뒤 60초 동안 "pulled <회> <뽑힌 uptime>".
#   다음 부팅의 dg_pull_endcheck가 지난 부팅의 마지막 박동으로 판정: 뽑힌 뒤 3초 안에 끊김 → 뽑기 직후 재부팅 의심, 붙은 채 끊김 →
#   판단 못 함(시동을 끈 것일 수 있음). 시험판용(1초 쓰기). 비밀값 없음. 리포트는 최근 10회.
# 끝나는 조건: 동글 상태가 wait·up·ok가 아님, 동글 사용 표시가 없음, 부팅이 바뀜, 86400번.
DG_PULLF=${DG_PULLF:-$BK/dongle.pulls}
DG_BEATF=${DG_BEATF:-$BK/dongle.beat}
DG_PULL_OK_SEC=${DG_PULL_OK_SEC:-20}
dg_up_s() { _dgu=; { read _dgu _dgux < ${UPTIME:-/proc/uptime}; } 2>/dev/null; _dgu=${_dgu%%.*}; case "$_dgu" in ''|*[!0-9]*) _dgu=0 ;; esac; }
dg_pull_line() { echo "$1" 2>/dev/null >> $DG_PULLF; $BB sync; }
dg_beat() { echo "$1" 2>/dev/null > $DG_BEATF; $BB sync; }
# dmesg에서 숫자만(뽑힘): 마지막 dev_remove start의 attached, start→done 밀리초, 중간 표시, 그 전 마지막 probe ret=0 뒤 초
dg_pull_dmesg() {
  # 리뷰 중간 3: 이번 뽑기 시각(인자 1, uptime초) 2초 전 뒤의 dev_remove만 본다(지난 회차 값이 붙지 않게). probe는 그 전 것
  dmesg 2>/dev/null | $BB awk -v t0="${1:-0}" '
    { i = index($0, "["); j = index($0, "]"); if (i == 0 || j <= i) next
      s = substr($0, i + 1, j - i - 1); while (substr(s, 1, 1) == " ") s = substr(s, 2); tm = s + 0 }
    /kp-protect: probe ret=0/ { pr = tm }
    /kp-protect: dev_remove start/ { if (tm < t0 - 2) next; st = tm; d = ""; g = "n"; u = "n"; a = "?"; if (match($0, /attached=[0-9]+/)) a = substr($0, RSTART + 9, RLENGTH - 9); spr = pr }
    /kp-protect: dev_remove ndev gone/ { if (st != "") g = "y" }
    /kp-protect: unload done/ { if (st != "") u = "y" }
    /kp-protect: dev_remove done/ { if (st != "") d = int((tm - st) * 1000 + 0.5) }
    END { if (st == "") { print "attached=? done_ms=? ndev=? unload=? probe_ago=?"; exit }
      print "attached=" a " done_ms=" (d == "" ? "?" : d) " ndev=" g " unload=" u " probe_ago=" (spr == "" ? "?" : int(st - spr)) }' 2>/dev/null
}
# dmesg에서 숫자만(다시 꽂음): 마지막 kp-protect probe ret·step
dg_back_dmesg() {
  dmesg 2>/dev/null | $BB awk -v t0="${1:-0}" '
    function tmof(l,   i, j, s) { i = index(l, "["); j = index(l, "]"); if (i == 0 || j <= i) return -1; s = substr(l, i + 1, j - i - 1); while (substr(s, 1, 1) == " ") s = substr(s, 2); return s + 0 }
    /kp-protect: probe ret=/ { if (tmof($0) < t0 - 2) next; r = "?"; s = "?"; if (match($0, /ret=-?[0-9]+/)) r = substr($0, RSTART + 4, RLENGTH - 4); if (match($0, /step=[0-9]+/)) s = substr($0, RSTART + 5, RLENGTH - 5) }
    END { print "probe_ret=" (r == "" ? "?" : r) " probe_step=" (s == "" ? "?" : s) }' 2>/dev/null
}
# 시험판 6(F7): 순정 AA의 USB 길 시작(UsbTransport : init)·결과(mUsbTransport.init() ret) 줄도 센다(다섯 번째 C에서 본 줄)
dg_aoa_count() { logcat -d 2>/dev/null | $BB awk '/startAccessory|locateGoogleDevice|UsbAccesory|UsbTransport : init|mUsbTransport\.init\(\) ret/ { n++ } END { print n + 0 }' 2>/dev/null; }
# 그 포트에 지금 있는 장치가 우리 허용 동글인가(셸 내장 read만): 1 동글, 2 다른 장치, 0 없음. 번호(devnum)는 _dgdn
dg_pull_now() {
  _dgdn=; [ -d "$DG_USBDEV" ] || return 0
  _dgiv=; _dgip=; { read _dgiv < $DG_USBDEV/idVendor; read _dgip < $DG_USBDEV/idProduct; read _dgdn < $DG_USBDEV/devnum; } 2>/dev/null
  [ "$_dgiv:$_dgip" = "$DG_USBID" ] && return 1
  # 베타 2(소유자 11-22, 세 동글 바꿔 꽂기): 다른 지원 동글이면 그것도 동글로 본다(바꿔 꽂기 = 뽑힘 → 다시 꽂음, 모델은 동글별 기록)
  dg_idok "$_dgiv:$_dgip" && return 1
  return 2
}
dg_pull_watch() {
  _dgpb=$BID; _dgpi=0; _dgpt=; _dgpk=0; _dgbk=; _dgbt=; _dgpd=; _dgfast=; _dgwk=
  # 리뷰 낮음 7: 같은 부팅에 감시가 다시 뜨면 회 번호를 이어 간다
  _dgpn=0; [ -f $DG_PULLF ] && _dgpn=$($BB awk -v b="$_dgpb" '$1 == b && $3 == "pull" { n++ } END { print n + 0 }' $DG_PULLF 2>/dev/null)
  case "$_dgpn" in ''|*[!0-9]*) _dgpn=0 ;; esac
  dg_pull_now; _dgpp=$?; _dgpd=$_dgdn
  [ $_dgpp = 1 ] && { dg_up_s; dg_beat "$_dgpb att $_dgpn $_dgu -"; }
  while [ $_dgpi -lt 86400 ]; do
    # 시험판 6(F5): 동글 부팅에 토글을 꺼도 이번 부팅은 동글 길이므로 감시를 이어 간다
    [ -f $DG_ON ] || dg_rm_now || break
    _dgps=; [ -f $W/dongle.state ] && read _dgps _dgpx < $W/dongle.state 2>/dev/null
    case "$_dgps" in wait|up|ok) ;; *) break ;; esac
    _dgpo=; read _dgpo < ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null; [ "$_dgpo" = "$_dgpb" ] || break
    dg_up_s
    dg_pull_now; _dgnow=$?
    # 리뷰 중간 2: 1초 안에 다시 잡혀 번호만 바뀐 것도 뽑힘+다시 꽂음으로 본다
    #   (이번 바퀴는 뽑힘으로 적고 다음 바퀴에 다시 꽂음으로 적는다)
    if [ $_dgpp = 1 ] && [ $_dgnow = 1 ] && [ -n "$_dgpd" ] && [ "$_dgdn" != "$_dgpd" ]; then _dgnow=0; _dgfast=1; fi
    if [ $_dgpp = 1 ] && [ $_dgnow != 1 ]; then
      _dgpn=$((_dgpn + 1)); _dgpt=$_dgu
      _dgap=?; _dgcp=?; _dgsa=?; _dgsu=; [ -f $W/dgsnap ] && read _dgap _dgcp _dgsu < $W/dgsnap 2>/dev/null
      case "$_dgsu" in ''|*[!0-9]*) ;; *) _dgsa=$((_dgu - _dgsu)) ;; esac
      _dgha=?; _dghu=; _dghb=; [ -f $W/hapd.up ] && read _dghu _dghb < $W/hapd.up 2>/dev/null
      [ "$_dghb" = "$_dgpb" ] && case "$_dghu" in ''|*[!0-9]*) ;; *) _dgha=$((_dgu - _dghu)) ;; esac
      _dgop=?; [ -r ${SYSNET:-/sys/class/net}/wlan0/operstate ] && read _dgop < ${SYSNET:-/sys/class/net}/wlan0/operstate 2>/dev/null
      case "$_dgop" in up|down|dormant|unknown|lowerlayerdown|notpresent) ;; *) _dgop=? ;; esac
      _dgmd=; _dgmx=; [ -f $W/dgmodel.cur ] && read _dgmd _dgmx _dgmy < $W/dgmodel.cur 2>/dev/null; [ "$_dgmx" = "$_dgpb" ] || _dgmd=
      dg_pull_line "$_dgpb $_dgpn pull up=$_dgu ap=${_dgap:-?} cp=${_dgcp:-?} snap_age=$_dgsa hapd_ago=$_dgha wlan0=$_dgop model=${_dgmd:-?}"
      _dgpk=1; _dgkn=$_dgpn; _dgkt=$_dgu
      [ $_dgnow = 2 ] && dg_pull_line "$_dgpb $_dgpn other up=$_dgu"
      dg_status_push
    elif [ $_dgpp != 1 ] && [ $_dgnow = 1 ]; then
      dg_pull_line "$_dgpb $_dgpn back up=$_dgu$([ -n "$_dgfast" ] && echo " fast=1")"; _dgbk=1; _dgbt=$_dgu; _dgbn=$_dgpn; _dgfast=
      dg_beat "$_dgpb att $_dgpn $_dgu -"
      # 시험판 6(F3·F4): 시도 기록을 다시 열고 표시 줄을 남긴 뒤 메인을 깨워 AP를 바로 다시 띄우게 한다.
      # wlan0이 아직 없으면 생길 때 한 번 더 깨운다(_dgwk, 10초 뒤 줄에서 끝남)
      dg_replug_mark; _dgwk=1
    elif [ $_dgpp = 0 ] && [ $_dgnow = 2 ]; then
      dg_pull_line "$_dgpb $_dgpn other up=$_dgu"
    fi
    # 심장 박동(리뷰 중간 6): 뽑힌 뒤 60초만 매초(sync). 붙어 있는 동안은 붙는 순간과 30초 점검(dg_pull_tick)만
    if [ -n "$_dgpt" ] && [ $_dgnow != 1 ] && [ $((_dgu - _dgpt)) -le 60 ]; then dg_beat "$_dgpb pulled $_dgpn $_dgu $_dgpt"; fi
    # 20초·10초 뒤 줄은 그 회 번호로(사이에 다음 뽑기가 와도 섞이지 않게)
    if [ $_dgpk = 1 ] && [ $((_dgu - _dgkt)) -ge $DG_PULL_OK_SEC ]; then dg_pull_line "$_dgpb $_dgkn ok20 $(dg_pull_dmesg $_dgkt) aoa=$(dg_aoa_count)"; _dgpk=0; fi
    # 재리뷰 낮음: 옛 wlan0이 아직 남아 있으면(번호가 AP를 띄운 때와 같음) 새 것이 생길 때까지 기다린다
    if [ "$_dgwk" = 1 ] && [ -d ${SYSNET:-/sys/class/net}/wlan0 ]; then
      dg_ifx; _dgw7=; _dgw8=; [ -f $DG_IFXF ] && read _dgw7 _dgw8 < $DG_IFXF 2>/dev/null
      [ -n "$_dgix" ] && [ "$_dgw7" = "$_dgpb" ] && [ "$_dgix" = "$_dgw8" ] || { dg_wake; _dgwk=; }
    fi
    if [ "$_dgbk" = 1 ] && [ $((_dgu - _dgbt)) -ge 10 ]; then
      _dgwk=
      _dgwl=n; [ -d ${SYSNET:-/sys/class/net}/wlan0 ] && _dgwl=y
      dg_pull_line "$_dgpb $_dgbn back10 $(dg_back_dmesg $_dgbt) wlan0=$_dgwl"; _dgbk=
    fi
    _dgpp=$_dgnow; _dgpd=$_dgdn
    sleep 1 & wait $!
    _dgpi=$((_dgpi + 1))
  done
  # 리뷰 중간 1: 감시가 일찍 끝나면 그렇게 적는다(다음 부팅이 재부팅으로 오판하지 않게)
  dg_up_s; dg_beat "$_dgpb stop $_dgpn $_dgu ${_dgpt:--}"
  rm -f $W/dgpull.pid
}
# 서비스가 시작할 때(dg_start 맨 앞) 지난 부팅의 마지막 박동으로 판정해 한 줄 남기고 박동 파일을 지운다
dg_pull_endcheck() {
  [ -f $DG_BEATF ] || return 0
  _dge1=; _dge2=; _dge3=; _dge4=; _dge5=; read _dge1 _dge2 _dge3 _dge4 _dge5 < $DG_BEATF 2>/dev/null
  [ -n "$BID" ] && [ "$_dge1" != "$BID" ] || return 0
  case "$_dge3$_dge4" in *[!0-9]*|'') rm -f $DG_BEATF; return 0 ;; esac
  # 리뷰 중간 1: 뽑힌 뒤 3초 안 끊김 → reboot, 60초(박동 끝)까지 이어짐 → survived, 그 사이 → cut(판단 못 함), 감시가 스스로 끝남 → stop
  case "$_dge2" in
    pulled) case "$_dge5" in ''|*[!0-9]*) _dgev=unknown ;; *) _dgec=$((_dge4 - _dge5)); if [ $_dgec -le 3 ]; then _dgev=reboot; elif [ $_dgec -ge 60 ]; then _dgev=survived; else _dgev=cut; fi ;; esac ;;
    att) _dgev=att_end ;;
    stop) _dgev=watcher_end ;;
    *) _dgev=unknown ;;
  esac
  dg_pull_line "$_dge1 $_dge3 end $_dgev last=$_dge4"
  rm -f $DG_BEATF
  # 리뷰 낮음 8: 최근 80줄만 남긴다(시동을 끄는 보통의 끝에서는 감시가 정리하지 못하므로 여기서)
  _dgpc=0; [ -f $DG_PULLF ] && _dgpc=$($BB awk 'END { print NR + 0 }' $DG_PULLF 2>/dev/null)
  [ "${_dgpc:-0}" -gt 80 ] 2>/dev/null && $BB awk '{ a[NR] = $0 } END { for (i = NR - 79; i <= NR; i++) print a[i] }' $DG_PULLF 2>/dev/null > $DG_PULLF.tmp && $BB mv -f $DG_PULLF.tmp $DG_PULLF
  return 0
}
# --- 동글별 기록(베타 2 니로 시험판, 소유자 11-22: 세 동글 바꿔 꽂기) ---
# 30초 점검마다 지금 꽂힌 지원 동글의 모델을 보고, 이 부팅에 처음 본 모델이면
# 판정 결과(기록만)와 함께 $BK/dongle.models에 한 줄, 그 모델로 무선 카플레이가 연결되면 한 줄. 최근 60줄만
DG_MODELF=${DG_MODELF:-$BK/dongle.models}
# 베타 3(B3-11·B2-8): 마지막 동글 상태 "model=<모델> sup=yes|no|unknown conn=yes|no t=<MM-DD_HH:MM>"($BK, 재부팅·업데이트에도 남음).
# 제보 USB를 꽂으려고 동글을 빼도 리포트에 직전 상태가 나오게 한다. 모델 이름은 확인된 제품 이름뿐(번호·MAC 없음)
DG_LASTF=${DG_LASTF:-$BK/dongle.last}
dg_last() {
  case "$1" in ''|*[!0-9A-Za-z._-]*) return 0 ;; esac
  _dlsp=unknown; case "$DG_OUIR" in ok|id|lax) _dlsp=yes ;; no) _dlsp=no ;; esac
  echo "model=$1 sup=$_dlsp conn=$2 t=$(date '+%m-%d_%H:%M' 2>/dev/null)" 2>/dev/null > $DG_LASTF.tmp && $BB mv -f $DG_LASTF.tmp $DG_LASTF 2>/dev/null
  return 0
}
# DG_USBDEV·DG_USBID(dg_usb 결과)로 모델 이름(영문 낱말, 공백 없음)
# 정식(A2): 모델 표도 해시(vid:pid, vid:pid|제품). 제품 칸이 *이면 그 번호면 그 모델
dg_model() {
  dg_h "$DG_USBID"; _dgmi=$_dgh; [ -n "$_dgmi" ] || { echo other; return 0; }
  us_rd $DG_USBDEV/product; dg_h "$DG_USBID|$_ur"; _dgmp=$_dgh
  while IFS='|' read -r _dgm1x _dgm2x _dgm3x; do
    [ "$_dgm1x" = "$_dgmi" ] || continue
    { [ "$_dgm2x" = '*' ] || { [ -n "$_dgmp" ] && [ "$_dgm2x" = "$_dgmp" ]; }; } && { echo "$_dgm3x"; return 0; }
  done <<DGMODELS
$DG_MODELS
DGMODELS
  echo other
}
dg_model_tick() {
  dg_usb
  if [ "$DG_USB" = ok ] && [ -n "$DG_USBDEV" ]; then _dgm1=$(dg_model)
  # 리뷰 중간 2: 허용 밖 동글(드라이버는 붙음)·문자열이 다른 동글도 "목록 밖"으로 남긴다
  elif [ "$DG_USB" = notlisted ] || dg_seen; then _dgm1=other
  else return 0; fi
  # 배포판(R8): 넷째 칸(그 모델을 본 uptime)까지 따로 읽는다(셋만 읽으면 셋째 칸에 넷째가 붙어 연결을 못 셈)
  _dgmc=; _dgmb=; _dgmz=; _dgmw=; [ -f $W/dgmodel.cur ] && read _dgmc _dgmb _dgmz _dgmw < $W/dgmodel.cur 2>/dev/null
  _dgmn=$(cat $CPN 2>/dev/null); case "$_dgmn" in ''|*[!0-9]*) _dgmn=0 ;; esac
  if [ "$_dgm1" != "$_dgmc" ] || [ "$_dgmb" != "$BID" ]; then
    if [ "$_dgm1" = other ]; then DG_OUIR=unk
    else
      # 동글 판정(DG-3). 리뷰 중간 3: 4번 점검(약 2분)에도 결과가 없으면 "확인 못 함"으로 적는다
      dg_oui
      if [ -z "$DG_OUIR" ]; then
        _dgt1=; _dgt2=0; [ -f $W/dgmodel.try ] && read _dgt1 _dgt2 < $W/dgmodel.try 2>/dev/null
        [ "$_dgt1" = "$_dgm1" ] || _dgt2=0; case "$_dgt2" in ''|*[!0-9]*) _dgt2=0 ;; esac
        _dgt2=$((_dgt2 + 1)); echo "$_dgm1 $_dgt2" 2>/dev/null > $W/dgmodel.try
        [ $_dgt2 -ge 4 ] || return 0
        DG_OUIR=unk
      fi
    fi
    rm -f $W/dgmodel.try
    # 리뷰 높음 1: 바꾼 직후 남은 연결(이전 동글의 것)을 새 모델로 세지 않게, 연결 수가 0인 것을 한 번 본 뒤부터만 센다(세 번째 칸 z).
    # 베타 2(R8): 그 모델을 본 uptime을 넷째 칸에 둔다(그 뒤 우리 AP가 다시 뜨고 기기가 붙으면 연결로 봄, 아래)
    _dgmz=0; [ "$_dgmn" = 0 ] && _dgmz=1
    # 리뷰(배포판 높음 2): "본 때"는 바꿔 꽂은 때(이 부팅 다시 잡힘 기록이 앞 모델 기록보다 나중이면 그 시각)로 둔다. 모델 기록은 주소를
    # 읽은 뒤라 AP가 다시 뜬 것보다 늦을 수 있다(여섯 번째: 바꿔 꽂고 약 2초 뒤 AP-ENABLED)
    dg_up_s; _dgmst=$_dgu
    _dgmr1=; _dgmr2=; [ -f $W/dgreplug ] && read _dgmr1 _dgmr2 < $W/dgreplug 2>/dev/null
    if [ "$_dgmr1" = "${BID:-none}" ]; then case "$_dgmr2" in ''|*[!0-9]*) ;; *)
      _dgmpw=$_dgmw; [ "$_dgmb" = "${BID:-none}" ] || _dgmpw=0; case "$_dgmpw" in ''|*[!0-9]*) _dgmpw=0 ;; esac
      [ "$_dgmr2" -gt "$_dgmpw" ] && [ "$_dgmr2" -le "$_dgu" ] && _dgmst=$_dgmr2 ;; esac; fi
    echo "$_dgm1 ${BID:-none} $_dgmz $_dgmst" 2>/dev/null > $W/dgmodel.cur
    echo "${BID:-none} seen model=$_dgm1 oui=$DG_OUIR" 2>/dev/null >> $DG_MODELF
    dg_last "$_dgm1" no
    log "동글별 기록: $_dgm1 꽂힘, 지원 동글 $(dg_oui_text $DG_OUIR)"
    # 시험판 5(메인 11-23, 운행마다 다른 동글): 부팅 기록에도 그 부팅의 모델을 한 줄(번호는 쓰지 않음)
    dg_boot0 "seen:$_dgm1"
    return 0
  fi
  if [ "$_dgmz" != 1 ]; then
    if [ "$_dgmn" = 0 ]; then echo "$_dgm1 ${BID:-none} 1 $_dgmw" 2>/dev/null > $W/dgmodel.cur; return 0; fi
    # 베타 2(R8, 여섯 번째 차): 바꿔 꽂는 동안 연결 수가 0으로 안 떨어져도, 이 모델을 본 뒤 우리 AP가 다시 떴고(다시 띄우면 옛 연결은
    # 모두 끊김) 동글 wlan0에 기기가 붙어 있으면(ARP 완료, 새 wlan0은 빈 표로 시작) 그 모델의 연결로 본다
    _dgmh=; _dgmb2=; [ -f $W/hapd.up ] && read _dgmh _dgmb2 < $W/hapd.up 2>/dev/null
    case "$_dgmh" in ''|*[!0-9]*) return 0 ;; esac
    case "$_dgmw" in ''|*[!0-9]*) return 0 ;; esac
    [ "$_dgmb2" = "${BID:-none}" ] && [ "$_dgmh" -ge "$_dgmw" ] || return 0
    _dgms=$($BB awk -v i=$WIF '$6 == i && $3 == "0x2" { n++ } END { print n + 0 }' ${PROC:-/proc}/net/arp 2>/dev/null)
    case "$_dgms" in ''|*[!0-9]*|0) return 0 ;; esac
  fi
  if [ "$_dgmn" -gt 0 ] && ! $BB grep -q "^${BID:-none} conn model=$_dgm1\$" $DG_MODELF 2>/dev/null; then
    echo "${BID:-none} conn model=$_dgm1" 2>/dev/null >> $DG_MODELF; log "동글별 기록: $_dgm1로 무선 카플레이 연결됨"
    dg_last "$_dgm1" yes
  fi
  _dgmk=0; [ -f $DG_MODELF ] && _dgmk=$($BB awk 'END { print NR + 0 }' $DG_MODELF 2>/dev/null)
  [ "${_dgmk:-0}" -gt 60 ] 2>/dev/null && $BB awk '{ a[NR] = $0 } END { for (i = NR - 59; i <= NR; i++) print a[i] }' $DG_MODELF 2>/dev/null > $DG_MODELF.tmp && $BB mv -f $DG_MODELF.tmp $DG_MODELF
  return 0
}
# dg_tick에서: 동글 길을 쓰는 중이면 점검 값(AP·카플레이 수·uptime)을 남기고, 감시가 없으면 띄운다(한 부팅에 한 감시)
dg_pull_tick() {
  case "$DG_ST" in up|ok) ;; *) return 0 ;; esac
  [ -n "$DG_USBDEV" ] && [ -d "$DG_USBDEV" ] || dg_usb
  [ -n "$DG_USBDEV" ] || return 0
  dg_up_s; _dgra=n; running "hostapd $CONF" && _dgra=y
  echo "$_dgra $(cat $CPN 2>/dev/null || echo 0) $_dgu" 2>/dev/null > $W/dgsnap
  # 붙어 있는 동안의 박동은 30초마다(리뷰 중간 6)
  dg_pull_now; [ $? = 1 ] && { _dgbl=; [ -f $DG_BEATF ] && read _dgbl _dgbk2 < $DG_BEATF 2>/dev/null; [ "$_dgbk2" = pulled ] || dg_beat "${BID:-none} att 0 $_dgu -"; }
  _dgw1=; _dgw2=; [ -f $W/dgpull.pid ] && read _dgw1 _dgw2 < $W/dgpull.pid 2>/dev/null
  if [ -n "$_dgw1" ] && [ "$_dgw2" = "$BID" ] && kill -0 $_dgw1 2>/dev/null; then return 0; fi
  ( dg_pull_watch ) </dev/null >/dev/null 2>&1 &
  echo "$! ${BID:-none}" 2>/dev/null > $W/dgpull.pid
  return 0
}

# --- 1.8.0 동글 판정(DG-3) ---
dg_oui() {
  DG_OUIR=
  [ -n "$DG_USBDEV" ] || return 0
  dg_names_has "$DG_USBID" || { DG_OUIR=id; return 0; }
  _dgaf=
  for _dgi3 in $DG_USBDEV/*:*; do for _dgn3 in $_dgi3/net/*; do [ -f $_dgn3/address ] && { _dgaf=$_dgn3/address; break 2; }; done; done
  [ -n "$_dgaf" ] || return 0
  # 동글 판정(DG-3) 비공개 기록. 값은 셸 변수에 두지 않고 awk가 파일로 바로 쓴다
  $BB awk -v af="$_dgaf" -v b="${BID:-none}" -v id="$DG_USBID" 'BEGIN { a = ""; if ((getline a < af) <= 0) exit
    a = toupper(a); if (a !~ /^[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]:/) exit; print b, id, substr(a, 1, 8) }' 2>/dev/null > $DG_OUIVF.tmp \
    && [ -s $DG_OUIVF.tmp ] && $BB mv -f $DG_OUIVF.tmp $DG_OUIVF 2>/dev/null; rm -f $DG_OUIVF.tmp
  # 정식(A2): awk는 꼴만 본다(unk·no, 대조할 것이면 chk). 대조할 "kp180|vid:pid|OUI" 한 줄은 셸 변수에 두지 않고 임시 파일(tmpfs)에 써서
  # 바로 sha1sum에 넘긴 뒤 지운다(dg_h와 같은 꼴: 값 뒤 줄바꿈 하나)
  # 정식 리뷰 L9: 임시 파일은 tmpfs(/dev)에 두고 해시한 뒤 바로 지운다(플래시에 쓰지 않음)
  _dgot=${DG_OUIT:-/dev/.kp-ouih}.$$
  DG_OUIR=$($BB awk -v id="$DG_USBID" -v af="$_dgaf" -v hp="$DG_HP" -v of="$_dgot" 'BEGIN {
      a = ""; if ((getline a < af) <= 0) { print "unk"; exit }
      a = toupper(a); if (a !~ /^[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]:/) { print "unk"; exit }
      f = index("0123456789ABCDEF", substr(a, 2, 1)) - 1; if (f % 4 >= 2) { print "no"; exit }
      print hp id "|" substr(a, 1, 8) > of; close(of); print "chk" }' 2>/dev/null)
  if [ "$DG_OUIR" = chk ]; then
    _dgoh=; [ -s $_dgot ] && _dgoh=$($BB sha1sum < $_dgot 2>/dev/null); _dgoh=${_dgoh%% *}
    rm -f $_dgot
    DG_OUIR=no
    case "$_dgoh" in ''|*[!0-9a-f]*) DG_OUIR=unk ;; *)
      while IFS='|' read -r _dgo1x _dgo2x; do [ "$_dgo2x" = "$_dgoh" ] && { DG_OUIR=ok; break; }; done <<DGOUI
$DG_OUI
DGOUI
      ;;
    esac
  fi
  rm -f $_dgot
  case "$DG_OUIR" in ok|no|unk) ;; *) DG_OUIR=unk ;; esac
  # 동글 판정(DG-3). 정식(A2): 해시(vid:pid|제품)로 대조
  if [ "$DG_OUIR" != ok ] && [ -n "$DG_OUI_LAX" ]; then
    us_rd $DG_USBDEV/product
    if [ -n "$_ur" ]; then
      dg_h "$DG_USBID|$_ur"
      [ -n "$_dgh" ] && case "
$DG_OUI_LAX
" in *"
$_dgh
"*) DG_OUIR=lax ;; esac
    fi
  fi
  return 0
}
# 공개 리포트·ap.log용 낱말(판단 방식을 드러내지 않음, 소유자 지시 11-23): 지원 동글 예·아니요·확인 못 함
dg_oui_text() { case "$1" in ok|id|lax) echo "예" ;; no) echo "아니요" ;; unk) echo "확인 못 함" ;; *) echo "기록 없음" ;; esac; }
# 이 결과로 우리 AP를 띄워도 되는가(막기 켜짐이면 ok·id만, 꺼짐이면 늘 됨)
dg_oui_allowed() { [ "$DG_OUI_ENFORCE" = 1 ] || return 0; case "$1" in ok|id|lax) return 0 ;; esac; return 1; }
# 동글 판정(DG-3): 30초 점검마다(드라이버가 올라온 뒤 한 부팅에 한 번)
dg_oui_tick() {
  case "$DG_ST" in up|ok) ;; *) return 0 ;; esac
  [ "$DG_OUIDONE" = 1 ] && return 0
  _dgo1=; _dgo2=; _dgo3=; [ -f $DG_OUIF ] && read _dgo1 _dgo2 _dgo3 < $DG_OUIF 2>/dev/null
  if [ -n "$BID" ] && [ "$_dgo3" = "$BID" ]; then
    # 같은 부팅에 서비스가 다시 시작함: 지난 결과를 그대로 쓴다
    DG_OUIR=$_dgo1
  else
    # 리뷰 낮음 6: 같은 부팅에 서비스가 다시 시작하면 dg_usb를 거치지 않으므로 장치를 다시 찾는다
    [ -n "$DG_USBDEV" ] || dg_usb
    # 동글이 아직 우리 드라이버에 붙지 않았으면(꽂기 전·프로브 중) 판단하지 않고 기다림도 세지 않는다
    dg_seen || return 0
    [ -n "$DG_USBDEV" ] || return 0
    dg_oui
    # 네트워크 장치 주소를 아직 못 읽음: 4번(30초 점검과 AP 띄우기 앞 확인이 함께 세어 약 1~2분)까지 기다린 뒤 "확인 못 함"
    # (배포판: 막기 켜짐이면 띄우지 않음). 재리뷰 중간 1: ok 상태라고 바로 "확인 못 함"으로 하지 않는다(바꿔 꽂은 직후 한 번 못 읽어도 기다림)
    if [ -z "$DG_OUIR" ]; then
      DG_OUIWAIT=$((${DG_OUIWAIT:-0} + 1)); [ $DG_OUIWAIT -ge 4 ] || return 0; DG_OUIR=unk
    fi
    echo "$DG_OUIR ${DG_USBID:--} ${BID:-none}" 2>/dev/null > $DG_OUIF
    log "동글 확인: 지원 동글 $(dg_oui_text $DG_OUIR)"
  fi
  DG_OUIDONE=1
  if ! dg_oui_allowed "$DG_OUIR"; then
    # 재리뷰 중간 2: 우리 AP를 띄우지 않으므로 위험한 단계가 남지 않는다. 다시 연 시도 기록을 닫는다(지원 밖 동글이 hang 막힘이 되지 않게)
    DG_ST=notours; dg_state notours "$DG_G"; dg_bst notours; stop_ours; rm -f $DG_TRY $BK/dongle.noprobe; $BB sync; dg_guard_release
    log "동글: 지원 목록의 동글이 아니라 이번 부팅은 우리 AP를 띄우지 않음(동글 설정은 그대로, 다음 시동에 다시 확인)"
  fi
  return 0
}
# 배포판: 동글 wlan0에 우리 AP를 띄우기 전에 지원 동글인지 정한다(up이 부름). 0이면 띄워도 됨, 1이면 아직(또는 막힘)
dg_oui_gate() {
  [ "$DG_OUI_ENFORCE" = 1 ] || return 0
  [ "$DG_OUIDONE" = 1 ] || dg_oui_tick
  [ "$DG_OUIDONE" = 1 ] && dg_oui_allowed "$DG_OUIR"
}
# --- 1.8.0 베타 2 DG-5·DG-6: 동글 wlan0 위의 우리 AP ---
# 동글 길을 쓰는 중인가: 이 서비스가 올린 우리 드라이버가 올라옴(up·ok). 이때 wlan0은 동글이다(내장 드라이버는 내렸거나 없음).
# 우리 AP는 예전과 같은 up()이 같은 설정(hostapd-kp.conf, 5GHz 149번 40MHz)으로 띄운다. 동글이 이 설정을 받는지는 차에서 확인 안 함.
dg_using() { [ "$DG_RUN" = 1 ] && case "$DG_ST" in up|ok) true ;; *) false ;; esac; }
DG_NOAP_MAX=${DG_NOAP_MAX:-5}
# hostapd 출력에서 실패 분류만 고른다(원문·SSID·MAC은 내지 않음, 끝에 한 줄)
# 정식 F5(beta3-reports 9장): 내비 hostapd는 오류를 표준 출력이 아니라 logcat(E/hostapd)에만 쓴다. 출력이 비면 dg_ap_died가 logcat에서
# 같은 분류를 한다. "Failed to request a scan of neighboring BSSes"는 40MHz 이웃 검색(HT_SCAN)을 드라이버가 거절한 것(늦게 꽂은 부팅 꼴)
DG_HAWHY_AWK='{ l = tolower($0) }
l ~ /failed to request a scan/ { r = "40MHz 이웃 검색을 드라이버가 거절" }
l ~ /not allowed|no-ir|no_ir|no ir|could not set channel|disabled channel|dfs/ { r = "채널 149를 쓸 수 없음(나라 규칙)" }
r == "" && l ~ /ht40|secondary channel|ht_capab/ { r = "40MHz 설정을 받지 않음" }
r == "" && l ~ /nl80211|driver/ && l ~ /fail|error|could not/ { r = "드라이버가 AP 모드를 받지 않음" }
r == "" && l ~ /unable to setup interface|failed to initialize|was not started|wasn.t started/ { r = "인터페이스를 시작하지 못함" }
END { if (r != "") print r }'
# 동글 wlan0에서 hostapd가 4초 안에 꺼짐(동글이 빠진 것·다른 hostapd에 비킨 것은 여기에 오지 않음: wlan0 없음·ap_yield)
dg_ap_died() {
  _dgwy=; [ -f $W/ha.why ] && IFS= read -r _dgwy < $W/ha.why 2>/dev/null
  # 정식 F5: 표준 출력에서 못 고르면 logcat의 hostapd 줄로 고른다(분류 낱말만 냄, SSID 등 원문은 남기지 않음)
  # 정식 2차 리뷰 L4: 이번 hostapd를 띄운 시각(HAPD_T0) 뒤 줄만 본다(지난 실패 줄로 이유를 정하지 않게). 시각을 모르면 모두 본다
  [ -n "$_dgwy" ] || _dgwy=$(logcat -d -v time -s hostapd:V 2>/dev/null | $BB awk -v t0="$HAPD_T0" 't0 == "" || ($1 " " $2) >= t0' 2>/dev/null | $BB awk "$DG_HAWHY_AWK" 2>/dev/null)
  DG_NOAP=$((${DG_NOAP:-0} + 1))
  log "동글: 우리 AP(hostapd)가 동글 wlan0에서 꺼짐(이어서 ${DG_NOAP}/${DG_NOAP_MAX}번, 이유 ${_dgwy:-모름})"
  echo "${BID:-none} $DG_NOAP ${_dgwy:-모름}" 2>/dev/null > $W/dongle.noap
  # 정식 F5(beta3-reports 9장): tcc803x에서 부팅 때 없던 동글(insmod 뒤 처음 꽂음)은 이 부팅 hostapd가 모두 4초 안에 꺼졌고(17/17),
  # 꽂은 채 재부팅하면 모두 떴다(4/4). 그래서 그 꼴의 첫 실패에서 바로 멈추고 재부팅을 안내한다. 다음 부팅의 이른 가드가 걸리게
  # 버스 기억도 지금 적는다(C1 ⓐ와 같은 dg_gbus_save). 니로(tcc897x)는 같은 꼴에서 떴으므로 칩을 tcc803x로 좁힌다(동작 그대로)
  if dg_late_first; then
    stop_ours; rm -f $DG_TRY $BK/dongle.noprobe
    echo "${BID:-none}" 2>/dev/null > $W/dg.lateap
    dg_gbus_save; $BB sync
    DG_ST=noap; dg_state noap "$DG_G"; dg_step noap-late; dg_bst noap
    log "동글: 이 부팅에 늦게 꽂은 동글(insmod 때 없음)에서 첫 hostapd가 4초 안에 꺼짐 — 다시 띄우지 않고 동글을 꽂은 채 재부팅하라고 안내"
    return 0
  fi
  # 시험판 5: 그 부팅만(막힘 기록 없음). 동글이 wlan0을 잡고 있어 내장으로 못 가므로 무선 없음, 다음 시동에 다시 시도
  if [ $DG_NOAP -ge $DG_NOAP_MAX ]; then
    stop_ours; rm -f $DG_TRY $BK/dongle.noprobe; $BB sync; DG_ST=noap; dg_state noap "$DG_G"; dg_step noap; dg_bst noap
    log "동글: 우리 AP가 ${DG_NOAP_MAX}번 꺼져 이번 부팅은 동글 AP를 그만 띄움 — 다음 시동에 다시 시도"
  fi
  return 0
}
# 정식 F5: 이 부팅에 늦게 꽂은 동글의 첫 hostapd 실패인가. tcc803x 묶음, insmod 때 동글 없음($W/dg.late가 이 부팅),
# 이어진 실패 첫 번째, 이 부팅에 우리 hostapd가 한 번도 뜨지 않음(hapd.any가 이 부팅이 아님)
dg_late_first() {
  [ "$DG_G" = tcc803x-a ] && [ "${DG_NOAP:-0}" = 1 ] || return 1
  _dglf=; [ -f $W/dg.late ] && read _dglf < $W/dg.late 2>/dev/null
  [ -n "$_dglf" ] && [ "$_dglf" != none ] && [ "$_dglf" = "$(dg_kv_bid)" ] || return 1
  _dglf=; [ -f $W/hapd.any ] && read _dglf < $W/hapd.any 2>/dev/null
  [ "$_dglf" != "$(dg_kv_bid)" ]
}
# 이번 부팅 noap가 늦게 꽂은 동글 때문인가(상태 화면 문구 고르기)
dg_lateap_now() { _dglf=; [ -f $W/dg.lateap ] && read _dglf < $W/dg.lateap 2>/dev/null; [ -n "$_dglf" ] && [ "$_dglf" = "$(dg_kv_bid)" ]; }
# DG-6: 동글 wlan0에 붙은 기기 수. 브로드컴 커널 줄(wifi_events)은 동글에서 나오지 않아 ARP(완료 0x2)로 센다.
# 한계: ARP 줄은 기기가 떠난 뒤에도 몇 분 남을 수 있어 0대가 늦게 잡힌다. 0대가 되면 WGONE(무선 AA 연결됨 지우기 근거)
dg_sta() {
  _dgsn=$($BB awk -v i=$WIF '$6 == i && $3 == "0x2" { n++ } END { print n + 0 }' ${PROC:-/proc}/net/arp 2>/dev/null)
  case "$_dgsn" in ''|*[!0-9]*) return 0 ;; esac
  [ "${WSTA:-0}" -gt 0 ] && [ "$_dgsn" = 0 ] && WGONE=1
  WSTA=$_dgsn
  return 0
}
# 동글 사용 표시가 있는가(막힘 없음). 칩 실패 셈(nowlan.boots)에서 빼는 데만 쓴다(부품 없는 동글 차가 "칩 실패"로 굳지 않게)
dg_dongle_on() { [ -f $DG_ON ] && [ ! -f $DG_BLOCK ]; }
# --- 1.8.0 DG-7: 삭제 때 우리가 올린 동글 드라이버만 내린다 ---
# 올라간 뒤 $BK/dongle.mod("<boot_id> <모듈 이름>")에 남긴다. 패키지를 지울 때(preun, uninstall만, 업데이트는 내리지 않음) 그 기록이
# 이번 부팅 것이고 그 모듈이 Live일 때만 rmmod한다(다른 패키지가 올린 같은 이름·지난 부팅 기록은 건드리지 않음).
# rmmod는 뒤에서 돌리고 DG_RMWAIT초(기본 10초)만 기다린다(커널 안에서 멈춰도 삭제가 멈추지 않게).
RMMOD_SYS=${RMMOD_SYS:-/system/bin/rmmod}
dg_unload() {
  [ -f $BK/dongle.mod ] || return 0
  _dgb=; _dgm=; read _dgb _dgm < $BK/dongle.mod 2>/dev/null
  _dgnow=$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)
  if [ "$_dgm" = $DG_MOD ] && [ -n "$_dgnow" ] && [ "$_dgb" = "$_dgnow" ] && dg_live; then
    _dgrm=$RMMOD_SYS; [ -x "$_dgrm" ] || _dgrm="$BB rmmod"
    # 리뷰 높음 2: 하위 셸째 입출력을 떼어 둔다(rmmod가 커널 안에서 멈춰도 NEMESIS의 출력 파이프를 잡고 있지 않게)
    ( $_dgrm $DG_MOD ) </dev/null >/dev/null 2>&1 &
    _dgw=0
    while dg_present && [ $_dgw -lt ${DG_RMWAIT:-10} ]; do sleep 1 & wait $!; _dgw=$((_dgw + 1)); done
    if dg_present; then echo "동글 드라이버를 내리지 못함(그대로 두고 지움, 재부팅하면 내려감)"; else echo "우리가 올린 동글 드라이버를 내림"; fi
  fi
  rm -f $BK/dongle.mod
  return 0
}
# --- 1.8.0 SC-5 동글 토글: 차주 선택과 자동 켜기(소유자 결정 2026-11-18 밤) ---
# 기록($BK, 업데이트에 남고 삭제에 지워짐):
#   dongle.on   토글 켜짐 표시(DG-4 이하가 봄)
#   dongle.user 차주가 상태 화면 토글로 직접 고른 값 "on|off". 있으면 자동은 아무것도 하지 않는다(차주 선택이 먼저)
#   dongle.auto 자동으로 켠 근거 "on <근거> <boot_id>"(근거: nopart 부품 없음, nochip 칩이 3번 깨워도 안 켜짐, nowlan 3부팅 넘게 wlan0 없음)
# 자동 켜기 조건(모두): 차주 선택 없음, 아직 꺼짐, 막힘 없음, 무선 모드 고정(mod.pin) 없음(결정 대기, 베타 2), 내장 Wi-Fi가 안 된다는
#   근거가 여러 부팅에 걸쳐 쌓임(위 셋 중 하나, 한 번의 실패로 바꾸지 않음), 허용 동글이 실제로 꽂혀 있음, 칩에 맞는 드라이버가 있음,
#   다른 동글 패키지 없음. 한 번 켜면 유지한다(자동으로 끄지 않음, 동글을 잠깐 빼도 그대로). 끄는 것은 차주만.
# 상태 키(앱 세션 제안에 맞춤, 11-18 밤): dongle_set=auto|on|off(auto = 차주가 고르지 않음, on/off = 차주 선택),
#   dongle_why=nochip|builtin_bad|builtin_ok|nodongle(자동일 때만, 차주 선택이면 빈 값):
#   nochip 부품 없음(nopart)으로 켬, builtin_bad 내장이 여러 부팅 안 됨(nochip·nowlan)으로 켬, builtin_ok 내장 Wi-Fi가 됨(꺼짐),
#   nodongle 근거는 있지만 허용 동글(또는 이 칩용 드라이버)이 없음(꺼짐). 지금 켜졌는지는 기존 dongle 키(off = 꺼짐)로 본다.
DG_USER=${DG_USER:-$BK/dongle.user}
DG_AUTO=${DG_AUTO:-$BK/dongle.auto}
DG_AUTO_NOWLAN=${DG_AUTO_NOWLAN:-3}
# 차주가 "자동으로 되돌리기"(설정 요청 dongle=auto, 소유자 결정 (가) 11-18 밤)를 고른 표시. 다음 부팅에 한 번 지금 토글을 비우고 자동 판단을 새로 한다
DG_REAUTO=${DG_REAUTO:-$BK/dongle.reauto}
DG_AUTO_MSG="내장 Wi-Fi가 되지 않아 USB Wi-Fi 동글을 쓰도록 자동으로 켰습니다."
# 차주 선택(설정 요청 dongle=on|off). 켜기·끄기를 하고 선택을 남긴다. 다시 읽어 맞으면 0
# 리뷰 낮음 7: 토글(dongle.on)을 먼저 바꾸고 확인한 뒤에 선택 기록을 쓴다. 기록을 못 쓰면 토글을 원래대로 돌린다(반쯤 바뀐 상태를 남기지 않음)
dg_toggle_set() {
  case "$1" in on|off) ;; *) return 1 ;; esac
  _dgprev=off; [ -f $DG_ON ] && _dgprev=on
  # 시험판 6(F5): 동글이 wlan0을 잡은 부팅(dg_rm_now)에는 꺼도 이번 부팅은 동글 길이라 가드를 풀지 않는다(다음 부팅에 /dev와 함께 없어짐).
  # 다섯 번째 C: 끄자마자 가드가 풀려 바꿔 꽂은 동글에 순정 AOA가 닿고 순정 resetUSB가 났다
  if [ "$1" = on ]; then : 2>/dev/null > $DG_ON; [ -f $DG_ON ] || return 1; else rm -f $DG_ON; [ ! -f $DG_ON ] || return 1; dg_rm_now || dg_guard_release; fi
  # 베타 3(B3-3 a_dongle): 꺼짐 → 켜짐일 때만
  [ "$1" = on ] && [ $_dgprev = off ] && dbg_trig a a_dongle
  # 리뷰 중간 2: 차주가 동글 사용을 껐다 켜면 바로 올리기 실패 수도 지운다(다시 시도)
  [ "$1" = on ] && rm -f $DG_FASTF $BK/dongle.noladder $BK/dongle.ladcrash
  # 시험판 5: 동글 사용을 끄면 계속 막힘(hang)을 푼다(다음에 켜면 다시 시도). 기록은 .prev로 남김
  if [ "$1" = off ] && [ -f $DG_BLOCK ]; then
    $BB mv -f $DG_BLOCK $DG_BLOCK.prev 2>/dev/null; rm -f $DG_TRY $BK/dongle.noprobe; log "동글: 동글 사용을 꺼서 막힘 기록을 풂(다음에 켜면 다시 시도)"
  fi
  if echo "$1" 2>/dev/null > $DG_USER.tmp && $BB mv -f $DG_USER.tmp $DG_USER 2>/dev/null; then
    # 리뷰 중간 3: 앱 답(45초)을 늦추지 않게 저장값 맞추기는 뒤에서(서비스 시작·재부팅 직전에도 다시 맞춤)
    rm -f $DG_AUTO $DG_REAUTO; ( dg_wifi_sync ) </dev/null 2>/dev/null & return 0
  fi
  rm -f $DG_USER.tmp
  if [ $_dgprev = on ]; then : 2>/dev/null > $DG_ON; else rm -f $DG_ON; fi
  return 1
}
# 내장 Wi-Fi가 안 된다는 근거(여러 부팅에 걸쳐 쌓인 기록만): nopart | nochip | nowlan | (빈 값)
# 리뷰(SC-5) 높음 2: 지금 칩이 보이면(SDIO·HMG-API 칩 기록) 근거가 아니다(상태 화면 판정 kp_verdict와 같게).
# 높음 1: 칩 실패(nochip)는 순정 Wi-Fi 근거 기록(nochip-wifi.txt)이 있을 때만(깨우는 도중에 시동을 꺼 횟수만 찬 기록은 아님).
# 중간 3: wlan0 없는 부팅(nowlan)은 우리가 칩을 깨워 본 적이 있고(wifi.woke) 무선 모드가 깔린 차(#55 꼴)만. 설정 중·지도 실패·부팅 보호
#   부팅에 쌓인 수는 근거로 보지 않는다
dg_evidence() {
  wifi_chip_seen && return 0
  if [ -f $BK/wifi.nopart ]; then echo nopart; return 0; fi
  if [ -f $BK/wifi.nochip ] && [ -s $BK/nochip-wifi.txt ]; then echo nochip; return 0; fi
  [ -f $BK/wifi.woke ] && [ -f $HMGDATA/mods/$MOD_ID/mod.json ] || return 0
  _dgnb=0; [ -f $BK/nowlan.boots ] && read _dgnb _dgx < $BK/nowlan.boots 2>/dev/null
  case "$_dgnb" in ''|*[!0-9]*) _dgnb=0 ;; esac
  [ $_dgnb -ge $DG_AUTO_NOWLAN ] && echo nowlan
  return 0
}
# 차주 선택을 지우고 다음 부팅부터 자동 판단을 따르게 한다(지금 토글은 다음 부팅의 dg_auto가 다시 정함)
dg_toggle_auto() {
  echo "${BID:-none}" 2>/dev/null > $DG_REAUTO.tmp && $BB mv -f $DG_REAUTO.tmp $DG_REAUTO 2>/dev/null || { rm -f $DG_REAUTO.tmp; return 1; }
  rm -f $DG_USER
  [ ! -f $DG_USER ] || { rm -f $DG_REAUTO; return 1; }
  return 0
}
dg_auto() {
  # 자동으로 되돌린 뒤 첫 부팅: 지난 선택으로 켜 둔 토글을 비우고 아래 조건대로 새로 정한다(맞으면 다시 켜고, 아니면 꺼진 채 = 다음 fix_perms가 정리)
  if [ -f $DG_REAUTO ] && [ ! -f $DG_USER ]; then
    rm -f $DG_REAUTO $DG_ON $DG_AUTO
    log "동글 토글: 차주가 자동으로 되돌림, 이번 부팅에 자동 판단을 새로 함"
  fi
  [ -f $DG_USER ] && return 0
  [ -f $DG_ON ] && return 0
  [ -f $DG_BLOCK ] && return 0
  [ -f $BK/mod.pin ] && return 0
  _dgwhy=$(dg_evidence)
  [ -n "$_dgwhy" ] || return 0
  dg_usb; [ $DG_USB = ok ] || return 0
  dg_pick || return 0
  [ -s $DG_DRV/$DG_G/$DG_MOD.ko ] || return 0
  dg_otherpkg && return 0
  echo "on $_dgwhy ${BID:-none}" 2>/dev/null > $DG_AUTO.tmp && $BB mv -f $DG_AUTO.tmp $DG_AUTO 2>/dev/null && : 2>/dev/null > $DG_ON
  if [ -f $DG_ON ]; then
    # 리뷰 낮음 6: 알림이 LAST_MSG(설정 진행 문구)를 바꾸지 않게 되돌린다(뒤의 fix_perms가 그 값을 실패 이유로 보이지 않게)
    log "동글 토글을 자동으로 켬(근거 $_dgwhy, 허용 동글이 꽂혀 있음)"; _dglm=$LAST_MSG; pnotice "Korea Projection: $DG_AUTO_MSG"; LAST_MSG=$_dglm
  else rm -f $DG_AUTO $DG_AUTO.tmp; fi
  return 0
}
# --- 니로 시험판 4(설계 변경 11-22, dongle.md 4-24): 동글을 쓰는 동안 순정 Wi-Fi 저장값을 꺼 두어 bcmdhd가 올라오지 않게 ---
# 순정 Wi-Fi HAL이 Wi-Fi를 켤 때(wifi_on=1) bcmdhd를 올린다(강한 추정). 동글 사용 표시가 있고 막힘이 없는 동안(dg_wifi_want)
# wifi_on·wifi_scan_always_enabled·wifi_ap_on을 0으로 둔다. svc wifi disable은 쓰지 않는다: 지금 부팅의 무선 카플레이를 끊고,
# 이 부팅의 내장 길(take_wlan0)이 다시 켜며, 같은 부팅에 bcmdhd를 내렸다 올리게 된다(5차 원칙). 저장값만 바꿔 다음 부팅부터 듣게 한다.
# - 원래 값은 처음 바꿀 때 한 번만 숫자로 남긴다(wifi_on → $DG_WIFI_ORIG, 스캔 → $DG_SCAN_ORIG, wifi_ap_on은 기존 $APON_ORIG 하나만).
# - 되돌리기(동글 끄기·자동으로 되돌리기 뒤 꺼짐·막힘·삭제): 지금 값이 아직 우리가 둔 0일 때만 원래 값으로, 다시 읽어 맞으면 기록을 지운다.
#   다른 값이면(차주·순정이 바꿈) 그대로 두고 기록만 지운다. 못 되돌리면 기록을 남겨 다음에 다시 한다. wifi_ap_on은 기존 규칙(삭제 때 apon_restore).
# - 부르는 곳: 토글 바꿈, 막힘, 서비스 시작(dg_start), 우리 svc wifi enable 뒤, 상태 화면 재부팅 직전, 삭제(preun).
# - settings가 없으면 아무것도 하지 않는다(로그 한 줄). 값은 숫자만 로그에 쓴다. settings 한 번에 몇 초 걸린다.
DG_WIFI_ORIG=${DG_WIFI_ORIG:-$BK/dongle.wifi_on.orig}
DG_SCAN_ORIG=${DG_SCAN_ORIG:-$BK/dongle.wifi_scan.orig}
# 리뷰 높음 1: wifi_ap_on도 동글 때 기록을 따로 두고 동글을 그만 쓰면 되돌린다(순정 AP를 쓰는 차가 끄기·막힘으로 돌아올 수 있게).
# 우리 핫스팟 때의 기록($APON_ORIG, apon_off)과는 따로다
DG_APON_ORIG=${DG_APON_ORIG:-$BK/dongle.wifi_ap.orig}
dg_sget() { _dsg=$(settings get global $1 2>/dev/null); case "$_dsg" in ''|*[!0-9]*) ;; *) echo "$_dsg" ;; esac; }
dg_wifi_want() { [ -f $DG_ON ] && [ ! -f $DG_BLOCK ]; }
# $1 키, $2 기록 파일: 0으로(원래 값 기록 한 번). 이미 0이거나 읽지 못하면 그대로
dg_wifi_zero() {
  _dwv=$(dg_sget $1)
  # 베타 3(B3-1): 이번에 0이 아니었거나 못 읽었으면 "시작 때 이미 0"이 아님(바로 올리기 조건)
  [ "$_dwv" = 0 ] || DG_WZ_OK=0
  case "$_dwv" in ''|0) return 0 ;; esac
  # 리뷰 중간 2: 기록을 디스크에 남긴 뒤에 바꾼다(그 사이 전원이 꺼져도 되돌릴 근거가 남게)
  [ -f $2 ] || { echo "$_dwv" 2>/dev/null > $2.tmp && $BB mv -f $2.tmp $2 2>/dev/null; $BB sync; }
  [ -s $2 ] || { rm -f $2.tmp; log "동글 Wi-Fi 저장값: $1 원래 값을 기록하지 못해 바꾸지 않음"; return 1; }
  settings put global $1 0 >/dev/null 2>&1
  if [ "$(dg_sget $1)" = 0 ]; then log "동글 Wi-Fi 저장값: $1 $_dwv → 0(다음 부팅부터 순정이 Wi-Fi를 켜지 않음, 동글을 끄면 되돌림)"
  else log "동글 Wi-Fi 저장값: $1을 0으로 바꾸지 못함(지금 값 $(dg_sget $1))"; return 1; fi
  return 0
}
# $1 키, $2 기록 파일: 되돌리기
dg_wifi_back() {
  [ -f $2 ] || return 0
  _dwo=; read _dwo < $2 2>/dev/null
  case "$_dwo" in ''|*[!0-9]*) rm -f $2; return 0 ;; esac
  _dwv=$(dg_sget $1)
  # 리뷰 중간 1: 지금 값을 읽지 못하면 기록을 지우지 않는다(다음에 다시)
  [ -n "$_dwv" ] || { log "동글 Wi-Fi 저장값: $1을 읽지 못해 되돌리기를 미룸"; return 1; }
  if [ "$_dwv" != 0 ]; then rm -f $2; log "동글 Wi-Fi 저장값: $1이 이미 ${_dwv:-읽지 못함}(우리가 둔 0이 아님) — 그대로 두고 기록만 지움"; return 0; fi
  settings put global $1 $_dwo >/dev/null 2>&1
  if [ "$(dg_sget $1)" = "$_dwo" ]; then rm -f $2; log "동글 Wi-Fi 저장값: $1 0 → $_dwo(되돌림)"; return 0; fi
  log "동글 Wi-Fi 저장값: $1을 되돌리지 못함(기록을 남겨 다음에 다시)"; return 1
}
# 바라는 상태로 맞춘다. $1=restore면 동글 사용과 상관없이 되돌린다(삭제). 실패가 있으면 1
dg_wifi_sync() {
  command -v settings >/dev/null 2>&1 || { [ -z "$DG_WIFI_TOLD" ] && log "동글 Wi-Fi 저장값 맞추기 건너뜀: settings 명령 없음"; DG_WIFI_TOLD=1; return 0; }
  _dwr=0
  if [ "$1" != restore ] && dg_wifi_want; then
    DG_WZ_OK=1
    dg_wifi_zero wifi_on $DG_WIFI_ORIG || _dwr=1
    [ "$(dg_sget wifi_scan_always_enabled)" = 1 ] && { dg_wifi_zero wifi_scan_always_enabled $DG_SCAN_ORIG || _dwr=1; }
    # 순정 AP 저장값(1이면 부팅 40~46초에 순정이 AP를 켜며 bcmdhd를 올림). wireless.projection이 있는 차는 건드리지 않는다
    if [ ! -d $WPDIR ]; then dg_wifi_zero wifi_ap_on $DG_APON_ORIG || _dwr=1
    else [ "$(dg_sget wifi_ap_on)" = 0 ] || DG_WZ_OK=0; fi
  else
    dg_wifi_back wifi_on $DG_WIFI_ORIG || _dwr=1
    dg_wifi_back wifi_scan_always_enabled $DG_SCAN_ORIG || _dwr=1
    dg_wifi_back wifi_ap_on $DG_APON_ORIG || _dwr=1
  fi
  return $_dwr
}
# 상태 파일의 토글 줄 둘(dongle_set·dongle_why). 앱은 dongle_set이 있을 때만 토글을 연다
dg_toggle_kv() {
  _dgset=auto; _dgwy=
  if [ -f $DG_USER ]; then
    read _dgset _dgx < $DG_USER 2>/dev/null; case "$_dgset" in on|off) ;; *) _dgset=auto ;; esac
  fi
  if [ $_dgset = auto ]; then
    if [ -f $DG_AUTO ]; then
      read _dga1 _dgaw _dga3 < $DG_AUTO 2>/dev/null
      case "$_dgaw" in nopart) _dgwy=nochip ;; nochip|nowlan) _dgwy=builtin_bad ;; *) _dgwy=builtin_bad ;; esac
    elif [ -n "$(dg_evidence)" ]; then _dgwy=nodongle
    else _dgwy=builtin_ok; fi
  fi
  echo "dongle_set=$_dgset"; echo "dongle_why=$_dgwy"
}
# --- 1.8.0 베타 2: 동글 이름은 늘 wlan0 (오케스트레이터 결정 11-19, 순정 무선 AA·카플레이가 wlan0 이름에 묶임: pkg.md "동글 인터페이스 이름") ---
# 동글을 쓰는 부팅에만, insmod 바로 전에 순정 Wi-Fi 드라이버(bcmdhd 모듈)가 wlan0을 잡고 있으면 그 부팅 동안만 내린다(rmmod).
# wifi_on 같은 순정 설정은 바꾸지 않는다(재부팅·토글 끄기로 저절로 원래대로). 내리지 못하면(모듈이 아닌 내장 드라이버, 쓰는 중, 멈춤)
# 동글을 올리지 않고 내장 경로를 그대로 둔다(builtinbusy). 시도 기록(dongle.try)을 쓴 뒤에 하므로 rmmod가 커널 안에서 멈춰
# 재부팅되면 다음 부팅에 막힘(hang) → 내장 경로로 돌아감(재부팅이 되풀이되지 않음).
DG_IFNAME=wlan0
DG_BUILTIN_MOD=bcmdhd
DG_BUSY_MSG="내장 Wi-Fi를 비우지 못해 이번 부팅은 동글을 쓰지 않습니다. 기존 무선 프로젝션은 그대로입니다."
# 베타 2(동글 5차 결과, 11-20 메인): 실행 중에 bcmdhd를 내렸다가 다시 올리면 모듈은 올라와도 12~15분 동안 내장 무선이 돌아오지 않고
# 재부팅으로만 돌아왔다(니로). 그래서 이 부팅에 순정 드라이버를 내렸으면(내렸을 수 있음 포함) 같은 부팅에는 내장 Wi-Fi로 되돌리지 않는다
# (svc wifi enable·칩 깨우기 안 함). 동글 길이 실패하면 상태 화면에 재부팅 안내만 보이고, 다음 부팅은 막힘·시도 기록으로 동글을 쓰지 않는다.
# 표시는 업데이트에도 남게 $BK에 이번 부팅 id로 둔다(같은 부팅에 업데이트해도 새 서비스가 내장을 다시 올리지 않게)
DG_RMF=${DG_RMF:-$BK/dongle.rmbuiltin}
DG_REBOOT_MSG="동글을 쓰지 못했습니다. 재부팅하면 내장 Wi-Fi로 돌아갑니다."
DG_INUSE_NOTE="동글을 빼기 전에 상태 화면에서 동글 사용을 끄고 재부팅하세요."
dg_rm_now() {
  _dgrb=$BID; [ -n "$_dgrb" ] || { read _dgrb < ${BOOT_ID:-/proc/sys/kernel/random/boot_id}; } 2>/dev/null
  _dgrv=; [ -f $DG_RMF ] && { read _dgrv _dgrx < $DG_RMF; } 2>/dev/null
  [ -n "$_dgrb" ] && [ "$_dgrv" = "$_dgrb" ]
}
# 서비스 시작 때 한 번. 무엇이 실패해도 0을 돌려준다(서비스는 계속 감)
# --- 니로 시험판 4(2026-11-22, 세 번째 시험판 재부팅 반영: pkg.md "니로 세 번째 시험판 리포트 판정", dongle.md 4-23) ---
# 세 번째 시험판은 부팅 60초에 bcmdhd 내림과 insmod가 같은 초였고, 차주가 그 몇 초 뒤 동글을 다시 꽂자 재부팅됐다(커널 흔적 없음).
# 8차(2h, 성공)처럼 바꾼다:
# - 기다림(dg_settle): 부팅 DG_BOOTWAIT초 뒤, 순정 Wi-Fi가 조용함(wpa_supplicant·hostapd 없음)이 DG_QUIET초 이어질 때 올린다(정식 P1: 예비 길·동글 빼기 기다림은 지움).
#   이 부팅은 내장 Wi-Fi를 깨우지 않으므로(DG-12) 그동안 카플레이 핫스팟도 없다.
# - DG_PRE_INS초 쉰 뒤 insmod, 끝나고 DG_PLUG_DELAY초 뒤에야 "이제 꽂아 주세요".
# - 단계 기록(dg_step_*): 내리기 직전부터 프로브 뒤 DG_STEP_AFTER초까지 1초마다 한 줄과 걸러 낸 dmesg 사본을 $BK에 sync로 남긴다.
#   위험한 일 앞에는 표시 줄(M)을 먼저 sync로 쓴다. 다음 부팅이 끝 줄로 "어디서 멈췄는지" 본다(리포트 "동글 단계 기록").
# - 시도 기록(dongle.try)은 동글이 붙고 우리 AP가 뜬 뒤 DG_OK_SEC초를 버텨야 지운다(늦게 꽂아도 프로브·AP 때 멈추면 막힘).
#   드라이버만 올라가 있고 동글이 한 번도 붙지 않은 채 끝난 부팅(시동 끔)은 막지 않는다(dg_step_noprobe).
# 기본 길(bcmdhd 없음): 서비스가 dg_start를 시작한 때(부팅이 끝난 뒤)부터 이만큼 기다린다(순정 AP 복구 40~46초가 지나게)
DG_BOOTWAIT=${DG_BOOTWAIT:-60}
# 리뷰 낮음 1: 기본 길(저장값을 꺼 둠)에서 동글을 못 쓰면 재부팅만으로는 내장으로 안 돌아온다(다음 부팅도 동글 길)
DG_REBOOT_CLEAN_MSG="동글을 쓰지 못했습니다. 동글 사용을 끄면 다음 시동부터 내비 Wi-Fi로 돌아갑니다."
dg_reboot_msg() { _dgrm2=; [ -f $DG_RMF ] && read _dgrm1 _dgrm2 < $DG_RMF 2>/dev/null; if [ "$_dgrm2" = clean ]; then echo "$DG_REBOOT_CLEAN_MSG"; else echo "$DG_REBOOT_MSG"; fi; }
# 순정 Wi-Fi 드라이버(bcmdhd)가 없고 wlan0도 없음
dg_bcm_absent() { ! $BB grep -q "^$DG_BUILTIN_MOD " ${PROC:-/proc}/modules 2>/dev/null && [ ! -e ${SYSNET:-/sys/class/net}/$DG_IFNAME ]; }
DG_QUIET=${DG_QUIET:-5}
DG_SETTLE_MAX=${DG_SETTLE_MAX:-900}
DG_PRE_INS=${DG_PRE_INS:-3}
DG_PLUG_DELAY=${DG_PLUG_DELAY:-5}
DG_OK_HAPD=${DG_OK_HAPD:-1}
DG_STEPREC=${DG_STEPREC:-1}
DG_STEP_AFTER=${DG_STEP_AFTER:-120}
DG_STEP_MAXS=${DG_STEP_MAXS:-900}
DG_STEPF=${DG_STEPF:-$BK/dongle.steps}
DG_KMSGF=${DG_KMSGF:-$BK/dongle.kmsg}
DG_STEPV=${DG_STEPV:-$BK/dongle.stepv}
DG_SKIPF=${DG_SKIPF:-$BK/dongle.skipboot}
DG_LOADING_MSG="동글 드라이버를 올리는 중입니다. 동글은 아직 꽂지 마세요."
DG_SKIP_MSG="설치한 부팅에는 동글을 쓰지 않습니다. 재부팅해 주세요."
# 지금 단계 이름(1초 기록이 읽음, sync 안 함). 우리가 정한 낱말만
dg_stage() { echo "$1" 2>/dev/null > $W/dgstage; }
# 표시 줄: "<uptime> M <낱말들>"을 덧붙이고 sync. 단계 기록 중(dgstep.on, 이번 부팅)일 때만, 한 부팅 200줄까지
dg_step() {
  [ "$DG_STEPREC" = 1 ] || return 0
  _dsb=; [ -f $W/dgstep.on ] && read _dsb < $W/dgstep.on 2>/dev/null
  # 재리뷰 중간: 1초 기록이 끝난 뒤에도 시도 기록이 열려 있는 동안은(이 부팅, 아직 버티지 못함) 표시 줄을 남긴다(늦은 AP 시작의 멈춤을 가리려고)
  if [ "$_dsb" != "${BID:-none}" ]; then
    _dst1=; [ -f $DG_TRY ] && read _dst1 _dst2 < $DG_TRY 2>/dev/null
    [ "$_dst1" = "${BID:-none}" ] || return 0
    _dsh1=; _dsh2=; [ -f $DG_STEPF ] && read _dsh1 _dsh2 < $DG_STEPF 2>/dev/null; [ "$_dsh2" = "${BID:-none}" ] || return 0
  fi
  DG_STEPM=$((${DG_STEPM:-0} + 1)); [ $DG_STEPM -le 200 ] || return 0
  _dsx=$_dgu; dg_up_s; echo "$_dgu M $*" 2>/dev/null >> $DG_STEPF; _dgu=$_dsx; $BB sync
}
# 걸러 낸 dmesg(시작 시각 $1 뒤, 드라이버·USB·Wi-Fi·커널 오류 줄만, 끝 80줄). MAC·USB 번호·일련번호·IP는 가리고 SSID·비밀번호 줄은 뺀다
dg_kmsg() {
  dmesg 2>/dev/null | $BB awk -v t0="${1:-0}" '
    { t = ""; if (match($0, /\[ *[0-9]+\.[0-9]+\]/)) { t = substr($0, RSTART + 1, RLENGTH - 2); gsub(/ /, "", t) } }
    t != "" && (t + 0) < (t0 + 0) { next }
    /[Ss][Ss][Ii][Dd]|[Pp][Ss][Kk]|[Pp]assphrase|[Pp]assword|command line|serialno|androidboot|VID[=:\/ ]|[^ ]PID[=:]|[Vv]endor/ { next }
    /88x2bu|RTW|rtw_|kp-protect|kpp|bcmdhd|dhd|wl_|cfg80211|wlan0|usb [0-9]|usbcore|dwc_otg|hub|Oops|BUG|Unable to handle|[Pp]anic|lockup|[Ww]atchdog|PC is at|LR is at|Backtrace|Call trace|Kernel|CPU: [0-9]|Comm:|Internal error|Tainted|\[</ {
      gsub(/[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]/, "xx:xx:xx:xx:xx:xx")
      gsub(/[0-9A-Fa-f][0-9A-Fa-f][:-][0-9A-Fa-f][0-9A-Fa-f][:-][0-9A-Fa-f][0-9A-Fa-f][:-][*][*][:-][*][*][:-][*][*]/, "xx:xx:xx:**:**:**")
      gsub(/id[VP][a-z]*=[0-9A-Fa-f]+/, "id=*")
      gsub(/[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]/, "xxxx:xxxx")
      if ($0 ~ /SerialNumber/) sub(/SerialNumber.*/, "SerialNumber: *")
      gsub(/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/, "x.x.x.x")
      a[n % 80] = $0; n++ }
    END { s = n > 80 ? n - 80 : 0; for (i = s; i < n; i++) print a[i % 80] }' 2>/dev/null
}
# dmesg 마지막 시각(초, 없으면 0)
dg_kmsg_t() { dmesg 2>/dev/null | $BB awk '{ if (match($0, /\[ *[0-9]+\.[0-9]+\]/)) { t = substr($0, RSTART + 1, RLENGTH - 2); gsub(/ /, "", t) } } END { print int(t + 0) }' 2>/dev/null; }
# 1초 기록 한 줄의 값들(0/1): m 순정 bcmdhd 모듈, d 우리 88x2bu 모듈, w wlan0 있음, u 허용 동글이 USB에 있음, s 동글이 우리 드라이버에 붙음,
#   h hostapd(아무것이나), p wpa_supplicant, f fix_perms 도는 중
dg_step_flags() {
  _dsm=0; $BB grep -q "^$DG_BUILTIN_MOD " ${PROC:-/proc}/modules 2>/dev/null && _dsm=1
  _dsd=0; dg_present && _dsd=1
  _dsw=0; [ -e ${SYSNET:-/sys/class/net}/$DG_IFNAME ] && _dsw=1
  _dsx=$_dgu; dg_usb; _dsu=0; [ $DG_USB = ok ] && _dsu=1; _dgu=$_dsx
  _dss=0; dg_seen && _dss=1
  _dsh=0; running hostapd && _dsh=1
  _dsp=0; running wpa_supplicant && _dsp=1
  _dsf=0; fix_running && _dsf=1
}
# 1초 기록(뒤에서 하나). 끝: 동글이 붙은 뒤 DG_STEP_AFTER초, 동글 사용 꺼짐, 부팅 바뀜, 86400번. 끝나면 "M end <이유>"
# 리뷰 높음 1: 동글이 붙기 전에는 끝내지 않는다(늦게 꽂아 프로브 때 멈춰도 기록이 남게). DG_STEP_MAXS번이 지나도 안 붙었으면
#   값(m d w u s h p f·단계)이 바뀐 때만 줄·dmesg 사본을 쓰고 sync한다(매초 sync를 줄임)
dg_step_rec() {
  _dri=0; _drs=; _dre=max; _drt0=$1; _drlast=
  while [ $_dri -lt 86400 ]; do
    [ -f $DG_ON ] || { _dre=off; break; }
    _dro=; read _dro < ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null; [ "$_dro" = "${BID:-none}" ] || { _dre=boot; break; }
    dg_step_flags; dg_up_s
    _drg=-; [ -f $W/dgstage ] && read _drg < $W/dgstage 2>/dev/null
    if [ -z "$_drs" ] && [ $_dss = 1 ]; then
      _drs=$_dgu; echo "${BID:-none} $_dgu" 2>/dev/null > $W/dongle.seen1
      _dri0=; [ -f $W/dgins.done ] && read _dri0 < $W/dgins.done 2>/dev/null
      case "$_dri0" in ''|*[!0-9]*) _drgap=? ;; *) _drgap=$((_dgu - _dri0)) ;; esac
      echo "$_dgu M usb-seen gap=$_drgap" 2>/dev/null >> $DG_STEPF
      log "동글 단계: 동글이 우리 드라이버에 붙음(insmod 끝 → 프로브 ${_drgap}초)"
      dg_tl probe $_dgu; dg_tl_kaoa; dg_tl_diag probe
      # 시험판 6: 메인을 깨워 AP를 바로 띄우고(30초 기다리지 않음) 상태 화면 파일을 다시 쓴다
      dg_wake; dg_status_push
    fi
    _drnow="${_drg:--} m$_dsm d$_dsd w$_dsw u$_dsu s$_dss h$_dsh p$_dsp f$_dsf"
    if [ -n "$_drs" ] || [ $_dri -lt $DG_STEP_MAXS ] || [ "$_drnow" != "$_drlast" ]; then
      echo "$_dgu S $_drnow" 2>/dev/null >> $DG_STEPF
      { dg_kmsg "$_drt0" 2>/dev/null > $DG_KMSGF.tmp && $BB mv -f $DG_KMSGF.tmp $DG_KMSGF; } 2>/dev/null
      $BB sync
    fi
    _drlast=$_drnow
    [ -n "$_drs" ] && [ $((_dgu - _drs)) -ge $DG_STEP_AFTER ] && { _dre=done; break; }
    # 리뷰 낮음 3: 붙기 전 DG_STEP_MAXS번이 지나면 3초마다 본다(부하를 줄임)
    if [ -z "$_drs" ] && [ $_dri -ge $DG_STEP_MAXS ]; then sleep 3 & wait $!; else sleep 1 & wait $!; fi
    _dri=$((_dri + 1))
  done
  dg_up_s; echo "$_dgu M end $_dre" 2>/dev/null >> $DG_STEPF; rm -f $W/dgstep.on; $BB sync
}
# 단계 기록 시작(bcmdhd를 내리기 바로 전, 한 부팅에 한 번): 지난 기록을 .prev로 옮기고 머리 줄 "B <boot_id>"를 쓴 뒤 1초 기록을 뒤에서 띄운다
dg_step_begin() {
  [ "$DG_STEPREC" = 1 ] || return 0
  _dsb=; [ -f $W/dgstep.on ] && read _dsb < $W/dgstep.on 2>/dev/null; [ "$_dsb" = "${BID:-none}" ] && return 0
  # 리뷰 낮음 6: 같은 부팅의 기록을 다시 시작하면 .prev(지난 부팅 기록)를 덮지 않는다
  _dsh1=; _dsh2=; [ -f $DG_STEPF ] && read _dsh1 _dsh2 < $DG_STEPF 2>/dev/null
  if [ "$_dsh2" != "${BID:-none}" ]; then
    # 시험판 5(메인 11-23): 세 운행을 리포트에 남기려고 두 대 앞(.prev2)까지 둔다
    # 시험판 6(F9): 네 세대(.prev3까지). 여섯 번째 절차의 제보 부팅(동글 없이 켬)이 한 세대를 쓴다
    [ -f $DG_STEPF.prev2 ] && $BB mv -f $DG_STEPF.prev2 $DG_STEPF.prev3 2>/dev/null
    [ -f $DG_KMSGF.prev2 ] && $BB mv -f $DG_KMSGF.prev2 $DG_KMSGF.prev3 2>/dev/null
    [ -f $DG_STEPF.prev ] && $BB mv -f $DG_STEPF.prev $DG_STEPF.prev2 2>/dev/null
    [ -f $DG_KMSGF.prev ] && $BB mv -f $DG_KMSGF.prev $DG_KMSGF.prev2 2>/dev/null
    [ -f $DG_STEPF ] && $BB mv -f $DG_STEPF $DG_STEPF.prev 2>/dev/null
    [ -f $DG_KMSGF ] && $BB mv -f $DG_KMSGF $DG_KMSGF.prev 2>/dev/null
  fi
  rm -f $W/dongle.seen1 $W/dgins.done
  # 리뷰 낮음 5: 같은 부팅에 다시 시작하면 지우지 않고 표시 한 줄을 덧붙인다
  if [ "$_dsh2" = "${BID:-none}" ]; then dg_up_s; echo "$_dgu M restart" 2>/dev/null >> $DG_STEPF; else echo "B ${BID:-none}" 2>/dev/null > $DG_STEPF; fi
  echo "${BID:-none}" 2>/dev/null > $W/dgstep.on; DG_STEPM=0
  _dst0=$(dg_kmsg_t); case "$_dst0" in ''|*[!0-9]*) _dst0=0 ;; esac; [ $_dst0 -gt 2 ] && _dst0=$((_dst0 - 2))
  $BB sync
  # 리뷰 낮음 3: 출력은 서비스와 같은 ap.log로(붙은 때 한 줄)
  ( dg_step_rec $_dst0 ) </dev/null 2>/dev/null &
  echo "$! ${BID:-none}" 2>/dev/null > $W/dgstep.pid
}
# 서비스 시작 때: 지난 부팅의 단계 기록이 끝 표시 없이 끊겼으면 판정 한 줄($DG_STEPV, 리포트가 읽음). 한 기록에 한 번만
dg_step_endcheck() {
  [ -f $DG_STEPF ] || return 0
  _dsh1=; _dsh2=; read _dsh1 _dsh2 < $DG_STEPF 2>/dev/null
  [ "$_dsh1" = B ] && [ -n "$_dsh2" ] && [ "$_dsh2" != "${BID:-none}" ] || return 0
  _dsv1=; [ -f $DG_STEPV ] && read _dsv1 _dsvx < $DG_STEPV 2>/dev/null; [ "$_dsv1" = "$_dsh2" ] && return 0
  _dsl=$($BB awk '$2 == "M" { m = $0 } { l = $0 } END { print l; print m }' $DG_STEPF 2>/dev/null)
  case "$_dsl" in *" M end "*) _dsvv=end ;; *) _dsvv=cut ;; esac
  _dslast=$(echo "$_dsl" | $BB awk 'NR == 1 { print $1, $2, $3; exit }'); _dslm=$(echo "$_dsl" | $BB awk 'NR == 2 { $1 = $1; print; exit }')
  echo "$_dsh2 $_dsvv last=${_dslast:-?} mark=${_dslm:-?}" 2>/dev/null > $DG_STEPV; $BB sync
  if [ $_dsvv = cut ]; then log "동글 단계 기록: 지난 부팅이 기록 중에 끊김(마지막 줄 uptime ${_dslast%% *}초, 마지막 표시 ${_dslm:-없음})"
  else log "동글 단계 기록: 지난 부팅 기록은 끝 표시까지 남음"; fi
}
# 지난 부팅(boot_id $1)이 위험한 단계 밖에서 끝났는가(평범한 시동 끔): 0이면 막지 않음(시험판 5 리뷰 높음 1).
# 근거는 그 부팅의 단계 기록뿐. 위험한 단계: insmod가 돌아오지 않음, 동글이 처음 보인 뒤·우리 AP를 띄우기 시작한 뒤 DG_OK_SEC초 안.
# 마지막 줄이 세 때(insmod 끝·처음 보임·AP 시작, 마지막 것)보다 모두 DG_OK_SEC초 넘게 뒤일 때만 위험 밖으로 본다(그 사이에 끊기면
# 프로브·AP 때 멈춤과 가를 수 없어 막는 쪽). 1초 기록이 끝난 뒤에도 시도 기록이 열려 있으면 표시 줄(AP 시작 등)은 계속 쓴다(dg_step).
# 시험판 6(F2·F4): 상태 화면 [지금 재부팅] 표시("M end reboot", insmod가 돌아온 뒤)가 기록의 끝 근처(35초 안)이고 그 뒤에 위험한
#   표시(AP 시작·다시 잡힘·붙음)가 없으면 막지 않는다(그 순간 내비가 살아 있었고 재부팅으로 끝남, 리뷰 중간 2).
#   다시 잡힌 동글("M replug")도 처음 보임처럼 DG_OK_SEC초 동안 위험 단계로 센다.
# 알려진 빈틈: 꽂는 순간 1초 표본(붙기 전 900번 뒤에는 3초)보다 빨리 멈추면 "꽂기 전 시동 끔"과 가를 수 없어 다음 시동에 다시 시도한다
dg_step_noprobe() {
  [ -n "$1" ] && [ -f $DG_STEPF ] || return 1
  $BB awk -v b="$1" -v ok="${DG_OK_SEC:-60}" '
    NR == 1 { if ($1 != "B" || $2 != b) exit 1; next }
    $2 == "M" && $3 == "ins-done" && $4 == "rc=0" { ins = $1 + 0; got = 1 }
    $2 == "M" && ($3 == "usb-seen" || $3 == "prompt-late") && !us { us = $1 + 0; hu = 1 }
    $2 == "S" && got && ($7 == "u1" || $8 == "s1") && !hu { us = $1 + 0; hu = 1 }
    $2 == "M" && $3 == "hapd-start" { hs = $1 + 0; hh = 1 }
    $2 == "M" && $3 == "replug" { rp = $1 + 0; hr = 1 }
    $2 == "M" && ($3 == "hapd-start" || $3 == "replug" || $3 == "usb-seen" || $3 == "prompt-late") { rb = 0 }
    $2 == "M" && $3 == "end" && $4 == "reboot" { rb = 1; rbt = $1 + 0 }
    { last = $1 + 0 }
    END {
      if (NR < 2 || !got) exit 1
      if (rb && last - rbt <= 35) exit 0
      if (last - ins <= ok) exit 1
      if (hu && last - us <= ok) exit 1
      if (hh && last - hs <= ok) exit 1
      if (hr && last - rp <= ok) exit 1
      exit 0 }' $DG_STEPF 2>/dev/null
}
# --- 니로 시험판 6(11-23, pkg.md "다섯 번째 시험판 차 결과 분석과 여섯 번째 계획" F1~F9) ---
# 다섯 번째 차 결과: 동글이 같은 부팅에 다시 잡히면(순정 카플레이 resetUSB의 포트 전원 껐다 켜기·바꿔 꽂기) wlan0이 새로 생기는데 우리
# hostapd는 옛 장치를 잡은 채 살아 있어 AP가 죽었다("Failed to set beacon parameters"). 다시 잡히면 몇 초 안에 AP를 다시 띄운다.
# 베타 2(소유자 결정 11-23 "반복 상한은 15회로 올리자"): 한 부팅 15번
DG_REUP_MAX=${DG_REUP_MAX:-15}
DG_REUPMAX_MSG="동글이 자꾸 다시 잡혀 이번에는 핫스팟을 멈췄습니다. 다음 시동 때 다시 시도하며, 동글 사용을 끄면 다음 시동부터 내비 Wi-Fi로 돌아갑니다."
DG_PLUGAGAIN_MSG="동글을 한 번 뺐다가 다시 꽂아 주세요. 그 뒤로는 그대로 두면 됩니다."
DG_IFXF=${DG_IFXF:-$W/hapd.ifx}
# wlan0 번호(ifindex, 장치가 새로 생기면 바뀜). 못 읽으면 빈 값
dg_ifx() { _dgix=; [ -r $WLAN/ifindex ] && read _dgix < $WLAN/ifindex 2>/dev/null; case "$_dgix" in ''|*[!0-9]*) _dgix= ;; esac; return 0; }
# 우리 hostapd를 띄운 wlan0 번호("<boot_id> <ifindex>")
dg_ifx_save() { dg_ifx; [ -n "$_dgix" ] && echo "${BID:-none} $_dgix" 2>/dev/null > $DG_IFXF; return 0; }
# up()이 부른다(동글 길·wlan0 있음): hostapd가 떠 있는데 wlan0 번호가 띄운 때와 다르면 우리 AP를 내리고(up이 이어서 다시 띄움) 센다.
# 한 부팅 DG_REUP_MAX번을 넘으면 이 부팅은 동글 AP를 그만 띄운다(reupmax, 빨강 문구, 다음 시동에 다시 시도)
dg_reup_check() {
  running "hostapd $CONF" || return 0
  dg_ifx; [ -n "$_dgix" ] || return 0
  _dgr1=; _dgr2=; [ -f $DG_IFXF ] && read _dgr1 _dgr2 < $DG_IFXF 2>/dev/null
  # 이번 부팅 기록이 없으면(서비스가 같은 부팅에 다시 시작 등) 지금 것을 맞는 것으로 둔다
  [ "$_dgr1" = "${BID:-none}" ] || { dg_ifx_save; return 0; }
  [ "$_dgr2" = "$_dgix" ] && return 0
  _dgrn=0; _dgrb=; [ -f $W/dgreup ] && read _dgrb _dgrn < $W/dgreup 2>/dev/null
  [ "$_dgrb" = "${BID:-none}" ] || _dgrn=0
  case "$_dgrn" in ''|*[!0-9]*) _dgrn=0 ;; esac
  if [ $_dgrn -ge $DG_REUP_MAX ]; then
    stop_ours; DG_ST=reupmax; dg_state reupmax "$DG_G"; dg_step reupmax; dg_bst reupmax; rm -f $DG_TRY; $BB sync
    log "동글: 이번 부팅에 동글이 ${DG_REUP_MAX}번 넘게 다시 잡혀 우리 AP를 그만 띄움 — 다음 시동에 다시 시도"
    return 0
  fi
  _dgrn=$((_dgrn + 1)); echo "${BID:-none} $_dgrn" 2>/dev/null > $W/dgreup
  log "동글: 동글이 다시 잡혀 wlan0이 새로 생김 — 우리 AP를 다시 띄움(이번 부팅 ${_dgrn}/${DG_REUP_MAX}번)"
  # 리뷰 중간 1: 뽑기 감시가 다시 잡힘을 놓쳤어도 AP를 다시 띄우는 동안은 시도 기록을 열어 둔다
  dg_try_reopen ap
  # 배포판: 다른 동글로 바꿔 꽂았을 수 있으므로 동글 판정을 다시 한다
  DG_OUIDONE=; DG_OUIWAIT=0; DG_USBDEV=; rm -f $DG_OUIF $W/dongle.ident; dg_usb
  stop_ours
  _dgrw=0; while running "hostapd $CONF" && [ $_dgrw -lt 5 ]; do sleep 1; _dgrw=$((_dgrw + 1)); done
  return 0
}
# 메인 반복의 30초 쉬기를 깨운다(다시 잡힌·처음 붙은 동글의 AP를 30초 기다리지 않게). 쉬기 sleep의 pid는 메인이 $W/tick.slp에 남긴다.
# pid가 그사이 다른 프로세스가 됐으면(명령줄에 sleep이 없음) 건드리지 않는다. 메인이 점검 중이면(쉬지 않음) 표시 파일($W/dgwake)을
# 남겨 다음 쉬기를 건너뛰게 한다(리뷰 낮음: 점검 중에 온 깨우기를 잃지 않게)
dg_wake() {
  : 2>/dev/null > $W/dgwake
  _dgk1=; _dgk2=; [ -f $W/tick.slp ] && read _dgk1 _dgk2 < $W/tick.slp 2>/dev/null
  # 베타 3(B3-2): 감시자(status.sh, BID가 빔)도 깨울 수 있게 부팅 id는 dg_kv_bid로 읽는다
  [ -n "$_dgk1" ] && [ "$_dgk2" = "$(dg_kv_bid)" ] || return 0
  case "$_dgk1" in *[!0-9]*) return 0 ;; esac
  if [ -r ${PROC:-/proc}/$_dgk1/cmdline ]; then $BB grep -q sleep ${PROC:-/proc}/$_dgk1/cmdline 2>/dev/null || return 0; fi
  kill $_dgk1 2>/dev/null
  return 0
}
# 시도 기록을 이번 부팅으로 다시 열고(F4: 다시 잡힌 프로브·AP 다시 띄우기 때 멈추면 다음 부팅이 hang으로 가름) 표시 줄 "replug"와
# 그 시각($W/dgreplug)을 남긴다(sync). 다시 연 기록은 dg_reup_close가 위험한 때가 지나면 닫는다
# 이번 AP 시작이 위험한가: 처음 길(up), 또는 이 부팅에 동글이 다시 잡힌(dgreplug) 뒤 AP가 아직 뜨지 않음(hapd.up이 없거나 더 이름)
dg_ap_risky() {
  [ "$DG_ST" = up ] && return 0
  _dgk3=; _dgk4=; [ -f $W/dgreplug ] && read _dgk3 _dgk4 < $W/dgreplug 2>/dev/null
  [ "$_dgk3" = "${BID:-none}" ] || return 1
  case "$_dgk4" in ''|*[!0-9]*) return 1 ;; esac
  _dgk5=; _dgk6=; [ -f $W/hapd.up ] && read _dgk5 _dgk6 < $W/hapd.up 2>/dev/null
  [ "$_dgk6" = "${BID:-none}" ] || return 0
  case "$_dgk5" in ''|*[!0-9]*) return 0 ;; esac
  [ $_dgk5 -lt $_dgk4 ]
}
# 시도 기록이 이번 부팅 것이 아니면 다시 연다(sync). 위험한 AP 시작(dg_ap_risky) 전에도 부른다
dg_try_open() {
  dg_up_s
  _dgm1=; [ -f $DG_TRY ] && read _dgm1 _dgmx < $DG_TRY 2>/dev/null
  if [ "$_dgm1" != "${BID:-none}" ]; then echo "${BID:-none} ${DG_G:--} $_dgu" 2>/dev/null > $DG_TRY.tmp && $BB mv -f $DG_TRY.tmp $DG_TRY 2>/dev/null; $BB sync; fi
  return 0
}
dg_try_reopen() {
  dg_try_open
  echo "${BID:-none} $_dgu" 2>/dev/null > $W/dgreplug
  dg_step "replug $1"
  $BB sync
  return 0
}
# 뽑기 감시가 동글이 (다시) 붙은 것을 본 때(F3): 동글 길(up·ok)이면 시도 기록을 다시 열고, 다시 꽂기 문구를 지우고, 메인을 깨워
# AP를 바로 다시 띄우게 한다(wlan0이 아직 없으면 감시가 wlan0이 생길 때 한 번 더 깨움)
dg_replug_mark() {
  _dgm2=; [ -f $W/dongle.state ] && read _dgm2 _dgm3 < $W/dongle.state 2>/dev/null
  case "$_dgm2" in up|ok) dg_try_reopen usb ;; esac
  rm -f $W/dg.plugagain
  dg_wake
  dg_status_push
  return 0
}
# 30초 점검(동글 길, wait 말고 어느 상태든): 다시 연 시도 기록은 다시 잡힘·AP 시작 가운데 늦은 때부터 DG_OK_SEC초가 지나면 닫는다.
# 둘 다 이번 부팅 기록이 없으면(아직 안 붙음) 그대로 둔다(꽂기 기다림·insmod 판정은 dg_watch·dg_plug_tick 몫)
# (그동안 내비가 살아 있었다는 뜻). 다시 잡힌 뒤 또 뽑히거나 wlan0이 안 생겨도 닫힌다(리뷰 높음 1: 몇 시간 뒤 시동 끔이 hang이 되지 않게)
dg_reup_close() {
  [ "$DG_RUN" = 1 ] || return 0
  # 재리뷰 낮음: 막힘(blocked)은 dg_block이 일부러 남긴 기록일 수 있어 건드리지 않는다
  case "$DG_ST" in wait|blocked|'') return 0 ;; esac
  _dgo1=; [ -f $DG_TRY ] && read _dgo1 _dgox < $DG_TRY 2>/dev/null; [ "$_dgo1" = "${BID:-none}" ] || return 0
  _dgo2=; _dgo3=; [ -f $W/dgreplug ] && read _dgo2 _dgo3 < $W/dgreplug 2>/dev/null
  { [ "$_dgo2" = "${BID:-none}" ] && case "$_dgo3" in ''|*[!0-9]*) false ;; *) true ;; esac; } || _dgo3=
  _dgo4=; _dgo5=; [ -f $W/hapd.st ] && read _dgo4 _dgo5 < $W/hapd.st 2>/dev/null
  if [ "$_dgo5" = "${BID:-none}" ]; then case "$_dgo4" in ''|*[!0-9]*) ;; *) { [ -z "$_dgo3" ] || [ $_dgo4 -gt $_dgo3 ]; } && _dgo3=$_dgo4 ;; esac; fi
  [ -n "$_dgo3" ] || return 0
  dg_up_s; [ $((_dgu - _dgo3)) -ge ${DG_OK_SEC:-60} ] || return 0
  # up(아직 ok가 아님)은 이 부팅에 동글이 한 번은 붙었을 때만 닫는다(다시 잡힌 뒤 또 뽑혀 up에 머무는 길, 리뷰 높음 1)
  if [ "$DG_ST" = up ]; then _dgo6=; [ -f $W/dongle.seen1 ] && read _dgo6 _dgo7 < $W/dongle.seen1 2>/dev/null; [ "$_dgo6" = "${BID:-none}" ] || return 0; fi
  rm -f $DG_TRY $BK/dongle.noprobe; $BB sync; log "동글: 다시 잡힘·AP 다시 띄움 뒤 위험한 때가 지나 시도 기록을 닫음"
  return 0
}
# 상태 화면 [지금 재부팅](status.sh 감시자)이 재부팅 바로 전에 부른다: 이번 부팅 단계 기록에 "M end reboot"(F2)
dg_step_rbmark() {
  [ -f $DG_STEPF ] || return 0
  _dsk1=; _dsk2=; read _dsk1 _dsk2 < $DG_STEPF 2>/dev/null
  [ "$_dsk1" = B ] && [ "$_dsk2" = "$(dg_kv_bid)" ] || return 0
  dg_up_s; echo "$_dgu M end reboot" 2>/dev/null >> $DG_STEPF; $BB sync
  return 0
}
# F8: 상태 화면 파일($STATUS)을 다시 쓴다. 동글 차(동글 사용 표시·이 부팅 동글 길)이고, 상태 화면을 이번 부팅에 연 뒤(Launch 감시자가
# 살아 있는 10분 동안, 리뷰 낮음: 지난 부팅의 상태 파일만 보고 매번 돌지 않게)만. 바라는 때($W/stpush.want)만 남기고, 잠금 폴더
# ($W/stpush.lock, 리뷰 중간 4: 둘이 함께 띄우지 않게)를 잡은 하나가 DG_PUSH_GAP초(3초)에 한 번까지 status.sh --push를 돌린다(20번까지)
DG_PUSH_GAP=${DG_PUSH_GAP:-3}
DG_PUSHLK=${DG_PUSHLK:-$W/stpush.lock}
# 베타 3(B3-4, 소유자 "동글을 쓰지 않은 차도 그냥 뭐든 상태 화면이 바뀌어야 알 수 있지"): 모든 차에서 돈다(예전에는 동글 차만).
# 동글 차가 아니면 감시자가 살아 있을 때만(상태 화면을 연 뒤 10분). 부르는 곳: 동글 상태, 카플레이 연결 수, AA·아이폰 안내(hint_write),
# 설치 진행 state, 그리고 감시자가 살아 있는 동안 30초 점검마다 한 번(판정은 status.sh가 계산하므로 서비스는 바뀐 것을 모름)
# 리뷰 낮음 6: 서비스 시작 중(dg_start 전, 지난 부팅 동글 상태가 남아 있을 때)에는 부르지 않는다
st_push() { [ "$ST_NOPUSH" = 1 ] && return 0; dg_status_push; }
dg_status_push() {
  [ -f ${STATUS:-/data/local/tmp/korea-projection-status.txt} ] || return 0
  # 재리뷰 낮음: 감시자가 끝났어도(Launch 뒤 10분) 동글을 기다리는 단계(꽂기 안내 전후)면 다시 쓴다(동글 차만)
  if ! st_alive $W/watch.pid --watch; then
    [ -f $DG_ON ] || dg_rm_now || return 0
    _dgq3=; [ -f $W/dongle.state ] && read _dgq3 _dgq4 < $W/dongle.state 2>/dev/null
    case "$_dgq3" in settle|bootwait|wait|up) ;; *) return 0 ;; esac
  fi
  # 바람 표시는 바뀌기만 하면 된다(소수점 uptime과 난수: 같은 초에 두 번 바라도 다른 값)
  _dgqu=; { read _dgqu _dgqx < ${UPTIME:-/proc/uptime}; } 2>/dev/null; echo "${_dgqu:-0} ${RANDOM:-0}" 2>/dev/null > $W/stpush.want
  dg_push_lock || return 0
  ( dg_push_loop ) </dev/null >/dev/null 2>&1 &
  return 0
}
# 잠금을 잡으면 0(안에 "<잡은 uptime> <boot_id>"). 잠금이 지난 부팅 것이거나 DG_PUSH_STALE초(300)보다 오래됐으면(정전·죽은 반복이 남김)
# 지우고 한 번 다시 잡는다. 한 반복은 20번 × (3초 + status.sh)라 300초 안에 끝난다
DG_PUSH_STALE=${DG_PUSH_STALE:-300}
dg_push_lockmark() { dg_up_s; echo "$_dgu $(dg_kv_bid)" 2>/dev/null > $DG_PUSHLK/at; }
dg_push_lock() {
  if mkdir $DG_PUSHLK 2>/dev/null; then dg_push_lockmark; return 0; fi
  _dgl1=; _dgl2=; [ -f $DG_PUSHLK/at ] && read _dgl1 _dgl2 < $DG_PUSHLK/at 2>/dev/null
  dg_up_s
  # 재리뷰 낮음: 표시가 없거나 깨진 잠금(잡자마자 죽음)은 낡은 것으로 본다(둘이 돌아도 임시 파일이 따로라 상하지 않음)
  case "$_dgl1" in ''|*[!0-9]*) _dgl1=-999999 ;; esac
  if [ "$_dgl2" = "$(dg_kv_bid)" ] && [ $((_dgu - _dgl1)) -lt $DG_PUSH_STALE ]; then return 1; fi
  rm -f $DG_PUSHLK/at; rmdir $DG_PUSHLK 2>/dev/null
  mkdir $DG_PUSHLK 2>/dev/null && { dg_push_lockmark; return 0; }
  return 1
}
# 바람이 바뀌는 동안 돈다. 끝낼 때는 잠금을 푼 뒤 바람을 한 번 더 보고, 그사이 바뀌었으면 잠금을 다시 잡아 이어 간다(놓치지 않게)
dg_push_loop() {
  _dgpl=0; _dgpd=
  while [ $_dgpl -lt 20 ]; do
    _dgpw=; read _dgpw < $W/stpush.want 2>/dev/null
    if [ "$_dgpw" = "$_dgpd" ]; then
      rm -f $DG_PUSHLK/at; rmdir $DG_PUSHLK 2>/dev/null
      _dgpw=; read _dgpw < $W/stpush.want 2>/dev/null
      [ "$_dgpw" != "$_dgpd" ] && mkdir $DG_PUSHLK 2>/dev/null || return 0
      dg_push_lockmark
    fi
    _dgpd=$_dgpw
    BB=$BB sh $APP/bin/status.sh --push </dev/null >/dev/null 2>&1
    sleep $DG_PUSH_GAP & wait $!
    _dgpl=$((_dgpl + 1))
  done
  rm -f $DG_PUSHLK/at; rmdir $DG_PUSHLK 2>/dev/null
  return 0
}
# F6(dongle.md 4-26): 꽂아 둔 채 시동. 가드를 서비스 시작(+4초)에 걸고, 가드보다 먼저 생긴 동글 노드는 지우고 같은 자리에 빈 폴더를 만든다
# (순정이 새로 열지 못함, 이미 연 것은 못 막음). "빼 달라"는 하지 않고 꽂힌 채 드라이버를 올린다(정식 P1: 예전 "빼 달라" 길은 지움).
# 포트 전원 껐다 켜기는 쓰지 않고 기록만 한다(MICOM 길은 쓰지 않음).
DG_GEARLY_MAX=${DG_GEARLY_MAX:-20}
DG_EARLYF=${DG_EARLYF:-$W/dg.early}
dg_guard_early() {
  dg_guard_on || return 0
  # 설치한 부팅(동글 길을 타지 않음)에는 걸지 않는다
  _dge1=; [ -f $DG_SKIPF ] && read _dge1 _dgex < $DG_SKIPF 2>/dev/null
  [ -n "$_dge1" ] && [ "$_dge1" = "${BID:-none}" ] && return 0
  # 리뷰 중간 3: 이번 부팅에 이미 결과가 난 부팅(서비스 다시 시작)은 걸지 않는다(그 결과대로 둠)
  _dge2=; [ -f $BK/dongle.bst ] && read _dge2 _dgey < $BK/dongle.bst 2>/dev/null
  [ "$_dge2" = "${BID:-none}" ] && return 0
  _dgew=0
  while :; do
    dg_usb
    # 베타 2(R6, 여섯 번째 차 결과): 동글이 아직 안 보여도 버스가 있으면 건다. 커널은 동글을 +12초쯤 잡으므로(+4초에는 아직 없음),
    # 미리 막아 두면 동글이 처음부터 막힌 자리로 들어가 순정이 열지 못한다. 대가(메인 받아들임): 동글 사용을 켠 차는 dg_start가 정할
    # 때까지 같은 버스의 유선 장치 노드가 생기지 않는다(동글 차는 그 포트를 동글이 씀, 내비 Wi-Fi로 가는 부팅은 dg_start가 풂)
    if dg_guard_paths && [ -d $DG_USBFS/$DG_GBUS ]; then dg_up_s; dg_tl bus $_dgu; dg_tl gwait $_dgew; break; fi
    # B3-9 기록 1: 왜 아직 못 걸었는지(hub: 루트 허브·동글·기록 모두 없음, dir: 버스 폴더 없음)
    if [ -n "$DG_GBUS" ]; then DG_GWHY=dir; else DG_GWHY=hub; fi
    [ $_dgew -lt $DG_GEARLY_MAX ] || { dg_tl gwhy ${DG_GWHY:-hub}; log "AOA 가드(이른): ${DG_GEARLY_MAX}초 안에 USB 버스를 찾지 못함 — 서비스 시작 뒤에 검"; return 0; }
    sleep 1 & wait $!; _dgew=$((_dgew + 1))
  done
  dg_guard_arm
  dg_up_s; dg_tl guard $_dgu; [ -n "$DG_GWHY" ] && dg_tl gwhy $DG_GWHY
  # B3-9 기록 4: 가드 직후 순정 AOA 줄 수
  _dgag=$(dg_aoa_count); case "$_dgag" in ''|*[!0-9]*) ;; *) dg_tl aoag $_dgag ;; esac
  # B3-9a: 기록된 같은 포트의 짝(OHCI, 12Mbps) 버스도 막는다(기록과 컨트롤러 경로가 같을 때만, 모뎀 버스는 빼고)
  dg_gbus_pair_arm
  dg_guard_swap early
  return 0
}
# 동글 노드 자리(DG_GNODE)를 본다: 빈 폴더면 blocked, 노드면 지우고 빈 폴더로(swapped), 못 바꾸면 keep, 동글이 없으면 none.
# 결과 $DG_EARLYF "<boot_id> <결과> <uptime>"(swapped가 한 번 나오면 그 부팅 동안 그대로)
dg_guard_swap() {
  _dgw0=none
  if [ -n "$DG_GNODE" ]; then
    if [ -d "$DG_GNODE" ] && [ ! -L "$DG_GNODE" ]; then _dgw0=blocked
    elif [ -e "$DG_GNODE" ] && [ ! -L "$DG_GNODE" ] && rm -f "$DG_GNODE" 2>/dev/null && mkdir "$DG_GNODE" 2>/dev/null; then
      echo "$DG_GNODE" 2>/dev/null >> $DG_AOAF; _dgw0=swapped
    else _dgw0=keep; fi
  fi
  dg_up_s
  _dgwq=; _dgwp=; [ -f $DG_EARLYF ] && read _dgwq _dgwp _dgwr < $DG_EARLYF 2>/dev/null
  [ "$_dgwq" = "${BID:-none}" ] && [ "$_dgwp" = swapped ] || echo "${BID:-none} $_dgw0 $_dgu" 2>/dev/null > $DG_EARLYF
  case "$_dgw0" in
    swapped)
      _dgvb=없음; [ -e ${DG_VBUSF:-/sys/devices/dwc_otg/vbus} ] && _dgvb=있음
      log "AOA 가드($1): 가드보다 먼저 생긴 동글 노드를 빈 폴더로 바꿈(uptime ${_dgu}초). 포트 전원 껐다 켜기는 쓰지 않음(기록만, vbus 파일 $_dgvb)" ;;
    keep) log "AOA 가드($1): 동글 노드를 빈 폴더로 바꾸지 못함(순정 AOA가 닿을 수 있음)" ;;
  esac
  return 0
}
# 물러설 길(F6): 가드보다 먼저 생긴 동글(swapped·keep)에 순정 AOA가 닿았고(서비스 시작 때 logcat, $W/dg.eaoa) 동글 AP가 뜨지 않으면
# (동글 wlan0에서 hostapd가 꺼짐, 또는 꽂혀 있는데 30초 넘게 드라이버에 안 붙음) 이 부팅에 한 번 "한 번 뺐다 꽂으세요"를 보인다.
# 다시 꽂으면(뽑기 감시 dg_replug_mark) 문구를 지운다. 새 번호 자리는 막혀 있어 순정이 열지 못한다
dg_plugagain_tick() {
  case "$DG_ST" in up|ok) ;; *) return 0 ;; esac
  _dgy1=; _dgy2=; [ -f $W/dg.eaoa ] && read _dgy1 _dgy2 < $W/dg.eaoa 2>/dev/null
  [ "$_dgy1" = "${BID:-none}" ] || return 0
  case "$_dgy2" in ''|*[!0-9]*|0) return 0 ;; esac
  _dgy3=; [ -f $W/dg.plugagain.done ] && read _dgy3 < $W/dg.plugagain.done 2>/dev/null
  [ "$_dgy3" = "${BID:-none}" ] && return 0
  _dgyb=
  [ "${DG_NOAP:-0}" -ge 1 ] 2>/dev/null && _dgyb=hapd
  if [ -z "$_dgyb" ] && ! dg_seen; then
    dg_usb
    if [ $DG_USB = ok ]; then
      _dgyi=; [ -f $W/dgins.done ] && read _dgyi < $W/dgins.done 2>/dev/null
      case "$_dgyi" in ''|*[!0-9]*) ;; *) dg_up_s; [ $((_dgu - _dgyi)) -ge 30 ] && _dgyb=nobind ;; esac
    fi
  fi
  [ -n "$_dgyb" ] || return 0
  # 베타 3(B3-9b, 소유자 결정 11-23 "방법 4가지를 순서대로 해보고 되는 것을 기록"): 드라이버가 붙기 전(nobind)이면 한 부팅에 한 차례
  # 다시 붙이기 사다리(dg_ladder)를 한다. 붙으면 안내 없이 끝, 모두 안 되면(또는 할 수 없으면) 지금처럼 "한 번 뺐다 꽂으세요"
  if [ "$_dgyb" = nobind ]; then
    dg_up_s; dg_tl nbt $_dgu
    dg_tl_diag nobind
    _dgld=; [ -f $W/dg.ladder ] && read _dgld _dglx < $W/dg.ladder 2>/dev/null
    if [ "$_dgld" != "${BID:-none}" ]; then dg_ladder && return 0; dg_seen && return 0; fi
  fi
  echo "${BID:-none}" 2>/dev/null > $W/dg.plugagain.done
  echo "${BID:-none}" 2>/dev/null > $W/dg.plugagain
  log "동글: 가드 전에 순정 AOA가 닿은 동글이 쓰이지 않음($_dgyb) — 한 번 뺐다 꽂으라고 안내(이 부팅만)"
  dg_status_push
  return 0
}
# 순정 상태 한 줄(내리기 바로 전, 값은 낱말·숫자만): wpa_supplicant·hostapd 수, wlan.driver.status, wifi_ap_on, bcmdhd 쓰는 수
dg_stock_line() {
  # 리뷰 낮음 4: busybox ps는 명령줄 전체를 보이므로 줄 안의 이름으로 센다
  _dsa=$($PS 2>/dev/null | $BB grep -v grep | $BB grep -v " Z " | $BB grep -c wpa_supplicant); _dsb2=$($PS 2>/dev/null | $BB grep -v grep | $BB grep -v " Z " | $BB grep -c hostapd)
  case "$_dsa" in ''|*[!0-9]*) _dsa=0 ;; esac; case "$_dsb2" in ''|*[!0-9]*) _dsb2=0 ;; esac
  _dsdr=$(getprop wlan.driver.status 2>/dev/null | $BB awk '{ gsub(/[^a-z0-9_]/, ""); print; exit }')
  _dsap=; [ "$1" = light ] || _dsap=$(settings get global wifi_ap_on 2>/dev/null | $BB awk '{ gsub(/[^a-z0-9_]/, ""); print; exit }')
  _dsrf=$($BB awk -v m=$DG_BUILTIN_MOD '$1 == m { print $3 + 0; exit }' ${PROC:-/proc}/modules 2>/dev/null)
  echo "wpa=$_dsa hostapd=$_dsb2 drv=${_dsdr:-none} apon=${_dsap:-none} bcmref=${_dsrf:--}"
}
# 동글 드라이버를 올리기 전 기다림. 0 됨, 1 순정 Wi-Fi가 끝내 조용해지지 않음, 2 동글 사용 꺼짐(막힘)
# 끝: DG_SETTLE_MAX번(1초씩, uptime을 못 읽어도 끝남. 리뷰 낮음 8: 늦게 다시 시작한 서비스도 이만큼 기다림).
# 리뷰 중간 3: 기다리는 동안 30번마다 설정 요청(토글)과 제보 요청을 받는다(본 반복에 들어가기 전이라)
# 인자: $1 기다릴 uptime, $2 상태 이름(bootwait). 1.8.0 정식(P1, R2): 예비 길(settle·bcmdhd 내림)과 "동글을 빼 달라" 기다림은 지웠다
# (베타 2부터 값으로 꺼 두었던 길). 동글은 꽂힌 채 둔다(시험판 6 F6)
dg_settle() {
  _dgq=0; _dgsn=0; _dgsm=${1:-0}; _dgss=${2:-bootwait}
  DG_ST=$_dgss; dg_state $_dgss "$DG_G"; dg_stage $_dgss
  log "동글: 내장 Wi-Fi 드라이버가 없음 — 부팅 ${_dgsm}초까지, 순정 Wi-Fi가 ${DG_QUIET}초 조용할 때 동글 드라이버를 올림(동글은 꽂힌 채 둠)"
  while [ $_dgsn -lt $DG_SETTLE_MAX ]; do
    [ -f $DG_ON ] && [ ! -f $DG_BLOCK ] || return 2
    dg_up_s; _dgsu=$_dgu
    if running wpa_supplicant || running hostapd; then _dgq=0; else _dgq=$((_dgq + 1)); fi
    [ $_dgsu -ge $_dgsm ] && [ $_dgq -ge $DG_QUIET ] && return 0
    [ $((_dgsn % 30)) = 29 ] && { set_take; req_report; }
    # 가드가 걸린 부팅만 10초마다 빈 자리를 다시 막는다(뺀 동글의 번호 자리 등)
    _dgsn=$((_dgsn + 1)); [ "$DG_GARMED" = 1 ] && [ $((_dgsn % 10)) = 0 ] && dg_guard_arm quiet
    sleep 1 & wait $!
  done
  return 1
}
# --- 니로 시험판 5(11-23, 소유자 결정 (가)·"설정을 잊지 않음", pkg.md "다섯 번째 니로 시험판") ---
# 동글 부팅은 순정 Wi-Fi를 아예 쓰지 않는다. 실패는 그 부팅만 내장으로 가고(설정은 그대로), 다음 부팅에 다시 동글을 시도한다.
# 계속 막는 것은 동글 길 도중 재부팅(hang) 하나뿐이고, 차주가 토글을 껐다 켜면 풀린다.
DG_KPROP=sys.kp.dongle
DG_PLUG_MAX=${DG_PLUG_MAX:-300}
# 1.8.0 정식(P1, R2): 예비 길(bcmdhd가 있으면 부팅 300초 뒤 내림)·"부팅 때 꽂힌 동글을 빼 달라"·기다리는 동안 동글 빼기 확인은 코드째 지웠다
# (시험판 5·베타 2부터 값으로 꺼 두었던 길: DG_FALLBACK=0·DG_PLUGGED_OK=1·DG_SETTLE_NOUSB). bcmdhd가 있으면 그 부팅은 내장으로 간다
# 부팅 때 동글이 없어도 동글 길을 탄다(1, 시험판 5). 0이면 예전처럼 "동글 없음"으로 끝(PC 시험의 옛 동작)
DG_NODEV_START=${DG_NODEV_START:-1}
DG_BOOT0F=${DG_BOOT0F:-$BK/dongle.boot0}
DG_GONE2_MSG="동글이 보이지 않습니다. 다시 꽂거나, 동글 사용을 끄면 다음 시동부터 내비 Wi-Fi로 돌아갑니다."
DG_NOBIND_MSG="동글이 꽂혀 있지만 쓸 수 없습니다. 동글 사용을 끄면 다음 시동부터 내비 Wi-Fi로 돌아갑니다."
DG_BCMUP_MSG="내비 Wi-Fi가 먼저 켜져 이번에는 동글을 쓰지 않았습니다. 다음 시동 때 다시 시도합니다."
# 1.8.1 I-8(#594 모하비 HM22): bcmup인데 내비 Wi-Fi로도 우리 핫스팟이 뜨지 않은 차(상태 화면 판정 dg_verdict만 씀).
# 예전에는 판정이 apoff("3분 후 재부팅")로 떨어져 차주가 재부팅만 되풀이했다. 재부팅을 권하지 않고 제보를 부탁한다
DG_BCMUP_NOAP_MSG="내비 Wi-Fi가 먼저 켜져 동글을 쓰지 못했고 핫스팟도 꺼져 있습니다. 다음 시동에도 같으면 제보해 주세요."
DG_FAILBOOT_MSG="동글 드라이버를 올리지 못해 이번에는 내비 Wi-Fi를 씁니다. 다음 시동 때 다시 시도합니다."
DG_PLUGTO_MSG="동글이 꽂히지 않아 이번에는 내비 Wi-Fi를 씁니다. 다음 시동 때 다시 시도합니다."
DG_NOAP_MSG="동글로 핫스팟을 띄우지 못했습니다. 다음 시동 때 다시 시도하며, 동글 사용을 끄면 다음 시동부터 내비 Wi-Fi로 돌아갑니다."
# 정식 F5: 늦게 꽂은 동글(tcc803x)의 첫 hostapd 실패. 꽂은 채 재부팅하면 뜬다(beta3-reports 9장)
DG_LATEAP_MSG="동글을 시동 뒤에 꽂아 핫스팟을 띄우지 못했습니다. 동글을 꽂은 채로 재부팅해 주세요."
DG_NODEVSTUCK_MSG="동글이 꽂히지 않았고 내비 Wi-Fi로도 바꾸지 못했습니다. 동글 사용을 끄면 다음 시동부터 내비 Wi-Fi로 돌아갑니다."
DG_PLUG_MSG="지금 동글을 꽂으세요. 동글 사용을 끄면 바로 내비 Wi-Fi로 돌아갑니다."
# 베타 3(B3-2, 메인 결정 11-23): 부품 없는 차에서 기다리는 중 끔 / 기다리는 동안 늘 보일 안내(가드가 데이터 USB 포트의 유선 연결을 막음)
DG_PLUGOFFNW_MSG="동글 사용을 껐습니다. 유선 프로젝션은 쓸 수 있습니다."
DG_PLUGWAIT_NOTE="동글을 기다리는 동안은 유선 프로젝션을 쓸 수 없습니다."
# 베타 3(B3-1, 메인 결정 11-23): 바로 올린 부팅에 순정 드라이버가 뒤늦게 올라옴(우리 AP를 멈춤, 그 부팅만의 실패)
DG_BCMLATE_MSG="내비 Wi-Fi가 뒤늦게 켜져 이번에는 동글을 쓰지 못했습니다. 재부팅해 주세요."
DG_BOOTWAIT_MSG="동글 준비 중입니다. 재부팅하지 마세요."
# 동글 부팅 속성: 바라는 값과 다를 때만 쓴다. 동글을 한 번도 안 쓴 차(속성이 비어 있음)에는 0도 쓰지 않는다
dg_kprop() {
  _dgkv=$(getprop $DG_KPROP 2>/dev/null)
  [ "$_dgkv" = "$1" ] && return 0
  [ "$1" = 0 ] && [ -z "$_dgkv" ] && return 0
  setprop $DG_KPROP $1 2>/dev/null; log "동글 부팅 속성 $DG_KPROP=$1"
}
# 계속 막힘(hang)만 동글을 막는다. 예전 판이 남긴 다른 이유(fail·gone·noap)는 지운다(그 부팅만의 실패로 바뀜)
dg_hang_block() {
  [ -f $DG_BLOCK ] || return 1
  _dghb1=; _dghb3=; read _dghb1 _dghb2 _dghb3 < $DG_BLOCK 2>/dev/null
  [ "$_dghb3" = hang ] && return 0
  rm -f $DG_BLOCK; log "동글: 예전 막힘 기록(${_dghb3:-?})을 지움 — 이제 그 부팅만의 실패로 보고 다시 시도함"
  return 1
}
# 부팅 기록 한 줄($BK/dongle.boot0, 최근 40줄): 부팅 번호, uptime, 때, 순정 bcmdhd·우리 88x2bu 있음, wlan0, 속성,
#   (올리기 직전 pre-ins 줄에만) 순정 저장값 셋·드라이버 상태·순정 HAL insmod 줄 수와 끝 시각. 동글을 켠 차에서만 쓴다
dg_boot0() {
  dg_wifi_want || return 0
  dg_up_s
  _dgbn=0; [ -f $BK/dongle.bootn ] && read _dgbn < $BK/dongle.bootn 2>/dev/null; case "$_dgbn" in ''|*[!0-9]*) _dgbn=0 ;; esac
  _dgbm=n; $BB grep -q "^$DG_BUILTIN_MOD " ${PROC:-/proc}/modules 2>/dev/null && _dgbm=y
  _dgbd=n; dg_present && _dgbd=y
  _dgbw=n; [ -e ${SYSNET:-/sys/class/net}/$DG_IFNAME ] && _dgbw=y
  _dgbl="#$_dgbn up=$_dgu $1 bcmdhd=$_dgbm 88x2bu=$_dgbd wlan0=$_dgbw prop=$(getprop $DG_KPROP 2>/dev/null)"
  # 저장값·logcat은 올리기 직전(pre-ins, 부팅 약 60초 뒤)에만: settings는 한 번에 몇 초 걸리고, 서비스 시작·부팅 끝 직후에는
  # 가드를 거는 일을 늦춘다. 그 때의 순정 HAL insmod 줄이 "wifi_on=0이면 bcmdhd가 안 올라오는지"의 근거다
  if [ "$1" = pre-ins ]; then
    _dgbh=$(logcat -d -v time 2>/dev/null | $BB awk '/WifiHW|wifi_load_driver/ && /insmod/ { n++; t = $2 } END { print n + 0 " " (n ? t : "-") }')
    _dgbl="$_dgbl wifi_on=$(dg_sget wifi_on) scan=$(dg_sget wifi_scan_always_enabled) ap_on=$(apon_get) drv=$(getprop wlan.driver.status 2>/dev/null | $BB awk '{ gsub(/[^a-z0-9_]/, ""); print; exit }') hal_insmod=${_dgbh:-?}"
  fi
  { $BB tail -n 39 $DG_BOOT0F 2>/dev/null; echo "$_dgbl"; } 2>/dev/null > $DG_BOOT0F.tmp && $BB mv -f $DG_BOOT0F.tmp $DG_BOOT0F 2>/dev/null
  $BB sync
}
# 이번 부팅만의 결과 기록($BK/dongle.bst "<boot_id> <상태>", 리뷰 중간 3): 같은 부팅에 서비스가 다시 시작해도(업데이트 포함) 그 결과를 되살린다
dg_bst() { echo "${BID:-none} $1" 2>/dev/null > $BK/dongle.bst; case "$1" in bcmlate|failboot|noap|nodevstuck|nobind|reupmax) dg_fast_fail "${BID:-none}" ;; esac; }
# 서비스가 시작할 때(부팅 +4초, 부팅 끝을 기다리기 전): 동글을 켠 차는 속성을 먼저 세워 모드가 순정 AP를 켜지 않게 한다.
# settings는 부르지 않는다(이 때는 시스템 서버가 아직 없음). 부팅 번호를 하나 올리고 기록 한 줄
dg_early() {
  dg_up_s; DG_SVCUP=$_dgu
  # B3-9 기록 1: 서비스 시작 uptime(1/100초)
  _dgec=; { read _dgec _dgex2 < ${UPTIME:-/proc/uptime}; } 2>/dev/null; _dgec=$(echo "$_dgec" | $BB awk '{ printf "%d", $1 * 100 }' 2>/dev/null)
  DG_SVCUPC=$_dgec
  [ -f $DG_ON ] || return 0
  # 예전 판의 막힘(hang이 아닌 것)은 여기서 지운다(그래야 아래 바라는 상태가 맞음)
  [ -f $DG_BLOCK ] && dg_hang_block && return 0
  dg_wifi_want || return 0
  _dgbn=0; [ -f $BK/dongle.bootn ] && read _dgbn < $BK/dongle.bootn 2>/dev/null; case "$_dgbn" in ''|*[!0-9]*) _dgbn=0 ;; esac
  [ "${SVC_FIRST:-1}" = 1 ] && echo $((_dgbn + 1)) 2>/dev/null > $BK/dongle.bootn
  dg_kprop 1
  dg_boot0 early
  # 시험판 6(F6): 꽂아 둔 채 시동이면 순정보다 먼저 가드를 건다
  dg_guard_early
}
# 이번 부팅만 내장 Wi-Fi로 간다(설정·저장값 기록은 그대로, 다음 부팅에 다시 동글). $1 상태, $2 로그 이유.
# 동글 드라이버가 올라가 있고 장치가 붙지 않았으면 먼저 내린다(rmmod-nodev, 장치가 붙어 있으면 내리지 않음 — 붙은 채 뽑기와 같은 길).
# 내리지 못하면 내장으로 가지 않고 그 부팅은 무선 없음(nodevstuck). 내장 켜기는 take_wlan0(svc wifi enable, 처음 올리는 bcmdhd)
dg_to_builtin() {
  # 예비 길(이 부팅에 순정 bcmdhd를 rmmod함)이면 같은 부팅에 내장으로 돌아가지 않는다(5차 원칙: 다시 올리면 안 됨). 재부팅 안내
  _dgtb2=; [ -f $DG_RMF ] && read _dgtb1 _dgtb2 < $DG_RMF 2>/dev/null
  if dg_rm_now && [ "$_dgtb2" != clean ]; then
    rm -f $DG_TRY; $BB sync; dg_guard_release
    DG_ST=$1; dg_state $1 "$DG_G"; log "동글: 이번 부팅에 순정 드라이버를 내려 내장으로 돌아가지 않음($2) — 재부팅하면 원래대로"
    pnotice "Korea Projection: $DG_REBOOT_MSG"; return 1
  fi
  if dg_present; then
    if dg_seen; then
      log "동글: 장치가 붙어 있어 동글 드라이버를 내리지 않음 — 이번 부팅은 무선 없음($1)"
      rm -f $DG_TRY; $BB sync
      DG_ST=nodevstuck; dg_state nodevstuck "$DG_G"; dg_bst nodevstuck; return 1
    fi
    dg_step rmmod-nodev
    _dgrm=$RMMOD_SYS; [ -x "$_dgrm" ] || _dgrm="$BB rmmod"
    # 리뷰 높음 2: 뒤에서 돌리고 DG_RMWAIT초까지만 기다린다(커널 안에서 멈춰도 서비스는 계속 감)
    ( $_dgrm $DG_MOD ) </dev/null >/dev/null 2>&1 &
    _dgw=0
    while dg_present && [ $_dgw -lt ${DG_RMWAIT:-10} ]; do sleep 1 & wait $!; _dgw=$((_dgw + 1)); done
    if dg_present; then
      # 리뷰 중간 1: 시도 기록을 지운다(다음 부팅이 이 실패를 "도중 재부팅"으로 막지 않게, 다음 시동에 다시 시도)
      rm -f $DG_TRY; $BB sync
      dg_step "rmmod-nodev rc=fail"; log "동글: 장치 없는 동글 드라이버를 내리지 못함 — 이번 부팅은 무선 없음"
      DG_ST=nodevstuck; dg_state nodevstuck "$DG_G"; dg_bst nodevstuck; return 1
    fi
    dg_step "rmmod-nodev rc=0"
  fi
  rm -f $DG_TRY $DG_RMF; $BB sync; dg_guard_release
  DG_ST=$1; dg_state $1 "$DG_G"; dg_stage builtin; dg_bst $1
  # 리뷰 높음 1: 그 부팅만의 실패로 끝났으니 "도중 재부팅 예외" 수를 지운다(몇 주 뒤의 시동 끔을 막힘으로 보지 않게)
  rm -f $BK/dongle.noprobe
  dg_kprop 0
  log "동글: 이번 부팅은 내비 Wi-Fi로 감($2) — 설정은 그대로, 다음 시동에 다시 동글을 시도함"
  return 0
}
# 꽂기 기다림 중(상태 up, 동글이 드라이버에 안 붙음, 이번 부팅에 한 번도 붙지 않음)인가. 이때 끄면 다음 점검이 그 부팅에 바로 내비 Wi-Fi로
# 돌린다(dg_plug_tick). 끄기 요청 처리(set_take)와 상태 키 dongle_wait가 함께 쓴다(둘이 어긋나지 않게)
dg_plugwait_now() {
  _dpw=; [ -f $W/dongle.state ] && read _dpw _dpwx < $W/dongle.state 2>/dev/null
  [ "$_dpw" = up ] || return 1
  dg_seen && return 1
  _dpws=; [ -f $W/dongle.seen1 ] && read _dpws _dpwy < $W/dongle.seen1 2>/dev/null
  [ "$_dpws" != "$(dg_kv_bid)" ]
}
# 30초 점검: 꽂으라는 안내 뒤 차주가 동글 사용을 끄면 이번 부팅은 내장으로(재부팅 없음).
# 베타 3(B3-2, 소유자 결정 11-23 "5분 지나도 안 꼽아도 그냥 냅두자"): 꽂지 않아도 시간으로 끝내지 않고 계속 기다린다(예전 plugto 없앰).
# 끄면 순서: 장치 없는 88x2bu 내리기 → 가드 풀기 → 순정 저장값 되돌리기(dg_wifi_sync, 앞에서) → 내장 켜기(take_wlan0).
# 부품 없는 차(근거 nopart·nochip)는 돌아갈 내장이 없어 내장을 켜지 않고 가드만 풀어 유선 프로젝션을 되살린다(plugoffnw)
dg_plug_tick() {
  case "$DG_ST" in up) ;; *) return 0 ;; esac
  dg_seen && return 0
  _dgs1=; [ -f $W/dongle.seen1 ] && read _dgs1 _dgsx < $W/dongle.seen1 2>/dev/null
  [ "$_dgs1" = "${BID:-none}" ] && return 0
  _dgpi=; _dgpb=; [ -f $W/dgins.done ] && read _dgpi < $W/dgins.done 2>/dev/null
  case "$_dgpi" in ''|*[!0-9]*) return 0 ;; esac
  dg_up_s
  # 리뷰 중간 6: 허용 동글이 USB에 보이는데 아직 드라이버에 붙지 않았으면(프로브 중) 내리지 않고 다음 점검을 기다린다.
  # 안내 뒤 DG_PLUG_MAX+60초가 지나도 그대로면 내리지 않고 이 부팅은 무선 없음(nodevstuck)
  _dgpu=; dg_usb; [ $DG_USB = ok ] && _dgpu=1; dg_up_s
  if [ -n "$_dgpu" ]; then
    [ $((_dgu - _dgpi)) -ge $((DG_PLUG_MAX + 60)) ] || return 0
    rm -f $DG_TRY; $BB sync; DG_ST=nobind; dg_state nobind "$DG_G"; dg_bst nobind; dg_tl nobind $_dgu
    log "동글: 동글이 꽂혀 있지만 드라이버에 붙지 않음 — 이번 부팅은 무선 없음"; return 0
  fi
  # 리뷰 낮음 3: 서비스 시작 중(dg_start 안)에는 내장 켜기를 main에 맡긴다
  [ -f $DG_ON ] && return 0
  case "$(dg_evidence)" in
    nopart|nochip)
      dg_to_builtin plugoffnw "꽂기 전에 동글 사용을 끔(내장 Wi-Fi 부품 없음: 내장은 켜지 않음)" && dg_wifi_sync ;;
    *) dg_to_builtin plugoff "꽂기 전에 동글 사용을 끔" && { dg_wifi_sync; [ "${DG_IN_START:-0}" = 0 ] && take_wlan0; } ;;
  esac
  return 0
}
# 30초 점검: 꽂힌 동글이 허용 3종인지(부팅 때 동글이 없었던 길). 목록 밖이면 우리 AP를 띄우지 않음(notours)
dg_ident_tick() {
  case "$DG_ST" in up|ok) ;; *) return 0 ;; esac
  [ -f $W/dongle.ident ] && return 0
  dg_seen || return 0
  dg_usb
  : 2>/dev/null > $W/dongle.ident
  [ $DG_USB = notlisted ] || return 0
  stop_ours; rm -f $DG_TRY; $BB sync; DG_ST=notours; dg_state notours "$DG_G"; dg_bst notours; log "동글: 꽂힌 동글이 지원 목록에 없어 우리 AP를 띄우지 않음"
}
dg_start() {
  dg_pull_endcheck; dg_step_endcheck; rm -f $W/hapd.up
  dg_up_s; DG_BOOT0=$_dgu
  DG_RUN=0; DG_ST=; DG_G=
  rm -f $W/dongle.state
  # SC-5: 차주 선택이 없고 근거가 쌓인 차는 허용 동글이 꽂혀 있으면 토글을 자동으로 켠다(그러면 이번 부팅부터 아래로 감)
  dg_auto
  # 시험판 4: 순정 Wi-Fi 저장값을 바라는 상태로(동글 사용이면 0, 아니면 기록이 있을 때 되돌림)
  dg_wifi_sync
  # 리뷰 높음 2: 동글 길을 타지 않는 부팅(같은 부팅 다시 시작 포함)은 이번 부팅 가드를 남기지 않는다
  # 시험판 5: 동글을 끈 차는 속성이 1로 남아 있을 때만 0으로(한 번도 안 쓴 차는 아무것도 쓰지 않음)
  [ -f $DG_ON ] || { dg_guard_release; dg_kprop 0; return 0; }
  DG_RUN=1
  # 리뷰 중간 3: 이번 부팅에 이미 그 부팅만의 실패로 끝났으면(서비스 다시 시작) 그 결과를 그대로 되살린다(동글 AP를 다시 띄우지 않음)
  _dgb1=; _dgb2=; [ -f $BK/dongle.bst ] && read _dgb1 _dgb2 < $BK/dongle.bst 2>/dev/null
  if [ -n "$BID" ] && [ "$_dgb1" = "$BID" ]; then
    case "$_dgb2" in
      noap|nodevstuck|nobind|notours|bcmup|failboot|plugto|plugoff|plugoffnw|bcmlate|reupmax)
        DG_ST=$_dgb2; dg_state $_dgb2 "$DG_G"
        case "$_dgb2" in noap|nodevstuck|nobind|notours|reupmax|bcmlate) ;; *) dg_kprop 0 ;; esac
        # 리뷰 중간 3: 동글이 wlan0을 잡지 않은 결과(내비 Wi-Fi로 감)·목록 밖이면 가드를 남기지 않는다
        case "$_dgb2" in noap|nodevstuck|nobind|reupmax|bcmlate) ;; *) dg_guard_release ;; esac
        log "동글: 이번 부팅은 이미 '$_dgb2'로 끝남(서비스 다시 시작) — 그대로 둠"; return 0 ;;
    esac
  fi
  dg_boot0 start
  if dg_hang_block; then
    dg_kprop 0
    DG_ST=blocked; _dgg=; read _dgb _dgg _dgx < $DG_BLOCK 2>/dev/null; dg_state blocked "$_dgg"; dg_guard_release
    log "동글 드라이버: 동글 길 도중 재부팅한 기록(hang)이 있어 올리지 않음 — 동글 사용을 껐다 켜면 다시 시도"; return 0
  fi
  dg_ladder_crashcheck
  if [ -f $DG_TRY ]; then
    _dgb=; _dgg=; read _dgb _dgg _dgt < $DG_TRY 2>/dev/null
    if [ -n "$BID" ] && [ "$_dgb" = "$BID" ]; then
      # 리뷰 중간 2: 순정 드라이버를 내리다 멈춰 insmod를 하지 않은 부팅(rmstuck)이면 그대로 되살린다(재부팅 안내가 사라지지 않게).
      # 정식 P1 뒤에도 기본 길에서 이 부팅 표시(clean)를 쓴 뒤 insmod 전에 서비스가 다시 시작하면 여기로 온다(지우지 않음)
      dg_rc
      if dg_rm_now && [ -z "$DG_RC" ] && ! dg_present; then
        DG_G=$_dgg; DG_ST=rmstuck; dg_state rmstuck "$_dgg"; dg_guard_release; log "동글: 이번 부팅은 순정 드라이버를 내리다 멈춘 부팅(서비스 다시 시작), 재부팅 안내"; return 0
      fi
      DG_G=$_dgg; DG_ST=wait; dg_state wait "$_dgg"
      log "동글 드라이버: 이번 부팅에 이미 올림(서비스 다시 시작), 다시 올리지 않고 결과만 봄"
      dg_tick; return 0
    fi
    # 시험판 4: 드라이버만 올라가 있고 동글이 한 번도 붙지 않은 채 끝난 부팅(시동 끔 등)은 막지 않고 이번 부팅에 다시 한다
    # 리뷰 높음 1: 이 예외는 잇달아 한 번만(두 번째면 막음). 시도 기록을 정상으로 지우면(dg_watch) 수를 지운다
    # 재리뷰 높음: 위험 단계 밖에서 끝난 부팅(평범한 시동 끔)은 몇 번이든 막지 않는다(예전의 한 번 예외 수는 쓰지 않음, 남은 파일은 지움)
    if dg_step_noprobe "$_dgb"; then
      rm -f $DG_TRY $BK/dongle.noprobe; $BB sync
      log "동글 드라이버: 지난 부팅은 위험한 단계 밖에서 끝남(평범한 시동 끔으로 봄) — 막지 않음"
    else
      dg_block hang; return 0
    fi
  fi
  # 리뷰 중간 3: 이번 부팅에 이미 insmod를 돌렸으면(시도 기록은 지운 뒤) 두 번 올리지 않는다. 모듈이 그대로면 ok, 사라졌으면 막음
  dg_rc
  if [ -n "$DG_RC" ]; then
    if dg_live; then DG_ST=ok; dg_state ok "$DG_G"; log "동글 드라이버: 이번 부팅에 올려 둔 그대로"
    else dg_to_builtin failboot "이번 부팅에 올린 동글 드라이버가 사라짐"; fi
    return 0
  fi
  # DG-8: 다른 동글 패키지가 있으면 시작하지 않음.
  # 1.8.1 I-7(#609 NX4·#612 DL3HEV22): 남의 패키지가 우리와 같은 이름의 드라이버(88x2bu)를 이미 올린 차는 예전에 아래 dg_present에서
  # other로 끝나 "다른 동글 패키지" 안내가 나오지 않았다(차주는 부품 없음만 봄). 다른 패키지 감지를 먼저 본다
  if dg_otherpkg; then dg_guard_release; DG_ST=otherpkg; dg_state otherpkg "$DG_OTHER"; log "동글: 다른 동글 패키지·드라이버($DG_OTHER)가 있어 쓰지 않음"; return 0; fi
  if dg_present; then dg_guard_release; DG_ST=other; dg_state other; log "동글 드라이버: $DG_MOD가 이미 목록에 있음(우리가 올린 것 아님), 건드리지 않음"; return 0; fi
  # DG-3: 허용한 동글이 꽂혀 있을 때만 올린다(없으면 올리지 않음, 동글을 꽂고 재부팅)
  dg_usb
  # 시험판 5: 부팅 때 동글이 없어도 동글 길을 탄다(드라이버를 먼저 올리고 "지금 동글을 꽂으세요", 허용 확인은 꽂은 뒤 dg_ident_tick)
  if [ $DG_USB = none ] && ! usb_adb_on && [ "$DG_NODEV_START" = 1 ]; then
    rm -f $DG_OUIF; log "동글: 부팅 때 동글이 없음 — 드라이버를 올린 뒤 꽂으라고 안내함"
  elif [ $DG_USB != ok ]; then
    # NM-2: USB ADB가 켜져 있으면 "동글 없음"이 아니라 그 이유를 보인다(동글이 꽂혀 있어도 안 보임)
    if [ $DG_USB = notlisted ]; then DG_ST=notlisted; elif usb_adb_on; then DG_ST=usbadb; else DG_ST=nodongle; fi
    dg_kprop 0
    # 동글 판정 기록은 지원 동글이 꽂혀 있지 않은 부팅에 지운다(다른 동글로 바꿨을 수 있음)
    rm -f $DG_OUIF; dg_guard_release
    dg_state $DG_ST; log "동글: 올리지 않음($DG_ST)"; return 0
  fi
  # 배포판: 지난 부팅의 "지원 동글 아님" 기록으로 미리 막지 않는다(다른 동글로 바꿨을 수 있음). 그 부팅만의 결과라
  # 이번 부팅에 붙은 뒤 다시 판단한다(dg_oui_gate). 동글을 쓰는 부팅은 내장 Wi-Fi 드라이버가 처음부터 없어 미리 막아도 얻는 것이 없다
  if ! dg_pick; then dg_guard_release; DG_ST=$DG_WHY; dg_state $DG_WHY; log "동글 드라이버: 올리지 않음($DG_WHY)"; return 0; fi
  _dgk=$DG_DRV/$DG_G/$DG_MOD.ko
  [ -s $_dgk ] || { dg_guard_release; DG_ST=nodrv; dg_state nodrv "$DG_G"; log "동글 드라이버: 이 칩용 파일이 패키지에 없음($DG_G)"; return 0; }
  [ -n "$BID" ] || { dg_guard_release; DG_ST=nowrite; dg_state nowrite "$DG_G"; log "동글 드라이버: 부팅 id를 못 읽어 올리지 않음"; return 0; }
  # 시험판 4: 이 패키지를 설치·업데이트한 부팅에는 동글 길을 타지 않는다(설치 USB가 포트에 있고 곧 재부팅함. post.sh가 그때 boot_id를 남김)
  _dgsk=; [ -f $DG_SKIPF ] && read _dgsk _dgskx < $DG_SKIPF 2>/dev/null
  if [ -n "$_dgsk" ] && [ "$_dgsk" = "$BID" ]; then
    dg_guard_release; DG_ST=skip; dg_state skip "$DG_G"; log "동글: 이 부팅에 패키지를 설치해 동글 길을 타지 않음(재부팅하면 시작)"; return 0
  fi
  rm -f $DG_SKIPF
  # 베타 2 AOA 가드: 순정 드라이버를 내리기 전에 건다. 부팅 때 이미 꽂힌 동글(노드가 있음)은 빼게 하고, 드라이버를 올린 뒤에 꽂게 한다(시험판 4)
  rm -f $W/aoa.state; DG_GARMED=; DG_GDONE=
  if dg_guard_on && dg_guard_paths; then
    dg_guard_arm
    # 배포판(리뷰 높음 3): 이른 가드 뒤에 붙은 동글 아닌 장치(유선 폰 등)는 노드를 되살린다
    dg_guard_unblock_others
    # 시험판 6(F6): 꽂아 둔 채 시동이면 빼 달라고 하지 않는다. 노드가 남아 있으면 빈 폴더로 바꾸고, 가드 전에 순정 AOA가 닿았는지 센다
    if [ "$DG_GARMED" = 1 ] && [ -n "$DG_GNODE" ]; then
      dg_guard_swap start
      _dgea=; _dgeb=; [ -f $DG_EARLYF ] && read _dgeb _dgea _dgec < $DG_EARLYF 2>/dev/null
      if [ "$_dgeb" = "$BID" ]; then
        case "$_dgea" in
          swapped|keep) _dgen=$(dg_aoa_count); case "$_dgen" in ''|*[!0-9]*) _dgen=0 ;; esac
            echo "$BID $_dgen" 2>/dev/null > $W/dg.eaoa; dg_tl aoa $_dgen
            log "AOA 가드: 꽂아 둔 채 시동 — 가드 전 노드 $_dgea, 순정 AOA 줄 $_dgen" ;;
          blocked) echo "$BID 0" 2>/dev/null > $W/dg.eaoa; log "AOA 가드: 꽂아 둔 채 시동 — 동글 자리가 가드로 막혀 있었음" ;;
        esac
        dg_boot0 "guard:$_dgea"
      fi
    fi
  fi
  # 시험판 4(설계 변경, dongle.md 4-24): 순정 Wi-Fi 저장값을 꺼 두어(dg_wifi_sync) bcmdhd가 없으면 기본 길(clean):
  #   부팅 DG_BOOTWAIT초 뒤(순정 AP 복구 40~46초가 지난 뒤)·순정 Wi-Fi 조용함을 기다린 뒤 rmmod 없이 insmod.
  # 시험판 5부터: bcmdhd가 있으면(또는 기다리는 동안 올라오면) 이번 부팅은 내장으로(설정은 그대로). 1.8.0 정식(P1): 예비 길 코드는 지웠다
  if ! dg_bcm_absent; then
    dg_guard_release; dg_to_builtin bcmup "부팅 때 순정 Wi-Fi 드라이버(bcmdhd)가 이미 있음"; return 0
  fi
  _dgway=clean
  # 베타 3(B3-1): 조건이 모두 맞으면 기다리지 않고 바로 올린다(아래 기다림을 건너뜀)
  DG_FASTWAY=
  dg_tl_kaoa; dg_tl_diag start
  if dg_fast_ok; then
    DG_FASTWAY=1; log "동글: 바로 올림(시동 뒤 기다림 없음 — 동글 부팅 속성·순정 저장값 0·순정 드라이버 없음)"
  else
    log "동글: 바로 올리지 않고 기다림 길로 감($DG_FASTWHY)"
    dg_settle $((DG_BOOT0 + DG_BOOTWAIT)) bootwait
    _dgsr=$?
    if [ $_dgsr = 2 ]; then dg_guard_release; DG_ST=; rm -f $W/dongle.state; dg_kprop 0; log "동글: 기다리는 동안 동글 사용이 꺼져 그만둠(아무것도 바꾸지 않음, 이번 부팅은 내비 Wi-Fi)"; return 0; fi
    if [ $_dgsr = 1 ]; then dg_guard_release; DG_ST=builtinbusy; dg_state builtinbusy "$DG_G"; log "동글: 순정 Wi-Fi가 끝내 조용해지지 않아 이번 부팅은 동글을 쓰지 않음(아무것도 바꾸지 않음)"; return 0; fi
    if ! dg_bcm_absent; then dg_guard_release; dg_to_builtin bcmup "기다리는 동안 순정 Wi-Fi 드라이버(bcmdhd)가 올라옴"; return 0; fi
  fi
  dg_stage pre-rm
  _dgstk=$(dg_stock_line); log "동글: 올리기 전 순정 상태 $_dgstk, 길 $_dgway"
  kp_up
  _dgl="$BID $DG_G ${_U:-0}"
  echo "$_dgl" 2>/dev/null > $DG_TRY.tmp && $BB mv -f $DG_TRY.tmp $DG_TRY 2>/dev/null && $BB sync
  _dgr=; [ -f $DG_TRY ] && _dgr=$(cat $DG_TRY 2>/dev/null)
  if [ "$_dgr" != "$_dgl" ]; then
    rm -f $DG_TRY $DG_TRY.tmp; dg_guard_release
    DG_ST=nowrite; dg_state nowrite "$DG_G"; log "동글 드라이버: 시도 기록을 남기지 못해 올리지 않음"; return 0
  fi
  # 시험판 4: 단계 기록 시작(1초 기록·dmesg 사본, sync). 위험한 일 앞에 표시 줄을 먼저 쓴다
  dg_step_begin; dg_step "stock $_dgstk path=$_dgway"
  dg_rm_now || rm -f $DG_RMF
  # 리뷰 중간 4: 내리는(또는 올리는) 동안부터 wait(상태 화면 "올리는 중… 꽂지 마세요", 내장 쉬기 dg_builtin_off). 지난 insmod 결과는 지운다
  rm -f $DG_RCF $W/dgins.start; DG_ST=wait; dg_state wait "$DG_G"
  dg_step rm-skip
  # 시험판 4: DG_PRE_INS초 쉰 다음 올린다(바로 올리는 길은 쉬지 않음)
  dg_stage pre-ins
  _dgiw=0; [ "$DG_FASTWAY" = 1 ] && _dgiw=$DG_PRE_INS
  while [ $_dgiw -lt $DG_PRE_INS ]; do sleep 1 & wait $!; _dgiw=$((_dgiw + 1)); done
  # 리뷰 중간 4: 차주가 동글 사용을 껐으면 올리지 않는다(시도 기록은 지움, 아무것도 바꾸지 않았으므로 이번 부팅은 내비 Wi-Fi)
  if ! { [ -f $DG_ON ] && [ ! -f $DG_BLOCK ]; }; then
    rm -f $DG_TRY; $BB sync; dg_guard_release; DG_ST=; rm -f $W/dongle.state; dg_stage off; dg_step ins-skip-off
    dg_kprop 0; log "동글: 올리기 전에 동글 사용이 꺼져 그만둠(아무것도 바꾸지 않음, 이번 부팅은 내비 Wi-Fi)"
    return 0
  fi
  # 기본 길: 올리기 바로 전에 bcmdhd가 없는지 한 번 더 보고(있으면 아무것도 바꾸지 않고 그만둠), 이 부팅 표시를 남긴다.
  # 표시가 있으면 동글 길이 실패해도 이 부팅에 내장 Wi-Fi를 켜지 않는다(88x2bu가 wlan0을 잡은 채 순정 HAL이 bcmdhd를 같은 이름으로 올리지 않게, 재부팅 안내)
  if ! dg_bcm_absent; then
    dg_step ins-skip-bcm; dg_guard_release; dg_to_builtin bcmup "올리기 바로 전에 순정 Wi-Fi 드라이버(bcmdhd)가 올라옴"; return 0
  fi
  echo "${BID:-none} clean" 2>/dev/null > $DG_RMF.tmp && $BB mv -f $DG_RMF.tmp $DG_RMF 2>/dev/null
  if ! dg_rm_now; then
    rm -f $DG_RMF.tmp $DG_TRY; $BB sync; dg_guard_release; DG_ST=nowrite; dg_state nowrite "$DG_G"; log "동글 드라이버: 이 부팅 표시를 남기지 못해 올리지 않음"; return 0
  fi
  _dgiu=0; dg_usb; [ $DG_USB = ok ] && { _dgiu=1; log "동글: insmod 때 동글이 이미 꽂혀 있음(안내 전에 꽂음)"; }
  # 정식 F5: insmod 때 동글이 없었던 부팅을 적는다(dg_late_first). 있었으면 지운다
  if [ $_dgiu = 1 ]; then rm -f $W/dg.late; else echo "${BID:-none}" 2>/dev/null > $W/dg.late; fi
  [ "$DG_FASTWAY" = 1 ] || dg_boot0 pre-ins
  dg_up_s; echo "${BID:-none} $_dgu" 2>/dev/null > $W/dgins.start
  dg_tl ins $_dgu
  if [ "$DG_FASTWAY" = 1 ]; then echo "${BID:-none}" 2>/dev/null > $BK/dongle.fastb; $BB sync; fi
  log "동글 드라이버를 올림($DG_G, 이름 $DG_IFNAME)"
  dg_stage insmod; dg_step "ins-start dongle=$_dgiu"
  # insmod는 뒤에서 돌린다(커널 안에서 멈추면 서비스까지 멈추지 않게). 결과 "<boot_id> <돌려준 값> <묶음>"은 tmp→mv로 쓴다
  # 시험판 4: 8차(2h)와 같은 인자(두 번째 이름 kpp%d — 드라이버가 둘째 장치를 만들 때 wlan 이름과 겹치지 않게)
  ( "$INSMOD_SYS" "$_dgk" ifname=$DG_IFNAME if2name=kpp%d >/dev/null 2>&1; echo "$BID $? $DG_G" 2>/dev/null > $DG_RCF.tmp && $BB mv -f $DG_RCF.tmp $DG_RCF ) &
  # 끝나는 조건: 결과 파일 또는 DG_WAIT초(기본 10초)
  _dgw=0
  while [ ! -f $DG_RCF ] && [ $_dgw -lt ${DG_WAIT:-10} ]; do sleep 1 & wait $!; _dgw=$((_dgw + 1)); done
  dg_rc; dg_up_s; echo "$_dgu" 2>/dev/null > $W/dgins.done
  dg_step "ins-done rc=${DG_RC:-none}"
  # 베타 3(B3-1): 바로 길은 순정 근거 줄을 insmod 뒤에 남기고, 늦은 순정 드라이버를 2초마다 지켜본다(120초에 끝)
  if [ "$DG_FASTWAY" = 1 ]; then dg_boot0 post-ins; ( dg_bcm_watch ) </dev/null >/dev/null 2>&1 & fi
  # 시험판 4: "이제 꽂아 주세요"는 insmod가 끝나고 DG_PLUG_DELAY초 뒤에(dg_tick이 up으로 바꾸면 상태 화면 문구가 바뀜)
  if [ "$DG_RC" = 0 ] && ! dg_seen; then
    dg_stage plug-delay
    _dgid=0; while [ $_dgid -lt $DG_PLUG_DELAY ]; do sleep 1 & wait $!; _dgid=$((_dgid + 1)); done
  fi
  dg_tick
  case "$DG_ST" in up|ok) dg_stage plug; dg_step prompt; if dg_seen; then log "동글: 꽂혀 있던 동글이 드라이버에 붙음(꽂기 안내 없음)"; else log "동글: 이제 동글을 꽂아 달라고 안내"; fi ;; esac
  return 0
}
# --- 베타 3(B3-1, 소유자 결정 11-23 "동글 사용 켜져있다면 … 바로 동글 붙이는거"): 시동 직후 바로 올리기 ---
# 부팅이 끝난 뒤(sys.boot_completed, 약 21초) 아래가 모두 맞으면 기다림(시작 +60초·순정 5초 조용함) 없이 올린다.
# +4초(dg_early)에는 올리지 않는다: 순정 Wi-Fi HAL이 부팅 약 10초에 드라이버를 내린다(동글 부팅마다 drv=unloading, K3 FINDINGS 2072행).
# 조건(근거 pkg.md "베타 3 설계 B3-1" 2장): 이번 부팅 속성 sys.kp.dongle=1, 서비스 시작 때 순정 저장값 wifi_on·wifi_ap_on이 이미 0
# (1이었던 부팅은 순정이 bcmdhd를 일찍 올림, 부팅 기록 #7), bcmdhd·wlan0 없음, wlan.driver.status가 ok·loading이 아님,
# 바로 올리기 실패가 잇달아 DG_FAST_MAXFAIL번(2) 미만(정식 후보라 기다림 길을 비상구로 남김, 메인 결정 11-23)
DG_FAST=${DG_FAST:-1}
DG_FAST_MAXFAIL=${DG_FAST_MAXFAIL:-2}
DG_FASTF=${DG_FASTF:-$BK/dongle.fastfail}
dg_fast_n() { _dgfn=0; [ -f $DG_FASTF ] && read _dgfn < $DG_FASTF 2>/dev/null; case "$_dgfn" in ''|*[!0-9]*) _dgfn=0 ;; esac; }
dg_fast_ok() {
  DG_FASTWHY=
  [ "$DG_FAST" = 1 ] || { DG_FASTWHY="바로 올리기 꺼짐"; return 1; }
  dg_fast_n; [ $_dgfn -lt $DG_FAST_MAXFAIL ] || { DG_FASTWHY="바로 올리기가 ${_dgfn}번 이어서 실패"; return 1; }
  [ "$(getprop $DG_KPROP 2>/dev/null)" = 1 ] || { DG_FASTWHY="동글 부팅 속성 없음"; return 1; }
  [ "$DG_WZ_OK" = 1 ] || { DG_FASTWHY="서비스 시작 때 순정 Wi-Fi 저장값이 0이 아니었음"; return 1; }
  dg_bcm_absent || { DG_FASTWHY="순정 Wi-Fi 드라이버 있음"; return 1; }
  _dgfd=$(getprop wlan.driver.status 2>/dev/null)
  # 리뷰 낮음 1: 순정 HAL이 내린 뒤(unloading·unloaded)나 값이 없을 때만(허용 목록)
  case "$_dgfd" in unloading|unloaded|'') ;; *) DG_FASTWHY="순정 Wi-Fi 드라이버 상태 $_dgfd"; return 1 ;; esac
  if running wpa_supplicant || running hostapd; then DG_FASTWHY="순정 Wi-Fi가 돌고 있음(wpa_supplicant·hostapd)"; return 1; fi
  return 0
}
# 바로 올린 부팅($BK/dongle.fastb의 부팅 id)이 실패로 끝났으면 실패 수 +1(같은 부팅은 한 번만). $1 그 부팅 id
dg_fast_fail() {
  _dgfb=; [ -f $BK/dongle.fastb ] && read _dgfb < $BK/dongle.fastb 2>/dev/null
  [ -n "$_dgfb" ] && [ "$_dgfb" = "$1" ] || return 0
  dg_fast_n; echo $((_dgfn + 1)) 2>/dev/null > $DG_FASTF; echo "$1 done" 2>/dev/null > $BK/dongle.fastb; $BB sync
  log "동글: 바로 올린 부팅이 실패로 끝남(잇달아 $((_dgfn + 1))번, ${DG_FAST_MAXFAIL}번이면 다음 부팅은 기다림 길)"
}
# 바로 올린 부팅에 우리 AP가 뜨면 실패 수를 지운다
dg_fast_ok_mark() {
  _dgfb=; [ -f $BK/dongle.fastb ] && read _dgfb < $BK/dongle.fastb 2>/dev/null
  [ "$_dgfb" = "${BID:-none}" ] || return 0
  # 리뷰 중간 2: 한 번 AP가 뜬 부팅은 뒤에 끊겨도(noap·reupmax 등) 실패로 세지 않는다
  echo "${BID:-none} ok" 2>/dev/null > $BK/dongle.fastb
  [ -f $DG_FASTF ] && { rm -f $DG_FASTF; log "동글: 바로 올린 부팅에 AP가 떠 실패 수를 지움"; }
  return 0
}
# 뒤에서 2초마다 120초: 순정 드라이버가 늦게 올라오면 메인을 깨워(dg_wake) dg_bcmlate_check가 바로 처리하게. 10초마다 순정 상태 한 줄을
# 단계 기록에 남긴다(부팅 40~46초 순정 AP 복구 창 확인용, 차 시험). 끝: 60번, 동글 사용 꺼짐, 부팅이 바뀜, 늦은 드라이버 봄
DG_BCMW_N=${DG_BCMW_N:-60}
dg_bcm_watch() {
  _dgbw=0
  while [ $_dgbw -lt $DG_BCMW_N ]; do
    [ -f $DG_ON ] || return 0
    if $BB grep -q "^$DG_BUILTIN_MOD " ${PROC:-/proc}/modules 2>/dev/null; then dg_wake; return 0; fi
    # 리뷰 낮음 2: settings(java)는 처음과 끝에만, 그 사이는 가벼운 줄(apon 없음)
    if [ $_dgbw = 0 ] || [ $_dgbw = $((DG_BCMW_N - 1)) ]; then dg_up_s; echo "$_dgu M stock10 $(dg_stock_line)" 2>/dev/null >> $DG_STEPF
    elif [ $((_dgbw % 5)) = 0 ]; then dg_up_s; echo "$_dgu M stock10 $(dg_stock_line light)" 2>/dev/null >> $DG_STEPF; fi
    _dgbw=$((_dgbw + 1))
    sleep 2 & wait $!
  done
  return 0
}
# 30초 점검(과 깨우기): 우리가 동글을 올린 부팅(이 부팅 표시 clean)에 순정 드라이버가 뒤늦게 올라오면 우리 AP를 멈추고 그 부팅은 실패.
# 내장으로 가지 않는다(88x2bu가 wlan0을 잡은 채 bcmdhd가 같은 이름을 쓰면 안 됨, 5차 원칙). 막힘 아님: 다음 시동에 다시 시도
dg_bcmlate_check() {
  case "$DG_ST" in wait|up|ok) ;; *) return 0 ;; esac
  dg_rm_now || return 0
  $BB grep -q "^$DG_BUILTIN_MOD " ${PROC:-/proc}/modules 2>/dev/null || return 0
  # 리뷰 중간 4: 지금 카플레이가 연결돼 있으면 끊지 않고 기록만 한다(다음 점검에 다시 봄: 연결이 끝나면 그때 멈춤)
  if [ "$(cat $CPN 2>/dev/null)" -gt 0 ] 2>/dev/null; then
    [ -f $W/dg.bcmlate.wait ] || { : > $W/dg.bcmlate.wait; log "동글: 순정 Wi-Fi 드라이버가 뒤늦게 올라왔지만 카플레이가 연결돼 있어 끊지 않음(연결이 끝나면 멈춤)"; }
    return 0
  fi
  stop_ours
  rm -f $DG_TRY $W/dg.bcmlate.wait; $BB sync
  dg_up_s; dg_step "bcm-late up=$_dgu"
  # 리뷰 중간 1: 동글이 아직 붙지 않았으면(꽂기 기다림) 장치 없는 88x2bu를 내리고 가드를 풀어 유선 프로젝션이라도 살린다(내장은 켜지 않음)
  if ! dg_seen && dg_present; then
    _dgrm=$RMMOD_SYS; [ -x "$_dgrm" ] || _dgrm="$BB rmmod"
    ( $_dgrm $DG_MOD ) </dev/null >/dev/null 2>&1 &
    _dgw=0
    while dg_present && [ $_dgw -lt ${DG_RMWAIT:-10} ]; do sleep 1 & wait $!; _dgw=$((_dgw + 1)); done
    if dg_present; then dg_step "bcm-late rmmod-nodev rc=fail"; else dg_step "bcm-late rmmod-nodev rc=0"; dg_guard_release; fi
  fi
  DG_ST=bcmlate; dg_state bcmlate "$DG_G"; dg_bst bcmlate
  log "동글: 순정 Wi-Fi 드라이버($DG_BUILTIN_MOD)가 뒤늦게 올라와 우리 AP를 멈춤(부팅 ${_dgu}초) — 이 부팅은 동글을 쓰지 않음, 다음 시동에 다시 시도"
  return 0
}
# 시각 기록(B3-1): 부팅마다 한 줄 "#<부팅 번호> start=<서비스 시작> ins=<insmod> probe=<붙음> ap=<AP> cp=<카플레이> way=fast|wait"(부팅 뒤 초).
# $BK/dongle.timeline 최근 10줄. 같은 부팅 값은 처음 것만(다시 잡힘·바꿔 꽂기는 기록하지 않음). 숫자만(개인정보 없음)
DG_TLF=${DG_TLF:-$BK/dongle.timeline}
dg_tl() {
  # 동글 길 부팅(DG_RUN) 또는 동글 사용이 켜진 서비스 시작 직후(dg_early·이른 가드, DG_RUN을 세우기 전)
  [ "$DG_RUN" = 1 ] || [ -f $DG_ON ] || return 0
  # 값은 숫자와 경로·목록용 글자만(이름·MAC이 들어갈 수 없게 공백 없음)
  case "$2" in ''|*[!0-9A-Za-z._/:,-]*) return 0 ;; esac
  _dgtn=0; [ -f $BK/dongle.bootn ] && read _dgtn < $BK/dongle.bootn 2>/dev/null; case "$_dgtn" in ''|*[!0-9]*) _dgtn=0 ;; esac
  _dgtw=wait; [ "$DG_FASTWAY" = 1 ] && _dgtw=fast
  _dgtc=; [ -f $W/dg.tl ] && read -r _dgtc < $W/dg.tl 2>/dev/null
  case "$_dgtc" in "$(dg_kv_bid) "*) ;; *) _dgtc="$(dg_kv_bid) start=${DG_SVCUP:--}" ;; esac
  case " $_dgtc " in *" $1="*) return 0 ;; esac
  _dgtc="$_dgtc $1=$2"
  echo "$_dgtc" 2>/dev/null > $W/dg.tl
  _dgtl="#$_dgtn ${_dgtc#* } way=$_dgtw"
  { $BB awk -v k="#$_dgtn " 'index($0, k) != 1' $DG_TLF 2>/dev/null | $BB tail -n 9; echo "$_dgtl"; } 2>/dev/null > $DG_TLF.tmp && $BB mv -f $DG_TLF.tmp $DG_TLF 2>/dev/null
  return 0
}
# 베타 3(메인 요청 11-23, tcc803x 꽂아 둔 채 시동 nobind 원인 가르기): 커널이 USB 장치를 처음 잡은 커널 초(dmesg "new high-speed USB device"
# 첫 줄, 정수)와 그 줄 수, 순정 AOA 첫 줄의 시각(logcat 시:분:초 → HHMMSS 숫자)을 시각 기록에 더한다. 시각과 개수만(장치 이름·번호 없음).
# 부르는 곳: dg_start(가드 뒤)와 동글이 처음 붙었을 때. 같은 부팅 값은 처음 것만(dg_tl)
dg_tl_kaoa() {
  _dgkk=$(dmesg 2>/dev/null | $BB awk '/new high-speed USB device/ { n++; if (n == 1 && match($0, /\[ *[0-9]+\./)) { t = substr($0, RSTART + 1, RLENGTH - 2); gsub(/ /, "", t) } } END { print (n ? t + 0 : "-") " " n + 0 }' 2>/dev/null)
  case "${_dgkk%% *}" in ''|*[!0-9]*) ;; *) dg_tl kusb ${_dgkk%% *}; dg_tl kusbn ${_dgkk#* } ;; esac
  _dgka=$(logcat -d -v time 2>/dev/null | $BB awk '/startAccessory|locateGoogleDevice|UsbAccesory|UsbTransport : init|mUsbTransport\.init\(\) ret/ { t = $2; gsub(/[^0-9]/, "", t); print substr(t, 1, 6); exit }' 2>/dev/null)
  case "$_dgka" in [0-9][0-9][0-9][0-9][0-9][0-9]) dg_tl aoa1 $_dgka ;; esac
  return 0
}
# --- 베타 3 B3-9(dongle.md 4-27, 메인 결정 11-23): tcc803x 꽂아 둔 채 시동 → 가드보다 순정 AOA가 먼저 → nobind ---
# a) 동글이 붙어 AP가 뜬 부팅에 그 버스 번호·루트 허브의 컨트롤러 경로(마지막 두 마디)·같은 플랫폼의 OHCI 짝 버스를 $BK/dongle.gbus에 남긴다
#    "<버스> <경로> <짝 버스|-> <짝 경로|->". 다음 부팅 이른 가드(+4초)가 같은 경로일 때만 그 버스(와 짝)를 미리 막는다. 바뀌면 고쳐 씀.
#    모뎀 등 tcc-ehci 컨트롤러 버스는 기록하지도 막지도 않는다(dg_bus_modem)
DG_GBUSF=${DG_GBUSF:-$BK/dongle.gbus}
# 루트 허브 usbN의 컨트롤러 경로 마지막 두 마디(예: 11980000.ehci/usb4). 못 읽으면 빈 값
dg_hub_path() { _dghp=$(cd -P "$USB_SYS/usb$1" 2>/dev/null && pwd -P); [ -n "$_dghp" ] || return 1; _dghq=${_dghp%/*}; echo "${_dghq##*/}/${_dghp##*/}"; }
dg_bus_modem() { case "$(dg_hub_path $1)" in *tcc-ehci*) return 0 ;; esac; return 1; }
# 기록된 버스가 지금도 같은 컨트롤러면 0과 DG_RBUS·DG_RPAIR
dg_gbus_rec() {
  DG_RBUS=; DG_RPAIR=
  [ -f $DG_GBUSF ] || return 1
  _dgr1=; _dgr2=; _dgr3=; _dgr4=; read _dgr1 _dgr2 _dgr3 _dgr4 < $DG_GBUSF 2>/dev/null
  case "$_dgr1" in ''|*[!0-9]*) return 1 ;; esac
  [ -n "$_dgr2" ] && [ "$(dg_hub_path $_dgr1)" = "$_dgr2" ] || return 1
  dg_bus_modem $_dgr1 && return 1
  DG_RBUS=$_dgr1
  case "$_dgr3" in ''|*[!0-9]*) ;; *) [ "$(dg_hub_path $_dgr3)" = "$_dgr4" ] && ! dg_bus_modem $_dgr3 && DG_RPAIR=$_dgr3 ;; esac
  return 0
}
dg_gbus_pair_arm() {
  [ -n "$DG_RPAIR" ] || return 0
  [ "$(dg_n3 $DG_RPAIR)" = "$DG_GBUS" ] && return 0
  _dgpk=$DG_GBUS; DG_GBUS=$(dg_n3 $DG_RPAIR); dg_guard_arm; DG_GBUS=$_dgpk
  dg_tl gpair $DG_RPAIR
  return 0
}
# 정식 2차 리뷰 L7: 돌려주는 값 — 0: 기록함(또는 같은 기록이 이미 있음, 모뎀 버스라 적을 것 없음), 1: 아직 모름(동글·버스·경로를 못 읽음).
# dg_car는 0일 때만 이 부팅 표시(dg.gbsaved)를 적는다(못 읽은 부팅에 다시 시도하게)
dg_gbus_save() {
  [ -n "$DG_USBDEV" ] || dg_usb
  [ -n "$DG_USBDEV" ] || return 1
  us_rd $DG_USBDEV/busnum; _dgsb=$_ur; case "$_dgsb" in ''|*[!0-9]*) return 1 ;; esac
  dg_bus_modem $_dgsb && return 0
  _dgxp=$(dg_hub_path $_dgsb); [ -n "$_dgxp" ] || return 1
  # 짝 찾기(정식 C1 ⓑ): ① 컨트롤러 이름에서 ehci를 ohci로 바꾼 이름이 같은 12Mbps 루트 허브(tcc803x ehci-mux.0 ↔ ohci-mux.0,
  # 베타 3 #522·#557 허브 표. 예전 규칙은 첫 마디 ehci-mux≠ohci-mux라 짝을 못 찾음) ② 같은 플랫폼(첫 마디가 같은 주소)의 12Mbps 루트 허브.
  # 주소가 다른 짝(11a00000.ehci ↔ 11a80000.ohci)은 근거가 없어 묶지 않는다(남의 버스를 막지 않게)
  _dgsa=${_dgxp%%/*}; _dgxq=-; _dgxr=-
  _dgst=; case "$_dgsa" in *ehci*) _dgst="${_dgsa%%ehci*}ohci${_dgsa#*ehci}" ;; esac
  if [ -n "$_dgst" ]; then
    for _dgsh in $USB_SYS/usb[0-9]*; do
      _dgsn=${_dgsh##*/usb}; [ "$_dgsn" = "$_dgsb" ] && continue
      case "$_dgsn" in ''|*[!0-9]*) continue ;; esac
      us_rd $_dgsh/speed; [ "$_ur" = 12 ] || continue
      _dgsq=$(dg_hub_path $_dgsn)
      [ "${_dgsq%%/*}" = "$_dgst" ] && ! dg_bus_modem $_dgsn && { _dgxq=$_dgsn; _dgxr=$_dgsq; break; }
    done
  fi
  _dgsa=${_dgsa%%.*}
  [ "$_dgxq" = - ] && for _dgsh in $USB_SYS/usb[0-9]*; do
    _dgsn=${_dgsh##*/usb}; [ "$_dgsn" = "$_dgsb" ] && continue
    case "$_dgsn" in ''|*[!0-9]*) continue ;; esac
    us_rd $_dgsh/speed; [ "$_ur" = 12 ] || continue
    _dgsq=$(dg_hub_path $_dgsn); _dgsc=${_dgsq%%/*}; _dgsc=${_dgsc%%.*}
    [ -n "$_dgsc" ] && [ "$_dgsc" = "$_dgsa" ] && ! dg_bus_modem $_dgsn && { _dgxq=$_dgsn; _dgxr=$_dgsq; break; }
  done
  _dgsl="$_dgsb $_dgxp $_dgxq $_dgxr"
  _dgso=; [ -f $DG_GBUSF ] && _dgso=$(cat $DG_GBUSF 2>/dev/null)
  [ "$_dgso" = "$_dgsl" ] && return 0
  echo "$_dgsl" 2>/dev/null > $DG_GBUSF.tmp && $BB mv -f $DG_GBUSF.tmp $DG_GBUSF 2>/dev/null || return 1
  log "동글: 다음 시동에 미리 막을 버스를 기록함(버스 $_dgsb, 짝 $_dgxq)"
  return 0
}
# b) 포트 전원 껐다 켜기: 후보 파일 중 있는 것(값이 on/off 또는 1/0일 때만). 한 부팅에 한 번, 드라이버가 붙지 않았을 때만.
#    전후 상태(값·동글 보임·붙음)는 단계 기록에 sync로. MICOM 길·sys.boot.vbus는 쓰지 않는다(sysfs 파일만)
DG_VBUSC=${DG_VBUSC:-/sys/devices/dwc_otg/vbus /sys/devices/11980000.dwc_otg/vbus}
dg_vbus_path() { for _dgvp in $DG_VBUSC; do [ -f "$_dgvp" ] && { echo "$_dgvp"; return 0; }; done; return 1; }
# 단계 기록이 끝났어도 전원 껐다 켜기 전후는 늘 남긴다(차에서 처음 하는 동작, sync)
dg_vstep() { dg_up_s; echo "$_dgu M $*" 2>/dev/null >> $DG_STEPF; $BB sync; }
dg_vbus_cycle() {
  dg_seen && return 1
  _dbf=$(dg_vbus_path) || return 1
  _dbv=; read _dbv < "$_dbf" 2>/dev/null
  case "$_dbv" in on) _dbo=off; _dbn2=on ;; 1) _dbo=0; _dbn2=1 ;; *) dg_vstep "vbus-skip val=${_dbv:-?}"; return 1 ;; esac
  dg_up_s; echo "${BID:-none} $_dgu" 2>/dev/null > $W/dg.vbus.done
  dg_usb; dg_vstep "vbus-before path=${_dbf#/sys/devices/} val=$_dbv usb=$DG_USB"; $BB sync
  log "동글: 드라이버가 붙지 않아(nobind) 포트 전원을 한 번 껐다 켬(${_dbf#/sys/devices/})"
  echo $_dbo 2>/dev/null > "$_dbf" || { dg_vstep "vbus-off rc=fail"; log "동글: 포트 전원을 끄지 못함 — 한 번 뺐다 꽂으라고 안내"; return 1; }
  sleep 2 & wait $!
  # 다시 켜기 전에 가드 자리를 다시 막는다(새 번호가 막힌 자리로 들어가게)
  dg_guard_arm quiet
  # 리뷰 M2: 다시 켜기는 3번까지 쓰고 읽어 확인한다
  _dbk=0; _dbw=
  while [ $_dbk -lt 3 ]; do
    echo $_dbn2 2>/dev/null > "$_dbf"; read _dbw < "$_dbf" 2>/dev/null
    [ "$_dbw" = "$_dbn2" ] && break
    _dbk=$((_dbk + 1)); sleep 1 & wait $!
  done
  dg_up_s; dg_usb; dg_vstep "vbus-after val=${_dbw:-?} usb=$DG_USB"; $BB sync
  dg_tl vbus $_dgu
  [ "$_dbw" = "$_dbn2" ] || { log "동글: 포트 전원을 다시 켰는지 확인하지 못함(값 ${_dbw:-?})"; return 1; }
  return 0
}
# --- B3-9b 다시 붙이기 사다리(소유자 결정 11-23: 베타 3는 네 방법을 순서대로 해 보고 기록, 정식판에서 고름) ---
# 단계: 1 authorized 0→1, 2 장치 드라이버(usb) unbind/bind, 3 USB 리셋(도우미 bin/kp-usbreset, 우리 폴더에 만든 노드), 4 포트 전원 껐다 켜기.
# 단계마다 DG_LAD_WAIT초(5)까지 1초씩 붙음(dg_seen)을 보고, 붙으면 거기서 멈춘다. 안전:
#  - 동글 USB 장치(허용 동글)에만, 모뎀(tcc-ehci) 버스면 하지 않음, 드라이버가 붙은 뒤에는 하지 않음, 한 부팅에 한 차례
#  - 단계 앞뒤로 $BK/dongle.ladder("<부팅 id> <단계> start|done", sync)와 단계 기록 표시 줄. 단계 도중 재부팅되면 다음 부팅 dg_start가
#    보고(dg_ladder_crashcheck) $BK/dongle.noladder를 남겨 그 뒤로 사다리를 끈다(차주가 동글 사용을 껐다 켜면 풂). 그때는 막지 않고 안내만
# 기록: 시각 기록 lad=<붙은 단계|0>, l1~l4=ok|no|skip|err(걸린 초), 비공개 $BK/dongle.ladlog(최근 20줄), 공개 리포트는 한 줄(dg_ladder_pub)
DG_LAD_WAIT=${DG_LAD_WAIT:-5}
DG_LADF=${DG_LADF:-$BK/dongle.ladder}
DG_LADLOG=${DG_LADLOG:-$BK/dongle.ladlog}
DG_USBRESET=${DG_USBRESET:-$APP/bin/kp-usbreset}
DG_USBDRV=${DG_USBDRV:-${USB_SYS%/devices}/drivers/usb}
DG_88DRV=${DG_88DRV:-${USB_SYS%/devices}/drivers/rtl88x2bu}
DG_LADDER_MSG="동글을 다시 연결하는 중입니다. 잠시만 기다려 주세요."
# 리뷰 M2·M3: 이번 부팅에 다시 붙이기 단계 도중(start)이면 그 단계를 되돌린다(1 authorized=1, 2 bind, 4 포트 전원 켬). 포트 전원은 단계와 상관없이
# 이번 부팅에 껐던 기록(dg.vbus.done)이 있고 지금 꺼져 있으면 켠다. 화면 문구가 "다시 연결하는 중"에 굳지 않게 dg.ladder run을 fail로.
# 부르는 곳: stop_all(TERM·업데이트), 서비스 시작(같은 부팅에 서비스가 다시 시작)
dg_ladder_restore() {
  _dgr1=; _dgr2=; _dgr3=; _dgr4=; [ -f $DG_LADF ] && read _dgr1 _dgr2 _dgr3 _dgr4 < $DG_LADF 2>/dev/null
  if [ -n "$_dgr1" ] && [ "$_dgr1" = "${BID:-none}" ] && [ "$_dgr3" = start ]; then
    case "$_dgr2" in
      1) [ -d "$_dgr4" ] && { echo 1 > $_dgr4/authorized; } 2>/dev/null ;;
      2) [ -d "$_dgr4" ] && { echo "${_dgr4##*/}" > $DG_USBDRV/bind; } 2>/dev/null ;;
    esac
    rm -f $DG_LADF; $BB sync
    log "동글: 다시 붙이기 ${_dgr2}단계 도중에 멈춰 되돌림($1)"
  fi
  _dgrv=; [ -f $W/dg.vbus.done ] && read _dgrv _dgrx < $W/dg.vbus.done 2>/dev/null
  if [ -n "$_dgrv" ] && [ "$_dgrv" = "${BID:-none}" ] && _dgrf=$(dg_vbus_path); then
    _dgrw=; read _dgrw < "$_dgrf" 2>/dev/null
    case "$_dgrw" in off) echo on 2>/dev/null > "$_dgrf"; log "동글: 꺼진 포트 전원을 다시 켬($1)" ;; 0) echo 1 2>/dev/null > "$_dgrf"; log "동글: 꺼진 포트 전원을 다시 켬($1)" ;; esac
  fi
  _dgrl=; [ -f $W/dg.ladder ] && read _dgrl _dgrs < $W/dg.ladder 2>/dev/null
  [ "$_dgrl" = "${BID:-none}" ] && [ "$_dgrs" = run ] && echo "${BID:-none} fail" 2>/dev/null > $W/dg.ladder
  return 0
}
# 지난 부팅이 다시 붙이기 단계 도중에 끝났으면(재부팅·시동 끔): 리뷰 L6 — 시동 끔과 멈춤을 가를 수 없어, 처음 한 번은 다음 부팅에 사다리를
# 다시 허용하고(시동 끔은 흔함), 같은 일이 잇달아 두 번이면 끈다(dongle.noladder, 동글 사용을 껐다 켜면 풂). 막지는 않는다.
# 같은 부팅 기록(서비스만 다시 시작)은 되돌리기만 한다
dg_ladder_crashcheck() {
  dg_ladder_restore start
  [ -f $DG_LADF ] || return 0
  _dgc1=; _dgc2=; _dgc3=; read _dgc1 _dgc2 _dgc3 _dgc4 < $DG_LADF 2>/dev/null
  [ "$_dgc1" = "${BID:-none}" ] && return 0
  if [ "$_dgc3" = start ]; then
    _dgcn=0; [ -f $BK/dongle.ladcrash ] && read _dgcn < $BK/dongle.ladcrash 2>/dev/null; case "$_dgcn" in ''|*[!0-9]*) _dgcn=0 ;; esac
    _dgcn=$((_dgcn + 1)); echo $_dgcn 2>/dev/null > $BK/dongle.ladcrash
    rm -f $DG_TRY $BK/dongle.noprobe
    if [ $_dgcn -ge 2 ]; then
      : 2>/dev/null > $BK/dongle.noladder
      log "동글: 다시 붙이기 도중에 끝난 부팅이 잇달아 ${_dgcn}번 — 다시 붙이기를 끔(동글 사용을 껐다 켜면 다시 함), 막지는 않음"
    else
      log "동글: 지난 부팅이 다시 붙이기 ${_dgc2}단계 도중에 끝남(시동 끔일 수 있음) — 이번에는 다시 허용, 잇달아 또 그러면 끔"
    fi
    $BB sync
    echo "$(date '+%m-%d_%H:%M' 2>/dev/null) crash step=$_dgc2 n=$_dgcn" 2>/dev/null >> $DG_LADLOG
  fi
  rm -f $DG_LADF
  return 0
}
dg_lad_mark() { echo "${BID:-none} $1 $2 ${DG_USBDEV:--}" 2>/dev/null > $DG_LADF; $BB sync; dg_vstep "lad-$2 step=$1"; }
# 단계 뒤 기다리며 붙음을 본다. 0 붙음
dg_lad_wait() { _dglw=0; while [ $_dglw -lt $DG_LAD_WAIT ]; do dg_seen && return 0; sleep 1 & wait $!; _dglw=$((_dglw + 1)); done; dg_seen; }
# 단계 하나: $1 번호. 결과를 _dglr(ok|no|skip|err)에
dg_lad_step() {
  _dglr=no; dg_up_s; _dgl0=$_dgu
  case "$1" in
    1) [ -w $DG_USBDEV/authorized ] || { _dglr=skip; return 0; }
       dg_lad_mark 1 start
       { echo 0 > $DG_USBDEV/authorized; } 2>/dev/null || _dglr=err
       sleep 1 & wait $!
       { echo 1 > $DG_USBDEV/authorized; } 2>/dev/null || _dglr=err ;;
    2) [ -w $DG_USBDRV/unbind ] && [ -w $DG_USBDRV/bind ] || { _dglr=skip; return 0; }
       dg_lad_mark 2 start
       { echo "${DG_USBDEV##*/}" > $DG_USBDRV/unbind; } 2>/dev/null || _dglr=err
       sleep 1 & wait $!
       { echo "${DG_USBDEV##*/}" > $DG_USBDRV/bind; } 2>/dev/null || _dglr=err ;;
    3) # 정식 C1 ⓓ(베타 3: 3단계가 5/5 skip): zip을 풀 때 실행 권한이 빠질 수 있다(함께 넣은 busybox와 같음, 23행).
       # 우리 패키지의 도우미일 때만 한 번 755로 되살린다(실패해도 조용히). skip 이유는 기록에 남긴다(nox·nonum·seen)
       [ "$DG_USBRESET" = "$APP/bin/kp-usbreset" ] && [ -f "$DG_USBRESET" ] && [ ! -x "$DG_USBRESET" ] && chmod 755 "$DG_USBRESET" 2>/dev/null
       [ -x "$DG_USBRESET" ] || { _dglr=skip-nox; return 0; }
       us_rd $DG_USBDEV/busnum; _dglb=$_ur; us_rd $DG_USBDEV/devnum; _dgln=$_ur
       # 정식 C1 stub이 찾음: 둘을 붙여 보면 하나만 비어도(예: 버스 4·번호 없음 → "4") 지나간다. 따로 본다
       case "$_dglb" in ''|*[!0-9]*) _dglr=skip-nonum; return 0 ;; esac
       case "$_dgln" in ''|*[!0-9]*) _dglr=skip-nonum; return 0 ;; esac
       # 노드는 가드(/dev/bus/usb)와 겹치지 않게 우리 작업 폴더에 따로 만든다(문자 189, 부 번호 (버스-1)×128+(번호-1))
       _dglk=$W/kp-usbnode; rm -f $_dglk
       $BB mknod $_dglk c 189 $(( (_dglb - 1) * 128 + _dgln - 1 )) 2>/dev/null || mknod $_dglk c 189 $(( (_dglb - 1) * 128 + _dgln - 1 )) 2>/dev/null || { _dglr=err; return 0; }
       # dongle-180(3.18.24 소스): 88x2bu에는 pre_reset·post_reset이 없어 드라이버가 붙어 있을 때 리셋하면 붙은 채 뽑기와 같다 → 붙지 않았을 때만
       dg_seen && { rm -f $_dglk; _dglr=skip-seen; return 0; }
       # 리셋이 실패해 새 번호로 다시 잡히면 그 자리도 막혀 있어야 한다(순정 AOA가 닿지 않게)
       dg_guard_arm quiet
       dg_lad_mark 3 start
       # 도우미가 멈춰도 서비스는 가게 뒤에서 돌리고 DG_LAD_WAIT초까지만 기다린다
       # 도우미 약속(11-23 확정): 성공은 표준 출력 "ok"·종료 0, 실패는 "err <errno> open|ioctl"·종료 errno, 인자 오류는 종료 2·출력 없음.
       # 종료 2가 open의 ENOENT와 겹치므로 종료 0과 출력 "ok"를 함께 보고, 출력 한 줄은 그대로(공백만 _로) 기록에 남긴다
       rm -f $W/kp-usbreset.out
       ( "$DG_USBRESET" $_dglk ) </dev/null 2>/dev/null > $W/kp-usbreset.out &
       _dglp=$!; _dglw=0; while [ $_dglw -lt $DG_LAD_WAIT ] && [ -d ${PROC:-/proc}/$_dglp ]; do sleep 1 & wait $!; _dglw=$((_dglw + 1)); done
       _dglc=0
       if [ -d ${PROC:-/proc}/$_dglp ]; then kill $_dglp 2>/dev/null; _dglc=timeout; else wait $_dglp 2>/dev/null; _dglc=$?; fi
       _dglo=; read -r _dglo < $W/kp-usbreset.out 2>/dev/null; rm -f $W/kp-usbreset.out
       _dglo=$(echo "$_dglo" | $BB awk '{ gsub(/[^0-9A-Za-z ]/, ""); gsub(/ /, "_"); print substr($0, 1, 24) }' 2>/dev/null)
       { [ "$_dglc" = 0 ] && [ "$_dglo" = ok ]; } || _dglr=err
       dg_tl l3o "${_dglo:-none}-$_dglc"
       rm -f $_dglk
       # 리셋 뒤 nobind였던 인터페이스는 저절로 다시 프로브되지 않는다 → 드라이버 bind에 인터페이스 이름(4-1:1.0 꼴)을 써서 프로브를 일으킨다
       for _dgli2 in $DG_USBDEV/*:*; do
         [ -d "$_dgli2" ] || continue
         us_drv $_dgli2/driver; [ -z "$_ud" ] || [ "$_ud" = "?" ] || continue
         { echo "${_dgli2##*/}" > $DG_88DRV/bind; } 2>/dev/null
       done ;;
    4) dg_vbus_path >/dev/null || { _dglr=skip; return 0; }
       # 리뷰 M2: vbus 파일은 dwc_otg 컨트롤러 포트 것이다. 동글이 그 컨트롤러 버스에 있을 때만(다른 포트 전원을 끄지 않게)
       us_rd $DG_USBDEV/busnum
       case "$(dg_hub_path $_ur)" in *dwc_otg*) ;; *) dg_vstep "vbus-skip notdwc"; _dglr=skip; return 0 ;; esac
       dg_lad_mark 4 start
       dg_vbus_cycle || _dglr=err ;;
  esac
  dg_lad_wait && _dglr=ok
  dg_lad_mark $1 done
  dg_up_s; _dglt=$((_dgu - _dgl0))
  return 0
}
dg_ladder() {
  [ -f $BK/dongle.noladder ] && { log "동글: 지난번 다시 붙이기 도중 재부팅되어 다시 붙이기를 하지 않음"; return 1; }
  dg_seen && return 1
  [ -n "$DG_USBDEV" ] || dg_usb
  [ "$DG_USB" = ok ] && [ -n "$DG_USBDEV" ] || return 1
  us_rd $DG_USBDEV/busnum; dg_bus_modem "$_ur" && { log "동글: 모뎀 버스라 다시 붙이기를 하지 않음"; return 1; }
  echo "${BID:-none} run" 2>/dev/null > $W/dg.ladder; dg_status_push
  log "동글: 드라이버가 붙지 않아(nobind) 다시 붙이기를 차례로 해 봄"
  _dgla=0; _dglsum=
  for _dgli in 1 2 3 4; do
    dg_seen && { _dgla=$_dgli; break; }
    dg_lad_step $_dgli
    dg_tl l$_dgli "$_dglr${_dglt:+-$_dglt}"
    _dglsum="$_dglsum $_dgli=$_dglr"
    _dglt=
    [ "$_dglr" = ok ] && { _dgla=$_dgli; break; }
  done
  dg_tl lad $_dgla
  echo "$(date '+%m-%d_%H:%M' 2>/dev/null)$_dglsum" 2>/dev/null >> $DG_LADLOG
  { $BB tail -n 20 $DG_LADLOG > $DG_LADLOG.tmp && $BB mv -f $DG_LADLOG.tmp $DG_LADLOG; } 2>/dev/null
  rm -f $DG_LADF $BK/dongle.ladcrash
  echo "${BID:-none} $_dgla" 2>/dev/null > $BK/dongle.ladres
  if [ $_dgla -gt 0 ]; then echo "${BID:-none} ok" 2>/dev/null > $W/dg.ladder; log "동글: 다시 붙이기 ${_dgla}단계에서 붙음($_dglsum)"; dg_wake; dg_status_push; return 0; fi
  echo "${BID:-none} fail" 2>/dev/null > $W/dg.ladder
  log "동글: 다시 붙이기가 모두 안 됨($_dglsum) — 한 번 뺐다 꽂으라고 안내"
  return 1
}
# B3-9 진단 기록(dongle.md 4-27 (3) 여덟 가지, 비공개 시각 기록·커널 줄 사본). 시각·경로·개수·속성만(MAC·이름·문자열 없음).
#  start: 1 서비스 시작(1/100초) 2 루트 허브 표 "버스:속도:경로:폴더있음" 3 커널 USB 줄 사본($BK/dongle.kusb, 걸러 냄)
#         4 순정 AOA 줄 수와 첫·끝 시각, 시계 짝(HHMMSS-uptime) 6 vbus 후보 파일·값, sys.boot.vbus·sys.usb.mode
#  probe: 7 동글 속도 8 떼어짐 → 새 번호 간격(1/100초)·순정 resetUSB·SYS_VBUS 줄 수
#  nobind: 5 authorized·bConfigurationValue·인터페이스 드라이버·마지막 kp-protect 프로브 결과
DG_KUSBF=${DG_KUSBF:-$BK/dongle.kusb}
dg_tl_diag() {
  case "$1" in
  start)
    [ -n "$DG_SVCUPC" ] && dg_tl startc $DG_SVCUPC
    _dgh=
    for _dghh in $USB_SYS/usb[0-9]*; do
      _dghn=${_dghh##*/usb}; case "$_dghn" in ''|*[!0-9]*) continue ;; esac
      us_rd $_dghh/speed; _dghs=${_ur:-?}; _dghx=$(dg_hub_path $_dghn); _dghd=n; [ -d $DG_USBFS/$(dg_n3 $_dghn) ] && _dghd=y
      _dgh="$_dgh,$_dghn:$_dghs:${_dghx:-?}:$_dghd"
    done
    [ -n "$_dgh" ] && dg_tl hubs "${_dgh#,}"
    dmesg 2>/dev/null | $BB awk '/new USB bus registered|USB device number|USB disconnect|kp-protect: probe/ { sub(/, assigned bus number/, " bus"); print }' 2>/dev/null | $BB tail -n 40 2>/dev/null > $DG_KUSBF.tmp \
      && $BB mv -f $DG_KUSBF.tmp $DG_KUSBF 2>/dev/null; rm -f $DG_KUSBF.tmp
    _dgaa=$(logcat -d -v time 2>/dev/null | $BB awk '/USB_DEVICE_ATTACHED|initSession|UsbTransport : init|mUsbTransport\.init\(\) ret|startAccessory|locateGoogleDevice|UsbAccesory/ { n++; t = $2; gsub(/[^0-9]/, "", t); t = substr(t, 1, 6); if (n == 1) f = t; l = t } END { print n + 0 " " (n ? f : "-") " " (n ? l : "-") }' 2>/dev/null)
    set -- $_dgaa; dg_tl aoas ${1:-0}; [ "$2" != - ] && dg_tl aoaf "$2"; [ "$3" != - ] && dg_tl aoal "$3"
    dg_up_s; dg_tl clk "$(date '+%H%M%S' 2>/dev/null)-$_dgu"
    _dgvb=none; for _dgvp in $DG_VBUSC; do [ -f "$_dgvp" ] && { _dgvq=; read _dgvq < "$_dgvp" 2>/dev/null; _dgvb="${_dgvp#/sys/devices/}:$(echo "$_dgvq" | $BB awk '{ gsub(/[^0-9a-z]/, ""); print substr($0, 1, 8) }')"; break; }; done
    dg_tl vbusf "$_dgvb"
    _dgvx=$(getprop sys.boot.vbus 2>/dev/null | $BB awk '{ gsub(/[^0-9a-z]/, ""); print substr($0, 1, 8) }'); dg_tl pvbus "${_dgvx:--}"
    _dgvy=$(getprop sys.usb.mode 2>/dev/null | $BB awk '{ gsub(/[^0-9a-z_]/, ""); print substr($0, 1, 12) }'); dg_tl umode "${_dgvy:--}"
    ;;
  probe)
    [ -n "$DG_USBDEV" ] || dg_usb
    [ -n "$DG_USBDEV" ] && { us_rd $DG_USBDEV/speed; dg_tl speed "${_ur:--}"; }
    _dgrg=$(dmesg 2>/dev/null | $BB awk '{ if (match($0, /\[ *[0-9]+\.[0-9]+\]/)) { t = substr($0, RSTART + 1, RLENGTH - 2) + 0 } else next }
      /USB disconnect/ { d = t } /new (high|full)-speed USB device number/ { if (d != "") { g = int((t - d) * 100); d = "" } }
      END { print (g == "" ? "-" : g) }' 2>/dev/null)
    dg_tl rgap "${_dgrg:--}"
    _dgrs=$(logcat -d 2>/dev/null | $BB awk '/resetUSB|SYS_VBUS_OFF_ON_C/ { n++ } END { print n + 0 }' 2>/dev/null); dg_tl rst "${_dgrs:-0}"
    ;;
  nobind)
    [ -n "$DG_USBDEV" ] || dg_usb
    [ -n "$DG_USBDEV" ] || return 0
    us_rd $DG_USBDEV/authorized; dg_tl nbauth "${_ur:--}"
    us_rd $DG_USBDEV/bConfigurationValue; dg_tl nbcfg "${_ur:--}"
    _dgnd=
    for _dgni in $DG_USBDEV/*:*; do [ -d "$_dgni" ] || continue; us_drv $_dgni/driver; _dgnd="$_dgnd,${_ud:--}"; done
    dg_tl nbdrv "$(echo "${_dgnd#,}" | $BB awk '{ gsub(/[^0-9A-Za-z_,-]/, ""); print substr($0, 1, 40) }')"
    _dgnp=$(dmesg 2>/dev/null | $BB awk '/kp-protect: probe ret=/ { l = $0 } END { if (l == "") print "-"; else { sub(/.*probe ret=/, "", l); gsub(/ step=/, "/", l); gsub("[^0-9/-]", "", l); print l } }' 2>/dev/null)
    dg_tl nbprobe "${_dgnp:--}"
    ;;
  esac
  return 0
}
# 30초 점검(req_tick)마다: 올리기 결과 보기(dg_watch), 그다음 동글 차 속성 맞추기(DG-9 dg_prop_sync)
dg_tick() {
  [ "$DG_RUN" = 1 ] || return 0
  case "$DG_ST" in wait|up) dg_watch ;; esac
  # 리뷰 높음 1 근거: 순정 드라이버를 내린 부팅에 그것이 다시 올라오면(순정 Wi-Fi 서비스 등) 한 번만 기록(리포트가 읽음). 우리는 다시 내리지 않는다
  if [ ! -f $W/dongle.bcmback ] && dg_rm_now && $BB grep -q "^$DG_BUILTIN_MOD " ${PROC:-/proc}/modules 2>/dev/null; then
    : 2>/dev/null > $W/dongle.bcmback; log "동글: 이 부팅에 내린 순정 Wi-Fi 드라이버($DG_BUILTIN_MOD)가 다시 올라옴(우리가 올린 것 아님)"
  fi
  dg_bcmlate_check
  dg_oui_tick
  dg_ident_tick
  dg_plug_tick
  dg_guard_tick
  dg_pull_tick
  dg_reup_close
  dg_plugagain_tick
  dg_modwait_tick
  case "$DG_ST" in up|ok) dg_model_tick ;; esac
  dg_prop_sync
  return 0
}
# 결과를 보고 막거나, 다 올라와 버틴 뒤 시도 기록을 지운다
dg_watch() {
  if [ "$DG_ST" = wait ]; then
    dg_rc
    # insmod가 아직 돌아오지 않음(올리다 멈춤 포함): 시도 기록을 그대로 두고 기다린다(다음 부팅에 막힘)
    [ -n "$DG_RC" ] || return 0
    [ "$DG_RC" = 0 ] || { dg_to_builtin failboot "동글 드라이버 insmod 실패(rc $DG_RC)" && [ "${DG_IN_START:-0}" = 0 ] && take_wlan0; return 0; }
    DG_ST=up; dg_state up "$DG_G"; log "동글 드라이버가 올라감($DG_G)"
    # 시험판 4 리뷰 낮음 7: insmod가 DG_WAIT보다 늦게 끝났으면 여기서 꽂기 안내(다음 부팅 판정은 "늦음"이라 막는 쪽)
    _dgsg=; [ -f $W/dgstage ] && read _dgsg < $W/dgstage 2>/dev/null
    [ "$_dgsg" = insmod ] && { dg_stage plug; dg_step "prompt-late rc=$DG_RC"; }
    # DG-7: 삭제 때 우리가 올린 것만 내리게 기록
    echo "$BID $DG_MOD" 2>/dev/null > $BK/dongle.mod
  fi
  dg_live || { dg_to_builtin failboot "동글 드라이버가 사라짐" && [ "${DG_IN_START:-0}" = 0 ] && take_wlan0; return 0; }
  _dgt=; [ -f $DG_TRY ] && read _dgb _dgg _dgt < $DG_TRY 2>/dev/null
  case "$_dgt" in ''|*[!0-9]*) _dgt=0 ;; esac
  kp_up
  # 시험판 4: 버틴 시간은 동글이 우리 드라이버에 붙고 우리 AP가 뜬 때부터 센다(늦게 꽂아 프로브·AP 때 멈춰도 다음 부팅이 막도록).
  # 아직 붙지 않았거나 AP가 없으면 시도 기록을 그대로 둔다(그 부팅이 동글 없이 끝나면 다음 부팅의 dg_step_noprobe가 가림)
  if [ "$DG_OK_HAPD" = 1 ]; then
    _dgt=; _dghb=; [ -f $W/hapd.up ] && read _dgt _dghb < $W/hapd.up 2>/dev/null
    case "$_dgt" in ''|*[!0-9]*) _dgt= ;; esac
    dg_seen || return 0
    # 리뷰 중간 2: 이 부팅에 우리 hostapd를 한 번도 띄우려 하지 않았으면(모드 기다림 등) 붙은 때부터 센다
    _dghx=; [ -f $W/hapd.try ] && read _dghx < $W/hapd.try 2>/dev/null
    if [ "$_dghx" != "${BID:-none}" ]; then
      _dgt=; _dgsx=; [ -f $W/dongle.seen1 ] && read _dgsx _dgt < $W/dongle.seen1 2>/dev/null
      case "$_dgt" in ''|*[!0-9]*) return 0 ;; esac; [ "$_dgsx" = "${BID:-none}" ] || return 0
      _dghb=${BID:-none}
    fi
    [ "$_dghx" != "${BID:-none}" ] || running "hostapd $CONF" || return 0
    # 같은 부팅에 서비스가 다시 시작해 AP 시작 시각을 잃었으면(dg_start가 지움, hostapd는 그대로) 지금부터 센다
    if [ "$_dghx" = "${BID:-none}" ] && { [ -z "$_dgt" ] || [ "$_dghb" != "${BID:-none}" ]; }; then
      _dgt=${_U:-0}; echo "$_dgt ${BID:-none}" 2>/dev/null > $W/hapd.up; return 0
    fi
  fi
  # 시험판 6(리뷰 중간 1): AP가 뜬 뒤 동글이 다시 잡혔으면(AP를 다시 띄우는 중) 여기서 닫지 않는다(dg_reup_close가 닫음)
  _dgw5=; _dgw6=; [ -f $W/dgreplug ] && read _dgw5 _dgw6 < $W/dgreplug 2>/dev/null
  if [ "$_dgw5" = "${BID:-none}" ] && case "$_dgw6$_dgt" in *[!0-9]*|'') false ;; *) [ "$_dgw6" -gt "$_dgt" ] ;; esac; then return 0; fi
  if [ -n "$_U" ] && [ $((_U - _dgt)) -ge ${DG_OK_SEC:-60} ]; then
    rm -f $DG_TRY $BK/dongle.noprobe; $BB sync
    DG_ST=ok; dg_state ok "$DG_G"; log "동글 드라이버가 다 올라와 버팀: 시도 기록을 지움"
  fi
  return 0
}
# --- 1.8.0 DG-9 (가)안(소유자 결정 11-18): 동글 차도 무선 모드를 넣는다 ---
# HMG-API는 우리 포크 모드 mod.json의 system 선언만 본다. 한국 차 일반 항목은 hmgapi.wifi(SDIO 칩 등)가 있어야 해서 USB 동글 차는
# 막힌다. 그래서 모드 2.4.6에 {"region":"KOR","props":{"persist.kp.wifi_dongle":"1"}} 항목을 더하고, 이 속성은 패키지만 쓴다.
#   - 동글 차(dg_car): 동글 사용 표시가 있고, 막힘 기록이 없고, 우리 동글 드라이버가 이번 부팅에 Live. 이때만 속성을 1로 두고
#     Wi-Fi 칩 확인(wake_wifi)을 건너뛴다. 동글이 없거나 드라이버가 안 올라온 부품 없음 차는 예전처럼 막힌다.
#   - (A)안(11-18 오케스트레이터 결정): 잠깐 뺀 동글은 속성 1을 그대로 둔다(내장 칩 차의 WIFIGONE과 같은 처리, 상태 화면에 "동글이 보이지
#     않습니다"). 모드가 깔린 채 속성이 0이면 HMG-API가 "이 차용이 아님" 문제로 적용 전체를 멈추기 때문이다(Engine.java 349·418행).
#   - 속성 0은 차주가 동글 사용을 끄거나 막힘(hang·fail·gone)일 때만 쓴다(dg_off). 순서: 우리 모드 지우기 → 계획이 우리 모드 되돌리기뿐일
#     때만 적용 → 0. 모드를 지우지 못하면 0으로 하지 않고 다음 부팅에 다시 한다. 패키지를 지울 때(preun)도 0으로 둔다.
#     persist 속성은 비우지 못하는 판이 있어 0을 쓴다(모드는 "1"만 받음).
#   - 차 확인 안 함: 모드가 깔려 있고 동글이 없을 때(속성 1, 훅 켜짐) 순정 유선 카플레이가 되는지.
# wifi-chip 표시 파일은 쓰지 않는다(다른 동글 패키지와 겹침, 소유자 결정).
DG_PROP=persist.kp.wifi_dongle
# 베타 2(R3): 부품 없는 차 첫 설치에서 동글이 아직 안 붙었을 때. 재부팅 대신 꽂아 두면 그 부팅에 이어서 설치한다(dg_modwait_tick)
DG_WAIT_MSG="USB Wi-Fi 동글이 붙으면 무선 모드 설치를 이어서 합니다. 동글을 꽂아 두고, 안 되면 동글을 꽂은 채 시동을 껐다 켜 주세요."
DG_GONE_MSG="동글이 보이지 않습니다. 다시 꽂아 주세요."
DG_OFF_MSG="동글 사용을 꺼서 무선 모드를 지웠습니다. 3분 후 재부팅해 주세요."
DG_OFF_APP_MSG="동글 사용을 꺼서 무선 모드를 지웠습니다. HMG-API 앱에서 변경 사항을 적용한 뒤 재부팅해 주세요."
# 바뀔 때만 쓰고, 다시 읽어 확인한다(리뷰 낮음 1: 못 쓰면 1을 돌려줌 → 동글 차로 보지 않음)
dg_prop() {
  [ "$(getprop $DG_PROP 2>/dev/null)" = "$1" ] && return 0
  setprop $DG_PROP $1 2>/dev/null
  if [ "$(getprop $DG_PROP 2>/dev/null)" = "$1" ]; then log "동글 차 속성 $DG_PROP=$1"; return 0; fi
  log "동글 차 속성 $DG_PROP=$1을 쓰지 못함"; return 1
}
# 동글이 실제로 보이는가: USB 장치의 인터페이스가 우리 동글 드라이버(이름에 88x2bu, 소스의 등록 이름 rtl88x2bu)에 붙어 있음
dg_seen() {
  for _dgi in $USB_SYS/*:*; do
    [ -d "$_dgi" ] || continue
    us_drv $_dgi/driver
    case "$_ud" in *88x2bu*) return 0 ;; esac
  done
  return 1
}
# 동글 차: 동글 사용 표시 + 막힘 없음 + 이번 부팅에 우리가 올린 드라이버(insmod 0, 리뷰 중간 3: 다른 패키지가 올린 같은 이름은 아님)가
# Live + 동글이 보임. 맞으면 속성 1과 "동글을 쓴 적 있음" 기록($BK/dongle.used, 그만 쓸 때 dg_off가 정리할 대상)
dg_car() {
  [ -f $DG_ON ] && [ ! -f $DG_BLOCK ] && [ "$DG_ST" != notours ] || return 1
  dg_rc; [ "$DG_RC" = 0 ] && dg_live && dg_seen || return 1
  # 시험판 4: 이 부팅에 동글이 붙은 적 있음(상태 화면이 "이제 꽂아 주세요"와 "다시 꽂아 주세요"를 가름, 단계 기록이 꺼져 있어도)
  _dgc1=; [ -f $W/dongle.seen1 ] && read _dgc1 _dgcx < $W/dongle.seen1 2>/dev/null
  [ "$_dgc1" = "${BID:-none}" ] || { dg_up_s; echo "${BID:-none} $_dgu" 2>/dev/null > $W/dongle.seen1; }
  # 정식 C1 ⓐ(베타 3 제보: 버스를 기억한 부팅은 10/10 저절로 붙음): 핫스팟이 버틴 때만이 아니라 동글이 우리 드라이버에 붙은 때에도
  # 다음 시동에 미리 막을 버스를 적는다(이 부팅에 한 번, 붙은 버스가 곧 동글 자리라 틀리지 않음. 바뀐 때만 씀)
  _dggs=; [ -f $W/dg.gbsaved ] && read _dggs < $W/dg.gbsaved 2>/dev/null
  [ "$_dggs" = "${BID:-none}" ] || { dg_gbus_save && echo "${BID:-none}" 2>/dev/null > $W/dg.gbsaved; }
  dg_prop 1 || return 1
  [ -f $BK/dongle.used ] || : 2>/dev/null > $BK/dongle.used
  return 0
}
# 30초 점검마다: 드라이버가 올라와 있고 동글이 보이면 속성 1(처음 본 때만 setprop). 빼도 0으로 하지 않는다((A)안)
dg_prop_sync() {
  case "$DG_ST" in up|ok) dg_car ;; esac
  return 0
}
# 계획이 우리 모드 되돌리기뿐인가(preun과 같은 조건): 되돌리기·같음 줄만 있으면 0
dg_plan_revert_only() {
  _dgbad=0; _dgrv=0
  hmgapid engine plan 2>/dev/null > $W/dg-plan.txt || _dgbad=1
  while IFS= read -r _dgpl; do
    case "$_dgpl" in
      "restore  "*|"setting  "*" back to stock"*|"unbind   "*) _dgrv=1 ;;
      "same     "*) ;;
      "change   "*|"update   "*|"setting  "*|"bind     "*|"problem  "*|"rebase   "*|"nothing changed"*) _dgbad=1 ;;
    esac
  done < $W/dg-plan.txt
  # 리뷰 낮음 1: 되돌리기 줄이 하나도 없으면(빈 계획 등) 적용하지 않는다
  [ $_dgrv = 1 ] || _dgbad=1
  return $_dgbad
}
# 동글을 그만 쓸 때(차주가 끔·막힘)만: 우리 모드 지우기 → 적용(계획이 되돌리기뿐일 때) → 속성 0.
# 할 일이 있는 차만: 속성이 1이거나 동글을 쓴 적 있음($BK/dongle.used, 리뷰 높음 2: 속성이 먼저 0이 된 채 모드가 남은 차도 정리).
# 모드가 깔려 있으면: 우리가 넣은 것(mod.ours)만 지운다. 지우지 못하거나 우리 것이 아니면 속성을 그대로 둔다(리뷰 높음 1: 모드가 남은 채
# 0이 되지 않게). 모드가 없으면 속성 0. 30초 반복이나 부팅 직후가 아니라 fix_perms(HMG-API가 응답한 뒤, setup_hmgapi 앞)에서만 부른다.
dg_off() {
  [ "$(getprop $DG_PROP 2>/dev/null)" = 1 ] || [ -f $BK/dongle.used ] || return 0
  # 베타 2(UP-2): 우리 빌드만 지운다(차주가 넣은 업스트림 판은 그대로, 속성도 그대로)
  if [ -f $HMGDATA/mods/$MOD_ID/mod.json ] && mod_kor; then
    if [ ! -f $BK/mod.ours ] || ! mod_ourkor; then
      log "동글을 그만 씀: 무선 모드가 우리가 넣은 것이 아니라 지우지 않음(속성 그대로)"; return 0
    fi
    if ! hmgapid engine remove $MOD_ID 2>/dev/null > $W/dg-remove.txt; then
      log "동글을 그만 씀: 무선 모드를 지우지 못함(속성은 그대로 두고 다음 부팅에 다시)"; return 0
    fi
    # 다음 설정이 새로 판단하게 우리 설치 기록을 지운다(내장 Wi-Fi가 되는 차는 칩 경로로 다시 넣음, 부품 없음 차는 막힘)
    # 되돌리기 USB의 고정(mod.pin)도 지운다(지운 모드에 대한 고정이 남아 다음 판 자동 업데이트를 막지 않게, 리뷰 낮음 3)
    rm -f $BK/mod.ours $BK/mod.tried $BK/mod.upd $BK/mod.pin $BK/mod.sig $BK/mod.sigdiff
    if dg_plan_revert_only && hmgapid engine apply >/dev/null 2>&1; then
      log "동글을 그만 씀: 무선 모드를 지우고 적용함"; pnotice "Korea Projection: $DG_OFF_MSG"
    else
      log "동글을 그만 씀: 무선 모드를 지웠지만 적용하지 않음(계획에 다른 변경, $W/dg-plan.txt)"; pnotice "Korea Projection: $DG_OFF_APP_MSG"
    fi
  fi
  [ "$(getprop $DG_PROP 2>/dev/null)" = 1 ] && { dg_prop 0 || return 0; }
  rm -f $BK/dongle.used
  return 0
}
# fix_perms가 부른다: 동글 사용을 껐거나 막힌 차만 dg_off
dg_off_due() {
  { [ ! -f $DG_ON ] || [ -f $DG_BLOCK ]; } && dg_off
  return 0
}
# 상태 파일의 동글 줄 넷(앱이 읽음). dongle=<상태>(off: 동글 사용 표시 없음), dongle_lv=0|1|2(없음·주의 노랑·멈춤 빨강), dongle_msg=<문구>,
# dongle_oldnav=yes|no(동글을 켰고 내비가 260902판이 아님: 앱이 노란 "내비 업데이트를 권합니다" 안내를 띄움, 문구·색은 앱 몫).
# 판정 줄(first 등)은 건드리지 않는다(내장 Wi-Fi·유선 카플레이가 되는 차의 판정을 덮지 않게)
DG_NOSUP_MSG="이 차의 내비 소프트웨어는 아직 동글을 지원하지 않습니다."
DG_NOWRITE_MSG="동글 드라이버를 준비하지 못했습니다. 재부팅해 보세요."
# 이번 부팅 id(status.sh가 라이브러리로 부를 때는 BID가 비어 있음)
dg_kv_bid() { _dgkb=$BID; [ -n "$_dgkb" ] || { read _dgkb < ${BOOT_ID:-/proc/sys/kernel/random/boot_id}; } 2>/dev/null; echo "${_dgkb:-none}"; }
dg_kv() {
  # 앱 결정 (2): 동글 사용 표시가 없으면(차주가 껐거나 처음부터 꺼짐) 지난 상태가 남아 있어도 dongle=off(앱의 "재부팅 필요" 딱지가 남지 않게)
  _dgs=off; [ -f $DG_ON ] && [ -f $W/dongle.state ] && read _dgs _dgx < $W/dongle.state 2>/dev/null
  case "$_dgs" in ''|*[!a-z]*) _dgs=off ;; esac
  case "$_dgs" in
    blocked) _dgl=2; _dgm=$DG_BLOCK_MSG ;;
    nosoc|nodrv) _dgl=1; _dgm=$DG_NOSUP_MSG ;;
    otherpkg) _dgl=1; _dgm=$DG_OTHERPKG_MSG ;;
    other) _dgl=1; _dgm=$DG_OTHERMOD_MSG ;;
    builtinbusy) _dgl=1; _dgm=$DG_BUSY_MSG ;;
    usbadb) _dgl=1; _dgm=$DG_USBADB_MSG ;;
    nodongle) _dgl=1; _dgm=$DG_NODONGLE_MSG ;;
    notlisted) _dgl=1; _dgm=$DG_NOTLISTED_MSG ;;
    # 시험판 5: 동글 부팅(이 부팅 표시)이면 동글이 wlan0을 잡아 내장으로도 못 감 → 빨강, 빠져나갈 길
    notours) if dg_rm_now; then _dgl=2; _dgm="지원 목록의 동글이 아닙니다. 동글 사용을 끄면 다음 시동부터 내비 Wi-Fi로 돌아갑니다."; else _dgl=1; _dgm=$DG_NOTOURS_MSG; fi ;;
    nowrite) _dgl=1; _dgm=$DG_NOWRITE_MSG ;;
    up|ok)
      # 시험판 4: 이 부팅에 아직 한 번도 붙지 않았으면 "이제 꽂아 주세요", 붙었다가 빠졌으면 "다시 꽂아 주세요"
      _dgsn1=; [ -f $W/dongle.seen1 ] && read _dgsn1 _dgsnx < $W/dongle.seen1 2>/dev/null
      _dgpa=; [ -f $W/dg.plugagain ] && read _dgpa < $W/dg.plugagain 2>/dev/null
      _dgkl=; [ -f $W/dg.ladder ] && read _dgkl _dgkq < $W/dg.ladder 2>/dev/null
      if [ "$_dgkl" = "$(dg_kv_bid)" ] && [ "$_dgkq" = run ]; then _dgl=1; _dgm=$DG_LADDER_MSG
      elif [ -n "$_dgpa" ] && [ "$_dgpa" = "$(dg_kv_bid)" ]; then _dgl=1; _dgm=$DG_PLUGAGAIN_MSG
      elif dg_seen; then _dgl=0; _dgm=
      # 시험판 5 리뷰 중간 2: 붙었다가 빠지면 이 부팅은 내장으로도 못 감 → 빨강, 빠져나갈 길
      elif [ -n "$_dgsn1" ] && [ "$_dgsn1" = "$(dg_kv_bid)" ]; then _dgl=2; _dgm=$DG_GONE2_MSG
      else _dgl=1; _dgm=$DG_PLUG_MSG; fi ;;
    bootwait) _dgl=1; _dgm=$DG_BOOTWAIT_MSG ;;
    wait)
      # 리뷰 중간 1: insmod가 DG_WAIT+20초 넘게 돌아오지 않으면(커널 안에서 멈춤) 빨강 재부팅 안내
      _dgl=1; _dgm=$DG_LOADING_MSG; _dgw1=; _dgw2=; [ -f $W/dgins.start ] && read _dgw1 _dgw2 < $W/dgins.start 2>/dev/null
      if [ "$_dgw1" = "$(dg_kv_bid)" ]; then
        # insmod 결과(이번 부팅 것)가 없을 때만. status.sh는 BID가 비어 있어 dg_rc 대신 직접 읽는다
        _dgw3=; [ -f $DG_RCF ] && read _dgw3 _dgw4 < $DG_RCF 2>/dev/null; dg_up_s
        case "$_dgw2" in ''|*[!0-9]*) ;; *) [ "$_dgw3" != "$_dgw1" ] && [ $((_dgu - _dgw2)) -gt $((${DG_WAIT:-10} + 20)) ] && { _dgl=2; _dgm=$(dg_reboot_msg); } ;; esac
      fi ;;
    skip) _dgl=1; _dgm=$DG_SKIP_MSG ;;
    # 시험판 5: 그 부팅만의 실패(설정은 그대로, 다음 시동에 다시 시도)
    bcmup) _dgl=1; _dgm=$DG_BCMUP_MSG ;;
    failboot) _dgl=1; _dgm=$DG_FAILBOOT_MSG ;;
    plugto) _dgl=1; _dgm=$DG_PLUGTO_MSG ;;
    plugoffnw) _dgl=1; _dgm=$DG_PLUGOFFNW_MSG ;;
    bcmlate) _dgl=2; _dgm=$DG_BCMLATE_MSG ;;
    noap) _dgl=2; _dgm=$DG_NOAP_MSG; dg_lateap_now && _dgm=$DG_LATEAP_MSG ;;
    nodevstuck) _dgl=2; _dgm=$DG_NODEVSTUCK_MSG ;;
    nobind) _dgl=2; _dgm=$DG_NOBIND_MSG ;;
    reupmax) _dgl=2; _dgm=$DG_REUPMAX_MSG ;;
    *) _dgl=0; _dgm= ;;
  esac
  # 5차 결과 반영: 이 부팅에 순정 드라이버를 내렸는데 동글 길을 쓰지 않게 됐으면(막힘·끄기·내리다 멈춤) 빨강으로 재부팅 안내
  # 시험판 5: 제 문구(빠져나갈 길 포함)가 있는 상태는 덮지 않는다
  case "$_dgs" in wait|up|ok|noap|nodevstuck|nobind|notours|reupmax|bcmlate) ;; *) dg_rm_now && { _dgl=2; _dgm=$(dg_reboot_msg); } ;; esac
  # 동글을 쓰는 동안 늘 보일 안내(dongle_note, 앱이 고정 줄로 보임): 뽑기 전에 끄고 재부팅
  _dgn=; case "$_dgs" in wait|up|ok) _dgn=$DG_INUSE_NOTE ;; esac
  # 베타 3(B3-2): 아직 한 번도 붙지 않은 꽂기 기다림이면 유선 프로젝션이 막힌다는 안내
  [ "$_dgs" = up ] && [ "$_dgm" = "$DG_PLUG_MSG" ] && _dgn=$DG_PLUGWAIT_NOTE
  echo "dongle=$_dgs"; echo "dongle_lv=$_dgl"; echo "dongle_msg=$_dgm"; echo "dongle_note=$_dgn"
  if [ "$_dgs" != off ] && dg_oldnav; then echo "dongle_oldnav=yes"; else echo "dongle_oldnav=no"; fi
  # 베타 3(B2-7, 앱 QR 동글 줄 요청 11-23): 마지막으로 붙은 동글이 지원 동글인가(결과만, 판단 방식·번호 없음)와 이번 부팅에 붙어 있는가
  _dgkp=unknown; _dgko=; [ -f $DG_OUIF ] && read _dgko _dgkx < $DG_OUIF 2>/dev/null
  case "$_dgko" in ok|id|lax) _dgkp=yes ;; no) _dgkp=no ;; esac
  echo "dongle_sup=$_dgkp"
  if dg_seen; then echo "dongle_seen=yes"; else echo "dongle_seen=no"; fi
  # 베타 3(리뷰 뒤 추가, 앱 요청 11-23): 지금 동글 사용을 끄면 그 부팅에 바로 적용되는가(끄기 요청 처리 set_take와 같은 함수)
  if [ -f $DG_ON ] && dg_plugwait_now; then echo "dongle_wait=yes"; else echo "dongle_wait=no"; fi
}
# --- 1.8.0 변조 검사(소유자 결정 2026-11-18): 우리 패키지 id(korea.projection)를 그대로 쓴 개조판(고정 비밀번호를 넣은 동글 묶음 등)이 있다 ---
# 패키지 파일(스크립트·앱·모드 zip·지도·busybox)의 md5를 빌드 때 만든 목록(bin/kp-files.md5, "md5  상대 경로" 줄, NEMESIS.data와 목록 자신은 뺌)과
# 파일마다(md5sum 표준입력)
# 맞춰 본다. 다르거나 목록이 없으면 "변조"로 보고 서비스는 아무것도 하지 않고 멈춘다(핫스팟·모드 설치·차 변경 없음).
# 결과는 $W/kp.tamper("ok" 또는 "bad <다른 파일 수>")에 남겨 상태 화면이 읽는다. 다른 파일 이름은 ap.log에 남긴다(우리 파일 이름뿐, 비밀 없음).
# 한계: 개조판이 이 스크립트까지 통째로 바꾸면 이 검사도 빠진다(리포트 status.sh가 따로 다시 본다). 완전히 막을 수는 없다(pkg.md).
TAMPER_MSG="변조된 Korea Projection입니다. 삭제 후 공식 GitHub에서 다운로드해 주세요."
kp_verify() {
  KP_BADN=0; KP_BADL=
  _kpl=${KPLIST:-$APP/bin/kp-files.md5}
  [ -s $_kpl ] || { KP_BADN=-1; return 1; }
  # 리뷰 높음 1: 차에서 확인된 꼴(md5sum < 파일, 표준입력)만 쓰고 해시만 비교한다(파일 이름을 인자로 줄 때의 출력 꼴은 차에서 확인 안 함)
  while read -r _kph _kpp; do
    [ -n "$_kpp" ] || continue
    _kpg=; set -- $($BB md5sum < "$APP/$_kpp" 2>/dev/null); _kpg=$1
    [ "$_kpg" = "$_kph" ] || { KP_BADN=$((KP_BADN + 1)); KP_BADL="$KP_BADL $_kpp"; }
  done < $_kpl
  [ $KP_BADN = 0 ]
}
main() {
  # 베타 3(B3-3): 서비스 안에서만 디버그 자동 켜기를 바로 처리한다(밖에서는 요청 파일로)
  DBG_SVC=1; ST_NOPUSH=1
  umask 077
  if ! has_bb; then
    log "시작 안 함: busybox가 없음 ($BB, 실행 안 됨). 이 내비는 아직 지원하지 않음(조사 중)"
    idle_forever
  fi
  $BB mkdir -p $W
  # 1.7.2(P-15): ap.log를 덧붙이기로 다시 열어 둔다(크기 제한 aplog_rotate가 비워도 이어서 쓰게)
  aplog_open
  # C4: 지난 실행이 남긴 앱 응답 파일(값이 들어 있음)을 지운다
  apcfg_rm
  # 1.8.1 I-1(설계 리뷰 2): 지난 실행이 남긴 우리 방화벽 체인을 먼저 뺀다(순정 AP 길·대기 길은 stop_ap보다 먼저 돈다)
  fw_aa_down
  # 1.8.0 변조 검사: 무엇이든 바꾸기 전에 본다. 다르면 진행 기록에 실패 문구를 쓰고 멈춘 채 기다린다(mode=restart가 다시 띄우지 않게 끝내지 않음)
  # 리뷰 중간 2: 지난 부팅의 결과를 먼저 지운다($W는 재부팅해도 남음). 업데이트 중 파일을 다 풀기 전처럼 잠깐 맞지 않을 수 있어
  # 30초 간격으로 KP_VERIFY_TRIES번(기본 4번, 약 2분)까지 다시 본 뒤에 판정한다. 끝나는 조건: 맞음 또는 횟수
  rm -f $W/kp.tamper
  _kvt=1
  while ! kp_verify && [ $_kvt -lt ${KP_VERIFY_TRIES:-4} ]; do
    [ $_kvt = 1 ] && log "패키지 파일이 목록과 다름(${KP_BADN}개): 잠시 뒤 다시 봄"
    _kvt=$((_kvt + 1)); sleep 30 & wait $!
  done
  if [ $KP_BADN = 0 ]; then
    echo ok > $W/kp.tamper
  else
    echo "bad $KP_BADN" > $W/kp.tamper
    if [ "$KP_BADN" = -1 ]; then log "시작 안 함: 패키지 파일 목록(bin/kp-files.md5)이 없음 → 변조로 봄"
    else log "시작 안 함: 패키지 파일 $KP_BADN개가 목록과 다름 →$KP_BADL (변조로 봄)"; fi
    prog 100 fail "$TAMPER_MSG"
    # 리뷰 낮음 2: 멈춘 채로도 [제보 파일 만들기]는 받는다(idle_req: 30초마다 요청만 봄, 차를 바꾸는 일은 하지 않음)
    idle_req
  fi
  # 1.7.4 베타 2(측정): 측정 기록에 서비스 시작 표시 줄
  perf_start
  # 1.7.2(P-8·P-11·P-17): 이번 부팅의 첫 시작인가. $W/svc.start "<부팅 id> <부팅 뒤 초>"(첫 시작 때만 씀, 리포트가 읽음).
  # 첫 시작이면 ap.log에 "서비스 시작: 이번 부팅 처음" 줄을 남긴다(리포트 "연결 기록" 칸은 이 줄 뒤만 보인다).
  # 업데이트하면 $W가 지워지므로 업데이트 뒤 첫 시작도 "처음"이다.
  _sb=$(cat $BOOT_ID 2>/dev/null); _su=$($BB awk '{ print int($1) }' $UPTIME 2>/dev/null); _so=
  # 1.7.3(K-7): 부팅 id는 한 부팅 동안 바뀌지 않으므로 서비스 시작 때 한 번 읽어 BID에 둔다(30초 점검마다 cat을 띄우지 않게).
  # BID가 비어 있으면(못 읽음, status.sh가 라이브러리로 쓸 때) 아래 함수들은 예전처럼 그때 읽는다
  BID=$_sb
  [ -f $W/svc.start ] && read _so _sx < $W/svc.start
  if [ -n "$_sb" ] && [ "$_so" = "$_sb" ]; then
    SVC_FIRST=0; log "서비스 다시 시작(같은 부팅, 부팅 뒤 ${_su:-?}초)"
  else
    SVC_FIRST=1; echo "${_sb:-none} ${_su:-0}" > $W/svc.start
    # 1.7.3(K-7, #65): 설치·업데이트는 $W를 지우므로 재부팅 없이 다시 설치해도 이 줄이 찍힌다. 헷갈리지 않게 그 경우도 적는다
    # (표시 줄 $SVC_MARK 자체는 리포트가 자르는 기준이라 그대로 둔다)
    log "$SVC_MARK(부팅 뒤 ${_su:-?}초. 재부팅 없이 설치·업데이트했으면 그 뒤 첫 시작)"
  fi
  # 상태 화면 안내 파일은 서비스만 쓴다: 지난 실행의 안내를 비운다
  HINT_ON=1; HA_READY=; HA=; HA_T=; HI=; HI_T=; HC=; HC_T=; hint_write
  # 1.7.4(L-9, 소유자 결정): 무선 AA 끄기 기능을 없앴다. 1.7.3 이하에서 꺼 둔 차에 남은 표시를 지운다(이 차는 AA가 다시 켜짐)
  # 묶음 E 리뷰(낮음 3): 실제로 지워졌을 때만 로그를 남긴다(못 지웠으면 조용히 지나감. 그 표시는 아무 곳에서도 읽지 않음)
  if [ -f $AAOFF ]; then rm -f $AAOFF 2>/dev/null; [ -f $AAOFF ] || log "예전 무선 안드로이드 오토 끄기 표시를 지웠습니다(1.7.4부터 늘 켜짐)"; fi
  prod=$(getprop ro.build.product)
  # svc, pm, HMG-API는 Android가 다 켜진 뒤에 쓴다
  # 시험판 5: 동글을 켠 차는 부팅이 끝나기 전에 동글 부팅 속성을 세운다(모드가 순정 AP를 켜지 않게, 부팅 +4초)
  dg_early
  while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 2; done
  # 묶음 I: 지금 꽂혀 있는 USB 장치를 부팅마다 한 번 남긴다(동글 조사용, 실패해도 계속)
  usb_seen_write
  # 1.8.0 DG-4: 동글 드라이버(동글 사용 표시가 있는 차만, 부팅마다 한 번). 실패해도 계속
  # 시험판 4(리뷰 중간 3): 동글 기다림이 길 수 있어(최대 약 20분) 멈춤 신호 처리를 먼저 건다(단계 기록 끝 표시를 남기게)
  trap 'stop_all; log "멈춤"; exit 0' TERM INT HUP
  DG_IN_START=1; dg_start; DG_IN_START=0
  ST_NOPUSH=
  # 리뷰 낮음 8: 무선 모드·softap.conf를 기다리는 차도 설치 표시(a_install)와 바뀜(A)을 받게, 부팅이 끝난 뒤 바로 시작 처리(뒤의 같은 줄은 확인만 함)
  debug_auto start
  # 시험판 5: 동글 길이 아닌 결과(설치한 부팅·다른 패키지·칩 없음 등)면 속성을 0으로(1로 남아 있을 때만)
  case "$DG_ST" in bootwait|wait|up|ok|noap|nodevstuck|nobind|notours|reupmax) ;; *) dg_kprop 0 ;; esac
  # 시계가 맞춰진 뒤의 시각으로 다시 잡는다(경과 시간)
  PSTART=$(date +%s); PUSTART=$(prog_up)
  # 설치 진행 기록: 설정이 끝난 차는 "확인 중", 아니면 시작(5%). 끝난 차도 핫스팟이 켜지면 "준비됨"으로 바꾼다.
  # 같은 부팅에 서비스가 다시 시작돼도 "재부팅 필요"·"실패"는 덮지 않는다
  if prog_final_this_boot; then :
  elif setup_done; then prog 100 done "무선 프로젝션 설정이 끝나 있습니다. 핫스팟을 켜는 중입니다."
  else prog 3 run "설치를 시작했습니다"; fi
  # 확인되지 않은 차에서도 한다: HMG-API가 기록한 그대로만 되돌리므로 (md5 확인)
  # 뒤에서 돌린다: HMG-API가 늦거나 멈춰도 핫스팟은 바로 켠다 (출력은 같은 ap.log로)
  if ! fix_running; then
    fix_perms &
    echo "$! ${BID:-$(cat $BOOT_ID 2>/dev/null)}" > $W/fix.pid
  fi
  if ! car_in "$prod" "$CARS"; then
    log "시작 안 함: $prod 는 확인된 차가 아님 ($CARS)"
    prog 100 fail "지원하지 않는 차(한국 내수 펌웨어가 아님)입니다. 아무것도 바꾸지 않았습니다."
    # mode=restart: 끝내지 않고 대기한다(svcmgr가 죽은 횟수를 세지 않게). 제보 요청은 본다(리뷰 L1)
    idle_req
  fi
  car_in "$prod" "$CARS_TRY" && log "시험 지원 차: $prod (차에서 아직 확인되지 않음)"
  trap 'stop_all; log "멈춤"; exit 0' TERM INT HUP
  if ! try_ready "$prod"; then
    log "대기: HMG-API 무선 모드가 설치·켜짐 상태가 아님 (시험 지원 차는 모드가 있어야 핫스팟을 켬)"
    if setup_pending; then
      $BB mkdir -p $BK; : > $BK/setup.told
      notice "Korea Projection: 무선 프로젝션을 설정하는 중입니다. 약 5분 동안 재부팅하거나 끄지 마세요."
    fi
    # 1.7.3(R-4): 모드를 기다리는 차도 제보 요청은 30초마다 본다(모드 확인은 지금처럼 1분마다)
    while ! try_ready "$prod"; do sleep 30 & wait $!; req_tick; sleep 30 & wait $!; req_tick; done
    log "무선 모드 확인됨: 시작"
  fi
  # 1.8.0 RS-2: 기본 위치에 순정 Wi-Fi 설정이 없어 /securedata 쪽을 읽는 차(캐스퍼 EV 등)는 그렇다고 한 줄 남긴다(경로만)
  src_pick
  conf_diag
  [ $SRC_USED_ALT = 1 ] && log "순정 카플레이 Wi-Fi 설정을 대체 위치에서 읽음: $SRC (기본 위치에 파일 없음)"
  # 베타 3(B3-7, 제보 #498: 0개가 4번, 2분 뒤 리포트는 5개): 한 번 못 읽어도 그 부팅에 포기하지 않고 다시 읽어, 읽히면 이어서 시작.
  # 간격(소유자 "30초 마다 읽으면 너무 길지 않나?" 11-23): 처음 CONF_FAST_S초(3분)는 CONF_FAST_GAP초(5초)마다, 그 뒤 30초마다.
  # 처음 3분은 상태 화면에 "다시 읽는 중"(진행 중), 그 뒤에도 못 읽으면 실패 문구. 기록은 처음·크기나 수정 시각이 바뀔 때·성공 때만
  # (내용·SSID 없음). 제보 요청은 30초마다 본다. 끝: 읽힘 또는 서비스 멈춤(TERM)
  if ! conf_ok; then
    _cfn=0; _cfl=; _cft=0; _cfr=0
    setup_done && prog 50 run "$SOFTAP_RETRY_MSG"
    # 이 부팅의 디버그 자동 켜기를 먼저(실패한 차도 기록이 남게, 제보 #498 B2-6)
    debug_auto start; logstart
    while ! conf_ok; do
      _cfm=$(conf_meta)
      if [ $_cfn = 0 ] || [ "$_cfm" != "$_cfl" ]; then
        log "시작 못 함: softap.conf에서 문자열 4개를 찾지 못함 (${NS:-0}개, $_cfm, $((_cfn + 1))번째) — 위치부터 다시 읽음"
      fi
      _cfl=$_cfm; _cfn=$((_cfn + 1))
      if [ $_cft -lt $CONF_FAST_S ]; then _cfg=$CONF_FAST_GAP; else _cfg=30; fi
      sleep $_cfg & wait $!
      _cft=$((_cft + _cfg)); _cfr=$((_cfr + _cfg))
      # 리뷰 H1: 30초마다 제보 요청과 함께 로그 밀어내기(cp.log 3MB×4·ap.log)와 디버그 48시간 끝 점검도 한다(이 반복은 끝이 없을 수 있음)
      [ $_cfr -ge 30 ] && { _cfr=0; req_tick; logrotate; }
      # 3분이 지나도 못 읽으면 실패 문구(한 번)
      [ $_cft -ge $CONF_FAST_S ] && [ $((_cft - _cfg)) -lt $CONF_FAST_S ] && setup_done && prog 100 fail "$SOFTAP_FAIL_MSG"
      src_pick
    done
    log "softap.conf를 다시 읽어 이어서 시작(${_cfn}번 실패 뒤, 문자열 ${NS}개, 위치 $SRC)"
    conf_diag
    # 다시 읽는 중·실패로 남긴 진행 기록을 지운다(뒤의 "준비됨"이 덮을 수 있게)
    $BB awk -v a="stage=$SOFTAP_FAIL_MSG" -v b="stage=$SOFTAP_RETRY_MSG" '$0 == a || $0 == b { f = 1 } END { exit !f }' $PROG 2>/dev/null && rm -f $PROG
  fi
  # C4: 파일 값을 기억해 둔다(순정 AP 판정은 파일 값으로). 서비스 값은 순정 AP 판정 뒤 우리 hostapd를 띄울 때만 묻는다(정식 2차 리뷰 L1)
  FS2=$S2; FS4=$S4
  write_conf
  # P-3: 지금 쓴 설정의 softap.conf 서명(30초 점검에서 비교)
  CONF_SIG=$(conf_sig $SRC)
  # 확인된 차가 아니면 순정 핫스팟(다른 hostapd)이 도는 동안 시작하지 않는다(svc wifi enable이 순정 핫스팟을 끈다)
  # 1.6.2: 순정 hostapd가 카플레이 AP(softap.conf의 카플레이 SSID)면 "순정 AP로 준비됨"으로 가고 돌아오지 않는다.
  # 일반 핫스팟이거나 판단할 수 없으면 예전처럼 순정이 멈출 때까지 기다린다.
  if ! car_in "$prod" "$CARS_OK"; then
    # 함께 넣은 busybox를 쓰는 내비(tcc803x, K3·K8)는 순정이 카플레이 AP를 직접 켤 수 있다(K3 #15). 부팅 직후 순정보다
    # 먼저 wlan0을 가져가지 않게 순정 hostapd를 최대 STOCK_GRACE초 기다린다. 내비에 busybox가 있는 차는 기다리지 않는다.
    # 아직 확인 안 함: 순정이 부팅 때 스스로 켜는지, 아이폰이 블루투스로 요청할 때만 켜는지(요청 때만이면 이 대기로는
    # 부족하다. 그때는 ap_yield가 우리 것을 멈추고 순정 AP 경로로 간다).
    if [ -f $BK/stockap.seen ] && stock_seen_stale; then
      rm -f $BK/stockap.seen $BK/stockap.miss
      log "순정 카플레이 AP를 ${STOCK_MISS_MAX}번의 부팅 동안 못 봄: 기록(stockap.seen)을 지우고 보통 흐름으로 돌아감"
    fi
    # 베타 3(B3-1, 제보 #497 B2-2): 동글을 쓰는 부팅은 순정이 Wi-Fi를 켜지 않아 순정 카플레이 AP가 뜰 수 없다. 기다리지 않는다
    if [ "$BB" = "$BB_OWN" ] && [ ! -f $BK/stockap.seen ] && ! stock_ap_on && dg_builtin_off; then
      log "동글 부팅: 순정 카플레이 AP 기다림(${STOCK_GRACE}초)을 건너뜀"; dg_step stock-grace-skip
    elif [ "$BB" = "$BB_OWN" ] && [ ! -f $BK/stockap.seen ] && ! stock_ap_on; then
      log "순정 카플레이 AP를 최대 ${STOCK_GRACE}초 기다림(busybox 없는 내비)"
      _g=0
      while [ $_g -lt $STOCK_GRACE ] && ! stock_ap_on; do sleep 10 & wait $!; _g=$((_g+10)); done
    fi
    _ss=$(stock_ssid)
    if [ "$_ss" = carplay ] || [ -f $BK/stockap.seen ]; then
      stock_ap_mode
    fi
    if [ "$_ss" != none ]; then
      log "대기: 다른 hostapd가 돌고 있음(순정 핫스팟 등, 판정 $_ss)"
      # 기다리는 동안에도 판정을 다시 본다: 순정이 카플레이 AP로 바꾸면 순정 AP 경로로 간다. 순정이 hostapd를 다시
      # 띄우는 틈에 wlan0을 가져가지 않게, 두 번 이어서(약 2분) 없을 때만 끝낸다(리뷰 M3). 끝나는 조건: 순정이 멈춤·TERM.
      _gone=0
      while [ $_gone -lt 2 ]; do
        # 1.7.3(R-4): 기다리는 동안에도 제보 요청은 30초마다 본다
        sleep 30 & wait $!; req_tick
        sleep 30 & wait $!; req_tick
        if stock_ap_on; then
          _gone=0
          [ "$(stock_ssid)" = carplay ] && stock_ap_mode
        else
          _gone=$((_gone+1))
        fi
      done
      log "다른 hostapd가 멈춤: 시작"
    fi
  fi
  # C4·정식 2차 리뷰 L1: 우리 hostapd를 띄우기 바로 전에만 묻는다(순정 AP 차는 broadcast·기다림 없음). 대체 위치 차는 서비스 값을 먼저
  ap_src_apply
  [ "$AP_SRC" = svc ] && write_conf
  log "시작 ($prod): softap.conf의 카플레이 SSID 길이 ${#S2}, 비밀번호 길이 ${#S4}"
  stop_ap
  # Wi-Fi 드라이버는 Wi-Fi를 켜야 올라오고, hostapd가 wlan0을 쓰려면 wpa_supplicant가 놓아야 한다(잠금 포함)
  take_wlan0
  debug_auto start
  logstart
  up
  aa_sig
  fw_aa_sync
  rm -f $CPN
  wifi_events; aa_events; cp_watch
  hint_tick
  # 설정이 끝난 차(재부팅 뒤 등)는 핫스팟이 켜지면 "준비됨". 설정 중이면 진행 기록은 fix_perms가 맡는다.
  # 이번 부팅에 "재부팅 필요"·"실패"를 이미 썼으면 덮어쓰지 않는다(재부팅해야 훅이 켜진다)
  if setup_done && { [ ! -f $PROG ] || $BB grep -q '^state=done$' $PROG 2>/dev/null; }; then
    # 1.7.4(D-14 문구, 묶음 E 리뷰): 상태 화면 판정·stock_ap_ready와 같은 문구(폰 안내를 붙이지 않음)
    prog 100 done "무선 프로젝션 준비됨."
  fi
  # 1.7.2(P-7): 우리 핫스팟을 켠 뒤에 순정 AP 저장값을 맞춘다(settings가 몇 초 걸려도 핫스팟은 이미 켜져 있음)
  apon_off
  # 1.8.1 W-8: NEMESIS LivePatch 상태를 한 번 읽는다(핫스팟을 켠 뒤라 늦어져도 연결에 영향 없음, 최대 LPF_WAIT초)
  lp_probe
  n=0
  while true; do
    # 시험판 6(F3): 뽑기 감시가 동글이 다시 잡힌 것을 보면 이 쉬기를 깨운다(dg_wake). pid와 부팅 id를 남긴다(동글 길 부팅만).
    # 점검 중에 온 깨우기(표시 $W/dgwake)가 있으면 이번 쉬기를 건너뛴다
    if [ "$DG_RUN" = 1 ] && [ -f $W/dgwake ]; then
      rm -f $W/dgwake
    elif [ "$DG_RUN" = 1 ]; then
      sleep 30 &
      echo "$! ${BID:-none}" 2>/dev/null > $W/tick.slp
      wait $!
      rm -f $W/dgwake
    else
      sleep 30 &
      wait $!
    fi
    # 묶음 H 재리뷰(중간 2): 30초 점검 회차 번호(up()이 "띄운 회차와 다른 회차에서 살아 있음"을 볼 때 씀)
    TICK_N=$((${TICK_N:-0}+1))
    perf_begin
    logrotate
    # 리뷰 L1: 제보 요청은 다른 hostapd에 비켜 주는 동안(ap_yield)에도 본다
    req_tick
    ap_yield && continue
    ap_tick
    conf_tick
    ap_src_retry
    up
    aa_sig
    fw_aa_sync
    pf_mark; wifi_events; pf_lap TW; aa_events; pf_lap TA; cp_watch
    hint_tick
    # 베타 3(B3-4): 상태 화면을 연 동안(감시자가 살아 있음)은 30초마다 한 번 상태 파일을 새로 씀(판정이 바뀐 것을 잡게)
    st_alive $W/watch.pid --watch && st_push
    n=$((n+1))
    # once an hour: one line with the CarPlay connections
    [ $((n % 120)) -eq 0 ] && log "동작 중: $(cp_count) 개 카플레이 연결"
    # 1.7.2(P-7, 리뷰 M2): 10분마다 순정 AP 저장값을 다시 본다(0이면 settings get 한 번뿐, 로그 없음)
    { [ $((n % 20)) -eq 0 ] || [ "$APON_AGAIN" = 1 ]; } && apon_off
    # 1.7.4 베타 2(측정): 이번 점검에 걸린 시간과 내비 부하·Wi-Fi 숫자를 한 줄로(프로세스를 띄우지 않음)
    perf_tick
  done
}

[ "$HOTSPOT_LIB" = 1 ] || main
