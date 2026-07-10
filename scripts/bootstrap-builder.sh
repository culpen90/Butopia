#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
instance=${BUTOPIA_LIMA_INSTANCE:-butopia-builder}

command -v limactl >/dev/null 2>&1 || {
  echo "Lima is required. Install it with:" >&2
  echo "  brew install lima lima-additional-guestagents" >&2
  exit 1
}

if test "${1:-}" = "--delete"; then
  if limactl list -q | grep -Fx "$instance" >/dev/null 2>&1; then
    limactl stop -f "$instance" >/dev/null 2>&1 || true
    limactl delete -f "$instance"
  else
    printf 'Builder %s does not exist.\n' "$instance"
  fi
  exit 0
fi

if ! limactl list -q | grep -Fx "$instance" >/dev/null 2>&1; then
  printf 'Creating isolated builder %s...\n' "$instance"
  limactl create -y --name "$instance" "$root/builder/lima.yaml"
fi

state=$(limactl list "$instance" --format '{{.Status}}')
if test "$state" != "Running"; then
  printf 'Starting isolated builder %s...\n' "$instance"
  limactl start -y "$instance"
fi

attempt=0
until limactl shell "$instance" true >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  if test "$attempt" -ge 36; then
    echo "Builder SSH did not become stable after 180 seconds." >&2
    exit 1
  fi
  sleep 5
done
guest_user=$(limactl shell "$instance" id -un)
limactl shell "$instance" sudo addgroup "$guest_user" abuild >/dev/null 2>&1 || true
printf 'Builder %s is ready.\n' "$instance"
