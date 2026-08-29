#!/usr/bin/env bash
# The defaults are written down twice, so this checks they agree.
#
# bin/cec-ir-bridge names every setting with the value it takes when the
# config says nothing, and cec-ir-bridge.conf.example ships those same
# values as the file an operator edits. Two copies of one fact drift, and
# the way they drift is that somebody adds a setting to one of them. This
# fails the pull request that did it rather than leaving a bridge whose
# documented default is not its actual one.
set -uo pipefail
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BRIDGE="$ROOT/bin/cec-ir-bridge"
EXAMPLE="$ROOT/cec-ir-bridge.conf.example"

echo "the example config"

is "$(bash -n "$EXAMPLE" 2>&1 && echo ok)" "ok" "it is valid shell, which is how it is read"

# Read the settings out of each file. In the script they are the block of
# assignments from ESP32_BASE_URL to usage(), which leaves VERSION and
# CONF_FILE out because neither is a setting an operator writes down. In
# the example they are every assignment there is.
script_settings() {
  sed -n '/^ESP32_BASE_URL=/,/^usage()/p' "$BRIDGE" | settings
}
example_settings() {
  settings < "$EXAMPLE"
}
settings() {
  grep -E '^[A-Z][A-Z0-9_]*=' | sed 's/=.*//' | sort
}

is "$(script_settings)" "$(example_settings)" \
  "both files name exactly the same settings"

echo "the values agree"

# Source each in its own shell and compare, which catches a default that
# was changed in one place. ESP32_BASE_URL is the exception: the script
# has nothing sensible to default it to and the example carries a worked
# address for somebody to replace, so those two are meant to differ.
values_from() {
  (
    set -u
    # shellcheck source=/dev/null
    . "$1" > /dev/null 2>&1
    for name in $(example_settings); do
      [ "$name" = "ESP32_BASE_URL" ] && continue
      printf '%s=%s\n' "$name" "${!name}"
    done
  )
}

# The script defines its defaults at the top level, so sourcing it is
# enough to read them: main() is not called on a source.
is "$(values_from "$BRIDGE")" "$(values_from "$EXAMPLE")" \
  "every default in the script is the value the example ships"

echo "the version"

version="$(grep -m1 '^VERSION=' "$BRIDGE" | sed 's/^VERSION="\(.*\)"$/\1/')"
case "$version" in
  [0-9]*.[0-9]*.[0-9]*) pass "VERSION is a semantic version ($version)" ;;
  *) fail "VERSION is a semantic version" "got: $version" ;;
esac
is "$("$BRIDGE" --version)" "cec-ir-bridge $version" "--version reports it"

# The release workflow lifts notes out of CHANGELOG.md by version, and a
# tag with no section there fails the release. Cheaper to notice here.
contains "$(cat "$ROOT/CHANGELOG.md")" "## [$version]" \
  "CHANGELOG.md has a section for it"

echo "the usage text"

# Prose the program emits is documentation and rots the same way, so the
# claims in it that can be checked, are.
help="$("$BRIDGE" --help)"
contains "$help" "/etc/cec-ir-bridge.conf" "--help names the config file it reads"
contains "$help" "$version" "--help carries the version"
is "$("$BRIDGE" --nonsense 2>/dev/null; echo $?)" "2" \
  "an unknown option is refused rather than started with"

summary
