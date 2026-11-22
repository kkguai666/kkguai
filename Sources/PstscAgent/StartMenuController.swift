import AppKit

/// A Mac-side copy of the Windows 11 Start menu. The real one cannot be shown: Windows does not
/// send its shell UI (Start, search, Action Center) to RemoteApp clients.
final class StartMenuController: NSWindowController, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    enum PowerAction {
        case toggleDesktop, disconnect, signOut, restart, shutDown
    }

    /// Extra search results: actions and open remote windows, so ⌥Space is a command palette.
    struct PaletteCommand {
        let title: String
        let run: () -> Void
    }
    var paletteCommands: (() -> [PaletteCommand])?

    var onLaunch: ((RemoteApp) -> Void)?
    var onPower: ((PowerAction) -> Void)?
    var userName = ""
    var isDesktopMode = false

    private let catalog: AppCatalog
    private let icons: AppIconStore
    private let prefs: StartMenuPrefs

    private enum Page { case home, all, search }
    private enum Row {
        case header(String)
        case app(RemoteApp)
        case command(PaletteCommand)
    }

    private var page: Page = .home
    private var rows: [Row] = []

    private let searchField = NSTextField()
    private let homeView = NSStackView()
    private let pinnedGrid = NSGridView()
    private let loadingLabel = NSTextField(wrappingLabelWithString: "")
    private let recentGrid = NSGridView()
    private let listView = NSStackView()
    private let listTitle = NSTextField(labelWithString: L("모든 앱"))
    private let backButton = NSButton()
    private let table = NSTableView()

    private lazy var powerButton: NSButton = {
        let button = NSButton(image: NSImage(systemSymbolName: "power", accessibilityDescription: L("전원"))!,
                              target: self, action: #selector(showPowerMenu(_:)))
        button.isBordered = false
        button.contentTintColor = NSColor(white: 0.9, alpha: 1)
        button.symbolConfiguration = .init(pointSize: 15, weight: .regular)
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }()

    private static let width: CGFloat = 640
    private static let listHeight: CGFloat = 560
    private static let columns = 6
    /// Visible frame of the screen the panel was opened on; kept so height changes stay anchored.
    private var anchorFrame: NSRect?

    init(catalog: AppCatalog, icons: AppIconStore, prefs: StartMenuPrefs) {
        self.catalog = catalog
        self.icons = icons
        self.prefs = prefs
        let panel = StartMenuPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.listHeight),
                                   styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.appearance = NSAppearance(named: .darkAqua)
        super.init(window: panel)
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.cancel() }
        buildLayout()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Showing

    func toggle() {
        if window?.isVisible == true {
            close()
        } else {
            present()
        }
    }

    /// Opens centered above the Dock on the screen with the mouse, like Windows 11.
    func present() {
        guard let window else { return }
        searchField.stringValue = ""
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        anchorFrame = screen.visibleFrame
        show(.home)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(searchField)
    }

    /// The catalog or icons changed: rebuild what is on screen.
    func reload() {
        guard window?.isVisible == true else { return }
        show(page)
    }

    /// Cheap progress tick while icons are still being fetched: refresh the "loading…" line
    /// without rebuilding (and losing the hover/selection of) the icon grids.
    func updateProgress() {
        guard window?.isVisible == true, page == .home else { return }
        let wasHidden = loadingLabel.superview?.isHidden ?? true
        updateLoadingLabel()
        if (loadingLabel.superview?.isHidden ?? true) != wasHidden {
            fitWindow(.home)
        }
    }

    override func close() {
        window?.orderOut(nil)
    }

    // MARK: Layout

    private func buildLayout() {
        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 1
        background.layer?.borderColor = NSColor(white: 1, alpha: 0.08).cgColor

        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 0.88).cgColor

        let search = makeSearchBox()
        search.heightAnchor.constraint(equalToConstant: 34).isActive = true
        search.setContentHuggingPriority(.init(1), for: .horizontal)
        let allButton = Self.pillButton(title: L("모두  ›"), target: self, action: #selector(showAll))
        let topBar = NSStackView(views: [search, allButton, powerButton])
        topBar.orientation = .horizontal
        topBar.spacing = 10
        topBar.alignment = .centerY

        buildHome()
        buildList()

        let body = NSView()
        for view in [homeView, listView] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            body.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: body.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: body.trailingAnchor),
                view.topAnchor.constraint(equalTo: body.topAnchor),
                view.bottomAnchor.constraint(equalTo: body.bottomAnchor),
            ])
        }

        for view in [tint, topBar, body] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        NSLayoutConstraint.activate([
            tint.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            tint.topAnchor.constraint(equalTo: background.topAnchor),
            tint.bottomAnchor.constraint(equalTo: background.bottomAnchor),

            topBar.topAnchor.constraint(equalTo: background.topAnchor, constant: 24),
            topBar.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 32),
            topBar.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -32),

            body.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 24),
            body.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 32),
            body.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -32),
            body.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -28),
        ])
        window?.contentView = background
    }

    /// Home is a short panel that hugs its icons; the searchable list keeps a fixed height.
    private func fitWindow(_ page: Page) {
        guard let window, let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let height = page == .home ? min(max(content.fittingSize.height, 220), 660) : Self.listHeight
        window.setContentSize(NSSize(width: Self.width, height: height))
        // setContentSize keeps the top edge; pin the bottom above the Dock instead so growth goes up.
        let visible = anchorFrame ?? (NSScreen.main?.visibleFrame ?? .zero)
        window.setFrameOrigin(NSPoint(x: (visible.midX - window.frame.width / 2).rounded(),
                                      y: visible.minY + 12))
    }

    private func makeSearchBox() -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 17
        box.layer?.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1).cgColor
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor(white: 1, alpha: 0.1).cgColor

        let glass = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!)
        glass.contentTintColor = NSColor(calibratedRed: 0.4, green: 0.7, blue: 1, alpha: 1)

        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 13)
        searchField.textColor = .white
        searchField.placeholderAttributedString = NSAttributedString(
            string: L("앱, 설정 및 문서 검색"),
            attributes: [.foregroundColor: NSColor(white: 1, alpha: 0.5), .font: NSFont.systemFont(ofSize: 13)])
        searchField.delegate = self

        for view in [glass, searchField] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(view)
        }
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            glass.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            glass.widthAnchor.constraint(equalToConstant: 16),
            searchField.leadingAnchor.constraint(equalTo: glass.trailingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            searchField.centerYAnchor.constraint(equalTo: box.centerYAnchor),
        ])
        return box
    }

    private func buildHome() {
        pinnedGrid.rowSpacing = 4
        pinnedGrid.columnSpacing = 4

        recentGrid.rowSpacing = 4
        recentGrid.columnSpacing = 4

        loadingLabel.textColor = NSColor(white: 1, alpha: 0.75)
        loadingLabel.font = .systemFont(ofSize: 12)

        homeView.orientation = .vertical
        homeView.alignment = .leading
        homeView.spacing = 16
        let loadingRow = Self.row(loadingLabel, accessory: nil)
        homeView.setViews([loadingRow, pinnedGrid, recentGrid], in: .top)
        loadingRow.widthAnchor.constraint(equalTo: homeView.widthAnchor).isActive = true
    }

    private func buildList() {
        listTitle.font = .boldSystemFont(ofSize: 14)
        listTitle.textColor = .white
        backButton.title = L("‹  뒤로")
        Self.stylePill(backButton, target: self, action: #selector(showHome))
        let header = Self.row(listTitle, accessory: backButton)

        table.addTableColumn(NSTableColumn(identifier: .init("app")))
        table.headerView = nil
        table.backgroundColor = .clear
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(tableClicked)
        table.menu = NSMenu()
        table.menu?.delegate = self

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay

        listView.orientation = .vertical
        listView.alignment = .leading
        listView.spacing = 10
        listView.setViews([header, scroll], in: .top)
        header.widthAnchor.constraint(equalTo: listView.widthAnchor).isActive = true
        scroll.widthAnchor.constraint(equalTo: listView.widthAnchor).isActive = true
        scroll.setContentHuggingPriority(.init(1), for: .vertical)
    }

    // MARK: Pages

    private func show(_ newPage: Page) {
        page = newPage
        homeView.isHidden = newPage != .home
        listView.isHidden = newPage == .home
        switch newPage {
        case .home:
            fillHome()
        case .all:
            listTitle.stringValue = L("모든 앱")
            backButton.isHidden = false
            rows = Self.grouped(catalog.apps)
            reloadTable()
        case .search:
            listTitle.stringValue = L("검색 결과")
            backButton.isHidden = true
            let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
            let matches = catalog.apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
            // Names that start with the query first, like Windows' best match.
            let ranked = matches.sorted {
                let a = $0.name.trimmed.lowercased().hasPrefix(query.lowercased())
                let b = $1.name.trimmed.lowercased().hasPrefix(query.lowercased())
                return a != b ? a : $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            let commands = (paletteCommands?() ?? []).filter {
                $0.title.localizedCaseInsensitiveContains(query)
            }
            var result: [Row] = ranked.map { .app($0) }
            if !commands.isEmpty {
                if !result.isEmpty { result.append(.header(L("명령"))) }
                result += commands.map { .command($0) }
            }
            rows = result.isEmpty ? [.header(L("'%@'에 대한 결과가 없습니다", query))] : result
            reloadTable()
        }
        fitWindow(newPage)
    }

    @objc private func showAll() { show(.all) }

    @objc private func showHome() {
        searchField.stringValue = ""
        show(.home)
        window?.makeFirstResponder(searchField)
    }

    private func fillHome() {
        updateLoadingLabel()
        Self.clear(pinnedGrid)
        let pinned = prefs.pinned(in: catalog.apps)
        if pinned.isEmpty && !catalog.apps.isEmpty {
            let label = NSTextField(wrappingLabelWithString: L("고정된 앱이 없습니다. '모두'에서 앱을 우클릭해 고정하세요."))
            label.textColor = NSColor(white: 1, alpha: 0.75)
            pinnedGrid.addRow(with: [label])
        }
        for start in stride(from: 0, to: min(pinned.count, Self.columns * 3), by: Self.columns) {
            let tiles: [NSView] = pinned[start..<min(start + Self.columns, pinned.count)].map { makeTile(for: $0) }
            pinnedGrid.addRow(with: tiles)
        }

        Self.clear(recentGrid)
        // An app that is already pinned above does not need a second tile at the bottom.
        let pinnedIDs = Set(pinned.map(\.appID))
        let recent = Array(prefs.recent(in: catalog.apps)
            .filter { !pinnedIDs.contains($0.appID) }
            .prefix(3))
        recentGrid.isHidden = recent.isEmpty
        if !recent.isEmpty {
            recentGrid.addRow(with: recent.map { makeTile(for: $0) })
        }
    }

    /// Shows "getting the app list…" with a wait percentage until it arrives, then an
    /// icon-download percentage, then hides.
    private func updateLoadingLabel() {
        if let percent = catalog.listWaitPercent() {
            loadingLabel.stringValue = L("원격 PC에서 앱 목록을 받아오는 중입니다… %d%%", Int32(percent))
            loadingLabel.superview?.isHidden = false
        } else if let p = catalog.iconProgress() {
            let percent = Int(Double(p.done) / Double(p.total) * 100)
            loadingLabel.stringValue = L("앱 아이콘 받는 중… %d%% (%d/%d)", Int32(percent), Int32(p.done), Int32(p.total))
            loadingLabel.superview?.isHidden = false
        } else if catalog.apps.isEmpty {
            loadingLabel.stringValue = L("원격 PC에 연결하는 중입니다…")
            loadingLabel.superview?.isHidden = false
        } else {
            loadingLabel.superview?.isHidden = true
        }
    }

    private func reloadTable() {
        table.reloadData()
        if let first = rows.firstIndex(where: { if case .app = $0 { return true } else { return false } }) {
            table.selectRowIndexes([first], byExtendingSelection: false)
            table.scrollRowToVisible(0)
        }
    }

    // MARK: Tiles

    private func makeTile(for app: RemoteApp) -> NSView {
        let tile = AppTileView(app: app, icon: icons.icon(for: app))
        tile.onClick = { [weak self] in self?.launch(app) }
        tile.menuProvider = { [weak self] in self?.contextMenu(for: app) }
        return tile
    }

    private func contextMenu(for app: RemoteApp) -> NSMenu {
        let menu = NSMenu()
        let pinned = prefs.isPinned(app, in: catalog.apps)
        let item = NSMenuItem(title: pinned ? L("시작 화면에서 고정 해제") : L("시작 화면에 고정"),
                              action: #selector(togglePin(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = app
        menu.addItem(item)
        return menu
    }

    @objc private func togglePin(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? RemoteApp else { return }
        prefs.togglePin(app, in: catalog.apps)
        if page == .home {
            fillHome()
            fitWindow(.home)
        }
    }

    private func launch(_ app: RemoteApp) {
        close()
        // The recent list is recorded in AppDelegate, so Dock/Spotlight launches count too.
        onLaunch?(app)
    }

    // MARK: Power menu

    @objc private func showPowerMenu(_ sender: NSButton) {
        let menu = NSMenu()
        func add(_ title: String, _ action: PowerAction) {
            let item = NSMenuItem(title: title, action: #selector(powerChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action
            menu.addItem(item)
        }
        add(isDesktopMode ? L("앱 창 모드로 돌아가기") : L("Windows 데스크톱 보기"), .toggleDesktop)
        menu.addItem(.separator())
        add(L("연결 끊기"), .disconnect)
        add(L("원격 PC 로그아웃…"), .signOut)
        add(L("원격 PC 다시 시작…"), .restart)
        add(L("원격 PC 시스템 종료…"), .shutDown)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func powerChosen(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? PowerAction else { return }
        close()
        onPower?(action)
    }

    // MARK: Search field

    func controlTextDidChange(_ obj: Notification) {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        show(query.isEmpty ? .home : .search)
    }

    /// Arrow keys move through results, Return launches, Esc goes back or closes.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)) where page != .home:
            moveSelection(by: 1)
        case #selector(NSResponder.moveUp(_:)) where page != .home:
            moveSelection(by: -1)
        case #selector(NSResponder.insertNewline(_:)):
            if page != .home { run(row: table.selectedRow) }
        case #selector(NSResponder.cancelOperation(_:)):
            cancel()
        default:
            return false
        }
        return true
    }

    private func cancel() {
        if page == .home {
            close()
        } else {
            showHome()
        }
    }

    private func moveSelection(by delta: Int) {
        var row = table.selectedRow
        repeat {
            row += delta
        } while rows.indices.contains(row) && { if case .header = rows[row] { return true } else { return false } }()
        guard rows.indices.contains(row) else { return }
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    // MARK: Table

    @objc private func tableClicked() {
        run(row: table.clickedRow)
    }

    private func run(row: Int?) {
        guard let row else { return }
        switch rows[safe: row] {
        case .app(let app):
            launch(app)
        case .command(let command):
            close()
            command.run()
        default:
            break
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .header = rows[row] { return 30 }
        return 38
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .header = rows[row] { return false }
        return true
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .header(let title):
            let label = NSTextField(labelWithString: title)
            label.font = .boldSystemFont(ofSize: 13)
            label.textColor = .white
            return Self.inset(label, left: 10)
        case .command(let command):
            let image = NSImageView(image: NSImage(systemSymbolName: "command",
                                                   accessibilityDescription: nil) ?? NSImage())
            image.contentTintColor = NSColor(white: 1, alpha: 0.7)
            let label = NSTextField(labelWithString: command.title)
            label.textColor = .white
            label.font = .systemFont(ofSize: 13)
            label.lineBreakMode = .byTruncatingTail
            let stack = NSStackView(views: [image, label])
            stack.spacing = 12
            image.widthAnchor.constraint(equalToConstant: 26).isActive = true
            image.heightAnchor.constraint(equalToConstant: 26).isActive = true
            return Self.inset(stack, left: 10)
        case .app(let app):
            let image = NSImageView(image: icons.icon(for: app))
            image.contentTintColor = NSColor(white: 1, alpha: 0.7)
            let label = NSTextField(labelWithString: app.name.trimmed)
            label.textColor = .white
            label.font = .systemFont(ofSize: 13)
            label.lineBreakMode = .byTruncatingTail
            let stack = NSStackView(views: [image, label])
            stack.spacing = 12
            image.widthAnchor.constraint(equalToConstant: 26).isActive = true
            image.heightAnchor.constraint(equalToConstant: 26).isActive = true
            return Self.inset(stack, left: 10)
        }
    }

    // MARK: Helpers

    /// "모두" list grouped like Windows: #, then A–Z, then ㄱ–ㅎ.
    private static func grouped(_ apps: [RemoteApp]) -> [Row] {
        let keyed = apps.map { (groupKey($0.name.trimmed), $0) }
        let order: (String) -> Int = { key in
            if key == "#" { return 0 }
            return key.unicodeScalars.first!.isASCII ? 1 : 2
        }
        let sorted = keyed.sorted {
            if $0.0 != $1.0 {
                return order($0.0) != order($1.0) ? order($0.0) < order($1.0) : $0.0 < $1.0
            }
            return $0.1.name.trimmed.localizedStandardCompare($1.1.name.trimmed) == .orderedAscending
        }
        var rows: [Row] = []
        var current: String?
        for (key, app) in sorted {
            if key != current {
                rows.append(.header(key))
                current = key
            }
            rows.append(.app(app))
        }
        return rows
    }

    private static let initials = ["ㄱ", "ㄱ", "ㄴ", "ㄷ", "ㄷ", "ㄹ", "ㅁ", "ㅂ", "ㅂ", "ㅅ", "ㅅ", "ㅇ", "ㅈ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"]

    private static func groupKey(_ name: String) -> String {
        guard let first = name.unicodeScalars.first else { return "#" }
        if (0xAC00...0xD7A3).contains(first.value) {
            return initials[Int((first.value - 0xAC00) / 588)]
        }
        if first.isASCII, CharacterSet.letters.contains(first) {
            return String(first).uppercased()
        }
        // Chinese/Japanese names: group by the first letter of the Latin reading (pinyin/romaji).
        if let latin = name.applyingTransform(.toLatin, reverse: false)?
            .folding(options: .diacriticInsensitive, locale: .current),
           let letter = latin.unicodeScalars.first(where: { CharacterSet.letters.contains($0) }) {
            return String(Character(letter)).uppercased()
        }
        return "#"
    }

    private static func row(_ left: NSView, accessory: NSView?) -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let stack = NSStackView(views: [left, spacer] + (accessory.map { [$0] } ?? []))
        stack.orientation = .horizontal
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        return stack
    }

    private static func pillButton(title: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton()
        button.title = title
        stylePill(button, target: target, action: action)
        return button
    }

    private static func stylePill(_ button: NSButton, target: AnyObject, action: Selector) {
        button.target = target
        button.action = action
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 4
        button.layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor
        button.attributedTitle = NSAttributedString(string: button.title, attributes: [
            .foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 12),
        ])
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    private static func inset(_ view: NSView, left: CGFloat) -> NSView {
        let container = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: left),
            view.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -10),
            view.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    /// removeRow leaves the cells' views in the grid, so old tiles would stay underneath new ones.
    private static func clear(_ grid: NSGridView) {
        while grid.numberOfRows > 0 {
            let views = (0..<grid.numberOfColumns).compactMap { grid.cell(atColumnIndex: $0, rowIndex: 0).contentView }
            grid.removeRow(at: 0)
            views.forEach { $0.removeFromSuperview() }
        }
    }
}

extension StartMenuController: NSWindowDelegate, NSMenuDelegate {
    /// Clicking anywhere else closes it, like the real Start menu.
    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    /// Right-click in the app list: pin or unpin that app.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard case .app(let app)? = rows[safe: table.clickedRow] else { return }
        for item in contextMenu(for: app).items {
            item.menu?.removeItem(item)
            menu.addItem(item)
        }
    }
}

/// Borderless panels refuse key status by default; the Start menu needs it for the search box.
private final class StartMenuPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// One app in the Start menu: icon above name.
private final class AppTileView: NSView {
    var onClick: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?
    private var hovering = false { didSet { needsDisplay = true } }

    init(app: RemoteApp, icon: NSImage) {
        super.init(frame: .zero)
        let image = NSImageView(image: icon)
        image.contentTintColor = NSColor(white: 1, alpha: 0.7)
        image.imageScaling = .scaleProportionallyUpOrDown
        let label = NSTextField(labelWithString: app.name.trimmed)
        label.textColor = .white
        label.font = .systemFont(ofSize: 11.5)
        label.lineBreakMode = .byTruncatingTail
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.cell?.wraps = true
        toolTip = app.name.trimmed

        for view in [image, label] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 92),
            heightAnchor.constraint(equalToConstant: 86),
            image.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            image.centerXAnchor.constraint(equalTo: centerXAnchor),
            image.widthAnchor.constraint(equalToConstant: 36),
            image.heightAnchor.constraint(equalToConstant: 36),
            label.topAnchor.constraint(equalTo: image.bottomAnchor, constant: 6),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }

    override func draw(_ dirtyRect: NSRect) {
        guard hovering else { return }
        NSColor(white: 1, alpha: 0.08).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
    }
}

private extension String {
    /// Some Start menu names carry stray spaces (" TransMac").
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
