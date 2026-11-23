import Foundation

/// 把断开原因翻译成「用户接下来该做什么」。
///
/// 原来只显示「连接断开了」，用户不知道是网线拔了、密码错了，还是有人在另一台机器
/// 抢走了会话。四种原因对应的动作完全不同，说清楚比报错误码有用。
enum DropExplanation {
    /// 面向用户的一句话，包含下一步动作。
    static func text(for reason: RDPSession.DropReason) -> String {
        switch reason {
        case .network:
            return L("网络断了，正在自动重连。检查那台电脑是否还开着、是否在同一网络。")
        case .credentials:
            return L("密码或账号不对。重新输入一次；如果改过 Windows 密码，这里也要跟着改。")
        case .loggedOff:
            return L("那台电脑上的会话已经注销，正在重新建立连接。")
        case .remoteEnded:
            return L("那台电脑主动断开了这次连接：可能有人在它前面登录了，或另一台设备接管了这个会话。")
        case .cancelled:
            return L("连接已断开。")
        }
    }

    /// 重连提示的措辞：告诉用户还要等多久，而不是只说「重试中」。
    static func retryText(seconds: Int, attempt: Int) -> String {
        if attempt <= 1 {
            return L("正在重连…")
        }
        return L("%d 秒后重试（第 %d 次）", Int32(seconds), Int32(attempt))
    }
}
