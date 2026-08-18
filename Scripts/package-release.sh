#!/bin/bash
#
# Builds, signs, notarizes, staples, and zips a distributable ClipPanel.
#
# This script deliberately does NOT handle your credentials. It expects:
#
#   1. A Developer ID Application certificate in your keychain. Find its exact name with:
#        security find-identity -v -p codesigning
#      Then export it:
#        export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
#
#   2. A notarytool keychain profile, created once with your Apple ID and an app-specific password
#      (an app-specific password, never your Apple ID password):
#        xcrun notarytool store-credentials ClipPanelNotary \
#          --apple-id you@example.com --team-id TEAMID --password APP_SPECIFIC_PASSWORD
#      Then export its name:
#        export NOTARY_PROFILE="ClipPanelNotary"
#
# Without those two variables the script stops before building and prints this again.

set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

BUILD_DIR="build/release"
ARCHIVE_PATH="$BUILD_DIR/ClipPanel.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP="$EXPORT_PATH/ClipPanel.app"
ZIP="$BUILD_DIR/ClipPanel.zip"

if [ -z "${DEVELOPER_ID:-}" ] || [ -z "${NOTARY_PROFILE:-}" ]; then
  # Prints the comment header above, stopping at the first line of actual script, so this
  # stays correct if the header is edited.
  awk 'NR > 2 && /^#/ { sub(/^# ?/, ""); print; next } NR > 2 { exit }' "$0"
  echo
  echo "Set DEVELOPER_ID and NOTARY_PROFILE, then run this again."
  exit 2
fi

echo "==> Cleaning"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving (Release)"
xcodebuild -project ClipPanel.xcodeproj \
           -scheme ClipPanel \
           -configuration Release \
           -destination 'generic/platform=macOS' \
           -archivePath "$ARCHIVE_PATH" \
           archive

echo "==> Exporting a signed app"
cat > "$BUILD_DIR/ExportOptions.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>automatic</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
           -archivePath "$ARCHIVE_PATH" \
           -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
           -exportPath "$EXPORT_PATH"

echo "==> Verifying the guarantees before anything is shipped"
Scripts/audit-logging.sh
Scripts/verify-release.sh "$APP"

echo "==> Zipping for notarization"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Notarizing (this waits for Apple)"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling the ticket"
xcrun stapler staple "$APP"

echo "==> Re-zipping the stapled app"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Final checks"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose "$APP"

echo
echo "Done: $ZIP"
echo "Gatekeeper should now accept it on a machine that has never seen it before."
