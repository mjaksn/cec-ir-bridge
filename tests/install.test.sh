#!/usr/bin/env bash
# install.sh, run end to end into a throwaway directory.
#
# DESTDIR is what makes this possible: every path the installer writes
# hangs off it, so nothing here needs root and nothing touches /etc. apt-get
# and systemctl are stubs on PATH, because a test has no business installing
# Debian packages or enabling a unit on the machine running it.
#
# The interesting part is the second run. Re-installing must refresh the
# bridge and the unit and leave every value in an existing config exactly
# as the operator left it, while picking up settings the example has gained
# since. That merge is the least obvious code in the repository.
#
# The boot config.txt gets the same treatment on a smaller scale: the
# installer adds hdmi_ignore_cec=1 once, and never touches a line the
# operator already wrote.
set -uo pipefail
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

export PATH="$ROOT/tests/stubs:$PATH"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
CONF="$STAGE/etc/cec-ir-bridge.conf"
BOOT="$STAGE/boot/firmware/config.txt"

# A config.txt shaped like the stock one, ending inside a model section so
# that a line appended without its own [all] header would land in [cm4].
mkdir -p "$(dirname "$BOOT")"
printf '%s\n' "dtparam=audio=on" "dtoverlay=vc4-kms-v3d" "" "[cm4]" "otg_mode=1" > "$BOOT"
boot_before="$(cat "$BOOT")"

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

is "$(grep -c '^hdmi_ignore_cec=1$' "$BOOT")" "1" \
  "it adds hdmi_ignore_cec=1 to the boot config"
is "$(grep -B1 '^hdmi_ignore_cec=' "$BOOT" | head -1)" "[all]" \
  "under its own [all] header, not whatever section the file ended in"
is "$(head -c "${#boot_before}" "$BOOT")" "$boot_before" \
  "and rewrites nothing that was already in config.txt"
contains "$(cat "$STAGE/out.log")" "Reboot once for hdmi_ignore_cec=1" \
  "the summary says a reboot is needed"

echo "a second install, over the first"

# An operator's edits, of the two kinds that matter: a changed value and a
# whole setting removed as though the config predated it.
sed -i 's|^OSD_NAME=.*|OSD_NAME="Living Room Bar"|' "$CONF"
sed -i '/^POWER_ON_PATH=/d' "$CONF"
# POWER_ON_PATH shares its comment with POWER_OFF_PATH, which stays. The
# comment goes too, so that finding it after the merge means the merge put
# it there, and not that it survived from the first install.
sed -i '/^# Optional: fire soundbar power IR/,/^POWER_OFF_PATH=/{/^#/d}' "$CONF"
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
is "$(grep -c '^hdmi_ignore_cec=' "$BOOT")" "1" \
  "nor is hdmi_ignore_cec"
lacks "$(cat "$STAGE/out.log")" "Reboot once" \
  "and with nothing changed in config.txt, no reboot is asked for"

echo "the boot config, in the other shapes it comes in"

# Each case gets its own stage with a config already in place, so it is a
# re-install as far as the URL is concerned and only config.txt varies.
boot_case() {
  local stage
  stage="$(mktemp -d)"
  mkdir -p "$stage/etc"
  cp "$CONF" "$stage/etc/cec-ir-bridge.conf"
  printf '%s' "$stage"
}

# install_into <stage>, with the output kept in the stage for inspection.
install_into() {
  ( cd "$ROOT" && DESTDIR="$1" STUB_LOG=/dev/null ./install.sh ) > "$1/out.log" 2>&1
}

OWN="$(boot_case)"
mkdir -p "$OWN/boot/firmware"
printf '%s\n' "dtoverlay=vc4-kms-v3d" "hdmi_ignore_cec=0" > "$OWN/boot/firmware/config.txt"
own_before="$(cat "$OWN/boot/firmware/config.txt")"
install_into "$OWN" || fail "an operator's own setting does not stop the install" "$(cat "$OWN/out.log")"
is "$(cat "$OWN/boot/firmware/config.txt")" "$own_before" \
  "an operator's hdmi_ignore_cec=0 is left exactly as it was"
contains "$(cat "$OWN/out.log")" "already set" "and the installer says why it did nothing"
rm -rf "$OWN"

# The narrower setting is the one people find first, and it is not enough:
# it keeps the firmware from claiming the input but leaves it on the bus.
INIT="$(boot_case)"
mkdir -p "$INIT/boot/firmware"
printf '%s\n' "hdmi_ignore_cec_init=1" > "$INIT/boot/firmware/config.txt"
install_into "$INIT" || fail "a config.txt with only the init setting installs" "$(cat "$INIT/out.log")"
is "$(grep -c '^hdmi_ignore_cec=1$' "$INIT/boot/firmware/config.txt")" "1" \
  "an existing hdmi_ignore_cec_init=1 does not count as hdmi_ignore_cec"
contains "$(cat "$INIT/boot/firmware/config.txt")" "hdmi_ignore_cec_init=1" \
  "and is left in place"
rm -rf "$INIT"

LEGACY="$(boot_case)"
mkdir -p "$LEGACY/boot"
printf '%s\n' "dtparam=audio=on" > "$LEGACY/boot/config.txt"
install_into "$LEGACY" || fail "an image with only /boot/config.txt installs" "$(cat "$LEGACY/out.log")"
is "$(grep -c '^hdmi_ignore_cec=1$' "$LEGACY/boot/config.txt")" "1" \
  "on an image older than Bookworm, /boot/config.txt is the one written"
rm -rf "$LEGACY"

MOVED="$(boot_case)"
mkdir -p "$MOVED/boot/firmware"
printf '%s\n' "dtparam=audio=on" > "$MOVED/boot/firmware/config.txt"
printf '%s\n' "DO NOT EDIT THIS FILE" > "$MOVED/boot/config.txt"
install_into "$MOVED" || fail "an image with both paths installs" "$(cat "$MOVED/out.log")"
is "$(grep -c '^hdmi_ignore_cec=1$' "$MOVED/boot/firmware/config.txt")" "1" \
  "with both present, /boot/firmware/config.txt wins"
is "$(cat "$MOVED/boot/config.txt")" "DO NOT EDIT THIS FILE" \
  "and the stub Bookworm leaves at the old path is not written to"
rm -rf "$MOVED"

NONE="$(boot_case)"
install_into "$NONE"
status=$?
is "$status" "0" "with no config.txt at all, as on a CI runner, the install still succeeds"
contains "$(cat "$NONE/out.log")" "skipping hdmi_ignore_cec" "and says it skipped the step"
lacks "$(cat "$NONE/out.log")" "Reboot once" "and asks for no reboot"
rm -rf "$NONE"

echo "refusals"

is "$( ( cd "$ROOT" && DESTDIR="$STAGE" ./install.sh "ftp://nope" ) > /dev/null 2>&1; echo $?)" "0" \
  "a bad URL is not reached on a re-install, which never reads the argument"

FRESH="$(mktemp -d)"
is "$( ( cd "$ROOT" && DESTDIR="$FRESH" STUB_LOG=/dev/null ./install.sh "ftp://nope" ) > /dev/null 2>&1; echo $?)" "1" \
  "on a first install a URL with no http scheme is refused"
rm -rf "$FRESH"

# The mistake that prompted the check's position: an address typed without
# its scheme. It used to be caught after apt had run, leaving the packages
# installed and nothing else, with the error lost in apt's output.
FRESH="$(mktemp -d)"
( cd "$ROOT" && DESTDIR="$FRESH" STUB_LOG="$FRESH/stubs.log" ./install.sh "192.168.1.50" ) \
  > "$FRESH/out.log" 2>&1
status=$?
is "$status" "1" "a bare address with no http:// is refused"
lacks "$(cat "$FRESH/stubs.log" 2>/dev/null)" "apt-get" \
  "before apt-get runs"
is "$(find "$FRESH" -path "$FRESH/etc/*" -o -path "$FRESH/usr/*" | head -1)" "" \
  "and before anything is written"
contains "$(cat "$FRESH/out.log")" "Nothing has been installed" \
  "and the error says so"
rm -rf "$FRESH"

summary
