#!/bin/bash
# Copy the 5 helper .app bundles into the main app's Contents/Frameworks.
# Each helper target builds its own .app into BUILT_PRODUCTS_DIR.
set -euo pipefail

DEST="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Frameworks"
mkdir -p "$DEST"

HELPERS=(
  "Goat Browser Helper"
  "Goat Browser Helper (Alerts)"
  "Goat Browser Helper (GPU)"
  "Goat Browser Helper (Plugin)"
  "Goat Browser Helper (Renderer)"
)

for h in "${HELPERS[@]}"; do
  SRC="$BUILT_PRODUCTS_DIR/$h.app"
  if [ ! -d "$SRC" ]; then
    echo "ERROR: helper bundle not found: $SRC" >&2
    exit 1
  fi
  echo "Copying $h.app -> $DEST"
  rm -rf "$DEST/$h.app"
  ditto "$SRC" "$DEST/$h.app"
done
echo "All helper apps copied."
