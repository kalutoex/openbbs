import 'dart:async';

import 'package:flutter/material.dart';

import '../permissions.dart';
import '../site_meta.dart';
import '../store.dart';
import '../widgets/app_drawer.dart';
import 'compose_page.dart';
import 'feed_tab.dart';
import 'login_page.dart';
import 'me_tab.dart';
import 'notice_tab.dart';

import '../l10n/app_localizations.dart';
import '../l10n/l10n.dart';
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _sk = GlobalKey<ScaffoldState>();

  /// 0 = 时间线，1 = 通知，2 = 我的
  late int _index = _tabOf(AppState.instance.startTab.value);

  /// IndexedStack 会把四个 tab 全部建出来、initState 一起发请求，
  /// 启动瞬间四路网络 + 四份骨架一起刷，看着就是一阵乱闪。
  /// 这里只建访问过的那个。
  late final Set<int> _started = {_index};

  /// 老版本存过 0..3（1 是板块），读出来按新表重排。
  static int _tabOf(int v) => switch (v) {
        2 => 1,
        3 => 2,
        _ => 0,
      };

  void _go(int i) {
    if (i == _index) return;
    setState(() {
      _index = i;
      _started.add(i);
    });
  }

  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // 第一次装完问一遍通知和相册；问过就不再提。
    WidgetsBinding.instance.addPostFrameCallback((_) => AppPerms.firstRun());
    AppState.instance.refreshUnread();
    AppState.instance.autoUnread.addListener(_syncTick);
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
    super.dispose();
  }

  void _menu() => _sk.currentState?.openDrawer();

  Future<void> _compose() async {
    if (AppState.instance.user == null) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const LoginPage()));
      if (!mounted || AppState.instance.user == null) return;
    }

    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ComposePage()),
    );
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
                  L.of(context).siteNeedsUpdate('$api', '${SiteMeta.supportedApi}'),
                  style: TextStyle(fontSize: 12.5, color: cs.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _sk,
      drawer: AppDrawer(
        currentTab: _index,
        onTimeline: () => _go(0),
        onMe: () => _go(2),
      ),
      // 站点比客户端新就顶一条提示。只提示，不拦着用——
      // 拦了人也没别的客户端可选，不如让人自己看到原因。
      body: AnimatedBuilder(
        animation: AppState.instance,
        builder: (context, _) {
          final meta = AppState.instance.siteMeta;
          return Column(
            children: [
              if (meta != null && meta.tooNew) _tooNewBanner(context, meta.api),
              Expanded(
                child: IndexedStack(
                  index: _index,
                  children: [
                    FeedTab(onMenu: _menu),
                    if (_started.contains(1))
                      NoticeTab(onMenu: _menu)
                    else
                      const SizedBox.shrink(),
                    if (_started.contains(2))
                      MeTab(onMenu: _menu)
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      // 加号只在时间线这一页出现，翻到别的 tab 就收起来
      floatingActionButton: _index == 0
          ? FloatingActionButton(
              onPressed: _compose,
              tooltip: Lc.current.newThread,
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: AnimatedBuilder(
        animation: AppState.instance,
        builder: (context, _) {
          final cs = Theme.of(context).colorScheme;
          final unread = AppState.instance.unread;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              border: Border(
                top: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: .35),
                ),
              ),
            ),
            child: NavigationBar(
              selectedIndex: _index,
              elevation: 0,
              height: 64,
              backgroundColor: Colors.transparent,
              indicatorColor: cs.secondaryContainer,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              onDestinationSelected: _go,
              destinations: [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: Lc.current.home,
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: unread > 0,
                    label: Text(unread > 99 ? '99+' : '$unread'),
                    child: const Icon(Icons.notifications_none_rounded),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: unread > 0,
                    label: Text(unread > 99 ? '99+' : '$unread'),
                    child: const Icon(Icons.notifications_rounded),
                  ),
                  label: Lc.current.notice,
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: Lc.current.me,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
