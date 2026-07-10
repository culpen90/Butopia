# Butopia mkimage profile. This file is sourced by Alpine's mkimage.sh.

profile_butopia() {
	profile_standard

	: "${BUTOPIA_VERSION:=0.1.0}"
	title="Butopia Linux"
	desc="Butopia Linux ${BUTOPIA_VERSION}: a graphical, installable, Alpine-compatible live distribution."
	profile_abbrev="butopia"
	image_name="butopia"
	output_filename="butopia-${BUTOPIA_VERSION}-${ARCH}.iso"
	arch="x86_64"
	hostname="butopia"
	apkovl="genapkovl-butopia.sh"

	syslinux_serial="0 115200"
	syslinux_timeout="30"
	kernel_cmdline="console=tty0 console=ttyS0,115200"
	grub_mod="$grub_mod serial"

	apks="$apks
		butopia-release butopia-base butopia-desktop butopia-installer
		bash bash-completion bind-tools ca-certificates curl file git
		htop iproute2 iputils jq less nano parted pciutils ripgrep
		tmux util-linux usbutils
		"
}

# Alpine's stock update-kernel uses XZ for its SquashFS modloop. Butopia keeps
# the same signed modloop design but uses Zstandard, which the pinned LTS
# kernel supports natively and which is dramatically faster under the
# cross-architecture Lima builder used on Apple silicon.
build_kernel() {
	local _flavor="$2" _modloopsign= _add
	shift 3
	local _pkgs="$@"
	if [ "$modloop_sign" = "yes" ]; then
		_modloopsign="--modloopsign --apk-pubkey $_abuild_pubkey"
		if [ -z "$PACKAGER_PRIVKEY" ]; then
			error "Need \$PACKAGER_PRIVKEY to be set for modloop_sign=yes"
			return 1
		fi
	fi
	"$HOME/.mkimage/update-kernel-butopia" \
		$_hostkeys \
		$_modloopsign \
		--media \
		--cache-dir "$APKROOT/etc/apk/cache" \
		--keys-dir "$APKROOT/etc/apk/keys" \
		--flavor "$_flavor" \
		--arch "$ARCH" \
		--package "$_pkgs" \
		--feature "$initfs_features" \
		--modloopfw "$modloopfw" \
		--repositories-file "$APKROOT/etc/apk/repositories" \
		"$DESTDIR"
	for _add in $boot_addons; do
		apk fetch --root "$APKROOT" --quiet --stdout $_add | tar -C "${DESTDIR}" -zx boot/
	done
}

# mkimage uses this label for EFI discovery and for the ISO volume name.
gen_volid() {
	printf 'BUTOPIA_%s_%s' "$RELEASE" "$ARCH" \
		| tr '[:lower:].-' '[:upper:]__' \
		| cut -c1-32
}

syslinux_gen_config() {
	printf 'SERIAL 0 115200\n'
	printf 'TIMEOUT %s\n' "${syslinux_timeout:-30}"
	printf 'PROMPT 0\n'
	printf 'DEFAULT %s\n' "${kernel_flavors%% *}"

	local flavor part initrd
	for flavor in $kernel_flavors; do
		initrd="/boot/initramfs-$flavor"
		for part in $initrd_ucode; do
			initrd="$part,$initrd"
		done
		cat <<-EOF

		LABEL $flavor
			MENU LABEL Butopia Linux ${BUTOPIA_VERSION} ($flavor kernel)
			KERNEL /boot/vmlinuz-$flavor
			INITRD $initrd
			APPEND $initfs_cmdline $kernel_cmdline
		EOF
	done
}

grub_gen_config() {
	cat <<-EOF
	set default="0"
	set timeout="3"
	serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1
	terminal_input console serial
	terminal_output console serial
	EOF

	local flavor part initrd
	for flavor in $kernel_flavors; do
		initrd="/boot/initramfs-$flavor"
		for part in $initrd_ucode; do
			initrd="$part $initrd"
		done
		cat <<-EOF

		menuentry "Butopia Linux ${BUTOPIA_VERSION} ($flavor kernel)" {
			linux /boot/vmlinuz-$flavor $initfs_cmdline $kernel_cmdline
			initrd $initrd
		}
		EOF
	done
}
