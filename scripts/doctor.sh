#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
status=0

printf 'Butopia host doctor\n'
printf '  repository: %s\n' "$root"
printf '  host:       %s %s\n' "$(uname -s)" "$(uname -m)"

check_command() {
  label=$1
  command_name=$2
  if command -v "$command_name" >/dev/null 2>&1; then
    printf '  %-11s OK (%s)\n' "$label" "$(command -v "$command_name")"
  else
    printf '  %-11s MISSING (%s)\n' "$label" "$command_name"
    status=1
  fi
}

check_command qemu qemu-system-x86_64
check_command python python3
check_command git git

case "$(uname -s)" in
  Darwin)
    if command -v limactl >/dev/null 2>&1; then
      printf '  %-11s OK (%s)\n' builder "$(limactl --version | head -1)"
    elif command -v docker >/dev/null 2>&1 || command -v podman >/dev/null 2>&1; then
      printf '  %-11s OK (container runtime)\n' builder
    else
      printf '  %-11s MISSING (install lima and lima-additional-guestagents)\n' builder
      status=1
    fi
    ;;
  Linux)
    if test -f /etc/alpine-release; then
      printf '  %-11s OK (Alpine %s)\n' builder "$(cat /etc/alpine-release)"
    else
      printf '  %-11s INFO (use builder/Containerfile or an Alpine builder)\n' builder
    fi
    ;;
esac

if test "$status" -ne 0; then
  printf '\nOne or more required host tools are missing.\n' >&2
  exit "$status"
fi

printf '\nHost prerequisites look good.\n'
