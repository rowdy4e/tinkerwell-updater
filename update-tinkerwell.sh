#!/bin/bash

# Tinkerwell Auto-Updater Script
# Usage: update-tinkerwell [--force] [--version X.Y.Z] [--uninstall]

set -euo pipefail

DATA_DIR="$HOME/.local/share/tinkerwell-updater"
TINKERWELL_DIR="$HOME/.local/opt/Tinkerwell"
BIN_LINK="$HOME/.local/bin/tinkerwell"
DESKTOP_FILE="$HOME/.local/share/applications/tinkerwell.desktop"

LOG_FILE="$DATA_DIR/updater.log"
MANIFEST_URL="https://tinkerwell.fra1.cdn.digitaloceanspaces.com/tinkerwell/latest-linux.yml"
BASE_CDN="https://tinkerwell.fra1.cdn.digitaloceanspaces.com/tinkerwell"
TMP_DIR="/tmp/tinkerwell-update-$$"
VERSION_FILE="$TINKERWELL_DIR/tinkerwell.desktop"

# --- Logging & notifications ---

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE" >&2
}

notify() {
    local urgency="$1" summary="$2" body="$3"
    DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}" \
        notify-send -u "$urgency" -i tinkerwell -a "Tinkerwell Updater" "$summary" "$body" 2>/dev/null || true
}

die() {
    log "ERROR: $*"
    notify "critical" "Tinkerwell Update Failed" "$*"
    exit 1
}

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# --- Helpers ---

ensure_dirs() {
    mkdir -p "$DATA_DIR" "$HOME/.local/opt" "$HOME/.local/bin" "$HOME/.local/share/applications"
}

get_current_version() {
    if [[ -f "$VERSION_FILE" ]]; then
        grep -oP 'X-AppImage-Version=\K.*' "$VERSION_FILE" 2>/dev/null || echo "0.0.0"
    else
        echo "0.0.0"
    fi
}

get_latest_info() {
    local manifest
    manifest=$(curl -sL --connect-timeout 10 --max-time 15 "$MANIFEST_URL" 2>/dev/null)
    [[ -z "$manifest" ]] && die "Failed to fetch update manifest"
    echo "$manifest"
}

parse_version() {
    echo "$1" | grep -oP '^version:\s*\K\S+'
}

parse_sha512() {
    echo "$1" | grep -m1 -oP '^sha512:\s*\K\S+'
}

parse_filename() {
    echo "$1" | grep -oP '^path:\s*\K\S+'
}

version_compare() {
    [[ "$1" == "$2" ]] && return 0
    local IFS=.
    local i ver1=($1) ver2=($2)
    for ((i=0; i<${#ver1[@]} || i<${#ver2[@]}; i++)); do
        if [ "${ver1[i]:-0}" -gt "${ver2[i]:-0}" ] 2>/dev/null; then
            return 1
        fi
        if [ "${ver1[i]:-0}" -lt "${ver2[i]:-0}" ] 2>/dev/null; then
            return 2
        fi
    done
    return 0
}

check_internet() {
    log "Checking internet connectivity..."
    local retries=3
    for ((i=1; i<=retries; i++)); do
        if ping -c1 -W3 1.1.1.1 &>/dev/null || curl -sf --connect-timeout 5 --max-time 10 "$MANIFEST_URL" &>/dev/null; then
            log "Internet connection OK"
            return 0
        fi
        log "Attempt $i/$retries failed, waiting ${i}s..."
        sleep "$i"
    done
    die "No internet connection after $retries attempts"
}

verify_sha512() {
    local file="$1" expected="$2"
    local actual
    actual=$(sha512sum "$file" | awk '{print $1}' | xxd -r -p | base64 -w0)
    if [[ "$actual" != "$expected" ]]; then
        die "SHA512 mismatch: expected $expected, got $actual"
    fi
    log "SHA512 verified OK"
}

download_appimage() {
    local url="$1" archive="$TMP_DIR/tinkerwell.AppImage"
    mkdir -p "$TMP_DIR"

    log "Downloading from $url..."
    if ! curl -L --silent --show-error --connect-timeout 15 --max-time 600 -o "$archive" "$url"; then
        die "Download failed"
    fi

    [[ -s "$archive" ]] || die "Downloaded file is empty"
    log "Download OK ($(du -h "$archive" | cut -f1))"
    echo "$archive"
}

install_tinkerwell() {
    local appimage="$1"
    local backup="${TINKERWELL_DIR}.backup-$(date +%Y%m%d-%H%M%S)"

    log "Extracting AppImage..."
    chmod +x "$appimage"
    cd "$TMP_DIR"
    "$appimage" --appimage-extract >/dev/null 2>&1 || die "AppImage extraction failed"
    [[ -d squashfs-root ]] || die "Extraction produced no output"

    log "Installing to $TINKERWELL_DIR..."

    # Backup
    if [[ -d "$TINKERWELL_DIR" ]]; then
        mv "$TINKERWELL_DIR" "$backup" || die "Backup failed"
    fi

    # Move extracted files
    if ! mv squashfs-root "$TINKERWELL_DIR"; then
        log "Install failed, rolling back..."
        [[ -d "$backup" ]] && mv "$backup" "$TINKERWELL_DIR"
        die "Installation failed"
    fi

    # Symlink binary
    ln -sf "$TINKERWELL_DIR/tinkerwell" "$BIN_LINK"

    # Desktop entry
    local icon_path="$TINKERWELL_DIR/usr/share/icons/hicolor/512x512/apps/tinkerwell.png"
    cat > "$DESKTOP_FILE" << DESKTOP
[Desktop Entry]
Name=Tinkerwell
Comment=Tinker with your PHP applications
Exec=$TINKERWELL_DIR/tinkerwell --no-sandbox %U
Terminal=false
Type=Application
Icon=$icon_path
StartupWMClass=Tinkerwell
Categories=Development;
DESKTOP

    # Cleanup old backups (keep 1)
    ls -dt ${TINKERWELL_DIR}.backup-* 2>/dev/null | tail -n +2 | xargs -r rm -rf || true

    log "Installation OK"
}

uninstall_tinkerwell() {
    log "=== Uninstalling Tinkerwell ==="

    rm -rf "$TINKERWELL_DIR" ${TINKERWELL_DIR}.backup-*
    rm -f "$BIN_LINK" "$DESKTOP_FILE"

    log "Tinkerwell uninstalled"
    notify "normal" "Tinkerwell Uninstalled" "Tinkerwell has been removed from this system"
}

# --- Main ---

main() {
    ensure_dirs
    log "=== Tinkerwell Auto-Updater ==="
    [[ "$EUID" -eq 0 ]] && die "Do not run as root"

    local force=false target_version="" quiet=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)     force=true; log "Force mode" ;;
            --version)   target_version="$2"; shift ;;
            --quiet)     quiet=true ;;
            --uninstall) uninstall_tinkerwell; exit 0 ;;
            *)           die "Unknown option: $1\nUsage: update-tinkerwell [--force] [--version X.Y.Z] [--quiet] [--uninstall]" ;;
        esac
        shift
    done

    check_internet

    local current_version
    current_version=$(get_current_version)
    log "Installed: $current_version"

    local download_url sha512 latest_version

    if [[ -n "$target_version" ]]; then
        force=true
        latest_version="$target_version"
        download_url="$BASE_CDN/Tinkerwell-${target_version}.AppImage"
        sha512=""
        log "Target version: $target_version"
    else
        local manifest
        manifest=$(get_latest_info)
        latest_version=$(parse_version "$manifest")
        sha512=$(parse_sha512 "$manifest")
        local filename
        filename=$(parse_filename "$manifest")
        download_url="$BASE_CDN/$filename"
        log "Latest: $latest_version"
    fi

    # Check if update needed
    if ! $force; then
        version_compare "$current_version" "$latest_version" && vc=$? || vc=$?
        case $vc in
            0)
                log "Already up to date"
                $quiet || notify "low" "Tinkerwell Up to Date" "Version $current_version — no update available"
                exit 0
                ;;
            1)
                log "Current version is newer"
                exit 0
                ;;
            2)
                log "Update available: $current_version → $latest_version"
                notify "normal" "Updating Tinkerwell" "Updating from $current_version to $latest_version..."
                ;;
        esac
    else
        if [[ -n "$target_version" ]]; then
            notify "normal" "Updating Tinkerwell" "Installing version $target_version (current: $current_version)..."
        else
            notify "normal" "Updating Tinkerwell" "Force reinstalling (current: $current_version)..."
        fi
    fi

    # Download
    local appimage
    appimage=$(download_appimage "$download_url")

    # Verify checksum (if available)
    if [[ -n "$sha512" ]]; then
        verify_sha512 "$appimage" "$sha512"
    fi

    # Install
    install_tinkerwell "$appimage"

    # Verify
    local new_version
    new_version=$(get_current_version)
    log "=== Done: $current_version → $new_version ==="
    notify "normal" "Tinkerwell Updated" "$current_version → $new_version"
}

main "$@"
