#!/bin/zsh
set -eu
cd "${0:A:h}/.."
APP="$PWD/dist/Tibo Watch.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" dist/Tibo.iconset
cp Assets/tibo-avatar.jpg "$APP/Contents/Resources/tibo-avatar.jpg"
cp Assets/audio/reset-confirmed.caf "$APP/Contents/Resources/reset-confirmed.caf"
cp Assets/audio/reset-planned.caf "$APP/Contents/Resources/reset-planned.caf"
cp Assets/audio/timebank.json "$APP/Contents/Resources/timebank.json"
for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" Assets/tibo-avatar.jpg --out "dist/Tibo.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -s format png -z "$double" "$double" Assets/tibo-avatar.jpg --out "dist/Tibo.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns dist/Tibo.iconset -o "$APP/Contents/Resources/Tibo.icns"
xcrun swiftc -swift-version 5 -O Sources/main.swift -o "$APP/Contents/MacOS/TiboWatch" -framework Cocoa -framework SwiftUI -framework UserNotifications -framework ServiceManagement
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.liulaoshi.TiboWatch</string>
<key>CFBundleName</key><string>Tibo Watch</string>
<key>CFBundleExecutable</key><string>TiboWatch</string>
<key>CFBundleIconFile</key><string>Tibo</string>
<key>CFBundleVersion</key><string>10</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "$APP"
