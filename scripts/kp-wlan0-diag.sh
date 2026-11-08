#!/system/bin/sh
umask 077
# wlan0 진단 USB (NEMESIS.sh, type=execute). 2026-11-08 작성.
# 대상: Wi-Fi 칩은 있는데(HMG-API wifi_chip: true) Wi-Fi 드라이버가 올라오지 않아 wlan0가 없는 차
# (그랜저 IG #52 IGPE21, #53·#54·#55 IGPEHEV). 우리 hostapd가 34초마다 "No such device"로 실패한다.
# 원인 후보 셋을 가르는 자료를 모은다:
#   1) 우리 Wi-Fi 잠금(/data/misc/wifi/wpa_supplicant.conf root 소유)이 드라이버 올리기까지 막는가
#   2) 순정 Wi-Fi 서비스(WifiController·WifiStateMachine)가 드라이버를 올리려 하지 않는 상태인가
#   3) 칩 깨우기 시점 문제로 칩(SDIO)이 응답하지 않는가(insmod가 오래 걸리고 HW 주소를 못 읽음)
#
# USB를 꽂을 때마다 한 단계씩 진행한다. 단계는 내비의 $D/step에 적는다.
#   1단계 관찰(읽기만): 부팅 직후부터 OBS_SEC초 동안 logcat·커널 기록을 받고 상태를 두 번 찍는다.
#                       USB를 꽂은 채 시동을 걸고 NEMESIS가 물으면 "예"를 누르게 안내한다.
#   2단계 다시 올리기(2026-11-08 추가, #55): 부팅 때 칩 펌웨어 올리기가 실패하면 bcmdhd 모듈이 장치 없이 남아
#                       Wi-Fi 서비스가 다시 올리지 않는다. Wi-Fi를 끄고 모듈을 내린(rmmod) 뒤 다시 켜서 순정 HAL이
#                       칩 전원·펌웨어 올리기를 다시 하게 한다. 최대 RELOAD_TRIES번, wlan0가 생기면 멈춘다(잠금은 그대로).
#                       wlan0가 생기면 그대로 둔다(패키지가 핫스팟을 띄운다). 생기지 않으면 Wi-Fi 켜짐 상태만 되돌린다.
#   3단계 Wi-Fi 껐다 켜기(잠금은 그대로): svc wifi disable → enable 뒤 TEST_SEC초 동안 드라이버·wlan0을 본다.
#                       켜기 전에 Wi-Fi가 꺼져 있었으면(wifi_on이 1이 아님) 끝나고 다시 끈다.
#   4단계 잠금 잠시 풀기: 패키지가 남긴 원래 소유자·권한(wpaconf.orig)과 crc32 백업으로 잠금 전 상태를 만들고
#                       Wi-Fi를 껐다 켠 뒤 TEST_SEC초 본다. 끝나면 시험 직전 상태(내용·소유자·권한·crc32 유무)로
#                       정확히 되돌리고 확인한다. 되돌리기 전에 원본을 내비($D/bak)에 백업하고 USB로는 옮기지 않는다.
#   2~4단계는 wlan0가 없을 때만 한다(무선 카플레이가 되는 차를 건드리지 않게). 4단계는 잠금이 걸려 있을 때만 한다.
#   $D/step 값: OBS(1단계 끝) → RELOAD(2단계 끝) → TOGGLE(3단계 끝) → DONE. 예전 판에서 OBS 뒤 바로 TOGGLE로
#   갔던 차도 TOGGLE이면 4단계를 이어서 한다.
#   USB 맨 위에 kp-wlan0-off가 있으면 어느 때든 작업을 멈추고 시험 전 상태로 되돌린 뒤 끝낸다(강제 되돌리기).
# 작업은 setsid로 뒤에서 돈다(USB를 빼거나 Wi-Fi를 껐다 켜며 USB가 다시 붙어도 이어지게). 끝나는 조건:
# 단계별 시간 상한(관찰 OBS_SEC, 시험 TEST_SEC+약 1분), 받기 크기 CAP_BYTES, 멈춤 파일, 시계를 못 읽음.
# Wi-Fi 이름·비밀번호, MAC, IP, 폰 이름, VIN, 전화번호는 쓰지 않거나 가린다(usb-aadiag의 MASK 그대로 +
# FINDINGS의 빈틈 "info name <이름>"·"Init name <이름>" 꼴). 설정 파일 내용은 USB에 옮기지 않는다.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin:/data/nemesis/bin
APP=${APP:-/data/nemesis/apps/korea.projection}
if [ -z "$BB" ] || [ ! -x "$BB" ]; then
  if [ -x /system/bin/busybox ]; then BB=/system/bin/busybox
  elif [ -x "$APP/bin/busybox" ]; then BB="$APP/bin/busybox"
  elif [ -x /data/nemesis/bin/busybox ]; then BB=/data/nemesis/bin/busybox
  elif [ -f "$APP/bin/busybox" ]; then chmod 755 "$APP/bin/busybox" 2>/dev/null; [ -x "$APP/bin/busybox" ] && BB="$APP/bin/busybox"
  fi
fi
if [ -z "$U" ] && [ "$KP_FROM_DATA" != 1 ]; then
  case "$0" in */*) U=$(cd "${0%/*}" 2>/dev/null && pwd) ;; esac
  case "$U" in /data/*) U= ;; esac
fi
U=${U:-/storage/usb0}
export U
SELF=$0
case "$SELF" in /*) ;; *) SELF=$(pwd)/$SELF ;; esac
cd /
D=${D:-/data/local/tmp/kp-wlan0diag}
W=${W:-/data/local/tmp/korea.projection}
APP=${APP:-/data/nemesis/apps/korea.projection}
BK=${BK:-/data/nemesis/backup/korea.projection}
CONF=${CONF:-/data/misc/wifi/hostapd-kp.conf}
APLOG=${APLOG:-/data/nemesis/logs/korea.projection/ap.log}
HMGLOG=${HMGLOG:-/data/hmgapi/logs/hmgapi}
HMGDATA=${HMGDATA:-/data/hmgapi}
WDIR=${WDIR:-/data/misc/wifi}
WCONF=${WCONF:-$WDIR/wpa_supplicant.conf}
WCRC=${WCRC:-$WDIR/wpa_supplicant_crc32.conf}
NET=${NET:-/sys/class/net}
SDIO=${SDIO:-/sys/bus/sdio/devices}
MODS=${MODS:-/proc/modules}
BCMPAR=${BCMPAR:-/sys/module/bcmdhd/parameters}
MOUNTS=${MOUNTS:-/proc/mounts}
UPTIME=${UPTIME:-/proc/uptime}
BOOTID=${BOOTID:-/proc/sys/kernel/random/boot_id}
PROC=${PROC:-/proc}
# 시간(초)·크기 상한. TICK마다 커널 기록과 상태 줄을 본다.
OBS_SEC=${OBS_SEC:-240}
TEST_SEC=${TEST_SEC:-90}
OFF_SEC=${OFF_SEC:-10}
# 4단계: 패키지가 다시 잠그기를 기다리는 최대 시간, 잠금을 다시 푼 뒤 Wi-Fi를 끈 채 두는 시간
SYNC_MAX=${SYNC_MAX:-45}
UNLOCK_OFF=${UNLOCK_OFF:-2}
# 2단계(다시 올리기): 시도 횟수, Wi-Fi를 켠 뒤 지켜보는 시간(부팅 때 실패는 약 13초 만에 포기했다), 끈 채 두는 시간
RELOAD_TRIES=${RELOAD_TRIES:-3}
RELOAD_SEC=${RELOAD_SEC:-45}
RELOAD_OFF=${RELOAD_OFF:-5}
# 지난 부팅의 커널 기록(2단계가 끊겼을 때 커널이 멈췄는지 본다)
LASTK=${LASTK:-/proc/last_kmsg}
# 2~4단계는 부팅 뒤 이만큼 지나야 한다(패키지가 Wi-Fi를 넘겨받기 전에 건드리지 않게. 리뷰 M1)
MIN_UP=${MIN_UP:-240}
SVC_MAX=${SVC_MAX:-20}
CAP_BYTES=${CAP_BYTES:-8388608}
TICK=${TICK:-2}
UO=$U/KP-wlan0-diag
O=$D/out

# 토스트. am은 시스템 서버를 부르므로(binder) 서버가 멈춰 있으면 끝나지 않을 수 있다: 5초만 기다린다(리뷰 M4)
toast() {
  echo "$1"
  am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "$1" \
    --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1 &
  _ap=$!; _ai=0
  while kill -0 $_ap 2>/dev/null && [ $_ai -lt 5 ]; do sleep 1; _ai=$((_ai + 1)); done
  kill $_ap 2>/dev/null
}

if [ ! -x "$BB" ]; then
  mkdir -p /data/local/tmp 2>/dev/null
  if [ -f "$U/busybox" ]; then
    cp "$U/busybox" /data/local/tmp/busybox 2>/dev/null
    chmod 755 /data/local/tmp/busybox 2>/dev/null
    [ -x /data/local/tmp/busybox ] && BB=/data/local/tmp/busybox
  fi
fi
if [ ! -x "$BB" ]; then
  toast "wlan0 진단: 이 내비에서는 진단 USB를 쓸 수 없습니다. 아무것도 바꾸지 않았습니다."
  exit 0
fi

# 내비에 복사해서 거기서 돈다. 새 파일에 쓴 뒤 mv로 바꾼다: 뒤에서 도는 작업자가 읽고 있는 run.sh를
# 제자리에서 덮어쓰지 않게(같은 inode를 자르면 읽던 셸이 깨질 수 있다).
if [ "$KP_FROM_DATA" != 1 ]; then
  export KP_FROM_DATA=1
  if $BB mkdir -p $D && $BB cp "$SELF" $D/run.sh.new && $BB mv -f $D/run.sh.new $D/run.sh; then exec sh $D/run.sh "$@"; fi
  toast "wlan0 진단: 내비에 작업 폴더를 만들지 못해 아무것도 바꾸지 않았습니다."
  exit 0
fi

up_s() { _u=; read _u _r < $UPTIME 2>/dev/null; echo "${_u%%.*}"; }
boot_id() { cat $BOOTID 2>/dev/null; }
now() { date '+%Y-%m-%d %H:%M:%S'; }
usb_in() { $BB grep -q " $U " $MOUNTS 2>/dev/null; }
# pid 파일은 "pid 부팅id". 이번 부팅에 적었고, 살아 있고, 명령줄 첫 인자에 $2가 있을 때만 우리 것(usb-aadiag와 같음)
savepid() { echo "$1 $(boot_id)" > "$2"; }
alive() {
  _p=; _b=; { read _p _b < "$1"; } 2>/dev/null
  [ -n "$_p" ] && [ "$_b" = "$(boot_id)" ] && kill -0 $_p 2>/dev/null && $BB grep -q -E "$2" $PROC/$_p/cmdline 2>/dev/null
}
killpid() { _p=; _b=; { read _p _b < "$1"; } 2>/dev/null; [ -n "$_p" ] && kill $_p 2>/dev/null; }
# 작업자(sh run.sh job …)가 살아 있는가. 같은 부팅에 pid가 다른 sh(패키지 hotspot.sh 등)로 다시 쓰였으면 아니다(리뷰 L1).
# cmdline은 인자를 NUL로 나누므로 busybox tr로 띄어쓰기로 바꿔 읽고 run.sh가 있는지 본다. tr이 안 되면
# 셸 명령 치환으로 읽는다: NUL에서 끊겨 "sh"만 보이면 예전처럼 sh인지만 본다.
job_alive() {
  alive $D/job.pid sh || return 1
  _c=$($BB tr '\000' ' ' < $PROC/$_p/cmdline 2>/dev/null)
  [ -n "$_c" ] || _c=$(cat $PROC/$_p/cmdline 2>/dev/null)
  case "$_c" in *run.sh*|sh|*/sh|"sh "|*"/sh ") return 0 ;; esac
  return 1
}
# 명령에 시간 상한을 둔다: tmo <초> <명령…>. 출력은 그대로 내보낸다. 시스템 서버를 부르는 dumpsys·settings용(리뷰 M4)
tmo() {
  _tn=$1; shift
  "$@" > $D/tmo.$$ 2>&1 &
  _tp=$!; _ti=0
  while kill -0 $_tp 2>/dev/null && [ $_ti -lt $_tn ]; do sleep 1; _ti=$((_ti + 1)); done
  if kill -0 $_tp 2>/dev/null; then kill $_tp 2>/dev/null; echo "(${_tn}초 안에 끝나지 않아 멈춤: $1 $2)" >> $D/tmo.$$; fi
  $BB cat $D/tmo.$$ 2>/dev/null; rm -f $D/tmo.$$
}

# ---- 가리기: usb-aadiag/NEMESIS.sh의 MASK 그대로. 이름 규칙에만 "info name <이름>"·"Init name <이름>" 꼴을 더했다
# (FINDINGS "#53 AA 진단과 진단 USB 이름 가리기 빈틈": Iap2Service 줄, 패키지 1.7.0 KPMASK와 같은 보강) ----
MASK='
function keepip(s) { return s == "192.168.43.1" || s == "0.0.0.0" || s == "127.0.0.1" }
function keepmac(s) { s = tolower(s); return s == "00:00:00:00:00:00" || s == "ff:ff:ff:ff:ff:ff" }
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
# 따옴표 안 문자열은 가린다(NetworkInfo extra: "<SSID>", 저장된 네트워크 목록 등. 리뷰 M5). 앞에서부터 따옴표를 짝지어
# 보고, "/"로 시작하는 경로("/data/misc/wifi/…")와 빈 문자열은 남긴다
function qmask(l,   o, m) {
  o = ""
  while (match(l, /"[^"]*"/)) {
    m = substr(l, RSTART, RLENGTH)
    o = o substr(l, 1, RSTART - 1) (m ~ /^"(\/|")/ ? m : "\"[가림]\"")
    l = substr(l, RSTART + RLENGTH)
  }
  return o l
}
# 커널 명령줄의 기기 고유값(btaddr·wifimac·serialno 등)은 값 전체를 가린다(#55: 구분자 없는 BT MAC이 그대로 나감)
function kvid(l,   o, k) {
  o = ""
  while (match(l, /(btaddr|bt_addr|wifimac|wifi_mac|macaddr|mac_addr|serialno|serial_no)=[^ \t]+/)) {
    k = substr(l, RSTART, RLENGTH); sub(/=.*/, "=", k)
    o = o substr(l, 1, RSTART - 1) k "[가림]"
    l = substr(l, RSTART + RLENGTH)
  }
  return o l
}
# 구분자 없는 12자리 MAC(앞뒤가 16진수가 아닌 것만)
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
  if (match(l, "^[ \t]*" H ":" H ":" H ":" H ":" H ":" H "[ \t]+[0-9]+[ \t]+-?[0-9]+")) l = "[가림: 주변 Wi-Fi 목록 줄]"
  t = tolower(l); gsub(/bssid/, "b_sid", t)
  if (match(t, /ssid|psk *[=:]|passphrase|password|passwd|wpa_key|key *[=:]|secret/))
    l = substr(l, 1, RSTART - 1) "[이하 가림: Wi-Fi 정보]"
  t = tolower(l); gsub(/classname/, "classnXme", t); gsub(/packagename/, "packagenXme", t); gsub(/filename/, "filenXme", t)
  if (match(t, /name *[=:]|alias *[=:]|device *name|friendly *name|phone *name|remote *name|info *name +|init *name +|device *[=:]|direct-/))
    l = substr(l, 1, RSTART + RLENGTH - 1) " [이하 가림: 이름]"
  l = macs(l)
  l = mac12(l)
  l = ips(l)
  gsub(/[Ff][Ee]80:[0-9A-Fa-f:]*/, "fe80:x", l)
  gsub(/[23][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f]*:[0-9A-Fa-f:]*/, "v6:x", l)
  gsub(V, "[VIN 가림]", l)
  gsub(/\+82[- ]?1[016789][- ]?[0-9][0-9][0-9][0-9]?[- ]?[0-9][0-9][0-9][0-9]/, "+82-xx-xxxx-xxxx", l)
  gsub(/01[016789]-?[0-9][0-9][0-9][0-9]?-?[0-9][0-9][0-9][0-9]/, "01x-xxxx-xxxx", l)
  print l
}'
mask() { $BB awk "$MASK"; }
lastn() { $BB awk -v n="$1" 'BEGIN { n = n + 0 } { a[NR % n] = $0 } END { s = NR > n ? NR - n + 1 : 1; for (i = s; i <= NR; i++) print a[i % n] }'; }

# 고르는 logcat 줄: 순정 Wi-Fi(HAL·서비스·컨트롤러), wpa_supplicant·hostapd, 드라이버, 그리고 메시지에 Wi-Fi·드라이버 낱말이 있는 줄.
# 태그 목록은 패키지 1.7.0 WLTAGS에 hostapd·dnsmasq·SoftAp·Tethering·HMG-API를 더한 것이다.
WLTAGS=' [VDIWEF]/(WifiHW|WifiStateMachine|WifiController|WifiService|WifiManager|WifiNative[^ (]*|WifiMonitor|WifiConfigStore|WifiWatchdogStateMachine|WifiP2pService|SoftapController|SoftApController|wpa_supplicant|hostapd|dnsmasq|Tethering|NetworkManagementService|CommandListener|bcmdhd|dhd|BCM[^ (]*|HMG-API) *\('
WLKEYS='wifi_load_driver|wifi_unload_driver|insmod|rmmod|bcmdhd|module_version|wlan0|[Ss]upplicant|setWifiEnabled|setWifiApEnabled|Cannot set RW|CRC Check'
wlfilter() { $BB grep -E "$WLTAGS|$WLKEYS"; }
# 커널 기록에서 고르는 낱말
KRE='dhd|bcm|sdio|mmc[0-9]|wlan|wifi|wl_|firmware|nvram|80211'

yn() { if "$@" >/dev/null 2>&1; then echo 예; else echo 아니요; fi; }
pver() { _v=$($BB grep '^package-version=' "$1" 2>/dev/null); echo "${_v#package-version=}"; }
wlan_here() { [ -d $NET/wlan0 ]; }
sdio_n() { $BB ls $SDIO 2>/dev/null | $BB awk 'END { print NR }'; }
drv_loaded() { $BB grep -q -E '^(bcmdhd|dhd) ' $MODS 2>/dev/null; }
# 장치 없이 남은 Wi-Fi 모듈을 내린다(toolbox rmmod, 안 되면 busybox). 커널에서 멈출 수 있어 시간 상한을 둔다
# 모듈 이름(bcmdhd 또는 dhd)과 상태. /proc/modules 줄: "<이름> <크기> <사용 수> <쓰는 모듈> <상태> <주소>"
drv_name() { $BB awk '$1 == "bcmdhd" || $1 == "dhd" { print $1; exit }' $MODS 2>/dev/null; }
# 사용 수 0이고 Live일 때만 내린다. Loading·Unloading이면(HAL이 올리거나 내리는 중) 최대 10초 기다린다(리뷰 2)
drv_idle() {
  _di=0
  while [ $_di -lt 10 ]; do
    $BB awk '($1 == "bcmdhd" || $1 == "dhd") && $3 == 0 && $5 == "Live" { f = 1 } END { exit !f }' $MODS 2>/dev/null && return 0
    drv_loaded || return 1
    sleep 1; _di=$((_di + 1))
  done
  return 1
}
# 이번 부팅에 칩 펌웨어 올리기가 실패한 흔적(#55 꼴)이 있는가. 없으면 모듈을 내리지 않는다(다른 원인의 차를 건드리지 않게. 리뷰 2)
fw_failed() { $BB grep -q -E 'failed to download firmware|si_attach failed|(TX|RX) FAILED' $D/kern.raw 2>/dev/null; }
# 장치 없이 남은 Wi-Fi 모듈을 내린다(toolbox rmmod). toolbox가 끝났는데 실패했을 때만 busybox로 한 번 더 한다:
# 커널에서 멈춰 시간 상한에 걸린 경우에는 다시 해도 같이 멈춘다(리뷰 6)
drv_unload() {
  _dn=$(drv_name); [ -n "$_dn" ] || return 0
  _uo=$(tmo 15 rmmod $_dn)
  echo "$_uo"
  case "$_uo" in *"안에 끝나지 않아 멈춤"*) return 1 ;; esac
  drv_loaded && tmo 15 $BB rmmod $_dn
  return 0
}
pnames() { $BB ps 2>/dev/null | $BB grep -v grep; }
supp_on() { pnames | $BB grep -q wpa_supplicant; }
our_ap() { pnames | $BB grep -q "hostapd $CONF"; }
other_ap() { pnames | $BB grep hostapd | $BB grep -v -q "hostapd $CONF"; }
# 파일 소유자(uid:gid)와 권한(8진 3자리). 패키지 hotspot.sh의 f_owner·f_perm과 같음
f_owner() { $BB ls -ln "$1" 2>/dev/null | $BB awk '{ print $3 ":" $4 }'; }
f_perm() { $BB ls -ln "$1" 2>/dev/null | $BB awk '{ p = 0; s = substr($1, 2, 9)
  for (i = 0; i < 3; i++) { d = 0; if (substr(s, i*3+1, 1) == "r") d += 4; if (substr(s, i*3+2, 1) == "w") d += 2; if (substr(s, i*3+3, 1) != "-") d += 1; p = p * 10 + d }
  printf "%03d\n", p }'; }
f_desc() { if [ -e "$1" ]; then echo "$(f_owner "$1") $(f_perm "$1") $(fsize "$1")바이트"; else echo 없음; fi; }
# 내용 비교: 같으면 0. cmp를 못 쓰면(2) 크기로만 본다
# busybox 1.8.1에 cmp가 있는지 확인하지 못했다: 없으면(applet not found) awk로 줄마다 비교하고 크기도 본다(리뷰 M3)
CMP_OK=0; $BB cmp /dev/null /dev/null >/dev/null 2>&1 && CMP_OK=1
fsize() { $BB ls -ln "$1" 2>/dev/null | $BB awk '{ print $5 }'; }
same() {
  [ -f "$1" ] && [ -f "$2" ] || return 1
  if [ $CMP_OK = 1 ]; then $BB cmp -s "$1" "$2"; return $?; fi
  [ "$(fsize "$1")" = "$(fsize "$2")" ] || return 1
  $BB awk 'NR == FNR { a[FNR] = $0; n = FNR; next } { if (!(FNR in a) || a[FNR] "" != $0 "") d = 1; m = FNR } END { exit (d || m != n) }' "$1" "$2"
}
locked() { [ "$(f_owner $WCONF)" = 0:0 ] && [ ! -e $WCRC ]; }

# 시험 단계에서 Wi-Fi를 켜고 끈다. svc는 시스템 서버가 멈춰 있으면 끝나지 않을 수 있어 뒤에서 돌리고 SVC_MAX초만 기다린다.
svc_bg() {
  svc wifi $1 >/dev/null 2>&1 &
  _sp=$!; _i=0
  while kill -0 $_sp 2>/dev/null && [ $_i -lt $SVC_MAX ]; do sleep 1; _i=$((_i + 1)); done
  if kill -0 $_sp 2>/dev/null; then kill $_sp 2>/dev/null; tl "svc wifi $1: ${SVC_MAX}초 안에 끝나지 않아 멈춤"
  else wait $_sp; tl "svc wifi $1: 종료 코드 $?"; fi
}

# ---- 시험 직전 상태로 되돌리기(4단계·강제 되돌리기·끊긴 시험 정리가 같이 쓴다) ----
# $D/bak/meta: "<설정 파일 있었음 0|1> <소유자> <권한> <crc 있었음 0|1> <crc 소유자> <crc 권한>"
# 설정 파일 내용이 달라졌거나(HAL이 지우거나 다시 만듦) 없으면 백업 내용을 임시 파일에 쓴 뒤 mv로 바꾼다.
# 확인까지 되면 0, 아니면 1(백업과 표시 파일은 남긴다: 다음에 다시 되돌린다).
restore_lock() {
  [ -f $D/bak/meta ] || return 1
  read _ce _co _cp _re _ro _rp < $D/bak/meta
  if [ "$_ce" = 1 ]; then
    if [ ! -f $WCONF ] || ! same $D/bak/conf $WCONF; then
      $BB cp -f $D/bak/conf $WCONF.kpd && $BB mv -f $WCONF.kpd $WCONF
    fi
    $BB chown $_co $WCONF; $BB chmod $_cp $WCONF
  else
    rm -f $WCONF
  fi
  if [ "$_re" = 1 ]; then
    if [ ! -f $WCRC ] || ! same $D/bak/crc $WCRC; then
      $BB cp -f $D/bak/crc $WCRC.kpd && $BB mv -f $WCRC.kpd $WCRC
    fi
    $BB chown $_ro $WCRC; $BB chmod $_rp $WCRC
  else
    rm -f $WCRC
  fi
  rm -f $WCONF.kpd $WCRC.kpd
  # 확인
  if [ "$_ce" = 1 ]; then
    [ -f $WCONF ] && same $D/bak/conf $WCONF && [ "$(f_owner $WCONF)" = "$_co" ] && [ "$(f_perm $WCONF)" = "$_cp" ] || return 1
  else
    [ ! -e $WCONF ] || return 1
  fi
  if [ "$_re" = 1 ]; then
    [ -f $WCRC ] && same $D/bak/crc $WCRC && [ "$(f_owner $WCRC)" = "$_ro" ] && [ "$(f_perm $WCRC)" = "$_rp" ] || return 1
  else
    [ ! -e $WCRC ] || return 1
  fi
  return 0
}
# 되돌리기를 확인했으면 백업(설정 파일 내용: Wi-Fi 이름이 있을 수 있다)과 표시 파일을 지운다
restore_and_clean() {
  # 백업이 없으면(지우는 도중 끊김 등) 되돌릴 것이 없다: 표시만 지운다. 잠금은 패키지가 부팅 때 다시 건다(리뷰 L2)
  if [ ! -f $D/bak/meta ]; then rm -f $D/test.state; rm -rf $D/bak; return 0; fi
  if restore_lock; then rm -f $D/test.state; rm -rf $D/bak; return 0; fi
  return 1
}
# 2~4단계에서 Wi-Fi가 원래 꺼져 있었으면 다시 끈다($D/wifi_on_before: 단계를 시작할 때의 wifi_on)
# 파일: "<wifi_on 값> <부팅 id>". 같은 부팅일 때만 되돌린다(재부팅 뒤에는 패키지가 Wi-Fi를 다룬다. 리뷰 M2).
#   1이었으면: 지금 1이 아닐 때만 다시 켠다(끄기와 켜기 사이에 멈춘 경우. 2차 리뷰 M-a)
#   0·null이었으면(패키지 wifi_was_off와 같은 기준): 다시 끈다
#   그 밖(읽지 못함, 시간 초과)이면 건드리지 않는다
wifi_save() {
  _wv=$(tmo 5 settings get global wifi_on | $BB awk 'NR == 1 { print $1 }')
  case "$_wv" in 0|1|null) ;; *) _wv="?" ;; esac
  echo "$_wv $(boot_id)" > $D/wifi_on_before
}
wifi_back() {
  [ -f $D/wifi_on_before ] || return 0
  _wo=; _wb=; read _wo _wb < $D/wifi_on_before 2>/dev/null
  if [ "$_wb" = "$(boot_id)" ]; then
    case "$_wo" in
    1) _wn=$(tmo 5 settings get global wifi_on | $BB awk 'NR == 1 { print $1 }')
       [ "$_wn" = 1 ] || { svc_bg enable; tl "Wi-Fi가 원래 켜져 있어 다시 켬"; } ;;
    0|null) svc_bg disable; tl "Wi-Fi가 원래 꺼져 있어(wifi_on=$_wo) 다시 끔" ;;
    esac
  fi
  rm -f $D/wifi_on_before
}

# 시간 줄(시험 시작 뒤 초)
tl() { _t=$(up_s); echo "+$(( ${_t:-0} - ${T0:-0} ))초 $*" >> $D/tl.txt; }
st_line() {
  echo "wlan0=$(yn wlan_here) SDIO장치=$(sdio_n) 드라이버모듈=$(yn drv_loaded) wlan.driver.status=$(getprop wlan.driver.status) wpa_supplicant=$(yn supp_on) 우리hostapd=$(yn our_ap) 설정파일=$(f_desc $WCONF) crc32=$( [ -e $WCRC ] && echo 있음 || echo 없음)"
}
# 커널 기록: 고른 줄 중 아직 안 받은 줄만 더한다(kern.raw는 첫 줄이 머리말이라 비어 있지 않다)
kpoll() {
  dmesg 2>/dev/null | $BB grep -i -E "$KRE" > $D/k.now
  $BB awk 'NR == FNR { s[$0] = 1; next } !s[$0]' $D/kern.raw $D/k.now >> $D/kern.raw 2>/dev/null
}
# $1초 동안(또는 멈춤 파일·크기 상한·시계 못 읽음까지) TICK마다 커널 기록과 상태 줄(바뀔 때만)을 남긴다.
# 멈춰야 하면 1을 돌려준다.
watch() {
  _end=$(( $(up_s) + $1 ))
  while :; do
    [ -f $D/job.stop ] && { tl "멈춤 파일(kp-wlan0-off)"; return 1; }
    _t=$(up_s)
    [ -n "$_t" ] || { tl "시계를 못 읽어 멈춤"; return 1; }
    [ "$_t" -ge $_end ] && return 0
    _sz=$( { $BB wc -c < $D/stream.txt; } 2>/dev/null)
    [ "${_sz:-0}" -ge $CAP_BYTES ] && { tl "받기 크기 상한(${CAP_BYTES}바이트)"; return 1; }
    sleep $TICK
    kpoll
    _s=$(st_line)
    [ "$_s" = "$(cat $D/st.last 2>/dev/null)" ] || { echo "$_s" > $D/st.last; tl "$_s"; }
  done
}

# 지금 상태 전체(시작·끝에 한 번씩)
state_dump() {
  echo "# 상태: $1 ($(now), 부팅 뒤 $(up_s)초)"
  echo "MAC·IP·Wi-Fi 이름·비밀번호·이름은 가렸습니다. 설정 파일 내용은 넣지 않았습니다."
  echo
  echo "## 기본"
  echo "- 펌웨어: $(getprop ro.build.product)"
  echo "- targetdir: $(getprop ro.mobis.targetdir)"
  echo "- Korea Projection: $(pver $APP/NEMESIS.data)"
  echo "- HMG-API:" $($BB grep -E '^(version|build) ' $HMGDATA/installed.txt 2>/dev/null)
  echo "- 요약: $(st_line)"
  echo
  echo "## 네트워크 장치 (/sys/class/net)"
  $BB ls $NET 2>/dev/null
  echo; echo "## ifconfig wlan0"
  $BB ifconfig wlan0 2>&1 | mask
  echo; echo "## 드라이버 모듈 (/proc/modules)"
  $BB cat $MODS 2>/dev/null
  echo; echo "## SDIO 장치 (vendor·device·class)"
  for _s in $SDIO/*; do
    [ -e "$_s" ] || continue
    echo "${_s##*/}: vendor=$(cat $_s/vendor 2>/dev/null) device=$(cat $_s/device 2>/dev/null) class=$(cat $_s/class 2>/dev/null)"
  done
  echo "(SDIO 장치 $(sdio_n)개)"
  echo; echo "## bcmdhd 모듈 인자"
  for _f in $BCMPAR/*; do [ -f "$_f" ] && echo "${_f##*/}=$(cat $_f 2>/dev/null)"; done | mask
  echo; echo "## 속성 (Wi-Fi 관련, 일련번호·전화번호·이름류 제외)"
  getprop 2>/dev/null | $BB grep -i -E 'wifi|wlan|supplicant|hostapd|dhd|bcm|p2p|softap|tether|init\.svc\.(wpa|p2p|hostapd|dhcp|iprenew)' \
    | $BB grep -v -i -E 'serial|imei|imsi|iccid|msisdn|vin|phone|number|ssid|pass|name' | mask
  echo; echo "## 설정 (settings get global)"
  # 강제 되돌리기(멈춤 파일)로 끝낼 때는 시스템 서버를 부르는 settings·dumpsys를 건너뛴다(빨리 끝내게. 2차 리뷰 M-b)
  [ -f $D/job.stop ] && { echo "(강제 되돌리기 중이라 settings·dumpsys는 건너뜀)"; _skip=1; } || _skip=0
  # 반복 변수는 _sk: collect의 _k(단계 이름)를 덮어써 리포트 제목이 비던 문제(#55 "wlan0 진단 리포트:  (2차)")
  [ $_skip = 1 ] || for _sk in wifi_on wifi_saved_state airplane_mode_on wifi_scan_always_enabled wifi_sleep_policy wifi_ap_state; do
    echo "$_sk=$(tmo 5 settings get global $_sk)"
  done
  echo; echo "## $WDIR 파일 (소유자·권한·크기·시각만, 내용 없음)"
  $BB ls -ln $WDIR 2>&1 | mask
  echo; echo "## Wi-Fi 설정 파일: $(f_desc $WCONF), crc32 파일: $(f_desc $WCRC)"
  echo; echo "## 패키지 기록 ($BK, 파일 이름만 + 잠금 원래 상태)"
  $BB ls -ln $BK 2>/dev/null | $BB awk '{ print $6, $7, $8, $NF }'
  echo "wpaconf.orig: $(cat $BK/wpaconf.orig 2>/dev/null || echo 없음)"
  echo "wpacrc.bak(잠글 때 치운 crc32): $($BB ls -ln $BK/wpacrc.bak 2>/dev/null | $BB awk '{ print $5 "바이트", $6, $7, $8 }')"
  echo "wpacrc.orig: $(cat $BK/wpacrc.orig 2>/dev/null || echo 없음)"
  echo "wifi_on(설치 전): $(cat $BK/wifi_on 2>/dev/null || echo 없음)"
  echo; echo "## HMG-API Wi-Fi 칩 기록 ($HMGDATA/public/wifi-chip)"
  $BB ls -ln $HMGDATA/public/wifi-chip 2>&1 | $BB awk '{ print $1, $3 ":" $4, $5, $6, $7, $8 }'
  echo; echo "## 프로세스 (이름만)"
  pnames | $BB grep -i -E 'hostapd|wpa_supp|p2p_supp|dnsmasq|dhcpcd|hotspot|logcat|netd' | $BB awk '{ print $NF }'
  echo; echo "## dumpsys wifi"
  [ $_skip = 1 ] || tmo 20 dumpsys wifi | mask
}

# 헤드유닛에 모은 것($O)을 USB로 옮긴다. 다 옮긴 것을 확인했으면 헤드유닛 쪽은 지운다. 성공하면 0.
copy_out() {
  [ -d $O ] || return 0
  [ -n "$($BB ls $O 2>/dev/null)" ] || return 0
  usb_in || return 1
  $BB mkdir -p $UO 2>/dev/null || return 1
  $BB cp -r $O/* $UO/ 2>/dev/null || return 1
  sync
  for _f in $O/* $O/*/* $O/*/*/*; do
    [ -f "$_f" ] || continue
    _r=${_f#$O/}
    [ "$($BB wc -c < "$_f")" = "$($BB wc -c < "$UO/$_r" 2>/dev/null)" ] || return 1
  done
  rm -rf $O
  return 0
}

# ---- 받기: logcat(뒤에서, 시작할 때 버퍼에 남은 부팅 기록부터 씀) ----
cap_start() {
  ( logcat -v time -b main -b system 2>/dev/null & savepid $! $D/lc.pid; wait ) | wlfilter | mask >> $D/stream.txt &
  _i=0
  while ! alive $D/lc.pid logcat && [ $_i -lt 10 ]; do sleep 1; _i=$((_i + 1)); done
  alive $D/lc.pid logcat
}
cap_stop() { alive $D/lc.pid logcat && killpid $D/lc.pid; sleep 1; rm -f $D/lc.pid; }

STEPNAME_obs="1-관찰"
STEPNAME_reload="2-다시올리기"
STEPNAME_toggle="3-Wi-Fi-껐다켜기"
STEPNAME_unlock="4-잠금풀기"
# 폴더 앞 번호는 새 단계 번호를 따른다(예전 판의 2-wifi-toggle·3-unlock과 이름이 겹치지 않는다)
stepdir() { case "$1" in obs) echo 1-observe ;; reload) echo 2-reload ;; toggle) echo 3-wifi-toggle ;; unlock) echo 4-unlock ;; esac; }

# 모은 줄로 요약 리포트를 쓴다($1 단계 이름, $2 받은 줄 파일, $3 결과 한 줄)
report() {
  L=$2
  cnt() { _c=$($BB grep -c -E "$1" $L 2>/dev/null); echo ${_c:-0}; }
  echo "# wlan0 진단 리포트: $1 (${N}차)"
  echo
  echo "첨부하기 전에 열어 보세요. Wi-Fi 이름·비밀번호, MAC, IP, 이름은 가리려고 했지만 모든 형태를 가렸다고"
  echo "장담할 수 없습니다. 폰 이름이 보이면 그 줄을 지워 주세요."
  echo
  echo "## 결과"
  echo "- $3"
  echo "- 시작: $(cat $D/t_start 2>/dev/null), 끝: $(now)"
  echo "- 시작 때 부팅 뒤 초: $(cat $D/up_start 2>/dev/null) (300초보다 작으면 부팅 때 기록까지 들어 있습니다)"
  echo "- 지금: $(st_line)"
  echo
  echo "## 핵심 줄 개수 (이번에 받은 logcat)"
  echo "| 무엇 | 줄 수 |"
  echo "|---|---|"
  echo "| Wi-Fi 켜기 요청(setWifiEnabled) | $(cnt 'setWifiEnabled') |"
  echo "| 드라이버 올리기(wifi_load_driver) | $(cnt 'wifi_load_driver') |"
  echo "| insmod | $(cnt 'insmod') |"
  echo "| 드라이버 내리기(wifi_unload_driver) | $(cnt 'wifi_unload_driver') |"
  echo "| 드라이버 올리기 실패(Failed to load driver) | $(cnt 'Failed to load driver') |"
  echo "| 설정 파일 권한 실패(Cannot set RW) | $(cnt 'Cannot set RW') |"
  echo "| wpa_supplicant 시작 실패(Failed to start supplicant) | $(cnt 'Failed to start supplicant') |"
  echo "| supplicant 다시 시작(restart supplicant) | $(cnt 'restart supplicant') |"
  echo "| CRC 확인(CRC Check) | $(cnt 'CRC Check') |"
  echo "| CRC 오류(CRC Check error, HAL이 설정 파일을 지움) | $(cnt 'CRC Check error') |"
  echo "| HW 주소 못 읽음(Failed to retrieve HW addr) | $(cnt 'Failed to retrieve HW addr') |"
  echo "| 장치 없음(No such device) | $(cnt 'No such device') |"
  echo "| hostapd nl80211 실패 | $(cnt 'nl80211 driver initialization failed') |"
  echo "| 커널: SDIO 카드 발견(new .*SDIO card) | $($BB grep -c -i -E 'new .*sdio card' $D/kern.raw 2>/dev/null) |"
  echo "| 커널: dhd·bcm 줄 | $($BB grep -c -i -E 'dhd|bcm' $D/kern.raw 2>/dev/null) |"
  echo "| 커널: 펌웨어 올리기 실패(failed to download firmware) | $($BB grep -c 'failed to download firmware' $D/kern.raw 2>/dev/null) |"
  echo "| 커널: 칩 연결 실패(si_attach failed) | $($BB grep -c 'si_attach failed' $D/kern.raw 2>/dev/null) |"
  echo "| 커널: SDIO 전송 오류(TX/RX FAILED) | $($BB grep -c -E '(TX|RX) FAILED' $D/kern.raw 2>/dev/null) |"
  echo "| 커널: 드라이버 probe 실패(probe of … failed) | $($BB grep -c -E 'probe of .* failed' $D/kern.raw 2>/dev/null) |"
  echo "| 커널: 드라이버 시작 성공(Firmware up·Dongle Host Driver) | $($BB grep -c -E 'Firmware up|Dongle Host Driver' $D/kern.raw 2>/dev/null) |"
  echo
  echo "## 읽는 법 (추정, 판단은 자료 전체로)"
  echo "- 펌웨어 올리기 실패·칩 연결 실패·SDIO 전송 오류가 있으면: 칩 전원은 켜졌지만 펌웨어를 받지 못함(#55 꼴). 2단계(다시 올리기)에서 '드라이버 시작 성공'이 나오면 다시 시도로 고칠 수 있다."
  echo "- 켜기 요청은 있는데 드라이버 올리기·insmod 줄이 0: 순정 Wi-Fi 서비스가 드라이버를 올리려 하지 않음(후보 2). 아래 상태 기계 줄을 볼 것."
  echo "- insmod가 있고 HW 주소 못 읽음·SDIO 장치 0: 칩이 응답하지 않음(후보 3, 칩 깨우기·전원)."
  echo "- 드라이버가 올라온 뒤 Cannot set RW → 내리기: 잠금이 드라이버까지 내리게 만듦(후보 1). 4단계에서 잠금을 풀었을 때와 비교."
  echo "- 4단계 동안에도 패키지 서비스는 30초마다 잠금을 다시 걸고 wpa_supplicant를 멈춘다. 시간 줄의 설정파일 소유자 변화와 wpa_supplicant 줄을 함께 볼 것."
  echo
  echo "## 드라이버·HAL 핵심 줄 (마지막 60줄)"
  echo '```'
  $BB grep -E 'wifi_load_driver|wifi_unload_driver|insmod|rmmod|module_version|Failed to|Cannot set RW|CRC Check|HW addr|No such device|setWifiEnabled|restart supplicant|nl80211|Wi-Fi will not' $L 2>/dev/null | lastn 60
  echo '```'
  echo
  echo "## Wi-Fi 상태 기계 줄 (WifiController·WifiStateMachine, 마지막 40줄)"
  echo '```'
  $BB grep -E '/(WifiController|WifiStateMachine) *\(' $L 2>/dev/null | lastn 40
  echo '```'
  echo
  echo "## dumpsys wifi에서 상태 줄 (끝)"
  echo '```'
  $BB grep -i -E 'Wi-Fi is|curState|mWifiState|current state|DeviceActive|ApStaDisabled|StaEnabled|DriverLoad|SoftAp|Supplicant(Start|Stop)' $D/state-end.txt 2>/dev/null | lastn 30
  echo '```'
  echo
  echo "## ap.log의 Wi-Fi 칩·잠금·wlan0 줄 (마지막 30줄)"
  echo '```'
  $BB grep -E 'Wi-Fi 칩|Wi-Fi 잠금|wlan0|Wi-Fi 장치|svc wifi|시작 \(|wpa_supplicant' $APLOG 2>/dev/null | mask | lastn 30
  echo '```'
  if [ -s $D/tl.txt ]; then
    echo
    echo "## 시간 줄 (단계 시작 뒤 초, 상태가 바뀔 때만)"
    echo '```'
    $BB cat $D/tl.txt | mask
    echo '```'
  fi
}

# 모은 것을 단계 폴더에 쓴다
collect() {
  _k=$1; _res=$2
  R=$O/round$N/$(stepdir $_k)
  $BB mkdir -p $R
  # logcat: 받은 줄 + 지금 버퍼(겹친 줄은 뺌) + events 버퍼의 Wi-Fi 줄
  { $BB cat $D/stream.txt 2>/dev/null; logcat -d -v time -b main -b system 2>/dev/null | wlfilter | mask; } \
    | $BB awk '!s[$0]++' > $D/all.txt
  state_dump "끝" > $D/state-end.txt 2>&1
  {
    echo "# logcat: 순정 Wi-Fi·드라이버·hostapd 줄 (${N}차 $_k)"
    echo "Wi-Fi 이름·비밀번호, MAC, IP, 이름은 가렸습니다. 폰 이름이 보이면 그 줄을 지워 주세요."
    echo
    $BB cat $D/all.txt
    echo
    echo "## events 버퍼 (Wi-Fi 줄)"
    logcat -d -v time -b events 2>/dev/null | $BB grep -i -E 'wifi|wlan|supplicant|hostapd' | mask
  } > $R/2-logcat.txt 2>&1
  {
    echo "# 서비스·커널 로그 (${N}차 $_k)"
    echo "MAC, IP, 이름은 가렸습니다."
    echo
    echo "## ap.log (마지막 400줄)"
    mask < $APLOG 2>/dev/null | lastn 400
    if [ -f $W/nowlan-wifi.txt ]; then
      echo; echo "## 패키지가 남긴 wlan0 없음 기록 (nowlan-wifi.txt, 1.7.0)"
      mask < $W/nowlan-wifi.txt
    fi
    echo; echo "## HMG-API 로그 (Wi-Fi·칩·모드 줄, 마지막 200줄)"
    $BB cat $HMGLOG/log.log.1 $HMGLOG/log.log 2>/dev/null | $BB grep -i -E 'wifi|wlan|chip|sdio|mod' | mask | lastn 200
    echo; echo "## 커널 기록 (이번에 받은 Wi-Fi·SDIO·드라이버 줄)"
    mask < $D/kern.raw
  } > $R/3-logs.txt 2>&1
  $BB mv -f $D/state-start.txt $R/4-state-start.txt 2>/dev/null
  $BB cp -f $D/state-end.txt $R/5-state-end.txt
  report "$(eval echo \$STEPNAME_$_k)" $D/all.txt "$_res" > $R/1-report.md 2>&1
  rm -f $D/all.txt $D/state-end.txt $D/k.now $D/st.last
}

# ======== 뒤에서 도는 작업자: sh run.sh job <obs|toggle|unlock> ========
job() {
  K=$1
  savepid $$ $D/job.pid
  N=$(cat $D/round 2>/dev/null); N=${N:-1}
  rm -f $D/stream.txt $D/tl.txt $D/st.last
  echo "# kernel" > $D/kern.raw
  : > $D/stream.txt
  T0=$(up_s); echo "$T0" > $D/up_start; now > $D/t_start
  cap_start || tl "logcat 받기를 시작하지 못함(버퍼만 모음)"
  kpoll
  state_dump "시작" > $D/state-start.txt 2>&1
  tl "시작: $(st_line)"
  res=
  case "$K" in
  obs)
    watch $OBS_SEC
    res="관찰만 했습니다(바꾼 것 없음). 끝 상태: wlan0 $(yn wlan_here), SDIO 장치 $(sdio_n)개"
    next=OBS
    ;;
  reload)
    # 잠금은 건드리지 않는다: 순정 HAL은 설정 파일을 보기 전에 드라이버를 올린다(#55 2단계 로그: wifi_load_driver
    # 다음에 Cannot set RW). 니로에서는 잠긴 채 Wi-Fi를 켜도 드라이버와 wlan0가 남았다(take_wlan0).
    wifi_save
    _wo0=; read _wo0 _x < $D/wifi_on_before 2>/dev/null
    got=0; i=0; stop_why=; norm=
    if drv_loaded && ! fw_failed; then
      # 모듈은 있는데 펌웨어 실패 흔적이 없다: 다른 원인이다. 모듈을 내리지 않고 Wi-Fi만 한 번 껐다 켜 본다
      tl "이번 부팅의 커널 기록에 펌웨어 올리기 실패 흔적이 없어 드라이버 모듈은 내리지 않음"
      RELOAD_TRIES=1; norm=1
    fi
    while [ $i -lt $RELOAD_TRIES ]; do
      i=$((i + 1))
      [ -f $D/job.stop ] && { stop_why="멈춤 파일"; break; }
      tl "시도 $i/$RELOAD_TRIES: Wi-Fi 끄기 (svc wifi disable)"
      svc_bg disable
      watch $RELOAD_OFF || { stop_why="멈춤"; break; }
      if [ "$norm" = 1 ]; then
        :
      elif wlan_here; then
        # 지난 시도의 늦은 올리기로 생겼을 수 있다: 내리지 않고 켜기만 해서 다시 본다(리뷰 1)
        tl "시도 $i: Wi-Fi를 끈 뒤에도 wlan0가 있어 모듈을 내리지 않음"
      elif drv_loaded; then
        if ! drv_idle; then
          tl "드라이버 모듈이 사용 중이거나 바뀌는 중이라 내리지 않음: $($BB grep -E '^(bcmdhd|dhd) ' $MODS 2>/dev/null)"
          stop_why="모듈이 사용 중"
          break
        fi
        if wlan_here; then
          tl "시도 $i: 내리기 직전에 wlan0가 생겨 내리지 않음"
        else
          tl "시도 $i: 장치 없이 남은 드라이버 모듈 내리기 (rmmod $(drv_name))"
          _ro=$(drv_unload 2>&1 | $BB awk 'NR <= 3' | mask)
          if drv_loaded; then
            tl "드라이버 모듈을 내리지 못함: ${_ro:-(출력 없음)}"
            stop_why="모듈을 내리지 못함"
            break
          fi
          tl "드라이버 모듈 내림"
        fi
      else
        tl "시도 $i: 드라이버 모듈이 올라와 있지 않음(내릴 것 없음)"
      fi
      _b=$($BB grep -c 'wlan0=예' $D/tl.txt 2>/dev/null)
      tl "시도 $i: Wi-Fi 켜기 (svc wifi enable: 순정이 칩 전원을 켜고 펌웨어를 다시 올림)"
      svc_bg enable
      watch $RELOAD_SEC; _wr=$?
      _a=$($BB grep -c 'wlan0=예' $D/tl.txt 2>/dev/null)
      # 성공: Wi-Fi를 켠 뒤 지켜보는 시간이 끝났을 때도 wlan0가 있다
      if [ $_wr = 0 ] && wlan_here; then tl "시도 $i: wlan0가 생김"; got=$i; break; fi
      [ "${_a:-0}" -gt "${_b:-0}" ] && tl "시도 $i: wlan0가 잠깐 보였다가 사라짐"
      [ $_wr = 0 ] || { stop_why="멈춤"; break; }
    done
    if [ $got -gt 0 ]; then
      # wlan0를 그대로 둔다(패키지가 핫스팟을 띄우게). Wi-Fi가 원래 꺼져 있었어도 끄지 않는다: 끄면 드라이버가 내려간다
      rm -f $D/wifi_on_before
      _wnote=; case "$_wo0" in 0|null) _wnote=" 원래 꺼져 있던 Wi-Fi를 켜 두었습니다." ;; esac
      res="다시 올리기 ${got}번째 시도에서 wlan0가 생겼습니다(그대로 둠).${_wnote} 끝 상태: wlan0 $(yn wlan_here), 우리 hostapd $(yn our_ap)"
    else
      wifi_back
      [ "$norm" = 1 ] && stop_why="${stop_why:+$stop_why, }펌웨어 실패 흔적이 없어 모듈은 내리지 않음"
      res="다시 올리기를 ${i}번 했지만 wlan0가 생기지 않았습니다${stop_why:+(${stop_why})}. 끝 상태: 드라이버 모듈 $(yn drv_loaded), wlan0 $(yn wlan_here)"
    fi
    next=RELOAD
    ;;
  toggle)
    wifi_save
    tl "Wi-Fi 끄기 (svc wifi disable)"
    svc_bg disable
    watch $OFF_SEC && { tl "Wi-Fi 켜기 (svc wifi enable)"; svc_bg enable; watch $TEST_SEC; }
    seen=$($BB grep -c 'wlan0=예' $D/tl.txt 2>/dev/null)
    wifi_back
    res="Wi-Fi를 껐다 켰습니다(잠금은 그대로). 그동안 wlan0가 보인 상태 줄: ${seen:-0}개. 끝 상태: wlan0 $(yn wlan_here)"
    next=TOGGLE
    ;;
  unlock)
    # 원래(잠금 전) 소유자·권한: 패키지 기록. 앞(foreground)에서 형식을 확인했다
    read uo up < $BK/wpaconf.orig
    # 잠금 전 상태 만들기: 원래 소유자·권한, 패키지가 치워 둔 crc32 파일(있으면)
    # 돌려주는 값은 설정 파일 chown·chmod의 결과다(바로 뒤에 패키지가 다시 잠가도 "풀지 못함"으로 보지 않게)
    unlock_now() {
      $BB chown $uo $WCONF && $BB chmod $up $WCONF; _ur=$?
      if [ -f $BK/wpacrc.bak ] && [ -f $BK/wpacrc.orig ]; then
        read ro rp < $BK/wpacrc.orig
        $BB cp -f $BK/wpacrc.bak $WCRC && $BB chown $ro $WCRC && $BB chmod $rp $WCRC
      fi
      return $_ur
    }
    # 1) 시험 직전 상태를 백업하고 확인한다(내비에만, USB로 옮기지 않음)
    rm -rf $D/bak; $BB mkdir -p $D/bak
    _re=0; [ -e $WCRC ] && _re=1
    ok=1
    $BB cp -f $WCONF $D/bak/conf && same $WCONF $D/bak/conf || ok=0
    if [ $_re = 1 ]; then $BB cp -f $WCRC $D/bak/crc && same $WCRC $D/bak/crc || ok=0; fi
    echo "1 $(f_owner $WCONF) $(f_perm $WCONF) $_re $(f_owner $WCRC) $(f_perm $WCRC)" > $D/bak/meta
    if [ $ok = 0 ]; then
      rm -rf $D/bak
      res="시험 직전 상태를 백업하지 못해 잠금을 풀지 않았습니다(바꾼 것 없음)."
      next=TOGGLE
    else
      # 2) 바꾸기 전에 표시 파일을 남긴다(도중에 끊기면 다음에 꽂을 때 되돌린다)
      echo "UNLOCK $(boot_id)" > $D/test.state
      wifi_save
      if ! unlock_now; then
        tl "잠금을 풀지 못함(소유자 $(f_owner $WCONF))"
        res="잠금을 풀지 못했습니다."
      else
        tl "잠금 풂: 설정 파일 $(f_desc $WCONF), crc32 $( [ -e $WCRC ] && echo 있음 || echo 없음)"
        # 패키지 서비스는 30초마다(ap_tick) 다시 잠근다. 그 때를 기다렸다가 바로 다시 풀고 Wi-Fi를 껐다 켠다:
        # 그러면 다음 재잠금까지 약 30초 동안 풀린 상태로 켜기를 시험한다(리뷰 H1). 켠 직후에도 잠겨 있으면 무효로 적는다.
        _w=0
        while [ "$(f_owner $WCONF)" != 0:0 ] && [ $_w -lt $SYNC_MAX ] && [ ! -f $D/job.stop ]; do sleep 1; _w=$((_w + 1)); done
        if [ "$(f_owner $WCONF)" = 0:0 ]; then
          tl "패키지가 다시 잠금(${_w}초 뒤): 바로 다시 풀고 Wi-Fi를 껐다 켬"
          unlock_now
        else
          tl "${_w}초 동안 다시 잠기지 않음: 그대로 Wi-Fi를 껐다 켬"
        fi
        valid="판단 못 함(중간에 멈춤)"
        if [ ! -f $D/job.stop ]; then
          tl "Wi-Fi 끄기 (svc wifi disable)"
          svc_bg disable
          if watch $UNLOCK_OFF; then
            tl "Wi-Fi 켜기 (svc wifi enable)"
            svc_bg enable
            _eo=$(f_owner $WCONF)
            # svc는 요청만 하고 돌아온다: 드라이버 올리기는 그 뒤라 "유효"도 참고값이다. 시간 줄의 소유자 변화와 함께 본다
            if [ "$_eo" = 0:0 ]; then valid="무효(Wi-Fi를 켠 직후 이미 다시 잠겨 있었음)"
            else valid="유효·참고(Wi-Fi를 켠 직후 설정 파일 ${_eo:-없음(HAL이 지움)}, 시간 줄의 소유자 변화도 볼 것)"; fi
            tl "판정: $valid"
            watch $TEST_SEC
          fi
        fi
        seen=$($BB grep -c 'wlan0=예' $D/tl.txt 2>/dev/null)
        res="잠금을 잠시 풀고 Wi-Fi를 껐다 켰습니다. 판정 $valid. 그동안 wlan0가 보인 상태 줄: ${seen:-0}개."
      fi
      # 3) 시험 직전 상태로 되돌리고 확인. Wi-Fi가 원래 꺼져 있었으면 다시 끈다(리뷰 M6)
      wifi_back
      if restore_and_clean; then
        tl "되돌림 확인: 설정 파일 $(f_desc $WCONF), crc32 $( [ -e $WCRC ] && echo 있음 || echo 없음)"
        res="$res 잠금을 시험 전 상태로 되돌리고 확인했습니다."
      else
        tl "되돌리기를 확인하지 못함"
        res="$res 되돌리기를 확인하지 못했습니다(백업은 내비에 남김)."
        cap_stop
        collect $K "$res"
        rm -f $D/stream.txt $D/kern.raw $D/tl.txt $D/up_start $D/t_start $D/job.stop
        copy_out
        toast "wlan0 진단: 잠금을 되돌리지 못했습니다. USB 맨 위에 kp-wlan0-off 파일을 넣고 다시 꽂아 주세요."
        rm -f $D/job.kind $D/job.pid
        return 0
      fi
    fi
    next=${next:-DONE}
    ;;
  esac
  cap_stop
  collect $K "$res"
  echo $next > $D/step
  rm -f $D/stream.txt $D/kern.raw $D/tl.txt $D/up_start $D/t_start $D/job.stop
  if copy_out; then
    case "$K" in
    obs) toast "wlan0 진단 1단계 끝: USB의 KP-wlan0-diag 폴더에 저장했습니다. USB를 빼셔도 됩니다." ;;
    reload)
      if [ "${got:-0}" -gt 0 ]; then
        toast "wlan0 진단 2단계 끝: Wi-Fi 장치가 올라왔습니다. USB를 빼고 아이폰으로 무선 카플레이를 시험해 보세요."
      else
        toast "wlan0 진단 2단계 끝: Wi-Fi 장치가 올라오지 않았습니다. USB를 빼고 내비를 재부팅해 주세요."
      fi ;;
    *) toast "wlan0 진단: 시험을 끝내고 원래대로 두었습니다. USB를 빼고 내비를 재부팅해 주세요." ;;
    esac
  else
    toast "wlan0 진단: 자료는 모았지만 USB에 저장하지 못했습니다. USB를 한 번 더 꽂아 주세요."
  fi
  sync
  # 진행 표시는 USB로 옮기기까지 끝낸 뒤에 지운다(그 사이에 다시 꽂아도 "진행 중"으로 보이게)
  rm -f $D/job.kind $D/job.pid
}
if [ "$1" = job ]; then job "$2"; exit 0; fi

# ======== USB를 꽂았을 때(앞에서) ========
$BB mkdir -p $O
had_out=0; [ -n "$($BB ls $O 2>/dev/null)" ] && had_out=1
running_job=0; job_alive && running_job=1

# ---- 강제 되돌리기 ----
if [ -f $U/kp-wlan0-off ]; then
  if [ $running_job = 1 ]; then
    : > $D/job.stop
    _i=0
    while job_alive && [ $_i -lt 120 ]; do sleep 1; _i=$((_i + 1)); done
    job_alive && killpid $D/job.pid
    # 작업자가 tmo로 받던 원문(가리기 전 dumpsys 등)이 남았으면 지운다
    rm -f $D/tmo.*
  fi
  cap_stop
  T0=$(up_s)
  msg="작업을 멈췄습니다."
  if [ -f $D/test.state ]; then
    if restore_and_clean; then msg="잠금을 시험 전 상태로 되돌렸습니다."; else msg="잠금을 되돌리지 못했습니다(백업은 내비에 남김). 재부팅하면 패키지가 다시 잠급니다."; fi
  fi
  wifi_back
  rm -f $D/stream.txt $D/kern.raw $D/tl.txt $D/job.kind $D/job.stop $D/job.pid $D/up_start $D/t_start
  echo DONE > $D/step
  copy_out
  toast "wlan0 진단: $msg 내비를 재부팅해 주세요."
  sync
  exit 0
fi

# ---- 진행 중인 작업이 있음(Wi-Fi를 껐다 켜며 USB가 다시 붙어 NEMESIS가 다시 물은 경우 등): 손대지 않는다 ----
if [ $running_job = 1 ]; then
  toast "wlan0 진단: $(cat $D/job.kind 2>/dev/null) 단계가 진행 중입니다. 끝 안내가 나올 때까지 기다려 주세요."
  exit 0
fi

copy_out
pending=$?

# ---- 지난 작업이 끝나지 않고 사라짐(재부팅·전원 끊김): 시험 중이었으면 되돌리고, 그 단계는 다음에 다시 한다 ----
if [ -f $D/job.kind ] || [ -f $D/test.state ]; then
  _k=$(cat $D/job.kind 2>/dev/null); _k=${_k:-unlock}
  N=$(cat $D/round 2>/dev/null); N=${N:-1}
  T0=$(up_s)
  msg="지난 단계($_k)가 중간에 끊겼습니다."
  if [ -f $D/test.state ]; then
    if restore_and_clean; then msg="$msg 잠금을 시험 전 상태로 되돌렸습니다."; else msg="$msg 잠금을 되돌리지 못했습니다."; fi
  fi
  $BB mkdir -p $O/round$N
  {
    echo "# 끊긴 단계 기록 ($(now))"
    echo "- $msg"
    echo "- 받던 줄(가림)의 마지막 200줄:"
    lastn 200 < $D/stream.txt 2>/dev/null
    # 다시 올리기(rmmod·insmod) 중에 끊겼으면 커널이 멈췄을 수 있다. 작업자가 다른 부팅에 있었으면 지난 부팅의
    # 커널 기록(last_kmsg), 같은 부팅이면(작업자만 죽음) 지금 커널 기록의 끝부분을 남긴다(리뷰 5)
    if [ "$_k" = reload ]; then
      _jb=; { read _jp _jb < $D/job.pid; } 2>/dev/null
      echo
      if [ -n "$_jb" ] && [ "$_jb" != "$(boot_id)" ] && [ -r $LASTK ]; then
        echo "## 지난 부팅의 커널 기록 (Wi-Fi·SDIO·오류 줄, 마지막 120줄)"
        $BB grep -i -E "$KRE|oops|panic|unable to handle|bug:|watchdog" $LASTK 2>/dev/null | lastn 120 | mask
      else
        echo "## 지금 커널 기록 (같은 부팅에서 끊김. Wi-Fi·SDIO·오류 줄, 마지막 120줄)"
        dmesg 2>/dev/null | $BB grep -i -E "$KRE|oops|panic|unable to handle|bug:|watchdog" | lastn 120 | mask
      fi
    fi
  } > $O/round$N/interrupted-$_k.txt 2>&1
  # 다시 올리기가 끊기면 같은 시험을 되풀이하지 않는다(커널이 멈춰 재부팅됐다면 또 멈출 수 있다): 2단계를 끝난 것으로 둔다
  [ "$_k" = reload ] && echo RELOAD > $D/step
  wifi_back
  rm -f $D/stream.txt $D/kern.raw $D/tl.txt $D/job.kind $D/job.stop $D/job.pid $D/up_start $D/t_start
  copy_out
  if [ -f $D/test.state ]; then
    toast "wlan0 진단: $msg USB 맨 위에 kp-wlan0-off 파일을 넣고 다시 꽂아 주세요."
  elif [ "$_k" = reload ]; then
    toast "wlan0 진단: $msg 이 기록이 중요합니다. USB의 KP-wlan0-diag 폴더를 보내 주세요."
  else
    toast "wlan0 진단: $msg USB를 다시 꽂으면 그 단계를 다시 합니다."
  fi
  sync
  exit 0
fi

if [ $pending != 0 ]; then
  toast "wlan0 진단: 지난 자료를 USB에 아직 옮기지 못했습니다. USB를 다시 꽂아 주세요."
  exit 0
fi
STEP=$(cat $D/step 2>/dev/null)
# 못 옮긴 자료를 옮기러 다시 꽂은 경우: 새 단계를 시작하지 않는다
if [ $had_out = 1 ]; then
  toast "wlan0 진단: 지난 자료를 USB의 KP-wlan0-diag 폴더에 옮겼습니다. 다음 단계는 USB를 다시 꽂으면 시작합니다."
  exit 0
fi

# 다음 단계 고르기
kind=obs
case "$STEP" in
OBS) kind=reload ;;
RELOAD) kind=toggle ;;
TOGGLE) kind=unlock ;;
esac
why=
if [ $kind != obs ]; then
  # 부팅 직후이거나 우리 핫스팟이 떠 있으면 단계를 바꾸지 않고 나중에 다시 꽂게 한다(정상 차도 부팅 직후에는 wlan0가 잠깐 없다. 리뷰 M1)
  _u=$(up_s)
  if [ -z "$_u" ] || [ "$_u" -lt $MIN_UP ]; then
    toast "wlan0 진단: 내비가 켜진 지 $(( MIN_UP / 60 ))분이 지나지 않았습니다. 잠시 뒤 USB를 다시 꽂아 주세요."
    exit 0
  fi
  if our_ap; then
    toast "wlan0 진단: 지금 무선 카플레이 핫스팟이 켜져 있습니다. 1분 뒤 USB를 다시 꽂아 주세요."
    exit 0
  fi
  if [ ! -d $APP ]; then why="Korea Projection이 설치되어 있지 않아"
  elif wlan_here; then why="지금 wlan0가 있어(무선이 될 수 있는 상태)"
  elif [ $kind = unlock ] && ! locked; then why="Wi-Fi 잠금이 걸려 있지 않아"
  elif [ $kind = unlock ] && ! $BB grep -q -E '^[0-9]+:[0-9]+ [0-7][0-7][0-7]$' $BK/wpaconf.orig 2>/dev/null; then why="잠금 전 원래 상태 기록(wpaconf.orig)이 없어"
  elif [ $kind = unlock ] && $BB grep -q '^0:0 ' $BK/wpaconf.orig 2>/dev/null; then why="잠금 전에도 설정 파일이 root 소유라(풀 것이 없어)"
  fi
fi
if [ -n "$why" ]; then
  echo DONE > $D/step
  toast "wlan0 진단: ${why} 시험 단계는 하지 않았습니다. 진단을 마칩니다. USB를 빼셔도 됩니다."
  exit 0
fi
if [ $kind = obs ]; then
  N=$(( $(cat $D/round 2>/dev/null || echo 0) + 1 ))
  echo $N > $D/round
fi
echo $kind > $D/job.kind
rm -f $D/job.stop
$BB setsid sh $D/run.sh job $kind </dev/null >/dev/null 2>&1 &
_i=0
while ! job_alive && [ $_i -lt 10 ]; do sleep 1; _i=$((_i + 1)); done
if ! job_alive; then
  rm -f $D/job.kind
  [ $kind = obs ] && echo $(( N - 1 )) > $D/round
  toast "wlan0 진단: 작업을 시작하지 못해 아무것도 바꾸지 않았습니다."
  exit 0
fi
case $kind in
obs) toast "wlan0 진단 1단계(관찰, 읽기만): 약 $(( OBS_SEC / 60 + 1 ))분 동안 기록합니다. '끝' 안내가 나올 때까지 USB를 꽂아 두세요." ;;
reload) toast "wlan0 진단 2단계: Wi-Fi 드라이버를 최대 ${RELOAD_TRIES}번 다시 올려 봅니다(약 $(( RELOAD_TRIES * (RELOAD_OFF + RELOAD_SEC + 10) / 60 + 1 ))~$(( RELOAD_TRIES * (RELOAD_OFF + RELOAD_SEC + 2 * SVC_MAX + 30) / 60 + 1 ))분). USB를 꽂아 두세요." ;;
toggle) toast "wlan0 진단 3단계: Wi-Fi를 껐다 켜며 약 $(( (OFF_SEC + TEST_SEC) / 60 + 1 ))분 기록합니다. 카플레이·블루투스가 잠시 끊길 수 있습니다." ;;
unlock) toast "wlan0 진단 4단계: Wi-Fi 잠금을 잠시 풀고 약 $(( (SYNC_MAX + UNLOCK_OFF + TEST_SEC) / 60 + 2 ))분 기록한 뒤 되돌립니다. USB를 꽂아 두세요." ;;
esac
sync
