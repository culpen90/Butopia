#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

find scripts builder distro -type f \( -name '*.sh' -o -name 'APKBUILD' \) \
  -exec sh -n {} \;

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile \
  tools/check_project.py \
  tests/smoke_boot.py
python3 tools/check_project.py

if git rev-parse --git-dir >/dev/null 2>&1; then
  git diff --check
fi

printf 'Butopia repository checks passed.\n'
