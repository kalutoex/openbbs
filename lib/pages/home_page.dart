import 'dart:async';

import '../widgets/fade_indexed_stack.dart';
import '../widgets/live_time.dart';

import 'package:flutter/material.dart';

import '../api.dart';
import '../permissions.dart';
import '../site_meta.dart';
import '../store.dart';
import '../widgets/app_drawer.dart';
import '../widgets/page_width.dart';
import 'compose_page.dart';
import '../haptics.dart';
import 'feed_tab.dart';
import 'login_page.dart';
import 'me_tab.dart';
import 'messages_page.dart';
import 'site_catalog_page.dart';

import '../l10n/app_localizations.dart';
import '../l10n/l10n.dart';
import '../update_prompt.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _sk = GlobalKey<ScaffoldState>();

  /// 0 = 时间线，1 = 站点，2 = 消息，3 = 我的
  late int _index = _tabOf(AppState.instance.startTab.value);

  /// 底栏只露这几页。站点（1）暂时没那么大用处，先不放进底栏，
  /// 页面和索引都留着，想放回来把 1 加回这个列表就行。
  static const _barTabs = <int>[0, 2, 3];

  /// IndexedStack 会把四个 tab 全部建出来、initState 一起发请求，
  /// 启动瞬间四路网络 + 四份骨架一起刷，看着就是一阵乱闪。
  /// 这里只建访问过的那个。
  late final Set<int> _started = {_index};

  /// 历史版本存过 0..3（1 是站点），语义和现在这张表一致，越界就回首页。
  /// 站点没入口了，存着 1 的老设置直接给首页。
  static int _tabOf(int v) => v >= 0 && v <= 3 && v != 1 ? v : 0;

  void _go(int i) {
    if (!_barTabs.contains(i)) return;
    if (i == _index) return;
    Haptics.tap();
    setState(() {
      _index = i;
      _started.add(i);
    });
  }

  Timer? _tick;

  /// 「3 分钟前」这类字样得自己走。半分钟敲一下，挂了 LiveTime 的地方跟着重算。
  Timer? _beat;

  @override
  void initState() {
    super.initState();
    // 第一次装完问一遍通知和相册；问过就不再提。
    WidgetsBinding.instance.addPostFrameCallback((_) => AppPerms.firstRun());
    // 启动后问一次有没有新版本。节流在 checkOnStart 里，失败静默。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(checkOnStart(context));
    });
    AppState.instance.refreshUnread();
    AppState.instance.autoUnread.addListener(_syncTick);
    _beat = Timer.periodic(const Duration(seconds: 30), (_) => beatClock());
    _syncTick();
  }

  /// 设置里关掉「自动检查通知」就停掉这个每分钟的轮询。
  void _syncTick() {
    _tick?.cancel();
    _tick = null;
    if (!AppState.instance.autoUnread.value) return;
    _tick = Timer.periodic(
      const Duration(seconds: 60),
      (_) => AppState.instance.refreshUnread(),
    );
  }

  @override
  void dispose() {
    AppState.instance.autoUnread.removeListener(_syncTick);
    _tick?.cancel();
    _beat?.cancel();
    super.dispose();
  }

  void _menu() => _sk.currentState?.openDrawer();

  Future<void> _compose() async {
    if (AppState.instance.user == null) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const LoginPage()));
      if (!mounted || AppState.instance.user == null) return;
    }

    final ok = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const ComposePage()));
    if (ok == true) AppState.instance.bumpFeed();
  }

  /// 协议版本提醒。用 errorContainer 而不是弹窗：这不该挡住看帖。
  Widget _tooNewBanner(BuildContext context, int api) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Icon(
                Icons.system_update_alt_rounded,
                size: 18,
                color: cs.onErrorContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  L
                      .of(context)
                      .siteNeedsUpdate('$api', '${SiteMeta.supportedApi}'),
                  style: TextStyle(fontSize: 12.5, color: cs.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 连不上服务器时顶一条细提示。不拦人、不弹窗：
  /// 大多数断网是十几秒的事，弹窗只会让人手忙脚乱。
  /// 哪个请求通了它就自己收起来，不用点。
  Widget _netBanner(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        child: Row(
          children: [
            Icon(Icons.wifi_off_rounded, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                Lc.current.netDownBanner,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
            TextButton(
              onPressed: () {
                AppState.instance.refreshUnread();
                AppState.instance.bumpFeed();
              },
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: Text(
                Lc.current.retry,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, cons) {
        // MD3 的窗口分级：expanded（>=840dp）把底栏收进左侧导航栏，
        // 不然内容区就被拉成一条又窄又长的手机屏。
        final wide = cons.maxWidth >= 840;
        return Scaffold(
          key: _sk,
          drawer: AppDrawer(
            currentTab: _index,
            onTimeline: () => _go(0),
            onSites: () => _go(1),
            onMe: () => _go(3),
          ),
          // 站点比客户端新就顶一条提示。只提示，不拦着用——
          // 拦了人也没别的客户端可选，不如让人自己看到原因。
          //
          // 结构固定成三个孩子：窄屏时前两个是空盒子。以前是
          // `wide ? Row(rail, content) : content`，拖窗口跨过 840 时
          // content 的父链一变，整个 tab 页重建，滚动位置和草稿全丢。
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide) _rail(context) else const SizedBox.shrink(),
              if (wide)
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: Theme.of(context).colorScheme.outlineVariant.withValues(
                    alpha: .35,
                  ),
                )
              else
                const SizedBox.shrink(),
              Expanded(child: _content(context)),
            ],
          ),
          // 加号只在时间线这一页出现，翻到别的 tab 就收起来
          floatingActionButton: _index == 0
              ? FloatingActionButton(
                  onPressed: _compose,
                  tooltip: Lc.current.newThread,
                  child: const Icon(Icons.add),
                )
              : null,
          bottomNavigationBar: wide ? null : _bottomBar(context),
        );
      },
    );
  }

  /// 底栏选中的是 _barTabs 里的位置，不是页面索引。
  int get _sel => _barTabs.contains(_index) ? _barTabs.indexOf(_index) : 0;

  Widget _content(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        final meta = AppState.instance.siteMeta;
        return Column(
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: Api.netDown,
              builder: (context, down, _) =>
                  down ? _netBanner(context) : const SizedBox.shrink(),
            ),
            if (meta != null && meta.tooNew) _tooNewBanner(context, meta.api),
            Expanded(
              child: FadeIndexedStack(
                index: _index,
                children: [
                  FeedTab(onMenu: _menu, onCompose: _compose),
                  if (_started.contains(1))
                    SiteCatalogPage(onMenu: _menu)
                  else
                    const SizedBox.shrink(),
                  if (_started.contains(2))
                    MessagesPage(onMenu: _menu)
                  else
                    const SizedBox.shrink(),
                  if (_started.contains(3))
                    MeTab(onMenu: _menu)
                  else
                    const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// 窄屏底栏。
  Widget _bottomBar(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final unread = AppState.instance.unread + AppState.instance.dmUnread;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            border: Border(
              top: BorderSide(color: cs.outlineVariant.withValues(alpha: .35)),
            ),
          ),
          // 宽屏时导航项也收进同一栏，别让四个图标散到屏幕四角。
          child: PageWidth(
            max: 760,
            child: NavigationBar(
              selectedIndex: _sel,
              elevation: 0,
              height: 64,
              backgroundColor: Colors.transparent,
              indicatorColor: cs.secondaryContainer,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              onDestinationSelected: (i) => _go(_barTabs[i]),
              destinations: [
                for (final t in _barTabs)
                  NavigationDestination(
                    icon: _tabIcon(t, unread, false),
                    selectedIcon: _tabIcon(t, unread, true),
                    label: _tabLabel(t),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 宽屏左侧导航栏，MD3 的 NavigationRail。
  Widget _rail(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        final unread = AppState.instance.unread + AppState.instance.dmUnread;
        return NavigationRail(
          selectedIndex: _sel,
          onDestinationSelected: (i) => _go(_barTabs[i]),
          labelType: NavigationRailLabelType.all,
          backgroundColor: cs.surface,
          indicatorColor: cs.secondaryContainer,
          destinations: [
            for (final t in _barTabs)
              NavigationRailDestination(
                icon: _tabIcon(t, unread, false),
                selectedIcon: _tabIcon(t, unread, true),
                label: Text(_tabLabel(t)),
              ),
          ],
        );
      },
    );
  }

  Widget _tabIcon(int tab, int unread, bool selected) {
    if (tab == 2) {
      return Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: Icon(
          selected
              ? Icons.chat_bubble_rounded
              : Icons.chat_bubble_outline_rounded,
        ),
      );
    }
    if (tab == 3) {
      return Icon(
        selected ? Icons.person_rounded : Icons.person_outline_rounded,
      );
    }
    return Icon(selected ? Icons.home_rounded : Icons.home_outlined);
  }

  String _tabLabel(int tab) {
    if (tab == 2) return Lc.current.messagesTab;
    if (tab == 3) return Lc.current.me;
    return Lc.current.home;
  }
}
