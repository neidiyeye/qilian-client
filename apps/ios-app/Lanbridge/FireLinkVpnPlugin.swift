import Flutter
import Foundation
import NetworkExtension

/// FireLinkVpnPlugin 把 Flutter 的平台无关动作转换为 NETunnelProviderManager 调用。
/// Flutter 不接触 sing-box 类型，未来替换 Core 时此通道协议保持不变。
final class FireLinkVpnPlugin: NSObject, FlutterPlugin {
    private let manager = DbaoPacketTunnelManager(
        appGroupID: DbaoTunnelConstants.placeholderAppGroupID,
        tunnelBundleID: DbaoTunnelConstants.placeholderTunnelBundleID
    )

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.ssyoo.huolian/vpn",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(FireLinkVpnPlugin(), channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        NSLog("[FireLinkVPN] Flutter action received: %@", call.method)
        switch call.method {
        case "prepare":
            manager.prepare { self.finish($0, result: result) }
        case "connect":
            guard let arguments = call.arguments as? [String: Any],
                  let payload = arguments["configuration"] as? [String: Any] else {
                finish(.failure(DbaoTunnelError.invalidPayload), result: result)
                return
            }
            let enableOnDemand = arguments["enable_on_demand"] as? Bool ?? true
            manager.connect(payload: payload, enableOnDemand: enableOnDemand) {
                self.finish($0, result: result)
            }
        case "reloadConfiguration":
            guard let payload = call.arguments as? [String: Any] else {
                finish(.failure(DbaoTunnelError.invalidPayload), result: result)
                return
            }
            manager.reload(payload: payload) { self.finish($0, result: result) }
        case "disconnect":
            manager.disconnect { self.finish($0, result: result) }
        case "getStatus":
            manager.status { status in
                DispatchQueue.main.async { result(self.statusText(status)) }
            }
        case "getTrafficStats":
            manager.trafficStats { response in
                switch response {
                case let .success(stats):
                    let value: [String: NSNumber] = [
                        "upload_bytes": NSNumber(value: stats["upload_bytes"] as? UInt64 ?? 0),
                        "download_bytes": NSNumber(value: stats["download_bytes"] as? UInt64 ?? 0),
                        "available": NSNumber(value: stats["available"] as? Bool ?? false),
                    ]
                    DispatchQueue.main.async { result(value) }
                case let .failure(error):
                    self.finish(.failure(error), result: result)
                }
            }
        case "checkConnectivity":
            guard let url = call.arguments as? String else {
                finish(.failure(DbaoTunnelError.invalidProbeURL), result: result)
                return
            }
            manager.checkConnectivity(urlString: url) { self.finish($0, result: result) }
        case "openConnectionLog":
            manager.openConnectionLog { self.finish($0, result: result) }
        case "clearConnectionLog":
            manager.clearConnectionLog { self.finish($0, result: result) }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func finish(_ response: Result<Void, Error>, result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            switch response {
            case .success:
                result(nil)
            case let .failure(error):
                let code = (error as? LocalizedError)?.errorDescription ?? "NATIVE_VPN_FAILED"
                NSLog("[FireLinkVPN] Flutter action failed: %@", code)
                result(FlutterError(code: code, message: code, details: nil))
            }
        }
    }

    private func statusText(_ status: NEVPNStatus) -> String {
        switch status {
        case .connected:
            return "connected"
        case .reasserting:
            // reasserting 表示系统 Tunnel 仍存在、正在适配新的物理网络。
            // 页面保持“已连接”，避免进出电梯或 Wi-Fi/蜂窝切换时闪成断开。
            return "connected"
        case .connecting:
            return "connecting"
        case .disconnecting:
            return "disconnecting"
        case .invalid, .disconnected:
            return "disconnected"
        @unknown default:
            return "failed"
        }
    }
}
