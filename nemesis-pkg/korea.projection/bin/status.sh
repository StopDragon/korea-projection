#!/system/bin/sh
# NEMESIS Manager > Korea Projection > Launch: 상태 토스트와 차량 제보용 리포트
# (korea-projection-report.md: USB가 꽂혀 있으면 USB에, 그리고 $W에 저장).
# 리포트에는 이름, 버전, 예/아니요, 개수만 넣는다. SSID, 비밀번호, 휴대폰 이름, MAC, IP는
# 넣지 않는다. 차 주인이 읽어 본 뒤 첨부한다.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
BB=${BB:-/system/bin/busybox}
APP=${APP:-/data/nemesis/apps/korea.projection}
HOTSPOT_LIB=1 . $APP/svc/hotspot.sh
ISSUES=https://github.com/StopDragon/korea-projection/issues/new?template=car-report.yml
umask 077
$BB mkdir -p $W

yn() { if "$@" >/dev/null 2>&1; then echo 예; else echo 아니요; fi; }
# USB가 마운트돼 있는가 (마운트 지점 폴더는 USB가 없어도 있을 수 있어 /proc/mounts로 본다)
USBS="/storage/usb0 /storage/usb1"
usb_in() {
  for _u in $USBS; do $BB grep -q " $_u " /proc/mounts 2>/dev/null && return 0; done
  return 1
}
# 순정 파일 위치 (테스트에서 바꿀 수 있게)
SYSAPP=${SYSAPP:-/system/app}
SYSLIB=${SYSLIB:-/system/lib}
SYSONE=${SYSONE:-/system/onebin}
HMGSTOCK=${HMGSTOCK:-/data/hmgapi/stock}
# NEMESIS.data의 값 하나 (이 헤드유닛에는 sed/cut/tr이 없다)
pver() { _v=$($BB grep '^package-version=' "$1" 2>/dev/null); echo "${_v#package-version=}"; }

report() {
  prod=$(getprop ro.build.product)
  echo "# Korea Projection 리포트"
  echo
  echo "첨부하기 전에 읽어 보세요. 이름, 버전, 예/아니요, 개수만 들어 있습니다"
  echo "(SSID, 비밀번호, 휴대폰 이름, MAC, IP 주소는 없습니다)."
  echo "제보: $ISSUES"
  echo
  echo "## 내비(헤드유닛)"
  echo "- 펌웨어 (NEMESIS os): $prod"
  echo "- targetdir (NEMESIS models): $(getprop ro.mobis.targetdir)"
  echo "- onebin: $(getprop ro.mobis.onebindir)"
  echo "- 이 패키지 버전: $(pver $APP/NEMESIS.data)"
  if is_car "$prod"; then echo "- 확인된 차: 예"; else echo "- 확인된 차: 아니요 (서비스가 대기만 함, 확인된 차: $CARS)"; fi
  echo "- NEMESIS: $(nemesis version 2>/dev/null)"
  # 따옴표 없이: 두 줄이 한 줄로 합쳐진다
  echo "- HMG-API:" $($BB grep -E '^(version|build) ' /data/hmgapi/installed.txt 2>/dev/null)
  echo "- wireless.projection 설치: $(yn [ -d /data/nemesis/apps/wireless.projection ])"
  echo "- HMG-API 무선 모드: 설치 $(mod_state) / 켜짐 $(mod_on_state) / 무선 카플레이 설정(bridge) $(bridge_state)"
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
  echo "- Wi-Fi 설정(wifi_on): $(settings get global wifi_on 2>/dev/null)"
  parse_conf $SRC
  echo "- softap.conf: $(yn [ -s $SRC ]), 찾은 문자열 ${NS:-0}개, 카플레이 SSID 길이 ${#S2}, 비밀번호 길이 ${#S4}"
  echo "- 우리 hostapd: $(yn running "hostapd $CONF"), 우리 DHCP: $(yn running "$DNSMASQ")"
  echo "- 다른 hostapd (순정 핫스팟): $(yn sh -c "$BB ps | $BB grep -v grep | $BB grep -v '$CONF' | $BB grep -q hostapd")"
  echo "- wpa_supplicant: $(yn running wpa_supplicant)"
  echo "- 지금 카플레이 연결 수: $($BB netstat -tn 2>/dev/null | $BB grep -c "$AP_IP:7000")"
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
  echo "## 서비스 로그 (ap.log 마지막 20줄)"
  echo '```'
  L=/data/nemesis/logs/korea.projection/ap.log
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
  if is_car "$_prod"; then echo "tested=yes"; else echo "tested=no"; fi
  echo "hmgapi="$($BB grep -E '^(version|build) ' /data/hmgapi/installed.txt 2>/dev/null)
  echo "nemesis=$(nemesis version 2>/dev/null)"
  echo "wp=$(yesno [ -d /data/nemesis/apps/wireless.projection ])"
  echo "mod=$(mod_state)"
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
  echo "our_dhcp=$(yesno running "$DNSMASQ")"
  echo "other_ap=$(yesno sh -c "$BB ps | $BB grep -v grep | $BB grep -v '$CONF' | $BB grep -q hostapd")"
  echo "wpa=$(yesno running wpa_supplicant)"
  echo "cp_conn=$($BB netstat -tn 2>/dev/null | $BB grep -c "$AP_IP:7000")"
  echo "made=$(date '+%Y-%m-%d %H:%M')"
}
( umask 022; status_kv > $STATUS.tmp 2>/dev/null && $BB chmod 644 $STATUS.tmp && $BB mv -f $STATUS.tmp $STATUS )

# 상태 화면 앱이 없으면(설치 때 실패) 여기서 다시 설치해 본다. 이어서 NEMESIS가 화면을 연다.
# 한 부팅에 한 번만 (sys.boot_completed를 바꿀 때마다 init의 부팅 완료 트리거가 다시 돌기 때문)
if ! app_installed; then
  _bid=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
  if [ "$(cat $W/app-try 2>/dev/null)" != "$_bid" ]; then
    echo "$_bid" > $W/app-try
    install_app >/dev/null 2>&1
  fi
fi

R=$W/korea-projection-report.md
report > $R 2>/dev/null
$BB chmod 600 $R
where=""
for u in $USBS; do
  # 마운트 지점 폴더는 USB가 없어도 있을 수 있다: /proc/mounts로 확인
  $BB grep -q " $u " /proc/mounts 2>/dev/null && $BB cp $R $u/korea-projection-report.md 2>/dev/null && sync && where=$u && break
done

# 상태는 이어서 열리는 화면(StatusActivity)이 보여 준다. 토스트는 USB에 리포트를 저장했을 때만.
[ -n "$where" ] || exit 0
a=off; running "hostapd $CONF" && a=on
d=off; running "$DNSMASQ" && d=on
c=$($BB netstat -tn 2>/dev/null | $BB grep -c "$AP_IP:7000")
# 켜짐/꺼짐
[ $a = on ] && a=켜짐 || a=꺼짐; [ $d = on ] && d=켜짐 || d=꺼짐
m="Korea Projection: 핫스팟 $a, DHCP $d, 카플레이 연결 $c개"
m="$m. 리포트를 USB에 저장했습니다(korea-projection-report.md)."
# 지원 목록에 없는 차이거나 HMG-API 훅이 켜져 있지 않으면, 새 차 추가에 필요한 HMG-API Car Report도
# 뒤에서 만들어 USB에 저장한다(1분쯤, 화면은 기다리지 않음). 끝나면 carreport.sh가 토스트로 알린다.
_need=0
is_car "$(getprop ro.build.product)" || _need=1
_hk=$(hooks_state); [ "${_hk%% *}" = on ] || _need=1
if [ $_need = 1 ] && command -v hmgapid >/dev/null 2>&1 && [ -f $APP/bin/carreport.sh ]; then
  W=$W $BB setsid sh $APP/bin/carreport.sh </dev/null >/dev/null 2>&1 &
  m="Korea Projection: 제보 자료를 USB에 저장하는 중입니다(약 1분). '이제 USB를 빼셔도 됩니다'가 뜰 때까지 꽂아 두세요."
fi
echo "$m"
am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "$m" \
  --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1
exit 0
