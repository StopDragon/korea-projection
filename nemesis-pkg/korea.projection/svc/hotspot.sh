#!/system/bin/sh
# korea.projection: the wireless CarPlay access point on Korean head units (tested: Niro DEPEHEV.KOR 260902;
# testing: Sonata DN822HEV.KOR 260902).
# There the stock hotspot call (setWifiApEnabledForConnectivity) does nothing, but the stock
# hostapd on wlan0 (nl80211) works. NEMESIS's svcmgr starts this at boot (mode=restart); it
# waits for Android, starts hostapd + dnsmasq with the CarPlay network from softap.conf, then
# keeps them up. Output goes to /data/nemesis/logs/korea.projection/ap.log; the passphrase
# is never written there.
# Test hooks: HOTSPOT_LIB=1 only defines the functions; BB, SRC, CONF, W, PROP override paths.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
BB=${BB:-/system/bin/busybox}
SRC=${SRC:-/data/misc/wifi/softap.conf}
# 짧게 유지: busybox ps가 명령줄을 약 80칸에서 잘라 "hostapd <경로>"가 약 50자를 넘으면 찾지 못한다
CONF=${CONF:-/data/misc/wifi/hostapd-kp.conf}
W=${W:-/data/local/tmp/korea.projection}
AP_IP=192.168.43.1
# busybox ps cuts command lines near 80 columns: match the start of dnsmasq's (netd starts it the
# same way, but the stock hotspot never runs on this car)
DNSMASQ='dnsmasq --keep-in-foreground --no-resolv --no-poll'
# 확인된 차(<모델>.<지역>:<펌웨어>, 띄어 쓰기로 구분): 니로 하이브리드, 쏘나타 하이브리드(DN8). 그 밖의 차는 기록만 하고 대기
CARS='DEPEHEV.KOR:260902 DN822HEV.KOR:260902'
# ro.build.product가 확인된 차인가 (<모델>.<지역>.<아무거나>.<펌웨어>).
# case 패턴에 변수로 넣은 |는 갈래로 풀리지 않아 하나씩 본다. 목록에 *가 없어 for의 파일 이름 풀이도 일어나지 않는다
is_car() {
  for _car in $CARS; do
    case "$1" in "${_car%%:*}".*."${_car#*:}") return 0 ;; esac
  done
  return 1
}
OLDPKG=${OLDPKG:-/data/nemesis/apps/niro.carplay.hotspot}
APP=${APP:-/data/nemesis/apps/korea.projection}

log() { echo "$(date '+%m-%d %H:%M:%S') $*"; }

# the head unit's busybox (1.8.1) od only knows -b: bytes come as 3-digit octal
# octal bytes -> string
decode() {
  _s=""
  for _b in "$@"; do _s="$_s$($BB printf "\\$_b")"; done
  # mksh의 echo는 \ 이스케이프를 해석하므로 printf %s로 그대로 낸다
  $BB printf '%s\n' "$_s"
}

# one 3-digit octal byte -> decimal (digit by digit: no leading-zero ambiguity)
o2d() {
  _r=${1#?}
  echo $(( ${1%??}*64 + ${_r%?}*8 + ${_r#?} ))
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
  for _t in "$@"; do eval "o$i=$_t; b$i=$(o2d $_t)"; i=$((i+1)); done
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

write_conf() {
  $BB cat > $CONF <<CONFEOF
interface=wlan0
driver=nl80211
ctrl_interface=/data/misc/wifi/hostapd
ssid=$S2
channel=6
hw_mode=g
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

# a live process by name; a zombie ([hostapd], state Z) doesn't count
running() { $BB ps | $BB grep -v grep | $BB grep -v " Z " | $BB grep -q "$1"; }

up() {
  $BB ifconfig wlan0 $AP_IP netmask 255.255.255.0 up 2>/dev/null
  if ! running "hostapd $CONF"; then
    hostapd $CONF >/dev/null 2>&1 &
    sleep 4
    $BB ifconfig wlan0 $AP_IP netmask 255.255.255.0 up 2>/dev/null
    log "hostapd 시작"
  fi
  if ! running "$DNSMASQ"; then
    # same style as netd: bare --pid-file (no /var/run here)
    dnsmasq --keep-in-foreground --no-resolv --no-poll --dhcp-authoritative --pid-file \
      --interface=wlan0 --bind-interfaces \
      --dhcp-range=192.168.43.10,192.168.43.50,255.255.255.0,1h --dhcp-option=3 --dhcp-option=6 >/dev/null 2>&1 &
    log "dnsmasq 시작"
  fi
}

# only our own hostapd and dnsmasq (matched by their command lines)
stop_ap() {
  for p in $($BB ps | $BB grep -v grep | $BB grep -E "hostapd $CONF|$DNSMASQ" | $BB awk '{print $1}'); do
    kill $p 2>/dev/null
  done
  killlog
}

# 서비스가 끝날 때(TERM)와 패키지를 지울 때만: 핫스팟에 더해 뒤에서 도는 권한 파일 확인(fix_perms)도 멈춘다.
# 시작할 때 부르는 stop_ap는 이것을 건드리지 않는다 (방금 띄운 확인 작업을 죽이지 않게)
stop_all() {
  stop_ap
  if fix_running; then set -- $(cat $W/fix.pid); kill $1 2>/dev/null; fi
  rm -f $W/fix.pid
}

# log.pid의 프로세스가 우리 로그 파이프(마지막 단계 uniq)일 때만 죽인다 (/data/local/tmp는 재부팅 뒤에도
# 남아 예전 pid가 다른 프로세스를 가리킬 수 있다). 마지막 단계가 죽으면 앞의 grep과 logcat은 SIGPIPE로 끝난다.
killlog() {
  _p=$(cat $W/log.pid 2>/dev/null)
  [ -n "$_p" ] && $BB grep -q -E 'logcat|grep|uniq' /proc/$_p/cmdline 2>/dev/null && kill $_p 2>/dev/null
  rm -f $W/log.pid
}

# $W/debug가 있을 때만: 카플레이 관련 logcat을 $W/cp.log에 남긴다(폰 이름, 교차로 이름이 들어가므로 기본은 꺼짐).
# 이 헤드유닛의 logcat은 -f와 함께 태그 필터를 무시하므로 grep으로 거른다.
# 길안내 중에는 분당 약 500KB가 쌓여(2026-11-06 run3) 쓸모없는 줄을 버린다:
#  - iAPSendMessage의 "done with"와 "Command Received": 보낸 줄마다 따라붙는 확인 줄
#  - getCANSTatus = true(ClusterService)와 getCANStatus(NavigationCluster): 몇 초마다 같은 줄
# 보낸 줄 "iAPSendMessage() : data(…) size(N)"은 남긴다: 정상 세션에서는 차 위치(크기 57/84/100)가
# 1초마다 나가므로, 위치가 아이폰에 가는지 이것으로 본다(2026-11-06, 1.4.2는 이 줄까지 버렸다).
# iAP2(순정 iAP2 라이브러리)는 아이폰의 위치 요청(LocationInformationStart)을 남긴다. 분당 수십 줄 이하.
# 같은 줄이 연달아 나오면(pcm_write failed가 1초에 수천 줄) uniq -c가 한 줄과 횟수로 줄인다
# (앞의 날짜·시간 두 칸은 비교하지 않는다). 그래서 각 줄 앞에 반복 횟수가 붙는다.
TAGS=' [VDIWEF]/(hostapd|dnsmasq|HMG-API|iAP2|Iap2Service|CarPlay_|TccCarPlay|WifiService|BTCMService|NavigationCluster|ClusterService) *\('
DROP='iAPSendMessage\(\) : done with \(0x00\)|iAPSendMessage Command Received|getCANSTatus = true|\): getCANStatus$'
# 보관: cp.log가 LOGMAX를 넘으면 cp.log.1~3으로 밀어 최대 4개(기본 3MB씩, 12MB)
LOGMAX=${LOGMAX:-3145728}
logstart() {
  [ -f $W/debug ] || return 0
  # busybox에 uniq가 없거나 -f를 모르면 줄이지 않고 그대로 남긴다 (로그가 아예 끊기지 않게)
  if echo x | $BB uniq -c -f 2 >/dev/null 2>&1; then _u="$BB uniq -c -f 2"; else _u="$BB grep ."; fi
  # grep이 DROP 정규식을 못 받으면(종료 코드 2) 파이프가 조용히 끝나 로그가 비므로, 그때는 아무 줄도 버리지 않는다
  _d=$DROP; echo x | $BB grep -E "$_d" >/dev/null 2>&1; [ $? -le 1 ] || _d='^$'
  logcat -v time 2>/dev/null | $BB grep -E "$TAGS" | $BB grep -v -E "$_d" | $_u >> $W/cp.log &
  echo $! > $W/log.pid
}
# 파이프를 다시 시작하지 않고 파일만 밀어낸다: 다시 시작하면 logcat이 버퍼 전체를 다시 써서
# 몇 분 치가 겹쳐 쌓였다(run3). uniq는 >>(O_APPEND)로 열었으므로 cp.log를 비우면 처음부터 다시 쓴다.
# 복사와 비우기 사이에 들어온 몇 줄은 잃을 수 있다(디버그용이라 감수).
logrotate() {
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
# 되돌린 파일은 HMG-API 것이므로 이 패키지를 지워도 남겨 둔다.
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
fix_running() {
  _l=$(cat $W/fix.pid 2>/dev/null) || return 1
  set -- $_l
  [ -n "$1" ] && [ "$1" != $$ ] && [ "$2" = "$(cat $BOOT_ID 2>/dev/null)" ] && [ -d /proc/$1 ] \
    && $BB grep -q hotspot.sh /proc/$1/cmdline 2>/dev/null
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
BK=${BK:-/data/nemesis/backup/korea.projection}
MOD_ID=wireless-carplay-aa
# 패키지에 든 모드 zip의 md5 (busybox 1.8.1에 sha256sum이 없다). zip을 바꾸면 함께 바꾼다.
MOD_MD5=27fa565c5c0f1add08968a7c8aa03766
toast() {
  am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "$1" \
    --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1
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
setup_hmgapi() {
  is_car "$(getprop ro.build.product 2>/dev/null)" || return 0
  [ -d $HMGDATA/maps ] || { log "자동 설정 건너뜀: HMG-API가 없음"; return 0; }
  $BB mkdir -p $BK
  # _fail: 안내 토스트를 이미 띄움 → 마지막 "설정을 마쳤습니다"로 덮지 않는다
  _restart=0; _fail=0
  # 지도: 차마다 임시 폴더에 다 복사한 뒤 한 번에 옮긴다(도중에 전원이 꺼져 반쪽 지도가 남지 않게).
  # 임시 폴더는 maps/.kp-tmp: HMG-API는 maps/<제조사>/<차종>/<지역>/<펌웨어>/만 읽으므로 반쪽 car.json을 보지 않는다.
  # 지도 확인(verify-map)은 이 차의 지도(펌웨어와 모델 코드가 같은 것)를 넣었을 때, 그리고 우리가 넣은 이 차
  # 지도가 아직 확인을 통과하지 못했을 때(지난번 실패, 확인 전에 꺼짐: map.checked에 없음) 한다.
  # 다른 차 지도를 넣지 못한 것은 이 차 설정을 막지 않는다(_mapbad는 이 차 지도만). 안내만 한다(_fail).
  # map.ours는 기록용이다: 지도는 HMG-API의 다른 모드도 쓰므로 패키지를 지워도 남긴다.
  _mapbad=0; _mine=0; _recheck=0; _myrel=
  _prod=$(getprop ro.build.product 2>/dev/null)
  _tmp=$HMGDATA/maps/.kp-tmp
  for _c in $KP_HMG/maps/*/*/*/*/car.json; do
    [ -f "$_c" ] || continue
    _d=${_c%/car.json}; _rel=${_d#$KP_HMG/maps/}
    _own=0
    [ "${_rel##*/}" = "${_prod##*.}" ] && $BB grep -q "\"${_prod%%.*}" $_c && { _own=1; _myrel=$_rel; }
    if [ -f $HMGDATA/maps/$_rel/car.json ]; then
      [ $_own = 1 ] && has_line "$_rel" $BK/map.ours && ! has_line "$_rel" $BK/map.checked && _recheck=1
      continue
    fi
    $BB rm -rf $_tmp
    if $BB mkdir -p $_tmp ${HMGDATA}/maps/${_rel%/*} && $BB cp $_d/*.json $_tmp/ && $BB chmod -R 700 $_tmp \
        && $BB rm -rf $HMGDATA/maps/$_rel && $BB mv $_tmp $HMGDATA/maps/$_rel; then
      echo "$_rel" >> $BK/map.ours
      log "지도 넣음: $_rel"
      [ $_own = 1 ] && _mine=1
    else
      $BB rm -rf $_tmp
      log "지도 넣기 실패: $_rel"; _fail=1
      [ $_own = 1 ] && _mapbad=1
    fi
  done
  if { [ $_mine = 1 ] || [ $_recheck = 1 ]; } && [ $_mapbad = 0 ]; then
    if hmgapid engine verify-map > $W/verify-map.txt 2>&1; then
      echo "$_myrel" >> $BK/map.checked
      # 다시 확인만 한 것(1.5.1에서 올린 차 등)은 이미 켜져 있을 수 있어 재시작 안내를 하지 않는다.
      # 모드를 이번에 적용하면 아래에서 안내한다.
      if [ $_mine = 1 ]; then log "지도 확인 통과 (다음 시작부터 훅 켜짐)"; _restart=1
      else log "지도 다시 확인 통과: $_myrel"; fi
    else
      log "지도 확인 실패 ($W/verify-map.txt)"; _fail=1; _mapbad=1
      toast "Korea Projection: HMG-API 지도 확인에 실패했습니다. Launch에서 상태를 확인해 주세요."
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
    elif ! hmgapid engine install $KP_HMG/$MOD_ID.zip > $W/mod-install.txt 2>&1; then
      log "무선 모드 설치 실패, 다음 부팅에 다시 함 ($W/mod-install.txt)"; _fail=1
      toast "Korea Projection: HMG-API 무선 모드를 설치하지 못했습니다. Launch에서 상태를 확인해 주세요."
    else
      : > $BK/mod.tried; : > $BK/mod.ours
      log "무선 모드 설치함"
      if ! plan_only_mod; then
        log "무선 모드 적용 안 함: 계획에 다른 변경이 있거나 훅이 꺼짐 ($W/plan.txt)"; _fail=1
        toast "Korea Projection: 무선 모드를 설치했습니다. HMG-API 앱에서 변경 사항을 적용한 뒤 차를 껐다 켜 주세요."
      elif hmgapid engine apply > $W/mod-apply.txt 2>&1; then
        log "무선 모드 적용함"; _restart=1
      else
        log "무선 모드 적용 실패 ($W/mod-apply.txt)"; _fail=1
        toast "Korea Projection: 무선 모드 적용에 실패했습니다. HMG-API 앱을 확인해 주세요."
      fi
    fi
  fi
  [ $_restart = 1 ] && [ $_fail = 0 ] && toast "Korea Projection: 무선 카플레이 설정을 마쳤습니다. 차를 껐다 켜 주세요(문 열고 닫기)."
  return 0
}

fix_perms() {
  command -v hmgapid >/dev/null 2>&1 || { rm -f $W/fix.pid; return 0; }
  _fix_perms
  rm -f $W/fix.pid
}
_fix_perms() {
  # 부팅 직후 HMG-API의 부팅 단계(hook-check: remount rw → 쓰기 → ro)와 겹치지 않게 잠시 기다린다
  sleep ${FIX_DELAY:-120}
  # 그사이 패키지가 지워졌으면 그만둔다
  [ -d $W ] || return 0
  # HMG-API 데몬이 뜰 때까지 기다린다 (최대 5분). 이 함수는 뒤에서 돌므로 핫스팟을 늦추지 않는다.
  _i=0
  until hmgapid ping >/dev/null 2>&1; do
    _i=$((_i+1)); [ $_i -ge 30 ] && { log "권한 파일 확인 건너뜀: HMG-API 데몬 응답 없음"; return 0; }
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
    else
      rm -f $PERMS/$_n.xml; log "권한 파일 쓰기 실패: $_n"
    fi
  done < $_todo
  [ $_was_ro = 1 ] && hmgapid remount ro >/dev/null 2>&1
  rm -f $_todo
  if [ ! -s $W/perms.done ]; then set +f; rm -f $W/perms.done; return 0; fi
  if ! plan_only_ours; then
    log "HMG-API apply 안 함: 계획에 다른 변경이 있음 ($W/plan.txt). HMG-API 앱에서 적용해 주세요"
    _m="Korea Projection: 무선 카플레이 기능 파일을 복구했습니다. HMG-API 앱에서 변경 사항을 적용한 뒤 차를 껐다 켜 주세요."
  elif hmgapid engine apply >/dev/null 2>&1; then
    log "HMG-API apply 완료"
    _m="Korea Projection: 무선 카플레이 기능 파일을 복구했습니다. 차를 껐다 켜 주세요(문 열고 닫기)."
  else
    log "HMG-API apply 실패"
    _m="Korea Projection: 무선 카플레이 기능 파일을 복구했지만 HMG-API 적용이 실패했습니다. HMG-API 앱을 확인해 주세요."
  fi
  set +f
  rm -f $W/perms.done
  am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "$_m" \
    --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1
}

# 상태 화면 앱(korea.projection.app). NEMESIS의 kind=apk 설치를 쓰지 않는다: 2026-11-06 니로에서
# /data/nemesis/apps/... 의 apk를 pm이 못 읽어 설치가 실패했고(시스템 사용자가 그 폴더를 못 연다),
# 그 실패가 패키지 설치 전체를 막아 핫스팟까지 없어졌다. 그래서 읽을 수 있는 곳(/data/local/tmp, 644)에
# 복사해 직접 설치하고, 실패해도 패키지는 그대로 둔다 (HMG-API 앱 설치와 같은 방식). APP는 위에서 정한다.
APK_SRC=${APK_SRC:-$APP/app/KoreaProjection.apk}
APK_COPY=${APK_COPY:-/data/local/tmp/korea-projection.apk}
APP_ID=korea.projection.app
# KitKat pm은 실패해도 종료 코드 0일 수 있어 출력으로 본다
app_installed() { pm path $APP_ID 2>/dev/null | $BB grep -q "^package:"; }
# 결과(Success/Failure 전체 출력)를 $W/app-install.log에 남긴다. 성공 0, 실패 1.
install_app() {
  [ -f $APK_SRC ] || { log "상태 화면 앱 파일 없음: $APK_SRC"; return 1; }
  $BB cp -f $APK_SRC $APK_COPY && $BB chmod 644 $APK_COPY || { log "상태 화면 앱 복사 실패"; return 1; }
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
  $BB mkdir -p $W 2>/dev/null
  echo "$(date '+%m-%d %H:%M:%S') pm install: $_r" >> $W/app-install.log
  case "$_r" in
    *Success*) rm -f $APK_COPY; log "상태 화면 앱 설치됨"; return 0 ;;
    *) log "상태 화면 앱 설치 실패 (핫스팟과는 상관없음): $($BB echo $_r)"; return 1 ;;
  esac
}
remove_app() {
  pm uninstall $APP_ID >/dev/null 2>&1
  rm -f $APK_COPY
}

main() {
  umask 077
  $BB mkdir -p $W
  prod=$(getprop ro.build.product)
  # svc, pm, HMG-API는 Android가 다 켜진 뒤에 쓴다
  while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 2; done
  # 확인되지 않은 차에서도 한다: HMG-API가 기록한 그대로만 되돌리므로 (md5 확인)
  # 뒤에서 돌린다: HMG-API가 늦거나 멈춰도 핫스팟은 바로 켠다 (출력은 같은 ap.log로)
  if ! fix_running; then
    fix_perms &
    echo "$! $(cat $BOOT_ID 2>/dev/null)" > $W/fix.pid
  fi
  if ! is_car "$prod"; then
    log "시작 안 함: $prod 는 확인된 차가 아님 ($CARS)"
    # mode=restart: idle instead of exiting, so svcmgr doesn't count deaths
    while true; do sleep 3600; done
  fi
  trap 'stop_all; log "멈춤"; exit 0' TERM INT HUP
  # the package's earlier name runs its own hostapd: wait until it's uninstalled, then start
  if [ -d $OLDPKG ]; then
    log "대기: 예전 패키지 niro.carplay.hotspot이 설치되어 있음 (삭제해 주세요)"
    while [ -d $OLDPKG ]; do sleep 60 & wait $!; done
    log "예전 패키지 삭제됨: 시작"
  fi
  parse_conf $SRC
  if [ "${NS:-0}" -lt 4 ] || [ ${#S2} -lt 1 ] || [ ${#S4} -lt 8 ]; then
    log "시작 안 함: $SRC 에서 문자열 4개를 찾지 못함 (${NS:-0}개)"
    while true; do sleep 3600; done
  fi
  write_conf
  log "시작 ($prod): softap.conf의 카플레이 SSID 길이 ${#S2}, 비밀번호 길이 ${#S4}"
  stop_ap
  # the Wi-Fi driver loads with Wi-Fi on; wpa_supplicant has to let go of wlan0 for hostapd
  svc wifi enable; sleep 9
  $BB killall wpa_supplicant 2>/dev/null; sleep 2
  logstart
  up
  n=0
  while true; do
    sleep 30 &
    wait $!
    logrotate
    if running wpa_supplicant; then
      $BB killall wpa_supplicant 2>/dev/null
      log "wpa_supplicant가 다시 켜져서 멈춤"
    fi
    up
    n=$((n+1))
    # once an hour: one line with the CarPlay connections
    [ $((n % 120)) -eq 0 ] && log "동작 중: $($BB netstat -tn 2>/dev/null | $BB grep -c "$AP_IP:7000") 개 카플레이 연결"
  done
}

[ "$HOTSPOT_LIB" = 1 ] || main
