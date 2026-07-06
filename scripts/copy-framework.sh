#!/bin/bash
# Copy the CEF framework into the app bundle's Contents/Frameworks.
# The framework is loaded at runtime by CefScopedLibraryLoader.
set -euo pipefail

CEF_FRAMEWORK="$SRCROOT/ThirdParty/CEF/current/Release/Chromium Embedded Framework.framework"
DEST="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Frameworks"

FW="$DEST/Chromium Embedded Framework.framework"
SRC="$CEF_FRAMEWORK"
NAME="Chromium Embedded Framework"

mkdir -p "$DEST"
echo "Copying CEF framework -> $DEST"
rm -rf "$FW"

# The CEF distribution ships a *flat* (shallow) framework: binary + Resources/
# + Libraries/ directly under the .framework root, with Info.plist inside
# Resources/. macOS's builtin-validationUtility (run during the app target's
# Validate phase) rejects that layout inside Contents/Frameworks and demands a
# versioned/deep framework (Versions/Current/...). So we reconstruct a proper
# deep framework here. CEF is loaded at runtime via dlopen of
# .../Chromium Embedded Framework.framework/Chromium Embedded Framework, which
# resolves through the top-level symlink, so loading is unaffected.
mkdir -p "$FW/Versions/A"
ditto "$SRC/$NAME"      "$FW/Versions/A/$NAME"
ditto "$SRC/Resources" "$FW/Versions/A/Resources"
if [ -d "$SRC/Libraries" ]; then
  ditto "$SRC/Libraries" "$FW/Versions/A/Libraries"
fi

# Symlinks: Current -> A, and top-level shims.
ln -s "A" "$FW/Versions/Current"
ln -s "Versions/Current/$NAME"      "$FW/$NAME"
ln -s "Versions/Current/Resources"  "$FW/Resources"
if [ -d "$FW/Versions/A/Libraries" ]; then
  ln -s "Versions/Current/Libraries" "$FW/Libraries"
fi
echo "CEF framework copied (deep layout)."
