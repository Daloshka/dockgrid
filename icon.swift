import AppKit
let out = CommandLine.arguments[1]
func rgb(_ h: Int) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: 1)
}
for (px, name) in [(16,"16x16"),(32,"16x16@2x"),(32,"32x32"),(64,"32x32@2x"),(128,"128x128"),(256,"128x128@2x"),(256,"256x256"),(512,"256x256@2x"),(512,"512x512"),(1024,"512x512@2x")] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px), m = s * 0.098, side = s - 2 * m
    let rect = NSRect(x: m, y: m, width: side, height: side)
    let shape = NSBezierPath(roundedRect: rect, xRadius: side * 0.225, yRadius: side * 0.225)

    // тень под плиткой
    NSGraphicsContext.saveGraphicsState()
    let drop = NSShadow()
    drop.shadowColor = NSColor.black.withAlphaComponent(0.35)
    drop.shadowBlurRadius = s * 0.03
    drop.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    drop.set()
    rgb(0x4B3FD6).setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // фон: синий → фиолетовый → розовый
    NSGradient(colors: [rgb(0x3D7BFF), rgb(0x6A4BFF), rgb(0xC04BFF), rgb(0xFF5FA2)],
               atLocations: [0, 0.4, 0.75, 1], colorSpace: .sRGB)!.draw(in: shape, angle: -55)

    // мягкий блик сверху
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(starting: NSColor.white.withAlphaComponent(0.28), ending: NSColor.white.withAlphaComponent(0))!
        .draw(in: NSRect(x: m, y: m + side * 0.5, width: side, height: side * 0.5), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // сетка 3×3 белых плиток
    let inset = side * 0.2, area = side - 2 * inset, gap = area * 0.1, cell = (area - 2 * gap) / 3
    NSGraphicsContext.saveGraphicsState()
    let soft = NSShadow()
    soft.shadowColor = rgb(0x2A1A7A).withAlphaComponent(0.35)
    soft.shadowBlurRadius = s * 0.02
    soft.shadowOffset = NSSize(width: 0, height: -s * 0.008)
    soft.set()
    for r in 0..<3 { for c in 0..<3 {
        let x = m + inset + CGFloat(c) * (cell + gap), y = m + inset + CGFloat(2 - r) * (cell + gap)
        NSColor.white.withAlphaComponent(0.97 - CGFloat(r + c) * 0.045).setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: cell, height: cell), xRadius: cell * 0.3, yRadius: cell * 0.3).fill()
    } }
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.current = nil
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
