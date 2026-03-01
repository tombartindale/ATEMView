#!/usr/bin/env python3
# atem-status.py
# Deployed to: /usr/local/bin/atem-status.py
#
# Lightweight HTTP status page for diagnosing ATEMView.
# Runs as a systemd service (atem-status.service) on port 80.
# Access from any browser on the same network: http://atemview.local

import http.server
import subprocess
import html
import os
import socket
from datetime import datetime

PORT = 80
REFRESH_SECONDS = 5


def run(cmd):
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=5
        )
        return (result.stdout + result.stderr).strip()
    except Exception as e:
        return f"(error: {e})"


def atem_plugged_in():
    return os.path.exists("/dev/atem_video")


def get_ip_addresses():
    try:
        result = subprocess.run(
            ["hostname", "-I"], capture_output=True, text=True, timeout=3
        )
        return result.stdout.strip()
    except Exception:
        return "unknown"


def build_page():
    plugged = atem_plugged_in()
    status_colour = "#2a2" if plugged else "#a22"
    status_text = "CONNECTED" if plugged else "NOT CONNECTED"

    service_out = run(["systemctl", "status", "atem-display", "--no-pager", "-l"])
    usb_out = run(["lsusb"])
    v4l_out = run(["v4l2-ctl", "--list-devices"])
    log_out = run(["journalctl", "-u", "atem-display", "-n", "40", "--no-pager",
                   "--output=short-precise"])
    uptime_out = run(["uptime", "-p"])
    ip_out = get_ip_addresses()
    hostname = socket.gethostname()
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    def section(title, content, mono=True):
        tag = "pre" if mono else "p"
        return (
            f'<h2>{html.escape(title)}</h2>'
            f'<{tag}>{html.escape(content)}</{tag}>'
        )

    body = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta http-equiv="refresh" content="{REFRESH_SECONDS}">
  <title>ATEMView — {html.escape(hostname)}</title>
  <style>
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{ font-family: monospace; background: #111; color: #ddd;
            padding: 24px; max-width: 900px; margin: 0 auto; }}
    h1 {{ color: #fff; font-size: 1.4em; margin-bottom: 4px; }}
    .meta {{ color: #666; font-size: 0.85em; margin-bottom: 20px; }}
    .badge {{ display: inline-block; padding: 6px 14px; border-radius: 4px;
              font-weight: bold; font-size: 1em;
              background: {status_colour}; color: #fff; margin-bottom: 24px; }}
    h2 {{ color: #4af; font-size: 0.95em; text-transform: uppercase;
          letter-spacing: 0.05em; margin: 20px 0 6px; }}
    pre {{ background: #1a1a1a; border: 1px solid #333; border-radius: 4px;
           padding: 12px; overflow-x: auto; font-size: 0.82em;
           white-space: pre-wrap; word-break: break-all; line-height: 1.5; }}
    footer {{ margin-top: 30px; color: #444; font-size: 0.8em; }}
  </style>
</head>
<body>
  <h1>ATEMView Status — {html.escape(hostname)}</h1>
  <div class="meta">{html.escape(now)} &nbsp;·&nbsp; {html.escape(ip_out)} &nbsp;·&nbsp; {html.escape(uptime_out)}</div>
  <div class="badge">ATEM: {status_text}</div>
  {section("Display service", service_out)}
  {section("USB devices", usb_out)}
  {section("Video (V4L2) devices", v4l_out)}
  {section("Recent logs (atem-display)", log_out)}
  <footer>Refreshes every {REFRESH_SECONDS}s &nbsp;·&nbsp; ATEMView</footer>
</body>
</html>"""
    return body.encode("utf-8")


class StatusHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = build_page()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass  # Suppress per-request access logs


if __name__ == "__main__":
    server = http.server.HTTPServer(("0.0.0.0", PORT), StatusHandler)
    print(f"ATEMView status server listening on port {PORT}")
    server.serve_forever()
