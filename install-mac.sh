#!/bin/bash
# Builds meowmail in Release mode and installs it to /Applications.
# Run again any time to update the installed copy.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="meowmail.app"
DEST="/Applications/$APP_NAME"
BUILT="build/DerivedData/Build/Products/Release/$APP_NAME"

echo "Building meowmail..."
xcodebuild \
  -project MeowMail.xcodeproj \
  -scheme MeowMail \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData \
  -allowProvisioningUpdates \
  -quiet \
  build

# Quit the running copy so it can be replaced.
osascript -e 'if application id "dev.jaderowland.meowmail" is running then tell application id "dev.jaderowland.meowmail" to quit' >/dev/null 2>&1 || true

echo "Installing to $DEST..."
rm -rf "$DEST"
ditto "$BUILT" "$DEST"

echo "Done. Opening meowmail."
open "$DEST"
