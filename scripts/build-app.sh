#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_NAME="照片无障碍描述"
OUTPUT_DIR="$PROJECT_DIR/outputs"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"

cd "$PROJECT_DIR"
swift build -c release

/bin/rm -rf "$APP_DIR"
/bin/mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
/bin/cp ".build/release/PhotoAccessibilityStudio" "$APP_DIR/Contents/MacOS/PhotoAccessibilityStudio"
/bin/cp "AppBundle/Info.plist" "$APP_DIR/Contents/Info.plist"
/bin/cp "Sources/PhotoAccessibilityStudio/Resources/PrivacyInfo.xcprivacy" "$APP_DIR/Contents/Resources/"
/usr/bin/xattr -cr "$APP_DIR"
/usr/bin/codesign --force --deep --sign - "$APP_DIR"
/usr/bin/codesign --verify --deep --strict "$APP_DIR"
echo "$APP_DIR"
