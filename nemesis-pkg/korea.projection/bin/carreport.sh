#!/system/bin/sh
# 제보 파일 만들기(bin/status.sh make_report, 1.7.3부터 상태 화면 버튼)가 부른다: HMG-API Car Report를 USB에 저장한다(`hmgapid engine report --usb`).
# 새 차를 추가하려면 이 파일(그 차에서 직접 찾은 훅 지점 이름)이 필요하다. 만드는 데 1분쯤 걸려서,
# 1.7.0: status.sh --collect(뒤에서 도는 로그 모으기)가 마지막 단계로 부른다. 끝나면 리포트 진행 기록에 "USB를 빼셔도 됩니다"를 쓴다.
# - 한 번에 하나만: carreport.lock 폴더(mkdir는 한 번에 하나만 성공). 남은 잠금은 이번 부팅의 살아 있는
#   carreport.sh가 아니면 지우고 다시 잡는다.
# - 최대 CR_MAX*CR_WAIT초(기본 5분)만 기다린다. HMG-API 데몬은 우리가 그만 기다려도 보고서를 끝까지 쓰므로,
#   시간이 넘으면 1분 더 기다린 뒤 알린다(쓰는 중에 USB를 빼지 않게).
# - 성공은 HMG-API가 "usb: /storage/usbN/HMG-API reports/…" 줄을 냈고, 그 usbN이 정말 마운트돼 있을 때만이다
#   (USB를 뺀 빈 마운트 폴더에 써도 그 줄이 나온다: Report.java).
# Car Report에는 HMG-API가 차종 수준 정보만 넣는다(VIN·전화번호·계정 없음, 휴대폰 주소는 지움: Report.java).
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
# busybox: status.sh가 고른 것을 넘겨받는다. 없으면 hotspot.sh와 같은 규칙(내비의 것, 없으면 패키지에 함께 넣은 것)
if [ -z "$BB" ]; then
  BB=/system/bin/busybox
  [ -x $BB ] || BB=${APP:-/data/nemesis/apps/korea.projection}/bin/busybox
fi
W=${W:-/data/local/tmp/korea.projection}
BOOT_ID=${BOOT_ID:-/proc/sys/kernel/random/boot_id}
MOUNTS=${MOUNTS:-/proc/mounts}
CR_WAIT=${CR_WAIT:-5}
CR_MAX=${CR_MAX:-60}
CR_GRACE=${CR_GRACE:-60}
# USB 제보 폴더 이름(status.sh와 같아야 한다)
RDIR=${RDIR:-KoreaProjection-report}
# USB 마운트 위치의 앞부분(테스트에서 바꿀 수 있게)
USBROOT=${USBROOT:-/storage}
umask 077
$BB mkdir -p $W

# 1.7.0: 결과는 토스트가 아니라 리포트 진행 기록(RPROG, 644)에 쓴다(소유자 결정: 토스트 안 씀). 상태 화면 앱이 1초마다 읽어
# "완료: USB를 빼셔도 됩니다"를 보인다. $1: done|fail, $2: 문구
# 1.7.3: req·req2는 status.sh rprog와 같다(앱이 자기 요청의 결과를 id로 찾는다). REQID는 status.sh가 넘긴다.
RPROG=${RPROG:-/data/local/tmp/korea-projection-report-progress.txt}
result() {
  ( umask 022
    $BB printf 'pct=100\nstate=%s\nstage=%s\nstart=%s\nt=%s\nboot=%s\nreq=%s\nreq2=%s\n' "$1" "$2" "${RSTART:-$(date +%s)}" "$(date +%s)" \
      "$(cat $BOOT_ID 2>/dev/null)" "$REQID" "$(cat $W/req.join 2>/dev/null)" > $RPROG.tmp && $BB chmod 644 $RPROG.tmp && $BB mv -f $RPROG.tmp $RPROG ) 2>/dev/null
}

# 1.7.2(P-19): 제보 폴더 사본(2-car-report.json)은 공개 이슈에 올라가므로 IPv4 주소를 x.x.x.x로 가린다
# (모뎀 주소·텔레매틱스 서버 등). HMG-API가 반만 가린 꼴(a.b.x.x)도 다 가린다. 원본(HMG-API reports 폴더)은
# HMG-API 것이라 그대로 둔다. 가리기가 안 되면(awk 실패, 빈 결과) 사본을 만들지 않는다.
# HMG-API가 IPv6 앞부분만 지운 IPv4 매핑 주소(::ffff:a.b.c.d → [removed].b.c.d)의 뒤 세 칸도 지우고, MAC도 지운다(리뷰).
ipmask() {
  $BB awk '{ gsub(/[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*/, "x.x.x.x")
    gsub(/[0-9][0-9]*\.[0-9][0-9]*\.x\.x/, "x.x.x.x")
    gsub(/[[]removed[]]\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*/, "[removed]")
    gsub(/[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]/, "xx:xx:xx:xx:xx:xx")
    print }' "$1"
}
# 가린 결과에 숫자 IPv4가 남았으면(이 busybox의 awk가 다르게 동작) 쓰지 않는다
ipleft() {
  $BB grep -q '[0-9][0-9]*[.][0-9][0-9]*[.][0-9][0-9]*[.][0-9][0-9]*' "$1"
}

L=$W/carreport.lock
lock_alive() {
  _l=$(cat $L/pid 2>/dev/null)
  set -- $_l
  [ -n "$1" ] && [ "$2" = "$(cat $BOOT_ID 2>/dev/null)" ] && [ -d /proc/$1 ] || return 1
  # 1.7.3(리뷰 M3): 명령줄은 NUL로 나뉜다. busybox 1.8.1 grep은 NUL 뒤를 못 볼 수 있어 빈칸으로 바꿔 본다
  case " $($BB tr '\0' ' ' < /proc/$1/cmdline 2>/dev/null) " in *carreport.sh*) return 0 ;; esac
  return 1
}
if ! $BB mkdir $L 2>/dev/null; then
  lock_alive && exit 0
  rm -rf $L
  $BB mkdir $L 2>/dev/null || exit 0
fi
echo "$$ $(cat $BOOT_ID 2>/dev/null)" > $L/pid

p=
# 마지막 묶음 L4: 삭제·업데이트(preun)나 다른 이유로 TERM을 받으면 뒤에서 도는 hmgapid engine report도 멈추고 잠금을 푼다
trap '[ -n "$p" ] && kill $p 2>/dev/null; rm -rf $L; exit 0' TERM INT HUP
hmgapid engine report --usb > $W/carreport.txt 2>&1 &
p=$!
i=0; late=0
while kill -0 $p 2>/dev/null; do
  i=$((i+1))
  if [ $i -gt $CR_MAX ]; then kill $p 2>/dev/null; late=1; echo "시간 초과" >> $W/carreport.txt; break; fi
  sleep $CR_WAIT
done
wait $p 2>/dev/null
rc=$?
sync
ok=0; copied=0; maskfail=0
if [ $rc = 0 ]; then
  while IFS= read -r _x; do
    case "$_x" in
      "usb: $USBROOT/usb"*"/HMG-API reports/"*)
        _f=${_x#usb: }; _m=${_f%%/HMG-API reports/*}
        $BB grep -q " $_m " $MOUNTS 2>/dev/null || continue
        ok=1
        # 사용자가 한 폴더만 첨부하면 되게, 리포트를 제보 폴더에 정해진 이름(2-car-report.json)으로도 복사한다
        _o="$_m/$RDIR/2-car-report.json"
        if ! $BB mkdir -p "$_m/$RDIR" 2>/dev/null; then
          :
        elif ipmask "$_f" 2>/dev/null > "$_o.tmp" && [ -s "$_o.tmp" ] && ! ipleft "$_o.tmp" && $BB mv -f "$_o.tmp" "$_o" 2>/dev/null; then
          copied=1
        else
          # 가리지 못한 사본도, 예전(1.7.1 이하가 가리지 않고 만든) 사본도 남기지 않는다
          $BB rm -f "$_o.tmp" "$_o" 2>/dev/null
          maskfail=1
        fi ;;
    esac
  done < $W/carreport.txt
fi
# vfat는 쓰기를 늦게 내보낸다: "USB를 빼셔도 됩니다" 전에 내보낸다
sync
if [ $ok = 1 ] && [ $copied = 1 ]; then
  result done "완료: 제보 자료를 모두 저장했습니다(USB의 $RDIR 폴더). 이제 USB를 빼셔도 됩니다."
elif [ $ok = 1 ] && [ $maskfail = 1 ]; then
  # 원본에는 IP가 남아 있으므로 공개 이슈에 붙이라고 안내하지 않는다(리뷰)
  result done "완료: Car Report는 IP를 가리지 못해 제보 폴더에 넣지 않았습니다(공개 이슈에 올리지 마세요). 이제 USB를 빼셔도 됩니다."
elif [ $ok = 1 ]; then
  result done "완료: 제보 자료를 저장했습니다. Car Report는 USB의 'HMG-API reports' 폴더에 있습니다. 이제 USB를 빼셔도 됩니다."
else
  # 시간이 넘었으면 HMG-API가 아직 쓰는 중일 수 있다: 조금 더 기다린 뒤 알린다
  [ $late = 1 ] && { sleep $CR_GRACE; sync; }
  result fail "리포트(1·3번 파일)는 저장했지만 Car Report는 저장하지 못했습니다(필요하면 USB를 다시 꽂고 [제보 파일 만들기]). 이제 USB를 빼셔도 됩니다."
fi
rm -rf $L
exit 0
