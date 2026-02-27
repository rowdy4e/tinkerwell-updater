#!/bin/bash

# Tinkerwell Updater - Install Script
# Usage: sudo ./install.sh

set -euo pipefail

INSTALL_DIR="/usr/local/bin"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CURRENT_USER="${SUDO_USER:-$(whoami)}"

echo "=== Tinkerwell Updater - Installer ==="

[[ "$EUID" -ne 0 ]] && { echo "Run with sudo: sudo ./install.sh"; exit 1; }

echo "[1/3] Installing script..."
cp "$SCRIPT_DIR/update-tinkerwell.sh" "$INSTALL_DIR/update-tinkerwell"
chmod +x "$INSTALL_DIR/update-tinkerwell"
echo "      ✓ Installed to $INSTALL_DIR/update-tinkerwell"

echo "[2/3] Configuring passwordless sudo for user: $CURRENT_USER..."
cat > /etc/sudoers.d/tinkerwell-updater << EOF
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/mv /opt/Tinkerwell /opt/Tinkerwell.backup-*
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/mv /opt/Tinkerwell.backup-* /opt/Tinkerwell
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/mv squashfs-root /opt/Tinkerwell
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/rm -rf /opt/Tinkerwell.backup-*
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/tee /usr/local/bin/tinkerwell
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/chmod +x /usr/local/bin/tinkerwell
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/cp /opt/Tinkerwell/tinkerwell.desktop /usr/share/applications/tinkerwell.desktop
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/sed -i * /usr/share/applications/tinkerwell.desktop
EOF
chmod 440 /etc/sudoers.d/tinkerwell-updater
echo "      ✓ Sudoers configured"

echo "[3/3] Done!"
echo ""
echo "Usage:"
echo "  update-tinkerwell                    # auto-update (or fresh install)"
echo "  update-tinkerwell --force            # force reinstall"
echo "  update-tinkerwell --version 5.10.0   # specific version"
