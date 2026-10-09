#!/bin/sh
# Unlock the PS4's internal user partition and mount it at /ps4hdd, the same
# way initramfs-ps4's init does. Exits 0 if /ps4hdd is mounted afterwards.
# The Linux loader payload provides /key/eap_hdd_key.bin.

# Provided by initramfs-ps4
# shellcheck source=/dev/null
. /functions.sh

mountpoint -q /ps4hdd && exit 0

if [ ! -r /key/eap_hdd_key.bin ]; then
    eerror "No HDD key at /key/eap_hdd_key.bin; boot with a Linux loader payload."
    exit 1
fi

if [ ! -e /dev/mapper/ps4hdd ]; then
    cryptsetup -d /key/eap_hdd_key.bin --cipher aes-xts-plain64 -s 256 --offset 0 \
        --skip 111669149696 create ps4hdd /dev/sd?27 || { eerror "Unlocking the internal drive failed."; exit 1; }
fi
mkdir -p /ps4hdd
mount -t ufs -o ufstype=ufs2 /dev/mapper/ps4hdd /ps4hdd || { eerror "Mounting the PS4 storage failed."; exit 1; }
