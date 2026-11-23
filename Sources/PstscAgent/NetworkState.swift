import Foundation
import Network

/// 诊断用的网络状态。只做同步、短超时的检查，写进诊断报告里，不弹窗、不改任何设置。
///
/// 用户报「连不上」时，第一件要分清的事是：Mac 自己有没有网，还是那台 Windows 不通。
/// 这两件事的排查方向完全不同，所以诊断报告里要分开写。
enum NetworkState {
    /// 当前有没有可用的网络路径，以及是 Wi-Fi 还是有线。
    static func summary() -> String {
        let monitor = NWPathMonitor()
        let semaphore = DispatchSemaphore(value: 0)
        var result = "unknown"
        monitor.pathUpdateHandler = { path in
            if path.status == .satisfied {
                let kinds = [
                    path.usesInterfaceType(.wifi) ? "wifi" : nil,
                    path.usesInterfaceType(.wiredEthernet) ? "ethernet" : nil,
                    path.usesInterfaceType(.cellular) ? "cellular" : nil,
                    path.usesInterfaceType(.other) ? "other" : nil,
                ].compactMap { $0 }
                let expensive = path.isExpensive ? " (metered)" : ""
                result = "online via \(kinds.isEmpty ? "unknown" : kinds.joined(separator: "+"))\(expensive)"
            } else {
                result = "offline"
            }
            semaphore.signal()
        }
        monitor.start(queue: .global(qos: .utility))
        // 路径状态通常立刻就有，但不该为它卡住诊断报告。
        _ = semaphore.wait(timeout: .now() + 2)
        monitor.cancel()
        return result
    }

    /// 到那台电脑的 3389 通不通，顺带给出握手耗时。
    static func reachability(host: String) -> String {
        let start = Date()
        let connection = NWConnection(host: NWEndpoint.Host(host),
                                      port: NWEndpoint.Port(rawValue: 3389) ?? 3389,
                                      using: .tcp)
        let semaphore = DispatchSemaphore(value: 0)
        var result = "no answer within 4 s"
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                result = "port 3389 reachable (\(ms) ms)"
                semaphore.signal()
            case .failed(let error):
                result = "port 3389 failed: \(error.localizedDescription)"
                semaphore.signal()
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .utility))
        _ = semaphore.wait(timeout: .now() + 4)
        connection.cancel()
        return result
    }
}
