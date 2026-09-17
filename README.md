# 启连加速器客户端

这是启连加速器的公开客户端源码，包含 Flutter 界面、iOS 原生宿主、
Network Extension Packet Tunnel 以及 sing-box Libbox 适配层。

该仓库对应 iOS `1.0 (3)`。服务端账号、订阅管理、逻辑节点调度、
机场凭据和运营后台不在本仓库中，也不会被打包进客户端。

## 目录

```text
apps/mobile-flutter     Flutter 用户界面和业务状态
apps/ios-app            iOS 主 App、签名配置模板和 XcodeGen 工程
native/ios-vpn-plugin   Network Extension 与 VPN Core 适配层
scripts                 第三方核心的可复现构建脚本
third_party/sing-box    本地构建产物目录（产物不提交）
```

## 构建环境

- macOS 与 Xcode
- Flutter
- XcodeGen
- CocoaPods
- Go

克隆仓库时初始化固定版本的 sing-box 子模块，再构建 Libbox：

```bash
git submodule update --init --recursive
./scripts/build-libbox.sh
```

再生成 iOS 工程并安装 Flutter/CocoaPods 依赖：

```bash
./apps/ios-app/scripts/setup-flutter.sh
open apps/ios-app/LanbridgeIOS.xcworkspace
```

真机运行前，需要在 Apple Developer 账号中配置主 App、Packet Tunnel
Extension 和 App Group，并在 `apps/ios-app/project.yml` 及 entitlements 中
替换为自己的标识。

API 地址可通过 Dart Define 覆盖：

```bash
flutter build ios --dart-define=API_BASE_URL=https://example.com
```

## VPN Core

本版本固定使用：

- sing-box `v1.14.0`
- commit `0b8995879f29a9b98ee027bc17b75e101445b238`
- gomobile `v0.1.13`

`scripts/build-libbox.sh` 会校验提交并生成同时支持 iPhone 和 iOS
Simulator 的 `third_party/sing-box/Libbox.xcframework`。二进制框架不提交，
避免仓库膨胀，任何人都可以使用同一公开源码重新生成。

## 许可证

本仓库以 GNU GPL v3 或更高版本发布。第三方组件仍受各自许可证约束，
详见 `THIRD_PARTY_NOTICES.md`。
