import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// 服务端返回的稳定业务错误码，页面负责翻译成人类可读文案。
final class ApiException implements Exception {
  const ApiException(this.code);

  final String code;

  @override
  String toString() => code;
}

/// 所有控制面请求集中在此处，VPN 数据流不会经过 Go API。
final class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  static const String _defaultBaseUrl = 'https://client-api.qljsp.com';
  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _defaultBaseUrl,
  );
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _accessTokenKey = 'huolian_access_token';
  static const String _refreshTokenKey = 'huolian_refresh_token';
  static const String _activeConnectionKey = 'huolian_active_connection';
  static const String _installationIdKey = 'huolian_installation_id';

  final http.Client _client;
  String? _accessToken;
  String? _refreshToken;
  String? _installationId;
  Future<void>? _refreshing;

  String get trafficReportUrl => '$_baseUrl/api/client/traffic';

  /// 令牌使用系统钥匙串保存，App 重启后不需要重复登录。
  Future<bool> restoreSession() async {
    _accessToken = await _storage.read(key: _accessTokenKey);
    _refreshToken = await _storage.read(key: _refreshTokenKey);
    return _accessToken != null && _refreshToken != null;
  }

  Future<String> installationId() async {
    if (_installationId != null) return _installationId!;
    final secured = await _storage.read(key: _installationIdKey);
    if (secured != null && secured.length >= 16) {
      return _installationId = secured;
    }
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_installationIdKey);
    if (saved != null && saved.length >= 16) {
      await _storage.write(key: _installationIdKey, value: saved);
      return _installationId = saved;
    }
    final random = Random.secure();
    final generated = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    await Future.wait([
      _storage.write(key: _installationIdKey, value: generated),
      preferences.setString(_installationIdKey, generated),
    ]);
    return _installationId = generated;
  }

  Future<UserProfile> login(String username, String password) =>
      _authenticate('/api/auth/login', username, password);

  Future<UserProfile> register(String username, String password) =>
      _authenticate('/api/auth/register', username, password);

  Future<UserProfile> _authenticate(
    String path,
    String username,
    String password,
  ) async {
    final body = await _send(
      path,
      method: 'POST',
      authenticated: false,
      payload: {
        'username': username.trim(),
        'password': password,
        'device_id': await installationId(),
        'device_name': Platform.isIOS ? 'iPhone' : Platform.localHostname,
        'platform': Platform.isIOS
            ? 'ios'
            : Platform.isAndroid
            ? 'android'
            : 'macos',
        'app_version': '0.2.0',
      },
    );
    _accessToken = body['access_token'] as String?;
    _refreshToken = body['refresh_token'] as String?;
    await Future.wait([
      _storage.write(key: _accessTokenKey, value: _accessToken),
      _storage.write(key: _refreshTokenKey, value: _refreshToken),
    ]);
    return UserProfile.fromJson(Map<String, dynamic>.from(body['user'] as Map));
  }

  Future<void> logout() async {
    try {
      await _send('/api/auth/logout', method: 'POST');
    } catch (_) {
      // 服务端不可达时仍清理本地凭据，避免用户无法退出。
    }
    _accessToken = null;
    _refreshToken = null;
    await Future.wait([
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
      _storage.delete(key: _activeConnectionKey),
    ]);
  }

  Future<(UserProfile, Membership?)> getProfile() async {
    final data = await _send('/api/user/profile');
    final membership = data['membership'] is Map
        ? Membership.fromJson(
            Map<String, dynamic>.from(data['membership'] as Map),
          )
        : null;
    return (
      UserProfile.fromJson(Map<String, dynamic>.from(data['user'] as Map)),
      membership,
    );
  }

  Future<List<VpnNode>> getNodes() async {
    final data = await _send('/api/client/nodes');
    return (data['nodes'] as List? ?? const [])
        .map(
          (value) => VpnNode.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .toList(growable: false);
  }

  Future<List<BoundDevice>> getDevices() async {
    final data = await _send('/api/user/devices');
    final values = data is List ? data : const [];
    return values
        .map(
          (value) =>
              BoundDevice.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .toList(growable: false);
  }

  Future<void> unbindDevice(String id) => _send(
    '/api/user/devices/unbind',
    method: 'POST',
    payload: {'id': id},
  ).then((_) {});

  Future<ConnectionLease> connect(String nodeId, ConnectionMode mode) async {
    final data = await _send(
      '/api/client/connect',
      method: 'POST',
      payload: {
        'device_id': await installationId(),
        'platform': Platform.isIOS
            ? 'ios'
            : Platform.isAndroid
            ? 'android'
            : 'macos',
        'node_id': nodeId,
        'mode': mode.name,
        'app_version': '0.2.0',
      },
    );
    return ConnectionLease.fromJson(data);
  }

  Future<ConnectionLease> failover(String sessionId, String reason) async =>
      ConnectionLease.fromJson(
        await _send(
          '/api/client/failover',
          method: 'POST',
          payload: {'session_id': sessionId, 'reason': reason},
        ),
      );

  Future<HeartbeatDecision> heartbeat(
    String sessionId,
    TrafficSnapshot traffic,
  ) async {
    final data = await _send(
      '/api/client/heartbeat',
      method: 'POST',
      payload: {
        'session_id': sessionId,
        'upload_bytes': traffic.uploadBytes,
        'download_bytes': traffic.downloadBytes,
      },
    );
    return HeartbeatDecision.fromJson(data);
  }

  Future<void> reportHealth(
    String sessionId,
    bool success, {
    String errorCode = '',
  }) => _send(
    '/api/client/node-health',
    method: 'POST',
    payload: {
      'session_id': sessionId,
      'success': success,
      'latency_ms': success ? 1 : 0,
      'error_code': errorCode,
    },
  ).then((_) {});

  Future<void> disconnect(String sessionId) => _send(
    '/api/client/disconnect',
    method: 'POST',
    payload: {'session_id': sessionId},
  ).then((_) {});

  /// Keychain 只保存恢复心跳所需的会话标识，不保存节点密码或 Core 配置。
  Future<void> saveActiveConnection(ActiveConnectionSnapshot snapshot) =>
      _storage.write(
        key: _activeConnectionKey,
        value: jsonEncode(snapshot.toJson()),
      );

  Future<ActiveConnectionSnapshot?> loadActiveConnection() async {
    final encoded = await _storage.read(key: _activeConnectionKey);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return null;
      final snapshot = ActiveConnectionSnapshot.fromJson(decoded);
      return snapshot.isValid ? snapshot : null;
    } catch (error) {
      debugPrint('[FireLinkAPI] invalid active connection snapshot: $error');
      await clearActiveConnection();
      return null;
    }
  }

  Future<void> clearActiveConnection() =>
      _storage.delete(key: _activeConnectionKey);

  Future<dynamic> _send(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? payload,
    bool authenticated = true,
    bool retry = true,
  }) async {
    if (authenticated && _accessToken == null) {
      throw const ApiException('INVALID_TOKEN');
    }
    final uri = Uri.parse('$_baseUrl$path');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (authenticated) headers['Authorization'] = 'Bearer $_accessToken';

    try {
      final response = method == 'POST'
          ? await _client
                .post(
                  uri,
                  headers: headers,
                  body: jsonEncode(payload ?? const {}),
                )
                .timeout(const Duration(seconds: 15))
          : await _client
                .get(uri, headers: headers)
                .timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic> || decoded['code'] is! String) {
        throw const ApiException('NETWORK_ERROR');
      }
      final code = decoded['code'] as String;
      if (code == 'TOKEN_EXPIRED' && authenticated && retry) {
        await _refresh();
        return _send(path, method: method, payload: payload, retry: false);
      }
      if (code != 'OK') throw ApiException(code);
      return decoded['data'];
    } on ApiException {
      rethrow;
    } catch (error, stackTrace) {
      debugPrint('[FireLinkAPI] $method $path failed: $error\n$stackTrace');
      throw const ApiException('NETWORK_ERROR');
    }
  }

  Future<void> _refresh() async {
    if (_refreshing != null) return _refreshing;
    final completer = _doRefresh();
    _refreshing = completer;
    try {
      await completer;
    } finally {
      _refreshing = null;
    }
  }

  Future<void> _doRefresh() async {
    if (_refreshToken == null) throw const ApiException('INVALID_TOKEN');
    final data = await _send(
      '/api/auth/refresh',
      method: 'POST',
      authenticated: false,
      payload: {'refresh_token': _refreshToken},
    );
    _accessToken = data['access_token'] as String?;
    _refreshToken = data['refresh_token'] as String?;
    await Future.wait([
      _storage.write(key: _accessTokenKey, value: _accessToken),
      _storage.write(key: _refreshTokenKey, value: _refreshToken),
    ]);
  }
}
