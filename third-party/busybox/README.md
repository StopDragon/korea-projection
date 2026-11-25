# busybox (busybox 없는 내비용, 1.5.6에 넣을 예정)

K3 `BDPE`·K8 `GL3HEV`(tcc803x) 내비에는 `/system/bin/busybox`가 없다. 이 차들에서 우리 스크립트를 그대로 쓰려고 패키지에 함께 넣는 busybox다.

## 출처 (2026-11-07 KST 가져옴)
- Alpine Linux 3.20.10 `busybox-static-1.36.1-r31` 패키지의 `/bin/busybox.static`
- Docker `alpine:3.20`(linux/arm/v7, 이미지 digest `sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc`) 안에서 `apk add busybox-static`으로 설치했다. `apk`는 Alpine 서명을 확인한 뒤에만 설치한다.
- 파일: `busybox` (ELF 32-bit ARM EABI5, 정적 링크, 877,900바이트)
- SHA-256 `3d31efecd4d09625a5d04597ad857f3475d35e6d63a3365912a7edd4c60770a5`
- 들어 있는 명령 목록: `applets.txt` (305개, 우리가 쓰는 21개 모두 있음)

## 라이선스
- GPLv2. 배포할 때 아래 소스 위치를 함께 알린다(패키지 README와 공개 저장소).
  - BusyBox 1.36.1 소스: https://busybox.net/downloads/busybox-1.36.1.tar.bz2
  - Alpine 빌드 설정·패치: https://gitlab.alpinelinux.org/alpine/aports/-/tree/3.20-stable/main/busybox

## 다시 가져오기
```sh
docker run --rm --platform linux/arm/v7 -v "$PWD":/out alpine:3.20 \
  sh -c 'apk add --no-cache busybox-static && cp /bin/busybox.static /out/busybox'
shasum -a 256 busybox
```
