import AppKit

// Renders three candidate Dock icons for kkguai into the folder given as argv[1].
// usage: swift scripts/icon-preview.swift /tmp/kkicons

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    if let d = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { return f }
    return base
}

func card(_ r: NSRect, _ colors: [NSColor], radius: CGFloat = 104, angle: CGFloat = -90) {
    let p = NSBezierPath(roundedRect: r.insetBy(dx: 40, dy: 40), xRadius: radius, yRadius: radius)
    NSGradient(colors: colors)?.draw(in: p, angle: angle)
}

func centered(_ text: NSAttributedString, in r: NSRect, dy: CGFloat = 0) {
    let s = text.size()
    text.draw(at: NSPoint(x: r.midX - s.width / 2, y: r.midY - s.height / 2 + dy))
}

// A — KK monogram on a blue card.
func iconA(_ r: NSRect) {
    card(r, [NSColor(calibratedRed: 0.33, green: 0.60, blue: 1, alpha: 1),
             NSColor(calibratedRed: 0.09, green: 0.23, blue: 0.78, alpha: 1)])
    let text = NSAttributedString(string: "kk", attributes: [
        .font: rounded(270, .bold),
        .foregroundColor: NSColor.white,
        .kern: -18,
    ])
    centered(text, in: r, dy: -10)
}

// B — a friendly little monster (kkguai = 怪).
func iconB(_ r: NSRect) {
    card(r, [NSColor(calibratedRed: 0.62, green: 0.36, blue: 0.96, alpha: 1),
             NSColor(calibratedRed: 0.98, green: 0.45, blue: 0.65, alpha: 1)], angle: 45)

    // Body.
    NSColor.white.setFill()
    let body = NSRect(x: r.midX - 150, y: r.minY + 118, width: 300, height: 300)
    NSBezierPath(roundedRect: body, xRadius: 132, yRadius: 132).fill()

    // Antennae.
    let ink = NSColor(calibratedRed: 0.24, green: 0.12, blue: 0.42, alpha: 1)
    ink.setStroke()
    for dx: CGFloat in [-86, 86] {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: r.midX + dx, y: body.maxY - 30))
        p.curve(to: NSPoint(x: r.midX + dx * 1.35, y: body.maxY + 62),
                controlPoint1: NSPoint(x: r.midX + dx, y: body.maxY + 30),
                controlPoint2: NSPoint(x: r.midX + dx * 1.3, y: body.maxY + 24))
        p.lineWidth = 14
        p.lineCapStyle = .round
        p.stroke()
        ink.setFill()
        NSBezierPath(ovalIn: NSRect(x: r.midX + dx * 1.35 - 20, y: body.maxY + 42, width: 40, height: 40)).fill()
    }

    // Eyes.
    let eyeY = body.midY + 34
    for dx: CGFloat in [-66, 66] {
        let eye = NSRect(x: r.midX + dx - 44, y: eyeY - 48, width: 88, height: 96)
        NSColor(calibratedRed: 0.16, green: 0.10, blue: 0.30, alpha: 1).setFill()
        NSBezierPath(ovalIn: eye).fill()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: eye.minX + 50, y: eye.minY + 56, width: 24, height: 24)).fill()
    }

    // Smile.
    let smile = NSBezierPath()
    smile.move(to: NSPoint(x: r.midX - 52, y: eyeY - 72))
    smile.curve(to: NSPoint(x: r.midX + 52, y: eyeY - 72),
                controlPoint1: NSPoint(x: r.midX - 26, y: eyeY - 112),
                controlPoint2: NSPoint(x: r.midX + 26, y: eyeY - 112))
    smile.lineWidth = 14
    smile.lineCapStyle = .round
    ink.setStroke()
    smile.stroke()
}

// C — a remote window with a K inside.
func iconC(_ r: NSRect) {
    card(r, [NSColor(calibratedRed: 0.11, green: 0.16, blue: 0.33, alpha: 1),
             NSColor(calibratedRed: 0.04, green: 0.06, blue: 0.16, alpha: 1)])

    // Back window, offset like a stack.
    NSColor.white.withAlphaComponent(0.14).setFill()
    NSBezierPath(roundedRect: NSRect(x: r.midX - 96, y: r.midY - 122, width: 300, height: 260),
                 xRadius: 34, yRadius: 34).fill()

    // Front window.
    let front = NSRect(x: r.midX - 168, y: r.midY - 168, width: 300, height: 260)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: front, xRadius: 34, yRadius: 34).fill()

    // Title dots.
    for i in 0..<3 {
        NSColor(calibratedWhite: 0.72, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: front.minX + 26 + CGFloat(i) * 30, y: front.maxY - 40, width: 16, height: 16)).fill()
    }

    // K.
    let k = NSAttributedString(string: "K", attributes: [
        .font: rounded(150, .heavy),
        .foregroundColor: NSColor(calibratedRed: 0.16, green: 0.40, blue: 0.98, alpha: 1),
    ])
    centered(k, in: NSRect(x: front.minX, y: front.minY + 10, width: front.width, height: front.height - 30), dy: -14)
}

let folder = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".", isDirectory: true)
try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

let designs: [(String, (NSRect) -> Void)] = [("A-kk", iconA), ("B-monster", iconB), ("C-window-k", iconC)]

for (name, draw) in designs {
    for px in [512, 128] {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let url = folder.appendingPathComponent("\(name)-\(px).png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
    print("wrote \(name)")
}
