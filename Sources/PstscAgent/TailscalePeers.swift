import Foundation

/// The Tailscale CLI knows which of the user's machines are online right now — including PCs that
/// are not on the Mac's own /24, which a LAN scan can never find.
enum TailscalePeers {
    struct Peer {
        let name: String
        let address: String
    }

    private static let locations = [
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        "/usr/local/bin/tailscale",
        "/opt/homebrew/bin/tailscale",
    ]

    static func onlinePeers() -> [Peer] {
        guard let tool = locations.first(where: FileManager.default.isExecutableFile(atPath:)) else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = ["status", "--json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        // `tailscale status` talks to the local daemon; give it a moment but never hang the UI.
        let deadline = Date().addingTimeInterval(6)
        while process.isRunning && Date() < deadline { usleep(50_000) }
        if process.isRunning { process.terminate() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let peers = json["Peer"] as? [String: Any] else { return [] }
        var result: [Peer] = []
        for value in peers.values {
            guard let peer = value as? [String: Any],
                  let online = peer["Online"] as? Bool, online,
                  let addresses = peer["TailscaleIPs"] as? [String],
                  let address = addresses.first(where: { !$0.contains(":") }) else { continue }
            let name = (peer["HostName"] as? String) ?? (peer["DNSName"] as? String) ?? address
            result.append(Peer(name: name, address: address))
        }
        return result.sorted { $0.name < $1.name }
    }
}
