#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_NAME="照片无障碍描述"
OUTPUT_DIR="$PROJECT_DIR/outputs"
ARCHIVE_PATH="$OUTPUT_DIR/$APP_NAME-macOS.zip"
STAGING_ROOT=$(/usr/bin/mktemp -d /private/tmp/pas-app.XXXXXX)
APP_DIR="$STAGING_ROOT/$APP_NAME.app"
trap '/bin/rm -rf -- "$STAGING_ROOT"' EXIT

cd "$PROJECT_DIR"
swift build -c release --disable-sandbox

/bin/mkdir -p "$OUTPUT_DIR"
/bin/rm -rf "$OUTPUT_DIR/$APP_NAME.app"
/bin/mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
/bin/cp ".build/release/PhotoAccessibilityStudio" "$APP_DIR/Contents/MacOS/PhotoAccessibilityStudio"
/bin/cp "AppBundle/Info.plist" "$APP_DIR/Contents/Info.plist"
/bin/cp "Sources/PhotoAccessibilityStudio/Resources/PrivacyInfo.xcprivacy" "$APP_DIR/Contents/Resources/"
/usr/bin/xattr -cr "$APP_DIR"
/usr/bin/codesign --force --deep --sign - "$APP_DIR"
/usr/bin/xattr -cr "$APP_DIR"
/usr/bin/codesign --verify --deep --strict "$APP_DIR"
/bin/rm -f "$ARCHIVE_PATH"
(
    cd "$STAGING_ROOT"
    COPYFILE_DISABLE=1 /usr/bin/zip -qry "$ARCHIVE_PATH" "$APP_NAME.app"
)
echo "$ARCHIVE_PATH"
