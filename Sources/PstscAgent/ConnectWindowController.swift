import AppKit

struct Credentials {
    var host: String
    var username: String
    var password: String
}

/// Asks for the remote PC and account. Everything except the password is remembered.
final class ConnectWindowController: NSWindowController {
    /// remember: save the password in the Keychain and connect automatically from now on.
    var onConnect: ((Credentials, _ remember: Bool) -> Void)?
    /// Retry the last connection in desktop mode (takes over an in-use session).
    var onConnectDesktop: (() -> Void)?
    /// Sign out the account's existing session on the remote PC, then connect in app mode.
    var onSignOutAndConnect: (() -> Void)?

    private let hostField = NSTextField()
    private let userField = NSTextField()
    private let passwordField = NSSecureTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let desktopButton = NSButton(title: L("데스크톱 모드로 접속"), target: nil, action: nil)
    private let signOutButton = NSButton(title: L("기존 세션 로그아웃 후 연결"), target: nil, action: nil)
    private let connectButton = NSButton(title: L("연결"), target: nil, action: nil)
    private let rememberBox = NSButton(checkboxWithTitle: L("비밀번호를 키체인에 저장하고 다음부터 자동 연결"), target: nil, action: nil)
    private let profilePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let scanButton = NSButton(title: L("네트워크에서 찾기"), target: nil, action: nil)
    private let scanStatus = NSTextField(labelWithString: "")
    private let scanner = NetworkScanner()
    private var discovered: [NetworkScanner.Host] = []

    private enum Key {
        static let host = "host"
        static let user = "username"
        static let recent = "recentPCs"
    }

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 320),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L("kkguai — 원격 PC 연결")
        super.init(window: window)

        let defaults = UserDefaults.standard
        hostField.stringValue = defaults.string(forKey: Key.host) ?? ""
        userField.stringValue = defaults.string(forKey: Key.user) ?? ""
        hostField.placeholderString = L("192.168.0.10 또는 pc.example.com")
        userField.placeholderString = L("사용자 이름 또는 MicrosoftAccount\\메일주소")

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 5

        connectButton.target = self
        connectButton.action = #selector(connect)
        connectButton.keyEquivalent = "\r"
        connectButton.bezelStyle = .push

        desktopButton.target = self
        desktopButton.action = #selector(connectDesktop)
        desktopButton.bezelStyle = .push
        desktopButton.isHidden = true

        signOutButton.target = self
        signOutButton.action = #selector(signOutAndConnect)
        signOutButton.bezelStyle = .push
        signOutButton.isHidden = true

        profilePopUp.target = self
        profilePopUp.action = #selector(profileChosen)
        profilePopUp.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scanButton.bezelStyle = .rounded
        scanButton.target = self
        scanButton.action = #selector(scanNetwork)
        scanStatus.textColor = .secondaryLabelColor
        scanStatus.font = .systemFont(ofSize: 11)
        let scanRow = NSStackView(views: [scanButton, scanStatus])
        scanRow.orientation = .horizontal
        scanRow.spacing = 10

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: L("저장된 PC")), profilePopUp],
            [NSTextField(labelWithString: L("원격 PC 주소")), hostField],
            [NSTextField(labelWithString: L("사용자")), userField],
            [NSTextField(labelWithString: L("비밀번호")), passwordField],
            [NSGridCell.emptyContentView, rememberBox],
            [NSGridCell.emptyContentView, scanRow],
        ])
        rememberBox.state = .on
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.column(at: 1).width = 300

        let buttons = NSStackView(views: [statusLabel, signOutButton, desktopButton, connectButton])
        buttons.orientation = .horizontal
        buttons.distribution = .fill
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [grid, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        buttons.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
        reloadProfiles()
        window.center()
        window.initialFirstResponder = hostField.stringValue.isEmpty ? hostField : passwordField
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Opens the form for connecting to another PC (or with another account): the last address and
    /// user are filled in, the password is asked again. The current connection stays until Connect.
    func prepareForNewConnection(connected: Bool) {
        let defaults = UserDefaults.standard
        hostField.stringValue = defaults.string(forKey: Key.host) ?? ""
        userField.stringValue = defaults.string(forKey: Key.user) ?? ""
        passwordField.stringValue = ""
        setBusy(false, status: connected ? L("연결을 누르면 지금 연결이 끊기고 새 PC로 연결합니다.") : "")
        reloadProfiles()
        window?.makeFirstResponder(hostField)
    }

    func setBusy(_ busy: Bool, status: String) {
        connectButton.isEnabled = !busy
        statusLabel.stringValue = status
        desktopButton.isHidden = true
        signOutButton.isHidden = true
    }

    /// Shows a status plus a "connect in desktop mode" button (e.g. a session is already in use).
    func offerDesktopMode(status: String) {
        connectButton.isEnabled = true
        statusLabel.stringValue = status
        desktopButton.isHidden = false
        signOutButton.isHidden = false
    }

    @objc private func connect() {
        let host = hostField.stringValue.trimmingCharacters(in: .whitespaces)
        let user = userField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !user.isEmpty, !passwordField.stringValue.isEmpty else {
            setBusy(false, status: L("주소, 사용자, 비밀번호를 모두 입력하세요."))
            return
        }

        let defaults = UserDefaults.standard
        defaults.set(host, forKey: Key.host)
        defaults.set(user, forKey: Key.user)
        rememberRecent(host: host, user: user)

        let credentials = Credentials(host: host, username: user, password: passwordField.stringValue)
        passwordField.stringValue = ""
        setBusy(true, status: L("연결 중… %d%%", Int32(0)))
        onConnect?(credentials, rememberBox.state == .on)
    }

    // MARK: Saved PCs and discovery

    private func rememberRecent(host: String, user: String) {
        let defaults = UserDefaults.standard
        var list = (defaults.array(forKey: Key.recent) as? [[String: String]]) ?? []
        list.removeAll { $0["host"]?.lowercased() == host.lowercased() }
        list.insert(["host": host, "user": user], at: 0)
        defaults.set(Array(list.prefix(8)), forKey: Key.recent)
        reloadProfiles()
    }

    private func reloadProfiles() {
        profilePopUp.removeAllItems()
        let recents = (UserDefaults.standard.array(forKey: Key.recent) as? [[String: String]]) ?? []
        if recents.isEmpty && discovered.isEmpty {
            profilePopUp.addItem(withTitle: L("저장된 PC 없음"))
            profilePopUp.isEnabled = false
            return
        }
        profilePopUp.isEnabled = true
        for entry in recents {
            guard let host = entry["host"] else { continue }
            let user = entry["user"] ?? ""
            profilePopUp.addItem(withTitle: user.isEmpty ? host : "\(user) @ \(host)")
            profilePopUp.lastItem?.representedObject = [host, user]
        }
        if !discovered.isEmpty {
            if !recents.isEmpty { profilePopUp.menu?.addItem(.separator()) }
            let header = NSMenuItem(title: L("이 네트워크에서"), action: nil, keyEquivalent: "")
            header.isEnabled = false
            profilePopUp.menu?.addItem(header)
            for host in discovered {
                let name = host.label.map { "\($0) — " } ?? ""
                profilePopUp.addItem(withTitle: "\(name)\(host.address) · \(host.latencyMS) ms")
                profilePopUp.lastItem?.representedObject = [host.address, ""]
            }
        }
        // Do not land on the disabled "On This Network" header when there are no recent PCs.
        profilePopUp.selectItem(at: recents.isEmpty ? 1 : 0)
    }

    @objc private func profileChosen() {
        guard let pair = profilePopUp.selectedItem?.representedObject as? [String], pair.count == 2 else { return }
        hostField.stringValue = pair[0]
        if !pair[1].isEmpty { userField.stringValue = pair[1] }
        window?.makeFirstResponder(passwordField)
    }

    @objc private func scanNetwork() {
        scanButton.isEnabled = false
        scanStatus.stringValue = L("검색 중…")
        scanner.scan { [weak self] hosts in
            guard let self else { return }
            self.discovered = hosts
            self.scanButton.isEnabled = true
            self.scanStatus.stringValue = hosts.isEmpty
                ? L("3389 포트를 여는 PC를 찾지 못했습니다.")
                : L("%d대 발견", hosts.count)
            self.reloadProfiles()
        }
    }

    @objc private func signOutAndConnect() {
        guard let window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("원격 PC의 기존 세션을 로그아웃할까요?")
        alert.informativeText = L("원격 PC의 기존 세션을 화면에 띄웁니다. 저장할 것을 저장한 뒤 시작 → 로그아웃을 누르면 앱 창 모드로 다시 연결합니다. 로그아웃하면 그 세션의 프로그램은 모두 닫힙니다.")
        alert.addButton(withTitle: L("계속"))
        alert.addButton(withTitle: L("취소"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.setBusy(true, status: L("데스크톱 모드로 연결 중…"))
            self.onSignOutAndConnect?()
        }
    }

    @objc private func connectDesktop() {
        setBusy(true, status: L("데스크톱 모드로 연결 중…"))
        onConnectDesktop?()
    }
}
