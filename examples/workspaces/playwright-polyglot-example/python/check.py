# Playwright, the Python way. Open a real page, screenshot it, print TITLE|SUM.
import os

from playwright.sync_api import sync_playwright

url = os.environ.get("PAGE_URL", "https://www.python.org/")
shot = os.environ.get("SHOT_PATH", "python.png")

with sync_playwright() as p:
    browser = p.chromium.launch()
    page = browser.new_page(viewport={"width": 1280, "height": 800})
    page.goto(url, wait_until="domcontentloaded", timeout=60000)
    page.wait_for_timeout(3000)
    total = page.evaluate("() => { let s = 0; for (let i = 1; i <= 10; i++) s += i; return s; }")
    title = page.title()
    page.screenshot(path=shot)
    print(f"{title}|{total}")
    browser.close()
