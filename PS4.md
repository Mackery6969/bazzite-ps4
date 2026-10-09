# Bazzite for PS4 Linux

`bazzite-ps4` is `bazzite-deck` (KDE Plasma + Game Mode) with the changes a
PS4 needs. Unlike flat PS4 rootfs tarballs it keeps Bazzite's ostree layout,
so `bootc upgrade` and the Game Mode update button keep working.

## How it boots

The PS4 cannot run GRUB or Bazzite's initramfs. The Linux payload kexecs a PS4
kernel (`bzImage`) and an initramfs from `/data/linux/boot`, adding the
console's HDD key and GPU firmware to it. The initramfs mounts the Linux root
and runs its `/sbin/init`:

- internal installs: `/user/home/linux.img` on the PS4's own drive, an ext4
  image that GattoDev's [initramfs-ps4](https://github.com/GattoDev-debug/initramfs-ps4)
  unlocks and mounts;
- external installs: an ext4 partition labelled `psxitarch` on a USB drive.

On a `bazzite-ps4` install, `/sbin/init` in that filesystem is a small shim
(`/bazzite/init`, run by a static busybox). It:

1. picks the newest ostree deployment from `/boot/loader/entries`
   (`bazzite.entry=N` on the kernel command line picks another one),
2. bind-mounts it with `/var`, a read-only `/usr` and `/sysroot` the way
   `ostree-prepare-root` would,
3. adds the deployment's `ostree=` argument to a bind-mounted
   `/proc/cmdline`, because bootc and rpm-ostree find the booted deployment
   through it,
4. pivots into the deployment and starts systemd.

`bazzite-ps4-sync-init.service` copies the shim from each new image onto the
partition, so updates to it ship like any other change.
`bazzite-ps4-growfs.service` grows the filesystem to fill `linux.img`.

## What differs from bazzite-deck

| Change | Why |
| --- | --- |
| Mesa rebuilt with the Liverpool/Gladius patch (x86_64 + i686), from this repo's `mesa-*` releases | radeonsi and RADV don't know the PS4 GPU otherwise |
| PS4 entries in `amdgpu.ids` | GPU name |
| composefs off (`prepare-root.conf`) | PS4 kernels have no EROFS or fs-verity |
| (SELinux stays configured but is inactive) | PS4 kernels are built without LSMs; keeping the policy lets bootc label files when installing from an SELinux host |
| `ps4fc.service` + `ps4fancontrol` | fan threshold over `/dev/icc`; set with `sudo ps4fancontrol --set 70` |
| tuned defaults to `throughput-performance-bazzite` | keeps the CPU governor at `performance` instead of Fedora's `balanced` |
| udev rule forcing GPU DPM level `high` | full GPU clocks when the kernel has DPM enabled |
| greenboot and bootupd units disabled | they drive GRUB, which the PS4 does not use |
| first boot creates `bazzite` / `ps4linux` (UID 1000) | no installer on the console; Game Mode autologin uses UID 1000 |
| first boot grows the root filesystem | internal installs start from a minimal image |

## Kernel

Use any PS4 kernel for your southbridge. Recommended: rmuxnet's
[Strawberry kernels](https://gitlab.com/rmuxnet/linux/-/releases), **General**
profile, Aeolia/Belize build. 7.1.x adds overlayfs, which Podman, Distrobox
and Waydroid want. The RAM/VRAM split is set by the payload, not the OS.

## Install to the PS4's internal drive

Linux lives in one file, `/user/home/linux.img`, on the PS4's storage. The
installer fills it with zeros first, so its size is really taken from the PS4
side (a sparse file would let PS4 games eat the space Linux expects).

On a Linux PC with Podman, in this repo:

```sh
just build-ps4-image        # bazzite-ps4.ext4.xz; asks for sudo and,
                            # optionally, WiFi details to preconfigure
just build-ps4-initramfs    # initramfs.cpio.gz: initramfs-ps4 + installer
```

The image holds a bootc deployment in a minimal ext4 filesystem. A filesystem
image keeps file capabilities (gamescope, newuidmap) that the stock installer's
busybox `tar` would drop. If you preconfigured WiFi, the image contains that
password, so don't share it.

Over FTP (GoldHEN, port 2121):

1. `/data/linux/boot/`: keep your `bzImage`; rename the old
   `initramfs.cpio.gz` to keep a backup and upload the new one.
2. `/user/system/boot/`: upload `bazzite-ps4.ext4.xz`.
3. `/user/system/boot/`: upload `bazzite-install.conf` containing one line,
   `SIZE=650` (GB for Bazzite; at least 32, and 20 GB always stays free for
   the PS4). This file starts the install.

Launch the `linux-1024mb.bin` payload. The initramfs unlocks the drive, sees
`bazzite-install.conf`, reserves the space (about 10 seconds per GB on the
stock drive, so roughly 2 hours for 650 GB), writes Bazzite, renames the file
to `bazzite-install.done` and boots. No keyboard needed. If it fails, the file
becomes `bazzite-install.failed` and the rescue shell opens.

Manual alternative: from the initramfs rescue shell run `install-bazzite.sh`,
which asks for the size and an `erase` confirmation.

After the first boot, a `linux-2048mb.bin` payload gives the GPU more memory.

## Install to a USB drive

From a Linux PC with Podman, with the drive attached:

```sh
just install-ps4 /dev/sdX2
```

This **erases** the partition, formats it as ext4 labelled `psxitarch`,
deploys the image with `bootc install to-filesystem --bootloader none`, and
installs the shim. Both initramfs builds boot a `psxitarch` USB partition.

## Updating

Normal Bazzite updates work: the Game Mode update button, `ujust update` or
`sudo bootc upgrade`. Reboot (back through the payload) to switch to the new
deployment. `sudo bootc rollback` swaps back to the previous one.

## CI

- `build_ps4_mesa.yml`: every 6 hours, checks Terra's Mesa version. When there
  is no `mesa-<version>-<release>.ps4.fcNN` release yet, it builds the SRPM
  with `spec_files/mesa-ps4/make-srpm.sh`, rebuilds it with `mock` for x86_64
  and i686 in parallel, publishes the RPMs as that release, then triggers the
  image build. No accounts or secrets beyond the default `GITHUB_TOKEN`.
- `build_ps4.yml`: every 6 hours, rebuilds `ghcr.io/mackery6969/bazzite-ps4`
  when upstream pushes a new `bazzite-deck`. Pushes from the `ps4` branch.
  The image build fails with a clear message if the Mesa release for the base
  image's Terra version doesn't exist yet; the next Mesa run fixes that.

The first time, run **Build PS4 Mesa** by hand from the Actions tab, and make
the `bazzite-ps4` package public under your GitHub profile's Packages after the
first image push so the PS4 can pull updates without logging in.

## Credits

Internal installs use GattoDev's
[initramfs-ps4](https://github.com/GattoDev-debug/initramfs-ps4).
Mesa patch from [DionKill/ps4-video-archlinux](https://github.com/DionKill/ps4-video-archlinux)
(based on centi07/arch-ps4-aur). Fan control from
[JKeyRandom/ps4fancontrol](https://github.com/JKeyRandom/ps4fancontrol),
derived from Ps3itaTeam's. Kernels by rmuxnet, crashniels, feeRnt and the
PS4 Linux community.
