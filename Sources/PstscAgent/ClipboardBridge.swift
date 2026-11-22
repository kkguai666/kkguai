import AppKit

/// Text clipboard both ways. AppKit has no change notification for the pasteboard, so it polls
/// the change counter; when the remote side was the source we remember that count and skip it,
/// otherwise the two sides would keep echoing text back and forth.
final class ClipboardBridge {
    static let shared = ClipboardBridge()

    /// Local text copied by the user, to be announced to the remote PC.
    var onLocalText: ((String) -> Void)?
    /// Whether sharing is on at all (menu toggle / preference).
    var isEnabled: () -> Bool = { true }

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var suppressedChangeCount = -1

    func start() {
        stop()
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.7, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Text came from the remote PC: put it on the Mac clipboard without sending it back.
    func applyRemoteText(_ text: String) {
        guard isEnabled() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        suppressedChangeCount = pasteboard.changeCount
        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        guard isEnabled() else { return }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard pasteboard.changeCount != suppressedChangeCount else { return }
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        // Files and images are not text; leave them alone so the remote side keeps its own.
        onLocalText?(text)
    }
}
