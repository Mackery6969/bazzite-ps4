#!/usr/bin/bash
# Build the initramfs for internal PS4 installs.
#
#   build-ps4-initramfs.sh [output]
#
# GattoDev's initramfs-ps4 already unlocks the PS4 drive and boots
# /user/home/linux.img. The kernel unpacks concatenated cpio archives in
# order, so appending ps4_initramfs/ adds install-bazzite.sh without
# rebuilding it. The Linux loader payload appends the HDD key and GPU firmware
# the same way at boot.

set -euo pipefail

OUT="$(realpath -m "${1:-initramfs.cpio.gz}")"
SRC="$(dirname "$(realpath "$0")")/../ps4_initramfs"
GATTO_REPO=GattoDev-debug/initramfs-ps4
GATTO_TAG=build-8404a67
GATTO_SHA256=52241ad1b44e8b35adc181c960a5bc8144c3ca68c515fa4ef0f6385baa50da6f

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

curl -fsSL --retry 3 -o "${WORK}/base.cpio.gz" \
    "https://github.com/${GATTO_REPO}/releases/download/${GATTO_TAG}/initramfs.cpio.gz"
echo "${GATTO_SHA256}  ${WORK}/base.cpio.gz" | sha256sum -c --quiet

(cd "${SRC}" && find . -mindepth 1 | sort | cpio -o -H newc --owner=0:0 --quiet) | gzip -9 > "${WORK}/bazzite.cpio.gz"

cat "${WORK}/base.cpio.gz" "${WORK}/bazzite.cpio.gz" > "${OUT}"
echo "Wrote ${OUT} (initramfs-ps4 ${GATTO_TAG} + install-bazzite.sh)"
