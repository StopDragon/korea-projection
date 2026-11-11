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
# 4b K-11: 은퇴한 USB 도구(kp-update-test.sh·kp-probe.sh)의 구문 검사는 tests/legacy/legacy-test.sh로 옮겼다
for f in $PKG/svc/hotspot.sh $PKG/scripts/post.sh $PKG/scripts/preun.sh $PKG/bin/status.sh \
         $PKG/bin/carreport.sh; do
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
# 1.7.1: 패키지는 토스트(am) 대신 알림 기록(NOTICE)에 쓴다. 시험의 알림 기록 파일은 $T/notice(1.7.3 K-2에서 이름을 바꿈).
export NOTICE=$T/notice
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
# 4b K-3: decode를 printf 한 번으로, o2d를 변수로 바꿨다. %·\·공백·한글(UTF-8)·끝 백슬래시가 든 softap.conf에서
# 결과(NS, S1~S5, conf_auth)가 고치기 전 함수(아래 $T/ref-parse.sh)와 바이트까지 같아야 한다
PK=$T/pk; mkdir -p $PK
# 기준: 1.7.2(고치기 전) decode·o2d·parse_conf·conf_auth 원본. 공개 저장소에도 이 시험이 그대로 돌게 파일 대신 여기에 둔다
cat > $T/ref-parse.sh <<'REFP'
# 1.7.2(4b 고치기 전) hotspot.sh의 decode·o2d·parse_conf·conf_auth 원본. 4b K-3 비교 시험(stub-test)의 기준값용이다.
# 제품 코드가 아니다. 고치지 마세요.
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

# 1.5.6: 5GHz 149번으로 띄운다. 순정 핫스팟 기본값(softap.conf)도 5GHz 149번이다.
# 폭은 순정 netd의 149번 설정과 같은 40MHz(HT40+). 20MHz로는 재부팅 뒤 아이폰이 스스로 붙지 않았다(2026-11-07 니로).
# 니로에서 이 설정으로 AP가 뜨고 아이폰 카플레이가 연결됨을 확인했다(2026-11-07 5GHz 시험 USB, 국가 설정 없이).

conf_auth() {
  [ -s "$1" ] || return 0
  set -- $(for _t in $($BB od -b -v "$1"); do [ ${#_t} -eq 3 ] && echo $_t; done)
  _ca=0; _cn=$#; _ci=0
  for _t in "$@"; do eval "_cb$_ci=$(o2d $_t)"; _ci=$((_ci+1)); [ $_ci -ge 200 ] && break; done
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
REFP
python3 - $PK <<'E'
import struct,sys
d=sys.argv[1]
u=lambda b:struct.pack('>H',len(b))+b
cases=[
 [b'My Car %d 50%',b'CP %s%n%%',b'x',b'a\\b\\\\c %s'],
 ['니로 카플'.encode(),'카플레이 Wi-Fi'.encode(),b'z',b'pass word% \\'],
 [b' lead sp ',b'\\n\\t\\0\\x41\\101',b'q',b'%%%%%%%%'+b'\\'*20],
 [b'A'*63,b'~!@#$%^&*()_+`-={}[]|:;"\'<>,.?/',b'r',b'end\\'],
 ['한글SSID%'.encode(),b'ok%1$s',b's','암호'.encode()+b'12345678'],
 # 4b 리뷰 L-2: 0x00·0xff·줄바꿈이 든 문자열, 길이 63·64, 길이만 맞고 깨진 꼬리
 [b'nul\x00in',b'ff\xffin',b'nl\nin',b'ok-ascii-1'],
 [b'B'*63,b'%'*63,b'C'*64,b'\\'*31+b'x'],
 [b'Z\x7f\x1fq',b'tail ok',b'\xff'*5,b'%s%s%s%s'],
]
for n,c in enumerate(cases):
    # 버전 3, 문자열 넷, 그 뒤 보안 방식 4바이트(conf_auth가 읽는 곳)와 꼬리
    open('%s/c%02d'%(d,n),'wb').write(struct.pack('>i',3)+b''.join(u(x) for x in c)+struct.pack('>i',4)+b'\x00\x95\x01')
# 잘린 파일: 둘째 문자열 가운데서 끊김, 길이 칸에서 끊김, 4바이트뿐
full=struct.pack('>i',3)+u(b'Trunc %d SSID')+u(b'Second\\str%')+u(b'x')+u(b'password99')
open('%s/c%02d'%(d,len(cases)),'wb').write(full[:4+2+13+2+5])
open('%s/c%02d'%(d,len(cases)+1),'wb').write(full[:4+2+13+1])
open('%s/c%02d'%(d,len(cases)+2),'wb').write(full[:4])
E
pk() { HOTSPOT_LIB=1 BB=$T/bin/bb SRC=$1 W=$T/w ${PKSH:-sh} -c '. '$T'/app/svc/hotspot.sh; '"$2"'parse_conf $SRC; printf "%s\n" "$NS" "$S1" "$S2" "$S3" "$S4" "$S5" "auth=$(conf_auth $SRC)"'; }
PKN=0; PKD=0
for f in $PK/c??; do pk $f '' > $f.new; pk $f '. '$T'/ref-parse.sh; ' > $f.old; PKN=$((PKN+1)); cmp -s $f.new $f.old && PKD=$((PKD+1)); done
check "  4b K-3: 특수 글자·0x00·0xff·줄바꿈·길이 63/64·잘린 softap.conf $PKN개 — parse_conf·conf_auth 결과가 고치기 전과 바이트까지 같음(sh)" '[ $PKN = 11 ] && [ $PKD = $PKN ]'
# 4b 리뷰 L-2: 차와 같은 ksh 계열(mksh 등)로도 같은 비교
for PKSH in $KSHS; do
  PKN=0; PKD=0
  for f in $PK/c??; do pk $f '' > $f.kn; pk $f '. '$T'/ref-parse.sh; ' > $f.ko; PKN=$((PKN+1)); cmp -s $f.kn $f.ko && cmp -s $f.kn $f.new && PKD=$((PKD+1)); done
  check "  4b 리뷰 L-2: $(basename $PKSH)로도 $PKN개 모두 고치기 전과 같고 sh 결과와도 같음" '[ $PKN = 11 ] && [ $PKD = $PKN ]'
done; unset PKSH
check "  4b 리뷰 L-2: 잘린·깨진 파일도 헛돌지 않음(4바이트뿐이면 NS=0, 둘째 문자열 중간에서 끊기면 첫 문자열만)" '[ "$(head -1 $PK/c10.new)" = 0 ] && [ "$(sed -n 1,2p $PK/c08.new | tr "\n" "|")" = "1|Trunc %d SSID|" ]'
check "  4b K-3: 비교가 헛돌지 않음(ASCII 문자열은 실제로 읽힘: % 와 \\ 가 그대로, conf_auth 숫자 나옴)" 'grep -qx "My Car %d 50%" $PK/c00.new && grep -qx "a\\\\b\\\\\\\\c %s" $PK/c00.new && grep -qx "CP %s%n%%" $PK/c00.old && grep -q "^auth=[0-9]" $PK/c00.new'
check "  4b K-3: 한글(UTF-8) 문자열은 예전처럼 문자열로 읽지 않음(32~126 밖) — 고치기 전과 같은 NS" '[ "$(head -1 $PK/c01.new)" = "$(head -1 $PK/c01.old)" ]'

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
fp() { (cd $T/fp && PATH=$T/fp/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 NOTICE=$T/fp/notice FIX_DELAY=0 BB=$T/bin/bb W=$T/fp/w BK=$T/fp/bk APLOG=$T/fp/ap.log PERMS=$T/fp/perms MOUNTS=$T/fp/mounts sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$T'/fp/bin:/usr/bin:/bin:/sbin; fix_perms'); }
fpreset() { rm -rf $T/fp/perms $T/fp/calls $T/fp/notice $T/fp/down; mkdir -p $T/fp/perms; }
# cwd($T/fp)에 한 글자 이름 "w" 폴더가 있다: "[wireless-carplay-aa]"가 파일 이름 패턴으로 풀리면 "w"로 바뀌어 잡힌다
fpreset; fp > $T/fp/out
check "fix_perms: 기록과 md5가 같은 권한 파일 2개만 씀" '[ "$(ls $T/fp/perms | wc -l | tr -d " ")" = 2 ] && [ "$(md5sum < $T/fp/perms/com.hkmc.software.connectivity.carplay_wireless.xml | cut -c1-32)" = 95ff801a064526de56059dba10960b05 ]'
check "  md5가 다른 권한 파일·라이브러리·설정 파일은 건드리지 않음" '[ ! -f $T/fp/perms/com.hkmc.software.other.xml ] && grep -q "건너뜀: com.hkmc.software.other" $T/fp/out'
check "  계획이 우리 것뿐 → 일반 apply, --force 안 씀, 재시작 안내" 'grep -qx "hmgapid engine apply" $T/fp/calls && ! grep -q -- --force $T/fp/calls && grep -q "내비를 재부팅해 주세요(RESET 버튼 또는 NEMESIS 재부팅)" $T/fp/notice'
check "  /system이 ro였으면 rw → ro로 되돌림" 'grep -q "remount rw" $T/fp/calls && grep -q "remount ro" $T/fp/calls'
check "  1.7.2 P-14: 새로 쓴 권한 파일 이름 2개를 삭제용 기록(perms.ours)에 남김(md5가 다른 것은 없음)" '[ "$(sort $T/fp/bk/perms.ours | tr "\n" " ")" = "com.hkmc.software.connectivity.androidauto_wireless com.hkmc.software.connectivity.carplay_wireless " ]'
rm -f $T/fp/perms/com.hkmc.software.connectivity.carplay_wireless.xml; fp > $T/fp/out
check "    다시 써도 기록에 같은 이름을 겹쳐 적지 않음" '[ "$(wc -l < $T/fp/bk/perms.ours | tr -d " ")" = 2 ]'
rm -f $T/fp/bk/perms.ours; printf '%s\n' "11-06 04:10:00 권한 파일 되돌림: com.hkmc.software.connectivity.carplay_wireless" "11-06 04:10:01 권한 파일 되돌림: bad/../x" > $T/fp/ap.log; fp > $T/fp/out; rm -f $T/fp/ap.log
check "    1.7.1까지 설치한 차: 기록이 없으면 서비스 시작 때 ap.log의 이름을 기록으로 옮김(이상한 이름은 버림, 리뷰 L5)" '[ "$(cat $T/fp/bk/perms.ours)" = com.hkmc.software.connectivity.carplay_wireless ]'
rm -f $T/fp/bk/perms.ours; fp > $T/fp/out
check "    옮길 것이 없어도 빈 기록을 만들어 다음 부팅에 다시 찾지 않음" '[ -f $T/fp/bk/perms.ours ] && [ ! -s $T/fp/bk/perms.ours ]'
fpreset; rm -f $T/fp/calls $T/fp/notice; fp > $T/fp/out
rm -f $T/fp/calls $T/fp/notice; fp > $T/fp/out
check "  파일이 이미 있으면 다시 쓰지도 apply하지도 않음" '! grep -q "engine apply" $T/fp/calls && [ ! -f $T/fp/notice ]'
fpreset; echo "/dev/block/system /system ext4 rw,relatime 0 0" > $T/fp/mounts; fp > $T/fp/out
check "  /system이 원래 rw였으면 ro로 바꾸지 않음" '! grep -q "remount ro" $T/fp/calls'
echo "/dev/block/system /system ext4 ro,relatime 0 0" > $T/fp/mounts
fpreset; cp $T/fp/plan $T/fp/plan.ok; echo "change   /system/app/HKMC_DiPO.apk [other-mod] -> 1234   [restart the app]" >> $T/fp/plan; fp > $T/fp/out
check "  계획에 다른 변경이 있으면 apply하지 않고 앱에서 적용하라고 안내" '! grep -qx "hmgapid engine apply" $T/fp/calls && grep -q "HMG-API 앱에서" $T/fp/notice'
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
# 1.7.3(모드 2.4.1, A-1): 모드가 준비(1)를 다시 보낸 줄과 훅 줄. 숫자·이유만 옮기고, 혹시 섞인 MAC 꼴은 지움
rm -f $WE/w/aatime
printf '%s\n' "11-10 09:00:00.100 I/HMG-API (  775): Android Auto: ready resend hook in com.google.android.projection.sink (active only while sys.kp.aa_ap=1)" "11-10 09:00:05.200 I/HMG-API (  775): [wireless-carplay-aa] AA 준비 다시 보냄 2대" "11-10 09:00:06.300 I/HMG-API (  775): [wireless-carplay-aa] AA 준비 다시 보냄 0대 (이미 연결됨)" "11-10 09:00:07.400 I/HMG-API (  775): [wireless-carplay-aa] AA 준비 다시 보냄 1대 (실패 1) AA:BB:CC:DD:EE:FF" > $WE/aalog241
printf '#!/bin/sh\ncat %s/aalog241\n' $WE > $WE/bin/logcat; chmod +x $WE/bin/logcat
we aa_events > $WE/aa241
check "1.7.3 모드 2.4.1: '준비 다시 보냄 N대'·'0대 (이미 연결됨)'·훅 줄을 ap.log에, MAC 꼴은 지움" 'grep -q "안드로이드 오토: 모드가 준비 다시 보냄 2대 (09:00:05.200)" $WE/aa241 && grep -q "안드로이드 오토: 모드가 준비 다시 보냄 0대 (이미 연결됨) (09:00:06.300)" $WE/aa241 && grep -q "안드로이드 오토: 모드의 준비 다시 보내기 훅 걸림(com.google.android.projection.sink) (09:00:00.100)" $WE/aa241 && ! grep -q "AA:BB" $WE/aa241'
# 확정 2.4.1: 모드 타이머 예외 줄(연결마다 한 번)을 ap.log에. 예외 이름만(영문·숫자·점)
rm -f $WE/w/aatime
printf '%s\n' "11-10 09:01:00.100 W/HMG-API (  775): [wireless-carplay-aa] AA: timer error java.lang.NullPointerException: x a1:b2:c3:d4:e5:f6" > $WE/aalogte
printf '#!/bin/sh\ncat %s/aalogte\n' $WE > $WE/bin/logcat; chmod +x $WE/bin/logcat
we aa_events > $WE/aate
check "  확정 2.4.1: 'AA: timer error <종류>' → '모드 타이머 오류(종류)' 한 줄, 뒤의 글·MAC은 옮기지 않음" 'grep -q "안드로이드 오토: 모드 타이머 오류(java.lang.NullPointerException) (09:01:00.100)" $WE/aate && ! grep -q "a1:b2" $WE/aate'
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
check "  리포트·상태 파일·알림·서비스 로그가 모두 cp_count를 씀(netstat으로 세는 곳이 남지 않음, status.sh는 K_CP 한 번으로 셈 — 4b K-3)" '! grep -n "netstat" $PKG/svc/hotspot.sh $PKG/bin/status.sh | grep -v "^[^:]*:[0-9]*:[[:space:]]*#" | grep -q . && [ "$(grep -c "cp_count)" $PKG/bin/status.sh)" = 1 ] && grep -q "K_CP=\$(cp_count)" $PKG/bin/status.sh'
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
check "  리포트 3-log.txt에 그 기록 파일이 들어감, 상태 파일 nowlan 키" 'grep -q "for _f in \$NOWLAN_LOG" $PKG/bin/status.sh && grep -q "cat \$APLOG.1 \$APLOG" $PKG/bin/status.sh && grep -q "K_NOWLAN=\$(yesno nowlan_now)" $PKG/bin/status.sh && grep -q "echo \"nowlan=\$K_NOWLAN\"" $PKG/bin/status.sh'
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
# 재리뷰 L4: 서비스 안의 기다림은 부팅 뒤 초로 잰다(가짜 부팅 뒤 1000초)
echo "1000.00 1.00" > $WE/uptime
H0=$(date '+%m-%d %H:%M:%S').000
echo "$H0 I/HMG-API (  905): [wireless-carplay-aa] bridge: iAP2 connected comp=4" > $WE/aalog2
wa 'UPTIME='$WE'/uptime; HINT_ON=1; aa_events; echo "IPH=$((1000 - IPH_AT))"' > $WE/i1
check "1.7.2 P-5: iAP2 연결(구성요소 4) 줄 → 기록 한 줄과 판정 시작(로그 시각 기준)" 'grep -q "카플레이: 아이폰 블루투스 연결(iAP2)" $WE/i1 && grep -q -E "^IPH=[0-2]$" $WE/i1'
echo 0 > $WE/w/cpn
wa 'UPTIME='$WE'/uptime; HINT_ON=1; IPH_AT=$((1000 - 61)); hint_tick' > $WE/i2
check "  60초 동안 기기 연결이 없으면 iph=wifi 안내와 ap.log 한 줄" 'grep -qx "iph=wifi" $WE/hint && grep -q "60초 동안 Wi-Fi에 오지 않음" $WE/i2'
rm -f $WE/hint; wa 'UPTIME='$WE'/uptime; HINT_ON=1; IPH_AT=$((1000 - 30)); hint_tick' > $WE/i3
check "  60초 전에는 안내 안 함" '[ ! -f $WE/hint ] && [ ! -s $WE/i3 ]'
wa 'UPTIME='$WE'/uptime; HINT_ON=1; IPH_AT=$((1000 - 61)); WCONN_AT=980; WSTA=1; hint_tick' > $WE/i4
check "  베타 1 리뷰 A: 우리 Wi-Fi에 기기가 붙어 있는데 카플레이가 60초 동안 없으면 'Wi-Fi에 오지 않음'이 아니라 iph=nocp(재부팅 안내), 로그에 원인" 'grep -qx "iph=nocp" $WE/hint && grep -q "60초 동안 카플레이가 시작되지 않음(우리 Wi-Fi에 붙은 기기 1대" $WE/i4 && ! grep -q "Wi-Fi에 오지 않음" $WE/i4'
rm -f $WE/hint
wa 'UPTIME='$WE'/uptime; HINT_ON=1; IPH_AT=$((1000 - 61)); WCONN_AT=700; WSTA=1; HA=ok; hint_tick' > $WE/i4b
check "  재리뷰 M3: 무선 AA가 연결된 동안(HA=ok)은 아이폰 안내를 내지 않음(쓰는 AA를 끊으라고 하지 않게)" '[ ! -f $WE/hint ] && [ ! -s $WE/i4b ]'
rm -f $WE/hint
wa 'UPTIME='$WE'/uptime; HINT_ON=1; HI=nocp; HI_T=$(( $(date +%s) - 10 )); HI_U=990; WCONN_AT=1000; hint_tick' > $WE/i4c
check "  베타 1 리뷰 A: nocp 안내는 기기가 Wi-Fi에 붙었다고 지우지 않음(카플레이 연결·10분에만)" '[ ! -f $WE/hint ] && [ ! -s $WE/i4c ]'
echo 1 > $WE/w/cpn; wa 'UPTIME='$WE'/uptime; HINT_ON=1; HI=nocp; HI_T=$(( $(date +%s) - 10 )); HI_U=990; hint_tick' > $WE/i4d; echo 0 > $WE/w/cpn
check "  베타 1 리뷰 A: 카플레이가 연결되면 nocp 안내를 지움" 'grep -qx "iph=" $WE/hint && grep -q "안내(상태 화면) 지움: 카플레이 연결됨" $WE/i4d'
rm -f $WE/hint
# 재리뷰 M3: 무선 AA "연결됨"(aa=ok)은 10분으로 지우지 않고, 우리 AP의 기기가 끊김으로 0대가 됐을 때만 지움
wa 'UPTIME='$WE'/uptime; HINT_ON=1; HA=ok; HA_T=$(( $(date +%s) - 700 )); WSTA=1; hint_tick; echo "HA=[$HA]"' > $WE/aa10
check "재리뷰 M3: 무선 AA 연결(ok)이 10분 넘게 이어져도 지우지 않음(10분 만료는 bt·cpwait 안내에만)" 'grep -qx "HA=\[ok\]" $WE/aa10 && ! grep -q "10분 지남" $WE/aa10'
wa 'UPTIME='$WE'/uptime; HINT_ON=1; HA=ok; HA_T=1; WSTA=0; hint_tick; echo "HA=[$HA]"' > $WE/aa11
check "  재리뷰 M3: 기기 수가 0이어도 끊김 줄로 0이 된 것이 아니면(커널 줄을 놓친 경우) 한 회차로는 지우지 않음" 'grep -qx "HA=\[ok\]" $WE/aa11'
wa 'UPTIME='$WE'/uptime; HINT_ON=1; HA=ok; HA_T=1; WSTA=0; hint_tick; hint_tick; echo "HA=[$HA]"' > $WE/aa11b
check "  확인 리뷰 M2: 무선 AA 연결됨인데 기기 0대가 두 회차(약 60초) 이어지면 지움" 'grep -qx "HA=\[\]" $WE/aa11b && grep -q "기기 0대가 두 회차 이어짐" $WE/aa11b'
rm -rf $WE/bk; mkdir -p $WE/bk; rm -f $WE/w/ktime
printf '%s\n' "<4>[  970.0] ETHER_TYPE_802_1X[wlan0] [RX] : M4 of 4way" "<6>[  975.0] CFG80211-ERROR) wl_cfg80211_del_station : Disconnect STA : aa:bb:cc:dd:ee:ff" > $WE/dmesg
wa 'UPTIME='$WE'/uptime; HINT_ON=1; WSTA=0; wifi_events >/dev/null; aa_hint ok; hint_tick; echo "HA=[$HA]"' > $WE/aa11c
check "  확인 리뷰 M2: 한 회차 안에 붙었다 끊긴 뒤 늦게 온 연결됨(ok)이 0대 기록을 지우지 않아 바로 지워짐" 'grep -qx "HA=\[\]" $WE/aa11c'
rm -rf $WE/bk; rm -f $WE/w/ktime $WE/dmesg
wa 'UPTIME='$WE'/uptime; HINT_ON=1; HA=bt; HA_T=$(date +%s); HA_U=399; hint_tick; echo "HA=[$HA]"' > $WE/aa11d
check "  확인 리뷰 L3: 블루투스 안내(bt) 10분 지우기는 부팅 뒤 초로 잼(시계는 방금이어도 부팅 뒤 601초 지났으면 지움)" 'grep -qx "HA=\[\]" $WE/aa11d && grep -q "10분 지남" $WE/aa11d'
rm -rf $WE/bk; mkdir -p $WE/bk; rm -f $WE/w/ktime
printf '%s\n' "<4>[  950.0] ETHER_TYPE_802_1X[wlan0] [RX] : M4 of 4way" "<6>[  960.0] CFG80211-ERROR) wl_cfg80211_del_station : Disconnect STA : aa:bb:cc:dd:ee:ff" > $WE/dmesg
wa 'UPTIME='$WE'/uptime; HINT_ON=1; WSTA=0; HA=ok; HA_T=1; wifi_events >/dev/null; hint_tick; echo "HA=[$HA]"' > $WE/aa12
check "  재리뷰 M3: 연결된 기기가 끊겨 0대가 되면 AA 연결됨을 지움(로그에 까닭)" 'grep -qx "HA=\[\]" $WE/aa12 && grep -q "우리 Wi-Fi에 붙은 기기가 0대가 됨(무선 AA 끊김으로 봄)" $WE/aa12'
wa 'UPTIME='$WE'/uptime; HINT_ON=1; HA=ok; HI=wifi; HI_T=$(date +%s); HI_U=990; hint_tick' > $WE/aa13
check "  재리뷰 M3: 무선 AA가 연결되면 남아 있던 아이폰 안내도 지움" 'grep -qx "iph=" $WE/hint && grep -q "안내(상태 화면) 지움: 무선 안드로이드 오토 연결됨" $WE/aa13'
rm -rf $WE/bk; rm -f $WE/w/ktime $WE/dmesg $WE/hint
echo 1 > $WE/w/cpn; wa 'UPTIME='$WE'/uptime; HINT_ON=1; IPH_AT=$((1000 - 61)); hint_tick' > $WE/i5; echo 0 > $WE/w/cpn
check "  카플레이가 연결되어 있으면 안내 안 함" '[ ! -f $WE/hint ]'
: > $T/ps; wa 'UPTIME='$WE'/uptime; HINT_ON=1; IPH_AT=$((1000 - 61)); hint_tick' > $WE/i6; echo "  1 root 0 S hostapd $WE/hk.conf" > $T/ps
check "  우리 hostapd가 없으면 안내 안 함" '[ ! -f $WE/hint ]'
wa 'UPTIME='$WE'/uptime; HINT_ON=1; HI=wifi; HI_T=$(( $(date +%s) - 10 )); HI_U=990; WCONN_AT=1000; hint_tick' > $WE/i7
check "  안내 뒤 기기가 연결되면 지움" 'grep -qx "iph=" $WE/hint && grep -q "아이폰이 Wi-Fi에 연결됨" $WE/i7'
wa 'UPTIME='$WE'/uptime; HINT_ON=1; HI=wifi; HI_T=$(( $(date +%s) - 601 )); HI_U=399; hint_tick' > $WE/i8
check "  10분 지나면 지움" 'grep -qx "iph=" $WE/hint'
rm -f $WE/w/aatime
printf '%s\n' "$H0 I/HMG-API (  905): [wireless-carplay-aa] bridge: iAP2 connected comp=4" "$H0 I/HMG-API (  905): [wireless-carplay-aa] bridge: iAP2 disconnected comp=4" > $WE/aalog2
wa 'UPTIME='$WE'/uptime; HINT_ON=1; aa_events; echo "IPH=[$IPH_AT]"' > $WE/i9
check "  iAP2가 끊기면 판정을 멈춤" 'grep -q "IPH=\[\]" $WE/i9 && grep -q "아이폰 블루투스 iAP2 끊김" $WE/i9'
rm -f $WE/w/aatime
printf '%s\n' "$H0 I/HMG-API (  905): [wireless-carplay-aa] bridge: iAP2 connected comp=1" "$H0 I/HMG-API (  905): [wireless-carplay-aa] bridge: iAP2 connected comp=4" > $WE/aalog2
wa 'UPTIME='$WE'/uptime; HINT_ON=1; aa_events; echo "IPH=[$IPH_AT]"' > $WE/i11
check "  리뷰 M-3: 유선(USB, 구성요소 1) 카플레이 중에는 블루투스 iAP2가 붙어도 아이폰 Wi-Fi 안내 판정을 하지 않음" 'grep -q "IPH=\[\]" $WE/i11 && grep -q "아이폰 USB(유선) iAP2 연결" $WE/i11'
rm -f $WE/w/aatime
printf '%s\n' "$H0 I/HMG-API (  905): [wireless-carplay-aa] bridge: iAP2 connected comp=1" "$H0 I/HMG-API (  905): [wireless-carplay-aa] bridge: iAP2 disconnected comp=1" "$H0 I/HMG-API (  905): [wireless-carplay-aa] bridge: iAP2 connected comp=4" > $WE/aalog2
wa 'UPTIME='$WE'/uptime; HINT_ON=1; aa_events; echo "IPH=$((1000 - IPH_AT))"' > $WE/i12
check "  유선이 끊긴 뒤의 블루투스 iAP2는 다시 판정함" 'grep -q -E "^IPH=[0-2]$" $WE/i12'
printf '%s\n' "<6>[  400.0] CFG80211-ERROR) wl_notify_connect_status_ap : ** AP/GO Link up event **" "<4>[  701.372626] ETHER_TYPE_802_1X[wlan0] [RX] : M4 of 4way" > $WE/dmesg; echo "710.50 100.0" > $WE/uptime; rm -f $WE/w/ktime
wa 'UPTIME='$WE'/uptime; wifi_events; echo "WC=$WCONN_AT"' > $WE/i10
check "  wifi_events가 기기 연결 시각을 부팅 뒤 초(커널 시각 701초)로 기억(재리뷰 L4: 시계가 아니라 부팅 뒤 초로 비교)" 'grep -qx "WC=701" $WE/i10'
# --- 베타 2 차주 제보(#64): "can't create /ktime" ---
# 차와 같은 기본값(환경 변수 없음)으로 hotspot.sh를 읽었을 때 경로가 실제 기본값인지(예전에는 KTB가 /ktime)
DEFP=$(env -i PATH=/usr/bin:/bin HOTSPOT_LIB=1 sh -c '. '$PKG'/svc/hotspot.sh; echo "$KTB|$KT|$BK|$W|$AAOFF|$APON_ORIG"' 2>/dev/null)
check "베타 2 차주 제보: 환경 변수 없이(차와 같은 기본값) KTB·KT·BK·W·AAOFF·APON_ORIG가 실제 기본 경로(KTB=/data/nemesis/backup/korea.projection/ktime)" '[ "$DEFP" = "/data/nemesis/backup/korea.projection/ktime|/data/local/tmp/korea.projection/ktime|/data/nemesis/backup/korea.projection|/data/local/tmp/korea.projection|/data/nemesis/backup/korea.projection/aa-off|/data/nemesis/backup/korea.projection/wifi_ap_on.orig" ]'
# 정적 검사: 맨 위 기본값 대입이 아래에서 정해지는 변수를 먼저 쓰지 않음, "> 파일 2>/dev/null" 순서가 없음(tests/tools/defuse-check.py)
python3 $B/tests/tools/defuse-check.py $PKG > $T/defuse.out 2>&1; DEFRC=$?
check "  베타 2 차주 제보: 정적 검사 — 정의 전에 쓰는 변수·'> 파일 2>/dev/null' 순서가 패키지 스크립트에 없음" '[ $DEFRC = 0 ] && [ ! -s $T/defuse.out ]' || cat $T/defuse.out
# 검사기가 헛돌지 않는지: 예전 꼴(KTB=${KTB:-$BK/ktime}, "> $KTB 2>/dev/null")을 심은 사본에서는 잡아야 함
mkdir -p $T/defbad/svc $T/defbad/bin $T/defbad/scripts; cp $PKG/bin/status.sh $PKG/bin/carreport.sh $T/defbad/bin/; cp $PKG/scripts/post.sh $PKG/scripts/preun.sh $T/defbad/scripts/
sed -e 's#^KTB=.*#KTB=${KTB:-$BK/ktime}#' -e 's#echo "$_bid $_kt $WSTA" 2>/dev/null > $KTB#echo "$_bid $_kt $WSTA" > $KTB 2>/dev/null#' $PKG/svc/hotspot.sh > $T/defbad/svc/hotspot.sh
python3 $B/tests/tools/defuse-check.py $T/defbad > $T/defbad.out 2>&1; DEFRC2=$?
check "  베타 2 차주 제보: 정적 검사가 예전 꼴을 잡음(KTB가 BK를 먼저 씀, '> \$KTB 2>/dev/null' 순서)" '[ $DEFRC2 = 1 ] && grep -q "KTB=…가 BK" $T/defbad.out && grep -q "^svc/hotspot.sh:[0-9]* \"> 파일 2>/dev/null\" 순서" $T/defbad.out'
rm -rf $T/defbad
# 동작: 백업 폴더($BK)를 쓸 수 없어도(차의 /ktime처럼) wifi_events가 셸 오류 줄을 ap.log(표준 오류)에 남기지 않음
mkdir -p $WE/robk; chmod 500 $WE/robk; rm -f $WE/w/ktime
printf '%s\n' "<6>[  990.0] CFG80211-ERROR) wl_notify_connect_status_ap : ** AP/GO Link up event **" > $WE/dmesg
(PATH=$WE/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$WE/w BOOT_ID=$WE/bootid KTB=$WE/robk/sub/ktime sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$WE'/bin:'$T'/bin:/usr/bin:/bin:/sbin; wifi_events' > $WE/ro.out 2> $WE/ro.err)
check "  베타 2 차주 제보: 백업 사본을 쓸 수 없어도 셸 오류(can't create·Permission denied) 없이 \$W 기록은 씀" '[ ! -s $WE/ro.err ] && grep -q "AP 올라옴 (커널 990초)" $WE/ro.out && grep -q " 990.0 " $WE/w/ktime'
chmod 700 $WE/robk; rm -rf $WE/robk; rm -f $WE/dmesg $WE/w/ktime

# 베타 1 리뷰 A: 지금 우리 AP에 붙은 기기 수(WSTA)를 커널 줄로 센다(연결 +1, 끊김 -1, 브로드캐스트 끊김은 안 셈, AP 올라옴 0)
WBID=$(cat $WE/bootid); echo boot-A > $WE/bootid; rm -rf $WE/bk; mkdir -p $WE/bk; rm -f $WE/w/ktime
printf '%s\n' "<6>[  900.0] CFG80211-ERROR) wl_notify_connect_status_ap : ** AP/GO Link up event **" "<4>[  901.0] ETHER_TYPE_802_1X[wlan0] [RX] : M4 of 4way" "<4>[  902.0] ETHER_TYPE_802_1X[wlan0] [RX] : M4 of 4way" "<6>[  903.0] CFG80211-ERROR) wl_cfg80211_del_station : Disconnect STA : aa:bb:cc:dd:ee:ff" "<6>[  904.0] CFG80211-ERROR) wl_cfg80211_del_station : Disconnect STA : ff:ff:ff:ff:ff:ff scb_val.val 3" > $WE/dmesg
wa 'UPTIME='$WE'/uptime; wifi_events; echo "WSTA=$WSTA"' > $WE/ws1
check "베타 1 리뷰 A: 붙은 기기 수 = 연결 2 - 끊김 1(브로드캐스트 끊김은 안 셈) = 1, 부팅 id·커널 초와 함께 \$W·\$BK에 둠" 'grep -qx "WSTA=1" $WE/ws1 && grep -qx "boot-A 904.0 1" $WE/w/ktime && grep -qx "boot-A 904.0 1" $WE/bk/ktime'
echo "<6>[  905.0] CFG80211-ERROR) wl_notify_connect_status_ap : ** AP/GO Link up event **" >> $WE/dmesg
wa 'UPTIME='$WE'/uptime; wifi_events; echo "WSTA=$WSTA"' > $WE/ws2
check "  베타 1 리뷰 A: 서비스가 다시 시작해도 기록에서 이어 받고, AP가 다시 올라오면 0" 'grep -qx "WSTA=0" $WE/ws2 && grep -qx "boot-A 905.0 0" $WE/bk/ktime'
# 베타 1 리뷰 C: 재부팅 없이 업데이트($W 지워짐)해도 \$BK의 기록으로 이미 남긴 커널 줄을 다시 쓰지 않음
rm -f $WE/w/ktime
wa 'UPTIME='$WE'/uptime; wifi_events' > $WE/ws3
check "베타 1 리뷰 C: \$W 기록이 지워져도(업데이트) \$BK 사본이 있으면 옛 'AP 채널'·'AP 올라옴' 줄을 다시 옮기지 않음" '[ ! -s $WE/ws3 ]'
echo boot-Z > $WE/bootid; rm -f $WE/w/ktime
wa 'UPTIME='$WE'/uptime; wifi_events' > $WE/ws4
check "  베타 1 리뷰 C: 부팅이 바뀌면(사본이 지난 부팅 것) 처음부터 다시 남김" 'grep -q "Wi-Fi: AP 올라옴 (커널 900초)" $WE/ws4'
echo "$WBID" > $WE/bootid; rm -rf $WE/bk; rm -f $WE/w/ktime $WE/dmesg
# 베타 1 리뷰 B: 시계가 맞기 전(연도가 패키지를 만든 해보다 이전)이면 ap.log 줄 앞에 시각 대신 "부팅 직후"
printf '#!/bin/sh\ncase "$1" in "+%%Y %%m-%%d %%H:%%M:%%S") echo "2016 01-01 18:30:05" ;; *) exec /bin/date "$@" ;; esac\n' > $WE/bin/date; chmod +x $WE/bin/date
echo "12.50 1.00" > $WE/upt12; we 'UPTIME='$WE'/upt12; log "시험 줄"' > $WE/lt1
we 'UPTIME='$WE'/upt12; log "권한 파일 되돌림: com.x.y"' > $WE/lt3
rm -f $WE/bin/date
we 'log "시험 줄"' > $WE/lt2
check "베타 1 리뷰 B·재리뷰 L6: 시계가 맞기 전이면 '부팅 직후(+12초) 시험 줄'(부팅 뒤 초), 맞은 뒤에는 'MM-DD HH:MM:SS 시험 줄'(예전 꼴)" 'grep -qx "부팅 직후(+12초) 시험 줄" $WE/lt1 && grep -q -E "^[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} 시험 줄$" $WE/lt2'
check "  재리뷰 L6: '부팅 직후(+N초)'도 두 칸이라 perms_seed의 칸 위치 읽기(\$3 == 권한, NF == 6)가 그대로 맞음" '[ "$(awk "\$3 == \"권한\" && \$4 == \"파일\" && \$5 == \"되돌림:\" && NF == 6 { print \$6 }" $WE/lt3)" = com.x.y ] && grep -q "^부팅 직후(+12초) 권한 파일 되돌림: com.x.y$" $WE/lt3'
check "  베타 1 리뷰 B: status.sh 감시자 로그(aplog)도 같은 log_ts를 씀" 'grep -q "^aplog() { log_ts; echo \"\$_LT \$\*\" 2>/dev/null >> \$APLOG; }$" $PKG/bin/status.sh'
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
check "  logstart는 log.pid에 pid와 부팅 id를 함께 남김(4b K-7: 서비스가 시작 때 읽은 BID, 없으면 그때 읽음)" 'grep -q "echo \"\$! \${BID:-\$(cat \${BOOT_ID" $PKG/svc/hotspot.sh'

# --- 1.7.2 P-17·P-11 구조 확인 ---
check "1.7.2 P-17: 이번 부팅 첫 시작이면 svc.start와 표시 줄, 같은 부팅이면 '다시 시작'" 'grep -q "^SVC_MARK=\"서비스 시작: 이번 부팅 처음\"" $PKG/svc/hotspot.sh && awk "/^main\(\) \{/,/^}/" $PKG/svc/hotspot.sh | grep -q "log \"\$SVC_MARK" && awk "/^main\(\) \{/,/^}/" $PKG/svc/hotspot.sh | grep -q "서비스 다시 시작(같은 부팅"'
# 4b K-7: 작은 단순화(동작 그대로)
check "4b K-7: mod_update는 mod_pending으로 조건을 보고, try_ready는 setup_done을 부름(같은 조건이 한 곳에)" 'awk "/^mod_update\(\) \{/,/^}/" $PKG/svc/hotspot.sh | grep -q "^  mod_pending || return 1$" && ! awk "/^mod_update\(\) \{/,/^}/" $PKG/svc/hotspot.sh | grep -q "mod.upd ] && read" && awk "/^try_ready\(\) \{/,/^}/" $PKG/svc/hotspot.sh | grep -q "^  setup_done$"'
check "  4b K-7: 지원 안 되는 차 대기도 idle_forever 꼴(sleep을 뒤에서 돌리고 wait, 리뷰 L-3; 6단계 리뷰 L1부터 제보 요청을 보는 idle_req), sleep 3600 반복이 main에 남지 않음" '! awk "/^main\(\) \{/,/^}/" $PKG/svc/hotspot.sh | grep -q "do sleep 3600; done" && [ "$(awk "/^main\(\) \{/,/^}/" $PKG/svc/hotspot.sh | grep -c "^ *idle_forever$")" = 1 ] && [ "$(awk "/^main\(\) \{/,/^}/" $PKG/svc/hotspot.sh | grep -c "^ *idle_req$")" = 2 ]'
check "  4b K-7: 서비스는 시작 때 부팅 id를 한 번 읽어 BID에 둠" 'awk "/^main\(\) \{/,/^}/" $PKG/svc/hotspot.sh | grep -q "^  BID=\$_sb$"'
check "  4b K-7(#65): 첫 시작 줄에 '재부팅 없이 설치·업데이트했으면 그 뒤 첫 시작'도 적음(표시 줄 SVC_MARK는 그대로)" 'grep -q "log \"\$SVC_MARK(부팅 뒤 \${_su:-?}초. 재부팅 없이 설치·업데이트했으면 그 뒤 첫 시작)\"" $PKG/svc/hotspot.sh && grep -q "이번 부팅 처음 시작, 재부팅 없이 설치·업데이트했으면 그 뒤 첫 시작" $PKG/bin/status.sh'
# BID가 있으면 그것을 쓰고(부팅 id 파일을 다시 읽지 않음), 없으면 예전처럼 파일을 읽는다
echo boot-F > $WE/bootid; echo boot-M > $WE/w/nowlan
check "  4b K-7: BID가 있으면 그 값으로 이번 부팅을 봄, 없으면 부팅 id 파일을 읽음(예전 그대로)" '[ "$(we "BID=boot-M; NOWLAN=$WE/w/nowlan; nowlan_now && echo Y")" = Y ] && [ -z "$(we "NOWLAN=$WE/w/nowlan; nowlan_now && echo Y")" ]'
rm -f $WE/w/nowlan
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
  "engine install") [ -f "\$BK/mod.pin" ] && echo "pin-at-install" >> $X/calls; [ -f $X/inst_fail ] && exit 1; [ -f $X/chip_drop ] && { rm -rf $X/sdio; mkdir -p $X/sdio; exit 1; }; case "\$3" in *-2.4.0.zip) [ -f $X/inst_noop ] || { [ -f "\$HMGDATA/mods/wireless-carplay-aa/mod.json" ] && sed "s/2[.]4[.]1/2.4.0/" "\$HMGDATA/mods/wireless-carplay-aa/mod.json" > "\$HMGDATA/mods/wireless-carplay-aa/mod.json.t" && mv -f "\$HMGDATA/mods/wireless-carplay-aa/mod.json.t" "\$HMGDATA/mods/wireless-carplay-aa/mod.json"; } ;; esac; mkdir -p $X/hd/mods/wireless-carplay-aa; echo '{}' > $X/hd/mods/wireless-carplay-aa/mod.json; exit 0 ;;
  "engine plan") [ -f $X/plan_fail ] && { echo "error: engine is busy"; exit 3; }; cat $X/plan; exit 0 ;;
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
asreset() { rm -rf $X/hd $X/bk $X/w $X/calls $X/mc_nw $X/vm_fail $X/inst_fail $X/apply_fail $X/down $T/notice; mkdir -p $X/hd/maps/kia/ev6 $X/bk $X/w; mkdir -p $X/hd/public; : > $X/hd/public/wifi-chip; printf '%s\n' "$PLAN_OK" > $X/plan; }
as() { (PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$X/w BK=$X/bk HMGDATA=$X/hd KP_HMG=$T/app/hmgapi SDIO=$X/nosdio sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$X'/bin:'$T'/bin:/usr/bin:/bin:/sbin; setup_hmgapi'); }
NM=$X/hd/maps/kia/niro/kor/260902
asreset; as > $X/out
check "자동 설정: 니로 지도 12개를 넣고 HMG-API 지도 확인 실행" '[ "$(ls $NM | wc -l | tr -d " ")" = 12 ] && grep -qx "hmgapid engine verify-map" $X/calls && [ -f $X/bk/map.ours ]'
check "  넣은 지도가 패키지 것과 같음" 'diff -r $NM $T/app/hmgapi/maps/kia/niro/kor/260902 >/dev/null'
check "  무선 모드 설치 → 계획이 이 모드뿐 → 적용, 우리가 설치한 표시" 'grep -q "hmgapid engine install .*/hmgapi/wireless-carplay-aa.zip" $X/calls && grep -qx "hmgapid engine apply" $X/calls && [ -f $X/bk/mod.ours ] && [ -f $X/bk/mod.tried ]'
check "  끝나면 내비를 재부팅하라는 알림(RESET 버튼 또는 NEMESIS)" 'grep -q "설정을 마쳤습니다. 내비를 재부팅해 주세요(RESET 버튼 또는 NEMESIS 재부팅)" $T/notice'
rm -f $X/calls $T/notice; as > $X/out
check "  다시 부팅해도 이미 있으면 아무것도 안 함" '! grep -q -E "install|apply|verify-map" $X/calls && [ ! -f $T/notice ]'
rm -rf $X/hd/mods/wireless-carplay-aa; rm -f $X/calls; as > $X/out
check "차주가 모드를 지운 뒤에는 다시 설치하지 않음 (mod.tried)" '! grep -q "engine install" $X/calls'
asreset; mkdir -p $NM; echo official > $NM/car.json; as > $X/out
check "HMG-API에 이 차 지도가 이미 있으면(공식판 등) 덮어쓰지 않음 (다른 차 지도만 넣음)" '[ "$(cat $NM/car.json)" = official ] && ! grep -q verify-map $X/calls && ! grep -q "kia/niro" $X/bk/map.ours 2>/dev/null'
asreset; mkdir -p $X/hd/mods/wireless-carplay-aa; echo '{}' > $X/hd/mods/wireless-carplay-aa/mod.json; : > $X/hd/mods/wireless-carplay-aa/.disabled; as > $X/out
check "모드가 이미 있으면(꺼 둔 것 포함) 설치·적용 안 함" '! grep -q "engine install" $X/calls && ! grep -q "engine apply" $X/calls && [ -f $X/hd/mods/wireless-carplay-aa/.disabled ]'
asreset; printf '%s\n' "$PLAN_OK" "change   /system/app/X.apk [other-mod] -> 1   [restart the app]" > $X/plan; as > $X/out
check "계획에 다른 모드 변경이 있으면 적용하지 않고 앱에서 적용하라고 안내" '! grep -qx "hmgapid engine apply" $X/calls && grep -q "HMG-API 앱에서 변경 사항을 적용" $T/notice && [ -f $X/bk/mod.ours ]'
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
check "  알림은 띄우지 않고(소유자 결정) 진행 화면은 그 안내로 실패, 표시 기록 파일 없음" '[ ! -f $T/notice ] && grep -qx "state=fail" $X/prog && grep -q "^stage=차에 있는 HMG-API 무선 모드가 한국 차용이 아닙니다" $X/prog && [ ! -f $X/bk/mod.foreign.told ]'
rm -f $T/notice $X/prog; asp > $X/out
check "  두 번째 부팅에도 알림 없이 진행 화면 안내만" '[ ! -f $T/notice ] && grep -q "^stage=차에 있는 HMG-API 무선 모드가 한국 차용이 아닙니다" $X/prog'
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
asreset; rm -f $X/prog; mkdir -p $X/hd/mods/wireless-carplay-aa; echo "$FMJ" > $X/hd/mods/wireless-carplay-aa/mod.json; asp > $X/out; rm -rf $X/hd/mods; rm -f $T/notice; asp > $X/out
check "  다른 판을 지운 뒤 다음 부팅에는 한국 차용 모드를 설치·적용" 'grep -q "engine install" $X/calls && grep -qx "hmgapid engine apply" $X/calls && [ -f $X/bk/mod.ours ]'
asreset; rm -f $X/prog; mkdir -p $X/hd/maps/kia/niro/kor/260902; echo '{}' > $X/hd/maps/kia/niro/kor/260902/car.json; mkdir -p $X/hd/mods/wireless-carplay-aa; echo '{"system": [{"region": "KOR"}]}' > $X/hd/mods/wireless-carplay-aa/mod.json; asp > $X/out
check "  무선 모드(한국 차 지원)가 있지만 적용되지 않았으면 그 사유(앱에서 켜고 적용)로 실패" 'grep -qx "state=fail" $X/prog && grep -q "^stage=HMG-API 무선 모드가 있지만 꺼져 있거나 적용되지 않았습니다" $X/prog'
asreset; rm -f $X/prog; echo TESTX.KOR.0000.V001.001.250101 > $T/product; echo "  77 1010 hostapd /data/misc/wifi/hostapd.conf" > $T/ps; asp > $X/out; rm -f $T/product $T/ps
check "  순정 핫스팟이 켜져 있어 건너뛰면 그 사유로 표시" 'grep -qx "state=fail" $X/prog && grep -q "^stage=순정 핫스팟이 켜져 있어" $X/prog'
asreset; rm -f $X/prog; echo TESTX.USA.0000.V001.001.250101 > $T/product; asp > $X/out; rm -f $T/product
check "  지원하지 않는 차(해외)는 바로 실패로 끝남(진행 중으로 남지 않음)" 'grep -qx "state=fail" $X/prog && grep -q "^stage=지원하지 않는 차" $X/prog'
asreset; touch $X/inst_fail; as > $X/out
check "모드 설치 실패 → 안내, 우리 것 표시 없음, 적용 안 함" 'grep -q "설치하지 못했습니다" $T/notice && [ ! -f $X/bk/mod.ours ] && ! grep -q "engine apply" $X/calls'
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
# 1.7.3: 1.7.2 정식(모드 2.4.0)에서 1.7.3(2.4.1)으로 올리는 차: 우리 2.4.0이 있으면 새 판으로 설치하고 재부팅 안내
museed; echo "$KMJ210" | sed 's/2\.1\.0/2.4.0/' > $X/hd/mods/wireless-carplay-aa/mod.json; asp > $X/out
check "1.7.3 모드 2.4.1: 차에 우리 2.4.0이 있으면 패키지의 2.4.1로 설치(mod_update), 진행 기록 '새 판(2.4.1)으로 바꿨습니다'·재부팅 필요, 판 기록 mod.upd" 'grep -q "hmgapid engine install .*/hmgapi/wireless-carplay-aa.zip" $X/calls && grep -qx "state=reboot" $X/prog && grep -q "^stage=무선 모드를 새 판(2.4.1)으로 바꿨습니다" $X/prog && [ "$(cat $X/bk/mod.upd)" = "2.4.1 1" ] && grep -q "업데이트함: 2.4.0 →" $X/out'
check "  패키지 모드 zip md5가 MOD_MD5(2.4.1 확정, 0667dff0…)와 같음" '[ "$(sed -n "s/^MOD_MD5=//p" $PKG/svc/hotspot.sh)" = 0667dff0a8469241689baf13e36e41f9 ] && [ "$(md5 -q $PKG/hmgapi/wireless-carplay-aa.zip 2>/dev/null || md5sum < $PKG/hmgapi/wireless-carplay-aa.zip | cut -c1-32)" = 0667dff0a8469241689baf13e36e41f9 ] && [ "$MV" = 2.4.1 ]'
museed; asp > $X/out
check "1.5.7: 우리가 넣은 2.1.0이 있으면 새 판으로 설치, 적용은 안 함(hooks.jar만: nothing changed), 재부팅 안내(1.7.3 U-5: 진행 기록에만, 알림에 겹치지 않음)" 'grep -q "hmgapid engine install .*/hmgapi/wireless-carplay-aa.zip" $X/calls && ! grep -qx "hmgapid engine apply" $X/calls && [ "$(cat $X/bk/mod.upd)" = "$MV 1" ] && grep -qx "state=reboot" $X/prog && grep -q "^stage=무선 모드를 새 판($MV)으로 바꿨습니다" $X/prog && ! grep -q "새 판($MV)으로 바꿨습니다. 내비를 재부팅" $T/notice 2>/dev/null && grep -q "업데이트함: 2.1.0 →" $X/out'
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
check "  리포트에 차·패키지 판과 대기 안내(1.7.2 P-18: 할 일), 상태 파일에 modver·mod_pending" 'grep -q "무선 모드 판: 차 \$(mod_ver) / 패키지 \$MOD_VER" $PKG/bin/status.sh && grep -q "할 일: 내비를 재부팅하고 3분 기다린 뒤 한 번 더 재부팅해 주세요" $PKG/bin/status.sh && grep -q "새 판(\$MOD_VER)으로 바뀌니" $PKG/bin/status.sh && grep -q "K_PENDING=\$(yesno mod_pending)" $PKG/bin/status.sh && grep -q "echo \"mod_pending=\$K_PENDING\"" $PKG/bin/status.sh'
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
check "  설치 실패 1번째: 이전 판 그대로, 실패 안내 없이 다음 부팅에 다시(횟수 1)" '! grep -q "바꾸지 못했습니다" $T/notice 2>/dev/null && grep -q "2.1.0" $X/hd/mods/wireless-carplay-aa/mod.json && [ "$(cat $X/bk/mod.upd)" = "$MV 1" ] && grep -q "업데이트 실패(1/3)" $X/out'
rm -f $X/calls $T/notice $X/prog; asp > $X/out; rm -f $X/calls $T/notice $X/prog; asp > $X/out; rm -f $X/inst_fail
check "  3번째도 실패하면 그때 한 번 안내(진행 기록 실패 문구, 알림에 겹치지 않음), 적용 안 함" 'grep -q "^stage=무선 모드를 새 판으로 바꾸지 못했습니다. 카플레이는 이전 판으로 계속 됩니다" $X/prog && ! grep -q "새 판으로 바꾸지 못했습니다" $T/notice 2>/dev/null && grep -qx "state=fail" $X/prog && ! grep -q "engine apply" $X/calls && [ "$(cat $X/bk/mod.upd)" = "$MV 3" ]'
rm -f $X/calls $T/notice; asp > $X/out
check "  그 뒤로는 이 버전을 다시 시도하지 않음" '! grep -q "engine install" $X/calls && [ ! -f $T/notice ]'
# 1.5.7 니로에서 실제로 나온 계획(2026-11-07 21:36): "same" 줄뿐, "nothing changed" 줄은 없음
PLAN_SAME='same     /system/etc/permissions/com.hkmc.software.connectivity.androidauto_wireless.xml [wireless-carplay-aa]
same     /system/etc/permissions/com.hkmc.software.connectivity.carplay_wireless.xml [wireless-carplay-aa]
same     /system/lib/libleafiaaac.so [wireless-carplay-aa]
same     /system/onebin/depehev_kr/featurexml.cfg [wireless-carplay-aa]
same     setting prop/persist.iap2.iden.wireless = t [wireless-carplay-aa]
same     setting prop/persist.ium.support = carplay [wireless-carplay-aa]
same     setting prop/persist.sys.iap2.wifi = t [wireless-carplay-aa]'
museed; printf '%s\n' "$PLAN_SAME" > $X/plan; asp > $X/out
check "  니로에서 나온 계획('same' 줄뿐)이면 적용할 것이 없어 앱 적용 안내 없이 재부팅만 안내" '! grep -qx "hmgapid engine apply" $X/calls && ! grep -q "앱에서 변경 사항을 적용" $T/notice && grep -qx "state=reboot" $X/prog && ! grep -q "차주에게 맡김" $X/out'
# 1.7.3(M-9): HMG-API 계획의 note 줄(예: "line … isn't there: nothing to comment")은 변경이 아니다(쓸데없는 "앱에서 적용" 안내 없음)
museed; printf '%s\n' "$PLAN_SAME" "note     /system/onebin/depehev_kr/featurexml.cfg: line \"-x\" isn't there: nothing to comment" > $X/plan; asp > $X/out
check "1.7.3 M-9: 'same'과 'note' 줄뿐인 계획이면 적용할 것이 없어 앱 적용 안내 없이 재부팅만 안내" '! grep -qx "hmgapid engine apply" $X/calls && ! grep -q "앱에서 변경 사항을 적용" $X/prog && grep -qx "state=reboot" $X/prog'
museed; : > $X/plan; asp > $X/out
check "  계획이 비어 있으면(엔진이 답하지 않음) 확인할 수 없어 앱에서 보라고 안내(진행 기록, 알림에 겹치지 않음)" 'grep -q "^stage=.*앱에서 변경 사항을 적용" $X/prog && ! grep -q "앱에서 변경 사항을 적용" $T/notice 2>/dev/null'
museed; printf '%s\n' "$PLAN_OK" > $X/plan; asp > $X/out
check "  새 판에 적용할 변경이 있으면 운행 중일 수 있어 적용하지 않고, 차를 세운 뒤 앱에서 적용하라고 안내" '! grep -qx "hmgapid engine apply" $X/calls && grep -q "^stage=.*차를 세운 뒤 HMG-API 앱에서 변경 사항을 적용" $X/prog && ! grep -q "차를 세운 뒤" $T/notice 2>/dev/null && grep -qx "state=fail" $X/prog'
museed; printf '%s\n' "nothing changed" "problem  /system/x [wireless-carplay-aa]" > $X/plan; asp > $X/out
check "  'nothing changed'여도 problem 줄이 있으면 앱에서 확인하라고 안내(진행 기록)" '! grep -qx "hmgapid engine apply" $X/calls && grep -q "^stage=.*앱에서 변경 사항을 적용" $X/prog'
museed; rm -rf $X/hd/mods; asp > $X/out
check "  모드가 없으면(차주가 지움) 업데이트 경로는 아무것도 안 함" '! grep -q "engine install" $X/calls'
if [ -d $B/usb-modrollback ]; then
# 되돌리기 USB(usb-modrollback): 1.7.3(K-9)부터 1.7.3의 2.4.1을 1.7.2의 2.4.0으로 --force 설치하고 고정(1.7.2 R-4와 같은 방식).
# 1.7.2용 USB(2.3.1~2.4.0 → 2.3.0)는 v1.7.2 릴리스에 공개된 것을 그대로 둔다. 토스트 없이 RESULT.txt·알림 기록
RB=$T/rb; RBS=$B/usb-modrollback/NEMESIS.sh; RBZ=$B/usb-modrollback/kp-rollback/wireless-carplay-aa-2.4.0.zip
# 차에 있는 1.7.3 모드(2.4.1). 아래 시험은 이 판을 다른 판으로 바꿔(sed) 쓴다
KMJ231='{"id": "wireless-carplay-aa", "version": "2.4.1", "system": [{"model": ["DEPEHEV"], "region": "KOR", "firmware": "260902"}]}'
rbreset() { rm -rf $RB; mkdir -p $RB/usb/kp-rollback $RB/hd/mods/wireless-carplay-aa $RB/bk $RB/d $RB/kw $RB/proc $RB/w; : > $RB/bk/mod.ours; echo boot1 > $RB/bootid; cp $RBZ $RB/usb/kp-rollback/; echo "$KMJ231" > $RB/hd/mods/wireless-carplay-aa/mod.json; rm -f $X/calls $T/notice $X/inst_fail $X/apply_fail $X/plan_fail $X/inst_noop; printf '%s\n' "$PLAN_OK" > $X/plan; echo "/dev/block/sda1 $RB/usb vfat rw 0 0" > $RB/mounts; }
# 스크립트 첫 줄의 차 PATH를 테스트 PATH(가짜 hmgapid·am)로 바꿔 돌린다(fixpath와 같은 방식)
rb() { sed "s#^export PATH=.*#export PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin#" $RBS > $RB/run.sh; (KP_FROM_DATA=1 BB=$T/bin/bb U=$RB/usb D=$RB/d HMGDATA=$RB/hd BK=$RB/bk MOUNTS=$RB/mounts KW=$RB/kw PROC=$RB/proc BOOT_ID=$RB/bootid NOTICE=$RB/notice sh $RB/run.sh) > $RB/out 2>&1; }
# 결과: USB의 RESULT.txt와 상태 화면 알림 기록 둘 다에 있는가
rbres() { grep -q "$1" $RB/usb/kp-rollback/RESULT.txt && grep -q "^[0-9][0-9]* boot1 되돌리기 USB: .*$1" $RB/notice; }
# 1.7.3 패키지의 mod_update(부팅 2분 뒤)를 이 차 상태로 돌린다
rbmu() { (PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$RB/w BK=$RB/bk HMGDATA=$RB/hd KP_HMG=$T/app/hmgapi NOTICE=$RB/pkgnotice sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$X'/bin:'$T'/bin:/usr/bin:/bin:/sbin; mod_update; echo "rc=$?"') > $RB/mu.out 2>&1; }
check "되돌리기 USB: 스크립트 앞에 umask 077, 셸 문법, 토스트(am broadcast) 없음" 'grep -qx "umask 077" $RBS && sh -n $RBS && ! grep -q -i -e "am broadcast" -e "TOAST" $RBS'
check "  USB의 되돌리기 zip이 1.7.2 패키지 모드(2.4.0, 1.7.2 MOD_MD5)의 md5와 같고, 옛 2.1.0·2.3.0 zip은 USB에 없음" '[ "$(md5sum < $RBZ | cut -c1-32)" = "$(sed -n "s/^OLD_MD5=//p" $RBS)" ] && [ "$(sed -n "s/^OLD_MD5=//p" $RBS)" = 82b013c6b547dce0e958109b0d2eea98 ] && unzip -p $RBZ mod.json | grep -q "\"version\": \"2.4.0\"" && [ ! -f $B/usb-modrollback/kp-rollback/wireless-carplay-aa-2.3.0.zip ] && [ ! -f $B/usb-modrollback/kp-rollback/wireless-carplay-aa-2.1.0.zip ]'
check "  되돌리는 판(FROM_VERS)은 1.7.3의 2.4.1 하나이고 패키지의 MOD_VER가 들어 있음" '[ "$(sed -n "s/^FROM_VERS=//p" $RBS)" = "\" 2.4.1 \"" ] && case "$(sed -n "s/^FROM_VERS=//p" $RBS)" in *" $(sed -n "s/^MOD_VER=//p" $PKG/svc/hotspot.sh) "*) true ;; *) false ;; esac'
rbreset; rb
check "  2.4.1 → --force로 2.4.0 설치, 고정(mod.pin), 적용, RESULT.txt·상태 화면에 재부팅 안내, 알림 없음, 기록을 USB에" 'grep -q "hmgapid engine install .*wireless-carplay-aa-2.4.0.zip --force" $X/calls && grep -qx "hmgapid engine apply" $X/calls && [ -f $RB/bk/mod.pin ] && rbres "2.4.0으로 되돌리고 고정했습니다. 내비를 재부팅" && [ ! -f $T/notice ] && [ -f $RB/usb/kp-rollback/log/rollback.log ] && [ "$(stat -f %Lp $RB/notice)" = 644 ]'
# 차 흐름: 2.4.1 → (USB) 2.4.0 → 고정 → 재부팅(1.7.3 mod_update가 다시 바꾸지 않음) → (USB UNPIN) → 재부팅 → 2.4.1
echo "$KMJ231" | sed 's/2\.4\.1/2.4.0/' > $RB/hd/mods/wireless-carplay-aa/mod.json; rm -f $X/calls; rbmu
check "  흐름: 고정된 2.4.0이면 재부팅 뒤 1.7.3 mod_update가 2.4.1로 다시 바꾸지 않음" 'grep -qx "rc=1" $RB/mu.out && ! grep -q "engine install" $X/calls 2>/dev/null'
: > $RB/usb/kp-rollback/UNPIN; echo "2.4.1 3" > $RB/bk/mod.upd; rm -f $RB/usb/kp-rollback/RESULT.txt; rb; rm -f $RB/usb/kp-rollback/UNPIN
check "  흐름: UNPIN이면 고정만 풂(mod.pin·mod.upd 지움), 설치 안 함, 결과 안내" '[ ! -f $RB/bk/mod.pin ] && [ ! -f $RB/bk/mod.upd ] && ! grep -q "engine install" $X/calls 2>/dev/null && rbres "고정을 풀었습니다"'
rm -f $X/calls; rbmu
check "  흐름: 고정을 푼 뒤 재부팅하면 1.7.3 mod_update가 패키지의 판(2.4.1)을 설치(시도 1)" 'grep -q "hmgapid engine install .*/hmgapi/wireless-carplay-aa.zip" $X/calls && [ "$(cat $RB/bk/mod.upd)" = "$(sed -n "s/^MOD_VER=//p" $PKG/svc/hotspot.sh) 1" ]'
for i in 1 2 3 4 5 6; do echo "1 boot0 old$i" >> $RB/notice; done; rb
check "  알림 기록은 최근 5줄만 남고(1.7.2 notice와 같게) 임시 파일이 남지 않음" '[ "$(wc -l < $RB/notice | tr -d " ")" = 5 ] && ! grep -q old2 $RB/notice && grep -q old6 $RB/notice && ! ls $RB/notice.rb.* >/dev/null 2>&1'
rbreset; echo "x" >> $RB/usb/kp-rollback/wireless-carplay-aa-2.4.0.zip; rb
check "  zip이 맞지 않으면 아무것도 바꾸지 않음" '! grep -q "engine install" $X/calls 2>/dev/null && [ ! -f $RB/bk/mod.pin ] && rbres "맞지 않습니다"'
rbreset; touch $X/inst_fail; rb; rm -f $X/inst_fail
check "  엔진이 거부하면 고정하지 않고 지금 판 그대로라고 안내" '[ ! -f $RB/bk/mod.pin ] && ! grep -q "engine apply" $X/calls && rbres "지금 판(2.4.1) 그대로"'
rbreset; echo '{"id": "wireless-carplay-aa", "version": "2.2.0", "system": [{"region": "USA"}]}' > $RB/hd/mods/wireless-carplay-aa/mod.json; rb
check "  한국 차 항목이 없는 다른 판은 덮어쓰지 않음" '! grep -q "engine install" $X/calls 2>/dev/null && rbres "Korea Projection 것이 아닙니다"'
rbreset; sed -i.bak 's/2\.4\.1/2.4.0/' $RB/hd/mods/wireless-carplay-aa/mod.json; rb
check "  1.7.3(K-9): 이미 2.4.0(1.7.2 판)이면 설치도 고정도 하지 않음(아무것도 안 함)" '! grep -q "engine install" $X/calls 2>/dev/null && [ ! -f $RB/bk/mod.pin ] && rbres "지금 무선 모드는 이미 2.4.0입니다. 아무것도 바꾸지 않았습니다"'
rbreset; sed -i.bak 's/2\.4\.1/2.4.0/' $RB/hd/mods/wireless-carplay-aa/mod.json; : > $RB/bk/mod.pin; rb
check "  이미 2.4.0으로 고정된 차는 설치하지 않고(고정 유지), 마지막 묶음 중간 3②: 남은 적용이 있으면 이어서 적용" '! grep -q "engine install" $X/calls 2>/dev/null && [ -f $RB/bk/mod.pin ] && grep -qx "hmgapid engine apply" $X/calls && rbres "이미 2.4.0으로 고정되어 있어 남은 적용을 마쳤습니다"'
rbreset; sed -i.bak 's/2\.4\.1/2.4.0/' $RB/hd/mods/wireless-carplay-aa/mod.json; : > $RB/bk/mod.pin; printf '%s\n' "$PLAN_SAME" > $X/plan; rb
check "  마지막 묶음 중간 3②: 이미 2.4.0·고정이고 적용할 것이 없으면 아무것도 바꾸지 않음(설치·적용 없음)" '! grep -q "engine install" $X/calls 2>/dev/null && ! grep -qx "hmgapid engine apply" $X/calls && [ -f $RB/bk/mod.pin ] && rbres "이미 2.4.0으로 고정되어 있습니다. 아무것도 바꾸지 않았습니다."'
rbreset; sed -i.bak 's/2\.4\.1/2.4.0/' $RB/hd/mods/wireless-carplay-aa/mod.json; : > $RB/bk/mod.pin; printf '%s\n' "change   /system/app/X.apk [other-mod] -> 1   [restart the app]" > $X/plan; rb
check "  마지막 묶음 중간 3②: 이미 고정인데 다른 모드 변경이 있으면 적용하지 않고 앱에서 적용하라고 안내" '! grep -qx "hmgapid engine apply" $X/calls && rbres "이미 2.4.0으로 고정되어 있습니다. HMG-API 앱에서 변경 사항을 적용"'
rbreset; : > $RB/bk/mod.pin; touch $X/inst_fail; rb; rm -f $X/inst_fail
check "  마지막 묶음 중간 3①: 2.4.1 차에 전에 쓴 고정이 남아 있어도 설치가 실패하면 고정을 지움(새 판으로 못 가는 길 막음)" 'grep -q "engine install" $X/calls && [ ! -f $RB/bk/mod.pin ] && rbres "HMG-API가 거부해 되돌리지 못했습니다"'
rbreset; printf '%s\n' "$PLAN_SAME" "WARNING: the car's ADB TCP switch is on" > $X/plan; rb
check "  마지막 묶음 L3: 계획이 same 줄과 WARNING 줄뿐이면 적용할 것 없음(적용 안 함, 재부팅 안내)" '! grep -qx "hmgapid engine apply" $X/calls && rbres "되돌리고 고정했습니다"'
# 되돌리기 USB 최종(중간 1): 계획 명령이 실패해 오류 줄만 내거나 아무것도 내지 않으면 적용하지 않고, 그때 판·고정을 알림
rbreset; touch $X/plan_fail; rb; rm -f $X/plan_fail
check "  되돌리기 최종 중간 1: 계획 명령이 실패하면(오류 줄만) 적용하지 않고 '계획을 확인하지 못해'와 지금 판·고정을 알림" '! grep -qx "hmgapid engine apply" $X/calls && grep -q "engine install" $X/calls && rbres "HMG-API 계획을 확인하지 못해 적용하지 않았습니다(무선 모드 2.4.0, 고정 있음)"'
rbreset; : > $X/plan; rb
check "  되돌리기 최종 중간 1: 계획이 빈 출력이면 '되돌리고 고정했습니다'라 하지 않고 확인하지 못했다고 알림" '! grep -qx "hmgapid engine apply" $X/calls && rbres "HMG-API 계획을 확인하지 못해" && ! grep -q "되돌리고 고정했습니다" $RB/usb/kp-rollback/RESULT.txt'
rbreset; sed -i.bak 's/2\.4\.1/2.4.0/' $RB/hd/mods/wireless-carplay-aa/mod.json; : > $RB/bk/mod.pin; touch $X/plan_fail; rb; rm -f $X/plan_fail
check "  되돌리기 최종 중간 1: 이어서 하기(이미 2.4.0·고정)에서도 계획 실패면 적용하지 않음" '! grep -qx "hmgapid engine apply" $X/calls && rbres "HMG-API 계획을 확인하지 못해 적용하지 않았습니다(무선 모드 2.4.0, 고정 있음)"'
# 되돌리기 최종(낮음 2): 설치했다는데 판이 그대로면 고정을 풀고 실패로 알림, 'nothing changed … problem'은 문제로 봄
rbreset; touch $X/inst_noop; rb; rm -f $X/inst_noop
check "  되돌리기 최종 낮음 2: 설치 뒤에도 판이 2.4.0이 아니면 고정을 풀고 '바꾸지 못했습니다'(되돌리고 고정했다고 하지 않음, 적용 안 함)" '[ ! -f $RB/bk/mod.pin ] && ! grep -qx "hmgapid engine apply" $X/calls && rbres "무선 모드를 2.4.0으로 바꾸지 못했습니다(지금 2.4.1, 고정은 풀었습니다)"'
rbreset; echo "nothing changed (1 problem)" > $X/plan; rb
check "  되돌리기 최종 낮음 2: 'nothing changed … problem'은 할 일 없음이 아니라 문제(적용하지 않고 앱에서 확인 안내)" '! grep -qx "hmgapid engine apply" $X/calls && rbres "HMG-API 앱에서 변경 사항을 적용" && ! grep -q "되돌리고 고정했습니다" $RB/usb/kp-rollback/RESULT.txt'
rbreset; rb
check "  되돌리기 최종: 정상 흐름은 설치 뒤 판이 2.4.0인 것을 확인하고 '되돌리고 고정했습니다'(시험의 가짜 엔진이 판을 실제로 바꿈)" 'grep -q "\"version\": \"2.4.0\"" $RB/hd/mods/wireless-carplay-aa/mod.json && [ -f $RB/bk/mod.pin ] && rbres "되돌리고 고정했습니다"'
# 1.7.3(K-9): 1.7.2 판(2.3.x)과 다른 판은 바꾸지도 고정하지도 않는다(옛 판을 2.4.0으로 올리거나 다음 판을 내리지 않음)
for v in 2.1.0 2.3.0 2.3.1 2.3.4 2.4.2 2.5.0 '2.4.1-x"name'; do
  rbreset; echo "$KMJ231" | sed "s/2\.4\.1/$v/" > $RB/hd/mods/wireless-carplay-aa/mod.json; rb
  check "  되돌리는 판이 아닌 $v는 바꾸지 않고 고정도 안 함" '! grep -q "engine install" $X/calls 2>/dev/null && [ ! -f $RB/bk/mod.pin ] && rbres "이 USB가 되돌리는 판(1.7.3의 2.4.1)이 아닙니다" && ! grep -q "name" $RB/usb/kp-rollback/RESULT.txt'
done
# 6단계 리뷰 L7: 고정 표시는 설치 전에 쓰고(설치 중 패키지 서비스가 끼어들지 않게), 설치가 실패하면 지움
rbreset; rb
check "  6단계 리뷰 L7: 고정(mod.pin)은 엔진 설치 **전에** 있음" 'grep -qx "pin-at-install" $X/calls && [ -f $RB/bk/mod.pin ]'
rbreset; touch $X/inst_fail; rb; rm -f $X/inst_fail
check "  6단계 리뷰 L7: 설치가 실패하면 이번에 쓴 고정을 지우고 아무것도 바꾸지 않음" 'grep -q "engine install" $X/calls && [ ! -f $RB/bk/mod.pin ] && rbres "HMG-API가 거부해 되돌리지 못했습니다"'
# 6단계 리뷰 L8: U를 주지 않으면 스크립트 위치($0)로 USB를 고르고, 헤드유닛에 복사해 다시 돌 때 넘김(export U)
RBU=$(sed -n '/^if \[ -z "\$U" \]; then/,/^export U$/p' $RBS)
check "  6단계 리뷰 L8: usb1에서 돌면 U=/storage/usb1, usb0이면 usb0, 정한 값은 export" '[ "$(U= sh -c "$RBU
echo \$U" /storage/usb1/NEMESIS.sh)" = /storage/usb1 ] && [ "$(U= sh -c "$RBU
echo \$U" /storage/usb0/NEMESIS.sh)" = /storage/usb0 ] && [ "$(U=/x/y sh -c "$RBU
echo \$U" /storage/usb1/NEMESIS.sh)" = /x/y ] && [ -n "$RBU" ]'
rbreset; : > $RB/bk/mod.pin; echo 2.4.1 > $RB/bk/mod.upd; : > $RB/usb/kp-rollback/UNPIN; rb
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
check "  재리뷰 M: 내비에 busybox가 없으면 패키지에 든 busybox로 되돌림" 'grep -q "hmgapid engine install .*wireless-carplay-aa-2.4.0.zip --force" $X/calls && [ -f $RB/bk/mod.pin ] && rbres "되돌리고 고정했습니다"'
rbreset; rbx $RB/nobb2
check "  busybox가 하나도 없으면 아무것도 바꾸지 않고 RESULT.txt·상태 화면에 이유를 남김" '! grep -q "engine" $X/calls 2>/dev/null && [ ! -f $RB/bk/mod.pin ] && rbres "busybox를 찾지 못해" && [ "$(stat -f %Lp $RB/notice)" = 644 ]'
rbreset; echo old > $RB/d/out/install.txt 2>/dev/null || { mkdir -p $RB/d/out; echo old > $RB/d/out/install.txt; }; touch $X/down; rb; rm -f $X/down
check "  재리뷰 L: 지난 실행의 기록(install.txt 등)은 USB로 다시 가지 않음" '[ ! -f $RB/usb/kp-rollback/log/install.txt ]'
rbreset; sed -i.bak 's/2\.4\.1/2.4.0/' $RB/hd/mods/wireless-carplay-aa/mod.json; rm -f $RB/bk/mod.ours; rb
check "  재리뷰 L: 2.4.0이어도 Korea Projection 것이 아니면 고정했다고 하지 않음" '[ ! -f $RB/bk/mod.pin ] && rbres "Korea Projection 것이 아닙니다"'
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
rm -f $X/vm_fail $X/calls $T/notice; as > $X/out
check "  다음 부팅: 같은 지도는 다시 넣지 않고, 확인·모드 설치도 안 함, 알림 없음" '[ ! -d $NM ] && ! grep -q -E "verify-map|engine install" $X/calls && [ ! -f $T/notice ] && grep -q "지도 확인에 실패한 지도" $X/out'
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
check "적용 실패 → 안내 (재시작 안내 없음)" 'grep -q "적용에 실패" $T/notice && ! grep -q "마쳤습니다" $T/notice'
asreset; touch $X/vm_fail; rm -f $X/plan; : > $X/plan; mkdir -p $X/hd/mods/wireless-carplay-aa; echo '{}' > $X/hd/mods/wireless-carplay-aa/mod.json; as > $X/out
check "지도 확인 실패 → 안내, 재시작 안내 없음" 'grep -q "지도 확인에 실패" $T/notice && ! grep -q "마쳤습니다" $T/notice'
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
check "쏘나타(시험 지원): 쏘나타 지도만 넣고 지도 확인 한 번, 무선 모드 설치·적용" 'diff -r $SM $T/app/hmgapi/maps/hyundai/sonata/kor/260902 >/dev/null && [ ! -d $NM ] && [ "$(grep -c verify-map $X/calls)" = 1 ] && grep -q "engine install" $X/calls && grep -qx "hmgapid engine apply" $X/calls && grep -q "설정을 마쳤습니다" $T/notice'
asreset; mkdir -p $X/hd/maps/unknown/dn822hev/kor/260902; echo own > $X/hd/maps/unknown/dn822hev/kor/260902/car.json
echo DN822HEV.KOR.0000.V039.001.260902 > $T/product; as > $X/out; rm -f $T/product
check "  차주가 차에서 만든 지도(unknown/dn822hev)는 그대로 두고 우리 지도를 더해 확인" '[ "$(cat $X/hd/maps/unknown/dn822hev/kor/260902/car.json)" = own ] && [ -f $SM/car.json ] && [ "$(grep -c verify-map $X/calls)" = 1 ]'
asreset; mkdir -p $X/hd/maps/unknown/dn822hev/kor/260902; echo own > $X/hd/maps/unknown/dn822hev/kor/260902/car.json; touch $X/vm_fail
echo DN822HEV.KOR.0000.V039.001.260902 > $T/product; as > $X/out; rm -f $T/product
check "  우리 지도의 확인이 실패하면 우리 지도만 빼고 차주 지도로 다시 확인, 모드 설치 안 함" '[ ! -d $SM ] && [ "$(cat $X/hd/maps/unknown/dn822hev/kor/260902/car.json)" = own ] && [ "$(grep -c verify-map $X/calls)" = 2 ] && ! grep -q "engine install" $X/calls'
asreset; echo DN822HEV.KOR.0000.V039.001.260101 > $T/product; as > $X/out; rm -f $T/product
check "  쏘나타라도 펌웨어가 다르면 자동 시험: 우리 쏘나타 지도는 넣지 않고 차에서 지도를 만들어 확인" '[ ! -d $SM ] && grep -qx "hmgapid engine map-car --write" $X/calls && [ -f $X/hd/maps/unknown/dn822hev/kor/260101/car.json ] && [ "$(grep -c verify-map $X/calls)" = 1 ] && grep -q "engine install" $X/calls && grep -q "자동으로 설정한 차" $T/notice'
# 자동 시험(목록에 없는 한국 차)
AM=$X/hd/maps/unknown/testx/kor/260101
asreset; echo TESTX.KOR.0000.V039.001.260101 > $T/product; as > $X/out
check "자동 시험: 목록에 없는 한국 차는 HMG-API가 차에서 지도를 만들고 확인한 뒤 모드 설치·적용, 시험 알림" '[ -f $AM/car.json ] && grep -qx "unknown/testx/kor/260101" $X/bk/map.ours && grep -qx "hmgapid engine verify-map" $X/calls && grep -q "engine install" $X/calls && grep -qx "hmgapid engine apply" $X/calls && grep -q "자동으로 설정한 차" $T/notice && [ ! -d $NM ]'
rm -f $X/calls $T/notice; as > $X/out
check "  다시 부팅: 지도가 있으면 다시 만들지 않고 다시 확인도 안 함" '! grep -q -E "map-car|verify-map|engine install" $X/calls'
rm -rf $X/hd/maps/unknown; rm -f $X/calls; as > $X/out
check "  HMG-API 업데이트로 지도 폴더가 바뀌면 다시 만들고 확인" '[ -f $AM/car.json ] && grep -q "map-car --write" $X/calls && grep -qx "hmgapid engine verify-map" $X/calls'
asreset; touch $X/vm_fail; as > $X/out
check "  만든 지도의 확인이 실패하면 그 지도를 지우고 automap.bad, 모드 설치 안 함" '[ ! -d $AM ] && [ -f $X/bk/automap.bad ] && ! grep -q "engine install" $X/calls && grep -q "지도 확인에 실패" $T/notice'
rm -f $X/vm_fail $X/calls $T/notice; as > $X/out
check "  다음 부팅: 실패 기록이 있으면 지도도 모드도 다시 하지 않음, 알림 없음" '! grep -q -E "map-car|verify-map|engine install" $X/calls && [ ! -f $T/notice ]'
asreset; mkdir -p $X/hd/maps/hyundai/testx/kor/260101; echo own > $X/hd/maps/hyundai/testx/kor/260101/car.json; as > $X/out
check "  차에 이 차 지도가 이미 있으면(차주·공식판) 만들지 않고 한 번 확인만, 실패해도 지우지 않음" '! grep -q map-car $X/calls && [ "$(grep -c verify-map $X/calls)" = 1 ] && [ -f $X/bk/automap.checked ]'
asreset; mkdir -p $X/hd/maps/hyundai/testx/kor/260101; echo own > $X/hd/maps/hyundai/testx/kor/260101/car.json; touch $X/vm_fail; as > $X/out
check "    그 지도의 확인이 실패하면 지우지 않고 automap.bad, 모드 설치 안 함" '[ "$(cat $X/hd/maps/hyundai/testx/kor/260101/car.json)" = own ] && [ -f $X/bk/automap.bad ] && ! grep -q "engine install" $X/calls'
asreset; touch $X/mc_fail; as > $X/out; rm -f $X/mc_fail
check "  지도 만들기가 실패하면 모드 설치 안 함, 제보 안내 알림" '[ -f $X/bk/automap.bad ] && ! grep -q "engine install" $X/calls && grep -q "지도를 만들지 못했습니다" $T/notice'
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
check "  wireless.projection이 있으면 삭제 안내 알림(한 번만)" 'grep -q "wireless.projection을 삭제한 뒤 내비를 재부팅" $T/notice && [ -f $X/bk/wp.told ]'
rm -f $T/notice; mkdir -p $X/wp; (PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$X/w BK=$X/bk HMGDATA=$X/hd KP_HMG=$T/app/hmgapi WPDIR=$X/wp SDIO=$X/nosdio sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$X'/bin:'$T'/bin:/usr/bin:/bin:/sbin; setup_hmgapi') > $X/out; rm -rf $X/wp
check "    다음 부팅에는 알림 없음" '[ ! -f $T/notice ]'
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
skreset() { rm -rf $SK/w $SK/bk $SK/hd $SK/calls $SK/notice $SK/prog $SK/ps $SK/ps.* $SK/hostapd-kp.conf $SK/wifi $SK/out; mkdir -p $SK/w $SK/bk $SK/hd/mods/wireless-carplay-aa $SK/wifi; echo "ctrl_interface=wlan0" > $SK/wifi/wpa_supplicant.conf; chmod 644 $SK/wifi/wpa_supplicant.conf; echo '{"system": [{"region": "KOR"}]}' > $SK/hd/mods/wireless-carplay-aa/mod.json; echo BDPE.KOR.0000.V039.001.260902 > $SK/product; : > $SK/ps; sconf 'SSID\cX'; }
skrun() { (PATH=$SK/bin:$T/bin:/usr/bin:/bin:/sbin env HOTSPOT_LIB=1 NOTICE=$SK/notice BB=$T/bin/bb W=$SK/w BK=$SK/bk HMGDATA=$SK/hd PROG=$SK/prog BOOT_ID=$SK/bootid PROC=$SK/proc CONF=$SK/hostapd-kp.conf SRC=$T/softap.conf WCONF=$SK/wifi/wpa_supplicant.conf WIFI_WAIT=0 WPDIR=$SK/none KT=$SK/w/kt "$@" ${SKSH:-sh} -c '. '$T'/app/svc/hotspot.sh; export PATH='$SK'/bin:'$T'/bin:/usr/bin:/bin:/sbin; fix_perms() { :; }; kill() { echo "kill $*" >> '$SK'/calls; }; _wc=0; wait() { _wc=$((_wc+1)); [ -f '$SK'/ps.$_wc ] && cp '$SK'/ps.$_wc '$SK'/ps; [ -f '$SK'/conf.$_wc ] && cp '$SK'/conf.$_wc '$SK'/stock/hostapd.conf; [ $_wc -ge ${SKW:-1} ] && exit 7; return 0; }; main') > $SK/out 2>&1; echo "rc=$?" >> $SK/out; }
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
# 1.7.3: 순정 AP 회차는 30초 대기 두 번(사이에 제보 요청 점검) 뒤에 본문이 돈다: 가짜 wait 번호는 회차마다 2씩
skreset; stockps > $SK/ps; : > $SK/ps.2; stockps > $SK/ps.4; skrun SKW=8
check "1.6.2: 순정 AP가 도중에 사라지면 우리 AP로 바꾸지 않고 기다림, 다시 켜지면 기록(바뀔 때만 한 줄씩)" '[ "$(grep -c "순정 카플레이 AP가 꺼짐: 순정이 다시 켤 때까지 기다림" $SK/out)" = 1 ] && [ "$(grep -c "순정 카플레이 AP가 켜짐$" $SK/out)" = 1 ] && noours && grep -qx "rc=7" $SK/out'
skreset; : > $SK/bk/stockap.seen; skrun SKW=2
check "  순정 AP를 본 차는 다음 부팅에 순정 AP가 늦어도 우리 AP를 켜지 않고 기다림, 못 본 부팅을 셈(1)" 'grep -q "순정 카플레이 AP를 기다림" $SK/out && noours && ! grep -q "내비 Wi-Fi" $SK/prog 2>/dev/null && [ "$(cat $SK/bk/stockap.miss)" = "1 boot-sk" ]'
skrun SKW=2
check "  같은 부팅에 서비스가 다시 시작돼도 한 번만 셈" '[ "$(cat $SK/bk/stockap.miss)" = "1 boot-sk" ]'
stockps > $SK/ps.2; skrun SKW=3
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
# 1.7.3: 다른 hostapd 대기도 30초 대기 두 번마다 한 번 본다(가짜 wait 번호 2씩)
skreset; stockps > $SK/ps; sconf HotspotName1; : > $SK/ps.2; stockps > $SK/ps.4; skrun SKW=5
check "  순정 hostapd가 한 번 안 보였다 다시 보이면 계속 기다림(우리 것 시작 안 함)" '! grep -q "다른 hostapd가 멈춤: 시작" $SK/out && noours'
skreset; stockps > $SK/ps; sconf HotspotName1; : > $SK/ps.2; skrun SKW=5; /bin/sleep 1
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
skl() { (PATH=$SK/bin:$T/bin:/usr/bin:/bin:/sbin env HOTSPOT_LIB=1 NOTICE=$SK/notice BB=$T/bin/bb W=$SK/w BK=$SK/bk HMGDATA=$SK/hd PROG=$SK/prog BOOT_ID=$SK/bootid PROC=$SK/proc CONF=$SK/hostapd-kp.conf SRC=${SKSRC:-$T/softap.conf} KT=$SK/w/kt sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$SK'/bin:'$T'/bin:/usr/bin:/bin:/sbin; kill() { echo "kill $*" >> '$SK'/calls; }; wait() { exit 7; }; parse_conf $SRC; '"$1"); }
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
PATH=$SK/bin:$T/bin:/usr/bin:/bin:/sbin env HOTSPOT_LIB=1 BB=$T/bin/bb W=$SK/w BK=$SK/bk HMGDATA=$SK/hd PROG=$SK/prog BOOT_ID=$SK/bootid PROC=$SK/proc CONF=$SK/hostapd-kp.conf SRC=$T/softap.conf WCONF=$SK/wifi/wpa_supplicant.conf WPDIR=$SK/none KT=$SK/w/kt sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$SK'/bin:'$T'/bin:/usr/bin:/bin:/sbin; fix_perms() { :; }; kill() { echo "kill $*" >> '$SK'/calls; }; sleep() { /bin/sleep 2; }; main' > $SK/out 2>&1 &
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
  skreset; stockps > $SK/ps; : > $SK/ps.2; stockps > $SK/ps.4; skrun SKW=8
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
chmod +x $X/bin/svc
aw() { (PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BOOT_ID=$X/bootid NOTICE=$X/notices BB=$T/bin/bb W=$X/w BK=$X/bk HMGDATA=$X/hd KP_HMG=$T/app/hmgapi SDIO=$X/sdio WAKE_MAX=100 sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$X'/bin:'$T'/bin:/usr/bin:/bin:/sbin; setup_hmgapi'); }
awreset() { asreset; rm -rf $X/sdio $X/chip_ok $X/chip_drop $X/notices; rm -f $X/hd/public/wifi-chip; mkdir -p $X/sdio; echo 0 > $X/bk/wifi_on; [ -f $X/bootid ] || echo b0 > $X/bootid; }
asreset; rm -f $X/notices; as > $X/out
check "Wi-Fi 칩 기록이 있으면 Wi-Fi를 건드리지 않음" '! grep -q "svc wifi" $X/calls && grep -q "engine install" $X/calls && ! grep -q "Wi-Fi를 한 번 켭니다" $X/notices'
awreset; mkdir -p $X/sdio/mmc1:0001:1; aw > $X/out
check "  칩이 SDIO에 이미 보이면 Wi-Fi를 건드리지 않음" '! grep -q "svc wifi" $X/calls && grep -q "engine install" $X/calls'
awreset; touch $X/chip_ok; aw > $X/out
check "칩이 안 보이면 미리 안내하고 Wi-Fi를 한 번 켜고, 칩이 나타나면 모드 설치" 'grep -q "Wi-Fi를 한 번 켭니다" $X/notices && grep -qx "svc wifi enable" $X/calls && grep -q "engine install" $X/calls && grep -q "칩이 나타남" $X/out && [ ! -f $X/bk/wifi.nochip ] && ! grep -q "svc wifi disable" $X/calls'
check "  깨우기는 모드 설치보다 먼저" '[ "$(grep -n "svc wifi enable" $X/calls | cut -d: -f1)" -lt "$(grep -n "engine install" $X/calls | cut -d: -f1)" ]'
awreset; touch $X/chip_ok $X/chip_drop; aw > $X/out; rm -f $X/calls $X/notices; aw > $X/out2
check "칩이 잠깐 보였다 사라져 설치가 실패해도 다음 부팅에 Wi-Fi를 다시 켜지 않음 (wifi.woke)" '[ -f $X/bk/wifi.woke ] && ! grep -q "svc wifi" $X/calls && ! grep -q "engine install" $X/calls && [ ! -s $X/notices ]'
# 1.7.3(W-4·G-1): 순정 module_version이 3이 아닌데 칩이 안 보이면 굳히지 않고 부팅마다 한 번씩, 최대 3번 깨운다(부팅은 boot_id로 셈)
echo b1 > $X/bootid; awreset; aw > $X/out
check "1.7.3 W-4: 첫 부팅에 Wi-Fi를 켜도 칩이 안 나타나면 모드 설치 안 함, 칩 없음으로 굳히지 않음(wifi.wake 1번째), 다음 부팅에 다시" '! grep -q "engine install" $X/calls && [ ! -f $X/bk/wifi.nochip ] && [ ! -f $X/bk/wifi.nopart ] && [ "$(cat $X/bk/wifi.wake)" = "1 b1" ] && grep -q "다음 부팅에 다시 깨움(1/3" $X/out'
check "  1.7.1: 그때의 순정 Wi-Fi 기록을 nochip-wifi.txt에 남김(가림: MAC·SSID 없음)" 'grep -q "칩 깨우기 실패 기록" $X/w/nochip-wifi.txt && grep -q "## logcat" $X/w/nochip-wifi.txt && grep -q "SUP_DISCONNEC" $X/w/nochip-wifi.txt'
check "  설치 전에 Wi-Fi가 꺼져 있었으면 다시 끔" 'grep -qx "svc wifi disable" $X/calls'
rm -f $X/calls $X/notices; aw > $X/out
check "  같은 부팅에 서비스가 다시 돌면 다시 켜지 않음(알림도 없음)" '! grep -q "svc wifi" $X/calls && [ ! -s $X/notices ] && [ "$(cat $X/bk/wifi.wake)" = "1 b1" ]'
echo b2 > $X/bootid; rm -f $X/calls; aw > $X/out
check "  2번째 부팅: 다시 깨움(2/3), 아직 굳히지 않음" 'grep -qx "svc wifi enable" $X/calls && [ "$(cat $X/bk/wifi.wake)" = "2 b2" ] && [ ! -f $X/bk/wifi.nochip ]'
echo b3 > $X/bootid; rm -f $X/calls $X/notices; aw > $X/out
check "  3번째 부팅에도 안 나타나면 칩 실패로 끝냄(wifi.nochip), W-2·W-6 문구(동글 안내)로 알림" 'grep -qx "svc wifi enable" $X/calls && [ -f $X/bk/wifi.nochip ] && grep -q "이 차는 Wi-Fi 칩이 켜지지 않아 지원하기 어렵습니다. USB Wi-Fi 동글로 쓰는 방법을 준비하고 있습니다." $X/notices && ! grep -q "engine install" $X/calls'
echo b4 > $X/bootid; rm -f $X/calls $X/notices; aw > $X/out
check "  그 뒤 부팅: Wi-Fi를 다시 켜지 않고, 알림도 없음" '! grep -q "svc wifi" $X/calls && ! grep -q "engine install" $X/calls && [ ! -s $X/notices ]'
mkdir -p $X/sdio/mmc1:0001:1; rm -f $X/calls; aw > $X/out
check "  그 뒤 칩이 보이게 되면(차주가 켬) 기록과 상관없이 모드 설치" 'grep -q "engine install" $X/calls && ! grep -q "svc wifi" $X/calls'
# 1.7.3(W-1): 순정 module_version 3이면 깨우지 않고 바로 부품 없음
printf '#!/bin/sh\necho "11-10 09:00:00.000 D/WifiHW   (  500): wifi_get_module_version: 3"\n' > $X/bin/logcat; chmod +x $X/bin/logcat
echo b1 > $X/bootid; awreset; aw > $X/out
check "1.7.3 W-1: 순정 module_version=3이면 Wi-Fi를 켜지 않고(USB·블루투스가 다시 시작되지 않게) 부품 없음(wifi.nopart)으로 끝냄, W-1·W-6 문구" '! grep -q "svc wifi" $X/calls && [ -f $X/bk/wifi.nopart ] && [ "$(cat $X/bk/wifi.modver)" = 3 ] && grep -q "이 차의 내비에는 Wi-Fi 부품이 없어 무선 카플레이를 쓸 수 없습니다. USB Wi-Fi 동글로 쓰는 방법을 준비하고 있습니다." $X/notices && ! grep -q "engine install" $X/calls'
check "  판정 근거를 nochip-wifi.txt(·\$BK 사본)에 남김" 'grep -q "부품 없음 판정" $X/w/nochip-wifi.txt && [ -s $X/bk/nochip-wifi.txt ]'
rm -f $X/bin/logcat
# 깨운 뒤 순정이 module_version 3을 남기면(드라이버를 올려 보고서야 알 수 있는 차) 그때 부품 없음
printf '#!/bin/sh\n[ -f %s/modver3 ] && echo "11-10 09:00:00.000 D/WifiHW   (  500): wifi_get_module_version: 3"\nexit 0\n' $X > $X/bin/logcat; chmod +x $X/bin/logcat
cat > $X/bin/svc <<E2
#!/bin/sh
echo "svc \$*" >> $X/calls
[ "\$*" = "wifi enable" ] && : > $X/modver3
exit 0
E2
chmod +x $X/bin/svc; awreset; rm -f $X/modver3; aw > $X/out
check "  깨운 뒤 module_version=3이 나오면 그때 부품 없음(한 번만 깨움)" '[ "$(grep -c "svc wifi enable" $X/calls)" = 1 ] && [ -f $X/bk/wifi.nopart ] && [ ! -f $X/bk/wifi.nochip ]'
rm -f $X/bin/logcat $X/modver3
# 가짜 svc를 원래대로(칩 나타남·멈춤·실패 흉내)
cat > $X/bin/svc <<E2
#!/bin/sh
echo "svc \$*" >> $X/calls
[ "\$*" = "wifi enable" ] && [ -f $X/chip_ok ] && mkdir -p $X/sdio/mmc1:0001:1
[ "\$*" = "wifi enable" ] && [ -f $X/svc_hang ] && exec /bin/sleep 30
[ "\$*" = "wifi enable" ] && [ -f $X/svc_fail ] && exit 3
exit 0
E2
chmod +x $X/bin/svc
awreset; echo 1 > $X/bk/wifi_on; aw > $X/out
check "  설치 전에 Wi-Fi가 켜져 있었으면 끄지 않음" '! grep -q "svc wifi disable" $X/calls'
awreset; echo null > $X/bk/wifi_on; aw > $X/out
check "  설치 전 값이 null(한 번도 안 켬)이면 꺼져 있던 것으로 보고 끔" 'grep -qx "svc wifi disable" $X/calls'
awreset; rm -f $X/bk/wifi_on; aw > $X/out
check "  설치 전 기록이 없으면 끄지 않음" '! grep -q "svc wifi disable" $X/calls'
awreset; touch $T/nowififeat $X/chip_ok; aw > $X/out; rm -f $T/nowififeat
check "Android Wi-Fi 기능이 목록에 없어도(니로처럼) Wi-Fi를 켜서 칩을 깨움" 'grep -qx "svc wifi enable" $X/calls && grep -q "engine install" $X/calls'
awreset; touch $X/svc_fail; aw > $X/out; rm -f $X/svc_fail
check "  svc wifi enable이 실패하면 종료 코드를 기록하고, 1.7.3: 다음 부팅에 다시(굳히지 않음)" 'grep -q "svc wifi enable 실패 (종료 코드 3)" $X/out && [ ! -f $X/bk/wifi.nochip ] && [ -f $X/bk/wifi.wake ] && ! grep -q "engine install" $X/calls'
awreset; touch $X/svc_hang; aw > $X/out; rm -f $X/svc_hang
check "  svc wifi enable이 끝나지 않으면 대기 시간 뒤 멈추고 끝냄(다음 부팅에 다시)" 'grep -q "끝나지 않아 멈춤" $X/out && [ ! -f $X/bk/wifi.nochip ] && [ -f $X/bk/wifi.wake ] && ! grep -q "engine install" $X/calls'
# 리뷰 H-1: 칩이 보이면 부품 없음·칩 실패·깨우기 기록을 지움(근거 기록 nochip-wifi.txt는 둠)
awreset; : > $X/bk/wifi.nopart; : > $X/bk/wifi.nochip; echo "2 b0" > $X/bk/wifi.wake; echo "판정 근거: x" > $X/bk/nochip-wifi.txt; mkdir -p $X/sdio/mmc1:0001:1; aw > $X/out
check "1.7.3 리뷰 H-1: 칩이 보이면 wifi.nopart·wifi.nochip을 지우고 모드 설치, 근거 기록은 남김, 재리뷰 중간 2: 깨우기 횟수(wifi.wake)는 남김" '[ ! -f $X/bk/wifi.nopart ] && [ ! -f $X/bk/wifi.nochip ] && [ "$(cat $X/bk/wifi.wake)" = "2 b0" ] && [ -s $X/bk/nochip-wifi.txt ] && grep -q "engine install" $X/calls && ! grep -q "svc wifi" $X/calls'
# 리뷰 M-1: 깨우기 전에 끝나는 조건을 본다
echo b5 > $X/bootid; awreset; echo "3 b4" > $X/bk/wifi.wake; aw > $X/out
check "1.7.3 리뷰 M-1: 횟수를 다 쓴 기록(3, 지난 부팅)이면 깨우지 않고 칩 실패로 끝냄(지난 깨우기 중 서비스가 멈춘 경우), 재리뷰 L-1: 꺼져 있던 Wi-Fi는 다시 끔" '! grep -q "svc wifi enable" $X/calls && grep -qx "svc wifi disable" $X/calls && [ -f $X/bk/wifi.nochip ]'
awreset; echo "x b4" > $X/bk/wifi.wake; aw > $X/out
check "  기록이 깨졌으면 깨우지 않음(안전 쪽), 재리뷰 L-1: 칩 실패로 굳히지도 않음" '! grep -q "svc wifi" $X/calls && [ ! -f $X/bk/wifi.nochip ] && grep -q "횟수 기록을 읽지 못해" $X/out'
awreset; mv $X/bootid $X/bootid.keep; aw > $X/out; mv $X/bootid.keep $X/bootid
check "  부팅 id를 못 읽으면 이번에는 깨우지 않음(부팅을 셀 수 없음), 칩 없음으로 굳히지도 않음" '! grep -q "svc wifi" $X/calls && [ ! -f $X/bk/wifi.nochip ] && grep -q "부팅 id를 읽지 못해" $X/out'
awreset; mkdir -p $X/bk/wifi.wake; aw > $X/out; rmdir $X/bk/wifi.wake
check "  깨우기 횟수를 기록하지 못하면 깨우지 않음" '! grep -q "svc wifi" $X/calls && grep -q "횟수를 기록하지 못해" $X/out'
# 재리뷰 중간 2: 칩이 보였다 안 보였다 하는 차(#52·#55 계열)에서도 깨우기는 모두 합쳐 3번까지(칩이 보이는 부팅에 횟수를 지우지 않음)
ww() { (PATH=$X/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BOOT_ID=$X/bootid NOTICE=$X/notices BB=$T/bin/bb W=$X/w BK=$X/bk HMGDATA=$X/hd SDIO=$X/sdio WAKE_MAX=3 sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$X'/bin:'$T'/bin:/usr/bin:/bin:/sbin; wake_wifi; echo "rc=$?"'); }
awreset; rm -f $X/calls
for b in 1 2 3 4 5 6 7 8; do
  echo "alt$b" > $X/bootid
  if [ $((b % 2)) = 1 ]; then mkdir -p $X/sdio/mmc1:0001:1; else rm -rf $X/sdio/mmc1:0001:1; fi
  ww >> $X/alt.out
done
check "1.7.3 재리뷰 중간 2: 칩이 보이는 부팅과 안 보이는 부팅이 8번 번갈아도 Wi-Fi 깨우기는 모두 3번, 그 뒤 칩 실패" '[ "$(grep -c "^svc wifi enable" $X/calls)" = 3 ] && [ -f $X/bk/wifi.nochip ] && [ "$(cut -d" " -f1 $X/bk/wifi.wake)" = 3 ]'
rm -f $X/alt.out; rm -rf $X/sdio/mmc1:0001:1
# 재리뷰 중간 4: 칩을 본 적 있는 차(wifi.woke)는 module_version 3이어도 부품 없음으로 굳히지 않음
printf '#!/bin/sh\necho "11-10 09:00:00.000 D/WifiHW   (  500): wifi_get_module_version: 3"\n' > $X/bin/logcat; chmod +x $X/bin/logcat
awreset; : > $X/bk/wifi.woke; ww > $X/out
check "1.7.3 재리뷰 중간 4: 칩을 본 적 있는 차(wifi.woke)는 module_version=3이어도 wifi.nopart를 쓰지 않음(깨우지도 않음)" '[ ! -f $X/bk/wifi.nopart ] && grep -qx "rc=2" $X/out && ! grep -q "svc wifi enable" $X/calls 2>/dev/null'
rm -f $X/bin/logcat
# 재리뷰 L-2: 1.7.0 근거 없던 칩 없음 차(다시 확인)도 새 근거 module_version이 3이 아니면 횟수를 남기고 다음 부팅에 다시
printf '#!/bin/sh\necho "11-10 09:00:00.000 D/WifiHW   (  500): wifi_get_module_version: 1"\n' > $X/bin/logcat; chmod +x $X/bin/logcat
echo r1 > $X/bootid; awreset; : > $X/bk/wifi.nochip; ww > $X/out
check "1.7.3 재리뷰 L-2: 근거 없던 칩 없음 기록 + 다시 확인에서 module_version=1 → 칩 없음 기록을 지우고 다음 부팅에 다시(rc 3, 1/3)" 'grep -qx "rc=3" $X/out && [ ! -f $X/bk/wifi.nochip ] && [ "$(cat $X/bk/wifi.wake)" = "1 r1" ] && [ -f $X/bk/nochip.rechk ]'
rm -f $X/bin/logcat; echo b5 > $X/bootid
check "  재리뷰 L-8: 설치 전 꺼져 있던 Wi-Fi 끄기(svc wifi disable)는 뒤에서 돌리고 회차 상한으로 기다림(소스)" 'awk "/^wifi_restore_off\(\) \{/,/^}/" $PKG/svc/hotspot.sh | grep -q "( svc wifi disable >/dev/null 2>&1; echo \$? > \$W/svcoff.rc ) &" && ! grep -q "wifi_was_off && svc wifi disable" $PKG/svc/hotspot.sh'
# D-9(소유자 결정 2026-11-10): 1.7.2까지 굳은 wifi.nochip은 근거(module_version)가 3이 아닐 때만 2번 더
awreset; : > $X/bk/wifi.nochip; : > $X/bk/wifi.woke; echo "판정 근거: 순정 module_version=1 (3이면 …)" > $X/bk/nochip-wifi.txt; aw > $X/out
check "1.7.3 D-9: 1.7.2의 wifi.nochip + 근거 module_version=1 + wifi.wake 없음 → 다시 깨움(2/3), 아직 굳히지 않음" 'grep -qx "svc wifi enable" $X/calls && [ "$(cat $X/bk/wifi.wake)" = "2 b5" ] && [ ! -f $X/bk/wifi.nochip ] && [ ! -f $X/bk/wifi.woke ]'
echo b6 > $X/bootid; rm -f $X/calls; aw > $X/out
check "  다음 부팅(3/3)에도 안 보이면 칩 실패로 끝남" 'grep -qx "svc wifi enable" $X/calls && [ -f $X/bk/wifi.nochip ]'
awreset; : > $X/bk/wifi.nochip; : > $X/bk/wifi.woke; echo "판정 근거: 순정 module_version=3 (3이면 …)" > $X/bk/nochip-wifi.txt; aw > $X/out
check "  합치기(이슈 조사 ①): 근거 module_version=3이면 깨우지 않고 칩 없음 기록을 부품 없음(wifi.nopart)으로 옮김(W-1 문구)" '! grep -q "svc wifi" $X/calls && [ ! -f $X/bk/wifi.nochip ] && [ -f $X/bk/wifi.nopart ] && grep -q "이 차의 내비에는 Wi-Fi 부품이 없어 무선 카플레이를 쓸 수 없습니다" $X/notices && ! grep -q "칩이 켜지지 않아" $X/notices'
awreset; : > $X/bk/wifi.nochip; echo "판정 근거: 순정 module_version=3 (3이면 …)" > $X/bk/nochip-wifi.txt; aw > $X/out
check "  wifi.woke가 없는 옛 기록이어도 깨우지 않고 부품 없음으로" '! grep -q "svc wifi" $X/calls && [ -f $X/bk/wifi.nopart ] && [ ! -f $X/bk/wifi.nochip ]'
awreset; : > $X/bk/wifi.nochip; : > $X/bk/wifi.woke; echo "판정 근거: 순정 module_version=없음 (3이면 …)" > $X/bk/nochip-wifi.txt; aw > $X/out
check "  근거에 숫자가 없으면 그대로(깨우지 않음)" '! grep -q "svc wifi" $X/calls && [ -f $X/bk/wifi.nochip ]'
echo b1 > $X/bootid
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
rm -f $X/bin/svc
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
check "서비스: 시험 지원 차 대기 반복은 try_ready로 끝남 (1분마다, 1.7.3: 30초 대기 두 번 사이마다 제보 요청 점검)" 'grep -q "while ! try_ready \"\$prod\"; do sleep 30 & wait \$!; req_tick; sleep 30 & wait \$!; req_tick; done" $T/app/svc/hotspot.sh'

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
wfreset() { rm -rf $WF/calls $WF/notices $WF/bk $WF/w $WF/wlan0 $WF/out $WF/ps $WF/wifi $WF/prog; mkdir -p $WF/bk $WF/w $WF/wifi $WF/wlan0; }
wfsys() { echo "ctrl_interface=wlan0" > $WC; echo 1000:1010 > $WC.owner; echo crc > $WR; echo 1000:1010 > $WR.owner; }
wf() { (PATH=$WF/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 NOTICE=$WF/notices BB=$T/bin/bb W=$WF/w BK=$WF/bk WLAN=$WF/wlan0 WCONF=$WC WIFI_WAIT=0 PROG=$WF/prog BOOT_ID=$WF/bootid sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$WF'/bin:'$T'/bin:/usr/bin:/bin:/sbin; sleep() { :; }; wait() { exit 7; }; '"$1") > $WF/out 2>&1; echo $? >> $WF/out; }
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
check "ap_tick: 잠금을 지키고, wpa_supplicant가 다시 뜨면 멈춤. SUPP_MAX번 넘게 이어지면 한 번만 알리고 계속(그만두지 않음)" '[ "$(cat $WC.owner)" = 0:0 ] && [ "$(grep -c "^killall wpa_supplicant" $WF/calls)" = 4 ] && grep -qx "ns=4" $WF/out && [ "$(grep -c "자꾸 끊깁니다" $WF/notices)" = 1 ] && [ -f $WF/bk/wifilock.told ] && [ "$(tail -1 $WF/out)" = 0 ]'
: > $WF/ps; wf 'ns=3; ap_tick; echo ns=$ns'
check "  wpa_supplicant가 없으면 0부터 다시 셈" 'grep -qx "ns=0" $WF/out'
# 4b K-4: 되풀이되는 줄은 이번 실행에서 3번까지 + "더 남기지 않음" 한 줄. 멈추기·다시 켜기 동작은 그대로
wfreset; wfsys; echo "  9 1010 wpa_supplicant -iwlan0" > $WF/ps; wf 'ns=0; ap_tick; ap_tick; ap_tick; ap_tick; ap_tick; ap_tick; echo ns=$ns'
check "  4b K-4: wpa_supplicant 6번 다시 뜸 → '다시 켜져서 멈춤' 3줄 + '더 남기지 않음' 1줄, 멈추기(killall)는 6번 그대로" '[ "$(grep -c "wpa_supplicant가 다시 켜져서 멈춤" $WF/out)" = 3 ] && [ "$(grep -c "wpa_supplicant가 자꾸 다시 켜짐: 이번 실행에서는 이 기록을 더 남기지 않음" $WF/out)" = 1 ] && [ "$(grep -c "^killall wpa_supplicant" $WF/calls)" = 6 ] && grep -qx "ns=6" $WF/out'
for _p in hostapd dnsmasq; do printf '#!/bin/sh\necho "%s $*" >> %s/calls\n' $_p $WF > $WF/bin/$_p; chmod +x $WF/bin/$_p; done
wfreset; wfsys; : > $WF/ps; wf "CONF=$WF/hk.conf; echo channel=149 > \$CONF; up; up; up; up; up; echo done"
# up은 hostapd를 뒤에서(&) 띄운다: 가짜 hostapd 5개가 기록을 남길 때까지 잠깐 기다린다(최대 약 3초)
_k=0; while [ "$(grep -c "^hostapd " $WF/calls 2>/dev/null)" != 5 ] && [ $_k -lt 30 ]; do /bin/sleep 0.1; _k=$((_k+1)); done
rm -f $WF/bin/hostapd $WF/bin/dnsmasq
check "  4b K-4: hostapd가 5번 바로 꺼짐 → '시작'·'4초 안에 꺼짐' 각 3줄 + '더 남기지 않음' 각 1줄" '[ "$(grep -c "hostapd 시작$" $WF/out)" = 3 ] && [ "$(grep -c "hostapd가 4초 안에 꺼짐(5GHz 149번" $WF/out)" = 3 ] && [ "$(grep -c "hostapd를 자꾸 다시 켬: 이번 실행에서는 이 기록을 더 남기지 않음" $WF/out)" = 1 ] && [ "$(grep -c "hostapd가 자꾸 4초 안에 꺼짐: 이번 실행에서는 이 기록을 더 남기지 않음" $WF/out)" = 1 ] && grep -qx done $WF/out'
check "  4b K-4: 기록을 줄여도 다시 시도는 그대로(up 5번 모두 hostapd를 띄움)" '[ "$(grep -c "^hostapd " $WF/calls)" = 5 ]'
check "  4b K-4: 제한은 log_cap 한 곳(3곳에서 씀)" '[ "$(grep -c "log_cap [A-Z_]* " $PKG/svc/hotspot.sh)" = 3 ] && grep -q "^log_cap() {" $PKG/svc/hotspot.sh'
# 4b 리뷰 M-1: 제한은 **이어진 실패**에만. 정상 다시 시작은 늘 남기고, 성공하면(hostapd가 살아 있음·wpa_supplicant 없음) 다시 센다
printf '#!/bin/sh\necho "hostapd $*" >> %s/calls\n[ -f %s/hok ] && echo "  1 root 0 S hostapd $*" > %s/ps\nexit 0\n' $WF $WF $WF > $WF/bin/hostapd
printf '#!/bin/sh\necho "dnsmasq $*" >> %s/calls\n' $WF > $WF/bin/dnsmasq; chmod +x $WF/bin/hostapd $WF/bin/dnsmasq
# 가짜 hostapd는 뒤에서(&) 돌며 ps를 쓴다: up 안의 4초 대기는 켜질 차례(hok)면 ps가 써질 때까지(최대 약 4초), 아니면 바로 넘어감
wfreset; wfsys; : > $WF/hok; wf "CONF=$WF/hk.conf; echo channel=149 > \$CONF; sleep() { if [ -f $WF/hok ]; then _w=0; while [ ! -s $WF/ps ] && [ \$_w -lt 40 ]; do /bin/sleep 0.1; _w=\$((_w+1)); done; fi; }; for k in 1 2 3 4 5; do : > $WF/ps; up; done; echo done"
check "  4b 리뷰 M-1: 정상 다시 시작 5번 → 'hostapd 시작' 5줄 모두 남음, hostapd '자꾸'·'꺼짐' 줄 없음(dnsmasq 가짜는 늘 꺼져 있어 그쪽 제한 줄은 따로)" '[ "$(grep -c "hostapd 시작$" $WF/out)" = 5 ] && ! grep -q "hostapd를 자꾸\|hostapd가 자꾸\|4초 안에 꺼짐" $WF/out && grep -qx done $WF/out'
wfreset; wfsys; rm -f $WF/hok; wf "CONF=$WF/hk.conf; echo channel=149 > \$CONF; sleep() { if [ -f $WF/hok ]; then _w=0; while [ ! -s $WF/ps ] && [ \$_w -lt 40 ]; do /bin/sleep 0.1; _w=\$((_w+1)); done; fi; }; for k in 1 2 3 4; do : > $WF/ps; up; done; : > $WF/hok; : > $WF/ps; up; rm -f $WF/hok; for k in 1 2; do : > $WF/ps; up; done; echo done"
check "  4b 리뷰 M-1: 실패 4번(3줄 + '더 남기지 않음') 뒤 한 번 성공하면 다시 셈(성공 줄 + 다음 실패 2번도 남음)" '[ "$(grep -c "hostapd 시작$" $WF/out)" = 6 ] && [ "$(grep -c "hostapd가 4초 안에 꺼짐(5GHz 149번" $WF/out)" = 5 ] && [ "$(grep -c "hostapd를 자꾸 다시 켬: 이번 실행에서는 이 기록을 더 남기지 않음" $WF/out)" = 1 ] && [ "$(grep -c "hostapd가 자꾸 4초 안에 꺼짐: 이번 실행에서는 이 기록을 더 남기지 않음" $WF/out)" = 1 ] && grep -qx done $WF/out'
rm -f $WF/bin/hostapd $WF/bin/dnsmasq $WF/hok
wfreset; wfsys; echo "  9 1010 wpa_supplicant -iwlan0" > $WF/ps; wf "ns=0; for k in 1 2 3 4; do ap_tick; done; : > $WF/ps; ap_tick; echo '  9 1010 wpa_supplicant -iwlan0' > $WF/ps; ap_tick; ap_tick; echo ns=\$ns"
check "  4b 리뷰 M-1: wpa_supplicant 4번(3줄 + 1줄) 뒤 없어지면 다시 셈(다음 2번도 남음), 멈추기는 6번 그대로" '[ "$(grep -c "wpa_supplicant가 다시 켜져서 멈춤" $WF/out)" = 5 ] && [ "$(grep -c "이 기록을 더 남기지 않음" $WF/out)" = 1 ] && [ "$(grep -c "^killall wpa_supplicant" $WF/calls)" = 6 ] && grep -qx "ns=2" $WF/out'
check "  4b 리뷰 M-1: 리포트 연결 기록 칸이 '더 남기지 않음' 줄도 보여 줌(그 뒤 흔적이 없어 보이지 않게)" 'grep -q "hostapd 시작|이 기록을 더 남기지 않음|" $PKG/bin/status.sh'
check "  4b 리뷰 L-5: 4초 안에 꺼짐 줄을 남기지 않을 때(4번째부터)는 채널을 읽는 awk를 띄우지 않음(소스)" 'grep -q "_hch=; \[ \${HA_DIES:-0} -lt 3 \] && _hch=" $PKG/svc/hotspot.sh'
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
pureset() { rm -rf $PU/bk $X/calls $T/notice $X/hd; mkdir -p $PU/bk $X/hd/mods/wireless-carplay-aa; echo '{"system": [{"region": "KOR"}]}' > $X/hd/mods/wireless-carplay-aa/mod.json; }
pu() { (HMGDATA=$X/hd W=$PU/w sh $PU/preun.sh) > $PU/out 2>&1; }
pureset; : > $PU/bk/mod.ours; printf '%s\n' "restore  /system/onebin/depehev_kr/featurexml.cfg (stock)" "setting  prop/persist.sys.iap2.wifi back to stock" > $X/plan; pu
check "삭제: 우리가 설치한 모드는 remove → 계획이 되돌리기뿐 → 적용, 삭제 출력에 알림(1.7.1: 알림 없음, 알림 기록도 지움)" 'grep -qx "hmgapid engine remove wireless-carplay-aa" $X/calls && grep -qx "hmgapid engine apply" $X/calls && grep -q "무선 모드도 지웠습니다" $PU/out && [ ! -f $T/notice ]'
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
rm -f $T/notice

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
rm -f $T/notice

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
  -e "s#/proc/mounts#$T/mounts#" -e "s#/data/nemesis/logs/korea.projection/ap.log#$T/logs/ap.log#" > $T/stl.sh
# 1.7.3(R-1): Launch(stl.sh)는 제보 파일을 만들지 않는다. 아래에서 리포트 내용을 보는 검사들은 st.sh로 돈다:
# Launch 뒤 상태 화면의 [제보 파일 만들기]를 누른 것과 같다(앱이 쓰는 요청 파일 → 서비스 점검이 띄우는 status.sh --report).
# 부팅 id는 맥에 /proc이 없어 가짜 파일로 준다(요청 파일의 boot_id와 같아야 받는다). Launch만 보는 검사는 stl.sh를 쓴다.
echo boot-T > $T/bootid
cat > $T/st.sh <<STW
#!/bin/sh
export BOOT_ID=\${BOOT_ID:-$T/bootid} REQ=\${REQ:-$T/report.req}
sh $T/stl.sh "\$@"; _rc=\$?
[ \$# -eq 0 ] || exit \$_rc
# 요청 id는 늘 다르게(같은 id는 이미 받은 요청으로 보고 다시 만들지 않는다: 같은 초에 두 번 돌아도 흔들리지 않게, 리뷰)
_n=\$((\$(cat $T/reqn 2>/dev/null || echo 0) + 1)); echo \$_n > $T/reqn
echo "\$_n \$(cat \$BOOT_ID) 0" > \$REQ
sh $T/stl.sh --report >/dev/null 2>&1
exit \$_rc
STW
STF=$T/status.txt
echo "  101 root  hostapd /data/misc/wifi/hostapd-kp.conf" > $T/ps
: > $T/mounts; printf 'pct=100\nstate=done\nstage=old\n' > $RPROG
STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/stl.sh >/dev/null
check "USB가 마운트 안 됐으면 USB에 쓰지 않고 알림도 없음 (상태는 화면이 보여 줌)" '[ ! -d $T/usb0/KoreaProjection-report ] && [ ! -f $T/notice ]'
check "  1.7.0: USB가 없으면 지난 저장 기록(RPROG)을 지움(화면에 지난 '완료'가 다시 안 보이게, 리뷰 L1)" '[ ! -f $RPROG ]'
rm -f $T/w/korea-projection-report.md
STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null
check "1.7.3 R-7: USB 없이 요청 → 실패 문구('USB를 꽂은 뒤 … 다시 눌러 주세요'), USB·리포트 파일을 만들지 않음, 요청 파일 지움" 'grep -qx "state=fail" $RPROG && grep -q "USB가 없습니다. USB를 꽂은 뒤 \[제보 파일 만들기\]를 다시 눌러 주세요." $RPROG && [ ! -d $T/usb0/KoreaProjection-report ] && [ ! -f $T/w/korea-projection-report.md ] && [ ! -f $T/report.req ]'
check "  1.7.0: 로그 모으기는 한 번에 하나(--wait도 collect.pid), carreport 잠금이 남으면 풀릴 때까지 기다린 뒤 완료(리뷰 M1)" 'awk "/^make_report\(\) \{/,/^}/" $PKG/bin/status.sh | sed -n 2p | grep -q "^  if collect_alive; then" && grep -q "while \[ -d \$W/carreport.lock \] && \[ \$_lw -lt 210 \]" $PKG/bin/status.sh'
echo "/dev/block/sda1 $T/usb0 vfat rw 0 0" > $T/mounts
mkdir -p $T/hl
printf '%s\n' "01-01 18:30:04.730 I/HMG-API (  148): hook map: none for Kia Niro, hooks off (no map)" "01-01 18:30:04.731 I/HMG-API (  148): mods: wireless-carplay-aa not loaded: hook point btsettings.projection_helper.open_wireless_page isn't mapped on this car (0 methods match): its hooks are off here, its other parts still apply" > $T/hl/log.log.1
printf '%s\n' "01-01 18:30:04.740 I/HMG-API (  148): hook map: mapped for Kia Niro Hybrid (kor 260902), hooks on, 1 point(s) not mapped (their features and mods are off)" "01-01 18:30:04.800 I/HMG-API (  144): mods: loaded wireless-carplay-aa 2.3.1" "11-06 09:05 I/HMG-API ( 1): other" > $T/hl/log.log
HMGLOG=$T/hl STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null
R=$T/usb0/KoreaProjection-report/1-report.md
G3=$T/usb0/KoreaProjection-report/3-log.txt
check "상태 화면용 파일: 644, 키 43개(1.6.1 mod_foreign, 1.6.2 stock_ssid·ap_mode·stock_seen, 1.7.0 state·aa·nowlan, 1.7.1 modver·mod_pending, 1.7.2 mod_hooks, 1.7.3 verdict·verdict_lv·verdict_msg·verdict_end·first·s1·s2·s3 추가)" '[ "$(stat -f %Lp $STF)" = 644 ] && [ "$(grep -c "=" $STF)" = 43 ] && grep -q "^modver=" $STF && grep -qx "mod_pending=no" $STF && grep -qx "nowlan=no" $STF && grep -qx "mod_foreign=no" $STF && grep -q "^state=" $STF && grep -qx "aa=yes" $STF'
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
export AAOFF=$T/aaoff; rm -f $AAOFF; : > $T/usb0/kp-aa-off; rm -f $T/notice
HMGLOG=$T/hl STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null 2>&1
check "  USB kp-aa-off → 끄기 표시, aa=no, 리포트에 꺼짐, 알림 없음" '[ -f $AAOFF ] && grep -qx "aa=no" $STF && grep -q "무선 안드로이드 오토: 꺼짐" $R && ! grep -q "안드로이드 오토" $T/notice 2>/dev/null'
: > $T/usb0/kp-aa-on
HMGLOG=$T/hl STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null 2>&1
check "  kp-aa-off·kp-aa-on이 함께 있으면 끄기가 먼저(꺼진 채)" '[ -f $AAOFF ] && grep -qx "aa=no" $STF'
rm -f $T/usb0/kp-aa-off; HMGLOG=$T/hl STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null 2>&1
check "  kp-aa-on만 있으면 다시 켬(끄기 표시 지움), 리포트에 켜짐(기본)" '[ ! -f $AAOFF ] && grep -qx "aa=yes" $STF && grep -q "무선 안드로이드 오토: 켜짐(기본)" $R'
# K-2: 예전 검사("껐습니다" 문구, 코드에 없어 늘 통과)를 실제 알림 파일 검사로 바꿈. 끈 뒤 한 번 더 Launch해도 알림이 없다
: > $T/usb0/kp-aa-off; HMGLOG=$T/hl STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null 2>&1
rm -f $T/notice; HMGLOG=$T/hl STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null 2>&1
check "  이미 꺼져 있을 때 다시 Launch해도 AA 끄기·켜기 알림을 쓰지 않음(알림 기록 파일, 리뷰 L6)" '[ -f $AAOFF ] && grep -qx "aa=no" $STF && ! grep -q -E "안드로이드 오토|Android Auto" $T/notice 2>/dev/null'
rm -f $T/usb0/kp-aa-on $T/usb0/kp-aa-off $T/notice $AAOFF; unset AAOFF
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
# 1.6.2: 순정 카플레이 AP(K3 #15). 순정 dnsmasq를 우리 DHCP로 세지 않고, 리포트·요약 문구는 "준비됨(내비 Wi-Fi)"
cp $T/ps $T/ps.st; stockps > $T/ps; rm -f $T/notice; : > $SK/bk/stockap.seen
HMGLOG=$T/hl STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w PROC=$SK/proc BK=$SK/bk sh $T/st.sh > $T/st-stock.out
check "1.6.2 상태: 순정 카플레이 AP → our_ap=no, our_dhcp=no(순정 dnsmasq 오판 없음), other_ap=yes, stock_ssid=carplay, ap_mode=stock" 'grep -qx "our_ap=no" $STF && grep -qx "our_dhcp=no" $STF && grep -qx "other_ap=yes" $STF && grep -qx "stock_ssid=carplay" $STF && grep -qx "ap_mode=stock" $STF && grep -qx "stock_seen=yes" $STF'
check "  리포트에 ap_mode 한 줄(값 없이 판정만), 순정 AP 기록, 우리 DHCP 아니요" 'grep -q "^- 무선 카플레이 AP: ap_mode=stock (순정 hostapd 판정: carplay, 순정 카플레이 AP 기록: 예)" $R && grep -q "우리 DHCP: 아니요" $R && ! grep -q -F -e "SSID\\cX" -e "word77x" $R $STF'
check "  요약 문구는 '무선 카플레이 준비됨(내비 Wi-Fi 사용)', 알림은 없음(1.7.0)" 'grep -q "무선 카플레이 준비됨(내비 Wi-Fi 사용)" $T/st-stock.out && [ ! -f $T/notice ]'
sconf HotspotName1; HMGLOG=$T/hl STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w PROC=$SK/proc sh $T/st.sh >/dev/null; sconf 'SSID\cX'
check "  순정 일반 핫스팟이면 ap_mode=none, stock_ssid=hotspot" 'grep -qx "ap_mode=none" $STF && grep -qx "stock_ssid=hotspot" $STF'
mv $T/ps.st $T/ps; rm -f $T/notice
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
check "1.7.2 P-8: 리포트 연결 진단 칸: wifi_ap_on, Last mode·[Feature] 문구, 우리 서비스 시작(부팅 뒤 초)" 'grep -q "^## 연결 진단" $R && grep -q "순정 AP 저장값(wifi_ap_on): 1" $R && grep -q "Last mode): Wi-Fi AP Enabled (for Wireless Connectivity)$" $R && grep -q "\[Feature\]): Hardware(supported)Client(not supported), Hotspot(not supported), Wireless(supported)$" $R && grep -q "우리 서비스 시작: 부팅 뒤 23초(이번 부팅 처음 시작, 재부팅 없이 설치·업데이트했으면 그 뒤 첫 시작)" $R'
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
check "쏘나타 하이브리드: 상태 화면 tested=yes, 1.7.3(D-6): README ✅ 차종이라 리포트 '확인된 차: 예'" 'grep -qx "tested=yes" $STF && grep -q "확인된 차: 예" $R'
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
rm -f $T/notice; HMGLOG=$T/hl0 STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh > $T/st-ready.out; rm -rf $T/hl0
check "요약 문구 한국어(준비된 차: 핫스팟 상태), 1.7.3(R-1): '제보 자료를 저장하는 중' 문구 없음, 알림은 없음(1.7.0 소유자 결정)" 'grep -q "핫스팟 켜짐" $T/st-ready.out && ! grep -q "저장하는 중" $T/st-ready.out && [ ! -f $T/notice ]'
check "  저장이 끝나면 진행 기록 100%, 'USB를 빼셔도 됩니다'(Car Report 결과와 상관없이), 644" 'grep -qx "pct=100" $RPROG && grep -q -E "^state=(done|fail)$" $RPROG && grep -q "USB를 빼셔도 됩니다" $RPROG && [ "$(stat -f %Lp $RPROG)" = 644 ]'
# 1.7.3(R-1·R-4·R-7): Launch는 감시자(status.sh --watch)만 뒤에 띄우고 제보 파일을 만들지 않는다(예전 1.7.0 "로그 모으기를
# 뒤에서" 검사를 이 흐름으로 바꿨다). 버튼 요청(요청 파일)이 오면 감시자가 1·2·3번을 만든다. 감시자는 가짜 부팅 뒤 초(UPTIME)로 끝난다.
i=0; while [ -d $T/w/carreport.lock ] && [ $i -lt 50 ]; do /bin/sleep 0.2; i=$((i+1)); done
rm -rf $T/usb0/KoreaProjection-report $T/usb0/KoreaProjection-private $T/w/watch.lock
rm -f $RPROG $T/report.req $T/w/req.last $T/w/req.join $T/w/watch.pid $T/w/watch.until $T/w/collect.pid
# 뒤에서 도는 것도 시험용 status.sh(stl.sh, 가짜 USB·mounts 경로)를 부르게 APP를 따로 둔다
rm -rf $T/app2; mkdir -p $T/app2/bin; for f in $T/app/*; do [ "${f##*/}" = bin ] || ln -s $f $T/app2/; done
cp $T/stl.sh $T/app2/bin/status.sh; cp $T/app/bin/carreport.sh $T/app2/bin/carreport.sh
# 가짜 busybox: setsid는 건너뛰고(뒤에서 띄우기만), 스크립트가 PATH를 바꿔도 맥 명령을 찾게 한다
printf '#!/bin/sh\n[ "$1" = setsid ] && shift\nPATH=%s/bin:/usr/bin:/bin:$PATH exec "$@"\n' $T > $T/bbs17; chmod +x $T/bbs17
# 가짜 /proc(맥에는 없다): 살아 있는 감시자·제보 만들기를 status.sh로 보이게 할 때 pid 폴더와 cmdline을 만든다
mkdir -p $T/fproc
# 베타 1 리뷰 1: 재부팅 받기는 /proc의 명령줄을 하나도 못 읽으면 막는다. 진짜 차처럼 평범한 프로세스 하나를 둔다
# 재리뷰 L2 시험용 가짜 sync(KP_SYNC): $T/sync_mkbusy가 있으면 sync 동안 엔진 apply 프로세스가 생긴 것처럼 만든다
printf '#!/bin/sh\n[ -f %s/sync_mkbusy ] && { mkdir -p %s/fproc/99992; printf "app_process\\0/system/bin\\0hmgapi.engine.Engine\\0apply\\0" > %s/fproc/99992/cmdline; }\nexit 0\n' $T $T $T > $T/fakesync; chmod +x $T/fakesync
mkdir -p $T/fproc/1; printf '/init\0' > $T/fproc/1/cmdline
# 가짜 부팅 뒤 초. 진짜 /proc/uptime은 읽는 중에 비지 않으므로 임시 파일 → 이름 바꾸기로 쓴다(">"로 쓰면 감시자가 빈 값을 읽고 끝남)
upset() { echo "$1.00 50.00" > $T/uptime.tmp && mv -f $T/uptime.tmp $T/uptime; }
upset 100
# 1.7.3(U-3): 재부팅 명령은 가짜(부르면 rbcalls에 한 줄). 감시자가 보는 설치 진행 기록은 $T/lwprog
printf '#!/bin/sh\necho reboot >> %s/rbcalls\nexit 1\n' $T > $T/fakereboot; chmod +x $T/fakereboot
printf 'pct=100\nstate=done\nstage=x\nt=1\nboot=boot-T\n' > $T/lwprog
# /system 마운트 상태(재부팅 거절 조건, 기본 ro)
echo "/dev/block/system /system ext4 ro,relatime 0 0" > $T/sysmounts
# KP_RB_WAIT: reboot 명령을 기다리는 회차 수. 시험의 가짜 sleep은 0.01초라 300회 ≈ 3초(가짜 reboot이 끝나기에 넉넉함)
LW() { (RPT_SYNC=${LWSYNC:-0}; export RPT_SYNC; KP_RB_WAIT=300 MOUNTS=$T/sysmounts KP_REBOOT=$T/fakereboot KP_SYNC=$T/fakesync HOOKSTARTS=$T/hstarts KP_DMESG=$T/kdmesg HMGINST=$T/lwinst KP_RBREQ=$T/reboot.req RBRES=$T/rbres WATCHF=$T/watchf PROG=${LWPROG:-$T/lwprog} BOOT_ID=$T/bootid REQ=$T/report.req UPTIME=$T/uptime PROC=$T/fproc WATCH_SECS=5 HMGLOG=$T/hl STATUS=$STF BB=$T/bbs17 APP=$T/app2 SRC=$T/softap.conf W=$T/w sh $T/stl.sh "$@"); }
# 진짜 /proc/<pid>/cmdline처럼 인자를 NUL로 나눠 쓴다(리뷰 M3: 차 busybox grep은 NUL 뒤를 못 볼 수 있어 코드는 tr로 읽는다)
fpalive() { mkdir -p $T/fproc/$1; printf 'sh\0/data/nemesis/apps/korea.projection/bin/%s\0%s\0' "${3:-status.sh}" "$2" > $T/fproc/$1/cmdline; }
crn() { grep -c "^hmgapid engine report --usb$" $T/calls 2>/dev/null; }
# 요청 파일 쓰기: 늘 다른 id(같은 초에 써도 이미 받은 요청으로 보지 않게, 리뷰). $1: boot_id(기본 boot-T), $2: 부팅 뒤 초(기본 지금 가짜 값)
# 앱처럼 임시 파일 → 이름 바꾸기로 쓴다(감시자가 반쯤 쓴 파일을 읽고 "깨진 요청"으로 지우지 않게)
RQN=1000; mkreq() { RQN=$((RQN+1)); echo "$RQN ${1:-boot-T} ${2:-$(cut -d. -f1 $T/uptime)}" > $T/report.req.tmp && mv -f $T/report.req.tmp $T/report.req; }
# 끝나지 않으면 테스트가 멈추지 않게: 뒤에서 띄운 감시자를 최대 $2초 기다리고, 그래도 살아 있으면 죽이고 1을 돌려준다
wdone() { _k=0; while kill -0 $1 2>/dev/null && [ $_k -lt $(($2*10)) ]; do /bin/sleep 0.1; _k=$((_k+1)); done; kill -0 $1 2>/dev/null && { kill $1; return 1; }; return 0; }
# RPROG가 그 요청 id의 끝(pct=100)이 될 때까지 기다린다(최대 20초)
# 베타 1 리뷰 뒤(동시 실행 흔들림 원인): Car Report가 pct=100을 쓴 뒤에도 감시자는 make_report를 마치고 "만드는 동안 쌓인 요청"을
# 지운다(rm -f $REQ). 그 틈에 다음 요청을 쓰면 지워져 다음 rpwait이 시간을 넘긴다. 그래서 제보 만들기(collect.pid)가 끝난 뒤
# 감시자가 그 줄을 지날 때까지 잠깐 더 기다린다
rpwait() { _k=0; while ! { grep -qx "pct=100" $RPROG && grep -qx "req=$1" $RPROG; } 2>/dev/null && [ $_k -lt 100 ]; do /bin/sleep 0.2; _k=$((_k+1)); done
  _k=0; while [ -f $T/w/collect.pid ] && [ $_k -lt 50 ]; do /bin/sleep 0.2; _k=$((_k+1)); done; /bin/sleep 0.5; }
LW > $T/st-async.out 2>/dev/null
i=0; while [ ! -s $T/w/watch.pid ] && [ $i -lt 50 ]; do /bin/sleep 0.1; i=$((i+1)); done
WP=$(cut -d' ' -f1 $T/w/watch.pid 2>/dev/null); /bin/sleep 1
check "1.7.3 R-7: USB가 꽂힌 채 Launch → 감시자만 뜨고(끝 = 부팅 뒤 100초+5초) USB에 아무 파일도 안 생김, 진행 기록 없음" '[ -n "$WP" ] && kill -0 $WP && [ "$(cat $T/w/watch.until)" = 105 ] && [ ! -e $T/usb0/KoreaProjection-report ] && [ ! -e $T/usb0/KoreaProjection-private ] && [ ! -f $RPROG ] && ! grep -q "저장" $T/st-async.out'
check "  감시자 기록은 '<pid> <boot_id>', 잠금 폴더(watch.lock)를 잡음" '[ "$(cat $T/w/watch.pid)" = "$WP boot-T" ] && [ -d $T/w/watch.lock ]'
fpalive $WP --watch
LW --watch & W2=$!
check "  한 번에 하나: 잠금이 있고 이번 부팅에 살아 있는 감시자가 있으면 두 번째 감시자는 바로 끝남(watch.pid·잠금 그대로)" 'wdone $W2 3 && [ "$(cat $T/w/watch.pid)" = "$WP boot-T" ] && [ -d $T/w/watch.lock ]'
upset 101; LW >/dev/null 2>&1
check "  Launch를 다시 누르면 감시자를 더 띄우지 않고 끝나는 시각만 다시 씀(부팅 뒤 101초 → 106)" '[ "$(cat $T/w/watch.until)" = 106 ] && [ "$(cat $T/w/watch.pid)" = "$WP boot-T" ]'
check "  끝나는 시각은 임시 파일 → 이름 바꾸기로 씀(감시자가 비운 순간을 읽고 끝나지 않게, 2026-11-10 흔들림 원인)" 'grep -q "> \$W/watch.until.tmp && \$BB mv -f \$W/watch.until.tmp \$W/watch.until" $PKG/bin/status.sh && [ ! -f $T/w/watch.until.tmp ] && kill -0 $WP'
c0=$(crn); mkreq; R1=$RQN; rpwait $R1
check "1.7.3 R-7: 요청 파일 → 감시자가 1·3번을 USB에 만들고 Car Report(2번) 만들기를 부름, 완료 문구, 요청 파일 지움" '[ -s $T/usb0/KoreaProjection-report/1-report.md ] && [ -s $T/usb0/KoreaProjection-report/3-log.txt ] && [ "$(crn)" = $((c0+1)) ] && grep -q "USB를 빼셔도 됩니다" $RPROG && [ ! -f $T/report.req ]'
check "  리뷰 중간 2: 진행 기록에 그 요청 id(req=)가 적힘(앱이 시각 대신 id로 짝지음), Car Report 결과 기록에도" 'grep -qx "req=$R1" $RPROG && grep -qx "pct=100" $RPROG && grep -q "^req2=" $RPROG'
check "  설치 중이 아니면 리포트 첫 줄은 제목(설치 중 표시 없음)" '[ "$(sed -n 1p $T/usb0/KoreaProjection-report/1-report.md)" = "# Korea Projection 리포트" ]'
mkreq; R2=$RQN; rpwait $R2
check "  D-1: 10분 안이면 같은 감시자가 다음 요청도 받음(두 번째 제보)" '[ "$(crn)" = $((c0+2)) ] && grep -qx "req=$R2" $RPROG && kill -0 $WP'
# 리뷰 M-4: 같은 감시자가 제보를 두 번 만들 때 판정 값(HMG-API 로그 등)을 다시 구한다(첫 값이 남지 않게)
mkdir -p $T/hl; cp $T/hl/log.log $T/hl.keep 2>/dev/null; printf '%s\n' "01-01 I/HMG-API ( 1): hook map: mapped for Kia Niro Hybrid (kor 260902), hooks on" > $T/hl/log.log
mkreq; R3=$RQN; rpwait $R3; h3=$(grep "HMG-API 훅(마지막 부팅 기록)" $T/usb0/KoreaProjection-report/1-report.md)
printf '%s\n' "01-01 I/HMG-API ( 1): hook map: none for Kia Niro, hooks off (no map)" > $T/hl/log.log
mkreq; R4=$RQN; rpwait $R4; h4=$(grep "HMG-API 훅(마지막 부팅 기록)" $T/usb0/KoreaProjection-report/1-report.md)
check "1.7.3 리뷰 M-4: 같은 감시자의 두 번째 제보는 그때의 HMG-API 로그로 다시 판정(첫 값이 남지 않음)" 'echo "$h3" | grep -q ": on mapped" && echo "$h4" | grep -q ": off none" && kill -0 $WP'
if [ -f $T/hl.keep ]; then mv $T/hl.keep $T/hl/log.log; else rm -f $T/hl/log.log; fi
# --- 1.7.3(U-3): [지금 재부팅] 요청은 감시자만 받는다. 막는 조건마다 가짜 reboot을 부르는지 본다 ---
RBN=5000; mkrb() { RBN=$((RBN+1)); echo "$RBN ${1:-boot-T} ${2:-$(cut -d. -f1 $T/uptime)}" > $T/reboot.req.tmp && mv -f $T/reboot.req.tmp $T/reboot.req; }
# 감시자가 요청을 다 처리할 때까지 기다린다. 감시자는 요청 파일을 먼저 지우고 그 뒤에 ap.log·sync·reboot을 하므로
# "파일이 사라짐"만으로는 이르다(부하에서 sync가 느려 검사가 앞섬, 2026-11-10). 결과(ap.log 줄 수)를 기다린다.
# rbw: 파일이 사라질 때까지(ap.log에 남기지 않는 경우: 이전 부팅·같은 id). rbl 패턴 이전수: ap.log에 그 줄이 하나 더 생길 때까지(최대 20초)
rbw() { _k=0; while [ -f $T/reboot.req ] && [ $_k -lt 200 ]; do /bin/sleep 0.1; _k=$((_k+1)); done; }
# ap.log가 아직 없으면 grep -c가 아무것도 내지 않으므로 0으로 둔다(빈 값이면 기다림이 바로 끝남)
alc() { _c=$(grep -c "$1" $AL 2>/dev/null); echo "${_c:-0}"; }
rbl() { _k=0; while [ "$(alc "$1")" -le "$2" ] && [ $_k -lt 200 ]; do /bin/sleep 0.1; _k=$((_k+1)); done; }
rbn() { _c=$(grep -c "^reboot$" $T/rbcalls 2>/dev/null); echo "${_c:-0}"; }
# 1.7.3(리뷰 M2): 감시자가 남긴 재부팅 결과(앱이 읽음). 방금 낸 요청(RBN)의 id와 code가 될 때까지 잠깐 기다린다(최대 약 3초)
rbr() { _k=0; until { grep -qx "id=$RBN" $T/rbres && grep -qx "code=$1" $T/rbres && grep -qx "boot=boot-T" $T/rbres; } 2>/dev/null || [ $_k -ge 30 ]; do /bin/sleep 0.1; _k=$((_k+1)); done; grep -qx "id=$RBN" $T/rbres && grep -qx "code=$1" $T/rbres && [ "$(stat -f %Lp $T/rbres)" = 644 ]; }
AL=$T/logs/ap.log
printf 'pct=100\nstate=reboot\nstage=x\nt=1\nboot=boot-T\n' > $T/lwprog.tmp; mv -f $T/lwprog.tmp $T/lwprog
c0=$(rbn); a0=$(alc "재부팅 명령이 끝났지만"); mkrb; rbl "재부팅 명령이 끝났지만" $a0
check "1.7.3 U-3: 이번 부팅 '재부팅 필요'(state=reboot) + 새 요청 → 감시자가 sync 뒤 reboot을 부름, ap.log에 한 줄, 요청 지움" '[ "$(rbn)" = $((c0+1)) ] && grep -q "상태 화면에서 재부팅 요청: 지금 재부팅함" $AL && [ ! -f $T/reboot.req ]'
check "  reboot 명령이 돌아오면(실패) 종료 코드와 함께 기록하고 감시자는 계속 돎" 'grep -q "재부팅 명령이 끝났지만 재부팅되지 않음(종료 코드 1)" $AL && ! grep -q "안에 끝나지 않음" $AL && kill -0 $WP'
# 리뷰 M2: 거절도 ap.log 이유 줄을 기다린 뒤 reboot 횟수를 센다("파일이 사라진 순간"만 보면 늘 통과할 수 있음)
RJ="재부팅 요청 거절: 이번 부팅의 새 요청이 아님"
c0=$(rbn); a0=$(alc "$RJ"); echo "$(cat $T/w/reboot.last) boot-T $(cut -d. -f1 $T/uptime)" > $T/reboot.req.tmp; mv -f $T/reboot.req.tmp $T/reboot.req; rbl "$RJ" $a0
check "  같은 요청 id는 다시 처리하지 않음(지우지 못해 남은 것): ap.log에 이유, reboot 안 부름" '[ "$(alc "$RJ")" = $((a0+1)) ] && [ "$(rbn)" = $c0 ]'
c0=$(rbn); a0=$(alc "$RJ"); mkrb boot-OLD; rbl "$RJ" $a0
check "  이전 부팅 요청 → 재부팅 안 함, ap.log에 이유, 요청 지움" '[ "$(alc "$RJ")" = $((a0+1)) ] && [ "$(rbn)" = $c0 ] && [ ! -f $T/reboot.req ]'
check "  1.7.3 리뷰 M2: 지난 부팅 요청 → 결과 파일에 code=bad(감시자는 있으니 다시 누르기 안내)" 'rbr bad'
a0=$(alc "$RJ"); echo "$RBN boot-OLD 1" > $T/reboot.req.tmp; mv -f $T/reboot.req.tmp $T/reboot.req; rbw; echo "$RBN boot-OLD 1" > $T/reboot.req.tmp; mv -f $T/reboot.req.tmp $T/reboot.req; rbw; /bin/sleep 0.5
check "  같은 내용의 거절은 한 번만 기록(지우지 못해 남아도 1초마다 줄이 쌓이지 않음)" '[ "$(alc "$RJ")" = $((a0+1)) ]'
c0=$(rbn); a0=$(alc "재부팅 요청 거절: 오래된 요청"); mkrb boot-T 30; rbl "재부팅 요청 거절: 오래된 요청" $a0
check "  40초보다 오래된 요청(부팅 뒤 30초에 쓰고 지금 101초) → 재부팅 안 함, ap.log에 이유" '[ "$(rbn)" = $c0 ] && grep -q "재부팅 요청 거절: 오래된 요청(71초)" $AL'
check "  1.7.3 리뷰 M2: 오래된 요청 → 앱이 읽는 결과 파일(644)에 이 요청 id와 code=old" 'rbr old'
# 재리뷰(낮음): 나이 경계 40초는 받고 41초는 거절, 음수(앞으로 온 요청)도 거절
c0=$(rbn); a0=$(alc "재부팅 요청 거절: 오래된 요청"); mkrb boot-T 60; rbl "재부팅 요청 거절: 오래된 요청" $a0
check "  재리뷰: 41초 → 거절(오래된 요청(41초))" '[ "$(rbn)" = $c0 ] && grep -q "재부팅 요청 거절: 오래된 요청(41초)" $AL'
c0=$(rbn); a0=$(alc "지금보다 뒤임"); mkrb boot-T 105; rbl "지금보다 뒤임" $a0
check "  재리뷰: 나이가 음수(부팅 뒤 105초에 쓴 요청, 지금 101초) → 거절, ap.log에 이유" '[ "$(rbn)" = $c0 ] && grep -q "재부팅 요청 거절: 요청 시각이 지금보다 뒤임(-4초)" $AL'
c0=$(rbn); a0=$(alc "재부팅 명령이 끝났지만"); mkrb boot-T 61; rbl "재부팅 명령이 끝났지만" $a0
check "  재리뷰: 40초 → 받음(reboot 부름)" '[ "$(rbn)" = $((c0+1)) ]'
# 1.7.3 베타 1(니로 차 확인): NEMESIS로 설치·업데이트하면 /system이 다음 재부팅까지 rw로 남는다. rw여도 재부팅을 받는다
echo "/dev/block/system /system ext4 rw,relatime 0 0" > $T/sysmounts.tmp; mv -f $T/sysmounts.tmp $T/sysmounts
c0=$(rbn); a0=$(alc "재부팅 명령이 끝났지만"); mkrb; rbl "재부팅 명령이 끝났지만" $a0
check "  베타 1: /system이 rw여도(업데이트 직후) 재부팅을 받음(reboot 부름), '쓰기 모드' 거절 줄 없음" '[ "$(rbn)" = $((c0+1)) ] && ! grep -q "쓰기 모드로 열려" $AL'
check "  베타 1: 받았는데 재부팅 명령이 돌아오면 결과 파일 code=cmd(앱은 RESET 안내)" 'rbr cmd'
check "  베타 1: 재부팅 받는 조건에 /system 쓰기 모드(system_ro)가 없음(소스)" '! awk "/^take_rbreq\(\) \{/,/^}/" $PKG/bin/status.sh | grep -q "system_ro\|rb_result rw\|rb_result state"'
echo "/dev/block/system /system ext4 ro,relatime 0 0" > $T/sysmounts.tmp; mv -f $T/sysmounts.tmp $T/sysmounts
# 재리뷰(낮음): reboot 명령이 돌아오지 않아도 감시자는 정한 시간(시험 1초)만 기다리고 기록한 뒤 계속 돈다
cp $T/fakereboot $T/fakereboot.keep; printf '#!/bin/sh
echo reboot >> %s/rbcalls
exec /bin/sleep 57%s
' $T $$ > $T/fakereboot.tmp; chmod +x $T/fakereboot.tmp; mv -f $T/fakereboot.tmp $T/fakereboot
c0=$(rbn); a0=$(alc "안에 끝나지 않음"); mkrb; rbl "안에 끝나지 않음" $a0
check "  재리뷰: reboot 명령이 돌아오지 않으면 KP_RB_WAIT 회차 뒤 기록('…안에 끝나지 않음')하고 감시자는 계속 돎(끝나는 조건)" '[ "$(rbn)" = $((c0+1)) ] && grep -q "재부팅 명령이 300초 안에 끝나지 않음(아직 재부팅되지 않음)" $AL && kill -0 $WP'
pkill -f "sleep 57$$\$" 2>/dev/null; mv -f $T/fakereboot.keep $T/fakereboot
printf 'pct=40\nstate=run\nstage=x\nt=1\nboot=boot-T\nut=95\n' > $T/lwprog.tmp; mv -f $T/lwprog.tmp $T/lwprog
c0=$(rbn); a0=$(alc "설치가 아직 진행 중"); mkrb; rbl "설치가 아직 진행 중" $a0
check "  설치 중(이번 부팅 state=run) → 재부팅 안 함, ap.log에 이유" '[ "$(rbn)" = $c0 ] && grep -q "재부팅 요청 거절: 설치가 아직 진행 중(이번 부팅 설치 진행 기록 run)" $AL'
check "  베타 1: 설치 중 → 앱이 읽는 결과 파일(644)에 이 요청 id와 code=install(앱은 '마무리하는 중')" 'rbr install'
printf 'pct=40\nstate=run\nstage=x\nt=1\nboot=boot-OLD\n' > $T/lwprog.tmp; mv -f $T/lwprog.tmp $T/lwprog
c0=$(rbn); a0=$(alc "재부팅 명령이 끝났지만"); mkrb; rbl "재부팅 명령이 끝났지만" $a0
check "  베타 1: 설치 중 기록이 지난 부팅 것이면 막지 않음(재부팅 부름)" '[ "$(rbn)" = $((c0+1)) ]'
printf 'pct=100\nstate=done\nstage=x\nt=1\nboot=boot-T\n' > $T/lwprog.tmp; mv -f $T/lwprog.tmp $T/lwprog
c0=$(rbn); a0=$(alc "재부팅 명령이 끝났지만"); mkrb; rbl "재부팅 명령이 끝났지만" $a0
check "  베타 1: 설정이 끝난 차(state=done)도 [지금 재부팅]을 받음(버튼이 늘 보임, '재부팅 필요'일 때만 받던 조건을 뺌)" '[ "$(rbn)" = $((c0+1)) ] && ! grep -q "필요한 상태가 아님" $AL'
printf 'pct=100\nstate=reboot\nstage=x\nt=1\nboot=boot-T\n' > $T/lwprog.tmp; mv -f $T/lwprog.tmp $T/lwprog
# 리뷰 H1: 설치 마무리(fix_perms, 서비스 hotspot.sh의 하위 셸)가 아직 돌면 state=reboot이어도 재부팅하지 않음
fpalive 99995 "" svc/hotspot.sh; echo "99995 boot-T" > $T/w/fix.pid
c0=$(rbn); a0=$(alc "설치 마무리"); mkrb; rbl "설치 마무리" $a0
check "1.7.3 리뷰 H1: state=reboot + 설치 마무리(fix.pid 살아 있음) → 재부팅 안 함, ap.log에 이유" '[ "$(rbn)" = $c0 ] && [ "$(alc "재부팅 요청 거절: 설치 마무리(시스템 파일·HMG-API 적용)가 아직 도는 중")" = $((a0+1)) ]'
check "  1.7.3 리뷰 M2: 설치 마무리 중 → 앱이 읽는 결과 파일(644)에 이 요청 id와 code=fix" 'rbr fix'
rm -rf $T/fproc/99995; rm -f $T/w/fix.pid
fpalive 99994 --report; echo "99994 boot-T" > $T/w/collect.pid
c0=$(rbn); a0=$(alc "재부팅 요청 거절: 제보 파일을 만드는 중"); mkrb; rbl "재부팅 요청 거절: 제보 파일을 만드는 중" $a0
check "  제보 파일을 만드는 중(collect.pid 살아 있음) → 재부팅 안 함, ap.log에 이유" '[ "$(rbn)" = $c0 ] && grep -q "재부팅 요청 거절: 제보 파일을 만드는 중" $AL'
check "  1.7.3 리뷰 M2: 제보 만드는 중 → 앱이 읽는 결과 파일(644)에 이 요청 id와 code=collect" 'rbr collect'
rm -rf $T/fproc/99994; rm -f $T/w/collect.pid
# 베타 1 리뷰 1: rw 확인 대신, 우리 밖에서 /system을 바꾸는 프로세스(HMG-API 엔진 apply·restore·recover, hmgapid remount,
# nemesis install·uninstall)가 돌면 거절(code=fix). 같은 엔진이라도 plan(읽기만)이면 받음. 명령줄을 하나도 못 읽으면 거절
mkdir -p $T/fproc/99993; printf 'app_process\0/system/bin\0hmgapi.engine.Engine\0apply\0' > $T/fproc/99993/cmdline
c0=$(rbn); a0=$(alc "시스템 영역을 바꾸는 작업"); mkrb; rbl "시스템 영역을 바꾸는 작업" $a0
check "베타 1 리뷰 1: HMG-API 엔진 apply(app_process … hmgapi.engine.Engine apply)가 돌면 재부팅 안 함, ap.log에 이유" '[ "$(rbn)" = $c0 ] && grep -q "재부팅 요청 거절: 시스템 영역을 바꾸는 작업이 도는 중(HMG-API 적용)" $AL'
check "  베타 1 리뷰 1·재리뷰 M2: 그때 결과 파일 code=sysw(앱은 '설정을 마무리하는 중', 이어지면 RESET 안내)" 'rbr sysw'
printf 'hmgapid\0remount\0rw\0' > $T/fproc/99993/cmdline
c0=$(rbn); a0=$(alc "시스템 영역을 바꾸는 작업"); mkrb; rbl "시스템 영역을 바꾸는 작업" $a0
check "  베타 1 리뷰 1: hmgapid remount가 돌면 거절" '[ "$(rbn)" = $c0 ] && grep -q "도는 중(remount)" $AL'
printf 'nemesis\0install\0/storage/usb0/packages/x.zip\0' > $T/fproc/99993/cmdline
c0=$(rbn); a0=$(alc "시스템 영역을 바꾸는 작업"); mkrb; rbl "시스템 영역을 바꾸는 작업" $a0
check "  베타 1 리뷰 1: nemesis install이 돌면 거절" '[ "$(rbn)" = $c0 ] && grep -q "도는 중(NEMESIS 설치·삭제)" $AL'
printf 'app_process\0/system/bin\0hmgapi.engine.Engine\0plan\0' > $T/fproc/99993/cmdline
c0=$(rbn); a0=$(alc "재부팅 명령이 끝났지만"); mkrb; rbl "재부팅 명령이 끝났지만" $a0
check "  베타 1 리뷰 1: 엔진 plan(읽기만)이면 막지 않음(재부팅 부름)" '[ "$(rbn)" = $((c0+1)) ]'
rm -rf $T/fproc/99993
# 재리뷰 M1: hook-check.sh(포크 boot.sh가 "sh /data/hmgapi/hook-check.sh"로 띄움), 엔진 update-hmgapi, nemesis remount도 거절
for c in 'sh\0/data/hmgapi/hook-check.sh\0' 'app_process\0/system/bin\0hmgapi.engine.Engine\0update-hmgapi\0/sdcard/h.zip\0' 'nemesis\0remount\0rw\0'; do
  mkdir -p $T/fproc/99993; printf "$c" > $T/fproc/99993/cmdline
  c0=$(rbn); a0=$(alc "시스템 영역을 바꾸는 작업"); mkrb; rbl "시스템 영역을 바꾸는 작업" $a0
  check "  재리뷰 M1: 명령줄 '$(printf "$c" | tr '\0' ' ')'이 돌면 재부팅 거절(code=sysw)" '[ "$(rbn)" = $c0 ] && rbr sysw'
done
rm -rf $T/fproc/99993
# 재리뷰 M2: /proc 명령줄을 하나도 못 읽으면 ps로 한 번 더 보고, ps에 엔진 apply가 보이면 거절
mv $T/fproc/1 $T/fproc1.keep; cp $T/ps $T/ps.m2keep
printf '%s\n' "  PID USER       VSZ STAT COMMAND" "  777 root     1000 S    app_process /system/bin hmgapi.engine.Engine apply" > $T/ps
c0=$(rbn); a0=$(alc "시스템 영역을 바꾸는 작업"); mkrb; rbl "시스템 영역을 바꾸는 작업" $a0
check "  재리뷰 M2: /proc 명령줄을 못 읽어도 ps에 엔진 apply가 보이면 거절(code=sysw)" '[ "$(rbn)" = $c0 ] && grep -q "도는 중(HMG-API 적용)" $AL && rbr sysw'
# ps도 아무것도 못 보이면 막지 않고(재부팅 받음) 로그만
: > $T/ps
c0=$(rbn); a0=$(alc "재부팅 명령이 끝났지만"); mkrb; rbl "재부팅 명령이 끝났지만" $a0
check "  재리뷰 M2: /proc·ps 모두 명령줄을 못 읽으면 막지 않고 재부팅 받음, ap.log에 '명령줄을 읽지 못함'(버튼이 영영 막히지 않게)" '[ "$(rbn)" = $((c0+1)) ] && grep -q "프로세스 명령줄을 읽지 못함(/proc·ps 모두). 막지 않음" $AL'
mv $T/fproc1.keep $T/fproc/1; cp $T/ps.m2keep $T/ps; rm -f $T/ps.m2keep
# 재리뷰 L2: 검사와 재부팅 사이(sync 동안) 바깥 작업이 새로 시작했으면 그때 거절. 가짜 sync가 엔진 apply 프로세스를 만든다
touch $T/sync_mkbusy
c0=$(rbn); a0=$(alc "sync 뒤 다시 보니"); mkrb; rbl "sync 뒤 다시 보니" $a0
check "  재리뷰 L2: sync 뒤 다시 보니 바깥 작업이 시작됐으면 재부팅 명령을 부르지 않고 거절(code=sysw)" '[ "$(rbn)" = $c0 ] && grep -q "재부팅 요청 거절: sync 뒤 다시 보니 시스템 영역·설치 마무리·제보 작업이 시작됨(HMG-API 적용)" $AL && rbr sysw'
rm -f $T/sync_mkbusy; rm -rf $T/fproc/99992
# 베타 2 #64: 부팅 뒤 120초 안이고 HMG-API 시작 횟수(starts)가 2·3이면 재부팅 거절(code=guard). 4 이상(이미 꺼짐)·못 읽음이면 막지 않음
# 10장 확인 리뷰 1: HMG-API 설치 기록(version)과 hook/enable이 있을 때만 거절한다(HOOKDIR는 starts 파일 폴더 = $T)
echo "version 1.0.2" > $T/lwinst; : > $T/enable
printf 2 > $T/hstarts
c0=$(rbn); a0=$(alc "부팅 보호 횟수"); mkrb; rbl "부팅 보호 횟수" $a0
check "베타 2 #64·확인 리뷰 4: 부팅 뒤 101초이고 starts=2(줄바꿈 없이 쓴 파일)면 재부팅 거절(커널 줄이 없으면 300초까지), 결과 파일 code=guard, ap.log에 이유" '[ "$(rbn)" = $c0 ] && rbr guard && grep -q "재부팅 요청 거절: 부팅 뒤 101초(HMG-API 시작 확인 시각 300초 전)이고 HMG-API 부팅 보호 횟수 starts=2" $AL'
echo 4 > $T/hstarts
c0=$(rbn); a0=$(alc "재부팅 명령이 끝났지만"); mkrb; rbl "재부팅 명령이 끝났지만" $a0
check "  베타 2 #64: starts=4(이미 훅 꺼짐)면 재부팅이 더 나빠지지 않아 막지 않음" '[ "$(rbn)" = $((c0+1)) ]'
# 리뷰 M1: watcher는 zygote 시작(커널 줄 "hooks on" 시각) 뒤 120초에 돈다. 그 시각 + 120 + 15초까지 막는다(zygote가 부팅 뒤 10초면 145초)
echo 3 > $T/hstarts; cp $T/w/watch.until $T/wu.keep 2>/dev/null; echo 5000 > $T/w/watch.until.tmp; mv -f $T/w/watch.until.tmp $T/w/watch.until
printf '%s\n' "<6>[   10.2] hmgapi-hook: zygote, hooks on, start 3, hmgapid" > $T/kdmesg; upset 130
c0=$(rbn); a0=$(alc "시작 확인 시각 145초 전"); mkrb; rbl "시작 확인 시각 145초 전" $a0
check "  리뷰 M1: 부팅 뒤 130초라도 zygote(10초)+120+15=145초 전이고 starts=3이면 거절(커널 부팅이 아니라 zygote 시각 기준)" '[ "$(rbn)" = $c0 ] && rbr guard'
upset 150
c0=$(rbn); a0=$(alc "재부팅 명령이 끝났지만"); mkrb; rbl "재부팅 명령이 끝났지만" $a0
check "  리뷰 M1: zygote 기준 145초가 지나면(부팅 뒤 150초) starts=3이어도 막지 않음" '[ "$(rbn)" = $((c0+1)) ]'
: > $T/kdmesg; upset 310
c0=$(rbn); a0=$(alc "재부팅 명령이 끝났지만"); mkrb; rbl "재부팅 명령이 끝났지만" $a0
check "  리뷰 M1: 커널 줄이 없어도 부팅 뒤 300초가 지나면 막지 않음(늘 끝이 있음)" '[ "$(rbn)" = $((c0+1)) ]'
upset 130; echo 1 > $T/hstarts; printf '%s\n' "<6>[   10.2] hmgapi-hook: zygote, hooks on, start 3, hmgapid" > $T/kdmesg
c0=$(rbn); a0=$(alc "재부팅 명령이 끝났지만"); mkrb; rbl "재부팅 명령이 끝났지만" $a0
check "  리뷰 M1: watcher가 돌아 starts가 0·1이 되면 그 구간 안이어도 바로 풀림" '[ "$(rbn)" = $((c0+1)) ]'
# 10장 확인 리뷰 4: 시각 없는 커널 줄(printk 시각 꺼짐)이면 "hooks on" 시각을 몰라 300초까지
echo 3 > $T/hstarts; printf '%s\n' "<6>hmgapi-hook: zygote, hooks on, start 3, hmgapid" > $T/kdmesg; upset 200
c0=$(rbn); a0=$(alc "시작 확인 시각 300초 전"); mkrb; rbl "시작 확인 시각 300초 전" $a0
check "  확인 리뷰 4: 커널 줄에 시각이 없으면 부팅 뒤 300초까지 거절(부팅 뒤 200초, starts=3)" '[ "$(rbn)" = $c0 ] && rbr guard'
# 10장 확인 리뷰 1: 막지 않아야 하는 차(모두 부팅 뒤 200초, starts=3)
: > $T/lwinst; : > $T/kdmesg
c0=$(rbn); a0=$(alc "재부팅 명령이 끝났지만"); mkrb; rbl "재부팅 명령이 끝났지만" $a0
check "  확인 리뷰 1: HMG-API를 --purge 없이 지운 차(설치 기록 version 없음)는 starts=3이 남아 있어도 막지 않음" '[ "$(rbn)" = $((c0+1)) ]'
echo "version 1.0.2" > $T/lwinst; printf '%s\n' "<6>[    3.0] hmgapi-hook: zygote, hooks off (disable file), hmgapid" > $T/kdmesg
c0=$(rbn); a0=$(alc "재부팅 명령이 끝났지만"); mkrb; rbl "재부팅 명령이 끝났지만" $a0
check "  확인 리뷰 1: 이번 부팅 zygote 줄이 off(disable 파일)면 막지 않음" '[ "$(rbn)" = $((c0+1)) ]'
printf '%s\n' "<6>[    3.0] hmgapi-hook: zygote, hooks off (boot guard, starts=3), hmgapid" > $T/kdmesg
c0=$(rbn); a0=$(alc "재부팅 명령이 끝났지만"); mkrb; rbl "재부팅 명령이 끝났지만" $a0
check "  확인 리뷰 1: 이번 부팅 zygote 줄이 guard(이미 꺼짐)면 막지 않음" '[ "$(rbn)" = $((c0+1)) ]'
: > $T/kdmesg; : > $T/disable
c0=$(rbn); a0=$(alc "재부팅 명령이 끝났지만"); mkrb; rbl "재부팅 명령이 끝났지만" $a0
check "  확인 리뷰 1: 커널 줄이 없고 hook/disable이 있으면 막지 않음" '[ "$(rbn)" = $((c0+1)) ]'
rm -f $T/disable $T/enable
c0=$(rbn); a0=$(alc "재부팅 명령이 끝났지만"); mkrb; rbl "재부팅 명령이 끝났지만" $a0
check "  확인 리뷰 1: 커널 줄이 없고 hook/enable이 없으면(훅을 켠 적 없음) 막지 않음" '[ "$(rbn)" = $((c0+1)) ]'
: > $T/enable; upset 100; printf '%s\n' "<6>[    3.0] hmgapi-hook: zygote, hooks on, start 3, hmgapid" > $T/kdmesg
c0=$(rbn); a0=$(alc "시작 확인 시각 138초 전"); mkrb; rbl "시작 확인 시각 138초 전" $a0
check "  확인 리뷰 1: 설치돼 있고 이번 부팅 줄이 on이면 그대로 거절(부팅 뒤 100초, 3+120+15=138초 전)" '[ "$(rbn)" = $c0 ] && rbr guard' 
rm -f $T/kdmesg $T/enable $T/lwinst
upset 100; [ -f $T/wu.keep ] && { cp $T/wu.keep $T/w/watch.until.tmp; mv -f $T/w/watch.until.tmp $T/w/watch.until; rm -f $T/wu.keep; }; rm -f $T/hstarts
# 확인 리뷰 M1: 차의 busybox tr이 NUL을 못 바꿔 명령줄이 잘리거나(첫 NUL에서) 붙는(NUL을 뺌) 경우. 감시자 자기 명령줄로 pcmd를 확인해
# 믿을 수 없으면 fix.pid·collect.pid는 살아 있으면 바쁨(막는 쪽), 바깥 작업은 ps로 본다
WPS=$(cut -d' ' -f1 $T/w/watch.pid); fpalive $WPS --watch
printf '#!/bin/sh\nif [ "$1" = "\\0" ] && [ -f %s/tr_trunc ]; then /usr/bin/tr "\\0" "\\n" | /usr/bin/head -1 | /usr/bin/tr -d "\\n"; exit 0; fi\nif [ "$1" = "\\0" ] && [ -f %s/tr_drop ]; then /usr/bin/tr -d "\\0"; exit 0; fi\nexec /usr/bin/tr "$@"\n' $T $T > $T/bin/tr; chmod +x $T/bin/tr
for m in trunc drop; do
  : > $T/tr_$m
  fpalive 99981 "" svc/hotspot.sh; echo "99981 boot-T" > $T/w/fix.pid
  c0=$(rbn); a0=$(alc "설치 마무리"); mkrb; rbl "설치 마무리" $a0
  check "확인 리뷰 M1: tr이 명령줄을 $m(잘림/붙음)해도 우리 설치 마무리(fix.pid 살아 있음) 중에는 재부팅 거절(막는 쪽)" '[ "$(rbn)" = $c0 ] && rbr fix'
  rm -rf $T/fproc/99981; rm -f $T/w/fix.pid
  cp $T/ps $T/ps.m1keep; mkdir -p $T/fproc/99982; printf 'app_process\0/system/bin\0hmgapi.engine.Engine\0apply\0' > $T/fproc/99982/cmdline
  printf '%s\n' "  PID USER       VSZ STAT COMMAND" "  777 root     1000 S    app_process /system/bin hmgapi.engine.Engine apply" > $T/ps
  c0=$(rbn); a0=$(alc "시스템 영역을 바꾸는 작업"); mkrb; rbl "시스템 영역을 바꾸는 작업" $a0
  check "  확인 리뷰 M1: tr이 $m이면 /proc 판정을 쓰지 않고 ps로 엔진 apply를 보고 거절(code=sysw), ap.log에 '잘려 읽힘'" '[ "$(rbn)" = $c0 ] && rbr sysw && grep -q "프로세스 명령줄이 잘려 읽힘(tr). ps로 확인함" $AL'
  rm -rf $T/fproc/99982; cp $T/ps.m1keep $T/ps; rm -f $T/ps.m1keep $T/tr_$m
done
# tr이 정상이면 같은 자기 확인을 거쳐 예전처럼(다른 프로그램의 pid면 막지 않음)
fpalive 99981 "" other.sh; echo "99981 boot-T" > $T/w/fix.pid
c0=$(rbn); a0=$(alc "재부팅 명령이 끝났지만"); mkrb; rbl "재부팅 명령이 끝났지만" $a0
check "  확인 리뷰 M1: tr이 정상이면(자기 명령줄 낱말 셋) fix.pid가 다른 프로그램을 가리킬 때는 막지 않음(재부팅 받음)" '[ "$(rbn)" = $((c0+1)) ]'
rm -rf $T/fproc/99981 $T/fproc/$WPS; rm -f $T/w/fix.pid $T/bin/tr
# 베타 1 리뷰 2: 이번 부팅 run 기록이 마지막으로 쓴 지(ut) 900초 넘었고 설치 마무리가 돌지 않으면 멈춘 기록으로 보고 받음
cp $T/w/watch.until $T/wu.keep 2>/dev/null; echo 5000 > $T/w/watch.until.tmp; mv -f $T/w/watch.until.tmp $T/w/watch.until; upset 1200
printf 'pct=40\nstate=run\nstage=x\nt=1\nboot=boot-T\nut=200\n' > $T/lwprog.tmp; mv -f $T/lwprog.tmp $T/lwprog
c0=$(rbn); a0=$(alc "재부팅 명령이 끝났지만"); mkrb; rbl "재부팅 명령이 끝났지만" $a0
check "베타 1 리뷰 2: run 기록이 1000초 그대로(ut)이고 설치 마무리가 없으면 멈춘 기록으로 보고 재부팅을 받음, ap.log에 한 줄" '[ "$(rbn)" = $((c0+1)) ] && grep -q "설치 진행 기록이 run인 채 1000초 그대로: 멈춘 기록으로 보고" $AL'
printf 'pct=40\nstate=run\nstage=x\nt=1\nboot=boot-T\nut=1150\n' > $T/lwprog.tmp; mv -f $T/lwprog.tmp $T/lwprog
c0=$(rbn); a0=$(alc "설치가 아직 진행 중"); mkrb; rbl "설치가 아직 진행 중" $a0
check "  베타 1 리뷰 2: 50초 전에 쓴 run이면 그대로 설치 중으로 거절" '[ "$(rbn)" = $c0 ] && rbr install'
printf 'pct=40\nstate=run\nstage=x\nt=1\nboot=boot-T\n' > $T/lwprog.tmp; mv -f $T/lwprog.tmp $T/lwprog
c0=$(rbn); a0=$(alc "재부팅 명령이 끝났지만"); mkrb; rbl "재부팅 명령이 끝났지만" $a0
check "  베타 1 리뷰 2: run 기록에 마지막 시각(ut)이 없으면 멈춘 기록으로 보고 받음(끝없이 거절하지 않게)" '[ "$(rbn)" = $((c0+1)) ] && grep -q "마지막 시각을 모름" $AL'
upset 100; [ -f $T/wu.keep ] && { cp $T/wu.keep $T/w/watch.until.tmp; mv -f $T/w/watch.until.tmp $T/w/watch.until; rm -f $T/wu.keep; }
printf 'pct=100\nstate=reboot\nstage=x\nt=1\nboot=boot-T\n' > $T/lwprog.tmp; mv -f $T/lwprog.tmp $T/lwprog
# 재리뷰 중간 1: pid는 이번 부팅에 살아 있는데 명령줄을 못 읽으면(빈 값) 돌고 있는 것으로 보고 거절(막는 쪽으로)
mkdir -p $T/fproc/99996; : > $T/fproc/99996/cmdline; echo "99996 boot-T" > $T/w/fix.pid
c0=$(rbn); a0=$(alc "설치 마무리"); mkrb; rbl "설치 마무리" $a0
check "1.7.3 재리뷰 중간 1: fix.pid가 살아 있고 명령줄을 못 읽으면 설치 마무리 중으로 보고 거절" '[ "$(rbn)" = $c0 ] && [ "$(alc "설치 마무리")" = $((a0+1)) ]'
rm -f $T/w/fix.pid; echo "99996 boot-T" > $T/w/collect.pid
c0=$(rbn); a0=$(alc "제보 파일을 만드는 중"); mkrb; rbl "제보 파일을 만드는 중" $a0
check "  collect.pid도 같음(명령줄을 못 읽으면 만드는 중으로 보고 거절)" '[ "$(rbn)" = $c0 ] && [ "$(alc "제보 파일을 만드는 중")" = $((a0+1)) ]'
rm -f $T/w/collect.pid; echo "99996 boot-OLD" > $T/w/fix.pid
c0=$(rbn); a0=$(alc "재부팅 명령이 끝났지만"); mkrb; rbl "재부팅 명령이 끝났지만" $a0
check "  지난 부팅 pid면 막지 않음(재부팅 부름)" '[ "$(rbn)" = $((c0+1)) ]'
check "  1.7.3 리뷰 M2: 받았지만 재부팅 명령이 돌아옴 → 앱이 읽는 결과 파일(644)에 이 요청 id와 code=cmd" 'rbr cmd'
rm -rf $T/fproc/99996; rm -f $T/w/fix.pid
# 재리뷰(낮음): boot_id를 못 읽으면 요청을 이번 부팅 것으로 볼 수 없어 거절
mv $T/bootid $T/bootid.keep; c0=$(rbn); a0=$(alc "$RJ"); mkrb; rbl "$RJ" $a0; mv $T/bootid.keep $T/bootid
check "  재리뷰: boot_id를 못 읽으면 거절(이번 부팅의 새 요청이 아님)" '[ "$(rbn)" = $c0 ] && [ "$(alc "$RJ")" = $((a0+1)) ]'
printf 'pct=100\nstate=done\nstage=x\nt=1\nboot=boot-T\n' > $T/lwprog.tmp; mv -f $T/lwprog.tmp $T/lwprog
upset 200
check "1.7.3 R-7: 감시자는 끝나는 시각(부팅 뒤 초)이 지나면 끝나고 watch.pid·잠금을 지움" 'wdone $WP 5 && [ ! -f $T/w/watch.pid ] && [ ! -d $T/w/watch.lock ]'
rm -rf $T/fproc/$WP; upset 100
# 재리뷰(낮음): 부팅 뒤 초를 못 읽으면(파일 없음) 감시자는 바로 끝나고 유효한 재부팅 요청도 처리하지 않음.
# (값이 숫자가 아니면 awk int가 0으로 읽어 나이가 음수가 되므로 "지금보다 뒤임"으로 거절된다: 위 음수 시험과 같은 길)
printf 'pct=100\nstate=reboot\nstage=x\nt=1\nboot=boot-T\n' > $T/lwprog; echo 999 > $T/w/watch.until; mkrb boot-T 100
rm -f $T/uptime; c0=$(rbn)
LW --watch & W5=$!
check "  재리뷰: 부팅 뒤 초를 못 읽으면 감시자는 끝나고 reboot을 부르지 않음(요청 파일 그대로)" 'wdone $W5 3 && [ "$(rbn)" = $c0 ] && [ -f $T/reboot.req ]'
upset 101; rm -f $T/w/watch.until
# 재리뷰(낮음): 감시자 밖(--report, --wait, 보통 Launch)은 유효한 재부팅 요청 + state=reboot이어도 reboot을 부르지 않음(동작으로)
mkrb; c0=$(rbn); LW --report >/dev/null 2>&1; (LWSYNC=1; LWPROG=$T/lwprog; LW --wait >/dev/null 2>&1); (LWSYNC=1; LW >/dev/null 2>&1); /bin/sleep 1
check "  재리뷰: --report·--wait·보통 Launch(감시자 없이)는 유효한 재부팅 요청이 있어도 reboot을 부르지 않고 요청도 건드리지 않음" '[ "$(rbn)" = $c0 ] && [ -f $T/reboot.req ]'
rm -f $T/reboot.req; printf 'pct=100\nstate=done\nstage=x\nt=1\nboot=boot-T\n' > $T/lwprog; upset 100
# 지난 부팅·죽은 감시자가 남긴 잠금: 1초 뒤에도 살아 있는 감시자가 없으면 지우고 잡는다
mkdir -p $T/w/watch.lock; echo "99990 boot-OLD" > $T/w/watch.pid; echo 103 > $T/w/watch.until
LW --watch & W3=$!; i=0; while ! grep -q "boot-T$" $T/w/watch.pid 2>/dev/null && [ $i -lt 50 ]; do /bin/sleep 0.1; i=$((i+1)); done
check "  남은 잠금(지난 부팅 감시자)은 지우고 새 감시자가 잡음" 'grep -q "^[0-9]* boot-T$" $T/w/watch.pid && ! grep -q 99990 $T/w/watch.pid && [ -d $T/w/watch.lock ]'
upset 200; wdone $W3 5; upset 100
echo x > $T/w/watch.until
LW --watch & W3=$!
check "  끝나는 시각을 읽지 못하면(숫자 아님) 바로 끝남(잠금도 풂)" 'wdone $W3 3 && [ ! -f $T/w/watch.pid ] && [ ! -d $T/w/watch.lock ]'
rm -f $T/w/watch.until
LW --watch & W3=$!
check "  끝나는 시각 파일이 없어도 바로 끝남" 'wdone $W3 3'
# 서비스 점검이 띄우는 --report(감시자 없음)
c0=$(crn); rm -f $RPROG; mkreq boot-OLD; LW --report >/dev/null 2>&1
check "1.7.3 R-7: 이전 부팅의 요청은 버림(만들지 않음, 요청 파일은 지움)" '[ "$(crn)" = $c0 ] && [ ! -f $RPROG ] && [ ! -f $T/report.req ]'
c0=$(crn); mkreq; LW --report >/dev/null 2>&1; LW --report >/dev/null 2>&1
check "1.7.3 R-7: 요청 하나에 --report 두 번 → 한 번만 돎" '[ "$(crn)" = $((c0+1)) ]'
c0=$(crn); rm -f $RPROG; echo "$RQN boot-T 100" > $T/report.req; LW --report >/dev/null 2>&1
check "  지우지 못해 남은 같은 요청(req.last의 id와 같음)은 다시 처리하지 않음(R-3 권한 대비)" '[ "$(crn)" = $c0 ] && [ ! -f $RPROG ]'
c0=$(crn); rm -f $RPROG; upset 300; mkreq boot-T 10; LW --report >/dev/null 2>&1
check "  리뷰 낮음: 2분 넘은 요청(부팅 뒤 10초에 쓰고 지금 300초)은 버림" '[ "$(crn)" = $c0 ] && [ ! -f $RPROG ] && [ ! -f $T/report.req ]'
c0=$(crn); mkreq boot-T 200; LW --report >/dev/null 2>&1; upset 100
check "  2분 안의 요청(부팅 뒤 200초에 쓰고 지금 300초)은 받음" '[ "$(crn)" = $((c0+1)) ]'
c0=$(crn); rm -f $RPROG; mkreq boot-T 0x; LW --report >/dev/null 2>&1
check "  값이 숫자가 아니면 받지 않고 지움" '[ "$(crn)" = $c0 ] && [ ! -f $RPROG ] && [ ! -f $T/report.req ]'
fpalive 99991 --report; echo "99991 boot-T" > $T/w/collect.pid; c0=$(crn)
printf 'pct=40\nstate=run\nstage=x\nt=1\nboot=boot-T\nreq=777\nreq2=\n' > $RPROG
mkreq; RJ=$RQN; LW --report >/dev/null 2>&1
check "  다른 제보 만들기(collect.pid가 이번 부팅에 살아 있음)가 돌면 겹쳐 돌지 않고, 그 요청 id를 req.join에 남김(리뷰 낮음)" '[ "$(crn)" = $c0 ] && grep -qx "req=777" $RPROG && [ "$(cat $T/w/collect.pid)" = "99991 boot-T" ] && [ "$(cat $T/w/req.join)" = $RJ ]'
check "  돌고 있는 쪽의 진행 기록 쓰기(rprog·carreport result)가 req2로 그 id를 적음(소스)" 'grep -q "\"\$REQID\" \"\$(cat \$W/req.join 2>/dev/null)\"" $PKG/bin/status.sh && grep -q "\"\$REQID\" \"\$(cat \$W/req.join 2>/dev/null)\"" $PKG/bin/carreport.sh'
rm -rf $T/fproc/99991; rm -f $T/w/collect.pid $T/w/req.join $RPROG
fpalive 99992 --watch; echo "99992 boot-T" > $T/w/watch.pid; c0=$(crn); mkreq; LW --report >/dev/null 2>&1
check "  감시자가 살아 있으면 --report는 요청을 건드리지 않고 감시자에 맡김" '[ "$(crn)" = $c0 ] && [ -f $T/report.req ]'
echo "sh /data/nemesis/apps/korea.projection/bin/status.sh --report" > $T/fproc/99992/cmdline; LW --report >/dev/null 2>&1
check "  리뷰 낮음: watch.pid의 pid가 status.sh라도 --watch가 아니면 감시자로 보지 않음" '[ "$(crn)" = $((c0+1)) ] && [ ! -f $T/report.req ]'
rm -rf $T/fproc/99992; rm -f $T/w/watch.pid $T/report.req
# 설치 진행 중(이번 부팅 PROG state=run)에 만들어진 리포트(서비스 백업 경로 등)는 첫 줄에 알린다(R-2, #114·#115)
printf 'pct=40\nstate=run\nstage=x\nt=1\nboot=boot-T\n' > $T/progr; rm -f $RPROG
mkreq; (LWPROG=$T/progr; LW --report >/dev/null 2>&1)
check "1.7.3 R-2: 설치 진행 중에 만든 리포트는 1-report.md 첫 줄에 '설치 진행 중에 만든 리포트'를 굵게" 'sed -n 1p $T/usb0/KoreaProjection-report/1-report.md | grep -q "^\*\*설치 진행 중에 만든 리포트입니다. 설치가 끝난 뒤 \[제보 파일 만들기\]로 다시 만들어 주세요.\*\*$"'
printf 'pct=40\nstate=run\nstage=x\nt=1\nboot=boot-OLD\n' > $T/progr; mkreq; (LWPROG=$T/progr; LW --report >/dev/null 2>&1)
check "  지난 부팅의 run 기록이면 그 줄 없음" '[ "$(sed -n 1p $T/usb0/KoreaProjection-report/1-report.md)" = "# Korea Projection 리포트" ]'
rm -f $T/progr
# --wait(설치가 끝난 뒤 한 번 더): 상태 파일만 다시 쓰고 USB에는 쓰지 않는다. 베타 1부터 설치가 끝났으면(done) 감시자도 띄운다
# ([지금 재부팅]·[제보 파일 만들기]가 늘 보이므로, 설치 중 Launch 뒤 10분이 지나 버튼이 안 듣는 일이 없게)
rm -rf $T/usb0/KoreaProjection-report; rm -f $RPROG $T/w/watch.until $STF; printf 'pct=100\nstate=done\nstage=x\n' > $T/progw
(LWPROG=$T/progw; LW --wait >/dev/null 2>&1)
i=0; while [ ! -s $T/w/watch.pid ] && [ $i -lt 50 ]; do /bin/sleep 0.1; i=$((i+1)); done; WP2=$(cut -d' ' -f1 $T/w/watch.pid 2>/dev/null)
check "1.7.3 R-7·베타 1: --wait 뒤 상태 파일만 다시 쓰고 USB에 쓰지 않음, 설치가 끝났으면 감시자를 띄움(끝 = 부팅 뒤 초+WATCH_SECS)" '[ -s $STF ] && [ ! -e $T/usb0/KoreaProjection-report ] && [ ! -f $RPROG ] && [ "$(cat $T/w/watch.until)" = 105 ] && [ -n "$WP2" ]'
upset 200; [ -n "$WP2" ] && wdone $WP2 5; upset 100; rm -f $T/w/watch.until
# 베타 1 리뷰 9: --wait는 설치가 run에서 done이 될 때까지 실제로 기다린 뒤에 상태 파일을 쓰고 감시자를 띄운다
rm -f $T/w/watch.until $T/watchf; printf 'pct=40\nstate=run\nstage=x\nboot=boot-T\n' > $T/progw9
(LWPROG=$T/progw9; LW --wait >/dev/null 2>&1) & W9=$!
/bin/sleep 0.1; W9A=$([ -f $T/w/watch.until ] && echo early || echo none)
printf 'pct=100\nstate=done\nstage=x\nboot=boot-T\n' > $T/progw9.tmp; mv -f $T/progw9.tmp $T/progw9
wait $W9
i=0; while [ ! -s $T/w/watch.pid ] && [ $i -lt 50 ]; do /bin/sleep 0.1; i=$((i+1)); done; WP9=$(cut -d' ' -f1 $T/w/watch.pid 2>/dev/null)
check "베타 1 리뷰 9: --wait는 run 동안 감시자를 띄우지 않고 기다렸다가, done이 된 뒤 띄움(감시자 끝 시각 파일도 씀)" '[ "$W9A" = none ] && [ "$(cat $T/w/watch.until)" = 105 ] && [ -n "$WP9" ] && grep -qx "until=105" $T/watchf'
upset 200; [ -n "$WP9" ] && wdone $WP9 5; upset 100; rm -f $T/w/watch.until $T/progw9
# 4b K-7: 설치 중 Launch가 띄우는 --wait의 wait.pid도 "<pid> <boot_id>". 지난 부팅의 같은 pid는 살아 있는 것으로 보지 않음
printf 'pct=40\nstate=run\nstage=x\nboot=boot-T\n' > $T/progk7; echo boot-T > $T/bootid; rm -f $T/w/wait.pid
fpalive 4747 --wait; echo "4747 boot-T" > $T/w/wait.pid; (LWPROG=$T/progk7; LW >/dev/null 2>&1)
check "4b K-7: 이번 부팅의 --wait가 살아 있으면 다시 띄우지 않음(wait.pid 그대로)" '[ "$(cat $T/w/wait.pid)" = "4747 boot-T" ]'
echo "4747 boot-OLD" > $T/w/wait.pid; (LWPROG=$T/progk7; LW >/dev/null 2>&1)
K7P=; K7B=; read K7P K7B < $T/w/wait.pid
check "  4b K-7: 지난 부팅 것이면 새로 띄우고 wait.pid에 '<pid> <이번 부팅 id>'를 씀" '[ -n "$K7P" ] && [ "$K7P" != 4747 ] && [ "$K7B" = boot-T ]'
[ -n "$K7P" ] && kill $K7P 2>/dev/null; rm -rf $T/fproc/4747 $T/w/wait.pid $T/progk7
# 4b 리뷰 L-3: 1.7.2까지의 pid만 든 wait.pid는 부팅 id가 없어 살아 있는 것으로 보지 않음(새로 띄움)
printf 'pct=40\nstate=run\nstage=x\nboot=boot-T\n' > $T/progk7; fpalive 4747 --wait; echo "4747" > $T/w/wait.pid; (LWPROG=$T/progk7; LW >/dev/null 2>&1)
K7P=; K7B=; read K7P K7B < $T/w/wait.pid
check "  4b 리뷰 L-3: pid만 든 옛 wait.pid면 새로 띄우고 '<pid> boot-T'로 씀" '[ -n "$K7P" ] && [ "$K7P" != 4747 ] && [ "$K7B" = boot-T ]'
[ -n "$K7P" ] && kill $K7P 2>/dev/null; rm -rf $T/fproc/4747 $T/w/wait.pid $T/progk7
# 4b 리뷰 L-3: BID가 빈 값이면 fix_running·st_alive는 예전처럼 부팅 id 파일을 읽고, 값이 있으면 그 값을 씀
mkdir -p $T/wk7; fpalive 4848 x hotspot.sh; echo "4848 boot-T" > $T/wk7/fix.pid; fpalive 4747 --watch; echo "4747 boot-T" > $T/wk7/watch.pid
K7O=$(HOTSPOT_LIB=1 BB=$T/bin/bb W=$T/wk7 PROC=$T/fproc BOOT_ID=$T/bootid sh -c '. '$T'/app/svc/hotspot.sh; BID=; fix_running && echo F1; st_alive $W/watch.pid --watch && echo S1; BID=boot-OTHER; fix_running || echo F0; st_alive $W/watch.pid --watch || echo S0' 2>/dev/null | tr '\n' ' ')
check "  4b 리뷰 L-3: BID 빈 값 → 파일을 읽어 이번 부팅(fix_running·st_alive 살아 있음), BID가 다른 부팅이면 아님" '[ "$K7O" = "F1 S1 F0 S0 " ]'
rm -rf $T/fproc/4747 $T/fproc/4848 $T/wk7
check "  4b K-7: 감시자 1초 반복은 끝 시각·부팅 뒤 초를 read로 읽고, 요청 파일이 있을 때만 받는 함수를 부름(하위 셸 줄임)" 'sed -n "/^if \[ \"\$1\" = --watch \]/,/^fi/p" $PKG/bin/status.sh > $T/wsrc && grep -q "{ read _wu < \$W/watch.until; } 2>/dev/null" $T/wsrc && grep -q "{ read _wn _wx < \$UPTIME; } 2>/dev/null; _wn=\${_wn%%.\*}" $T/wsrc && grep -q "if \[ -f \$RBREQ \] && take_rbreq; then" $T/wsrc && grep -q "if \[ -f \$REQ \] && take_req; then" $T/wsrc && ! grep -q "\$(up_s)\|\$(cat \$W/watch.until" $T/wsrc'
rm -f $T/progw
# 리뷰 L1: 설치가 "재부팅 필요"로 끝난 뒤의 --wait는 지금부터 10분 동안 [지금 재부팅]을 받도록 감시자를 띄운다
rm -f $T/w/watch.until; printf 'pct=100\nstate=reboot\nstage=x\nt=1\nboot=boot-T\n' > $T/progw
(LWPROG=$T/progw; LW --wait >/dev/null 2>&1)
i=0; while [ ! -s $T/w/watch.pid ] && [ $i -lt 50 ]; do /bin/sleep 0.1; i=$((i+1)); done; WP3=$(cut -d' ' -f1 $T/w/watch.pid 2>/dev/null)
check "1.7.3 리뷰 L1: 설치가 '재부팅 필요'로 끝난 --wait는 감시자를 띄움(끝 = 부팅 뒤 초+WATCH_SECS), USB에는 안 씀" '[ "$(cat $T/w/watch.until)" = 105 ] && [ -n "$WP3" ] && [ ! -e $T/usb0/KoreaProjection-report ]'
check "베타 1 리뷰 3: Launch(--wait 포함)가 감시자 끝 시각을 앱이 읽는 파일에 씀(boot·until, 644)" 'grep -qx "boot=boot-T" $T/watchf && grep -qx "until=105" $T/watchf && [ "$(stat -f %Lp $T/watchf)" = 644 ]'
upset 200; [ -n "$WP3" ] && wdone $WP3 5
check "  베타 1 리뷰 3: 감시자가 끝나면 그 시각(지금 부팅 뒤 초)으로 다시 씀(앱이 '감시자 끝남'을 앎)" 'grep -qx "until=200" $T/watchf'
# 재리뷰 L1: 옛 감시자가 끝날 때 새 Launch가 쓴 끝 시각(옛 감시자가 본 값과 다름)을 덮지 않음
rm -f $T/w/watch.until; printf 'pct=100\nstate=done\nstage=x\nt=1\nboot=boot-T\n' > $T/progw
(LWPROG=$T/progw; LW --wait >/dev/null 2>&1)
i=0; while [ ! -s $T/w/watch.pid ] && [ $i -lt 50 ]; do /bin/sleep 0.1; i=$((i+1)); done; WP4=$(cut -d' ' -f1 $T/w/watch.pid 2>/dev/null)
printf 'boot=boot-T\nuntil=999\n' > $T/watchf
upset 200; [ -n "$WP4" ] && wdone $WP4 5
check "  재리뷰 L1: 옛 감시자는 끝날 때 자기가 본 끝 시각과 다른 값(새 Launch가 쓴 999)을 덮지 않음" '[ -n "$WP4" ] && grep -qx "until=999" $T/watchf'

check "  베타 1 리뷰 7: 감시자는 끝내기 전에 1초 뒤 끝 시각을 한 번 더 읽고, 늘어났으면 계속(소스)" 'sed -n "/^if \[ \"\$1\" = --watch \]/,/^fi/p" $PKG/bin/status.sh | grep -A3 "if \[ \"\$_wn\" -ge \"\$_wu\" \]; then" | grep -q "sleep 1"'
upset 100; rm -f $T/progw $T/w/watch.until
check "  리뷰 낮음: --watch·--report 갈래는 상태 파일 쓰기·앱 설치보다 먼저(소스 순서)" '[ "$(grep -n "^if \[ \"\$1\" = --watch \]" $PKG/bin/status.sh | cut -d: -f1)" -lt "$(grep -n "^status_kv 2>/dev/null > " $PKG/bin/status.sh | cut -d: -f1)" ] && [ "$(grep -n "^if \[ \"\$1\" = --report \]" $PKG/bin/status.sh | cut -d: -f1)" -lt "$(grep -n "^install_app_once" $PKG/bin/status.sh | cut -d: -f1)" ]'
# 서비스 30초 점검의 백업 경로(hotspot.sh req_tick): 감시자가 없을 때 받을 요청을 보면 status.sh --report를 뒤에서 띄운다
svreq() { (PATH=$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bbs17 APP=${SVAPP:-$T/app2} W=$T/w REQ=$T/report.req PROC=$T/fproc BOOT_ID=$T/bootid UPTIME=$T/uptime HMGLOG=$T/hl STATUS=$STF SRC=$T/softap.conf sh -c '. '$T'/app/svc/hotspot.sh; req_tick; echo "rc=$?"'); }
c0=$(crn); rm -f $RPROG; mkreq; RS=$RQN
svreq > $T/svreq.out 2>/dev/null; rpwait $RS
check "1.7.3 R-7: 서비스 점검(req_tick)이 요청을 보면 --report를 뒤에서 띄워 만듦, 0을 돌려줌, ap.log에 한 줄" 'grep -qx "rc=0" $T/svreq.out && grep -q "제보 파일 만들기 요청을 받음(서비스 점검)" $T/svreq.out && [ "$(crn)" = $((c0+1)) ] && grep -qx "req=$RS" $RPROG && [ -s $T/usb0/KoreaProjection-report/1-report.md ] && [ ! -f $T/report.req ]'
# 리뷰 중간 1: root가 읽기만 하고 지우지 못하는 요청(같은 내용이 계속 남음)이어도 서비스는 한 번만 띄운다
c0=$(crn); mkreq; RU=$RQN; cp $T/report.req $T/req.keep; rm -f $RPROG
svreq > $T/svreq.out 2>/dev/null; rpwait $RU
for k in 1 2 3; do cp $T/req.keep $T/report.req; svreq >> $T/svreq.out 2>/dev/null; done; /bin/sleep 3
check "  리뷰 중간 1: 지울 수 없는 요청(같은 id가 다시 남음) + req_tick 네 번 → --report 한 번, '요청을 받음'도 한 번" '[ "$(crn)" = $((c0+1)) ] && [ "$(grep -c "요청을 받음" $T/svreq.out)" = 1 ] && [ "$(grep -c "^rc=0$" $T/svreq.out)" = 4 ]'
c0=$(crn); rm -f $RPROG; mkreq boot-OLD; svreq > $T/svreq.out 2>/dev/null; /bin/sleep 3
check "  이전 부팅 요청이면 서비스는 띄우지 않음" '[ "$(crn)" = $c0 ] && ! grep -q "요청을 받음" $T/svreq.out && [ ! -f $RPROG ]'
rm -f $T/report.req
fpalive 99993 --watch; echo "99993 boot-T" > $T/w/watch.pid; c0=$(crn); rm -f $RPROG; mkreq
svreq > $T/svreq.out 2>/dev/null; /bin/sleep 3
check "  감시자가 살아 있으면 서비스는 띄우지 않음(감시자에 맡김), 0을 돌려줌(3초 기다려 늦게 띄워지는 것도 없음)" 'grep -qx "rc=0" $T/svreq.out && [ "$(crn)" = $c0 ] && [ -f $T/report.req ] && [ ! -f $RPROG ]'
rm -rf $T/fproc/99993; rm -f $T/w/watch.pid $T/report.req
svreq > $T/svreq.out 2>/dev/null
printf 'pct=100\nstate=reboot\nstage=x\nt=1\nboot=boot-T\n' > $T/lwprog; c0=$(rbn); mkrb
(PROG=$T/lwprog KP_REBOOT=$T/fakereboot KP_RBREQ=$T/reboot.req; export PROG KP_REBOOT KP_RBREQ; svreq > $T/svreq.out 2>/dev/null); /bin/sleep 3
check "1.7.3 U-3: 서비스 점검(req_tick)은 재부팅 요청을 받지 않음(늦게 재부팅해 놀라게 하지 않게): reboot 안 부름, 요청 파일 그대로" '[ "$(rbn)" = $c0 ] && [ -f $T/reboot.req ] && grep -qx "rc=0" $T/svreq.out'
rm -f $T/reboot.req; printf 'pct=100\nstate=done\nstage=x\nt=1\nboot=boot-T\n' > $T/lwprog
check "  재부팅은 감시자(--watch) 회차에서만 부름(소스: take_rbreq를 부르는 곳 한 곳, hotspot.sh에는 없음)" '[ "$(grep -c "take_rbreq; then" $PKG/bin/status.sh)" = 1 ] && ! grep -q "take_rbreq\|KP_REBOOT" $PKG/svc/hotspot.sh && grep -q "\${KP_REBOOT:-/system/bin/reboot}" $PKG/bin/status.sh'
check "  요청이 없거나(또는 읽지 못하면) 아무것도 안 하고 0" 'grep -qx "rc=0" $T/svreq.out && ! grep -q "요청을 받음" $T/svreq.out'
mkreq; SVAPP=$T/nope svreq > $T/svreq.out 2>/dev/null
check "  status.sh가 없어도 0(서비스 반복이 멈추지 않음, mode=restart)" 'grep -qx "rc=0" $T/svreq.out && ! grep -q "요청을 받음" $T/svreq.out'
rm -f $T/report.req
check "  req_tick은 30초마다: 우리 핫스팟 회차, 순정 AP 회차(60초 회차 안에서 두 번), 모드 대기·다른 hostapd 대기 회차" '[ "$(grep -c "^ *req_tick$" $PKG/svc/hotspot.sh)" = 3 ] && grep -q "while ! try_ready \"\$prod\"; do sleep 30 & wait \$!; req_tick; sleep 30 & wait \$!; req_tick; done" $PKG/svc/hotspot.sh && [ "$(grep -c "sleep 30 & wait \$!; req_tick$" $PKG/svc/hotspot.sh)" = 2 ] && awk "/^req_tick\(\) \{/,/^}/" $PKG/svc/hotspot.sh | grep -q "return 0"'
check "  1.7.3 리뷰 L1: 우리 핫스팟 30초 회차에서 req_tick이 ap_yield보다 먼저(다른 hostapd에 비켜 주는 동안에도 제보 요청을 봄)" '[ "$(awk "/^main\(\) \{/,/^}/" $PKG/svc/hotspot.sh | grep -n -E "^    req_tick$|^    ap_yield && continue$" | cut -d: -f2 | tr -d " " | tr "\n" ,)" = "req_tick,ap_yield&&continue," ]'
K6L1=$(HOTSPOT_LIB=1 BB=$T/bin/bb W=$T/w sh -c '. '$T'/app/svc/hotspot.sh; sleep() { :; }; k=0; req_tick() { k=$((k+1)); [ $k -ge 3 ] && { echo ticks=$k; exit 0; }; }; idle_req' 2>&1)
check "  1.7.3 리뷰 L1: 무선 설정 없이 대기하는 차(idle_req)도 30초마다 req_tick을 부름(대기는 끝나지 않음)" '[ "$K6L1" = ticks=3 ] && grep -q "^idle_req() { while true; do sleep 30 & wait \$!; req_tick; done; }$" $PKG/svc/hotspot.sh'
check "1.7.3 R-1: 서비스 안내 문구에 'Launch로 제보 파일'·'Launch에서 상태를 확인' 옛 안내가 없고, 버튼 안내(4곳, 칩 실패 문구는 1.7.3 W-2·W-6 문구로)로 바뀜" '! grep -q -E "Launch로|Launch에서" $PKG/svc/hotspot.sh $PKG/bin/status.sh $PKG/bin/carreport.sh && [ "$(grep -c "Launch 화면의 \[제보 파일 만들기\]를 눌러 보내 주세요" $PKG/svc/hotspot.sh)" = 4 ]'
check "  리뷰 낮음: preun이 감시자·제보 만들기(watch.pid·collect.pid)도 멈추고, 지울 때만 RPROG를 지움(업데이트 갈래 뒤)" 'grep -q "for _pf in wait.pid watch.pid collect.pid carreport.lock/pid; do" $PKG/scripts/preun.sh && [ "$(grep -n "rm -f \$RPROG \$RPROG.tmp" $PKG/scripts/preun.sh | cut -d: -f1)" -gt "$(grep -n "업데이트: 이전 버전 정리" $PKG/scripts/preun.sh | cut -d: -f1)" ]'
check "1.7.3 K-1: 요청 파일(report.req·reboot.req)은 앱 개인 폴더(앱을 지우면 함께 지워짐), 앱과 같은 이름" 'grep -q "^RBREQ=\${KP_RBREQ:-/data/data/korea.projection.app/files/reboot.req}" $PKG/svc/hotspot.sh && grep -q "RB_NAME = \"reboot.req\"" $B/nemesis-pkg/app-src/java/korea/projection/app/StatusActivity.java && grep -q "^remove_app$" $PKG/scripts/preun.sh'
check "1.7.3 K-6: 옛 개발용 패키지 호환 코드 없음(OLDPKG 대기, cp-drive 정리, 예전 패키지 안내), NEMESIS.data depends는 그대로" '! grep -q "OLDPKG" $PKG/svc/hotspot.sh && ! grep -q -E "cpdrive|watchdog" $PKG/scripts/post.sh && ! grep -q "niro.carplay.hotspot을 삭제" $PKG/scripts/post.sh && grep -qx "depends=\"!niro.carplay.hotspot\"" $PKG/NEMESIS.data'
check "1.7.3 K-2: 패키지에 LAST_TOAST 이름이 남지 않음(LAST_MSG)" '! grep -q LAST_TOAST $PKG/svc/hotspot.sh $PKG/bin/status.sh && [ "$(grep -c LAST_MSG $PKG/svc/hotspot.sh)" -ge 10 ]'
# U-5: 진행 기록을 쓰는 동안(P_ON=1)은 판정 줄과 같은 문장을 알림으로 또 쓰지 않음(ap.log에는 남김)
pn() { (PATH=$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$T/w NOTICE=$T/pn.notice BOOT_ID=$T/bootid sh -c '. '$T'/app/svc/hotspot.sh; P_ON='$1'; pnotice "Korea Projection: 무선 카플레이 설정을 마쳤습니다. 내비를 재부팅해 주세요."'); }
rm -f $T/pn.notice; pn 1 > $T/pn.out
check "1.7.3 U-5: P_ON=1이면 pnotice는 알림을 쓰지 않고 ap.log에만 '안내(진행 기록에 남김)'" '[ ! -s $T/pn.notice ] && grep -q "안내(진행 기록에 남김): 무선 카플레이 설정을 마쳤습니다" $T/pn.out'
pn 0 > $T/pn.out
check "  P_ON=0(진행 기록을 쓰지 않는 경로)이면 알림으로 남김(앞의 'Korea Projection: '은 뗌)" 'grep -q " boot-T 무선 카플레이 설정을 마쳤습니다. 내비를 재부팅해 주세요.$" $T/pn.notice'
check "  설정 끝 재부팅 안내·새 판 안내·wireless.projection 안내·모드 새 판 실패 안내·(1.7.3) Wi-Fi 부품·칩 안내는 pnotice로(판정 줄과 겹치는 것만)" '[ "$(grep -c "^ *pnotice \"" $PKG/svc/hotspot.sh)" = 6 ]'
# 2026-11-10(리뷰 반영 중 PC 시험에서 찾음): 받지 않는 요청을 지울 때 req_peek이 읽은 그 내용만 지운다. 파일을 다시 보고 지우면
# req_peek이 읽은 뒤(파일 없음) 막 들어온 새 요청을 지운다(감시자가 정상 요청을 "새 요청 아님"으로 버린 실패를 진단으로 확인)
rd() { (PATH=$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$T/w sh -c '. '$T'/app/svc/hotspot.sh; '"$1"); }
echo "2 boot-T 1" > $T/rd.req; rd 'RQ_RAW="1 boot-T 1"; req_drop '$T'/rd.req'; r1=$([ -f $T/rd.req ] && echo kept)
rd 'RQ_RAW=; req_drop '$T'/rd.req'; r2=$([ -f $T/rd.req ] && echo kept)
rd 'RQ_RAW="2 boot-T 1"; req_drop '$T'/rd.req'; r3=$([ -f $T/rd.req ] && echo kept)
check "1.7.3 req_drop: 읽은 내용과 다른 새 요청·읽지 못했을 때(빈 값)는 지우지 않고, 같은 내용만 지움" '[ "$r1" = kept ] && [ "$r2" = kept ] && [ -z "$r3" ]'
check "  take_req·take_rbreq는 받지 않는 요청·받은 요청 모두 req_drop으로 지움(파일을 다시 보고 rm 하지 않음)" '[ "$(grep -c "req_drop \$REQ$" $PKG/bin/status.sh)" = 2 ] && [ "$(grep -c "req_drop \$RBREQ$" $PKG/bin/status.sh)" = 2 ] && ! grep -q "\[ -f \$REQ \] && rm\|\[ -f \$RBREQ \] && rm" $PKG/bin/status.sh'
# 리뷰 H1: fix_perms 안에서 setup_hmgapi가 "재부팅 필요"를 써도, 권한 파일 되돌리기(뒤 단계)가 끝날 때까지는 "마무리하는 중"(run)
fh() { (PATH=$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$T/fh/w BK=$T/fh/bk PROG=$T/fh/prog BOOT_ID=$T/bootid sh -c '. '$T'/app/svc/hotspot.sh; setup_done() { return 1; }; mod_pending() { return 1; }; _fix_perms() { ptrack 70 run "무선 모드를 설치하는 중입니다"; ptrack 100 reboot "무선 카플레이 설정을 마쳤습니다. 내비를 재부팅해 주세요."; cp $PROG '$T'/fh/mid; '"$1"'; }; fix_perms'); }
mkdir -p $T/fh/w $T/fh/bk; rm -f $T/fh/prog $T/fh/mid; fh ':'
check "1.7.3 리뷰 H1: 설치 마무리 중에는 '재부팅 필요'를 미루고 '설치를 마무리하는 중입니다'(run 95%, 5/5)를 보임" 'grep -qx "state=run" $T/fh/mid && grep -qx "pct=95" $T/fh/mid && grep -qx "stage=설치를 마무리하는 중입니다" $T/fh/mid && grep -qx "step=5/5" $T/fh/mid'
check "  마무리가 끝나면 미뤄 둔 '재부팅 필요'를 그 문구로 씀" 'grep -qx "state=reboot" $T/fh/prog && grep -qx "stage=무선 카플레이 설정을 마쳤습니다. 내비를 재부팅해 주세요." $T/fh/prog'
rm -f $T/fh/prog; fh 'ptrack 100 fail "권한 파일 실패"'
check "  마무리 중 실패를 쓰면 미뤄 둔 '재부팅 필요'로 덮지 않음" 'grep -qx "state=fail" $T/fh/prog && grep -qx "stage=권한 파일 실패" $T/fh/prog'
rm -f $T/fh/prog; (PATH=$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$T/fh/w PROG=$T/fh/prog BOOT_ID=$T/bootid P_ON=1 sh -c '. '$T'/app/svc/hotspot.sh; ptrack 100 reboot "바로"')
check "  fix_perms 밖(P_HOLD 없음)에서는 예전처럼 바로 씀" 'grep -qx "state=reboot" $T/fh/prog && grep -qx "stage=바로" $T/fh/prog'
# 재리뷰(낮음): 실제 _fix_perms(권한 파일: remount rw → 쓰기 → ro → engine apply)를 돌리며, 가짜 hmgapid가 remount·apply를
# 받는 순간의 진행 기록 state를 남긴다. setup_hmgapi는 "재부팅 필요"를 쓰는 것으로 바꿔 둔다(그 뒤에 마무리가 도는 경우)
mkdir -p $T/fp/bin2; printf '#!/bin/sh\necho "$* | $(grep "^state=" %s/fp/prog)" >> %s/fp/hcalls\nexec %s/fp/bin/hmgapid "$@"\n' $T $T $T > $T/fp/bin2/hmgapid; chmod +x $T/fp/bin2/hmgapid
fpreset; rm -f $T/fp/prog $T/fp/hcalls
(cd $T/fp && PATH=$T/fp/bin2:$T/fp/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 NOTICE=$T/fp/notice FIX_DELAY=0 BB=$T/bin/bb W=$T/fp/w BK=$T/fp/bk APLOG=$T/fp/ap.log PERMS=$T/fp/perms MOUNTS=$T/fp/mounts PROG=$T/fp/prog BOOT_ID=$T/bootid sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$T'/fp/bin2:'$T'/fp/bin:'$T'/bin:/usr/bin:/bin:/sbin; setup_done() { return 1; }; mod_pending() { return 1; }; setup_hmgapi() { ptrack 100 reboot "무선 카플레이 설정을 마쳤습니다. 내비를 재부팅해 주세요."; }; fix_perms') > $T/fp/out 2>&1
check "1.7.3 재리뷰: 실제 권한 파일 마무리에서 remount rw·ro·engine apply를 받는 순간 진행 기록은 한 번도 reboot이 아님, 끝난 뒤 reboot" 'grep -q "^remount rw | state=run$" $T/fp/hcalls && grep -q "^remount ro | state=run$" $T/fp/hcalls && grep -q "^engine apply | state=run$" $T/fp/hcalls && ! grep -q -E "^(remount|engine apply).*state=reboot" $T/fp/hcalls && grep -qx "state=reboot" $T/fp/prog'
rm -rf $T/fp/bin2
# 재리뷰(낮음): 같은 부팅에 서비스가 다시 시작돼 fix_perms가 다시 돌아도 이미 쓴 "재부팅 필요"를 덮지 않음
printf 'pct=100\nstate=reboot\nstage=재부팅해 주세요\nt=1\nboot=boot-T\n' > $T/fh/prog; fh 'ptrack 10 run "기다리는 중"'
check "  재리뷰: 이번 부팅에 이미 '재부팅 필요'면 서비스가 다시 돌아도 진행 기록을 run·fail로 덮지 않음(재부팅 버튼 유지)" 'grep -qx "state=reboot" $T/fh/prog && grep -qx "stage=재부팅해 주세요" $T/fh/prog'
# U-7: 진행 기록에 단계(step=N/5): 진행 중일 때만
pg() { (PATH=$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$T/bin/bb W=$T/w PROG=$T/pg.prog BOOT_ID=$T/bootid sh -c '. '$T'/app/svc/hotspot.sh; prog '"$1"); }
pg '30 run "지도와 무선 모드를 확인하는 중입니다"'; s30=$(grep "^step=" $T/pg.prog)
pg '62 run "Wi-Fi 칩을 깨우는 중입니다"'; s62=$(grep "^step=" $T/pg.prog)
pg '85 run "무선 모드를 적용하는 중입니다"'; s85=$(grep "^step=" $T/pg.prog)
pg '100 reboot "x"'; sdone=$(grep "^step=" $T/pg.prog)
check "1.7.3 U-7: 진행 기록 step: 30% → 2/5, 62% → 4/5, 85% → 5/5, 끝(reboot)은 빈 값, 다른 줄은 그대로" '[ "$s30" = step=2/5 ] && [ "$s62" = step=4/5 ] && [ "$s85" = step=5/5 ] && [ "$sdone" = step= ] && grep -qx "state=reboot" $T/pg.prog && grep -qx "boot=boot-T" $T/pg.prog'
pg '15 run "HMG-API가 준비되기를 기다리는 중입니다"'; s15=$(grep "^step=" $T/pg.prog)
pg '95 run "설치를 마무리하는 중입니다"'; s95=$(grep "^step=" $T/pg.prog)
MOD_WAIT=1; export MOD_WAIT; pg '15 run "x"'; m15=$(grep "^step=" $T/pg.prog); pg '70 run "x"'; m70=$(grep "^step=" $T/pg.prog); unset MOD_WAIT
check "  리뷰 L5: 기다림 5~25% → 1/5, 마무리 95% → 5/5, 모드를 새 판으로만 바꾸는 경로(MOD_WAIT)는 1/3 → 3/3(5/5로 뛰지 않음)" '[ "$s15" = step=1/5 ] && [ "$s95" = step=5/5 ] && [ "$m15" = step=1/3 ] && [ "$m70" = step=3/3 ]'
check "  리뷰 L6: 진행 기록에 부팅 뒤 초(ust·ut)를 함께 씀" 'grep -q "^ust=" $T/pg.prog && grep -q "^ut=" $T/pg.prog'

check "  요청 파일은 앱 개인 폴더(다른 앱이 쓸 수 없음), 앱과 같은 이름" 'grep -q "^REQ=\${REQ:-/data/data/korea.projection.app/files/report.req}" $PKG/svc/hotspot.sh && grep -q "REQ_NAME = \"report.req\"" $B/nemesis-pkg/app-src/java/korea/projection/app/StatusActivity.java'
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
rm -f $T/w/korea-projection-report.md
: > $T/mounts; SYSAPP=$T/sys/app STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null
check "  1.7.3: USB가 없으면 리포트를 만들지 않음(체크섬도 계산하지 않음, 실패 문구)" '[ ! -f $T/w/korea-projection-report.md ] && grep -qx "state=fail" $RPROG'
echo "/dev/block/sda1 $T/usb0 vfat rw 0 0" > $T/mounts; rm -rf $T/sys

# --- 1.7.3 3단계(K-5·W·G·U): 판정은 한 곳(status.sh kp_verdict). 상태 파일 verdict·verdict_msg와 리포트 "## 판정"이 같다 ---
VR=$T/vr; rm -rf $VR; mkdir -p $VR/mod $VR/hl $VR/bk $VR/w $VR/proc/777
echo "version 1.0.2" > $VR/inst; echo '{"id":"wireless-carplay-aa"}' > $VR/mod/mod.json; echo '{}' > $VR/set.json
printf '%s\n' "01-01 I/HMG-API ( 1): hook map: mapped for Kia Niro Hybrid (kor 260902), hooks on" "01-01 I/HMG-API ( 1): mods: loaded wireless-carplay-aa 2.4.1" > $VR/hl/log.log
echo "777 (dnsmasq) S 1" > $VR/proc/777/stat; echo "777 boot-T" > $VR/dns.pid
VPS="  101 root  hostapd /data/misc/wifi/hostapd-kp.conf"
# vr: 판정 시험용 Launch + [제보 파일 만들기]. 기본은 "준비된 니로"(HMG-API 1.0.2, 모드·훅 켜짐, 우리 핫스팟·DHCP, 무선 기능 있음)
# 기본은 "연결 없음"(빈 /proc/net). 연결이 있는 경우를 볼 때만 VPN=$PROCNET(카플레이 연결 1개)
mkdir -p $VR/pn0; : > $VR/pn0/tcp; : > $VR/pn0/tcp6; : > $VR/pn0/if_inet6
vr() { rm -f $T/usb0/KoreaProjection-report/1-report.md; (SDIO=${VSDIO:-$VR/nosdio} PROCNET=${VPN:-$VR/pn0} HINT=$VR/hint HMGINST=$VR/inst HMGMOD=$VR/mod HMGSET=$VR/set.json HMGLOG=$VR/hl BK=$VR/bk PROG=$VR/prog BOOT_ID=$T/bootid DNSPID=$VR/dns.pid PROC=$VR/proc NOWLAN=$VR/w/nowlan STATUS=$STF BB=$T/bin/bb APP=$T/app SRC=$T/softap.conf W=$VR/w AAOFF=$VR/aaoff HOOKSTARTS=$VR/hstarts KP_DMESG=$VR/kdmesg sh $T/st.sh) >/dev/null 2>&1; }
vkey() { grep "^$1=" $STF | sed "s/^$1=//"; }
vrep() { grep "^- 판정: " $T/usb0/KoreaProjection-report/1-report.md; }
vsame() { [ "$(vrep)" = "- 판정: $(vkey verdict) (수준 $(vkey verdict_lv)) $(vkey verdict_msg)" ]; }
cp $T/ps $T/ps.vr 2>/dev/null; [ -f $T/feat ] && FEATVR=1 || FEATVR=0
touch $T/feat; echo "$VPS" > $T/ps; rm -f $VR/prog
VPN=$PROCNET; vr; VPN=
check "1.7.3 K-5: 준비된 니로(연결 1대) → verdict=connected, 수준 0, 리포트 '## 판정' 줄이 상태 파일과 같음, 요약 3줄" '[ "$(vkey verdict)" = connected ] && [ "$(vkey verdict_lv)" = 0 ] && vsame && [ "$(vkey s1)" = "설치: 끝남" ] && [ "$(vkey s2)" = "무선 Wi-Fi: 켜짐" ] && [ "$(vkey s3)" = "폰 연결: 카플레이 1대 연결됨" ]'
# wlan0이 없는 네 가지(설치 중·Wi-Fi 꺼짐·부품 없음·칩 실패)는 각각 다른 문구(로드맵 완료 기준)
: > $T/ps; printf 'pct=40\nstate=run\nstage=x\nt=1\nboot=boot-T\n' > $VR/prog; vr; m1=$(vkey verdict_msg); c1=$(vkey verdict)
rm -f $VR/prog; cat $T/bootid > $VR/w/nowlan; vr; m2=$(vkey verdict_msg); c2=$(vkey verdict); rm -f $VR/w/nowlan
# 부품 없음·칩 실패는 모드가 없고 칩이 안 보일 때만(리뷰 H-1)
mv $VR/mod/mod.json $VR/mod.json.keep
: > $VR/bk/wifi.nopart; vr; m3=$(vkey verdict_msg); c3=$(vkey verdict); e3=$(vkey verdict_end); rm -f $VR/bk/wifi.nopart
: > $VR/bk/wifi.nochip; vr; m4=$(vkey verdict_msg); c4=$(vkey verdict); e4=$(vkey verdict_end); s24=$(vkey s2); rm -f $VR/bk/wifi.nochip
mv $VR/mod.json.keep $VR/mod/mod.json
check "1.7.3 G-1·W: wlan0 없는 네 가지가 각각 다른 판정·문구(설치 중 / Wi-Fi 켜는 중 / 부품 없음 / 칩 실패)" '[ "$c1 $c2 $c3 $c4" = "installing wifioff nopart nochip" ] && [ "$m1" = "설치 중입니다. 끝날 때까지 기다려 주세요." ] && [ "$m2" = "Wi-Fi를 켜는 중입니다(재부팅 뒤 한 번 더 확인). 내비를 재부팅해 주세요. (확인 1/3)" ] && [ "$m3" = "이 차의 내비에는 Wi-Fi 부품이 없어 무선 카플레이를 쓸 수 없습니다. USB Wi-Fi 동글로 쓰는 방법을 준비하고 있습니다." ] && [ "$m4" = "이 차는 Wi-Fi 칩이 켜지지 않아 지원하기 어렵습니다. USB Wi-Fi 동글로 쓰는 방법을 준비하고 있습니다." ]'
check "  부품 없음·칩 실패는 '안 됨'으로 끝남(verdict_end=yes: 앱이 지우는 법 한 줄을 보임, U-6), 요약 Wi-Fi 줄" '[ "$e3 $e4" = "yes yes" ] && [ "$s24" = "무선 Wi-Fi: 칩이 켜지지 않음" ]'
# G-1·W-4: 설치에서 칩 깨우기 확인 중(모드 아직 없음)
rm -f $VR/mod/mod.json; echo "1 boot-T" > $VR/bk/wifi.wake; vr
check "1.7.3 G-1: 칩 깨우기 확인 중(모드 없음, 깨우기 1번째) → wificheck, 문구에 확인 횟수(1/3), 요약 '설치: 재부팅 필요'" '[ "$(vkey verdict)" = wificheck ] && [ "$(vkey verdict_msg)" = "Wi-Fi를 켜는 중입니다(재부팅 뒤 한 번 더 확인). 내비를 재부팅해 주세요. (확인 1/3)" ] && [ "$(vkey s1)" = "설치: 재부팅 필요" ] && vsame'
: > $VR/bk/wifi.woke; vr; c_woke=$(vkey verdict); rm -f $VR/bk/wifi.woke
echo "3 boot-T" > $VR/bk/wifi.wake; vr; c_used=$(vkey verdict); echo "1 boot-T" > $VR/bk/wifi.wake
: > $VR/bk/mod.tried; vr; c_tried=$(vkey verdict)
check "1.7.3 재리뷰 중간 1: 칩을 한 번 본 차(wifi.woke)·횟수를 다 쓴 차·모드를 지운 차(mod.tried)는 '확인 중'이 아니라 원래 판정" '[ "$c_woke" = nomod ] && [ "$c_used" = nomod ] && [ "$c_tried" = modgone ]'
rm -f $VR/bk/wifi.wake; vr
check "1.7.3 G-2②: 모드를 지운 기록이 있으면 '지운 기록' 문구, 넣지 못한 차는 다른 문구" '[ "$(vkey verdict)" = modgone ] && grep -q "^verdict_msg=무선 모드를 지운 기록이 있어 다시 넣지 않습니다" $STF'
rm -f $VR/bk/mod.tried; vr
check "  기록이 없으면 '넣지 못했습니다'(제보 안내)" '[ "$(vkey verdict)" = nomod ] && grep -q "^verdict_msg=무선 모드를 넣지 못했습니다" $STF'
echo '{"id":"wireless-carplay-aa"}' > $VR/mod/mod.json
# U-8: 재부팅 필요 → 남은 횟수
echo "$VPS" > $T/ps; printf 'pct=100\nstate=reboot\nstage=무선 카플레이 설정을 마쳤습니다. 내비를 재부팅해 주세요(RESET 버튼 또는 NEMESIS 재부팅).\nt=1\nboot=boot-T\n' > $VR/prog; vr
check "1.7.3 U-8: 재부팅 필요면 진행 기록의 첫 문장 + '내비를 재부팅해 주세요(재부팅 1번이면 끝납니다).'(재리뷰 L-5: 두 문장)" '[ "$(vkey verdict)" = reboot ] && [ "$(vkey verdict_msg)" = "무선 카플레이 설정을 마쳤습니다. 내비를 재부팅해 주세요(재부팅 1번이면 끝납니다)." ]'
# H-1: HMG-API 적용 거절(계획 problem 줄) → 안내와 리포트의 문제 줄(숫자·경로만)
printf 'pct=100\nstate=fail\nstage=x\nt=1\nboot=boot-T\n' > $VR/prog; printf '%s\n' "nothing changed: 1 problem(s)" "problem  /system/etc/permissions/com.hkmc.software.connectivity.carplay_wireless.xml [wireless-carplay-aa] already on the head unit, but 홍길동 add it" > $VR/w/plan.txt
echo "boot-T 20" > $VR/w/svc.start; touch -t 202601010000 $VR/w/svc.start; vr
check "1.7.3 H-1: 계획에 problem 줄이 있는 실패 → HMG-API 거절 안내, 리포트에 problem 줄(영문·경로만, 다른 글자는 뺌)" '[ "$(vkey verdict)" = hmgrefuse ] && grep -q "^verdict_msg=HMG-API가 적용을 거절했습니다. HMG-API 앱의 .Can.t apply. 창 아래쪽을 확인해 주세요." $STF && grep -q "^## HMG-API 계획의 문제 줄" $T/usb0/KoreaProjection-report/1-report.md && grep -q "^problem  /system/etc/permissions/com.hkmc.software.connectivity.carplay_wireless.xml \[wireless-carplay-aa\] already on the head unit, but  add it$" $T/usb0/KoreaProjection-report/1-report.md && ! grep -q 홍길동 $T/usb0/KoreaProjection-report/1-report.md'
touch -t 202601010000 $VR/w/plan.txt; touch $VR/w/svc.start; vr
check "  리뷰 L-2: plan.txt가 이번 부팅 서비스 시작보다 옛것이면(지난 부팅 기록) 거절 판정을 하지 않음" '[ "$(vkey verdict)" = failed ]'
rm -f $VR/prog $VR/w/plan.txt $VR/w/svc.start
# 리뷰 H-1: 부품 없음·칩 실패 기록이 있어도 지금 칩이 보이고 연결되면(다른 앱으로 Wi-Fi를 켠 1.7.2 차) connected
echo "$VPS" > $T/ps; : > $VR/bk/wifi.nochip; mkdir -p $VR/sdio/mmc1:0001:1; VSDIO=$VR/sdio; VPN=$PROCNET; vr
check "1.7.3 리뷰 H-1: 칩 실패 기록이 있어도 칩이 보이고 연결 중이면 connected(빨강 '지원하기 어렵습니다' 아님)" '[ "$(vkey verdict)" = connected ] && grep -qx "verdict_end=no" $STF'
: > $VR/bk/wifi.nopart; vr
check "  부품 없음 기록도 같음(칩이 보이면 nopart 아님)" '[ "$(vkey verdict)" = connected ]'
VSDIO=; rm -rf $VR/sdio; vr
check "  칩이 안 보여도 모드가 이미 있으면 nopart·nochip으로 보지 않음" '[ "$(vkey verdict)" = connected ]'
rm -f $VR/bk/wifi.nochip $VR/bk/wifi.nopart; VPN=
# 리뷰 H-2: "다른 Wi-Fi 패키지"는 netd가 띄우지 않은 hostapd가 실제로 돌고, 우리 AP·연결이 없을 때만
mkdir -p $VR/proc/888 $VR/proc/60 $VR/pn; echo "60 (netd) S 1" > $VR/proc/60/stat; : > $VR/pn/tcp; : > $VR/pn/tcp6; : > $VR/pn/if_inet6; rm -f $VR/dns.pid
echo "  888 wifi  /system/bin/hostapd /data/misc/wifi/hostapd.conf" > $T/ps; echo "888 (hostapd) S 60" > $VR/proc/888/stat; VPN=$VR/pn; vr
check "1.7.3 리뷰 H-2: 순정(netd가 띄운) hostapd인데 설정을 못 읽어 stock_ssid=unknown이어도 otherwifi가 아님" '[ "$(vkey stock_ssid)" = unknown ] && [ "$(vkey verdict)" != otherwifi ]'
echo "888 (hostapd) S 1" > $VR/proc/888/stat; mkdir -p $VR/proc/1; echo "1 (init) S 0" > $VR/proc/1/stat; vr
check "  netd가 띄우지 않은 hostapd가 돌고 우리 AP·연결이 없으면 otherwifi, 지우는 법 줄은 붙이지 않음(verdict_end=no)" '[ "$(vkey verdict)" = otherwifi ] && grep -qx "verdict_end=no" $STF'
VPN=$PROCNET; vr; VPN=
check "  그 hostapd가 돌아도 카플레이가 연결 중이면 otherwifi가 아님" '[ "$(vkey verdict)" != otherwifi ]'
rm -rf $VR/proc/888 $VR/proc/1 $VR/pn; echo "777 boot-T" > $VR/dns.pid
# 리뷰 M-3: 모드가 있는데 wlan0이 3번 넘는 부팅 동안 안 생기면 칩 실패, 그 전은 확인 중(횟수)
: > $T/ps; cat $T/bootid > $VR/w/nowlan; echo "2 boot-T" > $VR/bk/nowlan.boots; vr
check "1.7.3 리뷰 M-3: wlan0이 2번째 부팅까지 안 생기면 '확인 중(확인 2/3)'" '[ "$(vkey verdict)" = wifioff ] && grep -q "^verdict_msg=Wi-Fi를 켜는 중입니다.*(확인 2/3)$" $STF'
echo "3 boot-T" > $VR/bk/nowlan.boots; vr
check "  재리뷰 중간 3②: 3번째 부팅에도 안 생기지만 칩 실패 근거가 없으면 제보 부탁(수준 2, 지우는 법 없음)" '[ "$(vkey verdict)" = nowlanrepeat ] && grep -qx "verdict_msg=Wi-Fi 장치가 계속 켜지지 않습니다. 재부팅해도 같으면 USB를 꽂고 \[제보 파일 만들기\]로 알려 주세요." $STF && grep -qx "verdict_end=no" $STF && [ "$(vkey verdict_lv)" = 2 ]'
echo "[  12.3] bcmsdh_sdmmc: si_attach failed!" > $VR/bk/nochip-wifi.txt; vr; vrep_l5=$(grep "^- Wi-Fi 부품 없음 기록" $T/usb0/KoreaProjection-report/1-report.md); rm -f $VR/bk/nochip-wifi.txt
check "  근거(커널 칩 실패 줄 si_attach failed)가 있으면 칩 실패(W-2·W-6 문구, 안 됨으로 끝남)" '[ "$(vkey verdict)" = nowlanfail ] && grep -q "^verdict_msg=이 차는 Wi-Fi 칩이 켜지지 않아" $STF && grep -qx "verdict_end=yes" $STF'
echo 3 > $VR/bk/wifi.modver; vr; rm -f $VR/bk/wifi.modver
check "  근거(module_version 기록 3)여도 칩 실패" '[ "$(vkey verdict)" = nowlanfail ]'
VPN=$PROCNET; vr; VPN=
check "  재리뷰 L-3: 폰이 연결 중이면 wlan0·핫스팟 꺼짐 판정을 내지 않음(연결 판정이 앞섬)" '[ "$(vkey verdict)" = connected ]'
check "  리뷰 L-5: 리포트에 부품 없음·깨우기 횟수·module_version 기록·wlan0 안 생긴 부팅 수 한 줄" '[ "$vrep_l5" = "- Wi-Fi 부품 없음 기록(wifi.nopart): 아니요, 칩 깨우기 횟수(wifi.wake): 0/3, 순정 module_version 기록: 없음, wlan0 안 생긴 부팅 수: 3" ]'
rm -f $VR/w/nowlan $VR/bk/nowlan.boots; echo "$VPS" > $T/ps
# 리뷰 L-6: 무선 안드로이드 오토만 연결돼도 연결로 봄
printf 'boot=boot-T\naa=ok\naa_t=1\n' > $VR/hint; mkdir -p $VR/pn; : > $VR/pn/tcp; : > $VR/pn/tcp6; : > $VR/pn/if_inet6; VPN=$VR/pn; vr
check "1.7.3 리뷰 L-6·베타 1: 카플레이 연결 없이 무선 AA만 연결(이번 부팅 aa=ok)이면 connected '무선 안드로이드 오토 연결됨, 카플레이 준비됨', 요약 줄도" '[ "$(vkey verdict)" = connected ] && grep -qx "verdict_msg=무선 안드로이드 오토 연결됨, 카플레이 준비됨" $STF && grep -qx "s3=폰 연결: 무선 안드로이드 오토 연결됨" $STF'
printf 'boot=boot-OLD\naa=ok\naa_t=1\n' > $VR/hint; vr
check "  지난 부팅의 aa=ok는 연결로 보지 않음" '[ "$(vkey verdict)" != connected ]'
VPN=; rm -rf $VR/pn $VR/hint
# 베타 1(소유자 요청): 카플레이와 무선 안드로이드 오토를 한 줄로. 상태 파일·리포트 판정 줄이 같은 문구
RV=$T/usb0/KoreaProjection-report/1-report.md
rm -f $VR/aaoff; printf 'boot=boot-T\naa_ready=1700000000\naa=\naa_t=\n' > $VR/hint; vr
check "베타 1: 준비됨 + AA 신호 켜짐 → '무선 카플레이·안드로이드 오토 준비됨…' 한 줄, 리포트 판정 줄도 같은 문구" '[ "$(vkey verdict)" = ready ] && grep -qx "verdict_msg=무선 카플레이·안드로이드 오토 준비됨. 아이폰은 설정 → 일반 → CarPlay, 안드로이드는 블루투스 연결 뒤 '"'"'무선 Android Auto 사용'"'"'을 누르세요." $STF && grep -q "^- 판정: ready (수준 0) 무선 카플레이·안드로이드 오토 준비됨. 아이폰은" $RV'
rm -f $VR/hint; vr
check "  베타 1: AA를 켠 차인데 신호가 아직(aa_ready 없음) → '무선 카플레이 준비됨(안드로이드 오토는 준비 중)'" '[ "$(vkey verdict)" = ready ] && grep -q "^verdict_msg=무선 카플레이 준비됨(안드로이드 오토는 준비 중). 아이폰은" $STF'
printf 'boot=boot-T\naa_ready=1700000000\naa=\naa_t=\n' > $VR/hint; : > $VR/aaoff; vr
check "  베타 1: AA를 끈 차는 신호 기록이 남아도 '무선 카플레이 준비됨'만" '[ "$(vkey verdict)" = ready ] && grep -q "^verdict_msg=무선 카플레이 준비됨. 아이폰은 설정 → 일반 → CarPlay에서 연결하세요.$" $STF'
VPN=$PROCNET; vr
check "  베타 1: AA를 끈 차에 카플레이 연결 → '무선 카플레이 연결됨'" '[ "$(vkey verdict)" = connected ] && grep -qx "verdict_msg=무선 카플레이 연결됨" $STF'
rm -f $VR/aaoff; vr
check "  베타 1: 카플레이 연결 + AA 신호 켜짐 → '무선 카플레이 연결됨, 안드로이드 오토 준비됨', 리포트 판정 줄도" '[ "$(vkey verdict)" = connected ] && grep -qx "verdict_msg=무선 카플레이 연결됨, 안드로이드 오토 준비됨" $STF && grep -q "^- 판정: connected (수준 0) 무선 카플레이 연결됨, 안드로이드 오토 준비됨$" $RV'
printf 'boot=boot-T\naa_ready=1700000000\naa=ok\naa_t=1\n' > $VR/hint; vr
check "  베타 1: 카플레이와 AA가 둘 다 연결 → '무선 카플레이·안드로이드 오토 연결됨'" '[ "$(vkey verdict)" = connected ] && grep -qx "verdict_msg=무선 카플레이·안드로이드 오토 연결됨" $STF'
printf 'boot=boot-OLD\naa_ready=1700000000\naa=\naa_t=\n' > $VR/hint; vr
check "  베타 1: 지난 부팅의 AA 신호 기록은 준비됨으로 보지 않음" '[ "$(vkey verdict)" = connected ] && grep -qx "verdict_msg=무선 카플레이 연결됨" $STF'
VPN=; rm -f $VR/hint $VR/aaoff
# 베타 1 리뷰 4·5
printf 'boot=boot-T\naa_ready=1700000000\naa=ok\naa_t=1\n' > $VR/hint; : > $VR/aaoff; vr
check "베타 1 리뷰 4: AA를 끈 차에 aa=ok가 남아 있어도 AA 연결로 보지 않음(카플레이 준비됨)" '[ "$(vkey verdict)" = ready ] && grep -qx "verdict_msg=무선 카플레이 준비됨. 아이폰은 설정 → 일반 → CarPlay에서 연결하세요." $STF'
rm -f $VR/aaoff; printf 'boot=boot-T\naa_ready=1700000000\naa=cpwait\naa_t=1\n' > $VR/hint; VPN=$PROCNET; vr; VPN=
check "베타 1 리뷰 5: 카플레이 연결 중 AA가 기다리는 중(aa=cpwait)이면 'AA 준비됨'이라 하지 않고 '무선 카플레이 연결됨'만" '[ "$(vkey verdict)" = connected ] && grep -qx "verdict_msg=무선 카플레이 연결됨" $STF'
check "  베타 1 리뷰 4: AA만 연결일 때 '카플레이 준비됨'은 우리 핫스팟이 켜져 있을 때만(소스)" 'grep -q "elif \[ \"\$K_OURAP\" = yes \]; then _vs connected 0 \"무선 안드로이드 오토 연결됨, 카플레이 준비됨\"" $PKG/bin/status.sh && grep -q "else _vs connected 0 \"무선 안드로이드 오토 연결됨\"; fi" $PKG/bin/status.sh'
rm -f $VR/hint
# 베타 2 #64: HMG-API 부팅 보호(boot guard). starts(올린 뒤 값) 4 이상이면 이번 부팅 훅 꺼짐. 커널 로그 줄은 보조 근거. starts를 못 읽으면 판정 안 함
RV=$T/usb0/KoreaProjection-report/1-report.md
# 10장 확인 리뷰 2: 훅이 켜질 수 있는 차(hook/enable 있음, HOOKDIR = starts 파일 폴더 = $VR)
: > $VR/enable
echo 4 > $VR/hstarts; printf '%s\n' "<6>[    3.0] hmgapi-hook: zygote, hooks off (boot guard, starts=3), hmgapid" > $VR/kdmesg; vr
check "베타 2 #64: starts=4·커널 로그 boot guard → 판정 bootguard(수준 2), '지우지 말고 다시 설치(업데이트)' 안내, 요약 줄, QR 판정 코드" '[ "$(vkey verdict)" = bootguard ] && [ "$(vkey verdict_lv)" = 2 ] && grep -qx "verdict_msg=HMG-API가 재부팅이 너무 잦은 것으로 보고 무선 기능을 껐습니다. HMG-API를 지우지 말고 NEMESIS에서 다시 설치(업데이트)한 뒤 재부팅하고, 2분 넘게 켜 두세요." $STF && grep -qx "s1=설치: HMG-API 훅 꺼짐(부팅 보호)" $STF'
check "  베타 2 #64: 리포트 판정 줄과 '부팅 보호: starts=4(3 이상이면 다음 부팅 훅 꺼짐), 이번 부팅 boot guard 줄 있음', 훅 줄에 '이번 부팅 기록 없음'" 'grep -q "^- 판정: bootguard (수준 2) HMG-API가 재부팅이 너무 잦은" $RV && grep -qx "\- HMG-API 부팅 보호: starts=4(3 이상이면 다음 부팅 훅 꺼짐), 이번 부팅 boot guard 줄 있음" $RV && grep -q "^- 무선 모드 훅(마지막 부팅 기록): .*(이번 부팅 기록 없음: 이번 부팅은 부팅 보호로 훅 꺼짐)$" $RV && grep -q "^- HMG-API 훅(마지막 부팅 기록): .*(이번 부팅 기록 없음: 이번 부팅은 부팅 보호로 훅 꺼짐)$" $RV'
echo 3 > $VR/hstarts; printf '%s\n' "<6>[    3.0] hmgapi-hook: zygote, hooks on, start 3, hmgapid" > $VR/kdmesg; vr
check "  베타 2 #64: starts=3(훅이 켜진 3번째 시작)이면 부팅 보호 판정 아님, 훅 줄에 '이번 부팅 훅 켜짐', boot guard 줄 없음" '[ "$(vkey verdict)" != bootguard ] && grep -q "^- HMG-API 훅(마지막 부팅 기록): .*(이번 부팅 훅 켜짐)$" $RV && grep -qx "\- HMG-API 부팅 보호: starts=3(3 이상이면 다음 부팅 훅 꺼짐), 이번 부팅 boot guard 줄 없음" $RV'
echo 2 > $VR/hstarts; printf '%s\n' "<6>[    3.0] hmgapi-hook: zygote, hooks off (boot guard, starts=5), hmgapid" > $VR/kdmesg; vr
check "  베타 2 #64·리뷰 L1: 이번 부팅 커널 로그가 boot guard인데 starts가 4보다 작으면(그 사이 HMG-API 다시 설치) 재부팅만 안내(수준 1)" '[ "$(vkey verdict)" = bootguard ] && [ "$(vkey verdict_lv)" = 1 ] && grep -qx "verdict_msg=HMG-API를 다시 설치한 것으로 보입니다. 내비를 재부팅하고 2분 넘게 켜 두세요." $STF'
rm -f $VR/hstarts; vr
check "  리뷰 M2: 이번 부팅 커널 로그에 boot guard 줄이 있으면 starts를 못 읽어도 부팅 보호(커널 줄을 따름), 리포트에 '읽지 못함'" '[ "$(vkey verdict)" = bootguard ] && [ "$(vkey verdict_lv)" = 2 ] && grep -q "^- HMG-API 부팅 보호: starts=읽지 못함" $RV'
: > $VR/kdmesg; vr
check "  베타 2 #64: starts 파일도 커널 줄도 없으면 판정하지 않음" '[ "$(vkey verdict)" != bootguard ]'
# 리뷰 M2: zygote가 같은 부팅에 다시 시작한 순서(마지막 줄을 따름), disable로 끈 차, HMG-API를 지운 차의 남은 starts
echo 4 > $VR/hstarts; printf '%s\n' "<6>[    3.0] hmgapi-hook: zygote, hooks on, start 3, hmgapid" "<6>[  200.0] hmgapi-hook: zygote, hooks off (boot guard, starts=3), hmgapid" > $VR/kdmesg; vr
check "  리뷰 M2: zygote 재시작 on → guard(마지막이 guard)면 부팅 보호" '[ "$(vkey verdict)" = bootguard ]'
echo 1 > $VR/hstarts; printf '%s\n' "<6>[    3.0] hmgapi-hook: zygote, hooks off (boot guard, starts=4), hmgapid" "<6>[  300.0] hmgapi-hook: zygote, hooks on, start 1, hmgapid" > $VR/kdmesg; vr
check "  리뷰 M2: zygote 재시작 guard → on(마지막이 on)이면 부팅 보호 아님, 훅 줄에 '이번 부팅 훅 켜짐'" '[ "$(vkey verdict)" != bootguard ] && grep -q "^- HMG-API 훅(마지막 부팅 기록): .*(이번 부팅 훅 켜짐)$" $RV'
echo 7 > $VR/hstarts; printf '%s\n' "<6>[    3.0] hmgapi-hook: zygote, hooks off (disable file), hmgapid" > $VR/kdmesg; vr
check "  리뷰 M2: disable 파일로 훅을 끈 차(커널 줄 'hooks off (disable file)')는 starts가 높아도 부팅 보호 아님" '[ "$(vkey verdict)" != bootguard ]'
: > $VR/kdmesg; printf 4 > $VR/hstarts; vr
check "  리뷰 M2·확인 리뷰 4: 커널 줄이 없으면 starts≥4로 판정(예전 기준, 줄바꿈 없이 쓴 starts도 읽음)" '[ "$(vkey verdict)" = bootguard ]'
: > $VR/disable; vr; rm -f $VR/disable
check "  확인 리뷰 2: 커널 줄이 없어도 hook/disable이 있으면 starts≥4로 판정하지 않음" '[ "$(vkey verdict)" != bootguard ]'
rm -f $VR/enable; vr; : > $VR/enable
check "  확인 리뷰 2: 커널 줄이 없고 hook/enable이 없으면(훅을 켠 적 없음) starts≥4로 판정하지 않음" '[ "$(vkey verdict)" != bootguard ]'
echo 4 > $VR/hstarts
: > $VR/inst; vr; echo "version 1.0.2" > $VR/inst
check "  리뷰 M2: HMG-API를 지운 차(설치 기록 없음)는 남은 starts가 4 이상이어도 부팅 보호가 아니라 'HMG-API가 없습니다'" '[ "$(vkey verdict)" = nohmgapi ]'
echo 5 > $VR/hstarts; VPN=$PROCNET; vr; VPN=
check "  베타 2 #64: 카플레이가 연결돼 있으면 부팅 보호보다 연결 판정이 앞섬" '[ "$(vkey verdict)" = connected ]'
rm -f $VR/hstarts; : > $VR/kdmesg; vr
check "  베타 2 #64: 커널 로그에 HMG-API 줄이 없으면 훅 줄에 '이번 부팅인지 모름'" 'grep -q "^- HMG-API 훅(마지막 부팅 기록): .*(이번 부팅인지 모름: 커널 로그에 줄 없음)$" $RV'
rm -f $VR/hstarts $VR/kdmesg $VR/enable
rm -f $VR/prog $VR/w/plan.txt
# G-4: README ✅ 차종인데 문제(핫스팟 꺼짐) → 먼저 할 일. 내비 버전이 옛것이면 업데이트를 맨 앞에
: > $T/ps; rm -f $VR/dns.pid; vr
check "1.7.3 G-4: ✅ 차(니로 260902)인데 핫스팟 꺼짐 → '먼저 할 일: 같은 차에서 된 분이 있습니다'" '[ "$(vkey verdict)" = apoff ] && grep -q "^first=먼저 할 일: 같은 차에서 된 분이 있습니다" $STF && grep -q "^- 먼저 할 일: 같은 차에서 된 분이 있습니다" $T/usb0/KoreaProjection-report/1-report.md'
echo DEPEHEV.KOR.0000.V039.001.260601 > $T/product; vr
check "  내비 버전이 260902보다 옛것(260601)이면 '내비를 업데이트한 뒤 다시 설치'가 먼저" 'grep -q "^first=먼저 할 일: 내비 버전이 확인된 차(260902)보다 옛것입니다. 내비를 업데이트한 뒤 NEMESIS·HMG-API·Korea Projection을 다시 설치해 주세요." $STF'
rm -f $T/product; : > $VR/bk/wifi.nopart; mv $VR/mod/mod.json $VR/mod.json.keep; vr; rm -f $VR/bk/wifi.nopart; mv $VR/mod.json.keep $VR/mod/mod.json
check "  근거 있는 '부품 없음'이면 먼저 할 일을 보이지 않음(부품 없음 안내가 앞섬)" '[ "$(vkey verdict)" = nopart ] && grep -qx "first=" $STF'
: > $VR/inst; vr; echo "version 1.0.2" > $VR/inst
check "  리뷰 L-1: 원인이 분명한 판정(HMG-API 없음 등)에는 먼저 할 일을 붙이지 않음" '[ "$(vkey verdict)" = nohmgapi ] && grep -qx "first=" $STF'
# U-10: 확인 안 된 한국 차(README ✅ 아님)가 연결되면 제보 부탁
echo "$VPS" > $T/ps; echo "777 boot-T" > $VR/dns.pid; echo TESTX.KOR.0000.V001.001.260902 > $T/product; VPN=$PROCNET; vr; VPN=; rm -f $T/product
check "1.7.3 U-10: 확인 안 된 차가 연결되면 newconnected, '연결됐습니다! QR로 ...지원 목록에 올립니다.'(수준 0)" '[ "$(vkey verdict)" = newconnected ] && [ "$(vkey verdict_lv)" = 0 ] && grep -q "^verdict_msg=연결됐습니다! QR로 .연결됨.을 알려 주시면 지원 목록에 올립니다." $STF'
# 리뷰 M-5: 공개 README 지원 표의 ✅ 차종 코드와 CARS_SEEN이 같음(README가 바뀌면 같이 알아채게)
RMC=$(grep '✅' $B/../public/README.md 2>/dev/null | grep -o '`[A-Z0-9]*`' | tr -d '`' | sort -u | tr '\n' ' ')
CSC=$(sed -n "s/^CARS_SEEN='\(.*\)'$/\1/p" $PKG/svc/hotspot.sh | tr ' ' '\n' | sed 's/\..*//' | sort -u | tr '\n' ' ')
check "1.7.3 리뷰 M-5: README ✅ 차종 코드와 CARS_SEEN이 같음(30종)" '[ -n "$RMC" ] && [ "$RMC" = "$CSC" ] && [ "$(echo $RMC | wc -w | tr -d " ")" = 30 ]'
check "  K-5: modhooks·hooks는 HMG-API 로그를 한 번만 읽은 값(hmg_hooks_load)을 씀, 판정 함수는 하나(kp_verdict)" 'grep -qx "modhooks_state() { hmg_hooks_load; echo \"\$_MH\"; }" $PKG/bin/status.sh && grep -qx "hooks_state() { hmg_hooks_load; echo \"\$_HK\"; }" $PKG/bin/status.sh && [ "$(grep -c "^kp_verdict() {" $PKG/bin/status.sh)" = 1 ]'
[ $FEATVR = 1 ] || rm -f $T/feat; mv $T/ps.vr $T/ps 2>/dev/null; rm -rf $VR
# --- 2b. Launch가 뒤에서 HMG-API Car Report를 USB에 저장 (지원 목록에 없거나 훅이 꺼진 차) ---
CR=$T/cr; mkdir -p $CR/bin $CR/w
cat > $CR/bin/hmgapid <<E
#!/bin/sh
echo "hmgapid \$*" >> $CR/calls
[ -f $CR/slow ] && /bin/sleep 3
[ -f $CR/fail ] && { echo "error"; exit 1; }
echo "report: kia-niro-20261106"; echo "usb: /storage/usb0/HMG-API reports/kia-niro-20261106.json"; exit 0
E
# 가짜 busybox: setsid는 건너뛰고, 스크립트가 PATH를 헤드유닛 경로로 바꿔도 맥 명령을 찾게 한다
printf '#!/bin/sh\n[ "$1" = setsid ] && shift\nPATH=/usr/bin:/bin:$PATH exec "$@"\n' > $CR/bin/bbs
chmod +x $CR/bin/*
echo "/dev/block/sda1 /storage/usb0 vfat rw 0 0" > $CR/mounts
cr() { (PATH=$CR/bin:/usr/bin:/bin BB=$T/bin/bb W=$CR/w CR_WAIT=0.2 CR_MAX=${CRMAX:-50} CR_GRACE=0 MOUNTS=$CR/mounts BOOT_ID=$CR/boot sh -c 'sed "s#^export PATH=.*#export PATH='$CR'/bin:/usr/bin:/bin#" '$T'/app/bin/carreport.sh > '$CR'/cr.sh; sh '$CR'/cr.sh'); }
echo b1 > $CR/boot
rm -f $CR/calls $RPROG; cr
check "Car Report: hmgapid engine report --usb 실행 → 진행 기록 완료(이제 USB를 빼셔도 됩니다, am 호출 없음), 잠금 해제" 'grep -qx "hmgapid engine report --usb" $CR/calls && grep -qx "state=done" $RPROG && grep -q "이제 USB를 빼셔도" $RPROG && ! grep -q -E "(^|[;&|] *)am " $PKG/bin/carreport.sh && [ ! -d $CR/w/carreport.lock ]'
: > $CR/mounts; rm -f $RPROG; cr; echo "/dev/block/sda1 /storage/usb0 vfat rw 0 0" > $CR/mounts
check "  USB가 실제로 마운트돼 있지 않으면(빈 마운트 폴더에 씀) 성공으로 보지 않음" 'grep -qx "state=fail" $RPROG && grep -q "저장하지 못했습니다" $RPROG'
# 마지막 묶음 L4: Car Report 저장 중 TERM(삭제·업데이트)을 받으면 뒤의 hmgapid engine report도 멈추고 잠금을 푼다
touch $CR/slow; rm -f $RPROG; rm -rf $CR/w/carreport.lock; (cr) & CRB=$!
_k=0; while [ ! -s $CR/w/carreport.lock/pid ] && [ $_k -lt 40 ]; do /bin/sleep 0.1; _k=$((_k+1)); done; /bin/sleep 0.4
CRP=; read CRP _x < $CR/w/carreport.lock/pid; [ -n "$CRP" ] && kill -TERM $CRP 2>/dev/null; wait $CRB 2>/dev/null; /bin/sleep 0.3
check "  마지막 묶음 L4: 저장 중 TERM → 잠금(carreport.lock)을 풀고 hmgapid engine report도 멈춤" '[ -n "$CRP" ] && [ ! -d $CR/w/carreport.lock ] && ! ps -ax -o command | grep -v grep | grep -q "$CR/bin/hmgapid engine report"'
rm -f $CR/slow
# 제보 폴더로 복사: USBROOT를 가짜 폴더로 돌려 실제 파일 복사를 본다
mkdir -p "$CR/st/usb0/HMG-API reports"; echo '{"report": "hmgapi car report 1"}' > "$CR/st/usb0/HMG-API reports/kia-niro-20261106.json"
sed -e "s#/storage/usb0/HMG-API#$CR/st/usb0/HMG-API#" $CR/bin/hmgapid > $CR/hm2; cp $CR/bin/hmgapid $CR/hm1; cp $CR/hm2 $CR/bin/hmgapid; chmod +x $CR/bin/hmgapid
echo "/dev/block/sda1 $CR/st/usb0 vfat rw 0 0" > $CR/mounts; rm -f $RPROG
(PATH=$CR/bin:/usr/bin:/bin BB=$T/bin/bb W=$CR/w CR_WAIT=0.2 CR_MAX=50 CR_GRACE=0 MOUNTS=$CR/mounts BOOT_ID=$CR/boot USBROOT=$CR/st sh $CR/cr.sh)
check "  Car Report를 제보 폴더에 2-car-report.json으로도 복사, 진행 기록 문구에 폴더 이름" 'cmp -s "$CR/st/usb0/HMG-API reports/kia-niro-20261106.json" $CR/st/usb0/KoreaProjection-report/2-car-report.json && grep -q "USB의 KoreaProjection-report 폴더)" $RPROG'
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
check "제보 파일 만들기(1.7.0, 1.7.3부터 버튼 요청): 확인된 차이고 훅이 켜져 있어도 Car Report를 만듦(파일 3개, #41)" '[ -f $T/w/carreport.txt ]'
printf '%s\n' "01-01 18:30:04.740 I/HMG-API (  148): hook map: none for Kia Niro, hooks off (no map)" > $T/hl/log.log
# 1.7.0: 앞 Launch도 Car Report를 뒤에서 만든다. 그것이 끝나며 쓰는 기록이 이번 확인과 섞이지 않게 끝날 때까지 기다린다
i=0; while [ -d $T/w/carreport.lock ] && [ $i -lt 50 ]; do /bin/sleep 0.2; i=$((i+1)); done; /bin/sleep 0.5; rm -f $T/w/carreport.txt $T/notice
PATH=$CR/bin:$PATH HMGLOG=$T/hl STATUS=$STF BB=$CR/bin/bbs APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh > $T/st17.out 2>/dev/null
i=0; while [ ! -f $T/w/carreport.txt ] && [ $i -lt 30 ]; do /bin/sleep 0.2; i=$((i+1)); done
check "  훅이 꺼져 있어도 요청으로 Car Report를 만듦, Launch 요약은 상태 문구만(1.7.3 R-1: '저장하는 중' 없음)" '[ -f $T/w/carreport.txt ] && ! grep -q "저장하는 중" $T/st17.out && grep -q "카플레이 연결" $T/st17.out'
: > $T/mounts; rm -f $T/w/carreport.txt
PATH=$CR/bin:$PATH HMGLOG=$T/hl STATUS=$STF BB=$CR/bin/bbs APP=$T/app SRC=$T/softap.conf W=$T/w sh $T/st.sh >/dev/null 2>&1
/bin/sleep 1
check "  USB가 없으면 만들지 않음" '[ ! -f $T/w/carreport.txt ]'
echo "/dev/block/sda1 $T/usb0 vfat rw 0 0" > $T/mounts; rm -rf $T/hl

# 4b K-11(2026-11-10): 은퇴한 USB 시험 도구(kp-test.sh·kp-update-test.sh, D-14로 archive/old-tools/scripts/)의 시험은 tests/legacy/legacy-test.sh에 있다.

# --- 1.5.4: busybox가 없는 내비(K3 #15), 설치 문구, 설정 중 안내, 앱 설치 기록 ---
NB=$T/nb; rm -rf $NB; mkdir -p $NB/bin $NB/bk $NB/w $NB/hd/maps
export NOTICE=$NB/notices
printf '#!/bin/sh\necho "pm $*" >> %s/calls\necho Failure\n' $NB > $NB/bin/pm
chmod +x $NB/bin/*
# toolbox만 있는 PATH(K3 탐사로 확인한 명령만): 차에 없는 printf·awk·sed·head·tail·stat을 부르면 "not found"가 난다
mkdir -p $NB/tb
for c in cp rm mkdir chmod ls cat grep date sleep sync; do ln -sf "$(command -v $c)" $NB/tb/$c; done
# 1.7.1: 차의 toolbox mv는 옵션을 모른다(-f를 파일 이름으로 봄, 리뷰 H1). 첫 인자가 -로 시작하면 실패하게 흉내 낸다.
printf '#!/bin/sh\ncase "$1" in -*) echo "mv: $1: No such file" >&2; exit 1 ;; esac\nexec %s "$@"\n' "$(command -v mv)" > $NB/tb/mv
cp $NB/bin/pm $NB/tb/
printf '#!/bin/sh\ncase "$1" in sys.boot_completed) echo 1 ;; *) echo TEST ;; esac\n' > $NB/tb/getprop
printf '#!/bin/sh\necho "setprop $*" >> %s/setprop.log\n' $NB > $NB/tb/setprop
chmod +x $NB/tb/*
echo boot-1 > $NB/bootid
TB="$NB/tb"
(PATH=$NB/bin:$T/bin:/usr/bin:/bin:/sbin HOTSPOT_LIB=1 BB=$NB/none W=$NB/w BK=$NB/bk sh -c '. '$T'/app/svc/hotspot.sh; export PATH='$NB'/bin:'$T'/bin:/usr/bin:/bin:/sbin; wait() { exit 7; }; main') > $NB/out 2>&1; echo $? >> $NB/out
check "서비스: busybox가 없으면 아무것도 하지 않고 로그만 남기고 대기" 'grep -q "busybox가 없음" $NB/out && [ "$(tail -1 $NB/out)" = 7 ] && [ ! -d $NB/w/x ] && ! grep -q "svc\|hostapd" $NB/out'
# post.sh: 이 PC에는 /system/bin/busybox가 없다(그대로 busybox 없는 내비)
sed -e "s#/data/nemesis/apps/korea.projection/svc/hotspot.sh#$T/app/svc/hotspot.sh; export PATH=$NB/bin:$T/bin:/usr/bin:/bin:/sbin#" \
  -e "s#^export PATH=.*#export PATH=$NB/bin:$T/bin:/usr/bin:/bin:/sbin#" -e "s#^BK=.*#BK=$NB/bk#" \
  -e "s#^W=.*#W=$NB/w#" $T/app/scripts/post.sh > $NB/post.sh
echo apk > $NB/fake.apk
sed -e "s#^export PATH=.*#export PATH=$TB#" -e "s#; export PATH=$NB/bin:$T/bin:/usr/bin:/bin:/sbin#; export PATH=$TB#" $NB/post.sh > $NB/post-tb.sh
rm -f $NB/notices $NB/calls $NB/w/app-install.log $NB/setprop.log; (W=$NB/w APK_SRC=$NB/fake.apk APK_COPY=$NB/copy.apk /bin/sh $NB/post-tb.sh) > $NB/out 2>&1; echo $? >> $NB/out
check "설치: busybox가 없으면 무선 설정 없이 '아직 동작하지 않습니다(지원 조사 중)' 안내, 성공(0)으로 끝남" 'grep -q "아직 동작하지 않습니다(지원 조사 중)" $NB/notices && ! grep -q busybox $NB/notices && [ "$(tail -1 $NB/out)" = 0 ]'
check "  1.7.1: 알림 기록 한 줄(\"<초> <부팅 id> <문구>\", 644)이 toolbox mv(옵션 없음)로도 생기고 임시 파일이 남지 않음(리뷰 H1·L1)" 'grep -q "^[0-9][0-9]* [^ ]* 이 내비에서는 아직 동작하지 않습니다" $NB/notices && [ "$(stat -f %Lp $NB/notices)" = 644 ] && [ -z "$(ls $NB | grep "^toasts\.")" ]'
check "  1.5.5: busybox가 없어도 상태 화면 앱은 toolbox 명령으로 설치를 시도하고 결과를 남김(실패해도 성공)" 'grep -q "^pm install -r $NB/copy.apk" $NB/calls && grep -q "pm install: Failure" $NB/w/app-install.log && [ -f $NB/copy.apk ]'
check "  toolbox 명령만으로 끝남(not found 없음), 부팅 완료 표시를 0으로 내렸다가 1로 되돌림" '! grep -q "not found" $NB/out && [ "$(cat $NB/setprop.log)" = "$(printf "setprop sys.boot_completed 0\nsetprop sys.boot_completed 1")" ]'
rm -f $NB/notices $NB/calls; (W=$NB/w APK_SRC=$NB/none.apk APK_COPY=$NB/copy2.apk /bin/sh $NB/post-tb.sh) > $NB/out 2>&1; echo $? >> $NB/out
check "  앱 파일이 없어도 설치는 성공(0), pm을 부르지 않음" '[ "$(tail -1 $NB/out)" = 0 ] && ! grep -q "pm install" $NB/calls 2>/dev/null'
sed -i '' "s#^BB=.*#BB=$T/bin/bb#" $NB/post.sh
rm -f $NB/notices; (W=$NB/w APK_SRC=$NB/none.apk sh $NB/post.sh) > $NB/out 2>&1
check "  앱 설치 실패 문구는 핫스팟 상태를 말하지 않음" 'grep -q "상태 화면 앱을 설치하지 못했습니다" $NB/notices && ! grep -q "핫스팟은 정상" $NB/notices'
# status.sh: busybox 없는 내비는 셸 기본 명령으로 짧은 리포트를 USB에 남김
rm -rf $T/usb0/KoreaProjection-report; rm -f $T/notice
rm -f $STF $NB/calls $NB/notices $NB/setprop.log $NB/w/app-try
# 앞의 Car Report 테스트가 뒤에서 같은 USB 폴더에 쓰는 중일 수 있다(가끔 실패): 끝날 때까지 기다린다
i=0; while { [ -d $T/w/carreport.lock ] || [ -d $CR/w/carreport.lock ]; } && [ $i -lt 100 ]; do /bin/sleep 0.2; i=$((i+1)); done
PV=$(grep '^package-version=' $PKG/NEMESIS.data); PV=${PV#package-version=}
cp $PKG/NEMESIS.data $T/app/NEMESIS.data
# status.sh가 읽어 들이는 hotspot.sh가 PATH를 $T/bin으로 다시 정하므로, 그 뒤에 이 구역의 pm·am이 먼저 오게 한다
sed -e "s#^export PATH=.*#export PATH=$TB#" -e "s#^\(HOTSPOT_LIB=1 \. .*hotspot\.sh\)\$#\1; export PATH=$TB#" $T/stl.sh > $NB/st.sh
(STATUS=$STF BB=$NB/none BOOT_ID=$NB/bootid APP=$T/app SRC=$T/softap.conf W=$NB/w APK_SRC=$NB/fake.apk APK_COPY=$NB/copy3.apk /bin/sh $NB/st.sh) > $NB/out 2>&1; echo $? >> $NB/out
check "Launch: busybox가 없으면 USB에 짧은 리포트(제품·플랫폼·명령 목록)만 남김" 'grep -q "busybox 없는 내비" $T/usb0/KoreaProjection-report/1-report.md && grep -q "^## /system/bin" $T/usb0/KoreaProjection-report/1-report.md && [ ! -f $T/usb0/KoreaProjection-report/3-log.txt ] && [ "$(tail -1 $NB/out)" = 0 ]'
check "  1.5.5: 앱이 읽을 짧은 상태 파일(support=nobb, usb=saved, 버전) 644" 'grep -q "^support=nobb$" $STF && grep -q "^usb=saved$" $STF && grep -qx "pkgver=$PV" $STF && grep -q "^made=" $STF && [ "$(stat -f %Lp $STF)" = 644 ]'
check "  앱이 없으면 다시 설치를 시도하고, 화면을 못 띄우므로 알림으로 안내" 'grep -q "^pm install -r $NB/copy3.apk" $NB/calls && grep -q "아직 동작하지 않습니다(지원 조사 중)" $NB/notices'
check "  toolbox 명령만으로 끝남: 오류 줄 없음(NEMESIS가 화면에 띄움)" '! grep -q "not found" $NB/out && [ ! -f $STF.tmp ]'
(STATUS=$STF BB=$NB/none BOOT_ID=$NB/bootid APP=$T/app SRC=$T/softap.conf W=$NB/w APK_SRC=$NB/fake.apk APK_COPY=$NB/copy3.apk /bin/sh $NB/st.sh) > /dev/null 2>&1
check "  Launch를 두 번 눌러도 앱 재설치(부팅 완료 표시 0→1)는 한 부팅에 한 번" '[ "$(grep -c "boot_completed 0" $NB/setprop.log)" = 1 ] && [ "$(grep -c "^pm install" $NB/calls)" = 1 ]'
echo boot-2 > $NB/bootid
(STATUS=$STF BB=$NB/none BOOT_ID=$NB/bootid APP=$T/app SRC=$T/softap.conf W=$NB/w APK_SRC=$NB/fake.apk APK_COPY=$NB/copy3.apk /bin/sh $NB/st.sh) > /dev/null 2>&1
check "  다음 부팅에는 다시 시도" '[ "$(grep -c "^pm install" $NB/calls)" = 2 ]'
rm -rf $T/usb0/KoreaProjection-report; rm -f $NB/notices
mkdir -p $NB/bin2
printf '#!/bin/sh\necho "pm $*" >> %s/calls\ncase "$1" in path) echo package:/data/app/x.apk ;; *) echo Success ;; esac\n' $NB > $NB/bin2/pm; chmod +x $NB/bin2/pm
sed -e "s#^export PATH=.*#export PATH=$NB/bin2:$T/bin:/usr/bin:/bin:/sbin#" -e "s#^\(HOTSPOT_LIB=1 \. .*hotspot\.sh\)\$#\1; export PATH=$NB/bin2:$T/bin:/usr/bin:/bin:/sbin#" $T/stl.sh > $NB/st2.sh
mv $T/mounts $T/mounts.keep; rm -f $NB/calls
# 리뷰 M1: 앱이 이 패키지 판(app.vc = APK_VC)으로 깔려 있는 경우
mkdir -p $NB/bk2; echo "$(sed -n 's/^APK_VC=//p' $PKG/svc/hotspot.sh)" > $NB/bk2/app.vc
(STATUS=$STF BB=$NB/none BK=$NB/bk2 APP=$T/app SRC=$T/softap.conf W=$NB/w sh $NB/st2.sh) > $NB/out 2>&1
mv $T/mounts.keep $T/mounts
check "  앱이 있으면 알림 없이 화면이 안내(USB 없으면 usb=none)" '[ ! -f $NB/notices ] && grep -q "^usb=none$" $STF && grep -q "^pm path" $NB/calls && ! grep -q "pm install" $NB/calls'
# 1.7.3 리뷰 M1: 업데이트 때 pm install -r이 실패해 옛 판(기록 28)이 남았으면 Launch가 한 부팅에 한 번 다시 설치하고, 성공하면 기록을 이 판으로
echo 28 > $NB/bk2/app.vc; rm -f $NB/calls $NB/w/app-try; echo boot-M1 > $NB/bootid
(STATUS=$STF BB=$NB/none BK=$NB/bk2 BOOT_ID=$NB/bootid APP=$T/app SRC=$T/softap.conf W=$NB/w APK_SRC=$NB/fake.apk APK_COPY=$NB/copy4.apk sh $NB/st2.sh) > $NB/out 2>&1
check "1.7.3 리뷰 M1: 앱은 있지만 옛 판 기록(28)이면 Launch가 다시 설치하고, 성공하면 app.vc를 이 판(APK_VC)으로 씀" 'grep -q "^pm install -r $NB/copy4.apk" $NB/calls && [ "$(cat $NB/bk2/app.vc)" = "$(sed -n "s/^APK_VC=//p" $PKG/svc/hotspot.sh)" ]'
rm -f $NB/calls
(STATUS=$STF BB=$NB/none BK=$NB/bk2 BOOT_ID=$NB/bootid APP=$T/app SRC=$T/softap.conf W=$NB/w APK_SRC=$NB/fake.apk APK_COPY=$NB/copy4.apk sh $NB/st2.sh) > $NB/out 2>&1
check "  리뷰 M1: 다시 깐 뒤에는 Launch가 또 설치하지 않음" '! grep -q "pm install" $NB/calls'
rm -f $NB/bk2/app.vc $NB/calls $NB/w/app-try; echo boot-M1b > $NB/bootid
(STATUS=$STF BB=$NB/none BK=$NB/bk2 BOOT_ID=$NB/bootid APP=$T/app SRC=$T/softap.conf W=$NB/w APK_SRC=$NB/fake.apk APK_COPY=$NB/copy4.apk sh $NB/st2.sh) > $NB/out 2>&1
check "  리뷰 M1: 기록이 없어도(1.7.2에서 올라와 post.sh 설치가 실패함) 다시 설치" 'grep -q "^pm install -r $NB/copy4.apk" $NB/calls'
check "  리뷰 M1: APK_VC가 앱 소스의 versionCode와 같음(올릴 때 함께)" '[ "$(sed -n "s/^APK_VC=//p" $PKG/svc/hotspot.sh)" = "$(sed -n "s/.*android:versionCode=\"\([0-9]*\)\".*/\1/p" $B/nemesis-pkg/app-src/AndroidManifest.xml)" ]'
# 마지막 묶음 L1: 옛 앱이 있는데 이 판 설치가 계속 실패하면(서명 다름 등) 부팅마다 되풀이하지 않고 3번에서 멈춤
mkdir -p $NB/bin3
printf '#!/bin/sh\necho "pm $*" >> %s/calls\ncase "$1" in path) [ -f %s/noapp ] || echo package:/data/app/x.apk ;; install) echo "Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE]" ;; esac\n' $NB $NB > $NB/bin3/pm; chmod +x $NB/bin3/pm
sed -e "s#^export PATH=.*#export PATH=$NB/bin3:$T/bin:/usr/bin:/bin:/sbin#" -e "s#^\(HOTSPOT_LIB=1 \. .*hotspot\.sh\)\$#\1; export PATH=$NB/bin3:$T/bin:/usr/bin:/bin:/sbin#" $T/stl.sh > $NB/st3.sh
echo 28 > $NB/bk2/app.vc; rm -f $NB/bk2/app.fail $NB/calls $NB/noapp
for b in L1a L1b L1c L1d; do echo boot-$b > $NB/bootid; (STATUS=$STF BB=$NB/none BK=$NB/bk2 BOOT_ID=$NB/bootid APP=$T/app SRC=$T/softap.conf W=$NB/w APK_SRC=$NB/fake.apk APK_COPY=$NB/copy5.apk sh $NB/st3.sh) > /dev/null 2>&1; done
check "마지막 묶음 L1: 옛 앱이 있고 이 판 설치가 실패하면 부팅마다 한 번씩 3번까지만(4번째 부팅에는 안 함), 횟수는 \$BK/app.fail" '[ "$(grep -c "^pm install" $NB/calls)" = 3 ] && [ "$(cat $NB/bk2/app.fail)" = "$(sed -n "s/^APK_VC=//p" $PKG/svc/hotspot.sh) 3" ]'
: > $NB/noapp; rm -f $NB/calls; echo boot-L1e > $NB/bootid
(STATUS=$STF BB=$NB/none BK=$NB/bk2 BOOT_ID=$NB/bootid APP=$T/app SRC=$T/softap.conf W=$NB/w APK_SRC=$NB/fake.apk APK_COPY=$NB/copy5.apk sh $NB/st3.sh) > /dev/null 2>&1
check "  마지막 묶음 L1: 앱이 아예 없으면(화면이 없음) 횟수와 상관없이 지금처럼 부팅마다 한 번 해 봄" 'grep -q "^pm install" $NB/calls'
rm -f $NB/noapp $NB/bk2/app.fail
rm -f $T/app/NEMESIS.data
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

export NOTICE=$T/notice
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
check "  post.sh·preun.sh는 BB를 비워 두고 hotspot.sh를 ps보다 먼저 읽음(1.7.3 K-6: post.sh는 ps를 쓰지 않음)" 'grep -qx "BB=" $PKG/scripts/post.sh && grep -qx "BB=" $PKG/scripts/preun.sh && { ! grep -q "\$PS" $PKG/scripts/post.sh || [ "$(grep -n "hotspot.sh$" $PKG/scripts/post.sh | cut -d: -f1)" -lt "$(grep -n "\$PS" $PKG/scripts/post.sh | head -1 | cut -d: -f1)" ]; }'
check "  ps는 모두 \$PS로 부름(\$BB ps 직접 호출 없음)" '! grep -n -F "\$BB ps" $PKG/svc/hotspot.sh $PKG/bin/status.sh $PKG/bin/carreport.sh $PKG/scripts/post.sh $PKG/scripts/preun.sh | grep -v "then PS="'
check "  status.sh는 뒤에서 띄우는 감시자(--watch)·--wait에 고른 BB를 넘김" '[ "$(grep -c "BB=\$BB .*setsid" $PKG/bin/status.sh)" = 2 ]'
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
# 4b 리뷰 L-2: 진짜 busybox(printf·od)로 parse_conf·conf_auth가 1.7.2 원본과 같은가. 비교는 하위 셸에서(parse_conf가 B 등을 바꿈)
_pn=0; _pd=0
for f in /t/pk/c??; do
  _pn=$((_pn+1))
  _pa=$(parse_conf $f; printf '%s|' "$NS" "$S1" "$S2" "$S3" "$S4" "$S5"; conf_auth $f)
  _pb=$(. /t/ref-parse.sh; parse_conf $f; printf '%s|' "$NS" "$S1" "$S2" "$S3" "$S4" "$S5"; conf_auth $f)
  [ "$_pa" = "$_pb" ] && _pd=$((_pd+1))
done
echo "pkcmp=$_pd/$_pn"
E
  cp -R $PK $BS/pk; cp $T/ref-parse.sh $BS/ref-parse.sh
  docker run --rm --pull never --platform linux/arm/v7 -v $T/app:/app:ro -v $B/vendor/busybox:/vb:ro -v $BS:/t:ro alpine:3.20 /vb/busybox sh /t/real.sh > $BS/real.out 2>&1
  check "  진짜 busybox(ARM 컨테이너): 실행됨, ps -o로 좀비를 보고 우리·순정 hostapd를 구분, 우리 것만 멈춤" 'grep -qx "OK=1" $BS/real.out && grep -qx "PS=/vb/busybox ps -o pid,stat,args" $BS/real.out && grep -qx zombie-seen $BS/real.out && grep -qx ours-running $BS/real.out && grep -qx stock-on $BS/real.out && grep -qx ours-stopped $BS/real.out && grep -qx stock-alive $BS/real.out'
  check "  4b 리뷰 L-2: 진짜 busybox로도 parse_conf·conf_auth가 1.7.2 원본과 같음(11개)" 'grep -qx "pkcmp=11/11" $BS/real.out'
  check "  진짜 busybox: od -b -v 바이트, f_perm·f_owner, md5sum 표준입력" 'grep -qx "od=000 005 150 151 377" $BS/real.out && grep -qx "perm=640 owner=0:0" $BS/real.out && grep -qx "md5=764efa883dda1e11db47671c4a3bbd9e  -" $BS/real.out'
else
  echo "skip 진짜 busybox 확인(Docker 또는 alpine:3.20 arm/v7 이미지 없음)"
fi

# --- 1.7.3 6단계 패키지 전체 리뷰 반영(낮음) ---
S6=$T/s6; mkdir -p $S6/w $S6/bk
s6() { HOTSPOT_LIB=1 BB=$T/bin/bb W=$S6/w BK=$S6/bk sh -c '. '$T'/app/svc/hotspot.sh; '"$1" 2>&1; }
# L3: 계획의 WARNING 줄(ADB TCP 스위치 경고)은 변경이 아님
printf '%s\n' "same     /system/framework/hooks.jar [wireless-carplay-aa]" "WARNING: the car's ADB TCP switch is on" "hook plan: 3 of 3" > $S6/w/plan.txt
S6A=$(s6 'plan_nothing && echo yes || echo no')
printf '%s\n' "same     /system/framework/hooks.jar [wireless-carplay-aa]" "WARNING: x" "change   /system/app/X.apk [other] -> 1" > $S6/w/plan.txt
S6B=$(s6 'plan_nothing && echo yes || echo no')
check "6단계 리뷰 L3: plan_nothing은 WARNING 줄을 변경으로 보지 않음(다른 변경 줄이 있으면 그대로 변경)" '[ "$S6A" = yes ] && [ "$S6B" = no ]'
# L4: 설치 마무리가 진행 중(run)이면 순정 AP 경로가 "준비됨"으로 덮지 않음
printf 'pct=95\nstate=run\nstage=x\n' > $S6/prog
S6C=$(s6 'PROG='$S6'/prog; setup_done() { return 0; }; prog_final_this_boot() { return 1; }; prog() { echo "PROG $*"; }; stock_ap_ready; printf "state=done\n" > $PROG; stock_ap_ready')
check "6단계 리뷰 L4: stock_ap_ready는 진행 중(run, 95% 보류)이면 덮지 않고, 아니면 준비됨을 씀" '[ "$(echo "$S6C" | grep -c "^PROG 100 done")" = 1 ]'
# L5: 칩 실패 근거의 -84는 Wi-Fi 줄(dhd·bcmdhd·sdio·wlan)만
# 마지막 묶음(중간 2): 실제 커널 줄. 칩 실패 근거인 줄 5개는 하나씩 잡고, 무관한 줄 4개는 하나도 잡지 않음
printf '%s\n' "<3>[ 9.10] sdioh_buffer_tofrom_bus: TX FAILED ede1c000, addr=0x08000, pkt_len=1968, ERR=-84" > $S6/y1
printf '%s\n' "<3>[ 9.20] dhdsdio_probe_attach: si_attach failed!" > $S6/y2
printf '%s\n' "<3>[ 9.30] failed to power up DHD generic adapter, 0 retry left" > $S6/y3
printf '%s\n' "<3>[ 9.40] dhd_bus_start: failed to download firmware" > $S6/y4
printf '%s\n' "<3>[ 9.50] mmc1: error -84 whilst initialising SDIO card" > $S6/y5
printf '%s\n' "<3>[ 2.10] mmc0: error -84 whilst initialising SD card" "<3>[ 12.3] mmcblk0: error -84 transferring data, sector 1234, nr 8, cmd response 0x900, card status 0xb00" "<6>[ 30.1] wlan0 rssi=-84" "<6>[ 31.2] dhd_rx_frame: rssi -84 dbm" > $S6/n1
S6D=$(s6 'NOCHIP_LOG=/nonexist; for f in y1 y2 y3 y4 y5 n1; do NOWLAN_LOG='$S6'/$f; chip_fail_evidence && echo "$f=y" || echo "$f=n"; done' | tr '\n' ' ')
check "6단계 리뷰 L5·마지막 묶음 중간 2: ERR=-84(sdio)·si_attach·power up DHD·download firmware·SDIO 카드 error -84는 근거, mmc0 SD 카드·mmcblk0·rssi -84 두 줄은 근거 아님" '[ "$S6D" = "y1=y y2=y y3=y y4=y y5=y n1=n " ]'
check "6단계 리뷰 L2: 제보의 로그 모음에 mod-update.txt도 들어감(같은 가리기)" 'grep -q "\$W/mod-apply.txt \$W/mod-update.txt \$W/carreport.txt" $PKG/bin/status.sh'
check "6단계 리뷰 L6: 삭제·업데이트 때 Car Report 저장(carreport.lock/pid의 carreport.sh)도 멈춤" 'grep -q "^for _pf in wait.pid watch.pid collect.pid carreport.lock/pid; do$" $PKG/scripts/preun.sh && grep -q "\*status.sh\*|\*carreport.sh\*) kill" $PKG/scripts/preun.sh'
check "6단계 리뷰 L9·M2: 진짜 삭제 갈래에서만 되돌리기 USB 작업 폴더·재부팅 결과 파일을 지움(업데이트 갈래 뒤)" '[ "$(grep -n "업데이트: 이전 버전 정리" $PKG/scripts/preun.sh | cut -d: -f1)" -lt "$(grep -n "^rm -rf \${KP_RB_D:-/data/local/tmp/kp-rollback}$" $PKG/scripts/preun.sh | cut -d: -f1)" ] && [ "$(grep -n "업데이트: 이전 버전 정리" $PKG/scripts/preun.sh | cut -d: -f1)" -lt "$(grep -n "^rm -f \$RBRES \$RBRES.tmp$" $PKG/scripts/preun.sh | cut -d: -f1)" ]'
check "6단계 리뷰 L10: 아직 옛 판인데 '바꿨습니다'라 하지 않고, 이번 부팅에 시도했는데 옛 판이면 '이번에는 못 바꿈, 재부팅하면 다시'" '! grep -q "무선 모드를 새 판으로 바꿨습니다. 재부팅하고" $PKG/bin/status.sh && grep -q "재부팅하면 무선 모드를 새 판으로 바꿉니다. 재부팅하고 3분 뒤 한 번 더 재부팅해 주세요(남은 재부팅 2번)." $PKG/bin/status.sh && grep -q "무선 모드를 이번에는 새 판으로 바꾸지 못했습니다. 재부팅하면 다시 시도합니다." $PKG/bin/status.sh && awk "/^mod_update\(\) \{/,/^}/" $PKG/svc/hotspot.sh | grep -q "> \$BK/mod.try$"'
check "  6단계 리뷰 L10: 세 문장 안내 두 곳을 두 문장으로(Car Report 실패, 자동 설정 끝)" '! grep -q "이제 USB를 빼셔도 됩니다. 필요하면 USB를 다시 꽂고" $PKG/bin/carreport.sh && grep -q "Car Report는 저장하지 못했습니다(필요하면 USB를 다시 꽂고 \[제보 파일 만들기\]). 이제 USB를 빼셔도 됩니다." $PKG/bin/carreport.sh && grep -q "내비를 재부팅(RESET 버튼 또는 NEMESIS 재부팅)한 뒤 결과를 제보해 주시면 지원 목록에 넣습니다." $PKG/svc/hotspot.sh'
check "6단계 리뷰 M3: hmgapi/README.txt의 모드 판 문구가 2.4.1(Korea Projection 1.7.3)" 'grep -q "한국 차 빌드 2.4.1입니다(Korea Projection 1.7.3)" $PKG/hmgapi/README.txt && ! grep -q "2.3.0입니다(Korea Projection 1.7.1)" $PKG/hmgapi/README.txt'
rm -rf $S6

# 4b K-11(2026-11-10): 진단 USB 스크립트(kp-probe·kp-wifi-diag·5GHz·A/B·kp-sys-restore)의 시험은 tests/legacy/legacy-test.sh로 옮겼다(지우지 않음).

echo "---"
[ $fails -eq 0 ] && echo "모두 통과" || { echo "실패 $fails개"; exit 1; }
