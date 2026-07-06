#!/usr/bin/env python3
# Multi-tab CDP exercise for Goat Browser MILESTONE 1.
#
# Connects to the first page target's DevTools WebSocket and calls
# window.open(...) with a synthesized user gesture. Our bridge's
# CefLifeSpanHandler::OnBeforePopup cancels the native popup and asks the Swift
# model to open a NEW TAB (a second CEF browser). We then poll the CDP target
# list and assert a second page target for the opened URL appears — proving the
# multi-tab engine path end to end.
#
# Exit 0 on success, 1 on failure.

import asyncio
import json
import sys
import time
import urllib.request

import websockets

PORT = 9222
OPEN_URL = "https://www.wikipedia.org/"
TIMEOUT = 25


def list_targets():
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json", timeout=2) as r:
            return json.loads(r.read().decode())
    except Exception:
        return []


def page_targets():
    return [t for t in list_targets() if t.get("type") == "page"]


async def trigger_window_open(ws_url):
    async with websockets.connect(ws_url, max_size=None) as ws:
        async def send(method, params=None):
            msg_id = send.counter = getattr(send, "counter", 0) + 1
            await ws.send(json.dumps({"id": msg_id, "method": method,
                                      "params": params or {}}))
            # Drain until we see our response id (ignore events).
            while True:
                resp = json.loads(await ws.recv())
                if resp.get("id") == msg_id:
                    return resp

        await send("Page.enable")
        await send("Runtime.enable")
        # userGesture=True so window.open isn't blocked as a popup.
        await send("Runtime.evaluate", {
            "expression": f"window.open('{OPEN_URL}', '_blank')",
            "userGesture": True,
        })


def main():
    # Wait for the first page target (example.com) to exist.
    deadline = time.time() + TIMEOUT
    first = None
    while time.time() < deadline:
        pts = page_targets()
        if pts:
            first = pts[0]
            break
        time.sleep(0.5)
    if not first:
        print("FAIL: no initial page target appeared")
        return 1

    before = len(page_targets())
    print(f"-- initial page targets: {before} ({first.get('url')})")

    ws_url = first["webSocketDebuggerUrl"]
    try:
        asyncio.run(trigger_window_open(ws_url))
    except Exception as e:
        print(f"FAIL: could not trigger window.open: {e}")
        return 1
    print(f"-- requested window.open('{OPEN_URL}') with user gesture")

    # Poll for a second page target (the new tab's browser).
    deadline = time.time() + TIMEOUT
    while time.time() < deadline:
        pts = page_targets()
        urls = [t.get("url", "") for t in pts]
        if len(pts) >= before + 1 and any("wikipedia" in u for u in urls):
            print(f"-- page targets now: {len(pts)}")
            for u in urls:
                print(f"     {u}")
            print("PASS: multi-tab — second CEF browser created via OnBeforePopup")
            return 0
        time.sleep(0.5)

    pts = page_targets()
    print(f"FAIL: second tab did not appear (targets={len(pts)})")
    for t in pts:
        print(f"     {t.get('url')}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
