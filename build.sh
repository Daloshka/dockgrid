#!/bin/zsh
# Сборка ~/Applications/Apps.app из main.swift.
set -e
cd "${0:A:h}"
APP="$HOME/Applications/Apps.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/AppIcon.iconset
swiftc -O -target arm64-apple-macos14 main.swift -o "$APP/Contents/MacOS/Apps"
swiftc icon.swift -o build/mkicon && build/mkicon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.apps-launcher</string>
  <key>CFBundleName</key><string>Apps</string>
  <key>CFBundleExecutable</key><string>Apps</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>local.apps-launcher</string>
    <key>CFBundleURLSchemes</key><array><string>apps-launcher</string></array>
  </dict></array>
</dict></plist>
PLIST
codesign --force -s - "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
echo built "$APP"
