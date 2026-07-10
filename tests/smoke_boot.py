#!/usr/bin/env python3
"""Boot a Butopia ISO and verify its CLI and graphical live session."""

from __future__ import annotations

import argparse
import os
import selectors
import shutil
import subprocess
import sys
import time
from pathlib import Path


REQUIRED_OUTPUT = (
    "BUTOPIA_BOOT_OK version=0.1.0 arch=x86_64",
    "BUTOPIA_GUI_READY display_manager=lightdm desktop=xfce",
    "SMOKE_ID=butopia",
    "SMOKE_ID_LIKE=alpine",
    "SMOKE_ARCH=x86_64",
    "SMOKE_BASE_APK=ok",
    "SMOKE_DESKTOP_APK=ok",
    "SMOKE_LIGHTDM=ok",
    "SMOKE_XFCE=ok",
    "SMOKE_OK",
)


def find_uefi_firmware() -> Path:
    candidates = (
        os.environ.get("OVMF_CODE"),
        "/opt/homebrew/share/qemu/edk2-x86_64-code.fd",
        "/usr/local/share/qemu/edk2-x86_64-code.fd",
        "/usr/share/OVMF/OVMF_CODE.fd",
        "/usr/share/edk2/x64/OVMF_CODE.fd",
        "/usr/share/qemu/OVMF.fd",
    )
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return Path(candidate)
    raise FileNotFoundError("x86_64 EDK2/OVMF firmware was not found")


def qemu_command(iso: Path, firmware: str) -> list[str]:
    qemu = os.environ.get("QEMU_SYSTEM_X86_64") or shutil.which(
        "qemu-system-x86_64"
    )
    if not qemu:
        raise FileNotFoundError("qemu-system-x86_64 is not installed")

    command = [
        qemu,
        "-machine",
        "q35",
        "-accel",
        "tcg,thread=multi",
        "-cpu",
        "max",
        "-smp",
        "2",
        "-m",
        os.environ.get("BUTOPIA_QEMU_MEMORY_MB", "4096"),
        "-boot",
        "order=d",
        "-cdrom",
        str(iso),
        "-vga",
        "std",
        "-display",
        "none",
        "-serial",
        "stdio",
        "-monitor",
        "none",
        "-netdev",
        "user,id=net0",
        "-device",
        "e1000,netdev=net0",
        "-no-reboot",
    ]
    if firmware == "uefi":
        command.extend(
            [
                "-drive",
                "if=pflash,format=raw,readonly=on,file=" + str(find_uefi_firmware()),
            ]
        )
    return command


def run_smoke(iso: Path, firmware: str, timeout: int, log_path: Path | None) -> None:
    command = qemu_command(iso, firmware)
    print(f"Booting Butopia through {firmware.upper()}...", flush=True)
    process = subprocess.Popen(
        command,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=0,
    )
    assert process.stdin is not None
    assert process.stdout is not None

    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + timeout
    output = bytearray()
    logged_in = False
    checks_sent = False

    test_command = (
        "printf 'SMOKE_BEGIN\\n'; "
        ". /etc/os-release; "
        "printf 'SMOKE_ID=%s\\n' \"$ID\"; "
        "printf 'SMOKE_ID_LIKE=%s\\n' \"$ID_LIKE\"; "
        "printf 'SMOKE_ARCH=%s\\n' \"$(uname -m)\"; "
        "apk info -e butopia-base >/dev/null && echo SMOKE_BASE_APK=ok; "
        "apk info -e butopia-desktop >/dev/null && echo SMOKE_DESKTOP_APK=ok; "
        "rc-service lightdm status >/dev/null && echo SMOKE_LIGHTDM=ok; "
        "pidof xfce4-session >/dev/null && echo SMOKE_XFCE=ok; "
        "echo SMOKE_OK; poweroff -f\n"
    ).encode()

    try:
        while time.monotonic() < deadline:
            if process.poll() is not None and not selector.select(timeout=0):
                break
            for key, _ in selector.select(timeout=0.25):
                chunk = os.read(key.fd, 4096)
                if not chunk:
                    continue
                output.extend(chunk)
                sys.stdout.buffer.write(chunk)
                sys.stdout.buffer.flush()

            text = output.decode(errors="replace")
            if not logged_in and "butopia login:" in text:
                process.stdin.write(b"root\n")
                process.stdin.flush()
                logged_in = True
            if logged_in and not checks_sent and "butopia:" in text and "#" in text:
                process.stdin.write(test_command)
                process.stdin.flush()
                checks_sent = True
            normalized = text.replace("\r", "")
            if all(marker in normalized for marker in REQUIRED_OUTPUT):
                break
        else:
            raise TimeoutError(f"Butopia did not finish its smoke test in {timeout}s")
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)

    text = output.decode(errors="replace").replace("\r", "")
    if log_path:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text(text)

    missing = [marker for marker in REQUIRED_OUTPUT if marker not in text]
    if missing:
        raise AssertionError("missing boot assertions: " + ", ".join(missing))

    print(f"\nButopia {firmware.upper()} GUI smoke test passed.")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--iso", required=True, type=Path)
    parser.add_argument("--firmware", choices=("bios", "uefi"), default="bios")
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument("--log", type=Path)
    args = parser.parse_args()

    iso = args.iso.resolve()
    if not iso.is_file():
        parser.error(f"ISO does not exist: {iso}")
    run_smoke(iso, args.firmware, args.timeout, args.log)


if __name__ == "__main__":
    main()
