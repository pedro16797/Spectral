from playwright.sync_api import Page, expect, sync_playwright
import os

def verify_themes(page: Page):
  page.goto('http://localhost:8080/')
  page.wait_for_timeout(5000)

  # Try to click settings icon.
  # In the previous screenshot it looked like it was around 1180, 40 (in 1280x720)
  # Let's try to find it more accurately or just click a range.
  page.mouse.click(1180, 40)
  page.wait_for_timeout(2000)

  page.screenshot(path='/home/jules/verification/settings_open.png')

if __name__ == "__main__":
  os.makedirs('/home/jules/verification/video', exist_ok=True)
  with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    # Standard 1280x720
    context = browser.new_context(viewport={'width': 1280, 'height': 720})
    page = context.new_page()
    try:
      verify_themes(page)
    finally:
      context.close()
      browser.close()
