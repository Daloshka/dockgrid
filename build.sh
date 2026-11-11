#!/bin/zsh
# Сборка ~/Applications/Apps.app из main.swift.
set -e
cd "${0:A:h}"
# DOCKGRID_APP — куда собирать, DOCKGRID_ARCHS — архитектуры (для релиза: "arm64 x86_64"),
# DOCKGRID_PACKAGE=1 — только собрать, ничего не регистрировать и не отключать (см. release.sh).
APP="${DOCKGRID_APP:-$HOME/Applications/Apps.app}"
# Версия приложения; release.sh выпускает релиз с тегом v$VERSION.
VERSION="${DOCKGRID_VERSION:-1.1.0}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/AppIcon.iconset
slices=()
for arch in ${=DOCKGRID_ARCHS:-arm64}; do
  swiftc -O -target $arch-apple-macos14 main.swift Launcher.swift Clipboard.swift Hotkeys.swift Windows.swift Settings.swift Highlight.swift QRCode.swift -o build/Apps-$arch
  slices+=(build/Apps-$arch)
done
lipo -create $slices -output "$APP/Contents/MacOS/Apps"
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
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>local.apps-launcher</string>
    <key>CFBundleURLSchemes</key><array><string>apps-launcher</string></array>
  </dict></array>
</dict></plist>
PLIST
codesign --force -s - "$APP"
[[ -n "$DOCKGRID_PACKAGE" ]] && { echo built "$APP"; exit 0; }
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
echo built "$APP"

# --- Конфликтующие программы -------------------------------------------------
# DOCKGRID_KEEP_SPOTLIGHT=1 ./build.sh — ничего не отключать.
if [[ -z "$DOCKGRID_KEEP_SPOTLIGHT" ]]; then
  # Сочетание Spotlight (Cmd+Space, системный хоткей 64) перехватывает хоткей истории буфера.
  state=$(defaults export com.apple.symbolichotkeys - 2>/dev/null | plutil -extract AppleSymbolicHotKeys.64.enabled raw - 2>/dev/null || true)
  if [[ "$state" != "false" ]]; then
    defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 \
      "<dict><key>enabled</key><false/><key>value</key><dict><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>1048576</integer></array><key>type</key><string>standard</string></dict></dict>"
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true
    echo "Spotlight: сочетание Cmd+Space отключено (вернуть: Системные настройки → Клавиатура → Сочетания клавиш → Spotlight)"
  fi
  # Индексацию трогаем только по явной просьбе: нужен sudo, и без индекса перестаёт работать поиск в Finder и Почте.
  if [[ "$1" == "--disable-indexing" ]]; then
    sudo mdutil -a -i off && echo "Spotlight: индексация выключена (вернуть: sudo mdutil -a -i on)"
  fi
  # Maccy ведёт свою историю буфера и занимает хоткей — завершаем, если запущен.
  if pgrep -xq Maccy; then
    pkill -x Maccy && echo "Maccy: завершён. Автозапуск отключите в его настройках (Launch at login), иначе он вернётся после входа."
  fi
  # Rectangle вешает те же сочетания на окна — сработали бы оба.
  if pgrep -xq Rectangle; then
    pkill -x Rectangle && echo "Rectangle: завершён, окнами теперь управляет DockGrid."
  fi
  if defaults read com.knollsoft.Rectangle >/dev/null 2>&1; then
    defaults write com.knollsoft.Rectangle launchOnLogin -bool false
    echo "Rectangle: если вернётся после входа, уберите его в Системные настройки → Основные → Объекты входа."
  fi
fi
