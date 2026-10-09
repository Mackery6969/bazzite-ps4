#!/bin/sh
# Install Bazzite PS4 to the PS4's internal drive.
#
#   install-bazzite.sh [size-in-GB]
#
# Runs in the rescue shell of GattoDev's initramfs-ps4, which this file is
# appended to, or unattended from the bazzite-autoinstall hook
# (BAZZITE_AUTO=1: no prompts, and boot continues normally afterwards).
# Expects /user/system/boot/bazzite-ps4.ext4.xz (uploaded over FTP).
# linux.img is filled with zeros first so its space is really taken from the
# PS4 side, then the image is written into it. Bazzite grows the filesystem to
# the full size on first boot.

# Provided by initramfs-ps4
# shellcheck source=/dev/null
. /functions.sh

IMAGE=/ps4hdd/home/linux.img
SOURCE=/ps4hdd/system/boot/bazzite-ps4.ext4.xz
# Space the PS4 OS keeps after Linux takes its share
PS4_RESERVE_GB=20

bazzite-unlock-hdd.sh || exit 1

if [ ! -r "${SOURCE}" ]; then
    eerror "${SOURCE#/ps4hdd} not found. Upload bazzite-ps4.ext4.xz to /user/system/boot over FTP."
    exit 1
fi

# Space available to linux.img: free space plus whatever an old image holds
free_kb="$(df -k /ps4hdd | awk 'NR == 2 { print $4 }')"
case "${free_kb}" in
    ''|*[!0-9]*) eerror "Could not read free space on /ps4hdd."; exit 1 ;;
esac
old_kb=0
[ -e "${IMAGE}" ] && old_kb="$(du -k "${IMAGE}" | awk '{ print $1 }')"
max_gb=$(( (free_kb + old_kb) / 1048576 - PS4_RESERVE_GB ))

size_gb="$1"
if [ -z "${size_gb}" ] && [ -z "${BAZZITE_AUTO}" ]; then
    einfo "Up to ${max_gb} GB can go to Bazzite (${PS4_RESERVE_GB} GB stays free for the PS4)."
    eask "How many GB should Bazzite get? "
    read -r size_gb
fi

case "${size_gb}" in
    ''|*[!0-9]*) eerror "Not a number: ${size_gb}"; exit 1 ;;
esac
if [ "${size_gb}" -lt 32 ]; then
    eerror "Bazzite needs at least 32 GB."
    exit 1
fi
if [ "${size_gb}" -gt "${max_gb}" ]; then
    eerror "Only ${max_gb} GB available."
    exit 1
fi

if [ -z "${BAZZITE_AUTO}" ]; then
    ewarn "This replaces /user/home/linux.img (any Linux install in it is lost)."
    eask "Type 'erase' to install Bazzite with ${size_gb} GB: "
    read -r answer
    [ "${answer}" = erase ] || { einfo "Aborted."; exit 1; }
fi

umount /newroot 2>/dev/null
rm -f "${IMAGE}"

einfo "Reserving ${size_gb} GB. This writes the whole area once and takes a while"
einfo "(roughly $(( size_gb * 10 / 60 )) minutes on the stock drive). Don't power off."
dd if=/dev/zero of="${IMAGE}" bs=1M count=$(( size_gb * 1024 )) || { eerror "Reserving space failed."; exit 1; }

einfo "Writing Bazzite ..."
xz -dc "${SOURCE}" | dd of="${IMAGE}" bs=1M conv=notrunc || { eerror "Writing the image failed."; exit 1; }
sync

einfo "Checking the filesystem ..."
e2fsck -fn "${IMAGE}" || { eerror "The written filesystem has errors; re-run the installer."; exit 1; }

einfo "--INSTALL COMPLETE--"
einfo "Booting Bazzite. First boot grows the filesystem, then Bazzite's setup reboots once."
[ -n "${BAZZITE_AUTO}" ] && exit 0
find-install.sh
resume-boot
