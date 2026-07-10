#!/bin/sh
set -eu

: "${HOST_UID:=1000}"
: "${HOST_GID:=1000}"

test -d /source || {
  echo "Mount the Butopia repository read-only at /source." >&2
  exit 1
}
test -d /export || {
  echo "Mount an output directory at /export." >&2
  exit 1
}

rm -rf /work
mkdir -p /work /home/builder/.cache
cp -a /source/. /work/
chown -R builder:builder /work /home/builder

su-exec builder env \
  HOME=/home/builder \
  BUTOPIA_CACHE_DIR=/home/builder/.cache/butopia \
  /work/scripts/build-linux.sh

rm -rf /export/*
cp -a /work/dist/. /export/
chown -R "$HOST_UID:$HOST_GID" /export 2>/dev/null || true
