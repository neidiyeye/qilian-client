import 'package:flutter/widgets.dart';

/// 启连加速器的轻量文案层。语言由用户手动选择并持久化，
/// 不会在每次登录时被账号默认语言意外覆盖。
final class AppText {
  const AppText(this.english);

  factory AppText.fromCode(String code) => AppText(code == 'en-US');

  static AppText of(BuildContext context) =>
      AppText(Localizations.localeOf(context).languageCode == 'en');

  final bool english;

  String pick(String zh, String en) => english ? en : zh;

  String get brandName => pick('启连加速器', 'Qilian');
  String get legalOpenFailed =>
      pick('页面暂时无法打开，请稍后重试', 'Unable to open this page. Try again later.');
  String get welcomeBack => pick('欢迎回来', 'Welcome back');
  String get loginSubtitle => pick('使用会员账号登录', 'Sign in with your account');
  String get account => pick('账号', 'Username');
  String get password => pick('密码', 'Password');
  String get showPassword => pick('显示密码', 'Show password');
  String get hidePassword => pick('隐藏密码', 'Hide password');
  String get rememberCredentials =>
      pick('记住账号和密码', 'Remember username and password');
  String get login => pick('登录', 'Sign in');
  String get freeRegister => pick('没有账号？免费注册', 'No account? Register free');
  String get loginAgreement =>
      pick('登录即表示你已阅读并同意', 'By signing in, you agree to');
  String get terms => pick('服务条款', 'Terms of Service');
  String get privacy => pick('隐私政策', 'Privacy Policy');
  String get chinese => '简体中文';
  String get englishName => 'English';
  String get usernameValidation => pick(
    '账号需为4–64位，不能包含空格',
    'Username must be 4–64 characters with no spaces',
  );
  String get passwordValidation =>
      pick('密码至少6位，数字、字母或符号均可', 'Password must be at least 6 characters');
  String get registerTitle => pick('注册免费账号', 'Create free account');
  String get createAccount => pick('创建账号', 'Create account');
  String get freeVersionNote => pick(
    '首版免费使用，不包含购买或自动续费',
    'Free to use in this version. No purchases or auto-renewal.',
  );
  String get usernameHint =>
      pick('至少4位，不能包含空格', 'At least 4 characters, no spaces');
  String get passwordHint => pick('至少6位，组成不限', 'At least 6 characters');
  String get register => pick('免费注册', 'Register free');
  String get registerAgreement =>
      pick('注册即表示你已阅读并同意', 'By registering, you agree to');
  String get connect => pick('连接', 'Connect');
  String get nodes => pick('节点', 'Locations');
  String get mine => pick('我的', 'Account');
  String get currentRoute => pick('当前线路', 'Current location');
  String get chooseNode => pick('选择节点', 'Choose location');
  String get notSelected => pick('尚未选择', 'Not selected');
  String get smartAllocation => pick('智能分配', 'Smart allocation');
  String get connectionMode => pick('连接模式', 'Connection mode');
  String get smartMode => pick('智能模式', 'Smart mode');
  String get globalMode => pick('全局模式', 'Global mode');
  String get switching => pick('正在切换', 'Switching');
  String get connecting => pick('正在连接', 'Connecting');
  String get accelerated => pick('已加速', 'Connected');
  String get disconnecting => pick('正在断开', 'Disconnecting');
  String get reconnect => pick('重新连接', 'Reconnect');
  String get start => pick('开始加速', 'Connect');
  String get disconnectHint => pick('双击断开 VPN', 'Double tap to disconnect VPN');
  String get connectHint => pick('双击连接 VPN', 'Double tap to connect VPN');
  String get searchNodes => pick('搜索国家或线路', 'Search country or location');
  String get noMatchingNodes => pick('没有匹配的节点', 'No matching locations');
  String routeCount(int count) => pick('$count 条线路', '$count locations');
  String get smartAssignedRoute => pick('智能分配线路', 'Smart assigned route');
  String get memberAccount => pick('会员账号', 'Member account');
  String get expiresAt => pick('到期时间', 'Expires');
  String get deviceQuota => pick('设备名额', 'Devices');
  String get onlineLimit => pick('同时在线', 'Online limit');
  String get loginDevices => pick('登录设备', 'Signed-in devices');
  String get settings => pick('设置', 'Settings');
  String get appearance => pick('外观', 'Appearance');
  String get followSystem => pick('跟随系统', 'System');
  String get light => pick('浅色', 'Light');
  String get dark => pick('深色', 'Dark');
  String get language => pick('语言', 'Language');
  String get connectionLog => pick('连接日志', 'Connection log');
  String get logout => pick('退出登录', 'Sign out');
  String get unbindDevice => pick('解绑设备', 'Unbind device');
  String unbindPrompt(String name) => pick(
    '确定解绑“$name”吗？该设备需要重新登录。',
    'Unbind "$name"? This device will need to sign in again.',
  );
  String get cancel => pick('取消', 'Cancel');
  String get unbind => pick('解绑', 'Unbind');
  String get close => pick('关闭', 'Close');
  String get connected => pick('已连接', 'Connected');
  String get connectionFailed => pick('连接失败', 'Connection failed');
  String get disconnected => pick('未连接', 'Disconnected');
  String get member => pick('会员', 'Membership');
  String get noMembership => pick('暂无有效会员', 'No active membership');
  String daysRemaining(int days) => pick('$days 天后到期', 'Expires in $days days');

  String country(String code) =>
      (english
          ? const {
              'HK': 'Hong Kong',
              'JP': 'Japan',
              'SG': 'Singapore',
              'TW': 'Taiwan',
              'KR': 'South Korea',
              'MY': 'Malaysia',
              'US': 'United States',
              'CA': 'Canada',
              'UK': 'United Kingdom',
              'DE': 'Germany',
              'IN': 'India',
              'FR': 'France',
              'AU': 'Australia',
              'NL': 'Netherlands',
            }
          : const {
              'HK': '香港',
              'JP': '日本',
              'SG': '新加坡',
              'TW': '台湾',
              'KR': '韩国',
              'MY': '马来西亚',
              'US': '美国',
              'CA': '加拿大',
              'UK': '英国',
              'DE': '德国',
              'IN': '印度',
              'FR': '法国',
              'AU': '澳大利亚',
              'NL': '荷兰',
            })[code] ??
      code;

  String date(DateTime value) => english
      ? '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}'
      : '${value.year}年${value.month}月${value.day}日';

  String error(String code) =>
      {
        'NETWORK_ERROR': pick(
          '网络连接失败，请检查网络后重试',
          'Network error. Check your connection and try again.',
        ),
        'INVALID_TOKEN': pick(
          '登录已失效，请重新登录',
          'Your session has expired. Sign in again.',
        ),
        'UNAUTHORIZED': pick('账号或密码错误', 'Incorrect username or password.'),
        'USER_BANNED': pick('账号已停用', 'This account is disabled.'),
        'USERNAME_EXISTS': pick(
          '该账号名已被使用，请换一个',
          'That username is already in use.',
        ),
        'DEVICE_ALREADY_REGISTERED': pick(
          '这台设备已注册过免费账号，请直接登录',
          'This device already registered a free account. Please sign in.',
        ),
        'MEMBERSHIP_EXPIRED': pick('会员已到期', 'Membership has expired.'),
        'DEVICE_LIMIT_REACHED': pick('登录设备已达上限', 'Device limit reached.'),
        'ONLINE_LIMIT_REACHED': pick(
          '同时在线设备已达上限',
          'Online device limit reached.',
        ),
        'NODE_UNAVAILABLE': pick(
          '当前线路暂不可用',
          'This location is temporarily unavailable.',
        ),
        'CONFIG_GENERATE_FAILED': pick(
          '节点配置不可用',
          'The location configuration is unavailable.',
        ),
        'CONNECTIVITY_PROBE_FAILED': pick(
          '线路已建立，但无法访问公网',
          'Connected, but internet access could not be verified.',
        ),
        'NATIVE_VPN_TIMEOUT': pick('系统 VPN 启动超时', 'VPN startup timed out.'),
        'NATIVE_VPN_START_FAILED': pick('系统 VPN 启动失败', 'VPN failed to start.'),
        'IOS_VPN_PERMISSION_DENIED': pick(
          'VPN 权限未生效，请重新安装并允许 VPN 配置',
          'VPN permission is unavailable. Reinstall and allow the VPN configuration.',
        ),
        'SING_BOX_IOS_CORE_MISSING': pick(
          '当前安装包缺少 VPN 核心',
          'This build is missing the VPN core.',
        ),
        'CONNECTION_LOG_EMPTY': pick('当前还没有连接日志', 'No connection logs yet.'),
      }[code] ??
      (code.contains('CONNECTIVITY')
          ? pick(
              '当前线路无法访问公网，请更换线路',
              'This location cannot reach the internet. Choose another one.',
            )
          : pick('操作失败，请稍后重试', 'Something went wrong. Try again later.'));
}
