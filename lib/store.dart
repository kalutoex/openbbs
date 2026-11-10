import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'accounts.dart';
import 'api.dart';
import 'disk_cache.dart';
import 'img_cache.dart';
import 'site_config.dart';
import 'site_meta.dart';
import 'site_store.dart';
import 'sites.dart';
import 'token_store.dart';

import '../l10n/l10n.dart';

/// 全局状态：服务器地址、登录状态。页面用它判断要不要显示「我的」内容。
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  static const _kBase = 'server_base';
  static const _kLastGood = 'server_last_good';
  static const _kActive = 'active_site';
  static const _kFont = 'font_scale';
  static const _kTheme = 'theme_mode';
  static const _kHue = 'accent_hue';
  static const _kDyn = 'use_dynamic_color';
  static const _kDensity = 'density';
  static const _kThumbs = 'thumbs';
  static const _kFeedSort = 'feed_sort';
  static const _kAutoUnread = 'auto_unread';
  static const _kSysNotify = 'sys_notify';
  static const _kStartTab = 'start_tab';
  static const _kHueCards = 'hue_cards';

  /// 底部 tab 表变过（板块改成站点），老键里存的值按旧表解释，新值单开一个键。
  static const _kStartTabV2 = 'start_tab_v2';
  static const _kLocale = 'locale';

  Map<String, dynamic>? user;
  bool ready = false;

  /// 站点自述。null = 还没读到或对方不支持，界面别据此报错。
  SiteMeta? siteMeta;

  void setSiteMeta(SiteMeta? m) {
    siteMeta = m;
    notifyListeners();
  }

  /// 本机站点表。第 4 段起所有网络请求都在这张表里选一座站。
  List<SiteEntry> sites = [];

  /// 当前在用的那座站（[SiteEntry.key]）。
  String activeKey = '';

  /// 当前账号被服务端封了。全应用只显示封禁页，直到退出登录。
  bool banned = false;

  SiteEntry? get activeSite {
    for (final s in sites) {
      if (s.key == activeKey) return s;
    }
    return sites.isEmpty ? null : sites.first;
  }

  /// 主站：出厂预置的那座（时间线）。
  ///
  /// 发帖只能发到主站或小站，主站就是这里认出来的那行；一行都不匹配
  /// （自编译、显式清空 SERVERS 的包）就退回登录站，保证总有得发。
  SiteEntry? get masterSite {
    for (final s in sites) {
      if (s.isHome) return s;
    }
    return loginSite;
  }

  /// 登录站：注册、登录、找回密码只发这里。
  SiteEntry? get loginSite {
    for (final s in sites) {
      if (s.master) return s;
    }
    return activeSite;
  }

  /// 登录站的全部入口，v6 优先；没有站点就是空。
  List<String> get loginUrls => loginSite?.orderedUrls ?? const [];

  void markBanned() {
    if (banned) return;
    banned = true;
    notifyListeners();
  }

  void clearBanned() {
    if (!banned) return;
    banned = false;
    notifyListeners();
  }

  /// 服务端说这个令牌不认了。清干净，别留着继续发请求。
  ///
  /// 走的是同步路径（接口层是从解析响应的位置回调过来的），落盘让它自己跑。
  void _tokenExpired() {
    if (Api.token == null || Api.token!.isEmpty) return;
    Api.token = null;
    user = null;
    _applyCacheScope(null);
    TokenStore.clear();
    notifyListeners();
  }

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

  /// 当前登录的人。没登录是 0。
  ///
  /// 需要按人分开存的东西（上传队列、草稿、游标）都拿它当作用域。
  int get uid => (user?['id'] as num?)?.toInt() ?? 0;

  int feedVersion = 0;

  /// 未读通知数，底部导航角标用。
  int unread = 0;

  /// 未读私信数。底部角标跟通知合起来显示，抽屉里单独显示。
  int dmUnread = 0;

  Future<void> refreshDmUnread() async {
    if (!loggedIn) {
      if (dmUnread != 0) {
        dmUnread = 0;
        notifyListeners();
      }
      return;
    }
    try {
      final d = await Api.get('/dm/unread');
      final n = (d['total'] ?? 0) as int;
      if (n != dmUnread) {
        dmUnread = n;
        notifyListeners();
      }
    } catch (_) {
      // 网络抖一下不清零
    }
  }

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

  /// 有新消息时弹系统通知。角标不受这个开关影响，照常更新。
  final ValueNotifier<bool> sysNotify = ValueNotifier(true);

  /// 启动落在哪个 tab：0 时间线 / 1 站点 / 2 通知 / 3 我的。
  final ValueNotifier<int> startTab = ValueNotifier(0);

  /// 界面语言：'' 跟随系统，'zh' / 'en' 强制。
  final ValueNotifier<String> localeCode = ValueNotifier('');

  /// 主题色色相，0-350。默认 175，就是原来的青绿。
  /// 范围收在 350 而不是 360：色环首尾是同一个颜色。
  static const double minHue = 0;
  static const double maxHue = 350;
  static const double defaultHue = 174;

  final ValueNotifier<double> accentHue = ValueNotifier(defaultHue);

  /// 卡片底色是否跟着作者的主题色走。
  /// 默认关：默认是干净的统一底色，想要「一眼认出谁发的」可以在设置里打开。
  /// 头像外圈不受这个开关影响，那个一直在。
  final ValueNotifier<bool> hueCards = ValueNotifier(false);

  Future<void> setHueCards(bool v) async {
    hueCards.value = v;
    final x = await SharedPreferences.getInstance();
    await x.setBool(_kHueCards, v);
  }

  /// 跟随系统壁纸取色（Android 12+ / 网页版不支持）。
  /// 开着时主题色由系统给，色相滑块不起作用。
  final ValueNotifier<bool> useDynamicColor = ValueNotifier(false);

  Future<void> setUseDynamicColor(bool on) async {
    useDynamicColor.value = on;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kDyn, on);
  }

  static List<String> get _hueNames => [
    Lc.current.hueRed,
    Lc.current.hueOrangeRed,
    Lc.current.hueOrange,
    Lc.current.hueAmber,
    Lc.current.hueYellow,
    Lc.current.hueLime,
    Lc.current.hueGrass,
    Lc.current.hueGreen,
    Lc.current.hueTeal,
    Lc.current.hueCyan,
    Lc.current.hueAzure,
    Lc.current.hueBlue,
    Lc.current.hueIndigo,
    Lc.current.hueViolet,
    Lc.current.huePurple,
    Lc.current.hueMagenta,
    Lc.current.huePink,
    Lc.current.huePinkLight,
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
    // 主题色也是身份色：登录了就落一份到账号上，别人看你才认得出。
    // 传不上去也不挡本机的改动，下次再设的时候补。
    if (Api.token == null) return;
    try {
      final d = await Api.patch('/me', {'hue': accentHue.value.round()});
      final u = d is Map ? d['user'] : null;
      if (u is Map<String, dynamic>) {
        user = u;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// 账号上的主题色是权威的：换设备登录、别人改了，这里跟着走。
  /// 账号还没有（老账号、或者从没登过）就把本机这个推上去，一个会话推一次。
  bool _huePushed = false;

  Future<void> _applyHue(Map<String, dynamic> u) async {
    final h = u['hue'];
    if (h is int && h >= 0) {
      final d = normalizeHue(h.toDouble());
      if ((accentHue.value - d).abs() >= 0.5) {
        accentHue.value = d;
        final p = await SharedPreferences.getInstance();
        await p.setDouble(_kHue, d);
      }
      return;
    }
    if (Api.token == null || _huePushed) return;
    _huePushed = true;
    try {
      await Api.patch('/me', {'hue': accentHue.value.round()});
    } catch (_) {
      _huePushed = false;
    }
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

  Future<void> setSysNotify(bool v) async {
    sysNotify.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kSysNotify, v);
  }

  Future<void> setStartTab(int v) async {
    startTab.value = v.clamp(0, 3);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kStartTabV2, startTab.value);
  }

  /// 读启动 tab。只存过老键的，按旧表（1 通知、2 我的）换算成新表。
  int _startTabOf(SharedPreferences p) {
    final v2 = p.getInt(_kStartTabV2);
    if (v2 != null) return v2.clamp(0, 3);
    return switch (p.getInt(_kStartTab) ?? 0) {
      1 => 2,
      2 => 3,
      _ => 0,
    };
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

  /// 轮询回来的角标数，直接落到界面，省一次 /notifications 全量拉取。
  void setBadges({required int dm, required int notice}) {
    var changed = false;
    if (notice != unread) {
      unread = notice;
      changed = true;
    }
    if (dm != dmUnread) {
      dmUnread = dm;
      changed = true;
    }
    if (changed) notifyListeners();
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
    await refreshDmUnread();
  }

  /// 只读本地设置，不发任何网络请求。
  ///
  /// 调用方是 `_boot()`，在 runApp **之后**跑（`main.dart` 里是
  /// `runApp(...); unawaited(_boot());`）。所以启动会有一帧默认色相、默认
  /// 明暗，读完盘再换过去——这是有意的取舍：读盘卡住时界面已经在屏幕上了，
  /// 不会白屏。别改回 runApp 之前 await。
  /// 冷启动把每座站的入口实探一遍。
  ///
  /// 入口通不通只有当场测了才算数——存下来的旧结果会骗人。
  /// 探完 notifyListeners，站点管理里那排点自己就亮了，不用用户去点测速。
  Future<void> probeSites() async {
    // 并发探，不逐站排队。三座站 × 两条入口串起来最坏要 39 秒，首屏的
    // feed 全程在跟它抢连接，弱网下就是「首页一直转，站点页倒是早亮了」。
    await Future.wait([
      for (final s in List<SiteEntry>.of(sites)) _probeOne(s),
    ]);
  }

  Future<void> _probeOne(SiteEntry s) async {
    try {
      final rep = await Api.probeReport(s.orderedUrls);
      s.epStatus
        ..clear()
        ..addAll(rep);
      // 探路不带耗时，旧数字留着会骗人。
      s.epMs.clear();
      String? ok;
      for (final e in rep.entries) {
        if (e.value) {
          ok = e.key;
          break;
        }
      }
      s.reachable = ok != null;
      if (ok != null) s.lastOk = ok;
      notifyListeners();
    } catch (_) {
      // 一座站探不动不该拖住别的站，更不该拖住启动。
    }
  }

  Future<void> loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    Api.token = await TokenStore.read();
    accounts = await AccountStore.read();
    fontScale.value = p.getDouble(_kFont) ?? 1.0;
    accentHue.value = normalizeHue(p.getDouble(_kHue) ?? defaultHue);
    useDynamicColor.value = p.getBool(_kDyn) ?? false;
    hueCards.value = p.getBool(_kHueCards) ?? false;
    density.value = (p.getInt(_kDensity) ?? 1).clamp(0, 2);
    thumbs.value = p.getBool(_kThumbs) ?? true;
    final fs = p.getString(_kFeedSort);
    if (fs == 'updated' || fs == 'created') feedSort.value = fs!;
    autoUnread.value = p.getBool(_kAutoUnread) ?? true;
    sysNotify.value = p.getBool(_kSysNotify) ?? true;
    startTab.value = _startTabOf(p);
    final lc = p.getString(_kLocale) ?? '';
    localeCode.value = (lc == 'zh' || lc == 'en') ? lc : '';
    final ti = p.getInt(_kTheme);
    if (ti != null && ti >= 0 && ti < ThemeMode.values.length) {
      themeMode.value = ThemeMode.values[ti];
    }
    // 站点表：第 4 段起地址不再是一个字符串。
    // 出厂站点每次开机都并进来——「时间线」不靠上一版存过什么。
    // 老版本只存 server_base 的，也在这里并成一座站，不丢用户填过的地址。
    final saved = await SiteStore.read();
    var table = ensureBuiltin(saved);
    if (table.isEmpty) {
      final seed = <String>[];
      final old = normalizeUrl(p.getString(_kBase) ?? '');
      if (old.isNotEmpty) seed.add(old);
      for (final u in SiteConfig.servers) {
        final v = normalizeUrl(u);
        if (v.isNotEmpty && !seed.contains(v)) seed.add(v);
      }
      if (kIsWeb) {
        final o = normalizeUrl(Uri.base.origin);
        if (o.isNotEmpty && !seed.contains(o)) seed.add(o);
      }
      if (seed.isNotEmpty) {
        table = [
          SiteEntry(urls: seed, name: SiteConfig.siteName, master: true),
        ];
      }
    }
    // 并表结果和盘上不一样才回写，别每次冷启动都写一遍闪存。
    if (!_sameTable(saved, table)) await SiteStore.write(table);
    sites = table;
    activeKey = p.getString(_kActive) ?? '';
    if (sites.isEmpty) {
      activeKey = '';
      Api.setEndpoints(const []);
      Api.base = normalizeUrl(Api.defaultBase);
    } else {
      if (sites.every((s) => s.key != activeKey)) activeKey = sites.first.key;
      final a = activeSite!;
      final urls = a.orderedUrls;
      final pref = a.lastOk ?? normalizeUrl(p.getString(_kLastGood) ?? '');
      Api.setEndpoints(urls);
      // 上次连通的入口优先，其次第一条（v6 优先排序后的第一条）。
      Api.base = urls.contains(pref) ? pref : (urls.isEmpty ? '' : urls.first);
    }
    // 换通道时把新地址记下来，下次冷启动先用它，省一轮探路。
    Api.onChannelChanged = (b) async {
      final a = activeSite;
      if (a != null) a.lastOk = b;
      final p = await SharedPreferences.getInstance();
      await p.setString(_kLastGood, b);
      notifyListeners();
    };
    // 接口层回「账号已被封禁」就切全局封禁页。
    Api.onBanned = markBanned;
    // 令牌失效就清本地登录状态：不 then 自动弹登录页，只保证不再拿废令牌
    // 到处撞「请先登录」。下次发帖一类要身份的操作会自己引到登录页。
    Api.onUnauthorized = _tokenExpired;
    ready = true;
  }

  /// 冷启动读到自述后并进当前站：入口取并集，名字和 id 补齐。
  Future<void> applySiteMeta(SiteMeta m) async {
    final s = activeSite;
    if (s == null) return;
    final before = s.urls.join('|');
    s.applyMeta(m, master: m.master);
    if (s.urls.join('|') == before) return;
    Api.setEndpoints(s.orderedUrls);
    if (!s.orderedUrls.contains(Api.base) && s.orderedUrls.isNotEmpty) {
      Api.base = s.orderedUrls.first;
    }
    await SiteStore.write(sites);
    notifyListeners();
  }

  /// 两张站点表内容是否一致（只比落盘字段）。
  static bool _sameTable(List<SiteEntry> a, List<SiteEntry> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.id != y.id || x.name != y.name || x.master != y.master) {
        return false;
      }
      if (x.urls.length != y.urls.length) return false;
      for (var j = 0; j < x.urls.length; j++) {
        if (x.urls[j] != y.urls[j]) return false;
      }
    }
    return true;
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

  /// 手填地址：并进站点表并切过去。设置页/首次启动用。
  /// 返回连不连得上——连不上也照样入表（标灰），让用户能改地址再试。
  Future<bool> setBase(String base) async {
    final u = normalizeUrl(base);
    if (u.isEmpty) return false;
    final hit = sites.indexWhere((s) => s.urls.contains(u));
    if (hit >= 0) {
      return switchSite(sites[hit]);
    }
    sites = mergeSites(sites, [
      SiteEntry(urls: [u]),
    ]);
    final s = sites.firstWhere((x) => x.urls.contains(u));
    await SiteStore.write(sites);
    return switchSite(s);
  }

  /// 切到另一座站。
  ///
  /// 连不上也切（标灰、不弹窗），返回 false 让界面自己决定怎么说。
  /// 登录态不随站点走：token 全局共用，换站只重新拉一次 /me。
  Future<bool> switchSite(SiteEntry s) async {
    activeKey = s.key;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kActive, activeKey);
    final urls = s.orderedUrls;
    Api.setEndpoints(urls);
    final pref = s.lastOk ?? '';
    Api.base = urls.contains(pref) ? pref : (urls.isEmpty ? '' : urls.first);
    final ok = await Api.probe();
    s.reachable = ok != null;
    if (ok != null) {
      Api.base = ok;
      s.lastOk = ok;
    }
    // 自述回来补 id / 名字 / 入口；登录站以服务端说的为准。
    final meta = await Api.loadMeta();
    if (meta != null) {
      s.applyMeta(meta, master: meta.master);
      if (meta.master == true) {
        for (final x in sites) {
          if (x.key != s.key) x.master = false;
        }
      }
      siteMeta = meta;
      // 自述只该往里加入口，但加了也得挂上——否则新入口要等下次切站才生效。
      Api.setEndpoints(s.orderedUrls);
      if (!s.orderedUrls.contains(Api.base) && s.orderedUrls.isNotEmpty) {
        Api.base = s.orderedUrls.first;
      }
    }
    // id 可能刚从空变成有值，key 变了，当前标记重新对上。
    activeKey = s.key;
    await p.setString(_kActive, activeKey);
    user = null;
    _applyCacheScope(null);
    await SiteStore.write(sites);
    notifyListeners();
    await refreshUser();
    feedVersion++;
    await refreshUnread();
    notifyListeners();
    return ok != null;
  }

  /// 把新站点并进表里，返回新增的行数（更新已有行不算）。
  Future<int> addSites(List<SiteEntry> incoming) async {
    final before = sites.length;
    sites = mergeSites(sites, incoming);
    final added = sites.length - before;
    await SiteStore.write(sites);
    if (activeKey.isEmpty && sites.isNotEmpty) {
      await switchSite(sites.first);
    } else {
      notifyListeners();
    }
    return added;
  }

  /// 删一座站。删的是当前站就落到下一座；一座不剩就断开，界面自己处理空表。
  ///
  /// 主站不给删：它是「至少还能发帖」的兜底，删掉就只剩小站了。
  /// 返回 false 表示被拦下来了。
  Future<bool> removeSite(SiteEntry s) async {
    if (s.isHome) return false;
    final wasActive = s.key == activeKey;
    sites = sites.where((x) => x.key != s.key).toList();
    if (sites.isNotEmpty && !sites.any((x) => x.master)) {
      sites.first.master = true;
    }
    await SiteStore.write(sites);
    if (!wasActive) {
      notifyListeners();
      return true;
    }
    if (sites.isEmpty) {
      activeKey = '';
      Api.setEndpoints(const []);
      Api.base = '';
      user = null;
      _applyCacheScope(null);
      notifyListeners();
      return true;
    }
    await switchSite(sites.first);
    return true;
  }

  /// 屏蔽 / 取消屏蔽一座站。主站不给屏蔽——它是兜底，屏蔽了就没站能发帖。
  Future<void> toggleBlocked(SiteEntry s) async {
    if (s.isHome) return;
    s.blocked = !s.blocked;
    await SiteStore.write(sites);
    notifyListeners();
  }

  /// 指定登录站。同一时间只有一个。
  Future<void> setLoginSite(SiteEntry s) async {
    for (final x in sites) {
      x.master = x.key == s.key;
    }
    await SiteStore.write(sites);
    notifyListeners();
  }

  /// 外部改了资料后同步到内存里（比如编辑资料页）。
  void applyUser(Map<String, dynamic> u) {
    user = u;
    _applyHue(u);
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
        await _applyHue(user!);
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
    _huePushed = false;
    await TokenStore.write(token);
    await _syncAccount(token, u);
    // 登录后主题色跟账号走：这个账号以前设过，就用它的。
    await _applyHue(u);
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

  /// 登录只能由登录站做，做完 token 全局共用。
  ///
  /// 当前站不是登录站时，登录回的是主站的行，得再拉一次 /me 换成这一站的影子行。
  Future<void> _afterLogin(Map<String, dynamic> d) async {
    await _saveToken(d['token'] as String, d['user'] as Map<String, dynamic>);
    if (!loginUrls.contains(Api.base)) await refreshUser();
  }

  Future<void> login(String name, String password) async {
    final d = await Api.postAt(loginUrls, '/login', {
      'name': name,
      'password': password,
    });
    await _afterLogin(d as Map<String, dynamic>);
  }

  Future<void> register(
    String name,
    String password,
    String email,
    String code, {
    String challengeId = '',
    String challengeAnswer = '',
    String challengeSig = '',
  }) async {
    final d = await Api.postAt(loginUrls, '/register', {
      'name': name,
      'password': password,
      'email': email,
      'code': code,
      if (challengeId.isNotEmpty) 'challenge_id': challengeId,
      if (challengeAnswer.isNotEmpty) 'challenge_answer': challengeAnswer,
      if (challengeSig.isNotEmpty) 'challenge_sig': challengeSig,
    });
    await _afterLogin(d as Map<String, dynamic>);
  }

  /// 注册前的人机校验题。服务端没开这项就返回 null，注册照常走。
  Future<Map<String, dynamic>?> fetchChallenge() async {
    try {
      final d = await Api.getAt(loginUrls, '/register/challenge');
      return (d as Map).cast<String, dynamic>();
    } on ApiException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 注册前先发验证码。返回冷却秒数。
  Future<int> requestCode(String email) async {
    final d = await Api.postAt(loginUrls, '/register/code', {'email': email});
    return (d['cooldown'] as num?)?.toInt() ?? 60;
  }

  /// 登录状态下改密码。服务端给这台设备发新 token，别的设备全部失效。
  Future<void> changePassword(String oldPw, String newPw) async {
    final d = await Api.post('/account/password', {'old': oldPw, 'new': newPw});
    await _saveToken(d['token'] as String, d['user'] as Map<String, dynamic>);
  }

  /// 退出其他设备。当前这台换新 token 继续用。
  Future<void> revokeOtherSessions() async {
    final d = await Api.post('/account/sessions/revoke', const {});
    await _saveToken(d['token'] as String, d['user'] as Map<String, dynamic>);
  }

  /// 找回密码：发重置验证码。返回冷却秒数。
  Future<int> requestResetCode(String email) async {
    final d = await Api.postAt(loginUrls, '/password/code', {'email': email});
    return (d['cooldown'] as num?)?.toInt() ?? 60;
  }

  /// 找回密码：验证码换新密码，成功直接登录。
  Future<void> resetPassword(String email, String code, String password) async {
    final d = await Api.postAt(loginUrls, '/password/reset', {
      'email': email,
      'code': code,
      'password': password,
    });
    await _afterLogin(d as Map<String, dynamic>);
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

  /// 管理员：所有人的云盘用量。只给数字，看不到文件内容。
  Future<List<Map<String, dynamic>>> adminCloudUsage({int page = 1}) async {
    final d = await Api.get(
      '/admin/cloud/usage',
      query: {'page': '$page', 'per_page': '100'},
    );
    return (d['items'] as List).cast<Map<String, dynamic>>();
  }

  /// 管理员：改某个人的云盘额度。quotaMb <= 0 = 回到全站默认。
  Future<Map<String, dynamic>> adminSetCloudQuota(int uid, int quotaMb) async {
    final d = await Api.post('/admin/cloud/quota', {
      'user_id': uid,
      'quota_mb': quotaMb,
    });
    return (d as Map).cast<String, dynamic>();
  }

  /// 管理员：把某个账号的密码重置成随机临时密码，返回一次，只显示这一回。
  Future<Map<String, dynamic>> adminResetPw(int uid) async {
    final d = await Api.post('/admin/user/$uid/reset_pw', {});
    return (d as Map).cast<String, dynamic>();
  }

  Future<void> logout() async {
    Api.token = null;
    user = null;
    banned = false;
    _applyCacheScope(null);
    await TokenStore.clear();
    notifyListeners();
  }
}
