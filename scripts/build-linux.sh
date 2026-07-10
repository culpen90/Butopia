#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$root/locks/sources.env"

if ! test -f /etc/alpine-release; then
	echo "Butopia ISO assembly requires an Alpine Linux builder." >&2
	exit 1
fi

if test "$(apk --print-arch)" != x86_64; then
	echo "The canonical Butopia 0.1 builder must be x86_64." >&2
	exit 1
fi

if ! id -nG | tr ' ' '\n' | grep -qx abuild; then
	echo "The builder user must run with membership in the abuild group." >&2
	exit 1
fi

for command_name in abuild apk git grub-mkimage mksquashfs openssl xorriso; do
	command -v "$command_name" >/dev/null 2>&1 || {
		echo "Missing builder command: $command_name" >&2
		exit 1
	}
done

actual_version=$(tr -d '\n' <"$root/VERSION")
if test "$actual_version" != "$BUTOPIA_VERSION"; then
	echo "VERSION ($actual_version) does not match sources.env ($BUTOPIA_VERSION)." >&2
	exit 1
fi

cache=${BUTOPIA_CACHE_DIR:-$HOME/.cache/butopia}
aports="$cache/aports"
keys="$cache/keys"
repository="$cache/repository"
mkhome="$cache/mkimage-home"
work="$cache/mkimage-work-$BUTOPIA_VERSION"
dist="$root/dist"

mkdir -p "$cache" "$keys" "$dist"

if ! test -d "$aports/.git"; then
	rm -rf "$aports"
	git init -q "$aports"
	git -C "$aports" remote add origin "$APORTS_REPOSITORY"
fi

if ! git -C "$aports" cat-file -e "$APORTS_COMMIT^{commit}" 2>/dev/null; then
	git -C "$aports" fetch --depth=1 origin \
		"refs/tags/$APORTS_TAG:refs/tags/$APORTS_TAG"
fi

git -C "$aports" checkout -q --detach "$APORTS_COMMIT"
checked_out=$(git -C "$aports" rev-parse HEAD)
test "$checked_out" = "$APORTS_COMMIT" || {
	echo "Pinned aports commit mismatch: $checked_out" >&2
	exit 1
}

if test -n "${BUTOPIA_SIGNING_KEY:-}"; then
	private_key=$BUTOPIA_SIGNING_KEY
else
	private_key="$keys/butopia.rsa"
fi
public_key="$private_key.pub"

if ! test -f "$private_key"; then
	umask 077
	openssl genrsa -out "$private_key" 4096 >/dev/null 2>&1
fi
if ! test -f "$public_key"; then
	openssl rsa -in "$private_key" -pubout -out "$public_key" >/dev/null 2>&1
fi

trusted_key="/etc/apk/keys/$(basename "$public_key")"
if ! test -f "$trusted_key" || ! cmp -s "$public_key" "$trusted_key"; then
	command -v sudo >/dev/null 2>&1 || {
		echo "sudo is required once to trust the Butopia public build key." >&2
		exit 1
	}
	sudo install -m 0644 "$public_key" "$trusted_key"
fi

export BUTOPIA_VERSION ALPINE_VERSION SOURCE_DATE_EPOCH
export PACKAGER="Butopia Build <build@butopia.invalid>"
export PACKAGER_PRIVKEY="$private_key"
export PACKAGER_PUBKEY="$public_key"
export REPODEST="$repository"

rm -rf "$repository"
mkdir -p "$repository"

for package in butopia-release butopia-base butopia-desktop butopia-installer; do
	printf 'Building %s APK...\n' "$package"
	(
		cd "$root/distro/packages/$package"
		abuild clean >/dev/null 2>&1 || true
		# These are noarch configuration/meta packages. Runtime dependencies are
		# resolved by mkimage for the target ISO, not installed into the builder.
		abuild -d -r
	)
done

apk_directory=$(find "$repository" -type f -name 'butopia-desktop-*.apk' \
	-exec dirname {} \; | head -1)
if test -z "$apk_directory"; then
	echo "The Butopia APK repository was not produced." >&2
	exit 1
fi
custom_repository=${apk_directory%/x86_64}

rm -rf "$mkhome" "$work"
mkdir -p "$mkhome/.mkimage" "$work"
cp "$root/distro/mkimage/mkimg.butopia.sh" "$mkhome/.mkimage/"
cp "$root/distro/mkimage/genapkovl-butopia.sh" "$mkhome/.mkimage/"
cp "$root/distro/mkimage/update-kernel-butopia" "$mkhome/.mkimage/"
# Alpine's apkovl section hashes the script relative to the aports working
# directory before resolving its normal $HOME/.mkimage fallback.
cp "$root/distro/mkimage/genapkovl-butopia.sh" "$aports/"
chmod 0755 \
	"$mkhome/.mkimage/genapkovl-butopia.sh" \
	"$aports/genapkovl-butopia.sh" \
	"$mkhome/.mkimage/update-kernel-butopia"

rm -rf "$dist"/*

printf 'Assembling Butopia %s ISO...\n' "$BUTOPIA_VERSION"
(
	cd "$aports"
	HOME="$mkhome" \
	PACKAGER_PRIVKEY="$private_key" \
	PACKAGER_PUBKEY="$public_key" \
	SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
	sh scripts/mkimage.sh \
		--tag "$BUTOPIA_VERSION" \
		--outdir "$dist" \
		--workdir "$work" \
		--arch x86_64 \
		--profile butopia \
		--repository "file://$custom_repository" \
		--repository "$ALPINE_MIRROR/$ALPINE_BRANCH/main" \
		--repository "$ALPINE_MIRROR/$ALPINE_BRANCH/community" \
		--checksum
)

iso="$dist/butopia-$BUTOPIA_VERSION-x86_64.iso"
test -s "$iso" || {
	echo "Expected ISO was not produced: $iso" >&2
	exit 1
}

manifest_tmp=$(mktemp -d)
trap 'rm -rf "$manifest_tmp"' EXIT INT TERM
xorriso -osirrox on -indev "$iso" \
	-extract /apks/x86_64/APKINDEX.tar.gz "$manifest_tmp/APKINDEX.tar.gz" \
	>/dev/null 2>&1
tar -xOf "$manifest_tmp/APKINDEX.tar.gz" APKINDEX \
	| awk '
		/^P:/ { package = substr($0, 3) }
		/^V:/ { version = substr($0, 3) }
		/^$/ {
			if (package != "" && version != "") print package "=" version
			package = ""; version = ""
		}
		END { if (package != "" && version != "") print package "=" version }
	' \
	| sort -u >"$dist/APK-MANIFEST.txt"

install -m 0644 "$public_key" "$dist/butopia-signing-key.rsa.pub"
(
	cd "$dist"
	sha256sum "$(basename "$iso")" >SHA256SUMS
)

cat >"$dist/BUILD-METADATA.txt" <<EOF
Butopia version: $BUTOPIA_VERSION ($BUTOPIA_CODENAME)
Alpine compatibility: $ALPINE_VERSION
Aports commit: $APORTS_COMMIT
Source date epoch: $SOURCE_DATE_EPOCH
Architecture: x86_64
Desktop: Xfce with LightDM
EOF

printf '\nBuilt %s\n' "$iso"
cat "$dist/SHA256SUMS"
