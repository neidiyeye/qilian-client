import Foundation
import NetworkExtension

// 这是 sing-box iOS Core 接入示例，不参与默认编译。
// 真正接入时需要把 sing-box/libbox iOS Framework 加入 Extension Target，
// 并实现 DbaoTunnelEngine.start/stop/trafficSnapshot。
//
// 重要：sing-box 是 GPLv3。闭源商业 App 上架前，必须确认许可证方案，
// 或替换为可闭源分发的 VPN Core。
/*
import Libbox

final class SingBoxTunnelEngine: DbaoTunnelEngine {
    func start(provider: NEPacketTunnelProvider, configContent: String) throws {
        // 参考 sing-box for Apple 的思路：
        // 1. LibboxSetup(...)
        // 2. 创建 platform interface，把 NEPacketTunnelProvider.packetFlow 交给核心
        // 3. commandServer.startOrReloadService(configContent, options: ...)
    }

    func reload(configContent: String) throws {
        // 保持 Packet Tunnel 在线，通过 Core 自己的 reload API 替换线路配置。
    }

    func sleep() {}

    func wake() {}

    func stop() {
        // 关闭 command server/service，释放 TUN。
    }

    func trafficSnapshot() -> (upload: UInt64, download: UInt64, available: Bool) {
        // 从核心状态接口读取真实累计上下行。
        (0, 0, false)
    }
}
*/
