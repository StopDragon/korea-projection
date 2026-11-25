#!/system/bin/sh
# 되돌리기 USB(kp-rollback, NEMESIS.sh type=execute). 정차 상태에서 USB를 꽂으면 한 번에 끝난다.
# Korea Projection 1.8.0의 무선 모드(2.4.6)가 이상할 때, 1.7.4 정식이 넣었던 무선 모드 2.4.5로 되돌리고 고정한다($BK/mod.pin).
# 고정해 두면 korea.projection(1.8.0)이 부팅 때 1.8.0 판으로 다시 바꾸지 않는다(mod_update·mod_pending이 mod.pin을 본다).
# mod.pin에 고정한 판 번호(2.4.5)를 적는다(1.7.4 B-8 ②). 패키지는 읽어서 보여 주기만 한다.
# USB에 kp-rollback/UNPIN 파일이 있으면 반대로 고정만 푼다(다음 부팅 약 3분 뒤 패키지가 1.8.0 판으로 다시 바꾼다).
# 1.8.0: 1.7.4용 USB(2.4.2~2.4.5 → 2.4.1)는 v1.7.4 릴리스(release-1.7.4-pc/korea-projection-1.7.4-rollback-usb.zip)에, 1.7.3용(→ 2.4.0)은
#   v1.7.3 릴리스에 따로 있다. 이 USB는 1.8.0의 판만 되돌린다.
# 동글 차(내장 Wi-Fi 부품 없이 USB 동글로 쓰는 차): 2.4.5에는 동글 차 항목이 없어 HMG-API가 설치를 거절한다. 그러면 아래대로
#   아무것도 바꾸지 않고 "지금 판 그대로"라고 알린다(안내서에 "동글 차는 쓰지 마세요").
# 바꾸는 것: HMG-API 무선 모드 폴더(엔진 install --force), 고정 표시. 시스템 파일은 엔진 적용(apply)이 맡는다.
# 설치(install)가 실패하면 아무것도 바꾸지 않는다: 엔진은 설치에 실패하면 원래 모드 폴더를 그대로 둔다.
# 설치 뒤 적용(apply)만 실패하면 되돌린 판과 고정은 남기고, HMG-API 앱에서 적용하라고 안내한다.
# 이 USB의 2.4.5는 1.7.4 정식 패키지에 든 판과 바이트까지 같다(md5 = 1.7.4 MOD_MD5).
# 안내는 토스트를 쓰지 않는다(CLAUDE.md 1장): USB의 kp-rollback/RESULT.txt와 상태 화면 알림 기록에 남긴다.
# 비밀번호, SSID, 휴대폰 이름, MAC은 어디에도 쓰지 않는다.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin:/data/nemesis/bin
umask 077
# busybox: 내비의 것(니로 등 1.8.1)을 쓰고, 없는 내비(K3·K8 tcc803x)는 Korea Projection 패키지에 함께 든 것을 쓴다(hotspot.sh와 같은 순서).
# 둘 다 쓸 수 없으면 BB를 비운다: 아래 "$BB mkdir"·"$BB cp"는 toolbox 명령이 되고, 확인이 필요한 일은 하지 않는다.
BB_SYS=${BB_SYS:-/system/bin/busybox}
BB_OWN=${BB_OWN:-/data/nemesis/apps/korea.projection/bin/busybox}
if [ -z "$BB" ]; then
  if [ -x $BB_SYS ]; then BB=$BB_SYS
  elif "$BB_OWN" true >/dev/null 2>&1; then BB=$BB_OWN
  fi
fi
# 리뷰 L8: USB가 usb1로 붙는 차도 있다. 이 스크립트가 놓인 곳($0)을 먼저 보고, 모르면 kp-rollback 폴더가 있는 쪽(usb0 먼저).
# 헤드유닛으로 복사해 다시 돌 때는 $0이 바뀌므로 정한 값을 넘긴다(export U)
if [ -z "$U" ]; then
  case "$0" in
    /storage/usb1/*) U=/storage/usb1 ;;
    /storage/usb0/*) U=/storage/usb0 ;;
    *) if [ -d /storage/usb0/kp-rollback ]; then U=/storage/usb0
       elif [ -d /storage/usb1/kp-rollback ]; then U=/storage/usb1
       else U=/storage/usb0; fi ;;
  esac
fi
export U
D=${D:-/data/local/tmp/kp-rollback}
# 스크립트를 헤드유닛에 복사해 거기서 돈다(도중에 USB가 떨어져도 계속 읽을 수 있게)
if [ "$KP_FROM_DATA" != 1 ]; then
  export KP_FROM_DATA=1
  $BB mkdir -p $D && $BB cp "$0" $D/run.sh && exec sh $D/run.sh
fi
HMGDATA=${HMGDATA:-/data/hmgapi}
BK=${BK:-/data/nemesis/backup/korea.projection}
# korea.projection의 작업 폴더(부팅 자동 설정의 fix.pid)와 /proc, 부팅 id
KW=${KW:-/data/local/tmp/korea.projection}
PROC=${PROC:-/proc}
BOOT_ID=${BOOT_ID:-/proc/sys/kernel/random/boot_id}
# 상태 화면 앱이 읽는 알림 기록(1.7.2 hotspot.sh notice()와 같은 형식: "<초> <부팅 id> <문구>", 최근 5줄, 644)
NOTICE=${NOTICE:-/data/local/tmp/korea-projection-notice.txt}
MOD_ID=wireless-carplay-aa
SRC=$U/kp-rollback
# 되돌릴 판: 1.7.4 정식 패키지(hmgapi/wireless-carplay-aa.zip)에 든 2.4.5(md5가 1.7.4 MOD_MD5와 같음,
# mod-kor/wireless-carplay-aa-2.4.5.zip과 같은 파일. 2026-11-18 PC에서 대조함)
TO_VER=2.4.5
ZIP=$SRC/$MOD_ID-$TO_VER.zip
OLD_MD5=3ae048506f637548561f09fd5e549337
# 이 USB가 되돌리는 버전(1.8.0의 2.4.6·2.4.8·2.4.9, 1.8.1의 2.4.10)만. 2.4.6은 2.4.5와 코드가 같고 동글 차 항목만 더한 판이다.
# 2.4.8(1.8.0 베타 2)은 2.4.7의 길안내 고침에 동글 부팅 속성(sys.kp.dongle)을 더한 판이다. 2.4.7은 내보낸 적 없는 후보라 넣지 않는다.
# 2.4.9(1.8.0 정식)는 2.4.8에 무선 안드로이드 오토 포트(40515) 방화벽 허용 규칙(aa_firewall)만 더한 판이다(코드 같음).
# 2.4.10(1.8.1)은 무선 AA 준비 다시 보내기·계기판 길안내·기록 보강 판이다(1.8.1 메인 결정: 새 판에서도 되돌릴 수 있게).
# 다른 판(더 옛 판이나 다음 패키지의 새 판)은 건드리지 않는다
FROM_VERS=" 2.4.6 2.4.8 2.4.9 2.4.10 "
O=$D/out
UO=$SRC/log
$BB mkdir -p $O
# 지난 실행의 기록(install·plan·apply)이 이번 결과와 섞여 USB로 가지 않게 비운다
rm -f $O/*
# USB가 아직 꽂혀 있는가(grep 없이 셸로: busybox가 없어도 결과를 남기게)
usb_on() {
  while read -r _a _b _c; do [ "$_b" = "$U" ] && return 0; done < ${MOUNTS:-/proc/mounts}
  return 1
}
copy_out() {
  usb_on 2>/dev/null || return 0
  $BB mkdir -p $UO 2>/dev/null && $BB cp $O/* $UO/ 2>/dev/null
  [ -f $O/RESULT.txt ] && $BB cp $O/RESULT.txt $SRC/RESULT.txt 2>/dev/null
  sync
}
trap 'copy_out' EXIT
log() { echo "$(date '+%m-%d %H:%M:%S') $1" >> $O/rollback.log; }
# 상태 화면 알림 기록에 한 줄 더한다(앞의 4줄을 남겨 5줄). 실패해도 되돌리기 결과에는 영향 없음
notice() {
  _nb=$(cat $BOOT_ID 2>/dev/null)
  _nt=$NOTICE.rb.$$
  ( umask 022
    if [ -n "$BB" ]; then
      { [ -f $NOTICE ] && $BB awk '{ a[NR] = $0 } END { s = NR - 3; if (s < 1) s = 1; for (i = s; i <= NR; i++) print a[i] }' $NOTICE
        echo "$(date +%s) ${_nb:-none} $1"; } > $_nt && $BB chmod 644 $_nt && $BB mv -f $_nt $NOTICE
    else
      # busybox가 없으면 새 줄 하나만(toolbox mv는 옵션을 모른다)
      echo "$(date +%s) ${_nb:-none} $1" > $_nt && chmod 644 $_nt && mv $_nt $NOTICE
    fi
    rm -f $_nt ) 2>/dev/null
  return 0
}
# 결과 한 번: USB의 RESULT.txt(자세히), 상태 화면(짧게), 기록
result() {
  log "결과: $1"
  { echo "Korea Projection 되돌리기 USB 결과 ($(date '+%Y-%m-%d %H:%M:%S'))"
    echo "$1"
    echo "자세한 기록: kp-rollback/log/rollback.log"; } > $O/RESULT.txt
  notice "되돌리기 USB: $1"
}
# 차에 있는 무선 모드의 버전(mod.json의 첫 "version" 줄). 숫자와 점만 남긴다(기록·문구에 쓰므로)
mod_ver() {
  _mv=
  while IFS= read -r _l; do
    case "$_l" in
      *'"version"'*) _mv=${_l#*\"version\"}; _mv=${_mv#*\"}; _mv=${_mv%%\"*}; break ;;
    esac
  done < $HMGDATA/mods/$MOD_ID/mod.json 2>/dev/null
  case "$_mv" in *[!0-9.]*) _mv="?" ;; esac
  echo "$_mv"
}

log "시작: 모드 $(mod_ver), 고정 $([ -f $BK/mod.pin ] && echo 있음 || echo 없음)"
if [ -f $SRC/UNPIN ]; then
  rm -f $BK/mod.pin $BK/mod.upd
  log "고정 풀기"
  # 리뷰 반영: 무조건 약속하지 않는다(패키지가 지워졌거나 다른 판이면 바뀌지 않음). 동작은 그대로
  result "고정을 풀었습니다. Korea Projection 1.8.0 이상이 설치돼 있으면 재부팅 약 3분 뒤 새 버전으로 다시 바뀝니다."
  exit 0
fi
if [ -z "$BB" ]; then
  result "busybox를 찾지 못해 파일을 확인할 수 없습니다. 아무것도 바꾸지 않았습니다. Korea Projection 1.8.0 이상이 설치돼 있는지 확인해 주세요."
  exit 1
fi
if ! hmgapid ping >/dev/null 2>&1; then
  result "HMG-API가 응답하지 않아 아무것도 바꾸지 않았습니다. 재부팅 뒤 USB를 다시 꽂아 주세요."
  exit 1
fi
# 부팅 2분 뒤 korea.projection 자동 설정이 HMG-API 엔진을 쓰는 중이면 겹치지 않게 그만둔다(엔진에는 잠금이 없다)
if [ -f $KW/fix.pid ]; then
  set -- $(cat $KW/fix.pid 2>/dev/null)
  if [ -n "$1" ] && [ -d $PROC/$1 ] && [ "$2" = "$(cat $BOOT_ID 2>/dev/null)" ]; then
    result "Korea Projection이 설정을 확인하는 중입니다. 3분쯤 뒤에 USB를 다시 꽂아 주세요."
    exit 1
  fi
fi
if [ ! -f $HMGDATA/mods/$MOD_ID/mod.json ]; then
  result "무선 모드가 없어 되돌릴 것이 없습니다. 아무것도 바꾸지 않았습니다."
  exit 1
fi
set -- $($BB md5sum < $ZIP 2>/dev/null)
if [ "$1" != $OLD_MD5 ]; then
  log "zip md5 다름: ${1:-없음}"
  result "USB의 되돌리기 파일이 맞지 않습니다. 아무것도 바꾸지 않았습니다."
  exit 1
fi
CUR=$(mod_ver)
# 계획을 보고 이 모드의 변경뿐이면 적용한다. $1=new(방금 설치함) 또는 resume(이미 되돌릴 판·고정: 설치는 됐는데 적용 전에
# 꺼진 경우 다시 꽂으면 이어서, 마지막 묶음 중간 3②). 결과를 쓰고 이 스크립트를 끝낸다.
plan_apply() {
  # 아래 set -- 이 위치 인자를 바꾸므로 갈래를 먼저 둔다
  _pm=$1
  # 되돌리기 USB 최종(중간 1): 계획 명령이 실패했거나 아무것도 내지 않으면 적용하지 않는다. 오류 줄을 "할 일"로 세어
  # 확인 없이 적용하면 다른 모드가 쌓아 둔 변경까지 적용될 수 있다(패키지 plan_only_ours·plan_nothing과 같은 판단)
  if ! hmgapid engine plan > $O/plan.txt 2>&1 || [ ! -s $O/plan.txt ]; then
    log "계획 확인 실패(종료 코드 또는 빈 출력)"
    result "HMG-API 계획을 확인하지 못해 적용하지 않았습니다(무선 모드 $(mod_ver), 고정 $([ -f $BK/mod.pin ] && echo 있음 || echo 없음)). HMG-API 앱에서 변경 사항을 확인한 뒤 재부팅해 주세요."
    exit 1
  fi
  bad=0
  while IFS= read -r l; do
    case "$l" in
      "change   "*|"update   "*) set -f; set -- $l; [ "$3" = "[$MOD_ID]" ] || bad=1; set +f ;;
      "setting  "*" back to stock"*) bad=1 ;;
      # "nothing changed … problem"은 할 일 없음이 아니라 문제다(패키지 plan_nothing과 같게)
      "nothing changed"*problem*) bad=1 ;;
      "setting  "*"[$MOD_ID]"*|"same     "*|"nothing changed"*) ;;
      "setting  "*|"problem  "*|"restore  "*|"rebase   "*|"bind     "*|"unbind   "*|"hooks "*) bad=1 ;;
    esac
  done < $O/plan.txt
  if [ $bad = 1 ]; then
    if [ "$_pm" = resume ]; then result "이미 ${TO_VER}로 고정되어 있습니다. HMG-API 앱에서 변경 사항을 적용한 뒤 재부팅해 주세요."
    else result "${TO_VER}로 바꿨습니다. HMG-API 앱에서 변경 사항을 적용한 뒤 재부팅해 주세요."; fi
    exit 0
  fi
  # 모든 줄이 "same"(이미 그대로)·"nothing changed"·"hook plan:"뿐이면 적용할 것이 없다
  _todo=0
  while IFS= read -r l; do
    # 1.7.3(리뷰 L-4): "note"는 HMG-API 안내 줄일 뿐 변경이 아니다(패키지 plan_nothing과 같게).
    # 마지막 묶음 L3: "WARNING"(ADB TCP 스위치 경고 등)도 정보일 뿐이다(패키지 plan_nothing·plan_only_ours와 같게)
    case "$l" in "same     "*|"hook plan:"*|"note     "*|"nothing changed"*|"WARNING"*|"") ;; *) _todo=1 ;; esac
  done < $O/plan.txt
  if [ $_todo = 0 ] && [ "$_pm" = resume ]; then
    result "이미 ${TO_VER}로 고정되어 있습니다. 아무것도 바꾸지 않았습니다."
    exit 0
  fi
  if [ $_todo = 1 ]; then
    if ! hmgapid engine apply > $O/apply.txt 2>&1; then
      result "${TO_VER}로 바꿨지만 적용하지 못했습니다. HMG-API 앱에서 적용한 뒤 재부팅해 주세요."
      exit 1
    fi
    log "적용함"
  fi
  if [ "$_pm" = resume ]; then result "이미 ${TO_VER}로 고정되어 있어 남은 적용을 마쳤습니다. 재부팅해 주세요."
  else result "무선 모드를 ${TO_VER}로 되돌리고 고정했습니다. 재부팅해 주세요."; fi
  exit 0
}
# Korea Projection이 넣은 모드(mod.ours, 한국 차 항목 있음)만 바꾸거나 고정한다. 차주의 다른 판은 덮어쓰지 않는다
if [ ! -f $BK/mod.ours ] || ! $BB grep -q '"KOR"' $HMGDATA/mods/$MOD_ID/mod.json 2>/dev/null; then
  result "차의 무선 모드가 Korea Projection 것이 아닙니다. 아무것도 바꾸지 않았습니다."
  exit 1
fi
# 1.7.3(K-9): 이미 되돌릴 판(2.4.5)이면 바꾸지도 고정하지도 않는다. 아직 2.4.5인 차(업데이트 전)를 고정해 두면 나중에 새 판이 나와도
# 바뀌지 않아 그 까닭을 알기 어렵다.
# 이미 고정돼 있으면(이 USB가 설치까지 한 차) 계획 확인·적용 단계를 이어서 한다(마지막 묶음 중간 3②: 적용 전에 꺼진 경우)
if [ "$CUR" = $TO_VER ]; then
  if [ -f $BK/mod.pin ]; then log "이미 $TO_VER·고정: 계획 확인·적용 단계를 이어서 함"; plan_apply resume
  else result "지금 무선 모드는 이미 $TO_VER입니다. 아무것도 바꾸지 않았습니다(1.8.0 이상의 버전으로 바뀐 뒤에 쓰는 USB입니다)."; fi
  exit 0
fi
case "$FROM_VERS" in
  *" $CUR "*) ;;
  *) result "지금 무선 모드(${CUR:-모름})는 이 USB가 되돌리는 버전(1.8.0·1.8.1의 2.4.6·2.4.8·2.4.9·2.4.10)이 아닙니다. 아무것도 바꾸지 않았습니다."
     exit 1 ;;
esac
# 리뷰 L7: 고정 표시는 설치 **전에** 쓴다. 설치 도중 패키지 서비스(mod_update)가 끼어들어 1.8.0 판으로 다시 바꾸지 않게.
# 설치가 실패하면 고정을 지운다. 여기까지 온 차는 지금 판이 1.8.0 판(FROM_VERS)이므로, 전에 있던 고정도 낡은 것(설치 전에 꺼진 실행이
# 남긴 것 등)으로 보고 함께 지운다(마지막 묶음 중간 3①: 1.8.0 판 차에 고정만 남아 새 판으로 못 가는 길을 막음)
# 1.7.4(B-8 ②): 고정한 판 번호를 적는다(패키지가 화면·리포트에 "무선 모드 고정: 2.4.5"로 보임)
$BB mkdir -p $BK 2>/dev/null; echo "$TO_VER" 2>/dev/null > $BK/mod.pin
# 묶음 E 리뷰(낮음 1): 설치 직후 전원이 끊겨도 고정이 남게 한 번 내려 쓴다. sync가 없거나 실패해도 멈추지 않는다
sync >/dev/null 2>&1 || :
# 1.7.4(D-12): 고정 파일이 실제로 써졌는지(내용이 $TO_VER인지) 셸로 다시 읽어 본다. 못 썼으면 설치하지 않는다:
# 고정 없이 2.4.5를 넣으면 패키지 서비스(mod_update)가 다음 부팅에 1.8.0 판으로 다시 바꾼다. 차는 지금 판 그대로 둔다
# 묶음 E 리뷰(낮음 2): 파일이 없으면 읽지 않는다(옛 mksh에서 없는 파일 리다이렉션 대비). 결과는 같다(빈 값 → 멈춤)
_pv=; [ -f $BK/mod.pin ] && { read -r _pv < $BK/mod.pin; } 2>/dev/null
if [ "$_pv" != "$TO_VER" ]; then
  rm -f $BK/mod.pin 2>/dev/null
  log "고정 파일 쓰기 실패: 설치하지 않음"
  result "고정 파일을 쓰지 못해 되돌리지 않았습니다. 지금 버전($CUR) 그대로입니다. USB의 kp-rollback 폴더를 보내 주세요."
  exit 1
fi
if ! hmgapid engine install $ZIP --force > $O/install.txt 2>&1; then
  rm -f $BK/mod.pin
  # 1.8.0: 동글 차는 2.4.5에 동글 차 항목이 없어 거부가 정상이다(안내서). 그 경우를 먼저 적어 쓸데없는 제보가 없게
  result "HMG-API가 거부해 되돌리지 못했습니다. 지금 버전($CUR) 그대로입니다. USB Wi-Fi 동글로 쓰는 차라면 정상입니다(이 USB를 쓰지 않음). 그 밖에는 USB의 kp-rollback 폴더를 보내 주세요."
  exit 1
fi
# 되돌리기 USB 최종(낮음 2): 설치했다는 엔진 말만 믿지 않고 판을 다시 본다. 되돌릴 판(2.4.5)이 아니면 고정을 풀고 실패로 알린다
# ("되돌리고 고정했습니다"가 거짓으로 나오지 않게, 고정만 남아 새 판으로도 못 가지 않게)
_nv=$(mod_ver)
if [ "$_nv" != $TO_VER ]; then
  rm -f $BK/mod.pin
  log "설치 뒤 판이 $TO_VER이 아님: ${_nv:-모름}"
  result "무선 모드를 ${TO_VER}로 바꾸지 못했습니다(지금 ${_nv:-모름}, 고정은 풀었습니다). USB의 kp-rollback 폴더를 보내 주세요."
  exit 1
fi
log "설치함: $_nv"
plan_apply new
