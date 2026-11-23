import Foundation

/// 崩溃自恢复。用户把这东西当上班工具天天开着，崩一次就得自己重新打开、重连、
/// 把窗口摆回来。这里做两件事：
///
/// 1. 用 `running` 标记识别「上次没正常退出」，下次启动写进日志，方便事后查。
/// 2. 致命信号发生时自动重启（10 分钟内最多 3 次，防止崩溃循环把机器拖死）。
///
/// 信号处理器里只能用异步信号安全的调用。Swift 的 String/Date/Array 都不安全，
/// 所以所有判断在安装处理器时就算完，处理器里只碰 setenv/posix_spawn/_exit。
enum CrashGuard {
    private static var relaunches = 0
    private static let maxRelaunches = 3

    private static var folder: URL { AppCatalog.supportFolder }
    private static var markerURL: URL { folder.appendingPathComponent("running") }

    /// 启动时调用一次。返回上次是否异常退出。
    @discardableResult
    static func begin() -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let crashedLastTime = fm.fileExists(atPath: markerURL.path)
        try? Data("\(getpid())".utf8).write(to: markerURL)
        if crashedLastTime {
            FileHandle.standardError.write(Data("[kkguai] 上次没有正常退出（可能是崩溃）\n".utf8))
        }
        // 重启次数通过环境变量跨进程传递。
        if let raw = ProcessInfo.processInfo.environment["KKGUAI_RELAUNCH_COUNT"],
           let n = Int(raw) { relaunches = n }
        installHandlers()
        return crashedLastTime
    }

    /// 正常退出时调用，清掉标记。
    static func endCleanly() {
        try? FileManager.default.removeItem(at: markerURL)
    }

    // 处理器只读这些：安装时算好，之后不再分配。
    nonisolated(unsafe) private static var openPath: UnsafeMutablePointer<CChar>?
    nonisolated(unsafe) private static var flagN: UnsafeMutablePointer<CChar>?
    nonisolated(unsafe) private static var appPath: UnsafeMutablePointer<CChar>?
    nonisolated(unsafe) private static var canRelaunch = false
    nonisolated(unsafe) private static var nextCount = "1"

    private static func installHandlers() {
        let bundle = Bundle.main.bundlePath
        // 只有真正的 .app 才能用 open -n 重启；swift run 出来的裸二进制没有 bundle。
        canRelaunch = bundle.hasSuffix(".app") && FileManager.default.fileExists(atPath: "/usr/bin/open")
        guard canRelaunch else { return }
        openPath = strdup("/usr/bin/open")
        flagN = strdup("-n")
        appPath = strdup(bundle)
        nextCount = String(relaunches + 1)
        for sig in [SIGTRAP, SIGSEGV, SIGBUS, SIGABRT, SIGILL, SIGFPE] {
            signal(sig, kkguaiFatalSignal)
        }
    }

    /// 只做异步信号安全的事。setenv 的字符串是安装时算好的静态缓冲。
    fileprivate static func handleFatalSignal(_ sig: Int32) {
        guard canRelaunch, relaunches < maxRelaunches,
              let openPath, let flagN, let appPath else { _exit(1) }
        _ = setenv("KKGUAI_RELAUNCH_COUNT", nextCount, 1)
        var args: [UnsafeMutablePointer<CChar>?] = [openPath, flagN, appPath, nil]
        var pid = pid_t()
        _ = posix_spawn(&pid, openPath, nil, nil, &args, environ)
        _exit(1)
    }
}

/// C 函数指针不能捕获上下文，所以走一个全局入口。
private func kkguaiFatalSignal(_ sig: Int32) {
    CrashGuard.handleFatalSignal(sig)
}
