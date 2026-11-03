import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../permissions.dart';
import '../store.dart';
import '../widgets/app_drawer.dart';
import 'compose_page.dart';
import 'feed_tab.dart';
import 'forum_page.dart';
import 'forums_tab.dart';
import 'login_page.dart';
import 'me_tab.dart';
import 'notice_tab.dart';

import '../l10n/error_text.dart';
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _sk = GlobalKey<ScaffoldState>();

  /// 0 = 时间线，1 = 板块，2 = 通知，3 = 用户
  late int _index = AppState.instance.startTab.value;

  /// IndexedStack 会把四个 tab 全部建出来、initState 一起发请求，
  /// 启动瞬间四路网络 + 四份骨架一起刷，看着就是一阵乱闪。
  /// 这里只建访问过的那个。
  late final Set<int> _started = {_index};

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

    List<Map<String, dynamic>> forums;
    try {
      final d = await Api.get('/forums');
      forums = (d['items'] as List).cast<Map<String, dynamic>>();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(errorText(context, e))));
      return;
    }
    if (!mounted) return;

    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (c) {
        final tt = Theme.of(c).textTheme;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  '发到哪个板块',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              for (final f in forums)
                ListTile(
                  title: Text((f['title'] ?? f['name'] ?? '') as String),
                  subtitle: ((f['intro'] ?? '') as String).isEmpty
                      ? null
                      : Text((f['intro'] ?? '') as String),
                  onTap: () => Navigator.pop(c, f),
                ),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) return;

    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ComposePage(
          forumName: (picked['name'] ?? '') as String,
          forumTitle: (picked['title'] ?? picked['name'] ?? '') as String,
        ),
      ),
    );
    if (ok == true) AppState.instance.bumpFeed();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _sk,
      drawer: AppDrawer(
        currentTab: _index,
        onTimeline: () => _go(0),
        onForums: () => _go(1),
        onMe: () => _go(3),
        onForum: (name, title) => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ForumPage(name: name, title: title),
          ),
        ),
      ),
      body: IndexedStack(
        index: _index,
        children: [
          FeedTab(onMenu: _menu),
          if (_started.contains(1))
            ForumsTab(onMenu: _menu)
          else
            const SizedBox.shrink(),
          if (_started.contains(2))
            NoticeTab(onMenu: _menu)
          else
            const SizedBox.shrink(),
          if (_started.contains(3))
            MeTab(onMenu: _menu)
          else
            const SizedBox.shrink(),
        ],
      ),
      // 加号只在时间线这一页出现，翻到别的 tab 就收起来
      floatingActionButton: _index == 0
          ? FloatingActionButton(
              onPressed: _compose,
              tooltip: '发帖',
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
                const NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: '首页',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.grid_view_outlined),
                  selectedIcon: Icon(Icons.grid_view_rounded),
                  label: '板块',
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
                  label: '通知',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: '我的',
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
