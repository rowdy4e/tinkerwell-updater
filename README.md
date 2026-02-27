# Tinkerwell Linux Updater

Automatic updater for [Tinkerwell](https://tinkerwell.app/) on Linux. Keeps your installation up to date — just add it to your startup scripts. Also works as a fresh installer if Tinkerwell isn't installed yet.

**No sudo required** — everything installs to `~/.local/`.

## Features

- **No root privileges needed** — installs to user-local directories
- **Automatic update detection** — fetches version manifest from Tinkerwell CDN, compares with installed version
- **Fresh install support** — installs Tinkerwell from scratch if not present
- **SHA-512 verification** — validates download integrity before installing
- **Specific version install** — install any Tinkerwell version by number
- **Uninstall** — clean removal with `--uninstall`
- **Desktop notifications** — system notifications for update status
- **Safe updates** — backs up current installation, automatic rollback on failure
- **Internet check** — verifies connectivity with retry logic
- **Startup-friendly** — designed to run silently at boot
- **Logging** — all actions logged to `~/.local/share/tinkerwell-updater/updater.log`

## Requirements

- Linux x64
- `curl`, `ping`, `sha512sum`
- `notify-send` (pre-installed on GNOME/KDE/Cinnamon)
- `~/.local/bin` in your `PATH` (default on most modern distros)

## Installation

```bash
git clone https://github.com/YOUR_USER/tinkerwell-updater.git
cd tinkerwell-updater
./install.sh
```

### Manual install

```bash
mkdir -p ~/.local/bin
cp update-tinkerwell.sh ~/.local/bin/update-tinkerwell
chmod +x ~/.local/bin/update-tinkerwell
```

### Add to startup (optional)

```bash
(sleep 60 && update-tinkerwell) &
```

Or `~/.config/autostart/tinkerwell-updater.desktop`:

```ini
[Desktop Entry]
Type=Application
Name=Tinkerwell Updater
Exec=bash -c "sleep 60 && update-tinkerwell"
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
```

## Usage

```bash
update-tinkerwell                    # auto-update to latest
update-tinkerwell --force            # force reinstall latest
update-tinkerwell --version 5.10.0   # install specific version
update-tinkerwell --uninstall        # remove Tinkerwell
```

| Option | Description |
|---|---|
| *(none)* | Check version manifest, install if new version available |
| `--force` | Skip check and reinstall |
| `--version X.Y.Z` | Install specific version (implies `--force`) |
| `--uninstall` | Remove Tinkerwell and all related files |

## How it works

1. **Internet check** — pings `1.1.1.1` or curls Tinkerwell CDN (3 retries with backoff)
2. **Version check** — fetches `latest-linux.yml` manifest from DigitalOcean Spaces CDN
3. **Download** — downloads AppImage from CDN
4. **Verify** — validates SHA-512 checksum against manifest
5. **Extract** — extracts AppImage using `--appimage-extract`
6. **Backup** — moves current installation to `~/.local/opt/Tinkerwell.backup-YYYYMMDD-HHMMSS`
7. **Install** — moves extracted files to `~/.local/opt/Tinkerwell`, creates symlink and desktop entry
8. **Cleanup** — removes old backups (keeps 1)
9. **Notify** — desktop notification with result

## Files

| Path | Description |
|---|---|
| `~/.local/bin/update-tinkerwell` | Updater script |
| `~/.local/bin/tinkerwell` | Symlink to Tinkerwell binary |
| `~/.local/opt/Tinkerwell/` | Installation directory |
| `~/.local/share/applications/tinkerwell.desktop` | Desktop entry |
| `~/.local/share/tinkerwell-updater/updater.log` | Log file |

## Uninstall

```bash
update-tinkerwell --uninstall
rm ~/.local/bin/update-tinkerwell
```

## License

MIT
