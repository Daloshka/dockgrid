// Управление окнами в духе Rectangle: хоткей двигает активное окно чужого приложения
// в половину, угол, треть экрана, на соседний монитор и т. п.
// Работает через Accessibility API, поэтому Apps.app нужно разрешение
// «Системные настройки → Конфиденциальность и безопасность → Универсальный доступ».
import AppKit
import ApplicationServices

enum WindowAction: String, CaseIterable {
    case leftHalf = "left-half", rightHalf = "right-half", topHalf = "top-half", bottomHalf = "bottom-half"
    case topLeft = "top-left", topRight = "top-right", bottomLeft = "bottom-left", bottomRight = "bottom-right"
    case firstThird = "first-third", centerThird = "center-third", lastThird = "last-third"
    case firstTwoThirds = "first-two-thirds", lastTwoThirds = "last-two-thirds"
    case maximize, almostMaximize = "almost-maximize", maximizeHeight = "maximize-height"
    case center, larger, smaller, restore
    case nextDisplay = "next-display", prevDisplay = "prev-display"

    /// Название в окне настроек.
    var title: String {
        switch self {
        case .leftHalf: "Левая половина"
        case .rightHalf: "Правая половина"
        case .topHalf: "Верхняя половина"
        case .bottomHalf: "Нижняя половина"
        case .topLeft: "Левый верхний угол"
        case .topRight: "Правый верхний угол"
        case .bottomLeft: "Левый нижний угол"
        case .bottomRight: "Правый нижний угол"
        case .firstThird: "Первая треть"
        case .centerThird: "Центральная треть"
        case .lastThird: "Последняя треть"
        case .firstTwoThirds: "Первые две трети"
        case .lastTwoThirds: "Последние две трети"
        case .maximize: "Развернуть"
        case .almostMaximize: "Почти развернуть"
        case .maximizeHeight: "На всю высоту"
        case .center: "По центру"
        case .larger: "Увеличить"
        case .smaller: "Уменьшить"
        case .restore: "Вернуть как было"
        case .nextDisplay: "Следующий монитор"
        case .prevDisplay: "Предыдущий монитор"
        }
    }

    /// Сочетания по умолчанию — как в Rectangle.
    var defaultKey: String {
        switch self {
        case .leftHalf: "ctrl+alt+left"
        case .rightHalf: "ctrl+alt+right"
        case .topHalf: "ctrl+alt+up"
        case .bottomHalf: "ctrl+alt+down"
        case .topLeft: "ctrl+alt+u"
        case .topRight: "ctrl+alt+i"
        case .bottomLeft: "ctrl+alt+j"
        case .bottomRight: "ctrl+alt+k"
        case .firstThird: "ctrl+alt+d"
        case .centerThird: "ctrl+alt+f"
        case .lastThird: "ctrl+alt+g"
        case .firstTwoThirds: "ctrl+alt+e"
        case .lastTwoThirds: "ctrl+alt+t"
        case .maximize: "ctrl+alt+return"
        case .almostMaximize: "none"
        case .maximizeHeight: "ctrl+alt+shift+up"
        case .center: "ctrl+alt+c"
        case .larger: "ctrl+alt+="
        case .smaller: "ctrl+alt+-"
        case .restore: "ctrl+alt+delete"
        case .nextDisplay: "ctrl+alt+cmd+right"
        case .prevDisplay: "ctrl+alt+cmd+left"
        }
    }
}

enum WindowManager {
    /// Что мы сделали с окном: исходная рамка (для restore) и последняя выставленная (для циклов).
    private struct Record {
        let window: AXUIElement
        var original: CGRect
        var applied: CGRect
        var action: WindowAction
        var step: Int
    }
    private static var records: [Record] = []

    static func perform(_ action: WindowAction) {
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(prompt) else {
            NSLog("DockGrid: для управления окнами нужно разрешение «Универсальный доступ»")
            return
        }
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let app = AXUIElementCreateApplication(front.processIdentifier)
        guard let win = focusedWindow(app), let cur = frame(win), !bool(win, "AXFullScreen") else { NSSound.beep(); return }
        let screens = screenRects()
        guard let screen = screens.max(by: { area($0.intersection(cur)) < area($1.intersection(cur)) }) else { return }

        // Запись действует, пока окно стоит там, куда мы его поставили; сдвинули руками — начинаем заново.
        let idx = records.firstIndex { CFEqual($0.window, win) }
        let known = idx.map { near(records[$0].applied, cur) } ?? false
        var original = cur, step = 0
        if let idx, known {
            original = records[idx].original
            if records[idx].action == action { step = records[idx].step + 1 }
        }
        if let idx { records.remove(at: idx) }

        let target: CGRect
        switch action {
        case .restore:
            guard known else { return }
            _ = apply(original, to: win, app: app)
            return
        case .nextDisplay, .prevDisplay:
            guard screens.count > 1, let i = screens.firstIndex(of: screen) else { return }
            let to = screens[(i + (action == .nextDisplay ? 1 : screens.count - 1)) % screens.count]
            // Переносим с сохранением пропорций относительно рабочей области экрана.
            let kx = to.width / screen.width, ky = to.height / screen.height
            target = CGRect(x: to.minX + (cur.minX - screen.minX) * kx, y: to.minY + (cur.minY - screen.minY) * ky,
                            width: cur.width * kx, height: cur.height * ky)
        default:
            target = rect(action, step: step, current: cur, screen: screen)
        }
        let applied = apply(target, to: win, app: app)
        records.append(Record(window: win, original: original, applied: applied, action: action, step: step))
        if records.count > 50 { records.removeFirst() }
    }

    /// Целевая рамка в координатах AX (начало — левый верхний угол главного экрана, y растёт вниз).
    static func rect(_ action: WindowAction, step: Int, current c: CGRect, screen s: CGRect) -> CGRect {
        func part(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: s.minX + s.width * x, y: s.minY + s.height * y, width: s.width * w, height: s.height * h)
        }
        // На вертикальном мониторе трети режутся по высоте.
        func third(_ from: CGFloat, _ len: CGFloat) -> CGRect {
            s.height > s.width ? part(0, from, 1, len) : part(from, 0, len, 1)
        }
        // Повтор left-half/right-half перебирает ширину: 1/2 → 2/3 → 1/3.
        let f: CGFloat = [1.0 / 2, 2.0 / 3, 1.0 / 3][step % 3]
        func fit(_ r: CGRect) -> CGRect {
            let w = min(r.width, s.width), h = min(r.height, s.height)
            return CGRect(x: min(max(r.minX, s.minX), s.maxX - w), y: min(max(r.minY, s.minY), s.maxY - h), width: w, height: h)
        }
        switch action {
        case .leftHalf: return part(0, 0, f, 1)
        case .rightHalf: return part(1 - f, 0, f, 1)
        case .topHalf: return part(0, 0, 1, 0.5)
        case .bottomHalf: return part(0, 0.5, 1, 0.5)
        case .topLeft: return part(0, 0, 0.5, 0.5)
        case .topRight: return part(0.5, 0, 0.5, 0.5)
        case .bottomLeft: return part(0, 0.5, 0.5, 0.5)
        case .bottomRight: return part(0.5, 0.5, 0.5, 0.5)
        case .firstThird: return third(0, 1.0 / 3)
        case .centerThird: return third(1.0 / 3, 1.0 / 3)
        case .lastThird: return third(2.0 / 3, 1.0 / 3)
        case .firstTwoThirds: return third(0, 2.0 / 3)
        case .lastTwoThirds: return third(1.0 / 3, 2.0 / 3)
        case .maximize: return s
        case .almostMaximize: return part(0.05, 0.05, 0.9, 0.9)
        case .maximizeHeight: return CGRect(x: c.minX, y: s.minY, width: c.width, height: s.height)
        case .center:
            let w = min(c.width, s.width), h = min(c.height, s.height)
            return CGRect(x: s.midX - w / 2, y: s.midY - h / 2, width: w, height: h)
        case .larger: return fit(c.insetBy(dx: -30, dy: -30))
        case .smaller:
            let dx: CGFloat = c.width - 60 >= s.width / 4 ? 30 : 0, dy: CGFloat = c.height - 60 >= s.height / 4 ? 30 : 0
            return fit(c.insetBy(dx: dx, dy: dy))
        case .restore, .nextDisplay, .prevDisplay: return c
        }
    }

    // MARK: - Экраны

    /// Рабочие области экранов (без меню и Dock) в координатах AX, слева направо.
    private static func screenRects() -> [CGRect] {
        guard let primary = NSScreen.screens.first else { return [] }
        return NSScreen.screens.map { $0.visibleFrame }
            .map { CGRect(x: $0.minX, y: primary.frame.maxY - $0.maxY, width: $0.width, height: $0.height) }
            .sorted { ($0.minX, $0.minY) < ($1.minX, $1.minY) }
    }

    private static func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }

    private static func near(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 2 && abs(a.minY - b.minY) < 2 && abs(a.width - b.width) < 2 && abs(a.height - b.height) < 2
    }

    // MARK: - Accessibility

    private static func value(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
        var ref: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success ? ref : nil
    }

    private static func bool(_ el: AXUIElement, _ attr: String) -> Bool {
        (value(el, attr) as? Bool) ?? false
    }

    private static func focusedWindow(_ app: AXUIElement) -> AXUIElement? {
        guard let ref = value(app, kAXFocusedWindowAttribute) ?? value(app, kAXMainWindowAttribute),
              CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    private static func frame(_ win: AXUIElement) -> CGRect? {
        guard let p = value(win, kAXPositionAttribute), let s = value(win, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Ставит рамку и возвращает фактическую: приложение может округлить размер (терминалы) или упереться в минимум.
    private static func apply(_ r: CGRect, to win: AXUIElement, app: AXUIElement) -> CGRect {
        // С включённым AXEnhancedUserInterface (VoiceOver и подобные) окна анимируются и встают неточно.
        let enhanced = bool(app, "AXEnhancedUserInterface")
        if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
        var origin = r.origin, size = r.size
        guard let p = AXValueCreate(.cgPoint, &origin), let s = AXValueCreate(.cgSize, &size) else { return r }
        // Размер — позиция — размер: при переносе на другой экран первый размер ограничен старым экраном.
        AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, s)
        AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, p)
        AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, s)
        if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
        return frame(win) ?? r
    }
}
