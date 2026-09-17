import Foundation

// DbaoTunnelStore 通过 App Group 在主 App 与 Packet Tunnel Extension 之间传递配置。
// 后端下发的节点配置只写入共享容器，不写普通日志，也不放 UserDefaults。
public final class DbaoTunnelStore {
    private static let maximumDebugLogBytes = 512 * 1024
    private static let retainedDebugLogBytes = 256 * 1024
    private let appGroupID: String
    private let fileManager: FileManager
    private let logQueue = DispatchQueue(label: "com.dbao.tunnel-store.debug-log")

    public init(appGroupID: String, fileManager: FileManager = .default) {
        self.appGroupID = appGroupID
        self.fileManager = fileManager
    }

    public func containerURL() throws -> URL {
        guard let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            throw DbaoTunnelError.appGroupUnavailable
        }
        return url
    }

    public func configURL() throws -> URL {
        try containerURL().appendingPathComponent(DbaoTunnelConstants.storedConfigFileName)
    }

    public func generatedConfigURL() throws -> URL {
        try containerURL().appendingPathComponent(DbaoTunnelConstants.generatedSingBoxFileName)
    }

    public func debugLogURL() throws -> URL {
        try containerURL().appendingPathComponent(DbaoTunnelConstants.debugLogFileName)
    }

    public func cacheURL() throws -> URL {
        try containerURL().appendingPathComponent(DbaoTunnelConstants.cacheFileName)
    }

    public func writeBackendPayload(_ payload: [String: Any]) throws {
        let data = try DbaoJSON.data(from: payload)
        let url = try configURL()
        // Packet Tunnel Extension 会在独立进程中启动。调试阶段不使用 completeFileProtection，
        // 避免真机在锁屏或保护状态切换时刚写入的配置对扩展不可读。
        try data.write(to: url, options: [.atomic])
    }

    public func readBackendPayload() throws -> [String: Any] {
        let data = try Data(contentsOf: configURL())
        return try DbaoJSON.object(from: data)
    }

    public func writeGeneratedConfig(_ content: String) throws {
        let url = try generatedConfigURL()
        try content.data(using: .utf8)?.write(to: url, options: [.atomic])
    }

    public func backendPayloadFileSize() throws -> UInt64 {
        let attributes = try fileManager.attributesOfItem(atPath: configURL().path)
        return attributes[.size] as? UInt64 ?? 0
    }

    public func generatedConfigFileSize() throws -> UInt64 {
        let attributes = try fileManager.attributesOfItem(atPath: generatedConfigURL().path)
        return attributes[.size] as? UInt64 ?? 0
    }

    public func clearDebugLog() {
        do {
            let url = try debugLogURL()
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        } catch {
            NSLog("[LanbridgeTunnel] clear debug log failed: %@", error.localizedDescription)
        }
    }

    public func appendDebugLog(_ message: String) {
        let line = "\(Self.timestamp()) \(message)\n"
        logQueue.sync {
            do {
                let url = try debugLogURL()
                let data = Data(line.utf8)
                if fileManager.fileExists(atPath: url.path) {
                    try trimDebugLogIfNeeded(at: url, incomingBytes: data.count)
                    let handle = try FileHandle(forWritingTo: url)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } else {
                    try data.write(to: url, options: [.atomic])
                }
            } catch {
                NSLog("[LanbridgeTunnel] append debug log failed: %@", error.localizedDescription)
            }
        }
    }

    /// Extension 可以在后台运行很久，调试日志必须有上限，不能持续占用共享容器。
    private func trimDebugLogIfNeeded(at url: URL, incomingBytes: Int) throws {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let currentBytes = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard currentBytes + incomingBytes > Self.maximumDebugLogBytes else { return }
        let existing = try Data(contentsOf: url)
        let retained = existing.suffix(Self.retainedDebugLogBytes)
        try Data(retained).write(to: url, options: [.atomic])
    }

    public func readDebugLogTail(maxBytes: Int = 16 * 1024) -> String {
        do {
            let data = try Data(contentsOf: debugLogURL())
            let suffix = data.suffix(max(0, maxBytes))
            return String(decoding: suffix, as: UTF8.self)
        } catch {
            return ""
        }
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
