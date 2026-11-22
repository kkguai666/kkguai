import Foundation
import QuartzCore

/// Opt-in performance counters, enabled with `PSTSC_STATS=1`. Prints a line to stderr every 5 s:
/// frames and pixels copied off the RDP thread, main-thread render time, and process CPU use.
final class PerfStats {
    static let shared = PerfStats()
    static let enabled = ProcessInfo.processInfo.environment["PSTSC_STATS"] == "1"

    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var startedAt = CACurrentMediaTime()

    // Counters for the current interval.
    private var frames = 0
    private var frameBytes = 0
    private var inputs = 0
    private var imageCount = 0
    private var imageTotal: Double = 0
    private var imageMax: Double = 0
    private var refreshCount = 0
    private var refreshTotal: Double = 0
    private var refreshMax: Double = 0
    private var showCount = 0
    private var showTotal: Double = 0
    private var showMax: Double = 0
    private var presentCount = 0
    private var presentTotal: Double = 0
    private var pendingInputAt: Double = 0
    private var latencyCount = 0
    private var latencyTotal: Double = 0
    private var latencyMax: Double = 0
    private var lastCPUTime: Double = 0

    private init() {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        lastCPUTime = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
            + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
    }

    func start() {
        guard Self.enabled, timer == nil else { return }
        startedAt = CACurrentMediaTime()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 5, repeating: 5)
        t.setEventHandler { [weak self] in self?.report() }
        t.resume()
        timer = t
        fputs("[stats] enabled (5 s interval)\n", stderr)
    }

    @inline(__always)
    func recordFrame(bytes: Int) {
        guard Self.enabled else { return }
        lock.lock(); frames += 1; frameBytes += bytes; lock.unlock()
    }

    @inline(__always)
    func recordInput() {
        guard Self.enabled else { return }
        lock.lock(); inputs += 1; pendingInputAt = CACurrentMediaTime(); lock.unlock()
    }

    /// Time spent building and handing off one frame.
    @inline(__always)
    func recordShow(_ seconds: Double) {
        guard Self.enabled else { return }
        lock.lock()
        showCount += 1
        showTotal += seconds
        showMax = max(showMax, seconds)
        lock.unlock()
    }

    /// Called when the pixels actually land in the view (draw), so the input-to-pixels latency
    /// covers everything the user waits for, not just the image build.
    @inline(__always)
    func recordPresented() {
        guard Self.enabled else { return }
        lock.lock()
        if pendingInputAt > 0 {
            let latency = CACurrentMediaTime() - pendingInputAt
            latencyCount += 1
            latencyTotal += latency
            latencyMax = max(latencyMax, latency)
            pendingInputAt = 0
        }
        lock.unlock()
    }

    /// Time spent creating and showing a remote window for the first time.
    @inline(__always)
    func recordPresent(_ seconds: Double) {
        guard Self.enabled else { return }
        lock.lock()
        presentCount += 1
        presentTotal += seconds
        lock.unlock()
    }

    /// Time spent building a CGImage for one window surface (main thread).
    @inline(__always)
    func recordImage(_ seconds: Double) {
        guard Self.enabled else { return }
        lock.lock()
        imageCount += 1
        imageTotal += seconds
        imageMax = max(imageMax, seconds)
        lock.unlock()
    }

    /// Time spent in one pass of RemoteWindowManager.refresh (main thread).
    @inline(__always)
    func recordRefresh(_ seconds: Double) {
        guard Self.enabled else { return }
        lock.lock()
        refreshCount += 1
        refreshTotal += seconds
        refreshMax = max(refreshMax, seconds)
        lock.unlock()
    }

    private func report() {
        lock.lock()
        let f = frames, fb = frameBytes, inp = inputs
        let ic = imageCount, it = imageTotal, imax = imageMax
        let rc = refreshCount, rt = refreshTotal, rmax = refreshMax
        let shc = showCount, sht = showTotal, shm = showMax
        let prc = presentCount, prt = presentTotal
        let lac = latencyCount, lat = latencyTotal, lmax = latencyMax
        frames = 0; frameBytes = 0; inputs = 0
        imageCount = 0; imageTotal = 0; imageMax = 0
        refreshCount = 0; refreshTotal = 0; refreshMax = 0
        showCount = 0; showTotal = 0; showMax = 0
        presentCount = 0; presentTotal = 0
        latencyCount = 0; latencyTotal = 0; latencyMax = 0
        lock.unlock()

        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
            + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
        let cpuPercent = (cpu - lastCPUTime) / 5.0 * 100
        lastCPUTime = cpu

        let imageAvg = ic > 0 ? it / Double(ic) * 1000 : 0
        let refreshAvg = rc > 0 ? rt / Double(rc) * 1000 : 0
        let showAvg = shc > 0 ? sht / Double(shc) * 1000 : 0
        let presentAvg = prc > 0 ? prt / Double(prc) * 1000 : 0
        let latencyAvg = lac > 0 ? lat / Double(lac) * 1000 : 0
        let mbps = Double(fb) / 5.0 / 1_048_576
        let line = String(
            format: "[stats] upd=%d (%.1f/s) px=%.1fMB/s images=%d avg=%.2fms max=%.2fms refreshes=%d avg=%.2fms max=%.2fms input=%d cpu=%.0f%% show=%d avg=%.2fms max=%.2fms presents=%d avg=%.2fms lat=%d avg=%.0fms max=%.0fms\n",
            f, Double(f) / 5.0, mbps, ic, imageAvg, imax * 1000, rc, refreshAvg, rmax * 1000, inp, cpuPercent,
            shc, showAvg, shm * 1000, prc, presentAvg, lac, latencyAvg, lmax * 1000)
        fputs(line, stderr)
    }
}
