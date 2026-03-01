#!/bin/bash
# atem-display.sh
# Deployed to: /usr/local/bin/atem-display.sh
#
# Monitors /dev/atem_video and runs mpv full-screen via DRM/KMS.
# When no device is connected, holds the DRM framebuffer open with a black
# screen so HDMI stays active and the monitor does not lose signal.
# Loops indefinitely — auto-recovers if mpv crashes or device disconnects.
# Managed by atem-display.service (started/stopped by udev on USB plug/unplug).

set -euo pipefail

DEVICE="/dev/atem_video"
LOG_TAG="atem-display"

logger -t "$LOG_TAG" "Service started"

LAST_STATE=""

while true; do
    if [[ ! -e "$DEVICE" ]]; then
        if [[ "$LAST_STATE" != "waiting" ]]; then
            logger -t "$LOG_TAG" "Waiting for $DEVICE — holding HDMI active with black screen"
            LAST_STATE="waiting"
        fi

        # Play a synthetic black frame via lavfi to keep the DRM framebuffer open.
        # --length=5 causes mpv to exit after 5 s so the outer loop re-checks the device.
        mpv \
            --no-config \
            --no-osc \
            --no-border \
            --fullscreen \
            --vo=drm \
            --drm-connector=HDMI-A-1 \
            --drm-mode=1920x1080@60 \
            --length=5 \
            "av://lavfi:color=c=black:size=1920x1080:rate=5" \
        2>/dev/null || true
        continue
    fi

    LAST_STATE="running"
    logger -t "$LOG_TAG" "Device found — launching mpv"

    mpv \
        --no-config \
        --profile=low-latency \
        --untimed \
        --no-osc \
        --no-border \
        --fullscreen \
        --vo=drm \
        --drm-connector=HDMI-A-1 \
        --drm-mode=1920x1080@60 \
        --video-sync=display-resample \
        --cache=no \
        --demuxer-readahead-secs=0 \
        --demuxer-lavf-o=video_size=1920x1080,framerate=30,input_format=mjpeg \
        "av://v4l2:${DEVICE}" \
    || true

    logger -t "$LOG_TAG" "mpv exited — retrying in 2s"
    sleep 2
done
