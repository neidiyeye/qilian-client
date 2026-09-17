import Foundation

// DbaoTunnelConstants 集中保存 iOS App 与 Packet Tunnel Extension 必须一致的标识。
// Bundle ID 和 App Group 需要等 Apple Developer 账号创建后替换为真实值。
public enum DbaoTunnelConstants {
    public static let placeholderAppGroupID = "group.com.ssyoo.vpn"
    public static let placeholderTunnelBundleID = "com.ssyoo.vpn.network-extension"
    public static let tunnelDisplayName = "启连加速器"
    public static let storedConfigFileName = "current-tunnel-config.json"
    public static let generatedSingBoxFileName = "generated-sing-box-config.json"
    public static let cacheFileName = "sing-box-cache.db"
    public static let debugLogFileName = "ios-vpn-debug.log"
}

// DbaoTunnelError 使用稳定错误码，前端可以直接复用现有多语言错误提示。
public enum DbaoTunnelError: Error, LocalizedError {
    case invalidPayload
    case appGroupUnavailable
    case vpnPermissionDenied
    case tunnelManagerUnavailable
    case tunnelCoreMissing
    case tunnelNotConnected
    case tunnelStartFailed(String)
    case invalidProbeURL

    public var errorDescription: String? {
        switch self {
        case .invalidPayload:
            return "INVALID_ENGINE_CONFIG"
        case .appGroupUnavailable:
            return "IOS_APP_GROUP_UNAVAILABLE"
        case .vpnPermissionDenied:
            return "IOS_VPN_PERMISSION_DENIED"
        case .tunnelManagerUnavailable:
            return "IOS_TUNNEL_MANAGER_UNAVAILABLE"
        case .tunnelCoreMissing:
            return "SING_BOX_IOS_CORE_MISSING"
        case .tunnelNotConnected:
            return "NATIVE_VPN_DISCONNECTED"
        case let .tunnelStartFailed(message):
            return message.isEmpty ? "NATIVE_VPN_START_FAILED" : message
        case .invalidProbeURL:
            return "INVALID_PROBE_URL"
        }
    }
}
