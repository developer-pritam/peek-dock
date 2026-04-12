#!/bin/bash
# build-unsigned.sh — builds WindowManager and zips it for direct download
# No Apple Developer account required.
# Users will need to right-click → Open on first launch (Gatekeeper warning).

set -euo pipefail

APP_NAME="WindowManager"
VERSION="1.0"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"

mkdir -p "$DIST_DIR"

echo "▶ Building Release..."
xcodebuild \
    -project "$PROJECT_ROOT/${APP_NAME}.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    build

# Find the built .app
BUILD_DIR=$(xcodebuild \
    -project "$PROJECT_ROOT/${APP_NAME}.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -showBuildSettings \
    CODE_SIGN_IDENTITY="-" \
    2>/dev/null | grep "BUILT_PRODUCTS_DIR" | head -1 | awk '{print $3}')

APP_PATH="$BUILD_DIR/${APP_NAME}.app"

echo "▶ Packaging..."
ZIP_PATH="$DIST_DIR/${APP_NAME}-${VERSION}.zip"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo ""
echo "✅ Done: $ZIP_PATH"
echo "   Size: $(du -sh "$ZIP_PATH" | cut -f1)"
echo ""
echo "Users who download this will need to:"
echo "  Right-click → Open on first launch, then click Open in the dialog."
echo "  Or run: xattr -d com.apple.quarantine /Applications/${APP_NAME}.app"
