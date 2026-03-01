#!/bin/bash
# atem-display.sh
# Deployed to: /usr/local/bin/atem-display.sh
#
# Monitors /dev/atem_video and runs mpv full-screen via DRM/KMS.
# Loops indefinitely — auto-recovers if mpv crashes or device disconnects.
# Managed by atem-display.service (started/stopped by udev on USB plug/unplug).

set -euo pipefail

DEVICE="/dev/atem_video"
LOG_TAG="atem-display"

logger -t "$LOG_TAG" "Service started"

while true; do
    if [[ ! -e "$DEVICE" ]]; then
        logger -t "$LOG_TAG" "Waiting for $DEVICE..."
        sleep 2
        continue
    fi

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
