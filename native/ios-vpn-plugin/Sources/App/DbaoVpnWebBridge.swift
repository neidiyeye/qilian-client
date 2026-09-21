import Foundation
import NetworkExtension
import WebKit

// DbaoVpnWebBridge 适用于自有 WKWebView 容器，与前端 bridge.ts 的消息协议一致。
// 如果使用 DCloud 原生插件，可复用 DbaoPacketTunnelManager，把入口换成 requireNativePlugin。
public final class DbaoVpnWebBridge: NSObject, WKScriptMessageHandler {
    private let manager: DbaoPacketTunnelManager

    public init(appGroupID: String, tunnelBundleID: String) {
        self.manager = DbaoPacketTunnelManager(appGroupID: appGroupID, tunnelBundleID: tunnelBundleID)
        super.init()
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let id = body["id"] as? String,
              let action = body["action"] as? String else {
            return
        }
        NSLog("[LanbridgeVPN] web action received: %@", action)
        let payload = body["payload"]
        switch action {
        case "prepare":
            manager.prepare { self.reply(id: id, result: $0) }
        case "connect":
            do {
                let object = try DbaoJSON.object(from: payload as Any)
                manager.connect(payload: object) { self.reply(id: id, result: $0) }
            } catch {
                reply(id: id, result: .failure(error))
            }
        case "disconnect":
            manager.disconnect { self.reply(id: id, result: $0) }
        case "getStatus":
            manager.status { status in
                self.replyValue(id: id, value: self.statusText(status))
            }
        case "getTrafficStats":
            manager.trafficStats { result in
                switch result {
                case let .success(value):
                    self.replyValue(id: id, value: value)
                case let .failure(error):
                    self.replyError(id: id, error: error)
                }
            }
        case "checkConnectivity":
            guard let urlString = payload as? String else {
                reply(id: id, result: .failure(DbaoTunnelError.invalidProbeURL))
                return
            }
            manager.checkConnectivity(urlString: urlString) { self.reply(id: id, result: $0) }
        case "openConnectionLog":
            manager.openConnectionLog { self.reply(id: id, result: $0) }
        case "clearConnectionLog":
            manager.clearConnectionLog { self.reply(id: id, result: $0) }
        default:
            reply(id: id, result: .failure(DbaoTunnelError.tunnelStartFailed("NATIVE_ACTION_UNSUPPORTED")))
        }
    }

    private func reply(id: String, result: Result<Void, Error>) {
        switch result {
        case .success:
            replyValue(id: id, value: [:])
        case let .failure(error):
            replyError(id: id, error: error)
        }
    }

    private func replyValue(id: String, value: Any) {
        let payload: [String: Any] = ["id": id, "ok": true, "result": value]
        evaluateReply(payload)
    }

    private func replyError(id: String, error: Error) {
        let code = (error as? LocalizedError)?.errorDescription ?? "NATIVE_VPN_FAILED"
        NSLog("[LanbridgeVPN] web action failed: %@", code)
        let payload: [String: Any] = ["id": id, "ok": false, "error": code]
        evaluateReply(payload)
    }

    private func evaluateReply(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        DispatchQueue.main.async {
            // 实际接入时由宿主 WKWebView 执行 window.__dbaoNativeReply(json)。
            NotificationCenter.default.post(name: .dbaoVpnBridgeReply, object: json)
        }
    }

    private func statusText(_ status: NEVPNStatus) -> String {
        switch status {
        case .connected:
            return "connected"
        case .connecting, .reasserting:
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

public extension Notification.Name {
    static let dbaoVpnBridgeReply = Notification.Name("DbaoVpnBridgeReply")
}
