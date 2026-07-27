"""Regenerates the store/doc screenshots from a live web build.

Prerequisites, all of which are easy to miss:

* ``flutter build web --release --no-web-resources-cdn`` — without the flag the
  bootstrap fetches CanvasKit from gstatic, and on a machine without that
  access the app never starts and every capture is blank white.
* ``resources/samples/`` must be bundled for the ``play_file`` scenes to show a
  live capture. They are deliberately excluded from ``pubspec.yaml`` to keep
  production builds small, so add them back temporarily:

      flutter:
        assets:
          - resources/locales/
          - resources/samples/audio/
          - resources/samples/rf/

  Rebuild, capture, then revert. Without this the app loads but sits at
  SIGNAL IDLE, because the asset it was asked to play does not exist.
* Optional env vars: ``PLAYWRIGHT_CHROMIUM_PATH`` to use a preinstalled browser
  and ``SCREENSHOT_FALLBACK_FONT`` to serve Roboto locally when fonts.gstatic
  is unreachable (otherwise the UI renders with no text at all).
"""

import os
import time
import subprocess
import http.server
import socketserver
import threading
import json
import base64
import sys
from playwright.sync_api import sync_playwright

PORT = 8081
DIRECTORY = "build/web"

# Screenshot resolutions (width, height)
RESOLUTIONS = {
    "phone": (1242, 2208),       # 5.5" Display (Standard for App Store/Play Store)
    "phone_modern": (1290, 2796), # 6.7" Display (Modern iPhone Max/Android Large)
    "tablet_landscape": (2732, 2048), # 12.9" iPad Pro (Landscape)
    "tablet_portrait": (2048, 2732),  # 12.9" iPad Pro (Portrait)
}

# CSS width each layout is composed at, before the device pixel ratio scales it
# up to the store resolution.
#
# Store resolutions must not be used as the viewport directly: a 1242px-wide
# viewport is a 1242px-wide *layout*, so the app lays out as if on a huge
# screen — dials and cards reflow, text stays tiny, and interaction
# coordinates no longer line up. Composing at phone-like CSS dimensions and
# scaling with device_scale_factor gives the real phone layout at store
# resolution, and lets click coordinates stay in one stable space.
LAYOUT_WIDTHS = {
    "phone": 450,
    "phone_modern": 450,
    "tablet_landscape": 1024,
    "tablet_portrait": 768,
}

# Coordinates below are expressed in this space, whatever the output size.
CLICK_SPACE = (450, 800)


def _resize_exact(path, size):
    """Nudge a capture to the exact store resolution.

    device_scale_factor cannot always hit the target exactly (the CSS size has
    to be a whole number), so the result can land a pixel or two out.
    """
    try:
        from PIL import Image
    except ImportError:
        return
    with Image.open(path) as img:
        if img.size == tuple(size):
            return
        img.resize(tuple(size), Image.LANCZOS).save(path)

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

def serve_forever(httpd):
    try:
        httpd.serve_forever()
    except Exception:
        pass

def generate_screenshots(output_base_dir="resources/screenshots"):
    # Start local server
    print(f"Starting server on port {PORT}...")
    socketserver.TCPServer.allow_reuse_address = True
    httpd = socketserver.TCPServer(("", PORT), Handler)

    server_thread = threading.Thread(target=serve_forever, args=(httpd,))
    server_thread.daemon = True
    server_thread.start()
    print(f"Serving at http://localhost:{PORT}")

    # Sample paths
    SINE_SAMPLE = "resources/samples/audio/sine_440_880.wav"
    SDR_SAMPLE = "resources/samples/rf/fm_multi_signals.iq"

    # Default settings
    default_settings = {
        "theme": "frost",
        "signalSource": "audio",
        "rfSource": "mock",
        "rtlTcpHost": "127.0.0.1",
        "rtlTcpPort": 1234,
        "centerFrequency": 100.0,
        "rfBandwidth": 2.0,
        "fftWindowSize": 1024,
        "fftWindowType": "hanning",
        "language": "en",
        "frequencySkew": 1.0,
        "peakHoldEnabled": False,
        "fftAveragingMode": "none",
        "fftAveragingCount": 5,
        "ppmCorrection": 0.0,
        "showHarmonics": False,
        "showSnr": False,
        "demodulationMode": "none",
        "audioOutputEnabled": False,
        "spectrumView": "rf",
    }

    try:
        with sync_playwright() as p:
            # Sandboxes and CI images often ship a Chromium that does not match
            # the pinned Playwright revision. Point at it explicitly rather
            # than downloading a second copy.
            chromium_path = os.environ.get("PLAYWRIGHT_CHROMIUM_PATH")
            # SwiftShader: with the default GPU path a headless capture of a
            # CanvasKit surface comes back blank even though the app is running.
            launch_args = {"args": [
                "--no-sandbox",
                "--disable-dev-shm-usage",
                "--use-gl=swiftshader",
                "--enable-unsafe-swiftshader",
            ]}
            if chromium_path:
                launch_args["executable_path"] = chromium_path
            browser = p.chromium.launch(**launch_args)

            for res_name, (width, height) in RESOLUTIONS.items():
                print(f"Generating screenshots for {res_name} ({width}x{height})...")
                res_dir = os.path.join(output_base_dir, res_name)
                os.makedirs(res_dir, exist_ok=True)

                # Compose at phone/tablet CSS dimensions, then scale up.
                css_width = LAYOUT_WIDTHS[res_name]
                scale = width / css_width
                css_height = max(1, round(height / scale))
                context = browser.new_context(
                    viewport={'width': css_width, 'height': css_height},
                    device_scale_factor=scale,
                )

                # Flutter fetches Roboto from fonts.gstatic.com. If that is
                # blocked the UI renders with no text whatsoever, which is easy
                # to mistake for a layout bug.
                fallback_font = os.environ.get("SCREENSHOT_FALLBACK_FONT")
                if fallback_font and os.path.exists(fallback_font):
                    context.route(
                        "**/fonts.gstatic.com/**",
                        lambda route: route.fulfill(path=fallback_font, content_type="font/ttf"),
                    )

                def capture_state(name, settings, url_suffix="", clicks=[]):
                    page = context.new_page()

                    settings_copy = settings.copy()
                    for key, value in settings_copy.items():
                        if hasattr(value, 'name'):
                            settings_copy[key] = value.name
                    settings_json = json.dumps(settings_copy)
                    settings_b64 = base64.b64encode(settings_json.encode()).decode()

                    full_url = f"http://localhost:{PORT}/{url_suffix}"
                    separator = "&" if "?" in full_url else "?"
                    full_url += f"{separator}settings_b64={settings_b64}"

                    page.goto(full_url)
                    page.wait_for_timeout(5000)

                    # Clicks are given in CLICK_SPACE and mapped onto the CSS
                    # viewport, which is the same layout at every resolution.
                    for cx, cy in clicks:
                        page.mouse.click(
                            cx * css_width / CLICK_SPACE[0],
                            cy * css_height / CLICK_SPACE[1],
                        )
                        page.wait_for_timeout(1500)

                    out_path = os.path.join(res_dir, f"{name}.png")
                    page.screenshot(path=out_path)
                    page.close()
                    _resize_exact(out_path, (width, height))

                # 1. Home
                capture_state("01_home", default_settings)

                # 2. Active Audio
                capture_state("02_audio_active", default_settings, f"?play_file={SINE_SAMPLE}", [(225, 757)])

                # 3. SDR Advanced
                adv_settings = default_settings.copy()
                adv_settings.update({
                    "signalSource": "rf",
                    "peakHoldEnabled": True,
                    "showSnr": True,
                    "centerFrequency": 100.0,
                    "rfBandwidth": 2.0,
                    "fftAveragingMode": "exponential"
                })
                capture_state("03_sdr_advanced", adv_settings, f"?play_file={SDR_SAMPLE}", [(225, 757)])

                # 4. Settings
                capture_state("04_settings", default_settings, "", [(360, 45)])

                # 5. Tuned FM channel: the waterfall shows the whole captured
                # band while audio is demodulated from the selected slice.
                tuned_settings = default_settings.copy()
                tuned_settings.update({
                    "signalSource": "rf",
                    "centerFrequency": 100.0,
                    "rfBandwidth": 2.0,
                    "demodulationMode": "fm",
                    "audioOutputEnabled": True,
                    "spectrumView": "rf",
                })
                capture_state("05_sdr_tuned_rf", tuned_settings,
                              f"?play_file={SDR_SAMPLE}", [(225, 757)])

                # 6. The same capture with the header toggle flipped, so the
                # analysis chain describes the demodulated audio instead.
                demod_settings = tuned_settings.copy()
                demod_settings.update({
                    "spectrumView": "demodulated",
                    "showSnr": True,
                    "showHarmonics": True,
                })
                capture_state("06_sdr_demodulated", demod_settings,
                              f"?play_file={SDR_SAMPLE}", [(225, 757)])

                # 7. SDR settings, including the driver status panel. The
                # settings button keeps its position when the spectrum-view
                # toggle appears, since the toggle is inserted to its left.
                sdr_settings = default_settings.copy()
                sdr_settings.update({
                    "signalSource": "rf",
                    "rfSource": "integrated",
                    "demodulationMode": "fm",
                })
                capture_state("07_sdr_settings", sdr_settings, "", [(360, 45)])

            browser.close()
    except Exception as e:
        print(f"Error during screenshot generation: {e}")
    finally:
        httpd.shutdown()
        httpd.server_close()
        print("Server stopped.")

if __name__ == "__main__":
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "resources/screenshots"
    generate_screenshots(out_dir)
