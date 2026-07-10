# Butopia architecture

Butopia 0.1 is an Alpine-compatible distribution layer, not an ISO with only a
changed wallpaper or banner.

The release has five owned layers:

1. `distro/mkimage/mkimg.butopia.sh` defines the hardware target, GUI package set,
   serial/VGA kernel command line, boot menus, ISO name, and volume ID.
2. `distro/packages/` contains signed APKs for release identity, the base
   command/service layer, the graphical desktop, and the installer entry point.
3. `distro/mkimage/genapkovl-butopia.sh` defines the live system's package
   world, OpenRC runlevels, console policy, hostname, and DHCP configuration.
4. `scripts/build-linux.sh` assembles the local APK repository and invokes a
   pinned Alpine `mkimage` implementation.
5. `tests/smoke_boot.py` boots the artifact and proves its identity and running
   Xfce session through both SeaBIOS and EDK2 UEFI.

The ISO uses Alpine's LTS kernel, musl, OpenRC, BusyBox, and APK ecosystem.
Butopia replaces the release-facing `os-release`, issue, and motd files while
retaining `/etc/alpine-release` for compatibility. The distinction is explicit:

```text
ID=butopia
ID_LIKE=alpine
```

The signed kernel modloop remains SquashFS but uses Zstandard level 5. The
pinned LTS kernel enables SquashFS Zstandard support, keeping the boot image
compact while making x86_64 builds practical on Apple-silicon hosts using QEMU
translation.

The older Butopia real-mode hobby kernel is intentionally not imported. A
16-bit floppy loader, BIOS drawing code, and a macOS serial host bridge would
not form a Linux distribution and would weaken the security boundary.

## Boot and install model

The image is a hybrid ISO with ISOLINUX for legacy BIOS and GRUB for x86_64
UEFI. The live root runs from RAM and uses the ISO as its signed boot package
repository. LightDM automatically starts an unprivileged `butopia` Xfce live
session. Both `tty1` and `ttyS0` retain root recovery consoles.

The desktop layer owns the wallpaper, icon, welcome center, LightDM policy,
Xfce defaults, desktop launchers, NetworkManager integration, and the
`BUTOPIA_GUI_READY` boot assertion. Xorg uses broad open-source PC video drivers
and a VESA fallback so the same ISO can boot in QEMU and on ordinary hardware.

`setup-butopia` is a guarded branding wrapper around `setup-alpine`. The
installed system retains Butopia's packages and identity because they are in
the live `/etc/apk/world`, rather than being injected only as an ephemeral
overlay.

## Security boundary

The live root account has no password, matching the physical-console recovery
model. No remote service is enabled by default. The build generates an RSA
package-signing key in the builder's persistent private cache; the private key
is never copied into this repository or the ISO. Production releases should
provide a protected long-lived key through the documented environment hook.
