import Foundation
import Network

/// Watches the Windows PC from the Mac side: a TCP probe against the RDP port every few seconds,
/// plus the system's own network path. When the PC comes back after a drop, the pending reconnect
/// can run immediately instead of waiting out the backoff.
final class ConnectionWatchdog {
    enum State: Equatable {
        case idle
        case checking
        case reachable(latencyMS: Int)
        case unreachable

        var isReachable: Bool {
            if case .reachable = self { return true }
            return false
        }
    }

    var onChange: ((State) -> Void)?
    /// The PC was unreachable (or the Mac had no network) and answers again.
    var onRecovered: (() -> Void)?

    private(set) var state: State = .idle {
        didSet {
            if state != oldValue { onChange?(state) }
        }
    }

    private var monitor: NWPathMonitor?
    private var timer: Timer?
    private var host: String?
    private var port: UInt16 = 3389
    private var probeInFlight = false

    func start(host: String, port: UInt16 = 3389) {
        // Reconnecting to the same PC: keep the monitor and the last reading instead of flickering.
        if host == self.host, monitor != nil {
            probe()
            return
        }
        stop()
        self.host = host
        self.port = port
        state = .checking
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self else { return }
                if path.status != .satisfied {
                    self.state = .unreachable
                } else if !self.state.isReachable {
                    self.probe()
                }
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
        self.monitor = monitor
        probe()
        let timer = Timer(timeInterval: 12, repeats: true) { [weak self] _ in self?.probe() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        monitor?.cancel()
        monitor = nil
        host = nil
        probeInFlight = false
        state = .idle
    }

    /// One short-lived TCP connection to host:3389; its handshake time is a decent latency estimate.
    private func probe() {
        guard let host, !host.isEmpty, !probeInFlight else { return }
        probeInFlight = true
        let started = Date()
        let connection = NWConnection(host: NWEndpoint.Host(host),
                                      port: NWEndpoint.Port(rawValue: port) ?? 3389,
                                      using: .tcp)
        var finished = false
        let finish: (Bool) -> Void = { [weak self] ok in
            DispatchQueue.main.async {
                guard let self, !finished else { return }
                finished = true
                self.probeInFlight = false
                connection.cancel()
                if ok {
                    let wasDown = self.state == .unreachable
                    self.state = .reachable(latencyMS: max(1, Int(Date().timeIntervalSince(started) * 1000)))
                    if wasDown { self.onRecovered?() }
                } else {
                    self.state = .unreachable
                }
            }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready: finish(true)
            case .failed, .cancelled: finish(false)
            default: break
            }
        }
        connection.start(queue: DispatchQueue.global(qos: .utility))
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { finish(false) }
    }
}
