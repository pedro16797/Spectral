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

            def new_clean_page(url_suffix=""):
                page = context.new_page()
                page.goto(f"http://localhost:{PORT}/{url_suffix}")
                # Clear localStorage to ensure fresh settings
                page.evaluate("window.localStorage.clear()")
                page.reload()
                page.wait_for_timeout(5000)
                return page

            # Screenshot 1: Home Screen
            print("Capturing home screen...")
            page = new_clean_page()
            page.screenshot(path="resources/screenshots/home_screen.png")
            page.close()

            # Screenshot 2: Demo Capturing (Active UI)
            print("Capturing demo capturing screen...")
            page = new_clean_page("?demo=true")
            page.mouse.click(225, 740) # Start Capture
            page.wait_for_timeout(3000)
            page.screenshot(path="resources/screenshots/demo_capturing.png")
            page.close()

            # Screenshot 3: Settings View
            print("Capturing settings view...")
            page = new_clean_page()
            page.mouse.click(360, 45) # Settings icon
            page.wait_for_timeout(2000)
            page.screenshot(path="resources/screenshots/settings_view.png")
            page.close()

            # Screenshot 4: SDR Configuration
            print("Capturing SDR configuration settings...")
            page = new_clean_page()
            page.mouse.click(360, 45) # Settings
            page.wait_for_timeout(1000)
            # Click Mode dropdown (Section 1)
            page.mouse.click(225, 230)
            page.wait_for_timeout(500)
            # Select SDR
            page.keyboard.press("ArrowDown")
            page.keyboard.press("Enter")
            page.wait_for_timeout(2000)
            page.screenshot(path="resources/screenshots/sdr_settings.png")
            page.close()

            # Screenshot 5: Waterfall Focus Mode
            print("Capturing waterfall focus mode...")
            page = new_clean_page("?demo=true")
            page.mouse.click(225, 740) # Start Capture
            page.wait_for_timeout(1000)
            page.mouse.click(410, 45) # Toggle Focus ON
            page.wait_for_timeout(2000)
            page.screenshot(path="resources/screenshots/waterfall_focus.png")
            page.close()

            # Screenshot 6: SDR Advanced Analysis
            print("Capturing SDR advanced analysis...")
            page = new_clean_page("?demo=true")
            # Switch to SDR first
            page.mouse.click(360, 45) # Settings
            page.wait_for_timeout(500)
            page.mouse.click(225, 230) # Mode
            page.wait_for_timeout(200)
            page.keyboard.press("ArrowDown")
            page.keyboard.press("Enter")
            page.wait_for_timeout(500)
            # Enable Peak Hold and SNR (using direct coordinates to avoid dropdown/semantics issues if any)
            # Peak Hold is roughly at y=600 if we scrolled, or lower down.
            # Let's try to find text and click its center
            try:
                page.get_by_text("Peak Hold").click()
                page.wait_for_timeout(200)
                page.get_by_text("Show SNR Overlay").click()
            except:
                # Fallback to clicks if text locators fail
                page.mouse.click(400, 600) # Toggle 1
                page.mouse.click(400, 650) # Toggle 2

            page.wait_for_timeout(500)
            page.keyboard.press("Escape")
            page.wait_for_timeout(1000)
            page.mouse.click(225, 740) # Start Capture
            page.wait_for_timeout(2000)
            # Place markers
            page.mouse.click(100, 500)
            page.mouse.click(200, 500)
            page.mouse.click(350, 500)
            page.wait_for_timeout(1000)
            page.screenshot(path="resources/screenshots/sdr_advanced_analysis.png")
            page.close()

            # Screenshot 7: Edge Dial Interaction (Gain)
            print("Capturing edge dial interaction (Gain)...")
            page = new_clean_page("?demo=true")
            page.mouse.click(225, 740) # Start Capture
            page.wait_for_timeout(500)
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
            page_ls.reload()
            page_ls.wait_for_timeout(5000)
            page_ls.mouse.click(670, 45) # Start capture in landscape
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
