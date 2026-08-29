#!/usr/bin/env bash
# install.sh, run end to end into a throwaway directory.
#
# DESTDIR is what makes this possible: every path the installer writes
# hangs off it, so nothing here needs root and nothing touches /etc. apt-get
# and systemctl are stubs on PATH, because a test has no business installing
# Debian packages or enabling a unit on the machine running it.
#
# The interesting part is the second run. Re-installing must refresh the
# scripts and leave every value in an existing config exactly as the
# operator left it, while picking up settings the example has gained since.
# That merge is the least obvious code in the repository.
set -uo pipefail
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

export PATH="$ROOT/tests/stubs:$PATH"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
CONF="$STAGE/etc/cec-ir-bridge.conf"

run_installer() {
  ( cd "$ROOT" && DESTDIR="$STAGE" STUB_LOG="$STAGE/stubs.log" \
      ./install.sh "$@" ) > "$STAGE/out.log" 2>&1
}

echo "a first install"

run_installer "http://192.168.1.99/" || fail "the installer exits cleanly" "$(cat "$STAGE/out.log")"

is "$([ -f "$CONF" ] && echo yes)" "yes" "it writes the config"
is "$([ -x "$STAGE/usr/local/bin/cec-ir-bridge" ] && echo yes)" "yes" \
  "it installs the bridge, executable"
is "$([ -f "$STAGE/etc/systemd/system/cec-ir-bridge.service" ] && echo yes)" "yes" \
  "it installs the systemd unit"

contains "$(cat "$CONF")" 'ESP32_BASE_URL="http://192.168.1.99"' \
  "the URL from the command line goes in, with the trailing slash trimmed"
lacks "$(cat "$CONF")" "192.168.1.50" "the example address does not survive"

contains "$(cat "$STAGE/stubs.log")" "apt-get install" "it installs the packages"
contains "$(cat "$STAGE/stubs.log")" "systemctl enable" "it enables the service"

# The installed config must be loadable by the thing that loads it, which
# is the check that catches a sed that mangled the file.
is "$(bash -n "$CONF" 2>&1 && echo ok)" "ok" "the config it wrote is valid shell"

echo "a second install, over the first"

# An operator's edits, of the two kinds that matter: a changed value and a
# whole setting removed as though the config predated it.
sed -i 's|^OSD_NAME=.*|OSD_NAME="Living Room Bar"|' "$CONF"
sed -i '/^POWER_ON_PATH=/d' "$CONF"
sed -i 's|^MUTE_IGNORE_INITIATORS=.*|MUTE_IGNORE_INITIATORS="0,4"|' "$CONF"
before="$(cat "$CONF")"

run_installer "http://192.168.1.1" || fail "re-installing exits cleanly" "$(cat "$STAGE/out.log")"

contains "$(cat "$CONF")" 'OSD_NAME="Living Room Bar"' \
  "a changed value is left alone"
contains "$(cat "$CONF")" 'MUTE_IGNORE_INITIATORS="0,4"' \
  "so is a changed filter list"
lacks "$(cat "$CONF")" 'ESP32_BASE_URL="http://192.168.1.1"' \
  "the URL argument does not overwrite the configured one"
contains "$(cat "$CONF")" 'POWER_ON_PATH=' \
  "the missing setting is added back"
contains "$(cat "$CONF")" "Optional: fire soundbar power IR" \
  "and its explanatory comment comes with it"
contains "$(cat "$STAGE/out.log")" "added: POWER_ON_PATH" \
  "the installer says which setting it added"
is "$(bash -n "$CONF" 2>&1 && echo ok)" "ok" "the merged config is still valid shell"

# Everything that was there before must still be there, byte for byte. The
# merge only ever appends, so the old content is a prefix of the new.
is "$(head -c "${#before}" "$CONF")" "$before" \
  "nothing already in the file was rewritten"

echo "a third install, with nothing to add"

run_installer "http://192.168.1.1" || fail "a third run exits cleanly" "$(cat "$STAGE/out.log")"
contains "$(cat "$STAGE/out.log")" "No new settings" \
  "it says so rather than appending a blank line every time"
is "$(grep -c '^POWER_ON_PATH=' "$CONF")" "1" \
  "and the setting it added last time is not added twice"

echo "refusals"

is "$( ( cd "$ROOT" && DESTDIR="$STAGE" ./install.sh "ftp://nope" ) > /dev/null 2>&1; echo $?)" "0" \
  "a bad URL is not reached on a re-install, which never reads the argument"

FRESH="$(mktemp -d)"
is "$( ( cd "$ROOT" && DESTDIR="$FRESH" STUB_LOG=/dev/null ./install.sh "ftp://nope" ) > /dev/null 2>&1; echo $?)" "1" \
  "on a first install a URL with no http scheme is refused"
rm -rf "$FRESH"

summary
