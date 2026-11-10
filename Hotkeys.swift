// Глобальные хоткеи через Carbon RegisterEventHotKey: не требуют разрешения Accessibility
// и сторонних программ. Настройка — ~/.config/apps-folder/hotkeys.txt, строки вида
//   apps = alt+a
//   clipboard = cmd+space
import AppKit
import Carbon.HIToolbox

enum HotKeys {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var refs: [EventHotKeyRef] = []
    private static var installed = false

    private static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "9": 25, "7": 26, "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40,
        "n": 45, "m": 46, "space": 49, "tab": 48, "return": 36, "enter": 36, "`": 50,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101,
        "f10": 109, "f11": 103, "f12": 111,
    ]
    private static let modifiers: [String: Int] = [
        "cmd": cmdKey, "command": cmdKey, "alt": optionKey, "opt": optionKey, "option": optionKey,
        "ctrl": controlKey, "control": controlKey, "shift": shiftKey,
    ]
    static let defaults = ["apps = alt+a", "clipboard = cmd+space"]

    /// "alt+a" → (keyCode, modifiers); nil, если сочетание не разобрано.
    static func parse(_ combo: String) -> (UInt32, UInt32)? {
        var mods = 0
        var key: UInt32?
        for part in combo.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if let m = modifiers[part] { mods |= m }
            else if let k = keyCodes[part], key == nil { key = k }
            else { return nil }
        }
        guard let key, mods != 0 else { return nil }
        return (key, UInt32(mods))
    }

    /// Читает hotkeys.txt (создаёт с умолчаниями, если файла нет) и регистрирует сочетания.
    static func setUp(_ handler: @escaping (Mode) -> Void) {
        if !FileManager.default.fileExists(atPath: Conf.dir.appendingPathComponent("hotkeys.txt").path) {
            Conf.write("hotkeys.txt", defaults)
        }
        if !installed {
            installed = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                HotKeys.actions[id.id]?()
                return noErr
            }, 1, &spec, nil, nil)
        }
        for ref in refs { UnregisterEventHotKey(ref) }
        refs = []
        actions = [:]
        var nextID: UInt32 = 1
        for line in Conf.read("hotkeys.txt") {
            let pair = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2 else { continue }
            let mode: Mode
            switch pair[0].lowercased() {
            case "apps": mode = .apps
            case "clipboard": mode = .clipboard
            default: NSLog("DockGrid: неизвестное действие в hotkeys.txt: %@", pair[0]); continue
            }
            guard let (key, mods) = parse(pair[1]) else {
                NSLog("DockGrid: не разобрано сочетание: %@", pair[1]); continue
            }
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(key, mods, EventHotKeyID(signature: OSType(0x44474B59), id: nextID),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                actions[nextID] = { handler(mode) }
                NSLog("DockGrid: хоткей %@ = %@ зарегистрирован", pair[0], pair[1])
            } else {
                NSLog("DockGrid: хоткей %@ = %@ не зарегистрирован, код %d", pair[0], pair[1], status)
            }
            nextID += 1
        }
    }
}
