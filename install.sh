#!/bin/bash

# Tinkerwell Updater - Install Script
# Usage: ./install.sh

set -euo pipefail

INSTALL_DIR="$HOME/.local/bin"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Tinkerwell Updater - Installer ==="

[[ "$EUID" -eq 0 ]] && { echo "Do not run as root. This installs to user directories."; exit 1; }

echo "[1/2] Creating directories..."
mkdir -p "$INSTALL_DIR" "$HOME/.local/opt" "$HOME/.local/share/applications" "$HOME/.local/share/tinkerwell-updater"
echo "      ✓ ~/.local directories ready"

echo "[2/2] Installing script..."
cp "$SCRIPT_DIR/update-tinkerwell.sh" "$INSTALL_DIR/update-tinkerwell"
chmod +x "$INSTALL_DIR/update-tinkerwell"
echo "      ✓ Installed to $INSTALL_DIR/update-tinkerwell"

# Ensure ~/.local/bin is in PATH
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
    echo ""
    echo "⚠  ~/.local/bin is not in your PATH. Add this to your ~/.bashrc or ~/.profile:"
    echo "   export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "Done! No sudo required."
echo ""
echo "Usage:"
echo "  update-tinkerwell                    # auto-update (or fresh install)"
echo "  update-tinkerwell --force            # force reinstall"
echo "  update-tinkerwell --version 5.10.0   # install specific version"
echo "  update-tinkerwell --uninstall        # remove Tinkerwell"
