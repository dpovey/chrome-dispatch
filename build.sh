#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Chrome Dispatch"
EXEC_NAME="ChromeDispatch"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

swiftc -O \
    -target arm64-apple-macos14.0 \
    Sources/main.swift \
    Sources/ChromeProfiles.swift \
    Sources/Mappings.swift \
    Sources/ProfileAvatar.swift \
    Sources/PickerView.swift \
    Sources/MappingsView.swift \
    -o "$APP_BUNDLE/Contents/MacOS/$EXEC_NAME"

# Strip any provenance/quarantine markers, then ad-hoc sign so LaunchServices
# will register the bundle as a browser URL handler.
xattr -cr "$APP_BUNDLE" || true
codesign --force --deep --sign - "$APP_BUNDLE"

# If a copy is already installed, refresh it in-place and re-register with
# LaunchServices so other apps (Outlook, Slack, etc.) pick up the new signature.
INSTALLED="/Applications/$APP_NAME.app"
if [ -d "$INSTALLED" ]; then
    pkill -f ChromeDispatch >/dev/null 2>&1 || true
    sleep 0.3
    rm -rf "$INSTALLED"
    cp -R "$APP_BUNDLE" "$INSTALLED"
    xattr -cr "$INSTALLED" || true
    LSREG=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
    "$LSREG" -f "$INSTALLED"
    echo "Refreshed installed copy: $INSTALLED"
else
    echo
    echo "Built: $APP_BUNDLE"
    echo
    echo "Install with:"
    echo "  cp -R '$APP_BUNDLE' /Applications/"
    echo "Then open it once and click 'Set as Default Browser'."
fi
