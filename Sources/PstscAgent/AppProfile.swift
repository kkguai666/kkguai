import Foundation

/// Per-program tuning. Remote apps differ a lot in how often their pixels matter: a video player
/// shows garbage if frames are dropped, while a chat or office window redraws dozens of times a
/// second for no visible gain. The profile decides how often each window uploads a frame, and
/// whether it opens always-on-top. Video players start in smooth mode; everything else follows
/// the automatic rule.
enum AppProfile {
    enum RefreshMode: Int, CaseIterable {
        /// Full rate while focused, a few frames per second in the background.
        case auto = 0
        /// Every update, focused or not.
        case smooth = 1
        /// A few frames per second even while focused: cheapest, for static tools.
        case eco = 2

        var title: String {
            switch self {
            case .auto: return L("자동 (권장)")
            case .smooth: return L("부드럽게 (영상·애니메이션)")
            case .eco: return L("절전 (정적인 앱)")
            }
        }
    }

    private static let modesKey = "appProfileModes"
    private static let pinnedKey = "appProfilePinned"

    /// Settings are keyed by the lowercase exe file name ("potplayermini64.exe"), so a program
    /// keeps them even when the same exe is reinstalled into another folder.
    static func key(_ programKey: String) -> String {
        let base = programKey.split(whereSeparator: { $0 == "\\" || $0 == "/" }).last.map(String.init)
            ?? programKey
        return base.lowercased()
    }

    static func mode(for programKey: String) -> RefreshMode {
        let key = self.key(programKey)
        guard let raw = UserDefaults.standard.dictionary(forKey: modesKey)?[key] as? Int,
              let mode = RefreshMode(rawValue: raw) else { return defaultMode(key) }
        return mode
    }

    /// Remembers an explicit choice; choosing the automatic mode again removes the override.
    static func setMode(_ mode: RefreshMode, for programKey: String) {
        let key = self.key(programKey)
        var all = UserDefaults.standard.dictionary(forKey: modesKey) ?? [:]
        if mode == defaultMode(key) {
            all.removeValue(forKey: key)
        } else {
            all[key] = mode.rawValue
        }
        UserDefaults.standard.set(all, forKey: modesKey)
    }

    static func isPinned(_ programKey: String) -> Bool {
        (UserDefaults.standard.dictionary(forKey: pinnedKey)?[key(programKey)] as? Bool) ?? false
    }

    static func setPinned(_ pinned: Bool, for programKey: String) {
        let key = self.key(programKey)
        var all = UserDefaults.standard.dictionary(forKey: pinnedKey) ?? [:]
        all[key] = pinned
        UserDefaults.standard.set(all, forKey: pinnedKey)
    }

    /// Drops both overrides: the program goes back to its built-in default.
    static func reset(_ programKey: String) {
        let key = self.key(programKey)
        var modes = UserDefaults.standard.dictionary(forKey: modesKey) ?? [:]
        modes.removeValue(forKey: key)
        UserDefaults.standard.set(modes, forKey: modesKey)
        var pinned = UserDefaults.standard.dictionary(forKey: pinnedKey) ?? [:]
        pinned.removeValue(forKey: key)
        UserDefaults.standard.set(pinned, forKey: pinnedKey)
    }

    /// Seconds between repaints for this program; 0 means every update is drawn.
    static func interval(for programKey: String, isFocused: Bool) -> TimeInterval {
        switch mode(for: programKey) {
        case .smooth: return 0
        case .eco: return 0.34
        case .auto: return isFocused ? 0 : 0.16
        }
    }

    /// Apps whose whole point is motion: throttling them shows as stutter, not as savings.
    private static func defaultMode(_ key: String) -> RefreshMode {
        let smooth = [
            "potplayer", "vlc", "mpv", "mplayer", "mpc-hc", "mpc-be", "kmplayer", "gomplayer",
            "wmplayer", "quicktime", "obs64", "iina", "plex", "youtube", "netflix",
        ]
        return smooth.contains(where: key.contains) ? .smooth : .auto
    }
}
