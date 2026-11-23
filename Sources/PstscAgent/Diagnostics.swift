import AppKit

/// Keeps a small log of what the app printed to stderr and can package it with system and
/// connection details, either as a zip on the Desktop or as text attached to feedback.
enum Diagnostics {
    static var folderURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/kkguai", isDirectory: true)
    }

    static var logURL: URL { folderURL.appendingPathComponent("kkguai.log") }

    /// Points stderr at the log file; everything the bridge and the app print lands there.
    static func installLogCapture() {
        let manager = FileManager.default
        try? manager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        if let size = try? manager.attributesOfItem(atPath: logURL.path)[.size] as? Int, size > 1_500_000 {
            let old = folderURL.appendingPathComponent("kkguai.old.log")
            try? manager.removeItem(at: old)
            try? manager.moveItem(at: logURL, to: old)
        }
        guard let handle = FileHandle(forWritingAtPath: logURL.path) ?? {
            manager.createFile(atPath: logURL.path, contents: nil)
            return FileHandle(forWritingAtPath: logURL.path)
        }() else { return }
        handle.seekToEndOfFile()
        dup2(handle.fileDescriptor, STDERR_FILENO)
        setvbuf(stderr, nil, _IONBF, 0)
        fputs("\n--- kkguai \(appVersion) (\(appBuild)) ---\n", stderr)
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    /// A plain-text report: no credentials, no keychain data, no remote screen contents.
    static func snapshot(extra: [String: String] = [:]) -> String {
        var lines: [String] = []
        lines.append("kkguai diagnostics")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("App: \(appVersion) (\(appBuild))")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("CPU: \(ProcessInfo.processInfo.processorCount) cores, \(ProcessInfo.processInfo.physicalMemory / 1_048_576) MB")
        lines.append("Language: \(UILanguage.current)")
        for screen in NSScreen.screens {
            lines.append(String(format: "Screen: %.0fx%.0f at %.0f,%.0f scale %.1f",
                                screen.frame.width, screen.frame.height, screen.frame.minX, screen.frame.minY,
                                screen.backingScaleFactor))
        }
        let peers = TailscalePeers.onlinePeers()
        lines.append("Tailscale peers: \(peers.isEmpty ? "none" : peers.map(\.name).joined(separator: ", "))")
        // 排障时最常被问的两件事：现在有没有网、那台电脑通不通。写进诊断就不用反复追问。
        lines.append("Network: \(NetworkState.summary())")
        if let host = extra["Host"], !host.isEmpty, host != "(none)" {
            lines.append("Probe: \(NetworkState.reachability(host: host))")
        }
        if !extra.isEmpty {
            lines.append("")
            lines.append("State:")
            for key in extra.keys.sorted() {
                lines.append("  \(key): \(extra[key] ?? "")")
            }
        }
        lines.append("")
        lines.append("Log (last 400 lines):")
        lines.append(contentsOf: logTail(lines: 400))
        return lines.joined(separator: "\n")
    }

    private static func logTail(lines: Int) -> [String] {
        guard let data = try? Data(contentsOf: logURL),
              let text = String(data: data, encoding: .utf8) else { return ["(no log yet)"] }
        return Array(text.split(separator: "\n").suffix(lines)).map(String.init)
    }

    /// Writes a zip next to the Desktop and returns where it went.
    static func saveBundle(extra: [String: String]) -> URL? {
        let manager = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let name = "kkguai-diagnostics-\(stamp)"
        let folder = manager.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try? manager.removeItem(at: folder)
        guard (try? manager.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return nil }
        try? snapshot(extra: extra).write(to: folder.appendingPathComponent("report.txt"),
                                          atomically: true, encoding: .utf8)
        if let log = try? Data(contentsOf: logURL) {
            try? log.write(to: folder.appendingPathComponent("kkguai.log"))
        }
        guard let desktop = manager.urls(for: .desktopDirectory, in: .userDomainMask).first else { return nil }
        let zip = desktop.appendingPathComponent(name).appendingPathExtension("zip")
        try? manager.removeItem(at: zip)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", folder.path, zip.path]
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        try? manager.removeItem(at: folder)
        return process.terminationStatus == 0 ? zip : nil
    }
}
