#!/usr/bin/env bash
# What each CEC opcode does, and who is allowed to send it.
#
# The bridge is sourced rather than run, so dispatch() can be called with
# a frame directly. curl is a stub on PATH that records the URL and the
# method instead of fetching anything, so no request leaves the machine
# and no ESP32 is involved.
set -uo pipefail
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

export PATH="$ROOT/tests/stubs:$PATH"

# Sourcing runs nothing: bin/cec-ir-bridge only calls main when executed.
# shellcheck source=../bin/cec-ir-bridge
. "$ROOT/bin/cec-ir-bridge"

ESP32_BASE_URL="http://esp32.test"

# fired <initiator> <payload> -> the calls it produced, one per line
fired() {
  CURL_LOG="$(mktemp)"
  export CURL_LOG
  # The event log goes to the journal in real life, and is asserted
  # separately below; here only the calls that resulted are of interest.
  dispatch "$1" "$2" >/dev/null
  # fire() backgrounds curl so a held button does not queue latency, so
  # the calls have to be waited for before the log is read.
  wait
  cat "$CURL_LOG"
  rm -f "$CURL_LOG"
}

echo "dispatch"

# The three volume commands, from a playback device, which is the Apple TV.
is "$(fired 4 44:41)" "POST http://esp32.test/button/volume_up/press" \
  "volume up from the Apple TV fires the volume up endpoint"
is "$(fired 4 44:42)" "POST http://esp32.test/button/volume_down/press" \
  "volume down from the Apple TV fires the volume down endpoint"
is "$(fired 4 44:43)" "POST http://esp32.test/button/mute/press" \
  "mute from the Apple TV fires the mute endpoint"

# The method is the whole point of the assertions above carrying one.
# ESPHome answers 405 to a GET on /button/<id>/press, so a change that
# dropped -X POST would leave every press silently failing.
contains "$(fired 4 44:41)" "POST " "the call is a POST, which ESPHome requires"

# Mute from the TV is the rogue-mute case: some TVs emit one on power off
# and never send the matching unmute, which leaves an IR soundbar stuck
# muted. MUTE_IGNORE_INITIATORS defaults to 0 for exactly this.
is "$(fired 0 44:43)" "" "mute from the TV is ignored by default"
is "$(fired 0 44:41)" "POST http://esp32.test/button/volume_up/press" \
  "volume from the TV is not caught by the mute filter"

# Power is opt-in: both paths are empty until somebody sets them.
is "$(fired 0 36)" "" "standby fires nothing while POWER_OFF_PATH is empty"
is "$(fired 0 04)" "" "wake fires nothing while POWER_ON_PATH is empty"

POWER_OFF_PATH="/button/power/press"
POWER_ON_PATH="/button/power/press"
is "$(fired 0 36)" "POST http://esp32.test/button/power/press" \
  "standby fires the power endpoint once it is set"
is "$(fired 0 04)" "POST http://esp32.test/button/power/press" \
  "Image View On is a wake"
is "$(fired 0 0d)" "POST http://esp32.test/button/power/press" \
  "Text View On is a wake too"
POWER_OFF_PATH=""
POWER_ON_PATH=""

# Anything the bridge has no opinion about.
is "$(fired 4 85)" "" "an unhandled opcode fires nothing"
is "$(fired 4 44:44)" "" "an unhandled user control key fires nothing"

echo "filtering"

# A list, rather than the single value the default carries.
VOLUME_IGNORE_INITIATORS="0,8"
is "$(fired 8 44:41)" "" "an initiator in a comma separated list is ignored"
is "$(fired 0 44:41)" "" "so is the other one"
is "$(fired 4 44:41)" "POST http://esp32.test/button/volume_up/press" \
  "an initiator not in the list still fires"

VOLUME_IGNORE_INITIATORS="0 8"
is "$(fired 8 44:41)" "" "the list may be space separated instead"

VOLUME_IGNORE_INITIATORS=""
is "$(fired 0 44:41)" "POST http://esp32.test/button/volume_up/press" \
  "an empty list ignores nobody"

# Substrings must not match: initiator 1 is not initiator 11.
VOLUME_IGNORE_INITIATORS="11"
is "$(fired 1 44:41)" "POST http://esp32.test/button/volume_up/press" \
  "ignoring 11 does not also ignore 1"
is "$(fired 11 44:41)" "" "ignoring 11 ignores 11"
VOLUME_IGNORE_INITIATORS=""

echo "logging"

# An ignored command is still logged. The README promises this, on the
# grounds that filtering should never hide bus activity from the operator.
#
# The log is what is under test here rather than the calls, but the stub
# still needs somewhere to write, so CURL_LOG is set for the whole section
# rather than per assertion. A `CURL_LOG=x contains "$(dispatch ...)"`
# prefix would come too late: the command substitution runs first, and the
# assignment would never be seen by the thing it was meant for.
CURL_LOG="$(mktemp)"
export CURL_LOG

contains "$(dispatch 0 44:43 2>&1)" "ignored" \
  "an ignored command says so on stdout"
contains "$(dispatch 4 44:41 2>&1)" "esp32.test" \
  "a fired command logs the URL it called"

wait
rm -f "$CURL_LOG"

summary
