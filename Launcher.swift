// Сетка приложений: сканирование папок, закрепление, поиск.
// Настройки: ~/.config/apps-folder/{pinned,system,hidden}.txt — по одному названию в строке.
import AppKit
import SwiftUI

enum Conf {
    static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/apps-folder")
    static func read(_ file: String) -> [String] {
        guard let text = try? String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
    static func write(_ file: String, _ lines: [String]) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? (lines.joined(separator: "\n") + "\n").write(to: dir.appendingPathComponent(file), atomically: true, encoding: .utf8)
    }
}

struct AppItem: Identifiable, Equatable {
    let name: String
    let url: URL
    var id: String { url.path }
}

struct AppSection {
    let title: String?
    let items: [AppItem]
}

final class Model: ObservableObject {
    @Published var query = "" { didSet { selected = 0 } }
    @Published var pinned: [String] = Conf.read("pinned.txt")
    @Published var all: [AppItem] = []
    @Published var selected = 0
    let cols = 8
    var onClose: ((_ restoreFocus: Bool) -> Void)?
    private var icons: [String: NSImage] = [:]

    init() { all = Self.scan() }

    static func scan() -> [AppItem] {
        let fm = FileManager.default
        let userApps = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        let system = Set(Conf.read("system.txt")), hidden = Set(Conf.read("hidden.txt"))
        let own = Bundle.main.bundleURL.standardizedFileURL.path
        func list(_ dir: URL) -> [URL] {
            (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        }
        var dirs: [(URL, Bool)] = [(URL(fileURLWithPath: "/Applications"), false), (userApps, false)]
        for sub in list(userApps) where sub.pathExtension != "app" && sub.hasDirectoryPath { dirs.append((sub, false)) }
        dirs.append((URL(fileURLWithPath: "/System/Applications"), true))
        dirs.append((URL(fileURLWithPath: "/System/Applications/Utilities"), true))
        var seen = Set<String>(), out: [AppItem] = []
        for (dir, isSystem) in dirs {
            for url in list(dir) where url.pathExtension == "app" {
                let name = url.deletingPathExtension().lastPathComponent
                if url.standardizedFileURL.path == own || hidden.contains(name) { continue }
                if isSystem && !system.contains(name) { continue }
                if seen.insert(name).inserted { out.append(AppItem(name: name, url: url.resolvingSymlinksInPath())) }
            }
        }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var sections: [AppSection] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            func rank(_ a: AppItem) -> Int {
                (a.name.lowercased().hasPrefix(q.lowercased()) ? 0 : 2) + (pinned.contains(a.name) ? 0 : 1)
            }
            let hits = all.filter { $0.name.localizedCaseInsensitiveContains(q) }
                .enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
            return hits.isEmpty ? [] : [AppSection(title: nil, items: hits)]
        }
        let top = pinned.compactMap { n in all.first { $0.name == n } }
        let rest = all.filter { !pinned.contains($0.name) }
        var out: [AppSection] = []
        if !top.isEmpty { out.append(AppSection(title: "Закреплённые", items: top)) }
        if !rest.isEmpty { out.append(AppSection(title: top.isEmpty ? nil : "Все приложения", items: rest)) }
        return out
    }

    func icon(_ item: AppItem) -> NSImage {
        if let hit = icons[item.id] { return hit }
        let img = NSWorkspace.shared.icon(forFile: item.url.path)
        icons[item.id] = img
        return img
    }

    func move(dx: Int, dy: Int) {
        let s = sections
        let total = s.reduce(0) { $0 + $1.items.count }
        guard total > 0 else { return }
        if dx != 0 { selected = min(max(selected + dx, 0), total - 1); return }
        var sec = 0, i = selected
        while sec < s.count - 1 && i >= s[sec].items.count { i -= s[sec].items.count; sec += 1 }
        let start = selected - i, count = s[sec].items.count, col = i % cols
        if dy > 0 {
            if i + cols < count { selected = start + i + cols }
            else if i / cols < (count - 1) / cols { selected = start + count - 1 }
            else if sec + 1 < s.count { selected = start + count + min(col, s[sec + 1].items.count - 1) }
        } else {
            if i - cols >= 0 { selected = start + i - cols }
            else if sec > 0 {
                let prev = s[sec - 1].items.count
                selected = start - prev + min(((prev - 1) / cols) * cols + col, prev - 1)
            }
        }
    }

    func launchSelected() {
        let flat = sections.flatMap(\.items)
        if flat.indices.contains(selected) { launch(flat[selected]) }
    }
    func launch(_ item: AppItem) {
        onClose?(false)
        NSWorkspace.shared.open(item.url)
    }
    func reveal(_ item: AppItem) {
        onClose?(false)
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }
    func togglePin(_ item: AppItem) {
        if pinned.contains(item.name) { pinned.removeAll { $0 == item.name } } else { pinned.append(item.name) }
        Conf.write("pinned.txt", pinned)
        selected = 0
    }
    func hide(_ item: AppItem) {
        if item.url.path.hasPrefix("/System/") {
            Conf.write("system.txt", Conf.read("system.txt").filter { $0 != item.name })
        } else {
            Conf.write("hidden.txt", Conf.read("hidden.txt") + [item.name])
        }
        if pinned.contains(item.name) { togglePin(item) }
        all = Self.scan()
    }
}

struct Blur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow; v.blendingMode = .behindWindow; v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

struct Cell: View {
    let item: AppItem
    let isSelected: Bool
    @ObservedObject var model: Model
    @State private var hovering = false

    var body: some View {
        let isPinned = model.pinned.contains(item.name)
        VStack(spacing: 6) {
            Image(nsImage: model.icon(item)).resizable().frame(width: 64, height: 64)
            Text(item.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
        }
        .frame(width: 100, height: 100)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(Color.primary.opacity(isSelected ? 0.16 : (hovering ? 0.08 : 0))))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { model.launch(item) }
        .contextMenu {
            Button(isPinned ? "Открепить" : "Закрепить сверху") { model.togglePin(item) }
            Button("Показать в Finder") { model.reveal(item) }
            Divider()
            Button("Скрыть из списка") { model.hide(item) }
        }
    }
}

struct LauncherView: View {
    @ObservedObject var model: Model
    @FocusState private var focused: Bool

    var body: some View {
        let secs = model.sections
        let offsets = secs.indices.map { i in secs[..<i].reduce(0) { $0 + $1.items.count } }
        let flat = secs.flatMap(\.items)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Поиск приложения", text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 18)).focused($focused)
                Button { model.onClose?(false); Settings.show() } label: {
                    Image(systemName: "gearshape").font(.system(size: 15)).foregroundStyle(.secondary)
                        .frame(width: 26, height: 26).contentShape(Rectangle())
                }
                .buttonStyle(.plain).focusable(false).help("Сочетания клавиш (Cmd+,)")
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if secs.isEmpty {
                            Text("Ничего не найдено").foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(.top, 60)
                        }
                        ForEach(secs.indices, id: \.self) { s in
                            if let title = secs[s].title {
                                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                                    .padding(.leading, 10).padding(.top, s == 0 ? 0 : 10)
                            }
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(100), spacing: 4), count: model.cols), spacing: 4) {
                                ForEach(Array(secs[s].items.enumerated()), id: \.element.id) { i, item in
                                    Cell(item: item, isSelected: offsets[s] + i == model.selected, model: model)
                                        .id(item.id)
                                }
                            }
                        }
                    }
                    .padding(14)
                }
                .onChange(of: model.selected) { _, new in
                    if flat.indices.contains(new) { proxy.scrollTo(flat[new].id) }
                }
            }
        }
        .frame(width: 868, height: 640)
        .background(Blur())
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .onAppear { focused = true }
    }
}

