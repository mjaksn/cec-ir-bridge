#!/usr/bin/env bash
# Build the release tarball.
#
#   scripts/build.sh            writes dist/cec-ir-bridge.tar.gz
#
# The version comes out of bin/cec-ir-bridge, which is the one place it is
# written down. It names the directory inside the archive but deliberately
# not the archive itself: an asset whose name never changes is what makes
# the /releases/latest/download/ URL in README.md work, and that URL is
# what keeps a version number out of the install instructions: they cd
# into the versioned directory the archive unpacks into instead.
#
# The file list below is the whole of what a release contains: the
# bridge, the installer, the unit, the example config and the prose.
# Tests, fixtures and workflows are deliberately not in it, since
# nothing on a Raspberry Pi has any use for them.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(grep -m1 '^VERSION=' bin/cec-ir-bridge | sed 's/^VERSION="\(.*\)"$/\1/')"
[ -n "$VERSION" ] || { echo "no VERSION in bin/cec-ir-bridge" >&2; exit 1; }

NAME="cec-ir-bridge-$VERSION"
FILES=(
  bin/cec-ir-bridge
  install.sh
  cec-ir-bridge.conf.example
  systemd/cec-ir-bridge.service
  README.md
  CHANGELOG.md
  LICENSE
)

# Staged into a directory and tarred from there, rather than tarred with a
# transform, because the transform flag is GNU tar's and this should build
# the same archive on a machine with BSD tar.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/$NAME"

for file in "${FILES[@]}"; do
  [ -f "$file" ] || { echo "missing from the release: $file" >&2; exit 1; }
  mkdir -p "$STAGE/$NAME/$(dirname "$file")"
  cp "$file" "$STAGE/$NAME/$file"
done

# The modes matter: an installer that arrives without its execute bit is a
# confusing first five minutes for whoever downloaded it.
chmod 755 "$STAGE/$NAME/install.sh" "$STAGE/$NAME/bin/cec-ir-bridge"

mkdir -p dist
rm -f dist/cec-ir-bridge.tar.gz
tar -czf dist/cec-ir-bridge.tar.gz -C "$STAGE" "$NAME"

echo "dist/cec-ir-bridge.tar.gz holds $NAME"
