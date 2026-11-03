import 'dart:async';

import 'package:flutter/material.dart';

import 'site_config.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api.dart';
import 'l10n/app_localizations.dart';
import 'pages/home_page.dart';
import 'store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 地址在 runApp 之前就定死，任何页面发请求都不会撞上空 base。
  // 先用出厂默认地址顶着（构建时 SERVERS 的第一个），等 _boot 探完再切到更好的那条。
  // 一个都没配就是空，首页会落到设置页。
  Api.base = Api.defaultBase;
  // 先把界面放上来，再读设置。
  // 之前是 await 完再 runApp，读盘一旦卡住（或抛异常），首帧永远不画，
  // 表现就是点开一片空白、以为打不开。设置读完会自己触发一次重建，
  // 主题跟着换过去，代价只是极短的一帧默认色。
  runApp(const ShijianxianApp());
  unawaited(_boot());
}

/// 读本地设置。读不出来也照常运行，只是用默认色相和明暗。
Future<void> _boot() async {
  try {
    await AppState.instance.loadPrefs();
  } catch (e) {
    debugPrint('failed to read settings, starting with defaults: $e');
    AppState.instance.ready = true;
  }
  // 只有自动档要探：先 IPv6，通了就用，不通再走 IPv4，全程在手机上判断。
  // 其余三档地址是定死的，启动时不用再问一遍。
  if (Api.mode == ServerMode.auto) {
    try {
      final b = await Api.probe();
      if (b != null) {
        Api.base = b;
        debugPrint('endpoint: $b');
      } else {
        debugPrint('both channels unreachable, using last: ${Api.base}');
      }
    } catch (e) {
      debugPrint('route selection failed, using last: ${Api.base} $e');
    }
  }
  // 设置读完才有 Api.token。冷启动必须在这里补一次 /me，
  // 否则杀掉后台再进来，token 还在、user 却是空的，看着就是掉登录。
  unawaited(AppState.instance.init());
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
    if (Api.mode != ServerMode.auto) return;
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

  ThemeData _theme(Brightness b) {
    final hue = AppState.instance.accentHue.value;
    final key = '${b.index}:$hue';
    return _cache.putIfAbsent(
      key,
      () => buildAppTheme(b, AppState.instance.colorOfHue(hue)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
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
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: AppState.instance.themeMode.value,
        builder: (ctx, child) => ValueListenableBuilder<double>(
          valueListenable: AppState.instance.fontScale,
          builder: (_, scale, _) {
            final mq = MediaQuery.of(ctx);
            return MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            );
          },
        ),
        home: const HomePage(),
      ),
    );
  }
}
