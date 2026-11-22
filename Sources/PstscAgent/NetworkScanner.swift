import Foundation

/// Finds Windows PCs on the local network by probing port 3389 across the /24 the Mac is on.
/// Plain TCP connects, no discovery protocol: works even when the PC never advertises itself.
final class NetworkScanner {
    struct Host {
        let address: String
        let latencyMS: Int
        var label: String? = nil
    }

    private let queue = DispatchQueue(label: "kkguai.network-scan", attributes: .concurrent)

    func scan(completion: @escaping ([Host]) -> Void) {
        guard let prefix = Self.localSubnetPrefix() else {
            completion([])
            return
        }
        var found: [Host] = []
        let lock = NSLock()
        let group = DispatchGroup()
        let gate = DispatchSemaphore(value: 48)
        for last in 1...254 {
            group.enter()
            gate.wait()
            queue.async {
                defer {
                    gate.signal()
                    group.leave()
                }
                let address = "\(prefix).\(last)"
                guard let ms = Self.probe(address) else { return }
                lock.lock()
                found.append(Host(address: address, latencyMS: ms))
                lock.unlock()
            }
        }
        group.notify(queue: queue) {
            var result = found.sorted { $0.latencyMS < $1.latencyMS }
            // Tailscale PCs live on 100.x, outside this /24; ask the local daemon which are online
            // and keep the ones that really answer on 3389.
            for peer in TailscalePeers.onlinePeers()
            where !result.contains(where: { $0.address == peer.address }) {
                let address = peer.address
                guard let ms = Self.probe(address) else { continue }
                result.append(Host(address: address, latencyMS: ms, label: peer.name))
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    /// "192.168.1" for the first non-loopback IPv4 interface with a /24-style mask.
    private static func localSubnetPrefix() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = pointer {
            defer { pointer = interface.pointee.ifa_next }
            let flags = Int32(interface.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let addr = interface.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  let mask = interface.pointee.ifa_netmask else { continue }
            let masked = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee.sin_addr.s_addr.bigEndian
            }
            // Only /24 networks are scanned; anything else would be a guess that hits strangers.
            guard masked & 0xFFFF_FF00 == 0xFFFF_FF00 else { continue }
            let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            let bytes = [UInt8(ip >> 24), UInt8((ip >> 16) & 0xFF), UInt8((ip >> 8) & 0xFF)]
            return "\(bytes[0]).\(bytes[1]).\(bytes[2])"
        }
        return nil
    }

    /// A plain non-blocking TCP connect with a 1 s deadline. Network.framework reports .ready
    /// for hosts that never answered, so the BSD socket is the honest check here.
    private static func probe(_ host: String) -> Int? {
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(3389).bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { return nil }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        let started = Date()
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result != 0 {
            guard errno == EINPROGRESS else { return nil }
            var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            guard poll(&descriptor, 1, 1000) > 0 else { return nil }
        }
        var error: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0, error == 0 else { return nil }
        return max(1, Int(Date().timeIntervalSince(started) * 1000))
    }
}
