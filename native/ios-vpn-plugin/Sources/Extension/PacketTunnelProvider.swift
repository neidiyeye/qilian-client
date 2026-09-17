import Foundation
import NetworkExtension

// PacketTunnelProvider 运行在 iOS Network Extension 进程内。
// 它负责读取 App Group 配置、生成完整 sing-box TUN 配置，并交给 DbaoTunnelEngine。
open class PacketTunnelProvider: NEPacketTunnelProvider {
    private var engine: DbaoTunnelEngine?
    private var store: DbaoTunnelStore?
    private var trafficReporter: DbaoTrafficReporter?

    override open func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        NSLog("[LanbridgeTunnel] startTunnel entered, optionKeys=%@", (options?.keys.sorted() ?? []).joined(separator: ","))
        var debugStore: DbaoTunnelStore?
        do {
            let appGroupID = try resolveAppGroupID(options: options)
            NSLog("[LanbridgeTunnel] app group resolved: %@", appGroupID)
            let store = DbaoTunnelStore(appGroupID: appGroupID)
            debugStore = store
            store.appendDebugLog("[Extension] startTunnel entered, optionKeys=\((options?.keys.sorted() ?? []).joined(separator: ","))")
            store.appendDebugLog("[Extension] app group resolved: \(appGroupID)")
            let backendPayload = try store.readBackendPayload()
            NSLog("[LanbridgeTunnel] backend payload loaded, %@", Self.payloadSummary(backendPayload))
            store.appendDebugLog("[Extension] backend payload loaded, \(Self.payloadSummary(backendPayload))")
            let configContent = try DbaoSingBoxConfigBuilder.build(
                from: backendPayload,
                cachePath: try store.cacheURL().path
            )
            try store.writeGeneratedConfig(configContent)
            let generatedSize = try store.generatedConfigFileSize()
            NSLog("[LanbridgeTunnel] sing-box config generated, bytes=%d", configContent.utf8.count)
            store.appendDebugLog("[Extension] sing-box config generated, builder=v2-no-legacy-inbound, bytes=\(generatedSize)")

            let engine = makeEngine()
            store.appendDebugLog("[Extension] engine created: \(String(describing: type(of: engine)))")
            try engine.start(provider: self, configContent: configContent)
            self.store = store
            self.engine = engine
            let trafficReporter = DbaoTrafficReporter(engine: engine, store: store)
            trafficReporter.update(payload: backendPayload)
            trafficReporter.start()
            self.trafficReporter = trafficReporter
            NSLog("[LanbridgeTunnel] engine started")
            store.appendDebugLog("[Extension] engine started")
            completionHandler(nil)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            NSLog("[LanbridgeTunnel] startTunnel failed: %@", message)
            debugStore?.appendDebugLog("[Extension] startTunnel failed: \(message)")
            completionHandler(error)
        }
    }

    override open func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        NSLog("[LanbridgeTunnel] stopTunnel reason=%d", reason.rawValue)
        store?.appendDebugLog("[Extension] stopTunnel reason=\(reason.rawValue)")
        trafficReporter?.flush()
        trafficReporter?.stop()
        trafficReporter = nil
        engine?.stop()
        engine = nil
        completionHandler()
    }

    /// 锁屏时系统会通知 Provider 进入休眠。这里保留 TUN 和 Core，避免把锁屏误当作断开。
    override open func sleep(completionHandler: @escaping () -> Void) {
        NSLog("[LanbridgeTunnel] provider sleep")
        store?.appendDebugLog("[Extension] provider sleep")
        engine?.sleep()
        completionHandler()
    }

    /// 唤醒时刷新上游网络路径；Core 继续使用原线路，不主动更换出口 IP。
    override open func wake() {
        NSLog("[LanbridgeTunnel] provider wake")
        store?.appendDebugLog("[Extension] provider wake")
        engine?.wake()
    }

    override open func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let completionHandler else { return }
        guard let request = try? DbaoJSON.object(from: messageData),
              let action = request["action"] as? String else {
            NSLog("[LanbridgeTunnel] app message invalid")
            completionHandler(Self.reply(error: "INVALID_ENGINE_CONFIG"))
            return
        }
        NSLog("[LanbridgeTunnel] app message action=%@", action)
        store?.appendDebugLog("[Extension] app message action=\(action)")
        switch action {
        case "getTrafficStats":
            completionHandler(Self.trafficReply(engine: engine))
        case "reloadConfiguration":
            guard let payload = request["payload"] as? [String: Any],
                  let store,
                  let engine else {
                completionHandler(Self.reply(error: "INVALID_ENGINE_CONFIG"))
                return
            }
            do {
                let configContent = try DbaoSingBoxConfigBuilder.build(
                    from: payload,
                    cachePath: try store.cacheURL().path
                )
                reasserting = true
                defer { reasserting = false }
                try engine.reload(configContent: configContent)
                // 只有 Core 接受新配置后才覆盖持久化配置，异常重启仍能使用最后一次成功线路。
                try store.writeBackendPayload(payload)
                try store.writeGeneratedConfig(configContent)
                trafficReporter?.update(payload: payload)
                trafficReporter?.flush()
                store.appendDebugLog("[Extension] configuration reloaded, \(Self.payloadSummary(payload))")
                completionHandler(Self.reply(value: ["ok": true]))
            } catch {
                let code = (error as? LocalizedError)?.errorDescription ?? "SING_BOX_RELOAD_FAILED"
                store.appendDebugLog("[Extension] configuration reload failed: \(code)")
                completionHandler(Self.reply(error: code))
            }
        case "checkConnectivity":
            guard let rawURL = request["url"] as? String,
                  let url = URL(string: rawURL),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host?.isEmpty == false else {
                NSLog("[LanbridgeTunnel] connectivity probe invalid url")
                completionHandler(Self.reply(error: "INVALID_PROBE_URL"))
                return
            }
            guard let engine else {
                NSLog("[LanbridgeTunnel] connectivity probe rejected, engine missing")
                completionHandler(Self.reply(error: "NATIVE_VPN_DISCONNECTED"))
                return
            }
            NSLog("[LanbridgeTunnel] connectivity probe start, host=%@", url.host ?? "")
            engine.checkConnectivity(url: url) { result in
                switch result {
                case .success:
                    NSLog("[LanbridgeTunnel] connectivity probe succeeded")
                    completionHandler(Self.reply(value: ["ok": true]))
                case let .failure(error):
                    NSLog("[LanbridgeTunnel] connectivity probe failed: %@", (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                    completionHandler(Self.reply(error: (error as? LocalizedError)?.errorDescription ?? "CONNECTIVITY_PROBE_FAILED"))
                }
            }
        default:
            NSLog("[LanbridgeTunnel] unsupported app message action=%@", action)
            completionHandler(Self.reply(error: "NATIVE_ACTION_UNSUPPORTED"))
        }
    }

    private static func trafficReply(engine: DbaoTunnelEngine?) -> Data? {
        let snapshot = engine?.trafficSnapshot() ?? (upload: 0, download: 0, available: false)
        return reply(value: [
            "upload_bytes": snapshot.upload,
            "download_bytes": snapshot.download,
            "available": snapshot.available,
        ])
    }

    private func resolveAppGroupID(options: [String: NSObject]?) throws -> String {
        if let appGroupID = options?["appGroupID"] as? String, !appGroupID.isEmpty {
            return appGroupID
        }
        if let providerConfiguration = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration,
           let appGroupID = providerConfiguration["appGroupID"] as? String,
           !appGroupID.isEmpty {
            return appGroupID
        }
        throw DbaoTunnelError.appGroupUnavailable
    }

    open func makeEngine() -> DbaoTunnelEngine {
        // 调试工程链接 Libbox 时使用真实 sing-box iOS Core。
        // 未放入 Libbox.xcframework 的环境仍保持显式失败，避免伪装成已连接。
        #if canImport(Libbox)
        return DbaoSingBoxTunnelEngine()
        #else
        return DbaoMissingTunnelEngine()
        #endif
    }

    private static func reply(value: [String: Any]) -> Data? {
        try? DbaoJSON.data(from: value)
    }

    private static func reply(error: String) -> Data? {
        try? DbaoJSON.data(from: ["ok": false, "error": error])
    }

    private static func payloadSummary(_ payload: [String: Any]) -> String {
        let outboundCount = (payload["outbounds"] as? [Any])?.count ?? 0
        let routeRuleCount = ((payload["route"] as? [String: Any])?["rules"] as? [Any])?.count ?? 0
        let keys = payload.keys.sorted().joined(separator: ",")
        return "payload keys=[\(keys)], outbounds=\(outboundCount), routeRules=\(routeRuleCount)"
    }
}

/// 主 App 被 iOS 挂起后 Packet Tunnel Extension 仍会运行，因此由这里定时提交 Core 累计流量。
/// 上报使用单会话令牌，不保存也不传递用户的登录令牌。
private final class DbaoTrafficReporter {
    private struct Control {
        let url: URL
        let sessionID: String
        let token: String
        let interval: TimeInterval
    }

    private weak var engine: DbaoTunnelEngine?
    private let store: DbaoTunnelStore
    private let queue = DispatchQueue(label: "com.ssyoo.huolian.traffic-reporter")
    private var control: Control?
    private var timer: DispatchSourceTimer?
    private var running = false
    private var requestInFlight = false

    init(engine: DbaoTunnelEngine, store: DbaoTunnelStore) {
        self.engine = engine
        self.store = store
    }

    func update(payload: [String: Any]) {
        let next = Self.control(from: payload)
        queue.async { [weak self] in
            guard let self else { return }
            self.control = next
            if self.running {
                self.scheduleTimer()
            }
        }
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.running else { return }
            self.running = true
            self.scheduleTimer()
        }
    }

    func flush() {
        // stopTunnel 会紧接着释放 reporter，这里必须强持有至请求已发出。
        queue.async { self.report() }
    }

    func stop() {
        queue.async { [weak self] in
            self?.running = false
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    private func scheduleTimer() {
        timer?.cancel()
        timer = nil
        guard running, let control else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 3, repeating: control.interval, leeway: .seconds(3))
        timer.setEventHandler { [weak self] in self?.report() }
        timer.resume()
        self.timer = timer
        store.appendDebugLog("[Traffic] background reporter scheduled, interval=\(Int(control.interval))s")
    }

    private func report() {
        guard !requestInFlight, let control, let engine else { return }
        let snapshot = engine.trafficSnapshot()
        guard snapshot.available else { return }
        let body: [String: Any] = [
            "session_id": control.sessionID,
            "token": control.token,
            "upload_bytes": snapshot.upload,
            "download_bytes": snapshot.download,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var request = URLRequest(url: control.url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        requestInFlight = true
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            self?.queue.async {
                guard let self else { return }
                self.requestInFlight = false
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if let error {
                    self.store.appendDebugLog("[Traffic] report failed: \(error.localizedDescription)")
                } else if !(200 ... 299).contains(status) {
                    self.store.appendDebugLog("[Traffic] report rejected, status=\(status)")
                }
            }
        }.resume()
    }

    private static func control(from payload: [String: Any]) -> Control? {
        guard let raw = payload["_firelink_control"] as? [String: Any],
              let urlText = raw["report_url"] as? String,
              let url = URL(string: urlText),
              url.scheme?.lowercased() == "https",
              let sessionID = raw["session_id"] as? String,
              sessionID.count == 32,
              let token = raw["token"] as? String,
              !token.isEmpty else {
            return nil
        }
        let requested = (raw["interval_seconds"] as? NSNumber)?.doubleValue ?? 30
        return Control(
            url: url,
            sessionID: sessionID,
            token: token,
            interval: max(30, min(60, requested))
        )
    }
}
