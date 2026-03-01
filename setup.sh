#!/bin/bash
# setup.sh — ATEMView installer
#
# Run once on the Raspberry Pi after copying this repository:
#   sudo bash setup.sh
#
# Must be run as root. Must be run from the ATEMView directory
# (the one containing this script and the files/ subdirectory).

set -euo pipefail

# ── Sanity checks ─────────────────────────────────────────────────────────────

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run as root: sudo bash setup.sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES_DIR="$SCRIPT_DIR/files"

if [[ ! -d "$FILES_DIR" ]]; then
    echo "ERROR: files/ directory not found. Run from the ATEMView directory."
    exit 1
fi

for f in atem-display.sh atem-display.service 99-atem.rules; do
    if [[ ! -f "$FILES_DIR/$f" ]]; then
        echo "ERROR: Missing required file: files/$f"
        exit 1
    fi
done

CONFIG=/boot/firmware/config.txt
if [[ ! -f "$CONFIG" ]]; then
    # Fallback for older Pi OS layouts
    CONFIG=/boot/config.txt
    if [[ ! -f "$CONFIG" ]]; then
        echo "ERROR: Cannot find config.txt (tried /boot/firmware/config.txt and /boot/config.txt)"
        exit 1
    fi
fi

echo "========================================"
echo "  ATEMView Setup"
echo "  Config file: $CONFIG"
echo "========================================"
echo ""

# ── 1. System update ──────────────────────────────────────────────────────────

echo "[1/7] Updating package lists..."
apt-get update -qq

echo "[1/7] Upgrading installed packages..."
apt-get upgrade -y -qq

# ── 2. Install packages ───────────────────────────────────────────────────────

echo "[2/7] Installing mpv and v4l-utils..."
apt-get install -y -qq mpv v4l-utils

# ── 3. Patch config.txt for 1080p60 HDMI ─────────────────────────────────────

echo "[3/7] Patching $CONFIG for forced 1080p60 on HDMI0..."

# Remove any pre-existing lines we're about to set, to avoid duplicates
sed -i \
    -e '/^hdmi_force_hotplug/d' \
    -e '/^hdmi_group/d' \
    -e '/^hdmi_mode/d' \
    -e '/^hdmi_drive/d' \
    -e '/^# ATEMView:/d' \
    "$CONFIG"

# Append our settings
cat >> "$CONFIG" << 'EOF'

# ATEMView: Force 1080p60 on HDMI0 (port nearest USB-C power)
# hdmi_mode options: 16=1080p60  31=1080p50  5=1080i60
# To target HDMI1 instead, change :0 to :1
hdmi_force_hotplug:0=1
hdmi_group:0=1
hdmi_mode:0=16
hdmi_drive:0=2
EOF

echo "    Done. Relevant config.txt lines:"
grep -E "^hdmi_" "$CONFIG" | sed 's/^/    /'

# ── 4. Install display script ─────────────────────────────────────────────────

echo "[4/7] Installing display script..."
install -m 755 "$FILES_DIR/atem-display.sh" /usr/local/bin/atem-display.sh
echo "    Installed: /usr/local/bin/atem-display.sh"

# ── 5. Install udev rules ─────────────────────────────────────────────────────

echo "[5/7] Installing udev rules..."
install -m 644 "$FILES_DIR/99-atem.rules" /etc/udev/rules.d/99-atem.rules
udevadm control --reload-rules
echo "    Installed: /etc/udev/rules.d/99-atem.rules"

# ── 6. Install and enable systemd service ─────────────────────────────────────

echo "[6/7] Installing systemd service..."
install -m 644 "$FILES_DIR/atem-display.service" /etc/systemd/system/atem-display.service
systemctl daemon-reload
systemctl enable atem-display.service
echo "    Installed and enabled: atem-display.service"

# ── 7. Disable TTY1 getty ─────────────────────────────────────────────────────

echo "[7/7] Disabling getty on TTY1 (avoids conflict with DRM output)..."
systemctl disable --now getty@tty1.service 2>/dev/null || true
echo "    Done."

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "========================================"
echo "  Setup complete."
echo "========================================"
echo ""
echo "NEXT STEPS:"
echo ""
echo "  1. Reboot the Pi:"
echo "       sudo reboot"
echo ""
echo "  2. Plug in the ATEM USB cable."
echo ""
echo "  3. Verify the video appears on HDMI and check logs:"
echo "       journalctl -u atem-display -f"
echo ""
echo "  4. If the video device uses a different vendor ID, check:"
echo "       lsusb | grep -i blackmagic"
echo "     Then update ATTRS{idVendor} in /etc/udev/rules.d/99-atem.rules"
echo "     and run: sudo udevadm control --reload-rules"
echo ""
echo "  5. Once confirmed working, enable read-only mode:"
echo "       sudo raspi-config"
echo "       → Performance Options → Overlay File System → Enable"
echo "       → Also write-protect boot partition: Yes"
echo "       → Reboot"
echo ""
echo "  See README.md for full documentation and troubleshooting."
echo ""
