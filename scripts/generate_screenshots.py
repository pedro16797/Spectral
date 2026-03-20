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
            page = context.new_page()

            # Screenshot 1: Home Screen
            print("Capturing home screen...")
            page.goto(f"http://localhost:{PORT}", wait_until="networkidle")
            page.wait_for_timeout(5000)
            page.screenshot(path="resources/screenshots/home_screen.png")

            # Screenshot 2: Demo Capturing (Active UI)
            print("Capturing demo capturing screen...")
            page.goto(f"http://localhost:{PORT}/?demo=true", wait_until="networkidle")
            page.wait_for_timeout(5000)
            print("Clicking Start Capture...")
            page.mouse.click(225, 740) # Center Capture button
            page.wait_for_timeout(3000)
            page.screenshot(path="resources/screenshots/demo_capturing.png")

            # Screenshot 3: Settings View
            print("Capturing settings view...")
            page.mouse.click(360, 45) # Settings icon
            page.wait_for_timeout(2000)
            page.screenshot(path="resources/screenshots/settings_view.png")

            # Screenshot 4: SDR Configuration (RF mode)
            print("Capturing SDR configuration settings...")
            # Open Mode dropdown
            page.mouse.click(225, 230)
            page.wait_for_timeout(1000)
            # Find the option (try to click exactly where it should appear)
            # dropdown options usually appear in a popup or overlay.
            # In Flutter Web, they might be rendered in the same canvas.
            # Let's try to click below the dropdown
            page.mouse.click(225, 280)
            page.wait_for_timeout(2000)
            page.screenshot(path="resources/screenshots/sdr_settings.png")

            page.keyboard.press("Escape")
            page.wait_for_timeout(1000)

            # Screenshot 5: Waterfall Focus Mode
            print("Capturing waterfall focus mode...")
            page.mouse.click(410, 45) # Layers icon
            page.wait_for_timeout(2000)
            page.screenshot(path="resources/screenshots/waterfall_focus.png")
            page.mouse.click(410, 45) # Back to normal
            page.wait_for_timeout(1000)

            # Screenshot 6: SDR Advanced Analysis
            print("Capturing SDR advanced analysis...")
            # Try to place markers even if we failed to switch to SDR (it will just show audio markers)
            page.mouse.click(300, 500)
            page.wait_for_timeout(200)
            page.mouse.click(150, 500)
            page.wait_for_timeout(1000)
            page.screenshot(path="resources/screenshots/sdr_advanced_analysis.png")

            # Screenshot 7: Edge Dial Interaction (Gain)
            print("Capturing edge dial interaction (Gain)...")
            page.mouse.click(60, 740) # Gain trigger
            page.wait_for_timeout(2000)
            page.screenshot(path="resources/screenshots/gain_dial.png")
            page.mouse.click(60, 740)
            page.wait_for_timeout(1000)

            # Screenshot 8: Landscape Mode
            print("Capturing landscape layout...")
            context_landscape = browser.new_context(viewport={'width': 800, 'height': 450})
            page_ls = context_landscape.new_page()
            page_ls.goto(f"http://localhost:{PORT}/?demo=true", wait_until="networkidle")
            page_ls.wait_for_timeout(5000)
            # Start capture in landscape (Header button)
            page_ls.mouse.click(670, 45)
            page_ls.wait_for_timeout(3000)
            page_ls.screenshot(path="resources/screenshots/landscape_active.png")

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
