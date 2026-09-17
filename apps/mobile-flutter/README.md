# 启连加速器 Flutter App

该模块是 Android、iOS 和后续桌面端共享的产品界面与业务状态机。iOS 当前通过 CocoaPods 嵌入 `apps/ios-app`，不是独立 Runner。

## 目录

```text
lib/main.dart                 页面、主题和交互组件
lib/core/models.dart          平台无关领域模型
lib/core/api_client.dart      Go 控制面 API
lib/core/app_controller.dart  登录、连接、心跳和故障恢复状态机
lib/core/vpn_core.dart        原生 VPN Core 抽象与 MethodChannel 实现
```

## 开发验证

```bash
flutter pub get
flutter analyze
flutter test
```

默认 API 为 `https://client-api.qljsp.com`。切换环境时使用：

```bash
flutter run --dart-define=API_BASE_URL=https://example.com
```

不要在 Flutter 中导入 sing-box/Libbox 类型，也不要在页面中拼装完整 Core 配置。新增平台时实现相同的 `VpnCore` 动作协议即可。
