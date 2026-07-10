#!/usr/bin/env python3
"""Fast, host-portable consistency checks for the Butopia source tree."""

from __future__ import annotations

import re
import hashlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        key, separator, value = line.partition("=")
        if not separator or not re.fullmatch(r"[A-Z][A-Z0-9_]*", key):
            raise AssertionError(f"invalid lock-file line: {raw_line!r}")
        values[key] = value
    return values


def main() -> None:
    version = (ROOT / "VERSION").read_text().strip()
    pins = read_env(ROOT / "locks" / "sources.env")
    assert version == pins["BUTOPIA_VERSION"], "VERSION and sources.env differ"
    assert re.fullmatch(r"\d+\.\d+\.\d+", version), "VERSION is not semantic"
    assert re.fullmatch(r"[0-9a-f]{40}", pins["APORTS_COMMIT"])
    assert re.fullmatch(r"[0-9a-f]{128}", pins["BUILDER_IMAGE_SHA512"])

    source_text = "\n".join(
        path.read_text(errors="replace")
        for path in (ROOT / "distro").rglob("*")
        if path.is_file()
    )
    for required in (
        "profile_butopia",
        "butopia-base",
        "butopia-desktop",
        "butopia-installer",
        "BUTOPIA_BOOT_OK",
        "BUTOPIA_GUI_READY",
        "ID=butopia",
        "ID_LIKE=alpine",
    ):
        assert required in source_text, f"missing distro invariant: {required}"

    private_keys = list(ROOT.rglob("*.rsa"))
    assert not private_keys, f"private signing key must not be committed: {private_keys}"

    relative_files = [
        str(path.relative_to(ROOT))
        for path in ROOT.rglob("*")
        if path.is_file() and ".git" not in path.parts
    ]
    folded: dict[str, str] = {}
    for relative_file in relative_files:
        key = relative_file.casefold()
        assert key not in folded, (
            "case-insensitive path collision: "
            f"{folded.get(key)!r} and {relative_file!r}"
        )
        folded[key] = relative_file

    for apkbuild in (ROOT / "distro" / "packages").glob("*/APKBUILD"):
        text = apkbuild.read_text()
        source_match = re.search(r'(?ms)^source="(.*?)"', text)
        sums_match = re.search(r'(?ms)^sha512sums="(.*?)"', text)
        assert source_match and sums_match, f"missing sources or hashes in {apkbuild}"
        sources = source_match.group(1).split()
        sums: dict[str, str] = {}
        for line in sums_match.group(1).strip().splitlines():
            digest, filename = line.split(None, 1)
            sums[filename.strip()] = digest
        assert set(sources) == set(sums), f"source/hash list mismatch in {apkbuild}"
        for filename in sources:
            digest = hashlib.sha512((apkbuild.parent / filename).read_bytes()).hexdigest()
            assert digest == sums[filename], f"stale hash for {apkbuild.parent.name}/{filename}"

    print(f"Butopia {version} source invariants passed.")


if __name__ == "__main__":
    main()
