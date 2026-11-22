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
