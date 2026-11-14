#!/bin/bash
# Builds build/micinput.app.
#   ./build.sh            build only
#   ./build.sh install    build, copy to /Applications and open it
#   ./build.sh dmg        build for Apple silicon and Intel, package build/micinput-<version>.dmg for a release
set -euo pipefail
cd "$(dirname "$0")"

APP=build/micinput.app

# A release has to run on any Mac; a local build only needs this one's architecture.
ARCHS=""
if [ "${1:-}" = dmg ]; then ARCHS="--arch arm64 --arch x86_64"; fi

swift build -c release $ARCHS

# The icon is drawn by code; rebuild it only when the drawing changes.
if [ ! -f Support/AppIcon.icns ] || [ Support/make-icon.swift -nt Support/AppIcon.icns ]; then
  rm -rf build/AppIcon.iconset
  swift Support/make-icon.swift build/AppIcon.iconset
  iconutil --convert icns build/AppIcon.iconset --output Support/AppIcon.icns
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release $ARCHS --show-bin-path)/micinput" "$APP/Contents/MacOS/"
cp Support/Info.plist "$APP/Contents/"
cp Support/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Built $APP"

if [ "${1:-}" = install ]; then
  pkill -x micinput || true
  rm -rf /Applications/micinput.app
  cp -R "$APP" /Applications/
  open /Applications/micinput.app
  echo "Installed /Applications/micinput.app"
fi

if [ "${1:-}" = dmg ]; then
  VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/Info.plist)
  DMG="build/micinput-$VERSION.dmg"
  # The disk image holds the app next to a shortcut to Applications, to drag one onto the other.
  rm -rf build/dmg "$DMG"
  mkdir build/dmg
  cp -R "$APP" build/dmg/
  ln -s /Applications build/dmg/Applications
  hdiutil create -volname micinput -srcfolder build/dmg -format UDZO -quiet "$DMG"
  rm -rf build/dmg
  echo "Packaged $DMG"
fi
