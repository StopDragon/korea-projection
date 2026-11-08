#!/system/bin/sh
# Stick script (NEMESIS.sh, type=execute): move the Niro to korea.projection and check whether
# wireless CarPlay works without wireless.projection on HMG-API 1.0.2. Runs in steps, one per
# stick insertion; the step is kept in /data/local/tmp/kp-test/step. Reports go to $U/kp/.
#   A: niro.carplay.hotspot -> korea.projection, then uninstall wireless.projection
#      (it may restart the head unit itself), then hmgapid engine apply.  -> restart the car
#   B: after the restart: are the wireless features there (pm list features)?
#      yes -> try wireless CarPlay.  no -> put HMG-API's 2 permission files back (md5-checked)
#      + engine apply, once -> restart (B again);
#      still none -> put wireless.projection back (it restarts the head unit).
#   C: copy the logs (korea.projection + HMG-API) and a state snapshot.
# A file kp-rollback on the stick: put wireless.projection back at once, whatever the step.
# Never writes the CarPlay passphrase anywhere.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin:/data/nemesis/bin
BB=${BB:-/system/bin/busybox}
[ -x "$BB" ] || BB=${APPS:-/data/nemesis/apps}/korea.projection/bin/busybox
U=${U:-/storage/usb0}
D=${D:-/data/local/tmp/kp-test}
O=$U/kp
FEAT=com.hkmc.software.connectivity.carplay_wireless
PERMS=${PERMS:-/system/etc/permissions}
trap 'sync' EXIT
umask 077
$BB mkdir -p $D $O

toast() {
  echo "$1"
  am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "$1" \
    --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1
}

state() {
  echo "=== $1 $(date) ==="
  echo "-- product (NEMESIS os) / targetdir (models) --"; getprop ro.build.product; getprop ro.mobis.targetdir
  for p in persist.ium.support persist.wifi.state persist.sys.iap2.wifi persist.iap2.iden.wireless; do
    echo "$p=$(getprop $p)"
  done
  echo "-- features --"; pm list features 2>/dev/null | $BB grep -iE "carplay|androidauto|hardware.wifi"
  echo "-- permission files --"
  $BB ls -la /system/etc/permissions/ | $BB grep -iE "carplay|androidauto|hotspot|hardware.wifi"
  FX=/system/onebin/$(getprop ro.mobis.onebindir)/featurexml.cfg
  echo "-- $FX --"; $BB grep -nE "carplay|androidauto|hotspot|hardware.wifi" $FX
  echo "-- NEMESIS packages --"; nemesis pkg-list 2>&1
  echo "-- HMG-API engine --"; hmgapid engine status 2>&1 | $BB head -20
  echo "-- access point --"
  $BB ps | $BB grep -E "hostapd|dnsmasq|hotspot.sh|wpa_supp" | $BB grep -v grep
}

has_feature() { pm list features 2>/dev/null | $BB grep -q "$FEAT"; }

# wireless.projection's (un)install can restart the head unit without returning: flush the
# reports every second for 3 minutes (fds closed so nothing waits on it)
flusher() { ( i=0; while [ $i -lt 180 ]; do sleep 1; sync; i=$((i+1)); done ) </dev/null >/dev/null 2>&1 & }

# HMG-API(엔진 Engine.features)가 쓰는 것과 똑같은 권한 파일. 이미 있으면 건드리지 않는다.
put_perm() {
  _f=$PERMS/$1.xml
  [ -f $_f ] && { echo "있음: $_f"; return 0; }
  $BB printf '<permissions>\n    <feature name="%s" />\n</permissions>\n' "$1" > $_f
  set -- "$2" $($BB md5sum $_f)
  if [ "$1" = "$2" ]; then $BB chmod 644 $_f; echo "씀: $_f ($1)"; else rm -f $_f; echo "md5 다름, 지움: $_f ($2)"; fi
}

rollback() {
  echo "B-rollback" > $D/step
  flusher
  {
    state "before putting wireless.projection back"
    hmgapid remount rw 2>&1
    nemesis install $U/wireless.projection.zip 2>&1
    echo "install exit $? (reaching here: no restart)"
    hmgapid remount ro 2>&1
    state "after putting wireless.projection back"
  } >> $O/rollback.txt 2>&1
  if [ -d ${APPS:-/data/nemesis/apps}/wireless.projection ]; then
    toast "Korea Projection 테스트: wireless.projection을 다시 설치했습니다. 재시작되지 않으면 내비를 재부팅해 주세요(RESET 버튼 또는 NEMESIS 재부팅)."
  else
    # 설치가 안 됐다: 다음에 꽂을 때 다시 시도한다
    echo "rollback-retry" > $D/step
    toast "Korea Projection 테스트: wireless.projection 재설치에 실패했습니다. USB를 다시 꽂으면 다시 시도합니다."
  fi
}

[ -f $U/kp-rollback ] && { rollback; exit 0; }

STEP=$(cat $D/step 2>/dev/null)
case "$STEP" in
"")
  # 되돌리기에 쓸 파일이 USB에 없으면 아무것도 바꾸지 않는다
  for z in $U/wireless.projection.zip $U/packages/korea.projection.zip $U/packages/niro.carplay.hotspot.zip; do
    if [ ! -s $z ]; then
      toast "Korea Projection 테스트: USB에 ${z##*/} 파일이 없어 시작하지 않았습니다."
      exit 0
    fi
  done
  rm -f $D/fixed $D/forced
  echo A > $D/step
  {
    state "A: before"
    echo "=== uninstall niro.carplay.hotspot ==="
    nemesis uninstall niro.carplay.hotspot 2>&1
    echo "=== install korea.projection ==="
    nemesis install $U/packages/korea.projection.zip 2>&1
    sleep 5
    state "A: korea.projection installed"
  } > $O/A.txt 2>&1
  sync
  # korea.projection refuses to install next to niro.carplay.hotspot (depends "!"): if it isn't
  # in, stop here and keep wireless.projection, so the car stays as it was
  if [ ! -d ${APPS:-/data/nemesis/apps}/korea.projection ]; then
    rm -f $D/step
    {
      echo "=== korea.projection 설치 안 됨: 중단, 예전 패키지를 다시 설치, wireless.projection 유지 ==="
      nemesis compat $U/packages/korea.projection.zip 2>&1
      nemesis install $U/packages/niro.carplay.hotspot.zip 2>&1
    } >> $O/A.txt 2>&1
    toast "Korea Projection 테스트: 새 패키지 설치에 실패해 중단했습니다(기존 상태 유지). USB를 가져와 주세요."
    exit 0
  fi
  flusher
  {
    echo "=== uninstall wireless.projection $(date) ==="
    hmgapid remount rw 2>&1
    nemesis uninstall wireless.projection 2>&1
    echo "uninstall exit $? (reaching here: no restart)"
    hmgapid remount ro 2>&1
    if [ -d ${APPS:-/data/nemesis/apps}/wireless.projection ]; then
      echo "=== wireless.projection이 삭제되지 않음: 중단 ==="
      echo C > $D/step
      state "A: wireless.projection 삭제 실패"
      toast "Korea Projection 테스트: wireless.projection 삭제에 실패해 중단했습니다. 카플레이는 그대로 쓸 수 있습니다. USB를 다시 꽂으면 로그를 가져옵니다."
      exit 0
    fi
    echo "=== hmgapid engine apply ==="
    hmgapid engine apply 2>&1
    state "A: after uninstall + apply"
  } >> $O/A.txt 2>&1
  toast "Korea Projection 테스트 1단계 완료. 내비를 재부팅한 뒤(RESET 버튼 또는 NEMESIS 재부팅) USB를 다시 꽂아 주세요."
  ;;
A|B1|B2)
  {
    state "B: after restart (step $STEP)"
  } > $O/B-$STEP.txt 2>&1
  if has_feature; then
    echo C > $D/step
    toast "Korea Projection 테스트: 무선 기능 정상. wireless.projection 없이 무선 카플레이를 연결해 보세요. 운행 후 USB를 다시 꽂으면 로그를 가져옵니다."
  elif [ ! -f $D/fixed ]; then
    # 11-06 차에서 확인: wireless.projection 삭제가 HMG-API의 권한 파일 2개까지 지웠고, HMG-API 1.0.2의
    # apply는 "changed outside HMG-API"로 멈춘다. --force도 소용없다(Engine.java:1654: 기록과 같은
    # 결과는 쓰지 않음). 그래서 HMG-API가 기록해 둔 것과 똑같은 바이트(md5 확인)로 되돌린 뒤 apply한다.
    : > $D/fixed
    echo B2 > $D/step
    {
      echo "=== 권한 파일 되돌리기 ==="
      hmgapid remount rw 2>&1
      put_perm com.hkmc.software.connectivity.carplay_wireless 95ff801a064526de56059dba10960b05
      put_perm com.hkmc.software.connectivity.androidauto_wireless fa91812d3eeee415768018ab6ee6804a
      hmgapid remount ro 2>&1
      echo "=== hmgapid engine apply ==="
      hmgapid engine apply 2>&1
      echo "apply exit $?"
      state "B: after restoring the permission files + apply"
    } >> $O/B-$STEP.txt 2>&1
    if [ -f $PERMS/$FEAT.xml ]; then
      toast "Korea Projection 테스트: 무선 기능 파일을 되돌렸습니다. 내비를 재부팅한 뒤(RESET 버튼 또는 NEMESIS 재부팅) USB를 다시 꽂아 주세요."
    else
      rollback
    fi
  else
    rollback
  fi
  ;;
rollback-retry)
  rollback
  ;;
B-rollback)
  # 재설치 도중 헤드유닛이 재시작됐을 수 있다: 무선 기능도 wireless.projection도 없으면 다시 설치
  if ! has_feature && [ ! -d ${APPS:-/data/nemesis/apps}/wireless.projection ]; then
    rollback
  else
    echo C > $D/step
    exec sh "$0"
  fi
  ;;
*)
  # C (or after a rollback): logs and a snapshot
  for PKG in korea.projection niro.carplay.hotspot; do
    for f in /data/nemesis/logs/$PKG/*.log /data/local/tmp/$PKG/cp.log*; do
      [ -f "$f" ] && $BB cp "$f" $O/$PKG-${f##*/}.txt
    done
  done
  for f in /data/hmgapi/logs/hmgapi/log.log*; do [ -f "$f" ] && $BB cp "$f" $O/hmgapi-${f##*/}.txt; done
  {
    state "C: logs ($STEP)"
    echo "-- CarPlay connections --"; $BB netstat -tn 2>/dev/null | $BB grep 192.168.43
  } > $O/C-$(date +%H%M).txt 2>&1
  toast "Korea Projection 테스트: 로그를 USB에 복사했습니다."
  ;;
esac
sync
echo "STEP $(cat $D/step)"
