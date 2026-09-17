import Foundation
import NetworkExtension

// DbaoTunnelEngine 是 VPN Core 适配层。iOS Packet Tunnel 只依赖这个协议，
// 不直接依赖 sing-box、Mihomo 或其他核心，方便处理许可证和后续替换。
public protocol DbaoTunnelEngine: AnyObject {
    func start(provider: NEPacketTunnelProvider, configContent: String) throws
    func reload(configContent: String) throws
    func sleep()
    func wake()
    func stop()
    func trafficSnapshot() -> (upload: UInt64, download: UInt64, available: Bool)
    func checkConnectivity(url: URL, completion: @escaping (Result<Void, Error>) -> Void)
}

// DbaoMissingTunnelEngine 用于没有接入真实 Core Framework 时的显式失败。
// 它不会伪造 VPN 已连接，避免测试时出现“图标亮了但不能上网”的假成功。
public final class DbaoMissingTunnelEngine: DbaoTunnelEngine {
    public init() {}

    public func start(provider: NEPacketTunnelProvider, configContent: String) throws {
        throw DbaoTunnelError.tunnelCoreMissing
    }

    public func reload(configContent: String) throws {
        throw DbaoTunnelError.tunnelCoreMissing
    }

    public func sleep() {}

    public func wake() {}

    public func stop() {}

    public func trafficSnapshot() -> (upload: UInt64, download: UInt64, available: Bool) {
        (0, 0, false)
    }

    public func checkConnectivity(url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.failure(DbaoTunnelError.tunnelCoreMissing))
    }
}
