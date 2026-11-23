import Foundation

/// A named set of remote programs. Saving captures what is running now; opening launches them all
/// again, and the window layout memory puts their windows back where they were.
struct Workspace: Codable {
    var name: String
    var host: String
    var appIDs: [String]
}

enum WorkspaceStore {
    private static let key = "workspaces"
    private static let lastSessionKey = "lastSession"

    /// 上次关掉 app 时还开着的程序。用户每天开同样的几个程序，重连后手动一个个点太蠢。
    /// 和命名工作区分开存：它会被自动覆盖，不该出现在工作区菜单里。
    struct LastSession: Codable {
        var host: String
        var appIDs: [String]
    }

    static func rememberLastSession(host: String, appIDs: [String]) {
        guard !appIDs.isEmpty else {
            UserDefaults.standard.removeObject(forKey: lastSessionKey)
            return
        }
        let session = LastSession(host: host, appIDs: appIDs)
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: lastSessionKey)
        }
    }

    static func lastSession(for host: String) -> [String]? {
        guard let data = UserDefaults.standard.data(forKey: lastSessionKey),
              let session = try? JSONDecoder().decode(LastSession.self, from: data),
              session.host.caseInsensitiveCompare(host) == .orderedSame,
              !session.appIDs.isEmpty else { return nil }
        return session.appIDs
    }

    static func forgetLastSession() {
        UserDefaults.standard.removeObject(forKey: lastSessionKey)
    }

    static func all() -> [Workspace] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Workspace].self, from: data) else { return [] }
        return list
    }

    static func workspaces(for host: String) -> [Workspace] {
        all().filter { $0.host.caseInsensitiveCompare(host) == .orderedSame }
    }

    static func save(_ workspace: Workspace) {
        var list = all().filter {
            !($0.name.caseInsensitiveCompare(workspace.name) == .orderedSame
              && $0.host.caseInsensitiveCompare(workspace.host) == .orderedSame)
        }
        list.append(workspace)
        persist(list)
    }

    static func remove(name: String, host: String) {
        persist(all().filter {
            !($0.name.caseInsensitiveCompare(name) == .orderedSame
              && $0.host.caseInsensitiveCompare(host) == .orderedSame)
        })
    }

    private static func persist(_ list: [Workspace]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
