#!/bin/sh
set -eu

hostname=${1:-butopia}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

makefile() {
	owner=$1
	mode=$2
	path=$3
	mkdir -p "$(dirname "$path")"
	cat >"$path"
	chown "$owner" "$path"
	chmod "$mode" "$path"
}

rc_add() {
	service=$1
	runlevel=$2
	mkdir -p "$tmp/etc/runlevels/$runlevel"
	ln -sf "/etc/init.d/$service" "$tmp/etc/runlevels/$runlevel/$service"
}

makefile root:root 0644 "$tmp/etc/hostname" <<EOF
$hostname
EOF

makefile root:root 0644 "$tmp/etc/network/interfaces" <<'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

makefile root:root 0644 "$tmp/etc/apk/world" <<'EOF'
alpine-base
bash
bash-completion
bind-tools
butopia-base
butopia-desktop
butopia-installer
butopia-release
ca-certificates
chrony
curl
dhcpcd
doas
e2fsprogs
file
git
htop
iproute2
iputils
jq
less
nano
openssh
parted
pciutils
ripgrep
tmux
util-linux
usbutils
EOF

makefile root:root 0644 "$tmp/etc/inittab" <<'EOF'
# Butopia OpenRC/BusyBox init configuration
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default

tty1::respawn:/sbin/getty 38400 tty1
tty2::respawn:/sbin/getty 38400 tty2
tty3::respawn:/sbin/getty 38400 tty3
tty4::respawn:/sbin/getty 38400 tty4
tty5::respawn:/sbin/getty 38400 tty5
tty6::respawn:/sbin/getty 38400 tty6
ttyS0::respawn:/sbin/getty -L 115200 ttyS0 vt100

::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/openrc shutdown
EOF

rc_add devfs sysinit
rc_add dmesg sysinit
rc_add udev sysinit
rc_add udev-trigger sysinit
rc_add udev-settle sysinit
rc_add hwdrivers sysinit
rc_add modloop sysinit

rc_add hwclock boot
rc_add modules boot
rc_add sysctl boot
rc_add hostname boot
rc_add bootmisc boot
rc_add syslog boot
rc_add dbus boot
rc_add elogind boot
rc_add udev-postmount boot

rc_add networkmanager default
rc_add chronyd default
rc_add butopia-ready default
rc_add lightdm default
rc_add butopia-gui-ready default

rc_add mount-ro shutdown
rc_add killprocs shutdown
rc_add savecache shutdown

if test -n "${SOURCE_DATE_EPOCH:-}"; then
	find "$tmp" -exec touch -h -d "@${SOURCE_DATE_EPOCH}" {} +
fi

tar -c -C "$tmp" etc | gzip -9n >"$hostname.apkovl.tar.gz"
