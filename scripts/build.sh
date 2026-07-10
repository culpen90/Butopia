#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if test "$(uname -s)" = Linux && test -f /etc/alpine-release; then
  exec "$root/scripts/build-linux.sh"
fi

if command -v limactl >/dev/null 2>&1; then
  instance=${BUTOPIA_LIMA_INSTANCE:-butopia-builder}
  "$root/scripts/bootstrap-builder.sh"

  stage=$(mktemp -d "${TMPDIR:-/tmp}/butopia-build.XXXXXX")
  trap 'rm -rf "$stage"' EXIT INT TERM

  archive="$stage/source.tar.gz"
  COPYFILE_DISABLE=1 tar -C "$root" \
    --no-acls \
    --no-fflags \
    --no-mac-metadata \
    --no-xattrs \
    --exclude .git \
    --exclude .build \
    --exclude .cache \
    --exclude dist \
    -czf "$archive" .

  limactl shell "$instance" sh -lc \
    'rm -rf /tmp/butopia-src /tmp/butopia-source.tar.gz && mkdir -p /tmp/butopia-src'
  limactl copy --backend=scp "$archive" "$instance:/tmp/butopia-source.tar.gz"
  limactl shell "$instance" sh -lc \
    'tar -xzf /tmp/butopia-source.tar.gz -C /tmp/butopia-src && cd /tmp/butopia-src && sudo -u "$(id -un)" -g abuild env HOME="$HOME" BUTOPIA_CACHE_DIR="$HOME/.cache/butopia" ./scripts/build-linux.sh'

  limactl copy --backend=scp -r "$instance:/tmp/butopia-src/dist" "$stage/"
  mkdir -p "$root/dist"
  rm -rf "$root/dist"/*
  cp -a "$stage/dist"/. "$root/dist"/
  printf 'Butopia artifacts copied to %s/dist\n' "$root"
  exit 0
fi

runtime=
if command -v docker >/dev/null 2>&1; then
  runtime=docker
elif command -v podman >/dev/null 2>&1; then
  runtime=podman
fi

if test -n "$runtime"; then
  "$runtime" build -t butopia-builder -f "$root/builder/Containerfile" "$root"
  mkdir -p "$root/dist"
  "$runtime" run --rm \
    -e "HOST_UID=$(id -u)" \
    -e "HOST_GID=$(id -g)" \
    -v "$root:/source:ro" \
    -v "$root/dist:/export" \
    butopia-builder
  exit 0
fi

echo "No supported Linux builder is available." >&2
echo "On macOS, run: brew install lima lima-additional-guestagents" >&2
exit 1
