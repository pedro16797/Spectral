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
            page.keyboard.press("Escape")
            page.wait_for_timeout(1000)

            # Screenshot 4: Waterfall Focus Mode
            print("Capturing waterfall focus mode...")
            page.mouse.click(410, 45) # Layers icon in header
            page.wait_for_timeout(2000)
            page.screenshot(path="resources/screenshots/waterfall_focus.png")
            page.mouse.click(410, 45) # Back to normal mode
            page.wait_for_timeout(1000)

            # Screenshot 5: Edge Dial Interaction (Gain)
            print("Capturing edge dial interaction (Gain)...")
            page.mouse.click(60, 740) # Gain trigger (bottom left)
            page.wait_for_timeout(2000)
            page.screenshot(path="resources/screenshots/gain_dial.png")
            page.mouse.click(60, 740) # Hide dial
            page.wait_for_timeout(1000)

            # Screenshot 6: Edge Dial Interaction (Sensitivity)
            print("Capturing edge dial interaction (Sensitivity)...")
            page.mouse.click(390, 740) # Sens trigger (bottom right)
            page.wait_for_timeout(2000)
            page.screenshot(path="resources/screenshots/sens_dial.png")
            page.mouse.click(390, 740) # Hide dial
            page.wait_for_timeout(1000)

            # Screenshot 7: Landscape Mode (side-by-side)
            print("Capturing landscape layout...")
            context_landscape = browser.new_context(viewport={'width': 800, 'height': 450})
            page_ls = context_landscape.new_page()
            page_ls.goto(f"http://localhost:{PORT}/?demo=true", wait_until="networkidle")
            page_ls.wait_for_timeout(5000)
            # In landscape, start capture button is in header or bottom row depending on layout
            # Let's just click the header play button (first action button)
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
