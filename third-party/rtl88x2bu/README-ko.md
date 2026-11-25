# 동글 드라이버 소스 묶음 (Korea Projection 1.8.1)


> **이 폴더에서:** 아래 "들어 있는 것"은 같은 폴더의 `rtl88x2bu-source-1.8.1.tar.gz` 안에 있습니다(SHA-256 `f58c423af15e1f7b55bcdd101181419397d7efa314e594c8c6c6557608a41bdd`, 8.3MB). 저장소를 가볍게 하려고 묶어 두었습니다.

Korea Projection 1.8.1 패키지에 들어 있는 USB Wi-Fi 동글 드라이버(`88x2bu.ko`)의 소스입니다.
드라이버는 GPL-2.0 오픈소스 [cilynx/rtl88x2bu](https://github.com/cilynx/rtl88x2bu)에 우리 보호 패치를 얹어 만들었습니다.
이 묶음도 GPL-2.0을 따릅니다.

| 패키지 안 파일 | md5 | sha256 | 원본 커밋 | 이 묶음의 소스 |
|---|---|---|---|---|
| `drv/tcc897x/88x2bu.ko` | `4365323f5141ead1714a8c08207b9788` | `572a18ea0e150fe04e3b81c651c20a683332cd080d83328f60116628e287ca91` | `04ed7009bac4b235fe1880ba29e23159f49a6121` | `tcc897x/` |
| `drv/tcc803x-a/88x2bu.ko` | `f5647f3100b02ec45834785b419c87ec` | `a6f90345d9adc0f3ea5f8c5b7c4b7e56aec911004ed2a4f891bd4f6f8485b2fd` | `fc158d1f71b9e5dfcd1fccaf4d28725b65086e3b` | `tcc803x/` |

- tcc897x는 1.8.0과 같은 파일이고, tcc803x는 1.8.1에서 다시 빌드했습니다(1.8.0의 `e16ccc02…`와 소스·설정이 같고 빌드 시각 문자열과 build-id 27바이트만 다릅니다).
- 원 드라이버 저장소: <https://github.com/cilynx/rtl88x2bu> (GPL-2.0, 라이선스 전문은 각 소스 폴더의 `LICENSE`, 이 묶음도 GPL-2.0을 따릅니다).

## 들어 있는 것

- `tcc897x/rtl88x2bu/`, `tcc803x/rtl88x2bu/`: 원본 커밋에 보호 패치를 적용한 드라이버 소스 전체입니다.
- `tcc897x/kp-protect.diff`, `tcc803x/kp-protect.diff`: 원본 커밋과 달라진 부분입니다(보호 패치).
- `tcc897x/kernel.config`: tcc897x 빌드에 쓴 커널 설정입니다(`vexpress_defconfig` + `scripts/config.frag`).
- `tcc803x/kernel.config`: tcc803x 빌드에 쓴 커널 설정입니다. 우리가 모듈 복사 USB로 받은 tcc803x 내비 차 5대의 `/proc/config.gz`를 푼 것이고 5대가 바이트까지 같습니다(sha256 `d35af8a0e9d098a47720ea66de594f21691d3d9608ce388ed199e0a5f82f9913`). 설정 파일에는 개인정보가 없습니다.
- `scripts/kp-protect.sh`: 보호 패치를 원본 소스에 얹는 스크립트입니다(뽑을 때 보호, 수신 오류 반복 막기, 기록).
- `scripts/hdr-patch.sh`, `scripts/hdr-patch-803x.sh`: kernel.org 커널 헤더의 구조체에 필드를 더해 내비 커널과 배치를 맞춥니다. 동작 코드는 바꾸지 않습니다.
- `scripts/config.frag`: tcc897x 커널 설정 조각입니다.
- `scripts/kernel-tcc897x.diff`, `scripts/kernel-tcc803x.diff`: 위 스크립트가 커널 소스에 만드는 변경 전체입니다.
- `build-tcc897x.sh`, `build-tcc803x.sh`: 빌드 스크립트입니다.

## 빌드에 필요한 것(묶음에 넣지 않음, 모두 공개 자료)

- 리눅스 x86_64. 우리는 Ubuntu 20.04 컨테이너에서 빌드했습니다.
  - 꾸러미: `build-essential bc kmod cpio xz-utils git perl libncurses-dev libssl-dev bison flex libelf-dev`
- 커널 소스: kernel.org `linux-3.18.24.tar.xz`
  - sha256 `ed54cf8c3ac6b95fc17b07b3a236bc42719c96fee08fe696cabfb5b8e07f8c1b`
- 툴체인: AOSP `platform/prebuilts/gcc/linux-x86/arm/arm-eabi-4.7`(kitkat-release), `arm-eabi-gcc (GCC) 4.7`
  - 우리가 쓴 `bin/arm-eabi-gcc`의 sha256: `89a07707b49062910fdec9b55a7fb920809638fde0517a70cf669cb6e4d3661b`

## 빌드

```bash
KTAR=/path/linux-3.18.24.tar.xz TC=/work/tc bash build-tcc897x.sh
```

```bash
KTAR=/path/linux-3.18.24.tar.xz TC=/work/tc bash build-tcc803x.sh
```

- 패키지의 `.ko`와 md5까지 같게 하려면 기본 경로를 그대로 쓰세요. `.ko` 안에 빌드 경로가 문자열로 들어가기 때문입니다.
  - tcc897x: 커널 `/work/src/linux-3.18.24`, 드라이버 `/work/kp/niro-drv`
  - tcc803x: 커널 `/work/t803/k-kp-h2/linux-3.18.24`, 드라이버 `/work/t803/d-kp-h2-pkp`
- 경로는 `K`, `D`로 바꿀 수 있습니다. 바꾸면 경로 문자열만 달라집니다.
- 스크립트는 끝에 결과 md5와 패키지 md5를 함께 보여 줍니다.

## 다시 빌드하면 md5가 다른 이유

- 드라이버의 `core/rtw_debug.c`가 컴파일 날짜·시각(`__DATE__`, `__TIME__`)을 문자열로 넣습니다. 그래서 빌드할 때마다 그 문자열이 바뀌고, 이에 따라 `.note.gnu.build-id`(20바이트)도 바뀝니다. gcc 4.7은 `SOURCE_DATE_EPOCH`를 지원하지 않습니다.
- 패키지 빌드 때 값은 tcc897x `Nov 18 2026 14:05:22`, tcc803x `Nov 25 2026 12:30:42`입니다.
- 이 두 값을 고정하면 md5까지 패키지와 같아집니다. 커널을 준비한 뒤 드라이버를 새로 복사하고 아래처럼 빌드합니다(tcc897x 예).

```bash
printf '#undef __DATE__\n#define __DATE__ "Nov 18 2026"\n#undef __TIME__\n#define __TIME__ "14:05:22"\n' > /tmp/pin.h
```

```bash
make -j8 ARCH=arm CROSS_COMPILE=arm-eabi- KSRC=/work/src/linux-3.18.24 KVER=3.18.24-tcc EXTRA_CFLAGS="-g -Wno-builtin-macro-redefined -include /tmp/pin.h"
```

- 확인(KST): tcc897x는 2026-11-23에, tcc803x는 2026-11-26에 이 묶음만으로 다시 빌드했습니다. 날짜·시각을 고정하면 두 `.ko` 모두 패키지와 md5가 같았습니다. 고정하지 않으면 날짜·시각 문자열과 build-id만 다르고, 크기·`srcversion`은 같았습니다.
