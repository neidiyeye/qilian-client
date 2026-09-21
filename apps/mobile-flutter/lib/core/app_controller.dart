import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'app_localizations.dart';
import 'models.dart';
import 'vpn_core.dart';

/// AppController 统一控制登录、目录、VPN 状态与后台心跳，页面只渲染状态。
final class AppController extends ChangeNotifier {
  AppController({required ApiClient api, required VpnCore vpn})
    : _api = api,
      _vpn = vpn;

  final ApiClient _api;
  final VpnCore _vpn;

  bool booting = true;
  bool authenticated = false;
  bool busy = false;
  bool checkingNodes = false;
  bool stoppingNodeCheck = false;
  bool switchingNode = false;
  bool verifyingConnectivity = false;
  bool? connectivityAvailable;
  ThemeMode themeMode = ThemeMode.system;
  String localeCode = 'zh-CN';
  UserProfile? user;
  Membership? membership;
  List<BoundDevice> devices = const [];
  String? currentDeviceId;
  String? unbindingDeviceId;
  List<VpnNode> nodes = const [];
  String? selectedNodeId;
  ConnectionMode mode = ConnectionMode.rule;
  VpnStatus vpnStatus = VpnStatus.disconnected;
  TrafficSnapshot traffic = const TrafficSnapshot(
    uploadBytes: 0,
    downloadBytes: 0,
  );
  RoutingPolicySummary? routingPolicy;
  String? message;
  int checkingIndex = 0;
  int checkingTotal = 0;
  String checkingNodeName = '';

  ConnectionLease? _lease;
  Timer? _heartbeatTimer;
  Timer? _statusTimer;
  Timer? _trafficTimer;
  Future<void> _connectionPersistence = Future<void>.value();
  bool _recovering = false;
  bool _userDisconnecting = false;
  bool _heartbeatInFlight = false;
  bool _statusPollInFlight = false;
  bool _foregroundSyncing = false;
  bool _appInForeground = true;
  int _disconnectedPolls = 0;
  TrafficSnapshot? _previousTrafficSample;
  DateTime? _previousTrafficSampleAt;
  final Map<String, DateTime> _localNodeCheckTimes = {};

  static const Duration nodeCheckCacheDuration = Duration(minutes: 10);
  static const String _routingPolicyPreference = 'qilian_routing_policy';

  bool get isEnglish => localeCode == 'en-US';

  VpnNode? get selectedNode {
    for (final node in nodes) {
      if (node.id == selectedNodeId) return node;
    }
    return null;
  }

  bool get membershipActive =>
      membership != null && membership!.expiresAt.isAfter(DateTime.now());

  /// 使用登录时提交给服务端的安装标识判断本机，不能依赖可能重复的设备名称。
  bool isCurrentDevice(BoundDevice device) =>
      currentDeviceId != null && device.deviceId == currentDeviceId;

  bool get canConnect =>
      !busy &&
      membershipActive &&
      selectedNode != null &&
      vpnStatus == VpnStatus.disconnected;

  bool get canChooseNode =>
      !busy &&
      !checkingNodes &&
      (vpnStatus == VpnStatus.disconnected || vpnStatus == VpnStatus.connected);

  /// 启动时恢复主题、登录令牌与系统 VPN 的真实状态。
  Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    themeMode = switch (preferences.getString('huolian_theme')) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    localeCode = preferences.getString('qilian_locale') == 'en-US'
        ? 'en-US'
        : 'zh-CN';
    final savedPolicy = preferences.getString(_routingPolicyPreference);
    if (savedPolicy != null) {
      try {
        routingPolicy = RoutingPolicySummary.fromJson(
          Map<String, dynamic>.from(jsonDecode(savedPolicy) as Map),
        );
      } catch (_) {
        await preferences.remove(_routingPolicyPreference);
      }
    }
    try {
      vpnStatus = await _vpn.getStatus();
    } catch (error) {
      debugPrint('[FireLink] initial VPN status failed: $error');
      vpnStatus = VpnStatus.disconnected;
    }
    if (await _api.restoreSession()) {
      try {
        await _loadAccountData();
        authenticated = true;
        await _restoreActiveConnection();
      } on ApiException {
        authenticated = false;
      }
    } else if (vpnStatus == VpnStatus.connected) {
      // 没有登录态时不能安全恢复控制面会话，清理无人管理的系统 Tunnel。
      await _disconnectUnmanagedTunnel();
    }
    booting = false;
    _startStatusPolling();
    notifyListeners();
  }

  Future<void> setLocale(String value) async {
    if (value != 'zh-CN' && value != 'en-US' || localeCode == value) return;
    localeCode = value;
    message = null;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('qilian_locale', value);
  }

  /// 前台页面只观察系统 Tunnel，不负责维持它的生命周期。
  ///
  /// iOS 锁屏后会暂停 Dart 定时器，但 Packet Tunnel Extension 仍可能正常工作。
  /// 回到前台时必须重新读取 `NEVPNStatus`，不能沿用暂停前的页面状态，也不能因为
  /// 心跳晚到就主动关闭仍可用的系统 VPN。
  void handleLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appInForeground = true;
      _startStatusPolling();
      unawaited(synchronizeVpnState());
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      final lease = _lease;
      if (lease != null && vpnStatus == VpnStatus.connected) {
        unawaited(_sendHeartbeat(lease));
      }
      _appInForeground = false;
      _statusTimer?.cancel();
      _statusTimer = null;
      _trafficTimer?.cancel();
      _trafficTimer = null;
    }
  }

  /// 使用 iOS NetworkExtension 的真实状态校准页面，并在需要时恢复控制面租约。
  Future<void> synchronizeVpnState() async {
    if (_foregroundSyncing || !_appInForeground) return;
    _foregroundSyncing = true;
    try {
      final previous = vpnStatus;
      var current = await _vpn.getStatus();
      if (current == VpnStatus.disconnected &&
          (_lease != null ||
              previous == VpnStatus.connected ||
              previous == VpnStatus.connecting)) {
        // App 刚恢复时 NetworkExtension 与主进程的状态通知可能相差一个调度周期。
        // 短暂复核一次可过滤假 disconnected，又不会掩盖真实退出。
        await Future<void>.delayed(const Duration(milliseconds: 350));
        current = await _vpn.getStatus();
      }

      if (current == VpnStatus.connected) {
        vpnStatus = VpnStatus.connected;
        _disconnectedPolls = 0;
        notifyListeners();
        if (authenticated && _lease == null) {
          await _restoreActiveConnection();
        } else if (_lease case final lease?) {
          _startConnectionTimers(lease.heartbeatSeconds);
          unawaited(_sendHeartbeat(lease));
        }
        return;
      }

      if (current == VpnStatus.connecting) {
        _disconnectedPolls = 0;
        vpnStatus = VpnStatus.connecting;
        notifyListeners();
        return;
      }

      if (_lease != null && !_userDisconnecting) {
        _disconnectedPolls++;
        if (_disconnectedPolls >= 2 && !_recovering) {
          await _recoverConnection();
        }
        return;
      }
      vpnStatus = current;
      notifyListeners();
    } catch (error) {
      // 状态读取失败不能覆盖最后一次可信状态，更不能触发断开。
      debugPrint('[FireLink] foreground VPN synchronization failed: $error');
    } finally {
      _foregroundSyncing = false;
    }
  }

  Future<void> login(String username, String password) async {
    if (busy || username.trim().isEmpty || password.isEmpty) return;
    _setBusy(true);
    message = null;
    try {
      user = await _api.login(username, password);
      authenticated = true;
      await _loadAccountData();
      await _restoreActiveConnection();
    } catch (error) {
      message = _errorMessage(error);
      authenticated = false;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> register(String username, String password) async {
    if (busy || username.trim().isEmpty || password.isEmpty) return;
    _setBusy(true);
    message = null;
    try {
      user = await _api.register(username, password);
      authenticated = true;
      await _loadAccountData();
    } catch (error) {
      message = _errorMessage(error);
      authenticated = false;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> logout() async {
    if (vpnStatus != VpnStatus.disconnected) await disconnect();
    await _api.logout();
    authenticated = false;
    user = null;
    membership = null;
    devices = const [];
    nodes = const [];
    selectedNodeId = null;
    message = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (busy) return;
    _setBusy(true);
    message = null;
    try {
      await _loadAccountData();
    } catch (error) {
      message = _errorMessage(error);
    } finally {
      _setBusy(false);
    }
  }

  void selectNode(String id) {
    if (!canChooseNode || !nodes.any((node) => node.id == id)) return;
    final previousNodeId = selectedNodeId;
    final previousLease = _lease;
    selectedNodeId = id;
    notifyListeners();
    unawaited(_persistSelectedNode(id));
    if (vpnStatus == VpnStatus.connected &&
        previousLease != null &&
        previousNodeId != null &&
        previousNodeId != id) {
      unawaited(
        _switchNode(
          nodeId: id,
          previousNodeId: previousNodeId,
          previousLease: previousLease,
        ),
      );
    }
  }

  /// 节点选择先更新界面，持久化放到后台，避免返回首页前出现可感知等待。
  Future<void> _persistSelectedNode(String id) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('huolian_selected_node', id);
  }

  void setMode(ConnectionMode next) {
    if (vpnStatus != VpnStatus.disconnected || checkingNodes) return;
    mode = next;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode next) async {
    themeMode = next;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('huolian_theme', next.name);
    notifyListeners();
  }

  /// 系统隧道建立成功即进入“已连接”；公网探测在后台执行，不阻塞主交互。
  /// 单个探测地址失败不代表整个 VPN 已断开，因此不能据此主动关闭隧道。
  Future<void> connect() async {
    final node = selectedNode;
    if (!canConnect || node == null) return;
    _setBusy(true);
    message = null;
    vpnStatus = VpnStatus.connecting;
    notifyListeners();
    ConnectionLease? pendingLease;
    final stopwatch = Stopwatch()..start();
    try {
      pendingLease = await _api.connect(node.id, mode);
      await _vpn.connect(_nativeConfiguration(pendingLease));
      _lease = pendingLease;
      unawaited(_rememberRoutingPolicy(pendingLease));
      vpnStatus = VpnStatus.connected;
      connectivityAvailable = null;
      _disconnectedPolls = 0;
      _startConnectionTimers(pendingLease.heartbeatSeconds);
      debugPrint(
        '[FireLink] system VPN connected in ${stopwatch.elapsedMilliseconds}ms',
      );
      notifyListeners();
      unawaited(_rememberActiveConnection(pendingLease, node.id));
      unawaited(_verifyConnectivity(pendingLease));
    } catch (error, stackTrace) {
      debugPrint('[FireLink] connect failed: $error\n$stackTrace');
      try {
        await _vpn.disconnect();
      } catch (_) {}
      if (pendingLease != null) {
        try {
          await _api.reportHealth(
            pendingLease.sessionId,
            false,
            errorCode: _errorCode(error),
          );
          await _api.disconnect(pendingLease.sessionId);
        } catch (_) {}
      }
      _lease = null;
      unawaited(_forgetActiveConnection());
      verifyingConnectivity = false;
      connectivityAvailable = null;
      vpnStatus = VpnStatus.disconnected;
      message = _errorMessage(error);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> disconnect() async {
    if (busy && vpnStatus != VpnStatus.connected) return;
    final lease = _lease;
    _cancelConnectionTimers();
    _userDisconnecting = true;
    busy = true;
    message = null;
    vpnStatus = VpnStatus.disconnecting;
    notifyListeners();
    try {
      if (lease != null) await _sendHeartbeat(lease);
      await _vpn.disconnect();
    } catch (error) {
      // 用户主动断开以本机状态为准，服务端释放失败只写调试日志。
      debugPrint('[FireLink] local disconnect returned an error: $error');
    } finally {
      _lease = null;
      verifyingConnectivity = false;
      connectivityAvailable = null;
      traffic = const TrafficSnapshot(uploadBytes: 0, downloadBytes: 0);
      _resetTrafficSamples();
      vpnStatus = VpnStatus.disconnected;
      busy = false;
      _userDisconnecting = false;
      notifyListeners();
    }
    unawaited(_forgetActiveConnection());
    if (lease != null) unawaited(_releaseLease(lease.sessionId));
  }

  /// 十分钟内已有明确结果的线路直接使用缓存，避免反复占用节点和系统 Tunnel。
  List<VpnNode> nodesNeedingCheck(Iterable<VpnNode> targets, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    return targets
        .where((node) {
          // 旧版检测算法可能向服务端写入错误的红色结果，升级后必须允许立即复测。
          // 蓝色结果可跨启动复用；红色结果只在本次运行中短期复用。
          final checkedAt = node.connectivity == 'online'
              ? node.lastCheckedAt
              : _localNodeCheckTimes[node.id];
          final hasResult =
              node.connectivity == 'online' || node.connectivity == 'offline';
          return !hasResult ||
              checkedAt == null ||
              reference.difference(checkedAt) >= nodeCheckCacheDuration;
        })
        .toList(growable: false);
  }

  /// 停止请求会在当前线路检测结束后生效，避免并发关闭正在工作的 Core。
  void cancelNodeCheck() {
    if (!checkingNodes || stoppingNodeCheck) return;
    stoppingNodeCheck = true;
    notifyListeners();
  }

  /// 节点检测按列表顺序执行，每完成一条立即更新对应行。
  Future<void> checkAllNodes(Iterable<VpnNode> targets) async {
    if (checkingNodes || busy || vpnStatus != VpnStatus.disconnected) return;
    final values = nodesNeedingCheck(targets);
    if (values.isEmpty) {
      message = AppText.fromCode(
        localeCode,
      ).pick('当前线路检测结果仍在有效期内', 'The latest location checks are still valid.');
      notifyListeners();
      return;
    }
    checkingNodes = true;
    stoppingNodeCheck = false;
    checkingIndex = 0;
    checkingTotal = values.length;
    message = null;
    notifyListeners();

    var probeTunnelStarted = false;
    try {
      await _vpn.prepare();
      for (var index = 0; index < values.length; index++) {
        if (stoppingNodeCheck) break;
        final node = values[index];
        checkingIndex = index + 1;
        checkingNodeName = node.name;
        _replaceNode(node.copyWith(connectivity: 'testing'));
        notifyListeners();
        ConnectionLease? testLease;
        try {
          testLease = await _api.connect(node.id, mode);
          if (probeTunnelStarted) {
            await _vpn.reloadConfiguration(_nativeConfiguration(testLease));
          } else {
            await _vpn.connect(
              _nativeConfiguration(testLease),
              enableOnDemand: false,
            );
            probeTunnelStarted = true;
          }
          await _vpn.checkConnectivity(
            testLease.probeUrl.isEmpty
                ? 'https://www.gstatic.com/generate_204'
                : testLease.probeUrl,
          );
          _replaceNode(
            node.copyWith(
              connectivity: 'online',
              lastCheckedAt: DateTime.now(),
            ),
          );
          _localNodeCheckTimes[node.id] = DateTime.now();
          // Core 一返回结果就先刷新当前行；健康上报较慢时也不阻塞视觉反馈。
          notifyListeners();
          await _api.reportHealth(testLease.sessionId, true);
        } catch (error) {
          if (!probeTunnelStarted) {
            try {
              await _vpn.disconnect();
            } catch (_) {}
          }
          _replaceNode(
            node.copyWith(
              connectivity: 'offline',
              lastCheckedAt: DateTime.now(),
            ),
          );
          _localNodeCheckTimes[node.id] = DateTime.now();
          // 与成功路径一致，先让用户看到当前线路不可用，再记录到服务端。
          notifyListeners();
          if (testLease != null) {
            try {
              await _api.reportHealth(
                testLease.sessionId,
                false,
                errorCode: _errorCode(error),
              );
            } catch (_) {}
          }
        } finally {
          if (testLease != null) {
            await _releaseLease(testLease.sessionId);
          }
          notifyListeners();
        }
      }
    } finally {
      if (probeTunnelStarted) {
        try {
          await _vpn.disconnect();
        } catch (error) {
          debugPrint('[FireLink] probe tunnel disconnect failed: $error');
        }
      }
      vpnStatus = VpnStatus.disconnected;
      checkingNodes = false;
      stoppingNodeCheck = false;
      checkingNodeName = '';
      checkingIndex = 0;
      checkingTotal = 0;
      notifyListeners();
    }
  }

  Future<void> unbindDevice(BoundDevice device) async {
    if (unbindingDeviceId != null) return;
    unbindingDeviceId = device.id;
    message = null;
    notifyListeners();
    try {
      await _api.unbindDevice(device.id);
      currentDeviceId ??= await _api.installationId();
      if (isCurrentDevice(device)) {
        await logout();
      } else {
        // 请求成功后立即移除，避免等待第二次网络请求才产生视觉反馈。
        devices = devices
            .where((candidate) => candidate.id != device.id)
            .toList(growable: false);
        notifyListeners();
        devices = await _api.getDevices();
        notifyListeners();
      }
    } catch (error) {
      message = _errorMessage(error);
      notifyListeners();
    } finally {
      unbindingDeviceId = null;
      notifyListeners();
    }
  }

  Future<void> openConnectionLog() async {
    try {
      await _vpn.openConnectionLog();
      message = AppText.fromCode(localeCode).pick(
        '连接日志已输出到 Xcode 控制台',
        'Connection logs were sent to the Xcode console.',
      );
    } catch (error) {
      message = _errorMessage(error);
    }
    notifyListeners();
  }

  Future<void> clearConnectionLog() async {
    try {
      await _vpn.clearConnectionLog();
      message = AppText.fromCode(
        localeCode,
      ).pick('连接日志已清除', 'Connection logs cleared.');
    } catch (error) {
      message = _errorMessage(error);
    }
    notifyListeners();
  }

  void clearMessage() {
    message = null;
    notifyListeners();
  }

  Future<void> _loadAccountData() async {
    final results = await Future.wait<dynamic>([
      _api.getProfile(),
      _api.getNodes(),
      _api.getDevices(),
      _api.installationId(),
    ]);
    final profile = results[0] as (UserProfile, Membership?);
    user = profile.$1;
    membership = profile.$2;
    nodes = results[1] as List<VpnNode>;
    devices = results[2] as List<BoundDevice>;
    currentDeviceId = results[3] as String;
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString('huolian_selected_node');
    if (saved != null && nodes.any((node) => node.id == saved)) {
      selectedNodeId = saved;
    } else if (!nodes.any((node) => node.id == selectedNodeId)) {
      selectedNodeId = nodes.isEmpty ? null : nodes.first.id;
    }
  }

  /// App 重启后以系统 VPN 状态为前提，再恢复控制面会话。
  Future<void> _restoreActiveConnection() async {
    if (vpnStatus != VpnStatus.connected && vpnStatus != VpnStatus.connecting) {
      return;
    }

    ActiveConnectionSnapshot? snapshot;
    try {
      snapshot = await _api.loadActiveConnection();
    } catch (error) {
      debugPrint('[FireLink] load active connection failed: $error');
    }
    if (snapshot == null || !nodes.any((node) => node.id == snapshot!.nodeId)) {
      // 系统 Tunnel 是数据面的真实状态。恢复元数据缺失只代表 App 暂时无法发送
      // 控制面心跳，不能在启动时擅自切断用户仍在使用的网络。
      debugPrint(
        '[FireLink] system VPN is active without a local lease snapshot',
      );
      return;
    }

    selectedNodeId = snapshot.nodeId;
    mode = snapshot.mode;
    final restoredLease = snapshot.toLease();
    try {
      _applyTrafficSample(await _vpn.getTrafficStats());
    } catch (_) {
      traffic = const TrafficSnapshot(uploadBytes: 0, downloadBytes: 0);
      _resetTrafficSamples();
    }

    _lease = restoredLease;
    try {
      final decision = await _api.heartbeat(restoredLease.sessionId, traffic);
      if (!decision.allowContinue) {
        await _handleHeartbeatRejection(restoredLease, decision.reason);
        return;
      }
    } catch (error) {
      // 控制面暂时不可达时保留真实系统 Tunnel，后续定时心跳会继续重试。
      debugPrint('[FireLink] active connection validation deferred: $error');
    }

    if (_lease?.sessionId != restoredLease.sessionId) return;
    _disconnectedPolls = 0;
    _startConnectionTimers(restoredLease.heartbeatSeconds);
  }

  Future<void> _disconnectUnmanagedTunnel() async {
    try {
      await _vpn.disconnect();
    } catch (error) {
      debugPrint('[FireLink] unmanaged tunnel cleanup failed: $error');
    }
    _lease = null;
    vpnStatus = VpnStatus.disconnected;
    traffic = const TrafficSnapshot(uploadBytes: 0, downloadBytes: 0);
    _resetTrafficSamples();
    try {
      await _forgetActiveConnection();
    } catch (_) {}
  }

  Future<void> _rememberActiveConnection(
    ConnectionLease lease,
    String nodeId,
  ) => _queueConnectionPersistence(
    () => _api.saveActiveConnection(
      ActiveConnectionSnapshot(
        sessionId: lease.sessionId,
        nodeId: nodeId,
        mode: mode,
        heartbeatSeconds: lease.heartbeatSeconds,
        probeUrl: lease.probeUrl,
        savedAt: DateTime.now(),
      ),
    ),
    'save',
  );

  Future<void> _forgetActiveConnection() =>
      _queueConnectionPersistence(_api.clearActiveConnection, 'clear');

  /// 串行执行 Keychain 写入，确保“刚连接就断开”等快速操作不会留下过期会话。
  Future<void> _queueConnectionPersistence(
    Future<void> Function() operation,
    String action,
  ) {
    _connectionPersistence = _connectionPersistence.then((_) async {
      try {
        await operation();
      } catch (error) {
        debugPrint('[FireLink] active connection $action failed: $error');
      }
    });
    return _connectionPersistence;
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    if (!_appInForeground) return;
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_statusPollInFlight) return;
      _statusPollInFlight = true;
      try {
        final current = await _vpn.getStatus();
        if (checkingNodes || _userDisconnecting) return;
        // startTunnel 期间系统可能短暂报告 disconnected，不能覆盖页面正在连接的状态。
        if (busy && vpnStatus == VpnStatus.connecting) return;
        if (current == VpnStatus.disconnected && _lease != null) {
          _disconnectedPolls++;
          // 连续两次确认再故障切换，过滤网络切换时的瞬时状态。
          if (_disconnectedPolls >= 2 && !_recovering) {
            await _recoverConnection();
          }
          return;
        }
        _disconnectedPolls = 0;
        if (current == vpnStatus) return;
        vpnStatus = current;
        notifyListeners();
        if (current == VpnStatus.connected && authenticated && _lease == null) {
          await _restoreActiveConnection();
        }
      } catch (error) {
        debugPrint('[FireLink] VPN status poll failed: $error');
      } finally {
        _statusPollInFlight = false;
      }
    });
  }

  /// 已连接时只重载 Extension 内的 Core 配置，系统 VPN 会话保持在线。
  Future<void> _switchNode({
    required String nodeId,
    required String previousNodeId,
    required ConnectionLease previousLease,
  }) async {
    switchingNode = true;
    busy = true;
    message = null;
    connectivityAvailable = null;
    verifyingConnectivity = false;
    vpnStatus = VpnStatus.connecting;
    _cancelConnectionTimers();
    notifyListeners();

    ConnectionLease? replacement;
    var restored = false;
    try {
      replacement = await _api.connect(nodeId, mode);
      await _vpn.reloadConfiguration(_nativeConfiguration(replacement));
      _lease = replacement;
      unawaited(_rememberRoutingPolicy(replacement));
      vpnStatus = VpnStatus.connected;
      _disconnectedPolls = 0;
      _startConnectionTimers(replacement.heartbeatSeconds);
      unawaited(_rememberActiveConnection(replacement, nodeId));
      unawaited(_verifyConnectivity(replacement));
    } catch (error, stackTrace) {
      debugPrint('[FireLink] node switch failed: $error\n$stackTrace');
      selectedNodeId = previousNodeId;
      unawaited(_persistSelectedNode(previousNodeId));

      if (replacement == null) {
        // 服务端尚未创建新会话，原线路与原会话仍然有效。
        _lease = previousLease;
        vpnStatus = VpnStatus.connected;
        _startConnectionTimers(previousLease.heartbeatSeconds);
        unawaited(_rememberActiveConnection(previousLease, previousNodeId));
        restored = true;
      } else {
        await _releaseLease(replacement.sessionId);
        try {
          final rollback = await _api.connect(previousNodeId, mode);
          await _vpn.reloadConfiguration(_nativeConfiguration(rollback));
          _lease = rollback;
          unawaited(_rememberRoutingPolicy(rollback));
          vpnStatus = VpnStatus.connected;
          _startConnectionTimers(rollback.heartbeatSeconds);
          unawaited(_rememberActiveConnection(rollback, previousNodeId));
          restored = true;
        } catch (rollbackError) {
          debugPrint('[FireLink] node switch rollback failed: $rollbackError');
        }
      }

      if (!restored) {
        try {
          await _vpn.disconnect();
        } catch (_) {}
        _lease = null;
        vpnStatus = VpnStatus.disconnected;
        unawaited(_forgetActiveConnection());
      }
      message = restored
          ? AppText.fromCode(localeCode).pick(
              '切换失败，已继续使用原线路',
              'Switch failed. The previous location is still active.',
            )
          : AppText.fromCode(
              localeCode,
            ).pick('切换失败，请重新连接', 'Switch failed. Please reconnect.');
    } finally {
      switchingNode = false;
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _releaseLease(String sessionId) async {
    try {
      await _api.disconnect(sessionId);
    } catch (error) {
      debugPrint('[FireLink] release server session failed: $error');
    }
  }

  void _startConnectionTimers(int heartbeatSeconds) {
    _cancelConnectionTimers();
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: heartbeatSeconds.clamp(10, 120)),
      (_) {
        final lease = _lease;
        if (lease == null || vpnStatus != VpnStatus.connected) return;
        unawaited(_sendHeartbeat(lease));
      },
    );
    if (!_appInForeground) return;
    _trafficTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (vpnStatus != VpnStatus.connected) return;
      try {
        _applyTrafficSample(await _vpn.getTrafficStats());
        notifyListeners();
      } catch (_) {}
    });
  }

  /// 心跳只维护账号控制面，不代表系统 Tunnel 是否仍在传输数据。
  Future<void> _sendHeartbeat(ConnectionLease lease) async {
    if (_heartbeatInFlight || _lease?.sessionId != lease.sessionId) return;
    _heartbeatInFlight = true;
    try {
      final currentTraffic = await _vpn.getTrafficStats();
      final decision = await _api.heartbeat(lease.sessionId, currentTraffic);
      if (!decision.allowContinue && _lease?.sessionId == lease.sessionId) {
        await _handleHeartbeatRejection(lease, decision.reason);
      }
    } catch (error) {
      // 控制面网络失败绝不能反向切断仍可用的数据面。
      debugPrint('[FireLink] heartbeat failed without stopping tunnel: $error');
    } finally {
      _heartbeatInFlight = false;
    }
  }

  /// 区分账号策略拒绝与控制面会话过期，避免把两者都粗暴处理为断开 VPN。
  Future<void> _handleHeartbeatRejection(
    ConnectionLease lease,
    String reason,
  ) async {
    debugPrint('[FireLink] heartbeat rejected: $reason');
    if (const {
      'membership_expired',
      'node_unavailable',
      'client_request',
    }.contains(reason)) {
      await disconnect();
      return;
    }
    await _renewControlLease(lease);
  }

  /// 系统 Tunnel 仍在线但旧会话已被回收时，热更新为同一用户所选线路的新租约。
  /// 该过程不停止 NETunnelProviderSession，因此不会出现打开 App 就瞬间断网。
  Future<void> _renewControlLease(ConnectionLease previous) async {
    final nodeId = selectedNodeId;
    if (_recovering ||
        nodeId == null ||
        _lease?.sessionId != previous.sessionId) {
      return;
    }
    _recovering = true;
    try {
      final replacement = await _api.connect(nodeId, mode);
      final nativeStatus = await _vpn.getStatus();
      if (nativeStatus == VpnStatus.connected ||
          nativeStatus == VpnStatus.connecting) {
        await _vpn.reloadConfiguration(_nativeConfiguration(replacement));
      } else {
        await _vpn.connect(_nativeConfiguration(replacement));
      }
      _lease = replacement;
      unawaited(_rememberRoutingPolicy(replacement));
      vpnStatus = VpnStatus.connected;
      _disconnectedPolls = 0;
      _startConnectionTimers(replacement.heartbeatSeconds);
      unawaited(_rememberActiveConnection(replacement, nodeId));
      debugPrint('[FireLink] control lease renewed without stopping tunnel');
      notifyListeners();
    } catch (error) {
      debugPrint('[FireLink] control lease renewal deferred: $error');
      if (error is ApiException &&
          const {
            'MEMBERSHIP_EXPIRED',
            'NODE_UNAVAILABLE',
          }.contains(error.code)) {
        message = _errorMessage(error);
        await disconnect();
      }
    } finally {
      _recovering = false;
    }
  }

  /// 后台验证只更新线路健康状态，不把一次 URL 测试失败误判为 VPN 断线。
  Future<void> _verifyConnectivity(ConnectionLease lease) async {
    if (lease.probeUrl.isEmpty || _lease?.sessionId != lease.sessionId) {
      return;
    }
    verifyingConnectivity = true;
    notifyListeners();
    try {
      await _vpn.checkConnectivity(lease.probeUrl);
      if (_lease?.sessionId != lease.sessionId) return;
      connectivityAvailable = true;
      notifyListeners();
      try {
        await _api.reportHealth(lease.sessionId, true);
      } catch (error) {
        // 健康上报属于控制面请求，失败不能覆盖已经成功的本地线路探测。
        debugPrint('[FireLink] connectivity health report failed: $error');
      }
    } catch (error) {
      debugPrint('[FireLink] background connectivity probe failed: $error');
      if (_lease?.sessionId != lease.sessionId) return;
      connectivityAvailable = false;
      notifyListeners();
      try {
        await _api.reportHealth(
          lease.sessionId,
          false,
          errorCode: _errorCode(error),
        );
      } catch (_) {}
    } finally {
      if (_lease?.sessionId == lease.sessionId) {
        verifyingConnectivity = false;
        notifyListeners();
      }
    }
  }

  /// 系统隧道异常退出时仅在当前逻辑线路内申请一次后端故障切换。
  Future<void> _recoverConnection() async {
    final lease = _lease;
    if (_recovering || lease == null) return;
    _recovering = true;
    vpnStatus = VpnStatus.connecting;
    notifyListeners();
    try {
      final replacement = await _api.failover(lease.sessionId, 'tunnel_exited');
      await _vpn.connect(_nativeConfiguration(replacement));
      _lease = replacement;
      unawaited(_rememberRoutingPolicy(replacement));
      vpnStatus = VpnStatus.connected;
      connectivityAvailable = null;
      _disconnectedPolls = 0;
      _startConnectionTimers(replacement.heartbeatSeconds);
      final nodeId = selectedNodeId;
      if (nodeId != null) {
        unawaited(_rememberActiveConnection(replacement, nodeId));
      }
      unawaited(_verifyConnectivity(replacement));
    } catch (error) {
      _lease = null;
      vpnStatus = VpnStatus.disconnected;
      message = AppText.fromCode(
        localeCode,
      ).pick('线路已断开，请重新连接', 'The location disconnected. Please reconnect.');
      unawaited(_forgetActiveConnection());
    } finally {
      _recovering = false;
      notifyListeners();
    }
  }

  void _cancelConnectionTimers() {
    _heartbeatTimer?.cancel();
    _trafficTimer?.cancel();
    _heartbeatTimer = null;
    _trafficTimer = null;
  }

  void _applyTrafficSample(TrafficSnapshot sample, {DateTime? sampledAt}) {
    final now = sampledAt ?? DateTime.now();
    final previous = _previousTrafficSample;
    final previousAt = _previousTrafficSampleAt;
    traffic = previous == null || previousAt == null
        ? sample
        : sample.withRatesFrom(previous, now.difference(previousAt));
    _previousTrafficSample = sample;
    _previousTrafficSampleAt = now;
  }

  void _resetTrafficSamples() {
    _previousTrafficSample = null;
    _previousTrafficSampleAt = null;
  }

  Future<void> _rememberRoutingPolicy(ConnectionLease lease) async {
    if (lease.config.isEmpty) return;
    final summary = RoutingPolicySummary.fromConfig(lease.config);
    routingPolicy = summary;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _routingPolicyPreference,
      jsonEncode(summary.toJson()),
    );
  }

  /// 会话级令牌只交给 Packet Tunnel Extension，主 App 的登录令牌不会写入共享配置。
  Map<String, dynamic> _nativeConfiguration(ConnectionLease lease) {
    final configuration = Map<String, dynamic>.from(lease.config);
    if (lease.trafficReportToken.isNotEmpty) {
      configuration['_firelink_control'] = <String, dynamic>{
        'report_url': _api.trafficReportUrl,
        'session_id': lease.sessionId,
        'token': lease.trafficReportToken,
        'interval_seconds': lease.heartbeatSeconds.clamp(30, 60),
      };
    }
    return configuration;
  }

  void _replaceNode(VpnNode replacement) {
    nodes = nodes
        .map((node) => node.id == replacement.id ? replacement : node)
        .toList(growable: false);
  }

  void _setBusy(bool value) {
    busy = value;
    notifyListeners();
  }

  String _errorCode(Object error) {
    if (error is ApiException) return error.code;
    if (error is PlatformException) {
      return error.code.isNotEmpty
          ? error.code
          : (error.message ?? 'NATIVE_VPN_FAILED');
    }
    return error.toString();
  }

  String _errorMessage(Object error) {
    final code = _errorCode(error);
    return AppText.fromCode(localeCode).error(code);
  }

  @override
  void dispose() {
    _appInForeground = false;
    _cancelConnectionTimers();
    _statusTimer?.cancel();
    super.dispose();
  }
}
