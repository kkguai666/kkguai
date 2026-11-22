import AppKit

/// Real in-app updates: asks GitHub for the latest release, downloads its DMG, checks the
/// signature and swaps the app on disk, then relaunches. No browser round-trip.
final class Updater: NSObject, URLSessionDownloadDelegate {
    static let shared = Updater()
    static let repo = "kkguai666/kkguai"

    struct Release {
        let version: String
        let notes: String
        let dmg: URL
    }

    enum UpdateError: LocalizedError {
        case network(String)
        case badResponse
        case noAsset
        case installFailed

        var errorDescription: String? {
            switch self {
            case .network(let reason): return reason
            case .badResponse: return L("GitHub 응답을 이해하지 못했습니다.")
            case .noAsset: return L("이 릴리스에 macOS 설치 파일이 없습니다.")
            case .installFailed: return L("설치 파일을 확인하지 못했습니다.")
            }
        }
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// 1.10.2 counts as newer than 1.9.9, and "1.2" equals "1.2.0".
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
        let b = current.split(separator: ".").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let new = index < a.count ? a[index] : 0
            let old = index < b.count ? b[index] : 0
            if new != old { return new > old }
        }
        return false
    }

    private lazy var session = URLSession(configuration: .default, delegate: self,
                                          delegateQueue: OperationQueue.main)
    private var progressHandler: ((Double) -> Void)?
    private var finishHandler: ((Result<URL, Error>) -> Void)?
    private var verifying = false

    /// nil means "already on the newest release".
    func check(completion: @escaping (Result<Release?, Error>) -> Void) {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("kkguai-updater/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        session.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if let error {
                    completion(.failure(UpdateError.network(error.localizedDescription)))
                    return
                }
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String else {
                    completion(.failure(UpdateError.badResponse))
                    return
                }
                let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                guard Self.isNewer(version, than: Self.currentVersion) else {
                    completion(.success(nil))
                    return
                }
                let assets = json["assets"] as? [[String: Any]] ?? []
                guard let asset = assets.first(where: { ($0["name"] as? String)?.hasSuffix("-macos-arm64.dmg") == true }),
                      let urlString = asset["browser_download_url"] as? String,
                      let url = URL(string: urlString) else {
                    completion(.failure(UpdateError.noAsset))
                    return
                }
                completion(.success(Release(version: version,
                                            notes: json["body"] as? String ?? "",
                                            dmg: url)))
            }
        }.resume()
    }

    func download(_ release: Release, progress: @escaping (Double) -> Void,
                  completion: @escaping (Result<URL, Error>) -> Void) {
        progressHandler = progress
        finishHandler = completion
        session.downloadTask(with: release.dmg).resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler?(fraction)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("kkguai-update.dmg")
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            try Self.verify(dmg: destination)
            finishHandler?(.success(destination))
        } catch {
            finishHandler?(.failure(error))
        }
        finishHandler = nil
        progressHandler = nil
    }

    /// Mounts the DMG and checks that the app inside is intact, without touching /Applications yet.
    static func verify(dmg: URL) throws {
        let mount = NSTemporaryDirectory() + "kkguai-verify-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: mount, withIntermediateDirectories: true)
        defer {
            shell("/usr/bin/hdiutil", ["detach", mount, "-quiet"])
            try? FileManager.default.removeItem(atPath: mount)
        }
        guard shell("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-mountpoint", mount,
                                         dmg.path]) != nil,
              shell("/usr/bin/codesign", ["--verify", "--deep", "--strict", mount + "/kkguai.app"]) != nil else {
            throw UpdateError.installFailed
        }
    }

    /// A detached script waits for this process to exit, then replaces the app and relaunches it.
    /// Doing the swap while the app is running would replace files in use.
    static func installAndRelaunch(dmg: URL) throws {
        let script = """
        #!/bin/sh
        pid="$1"; dmg="$2"
        while kill -0 "$pid" 2>/dev/null; do sleep 0.3; done
        mnt="$(mktemp -d /tmp/kkguai-update.XXXXXX)"
        if ! /usr/bin/hdiutil attach -nobrowse -readonly -mountpoint "$mnt" "$dmg" >/dev/null 2>&1; then
            exit 1
        fi
        if ! /usr/bin/codesign --verify --deep --strict "$mnt/kkguai.app" >/dev/null 2>&1; then
            /usr/bin/hdiutil detach "$mnt" -quiet; exit 1
        fi
        rm -rf /Applications/kkguai.app
        if ! /usr/bin/ditto "$mnt/kkguai.app" /Applications/kkguai.app; then
            /usr/bin/hdiutil detach "$mnt" -quiet; exit 1
        fi
        /usr/bin/xattr -dr com.apple.quarantine /Applications/kkguai.app 2>/dev/null
        /usr/bin/hdiutil detach "$mnt" -quiet
        /usr/bin/open /Applications/kkguai.app
        """
        let path = NSTemporaryDirectory() + "kkguai-install.sh"
        try script.write(toFile: path, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [path, String(ProcessInfo.processInfo.processIdentifier), dmg.path]
        try process.run()
    }

    @discardableResult
    private static func shell(_ tool: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
