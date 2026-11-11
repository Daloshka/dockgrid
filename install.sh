#!/bin/sh
# Установка DockGrid одной командой:
#   curl -fsSL https://raw.githubusercontent.com/Daloshka/dockgrid/main/install.sh | sh
# Скачивает готовое приложение из последнего релиза, ставит в ~/Applications/Apps.app,
# включает автозапуск и запускает. Xcode не нужен.
#   DOCKGRID_KEEP_SPOTLIGHT=1 — не трогать сочетание Spotlight и Maccy.
#   DOCKGRID_ZIP=/путь/DockGrid.zip — поставить из локального архива вместо скачивания.
set -e

major=$(sw_vers -productVersion | cut -d. -f1)
if [ "$major" -lt 14 ]; then echo "Нужна macOS 14 или новее (у вас $(sw_vers -productVersion))." >&2; exit 1; fi

APP="$HOME/Applications/Apps.app"
AGENT="$HOME/Library/LaunchAgents/local.dockgrid.plist"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if [ -n "$DOCKGRID_ZIP" ]; then
  cp "$DOCKGRID_ZIP" "$tmp/DockGrid.zip"
else
  echo "Скачиваю DockGrid…"
  curl -fsSL https://github.com/Daloshka/dockgrid/releases/latest/download/DockGrid.zip -o "$tmp/DockGrid.zip"
fi
ditto -x -k "$tmp/DockGrid.zip" "$tmp/unpacked"
[ -x "$tmp/unpacked/Apps.app/Contents/MacOS/Apps" ] || { echo "В архиве нет Apps.app." >&2; exit 1; }

# Останавливаем прежнюю копию и ставим новую.
launchctl bootout "gui/$(id -u)/local.dockgrid" 2>/dev/null || true
pkill -f "$APP/Contents/MacOS/Apps" 2>/dev/null || true
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
rm -rf "$APP"
mv "$tmp/unpacked/Apps.app" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"

if [ -z "$DOCKGRID_KEEP_SPOTLIGHT" ]; then
  # Сочетание Spotlight (Cmd+Space) перехватывает хоткей истории буфера.
  state=$(defaults export com.apple.symbolichotkeys - 2>/dev/null | plutil -extract AppleSymbolicHotKeys.64.enabled raw - 2>/dev/null || true)
  if [ "$state" != "false" ]; then
    defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 \
      "<dict><key>enabled</key><false/><key>value</key><dict><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>1048576</integer></array><key>type</key><string>standard</string></dict></dict>"
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true
    echo "Сочетание Spotlight (Cmd+Space) отключено. Вернуть: Системные настройки → Клавиатура → Сочетания клавиш → Spotlight."
  fi
  if pgrep -xq Maccy; then
    pkill -x Maccy && echo "Maccy завершён. Отключите его автозапуск в настройках Maccy, иначе он вернётся после входа."
  fi
fi

# Автозапуск при входе; bootstrap заодно запускает приложение сейчас.
cat > "$AGENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>local.dockgrid</string>
  <key>ProgramArguments</key><array>
    <string>/bin/sh</string><string>-c</string>
    <string>exec /usr/bin/open -g -a "$HOME/Applications/Apps.app" --args --background</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict></plist>
PLIST
launchctl bootstrap "gui/$(id -u)" "$AGENT"

cat <<'DONE'

DockGrid установлен и запущен.
  Option+A   — сетка приложений
  Cmd+Space  — история буфера обмена
  Ctrl+Option+стрелки, Enter, U/I/J/K… — раскладка окон (как в Rectangle)
Сочетания меняются в ~/.config/apps-folder/hotkeys.txt.
Чтобы открывать кликом, перетащите ~/Applications/Apps.app в Dock.
Для управления окнами и вставки по Option+Enter выдайте Apps.app разрешение в «Системные настройки → Конфиденциальность → Универсальный доступ».
Удалить: launchctl bootout gui/$(id -u)/local.dockgrid; rm -rf ~/Applications/Apps.app ~/Library/LaunchAgents/local.dockgrid.plist
DONE
