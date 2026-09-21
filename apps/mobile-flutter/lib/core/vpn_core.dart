import 'package:flutter/services.dart';

import 'models.dart';

/// 主 App 只依赖此接口。未来替换 sing-box 时，Flutter 页面无需修改。
abstract interface class VpnCore {
  Future<void> prepare();

  Future<void> connect(
    Map<String, dynamic> configuration, {
    bool enableOnDemand = true,
  });

  Future<void> reloadConfiguration(Map<String, dynamic> configuration);

  Future<void> disconnect();

  Future<VpnStatus> getStatus();

  Future<TrafficSnapshot> getTrafficStats();

  Future<void> checkConnectivity(String url);

  Future<void> openConnectionLog();

  Future<void> clearConnectionLog();
}

/// MethodChannel 只传平台无关动作，具体 VPN Core 被封装在 Packet Tunnel 内。
final class NativeVpnCore implements VpnCore {
  const NativeVpnCore();

  static const MethodChannel _channel = MethodChannel('com.ssyoo.huolian/vpn');

  @override
  Future<void> prepare() => _channel.invokeMethod<void>('prepare');

  @override
  Future<void> connect(
    Map<String, dynamic> configuration, {
    bool enableOnDemand = true,
  }) => _channel.invokeMethod<void>('connect', {
    'configuration': configuration,
    'enable_on_demand': enableOnDemand,
  });

  @override
  Future<void> reloadConfiguration(Map<String, dynamic> configuration) =>
      _channel.invokeMethod<void>('reloadConfiguration', configuration);

  @override
  Future<void> disconnect() => _channel.invokeMethod<void>('disconnect');

  @override
  Future<VpnStatus> getStatus() async {
    final value = await _channel.invokeMethod<String>('getStatus') ?? 'failed';
    return switch (value) {
      'disconnected' => VpnStatus.disconnected,
      'connecting' => VpnStatus.connecting,
      'connected' => VpnStatus.connected,
      'disconnecting' => VpnStatus.disconnecting,
      _ => VpnStatus.failed,
    };
  }

  @override
  Future<TrafficSnapshot> getTrafficStats() async {
    final value = await _channel.invokeMapMethod<dynamic, dynamic>(
      'getTrafficStats',
    );
    return TrafficSnapshot.fromJson(value ?? const {});
  }

  @override
  Future<void> checkConnectivity(String url) =>
      _channel.invokeMethod<void>('checkConnectivity', url);

  @override
  Future<void> openConnectionLog() =>
      _channel.invokeMethod<void>('openConnectionLog');

  @override
  Future<void> clearConnectionLog() =>
      _channel.invokeMethod<void>('clearConnectionLog');
}
