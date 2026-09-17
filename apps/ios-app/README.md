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

在 Xcode 中选择 `Lanbridge` Scheme 和已加入开发者账号的 iPhone 后运行。
首次连接时，iOS 会要求用户授权添加系统 VPN 配置。

## Apple 标识示例

```text
Team ID: 8VHFT94C93
主 App Bundle ID: com.ssyoo.vpn
Tunnel Bundle ID: com.ssyoo.vpn.network-extension
App Group ID: group.com.ssyoo.vpn
```

发布自己的构建时，请替换上述标识。主 App 与 Extension 都必须启用
`Network Extensions / Packet Tunnel`，并关联同一个 App Group。

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
