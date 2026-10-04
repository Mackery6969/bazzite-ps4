#!/usr/bin/bash
# Install Bazzite PS4 onto a PS4 Linux root partition from a PC.
#
#   install-ps4.sh <partition> [image]
#
# image can be a registry reference, localhost/..., or a transport reference
# such as oci-archive:/path/to/image.tar for testing local builds.
#
# The partition is reformatted as ext4 labelled "psxitarch" (what the PS4
# Linux initramfs mounts) and receives an ostree sysroot deployed with bootc,
# so `bootc upgrade` and Bazzite's updater keep working on the console.

set -euo pipefail

PART="${1:-}"
IMAGE="${2:-ghcr.io/mackery6969/bazzite-ps4:stable}"
TARGET_IMGREF="${TARGET_IMGREF:-ghcr.io/mackery6969/bazzite-ps4:stable}"

if [[ -z "${PART}" || ! -b "${PART}" ]]; then
    echo "usage: $0 <partition, e.g. /dev/sda2> [image]" >&2
    exit 1
fi

if [[ "$(lsblk -dno TYPE "${PART}")" != "part" ]]; then
    echo "${PART} is not a partition; refusing to format a whole disk" >&2
    exit 1
fi

if findmnt -rn -S "${PART}" >/dev/null; then
    echo "${PART} is mounted; unmount it first" >&2
    exit 1
fi

lsblk -o NAME,SIZE,FSTYPE,LABEL,MODEL "${PART}"
echo
echo "Everything on ${PART} will be erased."
read -r -p "Type 'erase' to continue: " answer
[[ "${answer}" == "erase" ]] || { echo "Aborted."; exit 1; }

if [[ "${IMAGE}" != localhost/* && "${IMAGE}" != *:/* ]]; then
    sudo podman pull "${IMAGE}"
fi

sudo mkfs.ext4 -F -L psxitarch "${PART}"
# bootc requires UUID= mount specs; the PS4 boot shim ignores them anyway
UUID="$(sudo blkid -s UUID -o value "${PART}")"

MNT="$(mktemp -d)"
trap 'sudo umount "${MNT}" 2>/dev/null || true; rmdir "${MNT}"' EXIT
sudo mount "${PART}" "${MNT}"

run_image() {
    sudo podman run --rm --privileged --pid=host \
        --security-opt label=type:unconfined_t \
        -v /var/lib/containers:/var/lib/containers \
        -v /dev:/dev \
        -v "${MNT}:/target" \
        "${IMAGE}" "$@"
}

run_image bootc install to-filesystem \
    --bootloader none \
    --skip-finalize \
    --root-mount-spec "UUID=${UUID}" \
    --boot-mount-spec "UUID=${UUID}" \
    --target-imgref "${TARGET_IMGREF}" \
    /target

# bootc writes a /boot mount for the boot spec, but /boot is a plain directory
# on the same partition here; leaving it in fstab sends boot to emergency mode
run_image bash -c 'sed -i "\| /boot |d" /target/ostree/deploy/*/deploy/*/etc/fstab'

run_image /usr/libexec/bazzite-ps4/sync-init /target

sudo sync
echo
echo "Done. Put this drive in the PS4 and boot PS4 Linux as usual."
echo "First boot creates user 'bazzite' with password 'ps4linux'."
