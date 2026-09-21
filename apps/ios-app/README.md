# 启连加速器 iOS App

更新时间：2026-09-16

该目录是启连加速器的 iOS 原生宿主。界面由 `apps/mobile-flutter` 提供，系统 VPN 能力由 Swift、`NetworkExtension` 和 Packet Tunnel Extension 提供。

## 当前结构

```text
Flutter UI
  -> MethodChannel: com.ssyoo.huolian/vpn
  -> FireLinkVpnPlugin
  -> DbaoPacketTunnelManager
  -> NETunnelProviderManager
  -> PacketTunnelProvider
  -> DbaoTunnelEngine
  -> sing-box Libbox
```

Flutter 只使用 `prepare`、`connect`、`disconnect`、`getStatus`、`getTrafficStats`、`checkConnectivity` 和 `openConnectionLog`。sing-box 的配置补全、生命周期和 TUN 操作都留在原生层，后续替换 Core 不需要改页面或业务状态机。

## 首次准备

```bash
./apps/ios-app/scripts/setup-flutter.sh
```

该脚本会依次执行 Flutter 依赖安装、XcodeGen 和 CocoaPods。之后必须打开 workspace：

```bash
open apps/ios-app/LanbridgeIOS.xcworkspace
```

不要直接使用 `LanbridgeIOS.xcodeproj`，否则 Flutter Pods 不会参与链接。

## 真机安装

```bash
./apps/ios-app/scripts/run-on-device.sh
```

脚本固定使用 iPhone SE：

```text
UDID: 00008030-000E40EC1183802E
```

iPhone 15 Pro Max 已被脚本排除，除非用户明确要求，否则不能用于测试。Ad Hoc 测试包使用：

脚本构建 `Profile` 包，因为 Flutter `Debug` 包不能脱离 Flutter tooling 或 Xcode 独立启动；Profile 仍保留原生 VPN 的 `NSLog` 调试日志。

```bash
./apps/ios-app/scripts/run-ad-hoc-on-device.sh
```

## Apple 标识

```text
Team ID: 8VHFT94C93
主 App Bundle ID: com.ssyoo.vpn
Tunnel Bundle ID: com.ssyoo.vpn.network-extension
App Group ID: group.com.ssyoo.vpn
```

主 App 与 Extension 都必须启用 `Network Extensions / Packet Tunnel`，并关联同一个 App Group。第一次连接时 iOS 会显示系统 VPN 授权弹窗。

## 验证

```bash
cd apps/mobile-flutter
flutter analyze
flutter test

cd ../ios-app
xcodebuild \
  -workspace LanbridgeIOS.xcworkspace \
  -scheme Lanbridge \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  build
```

开发环境可通过 Dart Define 切换 API：

```bash
flutter build ios --dart-define=API_BASE_URL=https://client-api.qljsp.com
```

客户端上网流量不会经过该 Go API。
