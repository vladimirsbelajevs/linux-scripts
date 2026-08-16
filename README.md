# Linux scripts

A collection of Linux desktop, gaming, display, development, and system-maintenance utilities.

> [!NOTE]
> Several scripts contain machine-specific paths, display connector names, resolutions, and hardware settings. Review and adjust them before running on another system.

## Scripts

### `cleanup-cache.sh`

Interactively lists immediate entries in `${XDG_CACHE_HOME:-$HOME/.cache}`,
largest first, and permanently removes selected entries by number. Run it as
your normal user:

```bash
./cleanup-cache.sh
```

Enter comma-separated numbers such as `1,3,5`, review the selected entries and
total size, and type `yes` to confirm. Pass a different cache directory when
needed:

```bash
./cleanup-cache.sh ~/.npm
```

Use `--help` to display usage information. The script refuses to run with
`sudo`, rejects unsafe cache roots, and validates every selected path before
deletion. It requires GNU `du`, `find`, `numfmt`, `realpath`, and `sort`.

### `convert_tif_to_png.sh`

Converts every `.tif` and `.tiff` file in the current directory to an 8-bit sRGB PNG using ImageMagick. The script prompts whether to preserve the alpha channel.

```bash
cd /path/to/images
/path/to/convert_tif_to_png.sh
```

Requires the ImageMagick `magick` command.

### `enable_gaming_mode.sh`

Enables gaming-oriented system settings:

- Disables the kernel split-lock mitigation.
- Starts the `lavd` scheduler through `scxctl` in gaming mode.
- Disables and stops `ananicy-cpp`.

```bash
./enable_gaming_mode.sh
```

Requires `sudo`, `scxctl`, and the `ananicy-cpp` systemd service.

### `disable_gaming_mode.sh`

Restores the corresponding general-purpose system settings:

- Enables the kernel split-lock mitigation.
- Stops the scheduler managed by `scxctl`.
- Enables and starts `ananicy-cpp`.

```bash
./disable_gaming_mode.sh
```

### `enable_hdr.sh`

Enables HDR and wide color gamut on KDE output `DP-3`, selects accuracy-oriented color processing, and sets full RGB range.

```bash
./enable_hdr.sh
```

Requires KDE's `kscreen-doctor`. Change `DP-3` if your display uses a different connector.

### `disable_hdr.sh`

Disables HDR and wide color gamut on KDE output `DP-3`, selects efficiency-oriented color processing, and restores automatic RGB range selection.

```bash
./disable_hdr.sh
```

Requires KDE's `kscreen-doctor`.

### `restore_monitor_settings.sh`

Restores a machine-specific dual-monitor KDE configuration for outputs `DP-3` and `DP-2`, including:

- Resolution and refresh rate
- Position and scaling
- Primary display
- SDR brightness and HDR state
- Brightness overrides, RGB range, color policy, and VRR policy

```bash
./restore_monitor_settings.sh
```

Requires KDE's `kscreen-doctor`. Review every output and mode value before using this script on another display setup.

### `gamescope_tty.sh`

Starts Steam Gamepad UI in an embedded DRM Gamescope session with HDR support. Available profiles are:

| Profile | Output mode | Sunshine | Notes |
| --- | --- | --- | --- |
| `TV` | 3840×2160 at 120 Hz | Yes | Fill scaling and 700-nit target |
| `TV_60` | 3840×2160 at 60 Hz | Yes | Fill scaling and 700-nit target |
| `PC` | 3840×2160 at 160 Hz | No | Adaptive sync and immediate flips |
| `Deck` | 1920×1080 output, 1280×800 internal | Yes | Fit scaling for a 16:10 image |

```bash
./gamescope_tty.sh TV
./gamescope_tty.sh TV_60
./gamescope_tty.sh PC
./gamescope_tty.sh Deck
```

Set `MANGOAPP=1` to enable Gamescope's MangoApp overlay:

```bash
MANGOAPP=1 ./gamescope_tty.sh PC
```

Requires Gamescope and Steam; TV and Deck profiles also require Sunshine. The target DRM output is currently configured as `DP-1`.

### `steam_launcher.sh`

Launches a command through `game-performance` with configurable Proton and MangoHud environment variables. Current defaults enable HDR, Proton DLSS upgrades, and native Wayland support.

```bash
./steam_launcher.sh <command> [arguments...]
```

Supported environment variables:

| Variable | Default | Purpose |
| --- | ---: | --- |
| `HDR` | `1` | Sets `PROTON_ENABLE_HDR=1` |
| `PROTON_DLSS_UPGRADE` | `1` | Enables Proton's DLSS upgrade option |
| `WAYLAND` | `1` | Enables Proton Wayland and selects monitor `DP-3` |
| `CLEAR_LD_PRELOAD` | `0` | Clears `LD_PRELOAD` before launch |
| `MANGO` | `0` | Enables MangoHud |
| `WINEDLLOVERRIDES` | empty | Passes Wine DLL overrides through |

The selected settings and launch command are recorded in the system journal with the `steam_launcher` tag.

### `launch_unity.sh`

Launches a specific Unity Editor installation with Vulkan and custom GTK scaling. Extra command-line arguments are passed directly to Unity.

```bash
./launch_unity.sh [Unity arguments...]
```

The script currently points to Unity `6000.3.9f1` under `/home/vladimirs/Unity`. Update `UNITY_PATH`, `SCALE`, and `DPI_SCALE` as needed.

### `dotnet-install.sh`

Microsoft's standalone .NET installation script for CI and non-administrative installations.

```bash
# Install the latest SDK from a channel
./dotnet-install.sh --channel 8.0

# Show all options
./dotnet-install.sh --help
```

This script downloads .NET without configuring a system-wide package manager installation.

## Docker storage migration

The scripts in [`Docker/`](./Docker/) move Docker metadata and containerd image layers to different directories on another mounted filesystem.

### `Docker/move-docker-storage.sh`

Run on the parent machine:

```bash
./Docker/move-docker-storage.sh \
  /mnt/Samsung_SSD/docker-data \
  /mnt/Samsung_SSD/containerd-data
```

The script requests root access, validates the paths, displays the source and destination filesystems, and asks for confirmation. It then:

1. Stops Docker and containerd.
2. Copies both data directories with `rsync`.
3. Updates Docker's `data-root` while preserving the existing daemon settings.
4. Creates systemd overrides for containerd's root and mount ordering.
5. Restarts and verifies both services.
6. Saves migration state in `/etc/docker-storage-migration.json`.

The original data directories are retained for rollback. Use `--yes` to skip the confirmation prompt.

### `Docker/cleanup-docker-storage-migration.sh`

Reboot and verify that Docker and its containers work, then run:

```bash
./Docker/cleanup-docker-storage-migration.sh
```

The cleanup script refuses to run during the same boot in which migration was performed. It verifies that Docker and containerd use the recorded destination directories before deleting only the recorded old source directories. It briefly stops and then restarts both services. Use `--yes` to skip confirmation.
