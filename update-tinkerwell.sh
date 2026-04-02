#!/bin/bash

# Tinkerwell Auto-Updater Script
# Usage: update-tinkerwell [--force] [--version X.Y.Z] [--uninstall]

set -euo pipefail

DATA_DIR="$HOME/.local/share/tinkerwell-updater"
TINKERWELL_DIR="$HOME/.local/opt/Tinkerwell"
BIN_LINK="$HOME/.local/bin/tinkerwell"
DESKTOP_FILE="$HOME/.local/share/applications/tinkerwell.desktop"

LOG_FILE="$DATA_DIR/updater.log"
IGNORED_VERSIONS_FILE="$DATA_DIR/ignored_versions"
VERSION_HISTORY_FILE="$DATA_DIR/version_history"
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

is_version_ignored() {
    local ver="$1"
    [[ -f "$IGNORED_VERSIONS_FILE" ]] && grep -qxF "$ver" "$IGNORED_VERSIONS_FILE"
}

record_version() {
    local ver="$1"
    [[ -z "$ver" || "$ver" == "0.0.0" ]] && return
    local tmp
    tmp=$(mktemp)
    { echo "$ver"; grep -vxF "$ver" "$VERSION_HISTORY_FILE" 2>/dev/null || true; } | head -20 > "$tmp"
    mv "$tmp" "$VERSION_HISTORY_FILE"
}

# --- TUI multi-select (arrow keys + space to toggle) ---

tui_multiselect() {
    local prompt="$1" prechecked="$2"
    shift 2
    local -a items=("$@")
    local count=${#items[@]}
    [[ $count -eq 0 ]] && return 1

    local cursor=0
    local -a checked=()
    for ((i=0; i<count; i++)); do checked+=("0"); done
    for idx in $prechecked; do
        (( idx >= 0 && idx < count )) && checked[$idx]=1
    done

    local max_vis
    max_vis=$(( $(tput lines 2>/dev/tty || echo 20) - 6 ))
    (( max_vis > count )) && max_vis=$count
    (( max_vis < 3 )) && max_vis=3
    local offset=0

    local saved_tty
    saved_tty=$(stty -g </dev/tty 2>/dev/null)
    trap 'printf "\e[?25h" >/dev/tty 2>/dev/null; stty "'"$saved_tty"'" </dev/tty 2>/dev/null; exit 130' INT
    printf '\e[?25l' >/dev/tty

    # Reserve space, move back up, save position
    local total=$((max_vis + 4))
    for ((i=0; i<total; i++)); do printf '\n' >/dev/tty; done
    printf '\e[%dA' "$total" >/dev/tty
    printf '\e7' >/dev/tty

    _tui_draw() {
        printf '\e8\e[J' >/dev/tty
        printf '  \e[1;36m%s\e[0m\n\n' "$prompt" >/dev/tty

        (( cursor < offset )) && offset=$cursor
        (( cursor >= offset + max_vis )) && offset=$((cursor - max_vis + 1))

        for ((i=offset; i < offset + max_vis && i < count; i++)); do
            local mark="\e[90m◻\e[0m" pfx="  " style=""
            (( checked[i] )) && mark="\e[32m◼\e[0m"
            if (( i == cursor )); then
                pfx="\e[32m❯\e[0m" style="\e[1m"
            fi
            printf '  %b %b %b%b\e[0m\n' "$pfx" "$mark" "$style" "${items[$i]}" >/dev/tty
        done

        printf '\n  \e[90m↑↓ navigate · space select · enter confirm · q cancel\e[0m' >/dev/tty
    }

    _tui_draw

    while true; do
        local key
        IFS= read -rsn1 key </dev/tty
        case "$key" in
            $'\e')
                local seq
                IFS= read -rsn2 -t 0.1 seq </dev/tty
                case "$seq" in
                    '[A') (( cursor > 0 )) && (( cursor-- )) ;;
                    '[B') (( cursor < count - 1 )) && (( cursor++ )) ;;
                esac
                _tui_draw
                ;;
            ' ')
                checked[$cursor]=$(( 1 - checked[cursor] ))
                _tui_draw
                ;;
            ''|$'\r')
                break
                ;;
            q)
                printf '\e[?25h' >/dev/tty
                stty "$saved_tty" </dev/tty 2>/dev/null
                trap - INT
                printf '\n\n  \e[33mCancelled\e[0m\n' >/dev/tty
                return 1
                ;;
        esac
    done

    printf '\e[?25h' >/dev/tty
    stty "$saved_tty" </dev/tty 2>/dev/null
    trap - INT
    printf '\n\n' >/dev/tty

    local any=false
    for ((i=0; i<count; i++)); do
        if (( checked[i] )); then
            echo "${items[$i]}"
            any=true
        fi
    done

    if ! $any; then
        printf '  \e[33mNo versions selected\e[0m\n' >/dev/tty
        return 1
    fi
}

tui_singleselect() {
    local prompt="$1"
    shift
    local -a items=("$@")
    local count=${#items[@]}
    [[ $count -eq 0 ]] && return 1

    local cursor=0
    local max_vis
    max_vis=$(( $(tput lines 2>/dev/tty || echo 20) - 6 ))
    (( max_vis > count )) && max_vis=$count
    (( max_vis < 3 )) && max_vis=3
    local offset=0

    local saved_tty
    saved_tty=$(stty -g </dev/tty 2>/dev/null)
    trap 'printf "\e[?25h" >/dev/tty 2>/dev/null; stty "'"$saved_tty"'" </dev/tty 2>/dev/null; exit 130' INT
    printf '\e[?25l' >/dev/tty

    local total=$((max_vis + 4))
    for ((i=0; i<total; i++)); do printf '\n' >/dev/tty; done
    printf '\e[%dA' "$total" >/dev/tty
    printf '\e7' >/dev/tty

    _tui_s_draw() {
        printf '\e8\e[J' >/dev/tty
        printf '  \e[1;36m%s\e[0m\n\n' "$prompt" >/dev/tty

        (( cursor < offset )) && offset=$cursor
        (( cursor >= offset + max_vis )) && offset=$((cursor - max_vis + 1))

        for ((i=offset; i < offset + max_vis && i < count; i++)); do
            if (( i == cursor )); then
                printf '  \e[32m❯\e[0m \e[1m%b\e[0m\n' "${items[$i]}" >/dev/tty
            else
                printf '    %b\n' "${items[$i]}" >/dev/tty
            fi
        done

        printf '\n  \e[90m↑↓ navigate · enter select · q cancel\e[0m' >/dev/tty
    }

    _tui_s_draw

    while true; do
        local key
        IFS= read -rsn1 key </dev/tty
        case "$key" in
            $'\e')
                local seq
                IFS= read -rsn2 -t 0.1 seq </dev/tty
                case "$seq" in
                    '[A') (( cursor > 0 )) && (( cursor-- )) ;;
                    '[B') (( cursor < count - 1 )) && (( cursor++ )) ;;
                esac
                _tui_s_draw
                ;;
            ''|$'\r')
                break
                ;;
            q)
                printf '\e[?25h' >/dev/tty
                stty "$saved_tty" </dev/tty 2>/dev/null
                trap - INT
                printf '\n\n  \e[33mCancelled\e[0m\n' >/dev/tty
                return 1
                ;;
        esac
    done

    printf '\e[?25h' >/dev/tty
    stty "$saved_tty" </dev/tty 2>/dev/null
    trap - INT
    printf '\n\n' >/dev/tty

    echo "${items[$cursor]}"
}

# --- Interactive ignore/unignore/version ---

interactive_ignore() {
    echo "Fetching available versions..."
    local versions=()

    local changelog
    changelog=$(curl -sL --connect-timeout 10 --max-time 15 "https://tinkerwell.app/changelog" 2>/dev/null)
    if [[ -n "$changelog" ]]; then
        mapfile -t versions < <(echo "$changelog" | grep -oP 'Tinkerwell \K[0-9]+\.[0-9]+\.[0-9]+' | awk '!seen[$0]++' | head -20)
    fi

    if [[ ${#versions[@]} -eq 0 ]]; then
        echo "Could not fetch version list. Try: update-tinkerwell --ignore X.Y.Z"
        return 1
    fi

    # Build labels & pre-check already-ignored
    local labels=() prechecked=""
    for ((i=0; i<${#versions[@]}; i++)); do
        if grep -qxF "${versions[$i]}" "$IGNORED_VERSIONS_FILE" 2>/dev/null; then
            labels+=("${versions[$i]}  \e[90m(already ignored)\e[0m")
            prechecked+="$i "
        else
            labels+=("${versions[$i]}")
        fi
    done

    local selected
    selected=$(tui_multiselect "Which versions do you want to ignore?" "$prechecked" "${labels[@]}") || return 0

    local added=0
    while IFS= read -r item; do
        local ver="${item%%  *}"
        if ! grep -qxF "$ver" "$IGNORED_VERSIONS_FILE" 2>/dev/null; then
            echo "$ver" >> "$IGNORED_VERSIONS_FILE"
            printf '  \e[32m✓\e[0m %s added to ignore list\n' "$ver"
            added=$((added + 1))
        fi
    done <<< "$selected"
    if [[ $added -eq 0 ]]; then
        echo "  No new versions ignored"
    fi
}

interactive_unignore() {
    if [[ ! -f "$IGNORED_VERSIONS_FILE" ]] || [[ ! -s "$IGNORED_VERSIONS_FILE" ]]; then
        echo "No ignored versions"
        return 0
    fi

    local versions=()
    mapfile -t versions < "$IGNORED_VERSIONS_FILE"

    local selected
    selected=$(tui_multiselect "Which versions do you want to unignore?" "" "${versions[@]}") || return 0

    while IFS= read -r ver; do
        sed -i "/^$(sed 's/[.[\*^$]/\\&/g' <<< "$ver")$/d" "$IGNORED_VERSIONS_FILE"
        printf '  \e[32m✓\e[0m %s removed from ignore list\n' "$ver"
    done <<< "$selected"
}

interactive_version() {
    echo "Fetching available versions..." >&2
    local versions=()

    local changelog
    changelog=$(curl -sL --connect-timeout 10 --max-time 15 "https://tinkerwell.app/changelog" 2>/dev/null)
    if [[ -n "$changelog" ]]; then
        mapfile -t versions < <(echo "$changelog" | grep -oP 'Tinkerwell \K[0-9]+\.[0-9]+\.[0-9]+' | awk '!seen[$0]++' | head -20)
    fi

    if [[ ${#versions[@]} -eq 0 ]]; then
        echo "Could not fetch version list. Try: update-tinkerwell --version X.Y.Z" >&2
        return 1
    fi

    # Mark installed version
    local installed
    installed=$(get_current_version)
    local labels=()
    for v in "${versions[@]}"; do
        if [[ "$v" == "$installed" ]]; then
            labels+=("$v  \e[90m(installed)\e[0m")
        else
            labels+=("$v")
        fi
    done

    local selected
    selected=$(tui_singleselect "Which version do you want to install?" "${labels[@]}") || return 1
    echo "${selected%%  *}"
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
            --version)
                if [[ -n "${2:-}" ]]; then
                    target_version="$2"; shift
                else
                    target_version=$(interactive_version) || exit 0
                fi
                ;;
            --quiet)     quiet=true ;;
            --uninstall) uninstall_tinkerwell; exit 0 ;;
            --list-ignored)
                if [[ ! -f "$IGNORED_VERSIONS_FILE" ]] || [[ ! -s "$IGNORED_VERSIONS_FILE" ]]; then
                    echo "No ignored versions"
                else
                    echo "Ignored versions:"
                    cat "$IGNORED_VERSIONS_FILE"
                fi
                exit 0
                ;;
            --ignore)
                if [[ -n "${2:-}" ]]; then
                    local ignore_ver="$2"
                    shift
                    if grep -qxF "$ignore_ver" "$IGNORED_VERSIONS_FILE" 2>/dev/null; then
                        echo "Version $ignore_ver is already in ignore list"
                    else
                        echo "$ignore_ver" >> "$IGNORED_VERSIONS_FILE"
                        echo "Version $ignore_ver added to ignore list"
                    fi
                else
                    interactive_ignore
                fi
                exit 0
                ;;
            --unignore)
                if [[ -n "${2:-}" ]]; then
                    local unignore_ver="$2"
                    shift
                    if grep -qxF "$unignore_ver" "$IGNORED_VERSIONS_FILE" 2>/dev/null; then
                        sed -i "/^$(sed 's/[.[\*^$]/\\&/g' <<< "$unignore_ver")$/d" "$IGNORED_VERSIONS_FILE"
                        echo "Version $unignore_ver removed from ignore list"
                    else
                        echo "Version $unignore_ver is not in ignore list"
                    fi
                else
                    interactive_unignore
                fi
                exit 0
                ;;
            *)           die "Unknown option: $1\nUsage: update-tinkerwell [--force] [--version X.Y.Z] [--quiet] [--uninstall] [--ignore X.Y.Z] [--unignore X.Y.Z] [--list-ignored]" ;;
        esac
        shift
    done

    check_internet

    local current_version
    current_version=$(get_current_version)
    log "Installed: $current_version"
    record_version "$current_version"

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
        record_version "$latest_version"
        log "Latest: $latest_version"
    fi

    # Skip ignored versions (unless --version was explicitly specified)
    if [[ -z "$target_version" ]] && is_version_ignored "$latest_version"; then
        log "Version $latest_version is in ignore list, skipping"
        $quiet || notify "low" "Tinkerwell Update Skipped" "Version $latest_version is ignored — edit ~/.local/share/tinkerwell-updater/ignored_versions to change this"
        exit 0
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
