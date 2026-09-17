import Foundation
import Network
import NetworkExtension

#if canImport(Libbox)
import Libbox

// DbaoSingBoxTunnelEngine 是 iOS 真机调试用的 sing-box 适配器。
// 它只暴露 DbaoTunnelEngine 协议，业务层仍然不知道具体 VPN Core。
final class DbaoSingBoxTunnelEngine: DbaoTunnelEngine {
    private var commandServer: LibboxCommandServer?
    private var platformInterface: DbaoSingBoxPlatformInterface?
    private var trafficMonitor: DbaoTrafficMonitor?
    private var connectivityProbe: DbaoConnectivityProbe?
    private let debugStore = DbaoTunnelStore(appGroupID: DbaoTunnelConstants.placeholderAppGroupID)

    func start(provider: NEPacketTunnelProvider, configContent: String) throws {
        NSLog("[LanbridgeTunnel] sing-box engine start requested, configBytes=%d", configContent.utf8.count)
        debugStore.appendDebugLog("[Engine] sing-box engine start requested, configBytes=\(configContent.utf8.count)")
        let paths = try DbaoSingBoxRuntimePaths(provider: provider)
        NSLog("[LanbridgeTunnel] sing-box runtime paths prepared")
        debugStore.appendDebugLog("[Engine] runtime paths prepared, base=\(paths.base.path)")
        try paths.removeStaleCommandSocket()
        debugStore.appendDebugLog("[Engine] stale command socket removed if present")
        let setupOptions = LibboxSetupOptions()
        setupOptions.basePath = paths.base.path
        setupOptions.workingPath = paths.working.path
        setupOptions.tempPath = paths.temp.path
        setupOptions.logMaxLines = 3000
        setupOptions.debug = true
        setupOptions.crashReportSource = "LanbridgePacketTunnel"
        setupOptions.appVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        setupOptions.appMarketingVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        setupOptions.oomKillerEnabled = true
        setupOptions.powerReportEnabled = false

        var setupError: NSError?
        LibboxSetup(setupOptions, &setupError)
        if let setupError {
            NSLog("[LanbridgeTunnel] LibboxSetup failed: %@", setupError.localizedDescription)
            debugStore.appendDebugLog("[Engine] LibboxSetup failed: \(setupError.localizedDescription)")
            throw DbaoTunnelError.tunnelStartFailed("SING_BOX_SETUP_FAILED: \(setupError.localizedDescription)")
        }
        NSLog("[LanbridgeTunnel] LibboxSetup succeeded")
        debugStore.appendDebugLog("[Engine] LibboxSetup succeeded")

        let platformInterface = DbaoSingBoxPlatformInterface(provider: provider)
        var serverError: NSError?
        guard let commandServer = LibboxNewCommandServer(platformInterface, platformInterface, &serverError) else {
            NSLog("[LanbridgeTunnel] LibboxNewCommandServer failed: %@", serverError?.localizedDescription ?? "unknown")
            debugStore.appendDebugLog("[Engine] LibboxNewCommandServer failed: \(serverError?.localizedDescription ?? "unknown")")
            throw DbaoTunnelError.tunnelStartFailed("SING_BOX_COMMAND_SERVER_FAILED: \(serverError?.localizedDescription ?? "unknown")")
        }

        do {
            NSLog("[LanbridgeTunnel] command server start")
            debugStore.appendDebugLog("[Engine] command server start")
            try commandServer.start()
            NSLog("[LanbridgeTunnel] command server startOrReloadService")
            debugStore.appendDebugLog("[Engine] command server startOrReloadService")
            try commandServer.startOrReloadService(configContent, options: LibboxOverrideOptions())
        } catch {
            NSLog("[LanbridgeTunnel] sing-box service failed: %@", error.localizedDescription)
            debugStore.appendDebugLog("[Engine] sing-box service failed: \(error.localizedDescription)")
            commandServer.close()
            throw DbaoTunnelError.tunnelStartFailed("SING_BOX_SERVICE_FAILED: \(error.localizedDescription)")
        }

        self.commandServer = commandServer
        self.platformInterface = platformInterface
        let trafficMonitor = DbaoTrafficMonitor(debugStore: debugStore)
        trafficMonitor.start()
        self.trafficMonitor = trafficMonitor
        NSLog("[LanbridgeTunnel] sing-box engine start completed")
        debugStore.appendDebugLog("[Engine] sing-box engine start completed")
    }

    func stop() {
        NSLog("[LanbridgeTunnel] sing-box engine stop requested")
        debugStore.appendDebugLog("[Engine] sing-box engine stop requested")
        try? commandServer?.closeService()
        trafficMonitor?.stop()
        connectivityProbe?.cancel()
        commandServer?.close()
        platformInterface?.reset()
        commandServer = nil
        platformInterface = nil
        trafficMonitor = nil
        connectivityProbe = nil
    }

    /// 在 Packet Tunnel 保持运行时替换线路配置，避免每次切换都重建系统 VPN。
    func reload(configContent: String) throws {
        guard let commandServer else {
            throw DbaoTunnelError.tunnelNotConnected
        }
        NSLog("[LanbridgeTunnel] sing-box service reload requested, configBytes=%d", configContent.utf8.count)
        debugStore.appendDebugLog("[Engine] sing-box service reload requested, configBytes=\(configContent.utf8.count)")
        do {
            try commandServer.startOrReloadService(configContent, options: LibboxOverrideOptions())
            NSLog("[LanbridgeTunnel] sing-box service reload completed")
            debugStore.appendDebugLog("[Engine] sing-box service reload completed")
        } catch {
            NSLog("[LanbridgeTunnel] sing-box service reload failed: %@", error.localizedDescription)
            debugStore.appendDebugLog("[Engine] sing-box service reload failed: \(error.localizedDescription)")
            throw DbaoTunnelError.tunnelStartFailed("SING_BOX_RELOAD_FAILED: \(error.localizedDescription)")
        }
    }

    /// iOS 即将休眠时保留 Core 和 TUN，仅记录状态；主动停止会导致锁屏后无法持续联网。
    func sleep() {
        NSLog("[LanbridgeTunnel] sing-box engine entering sleep")
        debugStore.appendDebugLog("[Engine] provider sleep, core retained")
        platformInterface?.sleep()
    }

    /// 唤醒后立即把当前物理网络重新发布给 Core，缩短 Wi-Fi/蜂窝切换后的恢复时间。
    func wake() {
        NSLog("[LanbridgeTunnel] sing-box engine waking")
        debugStore.appendDebugLog("[Engine] provider wake, refreshing network path")
        platformInterface?.wake()
    }

    func trafficSnapshot() -> (upload: UInt64, download: UInt64, available: Bool) {
        trafficMonitor?.snapshot() ?? (0, 0, false)
    }

    func checkConnectivity(url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        NSLog("[LanbridgeTunnel] sing-box connectivity request via proxy outbound, requestedHost=%@", url.host ?? "")
        debugStore.appendDebugLog("[Engine] connectivity urlTest start, requestedHost=\(url.host ?? "")")
        // Standalone urlTest 只负责触发任务，调用成功不代表线路可用。
        // 必须订阅 group history，并等待 proxy 成员产生本轮 delay 结果。
        connectivityProbe?.cancel()
        let probe = DbaoConnectivityProbe(debugStore: debugStore)
        connectivityProbe = probe
        probe.start { [weak self] result in
            self?.connectivityProbe = nil
            switch result {
            case .success:
                NSLog("[LanbridgeTunnel] sing-box connectivity urlTest succeeded")
                self?.debugStore.appendDebugLog("[Engine] connectivity urlTest succeeded")
                completion(.success(()))
            case let .failure(error):
                NSLog("[LanbridgeTunnel] sing-box connectivity urlTest failed: %@", error.localizedDescription)
                self?.debugStore.appendDebugLog("[Engine] connectivity urlTest failed: \(error.localizedDescription)")
                completion(.failure(DbaoTunnelError.tunnelStartFailed("CONNECTIVITY_PROBE_FAILED")))
            }
        }
    }
}

// DbaoSingBoxRuntimePaths 统一准备 App Group 内的 core 工作目录。
// sing-box 会在这些目录里放运行缓存、日志与临时文件，不能写到普通 H5 目录。
private struct DbaoSingBoxRuntimePaths {
    let base: URL
    let working: URL
    let temp: URL

    init(provider: NEPacketTunnelProvider) throws {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: DbaoTunnelConstants.placeholderAppGroupID
        ) else {
            throw DbaoTunnelError.appGroupUnavailable
        }
        // Libbox 会在 basePath 下创建 command.sock。iOS 的 Unix socket 路径长度很短，
        // 所以 basePath 必须尽量短，不能再额外套一层 sing-box 目录。
        base = groupURL
        working = groupURL.appendingPathComponent("Working", isDirectory: true)
        temp = groupURL.appendingPathComponent("Temp", isDirectory: true)
        try FileManager.default.createDirectory(at: working, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }

    func removeStaleCommandSocket() throws {
        let socketURL = base.appendingPathComponent("command.sock")
        if FileManager.default.fileExists(atPath: socketURL.path) {
            try FileManager.default.removeItem(at: socketURL)
        }
    }
}

// DbaoSingBoxPlatformInterface 是 Libbox 与 iOS NetworkExtension 的桥。
// 最核心的职责是 openTun：把 sing-box 解析出来的 TUN 参数转成 NEPacketTunnelNetworkSettings。
private final class DbaoSingBoxPlatformInterface: NSObject, LibboxPlatformInterfaceProtocol, LibboxCommandServerHandlerProtocol {
    private weak var provider: NEPacketTunnelProvider?
    private var networkSettings: NEPacketTunnelNetworkSettings?
    private var monitor: NWPathMonitor?
    private var interfaceListener: LibboxInterfaceUpdateListenerProtocol?
    private var lastNetworkPath = ""
    private let pathMonitorQueue = DispatchQueue(label: "com.ssyoo.huolian.network-path")
    private let debugStore = DbaoTunnelStore(appGroupID: DbaoTunnelConstants.placeholderAppGroupID)

    init(provider: NEPacketTunnelProvider) {
        self.provider = provider
    }

    func reset() {
        networkSettings = nil
        monitor?.cancel()
        monitor = nil
        interfaceListener = nil
        lastNetworkPath = ""
    }

    func sleep() {
        debugStore.appendDebugLog("[Platform] sleep, path monitor retained")
    }

    func wake() {
        guard let monitor, let listener = interfaceListener else {
            debugStore.appendDebugLog("[Platform] wake before path monitor ready")
            return
        }
        debugStore.appendDebugLog("[Platform] wake, publishing current path")
        pathMonitorQueue.async { [weak self] in
            self?.publish(path: monitor.currentPath, to: listener)
        }
    }

    func openTun(_ options: LibboxTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        NSLog("[LanbridgeTunnel] openTun requested")
        debugStore.appendDebugLog("[Platform] openTun requested")
        guard let provider else {
            throw Self.error("Packet tunnel provider is unavailable")
        }
        guard let options else {
            throw Self.error("Libbox did not provide TUN options")
        }
        guard let ret0_ else {
            throw Self.error("Libbox did not provide a TUN file descriptor pointer")
        }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.mtu = NSNumber(value: options.getMTU())

        var dnsCount = 0
        var dnsServers: [String] = []
        if options.getDNSMode()?.value != LibboxDNSModeDisabled {
            dnsServers = try options.getDNSServerAddress().toStringArray()
            dnsCount = dnsServers.count
            if !dnsServers.isEmpty {
                let nextDNSSettings = NEDNSSettings(servers: dnsServers)
                // 空匹配域表示接管所有域名查询。即使 IPv4 已包含默认路由也必须设置，
                // 否则 iOS 仍可能优先使用 Wi-Fi/旁路由 DNS，绕过 sing-box 的 DNS 路由。
                nextDNSSettings.matchDomains = [""]
                nextDNSSettings.matchDomainsNoSearch = true
                settings.dnsSettings = nextDNSSettings
            }
        }

        let ipv4Addresses = options.getInet4Address().toRoutePrefixes()
        var ipv4IncludedCount = 0
        var ipv4ExcludedCount = 0
        var hasIPv4DefaultRoute = false
        if !ipv4Addresses.isEmpty {
            let ipv4Settings = NEIPv4Settings(
                addresses: ipv4Addresses.map(\.address),
                subnetMasks: ipv4Addresses.map(\.mask)
            )
            let included = options.getInet4RouteAddress().toIPv4Routes()
            ipv4IncludedCount = included.count
            let finalIncluded = included.isEmpty ? [NEIPv4Route.default()] : included
            hasIPv4DefaultRoute = finalIncluded.contains(where: Self.isDefaultIPv4Route)
            ipv4Settings.includedRoutes = finalIncluded
            let excluded = options.getInet4RouteExcludeAddress().toIPv4Routes()
            ipv4ExcludedCount = excluded.count
            ipv4Settings.excludedRoutes = excluded
            settings.ipv4Settings = ipv4Settings
        }

        let ipv6Addresses = options.getInet6Address().toRoutePrefixes()
        var ipv6IncludedCount = 0
        var ipv6ExcludedCount = 0
        if !ipv6Addresses.isEmpty {
            let ipv6Settings = NEIPv6Settings(
                addresses: ipv6Addresses.map(\.address),
                networkPrefixLengths: ipv6Addresses.map { NSNumber(value: $0.prefix) }
            )
            let included = options.getInet6RouteAddress().toIPv6Routes()
            ipv6IncludedCount = included.count
            ipv6Settings.includedRoutes = included.isEmpty ? [NEIPv6Route.default()] : included
            let excluded = options.getInet6RouteExcludeAddress().toIPv6Routes()
            ipv6ExcludedCount = excluded.count
            ipv6Settings.excludedRoutes = excluded
            settings.ipv6Settings = ipv6Settings
        }

        if options.isHTTPProxyEnabled() {
            let proxy = NEProxySettings()
            let server = NEProxyServer(address: options.getHTTPProxyServer(), port: Int(options.getHTTPProxyServerPort()))
            proxy.httpServer = server
            proxy.httpsServer = server
            proxy.httpEnabled = true
            proxy.httpsEnabled = true
            proxy.exceptionList = options.getHTTPProxyBypassDomain().toStringArray()
            let matchDomains = options.getHTTPProxyMatchDomain().toStringArray()
            if !matchDomains.isEmpty {
                proxy.matchDomains = matchDomains
            }
            settings.proxySettings = proxy
        }

        networkSettings = settings
        NSLog(
            "[LanbridgeTunnel] applying tunnel settings, mtu=%d dns=%d ipv4Address=%d ipv4Include=%d ipv4Exclude=%d ipv6Address=%d ipv6Include=%d ipv6Exclude=%d httpProxy=%@",
            options.getMTU(),
            dnsCount,
            ipv4Addresses.count,
            ipv4IncludedCount,
            ipv4ExcludedCount,
            ipv6Addresses.count,
            ipv6IncludedCount,
            ipv6ExcludedCount,
            options.isHTTPProxyEnabled() ? "yes" : "no"
        )
        debugStore.appendDebugLog("[Platform] applying tunnel settings, mtu=\(options.getMTU()), dns=\(dnsCount), dnsServers=\(dnsServers.joined(separator: ",")), ipv4Address=\(ipv4Addresses.map(\.address).joined(separator: ",")), ipv4Include=\(ipv4IncludedCount), ipv4Default=\(hasIPv4DefaultRoute), ipv4Exclude=\(ipv4ExcludedCount), ipv6Address=\(ipv6Addresses.map(\.address).joined(separator: ",")), ipv6Include=\(ipv6IncludedCount), ipv6Exclude=\(ipv6ExcludedCount), httpProxy=\(options.isHTTPProxyEnabled())")
        // Hiddify 的常规实现会同步等待 setTunnelNetworkSettings，但 iOS 26.6.1 真机验证表明：
        // 该回调可能要等 openTun 返回后才恢复，形成循环等待并让系统长期停在 connecting。
        // 因此先提交设置，再等待系统暴露 packetFlow fd；这仍然使用系统创建的真实 TUN，
        // 不会提前向主 App 报告 connected。设置错误会写入共享日志并由系统终止扩展。
        Self.applyTunnelSettingsAsync(settings, provider: provider, debugStore: debugStore)
        let tunFD = try Self.waitForTunnelFileDescriptor(provider: provider, debugStore: debugStore)
        ret0_.pointee = tunFD
        NSLog("[LanbridgeTunnel] TUN fd ready=%d", tunFD)
        debugStore.appendDebugLog("[Platform] TUN fd ready=\(tunFD)")
    }

    func underNetworkExtension() -> Bool {
        true
    }

    func includeAllNetworks() -> Bool {
        // 和 NETunnelProviderProtocol.includeAllNetworks 保持一致，避免系统流量绕过隧道。
        true
    }

    func useProcFS() -> Bool {
        false
    }

    func usePlatformAutoDetectControl() -> Bool {
        false
    }

    func autoDetectControl(_ fd: Int32) throws {}

    func usePlatformBridge() -> Bool {
        false
    }

    func createBridge(_ options: LibboxBridgeOptions?) throws -> LibboxBridgeSessionProtocol {
        throw Self.error("Bridge is not supported on iOS test build")
    }

    func usePlatformShell() -> Bool {
        false
    }

    func checkPlatformShell() throws {
        throw Self.error("Platform shell is not supported on iOS")
    }

    func openShellSession(_ user: LibboxPlatformUser?, command: String?, environ: LibboxStringIteratorProtocol?, term: String?, rows: Int32, cols: Int32) throws -> LibboxShellSessionProtocol {
        throw Self.error("Platform shell is not supported on iOS")
    }

    func lookupSFTPServer(_ error: NSErrorPointer) -> String {
        error?.pointee = Self.error("SFTP is not supported on iOS")
        return ""
    }

    func lookupUser(_ username: String?) throws -> LibboxPlatformUser {
        throw Self.error("User lookup is not supported on iOS")
    }

    func readSystemSSHHostKey(_ error: NSErrorPointer) -> String {
        error?.pointee = Self.error("SSH host key is not supported on iOS")
        return ""
    }

    func tailscaleHostname() -> String {
        "iPhone"
    }

    func localDNSTransport() -> LibboxLocalDNSTransportProtocol? {
        nil
    }

    func clearDNSCache() {
        NSLog("[LanbridgeTunnel] clearDNSCache requested")
        guard let provider, let networkSettings else {
            return
        }
        // 这个回调可能来自 libbox 内部线程，不应该同步等待 NetworkExtension。
        // DNS 设置刷新异步执行即可，失败只写日志，不阻塞核心的数据面线程。
        Task.detached(priority: .utility) {
            provider.reasserting = true
            defer { provider.reasserting = false }
            do {
                try await provider.setTunnelNetworkSettings(nil)
                try await provider.setTunnelNetworkSettings(networkSettings)
            } catch {
                NSLog("[LanbridgeTunnel] clearDNSCache failed: %@", error.localizedDescription)
            }
        }
    }

    func readWIFIState() -> LibboxWIFIState? {
        nil
    }

    func registerMyInterface(_ name: String?) {}

    func startDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
        NSLog("[LanbridgeTunnel] default interface monitor start")
        guard let listener else {
            return
        }
        interfaceListener = listener
        let monitor = NWPathMonitor()
        self.monitor = monitor
        let semaphore = DispatchSemaphore(value: 0)
        monitor.pathUpdateHandler = { [weak self] path in
            self?.publish(path: path, to: listener)
            semaphore.signal()
        }
        monitor.start(queue: pathMonitorQueue)
        if semaphore.wait(timeout: .now() + 2) == .timedOut {
            // 弱网或无网环境下首次 NWPath 回调可能延迟。不能让 Core 初始化永久阻塞；
            // 后续 pathUpdateHandler 仍会把网络恢复事件正常发布给 sing-box。
            debugStore.appendDebugLog("[Platform] initial network path timed out; monitor remains active")
            publish(path: monitor.currentPath, to: listener)
        }
    }

    func closeDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
        NSLog("[LanbridgeTunnel] default interface monitor close")
        monitor?.cancel()
        monitor = nil
        interfaceListener = nil
        lastNetworkPath = ""
    }

    func getInterfaces() throws -> LibboxNetworkInterfaceIteratorProtocol {
        let interfaces: [LibboxNetworkInterface] = monitor?.currentPath.availableInterfaces.map { nwInterface in
            let item = LibboxNetworkInterface()
            item.name = nwInterface.name
            item.index = Int32(nwInterface.index)
            item.type = Self.libboxInterfaceType(from: nwInterface.type)
            return item
        } ?? []
        NSLog("[LanbridgeTunnel] getInterfaces count=%d", interfaces.count)
        return DbaoLibboxNetworkInterfaceIterator(interfaces)
    }

    func startNeighborMonitor(_ listener: LibboxNeighborUpdateListenerProtocol?) throws {}

    func closeNeighborMonitor(_ listener: LibboxNeighborUpdateListenerProtocol?) throws {}

    func findConnectionOwner(_ ipProtocol: Int32, sourceAddress: String?, sourcePort: Int32, destinationAddress: String?, destinationPort: Int32) throws -> LibboxConnectionOwner {
        throw Self.error("Connection owner lookup is not supported on iOS")
    }

    func send(_ notification: LibboxNotification?) throws {}

    func cancelNotification(_ identifier: String?, typeID: Int32) throws {}

    func connectSSHAgent(_ ret0_: UnsafeMutablePointer<Int32>?) throws {
        throw Self.error("SSH agent is not supported on iOS")
    }

    func getSystemProxyStatus() throws -> LibboxSystemProxyStatus {
        LibboxSystemProxyStatus()
    }

    func setSystemProxyEnabled(_ enabled: Bool) throws {}

    func serviceReload() throws {
        throw Self.error("Service reload is not wired in the iOS test bridge")
    }

    func serviceStop() throws {
        NSLog("[LanbridgeTunnel] serviceStop requested by command server")
        debugStore.appendDebugLog("[Platform] serviceStop requested by command server")
        provider?.cancelTunnelWithError(nil)
    }

    func triggerNativeCrash() throws {
        fatalError("Lanbridge native crash test")
    }

    func writeDebugMessage(_ message: String?) {
        guard let message else {
            return
        }
        NSLog("[LanbridgeTunnel] %@", message)
        debugStore.appendDebugLog("[Libbox] \(message)")
    }

    private func publish(path: Network.NWPath, to listener: LibboxInterfaceUpdateListenerProtocol) {
        let description = "\(path.status) interfaces=\(path.availableInterfaces.map(\.name).joined(separator: ","))"
        if description != lastNetworkPath {
            lastNetworkPath = description
            debugStore.appendDebugLog("[Platform] network path changed: \(description), expensive=\(path.isExpensive), constrained=\(path.isConstrained)")
        }
        guard path.status == .satisfied, let interface = Self.physicalInterface(for: path) else {
            provider?.reasserting = true
            listener.updateDefaultInterface("", interfaceIndex: -1, isExpensive: false, isConstrained: false)
            return
        }
        provider?.reasserting = false
        listener.updateDefaultInterface(interface.name, interfaceIndex: Int32(interface.index), isExpensive: path.isExpensive, isConstrained: path.isConstrained)
    }

    /// 只向 Core 发布真实上游接口，避免把 utun/other 重新选作自己的出口形成路由环。
    private static func physicalInterface(for path: Network.NWPath) -> NWInterface? {
        let preferredTypes: [NWInterface.InterfaceType] = [.wifi, .cellular, .wiredEthernet]
        for type in preferredTypes where path.usesInterfaceType(type) {
            if let interface = path.availableInterfaces.first(where: { $0.type == type }) {
                return interface
            }
        }
        return path.availableInterfaces.first(where: { $0.type != .other && $0.type != .loopback })
    }

    private static func libboxInterfaceType(from type: NWInterface.InterfaceType) -> Int32 {
        switch type {
        case .wifi:
            return LibboxInterfaceTypeWIFI
        case .cellular:
            return LibboxInterfaceTypeCellular
        case .wiredEthernet:
            return LibboxInterfaceTypeEthernet
        default:
            return LibboxInterfaceTypeOther
        }
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "DbaoSingBoxPlatformInterface", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func isDefaultIPv4Route(_ route: NEIPv4Route) -> Bool {
        route.destinationAddress == "0.0.0.0" && route.destinationSubnetMask == "0.0.0.0"
    }

    private static func applyTunnelSettingsAsync(
        _ settings: NEPacketTunnelNetworkSettings,
        provider: NEPacketTunnelProvider,
        debugStore: DbaoTunnelStore
    ) {
        debugStore.appendDebugLog("[Platform] setTunnelNetworkSettings submitted")
        provider.setTunnelNetworkSettings(settings) { error in
            if let error {
                debugStore.appendDebugLog("[Platform] setTunnelNetworkSettings failed: \(error.localizedDescription)")
                NSLog("[LanbridgeTunnel] setTunnelNetworkSettings failed: %@", error.localizedDescription)
            } else {
                debugStore.appendDebugLog("[Platform] setTunnelNetworkSettings completed")
                NSLog("[LanbridgeTunnel] setTunnelNetworkSettings completed")
            }
        }
    }

    private static func waitForTunnelFileDescriptor(
        provider: NEPacketTunnelProvider,
        debugStore: DbaoTunnelStore
    ) throws -> Int32 {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if let tunFD = provider.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32, tunFD >= 0 {
                debugStore.appendDebugLog("[Platform] TUN fd from packetFlow=\(tunFD)")
                return tunFD
            }
            let libboxFD = LibboxGetTunnelFileDescriptor()
            if libboxFD >= 0 {
                debugStore.appendDebugLog("[Platform] TUN fd from libbox=\(libboxFD)")
                return libboxFD
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw Self.error("系统 TUN 文件描述符 3 秒内未创建")
    }

}

/// DbaoConnectivityProbe 触发 Libbox URLTest，并等待 group history 返回本轮 proxy 结果。
/// URLTest 调用本身只代表任务已提交，不能直接当作线路可用。
private final class DbaoConnectivityProbe: NSObject, LibboxCommandClientHandlerProtocol {
    private let lock = NSLock()
    private let debugStore: DbaoTunnelStore
    private var client: LibboxCommandClient?
    private var completion: ((Result<Void, Error>) -> Void)?
    private var timeout: DispatchWorkItem?
    private var triggeredAt: Int64 = 0
    private var triggered = false
    private var finished = false

    init(debugStore: DbaoTunnelStore) {
        self.debugStore = debugStore
    }

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        lock.lock()
        self.completion = completion
        lock.unlock()

        let options = LibboxCommandClientOptions()
        options.addCommand(LibboxCommandGroup)
        guard let client = LibboxNewCommandClient(self, options) else {
            finish(.failure(Self.error("group command client unavailable")))
            return
        }
        self.client = client

        let timeout = DispatchWorkItem { [weak self] in
            self?.finish(.failure(Self.error("URL test timed out")))
        }
        self.timeout = timeout
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 8, execute: timeout)

        do {
            try client.connect()
            debugStore.appendDebugLog("[Probe] group command client started")
        } catch {
            finish(.failure(error))
        }
    }

    func cancel() {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        completion = nil
        let client = self.client
        self.client = nil
        let timeout = self.timeout
        self.timeout = nil
        lock.unlock()
        timeout?.cancel()
        DispatchQueue.global(qos: .utility).async {
            try? client?.disconnect()
        }
    }

    func connected() {
        lock.lock()
        guard !finished, !triggered else {
            lock.unlock()
            return
        }
        triggered = true
        triggeredAt = Int64(Date().timeIntervalSince1970)
        lock.unlock()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                guard let command = LibboxNewStandaloneCommandClient() else {
                    throw Self.error("standalone command client unavailable")
                }
                try command.urlTest(DbaoSingBoxConfigBuilder.connectivityProbeGroupTag)
                self.debugStore.appendDebugLog("[Probe] URL test triggered")
            } catch {
                self.finish(.failure(error))
            }
        }
    }

    func writeGroups(_ message: LibboxOutboundGroupIteratorProtocol?) {
        lock.lock()
        let minimumTime = triggeredAt
        let shouldRead = triggered && !finished
        lock.unlock()
        guard shouldRead, minimumTime > 0, let message else { return }

        while message.hasNext() {
            guard let group = message.next(),
                  group.tag == DbaoSingBoxConfigBuilder.connectivityProbeGroupTag,
                  let items = group.getItems() else { continue }
            while items.hasNext() {
                guard let item = items.next(), item.tag == "proxy",
                      item.urlTestTime >= minimumTime else { continue }
                let delay = item.urlTestDelay
                debugStore.appendDebugLog("[Probe] proxy result, delay=\(delay)")
                if delay > 0 && delay < 65_535 {
                    finish(.success(()))
                } else {
                    finish(.failure(Self.error("proxy URL test failed")))
                }
                return
            }
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let completion = self.completion
        self.completion = nil
        let client = self.client
        self.client = nil
        let timeout = self.timeout
        self.timeout = nil
        lock.unlock()

        timeout?.cancel()
        DispatchQueue.global(qos: .utility).async {
            try? client?.disconnect()
        }
        completion?(result)
    }

    private static func error(_ message: String) -> NSError {
        NSError(
            domain: "FireLinkConnectivityProbe",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    func disconnected(_ message: String?) {
        lock.lock()
        let shouldFail = !finished
        lock.unlock()
        if shouldFail {
            finish(.failure(Self.error(message ?? "group command client disconnected")))
        }
    }

    func clearLogs() {}
    func initializeClashMode(_ modeList: LibboxStringIteratorProtocol?, currentMode: String?) {}
    func setDefaultLogLevel(_ level: Int32) {}
    func updateClashMode(_ newMode: String?) {}
    func write(_ events: LibboxConnectionEvents?) {}
    func writeLogs(_ messageList: LibboxLogIteratorProtocol?) {}
    func writeOutbounds(_ message: LibboxOutboundGroupItemIteratorProtocol?) {}
    func writeStatus(_ message: LibboxStatusMessage?) {}
}

/// DbaoTrafficMonitor 订阅 libbox command server 的真实累计流量。
/// 未收到首个 status 消息前 available=false，前端显示占位符而不是伪造 0 B。
private final class DbaoTrafficMonitor: NSObject, LibboxCommandClientHandlerProtocol {
    private let lock = NSLock()
    private let debugStore: DbaoTunnelStore
    private var client: LibboxCommandClient?
    private var upload: UInt64 = 0
    private var download: UInt64 = 0
    private var available = false

    init(debugStore: DbaoTunnelStore) {
        self.debugStore = debugStore
    }

    func start() {
        let options = LibboxCommandClientOptions()
        options.addCommand(LibboxCommandStatus)
        options.statusInterval = Int64(NSEC_PER_SEC)
        guard let client = LibboxNewCommandClient(self, options) else {
            debugStore.appendDebugLog("[Traffic] command client unavailable")
            return
        }
        do {
            try client.connect()
            self.client = client
            debugStore.appendDebugLog("[Traffic] command client started")
        } catch {
            debugStore.appendDebugLog("[Traffic] command client failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        try? client?.disconnect()
        client = nil
    }

    func snapshot() -> (upload: UInt64, download: UInt64, available: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (upload, download, available)
    }

    func connected() {}
    func disconnected(_ message: String?) {}
    func clearLogs() {}
    func initializeClashMode(_ modeList: LibboxStringIteratorProtocol?, currentMode: String?) {}
    func setDefaultLogLevel(_ level: Int32) {}
    func updateClashMode(_ newMode: String?) {}
    func write(_ events: LibboxConnectionEvents?) {}
    func writeGroups(_ message: LibboxOutboundGroupIteratorProtocol?) {}
    func writeLogs(_ messageList: LibboxLogIteratorProtocol?) {}
    func writeOutbounds(_ message: LibboxOutboundGroupItemIteratorProtocol?) {}

    func writeStatus(_ message: LibboxStatusMessage?) {
        guard let message else { return }
        lock.lock()
        upload = UInt64(max(message.uplinkTotal, 0))
        download = UInt64(max(message.downlinkTotal, 0))
        available = message.trafficAvailable
        lock.unlock()
    }
}

private struct DbaoRoutePrefix {
    let address: String
    let mask: String
    let prefix: Int32
}

private final class DbaoLibboxNetworkInterfaceIterator: NSObject, LibboxNetworkInterfaceIteratorProtocol {
    private let items: [LibboxNetworkInterface]
    private var index = 0
    private var current: LibboxNetworkInterface?

    init(_ items: [LibboxNetworkInterface]) {
        self.items = items
    }

    func hasNext() -> Bool {
        guard index < items.count else {
            current = nil
            return false
        }
        current = items[index]
        index += 1
        return true
    }

    func next() -> LibboxNetworkInterface? {
        current
    }
}

private extension LibboxStringIteratorProtocol {
    func toStringArray() -> [String] {
        var values: [String] = []
        while hasNext() {
            values.append(next())
        }
        return values
    }
}

private extension LibboxStringIteratorProtocol? {
    func toStringArray() -> [String] {
        guard let iterator = self else {
            return []
        }
        return iterator.toStringArray()
    }
}

private extension LibboxRoutePrefixIteratorProtocol? {
    func toRoutePrefixes() -> [DbaoRoutePrefix] {
        guard let iterator = self else {
            return []
        }
        var values: [DbaoRoutePrefix] = []
        while iterator.hasNext(), let item = iterator.next() {
            values.append(DbaoRoutePrefix(address: item.address(), mask: item.mask(), prefix: item.prefix()))
        }
        return values
    }

    func toIPv4Routes() -> [NEIPv4Route] {
        toRoutePrefixes().map { NEIPv4Route(destinationAddress: $0.address, subnetMask: $0.mask) }
    }

    func toIPv6Routes() -> [NEIPv6Route] {
        toRoutePrefixes().map { NEIPv6Route(destinationAddress: $0.address, networkPrefixLength: NSNumber(value: $0.prefix)) }
    }
}
#endif
