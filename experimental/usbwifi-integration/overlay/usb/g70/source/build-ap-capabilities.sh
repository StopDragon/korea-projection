#!/bin/sh
# SPDX-License-Identifier: MIT-0
# Use Zig 0.13.0; static ARMv7 soft-float binary, no Android linker dependency.
set -eu
cd "${0%/*}"
${ZIG:-zig} cc -target arm-linux-musleabi -mcpu=cortex_a7 -Os -static -s \
    -Wall -Wextra -Werror ap-capabilities.c -o ../bin/ap-capabilities
