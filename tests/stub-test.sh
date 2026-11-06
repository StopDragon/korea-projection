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

mkdir -p $T/bin $T/app $T/w $T/apps $T/d $T/usb0/packages $T/logs
printf '#!/bin/sh\nexec "$@"\n' > $T/bin/bb
cat > $T/bin/getprop <<E
#!/bin/sh
case "\$1" in
  ro.build.product) cat $T/product 2>/dev/null || echo DEPEHEV.KOR.0000.V039.001.260902 ;;
  ro.mobis.targetdir) echo /system/onebin/depehev_kr/ ;;
  ro.mobis.onebindir) echo depehev_kr ;;
  sys.boot_completed) echo 1 ;;
  *) echo 0 ;;
esac
E
cat > $T/bin/pm <<E
#!/bin/sh
[ -f $T/feat ] && echo feature:com.hkmc.software.connectivity.carplay_wireless
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
printf '#!/bin/sh\ncat %s/ps 2>/dev/null\n' $T > $T/bin/ps
printf '#!/bin/sh\necho "tcp 0 0 192.168.43.1:7000 192.168.43.23:50000 ESTABLISHED"\n' > $T/bin/netstat
printf '#!/bin/sh\n/bin/sleep 0.01\n' > $T/bin/sleep
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
fp() { (cd $T/fp && PATH=$T/fp/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 FIX_DELAY=0 BB=$T/bin/bb W=$T/fp/w PERMS=$T/fp/perms MOUNTS=$T/fp/mounts sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$T'/fp/bin:/usr/bin:/bin:/sbin; fix_perms'); }
fpreset() { rm -rf $T/fp/perms $T/fp/calls $T/fp/toast $T/fp/down; mkdir -p $T/fp/perms; }
# cwd($T/fp)에 한 글자 이름 "w" 폴더가 있다: "[wireless-carplay-aa]"가 파일 이름 패턴으로 풀리면 "w"로 바뀌어 잡힌다
fpreset; fp > $T/fp/out
check "fix_perms: 기록과 md5가 같은 권한 파일 2개만 씀" '[ "$(ls $T/fp/perms | wc -l | tr -d " ")" = 2 ] && [ "$(md5sum < $T/fp/perms/com.hkmc.software.connectivity.carplay_wireless.xml | cut -c1-32)" = 95ff801a064526de56059dba10960b05 ]'
check "  md5가 다른 권한 파일·라이브러리·설정 파일은 건드리지 않음" '[ ! -f $T/fp/perms/com.hkmc.software.other.xml ] && grep -q "건너뜀: com.hkmc.software.other" $T/fp/out'
check "  계획이 우리 것뿐 → 일반 apply, --force 안 씀, 재시작 안내" 'grep -qx "hmgapid engine apply" $T/fp/calls && ! grep -q -- --force $T/fp/calls && grep -q "껐다 켜" $T/fp/toast'
check "  /system이 ro였으면 rw → ro로 되돌림" 'grep -q "remount rw" $T/fp/calls && grep -q "remount ro" $T/fp/calls'
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

# --- 1f. 1.5 자동 설정: 무선 모드와 니로 지도 (확인된 차에서만, 차주 선택은 덮어쓰지 않음) ---
X=$T/as; mkdir -p $X/bin
cat > $X/bin/hmgapid <<E
#!/bin/sh
echo "hmgapid \$*" >> $X/calls
case "\$1 \$2" in
  "ping "*) [ -f $X/down ] && exit 1; exit 0 ;;
  "engine verify-map") [ -f $X/vm_fail ] && { echo "the map doesn't fit"; exit 1; }; echo "map checked"; exit 0 ;;
  "engine install") [ -f $X/inst_fail ] && exit 1; mkdir -p $X/hd/mods/wireless-carplay-aa; echo '{}' > $X/hd/mods/wireless-carplay-aa/mod.json; exit 0 ;;
  "engine plan") cat $X/plan; exit 0 ;;
  "engine apply") [ -f $X/apply_fail ] && exit 1; exit 0 ;;
  "engine remove") rm -rf $X/hd/mods/\$3; exit 0 ;;
  "engine status") exit 0 ;;
esac
exit 0
E
chmod +x $X/bin/hmgapid
PLAN_OK='change   /system/onebin/depehev_kr/featurexml.cfg [wireless-carplay-aa] -> 2a7c   [restart the head unit]
setting  prop/persist.sys.iap2.wifi = t [wireless-carplay-aa]
hook plan: wireless-carplay-aa on'
asreset() { rm -rf $X/hd $X/bk $X/w $X/calls $X/vm_fail $X/inst_fail $X/apply_fail $X/down $T/toast; mkdir -p $X/hd/maps/kia/ev6 $X/bk $X/w; printf '%s\n' "$PLAN_OK" > $X/plan; }
as() { (PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$X/w BK=$X/bk HMGDATA=$X/hd KP_HMG=$T/app/hmgapi sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$X'/bin:'$T'/bin:/usr/bin:/bin:/sbin; setup_hmgapi'); }
NM=$X/hd/maps/kia/niro/kor/260902
asreset; as > $X/out
check "자동 설정: 니로 지도 12개를 넣고 HMG-API 지도 확인 실행" '[ "$(ls $NM | wc -l | tr -d " ")" = 12 ] && grep -qx "hmgapid engine verify-map" $X/calls && [ -f $X/bk/map.ours ]'
check "  넣은 지도가 패키지 것과 같음" 'diff -r $NM $T/app/hmgapi/maps/kia/niro/kor/260902 >/dev/null'
check "  무선 모드 설치 → 계획이 이 모드뿐 → 적용, 우리가 설치한 표시" 'grep -q "hmgapid engine install .*/hmgapi/wireless-carplay-aa.zip" $X/calls && grep -qx "hmgapid engine apply" $X/calls && [ -f $X/bk/mod.ours ] && [ -f $X/bk/mod.tried ]'
check "  끝나면 차를 껐다 켜라는 토스트" 'grep -q "설정을 마쳤습니다" $T/toast'
rm -f $X/calls $T/toast; as > $X/out
check "  다시 부팅해도 이미 있으면 아무것도 안 함" '! grep -q -E "install|apply|verify-map" $X/calls && [ ! -f $T/toast ]'
rm -rf $X/hd/mods/wireless-carplay-aa; rm -f $X/calls; as > $X/out
check "차주가 모드를 지운 뒤에는 다시 설치하지 않음 (mod.tried)" '! grep -q "engine install" $X/calls'
asreset; mkdir -p $NM; echo official > $NM/car.json; as > $X/out
check "HMG-API에 이 차 지도가 이미 있으면(공식판 등) 덮어쓰지 않음" '[ "$(cat $NM/car.json)" = official ] && ! grep -q verify-map $X/calls && ! grep -q "^kia/niro/" $X/bk/map.ours 2>/dev/null'
asreset; mkdir -p $X/hd/mods/wireless-carplay-aa; echo '{}' > $X/hd/mods/wireless-carplay-aa/mod.json; : > $X/hd/mods/wireless-carplay-aa/.disabled; as > $X/out
check "모드가 이미 있으면(꺼 둔 것 포함) 설치·적용 안 함" '! grep -q "engine install" $X/calls && ! grep -q "engine apply" $X/calls && [ -f $X/hd/mods/wireless-carplay-aa/.disabled ]'
asreset; printf '%s\n' "$PLAN_OK" "change   /system/app/X.apk [other-mod] -> 1   [restart the app]" > $X/plan; as > $X/out
check "계획에 다른 모드 변경이 있으면 적용하지 않고 앱에서 적용하라고 안내" '! grep -qx "hmgapid engine apply" $X/calls && grep -q "HMG-API 앱에서 변경 사항을 적용" $T/toast && [ -f $X/bk/mod.ours ]'
for extra in "problem  /system/x [wireless-carplay-aa]" "setting  prop/x back to stock" "restore  /system/y (stock)" "nothing changed: 1 problem(s)"; do
  asreset; printf '%s\n' "$PLAN_OK" "$extra" > $X/plan; as > $X/out
  check "  계획에 '${extra%% *}' 줄이 있으면 적용 안 함" '! grep -qx "hmgapid engine apply" $X/calls'
done
asreset; touch $X/inst_fail; as > $X/out
check "모드 설치 실패 → 안내, 우리 것 표시 없음, 적용 안 함" 'grep -q "설치하지 못했습니다" $T/toast && [ ! -f $X/bk/mod.ours ] && ! grep -q "engine apply" $X/calls'
rm -f $X/inst_fail $X/calls; as > $X/out
check "  일시적인 설치 실패는 다음 부팅에 다시 함 (mod.tried 안 남김)" 'grep -q "engine install" $X/calls && [ -f $X/bk/mod.ours ]'
asreset; printf '%s\n' "hooks are off on this car (no map): mods apply without their hooks" "$PLAN_OK" > $X/plan; as > $X/out
check "계획에 '훅 꺼짐'이 있으면 적용 안 함" '! grep -qx "hmgapid engine apply" $X/calls'
asreset; printf '%s\n' "$PLAN_OK" "hooks    wireless-carplay-aa won't load (point x not mapped)" > $X/plan; as > $X/out
check "  'won't load' 줄이 있으면 적용 안 함" '! grep -qx "hmgapid engine apply" $X/calls'
asreset; touch $X/vm_fail; as > $X/out
check "지도 확인에 실패하면 무선 모드를 설치·적용하지 않음" '! grep -q "engine install" $X/calls && ! grep -q "engine apply" $X/calls && [ ! -f $X/bk/mod.tried ]'
check "  지도는 임시 폴더 없이 한 번에 옮겨짐" '[ -f $NM/car.json ] && [ ! -d $X/hd/maps/.kp-tmp ] && [ ! -d $NM.kp-tmp ]'
asreset; rm -rf $X/kh; mkdir -p $X/kh; cp -R $T/app/hmgapi/. $X/kh/; mkdir -p $X/kh/maps/hyundai/sonata/kor/260101; echo '{}' > $X/kh/maps/hyundai/sonata/kor/260101/car.json
(PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$X/w BK=$X/bk HMGDATA=$X/hd KP_HMG=$X/kh sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$X'/bin:'$T'/bin:/usr/bin:/bin:/sbin; setup_hmgapi') > $X/out
check "패키지에 든 차별 지도를 모두 넣고 기록 (지도 확인은 한 번)" '[ -f $NM/car.json ] && [ -f $X/hd/maps/hyundai/sonata/kor/260101/car.json ] && grep -qx "hyundai/sonata/kor/260101" $X/bk/map.ours && [ "$(grep -c verify-map $X/calls)" = 1 ]'
asreset; mkdir -p $NM; echo official > $NM/car.json; mkdir -p $X/kh; cp -R $T/app/hmgapi/. $X/kh/; mkdir -p $X/kh/maps/hyundai/sonata/kor/260101; echo '{"products": ["DN8HEV.KOR."]}' > $X/kh/maps/hyundai/sonata/kor/260101/car.json
(PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$X/w BK=$X/bk HMGDATA=$X/hd KP_HMG=$X/kh sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$X'/bin:'$T'/bin:/usr/bin:/bin:/sbin; setup_hmgapi') > $X/out
check "  다른 차 지도만 넣었으면 지도 확인을 하지 않음 (이 차 지도는 그대로)" '[ -f $X/hd/maps/hyundai/sonata/kor/260101/car.json ] && ! grep -q verify-map $X/calls && [ "$(cat $NM/car.json)" = official ]'
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
SM=$X/hd/maps/hyundai/sonata/kor/260902
asreset; echo DN822HEV.KOR.0000.V039.001.260902 > $T/product; as > $X/out; rm -f $T/product
check "쏘나타(DN822HEV.KOR 260902): 쏘나타 지도를 넣고 지도 확인 한 번, 무선 모드 설치" '[ "$(ls $SM | wc -l | tr -d " ")" = 12 ] && [ "$(grep -c verify-map $X/calls)" = 1 ] && grep -q "engine install" $X/calls'
check "  넣은 쏘나타 지도가 패키지 것과 같음" 'diff -r $SM $T/app/hmgapi/maps/hyundai/sonata/kor/260902 >/dev/null'
# 확인된 차 판별 (case 패턴에 변수의 |를 쓰지 않고 목록을 하나씩 본다)
ic() { (HOTSPOT_LIB=1 BB=$T/bin/bb sh -c '. '$T'/app/svc/hotspot.sh; is_car "$1"' _ "$1"); }
check "is_car: 니로·쏘나타 260902는 확인된 차" 'ic DEPEHEV.KOR.0000.V039.001.260902 && ic DN822HEV.KOR.0000.V039.001.260902'
check "  지역·펌웨어·모델이 다르면 아님" '! ic DN822HEV.USA.0000.V039.001.260902 && ! ic DN822HEV.KOR.0000.V039.001.260101 && ! ic DN8HEV.KOR.0000.V039.001.260902 && ! ic DN822HEV.KOR.260902 && ! ic ""'
# 지도 확인 시점: 지난번 확인 실패나 다른 차 지도 실패가 이 차 설정을 막거나 건너뛰게 하지 않는다
asreset; touch $X/vm_fail; as > $X/out; rm -f $X/vm_fail $X/calls; as > $X/out
check "지도 확인 실패 뒤 다음 부팅: 지도가 이미 있어도 다시 확인하고 통과하면 모드 설치" 'grep -qx "hmgapid engine verify-map" $X/calls && grep -q "engine install" $X/calls && grep -qx "kia/niro/kor/260902" $X/bk/map.checked'
rm -f $X/calls; as > $X/out
check "  확인을 통과한 뒤에는 다시 확인하지 않음" '! grep -q verify-map $X/calls'
asreset; mkdir -p $NM; cp $T/app/hmgapi/maps/kia/niro/kor/260902/*.json $NM/; echo kia/niro/kor/260902 > $X/bk/map.ours; mkdir -p $X/hd/mods/wireless-carplay-aa; echo '{}' > $X/hd/mods/wireless-carplay-aa/mod.json; as > $X/out
check "1.5.1에서 올린 차(map.checked 없음): 한 번 다시 확인, 재시작 안내는 안 함" 'grep -qx "hmgapid engine verify-map" $X/calls && [ -f $X/bk/map.checked ] && [ ! -f $T/toast ]'
asreset; rm -rf $X/kh; mkdir -p $X/kh; cp -R $T/app/hmgapi/. $X/kh/; mkdir -p $X/kh/maps/hyundai/aaa/kor/260101; echo '{}' > $X/kh/maps/hyundai/aaa/kor/260101/car.json; chmod 000 $X/kh/maps/hyundai/aaa/kor/260101/car.json
(PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$X/w BK=$X/bk HMGDATA=$X/hd KP_HMG=$X/kh sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$X'/bin:'$T'/bin:/usr/bin:/bin:/sbin; setup_hmgapi') > $X/out
chmod 644 $X/kh/maps/hyundai/aaa/kor/260101/car.json; rm -rf $X/kh
check "다른 차 지도를 넣지 못해도 이 차는 지도 확인·모드 설치, 끝 안내는 안 함" 'grep -q "지도 넣기 실패: hyundai/aaa" $X/out && grep -qx "hmgapid engine verify-map" $X/calls && grep -q "engine install" $X/calls && ! grep -q "마쳤습니다" $T/toast 2>/dev/null'

# preun: 우리가 설치한 모드만 정리
PU=$T/pu; mkdir -p $PU/bk
sed -e "s#^BB=.*#BB=$T/bin/bb#" -e "s#^BK=.*#BK=$PU/bk#" -e "s#/data/nemesis/apps/korea.projection/svc/hotspot.sh#$T/app/svc/hotspot.sh; export PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin#" \
  -e "s#^export PATH=.*#export PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin#" -e "s#^STAGE=.*#STAGE=$PU/stage#" \
  -e "s#/data/local/tmp/korea-projection-status#$PU/status#g" $T/app/scripts/preun.sh > $PU/preun.sh
pureset() { rm -rf $PU/bk $X/calls $T/toast $X/hd; mkdir -p $PU/bk $X/hd/mods/wireless-carplay-aa; echo '{}' > $X/hd/mods/wireless-carplay-aa/mod.json; }
pu() { (HMGDATA=$X/hd W=$PU/w sh $PU/preun.sh) > $PU/out 2>&1; }
pureset; : > $PU/bk/mod.ours; printf '%s\n' "restore  /system/onebin/depehev_kr/featurexml.cfg (stock)" "setting  prop/persist.sys.iap2.wifi back to stock" > $X/plan; pu
check "삭제: 우리가 설치한 모드는 remove → 계획이 되돌리기뿐 → 적용, 토스트에 알림" 'grep -qx "hmgapid engine remove wireless-carplay-aa" $X/calls && grep -qx "hmgapid engine apply" $X/calls && grep -q "무선 모드도 지웠습니다" $T/toast'
pureset; pu
check "  원래 있던 모드(mod.ours 없음)는 건드리지 않음" '! grep -q "engine remove" $X/calls && [ -f $X/hd/mods/wireless-carplay-aa/mod.json ]'
pureset; : > $PU/bk/mod.ours; printf '%s\n' "restore  /system/x (stock)" "change   /system/app/Y.apk [other-mod] -> 1" > $X/plan; pu
check "  계획에 다른 변경이 있으면 지우기만 하고 적용은 앱에서 하라고 안내" 'grep -q "engine remove" $X/calls && ! grep -qx "hmgapid engine apply" $X/calls && grep -q "HMG-API 앱에서 변경 사항을 적용" $T/toast'
pureset; : > $PU/bk/mod.ours; mkdir -p $PU/stage; echo "id=korea.projection" > $PU/stage/NEMESIS.data; pu; rm -rf $PU/stage
check "  업데이트 중(staging에 새 버전)에는 모드를 지우지 않음" '! grep -q "engine remove" $X/calls'

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
printf '#!/bin/sh\ncat %s/in.txt\n' $LG > $LG/bin/logcat
printf '#!/bin/sh\n[ "$1" = uniq ] && exit 1\nexec "$@"\n' > $LG/bin/bb-nouniq
chmod +x $LG/bin/*
lg() { (PATH=$LG/bin:/usr/bin:/bin HOTSPOT_LIB=1 BB=${1:-$T/bin/bb} W=$LG/w sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$LG'/bin:/usr/bin:/bin; logstart; wait'); }
rm -f $LG/w/*; lg
check "디버그 파일이 없으면 로그를 켜지 않음" '[ ! -f $LG/w/cp.log ] && [ ! -f $LG/w/log.pid ]'
: > $LG/w/debug; lg
check "잡음 줄(iAPSendMessage 확인 줄, getCANSTatus, getCANStatus)과 다른 태그는 버림" '! grep -q -E "Command Received|done with \(0x00\)|getCANSTatus|getCANStatus|OtherApp" $LG/w/cp.log'
check "  전송 실패(done with 0x01)는 남김" 'grep -q "done with (0x01)" $LG/w/cp.log'
check "  보낸 iAPSendMessage 줄(크기)은 남김 (위치 전송 확인용)" 'grep -q "iAPSendMessage() : data(0x5F862158) size(57)" $LG/w/cp.log'
check "  iAP2 태그(위치 요청)와 getCANStatus로 시작하지 않는 NavigationCluster 줄은 남김" 'grep -q "LocationInformationStart" $LG/w/cp.log && grep -q "updateTBTSubInfo" $LG/w/cp.log'
check "  교차로 이름과 HMG-API 줄은 남김" 'grep -q "crossroadname is TEST-RD" $LG/w/cp.log && grep -q "hud list type 72" $LG/w/cp.log'
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
fixpath $PKG/bin/status.sh | sed -e "s#/storage/usb0 /storage/usb1#$T/usb0#" \
  -e "s#/proc/mounts#$T/mounts#" -e "s#/data/nemesis/logs/korea.projection/ap.log#$T/logs/ap.log#" > $T/st.sh
STF=$T/status.txt
echo "  101 root  hostapd /data/misc/wifi/hostapd-kp.conf" > $T/ps
: > $T/mounts
STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null
check "USB가 마운트 안 됐으면 USB에 쓰지 않고 토스트도 없음 (상태는 화면이 보여 줌)" '[ ! -f $T/usb0/korea-projection-report.md ] && [ ! -f $T/toast ]'
echo "/dev/block/sda1 $T/usb0 vfat rw 0 0" > $T/mounts
mkdir -p $T/hl
printf '%s\n' "01-01 18:30:04.730 I/HMG-API (  148): hook map: none for Kia Niro, hooks off (no map)" > $T/hl/log.log.1
printf '%s\n' "01-01 18:30:04.740 I/HMG-API (  148): hook map: mapped for Kia Niro Hybrid (kor 260902), hooks on, 1 point(s) not mapped (their features and mods are off)" "11-06 09:05 I/HMG-API ( 1): other" > $T/hl/log.log
HMGLOG=$T/hl STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null
R=$T/usb0/korea-projection-report.md
check "상태 화면용 파일: 644, 키 25개" '[ "$(stat -f %Lp $STF)" = 644 ] && [ "$(grep -c "=" $STF)" = 25 ]'
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
check "USB에 리포트 저장" '[ -s $R ]'
check "리포트에 SSID·비밀번호·폰 IP 없음" '! grep -q -e "SSID.cX" -e "PASS" -e HotspotName -e 192.168.43.23 $R'
check "우리 hostapd 인식" 'grep -q "우리 hostapd: 예" $R'
check "wifi.direct를 wifi로 착각하지 않음" 'grep -q "android.hardware.wifi: 아니요" $R'
mkdir -p $T/hl0; printf '%s\n' "01-01 18:30:04.740 I/HMG-API (  148): hook map: mapped for Kia Niro Hybrid (kor 260902), hooks on" > $T/hl0/log.log
HMGLOG=$T/hl0 STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null; rm -rf $T/hl0
check "토스트 한국어 (준비된 차: 핫스팟 상태와 리포트 저장)" 'grep -q "핫스팟 켜짐" $T/toast'
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
rm -f $CR/calls $CR/toast; cr
check "Car Report: hmgapid engine report --usb 실행 → 성공 토스트(이제 USB를 빼셔도 됩니다), 잠금 해제" 'grep -qx "hmgapid engine report --usb" $CR/calls && grep -q "이제 USB를 빼셔도" $CR/toast && [ ! -d $CR/w/carreport.lock ]'
: > $CR/mounts; rm -f $CR/toast; cr; echo "/dev/block/sda1 /storage/usb0 vfat rw 0 0" > $CR/mounts
check "  USB가 실제로 마운트돼 있지 않으면(빈 마운트 폴더에 씀) 성공으로 보지 않음" 'grep -q "저장하지 못했습니다" $CR/toast'
touch $CR/fail; rm -f $CR/toast; cr; rm -f $CR/fail
check "  실패하면 다시 해 달라는 토스트" 'grep -q "저장하지 못했습니다" $CR/toast'
touch $CR/slow; rm -f $CR/toast; CRMAX=2 cr; rm -f $CR/slow
check "  오래 걸리면 멈추고(제한 시간) 실패 안내" 'grep -q "시간 초과" $CR/w/carreport.txt && grep -q "저장하지 못했습니다" $CR/toast'
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
PATH=$CR/bin:$PATH HMGLOG=$T/hl STATUS=$STF BB=$CR/bin/bbs APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null 2>&1
/bin/sleep 1
check "Launch: 확인된 차이고 훅이 켜져 있으면 Car Report를 만들지 않음" '[ ! -f $T/w/carreport.txt ]'
printf '%s\n' "01-01 18:30:04.740 I/HMG-API (  148): hook map: none for Kia Niro, hooks off (no map)" > $T/hl/log.log
PATH=$CR/bin:$PATH HMGLOG=$T/hl STATUS=$STF BB=$CR/bin/bbs APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null 2>&1
i=0; while [ ! -f $T/w/carreport.txt ] && [ $i -lt 30 ]; do /bin/sleep 0.2; i=$((i+1)); done
check "  훅이 꺼져 있으면 Car Report를 뒤에서 만들고, 기다리라는 토스트" '[ -f $T/w/carreport.txt ] && grep -q "제보 자료를 USB에 저장하는 중" $T/toast'
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
    [ -f $X/inst_fail ] && { [ "\$2" = --update ] && rm -f $X/ver $X/ap; exit 1; }; [ "\$2" = --update ] && [ ! -f $X/ver ] && exit 1; echo 1.4.3 > $X/ver; mkdir -p $X/bk; [ -f $X/bk/wifi_on ] || cat $X/wifi > $X/bk/wifi_on; mkdir -p $X/apps/korea.projection $X/wd $X/bk; touch $X/conf; echo up > $X/ap ;;
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
check "업데이트: 1.4.3 설치되고 핫스팟 켜짐 → R" '[ "$(urun)" = R ] && grep -q "install --update" $X/calls'
check "  삭제 직후 확인 7개 통과 → R2 (재시작 안내)" '[ "$(urun)" = R2 ] && [ "$(grep -c "^통과" $X/usb/kp7/R.txt)" = 7 ] && grep -q "껐다 켠 뒤" $X/toast'
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

echo "---"
[ $fails -eq 0 ] && echo "모두 통과" || { echo "실패 $fails개"; exit 1; }
