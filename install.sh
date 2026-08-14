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
# existing /etc/cec-ir-bridge.conf is left untouched.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "Please run with sudo." >&2
  exit 1
fi

echo "==> Installing packages (cec-utils, v4l-utils, curl)..."
apt-get update
apt-get install -y cec-utils v4l-utils curl

if [[ -f /etc/cec-ir-bridge.conf ]]; then
  echo "==> Keeping existing /etc/cec-ir-bridge.conf"
else
  ESP32_BASE_URL="${1:-}"
  if [[ -z "$ESP32_BASE_URL" ]]; then
    read -rp "ESP32 base URL (e.g. http://192.168.1.50): " ESP32_BASE_URL
  fi
  if [[ ! "$ESP32_BASE_URL" =~ ^https?:// ]]; then
    echo "ESP32 base URL must start with http:// or https://" >&2
    exit 1
  fi
  ESP32_BASE_URL="${ESP32_BASE_URL%/}"

  echo "==> Writing /etc/cec-ir-bridge.conf ..."
  sed "s|^ESP32_BASE_URL=.*|ESP32_BASE_URL=\"${ESP32_BASE_URL}\"|" \
    "${REPO_DIR}/cec-ir-bridge.conf.example" > /etc/cec-ir-bridge.conf
  chmod 644 /etc/cec-ir-bridge.conf
fi

echo "==> Installing /usr/local/bin/cec-ir-bridge ..."
install -m 755 "${REPO_DIR}/bin/cec-ir-bridge" /usr/local/bin/cec-ir-bridge

echo "==> Installing systemd unit ..."
install -m 644 "${REPO_DIR}/systemd/cec-ir-bridge.service" \
  /etc/systemd/system/cec-ir-bridge.service

echo "==> Enabling and starting service..."
systemctl daemon-reload
systemctl enable --now cec-ir-bridge.service
systemctl restart cec-ir-bridge.service

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
