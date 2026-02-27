# Tinkerwell Linux Updater

Automatic updater for [Tinkerwell](https://tinkerwell.app/) on Linux. Keeps your installation up to date — just add it to your startup scripts. Also works as a fresh installer if Tinkerwell isn't installed yet.

## Features

- **Automatic update detection** — fetches version manifest from Tinkerwell CDN, compares with installed version
- **Fresh install support** — installs Tinkerwell from scratch if not present
- **SHA-512 verification** — validates download integrity before installing
- **Specific version install** — install any Tinkerwell version by number
- **Desktop notifications** — system notifications for update status
- **Safe updates** — backs up current installation, automatic rollback on failure
- **Internet check** — verifies connectivity with retry logic
- **Startup-friendly** — designed to run silently at boot
- **Logging** — all actions logged to `~/.tinkerwell-updater.log`

## Requirements

- Linux x64
- `curl`, `tar`, `ping`, `sha512sum`
- `notify-send` (pre-installed on GNOME/KDE/Cinnamon)
- `sudo` access

## Installation

```bash
git clone https://github.com/YOUR_USER/tinkerwell-updater.git
cd tinkerwell-updater
sudo ./install.sh
```

### Manual install

```bash
sudo cp update-tinkerwell.sh /usr/local/bin/update-tinkerwell
sudo chmod +x /usr/local/bin/update-tinkerwell
```

### Passwordless sudo (recommended for automation)

```bash
sudo visudo -f /etc/sudoers.d/tinkerwell-updater
```

```
your_username ALL=(ALL) NOPASSWD: /bin/mv /opt/Tinkerwell /opt/Tinkerwell.backup-*
your_username ALL=(ALL) NOPASSWD: /bin/mv /opt/Tinkerwell.backup-* /opt/Tinkerwell
your_username ALL=(ALL) NOPASSWD: /bin/mv squashfs-root /opt/Tinkerwell
your_username ALL=(ALL) NOPASSWD: /bin/rm -rf /opt/Tinkerwell.backup-*
your_username ALL=(ALL) NOPASSWD: /usr/bin/tee /usr/local/bin/tinkerwell
your_username ALL=(ALL) NOPASSWD: /bin/chmod +x /usr/local/bin/tinkerwell
your_username ALL=(ALL) NOPASSWD: /bin/cp /opt/Tinkerwell/tinkerwell.desktop /usr/share/applications/tinkerwell.desktop
your_username ALL=(ALL) NOPASSWD: /usr/bin/sed -i * /usr/share/applications/tinkerwell.desktop
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
```

| Option | Description |
|---|---|
| *(none)* | Check version manifest, install if new version available |
| `--force` | Skip check and reinstall |
| `--version X.Y.Z` | Install specific version (implies `--force`) |

## How it works

1. **Internet check** — pings `1.1.1.1` or curls Tinkerwell CDN (3 retries with backoff)
2. **Version check** — fetches `latest-linux.yml` manifest from DigitalOcean Spaces CDN
3. **Download** — downloads AppImage from CDN
4. **Verify** — validates SHA-512 checksum against manifest
5. **Extract** — extracts AppImage using `--appimage-extract`
6. **Backup** — moves `/opt/Tinkerwell` to `/opt/Tinkerwell.backup-YYYYMMDD-HHMMSS`
7. **Install** — moves extracted files to `/opt/Tinkerwell`, creates wrapper script and desktop entry
8. **Cleanup** — removes old backups (keeps 1)
9. **Notify** — desktop notification with result

## Files

| Path | Description |
|---|---|
| `/usr/local/bin/update-tinkerwell` | Updater script |
| `/usr/local/bin/tinkerwell` | Wrapper script (created by updater) |
| `~/.tinkerwell-updater.log` | Log file |
| `/opt/Tinkerwell` | Installation directory |
| `/usr/share/applications/tinkerwell.desktop` | Desktop entry |

## Uninstall

```bash
sudo rm /usr/local/bin/update-tinkerwell /usr/local/bin/tinkerwell
sudo rm /etc/sudoers.d/tinkerwell-updater
rm ~/.tinkerwell-updater.log
```

## License

MIT
