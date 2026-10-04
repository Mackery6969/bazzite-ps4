# Bazzite for PS4 Linux

`bazzite-ps4` is `bazzite-deck` (KDE Plasma + Game Mode) with the changes a
PS4 needs. Unlike flat PS4 rootfs tarballs it keeps Bazzite's ostree layout,
so `bootc upgrade` and the Game Mode update button keep working.

## How it boots

The PS4 cannot run GRUB or Bazzite's initramfs. The Linux payload kexecs a PS4
kernel (`bzImage`) and the better-initramfs `initramfs.cpio.gz`, which mounts
the ext4 partition labelled `psxitarch` and runs its `/sbin/init`.

On a `bazzite-ps4` install, `/sbin/init` on that partition is a small shim
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

## Kernel

Use any PS4 kernel for your southbridge. Recommended: rmuxnet's
[Strawberry kernels](https://gitlab.com/rmuxnet/linux/-/releases), **General**
profile, Aeolia/Belize build. 7.1.x adds overlayfs, which Podman, Distrobox
and Waydroid want. The RAM/VRAM split is set by the payload, not the OS.

## Install

From a Linux PC with Podman, with the PS4 USB drive attached:

```sh
just install-ps4 /dev/sdX2
```

This **erases** the partition, formats it as ext4 labelled `psxitarch`,
deploys the image with `bootc install to-filesystem --bootloader none`, and
installs the shim. Keep `bzImage` and `initramfs.cpio.gz` on the boot
partition as before.

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

Mesa patch from [DionKill/ps4-video-archlinux](https://github.com/DionKill/ps4-video-archlinux)
(based on centi07/arch-ps4-aur). Fan control from
[JKeyRandom/ps4fancontrol](https://github.com/JKeyRandom/ps4fancontrol),
derived from Ps3itaTeam's. Kernels by rmuxnet, crashniels, feeRnt and the
PS4 Linux community.
