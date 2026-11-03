import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'accounts.dart';
import 'api.dart';
import 'disk_cache.dart';
import 'img_cache.dart';
import 'token_store.dart';

/// 全局状态：服务器地址、登录状态。页面用它判断要不要显示「我的」内容。
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  static const _kBase = 'server_base';
  static const _kMode = 'server_mode';
  static const _kLastGood = 'server_last_good';
  static const _kFont = 'font_scale';
  static const _kTheme = 'theme_mode';
  static const _kHue = 'accent_hue';
  static const _kDensity = 'density';
  static const _kThumbs = 'thumbs';
  static const _kFeedSort = 'feed_sort';
  static const _kAutoUnread = 'auto_unread';
  static const _kStartTab = 'start_tab';
  static const _kLocale = 'locale';

  Map<String, dynamic>? user;
  bool ready = false;

  /// 服务器选路：自动 / 仅 IPv6 / 仅 IPv4 / 手动。
  ServerMode serverMode = ServerMode.auto;

  /// 管理员：未处理举报数。抽屉角标读这里，处理完就地改。
  int reportOpen = 0;

  void setReportOpen(int n) {
    if (reportOpen == n) return;
    reportOpen = n;
    notifyListeners();
  }

  /// 管理员：待看的需求单数。跟举报一样，抽屉角标读这里。
  int featureOpen = 0;

  void setFeatureOpen(int n) {
    if (featureOpen == n) return;
    featureOpen = n;
    notifyListeners();
  }

  /// 本机登录过的账号，最近用的排最前。切换账号只换 token，不重装。
  List<Account> accounts = [];

  Account? get activeAccount {
    final t = Api.token;
    if (t == null) return null;
    for (final a in accounts) {
      if (a.token == t) return a;
    }
    return null;
  }

  bool get loggedIn => user != null;

  int feedVersion = 0;

  /// 未读通知数，底部导航角标用。
  int unread = 0;

  /// 正文字号倍率，0.9 / 1.0 / 1.15 三档。
  final ValueNotifier<double> fontScale = ValueNotifier(1.0);

  /// 主题模式：跟随系统 / 浅色 / 深色。
  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

  /// 列表密度：0 紧凑 / 1 标准 / 2 宽松。
  final ValueNotifier<int> density = ValueNotifier(1);

  /// 时间线里的小图开关。
  final ValueNotifier<bool> thumbs = ValueNotifier(true);

  /// 时间线排序：updated 按最新回复，created 按最新发布。
  final ValueNotifier<String> feedSort = ValueNotifier('created');

  /// 每分钟去问一次未读数。
  final ValueNotifier<bool> autoUnread = ValueNotifier(true);

  /// 启动落在哪个 tab：0 时间线 / 1 板块 / 2 通知 / 3 我的。
  final ValueNotifier<int> startTab = ValueNotifier(0);

  /// 界面语言：'' 跟随系统，'zh' / 'en' 强制。
  final ValueNotifier<String> localeCode = ValueNotifier('');

  /// 主题色色相，0-350。默认 175，就是原来的青绿。
  /// 范围收在 350 而不是 360：色环首尾是同一个颜色。
  static const double minHue = 0;
  static const double maxHue = 350;
  static const double defaultHue = 174;

  final ValueNotifier<double> accentHue = ValueNotifier(defaultHue);

  static const _hueNames = [
    '红',
    '橙红',
    '橙',
    '橙黄',
    '黄',
    '黄绿',
    '草绿',
    '绿',
    '青绿',
    '青',
    '青蓝',
    '蓝',
    '靛蓝',
    '紫蓝',
    '紫',
    '紫红',
    '粉',
    '浅粉',
  ];

  static String hueName(double h) {
    final i = (normalizeHue(h) / 20).floor().clamp(0, _hueNames.length - 1);
    return _hueNames[i];
  }

  static double normalizeHue(double h) {
    if (!h.isFinite) return defaultHue;
    return h.clamp(minHue, maxHue);
  }

  /// 主色，色带的色块和色名圆点都用它。
  Color get accentColor =>
      HSVColor.fromAHSV(1.0, accentHue.value, 1.0, 0.9).toColor();

  Color colorOfHue(double h) =>
      HSVColor.fromAHSV(1.0, normalizeHue(h), 1.0, 0.9).toColor();

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode.value = m;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kTheme, m.index);
  }

  /// 拖动时只在内存里改，松手才落盘。
  void previewHue(double h) {
    final n = normalizeHue(h);
    if (n != accentHue.value) accentHue.value = n;
  }

  Future<void> setAccentHue(double h) async {
    accentHue.value = normalizeHue(h);
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kHue, accentHue.value);
  }

  Future<void> setLocale(String code) async {
    if (code != 'zh' && code != 'en') code = '';
    localeCode.value = code;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLocale, code);
  }

  Future<void> setDensity(int v) async {
    density.value = v.clamp(0, 2);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kDensity, density.value);
  }

  Future<void> setThumbs(bool v) async {
    thumbs.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kThumbs, v);
  }

  Future<void> setFeedSort(String v) async {
    feedSort.value = v == 'created' ? 'created' : 'updated';
    final p = await SharedPreferences.getInstance();
    await p.setString(_kFeedSort, feedSort.value);
  }

  Future<void> setAutoUnread(bool v) async {
    autoUnread.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAutoUnread, v);
  }

  Future<void> setStartTab(int v) async {
    startTab.value = v.clamp(0, 3);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kStartTab, startTab.value);
  }

  Future<void> setFontScale(double v) async {
    fontScale.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kFont, v);
  }

  /// 发完帖子让时间线自己刷新。
  void bumpFeed() {
    feedVersion++;
    notifyListeners();
  }

  Future<void> refreshUnread() async {
    if (!loggedIn) {
      if (unread != 0) {
        unread = 0;
        notifyListeners();
      }
      return;
    }
    try {
      final d = await Api.get('/notifications');
      final n = (d['unread'] ?? 0) as int;
      if (n != unread) {
        unread = n;
        notifyListeners();
      }
    } catch (_) {
      // 网络抖一下不清零，等下次
    }
  }

  /// 只读本地设置，不发任何网络请求。
  /// main() 里在 runApp **之前** await 它 —— 否则第一帧会先按默认色相和
  /// 默认明暗渲染，读完盘再跳一次，看着就是启动时闪一下。
  Future<void> loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    Api.token = await TokenStore.read();
    accounts = await AccountStore.read();
    fontScale.value = p.getDouble(_kFont) ?? 1.0;
    accentHue.value = normalizeHue(p.getDouble(_kHue) ?? defaultHue);
    density.value = (p.getInt(_kDensity) ?? 1).clamp(0, 2);
    thumbs.value = p.getBool(_kThumbs) ?? true;
    final fs = p.getString(_kFeedSort);
    if (fs == 'updated' || fs == 'created') feedSort.value = fs!;
    autoUnread.value = p.getBool(_kAutoUnread) ?? true;
    startTab.value = (p.getInt(_kStartTab) ?? 0).clamp(0, 3);
    final lc = p.getString(_kLocale) ?? '';
    localeCode.value = (lc == 'zh' || lc == 'en') ? lc : '';
    final ti = p.getInt(_kTheme);
    if (ti != null && ti >= 0 && ti < ThemeMode.values.length) {
      themeMode.value = ThemeMode.values[ti];
    }
    // 服务器选路：默认自动（先 IPv6，不通再 IPv4），判断全在手机上做。
    final m = p.getString(_kMode);
    serverMode = ServerMode.values.firstWhere(
      (e) => e.name == m,
      orElse: () => ServerMode.auto,
    );
    final savedBase = p.getString(_kBase) ?? '';
    Api.mode = serverMode;
    Api.lastGood = p.getString(_kLastGood) ?? '';
    switch (serverMode) {
      case ServerMode.ipv6:
        Api.base = Api.chIpv6;
      case ServerMode.ipv4:
        Api.base = Api.chIpv4;
      case ServerMode.manual:
        Api.base = savedBase.isNotEmpty ? savedBase : Api.chIpv4;
      case ServerMode.auto:
        Api.base = Api.lastGood.isNotEmpty ? Api.lastGood : Api.chIpv6;
    }
    // 换通道时把新地址记下来，下次冷启动先用它，省一轮探路。
    Api.onChannelChanged = (b) async {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kLastGood, b);
      notifyListeners();
    };
    ready = true;
  }

  /// 本地设置已在 loadPrefs 里读完，这里只补网络那部分（恢复登录态）。
  Future<void> init() async {
    if (!ready) {
      try {
        await loadPrefs();
      } catch (_) {
        // 读不出来就按默认值走，别把后续恢复登录态也一起卡死。
        ready = true;
      }
    }
    notifyListeners();
    if (Api.configured) {
      // 刚启动时网络往往还没起来，一次失败就显示未登录，用户会以为掉线了。
      // 令牌还在就再试两次，真 401 会被 refreshUser 清掉，循环自然结束。
      for (var i = 0; i < 3; i++) {
        await refreshUser();
        if (user != null || Api.token == null) break;
        await Future<void>.delayed(Duration(milliseconds: 400 * (i + 1)));
      }
    }
  }

  /// 手填地址：顺手切成手动档。
  Future<void> setBase(String base) async {
    var b = base.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    if (b.isNotEmpty && !b.startsWith('http')) b = 'http://$b';
    Api.base = b;
    serverMode = ServerMode.manual;
    Api.mode = ServerMode.manual;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kBase, b);
    await p.setString(_kMode, ServerMode.manual.name);
    notifyListeners();
  }

  /// 切换选路档位。
  ///
  /// 单通道（仅 IPv4 / 仅 IPv6）直接定死地址，不探测，点了就生效；
  /// 自动档在手机上探一遍：先 IPv6，通了就用，不通再走 IPv4。
  /// 探测失败时退回上次连通的地址，别让用户面对一个死地址。
  Future<void> setServerMode(ServerMode m) async {
    serverMode = m;
    Api.mode = m;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kMode, m.name);
    switch (m) {
      case ServerMode.ipv6:
        Api.base = Api.chIpv6;
      case ServerMode.ipv4:
        Api.base = Api.chIpv4;
      case ServerMode.manual:
        final saved = p.getString(_kBase) ?? '';
        Api.base = saved.isNotEmpty ? saved : Api.chIpv4;
      case ServerMode.auto:
        Api.base = Api.lastGood.isNotEmpty ? Api.lastGood : Api.chIpv6;
        final b = await Api.probe();
        if (b != null) {
          Api.base = b;
          await p.setString(_kLastGood, b);
        }
    }
    notifyListeners();
  }

  /// 外部改了资料后同步到内存里（比如编辑资料页）。
  void applyUser(Map<String, dynamic> u) {
    user = u;
    notifyListeners();
  }

  Future<void> refreshUser() async {
    // 记下发起时的 token：如果请求在飞的时候用户登录/退出过，
    // 晚到的响应会把新状态覆盖掉（启动时那次 /me 尤其容易撞上登录）。
    final tok = Api.token;
    try {
      final d = await Api.get('/me');
      if (Api.token != tok) return;
      user = d['user'] as Map<String, dynamic>?;
      if (user == null) {
        Api.token = null;
        _applyCacheScope(null);
      } else {
        _applyCacheScope(user!['id'] as int?);
        await _syncAccount(tok!, user!);
      }
    } on ApiException catch (e) {
      if (Api.token != tok) return;
      // 网络不通不代表登录失效，别把人踢下线；只有明确 401 才清。
      if (e.status == 401) {
        user = null;
        Api.token = null;
        _applyCacheScope(null);
      }
    }
    notifyListeners();
  }

  /// 缓存按账号分区。换号就换目录，统计和清缓存只认当前这份。
  String _scope = 'guest';

  void _applyCacheScope(int? uid) {
    final s = uid == null ? 'guest' : 'u$uid';
    if (s == _scope) return;
    _scope = s;
    DiskCache.setScope(s);
    ImgCache.setScope(s);
    // 内存里的图也放掉，否则切完还挂着上一个人的头像。
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  }

  Future<void> _saveToken(String token, Map<String, dynamic> u) async {
    Api.token = token;
    user = u;
    await TokenStore.write(token);
    await _syncAccount(token, u);
    notifyListeners();
  }

  /// 把当前账号的资料写进列表：同一个 id 就更新，没有就插到最前面。
  Future<void> _syncAccount(String token, Map<String, dynamic> u) async {
    final a = Account.fromUser(token, u);
    if (a.id == 0) return;
    final rest = accounts.where((x) => x.id != a.id).toList();
    final next = [a, ...rest];
    final same =
        next.length == accounts.length &&
        next.first.token == accounts.first.token &&
        next.first.nickname == accounts.first.nickname &&
        next.first.avatar == accounts.first.avatar &&
        next.first.handle == accounts.first.handle;
    accounts = next;
    if (!same) await AccountStore.write(accounts);
  }

  /// 切到另一个账号。返回 false 表示那个令牌已经失效、账号被摘掉了。
  Future<bool> switchAccount(Account a) async {
    if (a.token == Api.token) return true;
    Api.token = a.token;
    user = null;
    // 先挪到 guest，别把新账号的响应写进上一个账号的目录。
    _applyCacheScope(null);
    notifyListeners();
    await TokenStore.write(a.token);
    await refreshUser();
    if (user == null) {
      Api.token = null;
      accounts = accounts.where((x) => x.id != a.id).toList();
      await AccountStore.write(accounts);
      final next = accounts.isNotEmpty ? accounts.first : null;
      if (next != null) {
        // 失效的那个摘掉后，顺手落到下一个账号上
        Api.token = next.token;
        await TokenStore.write(next.token);
        await refreshUser();
      } else {
        await TokenStore.clear();
      }
      notifyListeners();
      return false;
    }
    feedVersion++;
    notifyListeners();
    return true;
  }

  /// 从列表里移除账号。移除的是当前账号时就退到下一个。
  Future<void> removeAccount(Account a) async {
    accounts = accounts.where((x) => x.id != a.id).toList();
    await AccountStore.write(accounts);
    if (Api.token == a.token) {
      Api.token = null;
      user = null;
      if (accounts.isNotEmpty) {
        await switchAccount(accounts.first);
      } else {
        await TokenStore.clear();
      }
    }
    notifyListeners();
  }

  Future<void> login(String name, String password) async {
    final d = await Api.post('/login', {'name': name, 'password': password});
    await _saveToken(d['token'] as String, d['user'] as Map<String, dynamic>);
  }

  Future<void> register(
    String name,
    String password,
    String email,
    String code,
  ) async {
    final d = await Api.post('/register', {
      'name': name,
      'password': password,
      'email': email,
      'code': code,
    });
    await _saveToken(d['token'] as String, d['user'] as Map<String, dynamic>);
  }

  /// 注册前先发验证码。返回冷却秒数。
  Future<int> requestCode(String email) async {
    final d = await Api.post('/register/code', {'email': email});
    return (d['cooldown'] as num?)?.toInt() ?? 60;
  }

  /// 找回密码：发重置验证码。返回冷却秒数。
  Future<int> requestResetCode(String email) async {
    final d = await Api.post('/password/code', {'email': email});
    return (d['cooldown'] as num?)?.toInt() ?? 60;
  }

  /// 找回密码：验证码换新密码，成功直接登录。
  Future<void> resetPassword(String email, String code, String password) async {
    final d = await Api.post('/password/reset', {
      'email': email,
      'code': code,
      'password': password,
    });
    await _saveToken(d['token'] as String, d['user'] as Map<String, dynamic>);
  }

  /// 绑定/换绑邮箱：先发码。返回冷却秒数。
  Future<int> requestBindCode(String email) async {
    final d = await Api.post('/account/email/code', {'email': email});
    return (d['cooldown'] as num?)?.toInt() ?? 60;
  }

  /// 绑定/换绑邮箱：验证码校验通过就生效。
  Future<void> bindEmail(String email, String code) async {
    await Api.post('/account/email/bind', {'email': email, 'code': code});
    await refreshUser();
  }

  /// 管理员：查账号。q 为空就是全部。
  Future<List<Map<String, dynamic>>> adminUsers(String q) async {
    final d = await Api.get('/admin/users', query: {'q': q});
    return (d['items'] as List).cast<Map<String, dynamic>>();
  }

  /// 管理员：把某个账号的密码重置成随机临时密码，返回一次，只显示这一回。
  Future<Map<String, dynamic>> adminResetPw(int uid) async {
    final d = await Api.post('/admin/user/$uid/reset_pw', {});
    return (d as Map).cast<String, dynamic>();
  }

  /// 用设置页复制出来的凭证恢复登录。
  Future<bool> useToken(String tok) async {
    final t = tok.trim();
    if (t.isEmpty) return false;
    Api.token = t;
    await refreshUser();
    if (user == null) {
      Api.token = null;
      return false;
    }
    await TokenStore.write(t);
    return true;
  }

  Future<void> logout() async {
    Api.token = null;
    user = null;
    _applyCacheScope(null);
    await TokenStore.clear();
    notifyListeners();
  }
}
