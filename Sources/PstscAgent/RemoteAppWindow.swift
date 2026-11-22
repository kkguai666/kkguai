import AppKit
import Carbon
import PstscRDP

/// A borderless Mac window showing one remote window. Windows draws its own title bar,
/// so the whole remote window is content and every click goes to the remote side.
final class RemoteAppWindow: NSWindow {
    let remoteId: UInt32
    private(set) var info: RemoteWindowInfo
    let remoteView: RemoteContentView
    private let session: RDPSession
    /// Whether the window was ever put on screen; only the first appearance takes focus.
    var hasBeenShown = false
    /// Set once the shared desktop framebuffer was freshly painted inside this window. Some apps
    /// (Steam, Explorer) never get their own GFX surface and are drawn there instead.
    var hasFreshDesktopPixels = false
    /// While the user drags the window locally, server position updates must not move it.
    var isLocallyMoving = false
    /// Frame we reported after a local move; older server updates arriving meanwhile are ignored.
    private var reportedFrame: (frame: CGRect, until: Date)?

    init(info: RemoteWindowInfo, session: RDPSession) {
        remoteId = info.id
        self.info = info
        self.session = session
        remoteView = RemoteContentView(session: session)
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)

        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        // Clear, not black: the server announces a new size before the resized surface arrives, and
        // the part the surface doesn't cover yet would otherwise show as a black bar at the edge.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        contentView = remoteView
        update(info)
    }

    /// Popups may take the keyboard too (typing into the Start menu's search box); keys go to the
    /// remote session as a whole, and popups never send a RAIL activate, which would close them.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { !info.isPopup }

    func update(_ info: RemoteWindowInfo) {
        self.info = info
        title = info.title
        level = info.isPopup ? .popUpMenu : .normal
        hasShadow = !info.isLayered
        if isLocallyMoving { return }
        if let reported = reportedFrame {
            if info.frame == reported.frame || Date() > reported.until {
                reportedFrame = nil
            } else {
                return // a stale position from before our move report
            }
        }
        let frame = Self.macFrame(forDesktopRect: info.frame)
        if frame != self.frame {
            setFrame(frame, display: false)
        }
    }

    /// Drags or resizes the window on the Mac until the mouse button is released and returns the
    /// new visible frame in desktop coordinates. type: 1–8 resize edges, 9 move (RAIL_WMSZ_*).
    func trackLocalMoveSize(type: UInt16) -> CGRect {
        let startMouse = NSEvent.mouseLocation
        let start = frame
        let minimum = NSSize(width: 120, height: 60)
        isLocallyMoving = true
        trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration,
                    mode: .eventTracking) { event, stop in
            guard let event else { return }
            let dx = NSEvent.mouseLocation.x - startMouse.x
            let dy = NSEvent.mouseLocation.y - startMouse.y
            var f = start
            switch type {
            case 9:
                f.origin.x += dx
                f.origin.y += dy
            default:
                // Windows edges; Mac y grows upward, so "top" is maxY.
                if [1, 4, 7].contains(type) { f.origin.x = min(start.minX + dx, start.maxX - minimum.width); f.size.width = start.maxX - f.origin.x }
                if [2, 5, 8].contains(type) { f.size.width = max(start.width + dx, minimum.width) }
                if [3, 4, 5].contains(type) { f.size.height = max(start.height + dy, minimum.height) }
                if [6, 7, 8].contains(type) {
                    f.origin.y = min(start.minY + dy, start.maxY - minimum.height)
                    f.size.height = start.maxY - f.origin.y
                }
            }
            self.setFrame(f, display: false)
            if event.type == .leftMouseUp { stop.pointee = true }
        }
        isLocallyMoving = false
        let screen = Self.primaryScreenFrame
        let s = DisplayScale.value
        let desktop = CGRect(x: (frame.minX - screen.minX) * s, y: (screen.maxY - frame.maxY) * s,
                             width: frame.width * s, height: frame.height * s).integral
        reportedFrame = (desktop, Date().addingTimeInterval(1.5))
        return desktop
    }

    /// Resizes the window with a drag started on the Mac (the remote resize border is invisible and
    /// sits outside this window, so it cannot be grabbed), then tells the server the new frame.
    /// type: 1–8 resize edges, same RAIL_WMSZ_* values the server uses.
    func beginLocalResize(type: UInt16) {
        guard info.showState != 3, NSEvent.pressedMouseButtons & 1 != 0 else { return }
        let info = self.info
        let visible = trackLocalMoveSize(type: type)
        let left = info.frame.minX - info.origin.x
        let top = info.frame.minY - info.origin.y
        let right = info.origin.x + info.windowSize.width - info.frame.maxX
        let bottom = info.origin.y + info.windowSize.height - info.frame.maxY
        let whole = CGRect(x: visible.minX - left, y: visible.minY - top,
                           width: visible.width + left + right, height: visible.height + top + bottom)
        session.moveWindow(remoteId, to: whole)
    }

    /// Uses the window's own GFX surface when the server sends one, else the shared desktop framebuffer.
    func refresh(from session: RDPSession) {
        if let surface = session.surface(for: remoteId) {
            remoteView.show(surface.image(of: info.surfaceCrop, alpha: info.isLayered))
        } else {
            remoteView.show(session.frames.image(of: info.frame))
        }
    }

    // MARK: Coordinate mapping (remote desktop = primary screen, 1 pixel = 1 point)

    static var primaryScreenFrame: CGRect {
        NSScreen.screens.first?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    static func macFrame(forDesktopRect r: CGRect) -> NSRect {
        let screen = primaryScreenFrame
        let s = DisplayScale.value
        return NSRect(x: screen.minX + r.minX / s, y: screen.maxY - r.maxY / s,
                      width: r.width / s, height: r.height / s)
    }

    static func desktopPoint(forScreenPoint p: NSPoint) -> CGPoint {
        let screen = primaryScreenFrame
        let s = DisplayScale.value
        return CGPoint(x: ((p.x - screen.minX) * s).rounded(.down),
                       y: ((screen.maxY - p.y) * s).rounded(.down))
    }
}

/// Draws the remote pixels and forwards mouse and keyboard input to the session.
final class RemoteContentView: NSView, NSTextInputClient {
    /// Turns a point in this view's coordinates into remote desktop pixels.
    typealias PointMapper = (_ viewPoint: NSPoint, _ view: NSView) -> CGPoint

    private let session: RDPSession
    private let mapPoint: PointMapper
    private var trackingArea: NSTrackingArea?
    private var scrollRemainderX: CGFloat = 0
    private var scrollRemainderY: CGFloat = 0
    /// Thickness of the Mac-side resize band inside each window edge.
    private static let resizeBand: CGFloat = 6
    /// Text the Mac input method is composing right now (nil when not composing).
    private var markedText: NSMutableAttributedString?
    /// Screen point of the last click: where the IME candidate window should appear, since the
    /// remote side never tells us where the text caret is.
    private var lastClickScreenPoint: NSPoint?
    private var cursorObserver: NSObjectProtocol?

    /// RemoteApp windows: the view sits where the remote window is, so map through screen coordinates.
    static let screenMapper: PointMapper = { point, view in
        guard let window = view.window else { return .zero }
        let inWindow = view.convert(point, to: nil)
        return RemoteAppWindow.desktopPoint(forScreenPoint: window.convertPoint(toScreen: inWindow))
    }

    init(session: RDPSession, scalesToFit: Bool = false, mapPoint: @escaping PointMapper = RemoteContentView.screenMapper) {
        self.session = session
        self.mapPoint = mapPoint
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contentsGravity = scalesToFit ? .resize : .topLeft
        layer?.isGeometryFlipped = true
        cursorObserver = NotificationCenter.default.addObserver(forName: .remoteCursorChanged,
                                                                object: nil, queue: .main) { [weak self] _ in
            guard let self, let window = self.window else { return }
            window.invalidateCursorRects(for: self)
        }
    }

    deinit {
        if let cursorObserver { NotificationCenter.default.removeObserver(cursorObserver) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var wantsUpdateLayer: Bool { true }

    func show(_ image: CGImage?) {
        guard let image else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = image
        layer?.contentsScale = DisplayScale.value
        CATransaction.commit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: Mouse

    private func desktopPoint(_ event: NSEvent) -> CGPoint {
        mapPoint(convert(event.locationInWindow, from: nil), self)
    }

    override func mouseMoved(with event: NSEvent) { session.mouseMove(to: desktopPoint(event)) }
    override func mouseDragged(with event: NSEvent) { session.mouseMove(to: desktopPoint(event)) }
    override func rightMouseDragged(with event: NSEvent) { session.mouseMove(to: desktopPoint(event)) }
    override func otherMouseDragged(with event: NSEvent) { session.mouseMove(to: desktopPoint(event)) }

    override func mouseDown(with event: NSEvent) {
        if let type = resizeEdge(at: convert(event.locationInWindow, from: nil)),
           let window = window as? RemoteAppWindow {
            window.beginLocalResize(type: type)
            return
        }
        lastClickScreenPoint = window?.convertPoint(toScreen: event.locationInWindow)
        let p = desktopPoint(event)
        session.mouseMove(to: p)
        session.mouseButton(PSTSC_MOUSE_LEFT, down: true, at: p)
    }

    /// Which resize edge the point touches (RAIL_WMSZ_* numbering), if any.
    private func resizeEdge(at p: NSPoint) -> UInt16? {
        let band = Self.resizeBand
        let left = p.x < band
        let right = p.x > bounds.width - band
        let bottom = p.y < band
        let top = p.y > bounds.height - band
        switch (left, right, top, bottom) {
        case (true, _, true, _): return 4
        case (_, true, true, _): return 5
        case (true, _, _, true): return 7
        case (_, true, _, true): return 8
        case (true, _, _, _): return 1
        case (_, true, _, _): return 2
        case (_, _, true, _): return 3
        case (_, _, _, true): return 6
        default: return nil
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        // Base cursor: whatever shape the remote side last set. Edge rects below override it.
        addCursorRect(bounds, cursor: RemoteCursorStore.shared.cursor)
        let band = Self.resizeBand
        addCursorRect(NSRect(x: 0, y: 0, width: band, height: bounds.height), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: bounds.width - band, y: 0, width: band, height: bounds.height), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: 0, y: 0, width: bounds.width, height: band), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: 0, y: bounds.height - band, width: bounds.width, height: band), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: 0, y: 0, width: band, height: band), cursor: .crosshair)
        addCursorRect(NSRect(x: bounds.width - band, y: 0, width: band, height: band), cursor: .crosshair)
        addCursorRect(NSRect(x: 0, y: bounds.height - band, width: band, height: band), cursor: .crosshair)
        addCursorRect(NSRect(x: bounds.width - band, y: bounds.height - band, width: band, height: band), cursor: .crosshair)
    }

    override func mouseUp(with event: NSEvent) { session.mouseButton(PSTSC_MOUSE_LEFT, down: false, at: desktopPoint(event)) }

    override func rightMouseDown(with event: NSEvent) {
        let p = desktopPoint(event)
        session.mouseMove(to: p)
        session.mouseButton(PSTSC_MOUSE_RIGHT, down: true, at: p)
    }

    override func rightMouseUp(with event: NSEvent) { session.mouseButton(PSTSC_MOUSE_RIGHT, down: false, at: desktopPoint(event)) }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        session.mouseButton(PSTSC_MOUSE_MIDDLE, down: true, at: desktopPoint(event))
    }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        session.mouseButton(PSTSC_MOUSE_MIDDLE, down: false, at: desktopPoint(event))
    }

    override func scrollWheel(with event: NSEvent) {
        let p = desktopPoint(event)
        // Windows: 120 units per notch. Trackpads report points, wheels report lines.
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 4 : 40
        scrollRemainderY += event.scrollingDeltaY * scale
        scrollRemainderX += -event.scrollingDeltaX * scale
        let dy = Int(scrollRemainderY), dx = Int(scrollRemainderX)
        if dy != 0 {
            session.mouseWheel(horizontal: false, delta: dy, at: p)
            scrollRemainderY -= CGFloat(dy)
        }
        if dx != 0 {
            session.mouseWheel(horizontal: true, delta: dx, at: p)
            scrollRemainderX -= CGFloat(dx)
        }
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        if usesInputMethod(for: event) {
            interpretKeyEvents([event])
            return
        }
        KeyboardBridge.shared.key(event, down: true, session: session)
    }

    override func keyUp(with event: NSEvent) {
        if hasMarkedText() { return }
        KeyboardBridge.shared.key(event, down: false, session: session)
    }

    override func flagsChanged(with event: NSEvent) { KeyboardBridge.shared.flagsChanged(event, session: session) }

    /// Plain typing goes through the Mac input method while a CJK input source is selected: the
    /// Mac composes Pinyin/Sogou locally and the finished text is sent as Unicode keys (the remote
    /// side has no matching IME state). Shortcuts and Latin layouts keep going as raw key codes.
    private func usesInputMethod(for event: NSEvent) -> Bool {
        if hasMarkedText() { return true }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        return Self.cjkInputSourceSelected
    }

    private static var cjkInputSourceSelected: Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return false }
        let id = (Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String).lowercased()
        return id.contains("inputmethod") || id.contains("pinyin") || id.contains("sogou")
            || id.contains("wubi") || id.contains("zhuyin") || id.contains("bopomofo")
            || id.contains("cangjie") || id.contains("hangul") || id.contains("kana")
    }

    // MARK: NSTextInputClient

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        markedText = nil
        for unit in text.utf16 {
            session.unicodeKey(unit, down: true)
            session.unicodeKey(unit, down: false)
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let text = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        markedText = NSMutableAttributedString(string: text)
    }

    func unmarkText() { markedText = nil }

    func hasMarkedText() -> Bool { markedText != nil }

    func markedRange() -> NSRange {
        guard let markedText else { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(location: 0, length: markedText.length)
    }

    func selectedRange() -> NSRange { NSRange(location: markedText?.length ?? 0, length: 0) }

    func attributedSubstring(forProposedRange range: NSRange,
                             actualRange: NSRangePointer?) -> NSAttributedString? { nil }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    func characterIndex(for point: NSPoint) -> Int { NSNotFound }

    /// Where the candidate window goes: just below the point the user last clicked, which is as
    /// close to the text caret as we can tell without the remote side reporting one.
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let anchor = lastClickScreenPoint ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var y = anchor.y - 30
        if y < visible.minY + 24 { y = anchor.y + 10 }
        let x = min(max(anchor.x, visible.minX + 4), visible.maxX - 240)
        return NSRect(x: x, y: y, width: 1, height: 22)
    }

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(deleteBackward(_:)): KeyboardBridge.shared.tap(51, session: session)
        case #selector(deleteForward(_:)): KeyboardBridge.shared.tap(117, session: session)
        case #selector(insertNewline(_:)): KeyboardBridge.shared.tap(36, session: session)
        case #selector(insertTab(_:)): KeyboardBridge.shared.tap(48, session: session)
        case #selector(insertBacktab(_:)): KeyboardBridge.shared.tap(48, session: session)
        case #selector(moveUp(_:)): KeyboardBridge.shared.tap(126, session: session)
        case #selector(moveDown(_:)): KeyboardBridge.shared.tap(125, session: session)
        case #selector(moveLeft(_:)): KeyboardBridge.shared.tap(123, session: session)
        case #selector(moveRight(_:)): KeyboardBridge.shared.tap(124, session: session)
        case #selector(cancelOperation(_:)): KeyboardBridge.shared.tap(53, session: session)
        default: break
        }
    }

    /// Command shortcuts go to the remote side (as Ctrl) instead of this app's menus, except Cmd+Q.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.isKeyWindow == true, event.type == .keyDown else { return false }
        if event.modifierFlags.contains(.command) && event.keyCode == KeyboardBridge.keyQ { return false }
        KeyboardBridge.shared.key(event, down: true, session: session)
        return true
    }
}
