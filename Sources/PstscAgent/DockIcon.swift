import AppKit

/// A friendly little monster face for the Dock button (kkguai = 怪).
enum DockIcon {
    static func make() -> NSImage {
        NSImage(size: NSSize(width: 512, height: 512), flipped: false) { r in
            let card = NSBezierPath(roundedRect: r.insetBy(dx: 40, dy: 40), xRadius: 104, yRadius: 104)
            NSGradient(colors: [NSColor(calibratedRed: 0.62, green: 0.36, blue: 0.96, alpha: 1),
                                NSColor(calibratedRed: 0.98, green: 0.45, blue: 0.65, alpha: 1)])?
                .draw(in: card, angle: 45)

            let ink = NSColor(calibratedRed: 0.24, green: 0.12, blue: 0.42, alpha: 1)

            // Body.
            NSColor.white.setFill()
            let body = NSRect(x: r.midX - 150, y: r.minY + 118, width: 300, height: 300)
            NSBezierPath(roundedRect: body, xRadius: 132, yRadius: 132).fill()

            // Antennae.
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

            return true
        }
    }
}
