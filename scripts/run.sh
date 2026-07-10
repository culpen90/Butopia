#!/bin/sh
set -eu

iso=${1:?usage: run.sh ISO [bios|uefi]}
firmware=${2:-bios}

test -f "$iso" || {
  echo "ISO not found: $iso" >&2
  exit 1
}

qemu=${QEMU_SYSTEM_X86_64:-qemu-system-x86_64}
memory=${BUTOPIA_QEMU_MEMORY_MB:-4096}
display_args=
if test "$(uname -s)" = Darwin; then
  display_args='-display cocoa'
fi

uefi_args=
if test "$firmware" = uefi; then
  ovmf=${OVMF_CODE:-/opt/homebrew/share/qemu/edk2-x86_64-code.fd}
  test -f "$ovmf" || {
    echo "UEFI firmware not found: $ovmf" >&2
    exit 1
  }
  uefi_args="-drive if=pflash,format=raw,readonly=on,file=$ovmf"
fi

# Word splitting is intentional for the small argument bundles above.
# shellcheck disable=SC2086
exec "$qemu" \
  -machine q35 \
  -accel tcg,thread=multi \
  -cpu max \
  -smp 2 \
  -m "$memory" \
  -boot order=d \
  -cdrom "$iso" \
  -netdev user,id=net0 \
  -device e1000,netdev=net0 \
  -serial stdio \
  -monitor none \
  $display_args $uefi_args
