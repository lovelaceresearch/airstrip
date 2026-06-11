#!/usr/bin/env bash
# Builds a Release Airstrip.app and zips it for sharing (AirDrop, USB, etc).
# Usage: Scripts/package-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."

DIST_DIR="dist"
DERIVED="$DIST_DIR/DerivedData"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

xcodebuild \
    -project Airstrip.xcodeproj \
    -scheme Airstrip \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    build

APP="$DERIVED/Build/Products/Release/Airstrip.app"
if [ ! -d "$APP" ]; then
    echo "Build product not found at $APP" >&2
    exit 1
fi

ditto -c -k --keepParent "$APP" "$DIST_DIR/Airstrip.zip"
rm -rf "$DERIVED"

echo
echo "Done: $DIST_DIR/Airstrip.zip"
echo "Send it over AirDrop. On the other Mac: unzip, drag Airstrip.app to"
echo "Applications, then right-click it and choose Open the first time"
echo "(it is not notarized, so a normal double-click is blocked once)."
