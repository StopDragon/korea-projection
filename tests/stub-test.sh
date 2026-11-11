#!/bin/sh
# PC(맥)에서 가짜 헤드유닛 환경으로 korea.projection 패키지와 USB 테스트 스크립트를 돌린다.
# 차에 올리기 전에 실행한다: sh tests/stub-test.sh   (실패하면 FAIL 줄과 종료 코드 1)
# 가짜 도구: getprop, pm, nemesis, hmgapid, am, settings, svc, ps, netstat, sleep, busybox
B=$(cd "$(dirname "$0")/.." && pwd)
PKG=$B/nemesis-pkg/korea.projection
T=$(mktemp -d /tmp/kp-stub.XXXXXX)
trap 'rm -rf $T' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# 차의 셸(mksh) 구문 검사. 아래 테스트는 bash로 돌아서 ksh 계열만 틀리는 구문을 못 잡는다
# (1.5.2: case 갈래 안의 ${_r%% (*} 때문에 모든 차에서 hotspot.sh가 시작되지 않았다).
# 있는 것을 모두 돌린다: ksh(맥 기본 ksh93)가 이번 버그를 잡았고, PC의 mksh는 차의 옛 mksh보다 너그러울 수 있다.
# 둘 다 없으면 건너뛰지 않고 실패로 둔다. 한계: eval 문자열 안, 실행할 때만 드러나는 차이, busybox 옵션은 못 잡는다.
KSHS=$(for s in mksh ksh; do command -v $s; done)
[ -n "$KSHS" ] || bad "구문 검사: mksh/ksh 없음"
for f in $PKG/svc/hotspot.sh $PKG/scripts/post.sh $PKG/scripts/preun.sh $PKG/bin/status.sh \
         $PKG/bin/carreport.sh $B/scripts/kp-update-test.sh $B/scripts/kp-probe.sh; do
  for KSH in $KSHS; do check "구문 검사 $(basename $KSH): ${f#$B/}" '$KSH -n $f'; done
done

mkdir -p $T/bin $T/app $T/w $T/apps $T/d $T/usb0/packages $T/logs
printf '#!/bin/sh\nexec "$@"\n' > $T/bin/bb
cat > $T/bin/getprop <<E
#!/bin/sh
case "\$1" in
  ro.build.product) cat $T/product 2>/dev/null || echo DEPEHEV.KOR.0000.V039.001.260902 ;;
  ro.mobis.targetdir) cat $T/targetdir 2>/dev/null || echo /system/onebin/depehev_kr ;;
  ro.mobis.onebindir) echo depehev_kr ;;
  sys.boot_completed) echo 1 ;;
  persist.sys.iap2.wifi) cat $T/iap2 2>/dev/null || echo 0 ;;
  *) echo 0 ;;
esac
E
cat > $T/bin/pm <<E
#!/bin/sh
[ -f $T/feat ] && echo feature:com.hkmc.software.connectivity.carplay_wireless
[ -f $T/hsfeat ] && echo feature:com.hkmc.software.wifihotspot
[ -f $T/nowififeat ] || echo feature:android.hardware.wifi
echo feature:android.hardware.wifi.direct
E
cat > $T/bin/nemesis <<E
#!/bin/sh
echo "nemesis \$*" >> $T/calls
case "\$1" in
  install) case "\$2" in
      *korea.projection.zip) [ -f $T/install_ok ] && mkdir -p $T/apps/korea.projection ;;
      *wireless.projection.zip) [ -f $T/wp_reinstall_fails ] || mkdir -p $T/apps/wireless.projection ;;
    esac ;;
  uninstall) [ "\$2" = wireless.projection ] && [ ! -f $T/wp_stuck ] && rmdir $T/apps/wireless.projection 2>/dev/null ;;
  version) echo 1.16.6 ;;
esac
exit 0
E
cat > $T/bin/hmgapid <<E
#!/bin/sh
echo "hmgapid \$*" >> $T/calls
exit 0
E
for c in svc settings; do printf '#!/bin/sh\necho "%s $*" >> %s/calls\necho 1\n' $c $T > $T/bin/$c; done
printf '#!/bin/sh\necho "$*" > %s/toast\n' $T > $T/bin/am
# 1.7.1: 패키지는 토스트(am) 대신 알림 기록(NOTICE)에 쓴다. 시험은 구역마다 예전 토스트 파일을 알림 기록으로 쓴다.
export NOTICE=$T/toast
printf '#!/bin/sh\ncat %s/ps 2>/dev/null\n' $T > $T/bin/ps
printf '#!/bin/sh\necho "tcp 0 0 192.168.43.1:7000 192.168.43.23:50000 ESTABLISHED"\n' > $T/bin/netstat
# 1.7.0 cp_count는 /proc/net/tcp·tcp6·if_inet6을 읽는다(전역 가짜: 192.168.43.1:7000 ESTABLISHED 1개)
mkdir -p $T/procnet; export PROCNET=$T/procnet
# 1.7.0: Launch마다 Car Report를 뒤에서 만든다. 기본 대기(5분)면 앞 Launch의 것이 잠금을 쥐고 남아 뒤 시험과 섞인다.
# Car Report 자체 시험(cr)은 값을 따로 준다.
export CR_WAIT=0.1 CR_MAX=5 CR_GRACE=0
# 1.7.0: Launch의 로그 모으기는 뒤에서(status.sh --collect) 돈다. 시험은 RPT_SYNC=1로 바로 하고, 뒤에서 도는 경로는 따로 본다.
# 저장 진행 기록(RPROG)도 가짜 위치로
export RPT_SYNC=1 RPROG=$T/rprog
printf '%s\n' "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode" "   0: 012BA8C0:1B58 172BA8C0:C350 01 00000000:00000000 00:00000000 00000000  1000        0 1" > $T/procnet/tcp
echo "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode" > $T/procnet/tcp6; : > $T/procnet/if_inet6
# 1.7.0 cp_count는 wlan0의 주소를 본다: 조회(인자가 wlan0 하나)일 때만 답하고, 설정 호출은 아무것도 내지 않는다
printf '#!/bin/sh\n[ "$#" = 1 ] && [ "$1" = wlan0 ] && { [ -f %s/ifc ] && cat %s/ifc || printf "wlan0 Link encap:Ethernet\\n  inet addr:192.168.43.1  Bcast:192.168.43.255  Mask:255.255.255.0\\n"; }\nexit 0\n' $T $T > $T/bin/ifconfig
printf '#!/bin/sh\n/bin/sleep 0.01\n' > $T/bin/sleep
cat > $T/bin/logcat <<'E'
#!/bin/sh
echo "11-06 20:49:35.100 D/WifiStateMachine(  500): SUP_DISCONNECTION_EVENT wlan0 a1:b2:c3:d4:e5:f6"
echo "11-06 20:49:35.200 D/WifiStateMachine(  500): CONNECT ssid=\"MyHomeNet\""
echo "11-06 20:49:35.300 E/hostapd ( 900): wpa_passphrase secret99"
echo "11-06 20:49:35.400 I/wpa_supplicant( 901): p2p device name Johns phone"
echo "11-06 20:49:35.500 I/OtherApp( 902): wifi stuff"
echo "11-06 20:49:35.600 D/WifiStateMachine(  500): NetworkInfo: type: WIFI extra: \"MyHomeNet\""
echo "11-06 20:49:35.700 I/hostapd ( 900): wlan0: STA xx WPA: pairwise key handshake completed (RSN)"
E
chmod +x $T/bin/*
# /sbin: 맥의 md5sum 위치
fixpath() { sed "s#^export PATH=.*#export PATH=$T/bin:/usr/bin:/bin:/sbin#" "$1"; }

# --- 1. hotspot.sh: softap.conf 해석, 설정 파일 이름 길이, printf ---
python3 - $T/softap.conf <<'E'
import struct,sys
u=lambda s:struct.pack('>H',len(s))+s.encode()
open(sys.argv[1],'wb').write(struct.pack('>i',3)+u('HotspotName1')+u('SSID\\cX')+u('x')+u('PASS\\word99'))
E
cp -R $PKG/* $T/app/
fixpath $PKG/svc/hotspot.sh > $T/app/svc/hotspot.sh
# 1.7.0: Launch의 로그 모으기가 carreport.sh를 직접 부른다. 헤드유닛 PATH로는 맥의 rm·sync를 못 찾아 잠금이 남으므로 맥 경로로
fixpath $PKG/bin/carreport.sh > $T/app/bin/carreport.sh
out=$(HOTSPOT_LIB=1 BB=$T/bin/bb SRC=$T/softap.conf W=$T/w sh -c '. '$T'/app/svc/hotspot.sh; parse_conf $SRC; printf "%s|%s|%s|%s\n" "$NS" "$S2" "$S4" "hostapd $CONF"')
# (맥의 sh echo는 \c를 해석하므로 테스트 쪽도 printf로 출력한다)
check "softap.conf 문자열 4개" '[ "${out%%|*}" = 4 ]'
check "백슬래시가 든 SSID/비밀번호 그대로" 'case "$out" in *"|SSID\\cX|PASS\\word99|"*) true;; *) false;; esac'
cmd=${out##*|}
check "hostapd 명령줄 ${#cmd}자 <= 45 (ps 잘림 대비)" '[ ${#cmd} -le 45 ]'

# --- 1b. hotspot.sh fix_perms: HMG-API 기록과 같은 권한 파일 되돌리기 (11-06 차의 engine status 줄 그대로) ---
mkdir -p $T/fp/bin $T/fp/perms $T/fp/w
cat > $T/fp/status <<E
CHANGED  $T/fp/perms/com.hkmc.software.connectivity.androidauto_wireless.xml [wireless-carplay-aa] stock fa91812d3eeee415768018ab6ee6804a, expected fa91812d3eeee415768018ab6ee6804a, found absent
CHANGED  $T/fp/perms/com.hkmc.software.connectivity.carplay_wireless.xml [wireless-carplay-aa] stock 95ff801a064526de56059dba10960b05, expected 95ff801a064526de56059dba10960b05, found absent
ok       /system/lib/libleafiaaac.so [wireless-carplay-aa] stock absent, expected a63e6492f38d541518b9606a978f5da3
CHANGED  $T/fp/perms/com.hkmc.software.other.xml [x] stock 00000000000000000000000000000000, expected 00000000000000000000000000000000, found absent
CHANGED  /system/lib/libfoo.so [x] stock 1, expected 2, found absent
CHANGED  /system/onebin/depehev_kr/featurexml.cfg [wireless-carplay-aa] stock c3fa5e8597b0a3e437ee81a6efc0e63a, expected 2a7ca4d59cb0bc3e6165042c1b8c62bc, found c3fa5e8597b0a3e437ee81a6efc0e63a
E
cat > $T/fp/bin/hmgapid <<E
#!/bin/sh
echo "hmgapid \$*" >> $T/fp/calls
case "\$*" in
  ping) [ -f $T/fp/down ] && exit 1; exit 0 ;;
  "engine status") cat $T/fp/status ;;
  "engine plan") cat $T/fp/plan ;;
esac
exit 0
E
printf '#!/bin/sh\necho "$*" > %s/fp/toast\n' $T > $T/fp/bin/am
printf '#!/bin/sh\n/bin/sleep 0.01\n' > $T/fp/bin/sleep
chmod +x $T/fp/bin/*
cat > $T/fp/plan <<E
rebase   /system/onebin/depehev_kr/featurexml.cfg: changed outside HMG-API (now c3fa), the mods' changes go on it
same     $T/fp/perms/com.hkmc.software.connectivity.androidauto_wireless.xml [wireless-carplay-aa]
same     $T/fp/perms/com.hkmc.software.connectivity.carplay_wireless.xml [wireless-carplay-aa]
change   /system/onebin/depehev_kr/featurexml.cfg [wireless-carplay-aa] -> 2a7ca4d59cb0bc3e6165042c1b8c62bc   [restart the head unit]
same     setting prop/persist.ium.support = carplay [wireless-carplay-aa]
E
echo "/dev/block/system /system ext4 ro,relatime 0 0" > $T/fp/mounts
mkdir -p $T/fp/bk
fp() { (cd $T/fp && PATH=$T/fp/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 NOTICE=$T/fp/toast FIX_DELAY=0 BB=$T/bin/bb W=$T/fp/w BK=$T/fp/bk APLOG=$T/fp/ap.log PERMS=$T/fp/perms MOUNTS=$T/fp/mounts sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$T'/fp/bin:/usr/bin:/bin:/sbin; fix_perms'); }
fpreset() { rm -rf $T/fp/perms $T/fp/calls $T/fp/toast $T/fp/down; mkdir -p $T/fp/perms; }
# cwd($T/fp)에 한 글자 이름 "w" 폴더가 있다: "[wireless-carplay-aa]"가 파일 이름 패턴으로 풀리면 "w"로 바뀌어 잡힌다
fpreset; fp > $T/fp/out
check "fix_perms: 기록과 md5가 같은 권한 파일 2개만 씀" '[ "$(ls $T/fp/perms | wc -l | tr -d " ")" = 2 ] && [ "$(md5sum < $T/fp/perms/com.hkmc.software.connectivity.carplay_wireless.xml | cut -c1-32)" = 95ff801a064526de56059dba10960b05 ]'
check "  md5가 다른 권한 파일·라이브러리·설정 파일은 건드리지 않음" '[ ! -f $T/fp/perms/com.hkmc.software.other.xml ] && grep -q "건너뜀: com.hkmc.software.other" $T/fp/out'
check "  계획이 우리 것뿐 → 일반 apply, --force 안 씀, 재시작 안내" 'grep -qx "hmgapid engine apply" $T/fp/calls && ! grep -q -- --force $T/fp/calls && grep -q "내비를 재부팅해 주세요(RESET 버튼 또는 NEMESIS 재부팅)" $T/fp/toast'
check "  /system이 ro였으면 rw → ro로 되돌림" 'grep -q "remount rw" $T/fp/calls && grep -q "remount ro" $T/fp/calls'
check "  1.7.2 P-14: 새로 쓴 권한 파일 이름 2개를 삭제용 기록(perms.ours)에 남김(md5가 다른 것은 없음)" '[ "$(sort $T/fp/bk/perms.ours | tr "\n" " ")" = "com.hkmc.software.connectivity.androidauto_wireless com.hkmc.software.connectivity.carplay_wireless " ]'
rm -f $T/fp/perms/com.hkmc.software.connectivity.carplay_wireless.xml; fp > $T/fp/out
check "    다시 써도 기록에 같은 이름을 겹쳐 적지 않음" '[ "$(wc -l < $T/fp/bk/perms.ours | tr -d " ")" = 2 ]'
rm -f $T/fp/bk/perms.ours; printf '%s\n' "11-06 04:10:00 권한 파일 되돌림: com.hkmc.software.connectivity.carplay_wireless" "11-06 04:10:01 권한 파일 되돌림: bad/../x" > $T/fp/ap.log; fp > $T/fp/out; rm -f $T/fp/ap.log
check "    1.7.1까지 설치한 차: 기록이 없으면 서비스 시작 때 ap.log의 이름을 기록으로 옮김(이상한 이름은 버림, 리뷰 L5)" '[ "$(cat $T/fp/bk/perms.ours)" = com.hkmc.software.connectivity.carplay_wireless ]'
rm -f $T/fp/bk/perms.ours; fp > $T/fp/out
check "    옮길 것이 없어도 빈 기록을 만들어 다음 부팅에 다시 찾지 않음" '[ -f $T/fp/bk/perms.ours ] && [ ! -s $T/fp/bk/perms.ours ]'
fpreset; rm -f $T/fp/calls $T/fp/toast; fp > $T/fp/out
rm -f $T/fp/calls $T/fp/toast; fp > $T/fp/out
check "  파일이 이미 있으면 다시 쓰지도 apply하지도 않음" '! grep -q "engine apply" $T/fp/calls && [ ! -f $T/fp/toast ]'
fpreset; echo "/dev/block/system /system ext4 rw,relatime 0 0" > $T/fp/mounts; fp > $T/fp/out
check "  /system이 원래 rw였으면 ro로 바꾸지 않음" '! grep -q "remount ro" $T/fp/calls'
echo "/dev/block/system /system ext4 ro,relatime 0 0" > $T/fp/mounts
fpreset; cp $T/fp/plan $T/fp/plan.ok; echo "change   /system/app/HKMC_DiPO.apk [other-mod] -> 1234   [restart the app]" >> $T/fp/plan; fp > $T/fp/out
check "  계획에 다른 변경이 있으면 apply하지 않고 앱에서 적용하라고 안내" '! grep -qx "hmgapid engine apply" $T/fp/calls && grep -q "HMG-API 앱에서" $T/fp/toast'
cp $T/fp/plan.ok $T/fp/plan
fpreset; sed 's/change   \/system\/onebin\/depehev_kr\/featurexml.cfg \[wireless-carplay-aa\]/change   \/system\/onebin\/depehev_kr\/featurexml.cfg [other-mod]/' $T/fp/plan.ok > $T/fp/plan; fp > $T/fp/out
check "  featurexml.cfg 변경이 다른 모드 것이면 apply 안 함" '! grep -qx "hmgapid engine apply" $T/fp/calls'
fpreset; cp $T/fp/plan.ok $T/fp/plan; echo "rebase   /system/app/X.apk: changed outside HMG-API (now 1), the mods' changes go on it" >> $T/fp/plan; fp > $T/fp/out
check "  featurexml.cfg 아닌 rebase가 있으면 apply 안 함" '! grep -qx "hmgapid engine apply" $T/fp/calls'
fpreset; cp $T/fp/plan.ok $T/fp/plan; echo "WARNING: the car's ADB TCP switch is on" >> $T/fp/plan; fp > $T/fp/out
check "  ADB 경고 같은 WARNING 줄은 막지 않음" 'grep -qx "hmgapid engine apply" $T/fp/calls'
fpreset; cp $T/fp/plan.ok $T/fp/plan; mv $T/fp/mounts $T/fp/mounts.x; fp > $T/fp/out; mv $T/fp/mounts.x $T/fp/mounts
check "  /proc/mounts를 못 읽으면 ro로 보고 ro로 되돌림" 'grep -q "remount ro" $T/fp/calls'
cp $T/fp/plan.ok $T/fp/plan
fpreset; touch $T/fp/down; fp > $T/fp/out
check "  HMG-API 데몬이 안 뜨면 아무것도 안 하고 기록만" '[ -z "$(ls $T/fp/perms)" ] && grep -q "데몬 응답 없음" $T/fp/out'

# 시작할 때의 stop_ap는 뒤에서 도는 확인 작업(fix.pid)을 건드리지 않고, 끝낼 때의 stop_all만 정리한다
mkdir -p $T/sa; echo "12345 boot" > $T/sa/fix.pid
(PATH=$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$T/sa sh -c '. '$T'/app/svc/hotspot.sh; stop_ap') >/dev/null 2>&1
check "stop_ap(시작 때)는 fix.pid를 남김" '[ -f $T/sa/fix.pid ]'
(PATH=$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$T/sa sh -c '. '$T'/app/svc/hotspot.sh; stop_all') >/dev/null 2>&1
check "stop_all(끝낼 때)는 fix.pid를 정리" '[ ! -f $T/sa/fix.pid ]'
# 1.5.6: 5GHz 149번 설정, Wi-Fi 연결 기록(커널 로그), 카플레이 연결 수 변화
WE=$T/we; mkdir -p $WE/bin $WE/w; echo boot-A > $WE/bootid
printf '#!/bin/sh\ncat %s/dmesg 2>/dev/null\n' $WE > $WE/bin/dmesg
printf '#!/bin/sh\ncat %s/netstat 2>/dev/null\n' $WE > $WE/bin/netstat; chmod +x $WE/bin/*
we() { (PATH=$WE/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$WE/w BOOT_ID=$WE/bootid CONF=$WE/hk.conf sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$WE'/bin:'$T'/bin:/usr/bin:/bin:/sbin; S2=SSIDx S4=PASS12345; '"$1"); }
we write_conf
check "1.5.6: 우리 hostapd는 5GHz 149번(hw_mode=a), 순정 netd와 같은 40MHz(HT40+), 2.4GHz 줄 없음" 'grep -qx "channel=149" $WE/hk.conf && grep -qx "hw_mode=a" $WE/hk.conf && grep -qx "ht_capab=\[HT40+\]\[SHORT-GI-20\]\[SHORT-GI-40\]" $WE/hk.conf && ! grep -q -e "^channel=6" -e "^hw_mode=g" $WE/hk.conf'
printf '%s\n' "<4>[   21.17] Firmware version = wl0: version 9.92.1" "<6>[  632.555666] CFG80211-ERROR) wl_cfg80211_set_channel : netdev_ifidx(10), chan_type(1) target channel(149) channel_width(1000)" "<6>[  632.605213] CFG80211-ERROR) wl_notify_connect_status_ap : ** AP/GO Link up event **" "<4>[  701.367538] ETHER_TYPE_802_1X[wlan0] [RX] : M2 of 4way" "<4>[  701.372626] ETHER_TYPE_802_1X[wlan0] [RX] : M4 of 4way" "<6>[  773.805023] CFG80211-ERROR) wl_cfg80211_del_station : Disconnect STA : aa:bb:cc:dd:ee:ff scb_val.val 3" "no bracket line HANG" > $WE/dmesg
we wifi_events > $WE/out1
check "  Wi-Fi 연결 기록: 채널·AP 올라옴·연결(인증 끝)·끊김을 커널 시각과 함께, MAC은 없음" '[ "$(grep -c "Wi-Fi: " $WE/out1)" = 4 ] && grep -q "Wi-Fi: AP 채널 149 (커널 632초)" $WE/out1 && grep -q "Wi-Fi: AP 올라옴 (커널 632초)" $WE/out1 && grep -q "Wi-Fi: 기기 연결(Wi-Fi 인증 끝) (커널 701초)" $WE/out1 && grep -q "Wi-Fi: 기기 연결 끊김 (커널 773초)" $WE/out1 && ! grep -q -e "aa:bb" -e HANG $WE/out1'
we wifi_events > $WE/out2
check "  같은 커널 로그는 다시 남기지 않음(어디까지 남겼는지 기억)" '[ ! -s $WE/out2 ] && grep -q "^boot-A 773.805" $WE/w/ktime'
echo "<6>[  800.1] CFG80211-ERROR) wl_cfg80211_del_station : Disconnect STA : aa:bb:cc:dd:ee:ff" >> $WE/dmesg; we wifi_events > $WE/out3
check "  새로 생긴 줄만 남김" '[ "$(grep -c "Wi-Fi: " $WE/out3)" = 1 ] && grep -q "커널 800초" $WE/out3'
echo boot-B > $WE/bootid; printf '%s\n' "<6>[   30.5] CFG80211-ERROR) wl_notify_connect_status_ap : ** AP/GO Link up event **" > $WE/dmesg; we wifi_events > $WE/out4
check "  재부팅하면(부팅 id가 다름) 커널 시각이 작아도 처음부터 남김" 'grep -q "Wi-Fi: AP 올라옴 (커널 30초)" $WE/out4'
echo boot-C > $WE/bootid; printf '%s\n' "<6>[    5.8] IPv6: ADDRCONF(NETDEV_CHANGE): ncm0: link becomes ready" "<6>[  300.0] CFG80211-ERROR) wl_cfg80211_del_station : Disconnect STA : ff:ff:ff:ff:ff:ff scb_val.val 3" "<4>[  301.0] dhd_os_send_hang: HANG event sent" > $WE/dmesg; we wifi_events > $WE/out5
check "  유선 카플레이(NETDEV_CHANGE)는 HANG으로 세지 않고, hostapd 시작 때 모두 비우는 끊김(ff:ff…)도 세지 않음, 진짜 HANG은 남김" '! grep -q "기기 연결 끊김" $WE/out5 && [ "$(grep -c "HANG" $WE/out5)" = 1 ] && grep -q "Wi-Fi 칩 응답 없음(HANG) (커널 301초)" $WE/out5'
# 1.7.1: 무선 AA 단계 기록(aa_events). 니로 성공 시도(2026-11-08 02:16)의 줄 꼴. 폰 이름(Pixel7·홍길동폰)이 섞여 있다.
echo boot-A > $WE/bootid
cat > $WE/aalog <<'E'
11-08 02:16:26.180 D/PhoneProjection( 1660): [ WirelessPhoneProjectionService ] broadcast action = android.bluetooth.device.action.START_SPP_CONNECT_FOR_CONNECTIVITY
11-08 02:16:27.850 I/AAProjection(  775): WirelessExplorer : [Pixel7] Sent WifiVersionRequest, Protocol version is 1.0	isRetry :false
11-08 02:16:27.940 D/AAProjection(  775): WirelessExplorer : 	WifiVersionResponse hasDeviceSerial: true	wirelessSupported = true
11-08 02:16:31.950 I/PhoneProjection( 1660): [ f ] getWiFiApMode wifiMode = 2
11-08 02:16:32.120 D/AAProjection(  775): WirelessExplorer : isWifiApEnable = true, mode = 2
11-08 02:16:32.170 D/AAProjection(  775): WirelessExplorer : [홍길동폰] Sent start request
11-08 02:16:32.410 I/AAProjection(  775): GalReceiverService : MSG_WIFI_TRANSPORT_INIT retu = 0
11-08 02:16:33.000 I/OtherApp(  1): Sent start request from someone else
E
printf '#!/bin/sh\ncat %s/aalog\n' $WE > $WE/bin/logcat; chmod +x $WE/bin/logcat
we aa_events > $WE/aa1
check "1.7.1 AA 단계 기록: 성공 시도 7단계를 순서대로 ap.log에, 이름·다른 태그 줄은 없음" '[ "$(grep -c "안드로이드 오토: " $WE/aa1)" = 7 ] && grep -q "안드로이드 오토: 블루투스로 연결 시작(SPP) (02:16:26.180)" $WE/aa1 && grep -q "폰 무선 지원 true" $WE/aa1 && grep -q "AP 모드 2 " $WE/aa1 && grep -q "AP 켜짐 true 모드 2" $WE/aa1 && grep -q "폰에 Wi-Fi 연결 요청" $WE/aa1 && grep -q "Wi-Fi 연결 준비 결과 0" $WE/aa1 && ! grep -q -E "Pixel7|홍길동|someone" $WE/aa1'
we aa_events > $WE/aa2
check "  같은 줄은 다시 남기지 않음(logcat 시각 기억)" '[ ! -s $WE/aa2 ] && grep -q "^boot-A 11-08 02:16:32.410" $WE/w/aatime'
printf '%s\n' "11-08 02:20:00.000 D/AAProjection(  775): GalReceiverService : Received ACTION_WIRELESS_SPP_CONNECT_TIMEOUT, address = 11:22:33:44:55:66" "11-08 02:20:00.100 W/AAProjection(  775): WirelessExplorer : ==> rfcommDisconnect, Start Wireless Session and Attached, but rfcommDisconnect" "11-08 02:20:01.000 I/PhoneProjection( 1660): [ f ] getWiFiApMode wifiManager.isWifiApEnabled() = false, return APMode.UNKNOWN" >> $WE/aalog
we aa_events > $WE/aa3
check "  새 줄만: 시간 초과·RFCOMM 끊김·AP 모드 모름, 주소는 없음" '[ "$(grep -c "안드로이드 오토: " $WE/aa3)" = 3 ] && grep -q "SPP 연결 시간 초과" $WE/aa3 && grep -q "블루투스 RFCOMM 끊김" $WE/aa3 && grep -q "AP 모드 모름" $WE/aa3 && ! grep -q "11:22:33" $WE/aa3'
rm -f $WE/w/aatime; (AAEV_MAX=3; export AAEV_MAX; we aa_events) > $WE/aa4
check "  한 번에 최대 AAEV_MAX줄(재시도가 몰려도 ap.log가 넘치지 않음)" '[ "$(grep -c "안드로이드 오토: " $WE/aa4)" = 3 ]'
printf '%s\n' "11-08 02:20:02.000 E/AAProjection(  775): WirelessExplorer : isWifiApEnable = false !!!" >> $WE/aalog; we aa_events > $WE/aa3b
check "  mode가 없는 isWifiApEnable 줄(니로 실제 꼴)은 'AP 켜짐 false'만, 시각을 값으로 잘라 오지 않음(리뷰 M2)" 'grep -q "AP 켜짐 false (02:20:02.000)" $WE/aa3b && ! grep -q "모드 [0-9]" $WE/aa3b'
echo boot-B > $WE/bootid; we aa_events > $WE/aa5
check "  재부팅(부팅 id가 다름)하면 처음부터 다시 봄" '[ "$(grep -c "안드로이드 오토: " $WE/aa5)" = 11 ]'
check "  서비스 30초 회차·순정 AP 회차 모두 aa_events를 부름, 리포트 폰 프로젝션 칸은 ModeManagerService V·I·D를 뺌" '[ "$(grep -c "wifi_events; aa_events; cp_watch" $T/app/svc/hotspot.sh)" = 4 ] && grep -q "grep -v -E \"\$PPNOISE\"" $T/app/bin/status.sh && grep -q "^PPNOISE=. \[VDI\]/ModeManagerService" $T/app/bin/status.sh'
rm -f $WE/bin/logcat $WE/w/aatime; echo boot-A > $WE/bootid
: > $WE/bootid; printf '%s\n' "<6>[  400.0] ** AP/GO Link up event **" > $WE/dmesg; we wifi_events > $WE/out6; we wifi_events > $WE/out7
check "  부팅 id를 못 읽어도 같은 줄을 30초마다 다시 남기지 않음" '[ "$(grep -c "AP 올라옴" $WE/out6)" = 1 ] && [ ! -s $WE/out7 ]'
check "  디버그 로그는 태그와 상관없이 Wi-Fi 이름·비밀번호가 나올 수 있는 줄을 버림, 설치 때 함께 넣은 busybox를 지우지 않음(1.6.2)" 'grep -q "grep -v -i -E .ssid|psk \*\[=:\]|passphrase|password|bssid|key=." $T/app/svc/hotspot.sh && for l in "I/GPM ( 1): wifi ssid HomeNet" "I/GPM ( 1): psk=Secret1" "I/GPM ( 1): PSK : Secret2" "I/GPM ( 1): passphrase x"; do echo "$l" | grep -v -i -E "ssid|psk *[=:]|passphrase|password|bssid|key=" | grep -q . && exit 1; done; echo "I/Iap2Service ( 1): Wifi Access Auth Type :  WPA2_PSK" | grep -v -i -E "ssid|psk *[=:]|passphrase|password|bssid|key=" | grep -q WPA2_PSK && ! grep -q "rm .*bin/busybox" $T/app/scripts/post.sh'
mkdir -p $WE/pn; echo "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode" > $WE/pn/tcp6; : > $WE/pn/if_inet6; echo "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode" > $WE/pn/tcp
(PROCNET=$WE/pn; we cp_watch) > $WE/c1
printf '%s\n' "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode" "   0: 012BA8C0:1B58 172BA8C0:CB20 01 0" "   1: 012BA8C0:1B58 172BA8C0:BF68 06 0" > $WE/pn/tcp
(PROCNET=$WE/pn; we cp_watch) > $WE/c2; (PROCNET=$WE/pn; we cp_watch) > $WE/c3; echo "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode" > $WE/pn/tcp; (PROCNET=$WE/pn; we cp_watch) > $WE/c4
check "  카플레이 연결 수(ESTABLISHED만)가 바뀔 때만 남김: 0→1, 같으면 없음, 1→0" '[ ! -s $WE/c1 ] && grep -q "카플레이 연결 0 → 1" $WE/c2 && [ ! -s $WE/c3 ] && grep -q "카플레이 연결 1 → 0" $WE/c4'
# 1.7.0: 무선 카플레이 연결 수 = /proc/net/tcp·tcp6에서 로컬 포트 7000(1B58)·ESTABLISHED(01)·로컬 주소가 wlan0 주소인 것
mkdir -p $WE/pn
printf '%s\n' "fe80000000000000021122fffe334455 07 40 20 80    wlan0" "fe800000000000000a0b0cfffe0d0e0f 05 40 20 80     ncm0" > $WE/pn/if_inet6
printf '%s\n' "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode" "   0: 012BA8C0:1B58 172BA8C0:CB20 01 0" "   1: 0101A8C0:1B58 1401A8C0:C351 01 0" "   2: 00000000:1B58 00000000:0000 0A 0" "   3: 012BA8C0:1B58 172BA8C0:BF68 06 0" "   4: 012BA8C0:1B59 172BA8C0:BF69 01 0" > $WE/pn/tcp
printf '%s\n' "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode" "   0: 000080FE00000000FF221102554433FE:1B58 000080FE00000000FF221102AABBCCDD:C352 01 0" "   1: 000080FE00000000FF0C0B0A0F0E0DFE:1B58 000080FE00000000FF0C0B0A11223344:C353 01 0" "   2: 0000000000000000FFFF0000012BA8C0:1B58 0000000000000000FFFF0000172BA8C0:C354 01 0" > $WE/pn/tcp6
printf 'wlan0 Link encap:Ethernet\n  inet addr:192.168.43.1  Mask:255.255.255.0\n' > $T/ifc
check "1.7.0 cp_count: wlan0 IPv4·긴 IPv6·IPv4-in-IPv6만 셈(3), 다른 망·LISTEN·TIME_WAIT·다른 포트·유선(ncm0)은 안 셈" '[ "$(PROCNET=$WE/pn we cp_count)" = 3 ]'
printf 'wlan0 Link encap:Ethernet\n  inet addr:192.168.1.1  Mask:255.255.255.0\n' > $T/ifc
check "  순정 AP 차(wlan0 주소가 다름, K3)는 그 주소로 셈(192.168.1.1 1개 + wlan0 IPv6 1개)" '[ "$(PROCNET=$WE/pn we cp_count)" = 2 ]'
# 1.7.1: 순정 AP가 ap0에 뜨는 차(차에서 본 적 없음): wlan0 IPv4는 없고 ap0이 192.168.1.1
mkdir -p $WE/sn/ap0; printf 'eth0 x\n' > $T/ifc
printf '#!/bin/sh\n[ "$1" = ap0 ] && { printf "ap0 Link encap:Ethernet\\n  inet addr:192.168.1.1  Mask:255.255.255.0\\n"; exit 0; }\nexec %s/bin/ifconfig "$@"\n' $T > $WE/bin/ifconfig; chmod +x $WE/bin/ifconfig
check "1.7.1 cp_count: ap0 같은 인터페이스의 주소도 셈(ap0 IPv4 1개 + wlan0 IPv6 1개)" '[ "$(SYSNET=$WE/sn PROCNET=$WE/pn we cp_count)" = 2 ] && [ "$(SYSNET=$WE/sn we cp_ifs)" = "wlan0 ap0" ]'
check "  ap0이 없으면 wlan0만(wlan0 IPv6 1개)" '[ "$(SYSNET=$WE/nosn PROCNET=$WE/pn we cp_count)" = 1 ]'
rm -f $WE/bin/ifconfig; rm -rf $WE/sn
: > $WE/pn/if_inet6; printf 'eth0 x\n' > $T/ifc
check "  wlan0 주소를 못 읽으면 0" '[ "$(PROCNET=$WE/pn we cp_count)" = 0 ]'
rm -f $WE/pn/if_inet6 $WE/pn/tcp6; rm -f $T/ifc
check "  IPv6 파일이 없는 커널에서도 IPv4는 셈" '[ "$(PROCNET=$WE/pn we cp_count)" = 1 ]'
rm -rf $WE/pn/*
check "  /proc/net 파일이 하나도 없으면 0(멈추지 않음)" '[ "$(PROCNET=$WE/pn we cp_count </dev/null)" = 0 ]'
check "  리포트·상태 파일·토스트·서비스 로그가 모두 cp_count를 씀(netstat으로 세는 곳이 남지 않음)" '! grep -n "netstat" $PKG/svc/hotspot.sh $PKG/bin/status.sh | grep -v "^[^:]*:[0-9]*:[[:space:]]*#" | grep -q . && [ "$(grep -c "cp_count)" $PKG/bin/status.sh)" = 3 ]'
# 1.7.0: 무선 안드로이드 오토 신호(기본 켜짐). 끄기 표시($BK/aa-off)가 없고 우리 hostapd가 돌 때만 sys.kp.aa_ap=1, 바뀔 때만 setprop
printf '#!/bin/sh\ncase "$1" in sys.kp.aa_ap) cat %s/aaprop 2>/dev/null ;; *) exec %s/bin/getprop "$@" ;; esac\n' $WE $T > $WE/bin/getprop
printf '#!/bin/sh\necho "setprop $*" >> %s/setprops; [ "$1" = sys.kp.aa_ap ] && echo "$2" > %s/aaprop\nexit 0\n' $WE $WE > $WE/bin/setprop
chmod +x $WE/bin/getprop $WE/bin/setprop
cp $T/ps $WE/ps.keep 2>/dev/null; rm -f $WE/aaprop $WE/setprops $WE/aa-off
: > $WE/aa-off; echo "  1 root 0 S hostapd $WE/hk.conf" > $T/ps
(AAOFF=$WE/aa-off; export AAOFF; we aa_sig) > $WE/a1
check "1.7.0 AA 신호: 끄기 표시(kp-aa-off)가 있으면 setprop 안 함(처음엔 조용히)" '[ ! -f $WE/setprops ] && [ ! -s $WE/a1 ]'
rm -f $WE/aa-off; (AAOFF=$WE/aa-off; export AAOFF; we aa_sig) > $WE/a2; (AAOFF=$WE/aa-off; export AAOFF; we aa_sig) > $WE/a3
check "  기본(끄기 표시 없음) + 우리 hostapd → 1, 로그 한 줄, 같은 값이면 다시 안 함" '[ "$(cat $WE/aaprop)" = 1 ] && [ "$(grep -c "sys.kp.aa_ap 1" $WE/setprops)" = 1 ] && grep -q "무선 안드로이드 오토(시험) 켜짐" $WE/a2 && [ ! -s $WE/a3 ]'
: > $T/ps; we aa_sig > $WE/a4
check "  우리 hostapd가 멈추면 0" '[ "$(cat $WE/aaprop)" = 0 ] && grep -q "신호 끔" $WE/a4'
echo "  1 root 0 S hostapd $WE/hk.conf" > $T/ps; we aa_sig >/dev/null; we stop_ap >/dev/null 2>&1
check "  stop_ap(서비스 끝·비켜 주기·삭제)는 신호를 0으로" '[ "$(cat $WE/aaprop)" = 0 ]'
echo "  1 root 0 S hostapd $WE/hk.conf" > $T/ps; we aa_sig >/dev/null
printf '%s\n' "  1 root 0 S hostapd $WE/hk.conf" "  2 root 0 S hostapd /data/misc/wifi/hostapd.conf" > $T/ps
we 'prod=TESTX.KOR.1.260902; ap_yield' >/dev/null 2>&1
check "  다른 hostapd에 비켜 주면 신호 0(리뷰 M1)" '[ "$(cat $WE/aaprop)" = 0 ]'
echo "  1 root 0 S hostapd $WE/hk.conf" > $T/ps
(PATH=$WE/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb BB_OWN=$T/bin/bb W=$WE/w BOOT_ID=$WE/bootid CONF=$WE/hk.conf sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$WE'/bin:'$T'/bin:/usr/bin:/bin:/sbin; aa_sig') >/dev/null 2>&1
check "  1.7.2(P-6): 함께 넣은 busybox를 쓰는 내비(tcc803x)도 순정 AP 기록이 없으면 신호를 켬(BB_OWN 조건 뺌)" '[ "$(cat $WE/aaprop)" = 1 ]'
check "  로그·신호에 SSID·비밀번호 값이 없음" '! grep -q -e SSIDx -e PASS12345 $WE/a2 $WE/a4 $WE/setprops'
check "  순정 AP 경로(stock_ap_mode)는 신호를 켜지 않음(aa_sig를 부르지 않음)" '[ -z "$(awk "/^stock_ap_mode\(\) \{/,/^}/" $PKG/svc/hotspot.sh | grep "aa_sig")" ]'
check "  설치 때 어느 USB든 kp-aa-off면 끄기 표시($BK, 업데이트해도 남음), 아니면 kp-aa-on으로 지움(끄기를 먼저 봄)" 'grep -q "kp-aa-off \] || \[ -f /storage/usb1/kp-aa-off \]; then : > \$BK/aa-off" $PKG/scripts/post.sh && grep -q "kp-aa-on \]; then rm -f \$BK/aa-off" $PKG/scripts/post.sh'
check "  모드 2.2.0 hooks.jar에 AA 훅이 있음(속성 이름이 패키지와 같음, AP 설정 저장도 막음)" 'unzip -p $PKG/hmgapi/wireless-carplay-aa.zip hooks.jar > $WE/hj.jar && unzip -p $WE/hj.jar classes.dex | strings | grep -qx "sys.kp.aa_ap" && unzip -p $WE/hj.jar classes.dex | strings | grep -qx "setWifiApConfiguration" && grep -q "^AAPROP=sys.kp.aa_ap$" $PKG/svc/hotspot.sh'
cp $WE/ps.keep $T/ps 2>/dev/null || : > $T/ps
# 1.7.0: Wi-Fi 장치(wlan0)가 없어 hostapd가 바로 꺼지는 차(그랜저 IG #52·#53). 이번 부팅에 한 번만 남기고 순정 Wi-Fi 기록을 파일로
echo boot-W > $WE/bootid; rm -f $WE/w/nowlan $WE/w/nowlan-wifi.txt; : > $T/ps
(WLAN=$WE/no-wlan0; export WLAN; we up) > $WE/u1 2>&1; (WLAN=$WE/no-wlan0; export WLAN; we up) > $WE/u2 2>&1
check "1.7.0 wlan0 없음: 처음 한 번 'Wi-Fi 장치(wlan0)가 없음'과 순정 Wi-Fi 기록 파일, 같은 부팅의 다음 시도는 조용히(34초마다 반복 줄 없음)" 'grep -q "Wi-Fi 장치(wlan0)가 없음" $WE/u1 && grep -q "^wifi_on=" $WE/w/nowlan-wifi.txt && [ "$(cat $WE/w/nowlan)" = boot-W ] && ! grep -q -e "hostapd 시작" -e "wlan0)가 없음" $WE/u2'
check "  5GHz 실패 문구로 오해하게 쓰지 않음" '! grep -q "5GHz" $WE/u1'
echo boot-X > $WE/bootid; (WLAN=$WE/no-wlan0; export WLAN; we up) > $WE/u3 2>&1
check "  다음 부팅에는 다시 한 번 남김" 'grep -q "Wi-Fi 장치(wlan0)가 없음" $WE/u3'
(we 'c=0; running() { c=$((c+1)); [ $c -gt 1 ]; }; up') > $WE/u4 2>&1
check "  wlan0가 생겨 hostapd가 켜지면 기록을 지우고 한 줄 남김" 'grep -q "Wi-Fi 장치(wlan0)가 생겨 hostapd가 켜짐" $WE/u4 && [ ! -f $WE/w/nowlan ]'
check "  리포트 3-log.txt에 그 기록 파일이 들어감, 상태 파일 nowlan 키" 'grep -q "for _f in \$NOWLAN_LOG" $PKG/bin/status.sh && grep -q "cat \$APLOG.1 \$APLOG" $PKG/bin/status.sh && grep -q "echo \"nowlan=\$(yesno nowlan_now)\"" $PKG/bin/status.sh'
# 1.7.0: 폰 프로젝션 기록의 가리기(KPMASK). #47 꼴(괄호 안 한글·띄어쓰기 이름)과 한 낱말 이름(Pixel7 등), C·UTF-8 로케일 모두
for loc in C en_US.UTF-8; do
  (LC_ALL=$loc; export LC_ALL; we 'awk "$KPMASK"') < $B/tests/kpmask-sample.txt > $WE/km.$loc
done
check "1.7.0 가리기: 폰 이름·SSID·비밀번호·MAC·다른 IP가 0건(C·UTF-8)" '! grep -q -E "홍길동|Fold7|Pixel7|GalaxyS24|MyPhone|MyNet|secret|AA:BB|AA-BB|1234 5678|abcdefgh1|10\.0\.0\.5|01098765432|홍길동|Kim Office|0212345678|02-1234-5678|1588-1234|세종대로|Hong Gildong|시험용폰|시험폰2" $WE/km.C $WE/km.en_US.UTF-8 && grep -q "V039.001.260902" $WE/km.C && grep -q "\[   12.345678\] dhd_module_init" $WE/km.C && [ "$(wc -l < $WE/km.C)" = "$(wc -l < $B/tests/kpmask-sample.txt)" ]'
check "  원인 자료는 남김: isWifiApEnable 줄, 'Failed to find host IP/BSSID', 핫스팟 주소, pid, 숫자 괄호, 클래스 표시" 'grep -q "isWifiApEnable = false, mode = 0" $WE/km.C && grep -q "Failed to find host IP/BSSID 192.168.43.1" $WE/km.C && grep -q "( 1625)" $WE/km.C && grep -q "connectStatus (4)" $WE/km.C && grep -q "\[ WirelessPhoneProjectionService \]" $WE/km.C'
check "1.7.1 가리기: 커널 명령줄 btaddr·wifimac·serialno 값, 따옴표 안 SSID, 구분자 없는 MAC이 0건(C·UTF-8)" '! grep -q -E "A1B2C3D4E5F6|001122AABBCC|KMHXX12345|ABC6789XYZ|HomeWiFi|9C2F4A7B1E3D" $WE/km.C $WE/km.en_US.UTF-8 && grep -q "Kernel command line: console=ttyS0 androidboot.btaddr=\[가림" $WE/km.C'
check "  경로·빈 따옴표는 남김(원인 자료)" 'grep -q "\"/data/misc/wifi/wpa_supplicant.conf\"" $WE/km.C && grep -q "empty \"\"" $WE/km.C'
check "  디버그 로그 태그에 AAProjection·PhoneProjection·RFCOMM이 있고, 없는 태그(GPM*·GalReceiver*)는 뺌" 'grep -q "^TAGS=.*AAProjection|PhoneProjection.*bt-rfcomm" $PKG/svc/hotspot.sh && ! grep -q "^TAGS=.*GPM\[" $PKG/svc/hotspot.sh'
check "  디버그 로그 파이프가 KPMASK를 거침, awk가 안 되면 남기지 않음(기본은 꺼짐 그대로)" 'grep -q "awk \"\$KPMASK\" | \$_u >> \$W/cp.log" $PKG/svc/hotspot.sh && grep -q "디버그 로그 안 남김: 가리기" $PKG/svc/hotspot.sh && grep -q "\[ -f \$W/debug \] || return 0" $PKG/svc/hotspot.sh'

# --- 1.7.2 P-6: aa_sig 조건(BB_OWN 뺌, wlan0 주소 더함), 이유 파일 aa.why ---
mkdir -p $WE/bk; rm -f $WE/bk/* $WE/w/aa.why $WE/setprops; echo 0 > $WE/aaprop
cp $T/ps $WE/ps.keep2 2>/dev/null
wa() { (BK=$WE/bk AAOFF=$WE/bk/aa-off HINT=$WE/hint; export BK AAOFF HINT; we "$1"); }
echo "  1 root 0 S hostapd $WE/hk.conf" > $T/ps
wa aa_sig > $WE/p6a
check "1.7.2 P-6: 우리 hostapd + wlan0에 우리 AP 주소 → 1, 이유 on" '[ "$(cat $WE/aaprop)" = 1 ] && [ "$(cat $WE/w/aa.why)" = on ] && grep -q "켜짐: 모드에 우리 AP를 알림" $WE/p6a'
printf 'wlan0 Link encap:Ethernet\n  inet6 addr: fe80::1/64\n' > $T/ifc; wa aa_sig > $WE/p6b
check "  wlan0에 우리 AP 주소가 없으면 0, 이유 noaddr, 로그 한 줄에 이유" '[ "$(cat $WE/aaprop)" = 0 ] && [ "$(cat $WE/w/aa.why)" = noaddr ] && grep -q "신호 끔: 이유 wlan0에 우리 AP 주소 없음" $WE/p6b'
wa aa_sig > $WE/p6c
check "  신호가 그대로면 로그를 다시 남기지 않음" '[ ! -s $WE/p6c ]'
rm -f $T/ifc; wa aa_sig > $WE/p6d
check "  주소가 생기면 다음 점검에서 1" '[ "$(cat $WE/aaprop)" = 1 ] && grep -q "켜짐" $WE/p6d'
: > $T/ps; wa aa_sig > $WE/p6e
check "  hostapd가 없으면 0, 이유 nohostapd" '[ "$(cat $WE/aaprop)" = 0 ] && [ "$(cat $WE/w/aa.why)" = nohostapd ] && grep -q "이유 우리 hostapd 없음" $WE/p6e'
echo "  1 root 0 S hostapd $WE/hk.conf" > $T/ps; : > $WE/bk/stockap.seen; wa aa_sig > $WE/p6f
check "  순정 카플레이 AP를 본 차(stockap.seen)는 hostapd가 돌아도 0, 이유 stockap(순정 AP 경로 차는 신호를 켜지 않음)" '[ "$(cat $WE/aaprop)" = 0 ] && [ "$(cat $WE/w/aa.why)" = stockap ]'
rm -f $WE/bk/stockap.seen; : > $WE/bk/aa-off; wa aa_sig > $WE/p6g
check "  끄기 파일이 있으면 0, 이유 off" '[ "$(cat $WE/aaprop)" = 0 ] && [ "$(cat $WE/w/aa.why)" = off ]'
rm -f $WE/bk/aa-off
(PATH=$WE/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb BB_OWN=$T/bin/bb BK=$WE/bk W=$WE/w BOOT_ID=$WE/bootid CONF=$WE/hk.conf sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$WE'/bin:'$T'/bin:/usr/bin:/bin:/sbin; aa_sig') > $WE/p6h 2>&1
check "  함께 넣은 busybox(BB_OWN)여도 순정 AP 기록이 없으면 1(P-6: BB_OWN 조건 뺌)" '[ "$(cat $WE/aaprop)" = 1 ]'
wa 'aa_sig 0 yield' > $WE/p6i
check "  비켜 줄 때는 이유 yield, stop_ap는 이유 stop" '[ "$(cat $WE/w/aa.why)" = yield ] && grep -q "이유 다른 hostapd에 비켜 줌" $WE/p6i && wa "aa_sig; stop_ap" >/dev/null 2>&1 && [ "$(cat $WE/w/aa.why)" = stop ]'
check "  이유 파일·로그에 SSID·비밀번호 값이 없음" '! grep -q -e SSIDx -e PASS12345 $WE/w/aa.why $WE/p6a $WE/p6b $WE/p6e $WE/p6i'
check "  status.sh는 kp-aa-off 때 이유 off로 끄고, 리포트에 이유를 보임" 'grep -q "aa_sig 0 off" $PKG/bin/status.sh && grep -q "모드에 알린 신호 .*(이유: " $PKG/bin/status.sh'

# --- 1.7.2 P-4: AA 상태 안내(hint 파일), aa_events 새 줄 ---
echo boot-H > $WE/bootid; rm -f $WE/w/aatime $WE/hint
echo "  1 root 0 S hostapd $WE/hk.conf" > $T/ps; echo 1 > $WE/aaprop
cat > $WE/aalog2 <<'E'
11-08 02:07:57.610 I/PhoneProjection( 1660): [ WirelessPhoneProjectionService ] isCheckReady ret = false
11-08 02:07:57.850 I/BTCMService( 1159): <> preConditionCheckForConnectSpp = false
11-08 02:07:57.870 D/PhoneProjection( 1660): [ b ] onSppConnect() ret = false
11-08 02:07:58.000 D/PhoneProjection( 1660): [ WirelessPhoneProjectionService ] requestWLDeviceConnectStatusUpdate [Pixel7]
E
printf '#!/bin/sh\ncat %s/aalog2\n' $WE > $WE/bin/logcat; chmod +x $WE/bin/logcat
wa 'HINT_ON=1; aa_events' > $WE/h1
check "1.7.2 P-4: isCheckReady false 뒤 30초 안 onSppConnect false → 상태 안내 aa=bt, ap.log에 이유, 이름 없음" 'grep -qx "aa=bt" $WE/hint && grep -qx "boot=boot-H" $WE/hint && grep -q "폰 프로젝션 준비 확인 false" $WE/h1 && grep -q "헤드유닛 쪽 블루투스(SPP) 다시 연결 거절" $WE/h1 && grep -q "안내(상태 화면): 안드로이드 폰의 블루투스를 껐다 켜 주세요" $WE/h1 && ! grep -q Pixel7 $WE/h1 $WE/hint'
check "  안내 파일은 누구나 읽을 수 있게(644), 비밀값 없음" '[ "$(stat -f %Lp $WE/hint)" = 644 ] && ! grep -q -e SSIDx -e PASS12345 $WE/hint'
rm -f $WE/w/aatime $WE/hint
printf '%s\n' "11-08 02:07:00.000 I/PhoneProjection( 1660): [ WirelessPhoneProjectionService ] isCheckReady ret = false" "11-08 02:07:57.870 D/PhoneProjection( 1660): [ b ] onSppConnect() ret = false" > $WE/aalog2
wa 'HINT_ON=1; aa_events' > $WE/h2
check "  isCheckReady false가 30초보다 앞이면 안내하지 않음(줄만 남김)" '! grep -q "^aa=bt" $WE/hint 2>/dev/null && grep -q "다시 연결 거절" $WE/h2'
rm -f $WE/w/aatime $WE/hint
printf '%s\n' "11-08 02:08:27.830 I/PhoneProjection( 1660): [ WirelessPhoneProjectionService ] connectivityConnectionTimeout() ppType[2], tryCount[1], timeoutReason[2]" > $WE/aalog2
wa 'HINT_ON=1; aa_events' > $WE/h3
check "  PP 연결 시간 초과 tryCount 1은 기록만(재시도 중)" 'grep -q "폰 프로젝션 연결 시간 초과(시도 1)" $WE/h3 && ! grep -q "^aa=bt" $WE/hint 2>/dev/null'
echo "11-08 02:08:33.050 I/PhoneProjection( 1660): [ WirelessPhoneProjectionService ] connectivityConnectionTimeout() ppType[2], tryCount[2], timeoutReason[2]" >> $WE/aalog2
wa 'HINT_ON=1; aa_events' > $WE/h4
check "  tryCount 2(재시도 포기) → aa=bt" 'grep -q "시도 2" $WE/h4 && grep -qx "aa=bt" $WE/hint && grep -q "다시 시도를 포기함" $WE/h4'
rm -f $WE/w/aatime $WE/hint
echo "11-08 01:56:34.170 E/PhoneProjection( 1669): [ WirelessPhoneProjectionService ] connectivityConnectPPHandler isConnectivityActivated return true" > $WE/aalog2
wa 'HINT_ON=1; aa_events' > $WE/h5
check "  isConnectivityActivated return true → aa=cpwait(카플레이가 연결되어 AA는 기다림)" 'grep -qx "aa=cpwait" $WE/hint && grep -q "카플레이 연결 중이라 건너뜀" $WE/h5'
rm -f $WE/w/aatime $WE/hint
printf '%s\n' "11-08 02:16:20.000 I/PhoneProjection( 1660): [ f ] getWiFiApMode wifiManager.isWifiApEnabled() = false, return APMode.UNKNOWN" "11-08 02:16:40.000 I/PhoneProjection( 1660): [ f ] getWiFiApMode wifiManager.isWifiApEnabled() = false, return APMode.UNKNOWN" > $WE/aalog2
wa 'HINT_ON=1; AA_ON_TM="11-08 02:16:30"; aa_events' > $WE/h6
check "  신호가 켜진 시각보다 먼저 온 'AP 모드 모름' → aa=bt, 뒤에 온 것은 기록만" 'grep -qx "aa=bt" $WE/hint && [ "$(grep -c "신호보다 먼저" $WE/h6)" = 2 ] && grep -q "신호보다 먼저 AP 모드를 물음" $WE/h6'
rm -f $WE/w/aatime $WE/hint
wa 'HINT_ON=1; aa_events' > $WE/h6b
check "  신호가 켜진 시각을 모르면(이번 실행에서 안 켜짐) 'AP 모드 모름'만으로는 안내 안 함" '! grep -q "^aa=bt" $WE/hint 2>/dev/null'
rm -f $WE/w/aatime $WE/hint
printf '%s\n' "11-08 02:07:57.610 I/PhoneProjection( 1660): [ WirelessPhoneProjectionService ] isCheckReady ret = false" "11-08 02:07:57.870 D/PhoneProjection( 1660): [ b ] onSppConnect() ret = false" > $WE/aalog2
echo 0 > $WE/aaprop; wa 'HINT_ON=1; aa_events' > $WE/h7
check "  신호가 0인 차는 안내하지 않음(줄만 남김)" '! grep -q "^aa=bt" $WE/hint 2>/dev/null && grep -q "다시 연결 거절" $WE/h7'
rm -f $WE/w/aatime $WE/hint; echo 1 > $WE/aaprop; : > $WE/bk/aa-off; wa 'HINT_ON=1; aa_events' > $WE/h8; rm -f $WE/bk/aa-off
check "  AA 끄기 파일이 있는 차는 안내하지 않음" '! grep -q "^aa=bt" $WE/hint 2>/dev/null'
rm -f $WE/w/aatime $WE/hint
printf '%s\n' "11-08 02:07:57.610 I/PhoneProjection( 1660): [ WirelessPhoneProjectionService ] isCheckReady ret = false" "11-08 02:07:57.870 D/PhoneProjection( 1660): [ b ] onSppConnect() ret = false" "11-08 02:09:00.000 I/AAProjection(  775): WirelessExplorer : 	Connection status STATUS_SUCCESS" "11-08 02:09:01.000 D/AAProjection(  775): WifiTransport : onConnectedCallback call  onConnected" > $WE/aalog2
wa 'HINT_ON=1; aa_events' > $WE/h9
check "  해소 줄(폰 Wi-Fi 접속 SUCCESS·TCP 연결)을 보면 aa=ok(연결됨)" 'grep -qx "aa=ok" $WE/hint && grep -q "폰 Wi-Fi 접속 SUCCESS" $WE/h9 && grep -q "TCP 연결됨" $WE/h9 && grep -q "무선 안드로이드 오토 연결됨" $WE/h9'
rm -f $WE/w/aatime $WE/hint
printf '%s\n' "11-08 02:07:57.610 I/PhoneProjection( 1660): [ WirelessPhoneProjectionService ] isCheckReady ret = false" "11-08 02:07:57.870 D/PhoneProjection( 1660): [ b ] onSppConnect() ret = false" "11-08 02:09:00.000 D/AAProjection(  775): WirelessExplorer : isWifiApEnable = true, mode = 2" > $WE/aalog2
wa 'HINT_ON=1; aa_events' > $WE/h10
check "  AP 켜짐 true를 보면 안내를 지움(aa 빈 값)" 'grep -qx "aa=" $WE/hint && grep -q "안드로이드 오토 안내 지움" $WE/h10'
wa 'HINT_ON=1; HA=bt; HA_T=$(( $(date +%s) - 601 )); hint_tick' > $WE/h11
check "  10분 지나면 안내를 지움(hint_tick)" 'grep -qx "aa=" $WE/hint && grep -q "10분 지남" $WE/h11'
wa 'HINT_ON=1; HA=bt; HA_T=$(( $(date +%s) - 30 )); hint_tick' > $WE/h12
check "  10분 전에는 그대로" '[ ! -s $WE/h12 ]'
rm -f $WE/w/aatime $WE/hint
printf '%s\n' "11-08 03:00:00.000 D/AAProjection(  775): d : canStartConnection = false" "11-08 03:00:00.100 D/AAProjection(  775): d : getWirelessConnection = false" "11-08 03:00:01.000 I/AAProjection(  775): ConnectionHandler : Connection Error - retry Wireless connection" > $WE/aalog2
wa 'HINT_ON=1; aa_events' > $WE/h13
check "  문 3(canStartConnection·getWirelessConnection false)과 Wi-Fi 세션 재시도도 참거짓만 기록" 'grep -q "연결 시작 막힘(canStartConnection false)" $WE/h13 && grep -q "AA 무선 설정 꺼짐(getWirelessConnection false)" $WE/h13 && grep -q "Wi-Fi 세션 오류로 한 번 다시 시도" $WE/h13'
wa 'HINT_ON=1; aa_sig 0 stop' > /dev/null 2>&1
check "  신호를 끄면 '준비됨'·AA 안내를 지움" 'grep -qx "aa_ready=" $WE/hint && grep -qx "aa=" $WE/hint'
wa 'echo 0 > '$WE'/aaprop; HINT_ON=1; aa_sig' > /dev/null 2>&1
check "  신호가 켜지면 '준비됨' 시각(aa_ready)을 안내 파일에" 'grep -q "^aa_ready=[0-9][0-9]*$" $WE/hint'
rm -f $WE/hint; wa 'aa_sig 0 off' >/dev/null 2>&1
check "  Launch(HINT_ON 없음)는 안내 파일을 쓰지 않음" '[ ! -f $WE/hint ]'
echo 0 > $WE/aaprop; : > $WE/aaoff_m2; wa 'AAOFF='$WE'/aaoff_m2; HINT_ON=1; HA_READY=123; aa_sig' > /dev/null 2>&1; rm -f $WE/aaoff_m2
check "  리뷰 M-2: Launch가 신호를 먼저 0으로 내렸어도 서비스 점검이 남은 '준비됨'을 지움" 'grep -qx "aa_ready=" $WE/hint'
check "  preun이 안내 파일을 지움" 'grep -q "rm -f \$HINT \$HINT.tmp" $PKG/scripts/preun.sh'

# --- 1.7.2 M-8 대신: GPM "준비(1)"가 PP에 닿는지 보는 진단 4줄(bt-aa-autoconnect.md 1-4) ---
# 니로 02:07 실패 부팅·00:08 부팅의 줄 꼴. 이름 자리에 가짜 폰 이름(숫자 섞음)을 넣어 새지 않는지 본다.
rm -f $WE/w/aatime $WE/hint
cat > $WE/aalog2 <<'E'
11-08 02:07:32.870 I/AAProjection(  775): GalReceiverService : PP Service is Running!
11-08 02:07:32.870 I/AAProjection(  775): GalReceiverService : send requestWLDeviceReadyStatusUpdate:  [Galaxy S23 77] 0
11-08 02:07:33.100 D/PhoneProjection( 1660): [ WirelessPhoneProjectionService ] requestWLDeviceReadyStatusUpdate [], Ready (0)
11-08 02:07:57.690 D/AAProjection(  775): a : onBTCMSppStatusChanged, device: 김철수 폰 42 status: 2
11-08 02:09:27.070 I/AAProjection(  789): GalReceiverService : send requestWLDeviceReadyStatusUpdate:  [Galaxy S23 77] 1
11-08 02:09:27.300 D/PhoneProjection( 1660): [ WirelessPhoneProjectionService ] requestWLDeviceReadyStatusUpdate [Galaxy S23 77], Ready (1)
11-08 02:09:27.400 D/PhoneProjection( 1660): [ WirelessPhoneProjectionService ] requestWLDeviceReadyStatusUpdate, Ready = true, mStatusInfo.getReadyStatus (0)
11-08 02:09:27.500 D/PhoneProjection( 1660): [ WirelessPhoneProjectionService ] requestWLDeviceReadyStatusUpdate ready!, type: 2 connectStatus = 0
11-08 02:09:28.000 D/AAProjection(  789): a : onBTCMSppStatusChanged, device: 김철수 폰 42
11-08 02:09:29.000 D/LocalBluetoothManager( 2101): onBTCMSppStatusChanged...device.. AA:BB:CC:DD:EE:FF ...status... 0
11-08 02:09:30.000 D/AAProjection(  789): a : onBTCMSppStatusChanged, device: 김철수 폰 status: 9x
11-08 02:09:31.000 I/AAProjection(  789): GalReceiverService : send requestWLDeviceReadyStatusUpdate:  [Ready] 0
E
printf '#!/bin/sh\ncat %s/aalog2\n' $WE > $WE/bin/logcat; chmod +x $WE/bin/logcat
wa 'HINT_ON=1; aa_events' > $WE/m8a
check "1.7.2 M-8 진단: PP 서비스 시작·GPM 준비 N 보냄·PP 준비 N 받음·GPM SPP 상태 N을 시각과 함께" 'grep -q "안드로이드 오토: 폰 프로젝션 서비스 시작(AA 앱이 확인) (02:07:32.870)" $WE/m8a && grep -q "AA 앱(GPM)이 폰 프로젝션에 준비 0 보냄 (02:07:32.870)" $WE/m8a && grep -q "폰 프로젝션이 준비 0 받음 (02:07:33.100)" $WE/m8a && grep -q "AA 앱(GPM)이 블루투스 SPP 상태 2 받음 (02:07:57.690)" $WE/m8a && grep -q "AA 앱(GPM)이 폰 프로젝션에 준비 1 보냄 (02:09:27.070)" $WE/m8a && grep -q "폰 프로젝션이 준비 1 받음 (02:09:27.300)" $WE/m8a'
check "  상태 숫자가 없거나 숫자가 아니면 '?', 다른 준비 줄·다른 태그(LocalBluetoothManager)는 세지 않음" '[ "$(grep -c "SPP 상태 ? 받음" $WE/m8a)" = 2 ] && [ "$(grep -c "준비 [01] 받음" $WE/m8a)" = 2 ] && [ "$(grep -c "안드로이드 오토: " $WE/m8a)" = 9 ] && grep -q "준비 0 보냄 (02:09:31.000)" $WE/m8a'
check "  이름·주소·이름 속 숫자(23·77·42)가 새지 않고, 안내(hint)는 만들지 않음(기록만)" '! sed -n "s/.*안드로이드 오토: //p" $WE/m8a | grep -q -E "Galaxy|S23|77|김철수|42|AA:BB|9x" && ! grep -q -E "Galaxy|김철수|AA:BB" $WE/m8a && ! grep -q "^aa=bt" $WE/hint 2>/dev/null'
we aa_events > $WE/m8b
check "  같은 줄은 다시 남기지 않음" '[ ! -s $WE/m8b ]'
# logcat 가짜($WE/aalog2를 읽음)는 아래 P-5 시험도 쓰므로 남긴다
rm -f $WE/w/aatime $WE/hint

# --- 1.7.2 P-5: 아이폰이 Wi-Fi에 오지 않음 ---
rm -f $WE/w/aatime $WE/hint $WE/w/cpn
H0=$(date '+%m-%d %H:%M:%S').000
echo "$H0 I/HMG-API (  905): [wireless-carplay-aa] bridge: iAP2 connected comp=4" > $WE/aalog2
wa 'HINT_ON=1; aa_events; n=$(date +%s); echo "IPH=$((n - IPH_AT))"' > $WE/i1
check "1.7.2 P-5: iAP2 연결(구성요소 4) 줄 → 기록 한 줄과 판정 시작(로그 시각 기준)" 'grep -q "카플레이: 아이폰 블루투스 연결(iAP2)" $WE/i1 && grep -q -E "^IPH=[0-2]$" $WE/i1'
echo 0 > $WE/w/cpn
wa 'HINT_ON=1; IPH_AT=$(( $(date +%s) - 61 )); hint_tick' > $WE/i2
check "  60초 동안 기기 연결이 없으면 iph=wifi 안내와 ap.log 한 줄" 'grep -qx "iph=wifi" $WE/hint && grep -q "60초 동안 Wi-Fi에 오지 않음" $WE/i2'
rm -f $WE/hint; wa 'HINT_ON=1; IPH_AT=$(( $(date +%s) - 30 )); hint_tick' > $WE/i3
check "  60초 전에는 안내 안 함" '[ ! -f $WE/hint ] && [ ! -s $WE/i3 ]'
wa 'HINT_ON=1; IPH_AT=$(( $(date +%s) - 61 )); WCONN_AT=$(( $(date +%s) - 20 )); hint_tick' > $WE/i4
check "  iAP2 뒤에 기기 연결(Wi-Fi 인증 끝)이 있으면 안내 안 함" '[ ! -f $WE/hint ] && [ ! -s $WE/i4 ]'
echo 1 > $WE/w/cpn; wa 'HINT_ON=1; IPH_AT=$(( $(date +%s) - 61 )); hint_tick' > $WE/i5; echo 0 > $WE/w/cpn
check "  카플레이가 연결되어 있으면 안내 안 함" '[ ! -f $WE/hint ]'
: > $T/ps; wa 'HINT_ON=1; IPH_AT=$(( $(date +%s) - 61 )); hint_tick' > $WE/i6; echo "  1 root 0 S hostapd $WE/hk.conf" > $T/ps
check "  우리 hostapd가 없으면 안내 안 함" '[ ! -f $WE/hint ]'
wa 'HINT_ON=1; HI=wifi; HI_T=$(( $(date +%s) - 10 )); WCONN_AT=$(date +%s); hint_tick' > $WE/i7
check "  안내 뒤 기기가 연결되면 지움" 'grep -qx "iph=" $WE/hint && grep -q "아이폰이 Wi-Fi에 연결됨" $WE/i7'
wa 'HINT_ON=1; HI=wifi; HI_T=$(( $(date +%s) - 601 )); hint_tick' > $WE/i8
check "  10분 지나면 지움" 'grep -qx "iph=" $WE/hint'
rm -f $WE/w/aatime
printf '%s\n' "$H0 I/HMG-API (  905): [wireless-carplay-aa] bridge: iAP2 connected comp=4" "$H0 I/HMG-API (  905): [wireless-carplay-aa] bridge: iAP2 disconnected comp=4" > $WE/aalog2
wa 'HINT_ON=1; aa_events; echo "IPH=[$IPH_AT]"' > $WE/i9
check "  iAP2가 끊기면 판정을 멈춤" 'grep -q "IPH=\[\]" $WE/i9 && grep -q "아이폰 블루투스 iAP2 끊김" $WE/i9'
rm -f $WE/w/aatime
printf '%s\n' "$H0 I/HMG-API (  905): [wireless-carplay-aa] bridge: iAP2 connected comp=1" "$H0 I/HMG-API (  905): [wireless-carplay-aa] bridge: iAP2 connected comp=4" > $WE/aalog2
wa 'HINT_ON=1; aa_events; echo "IPH=[$IPH_AT]"' > $WE/i11
check "  리뷰 M-3: 유선(USB, 구성요소 1) 카플레이 중에는 블루투스 iAP2가 붙어도 아이폰 Wi-Fi 안내 판정을 하지 않음" 'grep -q "IPH=\[\]" $WE/i11 && grep -q "아이폰 USB(유선) iAP2 연결" $WE/i11'
rm -f $WE/w/aatime
printf '%s\n' "$H0 I/HMG-API (  905): [wireless-carplay-aa] bridge: iAP2 connected comp=1" "$H0 I/HMG-API (  905): [wireless-carplay-aa] bridge: iAP2 disconnected comp=1" "$H0 I/HMG-API (  905): [wireless-carplay-aa] bridge: iAP2 connected comp=4" > $WE/aalog2
wa 'HINT_ON=1; aa_events; n=$(date +%s); echo "IPH=$((n - IPH_AT))"' > $WE/i12
check "  유선이 끊긴 뒤의 블루투스 iAP2는 다시 판정함" 'grep -q -E "^IPH=[0-2]$" $WE/i12'
printf '%s\n' "<6>[  400.0] CFG80211-ERROR) wl_notify_connect_status_ap : ** AP/GO Link up event **" "<4>[  701.372626] ETHER_TYPE_802_1X[wlan0] [RX] : M4 of 4way" > $WE/dmesg; echo "710.50 100.0" > $WE/uptime; rm -f $WE/w/ktime
wa 'UPTIME='$WE'/uptime; wifi_events; n=$(date +%s); echo "AGO=$((n - WCONN_AT))"' > $WE/i10
check "  wifi_events가 기기 연결의 실제 시각을 기억(커널 701초, 부팅 뒤 710초 → 약 9초 전)" 'grep -q -E "^AGO=(9|10)$" $WE/i10'
rm -f $WE/bin/logcat $WE/w/aatime $WE/hint $WE/w/cpn $WE/dmesg $WE/w/ktime; echo boot-A > $WE/bootid
cp $WE/ps.keep2 $T/ps 2>/dev/null || : > $T/ps

# --- 1.7.2 P-3: softap.conf 변경 감시 ---
python3 - $WE/sa1 $WE/sa2 $WE/sa3 <<'E'
import struct,sys
u=lambda s:struct.pack('>H',len(s))+s.encode()
w=lambda p,s2,s4: open(p,'wb').write(struct.pack('>i',3)+u('HotspotName1')+u(s2)+struct.pack('>i',4)+u('hotpass123')+u(s4)+struct.pack('>i',149))
w(sys.argv[1],'OldCarSSID','OldPass12345'); w(sys.argv[2],'NewCarSSIDx','NewPass678901'); w(sys.argv[3],'OldCarSSID','OldPass12345')
open(sys.argv[3],'ab').write(b'\x00\x01')
E
cp $WE/sa1 $WE/softap.conf
mkdir -p $WE/pn0; echo "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode" > $WE/pn0/tcp
echo "  4321 root 0 S hostapd $WE/hk.conf" > $T/ps
wc3() { (SRC=$WE/softap.conf PROCNET=${PN:-$WE/pn0}; export SRC PROCNET; wa 'parse_conf $SRC; write_conf; CONF_SIG=$(conf_sig $SRC); kill() { echo "kill $*" >> '$WE'/kills; }; HINT_ON=1; '"$1"); }
rm -f $WE/kills $WE/hint; wc3 'conf_tick' > $WE/c0
check "1.7.2 P-3: softap.conf가 그대로면 아무것도 안 함" '[ ! -s $WE/c0 ] && [ ! -f $WE/kills ] && grep -qx "ssid=OldCarSSID" $WE/hk.conf'
wc3 'cp '$WE'/sa2 $SRC; conf_tick' > $WE/c1
check "  카플레이 SSID·비밀번호가 바뀌고 연결이 없으면 설정을 다시 쓰고 우리 hostapd만 다시 띄움, 로그에는 길이만" 'grep -qx "ssid=NewCarSSIDx" $WE/hk.conf && grep -qx "wpa_passphrase=NewPass678901" $WE/hk.conf && grep -qx "kill 4321" $WE/kills && grep -q "SSID 길이 10→11, 비밀번호 길이 12→13" $WE/c1 && ! grep -q -e NewCarSSIDx -e NewPass -e OldCarSSID -e OldPass $WE/c1'
cp $WE/sa1 $WE/softap.conf; rm -f $WE/kills $WE/hint
(PN=$PROCNET; wc3 'cp '$WE'/sa2 $SRC; conf_tick; echo "S2=${#S2}"; conf_tick') > $WE/c2
check "  카플레이가 연결되어 있으면 미루고(설정·hostapd 그대로) 상태 화면에 conf=wait, 안내·로그는 한 번" 'grep -qx "ssid=OldCarSSID" $WE/hk.conf && [ ! -f $WE/kills ] && grep -qx "conf=wait" $WE/hint && [ "$(grep -c "연결이 끝나면 핫스팟을 다시 시작" $WE/c2)" = 1 ] && grep -q "S2=10" $WE/c2'
cp $WE/sa1 $WE/softap.conf; rm -f $WE/kills $WE/hint
(PN=$PROCNET; wc3 'cp '$WE'/sa2 $SRC; conf_tick; parse_conf() { echo PARSED; }; conf_tick') > $WE/c2b
check "  리뷰 M-4: 미뤄 둔 같은 변경은 연결 중 다시 읽지 않음(parse_conf 안 부름)" '! grep -q PARSED $WE/c2b'
cp $WE/sa1 $WE/softap.conf; rm -f $WE/kills
(PN=$PROCNET; wc3 'cp '$WE'/sa2 $SRC; conf_tick; PROCNET='$WE'/pn0; conf_tick') > $WE/c3
check "  연결이 끝나면 다음 점검에서 다시 띄우고 안내를 지움" 'grep -qx "ssid=NewCarSSIDx" $WE/hk.conf && grep -qx "kill 4321" $WE/kills && grep -qx "conf=" $WE/hint'
cp $WE/sa1 $WE/softap.conf; rm -f $WE/kills
wc3 'cp '$WE'/sa3 $SRC; conf_tick' > $WE/c4
check "  파일은 바뀌었지만 카플레이 SSID·비밀번호가 같으면 다시 띄우지 않음" '[ ! -f $WE/kills ] && grep -qx "ssid=OldCarSSID" $WE/hk.conf && ! grep -q "핫스팟을" $WE/c4'
cp $WE/sa1 $WE/softap.conf; rm -f $WE/kills
wc3 'printf "\0\0\0\3" > $SRC; conf_tick; echo "S2=$S2 NS=$NS"; conf_tick' > $WE/c5
check "  새 파일을 읽지 못하면 지금 설정 그대로(값 되돌림), 로그 한 번" '[ ! -f $WE/kills ] && grep -qx "ssid=OldCarSSID" $WE/hk.conf && grep -q "S2=OldCarSSID NS=4" $WE/c5 && [ "$(grep -c "읽지 못함" $WE/c5)" = 1 ]'
cp $WE/sa1 $WE/softap.conf
check "  conf_auth: 카플레이 SSID 다음 정수(4)만, 문자열은 내지 않음" '[ "$(SRC=$WE/softap.conf wa "conf_auth \$SRC")" = 4 ] && [ -z "$(SRC=$WE/none wa "conf_auth \$SRC")" ]'
check "  서비스 30초 점검이 conf_tick(up 전)·hint_tick을 부르고, 시작 때 서명을 기억함, 순정 AP 경로는 부르지 않음" 'awk "/^main\(\) \{/,/^}/" $PKG/svc/hotspot.sh | grep -A1 "ap_tick$" | grep -q "conf_tick" && grep -q "CONF_SIG=\$(conf_sig \$SRC)" $PKG/svc/hotspot.sh && [ -z "$(awk "/^stock_ap_mode\(\) \{/,/^}/" $PKG/svc/hotspot.sh | grep -e conf_tick -e hint_tick)" ] && [ "$(awk "/^main\(\) \{/,/^}/" $PKG/svc/hotspot.sh | grep -c "^ *hint_tick$")" = 2 ]'
cp $WE/ps.keep2 $T/ps 2>/dev/null || : > $T/ps

# --- 1.7.2 P-15: ap.log 크기 제한 ---
rm -f $WE/ap.log*
(wa 'APLOG='$WE'/ap.log; APMAX=200; fd_target() { echo "$APLOG"; }; aplog_open; i=0; while [ $i -lt 12 ]; do log "line $i"; i=$((i+1)); done; aplog_rotate; log after') >> $WE/ap.log
check "1.7.2 P-15: ap.log가 APMAX를 넘으면 ap.log.1로 옮기고 비운 뒤 이어서 씀(덧붙이기로 다시 열어 빈칸 없음)" 'grep -q "line 11" $WE/ap.log.1 && ! grep -q "line" $WE/ap.log && grep -q "after" $WE/ap.log && grep -q "ap.log.1로 옮김" $WE/ap.log && [ $(wc -c < $WE/ap.log) -lt 200 ]'
(wa 'APLOG='$WE'/ap.log; APMAX=10; fd_target() { echo "$APLOG"; }; aplog_open; log x2; aplog_rotate; log y2') >> $WE/ap.log
check "  최대 2개(ap.log, ap.log.1)만" '[ ! -f $WE/ap.log.2 ] && grep -q x2 $WE/ap.log.1 && grep -q y2 $WE/ap.log'
rm -f $WE/ap.log*; i=0; while [ $i -lt 20 ]; do echo "old line $i" >> $WE/ap.log; i=$((i+1)); done
wa 'APLOG='$WE'/ap.log; APMAX=10; aplog_open; aplog_rotate' > $WE/apo
check "  표준출력이 ap.log가 아니면(파이프 등) 밀지 않음" '[ ! -f $WE/ap.log.1 ] && grep -q "old line 19" $WE/ap.log'
check "  서비스는 시작 때 aplog_open, 점검마다 logrotate에서 aplog_rotate" 'awk "/^main\(\) \{/,/^}/" $PKG/svc/hotspot.sh | grep -q "^  aplog_open$" && awk "/^logrotate\(\) \{/,/^}/" $PKG/svc/hotspot.sh | grep -q "^  aplog_rotate$"'
check "  리포트 3-log.txt는 ap.log.1과 ap.log를 이어서 넣음" 'grep -q "cat \$APLOG.1 \$APLOG" $PKG/bin/status.sh'

# --- 1.7.2 P-16: killlog(NUL에 기대지 않음) ---
mkdir -p $WE/kp/777 $WE/kp/778; echo "777 (busybox) S 1 1" > $WE/kp/777/stat; echo "778 (sh) S 1 1" > $WE/kp/778/stat
printf '/system/bin/busybox\0uniq\0-c\0-f\0002\0' > $WE/kp/777/cmdline
kl() { rm -f $WE/kills; echo "$1" > $WE/w/log.pid; wa 'PROC='$WE'/kp; kill() { echo "kill $*" >> '$WE'/kills; }; killlog'; }
kl "777 boot-A"
check "1.7.2 P-16: log.pid의 pid가 이번 부팅의 busybox 애플릿(stat 이름 칸)이면 멈춤(cmdline NUL과 상관없음), log.pid 지움" 'grep -qx "kill 777" $WE/kills && [ ! -f $WE/w/log.pid ]'
kl "777 boot-OLD"
check "  지난 부팅의 pid는 멈추지 않음" '[ ! -f $WE/kills ] && [ ! -f $WE/w/log.pid ]'
kl "777"
check "  부팅 id가 없는 예전 형식(1.7.1까지)은 멈추지 않음" '[ ! -f $WE/kills ]'
kl "778 boot-A"
check "  이름이 busybox·uniq·grep이 아니면 멈추지 않음" '[ ! -f $WE/kills ]'
kl "779 boot-A"
check "  없는 pid는 멈추지 않음" '[ ! -f $WE/kills ]'
check "  logstart는 log.pid에 pid와 부팅 id를 함께 남김" 'grep -q "echo \"\$! \$(cat \${BOOT_ID" $PKG/svc/hotspot.sh'

# --- 1.7.2 P-17·P-11 구조 확인 ---
check "1.7.2 P-17: 이번 부팅 첫 시작이면 svc.start와 표시 줄, 같은 부팅이면 '다시 시작'" 'grep -q "^SVC_MARK=\"서비스 시작: 이번 부팅 처음\"" $PKG/svc/hotspot.sh && awk "/^main\(\) \{/,/^}/" $PKG/svc/hotspot.sh | grep -q "log \"\$SVC_MARK" && awk "/^main\(\) \{/,/^}/" $PKG/svc/hotspot.sh | grep -q "서비스 다시 시작(같은 부팅"'
rm -rf $WE

# --- 1f. 1.5 자동 설정: 무선 모드와 니로 지도 (확인된 차에서만, 차주 선택은 덮어쓰지 않음) ---
X=$T/as; mkdir -p $X/bin
cat > $X/bin/hmgapid <<E
#!/bin/sh
echo "hmgapid \$*" >> $X/calls
case "\$1 \$2" in
  "ping "*) [ -f $X/down ] && exit 1; exit 0 ;;
  "engine verify-map") [ -f $X/vm_fail ] && { echo "the map doesn't fit"; exit 1; }; echo "map checked"; exit 0 ;;
  "engine map-car") [ -f $X/mc_fail ] && { echo "error"; exit 1; }
    [ -f $X/mc_nw ] && { echo "not written: HMG-API has a map for this car (kia/dl3/kor/260101)"; exit 0; }
    p=\$(cat $T/product 2>/dev/null || echo DEPEHEV.KOR.0000.V039.001.260902); m=\$(echo \$p | awk -F. '{print tolower(\$1)}'); f=\$(echo \$p | awk -F. '{print \$NF}')
    mkdir -p $X/hd/maps/unknown/\$m/kor/\$f; echo '{"status": "probed"}' > $X/hd/maps/unknown/\$m/kor/\$f/car.json
    echo "map-car: 342 hook point(s) found"; echo "written: unknown/\$m/kor/\$f (status probed): run hmgapid engine verify-map, then restart, for its hooks"; exit 0 ;;
  "engine install") [ -f $X/inst_fail ] && exit 1; [ -f $X/chip_drop ] && { rm -rf $X/sdio; mkdir -p $X/sdio; exit 1; }; mkdir -p $X/hd/mods/wireless-carplay-aa; echo '{}' > $X/hd/mods/wireless-carplay-aa/mod.json; exit 0 ;;
  "engine plan") cat $X/plan; exit 0 ;;
  "engine apply") [ -f $X/apply_fail ] && exit 1; exit 0 ;;
  "engine remove") rm -rf $X/hd/mods/\$3; exit 0 ;;
  "engine status") [ -f $X/status ] && { cat $X/status; exit 4; }; echo "HMG-API owns no files"; exit 0 ;;
esac
exit 0
E
chmod +x $X/bin/hmgapid
PLAN_OK='change   /system/onebin/depehev_kr/featurexml.cfg [wireless-carplay-aa] -> 2a7c   [restart the head unit]
setting  prop/persist.sys.iap2.wifi = t [wireless-carplay-aa]
hook plan: wireless-carplay-aa on'
asreset() { rm -rf $X/hd $X/bk $X/w $X/calls $X/mc_nw $X/vm_fail $X/inst_fail $X/apply_fail $X/down $T/toast; mkdir -p $X/hd/maps/kia/ev6 $X/bk $X/w; mkdir -p $X/hd/public; : > $X/hd/public/wifi-chip; printf '%s\n' "$PLAN_OK" > $X/plan; }
as() { (PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$X/w BK=$X/bk HMGDATA=$X/hd KP_HMG=$T/app/hmgapi SDIO=$X/nosdio sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$X'/bin:'$T'/bin:/usr/bin:/bin:/sbin; setup_hmgapi'); }
NM=$X/hd/maps/kia/niro/kor/260902
asreset; as > $X/out
check "자동 설정: 니로 지도 12개를 넣고 HMG-API 지도 확인 실행" '[ "$(ls $NM | wc -l | tr -d " ")" = 12 ] && grep -qx "hmgapid engine verify-map" $X/calls && [ -f $X/bk/map.ours ]'
check "  넣은 지도가 패키지 것과 같음" 'diff -r $NM $T/app/hmgapi/maps/kia/niro/kor/260902 >/dev/null'
check "  무선 모드 설치 → 계획이 이 모드뿐 → 적용, 우리가 설치한 표시" 'grep -q "hmgapid engine install .*/hmgapi/wireless-carplay-aa.zip" $X/calls && grep -qx "hmgapid engine apply" $X/calls && [ -f $X/bk/mod.ours ] && [ -f $X/bk/mod.tried ]'
check "  끝나면 내비를 재부팅하라는 토스트(RESET 버튼 또는 NEMESIS)" 'grep -q "설정을 마쳤습니다. 내비를 재부팅해 주세요(RESET 버튼 또는 NEMESIS 재부팅)" $T/toast'
rm -f $X/calls $T/toast; as > $X/out
check "  다시 부팅해도 이미 있으면 아무것도 안 함" '! grep -q -E "install|apply|verify-map" $X/calls && [ ! -f $T/toast ]'
rm -rf $X/hd/mods/wireless-carplay-aa; rm -f $X/calls; as > $X/out
check "차주가 모드를 지운 뒤에는 다시 설치하지 않음 (mod.tried)" '! grep -q "engine install" $X/calls'
asreset; mkdir -p $NM; echo official > $NM/car.json; as > $X/out
check "HMG-API에 이 차 지도가 이미 있으면(공식판 등) 덮어쓰지 않음 (다른 차 지도만 넣음)" '[ "$(cat $NM/car.json)" = official ] && ! grep -q verify-map $X/calls && ! grep -q "kia/niro" $X/bk/map.ours 2>/dev/null'
asreset; mkdir -p $X/hd/mods/wireless-carplay-aa; echo '{}' > $X/hd/mods/wireless-carplay-aa/mod.json; : > $X/hd/mods/wireless-carplay-aa/.disabled; as > $X/out
check "모드가 이미 있으면(꺼 둔 것 포함) 설치·적용 안 함" '! grep -q "engine install" $X/calls && ! grep -q "engine apply" $X/calls && [ -f $X/hd/mods/wireless-carplay-aa/.disabled ]'
asreset; printf '%s\n' "$PLAN_OK" "change   /system/app/X.apk [other-mod] -> 1   [restart the app]" > $X/plan; as > $X/out
check "계획에 다른 모드 변경이 있으면 적용하지 않고 앱에서 적용하라고 안내" '! grep -qx "hmgapid engine apply" $X/calls && grep -q "HMG-API 앱에서 변경 사항을 적용" $T/toast && [ -f $X/bk/mod.ours ]'
for extra in "problem  /system/x [wireless-carplay-aa]" "setting  prop/x back to stock" "restore  /system/y (stock)" "nothing changed: 1 problem(s)"; do
  asreset; printf '%s\n' "$PLAN_OK" "$extra" > $X/plan; as > $X/out
  check "  계획에 '${extra%% *}' 줄이 있으면 적용 안 함" '! grep -qx "hmgapid engine apply" $X/calls'
done
asp() { (PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$X/w BK=$X/bk HMGDATA=$X/hd KP_HMG=$T/app/hmgapi SDIO=$X/nosdio PROG=$X/prog P_ON=1 sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$X'/bin:'$T'/bin:/usr/bin:/bin:/sbin; setup_hmgapi'); }
asreset; rm -f $X/prog; asp > $X/out
check "진행 기록: 무선 모드를 설치·적용하면 100% 재부팅 필요" 'grep -qx "pct=100" $X/prog && grep -qx "state=reboot" $X/prog && grep -q "^stage=무선 카플레이 설정을 마쳤습니다" $X/prog'
asreset; rm -f $X/prog; touch $X/inst_fail; asp > $X/out; rm -f $X/inst_fail
check "  설치에 실패하면 100% 실패, 사유는 그 안내 문구" 'grep -qx "state=fail" $X/prog && grep -q "^stage=HMG-API 무선 모드를 설치하지 못했습니다" $X/prog'
# 1.6.1: 차에 우리 것이 아닌, 한국 차를 지원하지 않는 무선 모드(HMG-API 기본 2.1.0, #25 팰리세이드)가 있으면 덮어쓰지 않고 안내
FMJ='{"id": "wireless-carplay-aa", "version": "2.1.0", "system": [{"model": ["CVEV", "NEEV", "NEEV23"], "region": "USA"}, {"model": ["CVEV", "NEEV"], "region": "CAN"}]}'
asreset; rm -f $X/prog; mkdir -p $X/hd/mods/wireless-carplay-aa; echo "$FMJ" > $X/hd/mods/wireless-carplay-aa/mod.json; asp > $X/out
check "1.6.1: 한국 차를 지원하지 않는 다른 무선 모드가 있으면 설치·적용하지 않고 덮어쓰지 않음" '! grep -q "engine install" $X/calls 2>/dev/null && ! grep -q "engine apply" $X/calls 2>/dev/null && [ "$(cat $X/hd/mods/wireless-carplay-aa/mod.json)" = "$FMJ" ]'
check "  토스트는 띄우지 않고(소유자 결정) 진행 화면은 그 안내로 실패, 표시 기록 파일 없음" '[ ! -f $T/toast ] && grep -qx "state=fail" $X/prog && grep -q "^stage=차에 있는 HMG-API 무선 모드가 한국 차용이 아닙니다" $X/prog && [ ! -f $X/bk/mod.foreign.told ]'
rm -f $T/toast $X/prog; asp > $X/out
check "  두 번째 부팅에도 토스트 없이 진행 화면 안내만" '[ ! -f $T/toast ] && grep -q "^stage=차에 있는 HMG-API 무선 모드가 한국 차용이 아닙니다" $X/prog'
mf() { (HOTSPOT_LIB=1 BB=$T/bin/bb W=$X/w BK=$X/bk HMGDATA=$X/hd sh -c '. '$T'/app/svc/hotspot.sh; mod_foreign'); }
: > $X/bk/mod.ours
check "  우리가 넣은 모드(mod.ours)는 다른 판으로 보지 않음" '! mf'
rm -f $X/bk/mod.ours; printf '{"system":[{"region":"KOR","features":["hmgapi.wifi"]}]}\n' > $X/hd/mods/wireless-carplay-aa/mod.json
check "  한국 차 항목(\"region\":\"KOR\", 공백 없이)이 있으면 다른 판으로 보지 않음" '! mf'
unzip -p $T/app/hmgapi/wireless-carplay-aa.zip mod.json > $X/hd/mods/wireless-carplay-aa/mod.json
check "  패키지에 든 우리 모드의 mod.json은 다른 판으로 보지 않음" '! mf'
rm -rf $X/hd/mods
check "  모드가 없으면 아님" '! mf'
mkdir -p $X/hd/mods/wireless-carplay-aa
printf '{\n\t"system": [{\n\t\t"region":\t[ "USA", "KOR" ]\n\t}]\n}\n' > $X/hd/mods/wireless-carplay-aa/mod.json
check "  한국 차 항목이 배열·탭 형식이어도 다른 판으로 보지 않음" '! mf'
: > $X/hd/mods/wireless-carplay-aa/mod.json
check "  빈 mod.json은 다른 판으로 보지 않음(판단 불가)" '! mf'
rm -rf $X/hd/mods
# 모드가 없으면 남은 기록(mod.ours)을 지움: 나중에 넣은 다른 판을 우리 것으로 보지 않게. mod.tried는 남김
asreset; : > $X/bk/mod.ours; : > $X/bk/mod.tried; as > $X/out
check "  모드가 없으면 남은 mod.ours를 지우고 mod.tried는 남김(다시 설치 안 함)" '[ ! -f $X/bk/mod.ours ] && [ -f $X/bk/mod.tried ] && ! grep -q "engine install" $X/calls 2>/dev/null'
# 차주가 다른 판을 지운 뒤 다음 부팅에는 우리 모드를 설치
asreset; rm -f $X/prog; mkdir -p $X/hd/mods/wireless-carplay-aa; echo "$FMJ" > $X/hd/mods/wireless-carplay-aa/mod.json; asp > $X/out; rm -rf $X/hd/mods; rm -f $T/toast; asp > $X/out
check "  다른 판을 지운 뒤 다음 부팅에는 한국 차용 모드를 설치·적용" 'grep -q "engine install" $X/calls && grep -qx "hmgapid engine apply" $X/calls && [ -f $X/bk/mod.ours ]'
asreset; rm -f $X/prog; mkdir -p $X/hd/maps/kia/niro/kor/260902; echo '{}' > $X/hd/maps/kia/niro/kor/260902/car.json; mkdir -p $X/hd/mods/wireless-carplay-aa; echo '{"system": [{"region": "KOR"}]}' > $X/hd/mods/wireless-carplay-aa/mod.json; asp > $X/out
check "  무선 모드(한국 차 지원)가 있지만 적용되지 않았으면 그 사유(앱에서 켜고 적용)로 실패" 'grep -qx "state=fail" $X/prog && grep -q "^stage=HMG-API 무선 모드가 있지만 꺼져 있거나 적용되지 않았습니다" $X/prog'
asreset; rm -f $X/prog; echo TESTX.KOR.0000.V001.001.250101 > $T/product; echo "  77 1010 hostapd /data/misc/wifi/hostapd.conf" > $T/ps; asp > $X/out; rm -f $T/product $T/ps
check "  순정 핫스팟이 켜져 있어 건너뛰면 그 사유로 표시" 'grep -qx "state=fail" $X/prog && grep -q "^stage=순정 핫스팟이 켜져 있어" $X/prog'
asreset; rm -f $X/prog; echo TESTX.USA.0000.V001.001.250101 > $T/product; asp > $X/out; rm -f $T/product
check "  지원하지 않는 차(해외)는 바로 실패로 끝남(진행 중으로 남지 않음)" 'grep -qx "state=fail" $X/prog && grep -q "^stage=지원하지 않는 차" $X/prog'
asreset; touch $X/inst_fail; as > $X/out
check "모드 설치 실패 → 안내, 우리 것 표시 없음, 적용 안 함" 'grep -q "설치하지 못했습니다" $T/toast && [ ! -f $X/bk/mod.ours ] && ! grep -q "engine apply" $X/calls'
rm -f $X/inst_fail $X/calls; as > $X/out
check "  일시적인 설치 실패는 다음 부팅에 다시 함 (mod.tried 안 남김)" 'grep -q "engine install" $X/calls && [ -f $X/bk/mod.ours ]'
# 1.5.7: 이미 있는 우리 모드(2.1.0)를 패키지의 새 판(2.1.1, 계기판 안내 수정)으로 바꾸기
KMJ210='{"id": "wireless-carplay-aa", "version": "2.1.0", "system": [{"model": ["DEPEHEV"], "region": "KOR", "firmware": "260902"}]}'
museed() { asreset; rm -f $X/prog; mkdir -p $X/hd/mods/wireless-carplay-aa; echo "$KMJ210" > $X/hd/mods/wireless-carplay-aa/mod.json; : > $X/bk/mod.ours; : > $X/bk/mod.tried; echo "nothing changed" > $X/plan; }
MV=$(sed -n "s/^MOD_VER=//p" $PKG/svc/hotspot.sh)
check "1.5.7: 패키지의 모드 버전(MOD_VER)이 zip의 mod.json과 같음" '[ "$(unzip -p $PKG/hmgapi/wireless-carplay-aa.zip mod.json | sed -n "s/.*\"version\": *\"\([^\"]*\)\".*/\1/p" | head -1)" = "$MV" ]'
check "  mod_ver: mod.json의 version을 셸만으로 읽음" '[ "$(museed; HOTSPOT_LIB=1 BB=$T/bin/bb W=$X/w BK=$X/bk HMGDATA=$X/hd sh -c ". $T/app/svc/hotspot.sh; mod_ver")" = 2.1.0 ]'
vl() { (HOTSPOT_LIB=1 BB=$T/bin/bb W=$X/w sh -c ". $T/app/svc/hotspot.sh; ver_lt $1 $2"); }
check "  ver_lt: 2.1.0<2.1.1, 1.9.9<2.1.1, 2.1<2.1.1, 2.1.1<2.1.10 / 같거나 높거나 숫자 아니면 아님" 'vl 2.1.0 2.1.1 && vl 1.9.9 2.1.1 && vl 2.1 2.1.1 && vl 2.1.1 2.1.10 && ! vl 2.1.1 2.1.1 && ! vl 2.2.0 2.1.1 && ! vl x 2.1.1 && ! vl "" 2.1.1'
museed; asp > $X/out
check "1.5.7: 우리가 넣은 2.1.0이 있으면 새 판으로 설치, 적용은 안 함(hooks.jar만: nothing changed), 재부팅 안내" 'grep -q "hmgapid engine install .*/hmgapi/wireless-carplay-aa.zip" $X/calls && ! grep -qx "hmgapid engine apply" $X/calls && [ "$(cat $X/bk/mod.upd)" = "$MV 1" ] && grep -qx "state=reboot" $X/prog && grep -q "^stage=무선 모드를 새 판($MV)으로 바꿨습니다" $X/prog && grep -q "새 판($MV)으로 바꿨습니다. 내비를 재부팅" $T/toast && grep -q "업데이트함: 2.1.0 →" $X/out'
# 1.7.1: 알림 기록(토스트 대신): busybox 차는 최근 5줄만, 644, 임시 파일 안 남음
NT=$X/nt; rm -f $NT*; for i in 1 2 3 4 5 6 7; do (PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 NOTICE=$NT BB=$T/bin/bb W=$X/w sh -c '. '$T'/app/svc/hotspot.sh; notice "Korea Projection: 안내 '$i'"') > /dev/null; done
check "1.7.1 알림 기록: 최근 5줄(안내 3~7), \"<초> <부팅 id> <문구>\", 644, 임시 파일 없음" '[ "$(wc -l < $NT | tr -d " ")" = 5 ] && head -1 $NT | grep -q "^[0-9][0-9]* [^ ]* 안내 3$" && tail -1 $NT | grep -q " 안내 7$" && [ "$(stat -f %Lp $NT)" = 644 ] && [ -z "$(ls $X | grep "^nt\.")" ]'
# 1.7.1: 새 판으로 바꾸기 전(부팅 약 2분 안)에 만든 리포트·상태 파일이 "업데이트 대기 중"을 보임(mod_pending)
mpd() { (PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$X/w BK=$X/bk HMGDATA=$X/hd sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$X'/bin:'$T'/bin:/usr/bin:/bin:/sbin; mod_pending && echo yes || echo no'); }
museed; check "1.7.1 모드 업데이트 대기: 우리가 넣은 이전 판이면 yes" '[ "$(mpd)" = yes ]'
museed; : > $X/bk/mod.pin; check "  되돌리기로 고정(mod.pin)했으면 no" '[ "$(mpd)" = no ]'
museed; echo "$MV 3" > $X/bk/mod.upd; check "  같은 판을 이미 3번 시도했으면 no" '[ "$(mpd)" = no ]'
museed; rm -f $X/bk/mod.ours; check "  우리가 넣은 모드가 아니면 no" '[ "$(mpd)" = no ]'
museed; sed "s/2.1.0/$MV/" $X/hd/mods/wireless-carplay-aa/mod.json > $X/mj && mv $X/mj $X/hd/mods/wireless-carplay-aa/mod.json; check "  이미 새 판이면 no" '[ "$(mpd)" = no ]'
check "  리포트에 차·패키지 판과 대기 안내(1.7.2 P-18: 할 일), 상태 파일에 modver·mod_pending" 'grep -q "무선 모드 판: 차 \$(mod_ver) / 패키지 \$MOD_VER" $PKG/bin/status.sh && grep -q "할 일: 내비를 재부팅하고 3분 기다린 뒤 한 번 더 재부팅해 주세요" $PKG/bin/status.sh && grep -q "새 판(\$MOD_VER)으로 바뀌니" $PKG/bin/status.sh && grep -q "echo \"mod_pending=\$(yesno mod_pending)\"" $PKG/bin/status.sh'
# 1.7.2(P-18): fix_perms의 120초 대기를 부팅 뒤 시간(/proc/uptime)으로 센다(#60 K3: 서비스가 다시 시작되면 처음부터 기다렸음)
FW=$X/fw; mkdir -p $FW/bin
printf '#!/bin/sh\necho "$1" >> %s/sleeps\n[ -f %s/prog ] && [ ! -f %s/prog.during ] && cp %s/prog %s/prog.during\nexit 0\n' $FW $X $FW $X $FW > $FW/bin/sleep; chmod +x $FW/bin/sleep
fw() { rm -f $FW/sleeps $FW/prog.during $X/prog; (PATH=$FW/bin:$X/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$X/w BK=$X/bk HMGDATA=$X/hd KP_HMG=$T/app/hmgapi SDIO=$X/nosdio PROG=$X/prog FIX_DELAY=120 UPTIME=$FW/uptime BOOT_ID=$FW/bootid PERMS=$FW/perms MOUNTS=$FW/mounts sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$FW'/bin:'$X'/bin:'$T'/bin:/usr/bin:/bin:/sbin; fix_perms') > $X/out 2>&1; }
# 대기(10초씩)가 끝난 뒤의 sleep은 세지 않도록, 대기 sleep은 앞에서부터 이어지는 10 이하 값의 합으로 본다
fwsum() { awk 'BEGIN { s = 0 } { s += $1 } END { print s }' $FW/sleeps 2>/dev/null; }
echo bootA > $FW/bootid
fwss() { echo "$1" > $X/w/svc.start; }
museed; fwss "bootA 27"; echo "77.37 80.00" > $FW/uptime; fw
check "1.7.2 P-18: 서비스가 이번 부팅 27초에 처음 시작했고 지금 77초면(다시 시작) 남은 70초만 기다림" '[ "$(fwsum)" = 70 ] && grep -q "첫 시작 뒤 50초 지남, 남은 대기 70초" $X/out'
check "  모드를 새 판으로 바꿀 차는 대기 중 상태 화면에 할 일(재부팅 안내가 나오면 재부팅)을 보이고, 끝나면 재부팅 안내" 'grep -qx "state=run" $FW/prog.during && grep -q "^stage=무선 모드를 새 판으로 바꾸기 전에 기다리는 중입니다(약 70초). 재부팅 안내가 나오면 내비를 재부팅해 주세요." $FW/prog.during && grep -qx "state=reboot" $X/prog && grep -q "업데이트함: 2.1.0 →" $X/out'
museed; fwss "bootA 27"; echo "500.12 900.00" > $FW/uptime; fw
check "  이미 120초가 지났으면(서비스가 다시 시작됨) 기다리지 않고 바로 함" '[ ! -s $FW/sleeps ] && grep -q "업데이트함: 2.1.0 →" $X/out && grep -q "남은 대기 0초" $X/out'
museed; fwss "bootA 27"; echo "27.5 1.0" > $FW/uptime; fw
check "  보통 부팅(첫 시작 직후)은 예전처럼 120초를 다 기다림(리뷰 M1)" '[ "$(fwsum)" = 120 ]'
museed; fwss "bootOld 27"; echo "500.0 1.0" > $FW/uptime; fw
check "  첫 시작 기록이 지난 부팅 것이면 지금부터 120초" '[ "$(fwsum)" = 120 ]'
museed; fwss "bootA 27"; rm -f $FW/uptime; fw
check "  uptime을 못 읽으면 예전처럼 120초를 다 기다림" '[ "$(fwsum)" = 120 ] && ! grep -q "남은 대기" $X/out'
museed; fwss "bootA 27"; echo "garbage" > $FW/uptime; fw
check "  uptime이 숫자가 아니어도 120초를 다 기다림(멈추지 않음)" '[ "$(fwsum)" = 120 ]'
asreset; fwss "bootA 27"; echo "57.0 1.0" > $FW/uptime; fw
check "  새로 설치하는 차(모드 업데이트 아님)는 HMG-API 대기 문구와 남은 초" 'grep -q "^stage=HMG-API가 준비되기를 기다리는 중입니다(약 90초)" $FW/prog.during && [ "$(fwsum)" = 90 ]'
museed; sed -i '' 's/"2.1.0"/"2.2.0"/' $X/hd/mods/wireless-carplay-aa/mod.json; asp > $X/out
check "1.7.1: 우리가 넣은 2.2.0(1.7.0)이 있으면 패키지의 새 판(\$MV)으로 설치, 재부팅 안내" 'grep -q "hmgapid engine install .*/hmgapi/wireless-carplay-aa.zip" $X/calls && grep -q "업데이트함: 2.2.0 → $MV" $X/out && grep -qx "state=reboot" $X/prog'
# 1.7.2: 1.7.1 사용자(모드 2.3.0)도 패키지의 새 판으로 바뀐다
museed; sed -i '' 's/"2.1.0"/"2.3.0"/' $X/hd/mods/wireless-carplay-aa/mod.json; asp > $X/out
check "1.7.2: 우리가 넣은 2.3.0(1.7.1)이 있으면 패키지의 새 판(\$MV)으로 설치, 재부팅 안내" 'vl 2.3.0 $MV && grep -q "hmgapid engine install .*/hmgapi/wireless-carplay-aa.zip" $X/calls && grep -q "업데이트함: 2.3.0 → $MV" $X/out && grep -qx "state=reboot" $X/prog'
museed; echo "$MV 3" > $X/bk/mod.upd; asp > $X/out
check "  같은 버전을 이미 3번 시도했으면(mod.upd) 다시 하지 않음" '! grep -q "engine install" $X/calls'
museed; echo "$MV 1" > $X/bk/mod.upd; asp > $X/out
check "  1번 실패한 기록이면 다시 시도하고 횟수를 올림" 'grep -q "engine install" $X/calls && [ "$(cat $X/bk/mod.upd)" = "$MV 2" ]'
museed; echo "2.0.9 3" > $X/bk/mod.upd; asp > $X/out
check "  다른 버전의 시도 기록은 새로 셈" 'grep -q "engine install" $X/calls && [ "$(cat $X/bk/mod.upd)" = "$MV 1" ]'
museed; : > $X/bk/mod.pin; asp > $X/out
check "  되돌리기로 고정했으면(mod.pin) 바꾸지 않음" '! grep -q "engine install" $X/calls && [ ! -f $X/bk/mod.upd ]'
museed; rm -f $X/bk/mod.ours; asp > $X/out
check "  우리가 넣은 것이 아니면(mod.ours 없음) 바꾸지 않음" '! grep -q "engine install" $X/calls'
museed; sed "s/2.1.0/$MV/" $X/hd/mods/wireless-carplay-aa/mod.json > $X/mj && mv $X/mj $X/hd/mods/wireless-carplay-aa/mod.json; asp > $X/out
check "  이미 같은 버전이면 아무것도 안 함" '! grep -q -E "engine (install|apply)" $X/calls && [ ! -f $X/bk/mod.upd ]'
museed; sed "s/2.1.0/9.0.0/" $X/hd/mods/wireless-carplay-aa/mod.json > $X/mj && mv $X/mj $X/hd/mods/wireless-carplay-aa/mod.json; asp > $X/out
check "  차에 더 새 판이 있으면 내리지 않음" '! grep -q "engine install" $X/calls'
museed; touch $X/inst_fail; asp > $X/out
check "  설치 실패 1번째: 이전 판 그대로, 실패 안내 없이 다음 부팅에 다시(횟수 1)" '! grep -q "바꾸지 못했습니다" $T/toast 2>/dev/null && grep -q "2.1.0" $X/hd/mods/wireless-carplay-aa/mod.json && [ "$(cat $X/bk/mod.upd)" = "$MV 1" ] && grep -q "업데이트 실패(1/3)" $X/out'
rm -f $X/calls $T/toast $X/prog; asp > $X/out; rm -f $X/calls $T/toast $X/prog; asp > $X/out; rm -f $X/inst_fail
check "  3번째도 실패하면 그때 한 번 안내, 진행 기록 실패, 적용 안 함" 'grep -q "새 판으로 바꾸지 못했습니다. 카플레이는 이전 판으로 계속 됩니다" $T/toast && grep -qx "state=fail" $X/prog && ! grep -q "engine apply" $X/calls && [ "$(cat $X/bk/mod.upd)" = "$MV 3" ]'
rm -f $X/calls $T/toast; asp > $X/out
check "  그 뒤로는 이 버전을 다시 시도하지 않음" '! grep -q "engine install" $X/calls && [ ! -f $T/toast ]'
# 1.5.7 니로에서 실제로 나온 계획(2026-11-07 21:36): "same" 줄뿐, "nothing changed" 줄은 없음
PLAN_SAME='same     /system/etc/permissions/com.hkmc.software.connectivity.androidauto_wireless.xml [wireless-carplay-aa]
same     /system/etc/permissions/com.hkmc.software.connectivity.carplay_wireless.xml [wireless-carplay-aa]
same     /system/lib/libleafiaaac.so [wireless-carplay-aa]
same     /system/onebin/depehev_kr/featurexml.cfg [wireless-carplay-aa]
same     setting prop/persist.iap2.iden.wireless = t [wireless-carplay-aa]
same     setting prop/persist.ium.support = carplay [wireless-carplay-aa]
same     setting prop/persist.sys.iap2.wifi = t [wireless-carplay-aa]'
museed; printf '%s\n' "$PLAN_SAME" > $X/plan; asp > $X/out
check "  니로에서 나온 계획('same' 줄뿐)이면 적용할 것이 없어 앱 적용 안내 없이 재부팅만 안내" '! grep -qx "hmgapid engine apply" $X/calls && ! grep -q "앱에서 변경 사항을 적용" $T/toast && grep -qx "state=reboot" $X/prog && ! grep -q "차주에게 맡김" $X/out'
museed; : > $X/plan; asp > $X/out
check "  계획이 비어 있으면(엔진이 답하지 않음) 확인할 수 없어 앱에서 보라고 안내" 'grep -q "앱에서 변경 사항을 적용" $T/toast'
museed; printf '%s\n' "$PLAN_OK" > $X/plan; asp > $X/out
check "  새 판에 적용할 변경이 있으면 운행 중일 수 있어 적용하지 않고, 차를 세운 뒤 앱에서 적용하라고 안내" '! grep -qx "hmgapid engine apply" $X/calls && grep -q "차를 세운 뒤 HMG-API 앱에서 변경 사항을 적용" $T/toast && grep -qx "state=fail" $X/prog'
museed; printf '%s\n' "nothing changed" "problem  /system/x [wireless-carplay-aa]" > $X/plan; asp > $X/out
check "  'nothing changed'여도 problem 줄이 있으면 앱에서 확인하라고 안내" '! grep -qx "hmgapid engine apply" $X/calls && grep -q "앱에서 변경 사항을 적용" $T/toast'
museed; rm -rf $X/hd/mods; asp > $X/out
check "  모드가 없으면(차주가 지움) 업데이트 경로는 아무것도 안 함" '! grep -q "engine install" $X/calls'
if [ -d $B/usb-modrollback ]; then
# 되돌리기 USB(usb-modrollback, 1.7.2 R-4): 1.7.2의 2.3.1을 1.7.1의 2.3.0으로 --force 설치하고 고정. 토스트 없이 RESULT.txt·알림 기록
RB=$T/rb; RBS=$B/usb-modrollback/NEMESIS.sh; RBZ=$B/usb-modrollback/kp-rollback/wireless-carplay-aa-2.3.0.zip
KMJ231='{"id": "wireless-carplay-aa", "version": "2.3.1", "system": [{"model": ["DEPEHEV"], "region": "KOR", "firmware": "260902"}]}'
rbreset() { rm -rf $RB; mkdir -p $RB/usb/kp-rollback $RB/hd/mods/wireless-carplay-aa $RB/bk $RB/d $RB/kw $RB/proc $RB/w; : > $RB/bk/mod.ours; echo boot1 > $RB/bootid; cp $RBZ $RB/usb/kp-rollback/; echo "$KMJ231" > $RB/hd/mods/wireless-carplay-aa/mod.json; rm -f $X/calls $T/toast $X/inst_fail $X/apply_fail; printf '%s\n' "$PLAN_OK" > $X/plan; echo "/dev/block/sda1 $RB/usb vfat rw 0 0" > $RB/mounts; }
# 스크립트 첫 줄의 차 PATH를 테스트 PATH(가짜 hmgapid·am)로 바꿔 돌린다(fixpath와 같은 방식)
rb() { sed "s#^export PATH=.*#export PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin#" $RBS > $RB/run.sh; (KP_FROM_DATA=1 BB=$T/bin/bb U=$RB/usb D=$RB/d HMGDATA=$RB/hd BK=$RB/bk MOUNTS=$RB/mounts KW=$RB/kw PROC=$RB/proc BOOT_ID=$RB/bootid NOTICE=$RB/notice sh $RB/run.sh) > $RB/out 2>&1; }
# 결과: USB의 RESULT.txt와 상태 화면 알림 기록 둘 다에 있는가
rbres() { grep -q "$1" $RB/usb/kp-rollback/RESULT.txt && grep -q "^[0-9][0-9]* boot1 되돌리기 USB: .*$1" $RB/notice; }
# 1.7.2 패키지의 mod_update(부팅 2분 뒤)를 이 차 상태로 돌린다
rbmu() { (PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$RB/w BK=$RB/bk HMGDATA=$RB/hd KP_HMG=$T/app/hmgapi NOTICE=$RB/pkgnotice sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$X'/bin:'$T'/bin:/usr/bin:/bin:/sbin; mod_update; echo "rc=$?"') > $RB/mu.out 2>&1; }
check "되돌리기 USB: 스크립트 앞에 umask 077, 셸 문법, 토스트(am broadcast) 없음" 'grep -qx "umask 077" $RBS && sh -n $RBS && ! grep -q -i -e "am broadcast" -e "TOAST" $RBS'
check "  USB의 되돌리기 zip이 1.7.1 패키지 모드(2.3.0)의 md5와 같고, 2.1.0 zip은 USB에 없음" '[ "$(md5sum < $RBZ | cut -c1-32)" = "$(sed -n "s/^OLD_MD5=//p" $RBS)" ] && [ "$(sed -n "s/^OLD_MD5=//p" $RBS)" = 57305323c4aceffe2da85a5af8f9348a ] && unzip -p $RBZ mod.json | grep -q "\"version\": \"2.3.0\"" && [ ! -f $B/usb-modrollback/kp-rollback/wireless-carplay-aa-2.1.0.zip ]'
check "  되돌리는 판(FROM_VERS)에 패키지의 MOD_VER가 들어 있음" 'case "$(sed -n "s/^FROM_VERS=//p" $RBS)" in *" $(sed -n "s/^MOD_VER=//p" $PKG/svc/hotspot.sh) "*) true ;; *) false ;; esac'
rbreset; rb
check "  2.3.1 → --force로 2.3.0 설치, 고정(mod.pin), 적용, RESULT.txt·상태 화면에 재부팅 안내, 토스트 없음, 기록을 USB에" 'grep -q "hmgapid engine install .*wireless-carplay-aa-2.3.0.zip --force" $X/calls && grep -qx "hmgapid engine apply" $X/calls && [ -f $RB/bk/mod.pin ] && rbres "2.3.0으로 되돌리고 고정했습니다. 내비를 재부팅" && [ ! -f $T/toast ] && [ -f $RB/usb/kp-rollback/log/rollback.log ] && [ "$(stat -f %Lp $RB/notice)" = 644 ]'
# 차 흐름: 2.3.1 → (USB) 2.3.0 → 고정 → 재부팅(1.7.2 mod_update가 다시 바꾸지 않음) → (USB UNPIN) → 재부팅 → 2.3.1
echo "$KMJ231" | sed 's/2\.3\.1/2.3.0/' > $RB/hd/mods/wireless-carplay-aa/mod.json; rm -f $X/calls; rbmu
check "  흐름: 고정된 2.3.0이면 재부팅 뒤 1.7.2 mod_update가 2.3.1로 다시 바꾸지 않음" 'grep -qx "rc=1" $RB/mu.out && ! grep -q "engine install" $X/calls 2>/dev/null'
: > $RB/usb/kp-rollback/UNPIN; echo "2.3.1 3" > $RB/bk/mod.upd; rm -f $RB/usb/kp-rollback/RESULT.txt; rb; rm -f $RB/usb/kp-rollback/UNPIN
check "  흐름: UNPIN이면 고정만 풂(mod.pin·mod.upd 지움), 설치 안 함, 결과 안내" '[ ! -f $RB/bk/mod.pin ] && [ ! -f $RB/bk/mod.upd ] && ! grep -q "engine install" $X/calls 2>/dev/null && rbres "고정을 풀었습니다"'
rm -f $X/calls; rbmu
check "  흐름: 고정을 푼 뒤 재부팅하면 1.7.2 mod_update가 패키지의 판을 설치(시도 1)" 'grep -q "hmgapid engine install .*/hmgapi/wireless-carplay-aa.zip" $X/calls && [ "$(cat $RB/bk/mod.upd)" = "$(sed -n "s/^MOD_VER=//p" $PKG/svc/hotspot.sh) 1" ]'
for i in 1 2 3 4 5 6; do echo "1 boot0 old$i" >> $RB/notice; done; rb
check "  알림 기록은 최근 5줄만 남고(1.7.2 notice와 같게) 임시 파일이 남지 않음" '[ "$(wc -l < $RB/notice | tr -d " ")" = 5 ] && ! grep -q old2 $RB/notice && grep -q old6 $RB/notice && ! ls $RB/notice.rb.* >/dev/null 2>&1'
rbreset; echo "x" >> $RB/usb/kp-rollback/wireless-carplay-aa-2.3.0.zip; rb
check "  zip이 맞지 않으면 아무것도 바꾸지 않음" '! grep -q "engine install" $X/calls 2>/dev/null && [ ! -f $RB/bk/mod.pin ] && rbres "맞지 않습니다"'
rbreset; touch $X/inst_fail; rb; rm -f $X/inst_fail
check "  엔진이 거부하면 고정하지 않고 지금 판 그대로라고 안내" '[ ! -f $RB/bk/mod.pin ] && ! grep -q "engine apply" $X/calls && rbres "지금 판(2.3.1) 그대로"'
rbreset; echo '{"id": "wireless-carplay-aa", "version": "2.2.0", "system": [{"region": "USA"}]}' > $RB/hd/mods/wireless-carplay-aa/mod.json; rb
check "  한국 차 항목이 없는 다른 판은 덮어쓰지 않음" '! grep -q "engine install" $X/calls 2>/dev/null && rbres "Korea Projection 것이 아닙니다"'
rbreset; sed -i.bak 's/2\.3\.1/2.3.0/' $RB/hd/mods/wireless-carplay-aa/mod.json; rb
check "  이미 2.3.0(1.7.1 그대로)이면 설치 없이 고정만" '! grep -q "engine install" $X/calls 2>/dev/null && [ -f $RB/bk/mod.pin ] && rbres "이미 2.3.0입니다"'
for v in 2.1.0 2.1.1 2.4.1 2.5.0 '2.3.1-x"name'; do
  rbreset; echo "$KMJ231" | sed "s/2\.3\.1/$v/" > $RB/hd/mods/wireless-carplay-aa/mod.json; rb
  check "  되돌리는 판이 아닌 $v는 바꾸지 않음(옛 판을 2.3.0으로 올리거나 다음 판을 내리지 않음)" '! grep -q "engine install" $X/calls 2>/dev/null && [ ! -f $RB/bk/mod.pin ] && rbres "이 USB가 되돌리는 판(1.7.2의 2.4.0, 시험판 2.3.1~2.3.4)이 아닙니다" && ! grep -q "name" $RB/usb/kp-rollback/RESULT.txt $RB/notice'
done
# 1.7.2 시험판 차(무선 모드 2.3.2)도 2.3.0으로 되돌린다
rbreset; echo "$KMJ231" | sed 's/2\.3\.1/2.3.2/' > $RB/hd/mods/wireless-carplay-aa/mod.json; rb
check "  시험판 2.3.2 → --force로 2.3.0 설치, 고정" 'grep -q "hmgapid engine install .*wireless-carplay-aa-2.3.0.zip --force" $X/calls && [ -f $RB/bk/mod.pin ] && rbres "2.3.0으로 되돌리고 고정했습니다"'
# 1.7.2 시험판 3(무선 모드 2.3.3)도 2.3.0으로 되돌린다
rbreset; echo "$KMJ231" | sed 's/2\.3\.1/2.3.3/' > $RB/hd/mods/wireless-carplay-aa/mod.json; rb
check "  시험판 2.3.3 → --force로 2.3.0 설치, 고정" 'grep -q "hmgapid engine install .*wireless-carplay-aa-2.3.0.zip --force" $X/calls && [ -f $RB/bk/mod.pin ] && rbres "2.3.0으로 되돌리고 고정했습니다"'
# 1.7.2 베타 2(무선 모드 2.3.4)도 2.3.0으로 되돌린다
rbreset; echo "$KMJ231" | sed 's/2\.3\.1/2.3.4/' > $RB/hd/mods/wireless-carplay-aa/mod.json; rb
check "  베타 2(2.3.4) → --force로 2.3.0 설치, 고정" 'grep -q "hmgapid engine install .*wireless-carplay-aa-2.3.0.zip --force" $X/calls && [ -f $RB/bk/mod.pin ] && rbres "2.3.0으로 되돌리고 고정했습니다"'
# 1.7.2 정식(무선 모드 2.4.0)도 2.3.0으로 되돌린다
rbreset; echo "$KMJ231" | sed 's/2\.3\.1/2.4.0/' > $RB/hd/mods/wireless-carplay-aa/mod.json; rb
check "  1.7.2 정식(2.4.0) → --force로 2.3.0 설치, 고정" 'grep -q "hmgapid engine install .*wireless-carplay-aa-2.3.0.zip --force" $X/calls && [ -f $RB/bk/mod.pin ] && rbres "2.3.0으로 되돌리고 고정했습니다"'
rbreset; : > $RB/bk/mod.pin; echo 2.3.1 > $RB/bk/mod.upd; : > $RB/usb/kp-rollback/UNPIN; rb
check "  UNPIN 파일이 있으면 고정만 풂(mod.pin·mod.upd 지움), 설치 안 함" '[ ! -f $RB/bk/mod.pin ] && [ ! -f $RB/bk/mod.upd ] && ! grep -q "engine install" $X/calls 2>/dev/null'
rbreset; touch $X/down; rb; rm -f $X/down
check "  HMG-API가 응답하지 않으면 아무것도 바꾸지 않음" '! grep -q "engine install" $X/calls && [ ! -f $RB/bk/mod.pin ] && rbres "HMG-API가 응답하지 않아"'
rbreset; printf '%s\n' "$PLAN_SAME" > $X/plan; rb
check "  계획이 'same' 줄뿐이면 적용 없이 재부팅 안내" '! grep -qx "hmgapid engine apply" $X/calls && rbres "되돌리고 고정했습니다"'
rbreset; echo "nothing changed" > $X/plan; rb
check "  계획이 'nothing changed'면 적용 없이 재부팅 안내" '! grep -qx "hmgapid engine apply" $X/calls && rbres "되돌리고 고정했습니다"'
rbreset; printf '%s\n' "$PLAN_OK" "change   /system/app/X.apk [other-mod] -> 1   [restart the app]" > $X/plan; rb
check "  계획에 다른 모드 변경이 있으면 적용하지 않고 앱에서 적용하라고 안내(고정은 함)" '! grep -qx "hmgapid engine apply" $X/calls && [ -f $RB/bk/mod.pin ] && rbres "HMG-API 앱에서 변경 사항을 적용"'
rbreset; printf '%s\n' "setting  prop/persist.sys.iap2.wifi back to stock [wireless-carplay-aa]" > $X/plan; rb
check "  계획에 'back to stock'이 있으면 적용하지 않음(1.7.2 plan_only_mod와 같게)" '! grep -qx "hmgapid engine apply" $X/calls && rbres "HMG-API 앱에서 변경 사항을 적용"'
rbreset; rm -f $RB/bk/mod.ours; rb
check "  Korea Projection이 넣은 모드가 아니면(mod.ours 없음) 바꾸지 않음" '! grep -q "engine install" $X/calls 2>/dev/null && [ ! -f $RB/bk/mod.pin ] && rbres "Korea Projection 것이 아닙니다"'
rbreset; mkdir -p $RB/proc/4321; echo "4321 boot1" > $RB/kw/fix.pid; rb
check "  부팅 자동 설정이 도는 중(fix.pid, 같은 부팅)이면 겹치지 않게 그만두고 다시 꽂으라고 안내" '! grep -q "engine install" $X/calls 2>/dev/null && rbres "3분쯤 뒤에 USB를 다시"'
rbreset; mkdir -p $RB/proc/4321; echo "4321 boot0" > $RB/kw/fix.pid; rb
check "  지난 부팅의 fix.pid는 무시하고 진행" 'grep -q "engine install" $X/calls'
rbreset; touch $X/apply_fail; rb; rm -f $X/apply_fail
check "  적용에 실패하면 고정은 남기고 앱에서 적용하라고 안내" '[ -f $RB/bk/mod.pin ] && rbres "적용하지 못했습니다"'
rbreset; rm -rf $RB/hd/mods; rb
check "  무선 모드가 없으면 아무것도 바꾸지 않음" '! grep -q "engine install" $X/calls 2>/dev/null && [ ! -f $RB/bk/mod.pin ] && rbres "되돌릴 것이 없습니다"'
# 재리뷰 M: busybox가 없는 내비(K3·K8). 패키지에 든 busybox를 쓰고, 그것도 없으면 바꾸지 않고 결과만 남김
rbx() { sed "s#^export PATH=.*#export PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin#" $RBS > $RB/run.sh; (KP_FROM_DATA=1 BB= BB_SYS=$RB/nobb BB_OWN=$1 U=$RB/usb D=$RB/d HMGDATA=$RB/hd BK=$RB/bk MOUNTS=$RB/mounts KW=$RB/kw PROC=$RB/proc BOOT_ID=$RB/bootid NOTICE=$RB/notice sh $RB/run.sh) > $RB/out 2>&1; }
rbreset; rbx $T/bin/bb
check "  재리뷰 M: 내비에 busybox가 없으면 패키지에 든 busybox로 되돌림" 'grep -q "hmgapid engine install .*wireless-carplay-aa-2.3.0.zip --force" $X/calls && [ -f $RB/bk/mod.pin ] && rbres "되돌리고 고정했습니다"'
rbreset; rbx $RB/nobb2
check "  busybox가 하나도 없으면 아무것도 바꾸지 않고 RESULT.txt·상태 화면에 이유를 남김" '! grep -q "engine" $X/calls 2>/dev/null && [ ! -f $RB/bk/mod.pin ] && rbres "busybox를 찾지 못해" && [ "$(stat -f %Lp $RB/notice)" = 644 ]'
rbreset; echo old > $RB/d/out/install.txt 2>/dev/null || { mkdir -p $RB/d/out; echo old > $RB/d/out/install.txt; }; touch $X/down; rb; rm -f $X/down
check "  재리뷰 L: 지난 실행의 기록(install.txt 등)은 USB로 다시 가지 않음" '[ ! -f $RB/usb/kp-rollback/log/install.txt ]'
rbreset; sed -i.bak 's/2\.3\.1/2.3.0/' $RB/hd/mods/wireless-carplay-aa/mod.json; rm -f $RB/bk/mod.ours; rb
check "  재리뷰 L: 2.3.0이어도 Korea Projection 것이 아니면 고정했다고 하지 않음" '[ ! -f $RB/bk/mod.pin ] && rbres "Korea Projection 것이 아닙니다"'
check "  USB 안내서에 NQ5 차주는 쓰지 말라는 주의가 있음" 'grep -q "NQ5" $B/usb-modrollback/GUIDE-ko.md && grep -q "쓰지 마세요" $B/usb-modrollback/GUIDE-ko.md'
rm -rf $RB
else
  echo "건너뜀: 되돌리기 USB 테스트 (공개 저장소에 없는 파일)"
fi
asreset; printf '%s\n' "hooks are off on this car (no map): mods apply without their hooks" "$PLAN_OK" > $X/plan; as > $X/out
check "계획에 '훅 꺼짐'이 있으면 적용 안 함" '! grep -qx "hmgapid engine apply" $X/calls'
asreset; printf '%s\n' "$PLAN_OK" "hooks    wireless-carplay-aa won't load (point x not mapped)" > $X/plan; as > $X/out
check "  'won't load' 줄이 있으면 적용 안 함" '! grep -qx "hmgapid engine apply" $X/calls'
asreset; touch $X/vm_fail; as > $X/out
check "지도 확인에 실패하면 무선 모드를 설치·적용하지 않음" '! grep -q "engine install" $X/calls && ! grep -q "engine apply" $X/calls && [ ! -f $X/bk/mod.tried ]'
check "  확인에 실패한 지도는 다시 빼고(임시 폴더도 없음) map.bad에 폴더와 md5를 남김" '[ ! -d $NM ] && [ ! -d $X/hd/maps/.kp-tmp ] && grep -qx "kia/niro/kor/260902 $(md5 -q $T/app/hmgapi/maps/kia/niro/kor/260902/car.json)" $X/bk/map.bad'
rm -f $X/vm_fail $X/calls $T/toast; as > $X/out
check "  다음 부팅: 같은 지도는 다시 넣지 않고, 확인·모드 설치도 안 함, 토스트 없음" '[ ! -d $NM ] && ! grep -q -E "verify-map|engine install" $X/calls && [ ! -f $T/toast ] && grep -q "지도 확인에 실패한 지도" $X/out'
echo "kia/niro/kor/260902 0123456789abcdef0123456789abcdef" > $X/bk/map.bad; rm -f $X/calls; as > $X/out
check "  지도가 바뀐 새 버전이면(md5 다름) 다시 넣고 확인" '[ -f $NM/car.json ] && grep -qx "hmgapid engine verify-map" $X/calls && grep -q "engine install" $X/calls'
asreset; echo "kia/niro/kor/260902 $(md5 -q $T/app/hmgapi/maps/kia/niro/kor/260902/car.json)" > $X/bk/map.bad; mkdir -p $NM; echo official > $NM/car.json; as > $X/out
check "  실패 기록이 있어도 같은 폴더에 다른 지도(공식판 등)가 생기면 그 지도로 모드 설치" '[ "$(cat $NM/car.json)" = official ] && grep -q "engine install" $X/calls'
asreset; rm -rf $X/kh; mkdir -p $X/kh; cp -R $T/app/hmgapi/. $X/kh/; mkdir -p $X/kh/maps/hyundai/sonata/kor/260101; echo '{}' > $X/kh/maps/hyundai/sonata/kor/260101/car.json
(PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$X/w BK=$X/bk HMGDATA=$X/hd KP_HMG=$X/kh sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$X'/bin:'$T'/bin:/usr/bin:/bin:/sbin; setup_hmgapi') > $X/out
check "이 차 지도만 넣고 기록 (다른 차·다른 펌웨어 지도는 넣지 않음, 지도 확인은 한 번)" '[ -f $NM/car.json ] && [ ! -d $X/hd/maps/hyundai ] && [ "$(cat $X/bk/map.ours)" = kia/niro/kor/260902 ] && [ "$(grep -c verify-map $X/calls)" = 1 ]'
asreset; mkdir -p $NM; echo official > $NM/car.json; mkdir -p $X/kh; cp -R $T/app/hmgapi/. $X/kh/; mkdir -p $X/kh/maps/hyundai/sonata/kor/260101; echo '{"products": ["DN8HEV.KOR."]}' > $X/kh/maps/hyundai/sonata/kor/260101/car.json
(PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$X/w BK=$X/bk HMGDATA=$X/hd KP_HMG=$X/kh sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$X'/bin:'$T'/bin:/usr/bin:/bin:/sbin; setup_hmgapi') > $X/out
check "  이 차 지도가 이미 있으면 아무 지도도 넣지 않고 지도 확인 안 함 (이 차 지도는 그대로)" '[ ! -d $X/hd/maps/hyundai ] && ! grep -q verify-map $X/calls && [ "$(cat $NM/car.json)" = official ] && [ ! -f $X/bk/map.ours ]'
rm -rf $X/kh
asreset; mkdir -p $X/w; : > $X/w/x; (cd $X/w && PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$X/w BK=$X/bk HMGDATA=$X/hd KP_HMG=$T/app/hmgapi sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$X'/bin:'$T'/bin:/usr/bin:/bin:/sbin; setup_hmgapi') > $X/out
check "  현재 폴더에 한 글자 파일이 있어도 [wireless-carplay-aa]를 그대로 비교" 'grep -qx "hmgapid engine apply" $X/calls'
asreset; touch $X/apply_fail; as > $X/out
check "적용 실패 → 안내 (재시작 안내 없음)" 'grep -q "적용에 실패" $T/toast && ! grep -q "마쳤습니다" $T/toast'
asreset; touch $X/vm_fail; rm -f $X/plan; : > $X/plan; mkdir -p $X/hd/mods/wireless-carplay-aa; echo '{}' > $X/hd/mods/wireless-carplay-aa/mod.json; as > $X/out
check "지도 확인 실패 → 안내, 재시작 안내 없음" 'grep -q "지도 확인에 실패" $T/toast && ! grep -q "마쳤습니다" $T/toast'
asreset; cp $T/app/hmgapi/wireless-carplay-aa.zip $X/bad.zip; echo x >> $X/bad.zip; (PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$X/w BK=$X/bk HMGDATA=$X/hd KP_HMG=$X/kh sh -c 'mkdir -p '$X'/kh/maps; cp '$X'/bad.zip '$X'/kh/wireless-carplay-aa.zip; . '$T'/app/svc/hotspot.sh; export PATH='$X'/bin:'$T'/bin:/usr/bin:/bin:/sbin; setup_hmgapi') > $X/out
check "패키지의 모드 zip md5가 다르면 설치 안 함" '! grep -q "engine install" $X/calls && grep -q "md5가 다름" $X/out'
asreset; rm -rf $X/hd/maps; as > $X/out
check "HMG-API가 없으면(/data/hmgapi/maps 없음) 아무것도 안 함" '[ ! -s $X/calls ] && grep -q "HMG-API가 없음" $X/out'
asreset; echo DEPEHEV.USA.0000.V039.001.260902 > $T/product; as > $X/out; rm -f $T/product
check "확인된 차가 아니면 아무것도 안 함" '[ ! -s $X/calls ] && [ ! -d $NM ]'
# 1.5.2: 쏘나타 하이브리드 DN8(DN822HEV.KOR 260902, 시험 지원)
SM=$X/hd/maps/hyundai/sonata/kor/260902
check "패키지의 쏘나타 지도: 파일 12개, 제품 DN822HEV.KOR., 펌웨어 260902" '[ "$(ls $T/app/hmgapi/maps/hyundai/sonata/kor/260902 | wc -l | tr -d " ")" = 12 ] && grep -q "\"DN822HEV.KOR.\"" $T/app/hmgapi/maps/hyundai/sonata/kor/260902/car.json && grep -q "\"firmware\": \"260902\"" $T/app/hmgapi/maps/hyundai/sonata/kor/260902/car.json'
asreset; echo DN822HEV.KOR.0000.V039.001.260902 > $T/product; as > $X/out; rm -f $T/product
check "쏘나타(시험 지원): 쏘나타 지도만 넣고 지도 확인 한 번, 무선 모드 설치·적용" 'diff -r $SM $T/app/hmgapi/maps/hyundai/sonata/kor/260902 >/dev/null && [ ! -d $NM ] && [ "$(grep -c verify-map $X/calls)" = 1 ] && grep -q "engine install" $X/calls && grep -qx "hmgapid engine apply" $X/calls && grep -q "설정을 마쳤습니다" $T/toast'
asreset; mkdir -p $X/hd/maps/unknown/dn822hev/kor/260902; echo own > $X/hd/maps/unknown/dn822hev/kor/260902/car.json
echo DN822HEV.KOR.0000.V039.001.260902 > $T/product; as > $X/out; rm -f $T/product
check "  차주가 차에서 만든 지도(unknown/dn822hev)는 그대로 두고 우리 지도를 더해 확인" '[ "$(cat $X/hd/maps/unknown/dn822hev/kor/260902/car.json)" = own ] && [ -f $SM/car.json ] && [ "$(grep -c verify-map $X/calls)" = 1 ]'
asreset; mkdir -p $X/hd/maps/unknown/dn822hev/kor/260902; echo own > $X/hd/maps/unknown/dn822hev/kor/260902/car.json; touch $X/vm_fail
echo DN822HEV.KOR.0000.V039.001.260902 > $T/product; as > $X/out; rm -f $T/product
check "  우리 지도의 확인이 실패하면 우리 지도만 빼고 차주 지도로 다시 확인, 모드 설치 안 함" '[ ! -d $SM ] && [ "$(cat $X/hd/maps/unknown/dn822hev/kor/260902/car.json)" = own ] && [ "$(grep -c verify-map $X/calls)" = 2 ] && ! grep -q "engine install" $X/calls'
asreset; echo DN822HEV.KOR.0000.V039.001.260101 > $T/product; as > $X/out; rm -f $T/product
check "  쏘나타라도 펌웨어가 다르면 자동 시험: 우리 쏘나타 지도는 넣지 않고 차에서 지도를 만들어 확인" '[ ! -d $SM ] && grep -qx "hmgapid engine map-car --write" $X/calls && [ -f $X/hd/maps/unknown/dn822hev/kor/260101/car.json ] && [ "$(grep -c verify-map $X/calls)" = 1 ] && grep -q "engine install" $X/calls && grep -q "자동으로 설정한 차" $T/toast'
# 자동 시험(목록에 없는 한국 차)
AM=$X/hd/maps/unknown/testx/kor/260101
asreset; echo TESTX.KOR.0000.V039.001.260101 > $T/product; as > $X/out
check "자동 시험: 목록에 없는 한국 차는 HMG-API가 차에서 지도를 만들고 확인한 뒤 모드 설치·적용, 시험 토스트" '[ -f $AM/car.json ] && grep -qx "unknown/testx/kor/260101" $X/bk/map.ours && grep -qx "hmgapid engine verify-map" $X/calls && grep -q "engine install" $X/calls && grep -qx "hmgapid engine apply" $X/calls && grep -q "자동으로 설정한 차" $T/toast && [ ! -d $NM ]'
rm -f $X/calls $T/toast; as > $X/out
check "  다시 부팅: 지도가 있으면 다시 만들지 않고 다시 확인도 안 함" '! grep -q -E "map-car|verify-map|engine install" $X/calls'
rm -rf $X/hd/maps/unknown; rm -f $X/calls; as > $X/out
check "  HMG-API 업데이트로 지도 폴더가 바뀌면 다시 만들고 확인" '[ -f $AM/car.json ] && grep -q "map-car --write" $X/calls && grep -qx "hmgapid engine verify-map" $X/calls'
asreset; touch $X/vm_fail; as > $X/out
check "  만든 지도의 확인이 실패하면 그 지도를 지우고 automap.bad, 모드 설치 안 함" '[ ! -d $AM ] && [ -f $X/bk/automap.bad ] && ! grep -q "engine install" $X/calls && grep -q "지도 확인에 실패" $T/toast'
rm -f $X/vm_fail $X/calls $T/toast; as > $X/out
check "  다음 부팅: 실패 기록이 있으면 지도도 모드도 다시 하지 않음, 토스트 없음" '! grep -q -E "map-car|verify-map|engine install" $X/calls && [ ! -f $T/toast ]'
asreset; mkdir -p $X/hd/maps/hyundai/testx/kor/260101; echo own > $X/hd/maps/hyundai/testx/kor/260101/car.json; as > $X/out
check "  차에 이 차 지도가 이미 있으면(차주·공식판) 만들지 않고 한 번 확인만, 실패해도 지우지 않음" '! grep -q map-car $X/calls && [ "$(grep -c verify-map $X/calls)" = 1 ] && [ -f $X/bk/automap.checked ]'
asreset; mkdir -p $X/hd/maps/hyundai/testx/kor/260101; echo own > $X/hd/maps/hyundai/testx/kor/260101/car.json; touch $X/vm_fail; as > $X/out
check "    그 지도의 확인이 실패하면 지우지 않고 automap.bad, 모드 설치 안 함" '[ "$(cat $X/hd/maps/hyundai/testx/kor/260101/car.json)" = own ] && [ -f $X/bk/automap.bad ] && ! grep -q "engine install" $X/calls'
asreset; touch $X/mc_fail; as > $X/out; rm -f $X/mc_fail
check "  지도 만들기가 실패하면 모드 설치 안 함, 제보 안내 토스트" '[ -f $X/bk/automap.bad ] && ! grep -q "engine install" $X/calls && grep -q "지도를 만들지 못했습니다" $T/toast'
asreset; touch $T/hsfeat; as > $X/out; rm -f $T/hsfeat
check "  순정 핫스팟 기능이 있어도 꺼져 있으면 우리 방식으로 자동 시험 (지도 만들기·모드 설치)" 'grep -q map-car $X/calls && grep -q "engine install" $X/calls && grep -q "꺼져 있음: 우리 방식" $X/out'
mv $T/ps $T/ps.keep 2>/dev/null; echo "  77 wifi  /system/bin/hostapd /data/misc/wifi/hostapd.conf" > $T/ps
asreset; touch $T/hsfeat; as > $X/out; rm -f $T/hsfeat
check "  순정 핫스팟이 켜져 있으면(우리 것이 아닌 hostapd) 이번 부팅은 건너뜀 (지도·모드 모두)" '! grep -q -E "map-car|verify-map|engine install" $X/calls && grep -q "다른 hostapd가 돌고 있음" $X/out'
echo DN822HEV.KOR.0000.V039.001.260902 > $T/product; asreset; as > $X/out
check "  시험 지원 차(쏘나타)도 순정 핫스팟이 켜져 있으면 건너뜀, 지도도 넣지 않음" '! grep -q -E "verify-map|engine install" $X/calls && [ ! -d $X/hd/maps/hyundai/sonata ] && grep -q "다른 hostapd가 돌고 있음" $X/out'
echo "  88 wifi  hostapd /data/misc/wifi/hostapd-kp.conf" > $T/ps; asreset; as > $X/out
check "  우리 hostapd만 돌면 순정으로 보지 않음" 'grep -q "engine install" $X/calls && ! grep -q "다른 hostapd가 돌고" $X/out'
rm -f $T/ps; mv $T/ps.keep $T/ps 2>/dev/null
asreset; mkdir -p $X/wp; (PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$X/w BK=$X/bk HMGDATA=$X/hd KP_HMG=$T/app/hmgapi WPDIR=$X/wp SDIO=$X/nosdio sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$X'/bin:'$T'/bin:/usr/bin:/bin:/sbin; setup_hmgapi') > $X/out; rm -rf $X/wp
check "  시험 지원 차(쏘나타)도 wireless.projection이 있으면 건너뜀, 지도도 넣지 않음" '! grep -q -E "verify-map|engine install" $X/calls && [ ! -d $X/hd/maps/hyundai/sonata ] && grep -q "wireless.projection이 설치" $X/out'
check "  wireless.projection이 있으면 삭제 안내 토스트(한 번만)" 'grep -q "wireless.projection을 삭제한 뒤 내비를 재부팅" $T/toast && [ -f $X/bk/wp.told ]'
rm -f $T/toast; mkdir -p $X/wp; (PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$X/w BK=$X/bk HMGDATA=$X/hd KP_HMG=$T/app/hmgapi WPDIR=$X/wp SDIO=$X/nosdio sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$X'/bin:'$T'/bin:/usr/bin:/bin:/sbin; setup_hmgapi') > $X/out; rm -rf $X/wp
check "    다음 부팅에는 토스트 없음" '[ ! -f $T/toast ]'
mv $T/ps $T/ps.keep 2>/dev/null
printf '%s\n' "  999997 wifi  Z [hostapd]" "  999996 root  busybox grep -E (hostapd|dnsmasq)" > $T/ps; asreset; as > $X/out
check "  좀비 hostapd·grep 줄은 순정 핫스팟으로 보지 않음" 'grep -q "engine install" $X/calls && ! grep -q "다른 hostapd가 돌고" $X/out'
rm -f $T/ps
for c in "IGPEHEV grandeur" "JSN veloster-n"; do
  # check는 eval 안에서 자기 인자($1·$2)를 쓰므로, 차 모델과 지도 폴더는 일반 변수로 넘긴다
  CM=${c% *}; CD=${c#* }; echo $CM.KOR.0000.V039.001.260902 > $T/product; asreset; as > $X/out
  check "  시험 지원 차 $CM: 그 차 지도($CD)만 넣고 확인·모드 설치" '[ -f $X/hd/maps/hyundai/$CD/kor/260902/car.json ] && [ "$(ls $X/hd/maps/hyundai | tr "\n" " ")" = "$CD " ] && grep -qx "hmgapid engine verify-map" $X/calls && grep -q "engine install" $X/calls'
done
# 핫스팟 도는 중 비켜 주기 (확인된 차가 아닐 때만)
yt() { (PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$X/yw sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$X'/bin:'$T'/bin:/usr/bin:/bin:/sbin; prod=$1; ap_yield; echo "rc=$?"' _ "$1"); }
rm -rf $X/yw; mkdir -p $X/yw
printf '%s\n' "  999998 wifi  hostapd /data/misc/wifi/hostapd-kp.conf" "  999999 wifi  /system/bin/hostapd /data/misc/wifi/hostapd.conf" > $T/ps
check "ap_yield: 시험 차는 다른 hostapd가 돌면 비켜 줌(로그 한 번)" 'yt JSN.KOR.0000.V039.001.260902 > $X/y1 && grep -q "rc=0" $X/y1 && grep -q "멈추고 기다림" $X/y1 && [ -f $X/yw/ap.yield ] && yt JSN.KOR.0000.V039.001.260902 > $X/y2 && grep -q "rc=0" $X/y2 && ! grep -q "멈추고" $X/y2'
echo "  999998 wifi  hostapd /data/misc/wifi/hostapd-kp.conf" > $T/ps
check "  다른 hostapd가 멈추면 다시 켬(로그 한 번)" 'yt JSN.KOR.0000.V039.001.260902 > $X/y3 && grep -q "rc=1" $X/y3 && grep -q "다시 켬" $X/y3 && [ ! -f $X/yw/ap.yield ]'
echo "  999999 wifi  /system/bin/hostapd /data/misc/wifi/hostapd.conf" > $T/ps
check "  확인된 차(니로)는 비켜 주지 않음" 'yt DEPEHEV.KOR.0000.V039.001.260902 > $X/y4 && grep -q "rc=1" $X/y4'
rm -f $T/ps; mv $T/ps.keep $T/ps 2>/dev/null
check "서비스: 시작 전 다른 hostapd 대기(1.6.2: 두 번 이어서 없을 때 끝)와 루프의 비켜 주기가 있음" 'grep -q "while \[ \$_gone -lt 2 \]; do" $T/app/svc/hotspot.sh && grep -q "ap_yield && continue" $T/app/svc/hotspot.sh'
# --- 1.6.2: 순정 카플레이 AP(K3 BDPE #15)와 순정 일반 핫스팟 가리기, 우리 dnsmasq는 pid로만 ---
# 서비스 main을 가짜 차에서 돌린다. wait를 바꿔 n번째 대기 때 ps.n이 있으면 ps를 바꾸고(순정 AP가 꺼지거나 켜짐),
# SKW번째 대기에서 7로 끝낸다. kill은 기록만 한다. 순정 hostapd의 ps 줄은 80칸에서 잘린 모양, cmdline은 전체다.
SK=$T/sk; rm -rf $SK; mkdir -p $SK/bin $SK/stock $SK/proc/77 $SK/proc/78 $SK/proc/60
cat > $SK/bin/getprop <<E
#!/bin/sh
case "\$1" in
  ro.build.product) cat $SK/product ;;
  sys.boot_completed) echo 1 ;;
  persist.sys.iap2.wifi) echo t ;;
  *) echo 0 ;;
esac
E
printf '#!/bin/sh\ncat %s/ps 2>/dev/null\n' $SK > $SK/bin/ps
for c in svc hostapd dnsmasq killall settings ifconfig; do printf '#!/bin/sh\necho "%s $*" >> %s/calls\n' $c $SK > $SK/bin/$c; done
printf '#!/bin/sh\necho "$*" > %s/toast\n' $SK > $SK/bin/am
printf '#!/bin/sh\nexit 0\n' > $SK/bin/sleep
printf '#!/bin/sh\nexit 0\n' > $SK/bin/dmesg
printf '#!/bin/sh\nexit 0\n' > $SK/bin/netstat
printf '#!/bin/sh\nexit 1\n' > $SK/bin/hmgapid
chmod +x $SK/bin/*
echo boot-sk > $SK/bootid
printf '/system/bin/hostapd\0-e\0/data/misc/wifi/entropy.bin\0%s\0' $SK/stock/hostapd.conf > $SK/proc/77/cmdline
# 순정 hostapd·dnsmasq의 부모는 netd(pid 60)다(KitKat SoftapController). 우리 USB 스크립트 것은 부모가 netd가 아니다.
echo "60 (netd) S 1 60" > $SK/proc/60/stat
echo "77 (hostapd) S 60 77" > $SK/proc/77/stat
echo "78 (dnsmasq) S 60 78" > $SK/proc/78/stat
# ps가 자른 순정 hostapd 줄(설정 파일 경로가 끝까지 안 보임)과 순정 dnsmasq(우리 것과 명령 앞부분이 같음)
SPS1="  77 wifi      /system/bin/hostapd -e /data/misc/wifi/entropy.bin ${SK%/*}/sk/stock/hos"
SPS2="  78 nobody    dnsmasq --keep-in-foreground --no-resolv --no-poll --dhcp-authoritative --pid-file"
stockps() { printf '%s\n' "$SPS1" "$SPS2"; }
sconf() { printf 'interface=wlan0\ndriver=nl80211\nctrl_interface=/data/misc/wifi/hostapd\nssid=%s\nchannel=149\nhw_mode=a\nwpa_passphrase=word77x\n' "$1" > $SK/stock/hostapd.conf; }
skreset() { rm -rf $SK/w $SK/bk $SK/hd $SK/calls $SK/toast $SK/prog $SK/ps $SK/ps.* $SK/hostapd-kp.conf $SK/wifi $SK/out; mkdir -p $SK/w $SK/bk $SK/hd/mods/wireless-carplay-aa $SK/wifi; echo "ctrl_interface=wlan0" > $SK/wifi/wpa_supplicant.conf; chmod 644 $SK/wifi/wpa_supplicant.conf; echo '{"system": [{"region": "KOR"}]}' > $SK/hd/mods/wireless-carplay-aa/mod.json; echo BDPE.KOR.0000.V039.001.260902 > $SK/product; : > $SK/ps; sconf 'SSID\cX'; }
skrun() { (PATH=$SK/bin:$T/bin:/usr/bin:/bin:/sbin env HOTSPOT_LIB=1 NOTICE=$SK/toast BB=$T/bin/bb W=$SK/w BK=$SK/bk HMGDATA=$SK/hd PROG=$SK/prog BOOT_ID=$SK/bootid PROC=$SK/proc CONF=$SK/hostapd-kp.conf SRC=$T/softap.conf WCONF=$SK/wifi/wpa_supplicant.conf WIFI_WAIT=0 OLDPKG=$SK/none WPDIR=$SK/none KT=$SK/w/kt "$@" ${SKSH:-sh} -c '. '$T'/app/svc/hotspot.sh; export PATH='$SK'/bin:'$T'/bin:/usr/bin:/bin:/sbin; fix_perms() { :; }; kill() { echo "kill $*" >> '$SK'/calls; }; _wc=0; wait() { _wc=$((_wc+1)); [ -f '$SK'/ps.$_wc ] && cp '$SK'/ps.$_wc '$SK'/ps; [ -f '$SK'/conf.$_wc ] && cp '$SK'/conf.$_wc '$SK'/stock/hostapd.conf; [ $_wc -ge ${SKW:-1} ] && exit 7; return 0; }; main') > $SK/out 2>&1; echo "rc=$?" >> $SK/out; }
# 우리 것을 하나도 하지 않았는가(svc wifi, hostapd·dnsmasq 시작, kill, Wi-Fi 잠금 파일)
noours() { ! grep -q -E "^(svc|hostapd|dnsmasq|kill|killall) " $SK/calls 2>/dev/null && [ "$(stat -f %Lp $SK/wifi/wpa_supplicant.conf)" = 644 ] && [ "$(cat $SK/wifi/wpa_supplicant.conf)" = "ctrl_interface=wlan0" ] && [ -z "$(ls $SK/wifi | grep -v "^wpa_supplicant.conf$")" ]; }
skreset; stockps > $SK/ps; skrun SKW=3
check "1.6.2: 시험 차(K3) + 순정 카플레이 AP → 준비됨(내비 Wi-Fi 사용), 진행 기록 done" 'grep -q "순정 카플레이 AP 사용: 우리 핫스팟을 켜지 않음 (카플레이 SSID 길이 7 일치)" $SK/out && grep -qx "state=done" $SK/prog && grep -qx "stage=무선 카플레이 준비됨(내비 Wi-Fi 사용). 아이폰을 연결해 보세요." $SK/prog'
check "  우리 hostapd·dnsmasq·svc wifi·Wi-Fi 잠금·kill 없음, 순정 AP 기록(stockap.seen)" 'noours && [ -f $SK/bk/stockap.seen ]'
check "  반복 없음: 3번 대기해도 로그는 처음 한 줄, '대기: 다른 hostapd' 없음, 60초 대기로 끝나지 않음(rc 7)" '[ "$(grep -c "순정 카플레이 AP" $SK/out)" = 1 ] && ! grep -q "대기: 다른 hostapd" $SK/out && grep -qx "rc=7" $SK/out'
check "  SSID·비밀번호 값은 로그·진행 기록에 없음(길이만)" '! grep -q -F -e "SSID\\cX" -e "HotspotName1" -e "word77x" -e "word99" $SK/out $SK/prog'
check "  우리 hostapd 설정 파일(5GHz 149)은 쓰기만 하고 띄우지 않음" 'grep -qx "channel=149" $SK/hostapd-kp.conf && ! grep -q "^hostapd " $SK/calls 2>/dev/null'
skreset; stockps > $SK/ps; sconf HotspotName1; skrun
check "1.6.2: 시험 차 + 순정 일반 핫스팟(핫스팟 SSID) → 지금처럼 비켜 줌(기다림), 준비됨·기록 없음" 'grep -q "대기: 다른 hostapd가 돌고 있음(순정 핫스팟 등, 판정 hotspot)" $SK/out && [ ! -f $SK/bk/stockap.seen ] && ! grep -q "내비 Wi-Fi" $SK/prog && noours'
skreset; stockps > $SK/ps; sconf OtherNet; skrun
check "  다른 SSID(판정 other)도 비켜 줌" 'grep -q "판정 other)" $SK/out && [ ! -f $SK/bk/stockap.seen ] && noours'
skreset; stockps > $SK/ps; : > $SK/ps.1; stockps > $SK/ps.2; skrun SKW=4
check "1.6.2: 순정 AP가 도중에 사라지면 우리 AP로 바꾸지 않고 기다림, 다시 켜지면 기록(바뀔 때만 한 줄씩)" '[ "$(grep -c "순정 카플레이 AP가 꺼짐: 순정이 다시 켤 때까지 기다림" $SK/out)" = 1 ] && [ "$(grep -c "순정 카플레이 AP가 켜짐$" $SK/out)" = 1 ] && noours && grep -qx "rc=7" $SK/out'
skreset; : > $SK/bk/stockap.seen; skrun SKW=2
check "  순정 AP를 본 차는 다음 부팅에 순정 AP가 늦어도 우리 AP를 켜지 않고 기다림, 못 본 부팅을 셈(1)" 'grep -q "순정 카플레이 AP를 기다림" $SK/out && noours && ! grep -q "내비 Wi-Fi" $SK/prog 2>/dev/null && [ "$(cat $SK/bk/stockap.miss)" = "1 boot-sk" ]'
skrun SKW=2
check "  같은 부팅에 서비스가 다시 시작돼도 한 번만 셈" '[ "$(cat $SK/bk/stockap.miss)" = "1 boot-sk" ]'
stockps > $SK/ps.1; skrun SKW=2
check "  기다리다 순정 AP가 켜지면 셈을 0으로" '[ "$(cat $SK/bk/stockap.miss)" = "0 boot-sk" ] && grep -q "순정 카플레이 AP가 켜짐" $SK/out'
skreset; : > $SK/bk/stockap.seen; echo "3 boot-old" > $SK/bk/stockap.miss; skrun; /bin/sleep 1
check "  못 본 부팅이 3번 이어지면 기록을 지우고 보통 흐름(우리 핫스팟)으로" 'grep -q "3번의 부팅 동안 못 봄" $SK/out && [ ! -f $SK/bk/stockap.seen ] && grep -q "^hostapd " $SK/calls'
skreset; : > $SK/bk/stockap.seen; echo "2 boot-old" > $SK/bk/stockap.miss; skrun
check "  2번이면 아직 기다림" 'grep -q "순정 카플레이 AP를 기다림" $SK/out && noours'
# 리뷰 H2: 우리 USB 스크립트(cp-ap.sh)처럼 netd가 아닌 것이 카플레이 SSID로 띄운 hostapd는 순정으로 보지 않음
skreset; echo "77 (hostapd) S 1 77" > $SK/proc/77/stat; stockps > $SK/ps; skrun
check "  netd가 띄우지 않은 hostapd(카플레이 SSID라도)는 순정 카플레이 AP로 보지 않음(판정 unknown, 기록 없음)" 'grep -q "판정 unknown)" $SK/out && [ ! -f $SK/bk/stockap.seen ] && noours'
echo "77 (hostapd) S 60 77" > $SK/proc/77/stat
skreset; printf '/system/bin/hostapd\0%s\0' $SK/stock/hostapd-cp.conf > $SK/proc/77/cmdline; cp $SK/stock/hostapd.conf $SK/stock/hostapd-cp.conf; stockps > $SK/ps; skrun
check "  hostapd-cp.conf(USB 스크립트 설정)도 순정으로 보지 않음" 'grep -q "판정 unknown)" $SK/out && [ ! -f $SK/bk/stockap.seen ]'
printf '/system/bin/hostapd\0-e\0/data/misc/wifi/entropy.bin\0%s\0' $SK/stock/hostapd.conf > $SK/proc/77/cmdline
# 리뷰 M3: 일반 핫스팟을 기다리는 중 판정이 카플레이로 바뀌면 순정 AP 경로로, 순정이 잠깐 내려가도 바로 시작하지 않음
skreset; stockps > $SK/ps; sconf HotspotName1; sconf 'SSID\cX'; cp $SK/stock/hostapd.conf $SK/conf.1; sconf HotspotName1; skrun SKW=3
check "  기다리는 중 순정이 카플레이 AP로 바꾸면 순정 AP 경로로" 'grep -q "판정 hotspot)" $SK/out && grep -q "순정 카플레이 AP 사용" $SK/out && [ -f $SK/bk/stockap.seen ] && noours'
skreset; stockps > $SK/ps; sconf HotspotName1; : > $SK/ps.1; stockps > $SK/ps.2; skrun SKW=3
check "  순정 hostapd가 한 번 안 보였다 다시 보이면 계속 기다림(우리 것 시작 안 함)" '! grep -q "다른 hostapd가 멈춤: 시작" $SK/out && noours'
skreset; stockps > $SK/ps; sconf HotspotName1; : > $SK/ps.1; skrun SKW=3; /bin/sleep 1
check "  두 번 이어서 안 보이면 그때 시작" '[ "$(grep -c "다른 hostapd가 멈춤: 시작" $SK/out)" = 1 ] && grep -q "^hostapd " $SK/calls'
sconf 'SSID\cX'
# busybox 없는 내비(함께 넣은 busybox, ps -o 형식): 순정 hostapd를 잠시 기다림
skreset; printf '%s\n' "PID   STAT COMMAND" "  77 S    /system/bin/hostapd -e /data/misc/wifi/entropy.bin $SK/stock/hostapd.conf" "  78 S    dnsmasq --keep-in-foreground --no-resolv --no-poll" > $SK/ps.1; skrun BB= BB_SYS=$SK/none BB_OWN=$T/bin/bb SKW=3
check "1.6.2: busybox 없는 내비(함께 넣은 busybox, ps -o) → 순정 AP를 기다렸다가 순정 AP로 준비됨" 'grep -q "순정 카플레이 AP를 최대 90초 기다림" $SK/out && grep -q "순정 카플레이 AP 사용" $SK/out && noours && grep -qx "state=done" $SK/prog'
skreset; skrun BB= BB_SYS=$SK/none BB_OWN=$T/bin/bb STOCK_GRACE=20 SKW=3; /bin/sleep 1  # 뒤에서 뜬 가짜 hostapd·dnsmasq가 기록을 쓸 틈
check "  기다려도 순정 AP가 없으면 우리 핫스팟(5GHz)을 켜고 dnsmasq pid를 남김" 'grep -q "최대 20초" $SK/out && grep -q "^svc wifi enable" $SK/calls && grep -q "^hostapd $SK/hostapd-kp.conf" $SK/calls && grep -q "^dnsmasq " $SK/calls && [ -s $SK/w/dnsmasq.pid ] && grep -qx "hw_mode=a" $SK/hostapd-kp.conf && [ ! -f $SK/bk/stockap.seen ]'
skreset; stockps > $SK/ps; echo DEPEHEV.KOR.0000.V039.001.260902 > $SK/product; skrun; /bin/sleep 1  # 뒤에서 뜬 가짜 hostapd·dnsmasq가 기록을 쓸 틈
check "1.6.2: 확인된 차(니로)는 바뀌지 않음: 순정 판정·기다림 없이 우리 핫스팟, 순정 dnsmasq는 죽이지 않음" '! grep -q -E "순정 카플레이|기다림|대기: 다른" $SK/out && grep -q "^svc wifi enable" $SK/calls && grep -q "^hostapd " $SK/calls && ! grep -qx "kill 78" $SK/calls && [ ! -f $SK/bk/stockap.seen ]'
skreset; echo DEPEHEV.KOR.0000.V039.001.260902 > $SK/product; skrun BB= BB_SYS=$SK/none BB_OWN=$T/bin/bb; /bin/sleep 1  # 뒤에서 뜬 가짜 hostapd·dnsmasq가 기록을 쓸 틈
check "  확인된 차는 함께 넣은 busybox여도 순정 AP를 기다리지 않음" '! grep -q "최대 90초" $SK/out && grep -q "^hostapd " $SK/calls'
# 우리 핫스팟이 도는 중에 순정 카플레이 AP가 켜짐(ap_yield)
skl() { (PATH=$SK/bin:$T/bin:/usr/bin:/bin:/sbin env HOTSPOT_LIB=1 NOTICE=$SK/toast BB=$T/bin/bb W=$SK/w BK=$SK/bk HMGDATA=$SK/hd PROG=$SK/prog BOOT_ID=$SK/bootid PROC=$SK/proc CONF=$SK/hostapd-kp.conf SRC=${SKSRC:-$T/softap.conf} KT=$SK/w/kt sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$SK'/bin:'$T'/bin:/usr/bin:/bin:/sbin; kill() { echo "kill $*" >> '$SK'/calls; }; wait() { exit 7; }; parse_conf $SRC; '"$1"); }
skreset; mkdir -p $SK/proc/91; echo "91 (dnsmasq) S 1 91" > $SK/proc/91/stat; echo "91 boot-sk" > $SK/w/dnsmasq.pid
{ echo "  90 wifi      hostapd $SK/hostapd-kp.conf"; stockps; echo "  91 root      dnsmasq --keep-in-foreground --no-resolv --no-poll --dhcp-authoritative --pid-file"; } > $SK/ps
skl 'prod=BDPE.KOR.0000.V039.001.260902; ap_yield' > $SK/out 2>&1
check "1.6.2: 우리 핫스팟 도는 중 순정 카플레이 AP가 켜지면 우리 hostapd·dnsmasq(pid)만 멈추고 순정 AP 경로로" 'grep -qx "kill 90" $SK/calls && grep -qx "kill 91" $SK/calls && ! grep -q -E "^kill (77|78)$" $SK/calls && [ ! -f $SK/w/dnsmasq.pid ] && grep -q "우리 핫스팟을 멈춤" $SK/out && grep -q "순정 카플레이 AP 사용" $SK/out && [ -f $SK/bk/stockap.seen ]'
# our_dhcp_on: pid 파일 기준(순정 dnsmasq를 우리 것으로 세지 않음)
skreset; stockps > $SK/ps
check "1.6.2 our_dhcp: 순정 dnsmasq만 돌면 우리 DHCP 아님(예전 명령 패턴은 우리 것으로 셌음)" '! skl our_dhcp_on && skl "running \"\$DNSMASQ\""'
mkdir -p $SK/proc/91; echo "91 (dnsmasq) S 1 91" > $SK/proc/91/stat
echo "91 boot-sk" > $SK/w/dnsmasq.pid
check "  pid 파일의 pid가 이번 부팅의 dnsmasq면 우리 DHCP" 'skl our_dhcp_on'
echo "91 boot-old" > $SK/w/dnsmasq.pid
check "  지난 부팅의 pid 파일은 무시" '! skl our_dhcp_on'
echo "91 boot-sk" > $SK/w/dnsmasq.pid; echo "91 (sleep) S 1 91" > $SK/proc/91/stat
check "  pid가 다른 프로그램이면 아님, 빈·숫자 아닌 pid도 아님" '! skl our_dhcp_on && echo "x1 boot-sk" > $SK/w/dnsmasq.pid && ! skl our_dhcp_on && : > $SK/w/dnsmasq.pid && ! skl our_dhcp_on'
skreset; stockps > $SK/ps; skl stop_ours
check "  stop_ours: 순정 hostapd가 돌고 pid 파일이 없으면 순정 dnsmasq를 죽이지 않음" '! grep -q "^kill" $SK/calls 2>/dev/null'
skreset; echo "  95 root      dnsmasq --keep-in-foreground --no-resolv --no-poll --dhcp-authoritative --pid-file" > $SK/ps; skl stop_ours
check "  stop_ours: 순정 hostapd가 없고 pid 파일도 없으면(예전 판이 띄운 우리 dnsmasq) 예전처럼 명령으로 멈춤" 'grep -qx "kill 95" $SK/calls'
# stock_ssid 판정
skreset
check "1.6.2 stock_ssid: 순정 hostapd 없음 → none" '[ "$(skl stock_ssid)" = none ]'
stockps > $SK/ps
check "  카플레이 SSID → carplay, 핫스팟 SSID → hotspot" '[ "$(skl stock_ssid)" = carplay ] && sconf HotspotName1 && [ "$(skl stock_ssid)" = hotspot ]'
printf 'ssid=a\nssid=b\n' > $SK/stock/hostapd.conf
check "  ssid 줄이 둘이면 unknown, ssid2=(16진)만 있으면 unknown" '[ "$(skl stock_ssid)" = unknown ] && printf "ssid2=53534944\n" > $SK/stock/hostapd.conf && [ "$(skl stock_ssid)" = unknown ]'
sconf 'SSID\cX'; mv $SK/proc/77 $SK/proc/77.x
check "  /proc의 명령줄을 못 읽으면 unknown(예전처럼 비켜 줌)" '[ "$(skl stock_ssid)" = unknown ]'
mv $SK/proc/77.x $SK/proc/77; rm $SK/stock/hostapd.conf
check "  설정 파일을 못 읽으면 unknown" '[ "$(skl stock_ssid)" = unknown ]'
sconf 'SSID\cX'
python3 - $SK/softap-same.conf <<'E'
import struct,sys
u=lambda s:struct.pack('>H',len(s))+s.encode()
open(sys.argv[1],'wb').write(struct.pack('>i',3)+u('SSID\\cX')+u('SSID\\cX')+u('x')+u('PASS\\word99'))
E
check "  핫스팟·카플레이 SSID가 같으면 가릴 수 없어 unknown" '[ "$(SKSRC=$SK/softap-same.conf skl stock_ssid)" = unknown ]'
printf 'interface=wlan0\nssid=SSID\\cX' > $SK/stock/hostapd.conf
check "  마지막 줄에 줄바꿈이 없어도 읽음" '[ "$(skl stock_ssid)" = carplay ]'
# 리뷰 M1: 예전 판 dnsmasq를 명령으로 찾을 때도 netd가 띄운 순정 dnsmasq는 멈추지 않음
skreset; echo "$SPS2" > $SK/ps; skl stop_ours
check "1.6.2 stop_ours: 순정 hostapd가 잠깐 없어도 netd가 띄운 dnsmasq는 멈추지 않음" '! grep -q "^kill" $SK/calls 2>/dev/null'
skreset; echo "$SPS2" > $SK/ps; echo "  96 root      dnsmasq --keep-in-foreground --no-resolv --no-poll --dhcp-authoritative --pid-file" >> $SK/ps; skl stop_ours
check "  같은 때 netd가 아닌 dnsmasq(예전 판의 우리 것)만 멈춤" 'grep -qx "kill 96" $SK/calls && ! grep -qx "kill 78" $SK/calls'
skreset; echo "  96 root      dnsmasq --keep-in-foreground --no-resolv --no-poll --dhcp-authoritative --pid-file" > $SK/ps; skl 'STOCK_MODE=1; stop_ours'
check "  순정 AP 경로(STOCK_MODE)에서는 명령으로 찾아 멈추지 않음" '! grep -q "^kill" $SK/calls 2>/dev/null'
# 순정 AP 경로에서 TERM을 받으면 바로 끝남(0), 순정 것은 멈추지 않음
skreset; stockps > $SK/ps
PATH=$SK/bin:$T/bin:/usr/bin:/bin:/sbin env HOTSPOT_LIB=1 BB=$T/bin/bb W=$SK/w BK=$SK/bk HMGDATA=$SK/hd PROG=$SK/prog BOOT_ID=$SK/bootid PROC=$SK/proc CONF=$SK/hostapd-kp.conf SRC=$T/softap.conf WCONF=$SK/wifi/wpa_supplicant.conf OLDPKG=$SK/none WPDIR=$SK/none KT=$SK/w/kt sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$SK'/bin:'$T'/bin:/usr/bin:/bin:/sbin; fix_perms() { :; }; kill() { echo "kill $*" >> '$SK'/calls; }; sleep() { /bin/sleep 2; }; main' > $SK/out 2>&1 &
SKPID=$!; /bin/sleep 1.5; kill -TERM $SKPID 2>/dev/null; wait $SKPID; echo "rc=$?" >> $SK/out
check "1.6.2: 순정 AP 경로에서 TERM을 받으면 정리하고 0으로 끝남, 순정 hostapd·dnsmasq는 멈추지 않음" 'grep -q "순정 카플레이 AP 사용" $SK/out && grep -q "멈춤$" $SK/out && grep -qx "rc=0" $SK/out && ! grep -q -E "^kill (77|78)$" $SK/calls 2>/dev/null'
# 리뷰 H1: 삭제·업데이트 때 순정 hostapd가 돌면 wlan0 주소를 지우지 않음
mkdir -p $SK/pbk $SK/phd
sed -e "s#^BB=.*#BB=$T/bin/bb#" -e "s#^BK=.*#BK=$SK/pbk#" -e "s#/data/nemesis/apps/korea.projection/svc/hotspot.sh#$T/app/svc/hotspot.sh; export PATH=$SK/bin:$T/bin:/usr/bin:/bin:/sbin#" \
  -e "s#^export PATH=.*#export PATH=$SK/bin:$T/bin:/usr/bin:/bin:/sbin#" -e "s#^STAGE=.*#STAGE=$SK/stage#" \
  -e "s#/data/local/tmp/korea-projection-status#$SK/pstatus#g" $T/app/scripts/preun.sh > $SK/preun.sh
skpu() { rm -f $SK/calls; mkdir -p $SK/pbk; (env HMGDATA=$SK/phd W=$SK/pw PROC=$SK/proc PROG=$SK/pprog BOOT_ID=$SK/bootid CONF=$SK/hostapd-kp.conf WCONF=$SK/wifi/wpa_supplicant.conf sh $SK/preun.sh) > $SK/pout 2>&1; }
stockps > $SK/ps; skpu
check "1.6.2 삭제: 순정 hostapd가 돌면 wlan0 주소를 지우지 않음(순정 카플레이가 끊기지 않게)" '! grep -q "^ifconfig wlan0 0.0.0.0" $SK/calls 2>/dev/null'
: > $SK/ps; skpu
check "  순정 hostapd가 없으면 예전처럼 지움" 'grep -q "^ifconfig wlan0 0.0.0.0" $SK/calls'
# --- 1.7.2(P-7): 순정 AP 저장값(wifi_ap_on) 맞추기 ---
# 값을 기억하는 가짜 settings($SK/apon: 지금 값, 없으면 null). apon.ro가 있으면 put이 듣지 않음.
# "settings 명령 없음"은 $SK/bin·$T/bin의 settings를 잠시 치워서 만든다.
cp $SK/bin/settings $SK/settings.keep
cat > $SK/apset <<E
#!/bin/sh
echo "settings \$*" >> $SK/calls
case "\$1 \$3" in
  "get wifi_ap_on")
    # apon.after(N): N번째 get 직전에 값이 다시 1이 됨(세션 중 순정 AP 켜기가 1을 다시 씀)
    if [ -f $SK/apon.after ]; then echo x >> $SK/apon.gets; [ "\$(wc -l < $SK/apon.gets)" -eq "\$(cat $SK/apon.after)" ] && echo 1 > $SK/apon; fi
    cat $SK/apon 2>/dev/null || echo null ;;
  "put wifi_ap_on") [ -f $SK/apon.ro ] || echo "\$4" > $SK/apon ;;
esac
exit 0
E
chmod +x $SK/apset; cp $SK/apset $SK/bin/settings
# 우리 hostapd가 돌고 있는 ps(apon_off는 우리 hostapd가 돌 때만 바꾼다)
ourline() { echo "  90 wifi      hostapd $SK/hostapd-kp.conf"; }
ourps() { ourline > $SK/ps; }
apreset() { skreset; rm -f $SK/apon $SK/apon.ro $SK/apon.after $SK/apon.gets; echo DEPEHEV.KOR.0000.V039.001.260902 > $SK/product; ourps; }
apput() { grep -q "^settings put global wifi_ap_on" $SK/calls 2>/dev/null; }
apreset; echo 1 > $SK/apon; skrun; /bin/sleep 1
check "1.7.2 P-7: 우리 핫스팟이 도는 니로 + wifi_ap_on=1 → 원래 값 1을 기록하고 0으로, 로그는 값만" '[ "$(cat $SK/apon)" = 0 ] && [ "$(cat $SK/bk/wifi_ap_on.orig)" = 1 ] && grep -q "순정 AP 저장값(wifi_ap_on) 1 → 0" $SK/out && grep -qx "rc=7" $SK/out'
apreset; echo 1 > $SK/apon; : > $SK/ps; skrun; /bin/sleep 1
check "  우리 hostapd가 돌지 않으면(켜지 못함) 바꾸지 않음(리뷰 L2)" 'grep -q "^hostapd " $SK/calls && [ "$(cat $SK/apon)" = 1 ] && [ ! -f $SK/bk/wifi_ap_on.orig ] && ! apput'
apreset; echo 1 > $SK/apon; skrun SKW=21; /bin/sleep 1
check "  30초 점검 20번째(10분)에 다시 봄: 값이 0이면 get 한 번뿐(put·로그 없음)" '[ "$(grep -c "^settings put global wifi_ap_on 0" $SK/calls)" = 1 ] && [ "$(grep -c "^settings get global wifi_ap_on" $SK/calls)" = 3 ] && [ "$(grep -c "wifi_ap_on" $SK/out)" = 1 ]'
apreset; echo 1 > $SK/apon; echo 3 > $SK/apon.after; skrun SKW=21; /bin/sleep 1
check "  시작 때 0으로 바꾼 뒤 세션 중 다시 1이 되면 10분 점검에서 또 0으로(리뷰 M2), 기록은 1 그대로" '[ "$(grep -c "^settings put global wifi_ap_on 0" $SK/calls)" = 2 ] && [ "$(cat $SK/apon)" = 0 ] && [ "$(cat $SK/bk/wifi_ap_on.orig)" = 1 ] && grep -qx "rc=7" $SK/out'
rm -f $SK/calls; skrun; /bin/sleep 1
check "  같은 부팅에 다시 시작(값 0): 기록은 1 그대로(0으로 덮지 않음), put 없음" '[ "$(cat $SK/bk/wifi_ap_on.orig)" = 1 ] && ! apput && ! grep -q "wifi_ap_on) 1 → 0" $SK/out'
echo 1 > $SK/apon; rm -f $SK/calls; skrun; /bin/sleep 1
check "  다른 곳에서 다시 1이 되면 다시 0으로, 기록은 1 그대로" '[ "$(cat $SK/apon)" = 0 ] && [ "$(cat $SK/bk/wifi_ap_on.orig)" = 1 ] && apput'
apreset; echo 0 > $SK/apon; skrun; /bin/sleep 1
check "  이미 0이면 아무것도 하지 않음(기록·put·로그 없음)" '[ ! -f $SK/bk/wifi_ap_on.orig ] && ! apput && ! grep -q "wifi_ap_on" $SK/out'
apreset; skrun; /bin/sleep 1
check "  값이 null(한 번도 안 씀)이면 그대로 두고 로그 한 줄, 기록 없음" '[ ! -f $SK/bk/wifi_ap_on.orig ] && ! apput && grep -q "wifi_ap_on) 그대로 둠: 값 없음·읽지 못함" $SK/out'
apreset; echo 1 > $SK/apon; : > $SK/apon.ro; skrun; /bin/sleep 1
check "  put이 듣지 않으면 로그 한 줄, 서비스는 계속 돎" 'grep -q "0으로 바꾸지 못함(지금 값 1)" $SK/out && grep -qx "rc=7" $SK/out'
apreset; echo 1 > $SK/apon; mv $SK/bin/settings $SK/settings.off; mv $T/bin/settings $T/settings.off; skrun; /bin/sleep 1
mv $SK/settings.off $SK/bin/settings; mv $T/settings.off $T/bin/settings
check "  settings 명령이 없으면 로그 한 줄만 남기고 넘어감(서비스는 계속, 기록 없음)" 'grep -q "맞추기 건너뜀: settings 명령 없음" $SK/out && [ ! -f $SK/bk/wifi_ap_on.orig ] && [ "$(cat $SK/apon)" = 1 ] && grep -qx "rc=7" $SK/out'
apreset; echo 1 > $SK/apon; mkdir -p $SK/wpdir; skrun WPDIR=$SK/wpdir; /bin/sleep 1; rmdir $SK/wpdir
check "  wireless.projection이 설치된 차는 건드리지 않음" '[ "$(cat $SK/apon)" = 1 ] && [ ! -f $SK/bk/wifi_ap_on.orig ] && ! apput'
apreset; echo 1 > $SK/apon; : > $SK/bk/wifi.nochip; skrun; /bin/sleep 1
check "  Wi-Fi 칩 없음 기록(wifi.nochip)이 있는 차는 건드리지 않음" '[ "$(cat $SK/apon)" = 1 ] && [ ! -f $SK/bk/wifi_ap_on.orig ] && ! apput'
apreset; echo 1 > $SK/apon; echo BDPE.KOR.0000.V039.001.260902 > $SK/product; skrun BB= BB_SYS=$SK/none BB_OWN=$T/bin/bb STOCK_GRACE=0; /bin/sleep 1
check "  함께 넣은 busybox를 쓰는 내비(tcc803x)는 우리 핫스팟이 돌아도 건드리지 않음" 'grep -q "시작 (BDPE" $SK/out && [ "$(cat $SK/apon)" = 1 ] && [ ! -f $SK/bk/wifi_ap_on.orig ] && ! apput'
apreset; echo 1 > $SK/apon; echo BDPE.KOR.0000.V039.001.260902 > $SK/product; { ourline; stockps; } > $SK/ps; skrun SKW=2
check "  순정 카플레이 AP 차(stockap 경로)는 건드리지 않음" 'grep -q "순정 카플레이 AP 사용" $SK/out && [ "$(cat $SK/apon)" = 1 ] && [ ! -f $SK/bk/wifi_ap_on.orig ] && ! apput'
apreset; echo 0 > $SK/apon; echo 1 > $SK/bk/wifi_ap_on.orig; echo BDPE.KOR.0000.V039.001.260902 > $SK/product; stockps > $SK/ps; skrun SKW=2
check "  순정 카플레이 AP 경로로 가도 되돌리지 않음(0과 기록 그대로, 삭제 때 되돌림, 리뷰 M1)" 'grep -q "순정 카플레이 AP 사용" $SK/out && [ "$(cat $SK/apon)" = 0 ] && [ "$(cat $SK/bk/wifi_ap_on.orig)" = 1 ] && ! apput'
# preun(삭제): $SK/preun.sh, BK=$SK/pbk
apreset; : > $SK/ps; mkdir -p $SK/pbk; echo 1 > $SK/pbk/wifi_ap_on.orig; echo 0 > $SK/apon; skpu
check "  삭제(preun): 기록이 있고 지금 0이면 원래 값 1로 되돌림" '[ "$(cat $SK/apon)" = 1 ] && grep -q "wifi_ap_on) 되돌림: 0 → 1" $SK/pout && grep -q "삭제 완료" $SK/pout'
apreset; mkdir -p $SK/pbk; echo 1 > $SK/pbk/wifi_ap_on.orig; echo 1 > $SK/apon; skpu
check "  삭제: 우리가 바꾼 뒤 다른 곳에서 바뀌었으면(지금 1) 그대로 둠(put 없음)" '[ "$(cat $SK/apon)" = 1 ] && ! apput && grep -q "다른 곳에서 바뀜(지금 값 1)" $SK/pout'
apreset; mkdir -p $SK/pbk; echo 0 > $SK/apon; skpu
check "  삭제: 기록이 없으면(우리가 바꾸지 않음) 0이어도 그대로" '[ "$(cat $SK/apon)" = 0 ] && ! apput'
apreset; mkdir -p $SK/pbk $SK/stage; echo id=korea.projection > $SK/stage/NEMESIS.data; echo 1 > $SK/pbk/wifi_ap_on.orig; echo 0 > $SK/apon; skpu; rm -rf $SK/stage
check "  업데이트(preun, staging에 새 버전): 되돌리지 않고 기록도 남김" '[ "$(cat $SK/apon)" = 0 ] && [ "$(cat $SK/pbk/wifi_ap_on.orig)" = 1 ] && ! apput && grep -q "업데이트: 이전 버전 정리" $SK/pout'
apreset; mkdir -p $SK/pbk; echo 1 > $SK/pbk/wifi_ap_on.orig; echo 0 > $SK/apon; mv $SK/bin/settings $SK/settings.off; mv $T/bin/settings $T/settings.off; skpu
mv $SK/settings.off $SK/bin/settings; mv $T/settings.off $T/bin/settings
check "  삭제: settings 명령이 없으면 로그 한 줄과 삭제 출력 안내, 삭제는 끝까지 진행" 'grep -q "되돌리기 건너뜀: settings 명령 없음" $SK/pout && grep -q "저장값(wifi_ap_on)을 되돌리지 못했습니다" $SK/pout && grep -q "삭제 완료" $SK/pout && [ "$(cat $SK/apon)" = 0 ]'
apreset; mkdir -p $SK/pbk; echo 1 > $SK/pbk/wifi_ap_on.orig; rm -f $SK/apon; skpu
check "  삭제: 값을 읽지 못하면(null) 되돌리지 않고 안내" '! apput && grep -q "되돌리기 건너뜀: 값을 읽지 못함" $SK/pout && grep -q "되돌리지 못했습니다" $SK/pout'
check "  리포트(status.sh): 우리가 바꾼 기록(원래 값, 숫자만)을 wifi_ap_on 줄 다음에 적음" 'grep -A3 "순정 AP 저장값(wifi_ap_on): " $PKG/bin/status.sh | grep -q "wifi_ap_on.orig" && grep -q "cat \$APON_ORIG" $PKG/bin/status.sh'
cp $SK/settings.keep $SK/bin/settings; rm -f $SK/apon $SK/apon.ro
# 차의 셸(ksh 계열)로도 순정 AP 경로를 돌린다(read·$!·함수 바꾸기가 sh와 같은지)
for SKSH in $KSHS; do
  skreset; stockps > $SK/ps; : > $SK/ps.1; stockps > $SK/ps.2; skrun SKW=4
  check "1.6.2 $(basename $SKSH): 순정 AP 준비됨·꺼짐·켜짐, 우리 것 없음" 'grep -q "순정 카플레이 AP 사용" $SK/out && grep -q "순정 카플레이 AP가 꺼짐" $SK/out && grep -q "순정 카플레이 AP가 켜짐$" $SK/out && grep -qx "state=done" $SK/prog && noours && grep -qx "rc=7" $SK/out'
done
SKSH=
check "1.6.2: hotspot.sh에 순정 판정·끝나는 조건이 있는 대기(60초, TERM)" 'grep -q "^stock_ap_mode() {" $T/app/svc/hotspot.sh && grep -q "^stock_ssid() {" $T/app/svc/hotspot.sh && grep -q "^our_dhcp_on() {" $T/app/svc/hotspot.sh'
check "패키지의 모드 zip md5가 MOD_MD5와 같음" '[ "$(md5 -q $PKG/hmgapi/wireless-carplay-aa.zip 2>/dev/null || md5sum < $PKG/hmgapi/wireless-carplay-aa.zip | cut -d" " -f1)" = "$(sed -n "s/^MOD_MD5=//p" $PKG/svc/hotspot.sh)" ]'
echo TESTX.KOR.0000.V039.001.260101 > $T/product
asreset; mkdir -p $X/wp; (PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$X/w BK=$X/bk HMGDATA=$X/hd KP_HMG=$T/app/hmgapi WPDIR=$X/wp sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$X'/bin:'$T'/bin:/usr/bin:/bin:/sbin; setup_hmgapi') > $X/out; rm -rf $X/wp
check "  wireless.projection이 설치된 차는 자동 시험 안 함" '! grep -q -E "map-car|verify-map|engine install" $X/calls && grep -q "wireless.projection이 설치" $X/out'
asreset; mkdir -p $X/hd/maps/kia/dl3/kor/260101; echo '{"products": ["TESTX.KOR."]}' > $X/hd/maps/kia/dl3/kor/260101/car.json
touch $X/mc_nw; as > $X/out; rm -f $X/calls; as > $X/out2; rm -f $X/mc_nw
check "  다른 폴더 이름의 이 차 지도(공식판)가 있으면 그 지도를 한 번 확인하고 모드 설치, 다음 부팅엔 지도 만들기·확인 안 함" 'grep -q "이미 있음" $X/out && [ -f $X/bk/automap.checked ] && [ -f $X/hd/maps/kia/dl3/kor/260101/car.json ] && ! grep -q -E "verify-map|map-car" $X/calls'
asreset; echo TESTX.USA.0000.V039.001.260101 > $T/product; as > $X/out
check "해외 차는 자동 시험도 하지 않음 (아무것도 안 함)" '[ ! -s $X/calls ]'
rm -f $T/product
# Wi-Fi 칩 깨우기 (한국 펌웨어에는 Wi-Fi를 켜는 메뉴가 없어, 한 번도 안 켠 차는 칩이 SDIO에 안 보인다)
cat > $X/bin/svc <<E
#!/bin/sh
echo "svc \$*" >> $X/calls
[ "\$*" = "wifi enable" ] && [ -f $X/chip_ok ] && mkdir -p $X/sdio/mmc1:0001:1
[ "\$*" = "wifi enable" ] && [ -f $X/svc_hang ] && exec /bin/sleep 30
[ "\$*" = "wifi enable" ] && [ -f $X/svc_fail ] && exit 3
exit 0
E
printf '#!/bin/sh\necho "$*" >> %s/toasts\n' $X > $X/bin/am
chmod +x $X/bin/svc $X/bin/am
aw() { (PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 NOTICE=$X/toasts BB=$T/bin/bb W=$X/w BK=$X/bk HMGDATA=$X/hd KP_HMG=$T/app/hmgapi SDIO=$X/sdio WAKE_MAX=100 sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$X'/bin:'$T'/bin:/usr/bin:/bin:/sbin; setup_hmgapi'); }
awreset() { asreset; rm -rf $X/sdio $X/chip_ok $X/chip_drop $X/toasts; rm -f $X/hd/public/wifi-chip; mkdir -p $X/sdio; echo 0 > $X/bk/wifi_on; }
asreset; rm -f $X/toasts; as > $X/out
check "Wi-Fi 칩 기록이 있으면 Wi-Fi를 건드리지 않음" '! grep -q "svc wifi" $X/calls && grep -q "engine install" $X/calls && ! grep -q "Wi-Fi를 한 번 켭니다" $X/toasts'
awreset; mkdir -p $X/sdio/mmc1:0001:1; aw > $X/out
check "  칩이 SDIO에 이미 보이면 Wi-Fi를 건드리지 않음" '! grep -q "svc wifi" $X/calls && grep -q "engine install" $X/calls'
awreset; touch $X/chip_ok; aw > $X/out
check "칩이 안 보이면 미리 안내하고 Wi-Fi를 한 번 켜고, 칩이 나타나면 모드 설치" 'grep -q "Wi-Fi를 한 번 켭니다" $X/toasts && grep -qx "svc wifi enable" $X/calls && grep -q "engine install" $X/calls && grep -q "칩이 나타남" $X/out && [ ! -f $X/bk/wifi.nochip ] && ! grep -q "svc wifi disable" $X/calls'
check "  깨우기는 모드 설치보다 먼저" '[ "$(grep -n "svc wifi enable" $X/calls | cut -d: -f1)" -lt "$(grep -n "engine install" $X/calls | cut -d: -f1)" ]'
awreset; touch $X/chip_ok $X/chip_drop; aw > $X/out; rm -f $X/calls $X/toasts; aw > $X/out2
check "칩이 잠깐 보였다 사라져 설치가 실패해도 다음 부팅에 Wi-Fi를 다시 켜지 않음 (wifi.woke)" '[ -f $X/bk/wifi.woke ] && ! grep -q "svc wifi" $X/calls && ! grep -q "engine install" $X/calls && [ ! -s $X/toasts ]'
awreset; aw > $X/out
check "Wi-Fi를 켜도 칩이 안 나타나면 모드 설치 안 함, wifi.nochip, 재부팅·제보 안내" '! grep -q "engine install" $X/calls && [ -f $X/bk/wifi.nochip ] && [ ! -f $X/bk/mod.tried ] && grep -q "Wi-Fi 칩을 찾지 못해.*재부팅" $X/toasts'
check "  1.7.1: 그때의 순정 Wi-Fi 기록을 nochip-wifi.txt에 남김(가림: MAC·SSID 없음), 로그에 그 파일 이름" 'grep -q "칩 깨우기 실패 기록" $X/w/nochip-wifi.txt && grep -q "## logcat" $X/w/nochip-wifi.txt && grep -q "SUP_DISCONNECTION_EVENT" $X/w/nochip-wifi.txt && ! grep -q -E "a1:b2|MyHomeNet" $X/w/nochip-wifi.txt && grep -q "nochip-wifi.txt" $X/out'
check "  설치 전에 Wi-Fi가 꺼져 있었으면 다시 끔" 'grep -qx "svc wifi disable" $X/calls'
rm -f $X/calls $X/toasts; aw > $X/out
check "  다음 부팅: Wi-Fi를 다시 켜지 않고, 토스트도 없음" '! grep -q "svc wifi" $X/calls && ! grep -q "engine install" $X/calls && [ ! -s $X/toasts ]'
mkdir -p $X/sdio/mmc1:0001:1; rm -f $X/calls; aw > $X/out
check "  그 뒤 칩이 보이게 되면(차주가 켬) 기록과 상관없이 모드 설치" 'grep -q "engine install" $X/calls && ! grep -q "svc wifi" $X/calls'
awreset; echo 1 > $X/bk/wifi_on; aw > $X/out
check "  설치 전에 Wi-Fi가 켜져 있었으면 끄지 않음" '! grep -q "svc wifi disable" $X/calls'
awreset; echo null > $X/bk/wifi_on; aw > $X/out
check "  설치 전 값이 null(한 번도 안 켬)이면 꺼져 있던 것으로 보고 끔" 'grep -qx "svc wifi disable" $X/calls'
awreset; rm -f $X/bk/wifi_on; aw > $X/out
check "  설치 전 기록이 없으면 끄지 않음" '! grep -q "svc wifi disable" $X/calls'
awreset; touch $T/nowififeat $X/chip_ok; aw > $X/out; rm -f $T/nowififeat
check "Android Wi-Fi 기능이 목록에 없어도(니로처럼) Wi-Fi를 켜서 칩을 깨움" 'grep -qx "svc wifi enable" $X/calls && grep -q "engine install" $X/calls'
awreset; touch $X/svc_fail; aw > $X/out; rm -f $X/svc_fail
check "  svc wifi enable이 실패하면 종료 코드를 기록하고 nochip으로 끝냄" 'grep -q "svc wifi enable 실패 (종료 코드 3)" $X/out && [ -f $X/bk/wifi.nochip ] && ! grep -q "engine install" $X/calls'
awreset; touch $X/svc_hang; aw > $X/out; rm -f $X/svc_hang
check "  svc wifi enable이 끝나지 않으면 대기 시간 뒤 멈추고 끝냄" 'grep -q "끝나지 않아 멈춤" $X/out && [ -f $X/bk/wifi.nochip ] && ! grep -q "engine install" $X/calls'
awreset; touch $X/chip_ok $X/vm_fail; aw > $X/out
check "지도 확인이 실패하면 Wi-Fi를 켜지 않음 (모드를 넣지 않을 때는 깨우지 않음)" '! grep -q "svc wifi" $X/calls'
awreset; touch $X/chip_ok; : > $X/bk/mod.tried; aw > $X/out
check "  모드 설치를 이미 해 봤으면(mod.tried) Wi-Fi를 켜지 않음" '! grep -q "svc wifi" $X/calls'
# 1.7.2(P-12): 칩 없음으로 멈췄는데 근거 기록(nochip-wifi.txt)이 없는 차(#58)는 한 번만 다시 확인
awreset; : > $X/bk/wifi.nochip; : > $X/bk/wifi.woke; aw > $X/out
check "1.7.2 P-12: wifi.nochip인데 근거 기록이 없으면 한 번 다시 깨워 근거(판정 근거 module_version 줄)를 남김" 'grep -qx "svc wifi enable" $X/calls && [ -f $X/bk/nochip.rechk ] && [ -f $X/bk/wifi.nochip ] && grep -q "^판정 근거: 순정 module_version=" $X/w/nochip-wifi.txt && grep -q "한 번만 다시 확인" $X/out'
check "  리뷰 M-1: 근거 사본을 업데이트에도 남는 \$BK에도 둠" 'grep -q "^판정 근거: 순정 module_version=" $X/bk/nochip-wifi.txt'
rm -f $X/calls $X/w/nochip-wifi.txt; aw > $X/out
check "  두 번째부터는 다시 깨우지 않음(횟수 제한 nochip.rechk)" '! grep -q "svc wifi" $X/calls'
awreset; : > $X/bk/wifi.nochip; echo "판정 근거: x" > $X/w/nochip-wifi.txt; aw > $X/out
check "  근거 기록이 이미 있으면 다시 깨우지 않음" '! grep -q "svc wifi" $X/calls && [ ! -f $X/bk/nochip.rechk ]'
awreset; : > $X/bk/wifi.nochip; echo "판정 근거: x" > $X/bk/nochip-wifi.txt; aw > $X/out
check "  리뷰 M-1: 업데이트로 \$W 기록이 지워져도 \$BK 사본이 있으면 다시 깨우지 않음" '! grep -q "svc wifi" $X/calls && [ ! -f $X/bk/nochip.rechk ]'
awreset; : > $X/bk/wifi.nochip; touch $X/chip_ok; aw > $X/out
check "  다시 확인에서 칩이 나타나면 칩 없음 기록을 지우고 모드 설치를 이어 감" '[ ! -f $X/bk/wifi.nochip ] && grep -q "engine install" $X/calls'
# 1.7.2(P-13, 이슈 #27 약속): 차주가 HMG-API 앱에서 모드를 지운 차의 안내 문구
p13() { (PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$X/w BK=$X/bk HMGDATA=$X/hd KP_HMG=$T/app/hmgapi SDIO=$X/nosdio PROG=$X/prog sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$X'/bin:'$T'/bin:/usr/bin:/bin:/sbin; '"$1"'; P_ON=1; setup_hmgapi') > $X/out 2>&1; }
# 지도·모드를 넣은 뒤 차주가 모드만 지운 상태(다음 부팅). 모드 담당이 zip을 바꿔도 이 검사가 흔들리지 않게 MOD_MD5를 지금 zip에 맞춘다
asreset; as > /dev/null 2>&1; rm -rf "${X:?}"/hd/mods/wireless-carplay-aa; rm -f $X/prog
p13 'set -- $(md5 -q $KP_HMG/$MOD_ID.zip); MOD_MD5=$1'
check "1.7.2 P-13: 지운 기록(mod.tried)이 있고 모드가 없으면 '지운 기록이 있어 다시 넣지 않습니다'와 다시 쓰는 방법(넣지 못했습니다 아님)" 'grep -q "^stage=무선 모드가 지워진 기록이 있어 다시 넣지 않습니다(HMG-API 앱에서 지웠거나 HMG-API를 다시 설치한 경우). 다시 쓰려면 NEMESIS에서 Korea Projection을 삭제하고 다시 설치" $X/prog && ! grep -q "넣지 못했습니다" $X/prog && grep -q "지운 기록(mod.tried)" $X/out'
rm -f $X/prog; p13 'MOD_MD5=00000000000000000000000000000000'
check "  zip md5가 달라 mod.tried가 남은 경우는 예전 문구(넣지 못했습니다)" 'grep -q "^stage=무선 모드를 넣지 못했습니다" $X/prog'
rm -f $X/bin/svc $X/bin/am
# car_in: 차 목록 비교 (case 패턴은 변수로 '|'를 넘길 수 없어 목록을 하나씩 본다)
cin() { (HOTSPOT_LIB=1 BB=$T/bin/bb W=$X/w sh -c '. '$T'/app/svc/hotspot.sh; car_in "$1" "$CARS"' _ "$1"); }
check "car_in: 한국 차는 모두 맞고(자동 시험 포함), 해외 차·빈 값은 아님" 'cin DEPEHEV.KOR.0000.V039.001.260902 && cin DN822HEV.KOR.0000.V039.001.260902 && cin DN822HEV.KOR.0000.V039.001.260101 && cin TESTX.KOR.0000.V001.001.250101 && ! cin DEPEHEV.USA.0000.V039.001.260902 && ! cin CVEV.USA.0000.V039.001.260507 && ! cin ""'
cin2() { (HOTSPOT_LIB=1 BB=$T/bin/bb W=$X/w sh -c '. '$T'/app/svc/hotspot.sh; car_in "$1" "$CARS_OK $CARS_TRY"' _ "$1"); }
check "  목록(확인·시험 지원)은 니로·쏘나타 260902만" 'cin2 DEPEHEV.KOR.0000.V039.001.260902 && cin2 DN822HEV.KOR.0000.V039.001.260902 && ! cin2 DN822HEV.KOR.0000.V039.001.260101 && ! cin2 TESTX.KOR.0000.V001.001.250101'
rm -rf $X/cwd; mkdir -p $X/cwd; : > $X/cwd/DEPEHEV.KOR.x.260902
check "  현재 폴더에 패턴과 맞는 파일이 있어도 목록을 글자 그대로 비교" '(cd $X/cwd && cin DEPEHEV.KOR.0000.V039.001.260902)'
check "  set -f 상태를 되돌림 (꺼져 있었으면 꺼짐, 켜져 있었으면 켜짐)" '(HOTSPOT_LIB=1 BB=$T/bin/bb W=$X/w sh -c ". $T/app/svc/hotspot.sh; car_in x \"\$CARS\"; case \$- in *f*) exit 1 ;; esac; set -f; car_in x \"\$CARS\"; case \$- in *f*) exit 0 ;; esac; exit 1")'
rm -rf $X/cwd
# try_ready: 시험 지원 차는 무선 모드가 설치·켜짐일 때만 핫스팟 시작 (확인된 차는 항상)
tr_() { (HOTSPOT_LIB=1 BB=$T/bin/bb W=$X/w HMGDATA=$X/hd sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$T'/bin:/usr/bin:/bin; try_ready "$1"' _ "$1"); }
asreset
check "try_ready: 니로는 모드가 없어도 시작, 쏘나타는 모드가 없으면 대기" 'tr_ DEPEHEV.KOR.0000.V039.001.260902 && ! tr_ DN822HEV.KOR.0000.V039.001.260902'
mkdir -p $X/hd/mods/wireless-carplay-aa; echo '{}' > $X/hd/mods/wireless-carplay-aa/mod.json
check "  쏘나타: 모드가 설치·켜짐이어도 적용 전(persist.sys.iap2.wifi≠t)이면 대기" '! tr_ DN822HEV.KOR.0000.V039.001.260902'
echo t > $T/iap2
check "  쏘나타·자동 시험 차: 모드가 적용되면(persist.sys.iap2.wifi=t) 시작" 'tr_ DN822HEV.KOR.0000.V039.001.260902 && tr_ TESTX.KOR.0000.V001.001.250101'
: > $X/hd/mods/wireless-carplay-aa/.disabled
check "  쏘나타: 모드를 꺼 두었으면 대기" '! tr_ DN822HEV.KOR.0000.V039.001.260902'
rm -f $T/iap2
check "서비스: 시험 지원 차 대기 반복은 try_ready로 끝남 (sleep 60 + wait)" 'grep -q "while ! try_ready \"\$prod\"; do sleep 60 & wait \$!; done" $T/app/svc/hotspot.sh'

# --- 1.5.5: Wi-Fi 잠금 (설정 파일 root 소유 + crc32 치움, 니로에서 검증된 상태) ---
WF=$T/wf; mkdir -p $WF/bin
# svc wifi enable은 (설정 파일이 없으면) Wi-Fi 서비스처럼 system:wifi 소유 파일과 crc32를 만든다
cat > $WF/bin/svc <<E
#!/bin/sh
echo "svc \$*" >> $WF/calls
if [ "\$2" = enable ] && [ ! -f $WF/wifi/wpa_supplicant.conf ]; then
  echo "ctrl_interface=wlan0" > $WF/wifi/wpa_supplicant.conf; echo 1000:1010 > $WF/wifi/wpa_supplicant.conf.owner
  echo crc > $WF/wifi/wpa_supplicant_crc32.conf; echo 1000:1010 > $WF/wifi/wpa_supplicant_crc32.conf.owner
fi
E
printf '#!/bin/sh\necho "killall $*" >> %s/calls\n' $WF > $WF/bin/killall
printf '#!/bin/sh\necho "$*" >> %s/toasts\n' $WF > $WF/bin/am
printf '#!/bin/sh\ncat %s/ps 2>/dev/null\n' $WF > $WF/bin/ps
cat > $WF/bin/chown <<E
#!/bin/sh
echo "chown \$*" >> $WF/calls
echo "\$1" > "\$2.owner"
E
cat > $WF/bin/ls <<E
#!/bin/sh
if [ "\$1" = -ln ]; then
  case "\$2" in $WF/*)
    [ -e "\$2" ] || exit 1
    o=\$(cat "\$2.owner" 2>/dev/null || echo 0:0); echo "-rw-rw----    1 \${o%%:*}        \${o#*:}              88 Nov  2 17:25 \$2"; exit 0 ;;
  esac
fi
exec /bin/ls "\$@"
E
chmod +x $WF/bin/*
WC=$WF/wifi/wpa_supplicant.conf; WR=$WF/wifi/wpa_supplicant_crc32.conf
wfreset() { rm -rf $WF/calls $WF/toasts $WF/bk $WF/w $WF/wlan0 $WF/out $WF/ps $WF/wifi $WF/prog; mkdir -p $WF/bk $WF/w $WF/wifi $WF/wlan0; }
wfsys() { echo "ctrl_interface=wlan0" > $WC; echo 1000:1010 > $WC.owner; echo crc > $WR; echo 1000:1010 > $WR.owner; }
wf() { (PATH=$WF/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 NOTICE=$WF/toasts BB=$T/bin/bb W=$WF/w BK=$WF/bk WLAN=$WF/wlan0 WCONF=$WC WIFI_WAIT=0 PROG=$WF/prog BOOT_ID=$WF/bootid sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$WF'/bin:'$T'/bin:/usr/bin:/bin:/sbin; sleep() { :; }; wait() { exit 7; }; '"$1") > $WF/out 2>&1; echo $? >> $WF/out; }
wfreset; wfsys; wf 'wifi_lock; echo rc=$?'
check "Wi-Fi 잠금: system:wifi 설정 파일을 root 소유(660)로, crc32 파일은 백업 뒤 치움, 원래 소유자 기록" '[ "$(cat $WC.owner)" = 0:0 ] && [ ! -e $WR ] && [ "$(cat $WF/bk/wpaconf.orig)" = "1000:1010 660" ] && [ "$(cat $WF/bk/wpacrc.bak)" = crc ] && grep -qx "rc=0" $WF/out && grep -q "Wi-Fi 잠금: 설정 파일을 root 소유로" $WF/out'
wfsys; wf 'wifi_lock; echo rc=$?'
check "  Wi-Fi 서비스가 파일을 새로 만들어도 다시 잠그고, 원래 기록은 덮어쓰지 않음" '[ "$(cat $WC.owner)" = 0:0 ] && [ ! -e $WR ] && [ "$(cat $WF/bk/wpaconf.orig)" = "1000:1010 660" ]'
wf 'wifi_lock; echo rc=$?'
check "  이미 잠겨 있으면 아무것도 하지 않음(로그 없음)" 'grep -qx "rc=0" $WF/out && ! grep -q "Wi-Fi 잠금" $WF/out'
wfreset; wf 'wifi_lock; echo rc=$?'
check "  설정 파일이 아직 없으면 1(Wi-Fi 서비스가 처음 켤 때 만든다)" 'grep -qx "rc=1" $WF/out && [ ! -e $WF/bk/wpaconf.orig ]'
wfreset; wfsys; wf 'wifi_lock; wifi_unlock'
check "  되돌리기(preun): 원래 소유자(1000:1010)와 crc32 파일(내용·소유자)" '[ "$(cat $WC.owner)" = 1000:1010 ] && [ "$(cat $WR)" = crc ] && [ "$(cat $WR.owner)" = 1000:1010 ]'
wfreset; echo "  9 1010 wpa_supplicant -iwlan0" > $WF/ps; wf 'take_wlan0'
check "take_wlan0: 파일이 없던 차는 Wi-Fi를 켠 뒤 잠그고, wpa_supplicant를 한 번 멈춤(svc wifi disable 없음)" '[ "$(sed -n 1p $WF/calls)" = "svc wifi enable" ] && [ "$(cat $WC.owner)" = 0:0 ] && grep -qx "killall wpa_supplicant" $WF/calls && ! grep -q "svc wifi disable" $WF/calls'
wfreset; wfsys; wf 'take_wlan0'
check "  파일이 있던 차는 켜기 전에 잠금" '[ "$(sed -n 1p $WF/calls)" = "chown 0:0 $WC" ] && grep -qx "svc wifi enable" $WF/calls'
# 1.7.2(P-11): 같은 부팅에서 서비스만 다시 시작(SVC_FIRST=0) + wlan0 있음 + wpa_supplicant 없음 + wifi_on=1 → Wi-Fi 켜기·대기 건너뜀
wfreset; wfsys; : > $WF/ps; wf 'SVC_FIRST=0; take_wlan0'
check "1.7.2 P-11: 같은 부팅 다시 시작이고 드라이버(wlan0)가 있고 wpa_supplicant가 없으면 svc wifi enable·대기를 건너뜀(잠금은 함)" '! grep -q "svc wifi" $WF/calls && [ "$(cat $WC.owner)" = 0:0 ] && grep -q "Wi-Fi 켜기·대기를 건너뜀" $WF/out'
wfreset; wfsys; : > $WF/ps; wf 'SVC_FIRST=1; take_wlan0'
check "  부팅 뒤 첫 시작(또는 업데이트 뒤)은 예전처럼 켬" 'grep -qx "svc wifi enable" $WF/calls'
wfreset; wfsys; echo "  9 1010 wpa_supplicant -iwlan0" > $WF/ps; wf 'SVC_FIRST=0; take_wlan0'
check "  wpa_supplicant가 돌면 건너뛰지 않음" 'grep -qx "svc wifi enable" $WF/calls'
wfreset; wfsys; rm -rf "${WF:?}"/wlan0; : > $WF/ps; wf 'SVC_FIRST=0; take_wlan0'
check "  wlan0가 없으면 건너뛰지 않음" 'grep -qx "svc wifi enable" $WF/calls'
wfreset; : > $WF/ps; wf 'SVC_FIRST=0; take_wlan0'
check "  설정 파일이 아직 없으면(Wi-Fi 서비스가 만들어야 함) 건너뛰지 않음" 'grep -qx "svc wifi enable" $WF/calls'
wfreset; wfsys; echo "  9 1010 wpa_supplicant -iwlan0" > $WF/ps; wf 'ns=0; ap_tick; ap_tick; ap_tick; ap_tick; echo ns=$ns'
check "ap_tick: 잠금을 지키고, wpa_supplicant가 다시 뜨면 멈춤. SUPP_MAX번 넘게 이어지면 한 번만 알리고 계속(그만두지 않음)" '[ "$(cat $WC.owner)" = 0:0 ] && [ "$(grep -c "^killall wpa_supplicant" $WF/calls)" = 4 ] && grep -qx "ns=4" $WF/out && [ "$(grep -c "자꾸 끊깁니다" $WF/toasts)" = 1 ] && [ -f $WF/bk/wifilock.told ] && [ "$(tail -1 $WF/out)" = 0 ]'
: > $WF/ps; wf 'ns=3; ap_tick; echo ns=$ns'
check "  wpa_supplicant가 없으면 0부터 다시 셈" 'grep -qx "ns=0" $WF/out'
echo boot-1 > $WF/bootid; wfreset; echo boot-1 > $WF/bootid; wf 'prog 40 run "지도"; P_ON=0; ptrack 90 run "안 씀"'
check "진행 기록: pct·state·stage·boot를 644로 쓰고, P_ON=0이면 ptrack은 쓰지 않음" 'grep -qx "pct=40" $WF/prog && grep -qx "state=run" $WF/prog && grep -qx "stage=지도" $WF/prog && grep -qx "boot=boot-1" $WF/prog && [ "$(stat -f %Lp $WF/prog)" = 644 ]'
wf 'prog 100 reboot "재부팅"; prog_final_this_boot && echo final=1; echo other > '$WF'/bootid; prog_final_this_boot || echo final=0'
check "  같은 부팅의 재부팅 필요·실패 기록은 '이미 끝남'으로 알아봄(다른 부팅 기록은 아님)" 'grep -qx "final=1" $WF/out && grep -qx "final=0" $WF/out'
echo boot-1 > $WF/bootid; wf 'prog 30 run "진행"; stop_all; cat '$WF'/prog'
check "  서비스가 설치 중에 멈추면 '중간에 멈춤' 실패로 남김" 'grep -qx "state=fail" $WF/prog && grep -q "중간에 멈췄습니다" $WF/prog'
wfreset; wfsys; echo bad > $WC.owner; wf 'wifi_lock; wifi_lock; wifi_lock; true'
check "  잠금 실패 로그는 부팅마다 한 번만" '[ "$(grep -c "Wi-Fi 잠금 실패" $WF/out)" = 1 ]'
check "차에 없는 printf를 busybox 없이 부르지 않음(awk 안의 printf \"%…와 주석 제외)" '[ -z "$(grep -n "printf " $PKG/svc/hotspot.sh $PKG/bin/status.sh $PKG/bin/carreport.sh $PKG/scripts/post.sh $PKG/scripts/preun.sh $B/scripts/kp-wifi-diag.sh $B/scripts/kp-sys-restore.sh | grep -v "BB printf" | grep -v "printf \"%" | grep -v -E "^[^:]+:[0-9]+:[[:space:]]*#")" ]'
check "서비스: 1.5.4의 'Wi-Fi 끄기' 방식은 없음(드라이버를 내려 #17에서 실패)" '! grep -q -e "svc wifi disable; _i" -e "give_up_ap" -e "WIFI_FW" $T/app/svc/hotspot.sh'
check "서비스: 트랩 뒤 대기는 sleep을 뒤에서 돌리고 wait (TERM에 바로 반응)" '! sed -n "/trap .stop_all/,\$p" $T/app/svc/hotspot.sh | grep -q "do sleep 3600; done"'

# preun: 우리가 설치한 모드만 정리
PU=$T/pu; mkdir -p $PU/bk
sed -e "s#^BB=.*#BB=$T/bin/bb#" -e "s#^BK=.*#BK=$PU/bk#" -e "s#/data/nemesis/apps/korea.projection/svc/hotspot.sh#$T/app/svc/hotspot.sh; export PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin#" \
  -e "s#^export PATH=.*#export PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin#" -e "s#^STAGE=.*#STAGE=$PU/stage#" \
  -e "s#/data/local/tmp/korea-projection-status#$PU/status#g" $T/app/scripts/preun.sh > $PU/preun.sh
pureset() { rm -rf $PU/bk $X/calls $T/toast $X/hd; mkdir -p $PU/bk $X/hd/mods/wireless-carplay-aa; echo '{"system": [{"region": "KOR"}]}' > $X/hd/mods/wireless-carplay-aa/mod.json; }
pu() { (HMGDATA=$X/hd W=$PU/w sh $PU/preun.sh) > $PU/out 2>&1; }
pureset; : > $PU/bk/mod.ours; printf '%s\n' "restore  /system/onebin/depehev_kr/featurexml.cfg (stock)" "setting  prop/persist.sys.iap2.wifi back to stock" > $X/plan; pu
check "삭제: 우리가 설치한 모드는 remove → 계획이 되돌리기뿐 → 적용, 삭제 출력에 알림(1.7.1: 토스트 없음, 알림 기록도 지움)" 'grep -qx "hmgapid engine remove wireless-carplay-aa" $X/calls && grep -qx "hmgapid engine apply" $X/calls && grep -q "무선 모드도 지웠습니다" $PU/out && [ ! -f $T/toast ]'
pureset; pu
check "  원래 있던 모드(mod.ours 없음)는 건드리지 않음" '! grep -q "engine remove" $X/calls && [ -f $X/hd/mods/wireless-carplay-aa/mod.json ]'
pureset; : > $PU/bk/mod.ours; echo "$FMJ" > $X/hd/mods/wireless-carplay-aa/mod.json; pu
check "  1.6.1: mod.ours가 남아 있어도 지금 모드가 한국 차 빌드가 아니면(차주가 넣은 기본판) 지우지 않음" '! grep -q "engine remove" $X/calls && [ "$(cat $X/hd/mods/wireless-carplay-aa/mod.json)" = "$FMJ" ]'
pureset; : > $PU/bk/mod.ours; printf '%s\n' "restore  /system/x (stock)" "change   /system/app/Y.apk [other-mod] -> 1" > $X/plan; pu
check "  계획에 다른 변경이 있으면 지우기만 하고 적용은 앱에서 하라고 안내" 'grep -q "engine remove" $X/calls && ! grep -qx "hmgapid engine apply" $X/calls && grep -q "HMG-API 앱에서 변경 사항을 적용" $PU/out'
pureset; : > $PU/bk/mod.ours; mkdir -p $PU/stage; echo "id=korea.projection" > $PU/stage/NEMESIS.data; pu; rm -rf $PU/stage
check "  업데이트 중(staging에 새 버전)에는 모드를 지우지 않음" '! grep -q "engine remove" $X/calls'
pureset; echo "1000:1010 660" > $PU/bk/wpaconf.orig; mkdir -p $PU/wifi; echo x > $PU/wifi/c.conf; echo 0:0 > $PU/wifi/c.conf.owner; rm -f $T/calls
cp $WF/bin/chown $X/bin/chown; (HMGDATA=$X/hd W=$PU/w WCONF=$PU/wifi/c.conf sh $PU/preun.sh) > $PU/out 2>&1; rm -f $X/bin/chown
check "삭제: Wi-Fi 잠금을 원래 소유자로 되돌림" '[ "$(cat $PU/wifi/c.conf.owner)" = 1000:1010 ] && grep -q "Wi-Fi 잠금 되돌림" $PU/out'
# 1.6.0: busybox 없는 내비에서 busybox를 함께 넣지 않은 버전(1.5.x)으로 바꾸면 업데이트 중에도 잠금을 되돌림
pureset; echo "1000:1010 660" > $PU/bk/wpaconf.orig; echo 0:0 > $PU/wifi/c.conf.owner; mkdir -p $PU/stage; echo "id=korea.projection" > $PU/stage/NEMESIS.data
cp $WF/bin/chown $X/bin/chown; (HMGDATA=$X/hd W=$PU/w WCONF=$PU/wifi/c.conf sh $PU/preun.sh) > $PU/out 2>&1
check "  1.6.0: busybox 없는 버전으로 내릴 때(업데이트)는 잠금을 되돌리고 기록은 남김" '[ "$(cat $PU/wifi/c.conf.owner)" = 1000:1010 ] && grep -q "busybox 없는 버전으로 바꿈" $PU/out && [ -f $PU/bk/wpaconf.orig ]'
echo 0:0 > $PU/wifi/c.conf.owner; mkdir -p $PU/stage/bin; : > $PU/stage/bin/busybox
(HMGDATA=$X/hd W=$PU/w WCONF=$PU/wifi/c.conf sh $PU/preun.sh) > $PU/out 2>&1; rm -f $X/bin/chown; rm -rf $PU/stage
check "    새 버전에 busybox가 있으면(보통 업데이트) 잠금을 그대로 둠" '[ "$(cat $PU/wifi/c.conf.owner)" = 0:0 ] && ! grep -q "잠금 되돌림" $PU/out'
pureset; echo null > $PU/bk/wifi_on; rm -f $T/calls; pu
check "삭제: 설치 전 Wi-Fi 값이 null(한 번도 안 켬)이면 Wi-Fi를 끔" 'grep -qx "svc wifi disable" $T/calls'
pureset; echo 1 > $PU/bk/wifi_on; rm -f $T/calls; pu
check "  설치 전에 켜져 있었으면 끄지 않음" '! grep -q "svc wifi disable" $T/calls 2>/dev/null'
pureset; rm -f $T/calls; pu
check "  설치 전 기록이 없으면 끄지 않음" '! grep -q "svc wifi disable" $T/calls 2>/dev/null'
printf '#!/bin/sh\necho "settings $*" >> %s/calls\ncat %s/wifiset\n' $T $X > $X/bin/settings; chmod +x $X/bin/settings
pureset; echo 1 > $PU/bk/wifi_on; echo 0 > $X/wifiset; rm -f $T/calls; pu
check "  설치 전에 켜져 있었는데 지금 wifi_on이 0이면(Wi-Fi 서비스 차) 값만 1로 되돌림" 'grep -qx "settings put global wifi_on 1" $T/calls && ! grep -q "svc wifi" $T/calls'
pureset; echo 1 > $PU/bk/wifi_on; echo 1 > $X/wifiset; rm -f $T/calls; pu
check "  지금도 1이면 건드리지 않음" '! grep -q "settings put" $T/calls 2>/dev/null'
pureset; echo null > $PU/bk/wifi_on; echo 0 > $X/wifiset; rm -f $T/calls; pu
check "  설치 전에 꺼져 있었으면 1로 바꾸지 않음" '! grep -q "settings put" $T/calls 2>/dev/null'
rm -f $X/bin/settings $X/wifiset
pureset; : > $PU/bk/mod.ours; touch $X/down; pu; rm -f $X/down
check "  HMG-API 데몬이 응답하지 않으면 지우지 못하니 앱에서 지우라고 안내" '! grep -q "engine remove" $X/calls && grep -q "HMG-API 앱에서 무선 모드" $PU/out'
rm -f $T/toast

# --- 1.7.2(P-14): 삭제할 때 우리가 쓴 무선 권한 파일과 featurexml 무선 줄(17·18) 되돌리기(perms_revert) ---
PR=$T/pr; mkdir -p $PR/bin
CPN_=com.hkmc.software.connectivity.carplay_wireless; AAN_=com.hkmc.software.connectivity.androidauto_wireless
cat > $PR/bin/hmgapid <<E
#!/bin/sh
echo "hmgapid \$*" >> $PR/calls
case "\$*" in
  ping) [ -f $PR/down ] && exit 1; exit 0 ;;
  "engine status") [ -f $PR/down ] && exit 1; [ -f $PR/status ] && { cat $PR/status; exit 4; }; echo "HMG-API owns no files"; exit 0 ;;
  "remount rw") [ -f $PR/rmfail ] && exit 1; echo "/dev/block/system /system ext4 rw,relatime 0 0" > $PR/mounts ;;
  "remount ro") echo "/dev/block/system /system ext4 ro,relatime 0 0" > $PR/mounts ;;
esac
exit 0
E
cat > $PR/bin/nemesis <<E
#!/bin/sh
echo "nemesis \$*" >> $PR/calls
case "\$*" in
  "remount rw") [ -f $PR/rmfail ] && exit 1; [ -f $PR/nemfail ] && exit 1; [ -f $PR/nemnoop ] && exit 0; echo "/dev/block/system /system ext4 rw,relatime 0 0" > $PR/mounts ;;
  "remount ro") echo "/dev/block/system /system ext4 ro,relatime 0 0" > $PR/mounts ;;
esac
exit 0
E
# busybox 대신: featurexml 바꾸기(mv)만 실패하게 할 수 있다
printf '#!/bin/sh\nif [ "$1" = mv ] && [ -f %s/mvfail ]; then case "$*" in *featurexml.cfg) exit 1 ;; esac; fi\nexec "$@"\n' $PR > $PR/bb
# 맥의 chown은 /usr/sbin에 있다(차의 busybox chown 대신)
printf '#!/bin/sh\nexec /usr/sbin/chown "$@"\n' > $PR/bin/chown
chmod +x $PR/bin/* $PR/bb
# 순정 꼴(CRLF, 21줄, 12번째 wifihotspot·17·18번째 무선 2개가 "-…")과, 지금 차 꼴(세 줄 모두 "#-…")
python3 - $PR/stock.cfg $PR/now.cfg $PR/want.cfg <<'E'
import sys
n=["com.hkmc.hardware.ev"]*11+["com.hkmc.software.wifihotspot"]+["com.hkmc.software.sml"]*4+["com.hkmc.software.connectivity.carplay_wireless","com.hkmc.software.connectivity.androidauto_wireless"]+["com.mobis.software.findmyvehicle"]*3
L=[b"-/system/etc/permissions/"+x.encode()+b".xml" for x in n]
open(sys.argv[1],'wb').write(b"\r\n".join(L)+b"\r\n")
N=list(L); N[11]=b"#"+N[11]; N[16]=b"#"+N[16]; N[17]=b"#"+N[17]
open(sys.argv[2],'wb').write(b"\r\n".join(N)+b"\r\n")
W=list(N); W[16]=L[16]; W[17]=L[17]
open(sys.argv[3],'wb').write(b"\r\n".join(W)+b"\r\n")
E
ptext() { printf '<permissions>\n    <feature name="%s" />\n</permissions>\n' "$1"; }
prreset() {
  rm -rf $PR/perms $PR/bk $PR/logs $PR/onebin $PR/wp $PR/calls $PR/status $PR/down $PR/rmfail $PR/nemfail $PR/nemnoop $PR/mvfail
  mkdir -p $PR/perms $PR/bk $PR/logs $PR/onebin/depehev_kr
  ptext $CPN_ > $PR/perms/$CPN_.xml; ptext $AAN_ > $PR/perms/$AAN_.xml; chmod 644 $PR/perms/*.xml
  printf '%s\n' $CPN_ $AAN_ > $PR/bk/perms.ours
  cp $PR/now.cfg $PR/onebin/depehev_kr/featurexml.cfg; chmod 644 $PR/onebin/depehev_kr/featurexml.cfg
  echo "/dev/block/system /system ext4 ro,relatime 0 0" > $PR/mounts
}
FXP=$PR/onebin/depehev_kr/featurexml.cfg
pr() { (PATH=$PR/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$PR/bb W=$PR/w BK=$PR/bk PERMS=$PR/perms MOUNTS=$PR/mounts APLOG=$PR/logs/ap.log FXML=$FXP WPDIR=$PR/wp sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$PR'/bin:'$T'/bin:/usr/bin:/bin:/sbin; perms_revert; echo "rc=$?"') > $PR/out 2>&1; }
prsame() { cmp -s $FXP $PR/now.cfg && [ -f $PR/perms/$CPN_.xml ] && [ -f $PR/perms/$AAN_.xml ] && [ "$(md5 -q $PR/perms/$CPN_.xml)" = 95ff801a064526de56059dba10960b05 ] && [ "$(md5 -q $PR/perms/$AAN_.xml)" = fa91812d3eeee415768018ab6ee6804a ]; }
prreset; pr
check "1.7.2 P-14 삭제 되돌리기: 우리가 쓴 권한 파일 2개를 지우고, featurexml은 17·18번째 줄의 '#'만 뗌(12번째 wifihotspot은 그대로, CRLF 그대로)" 'grep -qx "rc=0" $PR/out && [ ! -e $PR/perms/$CPN_.xml ] && [ ! -e $PR/perms/$AAN_.xml ] && cmp -s $FXP $PR/want.cfg && [ "$(wc -c < $FXP | tr -d " ")" = $(( $(wc -c < $PR/now.cfg) - 2 )) ] && sed -n 12p $FXP | grep -q "^#-.*wifihotspot.xml.$"'
check "  /system: nemesis remount rw → ro, 권한·소유자 그대로(644), ap.log에 이름만 기록" 'grep -qx "nemesis remount rw" $PR/calls && grep -qx "nemesis remount ro" $PR/calls && ! grep -q "hmgapid remount" $PR/calls && [ "$(stat -f %Lp $FXP)" = 644 ] && grep -q "무선 권한 파일 원래대로(없음): $CPN_" $PR/logs/ap.log && grep -q "featurexml 무선 줄 원래대로" $PR/logs/ap.log && [ -z "$(ls $PR/onebin/depehev_kr | grep -v "^featurexml.cfg$")" ] && [ ! -e $PR/bk/fx.new ] && [ ! -e $PR/bk/fx.orig ]'
prreset; touch $PR/nemfail; pr
check "  nemesis remount가 안 되면 hmgapid remount로" 'grep -qx "rc=0" $PR/out && grep -qx "hmgapid remount rw" $PR/calls && [ ! -e $PR/perms/$CPN_.xml ]'
prreset; touch $PR/nemnoop; pr
check "  nemesis remount가 0을 돌려줘도 ro로 남으면 hmgapid remount로(리뷰 M4)" 'grep -qx "rc=0" $PR/out && grep -qx "hmgapid remount rw" $PR/calls && [ ! -e $PR/perms/$CPN_.xml ]'
prreset; rm -f $PR/bk/perms.ours; pr
check "  기록이 없으면(백업 없음) 아무것도 바꾸지 않고 remount도 안 함" 'grep -qx "rc=0" $PR/out && prsame && ! grep -q remount $PR/calls 2>/dev/null'
prreset; rm -f $PR/bk/perms.ours; printf '%s\n' "11-07 01:21:49 서비스 시작" "11-07 01:24:00 권한 파일 되돌림: $CPN_" "11-07 01:24:00 권한 파일 되돌림: $AAN_" "11-07 01:24:01 권한 파일 되돌림: ../../etc/x" > $PR/logs/ap.log.1; pr
check "  1.7.1까지 설치한 차(기록 없음): ap.log의 '권한 파일 되돌림' 줄로 찾아 되돌림, 이상한 이름은 버림" 'grep -qx "rc=0" $PR/out && [ ! -e $PR/perms/$CPN_.xml ] && [ ! -e $PR/perms/$AAN_.xml ] && cmp -s $FXP $PR/want.cfg'
prreset; echo "<permissions>other</permissions>" > $PR/perms/$CPN_.xml; pr
check "  다른 쪽이 내용을 바꾼 파일은 두고(그 featurexml 줄도 그대로), 우리 것 그대로인 파일만 되돌림" 'grep -qx "rc=0" $PR/out && [ "$(cat $PR/perms/$CPN_.xml)" = "<permissions>other</permissions>" ] && [ ! -e $PR/perms/$AAN_.xml ] && sed -n 17p $FXP | grep -q "^#-" && sed -n 18p $FXP | grep -q "^-" && grep -q "그대로 둠(내용이 바뀜): $CPN_" $PR/out'
prreset; echo "ok       $PR/perms/$CPN_.xml [wireless-carplay-aa] stock absent, expected 95ff801a064526de56059dba10960b05" > $PR/status; pr
check "  HMG-API 모드가 관리 중인 파일은 HMG-API에 맡김(그 줄도 그대로)" 'grep -qx "rc=0" $PR/out && [ -f $PR/perms/$CPN_.xml ] && [ ! -e $PR/perms/$AAN_.xml ] && sed -n 17p $FXP | grep -q "^#-" && grep -q "HMG-API 모드가 관리 중" $PR/out'
prreset; echo "CHANGED  $FXP [wireless-carplay-aa] stock c3fa, expected 2a7c, found 2a7c" > $PR/status; pr
check "  featurexml을 HMG-API가 관리 중이면 featurexml은 두고 권한 파일만" 'grep -qx "rc=0" $PR/out && cmp -s $FXP $PR/now.cfg && [ ! -e $PR/perms/$CPN_.xml ]'
prreset; touch $PR/down; pr
check "  HMG-API가 응답하지 않으면 판단할 수 없어 그대로 두고 실패(1)" 'grep -qx "rc=1" $PR/out && prsame && grep -q "HMG-API 응답 없음" $PR/logs/ap.log && ! grep -q remount $PR/calls'
prreset; touch $PR/rmfail; pr
check "  remount 실패: 아무것도 바꾸지 않고 실패(1)와 기록" 'grep -qx "rc=1" $PR/out && prsame && grep -q "/system을 쓰기로 열지 못함" $PR/logs/ap.log && [ ! -e $PR/bk/fx.new ]'
prreset; touch $PR/mvfail; pr
check "  featurexml 쓰기 실패: 지운 권한 파일을 같은 내용으로 다시 쓰고(644) featurexml 원본 그대로, ro로 되돌리고 실패(1)" 'grep -qx "rc=1" $PR/out && prsame && [ "$(stat -f %Lp $PR/perms/$CPN_.xml)" = 644 ] && grep -qx "nemesis remount ro" $PR/calls && grep -q "featurexml 쓰기 실패" $PR/logs/ap.log && [ -z "$(ls $PR/onebin/depehev_kr | grep -v "^featurexml.cfg$")" ]'
prreset; python3 -c "import sys; p=sys.argv[1]; b=open(p,'rb').read(); open(p,'wb').write(b[:-2])" $FXP; cp $FXP $PR/nonl.cfg; pr
check "  featurexml이 예상과 다르면(끝 줄바꿈 없음) featurexml은 그대로 두고 기록, 권한 파일은 되돌림" 'grep -qx "rc=0" $PR/out && cmp -s $FXP $PR/nonl.cfg && [ ! -e $PR/perms/$CPN_.xml ] && grep -q "featurexml 그대로 둠(예상과 다름" $PR/logs/ap.log'
prreset; cp $PR/stock.cfg $FXP; pr
check "  featurexml이 이미 순정(-)이면 그대로" 'grep -qx "rc=0" $PR/out && cmp -s $FXP $PR/stock.cfg && [ ! -e $PR/perms/$CPN_.xml ]'
prreset; mkdir -p $PR/wp; pr
check "  wireless.projection이 설치돼 있으면 아무것도 바꾸지 않음" 'grep -qx "rc=0" $PR/out && prsame && ! grep -q remount $PR/calls 2>/dev/null'
prreset; echo "/dev/block/system /system ext4 rw,relatime 0 0" > $PR/mounts; pr
check "  /system이 원래 rw였으면 remount하지 않고 rw로 둠" 'grep -qx "rc=0" $PR/out && ! grep -q remount $PR/calls 2>/dev/null && [ ! -e $PR/perms/$CPN_.xml ]'
prreset; echo com.hkmc.software.wifihotspot >> $PR/bk/perms.ours; pr
check "  기록에 wifihotspot이 있어도 featurexml 12번째 줄은 건드리지 않음(HMG-API 몫)" 'cmp -s $FXP $PR/want.cfg'
prreset; rm -f $PR/perms/*.xml; pr
check "  권한 파일이 이미 없으면 featurexml 무선 줄만 되돌림" 'grep -qx "rc=0" $PR/out && cmp -s $FXP $PR/want.cfg'
prreset; cp $FXP $PR/before.cfg; echo DN8HEV.KOR.0000.V010.001.260902 > $T/product; pr; rm -f $T/product
check "  재리뷰 M: 니로(CARS_OK)가 아닌 차는 우리 권한 파일만 지우고 featurexml 줄은 그대로(기록만)" 'grep -qx "rc=0" $PR/out && [ ! -e $PR/perms/$CPN_.xml ] && cmp -s $FXP $PR/before.cfg && grep -q "featurexml 그대로 둠(순정 줄을 확인한 차가 아님)" $PR/logs/ap.log'
# featurexml 경로: 차의 ro.mobis.targetdir는 끝에 "/"가 없다(니로 2026-11-09 차 복사). 있든 없든 경로가 같아야 한다
fxp() { (PATH=$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 sh -c '. '$T'/app/svc/hotspot.sh; fx_path'); }
check "  featurexml 경로: 차 값(끝 / 없음)" '[ "$(fxp)" = /system/onebin/depehev_kr/featurexml.cfg ]'
echo /system/onebin/depehev_kr/ > $T/targetdir
check "  featurexml 경로: 끝에 / 가 있어도 같음" '[ "$(fxp)" = /system/onebin/depehev_kr/featurexml.cfg ]'
: > $T/targetdir
check "  featurexml 경로: 값이 없으면 빈 값(되돌리기 건너뜀)" '[ -z "$(fxp)" ]'
rm -f $T/targetdir
mkdir -p $PR/nohm; cp $PR/bin/nemesis $PR/bin/chown $T/bin/getprop $PR/nohm/  # getprop은 차에 늘 있다(니로 확인용)
prreset; (PATH=$PR/nohm:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$PR/bb W=$PR/w BK=$PR/bk PERMS=$PR/perms MOUNTS=$PR/mounts APLOG=$PR/logs/ap.log FXML=$FXP WPDIR=$PR/wp sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$PR'/nohm:/usr/bin:/bin:/sbin; perms_revert; echo "rc=$?"') > $PR/out 2>&1
check "  HMG-API를 먼저 지운 차(hmgapid 없음)도 우리 것을 되돌림(니로에서 생긴 순서)" 'grep -qx "rc=0" $PR/out && [ ! -e $PR/perms/$CPN_.xml ] && cmp -s $FXP $PR/want.cfg && grep -qx "nemesis remount rw" $PR/calls'
# preun에서: 모드를 지운 뒤 되돌림, 업데이트 중에는 하지 않음, 실패하면 삭제 출력에 안내
pupr() { cp $PR/bin/chown $PR/bin/nemesis $X/bin/; (HMGDATA=$X/hd W=$PU/w PERMS=$PR/perms MOUNTS=$PR/mounts APLOG=$PR/logs/ap.log FXML=$FXP WPDIR=$PR/wp sh $PU/preun.sh) > $PU/out 2>&1; rm -f $X/bin/chown $X/bin/nemesis; }
pureset; prreset; cp $PR/bk/perms.ours $PU/bk/perms.ours; : > $PU/bk/mod.ours; printf '%s\n' "restore  /system/onebin/depehev_kr/featurexml.cfg (stock)" > $X/plan; rm -f $X/status; pupr
check "preun: 우리 모드를 지운 뒤 우리 권한 파일·featurexml 무선 줄을 되돌림, umask 077" 'grep -q "무선 권한 파일 원래대로(없음)" $PU/out && [ ! -e $PR/perms/$CPN_.xml ] && cmp -s $FXP $PR/want.cfg && [ "$(grep -n "engine remove" $PKG/scripts/preun.sh | head -1 | cut -d: -f1)" -lt "$(grep -n "^elif ! perms_revert" $PKG/scripts/preun.sh | cut -d: -f1)" ] && grep -qx "umask 077" $PKG/scripts/preun.sh'
pureset; prreset; cp $PR/bk/perms.ours $PU/bk/perms.ours; : > $PU/bk/mod.ours; printf '%s\n' "restore  /system/x (stock)" "change   /system/app/Y.apk [other-mod] -> 1" > $X/plan; pupr
check "  우리 모드를 지웠지만 적용하지 못했으면 권한 파일·featurexml을 건드리지 않음(리뷰 M3)" 'prsame && grep -q "되돌리기 건너뜀: 무선 모드 삭제가 적용되지 않음" $PU/out'
pureset; prreset; cp $PR/bk/perms.ours $PU/bk/perms.ours; touch $PR/rmfail; pupr
check "  되돌리지 못하면 그대로 두고 삭제 출력에 안내" 'prsame && grep -q "무선 기능 파일을 되돌리지 못했습니다" $PU/out'
pureset; prreset; cp $PR/bk/perms.ours $PU/bk/perms.ours; mkdir -p $PU/stage; echo "id=korea.projection" > $PU/stage/NEMESIS.data; pupr; rm -rf $PU/stage
check "  업데이트 중에는 되돌리지 않고 기록(perms.ours)을 남김" 'prsame && [ -f $PU/bk/perms.ours ]'
rm -f $T/toast

# --- 1c. 상태 화면 앱: Report(판단·제보 링크)와 QR 크기, QrCode가 HMG-API 원본과 같은지 ---
if command -v javac >/dev/null 2>&1; then
  J=$T/java; mkdir -p $J
  if javac -nowarn -encoding UTF-8 -d $J $B/nemesis-pkg/app-src/java/korea/projection/app/Report.java \
       $B/nemesis-pkg/app-src/java/korea/projection/app/QrCode.java $B/tests/ReportTest.java 2>$T/javac.err; then
    java -cp $J korea.projection.app.ReportTest > $T/java.out 2>&1
    jr=$?
    grep -E "^(ok|FAIL)" $T/java.out | sed 's/^/  [Java] /'
    check "Java 테스트 전부" '[ $jr -eq 0 ]'
  else
    cat $T/javac.err; check "Java 컴파일" 'false'
  fi
  UP=$B/pr22-rebase/core/app/java/hmgapi/app/QrCode.java
  if [ -f $UP ]; then
    check "QrCode.java는 HMG-API 원본과 package 줄만 다름" '[ "$(sed 1,4d $B/nemesis-pkg/app-src/java/korea/projection/app/QrCode.java | sed 1d | md5sum)" = "$(sed 1d $UP | md5sum)" ]'
  fi
fi

# --- 1d. 상태 화면 앱 설치: 읽을 수 있는 곳에 복사해 직접 설치, 실패해도 패키지는 그대로 ---
IA=$T/ia; mkdir -p $IA/bin $IA/w $IA/tmp; echo apk > $IA/src.apk
cat > $IA/bin/pm <<E
#!/bin/sh
echo "pm \$*" >> $IA/calls
case "\$1" in
  install) echo "	pkg: \$3"; if [ -f $IA/ok ]; then echo Success; else echo "Failure [INSTALL_FAILED_INVALID_URI]"; fi ;;
  path) [ -f $IA/ok ] && echo package:/data/app/korea.projection.app-1.apk ;;
esac
exit 0
E
printf '#!/bin/sh\ncat %s/boot 2>/dev/null || echo 1\n' $IA > $IA/bin/getprop
printf '#!/bin/sh\necho "setprop $*" >> %s/calls; echo "$2" > %s/boot\n' $IA $IA > $IA/bin/setprop
chmod +x $IA/bin/*
ia() { (PATH=$IA/bin:/usr/bin:/bin HOTSPOT_LIB=1 BB=$T/bin/bb W=$IA/w APK_SRC=$IA/src.apk APK_COPY=$IA/tmp/kp.apk sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$IA'/bin:/usr/bin:/bin; install_app; echo "rc=$?"'); }
out=$(ia)
check "앱 설치 실패 → 1 돌려주고 기록, boot_completed는 1로 되돌림" 'echo "$out" | grep -q "rc=1" && grep -q "INVALID_URI" $IA/w/app-install.log && [ "$(cat $IA/boot)" = 1 ] && grep -q "setprop sys.boot_completed 0" $IA/calls'
check "  pm에는 읽을 수 있는 복사본(644)을 줌" 'grep -q "pm install -r $IA/tmp/kp.apk" $IA/calls && [ "$(stat -f %Lp $IA/tmp/kp.apk)" = 644 ]'
touch $IA/ok; rm -f $IA/calls; out=$(ia)
check "앱 설치 성공 → 0, 복사본 지움" 'echo "$out" | grep -q "rc=0" && [ ! -f $IA/tmp/kp.apk ]'
check "  app_installed는 pm path 출력으로 판단" '(PATH=$IA/bin:/usr/bin:/bin HOTSPOT_LIB=1 BB=$T/bin/bb W=$IA/w sh -c ". $T/app/svc/hotspot.sh; export PATH=$IA/bin:/usr/bin:/bin; app_installed")'

# --- 1e. 디버그 로그: 잡음 줄 버리기, 연속 같은 줄 줄이기, 파이프를 멈추지 않고 밀어내기 ---
LG=$T/lg; mkdir -p $LG/bin $LG/w
cat > $LG/in.txt <<'E'
11-06 04:25:55.900 D/ClusterService(  705): updateTPCrossroadName()::crossroadname is TEST-RD
11-06 04:25:55.910 D/ClusterService(  705): getCANSTatus = true
11-06 04:25:55.920 I/TccCarPlay( 1087):  [TccCarPlay] TccCarPlay_iAPSendMessage() : data(0x5F862158) size(57)
11-06 04:25:55.930 I/TccCarPlay( 1087):  [TccCarPlayCBSession] iAPSendMessage Command Received
11-06 04:25:55.935 I/TccCarPlay( 1087):  [TccCarPlay] TccCarPlay_iAPSendMessage() : done with (0x00)
11-06 04:25:55.937 I/TccCarPlay( 1087):  [TccCarPlay] TccCarPlay_iAPSendMessage() : done with (0x01)
11-06 04:25:55.940 D/NavigationCluster( 1305): getCANStatus
11-06 04:25:55.945 D/NavigationCluster( 1305): updateTBTSubInfo() distance: 0.0 unit: 15
11-06 04:25:55.950 E/iAP2    ( 1085):  iAP2SessionPacketParseParamListNew(1221) (LocationInformationStart) invalid parameter =0
11-06 04:25:56.040 I/TccCarPlay( 1087):  [TccCarPlayAudioTinyALSA] TccCarPlayAudioTinyALSA_ThreadPlayback() : pcm_write failed retry(0)
11-06 04:25:56.050 I/TccCarPlay( 1087):  [TccCarPlayAudioTinyALSA] TccCarPlayAudioTinyALSA_ThreadPlayback() : pcm_write failed retry(0)
11-06 04:25:57.120 I/TccCarPlay( 1087):  [TccCarPlayAudioTinyALSA] TccCarPlayAudioTinyALSA_ThreadPlayback() : pcm_write failed retry(0)
11-06 04:25:57.200 I/OtherApp( 999): not ours
11-06 04:25:58.000 I/HMG-API ( 800): CarPlay: hud list type 72 next 0
E
cat $B/tests/kpmask-sample.txt >> $LG/in.txt
printf '#!/bin/sh\ncat %s/in.txt\n' $LG > $LG/bin/logcat
printf '#!/bin/sh\n[ "$1" = uniq ] && exit 1\nexec "$@"\n' > $LG/bin/bb-nouniq
chmod +x $LG/bin/*
lg() { (PATH=$LG/bin:/usr/bin:/bin HOTSPOT_LIB=1 BB=${1:-$T/bin/bb} W=$LG/w sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$LG'/bin:/usr/bin:/bin; logstart; wait'); }
rm -f $LG/w/*; lg
check "디버그 파일이 없으면 로그를 켜지 않음" '[ ! -f $LG/w/cp.log ] && [ ! -f $LG/w/log.pid ]'
: > $LG/w/debug; lg
check "잡음 줄(iAPSendMessage 확인 줄, getCANSTatus, getCANStatus, 교차로 이름)과 다른 태그는 버림" '! grep -q -E "Command Received|done with \(0x00\)|getCANSTatus|getCANStatus|crossroadname|OtherApp" $LG/w/cp.log'
check "  전송 실패(done with 0x01)는 남김" 'grep -q "done with (0x01)" $LG/w/cp.log'
check "  보낸 iAPSendMessage 줄(크기)은 남김 (위치 전송 확인용)" 'grep -q "iAPSendMessage() : data(0x5F862158) size(57)" $LG/w/cp.log'
check "  iAP2 태그(위치 요청)와 getCANStatus로 시작하지 않는 NavigationCluster 줄은 남김" 'grep -q "LocationInformationStart" $LG/w/cp.log && grep -q "updateTBTSubInfo" $LG/w/cp.log'
check "  HMG-API 줄은 남김" 'grep -q "hud list type 72" $LG/w/cp.log'
check "  1.7.0: 폰 프로젝션 줄(AAProjection·PhoneProjection)을 남기되 폰 이름·MAC·다른 IP는 가림" 'grep -q "isWifiApEnable = false, mode = 0" $LG/w/cp.log && grep -q "requestWLDeviceConnectStatusUpdate \[가림: 이름\]" $LG/w/cp.log && ! grep -q -E "홍길동|Fold7|Pixel7|GalaxyS24|MyPhone|MyNet|secret|AA:BB|10\.0\.0\.5" $LG/w/cp.log'
check "  연속된 pcm_write 3줄은 한 줄과 횟수 3으로" '[ $(grep -c pcm_write $LG/w/cp.log) -eq 1 ] && grep -q -E "^ *3 11-06 04:25:56.040 .*pcm_write" $LG/w/cp.log'
rm -f $LG/w/cp.log*; lg $LG/bin/bb-nouniq
check "uniq를 못 쓰면 줄이지 않고 그대로 남김(로그가 끊기지 않음)" '[ $(grep -c pcm_write $LG/w/cp.log) -eq 3 ] && ! grep -q getCANSTatus $LG/w/cp.log'
printf '#!/bin/sh\n[ "$1" = grep ] && [ "$2" = -E ] && case "$3" in *getCANSTatus*) exit 2;; esac\n[ "$1" = grep ] && [ "$2" = -v ] && case "$4" in *getCANSTatus*) exit 2;; esac\nexec "$@"\n' > $LG/bin/bb-badre; chmod +x $LG/bin/bb-badre
rm -f $LG/w/cp.log*; lg $LG/bin/bb-badre
check "DROP 정규식을 grep이 못 받으면 버리지 않고 그대로 남김(로그가 끊기지 않음)" 'grep -q "hud list type 72" $LG/w/cp.log && grep -q getCANSTatus $LG/w/cp.log'
lr() { (HOTSPOT_LIB=1 BB=$T/bin/bb W=$LG/w LOGMAX=100 sh -c '. '$T'/app/svc/hotspot.sh; logrotate'); }
rm -f $LG/w/cp.log*; /bin/sleep 30 >/dev/null 2>&1 & SP=$!; echo $SP > $LG/w/log.pid
printf '%0200d\n' 1 > $LG/w/cp.log; lr
check "LOGMAX를 넘으면 cp.log.1로 복사하고 cp.log를 비움" '[ -s $LG/w/cp.log.1 ] && [ ! -s $LG/w/cp.log ] && [ -f $LG/w/cp.log ]'
check "  밀어낼 때 로그 파이프를 멈추지 않음" 'kill -0 $SP 2>/dev/null && [ "$(cat $LG/w/log.pid)" = $SP ]'
echo small > $LG/w/cp.log; lr
check "  LOGMAX 아래면 그대로" '[ "$(cat $LG/w/cp.log)" = small ] && [ ! -f $LG/w/cp.log.2 ]'
for i in 2 3 4 5; do printf "%0200d\n" $i > $LG/w/cp.log; lr; done
check "  최대 4개(cp.log, .1~.3)만 남고 오래된 것부터 지워짐" '[ ! -f $LG/w/cp.log.4 ] && grep -q 5$ $LG/w/cp.log.1 && grep -q 3$ $LG/w/cp.log.3'
printf '#!/bin/sh\n[ "$1" = cp ] && { echo partial > "$4"; exit 1; }\nexec "$@"\n' > $LG/bin/bb-nocp; chmod +x $LG/bin/bb-nocp
printf '%0200d\n' 7 > $LG/w/cp.log; (HOTSPOT_LIB=1 BB=$LG/bin/bb-nocp W=$LG/w LOGMAX=100 sh -c '. '$T'/app/svc/hotspot.sh; logrotate')
check "  복사가 실패해도(공간 부족) cp.log를 비우고 반쯤 쓴 .1은 지움" '[ ! -s $LG/w/cp.log ] && [ ! -f $LG/w/cp.log.1 ]'
echo live > $LG/w/cp.log; exec 9>>$LG/w/cp.log; printf '%0200d\n' 8 >&9; lr; echo after >&9; exec 9>&-
check "  열린 채 이어 쓰는 중에 비워도(O_APPEND) 새 줄이 맨 앞부터 이어짐" '[ "$(cat $LG/w/cp.log)" = after ] && grep -q 8$ $LG/w/cp.log.1'
kill $SP 2>/dev/null; wait $SP 2>/dev/null; rm -f $LG/w/log.pid; printf '%0200d\n' 9 > $LG/w/cp.log; lr
check "  로그가 꺼져 있으면(log.pid 없음) 밀어내지 않음" 'grep -q 9$ $LG/w/cp.log'

# --- 2. status.sh: 리포트, 비밀 미포함, USB 마운트 확인 ---
# 이 구역의 리포트는 Android Wi-Fi 기능이 없는 차로 만든다(wifi.direct만 있음: 둘을 헷갈리지 않는지 본다)
touch $T/nowififeat
fixpath $PKG/bin/status.sh | sed -e "s#/storage/usb0 /storage/usb1#$T/usb0#" \
  -e "s#/proc/mounts#$T/mounts#" -e "s#/data/nemesis/logs/korea.projection/ap.log#$T/logs/ap.log#" > $T/st.sh
STF=$T/status.txt
echo "  101 root  hostapd /data/misc/wifi/hostapd-kp.conf" > $T/ps
: > $T/mounts; printf 'pct=100\nstate=done\nstage=old\n' > $RPROG
STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null
check "USB가 마운트 안 됐으면 USB에 쓰지 않고 토스트도 없음 (상태는 화면이 보여 줌)" '[ ! -d $T/usb0/KoreaProjection-report ] && [ ! -f $T/toast ]'
check "  1.7.0: USB가 없으면 지난 저장 기록(RPROG)을 지움(화면에 지난 '완료'가 다시 안 보이게, 리뷰 L1)" '[ ! -f $RPROG ]'
check "  1.7.0: 로그 모으기는 한 번에 하나(--wait도 collect.pid), carreport 잠금이 남으면 풀릴 때까지 기다린 뒤 완료(리뷰 M1)" 'grep -q "^  collect_alive && return 0" $PKG/bin/status.sh && grep -q "while \[ -d \$W/carreport.lock \] && \[ \$_lw -lt 210 \]" $PKG/bin/status.sh'
echo "/dev/block/sda1 $T/usb0 vfat rw 0 0" > $T/mounts
mkdir -p $T/hl
printf '%s\n' "01-01 18:30:04.730 I/HMG-API (  148): hook map: none for Kia Niro, hooks off (no map)" "01-01 18:30:04.731 I/HMG-API (  148): mods: wireless-carplay-aa not loaded: hook point btsettings.projection_helper.open_wireless_page isn't mapped on this car (0 methods match): its hooks are off here, its other parts still apply" > $T/hl/log.log.1
printf '%s\n' "01-01 18:30:04.740 I/HMG-API (  148): hook map: mapped for Kia Niro Hybrid (kor 260902), hooks on, 1 point(s) not mapped (their features and mods are off)" "01-01 18:30:04.800 I/HMG-API (  144): mods: loaded wireless-carplay-aa 2.3.1" "11-06 09:05 I/HMG-API ( 1): other" > $T/hl/log.log
HMGLOG=$T/hl STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null
R=$T/usb0/KoreaProjection-report/1-report.md
G3=$T/usb0/KoreaProjection-report/3-log.txt
check "상태 화면용 파일: 644, 키 35개(1.6.1 mod_foreign, 1.6.2 stock_ssid·ap_mode·stock_seen, 1.7.0 state·aa·nowlan, 1.7.1 modver·mod_pending, 1.7.2 mod_hooks 추가)" '[ "$(stat -f %Lp $STF)" = 644 ] && [ "$(grep -c "=" $STF)" = 35 ] && grep -q "^modver=" $STF && grep -qx "mod_pending=no" $STF && grep -qx "nowlan=no" $STF && grep -qx "mod_foreign=no" $STF && grep -q "^state=" $STF && grep -qx "aa=yes" $STF'
check "  1.7.2: 무선 모드 훅 상태는 마지막 기록으로(앞 부팅에 거부, 이번 부팅에 켜짐 → 켜짐)" 'grep -qx "mod_hooks=on" $STF && grep -q "무선 모드 훅(마지막 부팅 기록): 켜짐" $R'
mkdir -p $T/hlx; printf '%s\n' "01-01 18:30:04.800 I/HMG-API (  144): mods: loaded wireless-carplay-aa 2.2.0" "01-01 18:31:04.731 I/HMG-API (  148): mods: wireless-carplay-aa not loaded: hook point btsettings.projection_helper.open_wireless_page isn't mapped on this car (0 methods match): its hooks are off here, its other parts still apply" > $T/hlx/log.log
HMGLOG=$T/hlx STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null 2>&1
check "  1.7.2: HMG-API가 무선 모드 훅을 거부했으면(스포티지 NQ5 #46) mod_hooks=off, 리포트에 굵게 '안 켜짐'과 HMG-API 이유" 'grep -qx "mod_hooks=off" $STF && grep -q "무선 모드 훅(마지막 부팅 기록): \*\*안 켜짐\*\* (HMG-API: hook point btsettings.projection_helper.open_wireless_page isn" $R'
mkdir -p $T/hly; printf '%s\n' "01-01 18:31:04.731 E/HMG-API (  148): mods: wireless-carplay-aa not loaded" "java.lang.RuntimeException: /data/x/y" > $T/hly/log.log
HMGLOG=$T/hly STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null 2>&1
check "  리뷰 L-7: 이유 없는 예외 줄이면 줄 전체 대신 '(예외…)'만 보임" 'grep -qx "mod_hooks=off" $STF && grep -q "안 켜짐\*\* (HMG-API: (예외, 자세한 이유는 HMG-API 로그)" $R && ! grep -q "18:31:04.731 E/HMG-API" $R'
rm -rf $T/hly
rm -rf $T/hlx; HMGLOG=$T/hl STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null 2>&1
check "  1.6.2: 우리 hostapd만 돌면 ap_mode=ours, stock_ssid=none" 'grep -qx "ap_mode=ours" $STF && grep -qx "stock_ssid=none" $STF && grep -q "ap_mode=ours (순정 hostapd 판정: none" $R'
# 1.7.0: 재부팅 전 리포트 표시, QR용 state, 무선 안드로이드 오토(시험) 켜기·끄기(Launch 때 USB 파일)
echo boot17 > $T/boot17; printf 'pct=100\nstate=reboot\nstage=x\nboot=boot17\n' > $T/prog17
BOOT_ID=$T/boot17 PROG=$T/prog17 HMGLOG=$T/hl STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null 2>&1
check "1.7.0 Launch: state=reboot이면 리포트 맨 위에 굵게 '아직 재부팅하지 않았습니다', 상태 파일 state=reboot" '[ "$(sed -n 3p $R)" = "**아직 재부팅하지 않았습니다. 내비를 재부팅한 뒤 리포트를 다시 만들어 주세요.**" ] && grep -qx "state=reboot" $STF'
printf 'pct=100\nstate=reboot\nstage=x\nboot=old\n' > $T/prog17
BOOT_ID=$T/boot17 PROG=$T/prog17 HMGLOG=$T/hl STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null 2>&1
check "  지난 부팅에 쓴 state=reboot이면 그 줄 없음(리뷰 L5)" '! grep -q "아직 재부팅하지" $R'
printf 'pct=100\nstate=done\nstage=x\n' > $T/prog17
PROG=$T/prog17 HMGLOG=$T/hl STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null 2>&1
check "  state=done이면 그 줄 없음" '! grep -q "아직 재부팅하지" $R && grep -qx "state=done" $STF'
export AAOFF=$T/aaoff; rm -f $AAOFF; : > $T/usb0/kp-aa-off; rm -f $T/toast
# 이 구역만: 토스트를 덮어쓰지 않고 쌓는다(마지막 USB 저장 토스트가 앞 토스트를 덮으므로)
cp $T/bin/am $T/am.keep; printf '#!/bin/sh\necho "$*" >> %s/toast\n' $T > $T/bin/am
HMGLOG=$T/hl STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null 2>&1
check "  USB kp-aa-off → 끄기 표시, aa=no, 리포트에 꺼짐, 토스트 없음" '[ -f $AAOFF ] && grep -qx "aa=no" $STF && grep -q "무선 안드로이드 오토: 꺼짐" $R && ! grep -q "안드로이드 오토" $T/toast 2>/dev/null'
: > $T/usb0/kp-aa-on
HMGLOG=$T/hl STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null 2>&1
check "  kp-aa-off·kp-aa-on이 함께 있으면 끄기가 먼저(꺼진 채)" '[ -f $AAOFF ] && grep -qx "aa=no" $STF'
rm -f $T/usb0/kp-aa-off; HMGLOG=$T/hl STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null 2>&1
check "  kp-aa-on만 있으면 다시 켬(끄기 표시 지움), 리포트에 켜짐(기본)" '[ ! -f $AAOFF ] && grep -qx "aa=yes" $STF && grep -q "무선 안드로이드 오토: 켜짐(기본)" $R'
rm -f $T/toast; HMGLOG=$T/hl STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null 2>&1
check "  이미 꺼져 있으면 '껐습니다' 토스트를 다시 띄우지 않음(리뷰 L6)" '! grep -q "껐습니다" $T/toast 2>/dev/null'
rm -f $T/usb0/kp-aa-on $T/usb0/kp-aa-off $T/toast $AAOFF; unset AAOFF; mv $T/am.keep $T/bin/am
# 1.7.0(소유자 결정): Launch는 카플레이·계기판 길안내·음악 logcat과 디버그 로그(cp.log)까지 가려서 모은다
cp $T/bin/logcat $T/logcat.keep
cat > $T/bin/logcat <<'E'
#!/bin/sh
echo "11-08 01:00:00.100 I/TccCarPlay( 1087):  [TccCarPlayAudioTinyALSA] TccCarPlayAudioTinyALSA_ThreadPlayback() : pcm_write failed retry(0)"
echo "11-08 01:00:00.200 D/NavigationCluster(  600): updateTBTInfo type 70 dist 120"
echo "11-08 01:00:00.300 V/MediaStatus(  700): title: Spring Day, artist: Someone"
echo "11-08 01:00:00.400 I/iAP2    ( 1085): CallStateUpdate remote name: Hong Gildong 010-1234-5678"
echo "11-08 01:00:00.500 I/AAProjection(  789): WirelessExplorer : [Pixel7] Wireless ==> Connecting"
echo "11-08 01:00:00.600 D/ClusterService(  600): getCANStatus"
echo "11-08 01:00:00.700 D/NavigationCluster(  600): updateTPDestinationName SeoulStation"
echo "11-08 01:00:00.800 I/iAP2    ( 1085): LocationInformation lat 37.566535 lon 126.977969"
echo "11-08 01:00:00.810 D/ClusterService(  655): updateTPCrossroadName()::crossroadname is Gangnam Station"
echo "11-08 01:00:00.900 V/VehicleInfoManager(  954): [onVehicleSpeedChanged()] speed: 18"
echo "11-08 01:00:00.910 V/VehicleInfoManager(  954): [onVehicleSpeedChanged()] speed: 18"
echo "11-08 01:00:00.920 V/VehicleInfoManager(  954): [onVehicleSpeedChanged()] speed: 18"
echo "11-08 01:00:01.000 I/CarPlay_( 1003): [ LocationInfoManager ] onGearStatus() gear : 3"
echo "11-08 01:00:01.100 D/CarPlay_( 1007): [ DipoService ] isTMUCall_ring() callState : 1"
echo "11-08 01:00:01.200 D/BluetoothHfDevice(  900): call state changed: incoming 010-9876-5432"
E
chmod +x $T/bin/logcat
printf '%s\n' "  1 11-08 01:00:01.000 I/PhoneProjection( 1625): [ x ] addDeviceStatusInfo (Pixel7)" > $T/w/cp.log
HMGLOG=$T/hl STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null 2>&1
L3=$T/usb0/KoreaProjection-report/3-log.txt
check "1.7.0 Launch 로그: 연결·차량 데이터 칸(TBT·곡 정보 줄 남김, pcm_write·getCANStatus 버림)" 'grep -q "== 연결·차량 데이터 로그" $L3 && grep -q "updateTBTInfo type 70" $L3 && grep -q "MediaStatus" $L3 && ! grep -q "pcm_write" $L3 && ! grep -q "getCANStatus" $L3'
check "  폰 프로젝션 칸, 폰 이름·통화 상대 이름·번호는 가림" 'grep -q "== 폰 프로젝션 로그" $L3 && ! grep -q -E "Pixel7|Hong Gildong|1234-5678|9876-5432" $L3'
check "  위치는 줄을 남기고 모자이크(목적지·교차로 이름·좌표 → [가림: …])" '! grep -q -E "SeoulStation|Gangnam|37\.5665|126\.97" $L3 && grep -q "updateTPDestinationName \[가림: 위치\]" $L3 && grep -q "updateTPCrossroadName():\[가림: 위치\]" $L3 && grep -q "LocationInformation lat \[가림: 좌표\]" $L3'
check "  차량 데이터(속도·기어)·전화 상태 줄을 모음, 연달아 같은 줄은 [xN] 한 줄로" 'grep -q "\[x3\] .*onVehicleSpeedChanged" $L3 && [ "$(grep -c onVehicleSpeedChanged $L3)" = 1 ] && grep -q "onGearStatus() gear : 3" $L3 && grep -q "isTMUCall_ring() callState : 1" $L3'

P4=$T/usb0/KoreaProjection-private/4-debug-private.txt
check "  1.7.2: 비공개 디버그 로그는 제보 폴더가 아닌 KoreaProjection-private 폴더에(제보 폴더를 모두 선택해 올려도 섞이지 않음, #56)" '[ -f $P4 ] && [ ! -f $T/usb0/KoreaProjection-report/4-debug-private.txt ] && [ -z "$(ls $T/usb0/KoreaProjection-report | grep -v -E "^(1-report.md|2-car-report.json|3-log.txt)$")" ]'
check "  디버그 로그는 3-log.txt에 넣지 않고 4-debug-private.txt(비공개 안내 맨 위, 가림)로 따로(리뷰 H1)" '! grep -q "addDeviceStatusInfo" $L3 && grep -q "GitHub 이슈에 올리지 마세요" $P4 && grep -q "addDeviceStatusInfo (가림: 이름)" $P4 && ! grep -q Pixel7 $P4'
rm -f $T/w/cp.log; HMGLOG=$T/hl STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null 2>&1
check "  디버그 로그가 꺼진 차는 4번 파일 없음(지난 것도 지움)" '[ ! -f $P4 ]'
mv $T/logcat.keep $T/bin/logcat
# 1.6.2: 순정 카플레이 AP(K3 #15). 순정 dnsmasq를 우리 DHCP로 세지 않고, 리포트·토스트는 "준비됨(내비 Wi-Fi)"
cp $T/ps $T/ps.st; stockps > $T/ps; rm -f $T/toast; : > $SK/bk/stockap.seen
HMGLOG=$T/hl STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w PROC=$SK/proc BK=$SK/bk sh $T/st.sh > $T/st-stock.out
check "1.6.2 상태: 순정 카플레이 AP → our_ap=no, our_dhcp=no(순정 dnsmasq 오판 없음), other_ap=yes, stock_ssid=carplay, ap_mode=stock" 'grep -qx "our_ap=no" $STF && grep -qx "our_dhcp=no" $STF && grep -qx "other_ap=yes" $STF && grep -qx "stock_ssid=carplay" $STF && grep -qx "ap_mode=stock" $STF && grep -qx "stock_seen=yes" $STF'
check "  리포트에 ap_mode 한 줄(값 없이 판정만), 순정 AP 기록, 우리 DHCP 아니요" 'grep -q "^- 무선 카플레이 AP: ap_mode=stock (순정 hostapd 판정: carplay, 순정 카플레이 AP 기록: 예)" $R && grep -q "우리 DHCP: 아니요" $R && ! grep -q -F -e "SSID\\cX" -e "word77x" $R $STF'
check "  요약 문구는 '무선 카플레이 준비됨(내비 Wi-Fi 사용)', 토스트는 없음(1.7.0)" 'grep -q "무선 카플레이 준비됨(내비 Wi-Fi 사용)" $T/st-stock.out && [ ! -f $T/toast ]'
sconf HotspotName1; HMGLOG=$T/hl STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w PROC=$SK/proc sh $T/st.sh >/dev/null; sconf 'SSID\cX'
check "  순정 일반 핫스팟이면 ap_mode=none, stock_ssid=hotspot" 'grep -qx "ap_mode=none" $STF && grep -qx "stock_ssid=hotspot" $STF'
mv $T/ps.st $T/ps; rm -f $T/toast
HMGLOG=$T/hl STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null
check "  HMG-API 무선 모드 파일이 없으면 mod=no, mod_on=no, bridge=on" 'grep -qx "mod=no" $STF && grep -qx "mod_on=no" $STF && grep -qx "bridge=on" $STF'
HM=$T/hm; mkdir -p $HM/mod $HM/set; echo '{"id":"wireless-carplay-aa"}' > $HM/mod/mod.json
st_m() { HMGMOD=$HM/mod HMGSET=$HM/set/w.json HMGLOG=$T/hl STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null; }
st_m
check "  모드 설치·켜짐 → mod=yes, mod_on=yes, bridge=on" 'grep -qx "mod=yes" $STF && grep -qx "mod_on=yes" $STF && grep -qx "bridge=on" $STF'
: > $HM/mod/.disabled; st_m
check "  .disabled 있으면 mod_on=no (11-06 시험 상태)" 'grep -qx "mod=yes" $STF && grep -qx "mod_on=no" $STF && grep -q "켜짐 no" $R'
rm -f $HM/mod/.disabled; echo '{"tbt":true,"bridge":false,"audio":true}' > $HM/set/w.json; st_m
check "  설정 파일에 \"bridge\":false면 bridge=off" 'grep -qx "bridge=off" $STF && grep -q "(bridge) off" $R'
echo '{"bridge" : true}' > $HM/set/w.json; st_m
check "  \"bridge\":true면 bridge=on" 'grep -qx "bridge=on" $STF'
rm -rf $HM
check "  HMG-API 훅: 두 로그 중 마지막 'hook map' 줄(켜짐, mapped)" 'grep -qx "hooks=on" $STF && grep -qx "hookmap=mapped" $STF && grep -q "HMG-API 훅(마지막 부팅 기록): on mapped" $R'
cp $T/hl/log.log.1 $T/hl/log.log
HMGLOG=$T/hl STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null
check "  꺼짐 줄이 마지막이면 hooks=off, 상태 none" 'grep -qx "hooks=off" $STF && grep -qx "hookmap=none" $STF'
rm -rf $T/hl
HMGLOG=$T/hl STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null
check "  HMG-API 로그가 없으면 빈 값" 'grep -qx "hooks=" $STF && grep -qx "hookmap=" $STF'
check "  SSID·비밀번호·폰 IP 없음, 길이만" '! grep -q -e "SSID.cX" -e PASS -e HotspotName -e 192.168.43.23 $STF && grep -qx "ssid_len=7" $STF'
check "  화면 키와 같은 이름 (our_ap, feat_carplay, cp_conn)" 'grep -qx "our_ap=yes" $STF && grep -q "^feat_carplay=" $STF && grep -qx "cp_conn=1" $STF' 
check "USB에 리포트 저장 (KoreaProjection-report/1-report.md)" '[ -s $R ]'
check "USB에 분석용 로그 저장 (3-log.txt): 서비스·자동 설정·HMG-API 로그 칸" '[ -s $G3 ] && grep -q "^== ap.log" $G3 && grep -q "^== verify-map.txt" $G3 && grep -q "^== HMG-API 로그" $G3'
mkdir -p $T/hlm; printf '%s\n' "11-06 09:00:00.000 I/HMG-API ( 1): [wireless-carplay-aa] bridge: iPhone BT connected: A1:B2:C3:D4:E5:F6" "11-06 09:00:01.000 I/HMG-API ( 1): dhcp 192.168.43.23 ok, version 1.0.2" "11-06 09:00:02.000 I/HMG-API ( 1): v6 fe80::1c2d:3eff:fe4f:5a6b%wlan0" > $T/hlm/log.log
echo old > $T/usb0/KoreaProjection-report/2-car-report.json
echo "11-06 09:00 시작 (DEPEHEV.KOR.0000.V039.001.260902): 폰 10.0.0.7 aa:bb:cc:dd:ee:ff" > $T/logs/ap.log
HMGLOG=$T/hlm STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null
check "  로그에서 블루투스 주소·IP는 지우고, 버전·제품명은 남김" '! grep -q -i -e "A1:B2:C3" -e "aa:bb:cc" -e 192.168.43.23 -e 10.0.0.7 $G3 && grep -q "xx:xx:xx:xx:xx:xx" $G3 && grep -q "x.x.x.x" $G3 && grep -q "version 1.0.2" $G3 && grep -q "DEPEHEV.KOR.0000.V039.001.260902" $G3 && ! grep -q "1c2d:3eff" $G3 && grep -q "fe80:x" $G3'
check "  예전 Launch의 2-car-report.json은 지움 (새 1·3번과 섞이지 않게)" '[ ! -f $T/usb0/KoreaProjection-report/2-car-report.json ]'
seq 1 1000 | sed "s/^/11-06 I\/HMG-API: line /" > $T/hlm/log.log; HMGLOG=$T/hlm STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null
check "  HMG-API 로그는 마지막 800줄만" '[ "$(grep -c "line " $G3)" = 800 ] && grep -q "line 1000$" $G3 && ! grep -q "line 200$" $G3'
check "  휴대폰 이름이 들어가는 디버그 로그(cp.log)는 넣지 않음" '! grep -q "cp.log" $G3'
check "3-log.txt에 Wi-Fi 로그 칸: Wi-Fi 서비스 줄과 연결 성공 줄(key handshake)은 남기고 MAC은 지움" 'grep -q "^== Wi-Fi 로그" $G3 && grep -q "WifiStateMachine.*SUP_DISCONNECTION" $G3 && grep -q "wlan0 xx:xx:xx:xx:xx:xx" $G3 && grep -q "pairwise key handshake completed" $G3'
check "  SSID·비밀번호·기기 이름이 나올 수 있는 줄과 다른 태그는 버림" '! grep -q -i -e "MyHomeNet" -e "secret99" -e "Johns" -e "OtherApp.*wifi" $G3'

# 1.5.6: 리포트에 Wi-Fi·카플레이 연결 기록과 지금 채널
printf '%s\n' "11-07 16:00:00 Wi-Fi: 기기 연결 끊김 (커널 5초)" "11-07 16:59:00 서비스 시작: 이번 부팅 처음(부팅 뒤 20초)" "11-07 17:00:00 hostapd 시작" "11-07 17:00:30 Wi-Fi: AP 채널 149 (커널 632초)" "11-07 17:01:00 Wi-Fi: 기기 연결(Wi-Fi 인증 끝) (커널 701초)" "11-07 17:01:00 카플레이 연결 0 → 1" "11-07 17:02:00 동작 중: 1 개 카플레이 연결" > $T/logs/ap.log
printf 'interface=wlan0\nssid=SSID\\cX\nchannel=149\nhw_mode=a\nwpa_passphrase=PASS\\word99\n' > $T/hk.conf
CONF=$T/hk.conf HMGLOG=$T/hlm STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null
check "1.5.6 리포트: Wi-Fi·카플레이 연결 기록 칸과 지금 채널(149, hw_mode=a), 다른 줄은 그 칸에 넣지 않음" '! sed -n "/^## Wi-Fi·카플레이 연결 기록/,/^## 서비스 로그/p" $R | grep -q "커널 5초" && grep -q "^## Wi-Fi·카플레이 연결 기록" $R && grep -q "지금 핫스팟 채널: 149 (hw_mode=a)" $R && grep -q "AP 채널 149 (커널 632초)" $R && grep -q "카플레이 연결 0 → 1" $R && [ "$(sed -n "/^## Wi-Fi·카플레이 연결 기록/,/^## 서비스 로그/p" $R | grep -c "동작 중")" = 0 ] && ! grep -q -e "SSID.cX" -e "word99" $R'
{ echo "11-07 서비스 시작: 이번 부팅 처음(부팅 뒤 20초)"; seq 1 60 | sed "s/^/11-07 Wi-Fi: 기기 연결 끊김 (커널 /; s/$/초)/"; } > $T/logs/ap.log; CONF=$T/hk.conf HMGLOG=$T/hlm STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null
check "  연결 기록은 마지막 40줄만, 순서대로" '[ "$(sed -n "/^## Wi-Fi·카플레이 연결 기록/,/^## 서비스 로그/p" $R | grep -c "끊김")" = 40 ] && [ "$(sed -n "/^## Wi-Fi·카플레이 연결 기록/,/^## 서비스 로그/p" $R | grep "끊김" | head -1)" = "11-07 Wi-Fi: 기기 연결 끊김 (커널 21초)" ] && sed -n "/^## Wi-Fi·카플레이 연결 기록/,/^## 서비스 로그/p" $R | grep "끊김" | tail -1 | grep -q "커널 60초"'
# 1.7.2(P-17): 연결 기록 칸은 이번 부팅(설치) 첫 시작 줄 뒤만. ap.log.1(크기 제한으로 민 앞부분)도 이어 본다
printf '%s\n' "11-07 10:00:00 Wi-Fi: 기기 연결 끊김 (커널 1초)" "11-07 10:00:01 서비스 시작: 이번 부팅 처음(부팅 뒤 20초)" "11-07 10:00:02 Wi-Fi: AP 채널 149 (커널 30초)" > $T/logs/ap.log.1
printf '%s\n' "11-07 10:01:00 카플레이 연결 0 → 1" > $T/logs/ap.log
CONF=$T/hk.conf HMGLOG=$T/hlm STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null
check "1.7.2 P-17: 연결 기록 칸은 '서비스 시작: 이번 부팅 처음' 줄 뒤만, ap.log.1부터 이어서" 'sed -n "/^## Wi-Fi·카플레이 연결 기록/,/^## 서비스 로그/p" $R > $T/cr.txt && grep -q "AP 채널 149 (커널 30초)" $T/cr.txt && grep -q "카플레이 연결 0 → 1" $T/cr.txt && ! grep -q "커널 1초" $T/cr.txt && ! grep -q "이번 부팅 처음" $T/cr.txt'
printf '%s\n' "11-07 10:00:00 Wi-Fi: 기기 연결 끊김 (커널 1초)" > $T/logs/ap.log; rm -f $T/logs/ap.log.1
CONF=$T/hk.conf HMGLOG=$T/hlm STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null
check "  첫 시작 줄이 없으면(업데이트 전 기록뿐) 연결 기록 칸이 비어 있음" '! sed -n "/^## Wi-Fi·카플레이 연결 기록/,/^## 서비스 로그/p" $R | grep -q "커널 1초"'
printf '%s\n' "11-07 10:00:00 Wi-Fi: 기기 연결 끊김 (커널 2초)" > $T/logs/ap.log.1; printf '%s\n' "11-07 10:01:00 카플레이 연결 0 → 1" > $T/logs/ap.log
CONF=$T/hk.conf HMGLOG=$T/hlm STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null
check "  리뷰 L-3: 회전(ap.log.1)으로 첫 시작 줄이 밀려났으면 '밀려남' 표시와 마지막 줄들을 보임" 'sed -n "/^## Wi-Fi·카플레이 연결 기록/,/^## 서비스 로그/p" $R > $T/cr2.txt && grep -q "밀려남" $T/cr2.txt && grep -q "카플레이 연결 0 → 1" $T/cr2.txt'
rm -f $T/logs/ap.log.1
# 1.7.2(P-8·P-12): 연결 진단 칸
cp $T/bin/logcat $T/logcat.p8
cat > $T/bin/logcat <<'E2'
#!/bin/sh
echo "01-01 18:30:09.270 I/WifiService(  562): [Feature] Hardware(supported)Client(not supported), Hotspot(not supported), Wireless(supported)"
echo "01-01 18:30:40.100 I/WifiService(  562): Last mode: Wi-Fi AP Enabled (for Wireless Connectivity)"
echo "11-08 01:00:00.100 D/ClusterService(  600): getOpState::mode = DIPO"
echo "11-08 01:00:00.200 D/ClusterService(  600): updateClusterInfo::mode = DIPO title MySecretSong"
echo "11-08 01:00:00.300 D/ClusterService(  600): updateClusterInfo::mode = DIPO title Other"
echo "11-08 01:00:00.400 D/ClusterService(  600): updateFilename length is 12"
echo "11-08 01:00:00.500 D/ClusterService(  600): *** Cluster New Protocol ***"
E2
chmod +x $T/bin/logcat
mkdir -p $T/hl8; printf '%s\n' "01-01 I/HMG-API ( 1): [wireless-carplay-aa] bridge: hotspot already up (mode 2)" "01-01 I/HMG-API ( 1): [wireless-carplay-aa] bridge: hotspot already up (mode 2)" "01-01 I/HMG-API ( 1): [wireless-carplay-aa] bridge: our hotspot already up, stock AP-on skipped" "01-01 I/HMG-API ( 1): [wireless-carplay-aa] bridge: our hotspot already up, stock AP-on skipped" "01-01 I/HMG-API ( 1): [wireless-carplay-aa] bridge: our hotspot already up, stock AP-on skipped" "01-01 I/HMG-API ( 1): Android Auto AP hooks in com.daudio.app.phoneprojection: 4 of 5 (active only while sys.kp.aa_ap=1)" "01-01 I/HMG-API ( 1): Android Auto AP hooks in com.daudio.app.phoneprojection: 5 of 5 (active only while sys.kp.aa_ap=1)" "01-01 I/HMG-API ( 1): Android Auto AP hooks in com.google.android.projection.sink: 5 of 5 (active only while sys.kp.aa_ap=1" > $T/hl8/log.log
mkdir -p $T/bk8; : > $T/bk8/mod.ours; : > $T/bk8/wifi.nochip; mkdir -p $T/w8; echo 1 > $T/bk8/wifi_ap_on.orig
printf '%s\n' "# 칩 깨우기 실패 기록" "판정 근거: 순정 module_version=3 (3이면 순정 Wi-Fi 서비스도 Wi-Fi 하드웨어가 없다고 봄, 1이면 부품 있음)" > $T/w8/nochip-wifi.txt
echo boot-8 > $T/boot8; echo "boot-8 23" > $T/w8/svc.start; echo noaddr > $T/w8/aa.why
BOOT_ID=$T/boot8 BK=$T/bk8 HMGLOG=$T/hl8 STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w8 sh $T/st.sh >/dev/null 2>&1
check "  리뷰 L-9: 진단 문구 정리에서 / 를 허용 글자로 둠(다른 차의 Client/Hotspot 꼴 대비, 소스 확인)" 'grep -q "gsub(/\[^A-Za-z0-9 (),.\\\\/-\]/" $PKG/bin/status.sh'
check "1.7.2 P-8: 리포트 연결 진단 칸: wifi_ap_on, Last mode·[Feature] 문구, 우리 서비스 시작(부팅 뒤 초)" 'grep -q "^## 연결 진단" $R && grep -q "순정 AP 저장값(wifi_ap_on): 1" $R && grep -q "Last mode): Wi-Fi AP Enabled (for Wireless Connectivity)$" $R && grep -q "\[Feature\]): Hardware(supported)Client(not supported), Hotspot(not supported), Wireless(supported)$" $R && grep -q "우리 서비스 시작: 부팅 뒤 23초(이번 부팅 처음 시작)" $R'
check "1.7.2 P-7: 브리지가 순정 AP 켜기를 건너뛴 줄을 (mode 2)와 따로 셈(3번), 우리가 바꾼 wifi_ap_on 기록(원래 값 1)" 'grep -q "순정 AP 켜기 건너뜀(our hotspot already up, stock AP-on skipped): 3번" $R && grep -q "hotspot already up (mode 2): 2번" $R && grep -q "순정 AP 저장값을 우리가 바꿈(wifi_ap_on.orig): 예, 원래 값 1$" $R'
check "  HMG-API hotspot already up 횟수, AA 훅 N of M(프로세스별 마지막)" 'grep -q "hotspot already up (mode 2): 2번" $R && grep -q "Android Auto AP 훅: com.daudio.app.phoneprojection 5 of 5, com.google.android.projection.sink 5 of 5$" $R'
check "  softap.conf 인증 종류 숫자, mod.ours·mod.pin 유무, AA 설정값 3개" 'grep -q "softap.conf 인증 종류 값(카플레이 SSID 다음 정수, 니로 4): [0-9]" $R && grep -q "무선 모드 기록: mod.ours 예, mod.pin 아니요" $R && grep -q "androidauto_information / _dr1 / _dr2): 1 / 1 / 1" $R'
check "  계기판 곡 제목 확인 줄은 개수만(제목 없음)" 'grep -q "getOpState DIPO 1, updateClusterInfo DIPO 2, updateClusterWithArtistInfo 0, updateFilename 1, PIO/OPIO TP 안 보냄 0, Cluster New Protocol 1, invalid TP Mode 0" $R && ! grep -q MySecretSong $R'
check "  AA 신호 이유를 보임" 'grep -q "모드에 알린 신호 .*(이유: wlan0에 우리 AP 주소 없음)" $R'
check "1.7.2 P-12: Wi-Fi 칩 없음 기록과 순정 판정 근거(module_version) 한 줄" 'grep -q "Wi-Fi 칩 없음 기록(wifi.nochip): 예, 다시 확인함(nochip.rechk): 아니요, 판정 근거: 순정 module_version=3" $R'
check "  연결 진단 칸에 SSID·비밀번호 없음" '! sed -n "/^## 연결 진단/,/^## /p" $R | grep -q -e "SSID.cX" -e "PASS" -e HotspotName'
rm -f $T/w8/svc.start; BOOT_ID=$T/boot8 BK=$T/bk8 HMGLOG=$T/hl8 STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w8 sh $T/st.sh >/dev/null 2>&1
check "  서비스 시작 기록이 없으면 '이번 부팅 기록 없음'" 'grep -q "우리 서비스 시작: 이번 부팅 기록 없음" $R'
mv $T/logcat.p8 $T/bin/logcat; rm -f $T/boot8; rm -rf "${T:?}"/hl8 "${T:?}"/bk8 "${T:?}"/w8
# 뒤의 검사가 보통 리포트(기본 설정 경로)를 보도록 다시 만든다
HMGLOG=$T/hlm STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null
rm -f $T/hk.conf
rm -rf $T/hlm; rm -f $T/logs/ap.log
check "리포트에 SSID·비밀번호·폰 IP 없음" '! grep -q -e "SSID.cX" -e "PASS" -e HotspotName -e 192.168.43.23 $R'
check "우리 hostapd 인식" 'grep -q "우리 hostapd: 예" $R'
check "wifi.direct를 wifi로 착각하지 않음" 'grep -q "android.hardware.wifi: 아니요" $R'
rm -f $T/nowififeat
check "니로: 상태 화면 tested=yes, 리포트 '확인된 차: 예'" 'grep -qx "tested=yes" $STF && grep -q "확인된 차: 예" $R'
echo DN822HEV.KOR.0000.V039.001.260902 > $T/product
mkdir -p $T/hl9; printf '%s\n' "01-01 18:30:04.740 I/HMG-API (  148): hook map: probed for Hyundai Sonata Hybrid (DN8) (kor 260902), hooks on" > $T/hl9/log.log
HMGLOG=$T/hl9 STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null
check "쏘나타(시험 지원): 상태 화면 tested=yes(앱이 '대기 중'으로 안 보임), 리포트 '시험 지원'" 'grep -qx "tested=yes" $STF && grep -q "확인된 차: 시험 지원" $R'
echo TESTX.KOR.0000.V001.001.250101 > $T/product
HMGLOG=$T/hl9 STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null
check "목록에 없는 한국 차(자동 시험): tested=yes, 리포트 '자동 설정'" 'grep -qx "tested=yes" $STF && grep -q "확인된 차: 자동 설정" $R'
echo DEPEHEV.USA.0000.V039.001.260902 > $T/product
HMGLOG=$T/hl0 STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null
check "목록에 없는 차: tested=no, 리포트 '아니요'" 'grep -qx "tested=no" $STF && grep -q "확인된 차: 아니요" $R'
rm -f $T/product
# 위 실행이 뒤에서 띄운 Car Report 작업이 끝날 때까지 기다린다(뒤 테스트와 겹치지 않게)
i=0; while [ -d $T/w/carreport.lock ] && [ $i -lt 50 ]; do /bin/sleep 0.2; i=$((i+1)); done
mkdir -p $T/hl0; printf '%s\n' "01-01 18:30:04.740 I/HMG-API (  148): hook map: mapped for Kia Niro Hybrid (kor 260902), hooks on" > $T/hl0/log.log
rm -f $T/toast; HMGLOG=$T/hl0 STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh > $T/st-ready.out; rm -rf $T/hl0
check "요약 문구 한국어(준비된 차: 핫스팟 상태와 저장 중), 토스트는 없음(1.7.0 소유자 결정)" 'grep -q "핫스팟 켜짐" $T/st-ready.out && grep -q "저장하는 중입니다(화면에 진행이 보입니다)" $T/st-ready.out && [ ! -f $T/toast ]'
check "  저장이 끝나면 진행 기록 100%, 'USB를 빼셔도 됩니다'(Car Report 결과와 상관없이), 644" 'grep -qx "pct=100" $RPROG && grep -q -E "^state=(done|fail)$" $RPROG && grep -q "USB를 빼셔도 됩니다" $RPROG && [ "$(stat -f %Lp $RPROG)" = 644 ]'
# 1.7.0: 보통 Launch는 로그 모으기를 뒤에서(status.sh --collect) 하고 바로 끝난다. 진행 기록이 run → 100%로 바뀐다
i=0; while [ -d $T/w/carreport.lock ] && [ $i -lt 50 ]; do /bin/sleep 0.2; i=$((i+1)); done
rm -f $T/usb0/KoreaProjection-report/3-log.txt $RPROG
# 뒤에서 도는 것도 시험용 status.sh(st.sh, 가짜 USB·mounts 경로)를 부르게 APP를 따로 둔다
rm -rf $T/app2; mkdir -p $T/app2/bin; for f in $T/app/*; do [ "${f##*/}" = bin ] || ln -s $f $T/app2/; done
cp $T/st.sh $T/app2/bin/status.sh; cp $T/app/bin/carreport.sh $T/app2/bin/carreport.sh
# 가짜 busybox: setsid는 건너뛰고(뒤에서 띄우기만), 스크립트가 PATH를 바꿔도 맥 명령을 찾게 한다
printf '#!/bin/sh\n[ "$1" = setsid ] && shift\nPATH=%s/bin:/usr/bin:/bin:$PATH exec "$@"\n' $T > $T/bbs17; chmod +x $T/bbs17
(RPT_SYNC=0; export RPT_SYNC; HMGLOG=$T/hl STATUS=$STF BB=$T/bbs17 APP=$T/app2 SRC=$T/softap.conf W=$T/w sh $T/st.sh > $T/st-async.out 2>/dev/null)
_r1=$(grep '^state=' $RPROG 2>/dev/null)
i=0; while ! grep -q '^pct=100$' $RPROG 2>/dev/null && [ $i -lt 100 ]; do /bin/sleep 0.2; i=$((i+1)); done
check "1.7.0 Launch: 로그 모으기를 뒤에서 하고 바로 끝남(진행 기록 run으로 시작 → 100%), 3-log.txt 저장" '[ "$_r1" = "state=run" ] && grep -qx "pct=100" $RPROG && [ -s $T/usb0/KoreaProjection-report/3-log.txt ] && grep -q "저장하는 중입니다" $T/st-async.out'
check "  status.sh에 토스트(am broadcast)가 없음(busybox 없는 내비 짧은 리포트 말고)" '[ "$(grep -c "am broadcast" $PKG/bin/status.sh)" = 0 ] && ! grep -q "^ *toast \"" $PKG/bin/carreport.sh'
check "USB가 꽂혀 있으면 리포트에 순정 파일 체크섬(없는 파일은 '없음')" 'grep -q "## 순정 파일 체크섬" $R && grep -q "^HKMC_DiPO.apk " $R && grep -q "^featurexml.cfg " $R'
mkdir -p $T/sys/app $T/sys/lib; echo dipo > $T/sys/app/HKMC_DiPO.apk
SYSAPP=$T/sys/app SYSLIB=$T/sys/lib STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null
mkdir -p $T/hs$T/sys/app; echo stock > $T/hs$T/sys/app/HKMC_DiPO.apk
SYSAPP=$T/sys/app SYSLIB=$T/sys/lib HMGSTOCK=$T/hs STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null
check "  HMG-API 순정 백업이 있으면 그 md5를 씀" 'grep -qx "HKMC_DiPO.apk $(md5sum < $T/hs$T/sys/app/HKMC_DiPO.apk | cut -c1-32) (HMG-API 순정 백업)" $R'
rm -rf $T/hs
SYSAPP=$T/sys/app SYSLIB=$T/sys/lib STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null
check "  있는 파일은 md5, 없는 파일은 '없음'" 'grep -qx "HKMC_DiPO.apk $(md5sum < $T/sys/app/HKMC_DiPO.apk | cut -c1-32)" $R && grep -qx "libCarPlayCore.so 없음" $R'
: > $T/mounts; SYSAPP=$T/sys/app STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null
check "  USB가 없으면 체크섬을 계산하지 않음 (화면이 늦지 않게)" 'grep -q "USB를 꽂은 채 Launch" $T/w/korea-projection-report.md && ! grep -q "^HKMC_DiPO.apk " $T/w/korea-projection-report.md'
echo "/dev/block/sda1 $T/usb0 vfat rw 0 0" > $T/mounts; rm -rf $T/sys

# --- 2b. Launch가 뒤에서 HMG-API Car Report를 USB에 저장 (지원 목록에 없거나 훅이 꺼진 차) ---
CR=$T/cr; mkdir -p $CR/bin $CR/w
cat > $CR/bin/hmgapid <<E
#!/bin/sh
echo "hmgapid \$*" >> $CR/calls
[ -f $CR/slow ] && /bin/sleep 3
[ -f $CR/fail ] && { echo "error"; exit 1; }
echo "report: kia-niro-20261106"; echo "usb: /storage/usb0/HMG-API reports/kia-niro-20261106.json"; exit 0
E
printf '#!/bin/sh\necho "$*" > %s/toast\n' $CR > $CR/bin/am
# 가짜 busybox: setsid는 건너뛰고, 스크립트가 PATH를 헤드유닛 경로로 바꿔도 맥 명령을 찾게 한다
printf '#!/bin/sh\n[ "$1" = setsid ] && shift\nPATH=/usr/bin:/bin:$PATH exec "$@"\n' > $CR/bin/bbs
chmod +x $CR/bin/*
echo "/dev/block/sda1 /storage/usb0 vfat rw 0 0" > $CR/mounts
cr() { (PATH=$CR/bin:/usr/bin:/bin BB=$T/bin/bb W=$CR/w CR_WAIT=0.2 CR_MAX=${CRMAX:-50} CR_GRACE=0 MOUNTS=$CR/mounts BOOT_ID=$CR/boot sh -c 'sed "s#^export PATH=.*#export PATH='$CR'/bin:/usr/bin:/bin#" '$T'/app/bin/carreport.sh > '$CR'/cr.sh; sh '$CR'/cr.sh'); }
echo b1 > $CR/boot
rm -f $CR/calls $RPROG; cr
check "Car Report: hmgapid engine report --usb 실행 → 진행 기록 완료(이제 USB를 빼셔도 됩니다, 토스트 없음), 잠금 해제" 'grep -qx "hmgapid engine report --usb" $CR/calls && grep -qx "state=done" $RPROG && grep -q "이제 USB를 빼셔도" $RPROG && [ ! -f $CR/toast ] && [ ! -d $CR/w/carreport.lock ]'
: > $CR/mounts; rm -f $RPROG; cr; echo "/dev/block/sda1 /storage/usb0 vfat rw 0 0" > $CR/mounts
check "  USB가 실제로 마운트돼 있지 않으면(빈 마운트 폴더에 씀) 성공으로 보지 않음" 'grep -qx "state=fail" $RPROG && grep -q "저장하지 못했습니다" $RPROG'
# 제보 폴더로 복사: USBROOT를 가짜 폴더로 돌려 실제 파일 복사를 본다
mkdir -p "$CR/st/usb0/HMG-API reports"; echo '{"report": "hmgapi car report 1"}' > "$CR/st/usb0/HMG-API reports/kia-niro-20261106.json"
sed -e "s#/storage/usb0/HMG-API#$CR/st/usb0/HMG-API#" $CR/bin/hmgapid > $CR/hm2; cp $CR/bin/hmgapid $CR/hm1; cp $CR/hm2 $CR/bin/hmgapid; chmod +x $CR/bin/hmgapid
echo "/dev/block/sda1 $CR/st/usb0 vfat rw 0 0" > $CR/mounts; rm -f $RPROG
(PATH=$CR/bin:/usr/bin:/bin BB=$T/bin/bb W=$CR/w CR_WAIT=0.2 CR_MAX=50 CR_GRACE=0 MOUNTS=$CR/mounts BOOT_ID=$CR/boot USBROOT=$CR/st sh $CR/cr.sh)
check "  Car Report를 제보 폴더에 2-car-report.json으로도 복사, 토스트에 폴더 이름" 'cmp -s "$CR/st/usb0/HMG-API reports/kia-niro-20261106.json" $CR/st/usb0/KoreaProjection-report/2-car-report.json && grep -q "USB의 KoreaProjection-report 폴더)" $RPROG'
# 1.7.2(P-19): 제보 폴더 사본만 IPv4를 가린다(원본은 그대로). 반만 가린 꼴(a.b.x.x)도 가린다. 결과는 JSON 그대로
printf '{"report": "hmgapi car report 1", "net": "inet 10.20.30.40/30 brd 10.20.30.43\\n inet 203.0.x.x/30 SRC=:[removed].0.113.7 mac aa:bb:cc:dd:ee:ff", "v": "4.4.2", "p": "DEPEHEV.KOR.0000.V039.001.260902"}\n' > "$CR/st/usb0/HMG-API reports/kia-niro-20261106.json"
rm -rf $CR/st/usb0/KoreaProjection-report; rm -f $RPROG
(PATH=$CR/bin:/usr/bin:/bin BB=$T/bin/bb W=$CR/w CR_WAIT=0.2 CR_MAX=50 CR_GRACE=0 MOUNTS=$CR/mounts BOOT_ID=$CR/boot USBROOT=$CR/st sh $CR/cr.sh)
RJ=$CR/st/usb0/KoreaProjection-report/2-car-report.json
check "  1.7.2(P-19): 제보 폴더 사본은 IPv4·반만 가린 IP·IPv6에 남은 IPv4 뒷부분·MAC을 가림, 버전·제품 문자열은 그대로" '! grep -q -E "[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+|203[.]0[.]x|0[.]113[.]7|aa:bb" $RJ && grep -q "inet x.x.x.x/30 brd x.x.x.x" $RJ && grep -q "SRC=:.removed. mac xx:xx" $RJ && grep -q "\"v\": \"4.4.2\"" $RJ && grep -q "DEPEHEV.KOR.0000.V039.001.260902" $RJ'
check "  1.7.2(P-19): 원본(HMG-API reports)은 바꾸지 않음, 사본은 JSON으로 읽힘, 임시 파일 없음" 'grep -q "10.20.30.40" "$CR/st/usb0/HMG-API reports/kia-niro-20261106.json" && python3 -c "import json,sys; json.load(open(sys.argv[1]))" $RJ && [ ! -f $RJ.tmp ]'
# 가리기(awk)가 안 되는 busybox: 사본을 만들지 않고 HMG-API reports 폴더를 안내
printf '#!/bin/sh\n[ "$1" = awk ] && exit 1\nexec %s "$@"\n' "$T/bin/bb" > $CR/bin/bbnoawk; chmod +x $CR/bin/bbnoawk
mkdir -p $CR/st/usb0/KoreaProjection-report; echo '{"old": "10.1.1.1"}' > $RJ; rm -f $RPROG
(PATH=$CR/bin:/usr/bin:/bin BB=$CR/bin/bbnoawk W=$CR/w CR_WAIT=0.2 CR_MAX=50 CR_GRACE=0 MOUNTS=$CR/mounts BOOT_ID=$CR/boot USBROOT=$CR/st sh $CR/cr.sh)
check "  1.7.2(P-19): 가리기가 안 되면 사본을 만들지 않고 예전 사본도 지움, 공개 이슈에 올리지 말라고 안내" '[ ! -f $RJ ] && [ ! -f $RJ.tmp ] && grep -q "IP를 가리지 못해" $RPROG && grep -q "공개 이슈에 올리지 마세요" $RPROG && ! grep -q "폴더에 있습니다" $RPROG'
# awk가 가리지 않고 그대로 내보내는 busybox(정규식 해석이 다름): 남은 IP를 보고 쓰지 않음
printf '#!/bin/sh\nif [ "$1" = awk ]; then cat "$3"; exit 0; fi\nexec %s "$@"\n' "$T/bin/bb" > $CR/bin/bbcat; chmod +x $CR/bin/bbcat
rm -rf $CR/st/usb0/KoreaProjection-report; rm -f $RPROG
(PATH=$CR/bin:/usr/bin:/bin BB=$CR/bin/bbcat W=$CR/w CR_WAIT=0.2 CR_MAX=50 CR_GRACE=0 MOUNTS=$CR/mounts BOOT_ID=$CR/boot USBROOT=$CR/st sh $CR/cr.sh)
check "  1.7.2(P-19): 가린 결과에 IP가 남으면 쓰지 않음" '[ ! -f $RJ ] && grep -q "IP를 가리지 못해" $RPROG'
echo '{"report": "hmgapi car report 1"}' > "$CR/st/usb0/HMG-API reports/kia-niro-20261106.json"
rm -rf $CR/st/usb0/KoreaProjection-report; : > $CR/st/usb0/KoreaProjection-report; rm -f $RPROG
(PATH=$CR/bin:/usr/bin:/bin BB=$T/bin/bb W=$CR/w CR_WAIT=0.2 CR_MAX=50 CR_GRACE=0 MOUNTS=$CR/mounts BOOT_ID=$CR/boot USBROOT=$CR/st sh $CR/cr.sh)
check "  제보 폴더로 복사가 실패하면 '파일 3개'라 하지 않고 HMG-API reports 폴더를 안내" 'grep -q "HMG-API reports. 폴더에 있습니다" $RPROG && ! grep -q "모두 저장했습니다" $RPROG'
rm -f $CR/st/usb0/KoreaProjection-report
cp $CR/hm1 $CR/bin/hmgapid; echo "/dev/block/sda1 /storage/usb0 vfat rw 0 0" > $CR/mounts
touch $CR/fail; rm -f $RPROG; cr; rm -f $CR/fail
check "  실패하면 진행 기록 fail, 다시 해 달라는 안내" 'grep -qx "state=fail" $RPROG && grep -q "저장하지 못했습니다" $RPROG'
touch $CR/slow; rm -f $RPROG; CRMAX=2 cr; rm -f $CR/slow
check "  오래 걸리면 멈추고(제한 시간) 실패 안내" 'grep -q "시간 초과" $CR/w/carreport.txt && grep -q "저장하지 못했습니다" $RPROG'
/bin/sleep 30 >/dev/null 2>&1 & SL=$!
printf '#!/bin/sh\nexec /bin/sleep 30\n' > $CR/carreport.sh; chmod +x $CR/carreport.sh
mkdir -p $CR/w/carreport.lock; echo "$SL b1" > $CR/w/carreport.lock/pid; rm -f $CR/calls; cr
check "  남은 잠금이 carreport.sh가 아닌 프로세스면 지우고 실행" 'grep -q "engine report" $CR/calls && [ ! -d $CR/w/carreport.lock ]'
mkdir -p $CR/w/carreport.lock; echo "$SL b0" > $CR/w/carreport.lock/pid; rm -f $CR/calls; cr
check "  지난 부팅의 잠금도 지우고 실행" 'grep -q "engine report" $CR/calls'
kill $SL 2>/dev/null; wait $SL 2>/dev/null
# status.sh에서: 확인된 차 + 훅 켜짐이면 띄우지 않고, 훅이 꺼지면 띄운다
mkdir -p $T/hl
printf '%s\n' "01-01 18:30:04.740 I/HMG-API (  148): hook map: mapped for Kia Niro Hybrid (kor 260902), hooks on" > $T/hl/log.log
rm -f $T/w/carreport.txt
CR_WAIT=0.2 CR_MAX=5 CR_GRACE=0 PATH=$CR/bin:$PATH HMGLOG=$T/hl STATUS=$STF BB=$CR/bin/bbs APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null 2>&1
i=0; while [ ! -f $T/w/carreport.txt ] && [ $i -lt 30 ]; do /bin/sleep 0.2; i=$((i+1)); done
check "Launch(1.7.0): 확인된 차이고 훅이 켜져 있어도 Car Report를 만듦(파일 3개, #41)" '[ -f $T/w/carreport.txt ]'
printf '%s\n' "01-01 18:30:04.740 I/HMG-API (  148): hook map: none for Kia Niro, hooks off (no map)" > $T/hl/log.log
# 1.7.0: 앞 Launch도 Car Report를 뒤에서 만든다. 그것이 끝나며 쓰는 토스트가 이번 확인과 섞이지 않게 끝날 때까지 기다린다
i=0; while [ -d $T/w/carreport.lock ] && [ $i -lt 50 ]; do /bin/sleep 0.2; i=$((i+1)); done; /bin/sleep 0.5; rm -f $T/w/carreport.txt $T/toast
PATH=$CR/bin:$PATH HMGLOG=$T/hl STATUS=$STF BB=$CR/bin/bbs APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh > $T/st17.out 2>/dev/null
i=0; while [ ! -f $T/w/carreport.txt ] && [ $i -lt 30 ]; do /bin/sleep 0.2; i=$((i+1)); done
check "  훅이 꺼져 있으면 Car Report를 뒤에서 만들고, 기다리라는 토스트(상태 문구도 남음)" 'grep -q "제보 자료를 USB의 KoreaProjection-report 폴더에 저장하는 중" $T/st17.out && grep -q "카플레이 연결" $T/st17.out'
: > $T/mounts; rm -f $T/w/carreport.txt
PATH=$CR/bin:$PATH HMGLOG=$T/hl STATUS=$STF BB=$CR/bin/bbs APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null 2>&1
/bin/sleep 1
check "  USB가 없으면 만들지 않음" '[ ! -f $T/w/carreport.txt ]'
echo "/dev/block/sda1 $T/usb0 vfat rw 0 0" > $T/mounts; rm -rf $T/hl

# --- 3. kp-test.sh: 단계별 경로 ---
fixpath $B/scripts/kp-test.sh > $T/kp.sh
run() { U=$T/usb0 D=$T/d APPS=$T/apps PERMS=$T/perms BB=$T/bin/bb sh $T/kp.sh >/dev/null 2>&1; cat $T/d/step 2>/dev/null || echo none; }
reset() { rm -rf $T/d/* $T/usb0/kp $T/calls $T/feat $T/install_ok $T/wp_stuck $T/force_ok $T/wp_reinstall_fails $T/perms $T/apps/*; mkdir -p $T/apps/wireless.projection $T/perms; }
reset
check "되돌리기 zip이 없으면 시작 안 함" '[ "$(run)" = none ] && ! grep -q uninstall $T/calls 2>/dev/null'
for z in wireless.projection.zip packages/korea.projection.zip packages/niro.carplay.hotspot.zip; do echo x > $T/usb0/$z; done
reset
check "새 패키지 설치 실패 → 중단" '[ "$(run)" = none ]'
check "  예전 패키지 재설치, wireless.projection 유지" 'grep -q "install $T/usb0/packages/niro.carplay.hotspot.zip" $T/calls && ! grep -q "uninstall wireless.projection" $T/calls'
reset; touch $T/install_ok $T/wp_stuck
check "wireless.projection 삭제 실패 → C로 중단" '[ "$(run)" = C ]'
reset; touch $T/install_ok
check "정상: A" '[ "$(run)" = A ]'
check "  기능 없음 → 권한 파일 2개를 md5 맞춰 쓰고 apply, B2" '[ "$(run)" = B2 ] && [ "$(md5sum < $T/perms/com.hkmc.software.connectivity.carplay_wireless.xml | cut -c1-32)" = 95ff801a064526de56059dba10960b05 ] && [ "$(md5sum < $T/perms/com.hkmc.software.connectivity.androidauto_wireless.xml | cut -c1-32)" = fa91812d3eeee415768018ab6ee6804a ] && ! grep -q -- --force $T/calls'
check "  재시작 뒤에도 없음 → 되돌리기 (파일 쓰기 다시 안 함)" '[ "$(run)" = B-rollback ] && grep -q "install $T/usb0/wireless.projection.zip" $T/calls'
reset; mkdir -p $T/perms; touch $T/install_ok
run >/dev/null; run >/dev/null; touch $T/feat
check "  재시작 뒤 기능 생김 → C" '[ "$(run)" = C ]'
reset; mkdir -p $T/perms; touch $T/install_ok; echo B1 > $T/d/step
check "지금 차 상태(B1)에서 다음 꽂기 → 파일 되돌리기(B2)" '[ "$(run)" = B2 ]'
reset; mkdir -p $T/perms; touch $T/install_ok $T/wp_reinstall_fails; echo B2 > $T/d/step; : > $T/d/fixed; rmdir $T/apps/wireless.projection
check "되돌리기 재설치 실패 → rollback-retry" '[ "$(run)" = rollback-retry ] && grep -q "재설치에 실패" $T/toast'
rm -f $T/wp_reinstall_fails
check "  다음 꽂기에 다시 설치 → B-rollback" '[ "$(run)" = B-rollback ]'
reset; mkdir -p $T/perms; touch $T/install_ok; : > $T/d/fixed
check "새로 시작하면 예전 표시 파일 지움" '[ "$(run)" = A ] && [ ! -f $T/d/fixed ]'
touch $T/feat
check "정상: 기능 있음 → C" '[ "$(run)" = C ]'
reset; touch $T/install_ok; echo B-rollback > $T/d/step; rmdir $T/apps/wireless.projection
check "되돌리기 중 재시작돼 둘 다 없음 → 다시 설치" '[ "$(run)" = B-rollback ] && grep -q "install $T/usb0/wireless.projection.zip" $T/calls'
reset; touch $T/install_ok; echo B-rollback > $T/d/step
check "되돌리기 끝난 뒤 꽂기 → 로그 수집(C)" '[ "$(run)" = C ] && ls $T/usb0/kp/C-*.txt >/dev/null 2>&1'
touch $T/usb0/kp-rollback
check "kp-rollback 파일 → 되돌리기" '[ "$(run)" = B-rollback ]'

# --- 4. kp-update-test.sh: 업데이트 → 삭제 확인 → 다시 설치 ---
# 시험 스크립트가 올릴 버전(WANT)을 그대로 쓴다: 버전을 올릴 때 테스트를 고치지 않아도 된다
KPW=$(sed -n "s/^WANT=//p" $B/scripts/kp-update-test.sh)
X=$T/up; mkdir -p $X/bin $X/usb/packages $X/d $X/apps $X/perms $X/wd $X/bk
echo zip > $X/usb/packages/korea.projection.zip; echo prev > $X/usb/packages/korea.projection-prev.zip
touch $X/perms/com.hkmc.software.connectivity.carplay_wireless.xml $X/perms/com.hkmc.software.connectivity.androidauto_wireless.xml
echo 1.1 > $X/ver; echo 1 > $X/wifi
cat > $X/bin/nemesis <<E
#!/bin/sh
echo "nemesis \$*" >> $X/calls
case "\$1" in
  pkg-list) echo "usb-handler|USB Handler|1|service|1.16.7|x"; [ -f $X/ver ] && echo "korea.projection|Korea Projection|0|service,application|\$(cat $X/ver)|x" ;;
  install) case "\$*" in *prev.zip) echo 1.3 > $X/ver; mkdir -p $X/apps/korea.projection $X/wd $X/bk; touch $X/conf; echo up > $X/ap; exit 0 ;; esac
    # 실제 NEMESIS처럼: 업데이트는 예전 것을 먼저 지우므로, 실패하면 아무것도 남지 않는다
    [ -f $X/inst_fail ] && { [ "\$2" = --update ] && rm -f $X/ver $X/ap; exit 1; }; [ "\$2" = --update ] && [ ! -f $X/ver ] && exit 1; echo $KPW > $X/ver; mkdir -p $X/bk; [ -f $X/bk/wifi_on ] || cat $X/wifi > $X/bk/wifi_on; mkdir -p $X/apps/korea.projection $X/wd $X/bk; touch $X/conf; echo up > $X/ap ;;
  uninstall) rm -f $X/ver; rm -rf $X/apps/korea.projection $X/bk; [ -f $X/leave_wd ] || rm -rf $X/wd; rm -f $X/conf $X/ap ;;
esac
exit 0
E
cat > $X/bin/ps <<E
#!/bin/sh
[ -f $X/ap ] && { echo "  1 1010 hostapd $X/conf"; echo "  2 9999 dnsmasq --keep-in-foreground --no-resolv"; }
echo "  3 1010 wpa_supplicant"
E
printf '#!/bin/sh\ncat %s/wifi\n' $X > $X/bin/settings
for c in hmgapid getprop; do printf '#!/bin/sh\nexit 0\n' > $X/bin/$c; done
cat > $X/bin/pm <<E
#!/bin/sh
case "\$1" in
  list) echo feature:com.hkmc.software.connectivity.carplay_wireless ;;
  path) [ -f $X/ver ] && echo package:/data/app/korea.projection.app-1.apk || exit 1 ;;
esac
E
printf '#!/bin/sh\necho "wlan0 Link encap:Ethernet HWaddr 00:11:22:33:44:55"\necho "  inet addr:192.168.43.1"\n' > $X/bin/ifconfig
printf '#!/bin/sh\necho "$*" > %s/toast\n' $X > $X/bin/am
printf '#!/bin/sh\n/bin/sleep 0.01\n' > $X/bin/sleep
chmod +x $X/bin/*
sed "s#^export PATH=.*#export PATH=$X/bin:/usr/bin:/bin:/sbin#" $B/scripts/kp-update-test.sh > $X/kp2.sh
echo "/dev/block/sda1 $X/usb vfat rw 0 0" > $X/mounts
urun() { (cd $X && MOUNTS=$X/mounts U=$X/usb D=$X/d APPS=$X/apps PERMS=$X/perms CONF=$X/conf WD=$X/wd BK=$X/bk BB=$T/bin/bb timeout 60 sh $X/kp2.sh >/dev/null 2>&1); cat $X/d/step 2>/dev/null || echo none; }
check "업데이트: $KPW 설치되고 핫스팟 켜짐 → R" '[ "$(urun)" = R ] && grep -q "install --update" $X/calls'
check "  삭제 직후 확인 7개 통과 → R2 (재시작 안내)" '[ "$(urun)" = R2 ] && [ "$(grep -c "^통과" $X/usb/kp7/R.txt)" = 7 ] && grep -q "내비를 재부팅한 뒤" $X/toast'
check "  재시작 뒤 확인 + 다시 설치 모두 통과 → DONE" '[ "$(urun)" = DONE ] && ! grep -q "^실패" $X/usb/kp7/R.txt && [ "$(grep -c "^통과" $X/usb/kp7/R.txt)" = 15 ] && grep -q "모두 통과" $X/toast'
check "  다시 설치는 헤드유닛에 복사한 zip으로" 'grep -q "^nemesis install $X/d/pkg.zip" $X/calls'
check "  그다음 꽂기: 로그 수집, MAC 안 남김" '[ "$(urun)" = DONE ] && ls $X/usb/kp7/C-*.txt >/dev/null 2>&1 && ! grep -q HWaddr $X/usb/kp7/C-*.txt'
echo R > $X/d/step; touch $X/leave_wd
check "삭제 뒤 작업 폴더가 남으면 실패로 잡음" '[ "$(urun)" = R2 ] && grep -q "^실패 작업 폴더" $X/usb/kp7/R.txt'
check "  끝에 실패 수를 알림" '[ "$(urun)" = DONE ] && grep -q "실패 1건" $X/toast'
rm -f $X/leave_wd
echo R > $X/d/step; mkdir -p $X/bk; echo 1 > $X/bk/wifi_on; echo 0 > $X/wifi
urun >/dev/null
check "Wi-Fi 비교는 설치 전 값(\$BK/wifi_on)과 한다" '[ "$(urun)" = DONE ] && grep -q "^실패 Wi-Fi 설정이 설치 전과 같음 (1)" $X/usb/kp7/R.txt'
echo 1 > $X/wifi
echo R > $X/d/step; urun >/dev/null; touch $X/inst_fail
check "다시 설치 실패 → DONE이라 하지 않고 REINSTALL" '[ "$(urun)" = REINSTALL ] && grep -q "확인되지 않았습니다" $X/toast'
rm -f $X/inst_fail
check "  다음 꽂기에 다시 설치 → DONE" '[ "$(urun)" = DONE ] && grep -q "다시 설치했습니다" $X/toast'
rm -f $X/d/step $X/ver $X/calls
check "업데이트가 비어 있으면(예전 것만 지워짐) 일반 설치로 메꿈 → R" '[ "$(urun)" = R ] && grep -q "^nemesis install $X/usb/packages/korea.projection.zip" $X/calls'
rm -f $X/d/step $X/calls; echo 1.3 > $X/ver; touch $X/inst_fail
check "새 버전 설치가 모두 실패하면 이전 버전으로 되돌리고 알림" '[ "$(urun)" = none ] && grep -q "install $X/usb/packages/korea.projection-prev.zip" $X/calls && grep -q "이전 버전(1.3)으로 되돌렸습니다" $X/toast && [ -f $X/ap ]'
rm -f $X/inst_fail
rm -f $X/d/step $X/calls; echo 1.4 > $X/ver; touch $X/usb/kp-only-update
check "kp-only-update: 업데이트만 하고 DONE (삭제 안 함)" '[ "$(urun)" = DONE ] && ! grep -q "uninstall" $X/calls && grep -q "Launch를 눌러" $X/toast'
rm -f $X/usb/kp-only-update
rm -f $X/d/step; echo 1.1 > $X/ver; rm -f $X/usb/packages/korea.projection.zip
check "USB에 zip이 없으면 시작 안 함" '[ "$(urun)" = none ] && grep -q "시작하지 않았습니다" $X/toast'

# --- 1.5.4: busybox가 없는 내비(K3 #15), 설치 문구, 설정 중 안내, 앱 설치 기록 ---
NB=$T/nb; rm -rf $NB; mkdir -p $NB/bin $NB/bk $NB/w $NB/hd/maps
printf '#!/bin/sh\necho "$*" >> %s/toasts\n' $NB > $NB/bin/am
export NOTICE=$NB/toasts
printf '#!/bin/sh\necho "pm $*" >> %s/calls\necho Failure\n' $NB > $NB/bin/pm
chmod +x $NB/bin/*
# toolbox만 있는 PATH(K3 탐사로 확인한 명령만): 차에 없는 printf·awk·sed·head·tail·stat을 부르면 "not found"가 난다
mkdir -p $NB/tb
for c in cp rm mkdir chmod ls cat grep date sleep sync; do ln -sf "$(command -v $c)" $NB/tb/$c; done
# 1.7.1: 차의 toolbox mv는 옵션을 모른다(-f를 파일 이름으로 봄, 리뷰 H1). 첫 인자가 -로 시작하면 실패하게 흉내 낸다.
printf '#!/bin/sh\ncase "$1" in -*) echo "mv: $1: No such file" >&2; exit 1 ;; esac\nexec %s "$@"\n' "$(command -v mv)" > $NB/tb/mv
cp $NB/bin/am $NB/bin/pm $NB/tb/
printf '#!/bin/sh\ncase "$1" in sys.boot_completed) echo 1 ;; *) echo TEST ;; esac\n' > $NB/tb/getprop
printf '#!/bin/sh\necho "setprop $*" >> %s/setprop.log\n' $NB > $NB/tb/setprop
chmod +x $NB/tb/*
echo boot-1 > $NB/bootid
TB="$NB/tb"
(PATH=$NB/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$NB/none W=$NB/w BK=$NB/bk sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$NB'/bin:'$T'/bin:/usr/bin:/bin:/sbin; wait() { exit 7; }; main') > $NB/out 2>&1; echo $? >> $NB/out
check "서비스: busybox가 없으면 아무것도 하지 않고 로그만 남기고 대기" 'grep -q "busybox가 없음" $NB/out && [ "$(tail -1 $NB/out)" = 7 ] && [ ! -d $NB/w/x ] && ! grep -q "svc\|hostapd" $NB/out'
# post.sh: 이 PC에는 /system/bin/busybox가 없다(그대로 busybox 없는 내비)
sed -e "s#/data/nemesis/apps/korea.projection/svc/hotspot.sh#$T/app/svc/hotspot.sh; export PATH=$NB/bin:$T/bin:/usr/bin:/bin:/sbin#" \
  -e "s#^export PATH=.*#export PATH=$NB/bin:$T/bin:/usr/bin:/bin:/sbin#" -e "s#^BK=.*#BK=$NB/bk#" -e "s#/data/local/tmp/cpdrive#$NB/cpdrive#" \
  -e "s#/data/nemesis/apps/niro.carplay.hotspot#$NB/old#" -e "s#^W=.*#W=$NB/w#" $T/app/scripts/post.sh > $NB/post.sh
echo apk > $NB/fake.apk
sed -e "s#^export PATH=.*#export PATH=$TB#" -e "s#; export PATH=$NB/bin:$T/bin:/usr/bin:/bin:/sbin#; export PATH=$TB#" $NB/post.sh > $NB/post-tb.sh
rm -f $NB/toasts $NB/calls $NB/w/app-install.log $NB/setprop.log; (W=$NB/w APK_SRC=$NB/fake.apk APK_COPY=$NB/copy.apk /bin/sh $NB/post-tb.sh) > $NB/out 2>&1; echo $? >> $NB/out
check "설치: busybox가 없으면 무선 설정 없이 '아직 동작하지 않습니다(지원 조사 중)' 안내, 성공(0)으로 끝남" 'grep -q "아직 동작하지 않습니다(지원 조사 중)" $NB/toasts && ! grep -q busybox $NB/toasts && [ "$(tail -1 $NB/out)" = 0 ]'
check "  1.7.1: 알림 기록 한 줄(\"<초> <부팅 id> <문구>\", 644)이 toolbox mv(옵션 없음)로도 생기고 임시 파일이 남지 않음(리뷰 H1·L1)" 'grep -q "^[0-9][0-9]* [^ ]* 이 내비에서는 아직 동작하지 않습니다" $NB/toasts && [ "$(stat -f %Lp $NB/toasts)" = 644 ] && [ -z "$(ls $NB | grep "^toasts\.")" ]'
check "  1.5.5: busybox가 없어도 상태 화면 앱은 toolbox 명령으로 설치를 시도하고 결과를 남김(실패해도 성공)" 'grep -q "^pm install -r $NB/copy.apk" $NB/calls && grep -q "pm install: Failure" $NB/w/app-install.log && [ -f $NB/copy.apk ]'
check "  toolbox 명령만으로 끝남(not found 없음), 부팅 완료 표시를 0으로 내렸다가 1로 되돌림" '! grep -q "not found" $NB/out && [ "$(cat $NB/setprop.log)" = "$(printf "setprop sys.boot_completed 0\nsetprop sys.boot_completed 1")" ]'
rm -f $NB/toasts $NB/calls; (W=$NB/w APK_SRC=$NB/none.apk APK_COPY=$NB/copy2.apk /bin/sh $NB/post-tb.sh) > $NB/out 2>&1; echo $? >> $NB/out
check "  앱 파일이 없어도 설치는 성공(0), pm을 부르지 않음" '[ "$(tail -1 $NB/out)" = 0 ] && ! grep -q "pm install" $NB/calls 2>/dev/null'
sed -i '' "s#^BB=.*#BB=$T/bin/bb#" $NB/post.sh
rm -f $NB/toasts; (W=$NB/w APK_SRC=$NB/none.apk sh $NB/post.sh) > $NB/out 2>&1
check "  앱 설치 실패 문구는 핫스팟 상태를 말하지 않음" 'grep -q "상태 화면 앱을 설치하지 못했습니다" $NB/toasts && ! grep -q "핫스팟은 정상" $NB/toasts'
# status.sh: busybox 없는 내비는 셸 기본 명령으로 짧은 리포트를 USB에 남김
rm -rf $T/usb0/KoreaProjection-report; rm -f $T/toast
rm -f $STF $NB/calls $NB/toasts $NB/setprop.log $NB/w/app-try
# 앞의 Car Report 테스트가 뒤에서 같은 USB 폴더에 쓰는 중일 수 있다(가끔 실패): 끝날 때까지 기다린다
i=0; while { [ -d $T/w/carreport.lock ] || [ -d $CR/w/carreport.lock ]; } && [ $i -lt 100 ]; do /bin/sleep 0.2; i=$((i+1)); done
PV=$(grep '^package-version=' $PKG/NEMESIS.data); PV=${PV#package-version=}
cp $PKG/NEMESIS.data $T/app/NEMESIS.data
# status.sh가 읽어 들이는 hotspot.sh가 PATH를 $T/bin으로 다시 정하므로, 그 뒤에 이 구역의 pm·am이 먼저 오게 한다
sed -e "s#^export PATH=.*#export PATH=$TB#" -e "s#^\(HOTSPOT_LIB=1 \. .*hotspot\.sh\)\$#\1; export PATH=$TB#" $T/st.sh > $NB/st.sh
(STATUS=$STF BB=$NB/none BOOT_ID=$NB/bootid APP=$T/app SRC=$T/softap.conf W=$NB/w APK_SRC=$NB/fake.apk APK_COPY=$NB/copy3.apk /bin/sh $NB/st.sh) > $NB/out 2>&1; echo $? >> $NB/out
check "Launch: busybox가 없으면 USB에 짧은 리포트(제품·플랫폼·명령 목록)만 남김" 'grep -q "busybox 없는 내비" $T/usb0/KoreaProjection-report/1-report.md && grep -q "^## /system/bin" $T/usb0/KoreaProjection-report/1-report.md && [ ! -f $T/usb0/KoreaProjection-report/3-log.txt ] && [ "$(tail -1 $NB/out)" = 0 ]'
check "  1.5.5: 앱이 읽을 짧은 상태 파일(support=nobb, usb=saved, 버전) 644" 'grep -q "^support=nobb$" $STF && grep -q "^usb=saved$" $STF && grep -qx "pkgver=$PV" $STF && grep -q "^made=" $STF && [ "$(stat -f %Lp $STF)" = 644 ]'
check "  앱이 없으면 다시 설치를 시도하고, 화면을 못 띄우므로 토스트로 안내" 'grep -q "^pm install -r $NB/copy3.apk" $NB/calls && grep -q "아직 동작하지 않습니다(지원 조사 중)" $NB/toasts'
check "  toolbox 명령만으로 끝남: 오류 줄 없음(NEMESIS가 화면에 띄움)" '! grep -q "not found" $NB/out && [ ! -f $STF.tmp ]'
(STATUS=$STF BB=$NB/none BOOT_ID=$NB/bootid APP=$T/app SRC=$T/softap.conf W=$NB/w APK_SRC=$NB/fake.apk APK_COPY=$NB/copy3.apk /bin/sh $NB/st.sh) > /dev/null 2>&1
check "  Launch를 두 번 눌러도 앱 재설치(부팅 완료 표시 0→1)는 한 부팅에 한 번" '[ "$(grep -c "boot_completed 0" $NB/setprop.log)" = 1 ] && [ "$(grep -c "^pm install" $NB/calls)" = 1 ]'
echo boot-2 > $NB/bootid
(STATUS=$STF BB=$NB/none BOOT_ID=$NB/bootid APP=$T/app SRC=$T/softap.conf W=$NB/w APK_SRC=$NB/fake.apk APK_COPY=$NB/copy3.apk /bin/sh $NB/st.sh) > /dev/null 2>&1
check "  다음 부팅에는 다시 시도" '[ "$(grep -c "^pm install" $NB/calls)" = 2 ]'
rm -rf $T/usb0/KoreaProjection-report; rm -f $NB/toasts
mkdir -p $NB/bin2; cp $NB/bin/am $NB/bin2/am
printf '#!/bin/sh\necho "pm $*" >> %s/calls\ncase "$1" in path) echo package:/data/app/x.apk ;; *) echo Success ;; esac\n' $NB > $NB/bin2/pm; chmod +x $NB/bin2/pm
sed -e "s#^export PATH=.*#export PATH=$NB/bin2:$T/bin:/usr/bin:/bin:/sbin#" -e "s#^\(HOTSPOT_LIB=1 \. .*hotspot\.sh\)\$#\1; export PATH=$NB/bin2:$T/bin:/usr/bin:/bin:/sbin#" $T/st.sh > $NB/st2.sh
mv $T/mounts $T/mounts.keep; rm -f $NB/calls
(STATUS=$STF BB=$NB/none APP=$T/app SRC=$T/softap.conf W=$NB/w sh $NB/st2.sh) > $NB/out 2>&1
mv $T/mounts.keep $T/mounts; rm -f $T/app/NEMESIS.data
check "  앱이 있으면 토스트 없이 화면이 안내(USB 없으면 usb=none)" '[ ! -f $NB/toasts ] && grep -q "^usb=none$" $STF && grep -q "^pm path" $NB/calls && ! grep -q "pm install" $NB/calls'
# preun: busybox 없는 내비에서 삭제하면 앱을 지우고 오류 줄 없이 끝남(toolbox PATH)
sed -e "s#^BB=.*#BB=$NB/none#" -e "s#^BK=.*#BK=$NB/pbk#" -e "s#/data/nemesis/apps/korea.projection/svc/hotspot.sh#$T/app/svc/hotspot.sh; export PATH=$TB#" \
  -e "s#^export PATH=.*#export PATH=$TB#" -e "s#^STAGE=.*#STAGE=$NB/stage#" -e "s#/data/local/tmp/korea-projection-status#$NB/status#g" $T/app/scripts/preun.sh > $NB/preun.sh
rm -f $NB/calls; mkdir -p $NB/pw $NB/pbk; : > $NB/status.txt
(HMGDATA=$NB/hd W=$NB/pw BK=$NB/pbk APK_COPY=$NB/copy4.apk /bin/sh $NB/preun.sh) > $NB/out 2>&1; echo $? >> $NB/out
check "삭제: busybox가 없는 내비도 상태 화면 앱을 지우고(pm uninstall) 작업 폴더·상태 파일을 지움, busybox 오류 줄 없음" 'grep -q "^pm uninstall korea.projection.app" $NB/calls && [ ! -d $NB/pw ] && [ ! -f $NB/status.txt ] && ! grep -q "busybox: not found\|none: not found" $NB/out'
# 앱 설치 기록이 3-log.txt에 들어감
echo "11-06 21:00:00 pm install: Failure [INSTALL_FAILED_X]" > $T/w/app-install.log
HMGLOG=$T/hl STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null 2>&1
check "3-log.txt에 상태 화면 앱 설치 기록(app-install.log) 칸" 'grep -q "^== app-install.log" $G3 && grep -q "INSTALL_FAILED_X" $G3'
rm -f $T/w/app-install.log
# 설정 중 안내: 할 일이 남았을 때만
sp() { (HOTSPOT_LIB=1 BB=$T/bin/bb W=$NB/w BK=$NB/bk HMGDATA=$NB/hd WPDIR=$NB/wp sh -c '. '$T'/app/svc/hotspot.sh; setup_pending'); }
check "setup_pending: 모드가 없고 다시 하지 않기로 한 기록이 없으면 설정 중" 'sp'
: > $NB/bk/mod.tried; check "  mod.tried가 있으면 아님" '! sp'; rm -f $NB/bk/mod.tried
: > $NB/bk/wifi.nochip; check "  wifi.nochip이 있으면 아님" '! sp'; rm -f $NB/bk/wifi.nochip
: > $NB/bk/automap.bad; check "  automap.bad가 있으면 아님" '! sp'; rm -f $NB/bk/automap.bad
mkdir -p $NB/hd/mods/wireless-carplay-aa; echo '{}' > $NB/hd/mods/wireless-carplay-aa/mod.json; check "  모드가 이미 있으면 아님" '! sp'; rm -rf $NB/hd/mods
mkdir -p $NB/wp; check "  wireless.projection이 있으면 아님" '! sp'; rm -rf $NB/wp
echo "x 1" > $NB/bk/map.bad; check "  시험 지원 차 지도 확인 실패 기록(map.bad)이 있으면 아님" '! sp'; rm -f $NB/bk/map.bad
: > $NB/bk/setup.told; check "  이미 한 번 안내했으면(setup.told) 아님: 부팅마다 뜨지 않음" '! sp'; rm -f $NB/bk/setup.told
check "서비스: 무선 모드 대기에 들어갈 때 설정 중이면 한 번 기록하고 재부팅하지 말라고 안내" 'grep -A4 "대기: HMG-API 무선 모드가 설치" $T/app/svc/hotspot.sh | grep -q "if setup_pending; then" && grep -A4 "대기: HMG-API 무선 모드가 설치" $T/app/svc/hotspot.sh | grep -q "setup.told"'
check "그랜저IG 2.5: 시험 지원 목록, 지도, 패치 세트 연결" '(HOTSPOT_LIB=1 BB=$T/bin/bb W=$X/w sh -c ". $T/app/svc/hotspot.sh; car_in IGPE.KOR.0000.V039.001.260902 \"\$CARS_TRY\"") && grep -q "\"IGPE.KOR.\"" $T/app/hmgapi/maps/hyundai/grandeur-gasoline/kor/260902/car.json'

export NOTICE=$T/toast
# ---- 1.6.0: busybox 고르기(내비의 것, 없으면 패키지에 함께 넣은 busybox 1.36.1) ----
BS=$T/bsel; mkdir -p $BS/sys $BS/own $BS/w
printf '#!/bin/sh\nexec "$@"\n' > $BS/sys/busybox; chmod 755 $BS/sys/busybox
printf '#!/bin/sh\nexec "$@"\n' > $BS/own/busybox; chmod 755 $BS/own/busybox
# 이 PC에서 실행되지 않는 busybox(예: noexec /data에 놓인 것)
printf '#!/bin/sh\nexit 126\n' > $BS/own/broken; chmod 755 $BS/own/broken
bsel() { (env HOTSPOT_LIB=1 W=$BS/w "$@" sh -c '. '$T'/app/svc/hotspot.sh; echo "BB=$BB"; echo "OK=$BB_OK"; echo "PS=$PS"'); }
printf '#!/bin/sh\n[ "$1" = true ] && { echo "true: applet not found" >&2; exit 127; }\nexec "$@"\n' > $BS/sys/notrue; chmod 755 $BS/sys/notrue
bsel BB= BB_SYS=$BS/sys/notrue BB_OWN=$BS/own/busybox > $BS/out
check "1.6.0: 내비 busybox는 실행 파일인지만 봄(true 명령이 없는 1.8.1이어도 그대로 씀, 확인된 차가 멈추지 않게)" 'grep -qx "BB=$BS/sys/notrue" $BS/out && grep -qx "OK=1" $BS/out'
bsel BB= BB_SYS=$BS/sys/busybox BB_OWN=$BS/own/busybox > $BS/out
check "  내비에 busybox가 있으면 그것을 쓰고 ps는 지금처럼(옵션 없음)" 'grep -qx "BB=$BS/sys/busybox" $BS/out && grep -qx "OK=1" $BS/out && grep -qx "PS=$BS/sys/busybox ps" $BS/out'
bsel BB= BB_SYS=$BS/none BB_OWN=$BS/own/busybox > $BS/out
check "  없으면 함께 넣은 busybox를 쓰고, ps는 상태 칸을 달라고 함(-o pid,stat,args)" 'grep -qx "BB=$BS/own/busybox" $BS/out && grep -qx "OK=1" $BS/out && grep -qx "PS=$BS/own/busybox ps -o pid,stat,args" $BS/out'
chmod 644 $BS/own/busybox; bsel BB= BB_SYS=$BS/none BB_OWN=$BS/own/busybox > $BS/out
check "  함께 넣은 busybox에 실행 권한이 없으면 755로 주고 씀" 'grep -qx "OK=1" $BS/out && [ "$(stat -f %Lp $BS/own/busybox)" = 755 ]'
bsel BB= BB_SYS=$BS/none BB_OWN=$BS/own/broken > $BS/out
check "  함께 넣은 busybox가 실행되지 않으면 쓸 수 없음(BB_OK=0 → busybox 없는 내비로 처리)" 'grep -qx "OK=0" $BS/out'
bsel BB= BB_SYS=$BS/none BB_OWN=$BS/none > $BS/out
check "  둘 다 없으면 쓸 수 없음" 'grep -qx "OK=0" $BS/out'
bsel BB=$BS/sys/busybox BB_SYS=$BS/none BB_OWN=$BS/own/busybox > $BS/out
check "  BB를 미리 정하면 그대로 씀(테스트·carreport 호출)" 'grep -qx "BB=$BS/sys/busybox" $BS/out && grep -qx "PS=$BS/sys/busybox ps" $BS/out'
(PATH=$NB/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB= BB_SYS=$BS/none BB_OWN=$BS/own/broken W=$NB/w2 BK=$NB/bk2 sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$NB'/bin:'$T'/bin:/usr/bin:/bin:/sbin; wait() { exit 7; }; main') > $BS/main.out 2>&1; echo $? >> $BS/main.out
check "  서비스: 쓸 수 있는 busybox가 없으면 지금처럼 로그만 남기고 대기" 'grep -q "busybox가 없음" $BS/main.out && [ "$(tail -1 $BS/main.out)" = 7 ]'
# ps -o pid,stat,args 형식(ARM 컨테이너에서 1.36.1로 본 모양): 좀비는 STAT Z, 이름은 [hostapd]
mv $T/ps $T/ps.keep 2>/dev/null
psx() { (PATH=$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB= BB_SYS=$BS/none BB_OWN=$T/bin/bb W=$BS/w sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$T'/bin:/usr/bin:/bin:/sbin; '"$1"); }
printf '%s\n' "PID   STAT COMMAND" "  999997 Z    [hostapd]" "  999996 S    {busybox} grep hostapd" > $T/ps
check "  함께 넣은 busybox: 좀비 hostapd는 도는 것으로 보지 않음(running, stock_ap_on)" '! psx "running hostapd" && ! psx stock_ap_on'
printf '%s\n' "PID   STAT COMMAND" "  4321 S    hostapd /data/misc/wifi/hostapd-kp.conf" "  4322 S    dnsmasq --keep-in-foreground --no-resolv --no-poll --dhcp-authoritative --pid-file --interface=wlan0" "  4400 S    hostapd /data/misc/wifi/hostapd.conf" > $T/ps
check "  우리 hostapd는 도는 것으로, 순정 hostapd는 순정 핫스팟으로 봄" 'psx "running \"hostapd \$CONF\"" && psx stock_ap_on'
printf '#!/bin/sh\necho "kill $*" >> %s/kills\n' $BS > $BS/kill; chmod 755 $BS/kill; rm -f $BS/kills
psx 'kill() { echo "kill $*" >> '$BS'/kills; }; stop_ours'
check "  stop_ours는 우리 hostapd(PID 첫 칸)만 멈춤: 순정 hostapd가 돌 때 pid 파일 없는 dnsmasq는 순정 것일 수 있어 두기(1.6.2)" '[ "$(cat $BS/kills 2>/dev/null)" = "kill 4321" ]'
rm -f $T/ps; mv $T/ps.keep $T/ps 2>/dev/null
# post.sh·preun.sh·status.sh는 BB를 정하지 않고 hotspot.sh가 고르게 한다
check "  post.sh·preun.sh는 BB를 비워 두고 hotspot.sh를 ps보다 먼저 읽음" 'grep -qx "BB=" $PKG/scripts/post.sh && grep -qx "BB=" $PKG/scripts/preun.sh && [ "$(grep -n "hotspot.sh$" $PKG/scripts/post.sh | cut -d: -f1)" -lt "$(grep -n "\$PS" $PKG/scripts/post.sh | head -1 | cut -d: -f1)" ]'
check "  ps는 모두 \$PS로 부름(\$BB ps 직접 호출 없음)" '! grep -n -F "\$BB ps" $PKG/svc/hotspot.sh $PKG/bin/status.sh $PKG/bin/carreport.sh $PKG/scripts/post.sh $PKG/scripts/preun.sh | grep -v "then PS="'
check "  status.sh는 carreport.sh·--wait에 고른 BB를 넘김" '[ "$(grep -c "BB=\$BB .*setsid" $PKG/bin/status.sh)" = 2 ]'
# 1.7.2(P-9): busybox(GPL-2.0) 라이선스 안내를 패키지 bin/에 두고, USB 묶음을 만들 때 빠졌으면 멈춘다
check "1.7.2 P-9: 패키지에 bin/busybox-LICENSE.txt(GPL-2.0, 대응 소스 위치, 패키지 busybox와 같은 SHA-256)" 'f=$PKG/bin/busybox-LICENSE.txt; grep -q "GPL-2.0" $f && grep -q "busybox-1.36.1.tar.bz2" $f && grep -q "aports/-/tree/3.20-stable/main/busybox" $f && { [ ! -f $PKG/bin/busybox ] || grep -q "$(shasum -a 256 < $PKG/bin/busybox | cut -c1-64)" $f; }'
mkdir -p $T/p9/pk/bin $T/p9/out; cp $PKG/NEMESIS.data $T/p9/pk/; echo bb > $T/p9/pk/bin/busybox
(cd $T/p9/pk && zip -q -X -r ../nolic.zip NEMESIS.data bin); cp $PKG/bin/busybox-LICENSE.txt $T/p9/pk/bin/; (cd $T/p9/pk && zip -q -X -r ../lic.zip NEMESIS.data bin)
check "  build-usb.sh: 패키지에 busybox만 있고 안내가 없으면 만들지 않음, 있으면 묶음 맨 위에도 BUSYBOX-LICENSE.txt" '! sh $B/scripts/build-usb.sh $T/p9/nolic.zip $T/p9/out >/dev/null 2>&1 && sh $B/scripts/build-usb.sh $T/p9/lic.zip $T/p9/out >/dev/null 2>&1 && unzip -l $T/p9/out/korea-projection-*-usb.zip | grep -q " BUSYBOX-LICENSE.txt$"'
rm -rf "${T:?}"/p9
# 1.6.2: busybox를 다시 함께 넣는다(1.5.6은 뺐다). vendor 사본과 같은 파일이고 실행 권한이 있다.
if [ -f $B/vendor/busybox/busybox ]; then
check "1.6.2: 패키지에 bin/busybox(755)가 있고 vendor 사본·README의 SHA-256과 같음" '[ -x $PKG/bin/busybox ] && [ "$(stat -f %Lp $PKG/bin/busybox)" = 755 ] && cmp -s $PKG/bin/busybox $B/vendor/busybox/busybox && grep -q "$(shasum -a 256 < $PKG/bin/busybox | cut -c1-64)" $B/vendor/busybox/README.md'
check "  vendor의 busybox는 ARM 32비트 정적 실행 파일(1.6.x 재개용)" 'file $B/vendor/busybox/busybox | grep -q "ELF 32-bit LSB executable, ARM.*statically linked"'
else
  echo "건너뜀: 함께 넣은 busybox 파일 확인 (공개 저장소에는 busybox 바이너리가 없음, 릴리스 zip에만)"
fi
bsel BB= BB_SYS=$BS/none BB_OWN=$T/app/bin/busybox > $BS/out
check "  내비에 busybox가 없고 패키지에도 없으면 BB_OK=0(서비스는 '지원 조사 중'으로 대기)" 'grep -qx "OK=0" $BS/out'
# 진짜 busybox 1.36.1(ARM)로 확인: Docker와 alpine:3.20 arm/v7 이미지가 이 PC에 있을 때만(없으면 건너뜀, 받지 않음)
if command -v docker >/dev/null 2>&1 && docker image inspect --platform linux/arm/v7 alpine:3.20 >/dev/null 2>&1; then
  cat > $BS/real.sh <<'E'
B=/vb/busybox
mkdir -p /x; echo 'while :; do sleep 1; done' > /x/hostapd
$B sh /x/hostapd /data/misc/wifi/hostapd-kp.conf & hp=$!
$B sh /x/hostapd /data/misc/wifi/hostapd.conf & sp=$!
( $B sleep 0 & exec $B sleep 3 ) &
$B sleep 1
HOTSPOT_LIB=1 BB= BB_SYS=/nonexist BB_OWN=/vb/busybox APP=/app W=/tmp/w . /app/svc/hotspot.sh
echo "OK=$BB_OK"; echo "PS=$PS"
$PS | $B grep -q " Z " && echo zombie-seen
running "hostapd $CONF" && echo ours-running
stock_ap_on && echo stock-on
stop_ours; $B sleep 1
kill -0 $hp 2>/dev/null || echo ours-stopped
kill -0 $sp 2>/dev/null && echo stock-alive
kill $sp
printf '\000\005hi\377' > /tmp/b; set -- $(for _t in $($B od -b -v /tmp/b); do [ ${#_t} -eq 3 ] && echo $_t; done); echo "od=$*"
echo hi > /tmp/f; chmod 640 /tmp/f; echo "perm=$(f_perm /tmp/f) owner=$(f_owner /tmp/f)"
echo "md5=$(echo hi | $B md5sum)"
E
  docker run --rm --pull never --platform linux/arm/v7 -v $T/app:/app:ro -v $B/vendor/busybox:/vb:ro -v $BS:/t:ro alpine:3.20 /vb/busybox sh /t/real.sh > $BS/real.out 2>&1
  check "  진짜 busybox(ARM 컨테이너): 실행됨, ps -o로 좀비를 보고 우리·순정 hostapd를 구분, 우리 것만 멈춤" 'grep -qx "OK=1" $BS/real.out && grep -qx "PS=/vb/busybox ps -o pid,stat,args" $BS/real.out && grep -qx zombie-seen $BS/real.out && grep -qx ours-running $BS/real.out && grep -qx stock-on $BS/real.out && grep -qx ours-stopped $BS/real.out && grep -qx stock-alive $BS/real.out'
  check "  진짜 busybox: od -b -v 바이트, f_perm·f_owner, md5sum 표준입력" 'grep -qx "od=000 005 150 151 377" $BS/real.out && grep -qx "perm=640 owner=0:0" $BS/real.out && grep -qx "md5=764efa883dda1e11db47671c4a3bbd9e  -" $BS/real.out'
else
  echo "skip 진짜 busybox 확인(Docker 또는 alpine:3.20 arm/v7 이미지 없음)"
fi

# 진단 USB 스크립트(kp-probe, kp-wifi-diag, kp-sys-restore)는 공개하지 않는다(차 기록·순정 파일이 필요하다).
# 공개 저장소에는 이 파일들이 없으므로 이 구역은 건너뛴다(패키지 테스트는 위에서 모두 돈다).
if [ -f $B/scripts/kp-probe.sh ] && [ -f $B/scripts/kp-wifi-diag.sh ] && [ -f $B/scripts/kp-sys-restore.sh ]; then
# ---- 탐사 USB(kp-probe.sh): busybox 없는 내비(K3 #15)용. 읽기만 하고, 비밀값을 남기지 않는다 ----
PR=$T/probe
mkdir -p $PR/bin $PR/usb $PR/wifi $PR/log $PR/apps/korea.projection
echo package-version=1.5.4 > $PR/apps/korea.projection/NEMESIS.data
# toolbox에 있는 명령만 둔다: busybox, awk, sed, head, tail, cut, tr, wc, od 실행 파일 없음
for c in ls cat grep mkdir cp mv rm chmod ln date dd sync id; do ln -s "$(command -v $c)" $PR/bin/$c; done
for c in getprop pm nemesis settings ps netstat; do ln -s $T/bin/$c $PR/bin/$c; done
# 진짜 sleep: 탐사의 시간 감시(bwait)가 실제 시간으로 돌아야 한다(가짜 sleep은 모든 명령을 바로 시간 초과로 만든다)
ln -s /bin/sleep $PR/bin/sleep
printf '#!/bin/sh\necho "$*" >> %s/toasts\n' $PR > $PR/bin/am
# 끝나지 않는 명령: run_to가 TO초 뒤 멈춰야 한다
printf '#!/bin/sh\nexec /bin/sleep 5\n' > $PR/bin/hmgapid
cat > $PR/bin/dmesg <<'E'
#!/bin/sh
echo "[   10.100000] dhd: Firmware version 7.10.323.48"
echo "[   10.200000] wlan0: link up a1:b2:c3:d4:e5:f6"
echo "[   10.300000] dhd: assoc ssid MyHomeNet"
echo "[   10.400000] wlan0: ip 192.168.43.7"
echo "[   10.500000] sdio: card ready"
E
chmod +x $PR/bin/*
echo "secret99 MyHomeNet" > $PR/wifi/softap.conf
echo 'network={ ssid="MyHomeNet" psk="secret99" }' > $PR/wifi/wpa_supplicant.conf
printf '11-06 10:00:00 시작 안 함: busybox가 없음\n11-06 10:00:01 폰 a1:b2:c3:d4:e5:f6 연결\n' > $PR/log/ap.log
echo "/dev/block/sda1 $PR/usb vfat rw 0 0" > $PR/mounts
sed "s#^export PATH=.*#export PATH=$PR/bin#" $B/scripts/kp-probe.sh > $PR/usb/NEMESIS.sh
probe() {  # $1: 셸 (sh 또는 ksh)
  rm -rf $PR/usb/kp-probe $PR/d $PR/toasts
  ln -sf "$(command -v $1)" $PR/bin/sh
  (cd /; KP_PROBE_TEST=1 D=$PR/d TO=2 TT=3 MOUNTS=$PR/mounts WIFIDIR=$PR/wifi APLOG=$PR/log/ap.log NAPPS=$PR/apps \
    $PR/bin/sh $PR/usb/NEMESIS.sh) > $PR/out 2>&1
  echo $? >> $PR/out
}
for SH in sh ksh; do
  command -v $SH >/dev/null || { bad "탐사 USB: $SH 없음"; continue; }
  probe $SH; PM=$PR/usb/kp-probe/probe.md
  check "탐사 USB($SH): 성공(0), USB에 probe.md·system-bin.txt, 끝까지 기록" '[ "$(tail -1 $PR/out)" = 0 ] && [ "$(tail -1 $PM)" = 끝 ] && grep -q "^== /system/bin" $PR/usb/kp-probe/system-bin.txt'
  check "  내비에 남긴 작업 폴더를 지움" '[ ! -e $PR/d ]'
  check "  비밀값(비밀번호·SSID·MAC·IP)이 결과에 없음" '! grep -r -q -E "secret99|MyHomeNet|a1:b2|192\.168\.43\.7" $PR/usb/kp-probe'
  check "  Wi-Fi 설정 파일은 이름과 크기만" 'grep -q "softap.conf" $PM && grep -q "wpa_supplicant.conf" $PM'
  check "  버전 줄과 일반 줄은 남김" 'grep -q "Firmware version 7.10.323.48" $PM && grep -q "sdio: card ready" $PM && grep -q "busybox가 없음" $PM'
  check "  끝나지 않는 명령은 TO초 뒤 멈춤, 다른 명령은 시간 초과가 없음" '[ "$(grep -c "시간 초과" $PM)" = 1 ] && grep -q "시간 초과 2초" $PM'
  check "  셸의 작업 종료 메시지(Terminated)가 결과에 섞이지 않음" '! grep -q -i "terminated" $PM'
  check "  없는 명령은 없음으로 적음" 'grep -q "^- busybox: 없음" $PM && grep -q "^- awk: 없음" $PM'
  check "  줄바꿈 없는 출력도 남김(dd로 읽은 hello)" 'grep -A1 "dd 가운데 5바이트" $PM | grep -q "> hello"'
  check "  설치된 패키지를 nemesis 명령 없이 폴더로 읽음" 'grep -q "^korea.projection package-version=1.5.4" $PM'
  check "  잠금(\$D.lock)을 끝나면 지움" '[ ! -e $PR/d.lock ]'
  check "  시작·끝 안내" 'grep -q "탐사를 시작합니다" $PR/toasts && grep -q "탐사가 끝났습니다" $PR/toasts'
done
# USB가 마운트돼 있지 않으면: 결과를 USB에 쓰지 않고 다시 꽂으라고 안내
: > $PR/mounts.none
rm -rf $PR/usb/kp-probe $PR/toasts; ln -sf "$(command -v sh)" $PR/bin/sh
(cd /; KP_PROBE_TEST=1 D=$PR/d TO=2 MOUNTS=$PR/mounts.none $PR/bin/sh $PR/usb/NEMESIS.sh) > $PR/out 2>&1
check "탐사 USB: USB를 못 찾으면 아무것도 쓰지 않고 다시 꽂으라고 안내" '[ ! -e $PR/usb/kp-probe ] && grep -q "USB를 찾지 못했습니다" $PR/toasts && [ ! -e $PR/d ]'
# 남은 잠금(죽은 실행의 것)은 지우고 진행
mkdir -p $PR/d.lock; echo 999999 > $PR/d.lock/pid
probe sh
check "탐사 USB: 죽은 실행이 남긴 잠금은 지우고 진행" '[ "$(tail -1 $PR/out)" = 0 ] && [ -f $PR/usb/kp-probe/probe.md ] && [ ! -e $PR/d.lock ]'
# 차에서는 경로를 환경 변수로 바꿀 수 없다(KP_PROBE_TEST가 없으면 D 등을 무시)
mkdir -p $PR/evil; : > $PR/evil/keep; rm -rf $PR/usb/kp-probe
(cd /; D=$PR/evil MOUNTS=$PR/mounts $PR/bin/sh $PR/usb/NEMESIS.sh) > $PR/out 2>&1
check "탐사 USB: 테스트 표시가 없으면 환경 변수 D·MOUNTS를 무시(다른 폴더를 지우지 않음)" '[ -f $PR/evil/keep ] && [ ! -e $PR/usb/kp-probe ] && [ ! -e $PR/usb/kp-probe-tmp ]'
check "탐사 USB: busybox를 부르지 않음" '! grep -v "^ *#" $B/scripts/kp-probe.sh | grep -q -E "\\\$BB|/system/bin/busybox"'
check "탐사 USB: 내비에 없는 명령(awk·sed·head·tail·cut·tr·wc·uniq·sort·setsid·killall)을 쓰지 않음" '! grep -v "^ *#" $B/scripts/kp-probe.sh | grep -q -E "(^|[|;&(] *)(awk|sed|head|tail|cut|tr|wc|uniq|sort|setsid|killall) "'
check "탐사 USB: 시스템을 바꾸는 명령(setprop·settings put·svc·pm install·nemesis install/uninstall·remount)이 없음" '! grep -v "^ *#" $B/scripts/kp-probe.sh | grep -q -E "(^|[|;&(] *)(setprop|settings put|svc|pm (install|uninstall)|nemesis (install|uninstall|remount)|hmgapid remount|mount) "'

# --- 니로 Wi-Fi 진단 USB 스크립트 (scripts/kp-wifi-diag.sh) ---
WD=$T/wd; rm -rf $WD; mkdir -p $WD/bin $WD/usb $WD/sys/net $WD/sys/mod/parameters $WD/data
mkparams() { mkdir -p $WD/sys/mod/parameters; echo wlan0 > $WD/sys/mod/parameters/iface_name; echo /data/misc/wifi/fw_bcmdhd.bin > $WD/sys/mod/parameters/firmware_path; echo /data/misc/wifi/bcmdhd.cal > $WD/sys/mod/parameters/nvram_path; echo /system/wifi/89359.clm_blob > $WD/sys/mod/parameters/clm_path; }
# Wi-Fi를 끄면 드라이버가 내려가고(wlan0 사라짐), 켜면 올라온다. $WD/stay가 있으면 꺼도 그대로
cat > $WD/bin/svc <<E
#!/bin/sh
echo "svc \$*" >> $WD/calls
case "\$2" in
  disable) [ -f $WD/stay ] || rm -rf $WD/sys/mod $WD/sys/net/wlan0 ;;
  enable) mkdir -p $WD/sys/net/wlan0; [ -d $WD/sys/mod ] || { mkdir -p $WD/sys/mod/parameters; [ -f $WD/noparams ] || { echo wlan0 > $WD/sys/mod/parameters/iface_name; echo /data/misc/wifi/fw_bcmdhd.bin > $WD/sys/mod/parameters/firmware_path; echo /data/misc/wifi/bcmdhd.cal > $WD/sys/mod/parameters/nvram_path; }; } ;;
esac
E
printf '#!/bin/sh\necho "insmod $*" >> %s/calls\nmkdir -p %s/sys/mod %s/sys/net/wlan0\n' $WD $WD $WD > $WD/bin/insmod
printf '#!/bin/sh\necho "rmmod $*" >> %s/calls\nrm -rf %s/sys/mod %s/sys/net/wlan0\n' $WD $WD $WD > $WD/bin/rmmod
printf '#!/bin/sh\necho "$*" >> %s/toasts\n' $WD > $WD/bin/am
printf '#!/bin/sh\n[ "$1" = get ] && echo 1\n' > $WD/bin/settings
printf '#!/bin/sh\necho "11-06 22:32:11.020 E/WifiStateMachine( 563): Connection lost, restart supplicant"\necho "11-06 22:32:11.060 D/WifiHW  ( 563): mac aa:bb:cc:dd:ee:ff ip 192.168.43.23"\necho "11-06 22:32:12.000 I/hostapd ( 9): conf PASS\\\\word99 here"\necho "11-06 22:32:12.100 I/BT ( 9): remote device name Johns iPhone"\necho "11-06 22:32:12.200 D/WifiHW ( 563): insmod args iface_name=wlan0 firmware_path=/x"\necho "11-06 22:32:12.300 I/BtConn ( 9): Connected to Kim'"'"'s phone"\n' > $WD/bin/logcat
printf '#!/bin/sh\necho "[  12.3] dhd: wlan0 MAC 11:22:33:44:55:66 loaded"\n' > $WD/bin/dmesg
printf '#!/bin/sh\necho "WifiStateMachine state: DriverStartedState"\necho "SSID: MyHomeNet"\n' > $WD/bin/dumpsys
printf '#!/bin/sh\necho 1.16.7\n' > $WD/bin/nemesis
printf '#!/bin/sh\ncat %s/ps 2>/dev/null\n' $WD > $WD/bin/ps
# sleep는 시계(uptime 파일)를 그만큼 앞으로 돌린다
printf '#!/bin/sh\nt=$(cat %s/uptime | cut -d. -f1); echo "$((t + ${1%%.*})).00 1.00" > %s/uptime\n' $WD $WD > $WD/bin/sleep
chmod +x $WD/bin/*
sed "s#^export PATH=.*#export PATH=$WD/bin:$T/bin:/usr/bin:/bin:/sbin#" $B/scripts/kp-wifi-diag.sh > $WD/diag.sh
echo "  1 root 1000 wpa_supplicant -iwlan0" > $WD/ps
wdreset() { rm -rf $WD/d $WD/usb/kp-wifidiag $WD/calls $WD/toasts $WD/stay $WD/noparams $WD/sys; mkdir -p $WD/sys/net/wlan0; mkparams; echo "100.00 1.00" > $WD/uptime; echo "/dev/block/sda1 $WD/usb vfat rw 0 0" > $WD/mounts; }
wdrun() { (cd $WD && BB=$T/bin/bb U=$WD/usb D=$WD/d APP=$T/app SRC=$T/softap.conf MOD=$WD/sys/mod NET=$WD/sys/net KO=/system/wifi/bcmdhd.ko APLOG=$WD/ap.log HMGLOG=$WD/hl MOUNTS=$WD/mounts INITRC=$WD/data/ UPT=$WD/uptime OBS_SEC=9 EXP_SEC=9 TICK=3 timeout 60 sh $WD/diag.sh) > $WD/out 2>&1; }
wdreset; wdrun
OB=$(ls -d $WD/usb/kp-wifidiag/out-OBS-* 2>/dev/null | head -1)
check "진단 1단계: 기록을 USB로 옮기고 다음은 2단계" '[ -n "$OB" ] && [ -s $OB/1-before.txt ] && [ -s $OB/2-timeline.txt ] && [ -s $OB/3-after.txt ] && [ -s $OB/logcat-before.txt ] && [ "$(cat $WD/d/step)" = EXP ] && [ -z "$(ls -d $WD/d/out-* 2>/dev/null)" ]'
check "  Wi-Fi를 껐다 켜고(순서대로) 시간표를 3초마다 남김, 끝에 안내" '[ "$(sed -n 1p $WD/calls)" = "svc wifi disable" ] && [ "$(sed -n 2p $WD/calls)" = "svc wifi enable" ] && [ "$(grep -c " | " $OB/2-timeline.txt)" -ge 5 ] && grep -q "1단계를 마쳤습니다" $WD/toasts'
check "  기록에 MAC·IP·카플레이 비밀번호·SSID 줄·기기 이름 줄이 없고, 드라이버 인자 줄은 남음" '! grep -r -q -i -e "aa:bb:cc" -e "11:22:33" -e "192.168.43.23" -e "word99" -e "MyHomeNet" -e "Johns" -e "Kim" $OB && grep -q "xx:xx:xx:xx:xx:xx" $OB/logcat-before.txt && grep -q "iface_name=wlan0" $OB/logcat-before.txt && grep -q "Connection lost" $OB/logcat-before.txt'
check "  설치 전 Wi-Fi 설정(wifi_on)을 적어 둠" '[ "$(cat $WD/d/wifi_on)" = 1 ]'
rm -f $WD/calls $WD/toasts; mkparams; wdrun
EX=$(ls -d $WD/usb/kp-wifidiag/out-EXP-* 2>/dev/null | head -1)
check "진단 2단계: Wi-Fi 서비스를 끄고 드라이버가 내려가면 읽어 둔 인자로 직접 올림, 끝에 내리고(rmmod) 되돌림" '[ -n "$EX" ] && grep -qx "insmod /system/wifi/bcmdhd.ko iface_name=wlan0 firmware_path=/data/misc/wifi/fw_bcmdhd.bin nvram_path=/data/misc/wifi/bcmdhd.cal clm_path=/system/wifi/89359.clm_blob" $WD/calls && [ "$(sed -n 1p $WD/calls)" = "svc wifi disable" ] && [ "$(sed -n 3p $WD/calls)" = "rmmod bcmdhd" ] && [ "$(sed -n 4p $WD/calls)" = "svc wifi enable" ] && [ "$(cat $WD/d/step)" = AFTER ]'
check "  아이폰 연결 안내 토스트" 'grep -q "아이폰으로 무선 카플레이를 연결해 보세요" $WD/toasts && grep -q "2단계를 마쳤습니다" $WD/toasts'
wdreset; echo EXP > $WD/d/step 2>/dev/null || { mkdir -p $WD/d; echo EXP > $WD/d/step; }; echo 1 > $WD/d/wifi_on; rm -rf $WD/sys/mod/parameters; mkdir -p $WD/sys/mod; wdrun
check "  드라이버 인자를 못 읽으면 직접 올리지 않음(추측하지 않음)" '! grep -q insmod $WD/calls && grep -r -q "인자를 읽지 못함" $WD/usb/kp-wifidiag'
wdreset; mkdir -p $WD/d; echo EXP > $WD/d/step; echo 1 > $WD/d/wifi_on; touch $WD/stay; wdrun
check "  Wi-Fi 서비스를 꺼도 드라이버가 그대로면 직접 올리지 않고 관찰만" '! grep -q insmod $WD/calls && grep -r -q "드라이버가 내려가지 않음" $WD/usb/kp-wifidiag'
wdreset; mkdir -p $WD/d; echo AFTER > $WD/d/step; echo 1 > $WD/d/wifi_on; wdrun
check "진단 3단계(재부팅 뒤): 모으기만 하고 끝, Wi-Fi는 건드리지 않음" '[ "$(cat $WD/d/step)" = DONE ] && [ ! -f $WD/calls ] && grep -q "모두 마쳤습니다" $WD/toasts'
wdreset; mkdir -p $WD/d; echo EXP > $WD/d/step; echo 0 > $WD/d/wifi_on; : > $WD/usb/kp-wifidiag-reset; wdrun; rm -f $WD/usb/kp-wifidiag-reset
check "되돌리기 파일: 실험 없이 설치 전 Wi-Fi 상태로(여기서는 꺼짐) 되돌리고 처음으로" '[ "$(cat $WD/calls)" = "svc wifi disable" ] && [ ! -f $WD/d/step ] && grep -q "처음으로 돌렸습니다" $WD/toasts'
wdreset; : > $WD/mounts; wdrun
check "USB가 떨어져 있으면 기록을 헤드유닛에 남김" '[ -n "$(ls -d $WD/d/out-OBS-* 2>/dev/null)" ] && grep -q "옮기지 못했습니다" $WD/toasts'
rm -f $WD/calls $WD/toasts; echo "/dev/block/sda1 $WD/usb vfat rw 0 0" > $WD/mounts; wdrun
check "  다음에 꽂으면 옮기기만 하고 다음 단계는 하지 않음" '[ -n "$(ls -d $WD/usb/kp-wifidiag/out-OBS-* 2>/dev/null)" ] && [ ! -f $WD/calls ] && [ "$(cat $WD/d/step)" = EXP ] && grep -q "지난번 기록을 USB로 옮겼습니다" $WD/toasts'
wdreset; mkdir -p $WD/d; echo EXP > $WD/d/step; : > $WD/usb/kp-wifidiag-reset; wdrun; rm -f $WD/usb/kp-wifidiag-reset
check "  설치 전 Wi-Fi 기록이 없으면 되돌리기는 켬(끄지 않음)" '[ "$(cat $WD/calls)" = "svc wifi enable" ]'
wdreset; mkdir -p $WD/d.lock; echo $$ > $WD/d.lock/pid; wdrun
check "  잠금이 남아 있어도 그 프로세스가 진단이 아니면 이어서 진행(남은 잠금 정리)" '[ "$(cat $WD/d/step)" = EXP ] && [ ! -d $WD/d.lock ]'
echo NIROX.KOR.0000.V039.001.260902 > $T/product; wdreset; wdrun; rm -f $T/product
check "  니로가 아니면 아무것도 하지 않음" '[ ! -f $WD/calls ] && grep -q "니로 하이브리드 전용" $WD/toasts'
wdreset; mkdir -p $WD/d; echo EXP > $WD/d/step; printf '1-before remove!\n' > $WD/usb/kp-wifidiag-snap; wdrun
SN=$(ls -d $WD/usb/kp-wifidiag/out-SNAP-1-beforeremove-* 2>/dev/null | head -1)
check "상태 사진(읽기 전용): Wi-Fi·드라이버를 건드리지 않고 단계도 그대로, 이름은 첫 줄의 영문·숫자" '[ -n "$SN" ] && [ -s $SN/1-now.txt ] && [ -s $SN/logcat-now.txt ] && [ ! -f $WD/calls ] && [ "$(cat $WD/d/step)" = EXP ] && [ ! -f $WD/d/wifi_on ] && grep -q "상태 사진(1-beforeremove)을 USB에 저장" $WD/toasts'
check "  흔적 찾기 항목(영구 속성, /data/misc/wifi 시각, 설정 목록, 시스템 파일 md5)" 'grep -q "흔적 찾기: 영구 속성" $SN/1-now.txt && grep -q "흔적 찾기: /data/misc/wifi" $SN/1-now.txt && grep -q "흔적 찾기: 설정 전체" $SN/1-now.txt && grep -q "app_process" $SN/1-now.txt'
wdreset; rm -f $WD/d/step; cp $T/app/svc/hotspot.sh $WD/usb/kp-hotspot-lib.sh; wdrun2() { (cd $WD && BB=$T/bin/bb U=$WD/usb D=$WD/d APP=$WD/noapp SRC=$T/softap.conf MOD=$WD/sys/mod NET=$WD/sys/net APLOG=$WD/ap.log HMGLOG=$WD/hl MOUNTS=$WD/mounts INITRC=$WD/data/ UPT=$WD/uptime timeout 60 sh $WD/diag.sh) > $WD/out 2>&1; }; wdrun2
SN=$(ls -d $WD/usb/kp-wifidiag/out-SNAP-* 2>/dev/null | head -1)
check "  우리 패키지가 없어도(NEMESIS 재설치 직후) USB의 해석기 사본으로 비밀번호를 가림" '[ -n "$SN" ] && ! grep -r -q "word99" $SN && grep -q "\[가림\]" $SN/logcat-now.txt && ! grep -q "주의: softap.conf" $SN/1-now.txt'
wdreset; rm -f $WD/usb/kp-hotspot-lib.sh; wdrun2; rm -f $WD/usb/kp-wifidiag-snap
SN=$(ls -d $WD/usb/kp-wifidiag/out-SNAP-* 2>/dev/null | head -1)
check "  해석기가 아예 없으면 그 사실을 남김(줄 단위로는 계속 거름)" 'grep -q "주의: softap.conf" $SN/1-now.txt'
printf '#!/bin/sh\necho "Row: 0 _id=1, name=wifi_on, value=1"\necho "Row: 1 _id=2, name=device_vin_code, value=KMHXX00000"\necho "Row: 2 _id=3, name=bluetooth_name, value=Kim phone"\n' > $WD/bin/content; chmod +x $WD/bin/content
wdreset; printf 'x\n' > $WD/usb/kp-wifidiag-snap; wdrun
SN=$(ls -d $WD/usb/kp-wifidiag/out-SNAP-* 2>/dev/null | head -1)
check "  settings list가 없으면 content query로 읽어 이름=값으로, 차대번호·기기 이름 줄은 버림" 'grep -q "content query로 읽음" $SN/1-now.txt && grep -qx "wifi_on=1" $SN/1-now.txt && ! grep -r -q -e "KMHXX" -e "Kim phone" $SN'
wdreset; mkdir -p $WD/d/out-OBS-old; echo old > $WD/d/out-OBS-old/x.txt; printf 'y\n' > $WD/usb/kp-wifidiag-snap; wdrun
check "  지난 기록이 남아 있어도 옮긴 뒤 이어서 상태 사진을 찍음" '[ -f $WD/usb/kp-wifidiag/out-OBS-old/x.txt ] && [ -n "$(ls -d $WD/usb/kp-wifidiag/out-SNAP-y-* 2>/dev/null)" ]'
wdreset; mkdir -p $WD/d; echo EXP > $WD/d/step; printf 'z\n' > $WD/usb/kp-wifidiag-snap; : > $WD/usb/kp-wifidiag-reset; wdrun; rm -f $WD/usb/kp-wifidiag-reset $WD/usb/kp-wifidiag-snap
check "  되돌리기 파일과 함께 있어도 사진은 읽기만(Wi-Fi 안 건드림)" '[ ! -f $WD/calls ] && [ "$(cat $WD/d/step)" = EXP ] && [ -n "$(ls -d $WD/usb/kp-wifidiag/out-SNAP-z-* 2>/dev/null)" ]'
rm -f $WD/bin/content
# --- 5GHz 확인(읽기 전용, kp-wifidiag-band) ---
# 순정 softap.conf 형식 3: 보안 있음(4), 5GHz 149, 2.4GHz 1, 2.4GHz 사용 안 함, vendorSpecific "", apMode 0
python3 - $WD/softap-band.conf <<'E'
import struct,sys
u=lambda s:struct.pack('>H',len(s))+s.encode()
open(sys.argv[1],'wb').write(struct.pack('>i',3)+u('HotspotName1')+u('CarPlayNet7')+struct.pack('>i',4)+u('PASS\\word99')+u('ConnPass1234')+struct.pack('>ii',149,1)+b'\x00'+u('')+struct.pack('>i',0))
E
# wl은 받은 인자를 적고, 읽기 결과처럼 답한다. chanspecs는 $WD/wlhang가 있으면 멈춘다(제한 시간 확인)
cat > $WD/bin/wl <<E
#!/bin/sh
echo "\$*" >> $WD/wlcalls
case "\$3" in
  bands) echo "a b" ;;
  country) echo "KR (KR/2) KOREA, REPUBLIC OF" ;;
  chanspecs) [ -f $WD/wlhang ] && /bin/sleep 30; echo "36 (0xd024)"; echo "149 (0xd095)" ;;
  ver) echo "wl0: Nov 2022 version 9.87.51.7 (r729845 CY) FWID 01-f3ce00e mac aa:bb:cc:dd:ee:01" ;;
  cap) echo "ap sta wme 802.11d 802.11h rm cqa cac dualband ampdu amsdu radio_pwrsave btamp p2p proptxstatus mchan wds dwds csa wnm bsstrans mimo_ps ldpc vht-prop-rates dfsradar" ;;
  *) echo 1 ;;
esac
E
cat > $WD/bin/getprop <<E
#!/bin/sh
if [ \$# -eq 0 ]; then
  echo "[wifi.info.channel]: [149]"; echo "[ro.wifi.country]: [KR]"; echo "[wifi.info.factory_pw]: [FactSecret9]"; echo "[wifi.info.factory_ssid]: [FactNet]"
else exec $T/bin/getprop "\$@"; fi
E
printf '#!/bin/sh\necho "netd: hw_mode=%%s channel=%%d ieee80211ac=1 ht_capab=[HT40+]"\n' > $WD/sbin-netd; chmod +x $WD/bin/wl $WD/bin/getprop
# 커널 로그: 4단 드라이버 버전(남아야 함), IP·MAC(가려야 함). logcat: 개방형 netd 명령의 SSID(버려야 함)
mv $WD/bin/dmesg $WD/dmesg.orig; mv $WD/bin/logcat $WD/logcat.orig
printf '#!/bin/sh\necho "[ 5.0] dhd_module_init: Driver version 1.579.77.41.22 firmware version 9.87.51.7"\necho "[ 6.0] dhd: wl_cfg80211 channel 6 peer 192.168.43.23 mac 11:22:33:44:55:66"\n' > $WD/bin/dmesg
printf '#!/bin/sh\necho "11-07 03:00:00.000 D/NetdConnector( 563): SND -> {12 softap set wlan0 OpenNet5 broadcast 149 open}"\necho "11-07 03:00:01.000 D/WifiApConfigStore( 563): 5GHz channel is not valid"\n' > $WD/bin/logcat
chmod +x $WD/bin/dmesg $WD/bin/logcat
printf 'macaddr=aa:bb:cc:dd:ee:02\nccode=KR\nregrev=2\naa5g=3\nboardflags=0x10401001\n' > $WD/nvram.cal
mkdir -p $WD/sysbin $WD/wifi; cp $WD/sbin-netd $WD/sysbin/netd; echo hostapd > $WD/sysbin/hostapd; printf 'clm' > $WD/clm.blob
printf 'interface=wlan0\nssid=SecretNet\nchannel=149\nhw_mode=a\nieee80211n=1\nht_capab=[HT40+]\nwpa_passphrase=Secret123\n' > $WD/wifi/hostapd.conf
printf 'network={\n ssid="HomeNet"\n psk="HomePass"\n}\n' > $WD/wifi/wpa_supplicant.conf
bdrun() { (cd $WD && BB=$T/bin/bb U=$WD/usb D=$WD/d APP=$T/app SRC=$WD/softap-band.conf MOD=$WD/sys/mod NET=$WD/sys/net APLOG=$WD/ap.log HMGLOG=$WD/hl MOUNTS=$WD/mounts INITRC=$WD/data/ UPT=$WD/uptime WIFIDIR=$WD/wifi SYSBIN=$WD/sysbin CLM=$WD/clm.blob NVRAM=$WD/nvram.cal LIM_SEC=${LIMS:-10} LIMSLEEP=/bin/sleep timeout 60 sh $WD/diag.sh) > $WD/out 2>&1; }
bdreset() { wdreset; rm -rf $WD/wlcalls $WD/wlhang $WD/usb/kp-stock-private; mkdir -p $WD/d; echo EXP > $WD/d/step; : > $WD/usb/kp-wifidiag-band; }
bdreset; LIMS=7 bdrun
BD=$(ls -d $WD/usb/kp-wifidiag/out-BAND-* 2>/dev/null | head -1)
check "5GHz 확인: 기록만 남기고 Wi-Fi·드라이버·단계는 그대로, 끝에 안내" '[ -n "$BD" ] && [ -s $BD/1-band.txt ] && [ ! -f $WD/calls ] && [ "$(cat $WD/d/step)" = EXP ] && [ ! -f $WD/d/wifi_on ] && grep -q "5GHz 확인 기록을 USB에 저장" $WD/toasts && [ -z "$(ls -d $WD/d/out-* 2>/dev/null)" ]'
check "  지키는 쪽 sleep이 남지 않음(명령이 먼저 끝난 경우)" '! pgrep -f "/bin/sleep 7$" >/dev/null'
check "  wl은 값 없는 읽기 명령만 부름(wlan0 지정)" '[ -s $WD/wlcalls ] && ! grep -v -x -E "\-i wlan0 (ver|revinfo|bands|band|country|chanspec|chanspecs -b [25] -w (20|40|80)|cap|ap|apsta|mbss|nmode|vhtmode|spect|dfs_status)" $WD/wlcalls'
check "  칩·국가·5GHz 채널 목록이 기록에 남음" 'grep -q "KR (KR/2)" $BD/1-band.txt && grep -q "149 (0xd095)" $BD/1-band.txt && grep -q "dualband" $BD/1-band.txt && grep -q "^wl: " $BD/1-band.txt'
check "  4단 펌웨어·드라이버 버전은 지워지지 않고, MAC·IP는 가림" 'grep -q "version 9.87.51.7" $BD/1-band.txt && grep -q "1.579.77.41.22" $BD/1-band.txt && ! grep -q -e "aa:bb:cc" -e "11:22:33" -e "192.168.43.23" $BD/1-band.txt'
check "  nvram은 국가·대역 칸만(MAC 줄 없음), 드라이버 인자도 남김" 'grep -qx "ccode=KR" $BD/1-band.txt && grep -qx "aa5g=3" $BD/1-band.txt && ! grep -q -e macaddr -e "ee:02" $BD/1-band.txt && grep -q "param nvram_path=" $BD/1-band.txt'
check "  netd 명령 기록(SSID가 든 softap set 줄)은 버림" '! grep -q -e OpenNet5 -e "SND ->" $BD/1-band.txt && grep -q "5GHz channel is not valid" $BD/1-band.txt'
check "  softap.conf 숫자 칸: 5GHz 149, 2.4GHz 1, 2.4GHz 사용 0, 판정 5GHz 149번" 'grep -q "5GHz 채널 149, 2.4GHz 채널 1, 2.4GHz 사용 0, vendorSpecific 길이 0, apMode 0" $BD/1-band.txt && grep -q "판정: 순정 핫스팟을 켜면 5GHz 149번" $BD/1-band.txt'
check "  hostapd 설정은 대역·채널 줄만(SSID·비밀번호 줄 없음), 접속용 설정 파일은 읽지 않음" 'grep -qx "channel=149" $BD/1-band.txt && grep -qx "hw_mode=a" $BD/1-band.txt && grep -qx "ht_capab=\[HT40+\]" $BD/1-band.txt && ! grep -r -q -e SecretNet -e Secret123 -e HomeNet -e HomePass $BD'
check "  Wi-Fi 이름·비밀번호·공장 설정 비밀번호가 기록에 없음, 채널 속성은 남음" '! grep -r -q -e HotspotName1 -e CarPlayNet7 -e word99 -e ConnPass1234 -e FactSecret9 -e FactNet $BD && grep -q "wifi.info.channel" $BD/1-band.txt && grep -q "ro.wifi.country" $BD/1-band.txt'
SP=$(ls -d $WD/usb/kp-stock-private/* 2>/dev/null | head -1)
check "  netd 문자열·md5는 기록에, 순정 파일 사본은 제보 폴더 밖(kp-stock-private)에만" 'grep -q "ieee80211ac=1" $BD/1-band.txt && [ "$(grep -c "^md5 " $BD/1-band.txt)" = 2 ] && [ -f "$SP/netd" ] && [ -f "$SP/clm.blob" ] && [ -z "$(find $WD/usb/kp-wifidiag -name netd -o -name clm.blob)" ]'
# softap.conf가 다른 형식이거나 어긋나면 숫자(비밀번호 바이트일 수 있음)를 내지 않는다
sbcase() { python3 - $WD/softap-band.conf "$1" <<'E'
import struct,sys
u=lambda s:struct.pack('>H',len(s))+s.encode()
c=sys.argv[2]
if c=='open': d=struct.pack('>i',3)+u('HotspotName1')+u('CarPlayNet7')+struct.pack('>i',0)+struct.pack('>ii',36,6)+b'\x01'+u('')+struct.pack('>i',0)
elif c=='v1': d=struct.pack('>i',1)+u('HotspotName1')+struct.pack('>i',4)+u('PASS\\word99')+b'\x00'*12
elif c=='short': d=struct.pack('>i',3)+u('HotspotName1')+u('CarPlayNet7')+struct.pack('>i',4)+u('PASS\\word99')
else: d=struct.pack('>i',3)+u('HotspotName1')+u('CarPlayNet7')+struct.pack('>i',4)+u('PASS\\word99')+u('ConnPass1234')+b'wxyzabcd\x05'
open(sys.argv[1],'wb').write(d)
E
bdreset; bdrun; cat $WD/usb/kp-wifidiag/out-BAND-*/1-band.txt 2>/dev/null; }
check "  softap.conf 보안 없음(0): 비밀번호 칸 없이 읽고 2.4GHz 6번 판정" 'sbcase open | grep -q "판정: 순정 핫스팟을 켜면 2.4GHz 6번"'
check "  softap.conf 형식이 3이 아니면 숫자를 읽지 않음" 'o=$(sbcase v1); echo "$o" | grep -q "형식 다름(1" && ! echo "$o" | grep -q "5GHz 채널 "'
check "  softap.conf가 잘렸으면 채널 칸이 없다고만 적음" 'sbcase short | grep -q "채널 칸이 없음"'
check "  softap.conf 값이 범위 밖이면(칸이 어긋남) 숫자를 내지 않음" 'o=$(sbcase bad); echo "$o" | grep -q "예상 범위 밖" && ! echo "$o" | grep -q "5GHz 채널 "'
python3 - $WD/softap-band.conf <<'E'
import struct,sys
u=lambda s:struct.pack('>H',len(s))+s.encode()
open(sys.argv[1],'wb').write(struct.pack('>i',3)+u('HotspotName1')+u('CarPlayNet7')+struct.pack('>i',4)+u('PASS\\word99')+u('ConnPass1234')+struct.pack('>ii',149,1)+b'\x00'+u('')+struct.pack('>i',0))
E
bdreset; : > $WD/usb/kp-wifidiag-reset; : > $WD/usb/kp-wifidiag-ab; bdrun; rm -f $WD/usb/kp-wifidiag-reset $WD/usb/kp-wifidiag-ab
check "  되돌리기·A/B 파일이 함께 있어도 읽기만(Wi-Fi·A/B 단계 안 건드림)" '[ ! -f $WD/calls ] && [ "$(cat $WD/d/step)" = EXP ] && [ ! -f $WD/d/abstep ] && [ -n "$(ls -d $WD/usb/kp-wifidiag/out-BAND-* 2>/dev/null)" ]'
bdreset; touch $WD/wlhang; s0=$(date +%s); LIMS=1 bdrun; s1=$(date +%s)
BD=$(ls -d $WD/usb/kp-wifidiag/out-BAND-* 2>/dev/null | head -1)
check "  wl이 응답하지 않으면 한 번만 기다리고 남은 wl은 건너뛰어 끝냄" '[ -n "$BD" ] && grep -q "1초 안에 응답 없음" $BD/1-band.txt && grep -q "앞의 wl이 응답하지 않아 건너뜀" $BD/1-band.txt && grep -q "5GHz 채널 149" $BD/1-band.txt && [ $((s1 - s0)) -lt 15 ] && [ ! -f $WD/d/wl.dead ]'
bdreset; rm -rf $WD/sys/net/wlan0; mkdir -p $WD/d/out-OBS-old; echo old > $WD/d/out-OBS-old/x.txt; bdrun
check "  지난 기록이 남아 있으면 옮긴 뒤 이어서 기록, wlan0이 없어도 끝까지" '[ -f $WD/usb/kp-wifidiag/out-OBS-old/x.txt ] && [ -n "$(ls -d $WD/usb/kp-wifidiag/out-BAND-* 2>/dev/null)" ] && grep -r -q "wlan0: 없음" $WD/usb/kp-wifidiag/out-BAND-*'
bdreset; rm -f $WD/bin/wl; printf 'x\n' > $WD/usb/kp-wifidiag-snap; bdrun; rm -f $WD/usb/kp-wifidiag-snap
BD=$(ls -d $WD/usb/kp-wifidiag/out-BAND-* 2>/dev/null | head -1)
check "  wl이 없으면 그 사실을 남기고 끝까지, 상태 사진 파일은 이번에 하지 않았다고 적음" 'grep -q "^wl: 없음" $BD/1-band.txt && grep -q "5GHz 채널 149" $BD/1-band.txt && grep -q "kp-wifidiag-snap 파일도 있었지만" $BD/1-band.txt && [ -z "$(ls -d $WD/usb/kp-wifidiag/out-SNAP-* 2>/dev/null)" ]'
bdreset; : > $WD/mounts; bdrun
check "  USB가 떨어져 있으면 기록을 헤드유닛에 남기고 안내" '[ -n "$(ls -d $WD/d/out-BAND-* 2>/dev/null)" ] && grep -q "기록을 USB에 옮기지 못했습니다" $WD/toasts'
echo "/dev/block/sda1 $WD/usb vfat rw 0 0" > $WD/mounts; rm -f $WD/usb/kp-wifidiag-band $WD/toasts; wdrun
check "  다음에 꽂으면 옮김" '[ -n "$(ls -d $WD/usb/kp-wifidiag/out-BAND-* 2>/dev/null)" ] && grep -q "지난번 기록을 USB로 옮겼습니다" $WD/toasts'
rm -f $WD/usb/kp-wifidiag-band $WD/bin/wl $WD/bin/getprop $WD/wlcalls $WD/wlhang $WD/nvram.cal; rm -rf $WD/sysbin $WD/wifi $WD/usb/kp-stock-private
mv $WD/dmesg.orig $WD/bin/dmesg; mv $WD/logcat.orig $WD/bin/logcat
# --- 5GHz 시험 (kp-wifidiag-5g) ---
# ps는 " #L"로 끝나는 줄을 살아 있는 프로세스일 때만 보인다(좀비도 뺀다: 헤드유닛 ps의 " Z " 거르기와 같음)
mv $WD/bin/ps $WD/ps.stub.orig; mv $WD/bin/sleep $WD/sleep.stub.orig; mv $WD/bin/dmesg $WD/dmesg.orig5
cat > $WD/bin/ps <<E
#!/bin/sh
while IFS= read -r l; do
  case "\$l" in
    *" #L") set -- \$l; st=\$(/bin/ps -o stat= -p \$1 2>/dev/null); case "\$st" in ""|Z*) ;; *) echo "\${l% #L}" ;; esac ;;
    *) echo "\$l" ;;
  esac
done < $WD/ps
E
# sleep는 시계를 앞으로 돌리고, 뒤에서 뜬 가짜 hostapd가 기록을 쓸 틈을 조금 준다
printf '#!/bin/sh\n/bin/sleep 0.3\nt=$(cat %s/uptime | cut -d. -f1); echo "$((t + ${1%%.*})).00 1.00" > %s/uptime\n' $WD $WD > $WD/bin/sleep
printf '#!/bin/sh\ncat %s/dmesg.log 2>/dev/null\n' $WD > $WD/bin/dmesg
printf '#!/bin/sh\necho "tcp 0 0 127.0.0.1:5037 127.0.0.1:40000 ESTABLISHED"\necho "tcp 0 0 192.168.43.1:7000 192.168.43.23:49000 TIME_WAIT"\n[ -f %s/cpold ] && echo "tcp 0 0 192.168.43.1:7000 192.168.43.30:51000 ESTABLISHED"\n[ -f %s/cpon ] && echo "tcp 0 0 192.168.43.1:7000 192.168.43.23:52000 ESTABLISHED"\nexit 0\n' $WD $WD > $WD/bin/netstat
printf '#!/bin/sh\necho "ifconfig $*" >> %s/ifcalls\n' $WD > $WD/bin/ifconfig
# 가짜 hostapd: 채널 6, 또는 h5ok에 "채널:국가"가 있으면 커널 로그에 채널·AP 줄을 남기고 계속 돈다. 아니면 바로 끝난다.
# cp5가 있으면 5GHz에서 아이폰이 붙는다. pullusb가 있으면 5GHz로 뜬 뒤 USB가 빠진다.
cat > $WD/bin/hostapd <<E
#!/bin/sh
c=\$1; ch=\$(sed -n 's/^channel=//p' \$c); cc=\$(sed -n 's/^country_code=//p' \$c)
echo "\$ch:\$cc:\$(sed -n 's/^hw_mode=//p' \$c)" >> $WD/hcalls
[ -f $WD/svcdup ] && [ "\$ch" != 6 ] && { rm -f $WD/svcdup; echo "11-07 16:00:00 hostapd 시작" >> $WD/ap.log; }
[ -f $WD/wrap ] && { tail -n 1 $WD/dmesg.log > $WD/dmesg.t; mv $WD/dmesg.t $WD/dmesg.log; }
if { [ "\$ch" = 6 ] && [ ! -f $WD/fail6 ]; } || grep -qx "\$ch:\$cc" $WD/h5ok 2>/dev/null; then
  echo "[ 99.0] CFG80211-ERROR) wl_cfg80211_set_channel : netdev_ifidx(10), chan_type(1) target channel(\$ch) channel_width(1000)" >> $WD/dmesg.log
  echo "[ 99.1] CFG80211-ERROR) wl_notify_connect_status_ap : ** AP/GO Link up event ** peer aa:bb:cc:dd:ee:09 192.168.43.23" >> $WD/dmesg.log
  if [ "\$ch" = 6 ]; then rm -f $WD/cpon; else [ -f $WD/cp5 ] && : > $WD/cpon; [ -f $WD/pullusb ] && : > $WD/mounts; fi
  echo "Using interface wlan0 with hwaddr aa:bb:cc:dd:ee:09 and ssid \"SSID\\\\cX\""
  echo "wlan0: AP-ENABLED key PASS\\\\word99"
  echo "  \$\$ root 1000 S hostapd \$c #L" >> $WD/ps
  exec /bin/sleep 597
fi
echo "Line 3: Could not set channel for kernel driver"
exit 1
E
chmod +x $WD/bin/ps $WD/bin/sleep $WD/bin/dmesg $WD/bin/netstat $WD/bin/ifconfig $WD/bin/hostapd
HC=$WD/hconf
printf 'interface=wlan0\ndriver=nl80211\nctrl_interface=/data/misc/wifi/hostapd\nssid=SSID\\cX\nchannel=6\nhw_mode=g\nieee80211n=1\nmax_num_sta=5\nwpa=2\nwpa_passphrase=PASS\\word99\n' > $WD/hconf.orig
t5kill() { pkill -f "sleep 597" 2>/dev/null; /bin/sleep 0.3; }
# $1=1: 우리 6번 hostapd가 돌고 있는 상태로 시작
t5reset() {
  t5kill; wdreset; rm -rf $WD/hcalls $WD/h5ok $WD/cp5 $WD/cpon $WD/cpold $WD/pullusb $WD/ifcalls $WD/svcdup $WD/fail6 $WD/wrap $WD/usb/kp-wifidiag-reset; : > $WD/ap.log
  mkdir -p $WD/d; echo EXP > $WD/d/step; : > $WD/usb/kp-wifidiag-5g
  cp $WD/hconf.orig $HC; chmod 660 $HC
  echo "[ 21.1] Firmware version = wl0: version 9.92.1" > $WD/dmesg.log
  echo "  1 root 1000 wpa_supplicant -iwlan0" > $WD/ps
  if [ "${1:-1}" = 1 ]; then /bin/sleep 597 & echo "  $! root 1000 S hostapd $HC #L" >> $WD/ps; fi
}
t5run() { (cd $WD && BB=$T/bin/bb U=$WD/usb D=$WD/d APP=$T/app SRC=$T/softap.conf MOD=$WD/sys/mod NET=$WD/sys/net APLOG=$WD/ap.log HMGLOG=$WD/hl MOUNTS=$WD/mounts INITRC=$WD/data/ UPT=$WD/uptime HCONF=$HC KMSG=$WD/dmesg.log T5_UP=4 T5_SEC=20 T5_TICK=5 LIM_SEC=3 LIMSLEEP=/bin/sleep timeout 120 sh $WD/diag.sh) > $WD/out 2>&1; }
t5live() { $WD/bin/ps | grep -c "hostapd $HC"; }
t5reset; echo "149:" > $WD/h5ok; : > $WD/cp5; t5run
R5=$(ls -d $WD/usb/kp-wifidiag/out-5G-* 2>/dev/null | head -1)
check "5GHz 시험: 149번으로 띄워 카플레이 연결을 기록하고 6번으로 되돌림" '[ -n "$R5" ] && grep -q "판정: 5GHz 149번에서 카플레이 연결됨" $R5/1-5g.txt && [ "$(sed -n 1p $WD/hcalls)" = "149::a" ] && [ "$(sed -n "\$p" $WD/hcalls)" = "6::g" ] && [ "$(wc -l < $WD/hcalls | tr -d " ")" = 2 ]'
check "  설정 파일은 원래 내용·권한 그대로, 우리 hostapd는 하나만 돎, 백업·출력은 헤드유닛에서 지움" 'cmp -s $HC $WD/hconf.orig && [ "$(stat -f %Lp $HC 2>/dev/null || stat -c %a $HC)" = 660 ] && [ "$(t5live)" = 1 ] && [ -z "$(ls $WD/d/h5-* 2>/dev/null)" ] && grep -q "2.4GHz 6번으로 다시 켜짐" $R5/1-5g.txt'
check "  Wi-Fi 이름·비밀번호·MAC·IP가 기록에 없음, 채널 줄은 남음" '! grep -r -q -e "SSID.cX" -e "word99" -e "aa:bb:cc" -e "192.168.43.23" $WD/usb/kp-wifidiag && grep -q "target channel(149)" $R5/1-5g.txt && grep -q "바꾼 줄: channel=149 hw_mode=a ieee80211n=1" $R5/1-5g.txt'
check "  단계·Wi-Fi 서비스는 그대로, 안내 토스트(시작·5GHz·연결·끝)" '[ "$(cat $WD/d/step)" = EXP ] && ! grep -q "^svc" $WD/calls 2>/dev/null && grep -q "5GHz 149번으로 바꿨습니다" $WD/toasts && grep -q "5GHz에서 카플레이가 연결됐습니다. 음악" $WD/toasts && grep -q "5GHz에서 카플레이가 연결됐습니다. USB를 빼셔도 됩니다" $WD/toasts'
check "  연결 기록이 간격마다 남음, wl은 -i 있이·없이 한 번씩" '[ "$(grep -c -E "^[0-9]+ \| 1 \| 1$" $R5/1-5g.txt)" -ge 2 ] && grep -q -- "--- wl chanspec" $R5/1-5g.txt && grep -q -- "--- wl -i wlan0 chanspec" $R5/1-5g.txt'
t5reset; echo "36:KR" > $WD/h5ok; t5run
R5=$(ls -d $WD/usb/kp-wifidiag/out-5G-* 2>/dev/null | head -1)
check "  149번이 안 되면 149번+KR, 36번+KR 순서로, 카플레이가 안 붙으면 그렇게 판정" '[ "$(tr "\n" " " < $WD/hcalls)" = "149::a 6::g 149:KR:a 6::g 36:KR:a 6::g " ] || [ "$(tr "\n" " " < $WD/hcalls)" = "149::a 149:KR:a 36:KR:a 6::g " ]; r=$?; [ $r = 0 ] && grep -q "판정: 5GHz 36번 AP는 올라왔지만" $R5/1-5g.txt && cmp -s $HC $WD/hconf.orig && [ "$(t5live)" = 1 ] && grep -q "켜졌지만 카플레이는 붙지 않았습니다. 내비를 한 번 재부팅" $WD/toasts && grep -q "국가(KR)를 넣어 시도했습니다" $R5/1-5g.txt'
check "  실패한 시도는 hostapd 오류와 사유를 남김" 'grep -q "Could not set channel" $R5/1-5g.txt && grep -q "결과: 실패(hostapd가 꺼짐)" $R5/1-5g.txt && grep -q "country_code=KR" $R5/1-5g.txt'
t5reset; t5run
R5=$(ls -d $WD/usb/kp-wifidiag/out-5G-* 2>/dev/null | head -1)
check "  5GHz가 모두 안 되면 6번으로 되돌리고 안내" 'grep -q "판정: 5GHz로 AP를 띄우지 못함" $R5/1-5g.txt && [ "$(sed -n "\$p" $WD/hcalls)" = "6::g" ] && cmp -s $HC $WD/hconf.orig && [ "$(t5live)" = 1 ] && grep -q "5GHz 핫스팟을 켜지 못했습니다" $WD/toasts'
t5reset 0; t5run
R5=$(ls -d $WD/usb/kp-wifidiag/out-5G-* 2>/dev/null | head -1)
check "  우리 hostapd가 안 돌면 아무것도 바꾸지 않음" '[ ! -f $WD/hcalls ] && cmp -s $HC $WD/hconf.orig && grep -q "중단: 우리 핫스팟이 돌고 있지 않아" $R5/1-5g.txt && grep -q "시험하지 않았습니다" $WD/toasts'
t5reset; sed -i.b 's/^channel=6/channel=11/' $HC; rm -f $HC.b; cp $HC $WD/hconf.11; t5run
check "  설정 파일이 예상한 모양(6번·g)이 아니면 바꾸지 않음" '[ ! -f $WD/hcalls ] && cmp -s $HC $WD/hconf.11 && grep -r -q "예상한 모양" $WD/usb/kp-wifidiag'
t5reset; echo "149:" > $WD/h5ok; : > $WD/pullusb; t5run
check "  기록 중 USB가 빠지면 바로 6번으로 되돌리고 기록은 헤드유닛에 남김" '[ "$(sed -n "\$p" $WD/hcalls)" = "6::g" ] && cmp -s $HC $WD/hconf.orig && [ "$(t5live)" = 1 ] && grep -q "USB가 빠져 기록을 멈춤" $WD/d/out-5G-*/1-5g.txt && grep -q "다음에 꽂으면 옮깁니다" $WD/toasts && [ -z "$(ls $WD/d/h5-* 2>/dev/null)" ]'
t5reset; echo "149:" > $WD/h5ok; : > $WD/usb/kp-wifidiag-reset; t5run
check "  되돌리기 파일이 함께 있어도 단계는 그대로(5GHz 시험만)" '[ "$(cat $WD/d/step)" = EXP ] && ! grep -q "^svc" $WD/calls 2>/dev/null && [ -n "$(ls -d $WD/usb/kp-wifidiag/out-5G-* 2>/dev/null)" ]'
t5reset; echo "149:" > $WD/h5ok; : > $WD/cpold; t5run
R5=$(ls -d $WD/usb/kp-wifidiag/out-5G-* 2>/dev/null | head -1)
check "  시험 전부터 있던 카플레이 연결·끊긴 연결은 5GHz 연결로 세지 않음" 'grep -q "판정: 5GHz 149번 AP는 올라왔지만" $R5/1-5g.txt && grep -q "카플레이 연결: 1" $R5/1-5g.txt && [ -z "$(ls $WD/d/cp0 $WD/d/cp1 2>/dev/null)" ]'
t5reset; echo "149:" > $WD/h5ok; : > $WD/cp5; : > $WD/svcdup; t5run
R5=$(ls -d $WD/usb/kp-wifidiag/out-5G-* 2>/dev/null | head -1)
check "  서비스의 30초 점검과 겹치면 모두 멈추고 다시 띄움(하나만 남김)" 'grep -q "서비스의 30초 점검과 겹쳐" $R5/1-5g.txt && grep -q "판정: 5GHz 149번에서 카플레이 연결됨" $R5/1-5g.txt && [ "$(t5live)" = 1 ] && cmp -s $HC $WD/hconf.orig'
t5reset; echo "149:" > $WD/h5ok; : > $WD/wrap; t5run
R5=$(ls -d $WD/usb/kp-wifidiag/out-5G-* 2>/dev/null | head -1)
check "  커널 로그 버퍼가 차서 표시 줄이 밀려도 채널 줄로 판정" 'grep -q "결과: 성공(5GHz 149번" $R5/1-5g.txt'
t5reset; echo "149:" > $WD/h5ok; : > $WD/fail6; t5run
R5=$(ls -d $WD/usb/kp-wifidiag/out-5G-* 2>/dev/null | head -1)
check "  6번으로 다시 못 띄우면 재부팅을 안내(되돌렸다고 하지 않음)" 'cmp -s $HC $WD/hconf.orig && grep -q "hostapd: 꺼져 있음(내비 재부팅 권함)" $R5/1-5g.txt && grep -q "내비를 한 번 재부팅해 주세요" $WD/toasts && ! grep -q "다시 켜짐" $R5/1-5g.txt'
# 강제로 끝나 5GHz 설정·백업이 남은 채 다시 꽂으면 먼저 되돌리고 백업을 지움
t5reset 0; cp $WD/hconf.orig $WD/d/h5-orig.conf; sed 's/^channel=6/channel=149/; s/^hw_mode=g/hw_mode=a/' $WD/hconf.orig > $HC; echo secret > $WD/d/h5.log
/bin/sleep 597 & echo "  $! root 1000 S hostapd $HC #L" >> $WD/ps; rm -f $WD/usb/kp-wifidiag-5g; : > $WD/usb/kp-wifidiag-band; t5run; rm -f $WD/usb/kp-wifidiag-band
check "  지난 시험이 강제로 끝나 5GHz 설정이 남았으면 다시 꽂을 때 먼저 되돌리고 백업·출력을 지움" 'cmp -s $HC $WD/hconf.orig && [ "$(t5live)" = 0 ] && [ -z "$(ls $WD/d/h5-* 2>/dev/null)" ] && grep -q "지난 5GHz 시험 설정을 2.4GHz로 되돌렸습니다" $WD/toasts'
# 도중에 끝나도(TERM) 되돌림: 연결 기록 중에 진단을 죽인다
t5reset; echo "149:" > $WD/h5ok
(cd $WD && BB=$T/bin/bb U=$WD/usb D=$WD/d APP=$T/app SRC=$T/softap.conf MOD=$WD/sys/mod NET=$WD/sys/net APLOG=$WD/ap.log HMGLOG=$WD/hl MOUNTS=$WD/mounts INITRC=$WD/data/ UPT=$WD/uptime HCONF=$HC KMSG=$WD/dmesg.log T5_UP=4 T5_SEC=600 T5_TICK=5 LIM_SEC=3 LIMSLEEP=/bin/sleep sh $WD/diag.sh > $WD/out 2>&1 & echo $! > $WD/t5.pid; wait) &
_w=0; while ! grep -q "5GHz 149번으로 바꿨습니다" $WD/toasts 2>/dev/null && [ $_w -lt 60 ]; do /bin/sleep 0.5; _w=$((_w+1)); done
/bin/sleep 1; kill $(cat $WD/d.lock/pid 2>/dev/null) 2>/dev/null; _w=0; while [ -d $WD/d.lock ] && [ $_w -lt 40 ]; do /bin/sleep 0.5; _w=$((_w+1)); done
check "  기록 중에 진단이 멈추면(TERM) 바로 설정 파일을 되돌리고 5GHz hostapd를 멈춤(6번은 서비스가 띄움)" 'cmp -s $HC $WD/hconf.orig && [ "$(t5live)" = 0 ] && [ -z "$(ls $WD/d/h5-* 2>/dev/null)" ] && grep -r -q "멈춤: 설정 파일만 되돌리고" $WD/usb/kp-wifidiag $WD/d/out-5G-* 2>/dev/null'
t5kill; rm -f $WD/cpold $WD/svcdup $WD/fail6 $WD/wrap $WD/usb/kp-wifidiag-5g $WD/bin/netstat $WD/bin/ifconfig $WD/bin/hostapd $WD/hcalls $WD/h5ok $WD/cp5 $WD/cpon $WD/pullusb $WD/ifcalls $WD/dmesg.log $HC $WD/hconf.orig $WD/hconf.11 $WD/t5.pid
mv $WD/ps.stub.orig $WD/bin/ps; mv $WD/sleep.stub.orig $WD/bin/sleep; mv $WD/dmesg.orig5 $WD/bin/dmesg
echo "  1 root 1000 wpa_supplicant -iwlan0" > $WD/ps
# --- A/B 시험 (root 소유 Wi-Fi 설정 파일) ---
# 이 PC에서는 다른 사용자로 소유자를 바꿀 수 없어, chown은 소유자를 옆 파일(<파일>.owner)에 적고 ls -ln은 그것을 보여 준다
AB=$WD/ab; mkdir -p $AB
cat > $WD/bin/chown <<E
#!/bin/sh
echo "chown \$*" >> $WD/calls
[ -f $WD/chown_fail ] && exit 1
echo "\$1" > "\$2.owner"
E
cat > $WD/bin/ls <<E
#!/bin/sh
if [ "\$1" = -ln ]; then
  case "\$2" in $AB/*)
    [ -e "\$2" ] || exit 1
    o=\$(cat "\$2.owner" 2>/dev/null || echo 0:0); echo "-rw-rw----    1 \${o%%:*}        \${o#*:}              88 Nov  2 17:25 \$2"; exit 0 ;;
  esac
fi
exec /bin/ls "\$@"
E
# mv는 옆 파일(소유자 기록)도 같이 옮긴다
cat > $WD/bin/mv <<E
#!/bin/sh
[ "\$1" = -f ] && shift
[ -f "\$1.owner" ] && /bin/mv -f "\$1.owner" "\$2.owner"
exec /bin/mv -f "\$1" "\$2"
E
chmod +x $WD/bin/chown $WD/bin/ls $WD/bin/mv
C=$AB/wpa_supplicant.conf; CR=$AB/wpa_supplicant_crc32.conf
abreset() { wdreset; rm -rf $AB/* $WD/chown_fail; printf 'network={\n ssid="OldTestNet"\n}\n' > $C; echo 0:0 > $C.owner; : > $WD/usb/kp-wifidiag-ab; }
abrun() { (cd $WD && BB=$T/bin/bb U=$WD/usb D=$WD/d APP=$T/app SRC=$T/softap.conf MOD=$WD/sys/mod NET=$WD/sys/net APLOG=$WD/ap.log HMGLOG=$WD/hl MOUNTS=$WD/mounts INITRC=$WD/data/ UPT=$WD/uptime OBS_SEC=6 TICK=3 WCONF=$C timeout 60 sh $WD/diag.sh) > $WD/out 2>&1; }
abreset; abrun
check "A/B 시험 A: 원래 상태(소유자 root, 권한 660, crc32 없음)를 백업하고 단계 B를 적은 뒤 정상 소유자로 바꿈" '[ "$(cat $C.owner)" = 1000:1010 ] && [ "$(cat $WD/d/ab-orig)" = "0:0 660 absent" ] && cmp -s $WD/d/ab-conf.bak $C && [ "$(cat $WD/d/abstep)" = B ] && ! grep -q "^svc" $WD/calls && grep -q "B를 꼭 진행" $WD/toasts'
check "  백업 내용(옛 Wi-Fi 이름)은 USB로 가지 않음" '! grep -r -q -e "OldTestNet" -e "network={" $WD/usb/kp-wifidiag'
rm -f $WD/d/abstep; abrun
check "  A가 끊겨 다시 돌아도 원래 소유자 기록(root)을 덮어쓰지 않음" '[ "$(cat $WD/d/ab-orig)" = "0:0 660 absent" ] && [ "$(cat $C.owner)" = 1000:1010 ]'
printf 'recreated OldTestNet\n' > $C; echo 1000:1010 > $C.owner; echo crc > $CR; echo 1000:1010 > $CR.owner; rm -f $WD/toasts; abrun
check "A/B 시험 B: 원래 내용·소유자(root)로 되돌리고 새로 생긴 crc32 파일은 지움, 확인 뒤 C로" '[ "$(cat $C.owner)" = 0:0 ] && grep -q "ssid=\"OldTestNet\"" $C && [ ! -e $CR ] && [ "$(cat $WD/d/abstep)" = C ] && grep -q "B 끝" $WD/toasts && [ -s "$(ls -d $WD/usb/kp-wifidiag/out-AB-B-* | head -1)/3-count.txt" ]'
check "  기록에 옛 Wi-Fi 이름이 남지 않음(백업의 ssid 값도 가림)" '! grep -r -q "OldTestNet" $WD/usb/kp-wifidiag'
printf 'changed at boot\n' > $C; rm -f $WD/toasts; abrun
check "A/B 시험 C: 부팅 중 바뀌었으면 다시 되돌리고 백업 유지, 단계는 C 그대로" '[ "$(cat $WD/d/abstep)" = C ] && [ -f $WD/d/ab-conf.bak ] && grep -q "ssid=\"OldTestNet\"" $C && grep -q "한 번 더 재부팅" $WD/toasts'
rm -f $WD/toasts; abrun
check "  원래와 같으면 백업 삭제·끝" '[ "$(cat $WD/d/abstep)" = DONE ] && [ ! -f $WD/d/ab-conf.bak ] && [ ! -f $WD/d/ab-orig ] && grep -q "모두 마쳤습니다" $WD/toasts'
abreset; abrun; touch $WD/chown_fail; rm -f $WD/toasts; abrun; rm -f $WD/chown_fail
check "  B에서 되돌리기를 확인하지 못하면 B에 머물고 실패 안내(백업 유지)" '[ "$(cat $WD/d/abstep)" = B ] && [ -f $WD/d/ab-conf.bak ] && grep -q "확인하지 못했습니다" $WD/toasts'
: > $WD/usb/kp-wifidiag-reset; rm -f $WD/toasts; abrun; rm -f $WD/usb/kp-wifidiag-reset
check "  되돌리기 파일과 함께: 백업으로 원래대로(root), 단계 처음으로" '[ "$(cat $C.owner)" = 0:0 ] && [ ! -f $WD/d/abstep ] && grep -q "원래대로 되돌렸습니다" $WD/toasts'
abreset; echo crc0 > $CR; echo 1000:1010 > $CR.owner; abrun; rm -f $CR $CR.owner; rm -f $WD/toasts; abrun
check "  crc32 파일이 원래 있었으면 내용·소유자까지 되돌림" '[ "$(cat $CR 2>/dev/null)" = crc0 ] && [ "$(cat $CR.owner)" = 1000:1010 ] && [ "$(cat $WD/d/abstep)" = C ]'
abreset; abrun; abrun; abrun; rm -f $WD/toasts; abrun
check "  끝난 뒤 다시 꽂으면 이미 마쳤다고만 안내(파일은 그대로)" '[ "$(cat $WD/d/abstep)" = DONE ] && grep -q "이미 마쳤습니다" $WD/toasts && [ "$(cat $C.owner)" = 0:0 ]'
: > $WD/usb/kp-wifidiag-reset; rm -f $WD/toasts; abrun; rm -f $WD/usb/kp-wifidiag-reset
check "  끝난 뒤 되돌리기 파일과 함께: 되돌릴 것 없이 단계만 처음으로" '[ ! -f $WD/d/abstep ] && grep -q "단계만 처음으로" $WD/toasts'
abreset; abrun; : > $WD/usb/kp-wifidiag-reset; abrun; rm -f $WD/usb/kp-wifidiag-reset
check "  되돌리기에 성공하면 백업도 지움(다음 A는 그때 상태를 새로 기록)" '[ ! -f $WD/d/ab-orig ] && [ ! -f $WD/d/ab-conf.bak ] && [ "$(cat $C.owner)" = 0:0 ]'
abreset; touch $WD/chown_fail; abrun; rm -f $WD/chown_fail
check "  소유자를 못 바꾸면 원래대로 두고 멈춤" '[ "$(cat $C.owner)" = 0:0 ] && [ ! -f $WD/d/abstep ] && grep -q "바꾸지 못해" $WD/toasts'
abreset; rm -f $C; abrun
check "  파일이 없으면 아무것도 바꾸지 않음" '[ ! -f $WD/d/abstep ] && grep -q "시험할 파일이 없어" $WD/toasts'
rm -f $WD/usb/kp-wifidiag-ab $WD/bin/chown $WD/bin/ls $WD/bin/mv
check "진단 스크립트 구문 검사(ksh 계열)" 'for k in $KSHS; do $k -n $B/scripts/kp-wifi-diag.sh || exit 1; done'

# --- 니로 시스템 파일 순정 되돌리기 USB 스크립트 (scripts/kp-sys-restore.sh) ---
SR=$T/sr; rm -rf $SR; mkdir -p $SR/bin $SR/usb $SR/onebin/depehev_kr $SR/perms
cat > $SR/bin/nemesis <<E
#!/bin/sh
echo "nemesis \$*" >> $SR/calls
[ "\$1" = remount ] && echo "/dev/block/system /system ext4 \$2,relatime 0 0" > $SR/sysmount
E
cat > $SR/bin/chown <<E
#!/bin/sh
echo "chown \$*" >> $SR/calls
echo "\$1" > "\$2.owner"
E
cat > $SR/bin/mv <<E
#!/bin/sh
[ "\$1" = -f ] && shift
[ -f "\$1.owner" ] && /bin/mv -f "\$1.owner" "\$2.owner"
exec /bin/mv -f "\$1" "\$2"
E
cat > $SR/bin/ls <<E
#!/bin/sh
if [ "\$1" = -ln ]; then
  case "\$2" in $SR/*)
    [ -e "\$2" ] || exit 1
    o=\$(cat "\$2.owner" 2>/dev/null || echo 0:0); echo "-rw-r--r--    1 \${o%%:*}        \${o#*:}              88 Nov  2 17:25 \$2"; exit 0 ;;
  esac
fi
exec /bin/ls "\$@"
E
printf '#!/bin/sh\necho "$*" >> %s/toasts\n' $SR > $SR/bin/am
chmod +x $SR/bin/*
FXT=$SR/onebin/depehev_kr/featurexml.cfg
srreset() {
  rm -rf $SR/d $SR/d.lock $SR/usb/kp-sysrestore $SR/calls $SR/toasts $SR/perms/*
  # 진짜 순정(11-03 고치기 전에 뜬 원본)에 17·18번째 줄 '#'을 붙여 지금 차의 파일(c3fa5e85…)을 만든다
  python3 - $FXT $B/usb-backup/CARPLAY-20261106-before-1.5.3/_dev/featurexml.before.cfg <<'E'
import sys
b=open(sys.argv[2],'rb').read().split(b"\r\n")
b[16]=b"#"+b[16]; b[17]=b"#"+b[17]
open(sys.argv[1],"wb").write(b"\r\n".join(b))
E
  echo 0:0 > $FXT.owner; cp $FXT $SR/orig.cfg
  echo '<permissions/>' > $SR/perms/com.hkmc.software.connectivity.carplay_wireless.xml
  echo '<permissions2/>' > $SR/perms/com.hkmc.software.connectivity.androidauto_wireless.xml
  echo "/dev/block/system /system ext4 ro,relatime 0 0" > $SR/sysmount
  echo "/dev/block/sda1 $SR/usb vfat rw 0 0" >> $SR/sysmount
}
srrun() { (cd $SR && PATH=$SR/bin:$T/bin:/usr/bin:/bin:/sbin BB=$T/bin/bb U=$SR/usb D=$SR/d MOUNTS=$SR/sysmount ONEBIN=$SR/onebin PERMS=$SR/perms sh -c 'sed "s#^export PATH=.*#export PATH='$SR'/bin:'$T'/bin:/usr/bin:/bin:/sbin#" '$B'/scripts/kp-sys-restore.sh > '$SR'/run.sh; sh '$SR'/run.sh') > $SR/out 2>&1; }
# USB 마운트 줄을 nemesis remount가 지우지 않게: 스텁은 /system 줄만 바꾸고 USB 줄은 다시 붙인다
cat > $SR/bin/nemesis <<E
#!/bin/sh
echo "nemesis \$*" >> $SR/calls
if [ "\$1" = remount ]; then
  { echo "/dev/block/system /system ext4 \$2,relatime 0 0"; echo "/dev/block/sda1 $SR/usb vfat rw 0 0"; } > $SR/sysmount
fi
E
chmod +x $SR/bin/nemesis
srreset; srrun
check "  바꾸기 전 파일이 지금 차의 md5(c3fa5e85)와 같음(테스트 준비 확인)" '[ "$(md5 -q $SR/orig.cfg 2>/dev/null || md5sum < $SR/orig.cfg | cut -d" " -f1)" = c3fa5e8597b0a3e437ee81a6efc0e63a ]'
check "순정 되돌리기: 결과가 11-03 원본과 바이트까지 같음(md5 a5ce9ddd), 권한 파일 2개 삭제" 'cmp -s $FXT $B/usb-backup/CARPLAY-20261106-before-1.5.3/_dev/featurexml.before.cfg && [ ! -e $SR/perms/com.hkmc.software.connectivity.carplay_wireless.xml ]'
check "  featurexml 17·18번째 줄의 '#'만 빠짐(CRLF 그대로, 크기 2바이트 줄어듦)" '[ $(( $(wc -c < $SR/orig.cfg) - $(wc -c < $FXT) )) = 2 ] && [ "$(sed -n 17p $FXT)" = "$(printf -- "-/system/etc/permissions/com.hkmc.software.connectivity.carplay_wireless.xml\r")" ] && [ "$(sed -n 18p $FXT)" = "$(printf -- "-/system/etc/permissions/com.hkmc.software.connectivity.androidauto_wireless.xml\r")" ] && [ "$(sed -n 12p $FXT)" = "$(sed -n 12p $SR/orig.cfg)" ] && [ ! -e $SR/perms/com.hkmc.software.connectivity.carplay_wireless.xml ] && [ ! -e $SR/perms/com.hkmc.software.connectivity.androidauto_wireless.xml ]'
check "  /system을 rw로 열었다가 원래(ro)로 닫고, 원본을 헤드유닛·USB에 백업, 소유자 유지" 'grep -qx "nemesis remount rw" $SR/calls && [ "$(tail -1 $SR/calls)" = "nemesis remount ro" ] && cmp -s $SR/d/bak/featurexml.cfg $SR/orig.cfg && [ -n "$(ls -d $SR/usb/kp-sysrestore/out-*/backup 2>/dev/null)" ] && [ "$(cat $FXT.owner)" = 0:0 ] && [ "$(cat $SR/d/step)" = DONE ] && grep -q "순정으로 되돌렸습니다" $SR/toasts'
rm -f $SR/toasts $SR/calls; srrun
check "  다시 꽂으면 상태만 기록(바꾸지 않음)" '! grep -q remount $SR/calls 2>/dev/null && grep -q "이미 바꿨습니다" $SR/toasts'
: > $SR/usb/kp-sysrestore-reset; rm -f $SR/toasts; srrun; rm -f $SR/usb/kp-sysrestore-reset
check "되돌리기 파일: 백업한 원본 featurexml(바이트 그대로)과 권한 파일 2개를 다시 넣음" 'cmp -s $FXT $SR/orig.cfg && [ "$(cat $SR/perms/com.hkmc.software.connectivity.carplay_wireless.xml)" = "<permissions/>" ] && [ -f $SR/perms/com.hkmc.software.connectivity.androidauto_wireless.xml ] && grep -q "원본으로 되돌렸습니다" $SR/toasts && [ "$(cat $SR/d/step)" = RESET ]'
srreset; printf 'line1\r\n' > $FXT; cp $FXT $SR/orig.cfg; srrun
check "  17·18번째 줄이 예상과 다르면 아무것도 바꾸지 않음(/system도 열지 않음)" 'cmp -s $FXT $SR/orig.cfg && [ -f $SR/perms/com.hkmc.software.connectivity.carplay_wireless.xml ] && ! grep -q remount $SR/calls 2>/dev/null && grep -q "아무것도 바꾸지 않았습니다" $SR/toasts'
srreset; python3 -c "
p='$FXT'; b=open(p,'rb').read(); open(p,'wb').write(b[:-2])"; cp $FXT $SR/orig.cfg; srrun
check "  원본 끝에 줄바꿈이 없으면(바이트가 더 바뀜) 쓰지 않음" 'cmp -s $FXT $SR/orig.cfg && ! grep -q remount $SR/calls 2>/dev/null'
srreset; echo NIROX.KOR.0000.V039.001.260902 > $T/product; srrun; rm -f $T/product
check "  니로가 아니면 아무것도 하지 않음" 'cmp -s $FXT $SR/orig.cfg && grep -q "니로 하이브리드 전용" $SR/toasts'
srreset; cp $B/usb-backup/CARPLAY-20261106-before-1.5.3/_dev/featurexml.before.cfg $FXT; cp $FXT $SR/orig.cfg; srrun
check "  featurexml이 이미 순정이면 그 파일은 그대로 두고 권한 파일만 지움" 'cmp -s $FXT $SR/orig.cfg && [ ! -e $SR/perms/com.hkmc.software.connectivity.carplay_wireless.xml ] && grep -q "순정으로 되돌렸습니다" $SR/toasts'
srreset; printf 'x' >> $FXT; cp $FXT $SR/orig.cfg; srrun
check "  md5가 예상(지금 값·순정)과 다르면 아무것도 바꾸지 않음" 'cmp -s $FXT $SR/orig.cfg && [ -f $SR/perms/com.hkmc.software.connectivity.carplay_wireless.xml ] && ! grep -q remount $SR/calls 2>/dev/null'
check "순정 되돌리기 스크립트 구문 검사(ksh 계열)" 'for k in $KSHS; do $k -n $B/scripts/kp-sys-restore.sh || exit 1; done'
else
  echo "건너뜀: 진단 USB 스크립트 테스트 (공개 저장소에 없는 파일)"
fi

# --- 와이드스크린·유선 보호: 그랜저 IG (IGPE.KOR.*.260902) 1920x720 & 유선 USB 설정 가드 ---
WS=$T/ws; rm -rf $WS; mkdir -p $WS/bin $WS/tb $WS/app $WS/bk $WS/w $WS/logs $WS/usb0 $WS/usb1 $WS/stage $WS/hd/mods/wireless-carplay-aa $WS/proc $WS/sys/app $WS/sys/lib $WS/sys/onebin/igpe_kr $WS/hm/mod $WS/hm/set $WS/hs
cp -R $PKG/* $WS/app/
sed "s#^export PATH=.*#export PATH=$WS/bin:/usr/bin:/bin:/sbin#" $PKG/svc/hotspot.sh > $WS/app/svc/hotspot.sh
sed "s#^export PATH=.*#export PATH=$WS/bin:/usr/bin:/bin:/sbin#" $PKG/bin/carreport.sh > $WS/app/bin/carreport.sh
PY3=$(command -v python3)
cat > $WS/bin/dbtool.py <<'PY'
import json, os, re, sys

db_path = os.environ["WS_DB"]
calls_path = os.environ["WS_CALLS"]
ws_dir = os.environ["WS_DIR"]

def load():
    if os.path.exists(db_path):
        with open(db_path, "r", encoding="utf-8") as f:
            return json.load(f)
    return {"system": {}, "global": {}, "secure": {}}

def save(db):
    tmp = db_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(db, f, sort_keys=True)
    os.replace(tmp, db_path)

def log_call(line):
    with open(calls_path, "a", encoding="utf-8") as f:
        f.write(line + "\n")

mode = sys.argv[1]
args = sys.argv[2:]

if mode == "settings":
    log_call("settings " + " ".join(args))
    if os.path.exists(os.path.join(ws_dir, "settings.fail")):
        sys.stderr.write("Error: settings service unavailable\n")
        sys.exit(1)
    if os.path.exists(os.path.join(ws_dir, "settings.garbage")):
        sys.stdout.write("Failure calling service settings: Broken pipe\n")
        sys.exit(0)
    if len(args) < 3:
        sys.stderr.write("settings: invalid args\n")
        sys.exit(2)
    op, ns, key = args[0], args[1], args[2]
    db = load()
    tbl = db.setdefault(ns, {})
    if op == "get":
        if os.path.exists(os.path.join(ws_dir, "settings.empty")):
            sys.exit(0)
        print(tbl.get(key, "null"))
        sys.exit(0)
    elif op == "put":
        if len(args) < 4:
            sys.stderr.write("settings put: missing value\n")
            sys.exit(2)
        val = args[3]
        ro_keys_file = os.path.join(ws_dir, "settings.ro_keys")
        ro_keys = set()
        if os.path.exists(ro_keys_file):
            with open(ro_keys_file, "r", encoding="utf-8") as f:
                ro_keys = set(f.read().split())
        if os.path.exists(os.path.join(ws_dir, "settings.ro")) or key in ro_keys:
            sys.exit(0)
        tbl[key] = val
        save(db)
        sys.exit(0)
    else:
        sys.stderr.write("Unsupported operation: %s\n" % op)
        sys.exit(1)

elif mode == "content":
    log_call("content " + " ".join(args))
    if os.path.exists(os.path.join(ws_dir, "content.fail")):
        sys.stderr.write("Error: content service unavailable\n")
        sys.exit(1)
    if not args or args[0] != "delete":
        sys.stderr.write("content: unsupported command\n")
        sys.exit(2)
    uri = None
    where = None
    i = 1
    while i < len(args):
        if args[i] == "--uri" and i + 1 < len(args):
            uri = args[i + 1]
            i += 2
        elif args[i] == "--where" and i + 1 < len(args):
            where = args[i + 1]
            i += 2
        else:
            i += 1
    m_uri = re.match(r"^content://settings/(system|global|secure)$", uri or "")
    m_where = re.match(r"^name='([A-Za-z0-9_]+)'$", where or "")
    if not m_uri or not m_where:
        sys.stderr.write("content delete: invalid args\n")
        sys.exit(2)
    if os.path.exists(os.path.join(ws_dir, "content.ro")):
        sys.exit(0)
    ns = m_uri.group(1)
    key = m_where.group(1)
    db = load()
    db.setdefault(ns, {}).pop(key, None)
    save(db)
    sys.exit(0)
PY
cat > $WS/bin/settings <<E
#!/bin/sh
WS_DB=$WS/db.json WS_CALLS=$WS/calls WS_DIR=$WS exec $PY3 $WS/bin/dbtool.py settings "\$@"
E
cat > $WS/bin/content <<E
#!/bin/sh
WS_DB=$WS/db.json WS_CALLS=$WS/calls WS_DIR=$WS exec $PY3 $WS/bin/dbtool.py content "\$@"
E
cat > $WS/bin/getprop <<E
#!/bin/sh
case "\$1" in
  ro.build.product) cat $WS/prop.product 2>/dev/null || echo IGPE.KOR.0000.V039.001.260902 ;;
  ro.device.splitscreen) [ -f $WS/prop.splitscreen ] && cat $WS/prop.splitscreen ;;
  ro.product.opt.stepofspec) [ -f $WS/prop.stepofspec ] && cat $WS/prop.stepofspec ;;
  ro.product.opt.useppsettings) [ -f $WS/prop.useppsettings ] && cat $WS/prop.useppsettings ;;
  ro.mobis.targetdir) echo /system/onebin/igpe_kr ;;
  ro.mobis.onebindir) echo igpe_kr ;;
  ro.board.platform) echo tcc897x ;;
  sys.boot_completed) echo 1 ;;
  persist.sys.iap2.wifi) cat $WS/prop.iap2 2>/dev/null || echo t ;;
  sys.kp.aa_ap) cat $WS/prop.aa_ap 2>/dev/null ;;
  *) echo 0 ;;
esac
E
cat > $WS/bin/pm <<E
#!/bin/sh
echo "pm \$*" >> $WS/calls
echo feature:com.hkmc.software.connectivity.carplay_wireless
echo feature:com.hkmc.software.connectivity.androidauto_wireless
echo feature:com.hkmc.software.wifihotspot
echo feature:android.hardware.wifi
E
cat > $WS/bin/nemesis <<E
#!/bin/sh
echo "nemesis \$*" >> $WS/calls
echo 1.16.6
E
printf '#!/bin/sh\necho "setprop $*" >> %s/calls\n[ "$1" = sys.kp.aa_ap ] && echo "$2" > %s/prop.aa_ap\nexit 0\n' $WS $WS > $WS/bin/setprop
printf '#!/bin/sh\necho "$*" >> %s/toasts\n' $WS > $WS/bin/am
printf '#!/bin/sh\necho "svc $*" >> %s/calls\nexit 0\n' $WS > $WS/bin/svc
printf '#!/bin/sh\necho "hostapd $*" >> %s/calls\n' $WS > $WS/bin/hostapd
printf '#!/bin/sh\necho "dnsmasq $*" >> %s/calls\n' $WS > $WS/bin/dnsmasq
printf '#!/bin/sh\necho "ifconfig $*" >> %s/calls\n[ "$1" = wlan0 ] && [ "$#" = 1 ] && printf "wlan0 Link encap:Ethernet\\n  inet addr:192.168.43.1  Mask:255.255.255.0\\n"\nexit 0\n' $WS > $WS/bin/ifconfig
printf '#!/bin/sh\ncat %s/ps 2>/dev/null\n' $WS > $WS/bin/ps
printf '#!/bin/sh\ncat %s/logcat 2>/dev/null\n' $WS > $WS/bin/logcat
printf '#!/bin/sh\nexit 0\n' > $WS/bin/dmesg
printf '#!/bin/sh\nexit 0\n' > $WS/bin/netstat
printf '#!/bin/sh\nexit 1\n' > $WS/bin/hmgapid
printf '#!/bin/sh\nexit 0\n' > $WS/bin/killall
printf '#!/bin/sh\n/bin/sleep 0.01\n' > $WS/bin/sleep
printf '#!/bin/sh\nexec "$@"\n' > $WS/bin/bb
chmod +x $WS/bin/*

# toolbox-only PATH($WS/tb): awk/sed/printf/tr/head/tail/stat 없음
for c in cp rm mkdir chmod ls cat grep date sleep sync; do ln -sf "$(command -v $c)" $WS/tb/$c; done
printf '#!/bin/sh\ncase "$1" in -*) echo "mv: $1: No such file" >&2; exit 1 ;; esac\nexec %s "$@"\n' "$(command -v mv)" > $WS/tb/mv
chmod +x $WS/tb/mv
cp $WS/bin/am $WS/bin/pm $WS/bin/getprop $WS/bin/setprop $WS/bin/settings $WS/bin/content $WS/bin/svc $WS/tb/

ws_db_set() {
  $PY3 -c 'import json,os,sys; p=sys.argv[1]; db=json.load(open(p)) if os.path.exists(p) else {"system":{},"global":{},"secure":{}}; db.setdefault(sys.argv[2],{})[sys.argv[3]]=sys.argv[4]; json.dump(db,open(p,"w"),sort_keys=True)' "$WS/db.json" "$1" "$2" "$3"
}
ws_db_del() {
  $PY3 -c 'import json,os,sys; p=sys.argv[1]; db=json.load(open(p)) if os.path.exists(p) else {"system":{},"global":{},"secure":{}}; db.setdefault(sys.argv[2],{}).pop(sys.argv[3],None); json.dump(db,open(p,"w"),sort_keys=True)' "$WS/db.json" "$1" "$2"
}
ws_db_get() {
  $PY3 -c 'import json,os,sys; p=sys.argv[1]; db=json.load(open(p)) if os.path.exists(p) else {}; print(db.get(sys.argv[2],{}).get(sys.argv[3],"__ABSENT__"))' "$WS/db.json" "$1" "$2"
}
ws_mode_perm() {
  $PY3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$1"
}
ws_reset() {
  rm -rf $WS/bk $WS/w $WS/logs $WS/usb0 $WS/usb1 $WS/stage $WS/hd $WS/calls $WS/toasts $WS/out $WS/pout $WS/stout \
    $WS/db.json $WS/settings.fail $WS/settings.ro $WS/settings.ro_keys $WS/settings.empty $WS/settings.garbage \
    $WS/content.fail $WS/content.ro $WS/prop.aa_ap $WS/rprog $WS/status.txt $WS/prog $WS/ps $WS/logcat $WS/mounts \
    $WS/victim $WS/victim_so $WS/extdir $WS/dangling_target
  mkdir -p $WS/bk $WS/w $WS/logs $WS/usb0 $WS/usb1 $WS/stage $WS/hd/mods/wireless-carplay-aa
  echo '{"system": [{"region": "KOR"}]}' > $WS/hd/mods/wireless-carplay-aa/mod.json
  echo IGPE.KOR.0000.V039.001.260902 > $WS/prop.product
  echo left_right > $WS/prop.splitscreen
  echo 110 > $WS/prop.stepofspec
  echo false > $WS/prop.useppsettings
  echo t > $WS/prop.iap2
  echo boot-ws > $WS/bootid
  echo "100.00 10.00" > $WS/uptime
  : > $WS/ps; : > $WS/logcat; : > $WS/mounts
  printf '{"system":{},"global":{},"secure":{}}\n' > $WS/db.json
}
wsl_fn() {
  (PATH=$WS/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$WS/bin/bb W=$WS/w BK=$WS/bk BOOT_ID=$WS/bootid \
   UPTIME=$WS/uptime HMGDATA=$WS/hd SRC=$T/softap.conf CONF=$WS/hk.conf NOTICE=$WS/toasts PROG=$WS/prog \
   PROC=$WS/proc WLAN=$WS/no-wlan WIFI_WAIT=0 WPDIR=$WS/no-wp OLDPKG=$WS/no-old \
   ${WSSH:-sh} -c '. '$WS'/app/svc/hotspot.sh; export PATH='$WS'/bin:/usr/bin:/bin:/sbin; '"$1")
}

# 1) wide_supported & usb_guard_supported
ws_reset
check "와이드스크린: wide_supported는 실차 검증 모델·버전(IGPE.KOR.0000·S5W_M .260902 + splitscreen=left_right)만 지원" '
  for p in IGPE.KOR.0000.V039.001.260902 IGPE.KOR.S5W_M.V039.001.260902; do
    echo "$p" > $WS/prop.product
    wsl_fn wide_supported || exit 1
  done'
check "  wide_supported: 타 모델(IGPE21/IGPEHEV/IGPE21HEV/DEPEHEV)·다른 빌드(260604)·해외·splitscreen 꺼짐 → 미지원" '
  for p in IGPE21.KOR.0000.V039.001.260902 IGPEHEV.KOR.0000.V039.001.260902 IGPE21HEV.KOR.0000.V039.001.260902 IGPE.KOR.S5W_M.V038.001.260604 DEPEHEV.KOR.0000.V039.001.260902 IGPE.USA.0000.V039.001.260902; do
    echo "$p" > $WS/prop.product
    ! wsl_fn wide_supported || exit 1
  done
  echo IGPE.KOR.S5W_M.V039.001.260902 > $WS/prop.product
  rm -f $WS/prop.splitscreen
  ! wsl_fn wide_supported || exit 1
  echo 0 > $WS/prop.splitscreen
  ! wsl_fn wide_supported || exit 1
  echo disable > $WS/prop.splitscreen
  ! wsl_fn wide_supported || exit 1'
check "  usb_guard_supported: IGPE.KOR.*.260902만(splitscreen=disable 포함) 지원, 타 모델·다른 빌드(260604)·해외 → 미지원" '
  for p in IGPE.KOR.0000.V039.001.260902 IGPE.KOR.S5W_M.V039.001.260902; do
    echo "$p" > $WS/prop.product
    echo disable > $WS/prop.splitscreen
    wsl_fn usb_guard_supported || exit 1
  done
  for p in IGPE21.KOR.0000.V039.001.260902 IGPEHEV.KOR.0000.V039.001.260902 IGPE21HEV.KOR.0000.V039.001.260902 IGPE.KOR.S5W_M.V038.001.260604 DEPEHEV.KOR.0000.V039.001.260902 IGPE.USA.0000.V039.001.260902; do
    echo "$p" > $WS/prop.product
    ! wsl_fn usb_guard_supported || exit 1
  done'

# 2) sys_get / sys_put / sys_del KitKat 트랩 검증
ws_reset
ws_db_set system k_one 1
ws_db_set system k_neg -1
$WS/bin/settings put system k_lit_null null
check "와이드스크린: KitKat mock·sys_del: settings put null은 리터럴 문자열, sys_del(content delete)은 행 삭제" '
  [ "$(ws_db_get system k_lit_null)" = "null" ] && wsl_fn "sys_del k_lit_null" && [ "$(ws_db_get system k_lit_null)" = "__ABSENT__" ] && grep -q "^content delete --uri content://settings/system --where name='\''k_lit_null'\''" $WS/calls'
check "  sys_get: null·0·1·-1 허용, 비정상 키 거부, 오류·빈 출력은 실패(비-0)" '
  [ "$(wsl_fn "sys_get k_one")" = 1 ] && [ "$(wsl_fn "sys_get k_neg")" = -1 ] && [ "$(wsl_fn "sys_get missing_k")" = null ] &&
  ! wsl_fn "sys_put \"bad;key\" 1" >/dev/null 2>&1 && ! wsl_fn "sys_del \"bad/key\"" >/dev/null 2>&1 &&
  { : > $WS/settings.empty; ! wsl_fn "sys_get k_one" >/dev/null 2>&1; } &&
  { rm -f $WS/settings.empty; : > $WS/settings.garbage; ! wsl_fn "sys_get k_one" >/dev/null 2>&1; } &&
  { rm -f $WS/settings.garbage; : > $WS/settings.fail; ! wsl_fn "sys_get k_one" >/dev/null 2>&1; }'

# 3) wide_apply: null/1/0, useppsettings=false vs true, idempotency, BlueLink 외부 변경 재적용, _0 키 없음
ws_reset
ws_db_set system carplay_ss_osd_dr1 1
ws_db_set system carplay_ss_osd_dr2 0
ws_db_set system androidauto_ss_osd_dr1 1
ws_db_set system androidauto_ss_osd_dr2 0
ws_db_set system phoneprojection_setting_use_split_screen 1
ws_db_set system phoneprojection_setting_use_split_screen_dr1 0
wsl_fn wide_apply > $WS/out 2>&1
check "와이드스크린: wide_apply(useppsettings=false): carplay/androidauto_ss_osd* → 0, use_split_screen 1 → -1, _0 없음" '
  for k in carplay_ss_osd carplay_ss_osd_dr1 carplay_ss_osd_dr2 androidauto_ss_osd androidauto_ss_osd_dr1 androidauto_ss_osd_dr2; do
    [ "$(ws_db_get system $k)" = 0 ] || exit 1
  done
  [ "$(ws_db_get system phoneprojection_setting_use_split_screen)" = -1 ] &&
  [ "$(ws_db_get system phoneprojection_setting_use_split_screen_dr1)" = 0 ] &&
  [ "$(ws_db_get system phoneprojection_setting_use_split_screen_dr2)" = "__ABSENT__" ] &&
  [ "$(ws_db_get system carplay_ss_osd_0)" = "__ABSENT__" ] &&
  [ "$(ws_db_get system androidauto_ss_osd_0)" = "__ABSENT__" ]'
check "  \$SYSORIG 백업: null→0, 1→0, 1→-1 기록, 이미 0이었던 _dr2는 기록 안 함" '
  [ "$(cat $WS/bk/sys.orig/carplay_ss_osd)" = "null 0" ] &&
  [ "$(cat $WS/bk/sys.orig/carplay_ss_osd_dr1)" = "1 0" ] &&
  [ ! -e $WS/bk/sys.orig/carplay_ss_osd_dr2 ] &&
  [ "$(cat $WS/bk/sys.orig/androidauto_ss_osd)" = "null 0" ] &&
  [ "$(cat $WS/bk/sys.orig/androidauto_ss_osd_dr1)" = "1 0" ] &&
  [ ! -e $WS/bk/sys.orig/androidauto_ss_osd_dr2 ] &&
  [ "$(cat $WS/bk/sys.orig/phoneprojection_setting_use_split_screen)" = "1 -1" ]'
rm -f $WS/calls
wsl_fn wide_apply > $WS/out 2>&1
check "  wide_apply 멱등성: 이미 맞춰진 상태에서 다시 불러도 settings put 없음" '! grep -q "^settings put " $WS/calls 2>/dev/null'
ws_db_set system carplay_ss_osd 1
ws_db_set system androidauto_ss_osd_dr1 1
rm -f $WS/calls
wsl_fn wide_apply > $WS/out 2>&1
check "  외부 변경(BlueLink 등 0→1): 다시 0으로 맞추되 \$SYSORIG 원래 값(null·1) 보존" '
  [ "$(ws_db_get system carplay_ss_osd)" = 0 ] && [ "$(ws_db_get system androidauto_ss_osd_dr1)" = 0 ] &&
  [ "$(cat $WS/bk/sys.orig/carplay_ss_osd)" = "null 0" ] && [ "$(cat $WS/bk/sys.orig/androidauto_ss_osd_dr1)" = "1 0" ]'
# useppsettings=true
ws_reset
echo true > $WS/prop.useppsettings
ws_db_set system phoneprojection_setting_use_split_screen_dr1 1
ws_db_set system phoneprojection_setting_use_split_screen_dr2 0
wsl_fn wide_apply > $WS/out 2>&1
check "  wide_apply(useppsettings=true): use_split_screen*도 0으로 설정" '
  [ "$(ws_db_get system phoneprojection_setting_use_split_screen)" = 0 ] &&
  [ "$(ws_db_get system phoneprojection_setting_use_split_screen_dr1)" = 0 ] &&
  [ "$(ws_db_get system phoneprojection_setting_use_split_screen_dr2)" = 0 ] &&
  [ "$(cat $WS/bk/sys.orig/phoneprojection_setting_use_split_screen)" = "null 0" ] &&
  [ "$(cat $WS/bk/sys.orig/phoneprojection_setting_use_split_screen_dr1)" = "1 0" ] &&
  [ ! -e $WS/bk/sys.orig/phoneprojection_setting_use_split_screen_dr2 ]'
# WIDEOFF / DEPEHEV / settings.ro / settings.fail / missing settings / symlink & set -f
ws_reset; : > $WS/bk/wide-off; wsl_fn wide_apply > $WS/out 2>&1; _wrc=$?
check "  wide_apply: \$WIDEOFF가 있으면 0을 돌려주고 아무것도 쓰지 않음" '[ $_wrc = 0 ] && ! grep -q "^settings put " $WS/calls 2>/dev/null && { [ ! -d $WS/bk/sys.orig ] || [ -z "$(ls $WS/bk/sys.orig 2>/dev/null)" ]; }'
ws_reset; echo DEPEHEV.KOR.0000.V039.001.260902 > $WS/prop.product; wsl_fn wide_apply > $WS/out 2>&1; _wrc=$?
check "  wide_apply: DEPEHEV에서는 0을 돌려주고 아무것도 쓰지 않음" '[ $_wrc = 0 ] && ! grep -q "^settings put " $WS/calls 2>/dev/null'
ws_reset; for _np in IGPE21HEV.KOR.0000.V039.001.260902 IGPE.KOR.S5W_M.V038.001.260604; do
  rm -f $WS/calls
  echo "$_np" > $WS/prop.product
  wsl_fn wide_apply > $WS/out 2>&1 || exit 1
  wsl_fn usb_guard > $WS/out 2>&1 || exit 1
done
check "  wide_apply·usb_guard: IGPE21HEV·다른 빌드(260604)에서는 settings 조회·쓰기 모두 0회" '! grep -q "^settings " $WS/calls 2>/dev/null'
ws_reset; : > $WS/settings.ro; wsl_fn wide_apply > $WS/out 2>&1; _wrc=$?
check "  wide_apply: put readback 실패 시 비-0(1) 반환 및 \$SYSORIG 백업 안 씀" '[ $_wrc != 0 ] && [ ! -f $WS/bk/sys.orig/carplay_ss_osd ]'
ws_reset; : > $WS/settings.fail; wsl_fn wide_apply > $WS/out 2>&1; _wrc=$?
check "  wide_apply: settings 실패 시 비-0(1) 반환" '[ $_wrc != 0 ]'
ws_reset; mv $WS/bin/settings $WS/settings.off; wsl_fn wide_apply > $WS/out 2>&1; _wrc=$?; mv $WS/settings.off $WS/bin/settings
check "  wide_apply: settings 명령 없으면 비-0(1) 반환" '[ $_wrc != 0 ]'
ws_reset; mkdir -p $WS/bk/sys.orig; echo "0 1" > $WS/victim; ln -s $WS/victim $WS/bk/sys.orig/carplay_ss_osd
wsl_fn wide_apply > $WS/out 2>&1; _wrc=$?
wsl_fn sys_restore_all > $WS/out 2>&1; _rrc=$?
check "  \$SYSORIG 키 심볼릭 링크 방어: wide_apply·sys_restore_all이 심볼릭 대상을 덮거나 지우지 않고 비-0(1)" '[ $_wrc != 0 ] && [ $_rrc != 0 ] && [ "$(cat $WS/victim)" = "0 1" ] && [ -L $WS/bk/sys.orig/carplay_ss_osd ]'
ws_reset; mkdir -p $WS/extdir; echo "null 0" > $WS/extdir/carplay_ss_osd; ln -s $WS/extdir $WS/bk/sys.orig
wsl_fn wide_apply > $WS/out 2>&1; _wrc=$?
wsl_fn sys_restore_all > $WS/out 2>&1; _rrc=$?
check "  \$SYSORIG 폴더 심볼릭 링크 방어: wide_apply·sys_restore_all이 심볼릭 폴더 내부를 건드리지 않고 비-0(1)" '[ $_wrc != 0 ] && [ $_rrc != 0 ] && [ "$(cat $WS/extdir/carplay_ss_osd)" = "null 0" ] && [ -L $WS/bk/sys.orig ]'
ws_reset; mkdir -p $WS/bk/sys.orig; ln -s $WS/dangling_target $WS/bk/sys.orig/carplay_ss_osd
wsl_fn wide_apply > $WS/out 2>&1; _wrc=$?
wsl_fn wide_restore > $WS/out 2>&1; _rrc=$?
check "  \$SYSORIG 깨진(dangling) 심볼릭 링크 방어: 대상 파일 생성 없이 비-0(1)" '[ $_wrc != 0 ] && [ $_rrc != 0 ] && [ ! -e $WS/dangling_target ] && [ -L $WS/bk/sys.orig/carplay_ss_osd ]'
ws_reset; echo target > $WS/victim; ln -s $WS/victim $WS/bk/wide-off
wsl_fn wide_apply > $WS/out 2>&1; _wrc=$?
check "  \$WIDEOFF 심볼릭 링크 무시: wide_apply가 끄기로 오인하지 않고 정상 적용" '[ $_wrc = 0 ] && [ "$(ws_db_get system carplay_ss_osd)" = 0 ]'
ws_reset; mkdir -p $WS/bk/sys.orig
check "  sys_restore_all(빈 \$SYSORIG): sh·mksh에서 set -f / set +f 상태를 그대로 보존" '
  for _fsh in sh $KSHS; do
    WSSH=$_fsh wsl_fn "set -f; sys_restore_all >/dev/null 2>&1 || exit 1; case \$- in *f*) exit 0 ;; *) exit 1 ;; esac" || exit 1
    WSSH=$_fsh wsl_fn "set +f; sys_restore_all >/dev/null 2>&1 || exit 1; case \$- in *f*) exit 1 ;; *) exit 0 ;; esac" || exit 1
  done'

# 4) usb_guard: null/-1/2 -> 1, 0 보존 + 주의 경고, enable_usb_cable(false vs true)
ws_reset
ws_db_set system androidauto_information_dr1 -1
ws_db_set system androidauto_information_dr2 0
ws_db_set system carplay_information 2
ws_db_set system carplay_information_dr1 1
ws_db_set system phoneprojection_setting_enable_usb_cable_dr1 -1
ws_db_set system phoneprojection_setting_enable_usb_cable_dr2 0
wsl_fn usb_guard > $WS/out 2>&1
check "유선 보호: usb_guard(useppsettings=false): null/-1/잘못된값 → 1, 0 보존+주의 경고, enable_usb_cable 1 안 씀 & 0→-1" '
  [ "$(ws_db_get system androidauto_information)" = 1 ] &&
  [ "$(ws_db_get system androidauto_information_dr1)" = 1 ] &&
  [ "$(ws_db_get system androidauto_information_dr2)" = 0 ] &&
  [ "$(ws_db_get system carplay_information)" = 1 ] &&
  [ "$(ws_db_get system carplay_information_dr1)" = 1 ] &&
  [ "$(ws_db_get system carplay_information_dr2)" = 1 ] &&
  [ "$(ws_db_get system phoneprojection_setting_enable_usb_cable)" = "__ABSENT__" ] &&
  [ "$(ws_db_get system phoneprojection_setting_enable_usb_cable_dr1)" = -1 ] &&
  [ "$(ws_db_get system phoneprojection_setting_enable_usb_cable_dr2)" = -1 ] &&
  [ "$(cat $WS/bk/sys.orig/androidauto_information)" = "null 1" ] &&
  [ "$(cat $WS/bk/sys.orig/androidauto_information_dr1)" = "-1 1" ] &&
  [ ! -e $WS/bk/sys.orig/androidauto_information_dr2 ] &&
  [ "$(cat $WS/bk/sys.orig/carplay_information)" = "2 1" ] &&
  [ ! -e $WS/bk/sys.orig/carplay_information_dr1 ] &&
  [ "$(cat $WS/bk/sys.orig/phoneprojection_setting_enable_usb_cable_dr2)" = "0 -1" ] &&
  grep -q "주의:.*androidauto_information_dr2=0" $WS/out'
rm -f $WS/calls
wsl_fn usb_guard > $WS/out 2>&1
check "  usb_guard 멱등성: 두 번째 호출에 settings put 없음" '! grep -q "^settings put " $WS/calls 2>/dev/null'
# useppsettings=true
ws_reset
echo true > $WS/prop.useppsettings
ws_db_set system phoneprojection_setting_enable_usb_cable_dr1 -1
ws_db_set system phoneprojection_setting_enable_usb_cable_dr2 0
wsl_fn usb_guard > $WS/out 2>&1
check "  usb_guard(useppsettings=true): enable_usb_cable null/-1 → 1, 0 보존+주의 경고" '
  [ "$(ws_db_get system phoneprojection_setting_enable_usb_cable)" = 1 ] &&
  [ "$(ws_db_get system phoneprojection_setting_enable_usb_cable_dr1)" = 1 ] &&
  [ "$(ws_db_get system phoneprojection_setting_enable_usb_cable_dr2)" = 0 ] &&
  grep -q "주의:.*phoneprojection_setting_enable_usb_cable_dr2=0" $WS/out'
ws_reset; echo DEPEHEV.KOR.0000.V039.001.260902 > $WS/prop.product; wsl_fn usb_guard > $WS/out 2>&1; _urc=$?
check "  usb_guard: DEPEHEV에서는 0을 돌려주고 아무것도 쓰지 않음" '[ $_urc = 0 ] && ! grep -q "^settings put " $WS/calls 2>/dev/null'
ws_reset; : > $WS/settings.ro; wsl_fn usb_guard > $WS/out 2>&1; _urc=$?
check "  usb_guard: put readback 실패(settings.ro) 시 비-0(1) 반환" '[ $_urc != 0 ]'
ws_reset; : > $WS/settings.fail; wsl_fn usb_guard > $WS/out 2>&1; _urc=$?
check "  usb_guard: settings 실패 시 비-0(1) 반환" '[ $_urc != 0 ]'
ws_reset; mv $WS/bin/settings $WS/settings.off; wsl_fn usb_guard > $WS/out 2>&1; _urc=$?; mv $WS/settings.off $WS/bin/settings
check "  usb_guard: settings 명령 없으면 비-0(1) 반환" '[ $_urc != 0 ]'

# 5) hotspot.sh main() 통합: try_ready 전 즉시 적용, 10분(n%20==0) 재적용, DEPEHEV 무영향
ws_reset
rm -rf $WS/hd/mods/wireless-carplay-aa
ws_db_set system carplay_ss_osd_dr1 1
ws_db_set system androidauto_information_dr1 -1
(PATH=$WS/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$WS/bin/bb W=$WS/w BK=$WS/bk HMGDATA=$WS/hd \
  BOOT_ID=$WS/bootid UPTIME=$WS/uptime SRC=$T/softap.conf CONF=$WS/hk.conf NOTICE=$WS/toasts PROG=$WS/prog \
  PROC=$WS/proc WLAN=$WS/no-wlan WCONF=$WS/nowconf WIFI_WAIT=0 WPDIR=$WS/no-wp OLDPKG=$WS/no-old \
  sh -c '. '$WS'/app/svc/hotspot.sh; export PATH='$WS'/bin:/usr/bin:/bin:/sbin; fix_perms() { :; }; wait() { exit 7; }; main') > $WS/out 2>&1
check "와이드스크린 main(): 시험 지원 IGPE가 try_ready 대기 전에도 wide_apply·usb_guard를 먼저 실행" '
  [ "$(ws_db_get system carplay_ss_osd)" = 0 ] && [ "$(ws_db_get system carplay_ss_osd_dr1)" = 0 ] &&
  [ "$(ws_db_get system androidauto_information)" = 1 ] && [ "$(ws_db_get system androidauto_information_dr1)" = 1 ] &&
  [ "$(ws_db_get system carplay_information)" = 1 ]'
ws_reset
for _msh in sh $KSHS; do
  ws_reset
  ws_db_set system carplay_ss_osd_dr1 1
  (PATH=$WS/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$WS/bin/bb W=$WS/w BK=$WS/bk HMGDATA=$WS/hd \
    BOOT_ID=$WS/bootid UPTIME=$WS/uptime SRC=$T/softap.conf CONF=$WS/hk.conf NOTICE=$WS/toasts PROG=$WS/prog \
    PROC=$WS/proc WLAN=$WS/no-wlan WCONF=$WS/nowconf WIFI_WAIT=0 WPDIR=$WS/no-wp OLDPKG=$WS/no-old \
    $_msh -c '. '$WS'/app/svc/hotspot.sh; export PATH='$WS'/bin:/usr/bin:/bin:/sbin; fix_perms() { :; }; _wc=0; wait() { _wc=$((_wc+1)); [ $_wc -eq 5 ] && '$WS'/bin/settings put system carplay_ss_osd 1; [ $_wc -ge 21 ] && exit 7; return 0; }; main') > $WS/out 2>&1
  check "  main()($_msh): 30초마다 반복 put/get 안 함, 10분(n=20) 주기에서 외부 변경(0→1)을 0으로 재적용·원래 값(null) 보존" '
    [ "$(ws_db_get system carplay_ss_osd)" = 0 ] &&
    [ "$(cat $WS/bk/sys.orig/carplay_ss_osd)" = "null 0" ] &&
    [ "$(grep -c "^settings put system carplay_ss_osd 0$" $WS/calls)" = 2 ] &&
    [ "$(grep -c "^settings get system carplay_ss_osd$" $WS/calls)" -le 6 ]'
done
ws_reset
echo DEPEHEV.KOR.0000.V039.001.260902 > $WS/prop.product
(PATH=$WS/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$WS/bin/bb W=$WS/w BK=$WS/bk HMGDATA=$WS/hd \
  BOOT_ID=$WS/bootid UPTIME=$WS/uptime SRC=$T/softap.conf CONF=$WS/hk.conf NOTICE=$WS/toasts PROG=$WS/prog \
  PROC=$WS/proc WLAN=$WS/no-wlan WCONF=$WS/nowconf WIFI_WAIT=0 WPDIR=$WS/no-wp OLDPKG=$WS/no-old \
  sh -c '. '$WS'/app/svc/hotspot.sh; export PATH='$WS'/bin:/usr/bin:/bin:/sbin; fix_perms() { :; }; wait() { exit 7; }; main') > $WS/out 2>&1
check "  main(): DEPEHEV에서는 system 설정(와이드·USB)을 건드리지 않음" '! grep -q "^settings put system " $WS/calls 2>/dev/null'

# 6) post.sh: 설치 시 적용, kp-wide-off(우위) / kp-wide-on, settings 실패 무중단, toolbox-only
ws_mk_post() {
  sed -e "s#/data/nemesis/apps/korea\.projection/svc/hotspot\.sh#$WS/app/svc/hotspot.sh; export PATH=$1#" \
    -e "s#/data/nemesis/apps/korea\.projection#$WS/app#g" \
    -e "s#^export PATH=.*#export PATH=$1#" \
    -e "s#^BK=.*#BK=$WS/bk#" \
    -e "s#^W=.*#W=$WS/w#" \
    -e "s#/data/local/tmp/cpdrive#$WS/cpdrive#g" \
    -e "s#/data/nemesis/apps/niro\.carplay\.hotspot#$WS/no-old#g" \
    -e "s#/storage/usb0#$WS/usb0#g" \
    -e "s#/storage/usb1#$WS/usb1#g" \
    $PKG/scripts/post.sh > $WS/post.sh
}
ws_reset; ws_mk_post "$WS/bin:/usr/bin:/bin:/sbin"
ws_db_set system carplay_ss_osd_dr1 1
ws_db_set system phoneprojection_setting_use_split_screen 1
(BB_SYS=$WS/bin/bb BB_OWN=$WS/bin/bb BOOT_ID=$WS/bootid NOTICE=$WS/toasts W=$WS/w BK=$WS/bk APK_SRC=$WS/no.apk sh $WS/post.sh) > $WS/out 2>&1; _prc=$?
check "와이드스크린 post.sh: 설치 시 IGPE 와이드스크린(0) + USB 가드(1) 적용" '
  [ $_prc = 0 ] && [ "$(ws_db_get system carplay_ss_osd)" = 0 ] && [ "$(ws_db_get system carplay_ss_osd_dr1)" = 0 ] &&
  [ "$(ws_db_get system phoneprojection_setting_use_split_screen)" = -1 ] &&
  [ "$(ws_db_get system androidauto_information)" = 1 ] && [ "$(ws_db_get system carplay_information)" = 1 ]'
: > $WS/usb0/kp-wide-on; : > $WS/usb1/kp-wide-off
(BB_SYS=$WS/bin/bb BB_OWN=$WS/bin/bb BOOT_ID=$WS/bootid NOTICE=$WS/toasts W=$WS/w BK=$WS/bk APK_SRC=$WS/no.apk sh $WS/post.sh) > $WS/out 2>&1; _prc=$?
check "  post.sh: kp-wide-off가 kp-wide-on보다 우선(usb1 off vs usb0 on), 와이드만 되돌리고 USB 가드 유지" '
  [ $_prc = 0 ] && [ -f $WS/bk/wide-off ] &&
  [ "$(ws_db_get system carplay_ss_osd)" = "__ABSENT__" ] &&
  [ "$(ws_db_get system carplay_ss_osd_dr1)" = 1 ] &&
  [ "$(ws_db_get system phoneprojection_setting_use_split_screen)" = 1 ] &&
  [ "$(ws_db_get system androidauto_information)" = 1 ]'
rm -f $WS/usb1/kp-wide-off
(BB_SYS=$WS/bin/bb BB_OWN=$WS/bin/bb BOOT_ID=$WS/bootid NOTICE=$WS/toasts W=$WS/w BK=$WS/bk APK_SRC=$WS/no.apk sh $WS/post.sh) > $WS/out 2>&1; _prc=$?
check "  post.sh: kp-wide-on만 있으면 wide-off 제거 후 다시 적용" '
  [ $_prc = 0 ] && [ ! -f $WS/bk/wide-off ] && [ "$(ws_db_get system carplay_ss_osd)" = 0 ] && [ "$(ws_db_get system carplay_ss_osd_dr1)" = 0 ]'
ws_reset; ws_mk_post "$WS/bin:/usr/bin:/bin:/sbin"; : > $WS/settings.fail
(BB_SYS=$WS/bin/bb BB_OWN=$WS/bin/bb BOOT_ID=$WS/bootid NOTICE=$WS/toasts W=$WS/w BK=$WS/bk APK_SRC=$WS/no.apk sh $WS/post.sh) > $WS/out 2>&1; _prc=$?
check "  post.sh: settings 명령이 실패해도 건너뜀 안내만 남기고 설치 성공(0)으로 끝남" '[ $_prc = 0 ] && grep -q "와이드스크린 설정 적용 건너뜀" $WS/out && grep -q "유선 프로젝션 설정 보호 건너뜀" $WS/out'
ws_reset; ws_mk_post "$WS/bin:/usr/bin:/bin:/sbin"; echo DO_NOT_TRUNCATE > $WS/victim; ln -s $WS/victim $WS/bk/wide-off; : > $WS/usb0/kp-wide-off
(BB_SYS=$WS/bin/bb BB_OWN=$WS/bin/bb BOOT_ID=$WS/bootid NOTICE=$WS/toasts W=$WS/w BK=$WS/bk APK_SRC=$WS/no.apk sh $WS/post.sh) > $WS/out 2>&1; _prc=$?
check "  post.sh: \$WIDEOFF 심볼릭 링크를 덮어쓰지 않고 제거 후 일반 파일로 생성" '[ $_prc = 0 ] && [ "$(cat $WS/victim)" = DO_NOT_TRUNCATE ] && [ ! -L $WS/bk/wide-off ] && [ -f $WS/bk/wide-off ]'
ws_reset; ws_mk_post "$WS/tb"
(BB=$WS/none BB_SYS=$WS/none BB_OWN=$WS/none BOOT_ID=$WS/bootid NOTICE=$WS/toasts W=$WS/w BK=$WS/bk APK_SRC=$WS/no.apk /bin/sh $WS/post.sh) > $WS/out 2>&1; _prc=$?
check "  post.sh: busybox 없는 toolbox PATH(! has_bb)에서도 not found 없이 성공(0)" '[ $_prc = 0 ] && ! grep -q "not found" $WS/out'
ws_reset; ws_mk_post "$WS/bin:/usr/bin:/bin:/sbin"
echo DEPEHEV.KOR.0000.V039.001.260902 > $WS/prop.product
: > $WS/usb0/kp-wide-off
(BB_SYS=$WS/bin/bb BB_OWN=$WS/bin/bb BOOT_ID=$WS/bootid NOTICE=$WS/toasts W=$WS/w BK=$WS/bk APK_SRC=$WS/no.apk sh $WS/post.sh) > $WS/out 2>&1; _prc=$?
check "  post.sh: 비대상 차(DEPEHEV)는 kp-wide-off USB가 있어도 wide-off 미생성·settings system 무변경" '
  [ $_prc = 0 ] && [ ! -e $WS/bk/wide-off ] && ! grep -q "^settings put system " $WS/calls 2>/dev/null'

# 7) status.sh: kp-wide-off/on 토글, kp-aa-* 동시 동작, 35키 유지, diag() 출력·경고·PII 없음
ws_reset
sed -e "s#/storage/usb0 /storage/usb1#$WS/usb0 $WS/usb1#" \
  -e "s#/proc/mounts#$WS/mounts#" \
  -e "s#/data/nemesis/logs/korea\.projection/ap\.log#$WS/logs/ap.log#" \
  $PKG/bin/status.sh > $WS/st.sh
echo "/dev/block/sda1 $WS/usb0 vfat rw 0 0" > $WS/mounts
ws_db_set system carplay_ss_osd_dr1 1
ws_db_set system androidauto_ss_osd_dr2 0
ws_db_set system androidauto_information_dr2 0
ws_db_set system phoneprojection_setting_use_split_screen 1
wsl_fn wide_apply >/dev/null 2>&1
wsl_fn usb_guard >/dev/null 2>&1
ws_st() {
  (PATH=$WS/bin:/usr/bin:/bin:/sbin RPT_SYNC=1 APP=$WS/app BB=$WS/bin/bb BK=$WS/bk W=$WS/w \
   STATUS=$WS/status.txt RPROG=$WS/rprog SRC=$T/softap.conf CONF=$WS/hk.conf HMGLOG=$WS/hl \
   HMGMOD=$WS/hm/mod HMGSET=$WS/hm/set/w.json HMGSTOCK=$WS/hs SYSAPP=$WS/sys/app \
   SYSLIB=$WS/sys/lib SYSONE=$WS/sys/onebin PROG=$WS/prog BOOT_ID=$WS/bootid \
   PROC=$WS/proc NOTICE=$WS/toasts AAOFF=$WS/bk/aa-off WIDEOFF=$WS/bk/wide-off SYSORIG=$WS/bk/sys.orig \
   sh $WS/st.sh) > $WS/stout 2>&1
}
WS_R=$WS/usb0/KoreaProjection-report/1-report.md
: > $WS/usb0/kp-wide-off; : > $WS/usb0/kp-aa-off
ws_st
check "와이드스크린 status.sh: kp-wide-off + kp-aa-off 동시 동작, carplay_ss_osd(null) content delete, 35키 유지" '
  [ -f $WS/bk/wide-off ] && [ -f $WS/bk/aa-off ] && grep -qx "aa=no" $WS/status.txt &&
  [ "$(grep -c "=" $WS/status.txt)" = 35 ] &&
  [ "$(ws_db_get system carplay_ss_osd)" = "__ABSENT__" ] &&
  [ "$(ws_db_get system carplay_ss_osd_dr1)" = 1 ] &&
  [ "$(ws_db_get system androidauto_ss_osd_dr2)" = 0 ] &&
  [ "$(ws_db_get system androidauto_information)" = 1 ]'
: > $WS/usb0/kp-wide-on
ws_st
check "  status.sh: kp-wide-off + kp-wide-on 함께 있으면 끄기(wide-off) 유지" '[ -f $WS/bk/wide-off ] && [ "$(ws_db_get system carplay_ss_osd)" = "__ABSENT__" ]'
printf '%s\n' "/dev/block/sda1 $WS/usb0 vfat rw 0 0" "/dev/block/sdb1 $WS/usb1 vfat rw 0 0" > $WS/mounts
: > $WS/usb0/kp-wide-on; : > $WS/usb1/kp-wide-off
ws_st
check "  status.sh: usb0=kp-wide-on + usb1=kp-wide-off 동시 마운트에서도 끄기(wide-off) 우선" '[ -f $WS/bk/wide-off ] && [ "$(ws_db_get system carplay_ss_osd)" = "__ABSENT__" ]'
echo "/dev/block/sda1 $WS/usb0 vfat rw 0 0" > $WS/mounts
rm -f $WS/usb0/kp-wide-off $WS/usb0/kp-aa-off $WS/usb1/kp-wide-off
: > $WS/usb0/kp-aa-on; : > $WS/usb0/kp-wide-on
ws_st
check "  status.sh: kp-aa-on + kp-wide-on 동시 동작 → aa=yes, wide-off 해제 및 재적용, 35키 유지" '
  [ ! -f $WS/bk/wide-off ] && [ ! -f $WS/bk/aa-off ] && grep -qx "aa=yes" $WS/status.txt &&
  [ "$(grep -c "=" $WS/status.txt)" = 35 ] &&
  [ "$(ws_db_get system carplay_ss_osd)" = 0 ] && [ "$(ws_db_get system carplay_ss_osd_dr1)" = 0 ]'
rm -f $WS/usb0/kp-aa-on $WS/usb0/kp-wide-on
echo DO_NOT_TRUNCATE > $WS/victim; ln -s $WS/victim $WS/bk/wide-off; : > $WS/usb0/kp-wide-off
ws_st
check "  status.sh: \$WIDEOFF 심볼릭 링크를 비우지 않고 제거 후 일반 파일로 생성" '[ "$(cat $WS/victim)" = DO_NOT_TRUNCATE ] && [ ! -L $WS/bk/wide-off ] && [ -f $WS/bk/wide-off ]'
rm -f $WS/usb0/kp-wide-off
rm -f $WS/toasts; : > $WS/settings.fail; : > $WS/usb0/kp-wide-on
ws_st
check "  status.sh: kp-wide-on 시 settings 실패하면 '일부 설정 적용 실패' 출력·알림" '[ ! -f $WS/bk/wide-off ] && grep -q "일부 설정 적용 실패" $WS/stout && grep -q "일부 설정 적용 실패" $WS/toasts'
rm -f $WS/settings.fail $WS/usb0/kp-wide-on
ws_db_set system carplay_ss_osd_dr1 1
wsl_fn wide_apply >/dev/null 2>&1
rm -f $WS/toasts; : > $WS/settings.fail; : > $WS/usb0/kp-wide-off
ws_st
check "  status.sh: kp-wide-off 시 settings 실패하면 '일부 설정 되돌리지 못함' 출력·알림" '[ -f $WS/bk/wide-off ] && grep -q "일부 설정 되돌리지 못함" $WS/stout && grep -q "일부 설정 되돌리지 못함" $WS/toasts'
rm -f $WS/settings.fail $WS/usb0/kp-wide-off
: > $WS/usb0/kp-wide-on; ws_st >/dev/null 2>&1; rm -f $WS/usb0/kp-wide-on
echo "SECRET_ORIG 0" > $WS/victim_so; ln -s $WS/victim_so $WS/bk/sys.orig/fake_secret
ws_db_set system carplay_ss_osd_dr2 "bad;val/x"
ws_st
sed -n '/^## 연결 진단/,/^## /p' $WS_R > $WS/diag.txt
check "  status.sh diag(): 와이드/USB 속성·설정키·\$SYSORIG(-1 부호 유지, 심볼릭 무시)·=0 주의 경고 출력 및 PII·특수문자 제거" '
  grep -q "left_right" $WS/diag.txt && grep -q "110" $WS/diag.txt && grep -q "false" $WS/diag.txt &&
  grep -q "carplay_ss_osd" $WS/diag.txt && grep -q "androidauto_ss_osd" $WS/diag.txt &&
  grep -q "androidauto_information" $WS/diag.txt && grep -q "carplay_information" $WS/diag.txt &&
  grep -q "phoneprojection_setting_enable_usb_cable" $WS/diag.txt &&
  grep -q "phoneprojection_setting_use_split_screen" $WS/diag.txt &&
  grep -q "phoneprojection_setting_use_split_screen=1->-1" $WS/diag.txt &&
  grep -q "badvalx" $WS/diag.txt &&
  grep -q "주의:" $WS/diag.txt &&
  ! grep -qE "SECRET_ORIG|fake_secret" $WS/diag.txt &&
  ! grep -q "bad;val/x" $WS/diag.txt &&
  ! grep -q -F -e "SSID\\cX" -e "PASS\\word99" -e "192.168.43.23" $WS_R $WS/status.txt'
ws_reset
sed -e "s#/storage/usb0 /storage/usb1#$WS/usb0 $WS/usb1#" \
  -e "s#/proc/mounts#$WS/mounts#" \
  -e "s#/data/nemesis/logs/korea\.projection/ap\.log#$WS/logs/ap.log#" \
  $PKG/bin/status.sh > $WS/st.sh
echo "/dev/block/sda1 $WS/usb0 vfat rw 0 0" > $WS/mounts
echo DEPEHEV.KOR.0000.V039.001.260902 > $WS/prop.product
: > $WS/usb0/kp-wide-off
rm -f $WS/calls
ws_st
check "  status.sh: 비대상 차(DEPEHEV)는 kp-wide-off 무시·와이드 settings 조회 0회·리포트 와이드 줄 생략" '
  [ ! -e $WS/bk/wide-off ] &&
  ! grep -q "와이드스크린" $WS/stout $WS_R &&
  ! grep -qE "carplay_information|carplay_ss_osd|androidauto_ss_osd|phoneprojection_setting" $WS/calls 2>/dev/null &&
  ! grep -qE "와이드스크린 설정:|시스템 설정 백업\(sys\.orig\):" $WS_R'

# 8) preun.sh: 업그레이드 보존, 전체 삭제 복원(content delete & put), 외부 변경 미덮어쓰기, 오류 시 modmsg 경고, toolbox-only(! has_bb)
ws_mk_preun() {
  sed -e "s#^BB=.*#BB=$1#" \
    -e "s#^BK=.*#BK=$WS/bk#" \
    -e "s#/data/nemesis/apps/korea\.projection/svc/hotspot\.sh#$WS/app/svc/hotspot.sh; export PATH=$2#" \
    -e "s#^export PATH=.*#export PATH=$2#" \
    -e "s#^STAGE=.*#STAGE=$WS/stage#" \
    -e "s#/data/local/tmp/korea-projection-status#$WS/pstatus#g" \
    $PKG/scripts/preun.sh > $WS/preun.sh
}
ws_pu() {
  (PATH=$1 HMGDATA=$WS/hd W=$WS/w BK=$WS/bk PROC=$WS/proc PROG=$WS/prog BOOT_ID=$WS/bootid \
   CONF=$WS/hk.conf WCONF=$WS/nowconf NOTICE=$WS/toasts \
   BB_SYS=$2 BB_OWN=$3 /bin/sh $WS/preun.sh) > $WS/pout 2>&1
}
ws_reset; ws_mk_preun "$WS/bin/bb" "$WS/bin:/usr/bin:/bin:/sbin"
ws_db_set system carplay_ss_osd_dr1 1
wsl_fn wide_apply >/dev/null 2>&1
: > $WS/bk/wide-off
echo id=korea.projection > $WS/stage/NEMESIS.data
rm -f $WS/calls
ws_pu "$WS/bin:/usr/bin:/bin:/sbin" "$WS/bin/bb" "$WS/bin/bb"
check "와이드스크린 preun.sh(업데이트): \$SYSORIG/*와 \$WIDEOFF 보존, settings/content 되돌림 없음" '
  [ -f $WS/bk/wide-off ] && [ -f $WS/bk/sys.orig/carplay_ss_osd ] &&
  ! grep -qE "^(settings put|content delete)" $WS/calls 2>/dev/null &&
  grep -q "업데이트: 이전 버전 정리" $WS/pout'

ws_reset; ws_mk_preun "$WS/bin/bb" "$WS/bin:/usr/bin:/bin:/sbin"
ws_db_set system carplay_ss_osd_dr1 1
ws_db_set system androidauto_information_dr1 -1
ws_db_set system phoneprojection_setting_enable_usb_cable_dr2 0
wsl_fn wide_apply >/dev/null 2>&1
wsl_fn usb_guard >/dev/null 2>&1
ws_db_set system androidauto_ss_osd 1
ws_pu "$WS/bin:/usr/bin:/bin:/sbin" "$WS/bin/bb" "$WS/bin/bb"; _purc=$?
check "  preun.sh(전체 삭제): null→content delete, 1/-1/0→put 복원, 외부 변경(androidauto_ss_osd=1) 유지" '
  [ $_purc = 0 ] &&
  [ "$(ws_db_get system carplay_ss_osd)" = "__ABSENT__" ] &&
  [ "$(ws_db_get system carplay_ss_osd_dr1)" = 1 ] &&
  [ "$(ws_db_get system androidauto_information)" = "__ABSENT__" ] &&
  [ "$(ws_db_get system androidauto_information_dr1)" = -1 ] &&
  [ "$(ws_db_get system phoneprojection_setting_enable_usb_cable_dr2)" = 0 ] &&
  [ "$(ws_db_get system androidauto_ss_osd)" = 1 ] &&
  grep -q "다른 곳에서 바뀜" $WS/pout &&
  grep -q "korea.projection 삭제 완료" $WS/pout &&
  [ ! -d $WS/bk ]'

ws_reset; ws_mk_preun "$WS/bin/bb" "$WS/bin:/usr/bin:/bin:/sbin"
wsl_fn wide_apply >/dev/null 2>&1
mv $WS/bin/settings $WS/settings.off
ws_pu "$WS/bin:/usr/bin:/bin:/sbin" "$WS/bin/bb" "$WS/bin/bb"; _purc=$?
mv $WS/settings.off $WS/bin/settings
check "  preun.sh: settings 명령 없으면 경고(modmsg) 남기고 삭제 완료(0)" '
  [ $_purc = 0 ] && grep -q "되돌리지 못했습니다" $WS/pout && grep -q "korea.projection 삭제 완료" $WS/pout'

ws_reset; ws_mk_preun "$WS/bin/bb" "$WS/bin:/usr/bin:/bin:/sbin"
wsl_fn wide_apply >/dev/null 2>&1
: > $WS/content.ro
ws_pu "$WS/bin:/usr/bin:/bin:/sbin" "$WS/bin/bb" "$WS/bin/bb"; _purc=$?
rm -f $WS/content.ro
check "  preun.sh: content delete readback 실패 시 경고(modmsg) 남기고 삭제 완료(0)" '
  [ $_purc = 0 ] && grep -q "되돌리지 못했습니다" $WS/pout && grep -q "korea.projection 삭제 완료" $WS/pout'

ws_reset; ws_mk_preun "$WS/none" "$WS/tb"
ws_db_set system carplay_ss_osd_dr1 1
ws_db_set system androidauto_information_dr1 -1
wsl_fn wide_apply >/dev/null 2>&1
wsl_fn usb_guard >/dev/null 2>&1
ws_pu "$WS/tb" "$WS/none" "$WS/none"; _purc=$?
check "  preun.sh(toolbox-only ! has_bb): busybox 없이 모든 \$SYSORIG 복원 + not found 없음 + 삭제 완료(0)" '
  [ $_purc = 0 ] &&
  [ "$(ws_db_get system carplay_ss_osd)" = "__ABSENT__" ] &&
  [ "$(ws_db_get system carplay_ss_osd_dr1)" = 1 ] &&
  [ "$(ws_db_get system androidauto_information)" = "__ABSENT__" ] &&
  [ "$(ws_db_get system androidauto_information_dr1)" = -1 ] &&
  ! grep -qE "not found|busybox" $WS/pout &&
  grep -q "korea.projection 삭제 완료" $WS/pout'

ws_reset
sed -e "s#/storage/usb0 /storage/usb1#$WS/usb0 $WS/usb1#" \
  -e "s#/proc/mounts#$WS/mounts#" \
  -e "s#/data/nemesis/logs/korea\.projection/ap\.log#$WS/logs/ap.log#" \
  $PKG/bin/status.sh > $WS/st.sh
echo "/dev/block/sda1 $WS/usb0 vfat rw 0 0" > $WS/mounts
echo IGPE.KOR.S5W_M.V039.001.260902 > $WS/prop.product
ws_mk_post "$WS/bin:/usr/bin:/bin:/sbin"
ws_mk_preun "$WS/bin/bb" "$WS/bin:/usr/bin:/bin:/sbin"
ws_db_set system carplay_ss_osd_dr1 1
(BB_SYS=$WS/bin/bb BB_OWN=$WS/bin/bb BOOT_ID=$WS/bootid NOTICE=$WS/toasts W=$WS/w BK=$WS/bk APK_SRC=$WS/no.apk sh $WS/post.sh) > $WS/out 2>&1 || true
ws_st
ws_pu "$WS/bin:/usr/bin:/bin:/sbin" "$WS/bin/bb" "$WS/bin/bb"; _s5rc=$?
check "  IGPE.KOR.S5W_M.V039.001.260902 실차 빌드 종단: 설치(0) → 진단 출력 → 삭제 원복(null·1)" '
  [ $_s5rc = 0 ] && grep -q "와이드스크린 설정:" $WS_R &&
  [ "$(ws_db_get system carplay_ss_osd)" = "__ABSENT__" ] &&
  [ "$(ws_db_get system carplay_ss_osd_dr1)" = 1 ] &&
  [ "$(ws_db_get system androidauto_information)" = "__ABSENT__" ]'

# 9) 스크립트 위생 검사: CRLF 없음, bare printf 없음, mksh/ksh 구문 검사
check "와이드스크린 위생 검사: CRLF(\\r) 없음 및 bare printf 없음(hotspot/post/preun/status)" '
  $PY3 - "$PKG/svc/hotspot.sh" "$PKG/scripts/post.sh" "$PKG/scripts/preun.sh" "$PKG/bin/status.sh" "$B/tests/stub-test.sh" <<'\''PY'\''
import re, sys
for p in sys.argv[1:]:
    data = open(p, "rb").read()
    if b"\r" in data:
        sys.stderr.write("CRLF in %s\n" % p)
        sys.exit(1)
    if p.endswith("stub-test.sh"):
        continue
    text = data.decode("utf-8")
    in_awk = False
    for idx, line in enumerate(text.splitlines(), 1):
        s = line.lstrip()
        if not s or s.startswith("#"):
            continue
        if not in_awk and "$BB awk" in line and line.count("'\''") % 2 == 1:
            in_awk = True
            continue
        if in_awk:
            if line.count("'\''") % 2 == 1:
                in_awk = False
            continue
        # 한 줄짜리 $BB awk '\''...'\'' 블록만 잠시 치워 검사한다
        cleaned = re.sub(r"\$BB awk(?:\s+-[^'\'']+)*\s+'\''[^'\'']*'\''", "", line)
        # 따옴표 밖 주석(# ...) 제거 후 모든 printf 토큰에 $BB 접두가 있는지 확인
        code = re.sub(r"(^|\s)#.*$", "", cleaned)
        for m in re.finditer(r"(?<![A-Za-z0-9_])printf\b", code):
            if not code[:m.start()].endswith("$BB "):
                sys.stderr.write("bare printf in %s:%d: %s\n" % (p, idx, line))
                sys.exit(1)
PY'

echo "---"
[ $fails -eq 0 ] && echo "모두 통과" || { echo "실패 $fails개"; exit 1; }
