#!/usr/bin/env bash
#
# install.sh
#
# Installs cec-ir-bridge on Raspberry Pi OS Lite (Trixie, also works on
# Bookworm). Run from the root of this repository:
#
#   sudo ./install.sh http://<esp32-ip-or-hostname>
#
# The ESP32 URL argument is optional; you will be prompted if omitted.
# Re-running is safe: scripts and the systemd unit are refreshed, but an
# existing config file keeps every value it already had. Settings added
# to the example since the last run are appended, with their comments.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# A staged install, in the usual `make install DESTDIR=...` sense: every
# path below hangs off it. Empty, which is the normal case, means the
# real system paths. The test suite sets it to a throwaway directory,
# which is also how the installer can be exercised without root.
DESTDIR="${DESTDIR:-}"
CONF_FILE="${DESTDIR}/etc/cec-ir-bridge.conf"
BIN_FILE="${DESTDIR}/usr/local/bin/cec-ir-bridge"
UNIT_FILE="${DESTDIR}/etc/systemd/system/cec-ir-bridge.service"

# Root owns those paths, so it is needed for a real install and not for a
# staged one.
if [[ -z "$DESTDIR" && $EUID -ne 0 ]]; then
  echo "Please run with sudo." >&2
  exit 1
fi

# Print the settings that are in the example config but not yet in an
# installed one, each with the comment block that explains it. Existing
# values are never read for anything but their names, so nothing the
# operator has set can be changed by this.
merge_new_settings() {
  local example="$1" existing="$2"
  awk -v conffile="$existing" '
    BEGIN {
      while ((getline line < conffile) > 0) {
        if (match(line, /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=/)) {
          key = line; sub(/=.*/, "", key); gsub(/[[:space:]]/, "", key)
          have[key] = 1
        }
      }
    }
    /^[[:space:]]*#/ { comments = comments $0 "\n"; next }
    /^[[:space:]]*$/ { comments = ""; next }
    /^[A-Za-z_][A-Za-z0-9_]*=/ {
      key = $0; sub(/=.*/, "", key)
      if (!(key in have)) { printf "\n%s%s\n", comments, $0; print key > "/dev/stderr" }
      comments = ""
      next
    }
    { comments = "" }
  ' "$example"
}

install_packages() {
  echo "==> Installing packages (cec-utils, v4l-utils, curl)..."
  apt-get update
  apt-get install -y cec-utils v4l-utils curl
}

write_config() {
  if [[ -f "$CONF_FILE" ]]; then
    echo "==> Existing $CONF_FILE found, checking for new settings..."
    local added
    added="$(merge_new_settings "${REPO_DIR}/cec-ir-bridge.conf.example" "$CONF_FILE" \
      2> >(sed "s/^/    added: /" >&2))"
    if [[ -n "$added" ]]; then
      printf '%s\n' "$added" >> "$CONF_FILE"
      echo "    (existing values were left unchanged)"
    else
      echo "    No new settings; config is up to date."
    fi
    return 0
  fi

  local url="${1:-}"
  if [[ -z "$url" ]]; then
    read -rp "ESP32 base URL (e.g. http://192.168.1.50): " url
  fi
  if [[ ! "$url" =~ ^https?:// ]]; then
    echo "ESP32 base URL must start with http:// or https://" >&2
    exit 1
  fi
  url="${url%/}"

  echo "==> Writing $CONF_FILE ..."
  mkdir -p "$(dirname "$CONF_FILE")"
  sed "s|^ESP32_BASE_URL=.*|ESP32_BASE_URL=\"${url}\"|" \
    "${REPO_DIR}/cec-ir-bridge.conf.example" > "$CONF_FILE"
  chmod 644 "$CONF_FILE"
}

install_files() {
  echo "==> Installing $BIN_FILE ..."
  mkdir -p "$(dirname "$BIN_FILE")"
  install -m 755 "${REPO_DIR}/bin/cec-ir-bridge" "$BIN_FILE"

  echo "==> Installing systemd unit ..."
  mkdir -p "$(dirname "$UNIT_FILE")"
  install -m 644 "${REPO_DIR}/systemd/cec-ir-bridge.service" "$UNIT_FILE"
}

start_service() {
  echo "==> Enabling and starting service..."
  systemctl daemon-reload
  systemctl enable --now cec-ir-bridge.service
  systemctl restart cec-ir-bridge.service
}

next_steps() {
  echo
  echo "Done. Useful commands:"
  echo "  journalctl -u cec-ir-bridge -f     # watch CEC events live"
  echo "  sudo systemctl restart cec-ir-bridge"
  echo "  sudo nano /etc/cec-ir-bridge.conf  # endpoints, engine, power options"
  echo
  echo "Next steps on the Apple TV:"
  echo "  Settings -> Remotes and Devices -> Volume Control -> Auto"
  echo "  (Toggle it or restart the Apple TV once so it re-scans the CEC bus.)"
  echo
  echo "If cec-client cannot find the adapter on your image, set"
  echo "ENGINE=\"cec-ctl\" in /etc/cec-ir-bridge.conf and restart the service."
}

main() {
  install_packages
  write_config "${1:-}"
  install_files
  start_service
  next_steps
}

# Executed, this installs. Sourced, as the test suite does, it defines the
# functions above and stops, so merge_new_settings can be driven directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
