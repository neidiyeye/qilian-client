import 'dart:async';
import 'dart:math' as math;

import 'package:country_flags/country_flags.dart' as country_flags;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/api_client.dart';
import 'core/app_localizations.dart';
import 'core/app_controller.dart';
import 'core/login_credential_storage.dart';
import 'core/models.dart';
import 'core/vpn_core.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );
  runApp(const FireLinkBootstrap());
}

/// 品牌色只用于主要动作；绿色专门表示线路已连通。
abstract final class FireLinkColors {
  static const brand = Color(0xFF5B4FF6);
  static const brandDark = Color(0xFF7D74FF);
  static const success = Color(0xFF1D9A6C);
  static const warning = Color(0xFFD98A16);
  static const danger = Color(0xFFD83D32);
  static const upload = Color(0xFFE06C3B);
  static const download = Color(0xFF3478C9);
  static const ink = Color(0xFF171816);
  static const paper = Color(0xFFF6F6F3);
  static const dark = Color(0xFF111210);
  static const darkSurface = Color(0xFF191A18);
}

final Uri _termsUri = Uri.parse('https://www.qljsp.com/contract.html');
final Uri _privacyUri = Uri.parse('https://www.qljsp.com/privacy.html');

/// 使用系统内置浏览器页打开协议，保留返回 App 的连续体验。
Future<void> _openLegalPage(BuildContext context, Uri uri) async {
  final opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppText.of(context).legalOpenFailed)),
    );
  }
}

class FireLinkBootstrap extends StatefulWidget {
  const FireLinkBootstrap({super.key});

  @override
  State<FireLinkBootstrap> createState() => _FireLinkBootstrapState();
}

class _FireLinkBootstrapState extends State<FireLinkBootstrap>
    with WidgetsBindingObserver {
  late final AppController controller = AppController(
    api: ApiClient(),
    vpn: const NativeVpnCore(),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    controller.handleLifecycleState(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => MaterialApp(
      title: 'Qilian Accelerator',
      debugShowCheckedModeBanner: false,
      locale: controller.isEnglish
          ? const Locale('en')
          : const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeMode: controller.themeMode,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: controller.booting
          ? const _LaunchScreen()
          : controller.authenticated
          ? MainShell(controller: controller)
          : LoginScreen(controller: controller),
    ),
  );

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: dark ? FireLinkColors.brandDark : FireLinkColors.brand,
      onPrimary: Colors.white,
      secondary: FireLinkColors.success,
      onSecondary: Colors.white,
      error: dark ? const Color(0xFFFF7B6E) : FireLinkColors.danger,
      onError: Colors.white,
      surface: dark ? FireLinkColors.darkSurface : Colors.white,
      onSurface: dark ? const Color(0xFFF1F2EE) : FireLinkColors.ink,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? FireLinkColors.dark
          : FireLinkColors.paper,
      dividerColor: dark ? const Color(0xFF2B2D29) : const Color(0xFFE3E4DE),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        bodyLarge: TextStyle(fontSize: 16, height: 1.4, letterSpacing: 0),
        bodyMedium: TextStyle(fontSize: 14, height: 1.4, letterSpacing: 0),
        labelLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF1D1F1C) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: dark ? const Color(0xFF343631) : const Color(0xFFD9DAD4),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: dark ? FireLinkColors.darkSurface : Colors.white,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 23,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _LaunchScreen extends StatelessWidget {
  const _LaunchScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: BrandLockup(compact: false)));
}

/// App 内与桌面图标使用同一份启连加速器品牌图。
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 42});

  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.2),
    child: Image.asset(
      'assets/images/qilian-logo.png',
      package: _sharedAssetPackage,
      width: size,
      height: size,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
    ),
  );
}

class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      BrandMark(size: compact ? 34 : 52),
      SizedBox(width: compact ? 10 : 14),
      Text(
        AppText.of(context).brandName,
        style: TextStyle(
          fontSize: compact ? 22 : 32,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    ],
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.controller,
    this.credentialStorage = const SecureLoginCredentialStorage(),
  });

  final AppController controller;
  final LoginCredentialStorage credentialStorage;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final username = TextEditingController();
  final password = TextEditingController();
  bool obscurePassword = true;
  bool rememberCredentials = true;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreCredentials());
  }

  Future<void> _restoreCredentials() async {
    try {
      final saved = await widget.credentialStorage.read();
      if (!mounted || saved == null) return;
      setState(() {
        username.text = saved.username;
        password.text = saved.password;
        rememberCredentials = true;
      });
    } catch (_) {
      // 钥匙串暂时不可用时仍允许手动登录。
    }
  }

  Future<void> _submit() async {
    final normalizedUsername = username.text.trim();
    final enteredPassword = password.text;
    final shouldRemember = rememberCredentials;
    final storage = widget.credentialStorage;
    final controller = widget.controller;
    if (!shouldRemember) await _clearStoredCredentials();
    await controller.login(normalizedUsername, enteredPassword);
    if (controller.authenticated && shouldRemember) {
      try {
        await storage.save(normalizedUsername, enteredPassword);
      } catch (_) {
        // 记住失败不应该影响已成功的登录。
      }
    }
  }

  Future<void> _clearStoredCredentials() async {
    try {
      await widget.credentialStorage.clear();
    } catch (_) {
      // 钥匙串暂时不可用时仍允许用户继续操作。
    }
  }

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final text = AppText.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: BrandLockup(compact: false),
                    ),
                    const SizedBox(height: 48),
                    Text(
                      text.welcomeBack,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      text.loginSubtitle,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: username,
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: text.account,
                        prefixIcon: const Icon(LucideIcons.userRound),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: password,
                      obscureText: obscurePassword,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: text.password,
                        prefixIcon: const Icon(LucideIcons.lockKeyhole),
                        suffixIcon: IconButton(
                          tooltip: obscurePassword
                              ? text.showPassword
                              : text.hidePassword,
                          onPressed: () => setState(
                            () => obscurePassword = !obscurePassword,
                          ),
                          icon: Icon(
                            obscurePassword
                                ? LucideIcons.eye
                                : LucideIcons.eyeOff,
                          ),
                        ),
                      ),
                    ),
                    CheckboxListTile(
                      value: rememberCredentials,
                      onChanged: controller.busy
                          ? null
                          : (value) {
                              final selected = value ?? false;
                              setState(() => rememberCredentials = selected);
                              if (!selected) {
                                unawaited(_clearStoredCredentials());
                              }
                            },
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      title: Text(text.rememberCredentials),
                    ),
                    if (controller.message != null) ...[
                      const SizedBox(height: 14),
                      InlineNotice(
                        message: controller.message!,
                        onClose: controller.clearMessage,
                      ),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: controller.busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: controller.busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(text.login),
                    ),
                    TextButton(
                      onPressed: controller.busy
                          ? null
                          : () {
                              controller.clearMessage();
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      RegisterScreen(controller: controller),
                                ),
                              );
                            },
                      child: Text(text.freeRegister),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      text.loginAgreement,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 4,
                      children: [
                        TextButton(
                          onPressed: () => _openLegalPage(context, _termsUri),
                          child: Text(text.terms),
                        ),
                        TextButton(
                          onPressed: () => _openLegalPage(context, _privacyUri),
                          child: Text(text.privacy),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LanguageSelector(controller: controller),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class LanguageSelector extends StatelessWidget {
  const LanguageSelector({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    return Semantics(
      label: text.language,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(
            onPressed: () => controller.setLocale('zh-CN'),
            child: Text(
              text.chinese,
              style: TextStyle(
                fontWeight: controller.isEnglish
                    ? FontWeight.w400
                    : FontWeight.w700,
              ),
            ),
          ),
          Text(
            '|',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
          TextButton(
            onPressed: () => controller.setLocale('en-US'),
            child: Text(
              text.englishName,
              style: TextStyle(
                fontWeight: controller.isEnglish
                    ? FontWeight.w700
                    : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegisterScreenState extends State<RegisterScreen> {
  final username = TextEditingController();
  final password = TextEditingController();
  bool obscurePassword = true;
  String? validationMessage;

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final text = AppText.fromCode(widget.controller.localeCode);
    final normalizedUsername = username.text.trim();
    if (normalizedUsername.runes.length < 4 ||
        normalizedUsername.runes.length > 64 ||
        RegExp(r'\s').hasMatch(normalizedUsername)) {
      setState(() => validationMessage = text.usernameValidation);
      return;
    }
    if (password.text.runes.length < 6) {
      setState(() => validationMessage = text.passwordValidation);
      return;
    }
    setState(() => validationMessage = null);
    await widget.controller.register(normalizedUsername, password.text);
    if (mounted && widget.controller.authenticated) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final text = AppText.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(text.registerTitle)),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: BrandLockup(compact: true),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        text.createAccount,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        text.freeVersionNote,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        controller: username,
                        enabled: !controller.busy,
                        autofillHints: const [AutofillHints.newUsername],
                        textInputAction: TextInputAction.next,
                        maxLength: 64,
                        decoration: InputDecoration(
                          labelText: text.account,
                          hintText: text.usernameHint,
                          prefixIcon: const Icon(LucideIcons.userRoundPlus),
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: password,
                        enabled: !controller.busy,
                        obscureText: obscurePassword,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => submit(),
                        decoration: InputDecoration(
                          labelText: text.password,
                          hintText: text.passwordHint,
                          prefixIcon: const Icon(LucideIcons.lockKeyhole),
                          suffixIcon: IconButton(
                            tooltip: obscurePassword
                                ? text.showPassword
                                : text.hidePassword,
                            onPressed: () => setState(
                              () => obscurePassword = !obscurePassword,
                            ),
                            icon: Icon(
                              obscurePassword
                                  ? LucideIcons.eye
                                  : LucideIcons.eyeOff,
                            ),
                          ),
                        ),
                      ),
                      if (validationMessage != null ||
                          controller.message != null) ...[
                        const SizedBox(height: 14),
                        InlineNotice(
                          message: validationMessage ?? controller.message!,
                          onClose: () {
                            setState(() => validationMessage = null);
                            controller.clearMessage();
                          },
                        ),
                      ],
                      const SizedBox(height: 22),
                      FilledButton(
                        onPressed: controller.busy ? null : submit,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: controller.busy
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(text.register),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        text.registerAgreement,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 4,
                        children: [
                          TextButton(
                            onPressed: () => _openLegalPage(context, _termsUri),
                            child: Text(text.terms),
                          ),
                          TextButton(
                            onPressed: () =>
                                _openLegalPage(context, _privacyUri),
                            child: Text(text.privacy),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final text = AppText.of(context);
    final destinations = [
      NavigationDestination(
        icon: const Icon(LucideIcons.power),
        selectedIcon: const Icon(LucideIcons.power),
        label: text.connect,
      ),
      NavigationDestination(
        icon: const Icon(LucideIcons.server),
        selectedIcon: const Icon(LucideIcons.serverCog),
        label: text.nodes,
      ),
      NavigationDestination(
        icon: const Icon(LucideIcons.circleUserRound),
        selectedIcon: const Icon(LucideIcons.userRoundCheck),
        label: text.mine,
      ),
    ];
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 760;
          final content = _buildContent(controller);
          if (!desktop) return SafeArea(bottom: false, child: content);

          return SafeArea(
            child: Row(
              children: [
                NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: (value) =>
                      setState(() => index = value),
                  labelType: NavigationRailLabelType.all,
                  leading: const Padding(
                    padding: EdgeInsets.only(top: 18, bottom: 22),
                    child: BrandMark(size: 42),
                  ),
                  destinations: destinations
                      .map(
                        (item) => NavigationRailDestination(
                          icon: item.icon,
                          selectedIcon: item.selectedIcon,
                          label: Text(item.label),
                        ),
                      )
                      .toList(growable: false),
                ),
                VerticalDivider(
                  width: 1,
                  color: Theme.of(context).dividerColor,
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: content,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width < 760
          ? NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (value) => setState(() => index = value),
              destinations: destinations,
            )
          : null,
    );
  }

  /// 页面栈始终保留状态，切换节点或账户页时不会重建连接页动画与滚动位置。
  Widget _buildContent(AppController controller) => Column(
    children: [
      if (controller.message != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: InlineNotice(
            message: controller.message!,
            onClose: controller.clearMessage,
          ),
        ),
      Expanded(
        child: IndexedStack(
          index: index,
          children: [
            ConnectScreen(
              controller: controller,
              onChooseNode: () => setState(() => index = 1),
            ),
            NodesScreen(
              controller: controller,
              onNodeSelected: () => setState(() => index = 0),
            ),
            AccountScreen(controller: controller),
          ],
        ),
      ),
    ],
  );
}

class ConnectScreen extends StatelessWidget {
  const ConnectScreen({
    super.key,
    required this.controller,
    required this.onChooseNode,
  });

  final AppController controller;
  final VoidCallback onChooseNode;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final desktop = MediaQuery.sizeOf(context).width >= 760;
    final connected = controller.vpnStatus == VpnStatus.connected;
    final node = controller.selectedNode;
    final canTapPower =
        !controller.switchingNode && (connected || controller.canConnect);
    return Stack(
      children: [
        const Positioned(
          top: 52,
          left: -62,
          right: -62,
          height: 292,
          child: _WorldMapBackdrop(),
        ),
        RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              Row(
                children: [
                  // 桌面端左侧导航已经展示品牌，内容区不再重复占用首行空间。
                  if (!desktop) const BrandLockup(compact: true),
                  const Spacer(),
                  _StatusPill(
                    status: controller.vpnStatus,
                    switching: controller.switchingNode,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Center(
                child: _ConnectionOrb(
                  status: controller.vpnStatus,
                  switching: controller.switchingNode,
                  enabled: canTapPower,
                  onTap: connected ? controller.disconnect : controller.connect,
                ),
              ),
              if (connected) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _TrafficValue(
                      icon: LucideIcons.arrowUpToLine,
                      color: FireLinkColors.upload,
                      bytes: controller.traffic.uploadBytesPerSecond,
                    ),
                    const SizedBox(width: 30),
                    _TrafficValue(
                      icon: LucideIcons.arrowDownToLine,
                      color: FireLinkColors.download,
                      bytes: controller.traffic.downloadBytesPerSecond,
                    ),
                  ],
                ),
                const SizedBox(height: 30),
              ] else
                const SizedBox(height: 24),
              Text(
                text.currentRoute,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              Material(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: controller.canChooseNode ? onChooseNode : null,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        RegionFlag(region: node?.region ?? 'UN', size: 42),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                node == null
                                    ? text.chooseNode
                                    : _nodeName(context, node),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                node == null
                                    ? text.notSelected
                                    : '${node.region}  ·  ${text.smartAllocation}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(LucideIcons.chevronRight, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                text.connectionMode,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              Semantics(
                enabled: controller.vpnStatus == VpnStatus.disconnected,
                child: AbsorbPointer(
                  absorbing: controller.vpnStatus != VpnStatus.disconnected,
                  child: SegmentedButton<ConnectionMode>(
                    segments: [
                      ButtonSegment(
                        value: ConnectionMode.rule,
                        icon: const Icon(LucideIcons.route, size: 18),
                        label: Text(text.smartMode),
                      ),
                      ButtonSegment(
                        value: ConnectionMode.global,
                        icon: const Icon(LucideIcons.globe2, size: 18),
                        label: Text(text.globalMode),
                      ),
                    ],
                    selected: {controller.mode},
                    onSelectionChanged: (value) =>
                        controller.setMode(value.first),
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      shape: WidgetStatePropertyAll(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _MembershipRow(membership: controller.membership),
            ],
          ),
        ),
      ],
    );
  }
}

class _WorldMapBackdrop extends StatelessWidget {
  const _WorldMapBackdrop();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: Opacity(
        opacity: dark ? 0.10 : 0.065,
        child: Image.asset(
          'assets/images/world-map-soft.png',
          package: _sharedAssetPackage,
          fit: BoxFit.contain,
          color: dark ? const Color(0xFFDCE8E2) : const Color(0xFF25332E),
          colorBlendMode: BlendMode.srcIn,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

/// 多层连接环只表达 VPN 状态，不参与连接判断；真实状态仍来自系统隧道。
class _ConnectionOrb extends StatefulWidget {
  const _ConnectionOrb({
    required this.status,
    required this.switching,
    required this.enabled,
    required this.onTap,
  });

  final VpnStatus status;
  final bool switching;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_ConnectionOrb> createState() => _ConnectionOrbState();
}

class _ConnectionOrbState extends State<_ConnectionOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  bool pressed = false;

  bool get rotating =>
      widget.switching ||
      widget.status == VpnStatus.connecting ||
      widget.status == VpnStatus.disconnecting;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncMotion());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant _ConnectionOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
    if (oldWidget.status != widget.status) {
      if (widget.status == VpnStatus.connected) {
        HapticFeedback.mediumImpact();
      } else if (widget.status == VpnStatus.failed) {
        HapticFeedback.heavyImpact();
      } else if (oldWidget.status == VpnStatus.disconnecting &&
          widget.status == VpnStatus.disconnected) {
        HapticFeedback.selectionClick();
      }
    }
  }

  void _syncMotion() {
    if (!mounted) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (rotating && !reduceMotion) {
      if (!motion.isAnimating) motion.repeat();
    } else {
      motion.stop();
      motion.value = 0;
    }
  }

  void _handleTap() {
    if (!widget.enabled) return;
    HapticFeedback.lightImpact();
    widget.onTap();
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = AppText.of(context);
    final connected = widget.status == VpnStatus.connected;
    final showAccent = widget.enabled || rotating || connected;
    final accent = connected
        ? FireLinkColors.success
        : widget.status == VpnStatus.failed
        ? scheme.error
        : scheme.primary;
    final label = widget.switching
        ? text.switching
        : switch (widget.status) {
            VpnStatus.connecting => text.connecting,
            VpnStatus.connected => text.accelerated,
            VpnStatus.disconnecting => text.disconnecting,
            VpnStatus.failed => text.reconnect,
            VpnStatus.disconnected => text.start,
          };

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: label,
      hint: connected ? text.disconnectHint : text.connectHint,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? _handleTap : null,
        onTapDown: widget.enabled
            ? (_) => setState(() => pressed = true)
            : null,
        onTapCancel: widget.enabled
            ? () => setState(() => pressed = false)
            : null,
        onTapUp: widget.enabled ? (_) => setState(() => pressed = false) : null,
        child: AnimatedScale(
          scale: pressed ? 0.975 : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: AnimatedBuilder(
            animation: motion,
            builder: (context, child) => CustomPaint(
              painter: _ConnectionOrbPainter(
                progress: motion.value,
                accent: accent,
                status: widget.status,
                switching: widget.switching,
                dark: Theme.of(context).brightness == Brightness.dark,
              ),
              child: child,
            ),
            child: SizedBox.square(
              dimension: 224,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: showAccent
                        ? accent
                        : scheme.onSurface.withValues(alpha: 0.12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.42),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        LucideIcons.power,
                        size: 42,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 12),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        child: Text(
                          label,
                          key: ValueKey(label),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionOrbPainter extends CustomPainter {
  const _ConnectionOrbPainter({
    required this.progress,
    required this.accent,
    required this.status,
    required this.switching,
    required this.dark,
  });

  final double progress;
  final Color accent;
  final VpnStatus status;
  final bool switching;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final pulse = (math.sin(progress * math.pi * 2) + 1) / 2;
    final rotating =
        switching ||
        status == VpnStatus.connecting ||
        status == VpnStatus.disconnecting;
    final connected = status == VpnStatus.connected;
    final neutral = dark ? Colors.white : FireLinkColors.ink;

    canvas.drawCircle(
      center,
      109,
      Paint()
        ..color = accent.withValues(
          alpha: rotating
              ? 0.08 + pulse * 0.04
              : connected
              ? 0.11
              : 0.035,
        ),
    );
    for (final ring in const [(104.0, 2.0), (91.0, 1.5), (80.0, 1.0)]) {
      canvas.drawCircle(
        center,
        ring.$1,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ring.$2
          ..color = rotating
              ? accent.withValues(alpha: 0.30 + pulse * 0.18)
              : connected
              ? accent.withValues(alpha: 0.48)
              : neutral.withValues(alpha: 0.12),
      );
    }

    if (!rotating) return;
    final rect = Rect.fromCircle(center: center, radius: 104);
    canvas.drawArc(
      rect,
      progress * math.pi * 2 - math.pi / 2,
      math.pi * 0.72,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3
        ..color = accent.withValues(alpha: 0.88),
    );
  }

  @override
  bool shouldRepaint(covariant _ConnectionOrbPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.accent != accent ||
      oldDelegate.status != status ||
      oldDelegate.switching != switching ||
      oldDelegate.dark != dark;
}

class NodesScreen extends StatefulWidget {
  const NodesScreen({
    super.key,
    required this.controller,
    required this.onNodeSelected,
  });

  final AppController controller;
  final VoidCallback onNodeSelected;

  @override
  State<NodesScreen> createState() => _NodesScreenState();
}

class _NodesScreenState extends State<NodesScreen> {
  String query = '';

  List<VpnNode> get filtered {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return widget.controller.nodes;
    final values = widget.controller.nodes
        .where((node) => _searchPriority(node, needle) < 2)
        .toList(growable: false);
    values.sort(
      (left, right) => _searchPriority(
        left,
        needle,
      ).compareTo(_searchPriority(right, needle)),
    );
    return values;
  }

  int _searchPriority(VpnNode node, String needle) {
    final fields = [
      node.name,
      node.englishName,
      node.region,
      node.protocol,
      const AppText(false).country(node.region),
      const AppText(true).country(node.region),
    ].map((value) => value.toLowerCase());
    if (fields.any((value) => value.startsWith(needle))) return 0;
    if (fields.any((value) => value.contains(needle))) return 1;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final text = AppText.of(context);
    final groups = <String, List<VpnNode>>{};
    for (final node in filtered) {
      groups.putIfAbsent(node.region, () => []).add(node);
    }
    return Column(
      children: [
        PageHeader(
          title: text.nodes,
          trailing: IconButton(
            onPressed: controller.busy ? null : controller.refresh,
            tooltip: text.refresh,
            icon: controller.busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.refreshCw),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
          child: TextField(
            onChanged: (value) => setState(() => query = value),
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: text.searchNodes,
              prefixIcon: const Icon(LucideIcons.search),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: groups.isEmpty
              ? Center(child: Text(text.noMatchingNodes))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: groups.length,
                  itemBuilder: (context, groupIndex) {
                    final entry = groups.entries.elementAt(groupIndex);
                    return _NodeGroup(
                      region: entry.key,
                      nodes: entry.value,
                      selectedId: controller.selectedNodeId,
                      enabled: controller.canChooseNode,
                      onSelected: (id) {
                        controller.selectNode(id);
                        if (mounted) widget.onNodeSelected();
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _NodeGroup extends StatelessWidget {
  const _NodeGroup({
    required this.region,
    required this.nodes,
    required this.selectedId,
    required this.enabled,
    required this.onSelected,
  });

  final String region;
  final List<VpnNode> nodes;
  final String? selectedId;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
        child: Row(
          children: [
            Text(
              '$region  ${AppText.of(context).country(region)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            Text(
              AppText.of(context).routeCount(nodes.length),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      Container(
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          children: [
            for (var index = 0; index < nodes.length; index++) ...[
              _NodeRow(
                node: nodes[index],
                selected: nodes[index].id == selectedId,
                enabled: enabled,
                onTap: () => onSelected(nodes[index].id),
              ),
              if (index != nodes.length - 1)
                Divider(
                  height: 1,
                  indent: 72,
                  color: Theme.of(context).dividerColor,
                ),
            ],
          ],
        ),
      ),
    ],
  );
}

class _NodeRow extends StatelessWidget {
  const _NodeRow({
    required this.node,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final VpnNode node;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      splashFactory: NoSplash.splashFactory,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: SizedBox(
        height: 72,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              RegionFlag(region: node.region, size: 40),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _nodeName(context, node),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      AppText.of(context).smartAssignedRoute,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? LucideIcons.circleCheckBig : LucideIcons.circle,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline,
                size: 23,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    return Column(
      children: [
        PageHeader(title: text.mine),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    child: Icon(
                      LucideIcons.userRound,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          controller.user?.username ?? '',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        if ((controller.user?.publicId ?? '').isNotEmpty)
                          InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () => _copyPublicId(context),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      '${text.userId}  ${controller.user!.publicId}',
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Icon(
                                    LucideIcons.copy,
                                    size: 14,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Text(
                            text.memberAccount,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              _AccountStat(
                label: text.expiresAt,
                value: controller.membership == null
                    ? '--'
                    : text.date(controller.membership!.expiresAt),
              ),
              _AccountStat(
                label: text.deviceQuota,
                value:
                    '${controller.devices.length}/${controller.membership?.deviceLimit ?? 0}',
              ),
              _AccountStat(
                label: text.onlineLimit,
                value: '${controller.membership?.onlineLimit ?? 0}',
              ),
              const SizedBox(height: 28),
              Text(
                text.loginDevices,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Container(
                color: Theme.of(context).colorScheme.surface,
                child: Column(
                  children: [
                    for (
                      var index = 0;
                      index < controller.devices.length;
                      index++
                    ) ...[
                      _DeviceRow(
                        device: controller.devices[index],
                        isCurrent: controller.isCurrentDevice(
                          controller.devices[index],
                        ),
                        busy:
                            controller.unbindingDeviceId ==
                            controller.devices[index].id,
                        onUnbind: () =>
                            _confirmUnbind(context, controller.devices[index]),
                      ),
                      if (index != controller.devices.length - 1)
                        Divider(
                          height: 1,
                          indent: 54,
                          color: Theme.of(context).dividerColor,
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text(
                text.settings,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _SettingRow(
                icon: LucideIcons.sunMoon,
                title: text.appearance,
                trailing: DropdownButton<ThemeMode>(
                  value: controller.themeMode,
                  underline: const SizedBox.shrink(),
                  onChanged: (value) =>
                      value == null ? null : controller.setThemeMode(value),
                  items: [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text(text.followSystem),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text(text.light),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: Text(text.dark),
                    ),
                  ],
                ),
              ),
              _SettingRow(
                icon: LucideIcons.languages,
                title: text.language,
                trailing: DropdownButton<String>(
                  value: controller.localeCode,
                  underline: const SizedBox.shrink(),
                  onChanged: (value) =>
                      value == null ? null : controller.setLocale(value),
                  items: [
                    DropdownMenuItem(value: 'zh-CN', child: Text(text.chinese)),
                    DropdownMenuItem(
                      value: 'en-US',
                      child: Text(text.englishName),
                    ),
                  ],
                ),
              ),
              _SettingRow(
                icon: LucideIcons.route,
                title: text.smartRules,
                onTap: () => _showRoutingPolicy(context),
              ),
              Divider(
                height: 1,
                indent: 52,
                color: Theme.of(context).dividerColor,
              ),
              _SettingRow(
                icon: LucideIcons.fileText,
                title: text.connectionLog,
                onTap: controller.openConnectionLog,
                trailing: IconButton(
                  onPressed: () => _confirmClearLog(context),
                  tooltip: text.clearConnectionLog,
                  icon: const Icon(LucideIcons.trash2, size: 18),
                ),
              ),
              Divider(
                height: 1,
                indent: 52,
                color: Theme.of(context).dividerColor,
              ),
              _SettingRow(
                icon: LucideIcons.scrollText,
                title: text.terms,
                onTap: () => _openLegalPage(context, _termsUri),
              ),
              Divider(
                height: 1,
                indent: 52,
                color: Theme.of(context).dividerColor,
              ),
              _SettingRow(
                icon: LucideIcons.shieldCheck,
                title: text.privacy,
                onTap: () => _openLegalPage(context, _privacyUri),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: controller.logout,
                icon: const Icon(LucideIcons.logOut),
                label: Text(text.logout),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmUnbind(BuildContext context, BoundDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppText.of(context).unbindDevice),
        content: Text(AppText.of(context).unbindPrompt(device.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppText.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppText.of(context).unbind),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.unbindDevice(device);
  }

  Future<void> _copyPublicId(BuildContext context) async {
    final publicId = controller.user?.publicId ?? '';
    if (publicId.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: publicId));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(AppText.of(context).copied)));
  }

  Future<void> _confirmClearLog(BuildContext context) async {
    final text = AppText.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(text.clearConnectionLog),
        content: Text(text.clearConnectionLogPrompt),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(text.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(text.clear),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.clearConnectionLog();
  }

  void _showRoutingPolicy(BuildContext context) {
    final text = AppText.of(context);
    final policy = controller.routingPolicy;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                text.smartRules,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                text.smartRulesSubtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              if (policy == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(text.policyPending),
                )
              else ...[
                _PolicyRow(
                  label: text.policyRevision,
                  value: 'v${policy.revision}',
                ),
                _PolicyRow(
                  label: text.privateNetworkDirect,
                  value: policy.directPrivateNetworks
                      ? text.direct
                      : text.disabled,
                ),
                _PolicyRow(
                  label: text.chinaDomainDirect,
                  value: policy.cnDomainRules ? text.direct : text.disabled,
                ),
                _PolicyRow(
                  label: text.chinaIpDirect,
                  value: policy.cnIpRules ? text.direct : text.disabled,
                ),
                _PolicyRow(
                  label: text.domainRecognition,
                  value: policy.enableSniff ? text.enabled : text.disabled,
                ),
                _PolicyRow(
                  label: text.ipv6Routing,
                  value: policy.enableIPv6 ? text.enabled : text.disabled,
                ),
                _PolicyRow(label: text.dnsStrategy, value: policy.dnsStrategy),
                _PolicyRow(
                  label: text.customRules,
                  value: text.customRuleCount(policy.customRouteCount),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PolicyRow extends StatelessWidget {
  const _PolicyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 16),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 62,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          ?trailing,
        ],
      ),
    ),
  );
}

class InlineNotice extends StatelessWidget {
  const InlineNotice({super.key, required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Icon(
          LucideIcons.circleAlert,
          size: 18,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
        ),
        IconButton(
          onPressed: onClose,
          tooltip: AppText.of(context).close,
          icon: const Icon(LucideIcons.x, size: 18),
        ),
      ],
    ),
  );
}

class RegionFlag extends StatelessWidget {
  const RegionFlag({super.key, required this.region, required this.size});

  final String region;
  final double size;

  @override
  Widget build(BuildContext context) {
    final normalizedRegion = region.toUpperCase();
    final countryCode = _countryFlagCode(normalizedRegion);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: countryCode == null
          ? Icon(
              LucideIcons.globe2,
              size: size * 0.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            )
          : country_flags.CountryFlag.fromCountryCode(
              countryCode,
              theme: country_flags.ImageTheme(
                width: size * 0.76,
                height: size * 0.76,
                shape: const country_flags.Circle(),
              ),
            ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, this.switching = false});

  final VpnStatus status;
  final bool switching;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final connected = status == VpnStatus.connected;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: connected
                ? FireLinkColors.success
                : Theme.of(context).colorScheme.outline,
          ),
        ),
        const SizedBox(width: 7),
        Text(
          switching
              ? text.switching
              : switch (status) {
                  VpnStatus.connected => text.connected,
                  VpnStatus.connecting => text.connecting,
                  VpnStatus.disconnecting => text.disconnecting,
                  VpnStatus.failed => text.connectionFailed,
                  VpnStatus.disconnected => text.disconnected,
                },
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _TrafficValue extends StatelessWidget {
  const _TrafficValue({
    required this.icon,
    required this.color,
    required this.bytes,
  });

  final IconData icon;
  final Color color;
  final int bytes;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 17, color: color),
      const SizedBox(width: 6),
      Text(
        _rate(bytes),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}

class _MembershipRow extends StatelessWidget {
  const _MembershipRow({required this.membership});

  final Membership? membership;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.badgeCheck, size: 20),
          const SizedBox(width: 10),
          Text(text.member),
          const Spacer(),
          Text(
            membership == null
                ? text.noMembership
                : text.daysRemaining(membership!.remainingDays),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _AccountStat extends StatelessWidget {
  const _AccountStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    height: 54,
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.isCurrent,
    required this.busy,
    required this.onUnbind,
  });

  final BoundDevice device;
  final bool isCurrent;
  final bool busy;
  final VoidCallback onUnbind;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 68,
    child: Row(
      children: [
        const SizedBox(width: 14),
        Icon(
          device.platform == 'ios'
              ? LucideIcons.smartphone
              : LucideIcons.monitor,
          size: 22,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                device.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Row(
                children: [
                  Text(
                    device.platform,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (isCurrent) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      AppText.of(context).currentDevice,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (busy)
          const SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          TextButton(
            onPressed: onUnbind,
            child: Text(AppText.of(context).unbind),
          ),
        const SizedBox(width: 6),
      ],
    ),
  );
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 58,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 12),
              Text(title),
              const Spacer(),
              if (trailing != null)
                trailing!
              else
                const Icon(LucideIcons.chevronRight, size: 18),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 后端沿用 `UK` 展示代码；旗帜资源使用 ISO 3166 的 `GB`。
String? _countryFlagCode(String region) => const {
  'HK': 'HK',
  'JP': 'JP',
  'SG': 'SG',
  'TW': 'TW',
  'KR': 'KR',
  'MY': 'MY',
  'US': 'US',
  'CA': 'CA',
  'UK': 'GB',
  'DE': 'DE',
  'IN': 'IN',
  'FR': 'FR',
  'AU': 'AU',
  'NL': 'NL',
}[region];

/// macOS 宿主以依赖包方式复用页面；iOS/Android 则把 Flutter 模块作为主包构建。
String? get _sharedAssetPackage =>
    defaultTargetPlatform == TargetPlatform.macOS ? 'huolian_app' : null;

String _nodeName(BuildContext context, VpnNode node) {
  final text = AppText.of(context);
  if (text.english && node.englishName.trim().isNotEmpty) {
    return node.englishName;
  }
  return node.name;
}

String _bytes(int value) {
  if (value < 1024) return '$value B';
  if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
  if (value < 1024 * 1024 * 1024) {
    return '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(value / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}

String _rate(int value) => '${_bytes(value)}/s';
