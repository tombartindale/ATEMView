#!/bin/bash
# atem-display.sh
# Deployed to: /usr/local/bin/atem-display.sh
#
# Monitors /dev/atem_video and runs mpv full-screen via DRM/KMS.
# When no device is connected, holds the DRM framebuffer open with a black
# screen so HDMI stays active and the monitor does not lose signal.
# Loops indefinitely — auto-recovers if mpv crashes or device disconnects.
# Managed by atem-display.service (started/stopped by udev on USB plug/unplug).

# Note: no set -e — this script is a long-running daemon loop and must not
# exit on any individual command failure. All error handling is explicit.
set -uo pipefail

LOG_TAG="atem-display"
DEVICE="/dev/atem_video"

logger -t "$LOG_TAG" "Service started" || true

# ── Find the DRM display card ─────────────────────────────────────────────────
# On Pi 4 with vc4-kms-v3d, card0 is V3D (render-only, no connectors) and
# card1 is vc4 (display, HDMI-A-1 / HDMI-A-2). Detect by looking for HDMI
# connector entries in sysfs rather than hardcoding the card number.
DRM_DEVICE=""
for card in /dev/dri/card*; do
    card_name="${card##*/}"
    if ls /sys/class/drm/"${card_name}"-HDMI-A-* 2>/dev/null | grep -q .; then
        DRM_DEVICE="$card"
        break
    fi
done
if [[ -z "$DRM_DEVICE" ]]; then
    logger -t "$LOG_TAG" "Warning: no card with HDMI connectors found, falling back to /dev/dri/card1" || true
    DRM_DEVICE="/dev/dri/card1"
fi
DRM_CARD="${DRM_DEVICE##*/}"
logger -t "$LOG_TAG" "Using DRM device: $DRM_DEVICE" || true

# ── Force HDMI connectors on ──────────────────────────────────────────────────
# The vc4 KMS driver reads HPD (hotplug detect) directly from hardware. If the
# monitor de-asserts HPD (e.g. during power-save / no-signal timeout), the
# driver reports the connector as 'disconnected' and mpv refuses to output.
# Writing 'on' to the DRM connector's sysfs 'force' file overrides the HPD
# state and tells the kernel to treat the connector as always connected.
for force_file in /sys/class/drm/"${DRM_CARD}"-HDMI-A-*/force; do
    echo "on" > "$force_file" 2>/dev/null || true
done

LAST_STATE=""

while true; do
    if [[ ! -e "$DEVICE" ]]; then
        if [[ "$LAST_STATE" != "waiting" ]]; then
            logger -t "$LOG_TAG" "Waiting for $DEVICE — holding HDMI active with black screen" || true
            LAST_STATE="waiting"
        fi

        # Play a synthetic black frame via lavfi to keep the DRM framebuffer open.
        # --length=5 causes mpv to exit after 5 s so the outer loop re-checks the device.
        # If mpv fails, sleep 2 s before retrying to avoid a hot spin-loop.
        mpv \
            --no-config \
            --no-osc --no-border --fullscreen \
            --vo=drm \
            --drm-device="$DRM_DEVICE" \
            --length=5 \
            "av://lavfi:color=c=black:size=1920x1080:rate=5" \
        2>/dev/null || sleep 2
        continue
    fi

    LAST_STATE="running"
    logger -t "$LOG_TAG" "Device found — launching mpv" || true

    mpv \
        --no-config --profile=low-latency --untimed \
        --no-osc --no-border --fullscreen \
        --vo=drm \
        --drm-device="$DRM_DEVICE" \
        --video-sync=display-resample \
        --cache=no \
        --demuxer-readahead-secs=0 \
        "av://v4l2:${DEVICE}" \
    || true

    logger -t "$LOG_TAG" "mpv exited — retrying in 2s" || true
    sleep 2
done
