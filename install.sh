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
# On a Pi it also adds hdmi_ignore_cec_init=1 to the boot config.txt,
# unless that file already sets it, so that rebooting the Pi does not
# switch the TV to its input.
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

BOOT_CONFIG_CHANGED=""

# At power on, the Pi's boot firmware announces itself on CEC as the active
# source, before Linux or the bridge are running, and a TV obeys by
# switching to the Pi's input. hdmi_ignore_cec_init=1 stops that one
# message and leaves CEC working for the bridge. A line the operator has
# already written is left alone whatever its value, so =0 is the way to
# keep the switching, and it survives a re-run.
write_boot_config() {
  # Bookworm moved the file and left a stub at the old path saying so, so
  # the new location has to be tried first.
  local boot_config=""
  if [[ -f "${DESTDIR}/boot/firmware/config.txt" ]]; then
    boot_config="${DESTDIR}/boot/firmware/config.txt"
  elif [[ -f "${DESTDIR}/boot/config.txt" ]]; then
    boot_config="${DESTDIR}/boot/config.txt"
  else
    echo "==> No config.txt in /boot/firmware or /boot, so not a Raspberry Pi; skipping hdmi_ignore_cec_init."
    return 0
  fi

  if grep -q '^[[:space:]]*hdmi_ignore_cec_init=' "$boot_config"; then
    echo "==> hdmi_ignore_cec_init is already set in ${boot_config#"$DESTDIR"}; leaving it as it is."
    return 0
  fi

  echo "==> Adding hdmi_ignore_cec_init=1 to ${boot_config#"$DESTDIR"} ..."
  # The [all] header is there because a hand-edited file can end inside a
  # [pi4] or [cm4] section, which would quietly scope the line to one model.
  printf '\n%s\n%s\n%s\n' \
    "# Added by cec-ir-bridge: stop the boot firmware switching the TV to this input." \
    "[all]" \
    "hdmi_ignore_cec_init=1" >> "$boot_config"
  BOOT_CONFIG_CHANGED=1
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
  if [[ -n "$BOOT_CONFIG_CHANGED" ]]; then
    echo
    echo "Reboot once for hdmi_ignore_cec_init=1 to take effect. After that the"
    echo "Pi no longer switches the TV to its input while it boots. A TV that"
    echo "still switches is following the HDMI signal by itself; look for an"
    echo "automatic input switching setting on the TV. To keep the old behaviour,"
    echo "change the line to hdmi_ignore_cec_init=0; re-installing leaves it alone."
  fi
}

main() {
  install_packages
  write_config "${1:-}"
  install_files
  write_boot_config
  start_service
  next_steps
}

# Executed, this installs. Sourced, as the test suite does, it defines the
# functions above and stops, so merge_new_settings can be driven directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
