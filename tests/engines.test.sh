#!/usr/bin/env bash
# The two engines, driven with recorded output.
#
# Both parsers read stdin, so a fixture file is the whole of the test rig:
# no CEC adapter, no libcec, no v4l-utils, and nothing to install. The
# fixtures are what the real tools print, trimmed to the interesting lines.
set -uo pipefail
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

export PATH="$ROOT/tests/stubs:$PATH"
# shellcheck source=../bin/cec-ir-bridge
. "$ROOT/bin/cec-ir-bridge"

ESP32_BASE_URL="http://esp32.test"
POWER_OFF_PATH="/button/power_off/press"
POWER_ON_PATH="/button/power_on/press"

# through <parser> <fixture> -> the calls it produced
through() {
  CURL_LOG="$(mktemp)"
  export CURL_LOG
  # Called directly rather than through a pipe, so the backgrounded calls
  # belong to this shell and `wait` can be sure they have finished.
  "$1" < "$ROOT/tests/fixtures/$2" > /dev/null
  wait
  cat "$CURL_LOG"
  rm -f "$CURL_LOG"
}

echo "cec-client (libcec TRAFFIC frames)"

got="$(through parse_cec_client cec-client.log)"

contains "$got" "POST http://esp32.test/button/volume_up/press" \
  "45:44:41 from the Apple TV is a volume up"
contains "$got" "POST http://esp32.test/button/volume_down/press" \
  "45:44:42 is a volume down"
contains "$got" "POST http://esp32.test/button/power_off/press" \
  "0f:36 broadcast is a standby"
contains "$got" "POST http://esp32.test/button/power_on/press" \
  "0f:04 broadcast is a wake"

# The fixture holds two mutes: 45:44:43 from the Apple TV, which is real,
# and 05:44:43 from the TV, which is the rogue one the default filter
# exists to drop. Exactly one call should survive, and counting is what
# distinguishes that from both being dropped or from neither being.
is "$(printf '%s
' "$got" | grep -c 'button/mute/press')" "1" \
  "the TV's rogue mute is dropped and the Apple TV's is kept"

# Outgoing frames are the bridge's own, and reacting to them would have it
# answering itself.
lacks "$got" "Soundbar" "an outgoing << frame is not read as an event"

# b5:44:41 has initiator 11, which is a playback device and perfectly
# legitimate. It is here because 11 is the first initiator whose decimal
# form is two digits, and reading the nibble as decimal rather than hex
# would silently mistake it for something else.
is "$(printf '%s\n' "$got" | grep -c 'volume_up')" "2" \
  "a hex initiator nibble above 9 is decoded, not dropped"

# Two short lines that must not be mistaken for frames. Asserted through
# the call log rather than through stdout: the parser's own logging is
# discarded, so a substitution around it would be empty either way and the
# assertion could never fail.
CURL_LOG="$(mktemp)"
export CURL_LOG
# A here-string rather than a pipe, so the parser runs in this shell and the
# calls it backgrounds are ones `wait` can actually wait for.
#
# Both halves are asserted, and the stderr half is the one with teeth. A
# short frame fires nothing whether or not the length guard is there, since
# there are no operand bytes left to dispatch on. An empty one is different:
# without the guard the initiator nibble is read out of an empty string and
# $((16#)) is an arithmetic error, so the service starts logging failures on
# every truncated line libcec prints.
# Built with printf rather than written out, because the empty-frame line is
# ">> " and it is the trailing space that gets it past the first guard and
# into the arithmetic. An editor that trims trailing whitespace would
# otherwise quietly turn this back into a test of nothing.
short_err="$( { parse_cec_client > /dev/null; } 2>&1 \
  <<< "$(printf '>> 85\n>> \nDEBUG: nothing\n')" )"
wait
is "$(cat "$CURL_LOG")" "" "a frame too short to hold an opcode fires nothing"
is "$short_err" "" "and is skipped without an arithmetic error"
rm -f "$CURL_LOG"

echo "cec-ctl (kernel CEC monitor)"

got="$(through parse_cec_ctl cec-ctl.log)"

contains "$got" "POST http://esp32.test/button/volume_up/press" \
  "ui-cmd: volume-up is a volume up"
contains "$got" "POST http://esp32.test/button/volume_down/press" \
  "ui-cmd: volume-down is a volume down"
contains "$got" "POST http://esp32.test/button/power_off/press" \
  "STANDBY is a standby"
contains "$got" "POST http://esp32.test/button/power_on/press" \
  "IMAGE_VIEW_ON is a wake"

# The initiator comes off the header line, which arrives before the
# indented operand it applies to. The fixture has a mute from the TV and a
# mute from the Apple TV, in that order, so exactly one should survive the
# default filter, and getting the header tracking wrong gives zero or two.
is "$(printf '%s\n' "$got" | grep -c 'button/mute/press')" "1" \
  "the initiator is carried from the header to the operand line"

echo "the two engines agree"

# The point of having two backends is that they do the same thing. These
# are the same four events in each tool's own words.
CURL_LOG="$(mktemp)"; export CURL_LOG
parse_cec_client > /dev/null <<< "TRAFFIC: >> 45:44:41"
wait
a="$(cat "$CURL_LOG")"
: > "$CURL_LOG"
parse_cec_ctl > /dev/null <<'CTL'
Received from Playback Device 1 to Audio System (4 to 5): USER_CONTROL_PRESSED
	ui-cmd: volume-up
CTL
wait
b="$(cat "$CURL_LOG")"
rm -f "$CURL_LOG"
is "$a" "$b" "one volume up is the same call whichever engine saw it"

summary
