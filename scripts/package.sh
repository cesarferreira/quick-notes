#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
PROFILE=release
if [[ "${1:-}" == "--debug" && "$#" == 1 ]]; then
    PROFILE=debug
elif [[ "$#" != 0 ]]; then
    printf 'Usage: %s [--debug]\n' "$0" >&2
    exit 2
fi
swift build -c "$PROFILE"
BIN_DIR="$(swift build -c "$PROFILE" --show-bin-path)"
APP="$ROOT/dist/Quick Notes.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/quick-notes" "$APP/Contents/MacOS/quick-notes"
xcrun swift "$ROOT/scripts/generate-icon.swift" "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleDisplayName</key><string>Quick Notes</string>
<key>CFBundleExecutable</key><string>quick-notes</string>
<key>CFBundleIdentifier</key><string>dev.cesar.quicknotes</string>
<key>CFBundleIconFile</key><string>QuickNotes</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>Quick Notes</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf '\nPackaged: %s\n' "$APP"
