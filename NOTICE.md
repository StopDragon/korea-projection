# 고지 (NOTICE)

Korea Projection은 GNU AGPL-3.0입니다(`LICENSE`). 아래는 다른 프로젝트에서 가져오거나 바탕으로 삼은 부분과 그 원저작권입니다.

## G70 USB Wi-Fi 실험 보조 패키지

- `experimental/g70-usbwifi/`의 새 셸/빌드/시험 코드는 이 저장소의 AGPL-3.0으로 제공합니다.
- `88x2bu.ko`는 별도 프로그램인 GPL-2.0 드라이버이며, 전체 업스트림 소스 압축과 대응 패치·설정·빌드 자료를 해당 폴더의 `pkg/source/driver/`에 함께 둡니다.
- 읽기 전용 `ctrl-status`는 MIT-0이고 정적 링크된 musl/Zig 고지를 함께 둡니다. 세부 출처와 고지는 실험 폴더의 `NOTICE.txt` 및 `pkg/source/`를 확인하세요.
- 기존 기본 패키지의 서명 APK·HMG-API 모드와 라이선스는 변경하지 않습니다.

## NEMESIS (xwtk, AGPL-3.0)

- https://github.com/xwtk/hmg_nemesis
- Korea Projection은 NEMESIS 패키지(`korea.projection`)로 설치되고, NEMESIS의 패키지 형식(`NEMESIS.data`)과 서비스 실행 방식을 따릅니다.

## HMG-API (VysseCodes, AGPL-3.0)

- https://github.com/Open-HMG/HMG-API (예전 주소 `VysseCodes/HMG-API`)
- `nemesis-pkg/korea.projection/hmgapi/wireless-carplay-aa.zip`: HMG-API v1.0.2의 "Wireless CarPlay + Android Auto" 모드 2.1.0에 한국 차 데이터를 더하고 Korea Projection 개발 키로 다시 서명한 것입니다.
  - 바꾼 부분과 대응 소스, 다시 만드는 방법은 `hmgapi-mod/README.md`에 있습니다.
  - 1.5.6까지는 코드(`hooks.jar`)가 업스트림과 같습니다.
- `nemesis-pkg/korea.projection/hmgapi/maps/`: HMG-API 지도 형식의 차별 훅 지도입니다. HMG-API `tools/report-map.py`로 만들었습니다.
- `nemesis-pkg/app-src/java/korea/projection/app/QrCode.java`: HMG-API의 QR 코드 생성 코드에서 `package` 줄만 바꿨습니다.
- 1.5.7부터 모드 코드(`hooks.jar`, 모드 2.1.1)가 업스트림과 다릅니다. 소스는 포크 `StopDragon/HMG-API`의 `korea-build` 브랜치(업스트림 `v1.0.2`에서 시작)에 있습니다.
  - 업스트림 main의 커밋 `83eb4ef`(Narayan, "Fix CarPlay turns for left-hand traffic and omitted angles")를 그대로 가져왔습니다.
  - 계기판·HUD 회전 안내(`dipo/CpTurns.java`, `dipo/Dipo.java`)를 고쳤습니다. 바꾼 내용과 날짜는 파일 머리말 주석에 있습니다.

## HMG-Seogaemo (seogaemo, AGPL-3.0)

- https://github.com/seogaemo/hmg-seogaemo (커밋 `26eeb97e`)
- 1.5.7 모드의 `dipo/CpTurns.java`에 seogaemo의 `modules/wireless-carplay-and-aa/payload/src/hmgapi/mods/wireless/dipo/CpTurns.java.src`에서 다음을 옮겨 쓰고 HMG-API 구조에 맞게 고쳤습니다.
  - 아이콘 대체 규칙(`fallbackIcon`, `bandedTurn`, `roundaboutIcon`, 빈 아이콘 `NO_ICON`)
  - HUD 빈 목록, 앞쪽 회전 아이콘 47~50
  - 안내 상태 주기 재전송(refresh)과 HUD 목록 재전송
- 옮긴 부분은 소스 주석에 "from HMG-Seogaemo"로 표시했습니다.

## BusyBox (GPL-2.0)

- https://busybox.net
- 1.7.0부터 릴리스 패키지(`korea.projection-*.zip`, USB 묶음 안의 `packages/korea.projection.zip`)에 `bin/busybox`가 들어 있습니다. 1.6.x 시험판에도 들어 있었고, 1.5.6에는 없습니다.
  - busybox가 없는 내비(K3·K8 등 tcc803x)에서 Korea Projection 스크립트를 돌리려고 함께 넣었습니다. 내비에 `/system/bin/busybox`가 있으면 그것을 쓰고, 이 파일은 쓰지 않습니다.
- BusyBox는 Korea Projection과 따로 동작하는 프로그램이고, AGPL-3.0이 아니라 **GNU GPL 2.0**으로 배포됩니다. 저희는 이 파일을 고치지 않았습니다.
- 파일: BusyBox v1.36.1, Alpine Linux 3.20 `busybox-static-1.36.1-r31` 패키지의 `/bin/busybox.static`(ARMv7 정적 링크, 877,900바이트)
  - SHA-256 `3d31efecd4d09625a5d04597ad857f3475d35e6d63a3365912a7edd4c60770a5`
  - Alpine 서명을 확인하는 `apk add busybox-static`(Docker `alpine:3.20`, linux/arm/v7)으로 받았습니다.
- 대응 소스
  - BusyBox 1.36.1: https://busybox.net/downloads/busybox-1.36.1.tar.bz2
  - Alpine 빌드 설정·패치(`APKBUILD`, 설정 파일, 패치): https://gitlab.alpinelinux.org/alpine/aports/-/tree/3.20-stable/main/busybox
- 라이선스 원문: https://www.gnu.org/licenses/old-licenses/gpl-2.0.txt
- 소스를 받기 어려우면 이슈로 알려 주세요. 위 소스를 직접 보내 드립니다.
