#!/usr/bin/env python3
import asyncio, json, sys, urllib.request, time
import websockets

PORT = 9222

def targets():
    with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json", timeout=3) as r:
        return json.load(r)

def page_target(url_sub=None):
    for t in targets():
        if t.get("type") == "page" and (url_sub is None or url_sub in t.get("url","")):
            return t
    return None

class CDP:
    def __init__(self, ws):
        self.ws = ws
        self.mid = 0
    async def send(self, method, params=None):
        self.mid += 1
        mid = self.mid
        await self.ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
        while True:
            msg = json.loads(await self.ws.recv())
            if msg.get("id") == mid:
                return msg
    async def nav(self, url):
        await self.send("Page.enable")
        await self.send("Page.navigate", {"url": url})
    async def eval(self, expr, user_gesture=True, await_promise=False):
        r = await self.send("Runtime.evaluate", {
            "expression": expr, "userGesture": user_gesture,
            "awaitPromise": await_promise, "returnByValue": True})
        return r

async def with_page(url_sub=None):
    t = page_target(url_sub)
    ws = await websockets.connect(t["webSocketDebuggerUrl"], max_size=None)
    return CDP(ws), t

async def test_permission_media():
    cdp, t = await with_page("example.com")
    # getUserMedia triggers OnRequestMediaAccessPermission
    await cdp.eval("navigator.mediaDevices.getUserMedia({audio:true}).then(()=>{}).catch(()=>{});",
                   await_promise=False)
    await cdp.ws.close()
    print("[perm] requested getUserMedia(audio)")

async def test_zoom():
    # zoom tested via app menu; here we just navigate to confirm page is alive
    pass

async def test_find():
    cdp, t = await with_page("example.com")
    await cdp.ws.close()

async def main():
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    if which in ("perm","all"):
        await test_permission_media()

asyncio.run(main())
