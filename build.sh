#!/bin/bash
set -e

APP="CleanSweep"
BUILD="build"

cd "$(dirname "$0")"

rm -rf "$BUILD"
mkdir -p "$BUILD"

echo "Compiling..."
swiftc Sources/*.swift \
    -o "$BUILD/$APP" \
    -parse-as-library \
    -swift-version 5 \
    -sdk "$(xcrun --show-sdk-path)" \
    -framework SwiftUI \
    -framework AppKit \
    -O

echo "Creating app bundle..."
BUNDLE="$BUILD/$APP.app/Contents"
mkdir -p "$BUNDLE/MacOS" "$BUNDLE/Resources"
mv "$BUILD/$APP" "$BUNDLE/MacOS/"
cp Info.plist "$BUNDLE/"
cp CleanSweep.icns "$BUNDLE/Resources/"

echo "Signing..."
codesign --force --sign - "$BUILD/$APP.app"

# Install to /Applications, clear ALL extended attributes including quarantine
rm -rf "/Applications/$APP.app"
cp -R "$BUILD/$APP.app" "/Applications/"
xattr -cr "/Applications/$APP.app"
# Also mark as approved by the user via spctl
spctl --add "/Applications/$APP.app" 2>/dev/null || true

echo ""
echo "Installed to /Applications/$APP.app"
echo "Run:   open /Applications/$APP.app"
