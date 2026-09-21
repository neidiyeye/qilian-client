import Foundation

// DbaoSingBoxConfigBuilder 把后端返回的 outbound_route 片段补成 iOS TUN 运行配置。
// 后端只负责分配节点与路由策略；iOS 端必须注入 tun inbound、DNS 与本地缓存路径。
public enum DbaoSingBoxConfigBuilder {
    /// Libbox URLTest 只接受 OutboundGroup，不能直接测试普通的 proxy 出站。
    public static let connectivityProbeGroupTag = "firelink-connectivity-probe"

    public static func build(from payload: [String: Any], cachePath: String) throws -> String {
        guard let outbounds = payload["outbounds"] as? [Any], !outbounds.isEmpty,
              let route = payload["route"] as? [String: Any], !route.isEmpty else {
            throw DbaoTunnelError.invalidPayload
        }
        let options = ClientOptions(payload["client_options"] as? [String: Any])

        var outboundsWithProbeGroup = outbounds
        outboundsWithProbeGroup.insert([
            "type": "selector",
            "tag": connectivityProbeGroupTag,
            // Group 至少需要两个成员才会出现在 Libbox group history 回调中。
            // 检测结果只读取 proxy；direct 仅用于让 Core 暴露该检测组。
            "outbounds": ["proxy", "direct"],
            "default": "proxy",
        ], at: 0)

        var routeWithResolver = route
        routeWithResolver["default_domain_resolver"] = routeWithResolver["default_domain_resolver"] ?? "bootstrap-dns"
        routeWithResolver["rules"] = prependTunnelRouteActions(
            to: removingLegacyQUICReject(from: routeWithResolver["rules"]),
            enableSniff: options.enableSniff
        )
        routeWithResolver["rule_set"] = ruleSetsWithDownloadDetour(routeWithResolver["rule_set"])

        var tunAddresses = ["172.19.0.1/30"]
        if options.enableIPv6 {
            tunAddresses.append("fdfe:dcba:9876::1/126")
        }

        let complete: [String: Any] = [
            "log": ["level": logLevel],
            "dns": [
                "servers": [
                    [
                        // 节点服务器域名必须在代理建立前解析，因此使用直连 DoH 引导 DNS。
                        // 使用固定 IP 和 SNI，既不依赖本地 UDP 53，也不受旁路由 Fake-IP 影响。
                        "type": "https",
                        "tag": "bootstrap-dns",
                        "server": options.bootstrapDNSServer,
                        "server_port": 443,
                        "path": "/dns-query",
                        "tls": ["server_name": options.bootstrapDNSTLSName],
                    ],
                    [
                        // 用户域名通过当前代理查询公共 DNS，避免本地网络污染和地域解析漂移。
                        // TCP DNS 不依赖 QUIC/UDP relay，兼容 Hysteria2、VMess、VLESS 等出站。
                        "type": "tcp",
                        "tag": "remote-dns",
                        "server": options.remoteDNSServer,
                        "detour": "proxy",
                    ],
                ],
                "rules": dnsRules(for: routeWithResolver),
                "final": "remote-dns",
                "strategy": options.dnsStrategy,
                "timeout": "6s",
            ],
            "inbounds": [[
                "type": "tun",
                "tag": "tun-in",
                "address": tunAddresses,
                // 使用保守 MTU，避免默认 4064 在不同 iOS/网络环境下影响 utun 初始化。
                "mtu": 1500,
                "auto_route": true,
                "strict_route": true,
            ]],
            "outbounds": outboundsWithProbeGroup,
            "route": routeWithResolver,
            "experimental": ["cache_file": [
                "enabled": true,
                "path": cachePath,
            ]],
        ]
        return try DbaoJSON.string(from: complete)
    }

    private struct ClientOptions {
        let bootstrapDNSServer: String
        let bootstrapDNSTLSName: String
        let remoteDNSServer: String
        let dnsStrategy: String
        let enableIPv6: Bool
        let enableSniff: Bool

        init(_ raw: [String: Any]?) {
            let values = raw ?? [:]
            bootstrapDNSServer = Self.safeHost(values["bootstrap_dns_server"], fallback: "223.5.5.5")
            bootstrapDNSTLSName = Self.safeHost(values["bootstrap_dns_tls_name"], fallback: "dns.alidns.com")
            remoteDNSServer = Self.safeHost(values["remote_dns_server"], fallback: "8.8.8.8")
            enableIPv6 = values["enable_ipv6"] as? Bool ?? false
            enableSniff = values["enable_sniff"] as? Bool ?? true

            let requestedStrategy = values["dns_strategy"] as? String ?? "ipv4_only"
            let allowedStrategies = ["prefer_ipv4", "prefer_ipv6", "ipv4_only", "ipv6_only", "as_is"]
            if allowedStrategies.contains(requestedStrategy), enableIPv6 || requestedStrategy != "ipv6_only" {
                dnsStrategy = requestedStrategy
            } else {
                dnsStrategy = "ipv4_only"
            }
        }

        private static func safeHost(_ value: Any?, fallback: String) -> String {
            guard let candidate = value as? String else { return fallback }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  trimmed.count <= 253,
                  !trimmed.contains("/"),
                  trimmed.unicodeScalars.allSatisfy({
                      !CharacterSet.controlCharacters.contains($0)
                  }) else {
                return fallback
            }
            return trimmed
        }
    }

    private static var logLevel: String {
#if DEBUG
        return "info"
#else
        // App Store 构建不记录用户访问目标，只保留核心错误。
        return "error"
#endif
    }

    private static func dnsRules(for route: [String: Any]) -> [[String: Any]] {
        guard let ruleSets = route["rule_set"] as? [[String: Any]],
              ruleSets.contains(where: { ($0["tag"] as? String) == "geosite-cn" }) else {
            return []
        }
        // 规则模式下国内域名使用本地 DNS，获得适合直连的国内 CDN 地址；其余域名仍通过代理 DNS。
        return [[
            "rule_set": ["geosite-cn"],
            "action": "route",
            "server": "bootstrap-dns",
        ]]
    }

    private static func removingLegacyQUICReject(from rawRules: Any?) -> [[String: Any]] {
        let rules = rawRules as? [[String: Any]] ?? []
        return rules.filter { rule in
            // 兼容已经部署但尚未升级的服务端。旧版本曾为 Safari 回落 TCP 而拒绝全部
            // UDP 443，实际会让部分 iOS 版本直接报 no route to host。
            let network = rule["network"] as? String
            let port = (rule["port"] as? NSNumber)?.intValue ?? rule["port"] as? Int
            let action = rule["action"] as? String
            return !(network == "udp" && port == 443 && action == "reject")
        }
    }

    private static func prependTunnelRouteActions(to rawRules: Any?, enableSniff: Bool) -> [[String: Any]] {
        var rules = rawRules as? [[String: Any]] ?? []
        // iOS 会把系统 DNS 指向 TUN 内部地址。必须由 sing-box 显式接管这些 DNS 包，
        // 否则查询可能继续落到 Wi-Fi/旁路由 DNS，Google 等域名会受到 Fake-IP 或污染影响。
        rules.insert([
            "protocol": "dns",
            "action": "hijack-dns",
        ], at: 0)
        if enableSniff {
            // sing-box 1.13+ 移除了 inbound 上的 sniff 等旧字段。
            // 嗅探必须先于 DNS 劫持和后端分流规则执行，才能让后续规则获得真实域名。
            rules.insert([
                "inbound": "tun-in",
                "action": "sniff",
                "timeout": "1s",
            ], at: 0)
        }
        return rules
    }

    private static func ruleSetsWithDownloadDetour(_ rawRuleSets: Any?) -> Any? {
        guard var ruleSets = rawRuleSets as? [[String: Any]] else {
            return rawRuleSets
        }
        for index in ruleSets.indices where (ruleSets[index]["type"] as? String) == "remote" {
            // iOS 首次建隧道时直连 GitHub 拉规则集容易阻塞启动。
            // 当前 core 仍支持 download_detour，后续固定新 core 后再迁到 http_client。
            ruleSets[index]["download_detour"] = ruleSets[index]["download_detour"] ?? "proxy"
        }
        return ruleSets
    }
}
