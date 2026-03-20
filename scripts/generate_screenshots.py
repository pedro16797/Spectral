import os
import time
import subprocess
import http.server
import socketserver
import threading
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
    # 2. Start local server
    print(f"Starting server on port {PORT}...")
    socketserver.TCPServer.allow_reuse_address = True
    httpd = socketserver.TCPServer(("", PORT), Handler)

    server_thread = threading.Thread(target=serve_forever, args=(httpd,))
    server_thread.daemon = True
    server_thread.start()
    print(f"Serving at http://localhost:{PORT}")

    # 3. Use Playwright to capture screenshots
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch()
            # Set a mobile-like viewport for better app screenshots
            # Using 450x800 for portrait (iPhone-like)
            context = browser.new_context(viewport={'width': 450, 'height': 800})
            page = context.new_page()

            # Screenshot 1: Home Screen
            print("Capturing home screen...")
            page.goto(f"http://localhost:{PORT}", wait_until="networkidle")
            page.wait_for_timeout(5000) # Give more time for Flutter to render
            page.screenshot(path="resources/screenshots/home_screen.png")

            # Screenshot 2: Demo Capturing (Active UI)
            print("Capturing demo capturing screen...")
            page.goto(f"http://localhost:{PORT}/?demo=true", wait_until="networkidle")
            page.wait_for_timeout(5000)
            print("Clicking Start Capture...")
            page.mouse.click(225, 740) # Center Capture button in portrait
            page.wait_for_timeout(3000)
            page.screenshot(path="resources/screenshots/demo_capturing.png")

            # Screenshot 3: Settings View
            print("Capturing settings view...")
            page.mouse.click(360, 45) # Tune icon (settings) in header
            page.wait_for_timeout(2000)
            page.screenshot(path="resources/screenshots/settings_view.png")

            # Screenshot 4: SDR Configuration (RF mode)
            print("Capturing SDR configuration settings...")
            # Click Signal Source dropdown (Section 1)
            # Based on layout, it's roughly near the top
            page.mouse.click(225, 230)
            page.wait_for_timeout(500)
            page.get_by_role("option", name="SDR (RF Support)").click()
            page.wait_for_timeout(1000)
            page.screenshot(path="resources/screenshots/sdr_settings.png")

            page.keyboard.press("Escape")
            page.wait_for_timeout(1000)

            # Screenshot 5: Waterfall Focus Mode
            print("Capturing waterfall focus mode...")
            page.mouse.click(410, 45) # Layers icon in header
            page.wait_for_timeout(2000)
            page.screenshot(path="resources/screenshots/waterfall_focus.png")
            page.mouse.click(410, 45) # Back to normal mode
            page.wait_for_timeout(1000)

            # Screenshot 6: SDR Advanced Analysis
            print("Capturing SDR advanced analysis...")
            # Settings already set to SDR from previous step
            # Enable Peak Hold and Markers
            page.mouse.click(360, 45) # Settings
            page.wait_for_timeout(1000)
            # Toggle Peak Hold (should be visible now)
            page.get_by_label("Peak Hold").click()
            page.wait_for_timeout(500)
            page.keyboard.press("Escape")
            page.wait_for_timeout(1000)
            # Click on FFT to place markers
            page.mouse.click(300, 500) # Marker 1
            page.wait_for_timeout(200)
            page.mouse.click(150, 500) # Marker 2
            page.wait_for_timeout(1000)
            page.screenshot(path="resources/screenshots/sdr_advanced_analysis.png")

            # Screenshot 7: Edge Dial Interaction (Gain)
            print("Capturing edge dial interaction (Gain)...")
            page.mouse.click(60, 740) # Gain trigger (bottom left)
            page.wait_for_timeout(2000)
            page.screenshot(path="resources/screenshots/gain_dial.png")
            page.mouse.click(60, 740) # Hide dial
            page.wait_for_timeout(1000)

            # Screenshot 8: Landscape Mode (side-by-side)
            print("Capturing landscape layout...")
            context_landscape = browser.new_context(viewport={'width': 800, 'height': 450})
            page_ls = context_landscape.new_page()
            page_ls.goto(f"http://localhost:{PORT}/?demo=true", wait_until="networkidle")
            page_ls.wait_for_timeout(5000)
            page_ls.mouse.click(670, 45) # Header Play/Stop
            page_ls.wait_for_timeout(3000)
            page_ls.screenshot(path="resources/screenshots/landscape_active.png")

            browser.close()
    except Exception as e:
        print(f"Error during screenshot generation: {e}")
    finally:
        # 4. Stop server
        httpd.shutdown()
        httpd.server_close()
        print("Server stopped.")

    print("Screenshots generated in resources/screenshots/")

if __name__ == "__main__":
    generate_screenshots()
