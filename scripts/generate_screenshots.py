import os
import time
import subprocess
import http.server
import socketserver
import threading
import json
import base64
from playwright.sync_api import sync_playwright

PORT = 8081
DIRECTORY = "build/web"

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

def serve_forever(httpd):
    try:
        httpd.serve_forever()
    except Exception:
        pass

def generate_screenshots():
    # Start local server
    print(f"Starting server on port {PORT}...")
    socketserver.TCPServer.allow_reuse_address = True
    httpd = socketserver.TCPServer(("", PORT), Handler)

    server_thread = threading.Thread(target=serve_forever, args=(httpd,))
    server_thread.daemon = True
    server_thread.start()
    print(f"Serving at http://localhost:{PORT}")

    # Use Playwright to capture screenshots
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch()
            # Set a mobile-like viewport (450x800)
            context = browser.new_context(viewport={'width': 450, 'height': 800})

            def new_configured_page(settings=None, url_suffix=""):
                page = context.new_page()
                full_url = f"http://localhost:{PORT}/{url_suffix}"

                if settings:
                    # Ensure enums are serialized as strings for the model's fromMap
                    settings_copy = settings.copy()
                    for key, value in settings_copy.items():
                        if hasattr(value, 'name'):
                            settings_copy[key] = value.name

                    # Use settings_b64 URL parameter for more robust state injection
                    settings_json = json.dumps(settings_copy)
                    settings_b64 = base64.b64encode(settings_json.encode()).decode()

                    separator = "&" if "?" in full_url else "?"
                    full_url += f"{separator}settings_b64={settings_b64}"

                page.goto(full_url)
                page.wait_for_timeout(5000)
                return page

            # Default clean settings
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
                "fftSmoothing": 0.0,
                "peakHoldEnabled": False,
                "fftAveragingMode": "none",
                "fftAveragingCount": 5,
                "ppmCorrection": 0.0,
                "showHarmonics": False,
                "showSnr": False
            }

            # Screenshot 1: Home Screen
            print("Capturing home screen...")
            page = new_configured_page(default_settings)
            page.screenshot(path="resources/screenshots/home_screen.png")
            page.close()

            # Screenshot 2: Demo Capturing (Active UI)
            print("Capturing demo capturing screen...")
            page = new_configured_page(default_settings, "?demo=true")
            page.mouse.click(225, 740) # Start Capture
            page.wait_for_timeout(3000)
            page.screenshot(path="resources/screenshots/demo_capturing.png")
            page.close()

            # Screenshot 3: Settings View
            print("Capturing settings view...")
            page = new_configured_page(default_settings)
            page.mouse.click(360, 45) # Settings icon
            page.wait_for_timeout(2000)
            page.screenshot(path="resources/screenshots/settings_view.png")
            page.close()

            # Screenshot 4: SDR Configuration
            print("Capturing SDR configuration settings...")
            sdr_settings = default_settings.copy()
            sdr_settings["signalSource"] = "rf"
            page = new_configured_page(sdr_settings)
            page.wait_for_timeout(2000)
            page.mouse.click(360, 45) # Settings
            page.wait_for_timeout(2000)
            page.screenshot(path="resources/screenshots/sdr_settings.png")
            page.close()

            # Screenshot 5: Waterfall Focus Mode
            print("Capturing waterfall focus mode...")
            page = new_configured_page(default_settings, "?demo=true")
            page.mouse.click(225, 740) # Start Capture
            page.wait_for_timeout(1000)
            page.mouse.click(410, 45) # Toggle Focus ON
            page.wait_for_timeout(2000)
            page.screenshot(path="resources/screenshots/waterfall_focus.png")
            page.close()

            # Screenshot 6: SDR Advanced Analysis
            print("Capturing SDR advanced analysis...")
            adv_settings = default_settings.copy()
            adv_settings.update({
                "signalSource": "rf",
                "peakHoldEnabled": True,
                "showSnr": True,
                "showHarmonics": True,
                "centerFrequency": 98.5,
                "rfBandwidth": 1.0,
                "fftAveragingMode": "exponential"
            })
            page = new_configured_page(adv_settings, "?demo=true")
            page.wait_for_timeout(2000)
            page.mouse.click(225, 740) # Start Capture
            page.wait_for_timeout(3000)
            # Place markers on the FFT chart (middle section)
            # Y coordinate for FFT chart is roughly 400-600 in portrait
            page.mouse.click(100, 500)
            page.mouse.click(225, 450)
            page.mouse.click(350, 550)
            page.wait_for_timeout(1000)
            page.screenshot(path="resources/screenshots/sdr_advanced_analysis.png")
            page.close()

            # Screenshot 7: Edge Dial Interaction (Gain)
            print("Capturing edge dial interaction (Gain)...")
            page = new_configured_page(default_settings, "?demo=true")
            page.mouse.click(225, 740) # Start Capture
            page.wait_for_timeout(1000)
            page.mouse.click(60, 740) # Gain trigger
            page.wait_for_timeout(2000)
            page.screenshot(path="resources/screenshots/gain_dial.png")
            page.close()

            # Screenshot 8: Landscape Mode
            print("Capturing landscape layout...")
            context_ls = browser.new_context(viewport={'width': 800, 'height': 450})
            page_ls = context_ls.new_page()
            page_ls.goto(f"http://localhost:{PORT}/?demo=true")
            page_ls.evaluate("window.localStorage.clear()")
            page_ls.evaluate(f"window.localStorage.setItem('flutter.app_settings', '{json.dumps(default_settings)}')")
            page_ls.reload()
            page_ls.wait_for_timeout(5000)
            page_ls.mouse.click(670, 45) # Start capture in landscape (top right ish)
            page_ls.wait_for_timeout(3000)
            page_ls.screenshot(path="resources/screenshots/landscape_active.png")
            page_ls.close()

            browser.close()
    except Exception as e:
        print(f"Error during screenshot generation: {e}")
    finally:
        httpd.shutdown()
        httpd.server_close()
        print("Server stopped.")

    print("Screenshots generated in resources/screenshots/")

if __name__ == "__main__":
    generate_screenshots()
