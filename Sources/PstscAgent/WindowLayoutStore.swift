import AppKit

/// Remembers where each remote program was on the Mac last time it was open, per PC.
/// Windows itself remembers its own positions after a reconnect, but those are desktop
/// coordinates; the Mac-side frame (including moves to a second display) is what users notice.
final class WindowLayoutStore {
    private static let defaultsKey = "windowLayouts"
    private static let limit = 400
    private let prefix: String

    init(host: String) {
        prefix = host.trimmingCharacters(in: .whitespaces).lowercased() + "|"
    }

    private static func key(for title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func frame(for title: String) -> NSRect? {
        guard !title.isEmpty,
              let all = UserDefaults.standard.dictionary(forKey: Self.defaultsKey),
              let numbers = all[prefix + Self.key(for: title)] as? [Double], numbers.count == 4 else { return nil }
        return NSRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }

    func store(_ frame: NSRect, title: String) {
        guard !title.isEmpty, frame.width >= 160, frame.height >= 80 else { return }
        var all = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) ?? [:]
        all[prefix + Self.key(for: title)] = [frame.origin.x, frame.origin.y, frame.width, frame.height]
        // Old PCs and long-gone documents should not grow this forever.
        if all.count > Self.limit {
            for key in all.keys.filter({ $0.hasPrefix(prefix) }).prefix(all.count - Self.limit) {
                all.removeValue(forKey: key)
            }
        }
        UserDefaults.standard.set(all, forKey: Self.defaultsKey)
    }
}
