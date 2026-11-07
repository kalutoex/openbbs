import 'package:flutter/material.dart';

import '../site_config.dart';
import '../api.dart';
import '../pages/admin_users_page.dart';
import '../pages/ui_config_page.dart';
import '../pages/admin_reports_page.dart';
import '../pages/feature_request_page.dart';
import '../pages/feature_requests_admin_page.dart';
import '../pages/follow_page.dart';
import '../pages/login_page.dart';
import '../pages/settings_page.dart';
import '../pages/thread_list_page.dart';
import '../pages/user_page.dart';
import '../store.dart';
import 'avatar.dart';
import 'name_tag.dart';

import '../l10n/l10n.dart';
import '../pages/cloud_page.dart';

/// 左侧抽屉：身份、导航、我的入口。
class AppDrawer extends StatefulWidget {
  /// 当前底部 tab，用来标出选中项。
  final int currentTab;
  final VoidCallback onTimeline;
  final VoidCallback? onSites;
  final VoidCallback? onMe;

  const AppDrawer({
    super.key,
    this.currentTab = 0,
    required this.onTimeline,
    this.onSites,
    this.onMe,
  });

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _loadReports();
    _loadFeatures();
    AppState.instance.refreshDmUnread();
  }

  /// 管理员才有，未处理举报数，拿不到就当 0。
  Future<void> _loadReports() async {
    if (AppState.instance.user?['is_admin'] != true) return;
    try {
      final d = await Api.get('/admin/reports/count');
      if (!mounted) return;
      AppState.instance.setReportOpen((d['open'] ?? 0) as int);
    } on ApiException {
      // 静默：角标不值得打扰
    }
  }

  /// 管理员才有，待看的需求单数。
  Future<void> _loadFeatures() async {
    if (AppState.instance.user?['is_admin'] != true) return;
    try {
      final d = await Api.get('/admin/feature-requests/count');
      if (!mounted) return;
      AppState.instance.setFeatureOpen((d['open'] ?? 0) as int);
    } on ApiException {
      // 静默
    }
  }

  void _close() => Navigator.of(context).pop();

  void _push(Widget page) {
    // 先把 Navigator 抓住：pop 掉抽屉之后 context 就跟着一起没了。
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = AppState.instance;

    return Drawer(
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(26),
          bottomRight: Radius.circular(26),
        ),
      ),
      child: SafeArea(
        child: AnimatedBuilder(
          animation: st,
          builder: (context, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Top(
                  st: st,
                  onTap: () {
                    if (!st.loggedIn) {
                      _push(const LoginPage());
                      return;
                    }
                    // 直达自己的主页，不再绕到「我的」页
                    final name = '${st.user?['name'] ?? ''}';
                    if (name.isEmpty) return;
                    _push(UserPage(name: name));
                  },
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                    children: [
                      _item(
                        context,
                        icon: Icons.dynamic_feed_outlined,
                        activeIcon: Icons.dynamic_feed,
                        label: Lc.current.home,
                        active: widget.currentTab == 0,
                        onTap: () {
                          _close();
                          widget.onTimeline();
                        },
                      ),
                      // 站点先收起：底栏已经拿掉了，抽屉里也一起不给入口。
                      // 要放回来，把这段和 home_page 里的 _barTabs 都加回 1。
                      // _item(
                      //   context,
                      //   icon: Icons.grid_view_outlined,
                      //   activeIcon: Icons.grid_view_rounded,
                      //   label: Lc.current.sites,
                      //   active: widget.currentTab == 1,
                      //   onTap: () {
                      //     _close();
                      //     widget.onSites?.call();
                      //   },
                      // ),
                      if (st.loggedIn) ...[
                        const SizedBox(height: 10),
                        _label(context, Lc.current.me),
                        _item(
                          context,
                          icon: Icons.bookmark_border,
                          label: Lc.current.myFavorites,
                          onTap: () => _push(
                            ThreadListPage(
                              title: Lc.current.myFavorites,
                              path: '/favorites',
                              emptyText: Lc.current.noFavoritesYet,
                            ),
                          ),
                        ),
                        _item(
                          context,
                          icon: Icons.cloud_outlined,
                          label: Lc.current.cloudDisk,
                          onTap: () => _push(const CloudPage()),
                        ),
                        _item(
                          context,
                          icon: Icons.people_outline,
                          label: Lc.current.follow,
                          onTap: () => _push(const FollowPage()),
                        ),
                        if (st.user?['is_admin'] == true)
                          _item(
                            context,
                            icon: Icons.flag_outlined,
                            label: Lc.current.reportHandling,
                            badge: st.reportOpen,
                            onTap: () => _push(const AdminReportsPage()),
                          ),
                        if (st.user?['is_admin'] == true)
                          _item(
                            context,
                            icon: Icons.tips_and_updates_outlined,
                            label: Lc.current.requestHandling,
                            badge: st.featureOpen,
                            onTap: () =>
                                _push(const FeatureRequestsAdminPage()),
                          ),
                        if (st.user?['is_admin'] == true)
                          _item(
                            context,
                            icon: Icons.manage_accounts_outlined,
                            label: Lc.current.accountManagement,
                            onTap: () => _push(const AdminUsersPage()),
                          ),
                        if (st.user?['is_admin'] == true)
                          _item(
                            context,
                            icon: Icons.tune,
                            label: Lc.current.uiConfigTitle,
                            onTap: () => _push(const UiConfigPage()),
                          ),
                        _item(
                          context,
                          icon: Icons.history,
                          label: Lc.current.browseHistory,
                          onTap: () => _push(
                            ThreadListPage(
                              title: Lc.current.browseHistory,
                              path: '/history',
                              emptyText: Lc.current.noHistoryYet,
                            ),
                          ),
                        ),
                        _item(
                          context,
                          icon: Icons.lightbulb_outline,
                          label: Lc.current.featureRequests,
                          onTap: () => _push(const FeatureRequestPage()),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                _item(
                  context,
                  icon: Icons.settings_outlined,
                  label: Lc.current.settings,
                  onTap: () => _push(const SettingsPage()),
                ),
                const SizedBox(height: 8),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: cs.outline,
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context, {
    required IconData icon,
    IconData? activeIcon,
    required String label,
    String? trailing,
    int badge = 0,
    bool active = false,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final fg = active ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: active ? cs.secondaryContainer : null,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(active ? (activeIcon ?? icon) : icon, size: 20, color: fg),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    color: active ? cs.onSecondaryContainer : cs.onSurface,
                  ),
                ),
              ),
              if (badge > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: cs.error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badge',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: cs.onError,
                    ),
                  ),
                ),
              if (trailing != null)
                Text(
                  trailing,
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 抽屉顶：品牌 + 身份卡。
class _Top extends StatelessWidget {
  final AppState st;
  final VoidCallback onTap;

  const _Top({required this.st, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final u = st.user;
    final nick = st.loggedIn
        ? '${u?['nickname'] ?? u?['name'] ?? ''}'
        : Lc.current.notLoggedIn;
    final handle = st.loggedIn ? '${u?['handle'] ?? ''}' : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  Icons.auto_stories,
                  size: 18,
                  color: cs.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                SiteConfig.brand,
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  CircleAvatarImg(
                    url: '${u?['avatar'] ?? ''}',
                    name: nick,
                    radius: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        NameTag(
                          name: nick,
                          handle: handle,
                          style: tt.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          st.loggedIn
                              ? ((u?['signature'] as String?)
                                            ?.trim()
                                            .isNotEmpty ??
                                        false
                                    ? (u!['signature'] as String).trim()
                                    : Lc.current.enterBio)
                              : Lc.current.tapToLogin,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.labelSmall?.copyWith(color: cs.outline),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    st.loggedIn ? Icons.chevron_right : Icons.login,
                    size: 18,
                    color: cs.outline,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
