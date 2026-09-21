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
    this.publicId = '',
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String? ?? '',
    username: json['username'] as String? ?? '',
    locale: json['locale'] as String? ?? 'zh-CN',
    publicId: json['public_id'] as String? ?? '',
  );

  final String id;
  final String username;
  final String locale;
  final String publicId;
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
    this.uploadBytesPerSecond = 0,
    this.downloadBytesPerSecond = 0,
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
  final int uploadBytesPerSecond;
  final int downloadBytesPerSecond;

  TrafficSnapshot withRatesFrom(TrafficSnapshot previous, Duration elapsed) {
    if (elapsed.inMilliseconds <= 0 ||
        uploadBytes < previous.uploadBytes ||
        downloadBytes < previous.downloadBytes) {
      return TrafficSnapshot(
        uploadBytes: uploadBytes,
        downloadBytes: downloadBytes,
        available: available,
      );
    }
    final seconds = elapsed.inMilliseconds / 1000;
    return TrafficSnapshot(
      uploadBytes: uploadBytes,
      downloadBytes: downloadBytes,
      available: available,
      uploadBytesPerSecond: ((uploadBytes - previous.uploadBytes) / seconds)
          .round(),
      downloadBytesPerSecond:
          ((downloadBytes - previous.downloadBytes) / seconds).round(),
    );
  }
}

/// 只保留用户可理解的路由策略摘要，不包含节点地址、凭据或订阅信息。
class RoutingPolicySummary {
  const RoutingPolicySummary({
    required this.revision,
    required this.directPrivateNetworks,
    required this.cnDomainRules,
    required this.cnIpRules,
    required this.dnsStrategy,
    required this.enableIPv6,
    required this.enableSniff,
    required this.customRouteCount,
  });

  factory RoutingPolicySummary.fromConfig(Map<String, dynamic> config) {
    final options = Map<String, dynamic>.from(
      config['client_options'] as Map? ?? const {},
    );
    final route = Map<String, dynamic>.from(
      config['route'] as Map? ?? const {},
    );
    final ruleSets = (route['rule_set'] as List? ?? const [])
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList(growable: false);
    final rules = (route['rules'] as List? ?? const [])
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList(growable: false);
    return RoutingPolicySummary(
      revision: (options['policy_revision'] as num?)?.toInt() ?? 0,
      directPrivateNetworks: rules.any(
        (rule) => rule['ip_is_private'] == true && rule['outbound'] == 'direct',
      ),
      cnDomainRules: ruleSets.any((item) => item['tag'] == 'geosite-cn'),
      cnIpRules: ruleSets.any((item) => item['tag'] == 'geoip-cn'),
      dnsStrategy: options['dns_strategy'] as String? ?? 'ipv4_only',
      enableIPv6: options['enable_ipv6'] == true,
      enableSniff: options['enable_sniff'] != false,
      customRouteCount: rules
          .where(
            (rule) => (rule['outbound'] as String? ?? '').startsWith('route-'),
          )
          .length,
    );
  }

  factory RoutingPolicySummary.fromJson(Map<String, dynamic> json) =>
      RoutingPolicySummary(
        revision: (json['revision'] as num?)?.toInt() ?? 0,
        directPrivateNetworks: json['direct_private_networks'] == true,
        cnDomainRules: json['cn_domain_rules'] == true,
        cnIpRules: json['cn_ip_rules'] == true,
        dnsStrategy: json['dns_strategy'] as String? ?? 'ipv4_only',
        enableIPv6: json['enable_ipv6'] == true,
        enableSniff: json['enable_sniff'] != false,
        customRouteCount: (json['custom_route_count'] as num?)?.toInt() ?? 0,
      );

  final int revision;
  final bool directPrivateNetworks;
  final bool cnDomainRules;
  final bool cnIpRules;
  final String dnsStrategy;
  final bool enableIPv6;
  final bool enableSniff;
  final int customRouteCount;

  Map<String, dynamic> toJson() => {
    'revision': revision,
    'direct_private_networks': directPrivateNetworks,
    'cn_domain_rules': cnDomainRules,
    'cn_ip_rules': cnIpRules,
    'dns_strategy': dnsStrategy,
    'enable_ipv6': enableIPv6,
    'enable_sniff': enableSniff,
    'custom_route_count': customRouteCount,
  };
}
