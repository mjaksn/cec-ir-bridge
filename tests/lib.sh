# shellcheck shell=bash
#
# Sourced rather than run, so it has no shebang for ShellCheck to infer the
# shell from, and the directive above says it instead.
#
# Assertions, and nothing more. This project has no dependencies, and a
# test framework would be the first one, so the suites are plain bash and
# this is the whole of the machinery they share.
#
# Each suite sources this, runs its cases, and ends with `summary`, whose
# exit status is what tests/run.sh collects.

CASES=0
FAILURES=0

pass() {
  CASES=$((CASES + 1))
  printf '  ok    %s\n' "$1"
}

fail() {
  CASES=$((CASES + 1))
  FAILURES=$((FAILURES + 1))
  printf '  FAIL  %s\n' "$1"
  [ $# -gt 1 ] && printf '%s\n' "$2" | sed 's/^/          /'
  return 0
}

# is <got> <want> <name>
is() {
  if [ "$1" = "$2" ]; then
    pass "$3"
  else
    fail "$3" "got:    $1
wanted: $2"
  fi
}

# contains <haystack> <needle> <name>
contains() {
  case "$1" in
    *"$2"*) pass "$3" ;;
    *) fail "$3" "wanted to find: $2
in:             $1" ;;
  esac
}

# lacks <haystack> <needle> <name>
lacks() {
  case "$1" in
    *"$2"*) fail "$3" "did not want to find: $2
in:                   $1" ;;
    *) pass "$3" ;;
  esac
}

summary() {
  if [ "$FAILURES" -eq 0 ]; then
    printf '  %d passed\n\n' "$CASES"
    return 0
  fi
  printf '  %d of %d failed\n\n' "$FAILURES" "$CASES"
  return 1
}

# The repository root, whichever directory a suite was started from. Used by
# the suites that source this rather than here, hence the directive.
# shellcheck disable=SC2034
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
