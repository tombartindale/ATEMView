#!/bin/bash
# build/chroot-setup.sh
#
# Runs inside the ARM64 chroot during the GitHub Actions image build.
# NOT intended to be run manually on a live Pi — use setup.sh for that.
#
# Problem: systemd is not running inside a chroot, so `systemctl start/stop`
# and `udevadm` fail. This script:
#   1. Places a systemctl stub on PATH that handles enable/disable via direct
#      symlink manipulation and silently ignores runtime commands
#   2. Runs the main setup.sh (which installs packages, copies files, etc.)
#   3. Removes the stub and cleans up user state ready for image distribution

set -euo pipefail

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

echo "=== ATEMView chroot build ==="

# ── systemctl stub ─────────────────────────────────────────────────────────────
# Placed at /usr/local/bin/systemctl so it takes precedence over /bin/systemctl.
# apt-get post-install scripts also call systemctl; the stub silences those too.

cat > /usr/local/bin/systemctl << 'STUB'
#!/bin/bash
# systemctl stub for chroot builds — handles enable/disable, ignores runtime ops
ACTION="${1:-help}"
shift || true
SERVICE="${*: -1}"

case "$ACTION" in
    enable)
        SERVICE_FILE="/etc/systemd/system/$SERVICE"
        if [[ ! -f "$SERVICE_FILE" ]]; then
            echo "systemctl stub: $SERVICE_FILE not found, skipping enable"
            exit 0
        fi
        WANTED_BY=$(grep "^WantedBy=" "$SERVICE_FILE" | head -1 | cut -d= -f2 | tr -d ' ')
        if [[ -n "$WANTED_BY" ]]; then
            mkdir -p "/etc/systemd/system/${WANTED_BY}.wants"
            ln -sf "$SERVICE_FILE" "/etc/systemd/system/${WANTED_BY}.wants/$SERVICE"
            echo "systemctl stub: enabled $SERVICE → ${WANTED_BY}.wants/"
        fi
        ;;
    disable)
        find /etc/systemd/system -name "$SERVICE" -type l -delete 2>/dev/null || true
        echo "systemctl stub: disabled $SERVICE"
        ;;
    daemon-reload|is-system-running|start|stop|restart|status|is-active|is-enabled|mask|unmask)
        echo "systemctl stub: $ACTION $SERVICE (no-op in chroot)"
        ;;
    *)
        echo "systemctl stub: unhandled: $ACTION $*" >&2
        ;;
esac
exit 0
STUB
chmod +x /usr/local/bin/systemctl

# ── Run main setup ─────────────────────────────────────────────────────────────

cd /opt/ATEMView
bash setup.sh

# ── Remove stub ────────────────────────────────────────────────────────────────

rm /usr/local/bin/systemctl

# ── Clean up for image distribution ───────────────────────────────────────────
# These items are machine-specific and must be absent so that each Pi that
# boots from this image gets its own fresh identity.

echo "Cleaning up for distribution..."

# apt cache — reduces image size
apt-get clean -qq

# SSH host keys — regenerated automatically on first boot by openssh-server
rm -f /etc/ssh/ssh_host_*

# machine-id — must be empty so systemd generates a unique one per machine.
# /var/lib/dbus/machine-id should be a symlink to /etc/machine-id on Pi OS;
# recreate it in case it was replaced with a regular file.
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id

# Remove the build repo — files are already installed to their final locations
rm -rf /opt/ATEMView

echo "=== Chroot build complete ==="
