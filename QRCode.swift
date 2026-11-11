// QR-коды на картинках из буфера: содержимое показывается под предпросмотром,
// ссылки http(s) открываются по клику. Распознавание — CoreImage, только для выбранной записи.
import AppKit
import CoreImage
import SwiftUI

enum QRCode {
    /// Содержимое QR-кодов на картинке; пусто, если кодов нет.
    static func read(_ url: URL) -> [String] {
        guard let image = CIImage(contentsOf: url),
              let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                        options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else { return [] }
        var seen = Set<String>(), out: [String] = []
        for case let code as CIQRCodeFeature in detector.features(in: image) {
            if let text = code.messageString, !text.isEmpty, seen.insert(text).inserted { out.append(text) }
        }
        return out
    }

    /// Ссылка, которую можно открыть по клику: только http и https с хостом.
    static func link(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host?.isEmpty == false else { return nil }
        return url
    }
}

struct QRLinks: View {
    let item: ClipItem
    @ObservedObject var model: ClipModel
    @State private var found: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(found, id: \.self) { text in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "qrcode").foregroundStyle(.secondary)
                    if let url = QRCode.link(text) {
                        Button {
                            model.onClose?(false)
                            NSWorkspace.shared.open(url)
                        } label: {
                            Text(text).underline().lineLimit(2).truncationMode(.middle).multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain).foregroundStyle(Color.accentColor).help("Открыть в браузере")
                    } else {
                        Text(text).lineLimit(3).textSelection(.enabled)
                    }
                    Spacer(minLength: 6)
                    Button("Скопировать") {
                        // Обычная запись в буфер: текст из кода попадёт в историю отдельной записью.
                        model.onClose?(true)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .font(.system(size: 12))
            }
        }
        .task(id: item.id) {
            found = []
            guard let url = model.store.imageURL(item) else { return }
            let result = await Task.detached(priority: .userInitiated) { QRCode.read(url) }.value
            if !Task.isCancelled { found = result }
        }
    }
}
