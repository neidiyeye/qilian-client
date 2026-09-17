import Foundation
import XCTest
@testable import DbaoIOSVPNPlugin

final class DbaoSingBoxConfigBuilderTests: XCTestCase {
    func testBuildsSplitDNSAndRemovesLegacyQUICReject() throws {
        let payload: [String: Any] = [
            "outbounds": [
                [
                    "type": "shadowsocks",
                    "tag": "proxy",
                    "server": "example.com",
                    "server_port": 443,
                    "method": "aes-128-gcm",
                    "password": "test-password",
                    "domain_resolver": ["server": "bootstrap-dns", "strategy": "prefer_ipv4"],
                ],
                ["type": "direct", "tag": "direct"],
            ],
            "route": [
                "final": "proxy",
                "auto_detect_interface": true,
                "rule_set": [
                    [
                        "type": "remote",
                        "tag": "geosite-cn",
                        "format": "binary",
                        "url": "https://example.com/geosite-cn.srs",
                    ],
                ],
                "rules": [
                    ["network": "udp", "port": 443, "action": "reject"],
                    ["ip_is_private": true, "action": "route", "outbound": "direct"],
                ],
            ],
        ]

        let content = try DbaoSingBoxConfigBuilder.build(from: payload, cachePath: "/tmp/lanbridge-test-cache.db")
        let data = try XCTUnwrap(content.data(using: .utf8))
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let dns = try XCTUnwrap(config["dns"] as? [String: Any])
        let servers = try XCTUnwrap(dns["servers"] as? [[String: Any]])
        XCTAssertEqual(servers.count, 2)
        XCTAssertEqual(servers[0]["tag"] as? String, "bootstrap-dns")
        XCTAssertEqual(servers[0]["type"] as? String, "https")
        XCTAssertNil(servers[0]["detour"])
        XCTAssertEqual(servers[1]["tag"] as? String, "remote-dns")
        XCTAssertEqual(servers[1]["detour"] as? String, "proxy")
        XCTAssertEqual(dns["final"] as? String, "remote-dns")

        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])
        let probeGroup = try XCTUnwrap(outbounds.first)
        XCTAssertEqual(probeGroup["type"] as? String, "selector")
        XCTAssertEqual(probeGroup["tag"] as? String, DbaoSingBoxConfigBuilder.connectivityProbeGroupTag)
        XCTAssertEqual(probeGroup["outbounds"] as? [String], ["proxy", "direct"])

        let dnsRules = try XCTUnwrap(dns["rules"] as? [[String: Any]])
        XCTAssertEqual(dnsRules.first?["server"] as? String, "bootstrap-dns")

        let route = try XCTUnwrap(config["route"] as? [String: Any])
        let routeRules = try XCTUnwrap(route["rules"] as? [[String: Any]])
        XCTAssertFalse(routeRules.contains(where: {
            ($0["network"] as? String) == "udp" && ($0["port"] as? Int) == 443 && ($0["action"] as? String) == "reject"
        }))
        XCTAssertEqual(routeRules.first?["action"] as? String, "sniff")
        XCTAssertEqual(routeRules.dropFirst().first?["action"] as? String, "hijack-dns")

        try checkWithSingBoxIfConfigured(content)
    }

    private func checkWithSingBoxIfConfigured(_ content: String) throws {
        guard let binary = ProcessInfo.processInfo.environment["SING_BOX_BIN"], !binary.isEmpty else {
            return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("config.json")
        try content.write(to: configURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["check", "-c", configURL.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let details = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, details)
    }
}
