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

DEVICE="/dev/atem_video"
LOG_TAG="atem-display"

logger -t "$LOG_TAG" "Service started" || true

LAST_STATE=""

while true; do
    if [[ ! -e "$DEVICE" ]]; then
        if [[ "$LAST_STATE" != "waiting" ]]; then
            logger -t "$LOG_TAG" "Waiting for $DEVICE — holding HDMI active with black screen" || true
            LAST_STATE="waiting"
        fi

        # Play a synthetic black frame via lavfi to keep the DRM framebuffer open.
        # --length=5 causes mpv to exit after 5 s so the outer loop re-checks the device.
        # No --drm-connector: mpv auto-detects the first connected display.
        # No --drm-mode: uses the display's preferred mode (config.txt forces 1080p60).
        # If mpv fails, sleep 2 s before retrying to avoid a hot spin-loop.
        mpv \
            --no-config \
            --no-osc \
            --no-border \
            --fullscreen \
            --vo=drm \
            --length=5 \
            "av://lavfi:color=c=black:size=1920x1080:rate=5" \
        2>/dev/null || sleep 2
        continue
    fi

    LAST_STATE="running"
    logger -t "$LOG_TAG" "Device found — launching mpv" || true

    mpv \
        --no-config \
        --profile=low-latency \
        --untimed \
        --no-osc \
        --no-border \
        --fullscreen \
        --vo=drm \
        --video-sync=display-resample \
        --cache=no \
        --demuxer-readahead-secs=0 \
        --demuxer-lavf-o=video_size=1920x1080,framerate=30,input_format=mjpeg \
        "av://v4l2:${DEVICE}" \
    || true

    logger -t "$LOG_TAG" "mpv exited — retrying in 2s" || true
    sleep 2
done
