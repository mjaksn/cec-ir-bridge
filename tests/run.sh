#!/usr/bin/env bash
# Every suite, and one exit status for the lot.
#
#   tests/run.sh              all of them
#   tests/run.sh dispatch     just the ones whose name matches
#
# Nothing here needs a CEC adapter, a Raspberry Pi, an ESP32 or the
# network: the engines are driven with recorded output, curl is a stub
# that writes to a file, and the installer runs into a temporary
# directory. It is safe to run on the machine you are reading this on.
set -uo pipefail

# The suites are found relative to this file, so a cd that failed would run
# whatever happened to match in the current directory instead of nothing.
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
filter="${1:-}"
failed=0
ran=0

for suite in *.test.sh; do
  case "$suite" in
    *"$filter"*) ;;
    *) continue ;;
  esac
  printf '\n== %s\n' "$suite"
  ran=$((ran + 1))
  bash "$suite" || failed=$((failed + 1))
done

if [ "$ran" -eq 0 ]; then
  echo "no suite matches '$filter'" >&2
  exit 2
fi
if [ "$failed" -ne 0 ]; then
  printf '%d of %d suites failed\n' "$failed" "$ran"
  exit 1
fi
printf 'all %d suites passed\n' "$ran"
