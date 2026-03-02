# ATEMView — Raspberry Pi 4 ATEM USB Display

Full-screen, low-latency display of a Blackmagic ATEM USB video feed on a Raspberry Pi 4 HDMI output. Designed as a hardened, read-only appliance.

---

## Features

- 1080p60 forced HDMI output, regardless of whether a display is connected at boot
- Hot-swap support — plug/unplug the ATEM without rebooting
- No X11 or Wayland — mpv writes directly to the display via DRM/KMS
- Read-only SD card via overlayfs — safe to hard power-cut at any time
- Auto-recovery if mpv crashes or the USB device misbehaves

---

## Hardware Requirements

| Item | Notes |
|---|---|
| Raspberry Pi 4 (any RAM) | USB 3.0 ports required for 1080p MJPEG bandwidth |
| Blackmagic ATEM Mini / Mini Pro / Mini Pro ISO | USB webcam (UVC) output mode |
| Micro-HDMI to HDMI cable | Use **HDMI0** — the port closest to the USB-C power connector |
| Display at 1080p | Or no display — Pi will output regardless |

The ATEM's USB output presents as a standard UVC webcam device. No proprietary drivers are needed.

---

## Repository Structure

```
ATEMView/
├── README.md                    # This file
├── setup.sh                     # Run once on the Pi to install everything
└── files/
    ├── atem-display.sh          # Display loop script  → /usr/local/bin/
    ├── atem-display.service     # systemd unit         → /etc/systemd/system/
    └── 99-atem.rules            # udev hot-swap rules  → /etc/udev/rules.d/
```

---

## Deployment

> **Pre-built image available.**
> Check the [GitHub Releases](https://github.com/tombartindale/ATEMView/releases) page for a ready-to-flash `.img.xz`. If a release exists, skip to Step 1 and use that image instead of flashing stock Pi OS and running `setup.sh`.

### Step 1 — Flash the OS

Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/) to flash either:
- A pre-built ATEMView release image (recommended), or
- Stock **Raspberry Pi OS Lite 64-bit** if you intend to run `setup.sh` manually

> **Raspberry Pi OS Lite 64-bit**

In the imager's **Advanced Options** (gear icon):
- Set hostname (e.g. `atemview`)
- Enable SSH
- Set a username and password
- Configure Wi-Fi if needed (only needed for initial setup — can remove after)

### Step 2 — Clone this repository onto the Pi

SSH into the Pi, then:

```bash
git clone https://github.com/tombartindale/ATEMView.git
```

> Git may not be installed on a fresh Pi OS Lite image. If so, install it first:
> ```bash
> sudo apt-get update && sudo apt-get install -y git
> ```

### Step 3 — Run the setup script

```bash
cd ATEMView
sudo bash setup.sh
```

The script will:
1. Update the system
2. Install `mpv` and `v4l-utils`
3. Patch `/boot/firmware/config.txt` — force 1080p60 on HDMI0, suppress GPU splash, enable UART
4. Patch `/boot/firmware/cmdline.txt` — suppress kernel boot messages and hide the cursor
5. Install the display script, udev rules, and display systemd service
6. Install the status web server (`atem-status.py`) and its systemd service (port 80)
7. Disable the TTY1 console (so it doesn't conflict with the DRM output)
8. Enable both services to start at boot

The result is a **fully black screen** from power-on: no splash, no boot text, no cursor. When the ATEM is plugged in, video appears. When it is unplugged, the screen returns to black.

### Step 4 — Verify it works

Reboot, then plug in the ATEM:

```bash
sudo reboot
# After reboot, plug in ATEM and check:
journalctl -u atem-display -f
```

You should see the ATEM video appear full-screen on the HDMI output within a couple of seconds of plugging in.

Test the udev symlink was created:

```bash
ls -la /dev/atem_video
```

Test mpv manually if needed:

```bash
sudo mpv --vo=drm --drm-connector=HDMI-A-1 --fullscreen av://v4l2:/dev/atem_video
```

### Step 5 — Enable read-only mode (do this last)

Once everything is confirmed working:

```bash
sudo raspi-config
```

Navigate to: **Performance Options → Overlay File System → Enable**

When prompted to also write-protect the boot partition, select **Yes**.

Reboot. The SD card is now read-only. All writes during operation go to RAM and are discarded on reboot.

> **To make future changes:** Disable the overlay in `raspi-config`, reboot, make changes, re-enable, reboot.

---

## How It Works

### Video stack

```
ATEM (USB UVC device)
        │
        ▼
   /dev/atem_video   ← stable udev symlink
        │
        ▼
   mpv (av://v4l2)   ← reads MJPEG frames via V4L2
        │
        ▼
   DRM/KMS output    ← direct framebuffer, no X11
        │
        ▼
   HDMI0 @ 1080p60
```

### Hot-swap flow

```
USB plug-in
    → kernel loads uvcvideo driver
    → udev fires ACTION=="add" rule
    → udev creates /dev/atem_video symlink
    → udev runs: systemctl start atem-display.service
    → script finds device, launches mpv

USB unplug
    → udev fires ACTION=="remove" rule
    → udev runs: systemctl stop atem-display.service
    → mpv exits; service loop waits for device to return
```

### Why MJPEG?

Raw YUV (YUYV) at 1920×1080@30fps requires ~3 Gbps of USB bandwidth, which exceeds USB 2.0 limits. The ATEM outputs **MJPEG-compressed** frames over USB, which fits comfortably within USB 3.0 bandwidth. The Pi 4's CPU decodes MJPEG in software with minimal CPU usage at 30fps.

### Why `--vo=drm`?

mpv's DRM output backend writes directly to the kernel's KMS framebuffer. This means:
- No X server or Wayland compositor is needed
- Fewer moving parts = higher reliability
- Startup is fast (no display server init)
- Works from a systemd service before any user logs in

### Black screen behaviour

Three layers combine to ensure the display is black whenever no ATEM video is present:

| Layer | Mechanism | Suppresses |
|---|---|---|
| GPU firmware | `disable_splash=1` in config.txt | Rainbow square at power-on |
| Kernel | `quiet loglevel=0 logo.nologo` in cmdline.txt | Boot messages and penguin logo |
| Console | `vt.global_cursor_default=0` in cmdline.txt | Blinking cursor on TTY1 |

When mpv exits (ATEM unplugged), DRM releases the display and TTY1 becomes visible again — but with all text and cursor suppressed it is just a black framebuffer.

---

## Configuration Reference

### HDMI modes (config.txt)

| `hdmi_mode` | Resolution | Refresh |
|---|---|---|
| `16` | 1920×1080 | 60 Hz |
| `31` | 1920×1080 | 50 Hz |
| `5`  | 1920×1080 | 60 Hz interlaced |

Change `hdmi_mode:0=16` in `/boot/firmware/config.txt` if your display needs a different rate.

### ATEM USB output resolution

Set in ATEM Software Control under **Output → USB Webcam Output**. Match what you configure in `atem-display.sh`:

```bash
--demuxer-lavf-o=video_size=1920x1080,framerate=30,input_format=mjpeg
```

If you set the ATEM to 720p, change `video_size=1280x720`.

### DRM connector name

On Pi 4, the connectors are:
- `HDMI-A-1` — HDMI0 (closest to USB-C power)
- `HDMI-A-2` — HDMI1

List all connectors on your system:

```bash
cat /sys/class/drm/*/status
```

---

## Debugging

Three debug interfaces are available, in order of reliability:

### 1. Web status page (easiest)

The setup installs a lightweight HTTP server on **port 80** that shows a live dashboard: ATEM connection state, service status, USB devices, V4L2 devices, and recent logs. It auto-refreshes every 5 seconds.

```
http://atemview.local
```

Or by IP address if mDNS isn't available:

```bash
# Find the Pi's IP from another machine
ping atemview.local
arp -n | grep -i "b8:27\|dc:a6\|e4:5f"   # Raspberry Pi MAC prefixes
```

The status page works even if HDMI output is broken. It does **not** work if the network is down.

```bash
# Check the status server itself
sudo systemctl status atem-status
journalctl -u atem-status -f
```

### 2. SSH (primary remote access)

```bash
ssh pi@atemview.local

# Watch display service logs live
journalctl -u atem-display -f

# List detected video devices
v4l2-ctl --list-devices

# Show formats supported by the ATEM
v4l2-ctl --device=/dev/video0 --list-formats-ext

# Confirm Blackmagic USB vendor ID
lsusb | grep -i blackmagic

# List DRM connectors and their state
cat /sys/class/drm/*/status

# Test mpv directly (stop service first)
sudo systemctl stop atem-display
sudo mpv --vo=drm --drm-connector=HDMI-A-1 --fullscreen av://v4l2:/dev/atem_video
```

### 3. UART serial console (last resort)

The setup enables a hardware serial console on the Pi's GPIO header. This works even if the network is down, HDMI is dead, or the Pi has failed to boot fully. You need a **USB-to-TTL serial adapter** (3.3V logic — common, cheap).

**Wiring (Pi 4 GPIO header):**

```
Pi GPIO 14 (TXD) — physical pin 8  →  RX on adapter
Pi GPIO 15 (RXD) — physical pin 10 →  TX on adapter
Pi GND            — physical pin 6  →  GND on adapter
```

Do **not** connect the adapter's 5V/3.3V pin — the Pi is self-powered.

**Connect from your Mac/PC:**

```bash
# macOS — find the device name first
ls /dev/tty.usbserial* /dev/tty.SLAB* /dev/tty.CH340* 2>/dev/null

# Then connect (replace with your actual device)
screen /dev/tty.usbserial-0001 115200
# or
minicom -b 115200 -D /dev/tty.usbserial-0001
```

**Linux:**

```bash
screen /dev/ttyUSB0 115200
```

Press Enter after connecting. You'll get a login prompt. To exit `screen`: `Ctrl-A` then `K`.

### Common issues

**No video after plugging in:**
- Run `lsusb | grep -i blackmagic` — if nothing appears, USB cable or ATEM USB output is off
- Check `v4l2-ctl --list-devices` to confirm `/dev/video0` exists
- Run `journalctl -u atem-display -f` and watch what happens when you plug in

**Wrong vendor ID in udev rules:**
- Run `lsusb` with ATEM plugged in and find the Blackmagic entry
- The ID format is `ID XXXX:YYYY` where `XXXX` is the vendor ID
- Update `ATTRS{idVendor}=="1edb"` in `99-atem.rules` if different

**mpv exits immediately:**
- The ATEM may not be in USB webcam output mode — check ATEM Software Control settings
- Try a lower resolution: change `video_size=1920x1080` to `video_size=1280x720`
- Check if another process is holding the device: `fuser /dev/video0`

**Display is not 1080p:**
- Check `config.txt` edits took effect: `vcgencmd get_config hdmi_mode`
- Verify the HDMI cable supports 1080p60
- Try `--drm-mode=1920x1080@60` in the mpv command in `atem-display.sh`

**Read-only mode — can't make changes:**
- `sudo raspi-config` → Performance Options → Overlay File System → Disable
- Reboot, make changes, re-enable, reboot

---

## Logs

When overlayfs is enabled, logs are in RAM only and lost on reboot. For persistent logging, add a USB stick and configure `journald` to log there, or use a syslog forwarder to a network server. For a display appliance this is usually unnecessary.

To view current session logs:

```bash
journalctl -u atem-display
journalctl -b   # all logs this boot
```

---

## Building a SD Card Image

The GitHub Actions workflow in [`.github/workflows/build-image.yml`](.github/workflows/build-image.yml) automatically produces a flashable `.img.xz` image using a chroot-based build (no physical Pi required).

### How it works

1. Downloads the official Raspberry Pi OS Lite 64-bit image
2. Loop-mounts the image and bind-mounts `/proc`, `/sys`, `/dev`
3. Copies `qemu-aarch64-static` into the chroot so ARM64 binaries run on the x86 GitHub Actions runner
4. Runs [`build/chroot-setup.sh`](build/chroot-setup.sh) inside the chroot, which:
   - Installs a `systemctl` stub (systemd cannot run in a chroot; the stub handles `enable`/`disable` via symlinks and silently ignores runtime commands like `start`/`stop`)
   - Runs `setup.sh` as normal
   - Cleans up SSH host keys and `machine-id` so each Pi gets a fresh identity on first boot
5. Shrinks the image with [PiShrink](https://github.com/Drewsif/PiShrink) and compresses with xz
6. Uploads the image as a workflow artifact and, on tagged releases, as a GitHub Release asset

### Triggering a build

**Automated release** — push a version tag:
```bash
git tag v1.0.0
git push origin v1.0.0
```
The workflow runs, produces `atemview-v1.0.0.img.xz`, and creates a GitHub Release with it attached.

**Manual build** — go to **Actions → Build SD Card Image → Run workflow** in the GitHub UI. The artifact is available for 30 days under the workflow run.

### What is and isn't pre-configured in the image

| Pre-configured | Not pre-configured (set in Raspberry Pi Imager) |
|---|---|
| ATEMView display service | Username and password |
| Status web server | Hostname |
| udev hot-swap rules | SSH keys (regenerated on first boot) |
| Silent 1080p60 boot | Wi-Fi credentials |
| UART serial console | |
