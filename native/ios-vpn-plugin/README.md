# 启连加速器 iOS VPN 原生层

更新时间：2026-09-16

该目录提供启连加速器 iOS 主 App 与 Packet Tunnel Extension 共用的原生 VPN 实现。Flutter 入口位于 `apps/mobile-flutter`，iOS 宿主位于 `apps/ios-app`。

## 模块

| 模块 | 文件 | 作用 |
| --- | --- | --- |
| 主 App 管理 | `Sources/App/DbaoPacketTunnelManager.swift` | 创建、修复和启动 `NETunnelProviderManager` |
| 配置共享 | `Sources/Shared/DbaoTunnelStore.swift` | 通过 App Group 共享配置、状态和日志 |
| 配置生成 | `Sources/Shared/DbaoSingBoxConfigBuilder.swift` | 把 Go 返回的配置补成 iOS TUN 配置 |
| Packet Tunnel | `Sources/Extension/PacketTunnelProvider.swift` | Network Extension 入口 |
| Core 接口 | `Sources/Extension/DbaoTunnelEngine.swift` | 隔离具体 VPN Core |
| sing-box 适配 | `Sources/Extension/DbaoSingBoxTunnelEngine.swift` | 使用 Libbox 执行协议、DNS 和 TUN |

`DbaoVpnWebBridge.swift` 与 `DbaoUniPluginBridge.swift.template` 仅为旧 H5/uni-app 原型保留，不参与当前 iOS target。

## Flutter 调用协议

当前宿主通过 `apps/ios-app/Lanbridge/FireLinkVpnPlugin.swift` 注册 MethodChannel，动作固定为：

```text
prepare
connect
disconnect
getStatus
getTrafficStats
checkConnectivity
openConnectionLog
```

这些动作不暴露 Libbox 类型。更换 Core 时保持 `DbaoTunnelEngine` 与 MethodChannel 契约不变。

## Apple 标识

```text
Team ID: 8VHFT94C93
主 App: com.ssyoo.vpn
Packet Tunnel: com.ssyoo.vpn.network-extension
App Group: group.com.ssyoo.vpn
```

主 App 和 Extension 都必须签入 `packet-tunnel-provider`，并使用同一个 App Group。

## Core 状态

当前真机 target 已链接：

```text
third_party/sing-box/Libbox.xcframework
```

`PacketTunnelProvider.makeEngine()` 当前返回真实的 `DbaoSingBoxTunnelEngine`。Core 负责 TUN、DNS、协议连接、流量统计和出口探测，不能用模拟成功替代。

## 构建

```bash
./apps/ios-app/scripts/setup-flutter.sh
./apps/ios-app/scripts/run-on-device.sh
```

不要单独使用 Swift Package 构建判断真机可用性；必须由包含主 App、Extension、Entitlements 和 Libbox 的 Xcode workspace 验证。

## 许可证

当前 sing-box/Libbox 用于验证产品和协议稳定性。正式分发前必须完成 GPLv3 审查：选择履行对应源码义务，或换成允许公司闭源分发的 Core。原生适配层已经为替换 Core 保留边界。
