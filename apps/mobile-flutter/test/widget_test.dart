import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huolian_app/core/api_client.dart';
import 'package:huolian_app/core/app_controller.dart';
import 'package:huolian_app/core/login_credential_storage.dart';
import 'package:huolian_app/core/models.dart';
import 'package:huolian_app/core/vpn_core.dart';
import 'package:huolian_app/main.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _testApp({
  required Widget home,
  Locale locale = const Locale('zh', 'CN'),
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: home,
  );
}

void main() {
  test('traffic snapshots derive per-second rates without changing totals', () {
    const previous = TrafficSnapshot(
      uploadBytes: 1000,
      downloadBytes: 2000,
      available: true,
    );
    const current = TrafficSnapshot(
      uploadBytes: 3048,
      downloadBytes: 6096,
      available: true,
    );

    final result = current.withRatesFrom(previous, const Duration(seconds: 2));
    expect(result.uploadBytes, 3048);
    expect(result.downloadBytes, 6096);
    expect(result.uploadBytesPerSecond, 1024);
    expect(result.downloadBytesPerSecond, 2048);
  });

  test('routing policy summary excludes credentials and exposes behavior', () {
    final summary = RoutingPolicySummary.fromConfig({
      'client_options': {
        'policy_revision': 12,
        'dns_strategy': 'prefer_ipv4',
        'enable_ipv6': true,
        'enable_sniff': false,
      },
      'route': {
        'rule_set': [
          {'tag': 'geosite-cn'},
          {'tag': 'geoip-cn'},
        ],
        'rules': [
          {'ip_is_private': true, 'outbound': 'direct'},
          {
            'domain_suffix': ['example.com'],
            'outbound': 'route-123',
          },
        ],
      },
      'outbounds': [
        {'password': 'must-not-be-read'},
      ],
    });

    expect(summary.revision, 12);
    expect(summary.directPrivateNetworks, isTrue);
    expect(summary.cnDomainRules, isTrue);
    expect(summary.cnIpRules, isTrue);
    expect(summary.enableIPv6, isTrue);
    expect(summary.enableSniff, isFalse);
    expect(summary.customRouteCount, 1);
    expect(summary.toJson().toString(), isNot(contains('must-not-be-read')));
  });

  testWidgets('brand lockup renders the product name', (tester) async {
    await tester.pumpWidget(
      _testApp(home: const Scaffold(body: BrandLockup(compact: false))),
    );

    expect(find.text('启连加速器'), findsOneWidget);
    expect(find.byType(BrandMark), findsOneWidget);
  });

  testWidgets('region flags use bundled image assets instead of emoji fonts', (
    tester,
  ) async {
    const regions = [
      'HK',
      'JP',
      'SG',
      'TW',
      'KR',
      'MY',
      'US',
      'CA',
      'UK',
      'DE',
      'IN',
      'FR',
      'AU',
      'NL',
    ];
    await tester.pumpWidget(
      _testApp(
        home: Scaffold(
          body: Wrap(
            children: [
              for (final region in regions)
                RegionFlag(region: region, size: 40),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(CountryFlag), findsNWidgets(regions.length));
    expect(find.text('🇹🇼'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login stays usable on an iPhone SE sized viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(750, 1334);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppController(api: ApiClient(), vpn: _FakeVpnCore());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _testApp(home: LoginScreen(controller: controller)),
    );

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields, hasLength(2));
    expect(fields[0].controller?.text, isEmpty);
    expect(fields[1].controller?.text, isEmpty);
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('没有账号？免费注册'), findsOneWidget);
    expect(find.text('记住账号和密码'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved login credentials are restored from secure storage', (
    tester,
  ) async {
    final storage = _FakeLoginCredentialStorage(
      const SavedLoginCredentials(username: 'saved-user', password: '654321'),
    );
    final controller = AppController(api: ApiClient(), vpn: _FakeVpnCore());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _testApp(
        home: LoginScreen(controller: controller, credentialStorage: storage),
      ),
    );
    await tester.pump();

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields[0].controller?.text, 'saved-user');
    expect(fields[1].controller?.text, '654321');
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(storage.clearCalls, 1);
  });

  testWidgets('login language selector switches the whole page to English', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {});
    final controller = AppController(api: ApiClient(), vpn: _FakeVpnCore());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      AnimatedBuilder(
        animation: controller,
        builder: (context, _) => _testApp(
          locale: controller.isEnglish
              ? const Locale('en')
              : const Locale('zh', 'CN'),
          home: LoginScreen(controller: controller),
        ),
      ),
    );

    expect(find.text('欢迎回来'), findsOneWidget);
    await tester.ensureVisible(find.text('English'));
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Qilian'), findsOneWidget);
    expect(controller.localeCode, 'en-US');
    expect(tester.takeException(), isNull);
  });

  testWidgets('registration stays usable on an iPhone SE sized viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(750, 1334);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppController(api: ApiClient(), vpn: _FakeVpnCore());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _testApp(home: RegisterScreen(controller: controller)),
    );

    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('注册免费账号'), findsOneWidget);
    expect(find.text('免费注册'), findsOneWidget);
    expect(find.text('首版免费使用，不包含购买或自动续费'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('connect screen stays usable on an iPhone SE sized viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(750, 1334);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppController(api: ApiClient(), vpn: _FakeVpnCore())
      ..user = const UserProfile(id: 'user', username: 'user', locale: 'zh-CN')
      ..nodes = const [
        VpnNode(
          id: 'hk-a',
          name: '香港-A',
          englishName: 'Hong Kong-A',
          region: 'HK',
          protocol: 'auto',
          connectivity: 'unknown',
        ),
      ]
      ..authenticated = true
      ..booting = false;
    addTearDown(controller.dispose);

    await tester.pumpWidget(_testApp(home: MainShell(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('启连加速器'), findsOneWidget);
    expect(find.text('开始加速'), findsOneWidget);
    expect(find.byType(BrandMark), findsOneWidget);
    expect(find.byIcon(LucideIcons.arrowUpToLine), findsNothing);
    expect(find.byIcon(LucideIcons.arrowDownToLine), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('connected orb settles into a steady state', (tester) async {
    final controller =
        AppController(
            api: ApiClient(),
            vpn: _FakeVpnCore(status: VpnStatus.connected),
          )
          ..user = const UserProfile(
            id: 'user',
            username: 'user',
            locale: 'zh-CN',
          )
          ..vpnStatus = VpnStatus.connected
          ..authenticated = true
          ..booting = false;
    addTearDown(controller.dispose);

    await tester.pumpWidget(_testApp(home: MainShell(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('已加速'), findsOneWidget);
    expect(find.byIcon(LucideIcons.arrowUpToLine), findsOneWidget);
    expect(find.byIcon(LucideIcons.arrowDownToLine), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legal documents are accessible before login', (tester) async {
    final controller = AppController(api: ApiClient(), vpn: _FakeVpnCore());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _testApp(home: LoginScreen(controller: controller)),
    );

    expect(find.text('服务条款'), findsOneWidget);
    expect(find.text('隐私政策'), findsOneWidget);
  });

  testWidgets('bottom navigation opens the node catalog', (tester) async {
    final controller = AppController(api: ApiClient(), vpn: _FakeVpnCore())
      ..user = const UserProfile(id: 'user', username: 'demo', locale: 'zh-CN')
      ..authenticated = true
      ..booting = false;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      AnimatedBuilder(
        animation: controller,
        builder: (context, _) =>
            _testApp(home: MainShell(controller: controller)),
      ),
    );
    await tester.tap(find.text('节点').last);
    await tester.pumpAndSettle();

    expect(find.text('搜索国家或线路'), findsOneWidget);
    expect(find.text('没有匹配的节点'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selecting a node returns to the connect screen', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final controller = AppController(api: ApiClient(), vpn: _FakeVpnCore())
      ..user = const UserProfile(id: 'user', username: 'demo', locale: 'zh-CN')
      ..nodes = const [
        VpnNode(
          id: 'jp-a',
          name: '日本-A',
          englishName: 'Japan-A',
          region: 'JP',
          protocol: 'vmess',
          connectivity: 'online',
        ),
      ]
      ..authenticated = true
      ..booting = false;
    addTearDown(controller.dispose);

    await tester.pumpWidget(_testApp(home: MainShell(controller: controller)));
    await tester.tap(find.text('节点').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('日本-A'));
    await tester.pumpAndSettle();

    expect(controller.selectedNodeId, 'jp-a');
    expect(find.text('当前线路'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('node search filters immediately by localized country name', (
    tester,
  ) async {
    final controller = AppController(api: ApiClient(), vpn: _FakeVpnCore())
      ..user = const UserProfile(id: 'user', username: 'demo', locale: 'zh-CN')
      ..nodes = const [
        VpnNode(
          id: 'us-a',
          name: 'Route-A',
          englishName: 'Route-A',
          region: 'US',
          protocol: 'vmess',
          connectivity: 'online',
        ),
        VpnNode(
          id: 'jp-a',
          name: 'Route-B',
          englishName: 'Route-B',
          region: 'JP',
          protocol: 'vmess',
          connectivity: 'online',
        ),
      ]
      ..authenticated = true
      ..booting = false;
    addTearDown(controller.dispose);

    await tester.pumpWidget(_testApp(home: MainShell(controller: controller)));
    await tester.tap(find.text('节点').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '美国');
    await tester.pump();

    expect(find.text('Route-A'), findsOneWidget);
    expect(find.text('Route-B'), findsNothing);
  });

  testWidgets('logical node results hide protocol and health details', (
    tester,
  ) async {
    final controller = AppController(api: ApiClient(), vpn: _FakeVpnCore())
      ..user = const UserProfile(id: 'user', username: 'demo', locale: 'zh-CN')
      ..nodes = [
        VpnNode(
          id: 'us-a',
          name: '美国-A',
          englishName: 'United States-A',
          region: 'US',
          protocol: 'vmess',
          connectivity: 'online',
          lastCheckedAt: DateTime(2026, 9, 16, 12, 30),
        ),
      ]
      ..authenticated = true
      ..booting = false;
    addTearDown(controller.dispose);

    await tester.pumpWidget(_testApp(home: MainShell(controller: controller)));
    await tester.tap(find.text('节点').last);
    await tester.pumpAndSettle();

    expect(find.text('智能分配线路'), findsOneWidget);
    expect(find.text('VMESS'), findsNothing);
    expect(find.text('可用'), findsNothing);
    expect(find.text('不可用'), findsNothing);
    expect(find.textContaining('12:30'), findsNothing);
  });

  testWidgets('account marks only the matching installation as current', (
    tester,
  ) async {
    final controller = AppController(api: ApiClient(), vpn: _FakeVpnCore())
      ..user = const UserProfile(id: 'user', username: 'demo', locale: 'zh-CN')
      ..devices = [
        BoundDevice(
          id: 'binding-1',
          deviceId: 'other-installation',
          platform: 'ios',
          name: 'iPhone',
          status: 'active',
          lastLoginAt: DateTime(2026, 9, 18),
        ),
        BoundDevice(
          id: 'binding-2',
          deviceId: 'current-installation',
          platform: 'ios',
          name: 'iPhone',
          status: 'active',
          lastLoginAt: DateTime(2026, 9, 18),
        ),
      ]
      ..currentDeviceId = 'current-installation'
      ..authenticated = true
      ..booting = false;
    addTearDown(controller.dispose);

    await tester.pumpWidget(_testApp(home: MainShell(controller: controller)));
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();

    expect(find.text('当前设备'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account exposes copyable public ID and routing policy details', (
    tester,
  ) async {
    final controller = AppController(api: ApiClient(), vpn: _FakeVpnCore())
      ..user = const UserProfile(
        id: 'internal-user-id',
        publicId: 'QL-20260921-ABCD',
        username: 'demo',
        locale: 'zh-CN',
      )
      ..routingPolicy = const RoutingPolicySummary(
        revision: 8,
        directPrivateNetworks: true,
        cnDomainRules: true,
        cnIpRules: true,
        dnsStrategy: 'prefer_ipv4',
        enableIPv6: false,
        enableSniff: true,
        customRouteCount: 2,
      )
      ..authenticated = true
      ..booting = false;
    addTearDown(controller.dispose);

    await tester.pumpWidget(_testApp(home: MainShell(controller: controller)));
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('QL-20260921-ABCD'), findsOneWidget);
    expect(find.textContaining('internal-user-id'), findsNothing);
    await tester.tap(find.text('智能规则'));
    await tester.pumpAndSettle();

    expect(find.text('策略版本'), findsOneWidget);
    expect(find.text('v8'), findsOneWidget);
    expect(find.text('局域网与私有地址'), findsOneWidget);
    expect(find.text('2 条'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('node catalog includes an explicit refresh action', (
    tester,
  ) async {
    final controller = AppController(api: ApiClient(), vpn: _FakeVpnCore())
      ..user = const UserProfile(id: 'user', username: 'demo', locale: 'zh-CN')
      ..authenticated = true
      ..booting = false;
    addTearDown(controller.dispose);

    await tester.pumpWidget(_testApp(home: MainShell(controller: controller)));
    await tester.tap(find.text('节点').last);
    await tester.pumpAndSettle();

    expect(find.byTooltip('刷新'), findsOneWidget);
  });

  testWidgets('node health check controls stay hidden', (tester) async {
    final controller = AppController(api: ApiClient(), vpn: _FakeVpnCore())
      ..user = const UserProfile(id: 'user', username: 'demo', locale: 'zh-CN')
      ..checkingNodes = true
      ..checkingIndex = 1
      ..checkingTotal = 2
      ..checkingNodeName = '日本-A'
      ..authenticated = true
      ..booting = false;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      AnimatedBuilder(
        animation: controller,
        builder: (context, _) =>
            _testApp(home: MainShell(controller: controller)),
      ),
    );
    await tester.tap(find.text('节点').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('正在检测'), findsNothing);
    expect(find.text('完成当前线路后停止'), findsNothing);
    expect(find.byTooltip('检测当前线路'), findsNothing);
    expect(find.byTooltip('停止检测'), findsNothing);
  });

  test('node check cache skips results younger than ten minutes', () {
    final controller = AppController(api: ApiClient(), vpn: _FakeVpnCore());
    addTearDown(controller.dispose);
    final now = DateTime(2026, 9, 16, 12);
    final targets = [
      VpnNode(
        id: 'fresh',
        name: 'Fresh',
        englishName: 'Fresh',
        region: 'JP',
        protocol: 'vmess',
        connectivity: 'online',
        lastCheckedAt: now.subtract(const Duration(minutes: 9)),
      ),
      VpnNode(
        id: 'stale',
        name: 'Stale',
        englishName: 'Stale',
        region: 'JP',
        protocol: 'vmess',
        connectivity: 'offline',
        lastCheckedAt: now.subtract(const Duration(minutes: 10)),
      ),
      VpnNode(
        id: 'old-red',
        name: 'Old red result',
        englishName: 'Old red result',
        region: 'JP',
        protocol: 'vmess',
        connectivity: 'offline',
        lastCheckedAt: now.subtract(const Duration(minutes: 1)),
      ),
    ];

    expect(
      controller.nodesNeedingCheck(targets, now: now).map((node) => node.id),
      ['stale', 'old-red'],
    );
  });

  test('active connection snapshot never contains core configuration', () {
    final snapshot = ActiveConnectionSnapshot(
      sessionId: 'session-id',
      nodeId: 'jp-a',
      mode: ConnectionMode.rule,
      heartbeatSeconds: 30,
      probeUrl: 'https://example.com/healthz',
      savedAt: DateTime.utc(2026, 9, 16),
    );

    final encoded = snapshot.toJson();
    expect(encoded['config'], isNull);
    expect(
      ActiveConnectionSnapshot.fromJson(encoded).toLease().config,
      isEmpty,
    );
  });

  test('manual disconnect does not expose a network error', () async {
    final controller = AppController(
      api: ApiClient(),
      vpn: _FakeVpnCore(throwOnDisconnect: true),
    )..vpnStatus = VpnStatus.connected;
    addTearDown(controller.dispose);

    await controller.disconnect();

    expect(controller.vpnStatus, VpnStatus.disconnected);
    expect(controller.message, isNull);
  });

  test('foreground synchronization trusts the active system tunnel', () async {
    final vpn = _FakeVpnCore(status: VpnStatus.connected);
    final controller = AppController(api: ApiClient(), vpn: vpn)
      ..vpnStatus = VpnStatus.disconnected;
    addTearDown(controller.dispose);

    await controller.synchronizeVpnState();

    expect(controller.vpnStatus, VpnStatus.connected);
    expect(vpn.disconnectCalls, 0);
  });
}

final class _FakeLoginCredentialStorage implements LoginCredentialStorage {
  _FakeLoginCredentialStorage(this.saved);

  final SavedLoginCredentials? saved;
  int clearCalls = 0;

  @override
  Future<void> clear() async {
    clearCalls++;
  }

  @override
  Future<SavedLoginCredentials?> read() async => saved;

  @override
  Future<void> save(String username, String password) async {}
}

/// Widget tests只验证页面交互，不启动真实的平台 VPN。
final class _FakeVpnCore implements VpnCore {
  _FakeVpnCore({
    this.throwOnDisconnect = false,
    this.status = VpnStatus.disconnected,
  });

  final bool throwOnDisconnect;
  VpnStatus status;
  int disconnectCalls = 0;

  @override
  Future<void> checkConnectivity(String url) async {}

  @override
  Future<void> clearConnectionLog() async {}

  @override
  Future<void> connect(
    Map<String, dynamic> configuration, {
    bool enableOnDemand = true,
  }) async {}

  @override
  Future<void> reloadConfiguration(Map<String, dynamic> configuration) async {}

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    if (throwOnDisconnect) throw PlatformException(code: 'NETWORK_ERROR');
  }

  @override
  Future<VpnStatus> getStatus() async => status;

  @override
  Future<TrafficSnapshot> getTrafficStats() async =>
      const TrafficSnapshot(uploadBytes: 0, downloadBytes: 0);

  @override
  Future<void> openConnectionLog() async {}

  @override
  Future<void> prepare() async {}
}
