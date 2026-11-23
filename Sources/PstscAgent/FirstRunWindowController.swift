import AppKit

/// 新用户装上以后看到的第一个东西。没有它，用户只能看到一个要填 IP 和密码的窗口，
/// 却不知道那台 Windows 得先开 RemoteApp——这是绝大多数人第一次用就放弃的地方。
///
/// 三步：先在 Windows 上开好 RemoteApp（附一键 .reg 和官网指南），再填连接信息，
/// 最后说明装不上/连不上时去哪看。做成一页，不引入任何新依赖。
final class FirstRunWindowController: NSWindowController {
    /// 用户点「开始连接」后交给主窗口，直接进入连接流程。
    var onStart: (() -> Void)?
    /// 用户选了「稍后」，关掉向导，正常显示连接窗口。
    var onSkip: (() -> Void)?

    private let steps = NSStackView()

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 560),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L("kkguai에 오신 것을 환영합니다")
        window.center()
        super.init(window: window)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        guard let window, let content = window.contentView else { return }

        let title = NSTextField(labelWithString: L("kkguai에 오신 것을 환영합니다"))
        title.font = .systemFont(ofSize: 24, weight: .semibold)

        let subtitle = NSTextField(labelWithString: L("다른 Windows PC의 프로그램을 맥의 독립된 창으로. 세 단계면 됩니다."))
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.maximumNumberOfLines = 3

        steps.orientation = .vertical
        steps.alignment = .leading
        steps.spacing = 18

        steps.addArrangedSubview(step(
            number: "1",
            title: L("그 Windows PC에서 RemoteApp 켜기"),
            detail: L("Windows 10/11 Pro, Enterprise 또는 Server가 필요합니다. Home은 안 됩니다. enable-remoteapp.reg를 실행한 뒤 한 번 재시작하세요."),
            actions: [
                (L("enable-remoteapp.reg 내려받기"), #selector(openRemoteAppReg)),
                (L("그림 가이드 보기"), #selector(openGuide)),
            ]))

        steps.addArrangedSubview(step(
            number: "2",
            title: L("돌아와서 그 PC의 주소와 계정 입력"),
            detail: L("주소는 그 Windows의 LAN IP입니다(예: 192.168.1.20). 두 기기가 같은 네트워크에 있거나 VPN으로 연결돼 있어야 합니다."),
            actions: [(L("네트워크에서 찾기"), #selector(scanHint))]))

        steps.addArrangedSubview(step(
            number: "3",
            title: L("연결되면 원격 프로그램이 Launchpad에 나타납니다"),
            detail: L("각 원격 프로그램은 ~/Applications/kkguai에 런처가 생기고, ⌥Space로 원격 시작 메뉴를 열 수 있습니다."),
            actions: []))

        let skip = NSButton(title: L("나중에"), target: self, action: #selector(skip))
        skip.bezelStyle = .rounded
        let start = NSButton(title: L("연결 시작"), target: self, action: #selector(start))
        start.bezelStyle = .rounded
        start.keyEquivalent = "\r"

        let buttons = NSStackView(views: [skip, start])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let stack = NSStackView(views: [title, subtitle, steps, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            buttons.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])
    }

    private func step(number: String, title: String, detail: String,
                      actions: [(String, Selector)]) -> NSView {
        let badge = NSTextField(labelWithString: number)
        badge.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        badge.textColor = .white
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        badge.layer?.cornerRadius = 11
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.widthAnchor.constraint(equalToConstant: 22).isActive = true
        badge.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 14, weight: .medium)
        heading.lineBreakMode = .byWordWrapping
        heading.maximumNumberOfLines = 2

        let body = NSTextField(labelWithString: detail)
        body.font = .systemFont(ofSize: 12)
        body.textColor = .secondaryLabelColor
        body.lineBreakMode = .byWordWrapping
        body.maximumNumberOfLines = 4

        var views: [NSView] = [heading, body]
        if !actions.isEmpty {
            let row = NSStackView(views: actions.map { title, action in
                let button = NSButton(title: title, target: self, action: action)
                button.bezelStyle = .inline
                button.isBordered = false
                button.contentTintColor = .linkColor
                return button
            })
            row.orientation = .horizontal
            row.spacing = 16
            views.append(row)
        }

        let text = NSStackView(views: views)
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4

        let row = NSStackView(views: [badge, text])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 12
        return row
    }

    // MARK: 动作

    @objc private func start() {
        window?.orderOut(nil)
        onStart?()
    }

    @objc private func skip() {
        UserDefaults.standard.set(true, forKey: FirstRun.completedKey)
        window?.orderOut(nil)
        onSkip?()
    }

    @objc private func openRemoteAppReg() {
        // 打包在 app 里的 remote/enable-remoteapp.reg；找不到就退回仓库页面。
        if let url = Bundle.main.url(forResource: "enable-remoteapp", withExtension: "reg") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            open(FirstRun.repoURL + "/blob/main/remote/enable-remoteapp.reg")
        }
    }

    @objc private func openGuide() {
        open(FirstRun.siteURL + "/remoteapp-guide.html")
    }

    @objc private func scanHint() {
        // 连接窗口里本来就有「在网络中查找」，这里只是提示，不重复实现。
        let alert = NSAlert()
        alert.messageText = L("그 PC의 주소를 모르시나요?")
        alert.informativeText = L("'연결 시작' 후 연결 창에서 '네트워크에서 찾기'를 누르면 같은 네트워크에서 3389 포트가 열린 PC를 찾습니다.")
        alert.addButton(withTitle: L("확인"))
        alert.runModal()
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}

enum FirstRun {
    static let completedKey = "firstRunCompleted"
    static let siteURL = "https://kkguai666.github.io/kkguai"
    static let repoURL = "https://github.com/kkguai666/kkguai"

    static var needed: Bool { !UserDefaults.standard.bool(forKey: completedKey) }
}
