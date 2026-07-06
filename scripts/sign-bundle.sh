#!/bin/bash
# Inside-out ad-hoc codesign of the app bundle:
#   1. CEF framework (and its nested Libraries/helpers)
#   2. each Helper .app
#   3. the main app
# Ad-hoc identity "-" keeps local runs simple (no provisioning).
set -euo pipefail

APP="$TARGET_BUILD_DIR/$WRAPPER_NAME"
FRAMEWORKS="$APP/Contents/Frameworks"
ID="-"

codesign_force() {
  /usr/bin/codesign --force --sign "$ID" --timestamp=none "$@"
}

echo "== Inside-out ad-hoc codesign =="

# 1. CEF framework. Sign nested dylibs first, then the framework bundle.
CEF_FW="$FRAMEWORKS/Chromium Embedded Framework.framework"
if [ -d "$CEF_FW/Versions/A/Libraries" ]; then
  find "$CEF_FW/Versions/A/Libraries" -name "*.dylib" -print0 | while IFS= read -r -d '' lib; do
    codesign_force "$lib"
  done
fi
# Sign the versioned framework. Point codesign at the versioned directory so it
# produces a valid deep-framework signature.
codesign_force "$CEF_FW/Versions/A"

# 2. Each helper app.
for h in "$FRAMEWORKS"/*.app; do
  [ -d "$h" ] || continue
  echo "Signing helper: $(basename "$h")"
  codesign_force "$h"
done

# 3. Main app (deep, last).
echo "Signing main app: $(basename "$APP")"
codesign_force --deep "$APP"

echo "== Codesign complete =="
codesign --verify --verbose=2 "$APP" || true
