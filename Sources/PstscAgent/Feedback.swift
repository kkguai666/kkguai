import AppKit

/// Where feedback goes. The access key is public by design (it ships inside the app); it only lets
/// someone submit through Web3Forms to this one inbox, never read it.
enum FeedbackConfig {
    // Replaced by scripts/build-app.sh? No — keep it here, one place to change.
    static let accessKey = ProcessInfo.processInfo.environment["KKGUAI_FEEDBACK_KEY"]
        ?? "REPLACE_WITH_WEB3FORMS_ACCESS_KEY"
    static let fallbackEmail = "REPLACE_WITH_QQ_EMAIL"
    static let endpoint = URL(string: "https://api.web3forms.com/submit")!
}

/// The JSON body Web3Forms expects. Kept separate from the window so its shape is easy to check.
struct FeedbackPayload {
    var message: String
    var contact: String

    var subject: String {
        let firstLine = message
            .split(whereSeparator: \.isNewline)
            .first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let short = firstLine.count > 60 ? String(firstLine.prefix(60)) + "…" : firstLine
        return short.isEmpty ? "[kkguai] 피드백" : "[kkguai] \(short)"
    }

    /// Everything the maintainer needs to judge a report without asking back.
    var body: String {
        var lines = ["Message:", message, "", "---"]
        if !contact.isEmpty { lines.append("Contact: \(contact)") }
        lines.append("App: kkguai \(Self.appVersion)")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Language: \(UILanguage.current)")
        lines.append("Date: \(ISO8601DateFormatter().string(from: Date()))")
        return lines.joined(separator: "\n")
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    func json() throws -> Data {
        var fields: [String: Any] = [
            "access_key": FeedbackConfig.accessKey,
            "subject": subject,
            "from_name": "kkguai feedback",
            "message": body,
            "botcheck": false,
        ]
        if !contact.isEmpty { fields["email"] = contact }
        return try JSONSerialization.data(withJSONObject: fields)
    }
}

/// Sends one piece of feedback. Network failures come back as a human-readable reason.
final class FeedbackSender {
    enum Failure: Error {
        case notConfigured
        case status(Int, String?)
        case network(String)
    }

    func send(_ payload: FeedbackPayload, completion: @escaping (Result<Void, Failure>) -> Void) {
        guard !FeedbackConfig.accessKey.hasPrefix("REPLACE_") else {
            completion(.failure(.notConfigured))
            return
        }
        var request = URLRequest(url: FeedbackConfig.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        do {
            request.httpBody = try payload.json()
        } catch {
            completion(.failure(.network(error.localizedDescription)))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            let result: Result<Void, Failure>
            if let error {
                result = .failure(.network(error.localizedDescription))
            } else if let http = response as? HTTPURLResponse {
                let body = data.flatMap { String(data: $0, encoding: .utf8) }
                if (200..<300).contains(http.statusCode), body?.contains("\"success\":true") != false {
                    result = .success(())
                } else {
                    result = .failure(.status(http.statusCode, body))
                }
            } else {
                result = .failure(.network(L("응답을 받지 못했습니다.")))
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}

/// The small form behind the menu item: message, optional reply address, Send.
final class FeedbackWindowController: NSWindowController, NSTextViewDelegate {
    private let messageView = NSTextView()
    private let contactField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let sendButton = NSButton(title: L("보내기"), target: nil, action: nil)
    private let sender = FeedbackSender()
    private var sending = false

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L("kkguai — 피드백 보내기")
        super.init(window: window)

        let hint = NSTextField(labelWithString: L("불편한 점이나 원하는 기능을 알려 주세요. 모든 메시지를 읽습니다."))
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 2

        messageView.font = .systemFont(ofSize: 13)
        messageView.isRichText = false
        messageView.isAutomaticQuoteSubstitutionEnabled = false
        messageView.allowsUndo = true
        messageView.delegate = self
        messageView.textContainerInset = NSSize(width: 6, height: 6)

        let scroll = NSScrollView()
        scroll.documentView = messageView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(equalToConstant: 180).isActive = true
        messageView.minSize = NSSize(width: 0, height: 0)
        messageView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                     height: CGFloat.greatestFiniteMagnitude)
        messageView.isVerticallyResizable = true
        messageView.isHorizontallyResizable = false
        messageView.autoresizingMask = [.width]
        messageView.textContainer?.widthTracksTextView = true

        contactField.placeholderString = L("답장 받을 이메일 (선택)")

        let privacy = NSTextField(labelWithString: L("앱 버전, macOS 버전, 언어만 함께 전송됩니다."))
        privacy.textColor = .tertiaryLabelColor
        privacy.lineBreakMode = .byWordWrapping

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 3

        sendButton.target = self
        sendButton.action = #selector(send)
        sendButton.keyEquivalent = "\r"
        sendButton.bezelStyle = .push

        let footer = NSStackView(views: [statusLabel, sendButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [hint, scroll, contactField, privacy, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in [scroll, contactField, footer, hint, privacy] as [NSView] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        }

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func prepareToShow() {
        guard !sending else { return }
        statusLabel.stringValue = ""
        window?.makeFirstResponder(messageView)
    }

    private var messageText: String {
        messageView.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @objc private func send() {
        guard !sending else { return }
        let message = messageText
        guard !message.isEmpty else {
            statusLabel.stringValue = L("내용을 입력하세요.")
            return
        }

        sending = true
        sendButton.isEnabled = false
        sendButton.title = L("보내는 중…")
        statusLabel.stringValue = ""

        let payload = FeedbackPayload(message: message,
                                      contact: contactField.stringValue.trimmingCharacters(in: .whitespaces))
        sender.send(payload) { [weak self] result in
            guard let self else { return }
            self.sending = false
            self.sendButton.isEnabled = true
            self.sendButton.title = L("보내기")
            switch result {
            case .success:
                self.messageView.string = ""
                self.statusLabel.stringValue = L("감사합니다! 피드백을 보냈습니다.")
            case .failure(.notConfigured):
                self.statusLabel.stringValue = L("피드백 수신 주소가 설정되지 않았습니다.")
            case .failure(.status(let code, let body)):
                self.showFailure("HTTP \(code)" + (body.map { " · \($0)" } ?? ""))
            case .failure(.network(let detail)):
                self.showFailure(detail)
            }
        }
    }

    func textDidChange(_ notification: Notification) {
        if !statusLabel.stringValue.isEmpty { statusLabel.stringValue = "" }
    }

    private func showFailure(_ reason: String) {
        var text = L("보내지 못했습니다: %@", reason)
        if !FeedbackConfig.fallbackEmail.hasPrefix("REPLACE_") {
            text += " " + L("또는 %@ 로 직접 보내 주세요.", FeedbackConfig.fallbackEmail)
        }
        statusLabel.stringValue = text
    }
}
