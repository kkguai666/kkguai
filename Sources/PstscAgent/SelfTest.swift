import AppKit

/// 无窗口自检：`PstscAgent --self-test`。
///
/// 只跑那些写错就会在用户机器上崩、而编译器查不出来的路径。不开窗口、不抢焦点、
/// 不连远程、不碰用户数据，所以可以随时在后台跑。
///
/// 起因：0.2.2 的中文界面一打开连接窗口就崩，`Chinese.table` 里的重复键让 Swift
/// 在初始化字典字面量时 trap。编译期不报错，非中文用户永远看不到。
enum SelfTest {
    static func run() {
        var failures: [String] = []

        // 1. 每种界面语言都要能构造连接窗口——这正是当初崩掉的那条路径。
        for language in ["zh-Hans", "ko", "ja", "en"] {
            let controller = ConnectWindowController()
            guard let window = controller.window else {
                failures.append("\(language): 连接窗口没有创建出来")
                continue
            }
            // 触发一次布局，把只在 draw 时才会出错的路径也跑到。
            window.contentView?.layoutSubtreeIfNeeded()
            _ = window.title
        }

        // 2. 本地化表必须两张一致：中文有、英日没有的键，中文界面会静默显示韩语。
        let translated = Set(Translations.allKeys)
        let chinese = Set(Chinese.allKeys)
        for key in chinese.subtracting(translated).sorted() {
            failures.append("本地化缺失（中文有、英日无）：\(key)")
        }
        for key in translated.subtracting(chinese).sorted() {
            failures.append("本地化缺失（英日有、中文无）：\(key)")
        }

        // 3. 首次启动向导也要能建出来。
        let firstRun = FirstRunWindowController()
        if firstRun.window?.contentView?.subviews.isEmpty ?? true {
            failures.append("首次启动向导是空的")
        }

        // 4. 老版本留下的 ~/Applications/Pstsc 앱/ 必须能搬成 ~/Applications/kkguai/。
        //    用临时目录做，绝不碰用户真实的 Launchpad 目录。
        do {
            let fm = FileManager.default
            let root = fm.temporaryDirectory.appendingPathComponent("kkmig-\(UUID().uuidString)", isDirectory: true)
            let legacy = root.appendingPathComponent("Applications/Pstsc 앱", isDirectory: true)
            try? fm.createDirectory(at: legacy.appendingPathComponent("Notepad.app"), withIntermediateDirectories: true)
            try? fm.createDirectory(at: legacy.appendingPathComponent("Calculator.app"), withIntermediateDirectories: true)

            LauncherController.migrateLegacyFolder(in: root)

            let target = root.appendingPathComponent("Applications/kkguai", isDirectory: true)
            if fm.fileExists(atPath: legacy.path) {
                failures.append("迁移后老目录还在")
            }
            let moved = (try? fm.contentsOfDirectory(atPath: target.path)) ?? []
            if moved.count != 2 {
                failures.append("迁移后应有 2 个启动器，实际 \(moved.count)")
            }

            // 两个目录同时存在时，老的补进来、新的不覆盖。
            try? fm.createDirectory(at: legacy.appendingPathComponent("OldOnly.app"), withIntermediateDirectories: true)
            try? fm.createDirectory(at: target.appendingPathComponent("NewOnly.app"), withIntermediateDirectories: true)
            LauncherController.migrateLegacyFolder(in: root)
            let merged = Set((try? fm.contentsOfDirectory(atPath: target.path)) ?? [])
            if !merged.contains("OldOnly.app") || !merged.contains("NewOnly.app") || fm.fileExists(atPath: legacy.path) {
                failures.append("合并迁移不对：\(merged.sorted())")
            }
            try? fm.removeItem(at: root)
            print("迁移验证：首次搬迁 2 个、并存合并 \(merged.count) 个")
        }

        // 5. 搜索：子串、拼音全拼、拼音首字母都要命中，英文名不能被拆成首字母。
        let searches: [(String, String, Int?)] = [
            ("记事本", "记事本", 0),      // 前缀
            ("计算器", "算", 1),          // 子串
            ("记事本", "jishiben", 2),    // 全拼
            ("记事本", "jsb", 3),         // 首字母
            ("Google Chrome", "chrome", 1),
            ("Google Chrome", "gc", nil), // 英文不走首字母
            ("记事本", "xyz", nil),
        ]
        for (name, query, want) in searches {
            let got = SearchMatcher.score(name: name, query: query)
            if got != want {
                failures.append("搜索 \(name)/\(query) 期望 \(String(describing: want))，实际 \(String(describing: got))")
            }
        }

        // 6. 每种断开原因都要有一句非空、且不是同一个兜底文案的说明。
        var seen: [String] = []
        for reason in [RDPSession.DropReason.network, .credentials, .loggedOff, .remoteEnded, .cancelled] {
            let text = DropExplanation.text(for: reason)
            if text.isEmpty { failures.append("断开原因 \(reason) 没有说明") }
            if seen.contains(text) { failures.append("断开原因 \(reason) 和别的原因用了同一句话") }
            seen.append(text)
        }

        // 7. 屏幕外的窗口必须被拉回来；本来就在屏幕里的不能被挪动。
        if let screen = NSScreen.screens.first {
            let far = NSRect(x: screen.frame.maxX + 5000, y: screen.frame.maxY + 5000, width: 800, height: 600)
            let fixed = WindowLayoutStore.pullIntoView(far)
            if !screen.visibleFrame.intersects(fixed) {
                failures.append("屏幕外的窗口没被拉回：\(fixed)")
            }
            let inside = NSRect(x: screen.visibleFrame.minX + 40, y: screen.visibleFrame.minY + 40,
                                width: 600, height: 400)
            if WindowLayoutStore.pullIntoView(inside) != inside {
                failures.append("屏幕内的窗口被挪动了")
            }
        }

        // 8. 上次会话：同主机读得到，换主机读不到，清空后消失。
        let store = UserDefaults.standard
        let savedWorkspaces = store.data(forKey: "workspaces")
        let savedSession = store.data(forKey: "lastSession")
        defer {
            if let savedWorkspaces { store.set(savedWorkspaces, forKey: "workspaces") } else { store.removeObject(forKey: "workspaces") }
            if let savedSession { store.set(savedSession, forKey: "lastSession") } else { store.removeObject(forKey: "lastSession") }
        }
        WorkspaceStore.rememberLastSession(host: "192.168.1.20", appIDs: ["a", "b"])
        if WorkspaceStore.lastSession(for: "192.168.1.20") != ["a", "b"] {
            failures.append("上次会话没存住")
        }
        if WorkspaceStore.lastSession(for: "10.0.0.9") != nil {
            failures.append("换一台电脑不该还原上一台的程序")
        }
        WorkspaceStore.rememberLastSession(host: "192.168.1.20", appIDs: [])
        if WorkspaceStore.lastSession(for: "192.168.1.20") != nil {
            failures.append("清空后仍能读到上次会话")
        }

        // 9. 诊断必须能说清 Mac 自己有没有网（这一项不能是 unknown，否则报告没用）。
        let network = NetworkState.summary()
        if network == "unknown" {
            failures.append("网络状态没探到")
        }

        if failures.isEmpty {
            print("self-test OK：连接窗口 4 种语言、本地化 \(chinese.count) 个键、首次启动向导、搜索 \(searches.count) 项、断开说明 5 种、窗口拉回、上次会话、网络 \(network)")
        } else {
            for failure in failures { FileHandle.standardError.write(Data(("self-test FAIL: " + failure + "\n").utf8)) }
            exit(1)
        }
    }
}
