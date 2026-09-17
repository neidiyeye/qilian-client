/// 启连加速器客户端支持的连接模式。
enum ConnectionMode { rule, global }

/// 系统 VPN 的稳定状态集合，页面不直接依赖 iOS 的 NEVPNStatus。
enum VpnStatus { disconnected, connecting, connected, disconnecting, failed }

/// 服务端对一次连接心跳的判定。
///
/// `reason` 只用于控制连接生命周期，不直接展示给用户。客户端必须先参考
/// 系统 VPN 状态，再决定是修复控制面会话还是停止真实 Tunnel。
class HeartbeatDecision {
  const HeartbeatDecision({required this.allowContinue, required this.reason});

  factory HeartbeatDecision.fromJson(Map<String, dynamic> json) =>
      HeartbeatDecision(
        allowContinue: json['allow_continue'] as bool? ?? false,
        reason: json['reason'] as String? ?? '',
      );

  final bool allowContinue;
  final String reason;
}

/// 登录用户的最小公开资料。
class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    required this.locale,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String? ?? '',
    username: json['username'] as String? ?? '',
    locale: json['locale'] as String? ?? 'zh-CN',
  );

  final String id;
  final String username;
  final String locale;
}

/// 会员有效期与设备限制均由服务端判定，客户端只负责展示。
class Membership {
  const Membership({
    required this.expiresAt,
    required this.deviceLimit,
    required this.onlineLimit,
  });

  factory Membership.fromJson(Map<String, dynamic> json) => Membership(
    expiresAt: DateTime.parse(json['expires_at'] as String),
    deviceLimit: json['device_limit'] as int? ?? 0,
    onlineLimit: json['online_limit'] as int? ?? 0,
  );

  final DateTime expiresAt;
  final int deviceLimit;
  final int onlineLimit;

  int get remainingDays {
    final difference = expiresAt.difference(DateTime.now()).inHours;
    return difference <= 0 ? 0 : (difference / 24).ceil();
  }
}

/// 已绑定设备用于账号页展示和解绑。
class BoundDevice {
  const BoundDevice({
    required this.id,
    required this.deviceId,
    required this.platform,
    required this.name,
    required this.status,
    required this.lastLoginAt,
  });

  factory BoundDevice.fromJson(Map<String, dynamic> json) => BoundDevice(
    id: json['id'] as String? ?? '',
    deviceId: json['device_id'] as String? ?? '',
    platform: json['platform'] as String? ?? '',
    name: json['device_name'] as String? ?? '',
    status: json['status'] as String? ?? '',
    lastLoginAt: DateTime.tryParse(json['last_login_at'] as String? ?? ''),
  );

  final String id;
  final String deviceId;
  final String platform;
  final String name;
  final String status;
  final DateTime? lastLoginAt;
}

/// 节点目录只包含展示信息，不包含机场 URL 或节点密钥。
class VpnNode {
  const VpnNode({
    required this.id,
    required this.name,
    required this.englishName,
    required this.region,
    required this.protocol,
    required this.connectivity,
    this.lastCheckedAt,
  });

  factory VpnNode.fromJson(Map<String, dynamic> json) => VpnNode(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    englishName: json['name_en'] as String? ?? '',
    region: json['region'] as String? ?? 'UN',
    protocol: json['protocol'] as String? ?? '',
    connectivity: json['connectivity'] as String? ?? 'untested',
    lastCheckedAt: DateTime.tryParse(json['last_checked_at'] as String? ?? ''),
  );

  final String id;
  final String name;
  final String englishName;
  final String region;
  final String protocol;
  final String connectivity;
  final DateTime? lastCheckedAt;

  VpnNode copyWith({String? connectivity, DateTime? lastCheckedAt}) => VpnNode(
    id: id,
    name: name,
    englishName: englishName,
    region: region,
    protocol: protocol,
    connectivity: connectivity ?? this.connectivity,
    lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
  );
}

/// 后端下发的核心配置保持为 JSON 对象，Flutter 不理解 sing-box 字段。
class ConnectionLease {
  const ConnectionLease({
    required this.sessionId,
    required this.config,
    required this.heartbeatSeconds,
    required this.probeUrl,
    this.trafficReportToken = '',
  });

  factory ConnectionLease.fromJson(Map<String, dynamic> json) =>
      ConnectionLease(
        sessionId: json['session_id'] as String? ?? '',
        config: Map<String, dynamic>.from(json['config'] as Map? ?? const {}),
        heartbeatSeconds: json['heartbeat_interval_seconds'] as int? ?? 30,
        probeUrl: json['connectivity_probe_url'] as String? ?? '',
        trafficReportToken: json['traffic_report_token'] as String? ?? '',
      );

  final String sessionId;
  final Map<String, dynamic> config;
  final int heartbeatSeconds;
  final String probeUrl;
  final String trafficReportToken;
}

/// App 重启时只恢复控制面会话元数据，不持久化包含机场凭据的 Core 配置。
class ActiveConnectionSnapshot {
  const ActiveConnectionSnapshot({
    required this.sessionId,
    required this.nodeId,
    required this.mode,
    required this.heartbeatSeconds,
    required this.probeUrl,
    required this.savedAt,
  });

  factory ActiveConnectionSnapshot.fromJson(Map<String, dynamic> json) {
    final modeName = json['mode'] as String? ?? '';
    return ActiveConnectionSnapshot(
      sessionId: json['session_id'] as String? ?? '',
      nodeId: json['node_id'] as String? ?? '',
      mode: ConnectionMode.values.firstWhere(
        (value) => value.name == modeName,
        orElse: () => ConnectionMode.rule,
      ),
      heartbeatSeconds: json['heartbeat_seconds'] as int? ?? 30,
      probeUrl: json['probe_url'] as String? ?? '',
      savedAt:
          DateTime.tryParse(json['saved_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String sessionId;
  final String nodeId;
  final ConnectionMode mode;
  final int heartbeatSeconds;
  final String probeUrl;
  final DateTime savedAt;

  bool get isValid => sessionId.isNotEmpty && nodeId.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'node_id': nodeId,
    'mode': mode.name,
    'heartbeat_seconds': heartbeatSeconds,
    'probe_url': probeUrl,
    'saved_at': savedAt.toUtc().toIso8601String(),
  };

  ConnectionLease toLease() => ConnectionLease(
    sessionId: sessionId,
    config: const {},
    heartbeatSeconds: heartbeatSeconds,
    probeUrl: probeUrl,
  );
}

/// Packet Tunnel 统计的累计流量。
class TrafficSnapshot {
  const TrafficSnapshot({
    required this.uploadBytes,
    required this.downloadBytes,
    this.available = false,
  });

  factory TrafficSnapshot.fromJson(Map<dynamic, dynamic> json) =>
      TrafficSnapshot(
        uploadBytes: (json['upload_bytes'] as num?)?.toInt() ?? 0,
        downloadBytes: (json['download_bytes'] as num?)?.toInt() ?? 0,
        available:
            json['available'] == true || (json['available'] as num?) == 1,
      );

  final int uploadBytes;
  final int downloadBytes;
  final bool available;
}
