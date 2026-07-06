#!/bin/bash
# Smoke test: launch the built Goat Browser app, poll the Chrome DevTools
# Protocol endpoint (remote_debugging_port=9222 on 127.0.0.1) until a page
# target whose URL contains example.com appears, then PASS/FAIL and clean up.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/build/Debug/Goat Browser.app}"
PORT=9222
TIMEOUT=20

if [ ! -d "$APP" ]; then
  echo "FAIL: app not found at: $APP" >&2
  exit 1
fi

echo "== Goat Browser CDP smoke test =="
echo "App:  $APP"
echo "Port: $PORT"

cleanup() {
  echo "-- cleanup: killing app + helpers --"
  pkill -f "Goat Browser.app/Contents/MacOS/Goat Browser" 2>/dev/null || true
  pkill -f "Goat Browser Helper" 2>/dev/null || true
}
trap cleanup EXIT

# Fresh start: make sure nothing stale is around.
cleanup
sleep 1

echo "-- launching app --"
open -n "$APP"

deadline=$((SECONDS + TIMEOUT))
found=""
version=""
while [ $SECONDS -lt $deadline ]; do
  version="$(curl -s --max-time 2 "http://127.0.0.1:$PORT/json/version" 2>/dev/null || true)"
  json="$(curl -s --max-time 2 "http://127.0.0.1:$PORT/json" 2>/dev/null || true)"
  if echo "$json" | grep -q "example.com"; then
    found="$json"
    break
  fi
  sleep 1
done

echo
echo "-- /json/version --"
echo "$version"
echo
echo "-- /json (targets) --"
if [ -n "$found" ]; then
  echo "$found"
else
  curl -s --max-time 2 "http://127.0.0.1:$PORT/json" 2>/dev/null || echo "(no response)"
fi
echo
echo "-- helper processes --"
pgrep -fl "Goat Browser Helper" || echo "(none)"
echo

if [ -n "$found" ]; then
  echo "RESULT: example.com target rendered via CDP — PASS (stage 1)."
else
  echo "RESULT: FAIL — example.com target did not appear within ${TIMEOUT}s."
  exit 1
fi

# -- Stage 2: multi-tab engine path ----------------------------------------
# Drive the first page to call window.open(...), which our bridge routes via
# CefLifeSpanHandler::OnBeforePopup -> Swift -> a NEW TAB (second CEF browser).
# Assert a second page target appears. Requires python3 + the websockets pkg;
# skipped (not failed) if unavailable so the core smoke test stays portable.
echo
echo "-- multi-tab check (window.open -> OnBeforePopup -> new tab) --"
MULTITAB="$ROOT/scripts/multitab_cdp.py"
if command -v python3 >/dev/null 2>&1 && \
   python3 -c "import websockets" >/dev/null 2>&1 && [ -f "$MULTITAB" ]; then
  if python3 "$MULTITAB"; then
    echo "RESULT: multi-tab PASS (stage 2)."
    exit 0
  else
    echo "RESULT: FAIL — multi-tab path did not produce a second target."
    exit 1
  fi
else
  echo "SKIP: python3/websockets unavailable; multi-tab CDP check skipped."
  echo "      (Stage 1 passed; run scripts/multitab_cdp.py manually to verify.)"
  exit 0
fi
