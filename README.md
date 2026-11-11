# DockGrid

**English** · [Русский](README.ru.md)

A lightweight app launcher, clipboard history and window manager for macOS — a replacement for Launchpad / the system "Apps" icon and for a clipboard manager, made for people who keep Spotlight turned off.
It does not use the Spotlight index: the app list is read from disk every time the window opens.

> The app interface and the installer messages are currently in Russian.

![App grid, search and clipboard history](docs/demo.gif)

| App grid | Clipboard history |
| --- | --- |
| ![App grid](docs/launcher.png) | ![Clipboard history](docs/clipboard.png) |

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/Daloshka/dockgrid/main/install.sh | sh
```

Requires macOS 14 or later (Apple Silicon or Intel); Xcode is not needed. The script downloads the prebuilt app from the latest release into `~/Applications/Apps.app`, enables launch at login and starts it right away: Option+A opens the app grid, Cmd+Space opens the clipboard history.
It also disables the system Spotlight shortcut (Cmd+Space) and quits Maccy if it is running; to skip that, run `curl -fsSL … | DOCKGRID_KEEP_SPOTLIGHT=1 sh`.

Uninstall:

```sh
launchctl bootout gui/$(id -u)/local.dockgrid
rm -rf ~/Applications/Apps.app ~/Library/LaunchAgents/local.dockgrid.plist
```

## Features

- App grid with search by name; arrow keys move around the grid, Enter launches, Esc closes.
- Pinned apps in a separate block at the top.
- Right-click an app: pin / unpin, show in Finder, hide from the list.
- Opens by clicking the Dock icon or with a hotkey (Option+A); doing it again hides the window.
- The process stays alive and the window is hidden; while hidden, the interface is unloaded and CPU use is close to zero.

## Clipboard history

- Remembers copied text, files and images (up to 200 entries, pinned ones are never evicted); copying the same thing again moves the entry to the top.
- Opens with a hotkey (Cmd+Space by default): a searchable list on the left, a preview and entry details on the right.
- Text that looks like code (including JSON and SQL) is syntax-highlighted in the preview: keywords, strings, comments, numbers, types and calls; long lines scroll sideways instead of wrapping.
- If a copied image contains a QR code, its content is shown under the preview: an http(s) link opens on click, any text can be copied.
- Enter or click copies the entry back to the clipboard; Option+Enter copies and pastes (needs the Accessibility permission for `Apps.app`; it has to be granted again after a rebuild).
- Cmd+1…9 — quick select, Cmd+Backspace — delete, right-click — pin, delete, show the file in Finder.
- Entries that password managers mark as concealed (`org.nspasteboard.ConcealedType` and similar, plus the custom types of 1Password, KeeWeb and TypeIt4Me) are not stored.
- Storage: `~/Library/Application Support/DockGrid/clipboard` (`index.json`, `images/*.png`, large texts in `texts/*.txt`), unencrypted, readable by the owner only.
- For large texts the preview and search cover the first 20,000 characters; the full text is copied.

### Known limitations

- IME input (Japanese, Chinese, Korean): Enter and the arrow keys always act on the list, so confirming a composition in the search field does not work.
- Option+Enter pastes by sending the V key at its QWERTY position; on layouts such as Dvorak the paste will not work.

## Window management

Hotkeys tile the focused window of any app — modelled on [Rectangle](https://github.com/rxhanson/rectangle), with the same default shortcuts:

| Action | Shortcut | What it does |
| --- | --- | --- |
| `left-half`, `right-half` | Ctrl+Option+← / → | left / right half; repeating cycles the width 1/2 → 2/3 → 1/3 |
| `top-half`, `bottom-half` | Ctrl+Option+↑ / ↓ | top / bottom half |
| `top-left`, `top-right`, `bottom-left`, `bottom-right` | Ctrl+Option+U / I / J / K | screen quarters |
| `first-third`, `center-third`, `last-third` | Ctrl+Option+D / F / G | thirds (split by height on a portrait display) |
| `first-two-thirds`, `last-two-thirds` | Ctrl+Option+E / T | two thirds |
| `maximize` | Ctrl+Option+Enter | fill the usable area (not full-screen mode) |
| `maximize-height` | Ctrl+Option+Shift+↑ | full height, width unchanged |
| `almost-maximize` | unassigned | 90% of the screen, centred |
| `center` | Ctrl+Option+C | centre without resizing |
| `larger`, `smaller` | Ctrl+Option+= / − | grow / shrink by 30 pt on each side |
| `restore` | Ctrl+Option+Backspace | bring back the frame the window had before tiling |
| `next-display`, `prev-display` | Ctrl+Option+Cmd+→ / ← | move to the adjacent display, keeping proportions |

- Needs the Accessibility permission for `Apps.app` (System Settings → Privacy & Security → Accessibility): the prompt appears on the first shortcut press; it has to be granted again after a rebuild.
- Shortcuts are changed in `hotkeys.txt` (see "Hotkeys"); `action = none` disables an action.
- `restore` works while the window still sits where DockGrid put it; full-screen windows are left alone.
- If Rectangle itself (or another window manager with the same shortcuts) is running, both will fire — keep one.

## Building from source

Requires Xcode Command Line Tools (`swiftc`, `iconutil`) and macOS 14+.

```sh
./build.sh
```

The release archive used by `install.sh` is built with `./release.sh` (a universal `build/DockGrid.zip`).

`build.sh` builds `~/Applications/Apps.app`, draws the icon (`icon.swift`), signs the app ad hoc and registers the `apps-launcher://` URL scheme.
After the build, drag `Apps.app` to the Dock.

The script also removes what gets in the way of the hotkeys:

- disables the system Spotlight shortcut (Cmd+Space) — re-enable it in System Settings → Keyboard → Keyboard Shortcuts → Spotlight;
- quits Maccy if it is running (Maccy's launch at login is turned off in its own settings);
- `./build.sh --disable-indexing` additionally turns off Spotlight indexing (`sudo mdutil -a -i off`; without the index, search in Finder and Mail stops working; revert with `sudo mdutil -a -i on`).

To leave everything untouched: `DOCKGRID_KEEP_SPOTLIGHT=1 ./build.sh`.

## Hotkeys

The app registers its global shortcuts itself (Carbon `RegisterEventHotKey`): no third-party tools are needed, and the Accessibility permission is required only for window management and Option+Enter pasting.
They are configured in `~/.config/apps-folder/hotkeys.txt`, which is created on first launch; actions it does not list yet (for example after an update) are appended to the end:

```
apps = alt+a
clipboard = cmd+space
left-half = ctrl+alt+left
…
```

Modifiers: `cmd`, `alt`, `ctrl`, `shift`; keys: letters, digits, `space`, `tab`, `return`, `delete`, arrows `left`/`right`/`up`/`down`, `=`, `-`, `[`, `]`, `,`, `.`, `/`, `f1`–`f12`. The value `none` leaves an action without a shortcut. Changes take effect after the app is restarted.
Hotkeys work only while the process is running (see "Launch at login"). For scripts there is a URL scheme: `open apps-launcher://toggle` and `open apps-launcher://clipboard`.

## Launch at login

The clipboard history is recorded and the hotkeys work only while the process is running. `install.sh` sets this up for you; after a manual build, make it start hidden at login with:

```sh
cp examples/local.dockgrid.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.dockgrid.plist
```

## Settings

Files in `~/.config/apps-folder/`, one app name per line, without `.app`:

| File | Purpose |
| --- | --- |
| `pinned.txt` | apps pinned to the top, in line order |
| `system.txt` | which apps from `/System/Applications` to show (other system apps are hidden) |
| `hidden.txt` | which third-party apps to hide |
| `hotkeys.txt` | global keyboard shortcuts |

Examples are in `examples/`. The list is built from `/Applications`, `~/Applications` (including first-level subfolders), `/System/Applications` and `Utilities`.

## How it works

- `main.swift` — the panel window, modes and switching; `Launcher.swift` — the app grid; `Clipboard.swift` — clipboard history (polls `NSPasteboard.changeCount` every 0.5 s); `Highlight.swift` — code detection and highlighting; `QRCode.swift` — reading QR codes from images; `Hotkeys.swift` — global hotkeys; `Windows.swift` — window management through the Accessibility API.
- The window is an `NSPanel` with the `nonactivatingPanel` style: it receives the keyboard without waiting for the app to be activated.
- A Dock click arrives as a reopen event, a hotkey as a Carbon event; both lead to the same `toggle()`.
- `tools/winvis.swift` — checks whether the window is visible on screen (for tests from the terminal).
