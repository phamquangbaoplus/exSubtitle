#!/bin/bash
set -euo pipefail

# Root project directory
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

SCHEME="exSubtitle"
PROJECT="exSubtitle.xcodeproj"
CONFIGURATION="Release"
BUILD_DIR="${PROJECT_DIR}/build"
DERIVED_DATA="${BUILD_DIR}/DerivedData"
STAGING_DIR="${BUILD_DIR}/dmg_staging"
DIST_DIR="${BUILD_DIR}/dist"
BACKGROUND_IMG="${PROJECT_DIR}/installer/background.png"

echo "==> Building exSubtitle for ${CONFIGURATION}..."
mkdir -p "$DIST_DIR" "$STAGING_DIR"

# Resolve package dependencies
xcodebuild -resolvePackageDependencies -project "$PROJECT" -scheme "$SCHEME"

# Build application
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES

APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/exSubtitle.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Error: Application not found at $APP_PATH" >&2
  exit 1
fi

# Read version from Info.plist or xcodebuild
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "1.0.0")
echo "==> Application version: ${VERSION}"

# Always regenerate background if script exists to keep layout & colors in sync
echo "==> Generating custom DMG background (680x480 Retina)..."
swift "${PROJECT_DIR}/installer/generate_dmg_background.swift" "$BACKGROUND_IMG"

# Prepare staging folder
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"

# Ensure create-dmg is available
CREATE_DMG_BIN=""
if command -v create-dmg >/dev/null 2>&1; then
  CREATE_DMG_BIN="$(command -v create-dmg)"
elif [ -x "/opt/homebrew/bin/create-dmg" ]; then
  CREATE_DMG_BIN="/opt/homebrew/bin/create-dmg"
elif [ -x "/usr/local/bin/create-dmg" ]; then
  CREATE_DMG_BIN="/usr/local/bin/create-dmg"
else
  echo "Error: create-dmg not found. Please install it using 'brew install create-dmg'" >&2
  exit 1
fi

FINAL_DMG="${DIST_DIR}/exSubtitle-${VERSION}.dmg"
GENERIC_DMG="${DIST_DIR}/exSubtitle.dmg"

echo "==> Creating DMG installer with create-dmg..."
"$CREATE_DMG_BIN" \
  --volname "exSubtitle" \
  --background "$BACKGROUND_IMG" \
  --window-pos 200 120 \
  --window-size 680 480 \
  --icon-size 128 \
  --text-size 13 \
  --icon "exSubtitle.app" 175 215 \
  --hide-extension "exSubtitle.app" \
  --app-drop-link 505 215 \
  --no-internet-enable \
  --overwrite \
  "$FINAL_DMG" \
  "$STAGING_DIR"

# Also create/update standard exSubtitle.dmg copy
cp -f "$FINAL_DMG" "$GENERIC_DMG"

echo "==> Successfully created DMG:"
echo "    - $FINAL_DMG"
echo "    - $GENERIC_DMG"
