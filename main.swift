// DockGrid — лаунчер приложений и история буфера обмена в одном окне-панели.
// Процесс живёт постоянно, окно прячется; пока оно скрыто, интерфейс выгружен.
//   клик в Dock, хоткей apps (Option+A)        — сетка приложений
//   хоткей clipboard (Cmd+Space)                — история буфера обмена
//   хоткеи окон (Ctrl+Option+стрелки и др.)     — раскладка окон, см. Windows.swift
//   шестерёнка в сетке, Cmd+, в панели          — окно сочетаний клавиш, см. Settings.swift
// Хоткеи глобальные, см. Hotkeys.swift; схема apps-launcher:// оставлена для скриптов.
import AppKit
import SwiftUI

final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
}

enum Mode { case apps, clipboard }

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: Panel!
    var mode = Mode.apps
    var visible = false
    var launcher: Model?
    var clip: ClipModel?
    private var lastShow = Date.distantPast
    private var lastHotkey: [Mode: Date] = [:]
    private var lastAutoHide = Date.distantPast
    private let size = NSSize(width: 868, height: 640)
    private let background = CommandLine.arguments.contains("--background")
    private let digitKeys: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    func applicationDidFinishLaunching(_ note: Notification) {
        setUp()
        if !visible && !background { show(.apps) }
    }

    // Вызывается лениво: при холодном старте по хоткею URL-событие приходит раньше didFinishLaunching.
    private func setUp() {
        guard window == nil else { return }
        // nonactivatingPanel получает клавиатуру, даже если система не отдала приложению фокус.
        window = Panel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                       backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in self?.handleKey(e) ?? e }
        ClipStore.shared.start()
        WindowManager.resetStaleGrant()
        HotKeys.setUp { [weak self] mode in self?.toggle(mode) }
    }

    private func handleKey(_ e: NSEvent) -> NSEvent? {
        guard visible else { return e }
        if e.keyCode == 53 { hide(restoreFocus: true); return nil }
        let cmd = e.modifierFlags.contains(.command), opt = e.modifierFlags.contains(.option)
        if cmd, e.keyCode == 43 { hide(restoreFocus: false); Settings.show(); return nil }
        switch mode {
        case .apps:
            guard let m = launcher else { return e }
            switch e.keyCode {
            case 36, 76: m.launchSelected()
            case 123: m.move(dx: -1, dy: 0)
            case 124: m.move(dx: 1, dy: 0)
            case 125: m.move(dx: 0, dy: 1)
            case 126: m.move(dx: 0, dy: -1)
            default: return e
            }
        case .clipboard:
            guard let m = clip else { return e }
            switch e.keyCode {
            case 125: m.move(1)
            case 126: m.move(-1)
            case 36, 76: m.activate(m.selected, paste: opt)
            case 51 where cmd: m.deleteSelected()
            default:
                guard cmd, let n = digitKeys.firstIndex(of: e.keyCode) else { return e }
                m.activate(n, paste: opt)
            }
        }
        return nil
    }

    func show(_ newMode: Mode) {
        setUp()
        mode = newMode
        launcher = nil
        clip = nil
        switch newMode {
        case .apps:
            let m = Model()
            m.onClose = { [weak self] restore in self?.hide(restoreFocus: restore) }
            launcher = m
            window.contentView = NSHostingView(rootView: LauncherView(model: m))
        case .clipboard:
            let m = ClipModel()
            m.onClose = { [weak self] restore in self?.hide(restoreFocus: restore) }
            clip = m
            window.contentView = NSHostingView(rootView: ClipView(model: m))
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            window.setFrame(NSRect(x: f.midX - size.width / 2, y: f.midY - size.height / 2,
                                   width: size.width, height: size.height), display: true)
        }
        visible = true
        lastShow = Date()
        window.makeKeyAndOrderFront(nil)
    }

    func hide(restoreFocus: Bool) {
        guard visible else { return }
        visible = false
        window.orderOut(nil)
        window.contentView = nil
        launcher = nil
        clip = nil
        // NSApp.hide спрятал бы и открытое окно настроек.
        if restoreFocus && !Settings.isOpen { NSApp.hide(nil) }
    }

    // Каждый сигнал — ровно одно переключение. Если этот же клик уже спрятал окно потерей
    // фокуса (lastAutoHide), он считается «скрыть», а не «показать заново».
    func toggle(_ target: Mode) {
        if visible && target != mode { show(target); return }
        let wasVisible = visible || Date().timeIntervalSince(lastAutoHide) < 0.4
        lastAutoHide = .distantPast
        if !wasVisible { show(target) }
        else if visible { hide(restoreFocus: true) }
        else if !Settings.isOpen { NSApp.hide(nil) }
    }

    func windowDidResignKey(_ note: Notification) {
        guard visible else { return }
        // Сразу после показа фокус может мигнуть при активации приложения — возвращаем его.
        if Date().timeIntervalSince(lastShow) < 1.0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, self.visible, !self.window.isKeyWindow else { return }
                self.window.makeKeyAndOrderFront(nil)
            }
            return
        }
        lastAutoHide = Date()
        hide(restoreFocus: false)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        toggle(.apps)
        return false
    }

    // Вызов из скриптов (open apps-launcher://…). Сигналы чаще 0,5 с пропускаем.
    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.first?.host == "settings" { Settings.show(); return }
        let target: Mode = urls.first?.host == "clipboard" ? .clipboard : .apps
        let gap = Date().timeIntervalSince(lastHotkey[target] ?? .distantPast)
        lastHotkey[target] = Date()
        if gap >= 0.5 { toggle(target) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
