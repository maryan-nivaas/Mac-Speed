#!/bin/zsh
# Builds Mac Speed.app from source and ad-hoc signs it.
set -e
cd "$(dirname "$0")"

APP="Mac Speed.app"

echo "Compiling (release)..."
swift build -c release

BIN="$(swift build -c release --show-bin-path)/MacSpeed"

echo "Assembling $APP ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacSpeed"
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "Signing (ad-hoc)..."
codesign --force --deep --sign - "$APP"

echo "Done: $(pwd)/$APP"
