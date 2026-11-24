#!/bin/sh
# NEMESIS 패키지 zip(korea.projection.zip)을 만든다.
# 1.7.4(B-14): zip 안의 권한을 여기서 못 박는다. 작업 폴더 권한을 그대로 넣으면, 폴더를 옮기다 그룹·기타 권한이 빠졌을 때
# (2026-11-11, 계획 Z-1) bin/busybox가 700으로 나간다. 그래서 임시 폴더에 복사한 뒤 아래 규칙으로 권한을 다시 정하고 묶는다.
#   폴더 755, 실행 파일(EXEC 목록) 755, 나머지 파일 644
# hmgapi/maps의 json은 1.7.3 zip에서 700이었지만 644로 둔다: 차에서는 hotspot.sh가 지도를 HMG-API 폴더로 복사한 뒤
# chmod -R 700을 하므로(설치 위치의 권한은 그쪽이 정함) 패키지 안 권한은 동작에 쓰이지 않는다. 내용도 공개 저장소에 있는 파일이다.
# 사용: sh scripts/build-pkg.sh [출력 zip]
#   기본값: nemesis-pkg/korea.projection.zip
#   PKGDIR=<폴더>로 묶을 패키지 폴더를 바꿀 수 있다(시험용). 기본값: nemesis-pkg/korea.projection
# APK는 이 스크립트가 만들지 않는다. 앱을 고쳤으면 먼저 sh scripts/build-app.sh를 돌린다.
# 리뷰 반영: APK의 versionCode가 hotspot.sh의 APK_VC와 같은지 aapt2로 본다(다르면 옛 APK를 묶는 것이라 멈춤).
#   aapt2 위치: AAPT2(시험용) 또는 SDK(기본 ~/.local/share/android-sdk)의 가장 높은 build-tools. 없으면 이유를 알리고 멈춘다.
# 숨김 파일(.*)·편집기 사본(*~, *.swp, *.orig)이 패키지에 있으면 지우지 않고 멈춘다(무엇이 섞였는지 사람이 보게).
set -e
umask 022
B=$(cd "$(dirname "$0")/.." && pwd)
SRC=${PKGDIR:-$B/nemesis-pkg/korea.projection}
OUT=${1:-$B/nemesis-pkg/korea.projection.zip}
# zip에 넣는 맨 위 항목(1.7.3과 같은 순서, 1.8.0 베타 2: 동글 드라이버 drv를 끝에)
TOP="NEMESIS.data svc scripts bin app hmgapi drv"
# 755로 둘 실행 파일. NEMESIS가 직접 부르거나(service·app·postinstall·preuninstall) 셸에서 바로 실행하는 것.
# bin/carreport.sh는 status.sh가 sh로 부르므로 1.7.3처럼 644다.
EXEC="svc/hotspot.sh scripts/post.sh scripts/preun.sh bin/status.sh bin/busybox bin/kp-usbreset"

[ -f "$SRC/NEMESIS.data" ] || { echo "패키지 폴더가 아닙니다: $SRC" >&2; exit 1; }
grep -q '^id=korea.projection$' "$SRC/NEMESIS.data" || { echo "korea.projection 패키지가 아닙니다: $SRC" >&2; exit 1; }
VER=$(grep '^package-version=' "$SRC/NEMESIS.data" | sed 's/^package-version=//; s/\r$//')
case "$VER" in
  ''|*[!0-9.]*) echo "package-version을 읽지 못했습니다: '$VER'" >&2; exit 1 ;;
esac
for t in $TOP; do [ -e "$SRC/$t" ] || { echo "패키지에 $t가 없습니다" >&2; exit 1; }; done
for e in $EXEC; do [ -f "$SRC/$e" ] || { echo "실행 파일이 없습니다: $e" >&2; exit 1; }; done

# 패키지 폴더 전체를 본다(zip에 넣지 않는 맨 위 파일도: 섞인 것이 있다는 뜻이므로)
BADF=$(cd "$SRC" && find . -mindepth 1 \( -name '.*' -o -name '*~' -o -name '*.swp' -o -name '*.orig' \) -print)
if [ -n "$BADF" ]; then
  echo "숨김 파일·편집기 사본이 있어 만들지 않습니다(지운 뒤 다시 실행하세요):" >&2; echo "$BADF" >&2; exit 1
fi
# APK versionCode 대조
SDK=${SDK:-$HOME/.local/share/android-sdk}
if [ -z "$AAPT2" ]; then
  AAPT2=$(ls -d "$SDK"/build-tools/*/ 2>/dev/null | sort -t/ -k1 -V | tail -n 1)aapt2
fi
[ -x "$AAPT2" ] || { echo "aapt2를 찾지 못해 APK 판을 확인할 수 없습니다: $AAPT2 (AAPT2=경로 또는 SDK=폴더로 알려 주세요)" >&2; exit 1; }
WANT=$(sed -n 's/^APK_VC=//p' "$SRC/svc/hotspot.sh")
GOT=$("$AAPT2" dump badging "$SRC/app/KoreaProjection.apk" 2>/dev/null | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p" | head -n 1)
case "$WANT" in ''|*[!0-9]*) echo "hotspot.sh의 APK_VC를 읽지 못했습니다: '$WANT'" >&2; exit 1 ;; esac
[ "$GOT" = "$WANT" ] || { echo "APK의 versionCode($GOT)가 hotspot.sh의 APK_VC($WANT)와 다릅니다. sh scripts/build-app.sh로 다시 만드세요" >&2; exit 1; }

W=$(mktemp -d /tmp/kp-pkg.XXXXXX)
trap 'rm -rf "$W"' EXIT
mkdir "$W/p"
# 맨 위 항목만 복사한다(작업 폴더의 다른 파일이 섞이지 않게). 숨김 파일은 위에서 이미 막았다
for t in $TOP; do cp -R "$SRC/$t" "$W/p/"; done
# 링크·특수 파일이 있으면 멈춘다(zip에 엉뚱한 것이 들어가지 않게)
if [ -n "$(find "$W/p" ! -type f ! -type d)" ]; then
  echo "일반 파일·폴더가 아닌 것이 있습니다:" >&2; find "$W/p" ! -type f ! -type d >&2; exit 1
fi
# 권한 다시 정하기: 폴더 755, 파일 644, 실행 파일 755
find "$W/p" -type d -exec chmod 755 {} +
find "$W/p" -type f -exec chmod 644 {} +
for e in $EXEC; do chmod 755 "$W/p/$e"; done

# 1.8.0 변조 검사: 차의 서비스는 bin/kp-files.md5(파일 목록과 md5)가 패키지 파일과 다르면 "변조"로 보고 멈춘다.
# 목록이 낡은 채 묶이면 모든 차가 멈추므로 여기서 대조하고, 다르면 만들지 않는다(목록 자신과 NEMESIS.data는 목록에 넣지 않음)
KPL="$W/p/bin/kp-files.md5"
[ -s "$KPL" ] || { echo "bin/kp-files.md5가 없습니다. 패키지 폴더에서 다시 만드세요(drafts/1.8.0-work/pkg.md '변조된 패키지 검사')" >&2; exit 1; }
KPWANT=$(cd "$W/p" && find . -type f ! -name NEMESIS.data ! -path ./bin/kp-files.md5 | sed 's|^\./||' | LC_ALL=C sort)
if [ "$(awk '{ print $2 }' "$KPL")" != "$KPWANT" ] || [ "$(cd "$W/p" && md5sum $KPWANT)" != "$(cat "$KPL")" ]; then
  echo "bin/kp-files.md5가 패키지 파일과 다릅니다(차에서 '변조'로 멈춥니다). 패키지 폴더에서 다시 만드세요:" >&2
  echo "  cd nemesis-pkg/korea.projection && md5sum \$(find . -type f ! -name NEMESIS.data ! -path ./bin/kp-files.md5 | sed 's|^\./||' | LC_ALL=C sort) > bin/kp-files.md5" >&2
  exit 1
fi

case "$OUT" in /*) ;; *) OUT=$(pwd)/$OUT ;; esac
rm -f "$OUT"
# -X: 확장 속성을 넣지 않는다. COPYFILE_DISABLE: macOS tar·zip이 ._ 파일을 만들지 않게
(cd "$W/p" && COPYFILE_DISABLE=1 zip -X -q -r "$OUT" $TOP)

echo "만듦: $OUT (Korea Projection $VER)"
shasum -a 256 "$OUT"
