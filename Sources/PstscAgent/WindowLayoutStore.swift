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
        return Self.pullIntoView(NSRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3]))
    }

    /// 拔掉外接显示器、改分辨率、把笔记本从扩展屏搬回内屏之后，之前记下的位置可能整块
    /// 落在所有屏幕之外——窗口看得见标题栏却拖不动，或者干脆不出现。把窗口拉回到最近的
    /// 屏幕可见区里，尺寸保留，位置贴边。
    static func pullIntoView(_ rect: NSRect) -> NSRect {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return rect }
        // 已经和某块屏幕有足够交叠就不动：只露出一角的窗口是用户自己摆的。
        let enough = rect.insetBy(dx: rect.width * 0.15, dy: 0).size
        for screen in screens {
            let overlap = screen.visibleFrame.intersection(rect)
            if !overlap.isNull && overlap.width >= min(enough.width, 120) && overlap.height >= 60 {
                return rect
            }
        }
        // 选离它中心最近的屏幕，然后把整个窗口挪进去。
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let target = screens.min { a, b in
            hypot(a.frame.midX - center.x, a.frame.midY - center.y)
                < hypot(b.frame.midX - center.x, b.frame.midY - center.y)
        } ?? screens[0]
        let visible = target.visibleFrame
        var fixed = rect
        fixed.size.width = min(rect.width, visible.width)
        fixed.size.height = min(rect.height, visible.height)
        fixed.origin.x = min(max(rect.minX, visible.minX), visible.maxX - fixed.width)
        fixed.origin.y = min(max(rect.minY, visible.minY), visible.maxY - fixed.height)
        return fixed
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
