#!/bin/bash
# kp-usbreset 빌드: AOSP arm-eabi-4.7 툴체인, libc 없이 정적 ARM(armv7) ELF
# 쓰는 법: TC=/path/arm-eabi-4.7 bash build.sh [출력 폴더]
set -euo pipefail
cd "$(dirname "$0")"
TC=${TC:?TC(arm-eabi-4.7 폴더)를 주세요}
OUT=${1:-.}
CC=$TC/bin/arm-eabi-gcc
STRIP=$TC/bin/arm-eabi-strip

"$CC" -Os -marm -march=armv7-a -mfloat-abi=soft \
  -ffreestanding -fno-builtin -fno-stack-protector -fno-asynchronous-unwind-tables -fno-unwind-tables \
  -nostdlib -static -Wl,-e,_start -Wl,--gc-sections -Wl,--build-id=none -Wl,-z,max-page-size=0x1000 \
  -Wall -Wextra -o "$OUT/kp-usbreset" kp-usbreset.c
"$STRIP" --strip-all -R .comment -R .ARM.attributes "$OUT/kp-usbreset"
ls -l "$OUT/kp-usbreset"
sha256sum "$OUT/kp-usbreset"
