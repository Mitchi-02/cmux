#!/bin/bash
# Build Release imux to a persistent DerivedData path and self-install as
# /Applications/imux.app (ad-hoc signed). Chained so install runs in the same
# detached process the moment the build succeeds — no cross-session /tmp wipe.
set -euo pipefail
cd /Users/ilyasbenhammadi/dev/cmux
export CMUX_ZIG=/opt/homebrew/opt/zig@0.15/bin/zig
DD="$HOME/Library/Developer/Xcode/DerivedData/cmux-imux"
PB=/usr/libexec/PlistBuddy

xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$DD" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build

SRC="$DD/Build/Products/Release/cmux.app"
DST="/Applications/imux.app"
[ -d "$SRC" ] || { echo "MISSING BUILT APP"; exit 1; }

osascript -e 'quit app "imux"' 2>/dev/null || true
pkill -f "/Applications/imux.app" 2>/dev/null || true
sleep 1
[ -d "$DST" ] && trash "$DST"
cp -R "$SRC" "$DST"
$PB -c "Set CFBundleName imux" "$DST/Contents/Info.plist"
$PB -c "Set CFBundleDisplayName imux" "$DST/Contents/Info.plist"
$PB -c "Set CFBundleIdentifier com.cmuxterm.app.imux" "$DST/Contents/Info.plist"
codesign --force --sign - "$DST/Contents/Resources/bin/ghostty"
codesign --force --deep --sign - "$DST"
echo "INSTALLED imux:"
file "$DST/Contents/Resources/bin/ghostty"
"$DST/Contents/Resources/bin/ghostty" +version 2>&1 | head -1
codesign -dv "$DST" 2>&1 | rg -i "Identifier|Signature"
open "$DST"
echo "IMUX_INSTALL_DONE"
