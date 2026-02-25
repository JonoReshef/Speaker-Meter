#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/VolumeMeter.app"

echo "Building VolumeMeter..."
cd "$PROJECT_DIR"
swift build --configuration release --arch arm64

echo "Assembling app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp .build/release/VolumeMeter "$APP_BUNDLE/Contents/MacOS/VolumeMeter"
cp Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "Signing app bundle..."
codesign --force --sign - --entitlements Resources/VolumeMeter.entitlements "$APP_BUNDLE"

echo "Done! App bundle at: $APP_BUNDLE"
echo "Run with: open $APP_BUNDLE"
