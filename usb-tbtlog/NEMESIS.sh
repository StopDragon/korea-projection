#!/system/bin/sh
umask 077
# 계기판 길안내 기록 USB(kp-tbtlog, NEMESIS.sh type=execute). 2026-11-17, **읽기만** 한다.
# 하는 일: 순정 내비로 길안내를 받으며 달리는 동안, 순정 내비가 계기판에 보내는 값을 logcat에서 골라 이 USB에 적는다.
#   - Korea Projection 무선 모드의 관찰 줄(HMG-API "stock navigation: …"): 회전 표시 번호·옆길·방향·막대·차로 프레임 등.
#     순정 계기판 서비스는 회전 번호를 로그에 남기지 않아 이 줄이 유일한 출처다(디버그 로그가 켜져 있어야 나온다).
#   - 순정 계기판 서비스(ClusterService)·NavigationCluster 줄 가운데 길안내 숫자만(남은 거리, 2C, 단속 정보의 막대 등).
#   - 우리 폰 안내 줄(HMG-API "CarPlay: maneuver …", "AA: turn ev …"): 같은 길을 카플레이·AA로 달려 견줄 때 쓴다.
#     11-23(소유자 요청): 무선 모드 진단 줄 "CarPlay diag: maneuver …"(폰이 준 남은 거리 remain, 곧 회전 막대가 한 칸 줄 때마다
#     한 줄, 디버그 로그가 켜져 있어야 나오고 무선 모드 프로세스당 300줄까지)도 남긴다. 폰 회전과 ADASIS 교차로(STUB)를 거리로 맞추려고.
#   - 차량 신호(V)·GPS(G), 소유자 요청(2026-11-17 저녁): 로그에 이미 남는 것만. 차속(VehicleInfoManager·BCMService·내비 엔진),
#     기어·주차 브레이크, 야간·조명, 카플레이로 보내는 PASCD, 맵매칭 상태, GisUtil 방위·고도, ADASIS 경로 위 위치(STD_POS_P),
#     GpsLocationProvider 위치 줄. 값이 앞 줄과 같으면 남기지 않는다. 조향각·방향지시등은 로그에 없어 받지 않는다.
# 꽂고 "예"를 누르면 뒤에서 도는 기록 하나를 띄우고 바로 끝난다. 그 기록은 15초마다 logcat 버퍼를 한 번 읽어(logcat -d)
#   새 줄만 덧붙이고, 180분이 지나거나·USB가 빠지거나·기록이 30MB를 넘으면 저절로 끝난다(끝나는 조건이 셋 다 있음).
# 동의: USB 맨 위에 KP-AGREE.txt(안내문을 읽은 차주가 KP-NOT-AGREED.txt 이름을 바꿈)가 없으면 기록하지 않는다(NM-8, 아래 tb_agreed).
# 하지 않는 것: 아래 알림 한 줄 말고는 내비에 쓰기(/system·/data, 설정, 디버그 로그 켜기·끄기), 서비스 시작·멈춤, logcat 비우기(-c),
#   CAN·MICOM 보내기. 쓰는 곳은 이 USB의 KoreaProjection-private/tbtlog-<시각>/ 폴더와 그 옆 tbtlog.pid,
#   그리고 상태 화면 알림 기록 한 줄(/data/local/tmp/korea-projection-notice.txt, 소유자 요청 11-17)뿐이다.
#   꽂을 때(정차 중) Korea Projection 상태 화면을 한 번 연다. 끝날 때는 알림만 쓰고 화면은 열지 않는다.
# 위치 정보: 소유자 결정(2026-11-17)으로 남긴다. 교차로·목적지 이름, ADASIS 제어점(PROSHORT·PROLONG의 countrolPoint),
#   카플레이 길안내 앱 이름은 그대로(종류 L) 적는다. 지하차도·고가 위치와 그때 순정 값을 맞춰 보려고. 결과는 비공개로만 둔다.
# 적지 않는 것: 폰 이름, MAC, VIN, 그 밖의 태그 전부. 줄 종류를 허용 목록으로 고르고, 계기판 서비스 숫자 줄(C)은 "이름=숫자"
#   쌍만 남긴다(이름에 mac·ssid·vin 등이 든 쌍은 버림). 위치 줄(L)은 제어 문자만 빼고 그대로 둔다.
# busybox: 내비의 것(1.8.1)을 쓰고, 없는 내비는 Korea Projection 패키지에 든 것을 쓴다. 없으면 그 사실만 적고 끝난다.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
# USB가 실제로 마운트된 곳에만 쓴다(빈 마운트 지점이면 내비에 쓰게 되므로). 동글 진단·모듈 복사 USB와 같은 방식
tb_mounted() {
  while read -r _ma _mb _mc; do [ "$_mb" = "$1" ] && return 0; done < ${MOUNTS:-/proc/mounts}
  return 1
}
BB_SYS=${BB_SYS:-/system/bin/busybox}
BB_OWN=${BB_OWN:-/data/nemesis/apps/korea.projection/bin/busybox}
if [ -z "$BB" ]; then
  if [ -x "$BB_SYS" ]; then BB=$BB_SYS
  elif [ -x "$BB_OWN" ] && "$BB_OWN" true >/dev/null 2>&1; then BB=$BB_OWN
  fi
fi
# 무선 모드 관찰 줄(StockLog)이 나오는 조건: 이 파일이 부팅 때 있었음(패키지 디버그 로그 켜기 파일). 있는지만 본다
DEBUGF=${DEBUGF:-/data/local/tmp/korea.projection/debug}
UPTIME=${UPTIME:-/proc/uptime}
PROCD=${PROCD:-/proc}
LOGCAT=${LOGCAT:-logcat}
# 기록 시간(분)·읽는 간격(초)·크기 상한(바이트). logcat 버퍼는 main·system을 따로 읽는다. 차 기록에서 main은 바쁠 때
# 약 40초 치만 남은 적이 있어(리뷰 M3) 간격을 15초로 두었다.
# 11-20 운행: 길안내 중 main은 약 30초 치만 남았고, 읽고 거르는 데 4~5초가 걸려 실제 간격이 19~20초였다. 그래서 회차의 약 5%에서
#   main이 넘쳐 4~13초씩 빠졌다(모두 1.5% 아래). 소유자 승인(11-20)으로 간격을 10초로 줄인다(실제 약 14~15초)
# 소유자 결정(2026-11-18 새벽): 3시간 또는 30MB 가운데 먼저 차는 쪽까지 기록한다. 120분이 약 4MB여서(차량 신호 포함 추정) 30MB는 안전 상한이다
TB_MIN=${TB_MIN:-180}
TB_INT=${TB_INT:-10}
TB_MAXB=${TB_MAXB:-31457280}
# 리뷰(낮음 L2): 숫자가 아니면 기본값(산술 오류로 멈추지 않게)
case "$TB_MIN" in ''|*[!0-9]*) TB_MIN=180 ;; esac
case "$TB_INT" in ''|*[!0-9]*) TB_INT=10 ;; esac
case "$TB_MAXB" in ''|*[!0-9]*) TB_MAXB=31457280 ;; esac
# 태그 요약(tags.txt)에 둘 서로 다른 태그 수 상한(소유자 결정 11-18). 넘는 태그의 줄은 버퍼·등급마다 "(상한 넘음)" 한 줄로 묶는다
TB_TAGMAX=${TB_TAGMAX:-3000}
case "$TB_TAGMAX" in ''|*[!0-9]*) TB_TAGMAX=3000 ;; esac
case "$TB_PASSES" in *[!0-9]*) TB_PASSES= ;; esac
TB_PASSES=${TB_PASSES:-$((TB_MIN * 60 / (TB_INT > 0 ? TB_INT : 1)))}
LOOPARG=kp-tbtlog-loop
# 시각(11-20 운행): busybox date는 내비의 시간대를 읽지 않아 폴더 이름·요약·회차 시각이 UTC로 적혔다(logcat은 한국 시간).
#   내비 시간대를 읽어 TZ로 내보내고 요약에 기준을 적는다(소유자 승인 11-20, 11-23 고침 아래).
#   리뷰(11-20 낮음 2): TZ를 내보내므로 여기서 부르는 logcat의 시각도 같은 기준이 된다(bionic은 TZ를 먼저 봄)
# 11-23 운행(메인 승인): 니로의 값은 "Mobis/UTC+09:00"이었다. Asia/Seoul만 보던 11-20 판은 이 값을 UTC로 보고 TZ=UTC0을 내보내
#   logcat까지 UTC가 됐다. 그래서 "UTC+hh:mm"·"GMT+hh:mm"·"UTC+h" 꼴은 오프셋을 읽어 POSIX TZ(부호가 반대)로 바꾸고,
#   읽지 못하면(빈 값·다른 이름) TZ를 건드리지 않는다(logcat은 내비 시각 그대로, 우리 date는 busybox 기본 = 보통 UTC)
tb_tz() {
  case "$1" in
    Asia/Seoul) TZ=KST-9; TZL="KST(한국 시간)"; TZS=1; return 0 ;;
    # tz 데이터베이스의 Etc/GMT+9는 부호가 반대(UTC-9)라 읽지 않는다
    Etc/*|*/Etc/*) return 1 ;;
    *UTC[+-]*) _o=${1##*UTC} ;;
    *GMT[+-]*) _o=${1##*GMT} ;;
    *) return 1 ;;
  esac
  _sg=; case "$_o" in +*) _sg=- ;; -*) _sg=+ ;; esac
  _o=${_o#?}; _h=${_o%%:*}; _m=00
  case "$_o" in *:*) _m=${_o#*:} ;; esac
  case "$_sg$_h$_m" in [+-][0-9][0-9]|[+-][0-9][0-9][0-9]|[+-][0-9][0-9][0-9][0-9]) ;; *) return 1 ;; esac
  case "$_m" in [0-5][0-9]) ;; *) return 1 ;; esac
  case "$_h" in [0-9]|0[0-9]|1[0-4]) ;; *) return 1 ;; esac
  _h=${_h#0}; [ -n "$_h" ] || _h=0
  if [ "$_sg$_h$_m" = "-900" ]; then TZ=KST-9; TZL="KST(한국 시간)"
  else TZ="LOC$_sg$_h:$_m"; [ "$_sg" = - ] && _sh=+ || _sh=-; TZL="UTC$_sh$_h:$_m(내비 시간대)"; fi
  TZS=1
  return 0
}
TZS=
if tb_tz "$(getprop persist.sys.timezone 2>/dev/null)"; then export TZ
else TZL="내비 시간대를 읽지 못함(폴더 이름·이 요약·1-passes.txt는 busybox 기본 시각, 환경에 TZ가 없으면 UTC)"; fi

# 거르기 awk. 입력은 logcat -v time 꼴("MM-DD HH:MM:SS.mmm P/Tag( pid): 내용"). 줄마다 종류를 붙여 남긴다:
#   S = 순정 관찰 줄(stock navigation), C = 계기판 서비스(ClusterService), N = NavigationCluster, P = 우리 폰 안내 줄,
#   L = 위치 줄(교차로·목적지 이름, ADASIS 제어점, 길안내 앱 이름), V = 차량 신호, G = GPS(방위·고도, 경로 위 위치, 드문 위치 줄)
#   V·G는 바뀔 때만 남기므로, 줄이 없으면 값이 그대로였다는 뜻일 수 있다(기록이 돌았는지는 1-passes.txt로 본다)
# 새 줄만: 지난번 마지막 시각(lt)보다 늦은 줄, 같은 시각이면 지난번에 이미 적은 개수(ln) 다음부터. 버퍼(main·system)마다 따로 센다.
# 리뷰(M3): 이 버퍼의 가장 오래된 줄이 지난번에 본 이 버퍼의 가장 늦은 줄(mx, 거른 줄만이 아니라 모든 줄)보다 늦으면
#   사이에 빠진 줄이 있을 수 있다(gap).
# 리뷰(M4): 버퍼 안에서 시각이 1초 넘게 거꾸로 가거나(시계를 맞춤) 버퍼 전체가 lt보다 이르면 back.
#   11-20 운행: 여러 프로세스가 동시에 쓰면 몇 ms 차이로 줄 순서가 바뀌어 회차의 약 30%에 알림이 났다. 1초 안의 뒤바뀜은 알리지 않는다. 버퍼 전체가 이르면 그 버퍼를 다 적고,
#   일부만 거꾸로면 lt보다 이른 줄은 빠질 수 있다(알림만). 다음 기준(nlt)은 적은 줄 가운데 가장 늦은 시각이다.
# 끝에 상태 한 줄(마지막 시각|그 시각의 줄 수|이번에 더한 줄|gap|back|이 버퍼의 가장 늦은 시각)을 st 파일에 쓴다.
# 태그 요약(소유자 결정 11-18, 통째 logcat 대신): 새로 읽은 모든 줄의 버퍼·등급·태그별 줄 수만 센다. 줄 내용(msg)은 남기지 않는다.
#   태그는 "P/" 뒤부터 "( pid): " 앞까지(뒤 공백 뺌). 거르는 줄과 상관없이 모든 줄을 세므로 이어 읽는 자리(tlt·tln)를 따로 둔다.
#   누적 값과 버퍼마다의 이어 읽는 자리는 tags.txt에 있어 logcat 앞에 붙여 넘기고, 새 값을 tt에 써서 셸이 바꿔 넣는다(회차마다. 도중에 끊겨도 남게).
#   태그 이름은 영문 인쇄 문자만 남기고(나머지는 ?), MAC 꼴과 7자리 이상 숫자는 #로 가리고, 64자에서 자른다.
TBF='
function keep(s) { gsub(/[^A-Za-z0-9 ._:=,()\/+-]/, "", s); sub(/ +$/, "", s); return substr(s, 1, 300) }
function raw(s) { gsub(/[[:cntrl:]]/, "", s); return substr(s, 1, 400) }
# 차량 신호·GPS(V·G): 같은 이름의 값이 앞 줄과 같으면 남기지 않는다(줄 수를 줄이려고. 여러 프로세스가 같은 값을 찍는 것도 걸러짐)
# 리뷰(11-18 낮음 1): 같은 값이면 빈 값이 아니라 표시(\001)를 돌려준다. 그 줄은 적지 않지만 "그 시각의 줄 수"에는 센다.
#   그래야 회차 사이에 버퍼 앞이 밀려 앞 값이 사라져도, 같은 시각에서 이어 읽는 자리가 어긋나 줄이 겹치지 않는다
function chg(k, s) { if (s == "") return ""; if (s == lastv[k]) return "\001"; lastv[k] = s; return s }
# 시각 문자열("MM-DD HH:MM:SS.mmm")의 그날 초. 날짜가 다르면 하루를 더해 견준다(리뷰 11-20 낮음 3: 자정을 넘는 ms 뒤바뀜).
#   하루보다 먼 날짜 차이(시계를 크게 맞춤)는 날짜 문자열이 거꾸로이므로 큰 차이로 본다
function tsec(s) { return substr(s, 7, 2) * 3600 + substr(s, 10, 2) * 60 + substr(s, 13, 6) }
function back1(a, b) { if (substr(a, 1, 5) == substr(b, 1, 5)) return tsec(a) - tsec(b) > 1; return tsec(a) + 86400 - tsec(b) > 1 }
function num(s) { sub(/^[^0-9-]*/, "", s); return s + 0 }
function pairs(s, allow,   o, k, v, t, n) {
  o = ""; n = 0
  while (match(s, /[A-Za-z_][A-Za-z0-9_]*[ ]*[:=][ ]*-?[0-9]+(\.[0-9]+)?/)) {
    t = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
    k = t; sub(/[ ]*[:=].*/, "", k); v = t; sub(/^[^:=]*[:=][ ]*/, "", v)
    if (allow != "" && index(" " allow " ", " " k " ") == 0) continue
    # 허용 목록을 준 경우(V·G)는 그 목록만 믿는다(relativeHeading의 "lat"처럼 이름 속 낱말로 잘못 버리지 않게)
    if (allow == "" && tolower(k) ~ /lat|lon|lng|gps|year|month|day|hour|minute|second|controlpoint|countrolpoint|dest|name|addr|poi$|coord|mac|ssid|vin/) continue
    o = o " " k "=" v
    if (++n >= 40) break
  }
  return o
}
# 태그 이름 거르기(이름에 개인정보가 섞여 나올 수 있어서)
function tagk(s,   lv, t) {
  lv = substr(s, 1, 1); t = substr(s, 3); sub(/^ +/, "", t); sub(/ +$/, "", t)
  if (t == "\001") return buf " " lv " (태그 못 읽음)"
  gsub(/[^ -~]/, "?", t)
  gsub(/[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f:]*/, "#", t)
  # 11-24(공개 리뷰 중간 3): 하이픈 전화번호 꼴과 콜론 없는 MAC 꼴(16진 12자)도 가린다. 영문 이름·VIN 꼴은 가리지 못한다(안내문에 적음)
  gsub(/[0-9][0-9][0-9]*-[0-9][0-9][0-9][0-9]*-[0-9][0-9][0-9][0-9]/, "#", t)
  gsub(/[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]/, "#", t)
  gsub(/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*/, "#", t)
  t = substr(t, 1, 64); if (t == "") t = "(빈 태그)"
  return buf " " lv " " t
}
BEGIN {
  n = 0; first = ""; maxts = ""; prev = ""; inv = 0; lnn = ln + 0
  an = 0; amax = ""; tlt = ""; tln = 0; nk = 0; oc = ""; ph = 0; pm = (mx == "")
}
# 입력 앞부분은 지금까지의 태그 요약(tags.txt), "#kp-tags-end" 줄 뒤가 logcat이다.
#   리뷰 전 확인: 차의 busybox 1.8.1 awk는 getline < 파일에서 멈추고, 열지 않은 파일의 close()에서 죽어서 이렇게 넘긴다
ph == 0 {
  if ($0 == "#kp-tags-end") { ph = 1; next }
  if (substr($0, 1, 5) == "#cur ") {
    # 이어 읽는 자리: "#cur <버퍼> <시각>|<그 시각의 줄 수>"
    if (substr($0, 6, length(buf) + 1) == buf " ") { tlt = substr($0, length(buf) + 7); tln = tlt; sub(/\|.*/, "", tlt); sub(/^[^|]*\|/, "", tln); tln += 0 }
    else oc = oc $0 "\n"
    next
  }
  if ($0 ~ /^[0-9]+ /) { k = $0; sub(/^[0-9]+ /, "", k); if (!(k in K)) nk++; K[k] += $1 }
  next
}
{
  # 태그 요약용: 머리가 있는 모든 줄의 시각과 "등급/태그"만 둔다(내용은 두지 않음)
  if (match($0, /^[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9][0-9][0-9] [A-Z]\//)) {
    an++; AT[an] = substr($0, 1, 18); ca[AT[an]]++; if (AT[an] > amax) amax = AT[an]
    r = substr($0, 20)
    if (match(r, /\([ ]*[0-9]+\): /)) AR[an] = substr(r, 1, RSTART - 1); else AR[an] = substr(r, 1, 2) "\001"
  }
  if (!match($0, /^[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9][0-9][0-9] [VDIWEF]\/[A-Za-z0-9_-]+[ ]*\([ ]*[0-9]+\): /)) next
  head = substr($0, 1, RLENGTH); msg = substr($0, RLENGTH + 1); ts = substr($0, 1, 18)
  if (first == "") first = ts
  # 11-23 운행(메인 승인): 한 번 생긴 뒤바뀜이 버퍼에 몇 분 남아 회차마다 다시 알렸다(15회차). 지난번에 본 가장 늦은 줄(mx)에
  #   닿은 뒤(pm)의 뒤바뀜만 알린다. 줄 순서 바뀜은 많아야 두 회차 알린다. 리뷰(11-23 중간 1): 시계를 회차 간격보다 크게 되돌리면
  #   시계가 mx를 따라잡을 때까지 회차마다 알린다. 그동안은 새 줄이 lt보다 이르다고 빠지므로 알리는 편이 맞다.
  #   리뷰(11-23 낮음 2): 해가 바뀌는 순간(12-31 → 01-01)도 문자열로는 거꾸로라 알리고, 그 뒤 줄이 빠질 수 있다(새해 자정 운행만)
  if (prev != "" && ts < prev && pm && back1(prev, ts)) inv = 1
  if (ts >= mx) pm = 1
  prev = ts
  if (ts > maxts) maxts = ts
  tag = head; sub(/^[^\/]*\//, "", tag); sub(/[ ]*\(.*/, "", tag)
  o = ""
  if (tag == "HMG-API") {
    if ((i = index(msg, "stock navigation: ")) > 0) o = "S " keep(substr(msg, i + 18))
    else if ((i = index(msg, "CarPlay: route guidance source ")) > 0) o = "L " raw(substr(msg, i))
    else {
      # 리뷰(L4): "[모드 이름] " 바로 뒤에서 시작하는 줄만(다른 줄 안의 같은 낱말은 거름)
      # 11-20(소유자 승인): 카플레이 길안내 구독이 끊겼다 다시 붙는지(모드 2.4.7 RgAsk) 보려고 "route guidance came back·asked again·
      #   asks ended", "no route guidance …", "turn-by-turn to the cluster …" 줄도 남긴다(숫자·고정 문구뿐)
      # 11-24(리뷰 낮음 3): 진단 줄 "CarPlay diag: …"는 숫자가 이어지는 두 머리말만 받는다. keep()은 영문 이름·MAC 꼴을 지우지 못하므로,
      #   무선 모드가 이 머리말 줄에 문자열(폰 이름·도로 이름)을 더하면 여기서 다시 걸러야 한다(지금은 숫자와 고정 낱말뿐, CpTurnsFit.diag)
      if ((i = index(msg, "] ")) > 0) msg = substr(msg, i + 2)
      if (msg ~ /^(CarPlay: (maneuver |near layout|far layout|hud list |route search|route guidance (came back after the iAP2 handover|asked again after the iAP2 handover|asks ended by)|no route guidance (after [0-9]+ asks|from the phone for [0-9]+ s)|turn-by-turn to the cluster \()|CarPlay diag: (maneuver -?[0-9]+ type -?[0-9]+ |lane guidance index -?[0-9]+ lanes -?[0-9]+$)|AA: (turn ev |rerouting|name change kept))/) o = "P " keep(msg)
    }
  } else if (tag == "NavigationCluster") {
    if (msg ~ /^updateTBTSubInfo\(\)/) o = "N updateTBTSubInfo" pairs(substr(msg, 19), "")
    else if (msg ~ /^direction must be between/) o = "N warn direction out of range"
    else if (msg ~ /^combiSideStreet must be between/) o = "N warn combiSideStreet out of range"
  } else if (tag == "ClusterService") {
    if (match(msg, /^NaviCluster\.(updateTBT[A-Za-z0-9_]*|updateRemainDis|updateCluData[A-Za-z0-9_]*|updateNaviWarnDist[A-Za-z0-9_]*|updateSLIFNaviInformation|updateISLWInformation)\(\)/))
      o = "C " substr(msg, 13, RLENGTH - 14) pairs(substr(msg, RLENGTH + 1), "")
    else if (match(msg, /^NaviCluster\.updateSTD_(SEG|STUB)_E[A-Za-z0-9_]*\(\)/))
      o = "C " substr(msg, 13, RLENGTH - 14) pairs(substr(msg, RLENGTH + 1), "")
    else if (msg ~ /^NaviCluster\.updateSTD_(PROSHORT|PROLONG)_E[A-Za-z0-9_]*\(\)/ || msg ~ /^updateTP(CrossroadName|FlexibleDestinationName)/)
      o = "L " raw(msg)
    else if (msg ~ /^NaviCluster\.updateSTD_POS_P_Info\(\)/)
      o = chg("pos", "G STD_POS_P" pairs(substr(msg, 35), "offset pathIndex positionAge positionProbability positionIndex rangeAvgSpeed currentLane positionConfidence relativeHeading"))
    else if (match(msg, /^NaviCluster\.sendDayNight\(\) mIsNight: (true|false)/))
      o = chg("cnight", "V clusterNight " substr(msg, 38, RLENGTH - 37))
  } else if (tag == "VehicleInfoManager") {
    # 차량 신호(소유자 요청 11-17 저녁): 차속(km/h), 기어(값의 뜻은 확인 안 함: 0·255만 봄), 주차 브레이크
    if (msg ~ /^\[onVehicleSpeedChanged\(\)\] speed: [0-9]+/) o = chg("speed", "V speed " num(substr(msg, 33)))
    else if (msg ~ /^\[onGearChanged\(\)\] gear: [0-9]+/) o = chg("gear", "V gear " num(substr(msg, 24)))
    else if (msg ~ /^\[onParkingBrakeChanged\(\)\] parkingBrake: [0-9]+/) o = chg("pbrake", "V parkingBrake " num(substr(msg, 40)))
  } else if (tag == "BCMService") {
    if (msg ~ /^mDisplaySpeedRaw : [0-9]+/) o = chg("dspeed", "V displaySpeed " num(substr(msg, 20)))
  } else if (tag == "CoNA") {
    if ((i = index(msg, "[SPEED] Set Display VehicleSpeed Changed : ")) > 0 && match(msg, /cur \[[0-9]+\]/))
      o = chg("nspeed", "V naviSpeed " substr(msg, RSTART + 5, RLENGTH - 6))
    else if ((i = index(msg, "[RG] [MM][Status] ")) > 0) o = chg("mm", "V mmStatus " raw(substr(msg, i + 18)))
  } else if (tag == "CarPlay_") {
    if (match(msg, /onGearStatus:: GearStatus\.[A-Z]+/)) o = chg("cpgear", "V cpGear " substr(msg, RSTART + 26, RLENGTH - 26))
    else if ((i = index(msg, "nmeaInfo_PASCD = $PASCD,")) > 0) o = "V pascd " raw(substr(msg, i + 18))
    else if (match(msg, /setNightMode\(\) isNightMode: (true|false)/)) o = chg("night", "V night " substr(msg, RSTART + 28, RLENGTH - 28))
    else if (match(msg, /onIlluminateStatusChanged dim:[0-9]+/)) o = chg("dim", "V dim " substr(msg, RSTART + 30, RLENGTH - 30))
  } else if (tag == "GisUtil") {
    # 위도·경도는 이 줄에서 가려져(***) 나오므로 방위·고도·정밀도만
    if (index(msg, "setGPSData mGPSDataList in gpsData = {") > 0) { o = pairs(msg, "HEADING ALT TYPE HDOP PDOP"); if (o != "") o = chg("gis", "G gis" o) }
  } else if (tag == "GpsLocationProvider") {
    if ((i = index(msg, "Location[gps ")) > 0) o = "G location " raw(substr(msg, i + 9))
  }
  if (o == "") next
  n++; L[n] = ts " " o; T[n] = ts; c[ts]++; DP[n] = (o == "\001")
}
END {
  gap = 0; back = 0; all = 0
  if (mx != "" && first != "" && first > mx) gap = 1
  if (lt != "" && maxts != "" && maxts < lt) all = 1
  if (all || inv) back = 1
  seen = 0; add = 0; nw = 0; nlt = all ? "" : lt; nln = lnn
  for (k = 1; k <= n; k++) {
    if (!all) {
      if (T[k] < lt) continue
      if (T[k] == lt) { seen++; if (seen <= lnn) continue }
    }
    nw++
    if (T[k] > nlt) nlt = T[k]
    if (DP[k]) continue
    print L[k] >> out; add++
  }
  if (nw > 0) nln = c[nlt] + 0
  else if (all) { nlt = maxts; nln = c[maxts] + 0 }
  # 태그 요약: 이어 읽는 자리 뒤의 줄만 센다(위와 같은 방법, 버퍼 전체가 이전 자리보다 이르면 다 셈)
  if (tt != "") {
    aall = (tlt != "" && amax != "" && amax < tlt); seen = 0; tw = 0; ntlt = aall ? "" : tlt; ntln = tln
    for (k = 1; k <= an; k++) {
      if (!aall) {
        if (AT[k] < tlt) continue
        if (AT[k] == tlt) { seen++; if (seen <= tln) continue }
      }
      tw++; if (AT[k] > ntlt) ntlt = AT[k]
      x = tagk(AR[k])
      if (!(x in K)) {
        if (nk >= tmax + 0) { x = buf " " substr(AR[k], 1, 1) " (상한 넘음)"; if (!(x in K)) nk++ }
        else nk++
      }
      K[x]++
    }
    if (tw > 0) ntln = ca[ntlt] + 0
    printf "%s\n", "# 태그 요약(기록 중이라 순서 없음). 칸: 줄 수, 버퍼, 등급, 태그 이름. 줄 내용은 적지 않습니다." > tt
    printf "%s", oc > tt
    if (ntlt != "") printf "%s %s %s|%d\n", "#cur", buf, ntlt, ntln > tt
    for (x in K) printf "%d %s\n", K[x], x > tt
    close(tt)
  }
  printf "%s|%d|%d|%d|%d|%s\n", nlt, nln, add, gap, back, (maxts == "" ? mx : maxts) > st
}'

# 지금 시각(초, 부팅 뒤). 못 읽으면 빈 값
up_s() { _u=; { read -r _u _x < $UPTIME; } 2>/dev/null; _u=${_u%%.*}; case "$_u" in ''|*[!0-9]*) echo "" ;; *) echo "$_u" ;; esac; }
now() { $BB date "+%H:%M:%S" 2>/dev/null; }
# 기록 폴더가 USB의 우리 자리이고 링크가 아니며, USB가 아직 마운트돼 있는가(쓰기 전마다 본다)
safe() { tb_mounted "$U" 2>/dev/null && [ ! -L "$ROOT" ] && [ -d "$OUTD" ] && [ ! -L "$OUTD" ] && [ ! -L "$OUTD/tbt.txt" ] && [ ! -L "$OUTD/tags.txt" ] && [ ! -L "$OUTD/.tags.tmp" ] && [ ! -L "$ROOT/tbtlog.pid" ]; }
# 동의 파일(NM-8): USB 맨 위에 KP-AGREE.txt가 있는가. 자세한 것은 아래 꽂는 쪽 주석
tb_agreed() {
  for _f in "$U"/[Kk][Pp]-[Aa][Gg][Rr][Ee][Ee]*; do
    case "${_f##*/}" in
      [Kk][Pp]-[Aa][Gg][Rr][Ee][Ee]|[Kk][Pp]-[Aa][Gg][Rr][Ee][Ee].[Tt][Xx][Tt]|[Kk][Pp]-[Aa][Gg][Rr][Ee][Ee].[Tt][Xx][Tt].[Tt][Xx][Tt]) ;;
      *) continue ;;
    esac
    [ -f "$_f" ] && [ ! -L "$_f" ] && return 0
  done
  return 1
}
# 상태 화면 알림(소유자 요청 2026-11-17, 토스트 대신). Korea Projection 상태 화면 앱이 읽는 알림 기록에 한 줄을 더한다.
#   형식·쓰는 방법은 패키지 hotspot.sh notice()와 같다: "<date +%s> <boot_id> <문구>", 최근 5줄, 임시 파일 → chmod 644 → mv.
#   앱은 이번 부팅·30분 안의 줄만 보인다. 이 파일만 내비 쪽에 쓴다(비밀값 없음). Korea Projection이 없으면 조용히 넘어간다
NOTICE=${NOTICE:-/data/local/tmp/korea-projection-notice.txt}
BOOT_ID=${BOOT_ID:-/proc/sys/kernel/random/boot_id}
KPDIR=${KPDIR:-/data/nemesis/apps/korea.projection}
AM=${AM:-am}
PM=${PM:-pm}
# 설치된 Korea Projection 판(NEMESIS.data의 package-version). 숫자와 점만 받는다. 없거나 이상하면 빈 값
tb_kpver() {
  _kv=; { while IFS='=' read -r _ka _kb; do [ "$_ka" = package-version ] && { _kv=$_kb; break; }; done < "$KPDIR/NEMESIS.data"; } 2>/dev/null
  case "$_kv" in ''|*[!0-9.]*|.*) echo "" ;; *) echo "$_kv" ;; esac
}
# 차에 깔린 무선 모드(HMG-API 모드 wireless-carplay-aa)의 판: mod.json의 첫 "version" 줄(읽기만, 패키지 hotspot.sh mod_ver와 같은 방법).
#   숫자와 점만 받는다. 없거나 이상하면 빈 값. 11-20 운행: 패키지는 1.8.0이어도 모드는 2.4.6(예전 한도)일 수 있어 따로 적는다
HMGMOD=${HMGMOD:-/data/hmgapi/mods/wireless-carplay-aa/mod.json}
tb_modver() {
  _mv=
  { while IFS= read -r _ml; do
      case "$_ml" in *'"version"'*) _mv=${_ml#*\"version\"}; _mv=${_mv#*\"}; _mv=${_mv%%\"*}; break ;; esac
    done < "$HMGMOD"; } 2>/dev/null
  case "$_mv" in ''|*[!0-9.]*|.*|*.|*..*) echo "" ;; *) echo "$_mv" ;; esac
}
# 무선 모드가 내비 앱 한 번 켜질 때 남기는 순정 회전 줄(S tbt) 한도: 모드 2.4.7부터 400(StockLog KIND_MAX, 소유자 결정 11-17),
#   그 앞 판은 100. 모드 판을 모르면 빈 값(요약에 두 값을 다 적음). 11-20 전에는 패키지 판으로 짐작해 틀릴 수 있었다
tb_tbtmax() {
  _v=$(tb_modver); [ -n "$_v" ] || { echo ""; return 0; }
  _ma=${_v%%.*}; _r=${_v#*.}; _mi=${_r%%.*}; _pa=0
  case "$_r" in *.*) _pa=${_r#*.}; _pa=${_pa%%.*} ;; esac
  case "$_v" in *.*) ;; *) echo ""; return 0 ;; esac
  case "$_ma$_mi$_pa" in ''|*[!0-9]*) echo ""; return 0 ;; esac
  if [ "$_ma" -gt 2 ] || { [ "$_ma" -eq 2 ] && { [ "$_mi" -gt 4 ] || { [ "$_mi" -eq 4 ] && [ "$_pa" -ge 7 ]; }; }; }; then echo 400; else echo 100; fi
}
tb_notice() {
  [ -n "$BB" ] && [ -d "$KPDIR" ] && [ -d "${NOTICE%/*}" ] && [ ! -L "$NOTICE" ] || return 0
  _nb=; { read -r _nb < "$BOOT_ID"; } 2>/dev/null
  # 리뷰(낮음 4): 시각을 못 읽으면 앱이 그 줄을 버리므로 쓰지 않는다
  _ns=$($BB date +%s 2>/dev/null); case "$_ns" in ''|*[!0-9]*) return 0 ;; esac
  _nl="$_ns ${_nb:-none} $1"
  _nt=$NOTICE.$$.tb${RANDOM:-0}
  ( umask 022
    rm -f "$_nt"
    if [ -f "$NOTICE" ]; then
      { $BB awk '{ a[NR] = $0 } END { s = NR - 3; if (s < 1) s = 1; for (i = s; i <= NR; i++) print a[i] }' "$NOTICE"
        echo "$_nl"; } > "$_nt"
    else
      echo "$_nl" > "$_nt"
    fi
    $BB chmod 644 "$_nt" && $BB mv -f "$_nt" "$NOTICE"
    [ -f "$_nt" ] && rm -f "$_nt" ) 2>/dev/null
  return 0
}
# 상태 화면을 연다(꽂을 때만: 그때는 정차 중). 앱이 없으면 열지 않는다(없는 화면 오류가 뜨지 않게)
tb_screen() {
  [ -n "$BB" ] && [ -d "$KPDIR" ] || return 0
  $PM path korea.projection.app 2>/dev/null | $BB grep -q "^package:" || return 0
  $AM start -n korea.projection.app/.StatusActivity </dev/null >/dev/null 2>&1
  return 0
}

# ---------- 뒤에서 도는 기록 ----------
if [ "$1" = "$LOOPARG" ]; then
  U=$2; OUTD=$3; ROOT=$U/KoreaProjection-private
  # 넘겨받은 폴더가 이 USB의 tbtlog-… 자리일 때만(다른 곳에 쓰지 않게)
  case "$OUTD" in "$ROOT"/tbtlog-*) ;; *) exit 0 ;; esac
  case "$OUTD" in */../*|*/..) exit 0 ;; esac
  [ -n "$BB" ] || exit 0
  # 작업 폴더를 USB 밖으로(USB를 뺄 때 붙잡지 않게)
  cd / 2>/dev/null
  safe || exit 0
  # 리뷰(M2): pid 파일이 링크면 쓰지 않는다(safe가 봄). 꽂은 쪽이 이 파일이 생기는지로 시작을 확인한다
  { echo "$$" > "$ROOT/tbtlog.pid"; } 2>/dev/null
  S=$OUTD/0-summary.txt; P=$OUTD/1-passes.txt; D=$OUTD/tbt.txt; ST=$OUTD/.tbtlog-state; TG=$OUTD/tags.txt; TT=$OUTD/.tags.tmp
  _t0=$(up_s); i=0; why="회차를 다 돎(${TB_PASSES}회)"; gaps=0
  LT_main=; LN_main=0; MX_main=; LT_system=; LN_system=0; MX_system=
  while [ $i -lt $TB_PASSES ]; do
    i=$((i+1))
    safe || { why=usb; break; }
    # 리뷰(11-19 낮음 1): 동의 파일이 없어졌으면(동의를 거둠) 더 읽지 않는다
    tb_agreed || { why="동의 파일(KP-AGREE.txt)이 없어짐"; break; }
    _sz=$( { $BB wc -c < "$D"; } 2>/dev/null | $BB awk '{ print $1 + 0 }')
    if [ "${_sz:-0}" -ge "$TB_MAXB" ]; then why="기록이 상한(${TB_MAXB}바이트)을 넘음"; break; fi
    _add=0; _note=; _bad=
    for _b in main system; do
      rm -f "$ST" "$TT" 2>/dev/null
      eval "_lt0=\$LT_$_b; _ln0=\$LN_$_b; _mx0=\$MX_$_b"
      { [ -f "$TG" ] && $BB cat "$TG"; echo "#kp-tags-end"; $LOGCAT -b $_b -d -v time; } 2>/dev/null | $BB awk -v lt="$_lt0" -v ln="$_ln0" -v mx="$_mx0" -v out="$D" -v st="$ST" -v buf="$_b" -v tt="$TT" -v tmax="$TB_TAGMAX" "$TBF" 2>/dev/null
      _l=; { IFS='|' read -r _lt _ln _ad _gap _back _mx < "$ST"; } 2>/dev/null && _l=1
      # 상태를 못 읽으면 USB에 쓰지 못한 것(빠짐·가득 참)으로 보고 멈춘다
      [ -n "$_l" ] || { _bad=1; break; }
      # 태그 요약을 바꿔 넣는다(이번 회차까지의 누적. 못 바꾸면 USB에 쓰지 못한 것)
      if [ -f "$TT" ]; then $BB mv -f "$TT" "$TG" 2>/dev/null || { _bad=1; break; }; fi
      case "$_ln$_ad" in *[!0-9]*) _ln=0; _ad=0 ;; esac
      eval "LT_$_b=\$_lt; LN_$_b=\$_ln; MX_$_b=\$_mx"
      _add=$((_add + _ad))
      [ "$_gap" = 1 ] && _note="$_note ($_b: 앞 회차와 사이에 빠진 줄이 있을 수 있음)"
      [ "$_back" = 1 ] && _note="$_note ($_b: 시계가 뒤로 감)"
    done
    [ -z "$_bad" ] || { why=usb; break; }
    case "$_note" in *빠진*) gaps=$((gaps+1)) ;; esac
    safe || { why=usb; break; }
    { echo "$(now) 회차 $i/$TB_PASSES 새 줄 ${_add:-0}$_note" >> "$P"; } 2>/dev/null || { why=usb; break; }
    $BB sync 2>/dev/null || sync 2>/dev/null
    _t=$(up_s)
    if [ -n "$_t0" ] && [ -n "$_t" ] && [ $((_t - _t0)) -ge $((TB_MIN * 60)) ]; then why="시간이 다 됨(${TB_MIN}분)"; break; fi
    [ $i -lt $TB_PASSES ] && $BB sleep $TB_INT 2>/dev/null
  done
  # USB가 빠졌으면 USB에는 아무것도 쓰지 않고 끝난다(빈 마운트 지점에 쓰지 않게). 상태 화면 알림만 남긴다(화면은 열지 않음)
  # 리뷰(중간 3): USB가 가득 차거나 폴더가 바뀌어도 여기로 오므로 원인을 하나로 정하지 않는다
  if [ "$why" = usb ] || ! safe; then tb_notice "길안내 기록이 멈췄습니다. USB가 빠졌거나 USB에 쓸 수 없습니다."; exit 0; fi
  rm -f "$ST" "$TT" 2>/dev/null
  # 태그 요약을 줄 수가 많은 순으로 한 번 정리한다(이어 읽는 자리 줄은 뺌). 정리한 줄 수가 다르면 정리 전 것을 그대로 둔다
  if [ -f "$TG" ]; then
    _n1=$($BB awk '/^[0-9]+ /{ n++ } END { print n + 0 }' "$TG" 2>/dev/null)
    { echo "# 태그별 줄 수(많은 순). 칸: 줄 수, 버퍼(main·system), 등급(V·D·I·W·E·F), 태그 이름. 줄 내용은 적지 않았습니다."
      $BB awk '/^[0-9]+ /' "$TG" | $BB sort -rn; } > "$TT" 2>/dev/null
    _n2=$($BB awk '/^[0-9]+ /{ n++ } END { print n + 0 }' "$TT" 2>/dev/null)
    if [ -n "$_n1" ] && [ "$_n1" = "$_n2" ]; then $BB mv -f "$TT" "$TG" 2>/dev/null; fi
    rm -f "$TT" 2>/dev/null
  fi
  {
    echo
    echo "## 기록 결과"
    echo "- 회차: $i번 (읽는 간격 ${TB_INT}초), 빠졌을 수 있는 회차: $gaps번"
    # 종류별 줄 수(3번째 칸 = 종류, 4번째 칸 = 세부 종류)
    _tm=$(tb_tbtmax); _kv=$(tb_modver)
    $BB awk -v tm="$_tm" -v kv="$_kv" '{ k = $3; t[k]++; if (k == "S" || k == "C") s[k " " $4 ($4 == "road" ? " " $5 : "")]++ }
      END {
        printf "%s%d%s", "- 순정 관찰 줄(S): ", t["S"] + 0, "줄"
        for (x in s) if (substr(x, 1, 2) == "S ") printf "%s%s %d", ", ", substr(x, 3), s[x]
        printf "%s- 계기판 서비스 줄(C): %d줄, NavigationCluster 줄(N): %d줄, 폰 안내 줄(P): %d줄, 위치 줄(L): %d줄\n", "\n", t["C"] + 0, t["N"] + 0, t["P"] + 0, t["L"] + 0
        printf "%s%d%s%d%s\n", "- 차량 신호 줄(V): ", t["V"] + 0, "줄, GPS 줄(G): ", t["G"] + 0, "줄"
        n = s["S tbt"] + 0
        if (tm != "" && n >= tm + 0) print "- 주의: 순정 회전 줄(S tbt)이 " tm "줄에 닿았습니다. 이 무선 모드(" kv ")는 내비 앱 한 번 켜질 때 " tm "줄까지만 남겨서 그 뒤 회전은 빠졌을 수 있습니다."
        if (tm == "" && n >= 100) print "- 주의: 순정 회전 줄(S tbt)이 " n "줄입니다. 무선 모드는 내비 앱 한 번 켜질 때 2.4.7 앞 판은 100줄, 2.4.7부터는 400줄까지만 남깁니다. 무선 모드 판을 몰라 그 뒤 회전이 빠졌는지 알 수 없습니다."
        if (t["S"] + 0 == 0) print "- 주의: 순정 관찰 줄이 없습니다. 디버그 로그가 꺼져 있었거나(부팅 때 켜져 있어야 함), 무선 모드의 tbt 설정이 꺼져 있거나, 순정 길안내가 없었습니다."
      }' "$D" 2>/dev/null
    # 태그 요약 줄 수(같은 태그도 버퍼·등급이 다르면 따로 셈)
    [ -f "$TG" ] && $BB awk -v mx="$TB_TAGMAX" '/^[0-9]+ /{ n++; s += $1; if (index($0, " (상한 넘음)") > 0) o += $1 }
      END { printf "%s%d%s%d%s", "- 태그 요약(tags.txt): 태그 ", n, "개(버퍼·등급이 다르면 따로 셈), 모두 ", s, "줄(줄 내용은 적지 않음)"; if (o > 0) printf "%s%d%s%d%s", ", 서로 다른 태그 상한 ", mx, "개를 넘은 태그의 줄 ", o, "줄은 (상한 넘음)으로 묶음"; printf "\n" }' "$TG" 2>/dev/null
    echo "- 끝: $why. ($(now))"
  } 2>/dev/null >> "$S"
  # 우리가 쓴 pid 파일이면 지운다
  _p=; { read -r _p < "$ROOT/tbtlog.pid"; } 2>/dev/null; [ "$_p" = "$$" ] && [ ! -L "$ROOT/tbtlog.pid" ] && rm -f "$ROOT/tbtlog.pid" 2>/dev/null
  $BB sync 2>/dev/null || sync 2>/dev/null
  # 끝 알림(USB 정리 뒤, 리뷰 낮음 8): 달리는 중일 수 있어 화면은 열지 않는다
  tb_notice "길안내 기록이 끝났습니다. 정차한 뒤 USB를 빼세요."
  exit 0
fi

# ---------- 꽂았을 때(NEMESIS가 부름): 확인하고 뒤에서 도는 기록을 띄운 뒤 바로 끝난다 ----------
if [ -n "$U" ]; then
  tb_mounted "$U" 2>/dev/null || U=
else
  case "$0" in /storage/usb1/*) _cand="/storage/usb1 /storage/usb0" ;; *) _cand="/storage/usb0 /storage/usb1" ;; esac
  for _c in $_cand; do tb_mounted $_c 2>/dev/null && { U=$_c; break; }; done
fi
[ -n "$U" ] || exit 0
# 동의 확인(NM-8, 2026-11-19). NEMESIS는 부팅 직후·앱 설치 중(sys.boot_completed가 잠깐 0)에 "실행할까요?" 창 없이
#   스크립트를 실행할 수 있다. 이 기록에는 위치가 들어가므로 창에만 기대지 않고,
#   안내문을 읽은 차주가 USB 맨 위의 KP-NOT-AGREED.txt 이름을 KP-AGREE.txt로 바꿨을 때만 기록한다.
#   대소문자는 가리지 않고, 확장자가 없거나 .txt.txt(윈도가 확장자를 숨길 때)여도 받는다. 폴더·링크는 받지 않는다.
#   동의가 없으면 USB에도 내비에도 기록하지 않고 상태 화면 알림 한 줄만 남긴다(꽂을 때라 화면도 연다)
if ! tb_agreed; then
  tb_notice "동의가 확인되지 않아 기록하지 않았습니다. 안내문에 동의하시면 PC에서 파일 이름을 KP-AGREE.txt로 바꿔 주세요."
  tb_screen
  exit 0
fi
ROOT=$U/KoreaProjection-private
# 리뷰(모듈 복사 USB 중간 1과 같음): 폴더가 링크면(링크를 만들 수 있는 USB) 내비 쪽에 쓰게 되므로 아무것도 하지 않는다
[ -L "$ROOT" ] && exit 0
# 시작하지 못함: 알림과 상태 화면(꽂을 때는 정차 중). 리뷰(중간 2)
tb_fail() { tb_notice "길안내 기록을 시작하지 못했습니다. USB의 KoreaProjection-private 폴더를 개발자에게 보내 주세요."; tb_screen; exit 0; }
mkdir -p "$ROOT" 2>/dev/null || tb_fail
[ -d "$ROOT" ] && [ ! -L "$ROOT" ] || tb_fail
tb_mounted "$U" 2>/dev/null || exit 0
# 이미 도는 기록이 있으면(같은 USB를 다시 꽂음) 새로 띄우지 않는다
_p=; { read -r _p < "$ROOT/tbtlog.pid"; } 2>/dev/null
case "$_p" in ''|*[!0-9]*) ;; *)
  if [ -r "$PROCD/$_p/cmdline" ] && [ -n "$BB" ] && $BB grep -q "$LOOPARG" "$PROCD/$_p/cmdline" 2>/dev/null; then
    tb_notice "길안내 기록이 이미 돌고 있습니다. USB를 꽂아 둔 채 이 화면을 닫고 출발하세요."; tb_screen; exit 0
  fi ;;
esac
# 결과 폴더: tbtlog-<날짜시각>, 이미 있으면 -2, 그것도 있으면 쓰지 않는다
_d=${TB_DATE:-$($BB date "+%Y%m%d-%H%M%S" 2>/dev/null)}
case "$_d" in ''|*[!0-9-]*) _d=nodate ;; esac
OUTD=$ROOT/tbtlog-$_d
[ -e "$OUTD" ] || [ -L "$OUTD" ] && OUTD=$OUTD-2
[ -e "$OUTD" ] || [ -L "$OUTD" ] && tb_fail
mkdir "$OUTD" 2>/dev/null || tb_fail
[ -d "$OUTD" ] && [ ! -L "$OUTD" ] || tb_fail
tb_mounted "$U" 2>/dev/null || exit 0
S=$OUTD/0-summary.txt
# 값 거르기(영문·숫자·몇 가지 기호만, 80자). 모듈 복사 USB의 dn_safe와 같다
dn_safe() { $BB awk '{ gsub(/[^A-Za-z0-9 ._:\/()+=,#-]/, ""); print substr($0, 1, 80) }' 2>/dev/null; }
{
  echo "Korea Projection 계기판 길안내 기록 (순정 내비 → 계기판, 읽기만)"
  echo "이 폴더는 비공개입니다. 지나간 길(교차로·목적지 이름, 위치 값)과 시각이 들어 있어 GitHub 이슈에 올리지 말고 개발자에게 따로 보내 주세요."
  echo
  echo "- 시작: $($BB date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
  # 11-24(공개 준비): 여러 판이 돌면 제보를 가를 수 없어 이 스크립트의 판을 적는다(고칠 때마다 날짜를 올린다)
  echo "- 수집 USB 버전: 20261124"
  if [ -z "$BB" ]; then
    echo "- busybox 없음: 기록하지 않았습니다. Korea Projection이 설치돼 있는지 확인해 주세요."
    echo "- 끝: busybox 없음."
  else
    echo "- 차 코드: $(getprop ro.build.product 2>/dev/null | dn_safe)"
    _kv=$(tb_kpver); _mv=$(tb_modver); _tm=$(tb_tbtmax)
    echo "- Korea Projection 판: ${_kv:-모름}"
    if [ -n "$_tm" ]; then echo "- 무선 모드 판: $_mv (순정 회전 줄은 내비 앱 한 번 켜질 때 ${_tm}줄까지 남음)"
    else echo "- 무선 모드 판: 모름 (순정 회전 줄 한도는 2.4.7 앞 판 100줄, 2.4.7부터 400줄)"; fi
    # 리뷰(11-17 저녁 중간 2·낮음 9): 한도는 내비 프로세스 하나에 세고, 판은 설치된 것이라 내비를 다시 켜야 그 한도가 된다
    echo "- 회전 줄 한도는 내비가 켜진 뒤 앞서 달린 만큼 줄어듭니다. 판을 바꾼 뒤에는 내비를 다시 켜야 새 한도가 됩니다(출발 직전에 다시 켜면 처음부터 셉니다)"
    echo "- 동의 파일(KP-AGREE.txt): 있음"
    if [ -n "$TZS" ]; then echo "- 시각 기준: $TZL. 폴더 이름·이 요약·1-passes.txt·tbt.txt·tags.txt가 모두 같은 기준입니다"
    else echo "- 시각 기준: $TZL. tbt.txt·tags.txt는 내비 로그 시각입니다"; fi
    echo "- 기록: 최대 ${TB_MIN}분, ${TB_INT}초마다 logcat 버퍼(main·system)를 읽음, 최대 ${TB_MAXB}바이트"
    if [ -f "$DEBUGF" ]; then echo "- 디버그 로그 켜기 파일: 있음 (부팅 때부터 있었다면 순정 회전 번호 줄이 남습니다)"
    else echo "- 디버그 로그 켜기 파일: 없음 (순정 회전 번호 줄(S)이 남지 않습니다. 계기판 서비스 숫자만 남습니다)"; fi
    _n=$($LOGCAT -d -v time 2>/dev/null | $BB awk '/stock navigation: /{ s++ } / [VDIWEF]\/HMG-API *\(/{ h++ } END { print s + 0 " " h + 0 }')
    echo "- 지금 logcat 버퍼: 순정 관찰 줄 ${_n%% *}줄, HMG-API 줄 ${_n##* }줄"
    echo
    echo "## 파일"
    echo "- tbt.txt: 기록. 줄마다 '날짜 시각 종류 내용'. 종류 S=순정 관찰 줄, C=계기판 서비스, N=NavigationCluster, P=폰 안내(카플레이·AA), L=위치(교차로·목적지 이름, 위치 값), V=차량 신호(차속·기어·주차 브레이크·야간), G=GPS(방위·고도, 경로 위 위치, 위치 값)"
    echo "- 1-passes.txt: 회차마다 한 줄(시각, 새 줄 수). 마지막 줄 시각이 기록이 멈춘 때입니다"
    echo "- tags.txt: 태그 요약. 로그를 남긴 프로그램 이름(태그)별 줄 수만 적고 줄 내용은 적지 않습니다. 기록이 도중에 끊기면 정렬되지 않은 채 남습니다"
  fi
} 2>/dev/null > "$S" || tb_fail
[ -n "$BB" ] || exit 0
# 리뷰(M1): 다시 부를 스크립트. NEMESIS가 주는 $0은 차에서 확인하지 않았다(sh 자체나 지워지는 임시 사본일 수 있음).
#   그래서 $0이 이 스크립트(LOOPARG가 든 파일)일 때만 쓰고, 아니면 USB 맨 위의 NEMESIS.sh를 같은 방법으로 확인한다
_self=
for _c in "$0" "$U/NEMESIS.sh"; do
  case "$_c" in /*) ;; *) continue ;; esac
  [ -f "$_c" ] && [ ! -L "$_c" ] && $BB grep -q "$LOOPARG" "$_c" 2>/dev/null && { _self=$_c; break; }
done
if [ -z "$_self" ]; then
  { echo "- 기록 시작: 안 됨(이 스크립트 위치를 찾지 못함). USB 맨 위에 NEMESIS.sh가 있는지 확인해 주세요."; } 2>/dev/null >> "$S"
  tb_fail
fi
# 지난 기록의 pid 파일(이미 끝난 것)은 지운다. 새 기록이 이 파일을 쓰는지로 시작을 확인한다
[ -L "$ROOT/tbtlog.pid" ] || rm -f "$ROOT/tbtlog.pid" 2>/dev/null
# 뒤에서 돌 기록을 띄운다. 새 세션(setsid)이라 NEMESIS가 끝나도 남고, 끝나는 조건은 시간·회차·USB 빠짐·크기다
if [ "${TB_FG:-0}" = 1 ]; then
  sh "$_self" "$LOOPARG" "$U" "$OUTD"
  exit 0
fi
$BB setsid sh "$_self" "$LOOPARG" "$U" "$OUTD" </dev/null >/dev/null 2>&1 &
# 리뷰(M1): 시작했는지 최대 TB_WAIT초 본다(pid 파일이 생기면 시작됨). 차에는 따로 알리지 않고 요약에만 적는다
_w=0; _ok=
while [ $_w -lt ${TB_WAIT:-10} ]; do
  _p=; { read -r _p < "$ROOT/tbtlog.pid"; } 2>/dev/null
  case "$_p" in ''|*[!0-9]*) ;; *) _ok=1; break ;; esac
  # 아주 짧은 기록은 이미 끝나 pid 파일을 지웠을 수 있다: 회차 기록이 있으면 시작된 것
  [ -f "$OUTD/1-passes.txt" ] && { _ok=1; break; }
  $BB sleep 1 2>/dev/null; _w=$((_w+1))
done
tb_mounted "$U" 2>/dev/null || exit 0
if [ -n "$_ok" ]; then _m="- 기록 시작: 됨"; else _m="- 기록 시작: 확인 못 함(${TB_WAIT:-10}초 안에 시작 표시가 없음). 1-passes.txt가 없으면 기록되지 않은 것입니다."; fi
{ echo "$_m"; } 2>/dev/null >> "$S"
# 상태 화면 알림과 화면 열기(꽂을 때는 정차 중). 시작을 확인했을 때만 "시작" 알림
if [ -n "$_ok" ]; then tb_notice "길안내 기록을 시작했습니다(최대 ${TB_MIN}분). USB를 꽂아 둔 채 이 화면을 닫고 출발하세요."
else tb_notice "길안내 기록이 시작됐는지 확인하지 못했습니다. 정차한 채 USB를 뺐다가 다시 꽂아 주세요."; fi
tb_screen
exit 0
