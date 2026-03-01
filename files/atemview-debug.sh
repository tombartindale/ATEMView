#!/bin/bash
# atemview-debug.sh
# Deployed to: /usr/local/bin/atemview-debug.sh
#
# Runs at boot when /boot/firmware/atemview-debug exists on the SD card.
# Enables a visible console on HDMI for diagnosing boot failures.
#
# How to enable debug mode (from any OS, SD card inserted in a reader):
#   touch /Volumes/<boot-volume>/atemview-debug   # macOS
#   type nul > D:\atemview-debug                   # Windows
#
# How to disable debug mode:
#   Delete /boot/firmware/atemview-debug and reboot

set -euo pipefail

LOG_TAG="atemview-debug"
CMDLINE="/boot/firmware/cmdline.txt"

logger -t "$LOG_TAG" "=================================================="
logger -t "$LOG_TAG" "ATEMView DEBUG MODE ACTIVE"
logger -t "$LOG_TAG" "  Flag:  /boot/firmware/atemview-debug"
logger -t "$LOG_TAG" "  HDMI:  login prompt (video display suspended)"
logger -t "$LOG_TAG" "  SSH:   available as normal"
logger -t "$LOG_TAG" "  To exit: delete the flag file and reboot"
logger -t "$LOG_TAG" "=================================================="

# Raise kernel console log level immediately so messages appear on the TTY
echo 8 > /proc/sys/kernel/printk

# Patch cmdline.txt to remove silent boot flags.
# These take effect on the NEXT boot — a reboot is required for full kernel verbosity.
if [[ -f "$CMDLINE" ]]; then
    CURRENT=$(cat "$CMDLINE")
    PATCHED="$CURRENT"
    for flag in quiet "loglevel=0" "logo.nologo" "vt.global_cursor_default=0"; do
        PATCHED="${PATCHED//$flag/}"
    done
    # Collapse extra spaces left by removals
    PATCHED=$(echo "$PATCHED" | tr -s ' ' | sed 's/^ //; s/ $//')
    if [[ "$PATCHED" != "$CURRENT" ]]; then
        printf '%s\n' "$PATCHED" > "$CMDLINE"
        logger -t "$LOG_TAG" "cmdline.txt patched — reboot for verbose kernel output"
    else
        logger -t "$LOG_TAG" "cmdline.txt already verbose (no quiet flags found)"
    fi
fi

# Start a getty on TTY1 so HDMI shows a login prompt.
# atem-display.service is inhibited via ConditionPathExists, so TTY1 is free.
systemctl start getty@tty1.service

logger -t "$LOG_TAG" "Getty started on TTY1 — HDMI console ready"
