#!/bin/bash
# build.sh: host half of the EV6 RTL8851BU (8851bu.ko) build, EXPERIMENTAL (macOS Docker, or any Docker host).
#
# Runs inner-build.sh in an x86-64 Ubuntu 20.04 container, because the AOSP
# arm-eabi-4.7 toolchain is an x86 binary. Results land in ./out:
#   out/8851bu.ko    the module (debug info stripped)
#   out/SOURCE.txt   commit, patch hashes, toolchain and kernel used (ship it with the .ko)
#   out/build.log    full log of this run
#
# Environment (all optional):
#   WORK_VOLUME    docker volume for downloads and build trees     (default ev6drv-cr)
#   SHARED_VOLUME  older cache volume, mounted read-only; its toolchain copy is a
#                  fallback when the AOSP clone fails               (default ev6drv-opt)
#   REF_KO         path of a module to compare vermagic and parameter names with
#   DRIVER_COMMIT  build another upstream commit (patches must still apply)
#   JOBS           parallel make jobs
#   FORCE_KERNEL_PREP=1   re-extract and re-prepare the kernel tree
#
# Usage: ./build.sh

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
image=${IMAGE:-ubuntu:20.04}
work_volume=${WORK_VOLUME:-ev6drv-cr}
shared_volume=${SHARED_VOLUME:-ev6drv-opt}

command -v docker >/dev/null || { echo "docker not found (start colima?)" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "docker daemon not reachable (colima start?)" >&2; exit 1; }

mkdir -p "$here/out"
rm -f "$here/out/8851bu.ko" "$here/out/SOURCE.txt"
docker volume create "$work_volume" >/dev/null

mounts=(-v "$work_volume:/work" -v "$here:/src:ro" -v "$here/out:/out")
if docker volume inspect "$shared_volume" >/dev/null 2>&1; then
    mounts+=(-v "$shared_volume:/opt/shared:ro")
fi
if [ -n "${REF_KO:-}" ]; then
    ref=$(cd "$(dirname "$REF_KO")" && pwd)/$(basename "$REF_KO")
    mounts+=(-v "$ref:/ref/ref.ko:ro")
fi

envs=()
for var in DRIVER_COMMIT JOBS FORCE_KERNEL_PREP REQUIRED_PARAMS; do
    if [ -n "${!var:-}" ]; then envs+=(-e "$var=${!var}"); fi
done

log=$here/out/build.log
{
    echo "EV6 8851bu build, $(date '+%Y-%m-%d %H:%M:%S %z'), host $(uname -sm)"
    echo "image $image, work volume $work_volume"
} > "$log"

docker run --rm --platform linux/amd64 \
    "${mounts[@]}" ${envs[@]+"${envs[@]}"} \
    "$image" bash /src/inner-build.sh 2>&1 | tee -a "$log"
