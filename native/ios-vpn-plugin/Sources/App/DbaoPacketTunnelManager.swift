import Foundation
import NetworkExtension

// DbaoPacketTunnelManager 运行在主 App 内，负责创建系统 VPN 配置并启动 Packet Tunnel。
// 它不直接处理数据包，真正转发发生在 Extension 进程内。
public final class DbaoPacketTunnelManager {
    private let appGroupID: String
    private let tunnelBundleID: String
    private let store: DbaoTunnelStore
    // NETunnelProviderManager 对象会持续同步 connection.status，无需每秒重新读取系统偏好。
    // 缓存它可减少状态轮询和流量刷新期间的 I/O 与日志噪声。
    private var cachedManager: NETunnelProviderManager?
    private var connectionObserver: NSObjectProtocol?
    private var connectionTimeout: DispatchWorkItem?
    // 真机上 Packet Tunnel 应在数秒内进入 connected 或明确失败。
    // 节点连通慢不应该表现为系统 VPN 长时间 connecting，所以这里保留短兜底，
    // 让页面及时显示可排查的中文错误。
    private static let connectionStartTimeoutSeconds: TimeInterval = 10

    public init(appGroupID: String, tunnelBundleID: String) {
        self.appGroupID = appGroupID
        self.tunnelBundleID = tunnelBundleID
        self.store = DbaoTunnelStore(appGroupID: appGroupID)
    }

    public func prepare(completion: @escaping (Result<Void, Error>) -> Void) {
        NSLog("[LanbridgeVPN] prepare requested")
        loadOrCreateManager { result in
            switch result {
            case let .success(manager):
                NSLog("[LanbridgeVPN] prepare ready, status=%@", Self.statusText(manager.connection.status))
            case let .failure(error):
                NSLog("[LanbridgeVPN] prepare failed: %@", Self.errorCode(error))
            }
            completion(result.map { _ in () })
        }
    }

    public func connect(
        payload: [String: Any],
        enableOnDemand: Bool = true,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        NSLog("[LanbridgeVPN] connect requested, %@", Self.payloadSummary(payload))
        do {
            store.clearDebugLog()
            store.appendDebugLog("[App] connect requested, \(Self.payloadSummary(payload))")
            try store.writeBackendPayload(payload)
            let fileSize = try store.backendPayloadFileSize()
            let configURL = try store.configURL()
            NSLog("[LanbridgeVPN] backend payload saved to app group, exists=%@ bytes=%llu path=%@", FileManager.default.fileExists(atPath: configURL.path) ? "yes" : "no", fileSize, configURL.path)
            store.appendDebugLog("[App] backend payload saved, bytes=\(fileSize), path=\(configURL.path)")
        } catch {
            NSLog("[LanbridgeVPN] backend payload save failed: %@", Self.errorCode(error))
            store.appendDebugLog("[App] backend payload save failed: \(Self.errorCode(error))")
            completion(.failure(error))
            return
        }
        loadOrCreateManager { result in
            switch result {
            case let .failure(error):
                NSLog("[LanbridgeVPN] load manager failed before start: %@", Self.errorCode(error))
                completion(.failure(error))
            case let .success(manager):
                let options: [String: NSObject] = [
                    "appGroupID": self.appGroupID as NSString,
                    "manualStart": NSNumber(value: true),
                ]
                self.startWhenReady(manager: manager, options: options) { startResult in
                    switch startResult {
                    case let .failure(error):
                        completion(.failure(error))
                    case .success:
                        guard enableOnDemand else {
                            completion(.success(()))
                            return
                        }
                        // 手动连接成功后才开启按需连接。后续锁屏、进程退出或网络切换时，
                        // iOS 可以使用 App Group 中最后一次成功配置重启 Extension。
                        self.setOnDemandEnabled(true, manager: manager) { onDemandResult in
                            if case let .failure(error) = onDemandResult {
                                self.store.appendDebugLog("[App] enable on-demand failed: \(Self.errorCode(error))")
                                NSLog("[LanbridgeVPN] enable on-demand failed: %@", Self.errorCode(error))
                            }
                            // 数据面已经连接；按需规则保存失败只影响后续自动恢复，
                            // 不能把本次成功连接反向显示成失败。
                            completion(.success(()))
                        }
                    }
                }
            }
        }
    }

    public func disconnect(completion: @escaping (Result<Void, Error>) -> Void) {
        NSLog("[LanbridgeVPN] disconnect requested")
        loadExistingManager { result in
            switch result {
            case .failure:
                // 没有系统配置等价于已经断开，保持主动断开的幂等性。
                completion(.success(()))
            case let .success(manager):
                // 先关闭按需规则再停止 Tunnel，防止系统在用户主动断开后立即拉起。
                self.setOnDemandEnabled(false, manager: manager) { onDemandResult in
                    if case let .failure(error) = onDemandResult {
                        self.store.appendDebugLog("[App] disable on-demand failed: \(Self.errorCode(error))")
                        NSLog("[LanbridgeVPN] disable on-demand failed: %@", Self.errorCode(error))
                    }
                    NSLog("[LanbridgeVPN] stopVPNTunnel called, current status=%@", Self.statusText(manager.connection.status))
                    manager.connection.stopVPNTunnel()
                    completion(.success(()))
                }
            }
        }
    }

    /// 保持 NETunnelProviderSession 在线，仅让 Extension 热重载 Core 配置。
    public func reload(payload: [String: Any], completion: @escaping (Result<Void, Error>) -> Void) {
        NSLog("[LanbridgeVPN] reload requested, %@", Self.payloadSummary(payload))
        sendProviderMessage(["action": "reloadConfiguration", "payload": payload]) { result in
            switch result {
            case let .success(reply):
                if reply["ok"] as? Bool == true {
                    NSLog("[LanbridgeVPN] reload succeeded")
                    completion(.success(()))
                } else {
                    let error = reply["error"] as? String ?? "SING_BOX_RELOAD_FAILED"
                    NSLog("[LanbridgeVPN] reload failed: %@", error)
                    completion(.failure(DbaoTunnelError.tunnelStartFailed(error)))
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    public func checkConnectivity(urlString: String, completion: @escaping (Result<Void, Error>) -> Void) {
        NSLog("[LanbridgeVPN] checkConnectivity requested, host=%@", URL(string: urlString)?.host ?? "")
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else {
            completion(.failure(DbaoTunnelError.invalidProbeURL))
            return
        }
        sendProviderMessage(["action": "checkConnectivity", "url": url.absoluteString]) { result in
            switch result {
            case let .success(reply):
                if (reply["ok"] as? Bool) == true {
                    NSLog("[LanbridgeVPN] checkConnectivity succeeded")
                    completion(.success(()))
                } else {
                    let error = reply["error"] as? String ?? "CONNECTIVITY_PROBE_FAILED"
                    NSLog("[LanbridgeVPN] checkConnectivity failed: %@", error)
                    completion(.failure(DbaoTunnelError.tunnelStartFailed(error)))
                }
            case let .failure(error):
                NSLog("[LanbridgeVPN] checkConnectivity provider message failed: %@", Self.errorCode(error))
                completion(.failure(error))
            }
        }
    }

    public func trafficStats(completion: @escaping (Result<[String: Any], Error>) -> Void) {
        sendProviderMessage(["action": "getTrafficStats"]) { result in
            switch result {
            case let .success(reply):
                let upload = Self.uint64Value(reply["upload_bytes"])
                let download = Self.uint64Value(reply["download_bytes"])
                let available = reply["available"] as? Bool ?? false
                completion(.success([
                    "upload_bytes": upload,
                    "download_bytes": download,
                    "available": available,
                ]))
            case let .failure(error):
                NSLog("[LanbridgeVPN] trafficStats failed: %@", Self.errorCode(error))
                completion(.failure(error))
            }
        }
    }

    public func openConnectionLog(completion: @escaping (Result<Void, Error>) -> Void) {
        let tail = store.readDebugLogTail(maxBytes: 64 * 1024)
        if tail.isEmpty {
            NSLog("[LanbridgeVPN] connection log is empty")
            completion(.failure(DbaoTunnelError.tunnelStartFailed("CONNECTION_LOG_EMPTY")))
            return
        }
        NSLog("[LanbridgeVPN] connection log tail:\n%@", tail)
        completion(.success(()))
    }

    public func clearConnectionLog(completion: @escaping (Result<Void, Error>) -> Void) {
        store.clearDebugLog()
        completion(.success(()))
    }

    public func status(completion: @escaping (NEVPNStatus) -> Void) {
        loadExistingManager { result in
            switch result {
            case let .success(manager):
                completion(manager.connection.status)
            case .failure:
                completion(.disconnected)
            }
        }
    }

    private func sendProviderMessage(_ payload: [String: Any], completion: @escaping (Result<[String: Any], Error>) -> Void) {
        loadExistingManager { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(manager):
                self.sendProviderMessage(
                    payload,
                    through: manager,
                    connectingDeadline: Date().addingTimeInterval(1.5),
                    completion: completion
                )
            }
        }
    }

    /// 向已经运行的 Packet Tunnel Extension 发送控制命令。
    ///
    /// 热切换线路时，Extension 会短暂设置 `reasserting`。此时系统 VPN 会话仍然存在，
    /// `NETunnelProviderSession` 也仍可接收消息，不能把它误判成断开。`connecting` 则可能是
    /// NetworkExtension 尚未完成状态同步，因此只等待一个很短的窗口，避免检测队列被长期阻塞。
    private func sendProviderMessage(
        _ payload: [String: Any],
        through manager: NETunnelProviderManager,
        connectingDeadline: Date,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        let status = manager.connection.status
        switch status {
        case .connected, .reasserting:
            break
        case .connecting where Date() < connectingDeadline:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self else {
                    completion(.failure(DbaoTunnelError.tunnelManagerUnavailable))
                    return
                }
                self.sendProviderMessage(
                    payload,
                    through: manager,
                    connectingDeadline: connectingDeadline,
                    completion: completion
                )
            }
            return
        case .invalid, .disconnected, .disconnecting, .connecting:
            NSLog("[LanbridgeVPN] provider message blocked, status=%@", Self.statusText(status))
            completion(.failure(DbaoTunnelError.tunnelNotConnected))
            return
        @unknown default:
            NSLog("[LanbridgeVPN] provider message blocked, unknown status")
            completion(.failure(DbaoTunnelError.tunnelNotConnected))
            return
        }

        guard let session = manager.connection as? NETunnelProviderSession else {
            completion(.failure(DbaoTunnelError.tunnelManagerUnavailable))
            return
        }
        do {
            let data = try DbaoJSON.data(from: payload)
            try session.sendProviderMessage(data) { response in
                do {
                    guard let response else {
                        NSLog("[LanbridgeVPN] provider message returned empty response")
                        completion(.failure(DbaoTunnelError.tunnelStartFailed("NATIVE_VPN_FAILED")))
                        return
                    }
                    completion(.success(try DbaoJSON.object(from: response)))
                } catch {
                    completion(.failure(error))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    private static func uint64Value(_ value: Any?) -> UInt64 {
        if let value = value as? UInt64 { return value }
        if let value = value as? Int { return UInt64(max(value, 0)) }
        if let value = value as? NSNumber { return value.uint64Value }
        return 0
    }

    private func waitForConnected(manager: NETunnelProviderManager, completion: @escaping (Result<Void, Error>) -> Void) {
        clearConnectionWait()

        let session = manager.connection
        let startedAt = Date()
        var finished = false
        var sawStartingState = [NEVPNStatus.connecting, .reasserting, .connected].contains(session.status)
        var observer: NSObjectProtocol?
        var timeout: DispatchWorkItem?

        func finish(_ result: Result<Void, Error>) {
            if finished { return }
            finished = true
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            timeout?.cancel()
            self.connectionObserver = nil
            self.connectionTimeout = nil
            let elapsedMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1000)
            self.store.appendDebugLog("[App] connection wait finished, elapsedMs=\(elapsedMilliseconds)")
            NSLog("[LanbridgeVPN] connection wait finished, elapsedMs=%d", elapsedMilliseconds)
            if case let .failure(error) = result {
                let tail = self.store.readDebugLogTail()
                if !tail.isEmpty {
                    NSLog("[LanbridgeVPN] tunnel debug log tail before failure:\n%@", tail)
                }
                self.store.appendDebugLog("[App] connect failed: \(Self.errorCode(error))")
            }
            completion(result)
        }

        func inspect(_ status: NEVPNStatus) {
            NSLog("[LanbridgeVPN] status changed: %@", Self.statusText(status))
            self.store.appendDebugLog("[App] status changed: \(Self.statusText(status))")
            switch status {
            case .connected:
                finish(.success(()))
            case .connecting, .reasserting:
                sawStartingState = true
            case .invalid:
                finish(.failure(DbaoTunnelError.tunnelManagerUnavailable))
            case .disconnected:
                if sawStartingState {
                    finish(.failure(DbaoTunnelError.tunnelStartFailed("NATIVE_VPN_START_FAILED")))
                }
            case .disconnecting:
                break
            @unknown default:
                finish(.failure(DbaoTunnelError.tunnelStartFailed("NATIVE_VPN_START_FAILED")))
            }
        }

        observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: session,
            queue: .main
        ) { _ in
            inspect(session.status)
        }
        timeout = DispatchWorkItem {
            NSLog("[LanbridgeVPN] startTunnel wait timed out, last status=%@", Self.statusText(session.status))
            finish(.failure(DbaoTunnelError.tunnelStartFailed("NATIVE_VPN_TIMEOUT")))
        }
        self.connectionObserver = observer
        self.connectionTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.connectionStartTimeoutSeconds, execute: timeout!)
        inspect(session.status)
    }

    private func startWhenReady(
        manager: NETunnelProviderManager,
        options: [String: NSObject],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        if manager.connection.status == .disconnecting {
            NSLog("[LanbridgeVPN] startTunnel deferred until disconnected")
            store.appendDebugLog("[App] startTunnel deferred until disconnected")
            waitForDisconnected(manager: manager) { result in
                switch result {
                case .success:
                    self.startWhenReady(manager: manager, options: options, completion: completion)
                case let .failure(error):
                    completion(.failure(error))
                }
            }
            return
        }

        do {
            NSLog("[LanbridgeVPN] startTunnel called, current status=%@", Self.statusText(manager.connection.status))
            store.appendDebugLog("[App] startTunnel called, status=\(Self.statusText(manager.connection.status))")
            try (manager.connection as? NETunnelProviderSession)?.startTunnel(options: options)
            waitForConnected(manager: manager, completion: completion)
        } catch {
            NSLog("[LanbridgeVPN] startTunnel threw error: %@", error.localizedDescription)
            store.appendDebugLog("[App] startTunnel threw error: \(error.localizedDescription)")
            completion(.failure(Self.normalize(error)))
        }
    }

    private func waitForDisconnected(manager: NETunnelProviderManager, completion: @escaping (Result<Void, Error>) -> Void) {
        let session = manager.connection
        if session.status != .disconnecting {
            completion(.success(()))
            return
        }
        clearConnectionWait()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.connectionObserver != nil else { return }
            self.clearConnectionWait()
            NSLog("[LanbridgeVPN] wait for disconnect timed out")
            completion(.failure(DbaoTunnelError.tunnelStartFailed("NATIVE_VPN_DISCONNECT_TIMEOUT")))
        }
        connectionObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: session,
            queue: .main
        ) { [weak self] _ in
            guard let self,
                  session.status != .disconnecting,
                  self.connectionObserver != nil else { return }
            self.clearConnectionWait()
            NSLog("[LanbridgeVPN] disconnect finished before deferred start, status=%@", Self.statusText(session.status))
            completion(.success(()))
        }
        connectionTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: timeout)
    }

    private func clearConnectionWait() {
        if let connectionObserver {
            NotificationCenter.default.removeObserver(connectionObserver)
        }
        connectionTimeout?.cancel()
        connectionObserver = nil
        connectionTimeout = nil
    }

    private func loadExistingManager(completion: @escaping (Result<NETunnelProviderManager, Error>) -> Void) {
        if let cachedManager {
            completion(.success(cachedManager))
            return
        }
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let error {
                NSLog("[LanbridgeVPN] loadAllFromPreferences failed: %@", error.localizedDescription)
                completion(.failure(Self.normalize(error)))
                return
            }
            if let manager = managers?.first(where: { current in
                (current.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == self.tunnelBundleID
            }) {
                self.cachedManager = manager
                NSLog(
                    "[LanbridgeVPN] existing manager loaded, enabled=%@ status=%@",
                    manager.isEnabled ? "yes" : "no",
                    Self.statusText(manager.connection.status)
                )
                completion(.success(manager))
                return
            }
            NSLog("[LanbridgeVPN] existing manager not found")
            completion(.failure(DbaoTunnelError.tunnelManagerUnavailable))
        }
    }

    private func loadOrCreateManager(completion: @escaping (Result<NETunnelProviderManager, Error>) -> Void) {
        loadExistingManager { result in
            switch result {
            case let .success(manager):
                self.ensureManagerReady(manager, completion: completion)
            case .failure:
                self.createManager(completion: completion)
            }
        }
    }

    private func ensureManagerReady(
        _ manager: NETunnelProviderManager,
        completion: @escaping (Result<NETunnelProviderManager, Error>) -> Void
    ) {
        var changed = false
        let proto: NETunnelProviderProtocol
        if let existingProto = manager.protocolConfiguration as? NETunnelProviderProtocol {
            proto = existingProto
        } else {
            proto = NETunnelProviderProtocol()
            manager.protocolConfiguration = proto
            changed = true
        }

        if proto.providerBundleIdentifier != tunnelBundleID {
            proto.providerBundleIdentifier = tunnelBundleID
            changed = true
        }
        if proto.includeAllNetworks != true {
            // 真机测试阶段按全量 VPN 处理；国内/国外分流交给 sing-box 规则决定。
            // 只改 libbox 平台接口不够，系统 VPN 配置层也必须声明全量接管。
            proto.includeAllNetworks = true
            changed = true
        }
        if proto.excludeLocalNetworks != false {
            proto.excludeLocalNetworks = false
            changed = true
        }
        if proto.enforceRoutes != true {
            proto.enforceRoutes = true
            changed = true
        }
        if proto.serverAddress?.isEmpty ?? true {
            proto.serverAddress = DbaoTunnelConstants.tunnelDisplayName
            changed = true
        }
        var providerConfiguration = proto.providerConfiguration ?? [:]
        if providerConfiguration["appGroupID"] as? String != appGroupID {
            providerConfiguration["appGroupID"] = appGroupID
            proto.providerConfiguration = providerConfiguration
            changed = true
        }
        if !manager.isEnabled {
            manager.isEnabled = true
            changed = true
        }
        manager.localizedDescription = DbaoTunnelConstants.tunnelDisplayName

        guard changed else {
            completion(.success(manager))
            return
        }

        NSLog("[LanbridgeVPN] existing manager repaired, saving preferences")
        store.appendDebugLog("[App] existing manager repaired, saving preferences")
        manager.saveToPreferences { error in
            if let error {
                NSLog("[LanbridgeVPN] repair saveToPreferences failed: %@", error.localizedDescription)
                completion(.failure(Self.normalize(error)))
                return
            }
            manager.loadFromPreferences { error in
                if let error {
                    NSLog("[LanbridgeVPN] repair loadFromPreferences failed: %@", error.localizedDescription)
                    completion(.failure(Self.normalize(error)))
                } else {
                    self.cachedManager = manager
                    NSLog(
                        "[LanbridgeVPN] existing manager repaired, enabled=%@ status=%@",
                        manager.isEnabled ? "yes" : "no",
                        Self.statusText(manager.connection.status)
                    )
                    completion(.success(manager))
                }
            }
        }
    }

    private func createManager(completion: @escaping (Result<NETunnelProviderManager, Error>) -> Void) {
        NSLog("[LanbridgeVPN] creating NETunnelProviderManager")
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = tunnelBundleID
        proto.serverAddress = DbaoTunnelConstants.tunnelDisplayName
        proto.providerConfiguration = ["appGroupID": appGroupID]
        proto.includeAllNetworks = true
        proto.excludeLocalNetworks = false
        proto.enforceRoutes = true

        let manager = NETunnelProviderManager()
        manager.localizedDescription = DbaoTunnelConstants.tunnelDisplayName
        manager.protocolConfiguration = proto
        manager.isEnabled = true
        manager.isOnDemandEnabled = false
        manager.saveToPreferences { error in
            if let error {
                NSLog("[LanbridgeVPN] saveToPreferences failed: %@", error.localizedDescription)
                completion(.failure(Self.normalize(error)))
                return
            }
            NSLog("[LanbridgeVPN] saveToPreferences succeeded")
            manager.loadFromPreferences { error in
                if let error {
                    NSLog("[LanbridgeVPN] loadFromPreferences after save failed: %@", error.localizedDescription)
                    completion(.failure(Self.normalize(error)))
                } else {
                    self.cachedManager = manager
                    NSLog("[LanbridgeVPN] manager loaded after save")
                    completion(.success(manager))
                }
            }
        }
    }

    /// 按需规则只负责恢复用户已经主动建立的 VPN，不用于首次连接。
    private func setOnDemandEnabled(
        _ enabled: Bool,
        manager: NETunnelProviderManager,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        if enabled {
            let rule = NEOnDemandRuleConnect()
            rule.interfaceTypeMatch = .any
            manager.onDemandRules = [rule]
        } else {
            manager.onDemandRules = []
        }
        manager.isOnDemandEnabled = enabled
        manager.saveToPreferences { error in
            if let error {
                completion(.failure(Self.normalize(error)))
                return
            }
            manager.loadFromPreferences { error in
                if let error {
                    completion(.failure(Self.normalize(error)))
                    return
                }
                self.cachedManager = manager
                self.store.appendDebugLog("[App] on-demand \(enabled ? "enabled" : "disabled")")
                completion(.success(()))
            }
        }
    }

    private static func statusText(_ status: NEVPNStatus) -> String {
        switch status {
        case .invalid:
            return "invalid"
        case .disconnected:
            return "disconnected"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case .reasserting:
            return "reasserting"
        case .disconnecting:
            return "disconnecting"
        @unknown default:
            return "unknown"
        }
    }

    private static func errorCode(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private static func normalize(_ error: Error) -> Error {
        if errorCode(error).lowercased().contains("permission denied") {
            return DbaoTunnelError.vpnPermissionDenied
        }
        return DbaoTunnelError.tunnelStartFailed(error.localizedDescription)
    }

    private static func payloadSummary(_ payload: [String: Any]) -> String {
        let outboundCount = (payload["outbounds"] as? [Any])?.count ?? 0
        let routeRuleCount = ((payload["route"] as? [String: Any])?["rules"] as? [Any])?.count ?? 0
        let keys = payload.keys.sorted().joined(separator: ",")
        return "payload keys=[\(keys)], outbounds=\(outboundCount), routeRules=\(routeRuleCount)"
    }
}
