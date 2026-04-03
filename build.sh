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

echo "Signing..."
codesign --force --sign - "$BUILD/$APP.app"

echo ""
echo "Built: $BUILD/$APP.app"
echo "Run:   open $BUILD/$APP.app"
