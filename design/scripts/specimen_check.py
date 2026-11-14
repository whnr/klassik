#!/usr/bin/env python3
"""Opens every specimen page in headless Chromium, in each room, contrast mode and accent, and fails on a script error.

Usage: uv run --with playwright==1.64.1 design/scripts/specimen_check.py
(once: uv run --with playwright==1.64.1 playwright install chromium)
It also fails when a page draws nothing, the timeline is missing or a tapped movement row does not open.
It checks the player overlay of ADR 0014: its three poses, the tab bar and the pill above it,
a tap on the cover that opens it, and a tap on another tab that closes it.
It cannot judge looks or Safari.
"""

import functools
import http.server
import sys
import threading
from pathlib import Path

from playwright.sync_api import sync_playwright

DESIGN = Path(__file__).resolve().parents[1]
PAGES = (
    "index.html",
    "work.html",
    "player.html",
    "player.html?album=3Is4qK0IBSlUYtEHMhh8YH",
    "chronology.html",
    "chronology.html?level=overview",
    "search.html",
    "person.html?name=Ludwig%20van%20Beethoven",
    "person.html?name=Karl%20B%C3%B6hm",
    "tokens.html",
    "settings.html",
    "index.html?overlay=opening",
    "work.html?overlay=open",
    "chronology.html?overlay=closing",
)
# Each mode: room, contrast, accent, player look, what plays, timeline edge.
MODES = (
    ("light", "normal", "claret", "room", "passion", "right"),
    ("dark", "high", "green", "hall", "sonatas", "left"),
    ("dark", "normal", "plum", "room", "album", "right"),
    ("light", "high", "claret", "hall", "recording", "left"),
)


def serve():
    handler = functools.partial(QuietHandler, directory=str(DESIGN))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format, *args):  # noqa: A002 - the base class names it format
        del format, args


def check_overlay(page, where, failures):
    """Dismissal restores the page under the player and each tab's last page."""
    before = page.locator(".edge-pill").bounding_box()
    url = page.url

    def open_player():
        page.locator(".edge-pill .cover-link").tap()
        page.wait_for_timeout(900)

    open_player()
    overlay = page.locator(".player-overlay")
    if not overlay.count():
        failures.append(f"{where}: a tap on the cover did not open the player overlay")
        return
    if not page.locator(".edge-pill .cover-link").count():
        failures.append(f"{where}: the pill lost its cover while the player is open")
    if page.locator(".edge-pill").bounding_box() != before:
        failures.append(f"{where}: opening the player moved the pill")
    bounds = overlay.bounding_box()
    if bounds != {"x": 0, "y": 0, "width": 393, "height": 852}:
        failures.append(f"{where}: the overlay does not fill the display: {bounds}")
    if not page.frame_locator(".player-overlay iframe").locator(".is-player .hero").count():
        failures.append(f"{where}: the overlay shows no player")
    grab = page.locator(".player-overlay .grab").bounding_box()
    page.mouse.move(grab["x"] + grab["width"] / 2, grab["y"] + grab["height"] - 8)
    page.mouse.down()
    page.mouse.move(190, 500, steps=10)
    page.mouse.up()
    page.wait_for_timeout(900)
    if overlay.count() or page.url != url:
        failures.append(f"{where}: sliding down did not restore the underlying page")
    open_player()
    page.locator(".tabs a.on, .tab-search.on").tap()
    page.wait_for_timeout(900)
    if overlay.count() or page.url != url:
        failures.append(f"{where}: the underlying tab did not keep its page")
    base = url.split("/specimen/")[0] + "/specimen/"
    for place in ("library", "chronology", "search"):
        destination = base + f"person.html?name=Karl%20B%C3%B6hm&place={place}"
        page.evaluate(
            "([place, url]) => sessionStorage.setItem('specimen.stack.' + place, JSON.stringify(url))",
            [place, destination],
        )
        current = page.locator(".tabs a.on, .tab-search.on").get_attribute("aria-label").lower()
        open_player()
        page.locator(f".tabbar a[aria-label='{place.title()}']").tap()
        page.wait_for_timeout(1500)
        if place == current:
            if page.url != url:
                failures.append(f"{where}: {place} reset its underlying page")
        elif "person.html" not in page.url or f"place={place}" not in page.url:
            failures.append(f"{where}: {place} did not restore its last page")
        url = page.url


def main():
    server = serve()
    base = f"http://127.0.0.1:{server.server_address[1]}/specimen/"
    failures, runs = [], 0
    with sync_playwright() as p:
        browser = p.chromium.launch()
        context = browser.new_context(
            viewport={"width": 393, "height": 852}, device_scale_factor=3, is_mobile=True, has_touch=True
        )
        for page_path in PAGES:
            for theme, contrast, accent, player, playing, side in MODES:
                sep = "&" if "?" in page_path else "?"
                settings = (
                    f"theme={theme}&contrast={contrast}&accent={accent}&player={player}&playing={playing}&side={side}"
                )
                url = f"{base}{page_path}{sep}{settings}"
                page = context.new_page()
                errors = []
                page.on("pageerror", lambda e, errors=errors: errors.append(str(e)))
                page.goto(url, wait_until="load")
                page.wait_for_timeout(1200)
                where = f"{page_path} {theme}/{contrast}/{accent}/{player}/{side}"
                if errors:
                    failures.append(f"{where}: {' | '.join(errors)}")
                if not page.locator(".app").count():
                    failures.append(f"{where}: no app frame")
                if page.locator(".timeline .seg").count() == 0:
                    failures.append(f"{where}: no timeline")
                if "overlay=" in page_path:
                    for part in (".player-overlay iframe", ".tabbar", ".edge-pill", ".timeline"):
                        if page.locator(part).count() != 1:
                            failures.append(f"{where}: overlay pose lacks {part}")
                    if not page.locator(".tabbar").is_visible() or not page.locator(".edge-pill .pp").is_visible():
                        failures.append(f"{where}: the tab bar or the play button is hidden by the overlay")
                elif page_path in ("index.html", "work.html") and page.locator(".edge-pill .cover-link").count():
                    check_overlay(page, where, failures)
                # A movement row that holds something opens in place on a tap (ADR 0027).
                rows = page.locator(".row-block.track button.row")
                if rows.count():
                    rows.first.tap()
                    page.wait_for_timeout(200)
                    if not page.locator(".track .open-body").count():
                        failures.append(f"{where}: a tapped row did not open")
                if errors:
                    failures.append(f"{where} after a tap: {' | '.join(errors)}")
                runs += 1
                page.close()
        browser.close()
    server.shutdown()
    for line in failures:
        print(f"FAIL {line}")
    print(f"specimen: {runs} pages, {len(failures)} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
