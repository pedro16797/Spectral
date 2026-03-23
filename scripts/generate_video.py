import os
import time
import subprocess
import http.server
import socketserver
import threading
import json
import base64
import sys
import shutil
from playwright.sync_api import sync_playwright

PORT = 8082
DIRECTORY = "build/web"

# Video resolutions (width, height)
RESOLUTIONS = {
    "phone": (1242, 2208),
    "tablet": (2732, 2048),
}

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

def serve_forever(httpd):
    try:
        httpd.serve_forever()
    except Exception:
        pass

def generate_videos(output_base_dir="resources/videos"):
    # Start local server
    print(f"Starting server on port {PORT}...")
    socketserver.TCPServer.allow_reuse_address = True
    httpd = socketserver.TCPServer(("", PORT), Handler)

    server_thread = threading.Thread(target=serve_forever, args=(httpd,))
    server_thread.daemon = True
    server_thread.start()
    print(f"Serving at http://localhost:{PORT}")

    SDR_SAMPLE = "resources/samples/rf/fm_multi_signals.iq"

    default_settings = {
        "theme": "frost",
        "signalSource": "rf",
        "rfSource": "mock",
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
        "showSnr": True,
        "demodulationMode": "fm",
        "audioOutputEnabled": True
    }

    try:
        with sync_playwright() as p:
            browser = p.chromium.launch()

            for res_name, (width, height) in RESOLUTIONS.items():
                print(f"Generating video for {res_name} ({width}x{height})...")
                temp_video_dir = f"temp_video_{res_name}"
                os.makedirs(temp_video_dir, exist_ok=True)

                context = browser.new_context(
                    viewport={'width': width, 'height': height},
                    device_scale_factor=1,
                    record_video_dir=temp_video_dir,
                    record_video_size={'width': width, 'height': height}
                )

                page = context.new_page()

                settings_json = json.dumps(default_settings)
                settings_b64 = base64.b64encode(settings_json.encode()).decode()
                full_url = f"http://localhost:{PORT}/?play_file={SDR_SAMPLE}&settings_b64={settings_b64}"

                page.goto(full_url)
                page.wait_for_timeout(10000) # Wait for app to load

                # 1. Start Capture
                print("  Starting capture...")
                capture_toggle = page.get_by_label("Capture Toggle", exact=True).first
                capture_toggle.wait_for(state="visible")
                capture_toggle.click()
                page.wait_for_timeout(3000)

                # 2. Adjust Gain
                print("  Adjusting Gain...")
                gain_trigger = page.get_by_label("GAIN", exact=True)
                gain_trigger.click()
                page.wait_for_timeout(1000)
                # Drag the Gain Dial (left side)
                gain_dial = page.get_by_label("Gain Dial", exact=True)
                gain_dial_box = gain_dial.bounding_box()
                if gain_dial_box:
                    center_x = gain_dial_box["x"] + gain_dial_box["width"] / 2
                    center_y = gain_dial_box["y"] + gain_dial_box["height"] / 2
                    page.mouse.move(center_x, center_y)
                    page.mouse.down()
                    page.mouse.move(center_x, center_y - 200, steps=20)
                    page.mouse.up()
                page.wait_for_timeout(2000)

                # 3. Adjust Sensitivity
                print("  Adjusting Sensitivity...")
                sens_trigger = page.get_by_label("SENS", exact=True)
                sens_trigger.click()
                page.wait_for_timeout(1000)
                # Drag the Sensitivity Dial (right side)
                sens_dial = page.get_by_label("Sensitivity Dial", exact=True)
                sens_dial_box = sens_dial.bounding_box()
                if sens_dial_box:
                    center_x = sens_dial_box["x"] + sens_dial_box["width"] / 2
                    center_y = sens_dial_box["y"] + sens_dial_box["height"] / 2
                    page.mouse.move(center_x, center_y)
                    page.mouse.down()
                    page.mouse.move(center_x, center_y + 200, steps=20)
                    page.mouse.up()
                page.wait_for_timeout(2000)

                # 4. Toggle Waterfall Focus
                print("  Toggling Waterfall Focus...")
                focus_toggle = page.get_by_label("Toggle Focus", exact=True)
                focus_toggle.click()
                page.wait_for_timeout(3000)

                # 5. Tweak Frequency Range
                print("  Tweaking Frequency Range...")
                # Click and drag the frequency slider
                slider = page.get_by_label("Frequency Focus Slider", exact=True)
                slider_box = slider.bounding_box()
                if slider_box:
                    center_x = slider_box["x"] + slider_box["width"] / 2
                    center_y = slider_box["y"] + slider_box["height"] / 2
                    page.mouse.move(center_x, center_y)
                    page.mouse.down()
                    page.mouse.move(center_x + 100, center_y, steps=20)
                    page.mouse.move(center_x - 100, center_y, steps=20)
                    page.mouse.up()
                page.wait_for_timeout(5000)

                context.close()

                # Move recorded video to final destination
                video_path = page.video.path()
                final_dir = os.path.join(output_base_dir, res_name)
                os.makedirs(final_dir, exist_ok=True)
                shutil.move(video_path, os.path.join(final_dir, "app_preview.webm"))
                shutil.rmtree(temp_video_dir)

            browser.close()
    except Exception as e:
        print(f"Error during video generation: {e}")
    finally:
        httpd.shutdown()
        httpd.server_close()
        print("Server stopped.")

if __name__ == "__main__":
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "resources/videos"
    generate_videos(out_dir)
