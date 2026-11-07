import 'app_globals.dart';
import 'dart:async';
import 'dart:io' show Platform;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

import 'site_config.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

import 'api.dart';
import 'bg_poll.dart';
import 'l10n/app_localizations.dart';
import 'notify.dart';
import 'pages/chat_page.dart';
import 'pages/home_page.dart';
import 'pages/banned_page.dart';
import 'pages/notice_page.dart';
import 'poller.dart';
import 'store.dart';
import 'theme.dart';
import 'ui_config.dart';
import 'upload_manager.dart';

/// 点通知跳页面要一个全局 Navigator，此时还没有 context。

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 地址在 runApp 之前就定死，任何页面发请求都不会撞上空 base。
  // 先用出厂默认地址顶着（构建时 SERVERS 的第一个），等 _boot 探完再切到更好的那条。
  Api.base = Api.defaultBase;
  // 先把界面放上来，再读设置。
  // 之前是 await 完再 runApp，读盘一旦卡住（或抛异常），首帧永远不画，
  // 表现就是点开一片空白、以为打不开。设置读完会自己触发一次重建，
  // 主题跟着换过去，代价只是极短的一帧默认色。
  runApp(const ShijianxianApp());
  unawaited(SysNotify.init(_onNotifyTap));
  _initBgPoll();
  unawaited(_boot());
}

/// 后台轮询交给系统的 WorkManager：前台进程被冻住的时候，只有它能醒过来。
///
/// 15 分钟是系统下限，写更小也会被拉回来。重复注册同一个 uniqueName 不会
/// 叠加任务，开机、升级后重新跑一遍也只是把老任务对齐。
void _initBgPoll() {
  if (kIsWeb || !Platform.isAndroid) return;
  unawaited(() async {
    try {
      await Workmanager().initialize(bgCallbackDispatcher);
      await Workmanager().registerPeriodicTask(
        bgTaskUnique,
        bgTaskName,
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (e) {
      debugPrint('bgPoll register failed: $e');
    }
  }());
}

/// 读本地设置。读不出来也照常运行，只是用默认色相和明暗。
Future<void> _boot() async {
  // 界面参数先拉：卡片尺寸这类东西，晚一步就有一帧长得不对。
  // 拉不到就用缓存/默认值，这里不 await 到底，卡住也不该挡住启动。
  unawaited(UiConfig.load());
  try {
    await AppState.instance.loadPrefs();
  } catch (e) {
    debugPrint('failed to read settings, starting with defaults: $e');
    AppState.instance.ready = true;
  }
  // 当前站点探一遍：v6 入口先，连不上按入口顺序回落。
  // 选路全在手机上判断，失败就退回上次连通的地址，别让用户对着死地址。
  try {
    final b = await Api.probe();
    if (b != null) {
      Api.base = b;
      debugPrint('endpoint: $b');
    } else {
      debugPrint('site unreachable, using last: ${Api.base}');
    }
  } catch (e) {
    debugPrint('route selection failed, using last: ${Api.base} $e');
  }
  // 站点自述：协议版本、站点名、可用入口。读不到就静默——
  // 老站没有 /.well-known，这不该挡住任何东西。
  try {
    final m = await Api.loadMeta();
    if (m != null) {
      AppState.instance.setSiteMeta(m);
      // 入口并进当前站，服务端加了新入口下次冷启动就不用再探。
      await AppState.instance.applySiteMeta(m);
    }
  } catch (e) {
    debugPrint('failed to read site meta: $e');
  }
  // 入口状态实探：站点管理里那排 v6 / v4 一进去就该是准的。
  unawaited(AppState.instance.probeSites());
  // 设置读完才有 Api.token。冷启动必须在这里补一次 /me，
  // 否则杀掉后台再进来，token 还在、user 却是空的，看着就是掉登录。
  unawaited(AppState.instance.init());
  // 上次没传完的东西接着传，断点接着续。
  unawaited(UploadManager.i.init());
  // 轮询放在最后启动：要有 token 才有东西可查。
  // 通知权限、电池豁免也挂在轮询第一次跑通之后问，见 Poller._maybeAskPerms。
  unawaited(Poller.instance.start());
}

/// 点通知回到 App 里。payload 只有两种：`dm:<id>:<名字>` 和 notice。
void _onNotifyTap(String payload) {
  final nav = appNav.currentState;
  if (nav == null) return;
  if (payload == 'notice') {
    nav.push(MaterialPageRoute(builder: (_) => const NoticePage()));
    return;
  }
  if (payload.startsWith('dm:')) {
    final parts = payload.split(':');
    if (parts.length < 3) return;
    final id = int.tryParse(parts[1]);
    if (id == null) return;
    final name = parts.sublist(2).join(':');
    nav.push(
      MaterialPageRoute(
        builder: (_) =>
            ChatPage(peer: {'id': id, 'name': name, 'nickname': name}),
      ),
    );
  }
}

class ShijianxianApp extends StatefulWidget {
  const ShijianxianApp({super.key});

  @override
  State<ShijianxianApp> createState() => _ShijianxianAppState();
}

class _ShijianxianAppState extends State<ShijianxianApp>
    with WidgetsBindingObserver {
  /// 主题构建不便宜（fromSeed 要跑一遍色板推导），色相和明暗没变就复用。
  final Map<String, ThemeData> _cache = {};

  /// 上次探路的时间，防止来回切 App 时反复探测。
  DateTime _lastProbe = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 切网络（家里 WiFi → 校园网 → 流量）不会通知 App，
  /// 但人回到前台时基本就是刚换过网络，这时候重新探一遍。
  /// 请求失败时 Api 里还有一层换通道，这里负责早点切回更快的 IPv6。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (Api.endpoints.isEmpty) return;
    final now = DateTime.now();
    if (now.difference(_lastProbe) < const Duration(seconds: 5)) return;
    _lastProbe = now;
    unawaited(() async {
      final b = await Api.probe();
      if (b != null && b != Api.base) {
        Api.base = b;
        Api.onChannelChanged?.call(b);
      }
    }());
  }

  late final Listenable _themeKeys = Listenable.merge([
    AppState.instance.themeMode,
    AppState.instance.accentHue,
    AppState.instance.useDynamicColor,
    AppState.instance.localeCode,
  ]);

  /// '' 跟随系统；zh / en 强制。
  /// 系统语言两种都不是时落到中文 —— ARB 模板就是中文，别给个空界面。
  Locale _resolveLocale(String code, Locale? system) {
    if (code == 'zh') return const Locale('zh');
    if (code == 'en') return const Locale('en');
    if (system?.languageCode == 'en') return const Locale('en');
    return const Locale('zh');
  }

  ThemeData _theme(Brightness b, [ColorScheme? dyn]) {
    final st = AppState.instance;
    // 壁纸色优先，没开或系统不给就退回自选色相。
    final useDyn = st.useDynamicColor.value && dyn != null;
    final hue = st.accentHue.value;
    final key = useDyn
        ? 'dyn:${b.index}:${dyn.primary.toARGB32()}'
        : '${b.index}:$hue';
    return _cache.putIfAbsent(
      key,
      () => useDyn
          ? buildAppThemeFromScheme(dyn, b)
          : buildAppTheme(b, st.colorOfHue(hue)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 壁纸取色：Android 12+ 给两份 scheme，别的平台给 null。
    return DynamicColorBuilder(
      builder: (lightDyn, darkDyn) => ListenableBuilder(
        listenable: _themeKeys,
        builder: (_, _) => MaterialApp(
          title: SiteConfig.brand,
          debugShowCheckedModeBanner: false,
          // 界面文案走 ARB；系统组件（长按菜单、日期选择）跟着语言走。
          locale: _resolveLocale(
            AppState.instance.localeCode.value,
            WidgetsBinding.instance.platformDispatcher.locale,
          ),
          supportedLocales: L.supportedLocales,
          localizationsDelegates: const [
            L.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // 切明暗、拖色相时不让 MaterialApp 自己跑一段颜色补间：
          // 补间会连带整棵树插值重建，边界处容易看见一闪。
          themeAnimationDuration: Duration.zero,
          theme: _theme(Brightness.light, lightDyn),
          darkTheme: _theme(Brightness.dark, darkDyn),
          themeMode: AppState.instance.themeMode.value,
          navigatorKey: appNav,
          scaffoldMessengerKey: appMessenger,
          builder: (ctx, child) => ValueListenableBuilder<double>(
            valueListenable: AppState.instance.fontScale,
            builder: (_, scale, _) {
              final mq = MediaQuery.of(ctx);
              return MediaQuery(
                data: mq.copyWith(textScaler: TextScaler.linear(scale)),
                // 点空白处退出输入状态，全站一处管住。
                // translucent 只是参与命中，真正的点击还是内层先拿走：
                // 点按钮、点列表项都照常，只有落在空底子上才收键盘。
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    final f = FocusManager.instance.primaryFocus;
                    if (f != null && f.hasFocus) f.unfocus();
                  },
                  child: child!,
                ),
              );
            },
          ),
          home: const _Root(),
        ),
      ),
    );
  }
}

/// 最外层两选一：封禁页 / 首页。
///
/// 账号被封时整棵树换掉——点哪个页面都是这一页，直到退出登录。
/// 站点表出厂就有一行「时间线」，所以不再有「首次启动先填地址」那一页。
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (_, _) {
        final st = AppState.instance;
        if (st.banned) return const BannedPage();
        return const HomePage();
      },
    );
  }
}
