#!/usr/bin/bash
# Build bazzite-ps4.ext4.xz for internal PS4 installs.
#
#   build-ps4-image.sh [output] [image]
#
# Produces a minimal-size ext4 filesystem (label "psxitarch") holding a bootc
# deployment of the image plus the PS4 boot shim. install-bazzite.sh writes it
# into the preallocated /user/home/linux.img on the console, and Bazzite grows
# it to the full size on first boot. A filesystem image, unlike a tarball,
# keeps file capabilities such as gamescope's and newuidmap's.

set -euo pipefail

OUT="$(realpath -m "${1:-bazzite-ps4.ext4.xz}")"
IMAGE="${2:-ghcr.io/mackery6969/bazzite-ps4:stable}"
TARGET_IMGREF="${TARGET_IMGREF:-ghcr.io/mackery6969/bazzite-ps4:stable}"
# Room for one deployment while building; shrunk to the minimum afterwards
BUILD_SIZE=40G

if [[ "${IMAGE}" != localhost/* && "${IMAGE}" != *:/* ]]; then
    sudo podman pull "${IMAGE}"
fi

WORK="$(mktemp -d /var/tmp/bazzite-ps4-image.XXXXXX)"
FS="${WORK}/root.ext4"
MNT="${WORK}/mnt"
LOOP=""

cleanup() {
    sudo umount "${MNT}" 2>/dev/null || true
    [[ -n "${LOOP}" ]] && sudo losetup -d "${LOOP}" 2>/dev/null || true
    rm -rf "${WORK}"
}
trap cleanup EXIT

truncate -s "${BUILD_SIZE}" "${FS}"
mkfs.ext4 -q -L psxitarch "${FS}"
UUID="$(tune2fs -l "${FS}" | awk -F': *' '/^Filesystem UUID/ { print $2 }')"

mkdir -p "${MNT}"
LOOP="$(sudo losetup --find --show "${FS}")"
sudo mount "${LOOP}" "${MNT}"

# shellcheck source=just_scripts/ps4-deploy.sh
. "$(dirname "$(realpath "$0")")/ps4-deploy.sh"
deploy_ps4 "${MNT}" "${UUID}" "${IMAGE}" "${TARGET_IMGREF}"
add_wifi_ps4 "${MNT}"

sudo umount "${MNT}"
sudo losetup -d "${LOOP}"
LOOP=""

e2fsck -fy "${FS}" >/dev/null || [[ $? -le 1 ]]
resize2fs -M "${FS}"
blocks="$(dumpe2fs -h "${FS}" 2>/dev/null | awk -F': *' '/^Block count/ { print $2 }')"
block_size="$(dumpe2fs -h "${FS}" 2>/dev/null | awk -F': *' '/^Block size/ { print $2 }')"
truncate -s $(( blocks * block_size )) "${FS}"
e2fsck -fn "${FS}"

echo "Compressing $(( blocks * block_size >> 20 )) MiB filesystem ..."
xz -T0 -6 -c "${FS}" > "${OUT}.tmp"
mv -f "${OUT}.tmp" "${OUT}"

echo
echo "Wrote ${OUT} ($(du -h "${OUT}" | cut -f1))"
echo "Upload it to /user/system/boot/ on the PS4, then run install-bazzite.sh"
echo "from the initramfs-ps4 rescue shell."
