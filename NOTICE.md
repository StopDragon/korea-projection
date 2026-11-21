# 고지 (NOTICE)

Korea Projection은 GNU AGPL-3.0입니다(`LICENSE`). 아래는 다른 프로젝트에서 가져오거나 바탕으로 삼은 부분과 그 원저작권입니다.

## 공통 USB Wi-Fi 통합 제안

- `experimental/usbwifi-integration/`는 개인용 1.7.4.2의 선택형 통합 소스와 호스트 시험입니다. 기본 배포를 바꾸거나 실차 지원 완료로 표시하지 않습니다.
- AGPL-3.0 실행 스크립트와 별도로 GPL-2.0 Realtek 드라이버를 제공하며, 완전한 업스트림 소스 압축·패치·설정·빌드 자료와 각 모듈의 해시를 함께 둡니다.
- EV6 보조 모드의 원작: EV6 KR USB Wi-Fi 동글 시스템 (MANN1309), https://github.com/MANN1309/ev6-kr-usbwifi-dongle . 원본 NOTICE/DISCLAIMER/ADDITIONAL-TERMS와 대응 소스를 유지합니다. 수정판은 원작자의 보증을 뜻하지 않습니다.
- 읽기 전용 `ctrl-status`와 `ap-capabilities`는 MIT-0이며 musl/Zig 고지를 유지합니다.
- 원본 APK·BusyBox·서명 무선 모드는 해시로 검증하는 빌드 입력이며 새 서명이나 개인 키를 제공하지 않습니다. 별도 NX4 서명 모드와 정확한 대응 소스를 확인하지 못한 미사용 GRT 바이너리는 커밋하지 않습니다.
- 상세 고지와 빌드 입력 제한은 실험 폴더의 README 및 `usb/THIRD-PARTY.txt`를 확인하세요.

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
