// Окно настройки сочетаний клавиш: клик по полю — запись нового сочетания, × — снять.
// Всё хранится в hotkeys.txt (см. Hotkeys.swift), окно лишь редактирует этот файл.
// Открывается шестерёнкой в сетке приложений, Cmd+, в панели или `open apps-launcher://settings`.
import AppKit
import SwiftUI

final class SettingsModel: ObservableObject {
    @Published var combos: [String: String] = [:]
    @Published var recording: String?

    func refresh() { combos = HotKeys.current() }

    /// На время записи свои хоткеи снимаются, иначе нажатие перехватит Carbon и оно не дойдёт до окна.
    func record(_ name: String) {
        if recording == name { cancel(); return }
        recording = name
        HotKeys.suspend()
    }

    func cancel() {
        guard recording != nil else { return }
        recording = nil
        HotKeys.reload()
    }

    func clear(_ name: String) {
        recording = nil
        HotKeys.set(name, nil)
        refresh()
    }

    func key(_ e: NSEvent) -> NSEvent? {
        let flags = e.modifierFlags
        guard let name = recording else {
            if e.keyCode == 13, flags.contains(.command) { Settings.window?.close(); return nil }
            return e
        }
        var parts: [String] = []
        if flags.contains(.control) { parts.append("ctrl") }
        if flags.contains(.option) { parts.append("alt") }
        if flags.contains(.shift) { parts.append("shift") }
        if flags.contains(.command) { parts.append("cmd") }
        if e.keyCode == 53, parts.isEmpty { cancel(); return nil }
        // Без модификатора глобальное сочетание отобрало бы клавишу у всех программ.
        guard !parts.isEmpty, let key = HotKeys.keyName(e.keyCode) else { NSSound.beep(); return nil }
        recording = nil
        HotKeys.set(name, (parts + [key]).joined(separator: "+"))
        refresh()
        return nil
    }
}

enum Settings {
    private final class Delegate: NSObject, NSWindowDelegate {
        func windowDidResignKey(_ note: Notification) { Settings.model.cancel() }
        func windowWillClose(_ note: Notification) { Settings.model.cancel() }
    }

    static var window: NSWindow?
    static let model = SettingsModel()
    private static let delegate = Delegate()
    static var isOpen: Bool { window?.isVisible ?? false }

    static func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 720),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Сочетания клавиш"
            w.isReleasedWhenClosed = false
            w.delegate = delegate
            w.contentView = NSHostingView(rootView: SettingsView(model: model))
            w.center()
            window = w
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
                guard let w = Settings.window, w.isKeyWindow else { return e }
                return model.key(e)
            }
        }
        model.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// "ctrl+alt+left" → "⌃⌥←".
    static func symbols(_ combo: String) -> String {
        let parts = combo.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        let mods = [("ctrl", "⌃"), ("alt", "⌥"), ("shift", "⇧"), ("cmd", "⌘")]
        let keys = ["left": "←", "right": "→", "up": "↑", "down": "↓", "return": "↩", "delete": "⌫",
                    "tab": "⇥", "space": "Space"]
        let key = parts.last ?? ""
        return mods.filter { parts.dropLast().contains($0.0) }.map(\.1).joined() + (keys[key] ?? key.uppercased())
    }
}

private enum Glyph {
    case symbol(String)
    case area(WindowAction)
}

private struct Entry: Identifiable {
    let id: String
    let title: String
    let glyph: Glyph
}

private let groups: [[Entry]] = {
    func w(_ actions: WindowAction...) -> [Entry] {
        actions.map { a in
            let symbols: [WindowAction: String] = [.larger: "plus", .smaller: "minus", .restore: "arrow.uturn.backward",
                                                   .nextDisplay: "chevron.right", .prevDisplay: "chevron.left"]
            return Entry(id: a.rawValue, title: a.title, glyph: symbols[a].map(Glyph.symbol) ?? .area(a))
        }
    }
    return [
        [Entry(id: "apps", title: "Сетка приложений", glyph: .symbol("square.grid.3x3")),
         Entry(id: "clipboard", title: "История буфера", glyph: .symbol("doc.on.clipboard"))],
        w(.leftHalf, .rightHalf, .topHalf, .bottomHalf),
        w(.topLeft, .topRight, .bottomLeft, .bottomRight),
        w(.firstThird, .centerThird, .lastThird, .firstTwoThirds, .lastTwoThirds),
        w(.maximize, .almostMaximize, .maximizeHeight, .larger, .smaller, .center, .restore),
        w(.nextDisplay, .prevDisplay),
    ]
}()

/// Миниатюра экрана с закрашенной областью, которую займёт окно.
private struct GlyphView: View {
    let glyph: Glyph
    var body: some View {
        switch glyph {
        case .symbol(let name):
            Image(systemName: name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .frame(width: 22, height: 14)
        case .area(let action):
            let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
            let r = WindowManager.rect(action, step: 0, current: CGRect(x: 0.3, y: 0.25, width: 0.4, height: 0.5), screen: unit)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.primary.opacity(0.18))
                Rectangle().fill(Color.primary.opacity(0.6))
                    .frame(width: 22 * r.width, height: 14 * r.height).offset(x: 22 * r.minX, y: 14 * r.minY)
            }
            .frame(width: 22, height: 14).clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}

private struct Row: View {
    let entry: Entry
    @ObservedObject var model: SettingsModel

    var body: some View {
        let combo = model.combos[entry.id], recording = model.recording == entry.id
        HStack(spacing: 8) {
            Text(entry.title).frame(width: 170, alignment: .trailing)
            GlyphView(glyph: entry.glyph)
            Button { model.record(entry.id) } label: {
                Text(recording ? "Нажмите сочетание…" : combo.map(Settings.symbols) ?? "Записать сочетание")
                    .font(.system(size: 13, weight: combo != nil && !recording ? .medium : .regular))
                    .foregroundStyle(combo != nil && !recording ? .primary : .secondary)
                    .frame(width: 170, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(recording ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.1)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).focusable(false)
            Button { model.clear(entry.id) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 22, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).focusable(false).foregroundStyle(.secondary)
            .opacity(combo == nil ? 0 : 1).disabled(combo == nil)
            .help("Снять сочетание")
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(groups.indices, id: \.self) { g in
                        ForEach(groups[g]) { Row(entry: $0, model: model) }
                        if g < groups.count - 1 { Spacer().frame(height: 10) }
                    }
                }
                .padding(.vertical, 18).frame(maxWidth: .infinity)
            }
            Divider()
            Text("Клик по полю — записать сочетание, Esc — отмена. Занятое сочетание снимается с прежнего действия.")
                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .frame(width: 470, height: 720)
    }
}
