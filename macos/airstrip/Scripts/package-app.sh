#!/usr/bin/env bash
# Builds a Release Airstrip.app, then creates both zip and dmg artifacts.
# Usage: Scripts/package-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."

DIST_DIR="dist"
DERIVED="$DIST_DIR/DerivedData"
STAGING="$DIST_DIR/dmg-staging"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

xcodebuild \
    -project Airstrip.xcodeproj \
    -scheme Airstrip \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build

APP="$DERIVED/Build/Products/Release/Airstrip.app"
if [ ! -d "$APP" ]; then
    echo "Build product not found at $APP" >&2
    exit 1
fi

ditto -c -k --keepParent "$APP" "$DIST_DIR/Airstrip.zip"

mkdir -p "$STAGING"
ditto "$APP" "$STAGING/Airstrip.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "Airstrip" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DIST_DIR/Airstrip.dmg"

rm -rf "$DERIVED"
rm -rf "$STAGING"

echo
echo "Done:"
echo "  $DIST_DIR/Airstrip.zip"
echo "  $DIST_DIR/Airstrip.dmg"
echo
echo "For another Mac: send Airstrip.dmg, open it, drag Airstrip.app to"
echo "Applications, then right-click Airstrip.app and choose Open the first time."
echo "This build is not notarized, so the first normal double-click may be blocked."
