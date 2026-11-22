import AppKit

/// A menu-bar dot that says, at a glance, whether the Windows PC is reachable — and how fast —
/// without switching to the app. The menu itself is rebuilt on open so it always shows live state.
final class StatusItemController: NSObject, NSMenuDelegate {
    var menuBuilder: (() -> NSMenu)?
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    override init() {
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        item.button?.imagePosition = .imageLeading
        update(state: .idle, connected: false)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let menuBuilder else { return }
        let fresh = menuBuilder()
        for child in fresh.items {
            fresh.removeItem(child)
            menu.addItem(child)
        }
    }

    func update(state: ConnectionWatchdog.State, connected: Bool) {
        guard let button = item.button else { return }
        let symbol = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
        symbol?.isTemplate = true
        button.image = symbol
        switch state {
        case .reachable(let ms):
            button.contentTintColor = connected ? .systemGreen : .systemYellow
            button.title = " \(ms) ms"
            button.toolTip = L("원격 PC 연결됨 · %d ms", ms)
        case .checking:
            button.contentTintColor = .systemYellow
            button.title = ""
            button.toolTip = L("원격 PC 확인 중…")
        case .unreachable:
            button.contentTintColor = .systemRed
            button.title = ""
            button.toolTip = L("원격 PC에 연결할 수 없습니다")
        case .idle:
            button.contentTintColor = .secondaryLabelColor
            button.title = ""
            button.toolTip = "kkguai"
        }
    }
}
