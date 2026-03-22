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
        "showSnr": False
    }

    try:
        with sync_playwright() as p:
            browser = p.chromium.launch()

            for res_name, (width, height) in RESOLUTIONS.items():
                print(f"Generating screenshots for {res_name} ({width}x{height})...")
                res_dir = os.path.join(output_base_dir, res_name)
                os.makedirs(res_dir, exist_ok=True)

                context = browser.new_context(viewport={'width': width, 'height': height}, device_scale_factor=1)

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

                    for cx, cy in clicks:
                        # Scale clicks based on resolution (relative to 450x800 for mobile, or landscape equivalent)
                        # This is a simplification; for complex interaction we'd need better logic
                        # But for screenshots, we'll keep it simple
                        page.mouse.click(cx * width / 450 if width < height else cx * width / 800,
                                         cy * height / 800 if width < height else cy * height / 450)
                        page.wait_for_timeout(1000)

                    page.screenshot(path=os.path.join(res_dir, f"{name}.png"))
                    page.close()

                # 1. Home
                capture_state("01_home", default_settings)

                # 2. Active Audio
                capture_state("02_audio_active", default_settings, f"?play_file={SINE_SAMPLE}", [(225, 740)])

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
                capture_state("03_sdr_advanced", adv_settings, f"?play_file={SDR_SAMPLE}", [(225, 740)])

                # 4. Settings
                capture_state("04_settings", default_settings, "", [(360, 45)])

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
