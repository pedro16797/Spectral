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
            context = browser.new_context(viewport={'width': 450, 'height': 800})
            page = context.new_page()

            # Screenshot 1: Home Screen
            print("Capturing home screen...")
            page.goto(f"http://localhost:{PORT}", wait_until="networkidle")
            page.wait_for_timeout(10000) # Give more time for Flutter to render
            page.screenshot(path="resources/screenshots/home_screen.png")

            # Screenshot 2: Demo Capturing
            print("Capturing demo capturing screen...")
            page.goto(f"http://localhost:{PORT}/?demo=true", wait_until="networkidle")
            page.wait_for_timeout(10000)

            print("Clicking Start Capture...")
            # Click center (Spectral Core)
            page.mouse.click(225, 400)

            print("Capturing active waveform...")
            # Wait longer for data generation and rendering
            page.wait_for_timeout(5000)
            page.screenshot(path="resources/screenshots/demo_capturing.png")

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
