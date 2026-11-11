#!/system/bin/sh
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
# 짧게 유지: busybox ps가 명령줄을 약 80칸에서 잘라 "hostapd <경로>"가 약 50자를 넘으면 찾지 못한다
CONF=${CONF:-/data/misc/wifi/hostapd-kp.conf}
W=${W:-/data/local/tmp/korea.projection}
AP_IP=192.168.43.1
# 1.7.0 무선 안드로이드 오토: 우리 hostapd가 도는 동안 시스템 속성 AAPROP=1을 건다(기본 켜짐, 2026-11-08 소유자 결정:
# 니로에서 첫·두 번째 연결과 카플레이 복귀를 확인함). HMG-API 모드(2.2.0, AaWifi)가 이 값이 1일 때만 GPM·PhoneProjection
# 안에서 "AP 켜짐, 모드 2"로 답한다. 속성은 재부팅하면 사라진다.
# 끄기: 설치·Launch 때 USB 맨 위의 kp-aa-off → $BK/aa-off(업데이트해도 남고 삭제하면 지워짐). 다시 켜기: kp-aa-on.
AAOFF=${AAOFF:-${BK:-/data/nemesis/backup/korea.projection}/aa-off}
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
CARS_SEEN='IGPE.KOR.*.260902 IGPE21.KOR.*.260902 IGPEHEV.KOR.*.260902 DN822HEV.KOR.*.260902 JSN.KOR.*.260902 LX2.KOR.*.260902 CN7.KOR.*.260902 CN7HEV.KOR.*.260902 TMFL.KOR.*.260902 AX1.KOR.*.260902 DN8.KOR.*.260902 NX4HEV.KOR.*.260902 NX4.KOR.*.260902 DEPEHEV.KOR.*.260902 DEPEPHEV.KOR.*.260902 SG2EV.KOR.*.260902 DL3HEV.KOR.*.260902 DL3HEV22.KOR.*.260902 YGPE.KOR.*.260902 YGPEHEV.KOR.*.260902 MQ422HEV.KOR.*.260902 MQ422.KOR.*.260902 MQ4HEV.KOR.*.260902 BDPE.KOR.* GL3HEV.KOR.*.260902 OSEV.KOR.*.260902 CKPE.KOR.*.260902 SK3EV.KOR.*.260902 SP221.KOR.*.260902 IKFL.KOR.*.260902'
# 1.7.3(G-4): 차종 코드만 같고 내비 버전(펌웨어 끝 6자리 날짜)이 다를 때를 보려고, 버전을 빼고 차종 코드만 본다
car_model_seen() {
  _cm=${1%%.*}
  for _cs in $CARS_SEEN; do [ "${_cs%%.*}" = "$_cm" ] && return 0; done
  return 1
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

# the head unit's busybox (1.8.1) od only knows -b: bytes come as 3-digit octal
# octal bytes -> string
# 1.7.3(K-3): 바이트마다 하위 셸로 printf를 부르던 것을 printf 한 번으로. 형식 문자열은 "\NNN"(8진 이스케이프)만으로 만들어
# % 나 \ 같은 글자도 이스케이프로만 들어간다(형식 지시자로 읽히지 않음). 결과는 예전과 바이트까지 같다(stub-test 비교)
decode() {
  _f=""
  for _b in "$@"; do _f="$_f\\$_b"; done
  $BB printf "$_f\n"
}

# one 3-digit octal byte -> decimal (digit by digit: no leading-zero ambiguity)
# 1.7.3(K-3): 결과를 echo로 내지 않고 _d에 넣는다(바이트마다 $(…) 하위 셸이 생기지 않게)
o2d() {
  _r=${1#?}
  _d=$(( ${1%??}*64 + ${_r%?}*8 + ${_r#?} ))
}

# softap.conf on this unit (version 3) isn't stock WifiApConfigStore: Java writeUTF strings
# (2-byte length + bytes): S1 hotspot SSID, S2 CarPlay SSID, S3, S4 CarPlay passphrase.
# Lengths are checked before any arithmetic: a bad $(( )) kills the whole script.
parse_conf() {
  NS=0
  [ -s "$1" ] || return 1
  # od -b lines: 7-digit offset, then 3-digit bytes; keep the bytes only
  set -- $(for _t in $($BB od -b -v "$1"); do [ ${#_t} -eq 3 ] && echo $_t; done)
  N=$#
  [ $N -ge 4 ] || return 1
  i=0
  for _t in "$@"; do o2d $_t; eval "o$i=$_t; b$i=$_d"; i=$((i+1)); done
  i=0
  while [ $((i+2)) -lt $N ]; do
    eval "_L=\$(( b$i*256 + b$((i+1)) ))"
    if [ $_L -ge 1 ] && [ $_L -le 63 ] && [ $((i+2+_L)) -le $N ]; then
      _ok=1; j=$((i+2))
      while [ $j -lt $((i+2+_L)) ]; do
        eval "_v=\$b$j"
        if [ $_v -lt 32 ] || [ $_v -gt 126 ]; then _ok=0; break; fi
        j=$((j+1))
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
write_conf() {
  $BB cat > $CONF <<CONFEOF
interface=wlan0
driver=nl80211
ctrl_interface=/data/misc/wifi/hostapd
ssid=$S2
channel=149
hw_mode=a
ht_capab=[HT40+][SHORT-GI-20][SHORT-GI-40]
ieee80211n=1
max_num_sta=5
ignore_broadcast_ssid=0
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_passphrase=$S4
CONFEOF
  # hostapd drops to the wifi user (1010): readable like the stock hostapd.conf
  $BB chown 1000:1010 $CONF; $BB chmod 660 $CONF
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
  if [ "$S2" = "$_o2" ] && [ "$S4" = "$_o4" ]; then
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
  CONF_SIG=$_ns
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

# a live process by name; a zombie ([hostapd], state Z) doesn't count
running() { $PS | $BB grep -v grep | $BB grep -v " Z " | $BB grep -q "$1"; }
# 우리 것이 아닌 hostapd(순정 핫스팟)가 살아 있는가: 우리 것은 설정 파일 경로($CONF)로 가린다
stock_ap_on() { $PS | $BB grep -v grep | $BB grep -v " Z " | $BB grep -v "$CONF" | $BB grep -q hostapd; }

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
other_hostapd_pids() { $PS | $BB grep -v grep | $BB grep -v " Z " | $BB grep -v "$CONF" | $BB grep hostapd | $BB awk '{print $1}'; }
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
  if [ $_sn -ne 1 ] || [ -z "$_ss" ] || [ "${NS:-0}" -lt 4 ] || [ ${#S2} -lt 1 ] || [ "$S1" = "$S2" ]; then echo unknown
  elif [ "$_ss" = "$S2" ]; then echo carplay
  elif [ "$_ss" = "$S1" ]; then echo hotspot
  else echo other; fi
  return 0
}
# 우리 dnsmasq가 살아 있는가: DNSPID의 pid가 이번 부팅의 것이고 이름이 dnsmasq일 때만(/data/local/tmp는 재부팅 뒤에도
# 남아 예전 pid가 순정 dnsmasq를 가리킬 수 있다)
our_dhcp_on() {
  [ -f $DNSPID ] || return 1
  read _dp _db < $DNSPID
  case "$_dp" in ''|*[!0-9]*) return 1 ;; esac
  [ "$_db" = "${BID:-$(cat $BOOT_ID 2>/dev/null)}" ] && [ -r $PROC/$_dp/stat ] || return 1
  read _dx _dc _dr < $PROC/$_dp/stat
  [ "$_dc" = "(dnsmasq)" ]
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
    _mv=$(logcat -d -v time 2>/dev/null | $BB grep 'wifi_get_module_version:' | $BB awk '{ v = $NF } END { gsub(/[^0-9]/, "", v); print v }')
    echo "판정 근거: 순정 module_version=${_mv:-없음} (3이면 순정 Wi-Fi 서비스도 Wi-Fi 하드웨어가 없다고 봄, 1이면 부품 있음)"
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
# 1.7.3(K-4): **이어진 실패**로 되풀이되는 줄은 3번까지만 남기고, 4번째에 "더 남기지 않음" 한 줄을 남긴다.
# 횟수는 성공하면(hostapd가 살아 있음, wpa_supplicant가 없음) 부르는 쪽이 0으로 되돌린다(리뷰 M-1: 정상 다시 시작은 늘 남김).
# 기록만 줄이고 다시 시도하는 동작은 그대로다. $1 횟수 변수, $2 줄, $3 그만 쓸 때 앞말
log_cap() {
  eval "_lc=\$((\${$1:-0}+1)); $1=\$_lc"
  if [ $_lc -le 3 ]; then log "$2"
  elif [ $_lc = 4 ]; then log "$3: 이번 실행에서는 이 기록을 더 남기지 않음"; fi
}
up() {
  $BB ifconfig wlan0 $AP_IP netmask 255.255.255.0 up 2>/dev/null
  if ! running "hostapd $CONF"; then
    hostapd $CONF >/dev/null 2>&1 &
    sleep 4
    $BB ifconfig wlan0 $AP_IP netmask 255.255.255.0 up 2>/dev/null
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
      fi
    else
      nowlan_now || log "hostapd 시작"
      HA_STARTS=0; HA_DIES=0
      [ -f $NOWLAN ] && { rm -f $NOWLAN; log "Wi-Fi 장치(wlan0)가 생겨 hostapd가 켜짐"; }
      # 재리뷰 중간 3①: 우리 hostapd가 켜지면 wlan0이 안 생긴 부팅 수를 지운다($BK는 업데이트에도 남고 $W의 NOWLAN은 지워지므로 따로)
      rm -f $BK/nowlan.boots
    fi
  fi
  if ! our_dhcp_on; then
    # same style as netd: bare --pid-file (no /var/run here)
    dnsmasq --keep-in-foreground --no-resolv --no-poll --dhcp-authoritative --pid-file \
      --interface=wlan0 --bind-interfaces \
      --dhcp-range=192.168.43.10,192.168.43.50,255.255.255.0,1h --dhcp-option=3 --dhcp-option=6 >/dev/null 2>&1 &
    echo "$! ${BID:-$(cat $BOOT_ID 2>/dev/null)}" > $DNSPID
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
  if our_dhcp_on; then
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
  stop_ours
  killlog
}
# AA 신호를 맞춘다. 인자가 있으면 그 값(0)으로, 없으면 켜기 파일·우리 hostapd·wlan0 주소·순정 AP 기록으로 정한다.
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
    on) echo "켜짐" ;; off) echo "끄기 파일(kp-aa-off)" ;; stockap) echo "순정 카플레이 AP 기록(stockap.seen)" ;;
    nohostapd) echo "우리 hostapd 없음" ;; noaddr) echo "wlan0에 우리 AP 주소 없음" ;; yield) echo "다른 hostapd에 비켜 줌" ;;
    *) echo "핫스팟 멈춤" ;;
  esac
}
# wlan0에 우리 AP 주소($AP_IP)가 있는가(ifconfig의 inet addr)
wlan_has_ip() {
  [ "$($BB ifconfig wlan0 2>/dev/null | $BB awk '/inet addr:/ { a = $0; sub(/.*inet addr:/, "", a); sub(/ .*/, "", a); print a; exit }')" = "$AP_IP" ]
}
aa_sig() {
  _a=${1:-}; _why=${2:-stop}
  if [ -z "$_a" ]; then
    _a=0
    if [ -f $AAOFF ]; then _why=off
    elif [ -f $BK/stockap.seen ]; then _why=stockap
    elif ! running "hostapd $CONF"; then _why=nohostapd
    elif ! wlan_has_ip; then _why=noaddr
    else _a=1; _why=on; fi
  fi
  [ "$_why" = "$(cat $AAWHY 2>/dev/null)" ] || echo "$_why" 2>/dev/null > $AAWHY
  if [ "$_a" = "$(getprop $AAPROP 2>/dev/null)" ]; then
    # 리뷰 M-2: Launch(kp-aa-off)가 신호를 먼저 내렸으면 속성은 이미 0이다. 서비스에 남은 "준비됨" 안내도 지운다.
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
  return 0
}
# AA 안내 바꾸기: $1 코드(bt|cpwait|ok|빈 값), $2 ap.log에 남길 이유. 같은 값이면 아무것도 하지 않는다.
aa_hint() {
  # 재리뷰 M3: 연결됨(ok)을 새로 받으면 그 전의 "0대가 됨"은 지난 일이다. 확인 리뷰 M2: 단, 지금 붙은 기기가 있을 때만
  # (한 회차 안에 붙었다 끊긴 뒤 늦게 온 ok가 0대 기록을 지워 ok가 남는 것을 막음)
  [ "$1" = ok ] && [ "${WSTA:-0}" -gt 0 ] && WGONE=
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
# aa_events가 넘긴 판정(F 줄) 하나를 처리한다. iap·iapd(아이폰)는 신호와 상관없이, AA 안내는 켜기 파일이 있고 신호가 1인 차만.
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
  esac
  { [ ! -f $AAOFF ] && [ "$(getprop $AAPROP 2>/dev/null)" = 1 ]; } || return 0
  case "$1" in
    unkpre) aa_hint bt "신호보다 먼저 AP 모드를 물음" ;;
    sppfail) aa_hint bt "헤드유닛 쪽 블루투스 다시 연결 거절" ;;
    giveup) aa_hint bt "폰 프로젝션이 다시 시도를 포기함" ;;
    cpwait) aa_hint cpwait ;;
    ok) aa_hint ok ;;
    clr) case "$HA" in bt|cpwait) aa_hint "" "AP 켜짐 확인" ;; esac ;;
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
  if [ "$HA" = ok ] && [ "$WGONE" = 1 ] && [ "${WSTA:-0}" = 0 ]; then aa_hint "" "우리 Wi-Fi에 붙은 기기가 0대가 됨(무선 AA 끊김으로 봄)"; fi
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
    prog 100 done "무선 카플레이 준비됨(내비 Wi-Fi 사용). 아이폰을 연결해 보세요."
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
  # 디버그 로그(차주가 USB 파일로 켰을 때만)는 순정 AP 차에서도 남긴다(리뷰 L2)
  logstart
  rm -f $CPN
  wifi_events; aa_events; cp_watch
  while true; do
    # 1.7.3(R-4): 이 회차는 60초지만 제보 요청은 30초마다 본다(앱의 기다림 표시와 맞게)
    sleep 30 & wait $!
    req_tick
    sleep 30 &
    wait $!
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
    wifi_events; aa_events; cp_watch
    req_tick
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
WLAN=${WLAN:-/sys/class/net/wlan0}
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
APON_ORIG=${APON_ORIG:-${BK:-/data/nemesis/backup/korea.projection}/wifi_ap_on.orig}
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
  settings put global wifi_ap_on 0 >/dev/null 2>&1
  if [ "$(apon_get)" = 0 ]; then
    log "순정 AP 저장값(wifi_ap_on) 1 → 0: 다음 부팅부터 순정이 AP를 켜지 않음(원래 값 $(cat $APON_ORIG 2>/dev/null), 삭제할 때 되돌림)"
  else
    [ -z "$APON_FAIL" ] && log "순정 AP 저장값(wifi_ap_on)을 0으로 바꾸지 못함(지금 값 $(apon_get))"
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
# 베타 2 차주 제보(#64): BK는 이 아래(1575행 근처)에서 정해진다. 예전 "${KTB:-$BK/ktime}"은 차에서 /ktime이 되어
# "can't create /ktime: Read-only file system"을 남기고 C 고침이 동작하지 않았다. AAOFF·APON_ORIG처럼 BK의 기본값을 함께 쓴다
KTB=${KTB:-${BK:-/data/nemesis/backup/korea.projection}/ktime}
UPTIME=${UPTIME:-/proc/uptime}
CPN=${CPN:-$W/cpn}
wifi_events() {
  _bid=$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null); _bid=${_bid:-none}
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
      # 재리뷰 M3: 끊김·AP 다시 올라옴으로 0대가 되면 WGONE=1(무선 AA "연결됨"을 지우는 근거, hint_tick)
      "D") [ "$WSTA" -gt 0 ] && WSTA=$((WSTA - 1)); [ "$WSTA" = 0 ] && WGONE=1 ;;
      "L") WSTA=0; WGONE=1 ;;
      "T "*) _kt=${_l#T } ;;
    esac
  done < $W/kev
  rm -f $W/kev
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
aa_events() {
  _bid=$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null); _bid=${_bid:-none}
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
  logcat -d -v time 2>/dev/null | $BB grep -E ' [VDIWEF]/(AAProjection|PhoneProjection|HMG-API) *\(' \
    | $BB grep -E 'START_SPP_CONNECT_FOR_CONNECTIVITY|Sent WifiVersionRequest|wirelessSupported = |getWiFiApMode|isWifiApEnable = |Sent start request|MSG_WIFI_TRANSPORT_INIT retu|ACTION_WIRELESS_SPP_CONNECT_TIMEOUT|==> rfcommDisconnect|Already AA|isCheckReady ret = false|onSppConnect.. ret = false|connectivityConnectionTimeout|isConnectivityActivated return true|Connection status STATUS_|WifiTransport : .*onConnected|retry Wireless connection|canStartConnection = false|getWirelessConnection = false|bridge: iAP2 (dis)?connected comp=[14]|send requestWLDeviceReadyStatusUpdate|requestWLDeviceReadyStatusUpdate \[|PP Service is Running|onBTCMSppStatusChanged|AA 준비 다시 보냄|ready resend hook in |AA: timer error ' \
    | $BB awk -v last="$_last" -v max="$AAEV_MAX" -v on="$AA_ON_TM" -v now="${_ns:-0}" '
    # 찾는 글이 없으면 빈 값(줄 앞의 시각을 값으로 잘라 오지 않게, 리뷰 M2)
    function after(s,   i) { i = index($0, s); if (i == 0) return ""; return substr($0, i + length(s)) }
    # 값은 영문·숫자만, 8자까지(다른 글자는 지움: 이름 등이 섞여 나오지 않게)
    function word(s) { sub("^ +", "", s); sub("[ ,\t].*", "", s); gsub("[^0-9A-Za-z]", "", s); return substr(s, 1, 8) }
    # logcat 시각("MM-DD HH:MM:SS.mmm")의 하루 안 초
    function sod(t) { return substr(t, 7, 2) * 3600 + substr(t, 10, 2) * 60 + substr(t, 13) }
    # 상태 숫자만: 칸 전체가 숫자("1")나 괄호 친 숫자("(1)")일 때만 그 숫자(3자까지), 아니면 "?"(이름 조각이 섞여 나오지 않게)
    function num(s) { if (s !~ /^[(]?[0-9]+[)]?$/) return "?"; gsub("[^0-9]", "", s); return substr(s, 1, 3) }
    { tm = $1 " " $2; nw = (last == "" || tm > last)
      if (index($0, "isCheckReady ret = false") > 0) ck = sod(tm)
      if (!nw) next
      e = ""; f = ""; p = "안드로이드 오토: "
      if (index($0, "START_SPP_CONNECT_FOR_CONNECTIVITY") > 0) e = "블루투스로 연결 시작(SPP)"
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
      else if (index($0, "Connection status STATUS_") > 0) { v = word(after("STATUS_")); e = "폰 Wi-Fi 접속 " v; if (v == "SUCCESS") f = "ok" }
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
      else if (index($0, "AA 준비 다시 보냄") > 0) { v = after("AA 준비 다시 보냄"); gsub("[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]", "x", v); sub("^ +", "", v); e = "모드가 준비 다시 보냄 " v }
      else if (index($0, "ready resend hook in ") > 0) { v = after("ready resend hook in "); sub(" .*", "", v); gsub("[^A-Za-z0-9._]", "", v); e = "모드의 준비 다시 보내기 훅 걸림(" substr(v, 1, 60) ")" }
      # 확정 2.4.1: 모드의 타이머(계기판 이름 붙잡기 nameDue·tick)가 예외로 넘어감(연결마다 한 번). 종류(예외 이름)만 영문·숫자·점으로
      else if (index($0, "AA: timer error ") > 0) { v = after("AA: timer error "); sub(" .*", "", v); gsub("[^A-Za-z0-9._]", "", v); e = "모드 타이머 오류(" substr(v, 1, 60) ")" }
      if (e != "" && n < max + 0) { print "E " p e " (" $2 ")"; n++ }
      if (f != "") print "F " f
      if (mx == "" || tm > mx) mx = tm }
    END { if (mx != "") print "T " mx }' 2>/dev/null > $W/aaev
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
  _ci=wlan0
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
  if [ "${_n:-0}" != "${_o:-0}" ]; then log "카플레이 연결 ${_o:-0} → ${_n:-0}"; echo "${_n:-0}" > $CPN; fi
  return 0
}

# 30초마다 한 번: 잠금을 지키고(Wi-Fi 서비스가 설정 파일을 새로 만들었으면 다시 잠금), wpa_supplicant가 다시 떴으면
# 멈춘다. 연달아 SUPP_MAX번을 넘으면 잠금이 듣지 않는 것이라 한 번 알린다($BK/wifilock.told).
ap_tick() {
  # 바꿀 때만 로그를 남긴다(Wi-Fi 서비스가 파일을 다시 만들어 다시 잠근 일을 기록으로 남기려고)
  wifi_lock
  if running wpa_supplicant; then
    log_cap SUPP_LOGS "wpa_supplicant가 다시 켜져서 멈춤" "wpa_supplicant가 자꾸 다시 켜짐"
    $BB killall wpa_supplicant 2>/dev/null
    ns=$((ns+1))
    if [ $ns -gt $SUPP_MAX ] && [ ! -f $BK/wifilock.told ]; then
      $BB mkdir -p $BK; : > $BK/wifilock.told
      log "Wi-Fi 잠금이 듣지 않음: wpa_supplicant가 ${SUPP_MAX}번 넘게 이어서 다시 뜸"
      notice "Korea Projection: 무선 카플레이 핫스팟이 자꾸 끊깁니다. USB를 꽂고 Launch 화면의 [제보 파일 만들기]를 눌러 보내 주세요."
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
  stop_ap
  if fix_running; then set -- $(cat $W/fix.pid); kill $1 2>/dev/null; fi
  rm -f $W/fix.pid
  # 설치 중에 서비스가 멈추면 진행 기록이 "진행 중"으로 남지 않게(설치 작업을 멈춘 뒤에 쓴다)
  fix_busy && prog 100 fail "설치가 중간에 멈췄습니다. 내비를 재부팅하면 다시 진행합니다."
  return 0
}

# log.pid의 프로세스가 우리 로그 파이프의 마지막 단계일 때만 죽인다. 마지막 단계가 죽으면 앞의 awk·grep·logcat은 SIGPIPE로 끝난다.
# log.pid에는 logstart의 $!가 들어간다: 뒤에서 돌린 파이프라인의 $!는 마지막 명령($_u: "$BB uniq -c -f 2" 또는 "$BB grep .")의 pid다.
# 1.7.2(P-16): 예전에는 /proc/<pid>/cmdline을 grep으로 봤는데, cmdline은 인자를 NUL로 나누고 busybox 1.8.1 grep은 첫 NUL에서
# 줄을 끊는다. 첫 인자가 "/system/bin/busybox"라 logcat|grep|uniq에 맞지 않아 로거를 멈추지 못했다(FINDINGS 2748행).
# 이제는 NUL이 없는 /proc/<pid>/stat의 이름 칸(busybox 애플릿이면 "(busybox)", toolbox면 "(grep)" 등)을 보고, pid와 함께
# 적어 둔 부팅 id가 이번 부팅과 같을 때만 죽인다(/data/local/tmp는 재부팅 뒤에도 남아 예전 pid가 다른 프로세스를 가리킬 수 있다).
# 부팅 id가 없는 예전 형식(1.7.1까지)은 죽이지 않는다(예전과 같은 결과).
killlog() {
  _p=; _pb=
  [ -f $W/log.pid ] && read _p _pb < $W/log.pid
  case "$_p" in ''|*[!0-9]*) _p= ;; esac
  if [ -n "$_p" ] && [ -n "$_pb" ] && [ "$_pb" = "${BID:-$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)}" ] && [ -r $PROC/$_p/stat ]; then
    read _k1 _k2 _kr < $PROC/$_p/stat
    case "$_k2" in "(busybox)"|"(uniq)"|"(grep)") kill $_p 2>/dev/null ;; esac
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
  # busybox에 uniq가 없거나 -f를 모르면 줄이지 않고 그대로 남긴다 (로그가 아예 끊기지 않게)
  if echo x | $BB uniq -c -f 2 >/dev/null 2>&1; then _u="$BB uniq -c -f 2"; else _u="$BB grep ."; fi
  # grep이 DROP 정규식을 못 받으면(종료 코드 2) 파이프가 조용히 끝나 로그가 비므로, 그때는 아무 줄도 버리지 않는다
  _d=$DROP; echo x | $BB grep -E "$_d" >/dev/null 2>&1; [ $? -le 1 ] || _d='^$'
  # 1.5.6: 안드로이드 오토는 폰에 Wi-Fi 이름·비밀번호를 보낸다. 그런 값이 나올 수 있는 줄은 태그와 상관없이 버린다.
  # "psk"는 값이 붙는 꼴(psk=, psk:)만 버린다: 보안 방식 줄("Auth Type : WPA2_PSK")은 원인을 찾는 데 필요하다(2026-11-07).
  # 1.7.0: 폰 이름·MAC·IP·VIN·전화번호를 가린다(KPMASK). 가리기 awk가 이 busybox에서 안 되면 디버그 로그를 남기지 않는다.
  echo "x" | $BB awk "$KPMASK" >/dev/null 2>&1 || { log "디버그 로그 안 남김: 가리기(awk)가 이 busybox에서 안 됨"; return 0; }
  logcat -v time 2>/dev/null | $BB grep -E "$TAGS" | $BB grep -v -E "$_d" | $BB grep -v -i -E 'ssid|psk *[=:]|passphrase|password|bssid|key=' | $BB awk "$KPMASK" | $_u >> $W/cp.log &
  # 1.7.2(P-16): pid와 부팅 id를 함께(killlog가 이번 부팅의 것인지 본다)
  echo "$! ${BID:-$(cat ${BOOT_ID:-/proc/sys/kernel/random/boot_id} 2>/dev/null)}" > $W/log.pid
}
# 파이프를 다시 시작하지 않고 파일만 밀어낸다: 다시 시작하면 logcat이 버퍼 전체를 다시 써서
# 몇 분 치가 겹쳐 쌓였다(run3). uniq는 >>(O_APPEND)로 열었으므로 cp.log를 비우면 처음부터 다시 쓴다.
# 복사와 비우기 사이에 들어온 몇 줄은 잃을 수 있다(디버그용이라 감수).
logrotate() {
  aplog_rotate
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
# 서비스 점검의 백업 경로(D-2): Launch가 띄운 감시자(status.sh --watch, 10분)가 끝난 뒤 눌러도 다음 점검(30초)에서 시작한다.
# 받을 요청(req_peek)이 있고 감시자·다른 제보 만들기가 없을 때만 띄운다. 이전 부팅·이미 받은 요청은 띄우지 않는다
# (root가 요청 파일을 지우지 못해도 30초마다 다시 띄우지 않게, 리뷰 중간 1). 요청을 받고 지우는 일은 status.sh --report가 한다.
# 무엇이 실패해도 0을 돌려준다(서비스 반복이 멈추지 않게, mode=restart).
req_tick() {
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
BK=${BK:-/data/nemesis/backup/korea.projection}
# 1.7.2(P-14): fix_perms가 새로 쓴 권한 파일 이름(한 줄에 하나). 패키지를 지울 때 perms_revert가 읽는다.
PERMS_OURS=${PERMS_OURS:-$BK/perms.ours}
MOD_ID=wireless-carplay-aa
# 패키지에 든 모드 zip의 md5 (busybox 1.8.1에 sha256sum이 없다). zip을 바꾸면 함께 바꾼다.
MOD_MD5=0667dff0a8469241689baf13e36e41f9
# 패키지에 든 모드의 버전(mod.json "version"). 1.5.7부터 차에 있는 우리 모드가 이것과 다르면 바꾼다(mod_update).
MOD_VER=2.4.1
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
#   2 예전에 깨우기를 해 봄(1.7.2까지의 기록, 다시 안 함), 3 아직 확인 중(다음 부팅에 다시 깨움, 1.7.3 W-4·G-1)
wifi_chip_seen() {
  [ -f $WIFI_SEEN ] || [ -n "$(ls $SDIO 2>/dev/null)" ]
}
wifi_was_off() {
  [ -f $BK/wifi_on ] && [ "$(cat $BK/wifi_on 2>/dev/null)" != 1 ]
}
# 뒤에서 돌린 svc wifi enable 정리: 아직 돌면 멈추고, 끝났으면 실패한 종료 코드만 기록한다(제보 분석용)
svc_done() {
  if kill -0 $1 2>/dev/null; then
    kill $1 2>/dev/null; log "svc wifi enable이 끝나지 않아 멈춤"
  else
    wait $1; _rc=$?
    [ $_rc = 0 ] || log "svc wifi enable 실패 (종료 코드 $_rc)"
  fi
}
# 1.7.3(W-1~W-4·W-6): Wi-Fi 판정 문구. 진행 기록·알림·상태 화면 판정(status.sh kp_verdict)이 같은 문장을 쓴다
WIFI_CHECK_MSG="Wi-Fi를 켜는 중입니다(재부팅 뒤 한 번 더 확인). 내비를 재부팅해 주세요."
DONGLE_MSG="USB Wi-Fi 동글로 쓰는 방법을 준비하고 있습니다."
NOPART_MSG="이 차의 내비에는 Wi-Fi 부품이 없어 무선 카플레이를 쓸 수 없습니다. $DONGLE_MSG"
NOCHIP_MSG="이 차는 Wi-Fi 칩이 켜지지 않아 지원하기 어렵습니다. $DONGLE_MSG"
# 1.7.3(W-1·W-4·G-1): 순정 module_version(마지막 값, 숫자만). 찾으면 $BK/wifi.modver에도 남긴다(로그 버퍼가 밀려도 다음 부팅에 쓰게).
# 3이면 순정 Wi-Fi 서비스도 Wi-Fi 하드웨어가 없다고 본다(#50·#58·#99). 모르면 빈 값
wifi_modver() {
  _mv=$(logcat -d -v time 2>/dev/null | $BB grep 'wifi_get_module_version:' | $BB awk '{ v = $NF } END { gsub(/[^0-9]/, "", v); print v }')
  if [ -n "$_mv" ]; then [ -d $BK ] && echo "$_mv" > $BK/wifi.modver; echo "$_mv"; else cat $BK/wifi.modver 2>/dev/null; fi
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
# 1.7.3(D-9, 소유자 결정 2026-11-10): 1.7.2까지 한 번 깨우고 wifi.nochip으로 굳은 차. 남은 근거 기록의 module_version이 숫자이고
# 3이 아니며 wifi.wake가 없으면, 첫 깨우기를 1번째로 쳐서 다음 부팅 2번까지 더 깨운다(그 뒤 칩 실패). 3이거나 근거가 없으면 그대로.
legacy_nochip_retry() {
  [ -f $BK/wifi.nochip ] && [ ! -f $BK/wifi.wake ] || return 1
  _lv=$($BB grep -h '^판정 근거: 순정 module_version=' $BK/nochip-wifi.txt $NOCHIP_LOG 2>/dev/null | $BB awk '{ v = $0 } END { sub(/^판정 근거: 순정 module_version=/, "", v); sub(/[^0-9].*/, "", v); print v }')
  # 합치기(이슈 조사 ①): 근거가 3이면 부품이 없는 차다(#120·#158·#139·#156 꼴). 동작은 그대로(깨우지 않음)이고 기록만
  # wifi.nopart로 옮겨 W-1 "부품 없음" 문구가 나오게 한다(예전에는 W-2 "칩이 켜지지 않아"가 나왔다)
  if [ "$_lv" = 3 ]; then
    : > $BK/wifi.nopart && rm -f $BK/wifi.nochip && log "1.7.2까지의 칩 없음 기록: 근거 module_version=3이라 부품 없음 기록으로 옮김(깨우지 않음)"
    return 1
  fi
  case "$_lv" in ''|*[!0-9]*) return 1 ;; esac
  echo "1 legacy" > $BK/wifi.wake || return 1
  # 1.7.2까지는 깨우기 전에 wifi.woke를 썼다(칩을 본 기록이 아님): 함께 지운다
  rm -f $BK/wifi.nochip $BK/wifi.woke
  log "1.7.2까지의 칩 없음 기록을 다시 확인함: 근거 module_version=$_lv(3 아님), 다음 부팅 2번까지 더 깨움"
  return 0
}
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
  # 1.7.3(D-9): 1.7.2까지 남은 wifi.nochip(한 번 깨워 실패)은 근거 module_version이 3이 아닐 때만 2번 더 깨운다(legacy_nochip_retry).
  _rechk=0
  legacy_nochip_retry
  # 옛 기록이 부품 없음으로 옮겨졌으면 깨우지 않고 끝낸다
  [ -f $BK/wifi.nopart ] && return 1
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
  if ! { $BB mkdir -p $BK && echo "$_wc $_bid" > $BK/wifi.wake; }; then
    log "깨우기 횟수를 기록하지 못해 Wi-Fi를 깨우지 않음"
    return 2
  fi
  log "Wi-Fi 칩이 아직 안 보임: Wi-Fi를 한 번 켜서 칩을 깨움(부팅 $_wc/$WAKE_BOOTS번째)"
  ptrack 62 run "Wi-Fi 칩을 깨우는 중입니다"
  notice "Korea Projection: 무선 카플레이 준비로 Wi-Fi를 한 번 켭니다. 카플레이·블루투스가 잠시 끊길 수 있습니다."
  # svc는 뒤에서 돌린다: 시스템 서버가 멈춰 있으면 바인더 호출이 끝나지 않을 수 있어, 아래 대기 시간이 상한이 된다
  svc wifi enable > /dev/null 2>&1 &
  _sp=$!
  _i=0
  while [ $_i -lt ${WAKE_MAX:-30} ]; do
    sleep 2
    if wifi_chip_seen; then
      svc_done $_sp; log "Wi-Fi 칩이 나타남"
      # 칩이 한 번 보였다: 그 뒤 사라져도 부팅마다 다시 켜지 않는다(예전 wifi.woke 뜻 그대로)
      : > $BK/wifi.woke
      [ $_rechk = 1 ] && rm -f $BK/wifi.nochip
      return 0
    fi
    _i=$((_i+1))
  done
  svc_done $_sp
  wifi_record "칩 깨우기 실패" $NOCHIP_LOG
  # 1.7.2 리뷰 M-1: $W는 업데이트 때 지워지므로 근거 사본을 $BK에도 둔다(업데이트 뒤 칩 없는 차가 Wi-Fi를 다시 켜지 않게)
  [ -s $NOCHIP_LOG ] && cat $NOCHIP_LOG 2>/dev/null > $BK/nochip-wifi.txt
  wifi_restore_off
  # 깨운 뒤 순정이 module_version 3을 남겼으면 부품 없음(W-1)
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
  ptrack 70 run "무선 모드를 새 판($MOD_VER)으로 바꾸는 중입니다"
  if ! hmgapid engine install $KP_HMG/$MOD_ID.zip > $W/mod-update.txt 2>&1; then
    log "무선 모드 업데이트 실패($_un/3), 이전 판($_iv) 그대로 ($W/mod-update.txt)"
    [ $_un -lt 3 ] && return 1
    LAST_MSG="무선 모드를 새 판으로 바꾸지 못했습니다. 카플레이는 이전 판으로 계속 됩니다."
    return 2
  fi
  log "무선 모드 업데이트함: $_iv → $MOD_VER"
  hmgapid engine plan > $W/plan.txt 2>&1
  if plan_nothing; then
    return 0
  fi
  log "무선 모드 적용은 차주에게 맡김: 계획에 변경이 있음 ($W/plan.txt)"
  LAST_MSG="무선 모드를 새 판으로 바꿨습니다. 차를 세운 뒤 HMG-API 앱에서 변경 사항을 적용하고 내비를 재부팅해 주세요."
  return 2
}
# 1.7.1: 우리가 넣은 무선 모드가 패키지에 든 새 판으로 바뀌기를 기다리는 중인가(mod_update와 같은 조건, 리포트·상태 파일이 씀).
# mod_update는 부팅 약 2분 뒤 돌아서, 설치 직후 만든 리포트에는 이전 판이 찍혔다(K3 #15 1.7.0, 2026-11-08).
mod_pending() {
  [ -f $BK/mod.ours ] && [ ! -f $BK/mod.pin ] && [ -f $HMGDATA/mods/$MOD_ID/mod.json ] && mod_kor || return 1
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
    case "$_p$_q" in *[!0-9]*) return 1 ;; esac
    [ "${_p:-0}" -lt "${_q:-0}" ] && return 0
    [ "${_p:-0}" -gt "${_q:-0}" ] && return 1
    case "$_x" in *.*) _x=${_x#*.} ;; *) _x= ;; esac
    case "$_y" in *.*) _y=${_y#*.} ;; *) _y= ;; esac
    _k=$((_k + 1))
  done
  return 1
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
  ptrack 30 run "지도와 무선 모드를 확인하는 중입니다"
  $BB mkdir -p $BK
  # 1.6.1: 무선 모드가 없으면 "우리가 넣음"(mod.ours) 기록을 지운다. 남겨 두면 차주가 나중에 넣은 다른 판을
  # 우리 것으로 보고 안내하지 않거나, 패키지를 지울 때 그 모드를 지운다.
  # mod.tried는 남긴다(차주가 일부러 지운 우리 모드는 다시 넣지 않는다).
  [ -f $HMGDATA/mods/$MOD_ID/mod.json ] || rm -f $BK/mod.ours
  # _fail: 안내를 이미 남김(알림 기록 또는 LAST_MSG → 마지막 진행 기록 문구) → "설정을 마쳤습니다"로 덮지 않는다
  _restart=0; _fail=0; _upd=0; _wchk=0
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
      LAST_MSG="wireless.projection이 설치되어 있어 무선 카플레이를 설정하지 않았습니다. wireless.projection을 삭제한 뒤 내비를 재부팅해 주세요."
      if [ ! -f $BK/wp.told ]; then
        : > $BK/wp.told
        pnotice "Korea Projection: wireless.projection이 설치되어 있어 무선 카플레이를 설정하지 않았습니다. wireless.projection을 삭제한 뒤 내비를 재부팅해 주세요."
      fi
    elif stock_ap_on; then
      log "무선 설정 안 함: 다른 hostapd가 돌고 있음(순정 핫스팟 등) (다음 부팅에 다시 봄)"; _skip=1
      LAST_MSG="순정 핫스팟이 켜져 있어 이번에는 설정하지 않았습니다. 순정 핫스팟을 끄고 내비를 재부팅해 주세요."
    elif pm list features 2>/dev/null | $BB grep -q '^feature:com\.hkmc\.software\.wifihotspot$'; then
      log "순정 핫스팟 기능이 있지만 꺼져 있음: 우리 방식으로 진행"
    fi
  fi
  [ $_skip = 1 ] && _mapbad=1
  for _c in $KP_HMG/maps/*/*/*/*/car.json; do
    [ $_skip = 1 ] && break
    [ -f "$_c" ] || continue
    _d=${_c%/car.json}; _rel=${_d#$KP_HMG/maps/}
    [ "${_rel##*/}" = "${_prod##*.}" ] && $BB grep -q "\"$_pm\.$_pr\.\"" $_c || continue
    # 같은 폴더에 지도가 이미 있으면(공식판 등) 그것을 쓴다: 실패 기록보다 먼저 본다
    [ -f $HMGDATA/maps/$_rel/car.json ] && continue
    set -- $($BB md5sum < $_c); _sum=$1
    if has_line "$_rel $_sum" $BK/map.bad; then
      log "지도 넣지 않음: $_rel (이 차에서 지도 확인에 실패한 지도)"; _mapbad=1; continue
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
  # 넣지 않음, 패키지를 지우면 같이 지워진다). HMG-API 업데이트로 지도 폴더가 바뀌면 다음 부팅에 다시 만든다.
  # 이미 있는 지도(공식판, 차주가 만든 것)는 건드리지 않고, 확인만 한 번 한다(_myrel 없음 → 지우지 않음).
  _auto=0
  car_in "$_prod" "$CARS_OK $CARS_TRY" || _auto=1
  # 위에서 건너뛰기로 한 차는 자동 시험도 하지 않는다
  [ $_skip = 1 ] && _auto=0
  if [ $_auto = 1 ] && [ -f $BK/automap.bad ]; then
    log "자동 시험: 이 차에서 만든 지도가 확인에 실패한 기록이 있어 무선 모드를 넣지 않음"; _mapbad=1
  elif [ $_auto = 1 ] && [ $_mine = 0 ]; then
    _lm=$(echo "$_pm" | $BB awk '{ print tolower($0) }'); _lr=$(echo "$_pr" | $BB awk '{ print tolower($0) }')
    _have=0
    for _e in $HMGDATA/maps/*/$_lm/$_lr/${_prod##*.}/car.json; do [ -f "$_e" ] && _have=1; done
    if [ $_have = 1 ]; then
      [ -f $BK/automap.checked ] || { _mine=1; : > $BK/automap.checked; }
    elif [ -f $BK/automap.foreign ]; then
      # 다른 폴더 이름의 이 차 지도(공식판 등)를 쓰기로 했다: 무거운 map-car를 부팅마다 다시 돌리지 않는다
      :
    elif ptrack 40 run "이 차의 지도를 만드는 중입니다(1~2분)"; hmgapid engine map-car --write > $W/map-car.txt 2>&1; then
      _nw=0
      while IFS= read -r _l; do
        case "$_l" in
          "written: "*) _r=${_l#written: }; _myrel=${_r%%" ("*} ;;
          "not written: HMG-API has a map"*) _nw=1 ;;
        esac
      done < $W/map-car.txt
      case "$_myrel" in
        */*/*/*) _mine=1; echo "$_myrel" >> $BK/map.ours; log "자동 시험: 이 차의 파일로 지도를 만듦 ($_myrel)" ;;
        *)
          _myrel=
          if [ $_nw = 1 ]; then
            # 다른 폴더 이름으로 이 차 지도(공식판 등)가 이미 있다: 만들지 않고 그 지도를 한 번 확인한다(지우지 않음)
            log "자동 시험: HMG-API에 이 차 지도가 이미 있음 (그 지도를 씀)"
            : > $BK/automap.foreign
            [ -f $BK/automap.checked ] || { _mine=1; : > $BK/automap.checked; }
          else
            log "자동 시험: 지도를 만들지 않음 ($W/map-car.txt)"; _mapbad=1
          fi ;;
      esac
    else
      log "자동 시험: 지도 만들기 실패 ($W/map-car.txt)"; _fail=1; _mapbad=1; : > $BK/automap.bad
      notice "Korea Projection: 이 차의 HMG-API 지도를 만들지 못했습니다. USB를 꽂고 Launch 화면의 [제보 파일 만들기]를 눌러 보내 주세요."
    fi
  fi
  if [ $_mine = 1 ] && [ $_mapbad = 0 ]; then
    if ptrack 55 run "지도를 확인하는 중입니다"; hmgapid engine verify-map > $W/verify-map.txt 2>&1; then
      log "지도 확인 통과 (다음 시작부터 훅 켜짐)"; _restart=1
      [ $_auto = 1 ] && : > $BK/automap.checked
    else
      log "지도 확인 실패 ($W/verify-map.txt)"; _fail=1; _mapbad=1
      [ $_auto = 1 ] && : > $BK/automap.bad
      case "$_myrel" in *..*|/*) _myrel= ;; esac
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
      notice "Korea Projection: HMG-API 지도 확인에 실패했습니다."
    fi
  fi
  # 무선 모드: 지도가 잘못됐으면 하지 않는다(훅 없이 기능 파일·속성만 바뀌므로).
  # mod.tried는 설치에 성공했거나 다시 해도 같은 결과일 때(zip md5 다름)만 남긴다. 일시적인 실패
  # (앞의 apply가 안 끝남, 데몬이 바쁨)는 다음 부팅에 다시 한다.
  if [ $_mapbad = 0 ] && [ ! -f $HMGDATA/mods/$MOD_ID/mod.json ] && [ ! -f $BK/mod.tried ]; then
    set -- $($BB md5sum < $KP_HMG/$MOD_ID.zip 2>/dev/null)
    if [ "$1" != $MOD_MD5 ]; then
      : > $BK/mod.tried
      log "무선 모드 설치 안 함: 패키지의 zip md5가 다름 (${1:-없음})"
    elif wake_wifi; _wk=$?; [ $_wk != 0 ]; then
      # 칩이 없으면 HMG-API가 모드를 받지 않는다: 설치를 시도하지 않는다. 안내는 처음 한 번만 한다.
      log "무선 모드 설치 안 함: Wi-Fi 칩을 찾지 못함"
      if [ $_wk = 3 ]; then
        # 1.7.3(G-1·W-4): 아직 확인 중. 실패로 끝내지 않고 재부팅 뒤 다시 깨운다(진행 기록은 "재부팅 필요", 화면은 판정이 문구를 정함)
        _wchk=1
        LAST_MSG="$WIFI_CHECK_MSG"
      elif [ $_wk = 1 ]; then
        _fail=1
        if [ -f $BK/wifi.nopart ]; then LAST_MSG="$NOPART_MSG"; else LAST_MSG="$NOCHIP_MSG"; fi
        pnotice "Korea Projection: $LAST_MSG"
      fi
    elif ptrack 70 run "무선 모드를 설치하는 중입니다"; ! hmgapid engine install $KP_HMG/$MOD_ID.zip > $W/mod-install.txt 2>&1; then
      log "무선 모드 설치 실패, 다음 부팅에 다시 함 ($W/mod-install.txt, HMG-API 칩 기록 $([ -f $WIFI_SEEN ] && echo 있음 || echo 없음))"; _fail=1
      notice "Korea Projection: HMG-API 무선 모드를 설치하지 못했습니다."
    else
      : > $BK/mod.tried; : > $BK/mod.ours
      log "무선 모드 설치함"
      if ! plan_only_mod; then
        log "무선 모드 적용 안 함: 계획에 다른 변경이 있거나 훅이 꺼짐 ($W/plan.txt)"; _fail=1
        notice "Korea Projection: 무선 모드를 설치했습니다. HMG-API 앱에서 변경 사항을 적용한 뒤 내비를 재부팅해 주세요(RESET 버튼 또는 NEMESIS 재부팅)."
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
    LAST_MSG="차에 있는 HMG-API 무선 모드가 한국 차용이 아닙니다. HMG-API 앱에서 그 모드를 지우고 적용한 뒤 재부팅해 주세요."
    _fail=1
  fi
  # 진행 기록의 마지막 결과(상태 화면 앱이 보여 줌)
  if [ $_restart = 1 ] && [ $_fail = 0 ] && [ $_upd = 1 ]; then
    ptrack 100 reboot "무선 모드를 새 판($MOD_VER)으로 바꿨습니다. 내비를 재부팅해 주세요(RESET 버튼 또는 NEMESIS 재부팅)."
  elif [ $_restart = 1 ] && [ $_fail = 0 ]; then
    ptrack 100 reboot "무선 카플레이 설정을 마쳤습니다. 내비를 재부팅해 주세요(RESET 버튼 또는 NEMESIS 재부팅)."
  elif [ $_wchk = 1 ] && [ $_fail = 0 ]; then
    ptrack 100 reboot "$WIFI_CHECK_MSG"
  elif [ $_fail = 1 ]; then
    ptrack 100 fail "${LAST_MSG:-무선 카플레이 설정에 실패했습니다. USB를 꽂고 Launch 화면의 [제보 파일 만들기]를 눌러 보내 주세요.}"
  elif setup_done; then
    ptrack 100 done "무선 카플레이 설정이 끝나 있습니다."
  elif [ -f $HMGDATA/mods/$MOD_ID/mod.json ] && [ -z "$LAST_MSG" ]; then
    ptrack 100 fail "HMG-API 무선 모드가 있지만 꺼져 있거나 적용되지 않았습니다. HMG-API 앱에서 켜고 변경 사항을 적용한 뒤 내비를 재부팅해 주세요."
  elif [ -z "$LAST_MSG" ] && [ -f $BK/mod.tried ] && [ ! -f $HMGDATA/mods/$MOD_ID/mod.json ] \
      && [ "$(set -- $($BB md5sum < $KP_HMG/$MOD_ID.zip 2>/dev/null); echo "$1")" = $MOD_MD5 ]; then
    # 1.7.2(P-13, 이슈 #27 약속): 우리가 넣은 모드를 차주가 HMG-API 앱에서 지운 차. mod.tried가 남아 다시 넣지 않는다(차주 선택 존중).
    # "넣지 못했습니다"로 보이면 실패로 오해하므로 지운 기록과 다시 쓰는 방법을 알린다. (zip md5가 다른 경우는 아래 보통 문구)
    log "무선 모드 안 넣음: 차주가 HMG-API 앱에서 지운 기록(mod.tried)이 있음"
    ptrack 100 fail "무선 모드가 지워진 기록이 있어 다시 넣지 않습니다(HMG-API 앱에서 지웠거나 HMG-API를 다시 설치한 경우). 다시 쓰려면 NEMESIS에서 Korea Projection을 삭제하고 다시 설치한 뒤 내비를 재부팅해 주세요."
  else
    ptrack 100 fail "${LAST_MSG:-무선 모드를 넣지 못했습니다. USB를 꽂고 Launch 화면의 [제보 파일 만들기]를 눌러 보내 주세요.}"
  fi
  if [ $_restart = 1 ] && [ $_fail = 0 ] && [ $_upd = 1 ]; then
    pnotice "Korea Projection: 무선 모드를 새 판($MOD_VER)으로 바꿨습니다. 내비를 재부팅해 주세요(RESET 버튼 또는 NEMESIS 재부팅)."
  elif [ $_restart = 1 ] && [ $_fail = 0 ]; then
    if car_in "$_prod" "$CARS_OK"; then
      pnotice "Korea Projection: 무선 카플레이 설정을 마쳤습니다. 내비를 재부팅해 주세요(RESET 버튼 또는 NEMESIS 재부팅)."
    else
      pnotice "Korea Projection: 무선 카플레이 설정을 마쳤습니다(자동으로 설정한 차). 내비를 재부팅(RESET 버튼 또는 NEMESIS 재부팅)한 뒤 결과를 제보해 주시면 지원 목록에 넣습니다."
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
  # 1.7.2(P-14, 리뷰 L5): 1.7.1까지 쓴 권한 파일 이름을 ap.log에서 찾아 기록으로 옮겨 둔다(ap.log가 회전돼 사라지기 전에)
  [ -d $BK ] && [ ! -f $PERMS_OURS ] && { perms_seed; [ -f $PERMS_OURS ] || : > $PERMS_OURS; }
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
      ptrack $((5 + 20 * _wt / (_fd > 0 ? _fd : 1))) run "무선 모드를 새 판으로 바꾸기 전에 기다리는 중입니다(약 $((_fd - _wt))초). 재부팅 안내가 나오면 내비를 재부팅해 주세요."
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
    _i=$((_i+1)); [ $_i -ge 30 ] && { log "권한 파일 확인 건너뜀: HMG-API 데몬 응답 없음"; ptrack 100 fail "HMG-API가 응답하지 않습니다. 내비를 재부팅한 뒤 다시 확인해 주세요."; return 0; }
    sleep 10
  done
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
    _m="Korea Projection: 무선 카플레이 기능 파일을 복구했습니다. HMG-API 앱에서 변경 사항을 적용한 뒤 내비를 재부팅해 주세요(RESET 버튼 또는 NEMESIS 재부팅)."
  elif hmgapid engine apply >/dev/null 2>&1; then
    log "HMG-API apply 완료"
    _m="Korea Projection: 무선 카플레이 기능 파일을 복구했습니다. 내비를 재부팅해 주세요(RESET 버튼 또는 NEMESIS 재부팅)."
  else
    log "HMG-API apply 실패"
    _m="Korea Projection: 무선 카플레이 기능 파일을 복구했지만 HMG-API 적용이 실패했습니다. HMG-API 앱을 확인해 주세요."
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
APK_VC=36
app_current() { app_installed && [ "$(cat $BK/app.vc 2>/dev/null)" = "$APK_VC" ]; }
# 마지막 묶음 L1: 같은 판 설치 실패 횟수($BK/app.fail "<판> <횟수>"). 서명이 다른 앱이 깔린 차 등에서 부팅마다 되풀이하지 않게
# 옛 앱이 있으면 3번에서 멈춘다(그 뒤에도 상태 화면은 옛 앱으로 열린다). 앱이 아예 없으면 화면이 없으므로 지금처럼 부팅마다 한 번 해 본다
APP_FAIL_MAX=3
app_fail_n() { _af=; _an=0; [ -f $BK/app.fail ] && read _af _an < $BK/app.fail; [ "$_af" = "$APK_VC" ] || _an=0; case "$_an" in ''|*[!0-9]*) _an=0 ;; esac; echo $_an; }
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
    *Success*) rm -f $APK_COPY $BK/app.fail; bbx mkdir -p $BK 2>/dev/null; echo "$APK_VC" 2>/dev/null > $BK/app.vc; log "상태 화면 앱 설치됨"; return 0 ;;
    *) bbx mkdir -p $BK 2>/dev/null; echo "$APK_VC $(( $(app_fail_n) + 1 ))" 2>/dev/null > $BK/app.fail
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

main() {
  umask 077
  if ! has_bb; then
    log "시작 안 함: busybox가 없음 ($BB, 실행 안 됨). 이 내비는 아직 지원하지 않음(조사 중)"
    idle_forever
  fi
  $BB mkdir -p $W
  # 1.7.2(P-15): ap.log를 덧붙이기로 다시 열어 둔다(크기 제한 aplog_rotate가 비워도 이어서 쓰게)
  aplog_open
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
  prod=$(getprop ro.build.product)
  # svc, pm, HMG-API는 Android가 다 켜진 뒤에 쓴다
  while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 2; done
  # 시계가 맞춰진 뒤의 시각으로 다시 잡는다(경과 시간)
  PSTART=$(date +%s); PUSTART=$(prog_up)
  # 설치 진행 기록: 설정이 끝난 차는 "확인 중", 아니면 시작(5%). 끝난 차도 핫스팟이 켜지면 "준비됨"으로 바꾼다.
  # 같은 부팅에 서비스가 다시 시작돼도 "재부팅 필요"·"실패"는 덮지 않는다
  if prog_final_this_boot; then :
  elif setup_done; then prog 100 done "무선 카플레이 설정이 끝나 있습니다. 핫스팟을 켜는 중입니다."
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
      notice "Korea Projection: 무선 카플레이를 설정하는 중입니다. 약 5분 동안 내비를 재부팅하거나 끄지 마세요."
    fi
    # 1.7.3(R-4): 모드를 기다리는 차도 제보 요청은 30초마다 본다(모드 확인은 지금처럼 1분마다)
    while ! try_ready "$prod"; do sleep 30 & wait $!; req_tick; sleep 30 & wait $!; req_tick; done
    log "무선 모드 확인됨: 시작"
  fi
  parse_conf $SRC
  if [ "${NS:-0}" -lt 4 ] || [ ${#S2} -lt 1 ] || [ ${#S4} -lt 8 ]; then
    log "시작 안 함: $SRC 에서 문자열 4개를 찾지 못함 (${NS:-0}개)"
    setup_done && prog 100 fail "순정 카플레이 Wi-Fi 설정(softap.conf)을 읽지 못했습니다. 제보해 주세요."
    idle_req
  fi
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
    if [ "$BB" = "$BB_OWN" ] && [ ! -f $BK/stockap.seen ] && ! stock_ap_on; then
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
  log "시작 ($prod): softap.conf의 카플레이 SSID 길이 ${#S2}, 비밀번호 길이 ${#S4}"
  stop_ap
  # Wi-Fi 드라이버는 Wi-Fi를 켜야 올라오고, hostapd가 wlan0을 쓰려면 wpa_supplicant가 놓아야 한다(잠금 포함)
  take_wlan0
  logstart
  up
  aa_sig
  rm -f $CPN
  wifi_events; aa_events; cp_watch
  hint_tick
  # 설정이 끝난 차(재부팅 뒤 등)는 핫스팟이 켜지면 "준비됨". 설정 중이면 진행 기록은 fix_perms가 맡는다.
  # 이번 부팅에 "재부팅 필요"·"실패"를 이미 썼으면 덮어쓰지 않는다(재부팅해야 훅이 켜진다)
  if setup_done && { [ ! -f $PROG ] || $BB grep -q '^state=done$' $PROG 2>/dev/null; }; then
    prog 100 done "무선 카플레이 준비됨. 아이폰을 연결해 보세요."
  fi
  # 1.7.2(P-7): 우리 핫스팟을 켠 뒤에 순정 AP 저장값을 맞춘다(settings가 몇 초 걸려도 핫스팟은 이미 켜져 있음)
  apon_off
  n=0
  while true; do
    sleep 30 &
    wait $!
    logrotate
    # 리뷰 L1: 제보 요청은 다른 hostapd에 비켜 주는 동안(ap_yield)에도 본다
    req_tick
    ap_yield && continue
    ap_tick
    conf_tick
    up
    aa_sig
    wifi_events; aa_events; cp_watch
    hint_tick
    n=$((n+1))
    # once an hour: one line with the CarPlay connections
    [ $((n % 120)) -eq 0 ] && log "동작 중: $(cp_count) 개 카플레이 연결"
    # 1.7.2(P-7, 리뷰 M2): 10분마다 순정 AP 저장값을 다시 본다(0이면 settings get 한 번뿐, 로그 없음)
    [ $((n % 20)) -eq 0 ] && apon_off
  done
}

[ "$HOTSPOT_LIB" = 1 ] || main
