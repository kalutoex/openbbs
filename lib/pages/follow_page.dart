import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets/avatar.dart';
import '../widgets/name_tag.dart';
import '../widgets/user_link.dart';

import '../l10n/error_text.dart';
/// 关注 / 粉丝。
///
/// 一个页面两个列表，顶上是自己画的分段控件（原来用 TabBar 塞进 AppBar，
/// 指示器和文字对不齐，切一下还整页重载）。两个列表都留在 IndexedStack 里，
/// 来回切不重发请求、不闪加载。
class FollowPage extends StatefulWidget {
  const FollowPage({super.key});

  @override
  State<FollowPage> createState() => _FollowPageState();
}

/// 一个列表的状态：数据、是否在加载、错误。
class _Bucket {
  final List<Map<String, dynamic>> items = [];
  bool loading = true;
  String? error;

  bool get isEmpty => !loading && error == null && items.isEmpty;
}

class _FollowPageState extends State<FollowPage> {
  int _tab = 0;

  final _following = _Bucket();
  final _followers = _Bucket();

  /// 我关注的人的 handle，用来判断粉丝里谁是互关。
  final _handles = <String>{};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _load(_following, '/me/following'),
      _load(_followers, '/me/followers'),
    ]);
    _syncHandles();
  }

  Future<void> _load(_Bucket b, String path) async {
    if (mounted) setState(() => b.error = null);
    try {
      final d = await Api.get(path);
      final items = ((d['items'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      if (!mounted) return;
      setState(() {
        b.items
          ..clear()
          ..addAll(items);
        b.loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        b.loading = false;
        b.error = errorText(context, e);
      });
    }
  }

  void _syncHandles() {
    _handles
      ..clear()
      ..addAll(_following.items.map(_handleOf).where((h) => h.isNotEmpty));
  }

  String _handleOf(Map<String, dynamic> u) =>
      '${u['handle'] ?? u['name'] ?? ''}';

  String _nameOf(Map<String, dynamic> u) =>
      '${u['nickname'] ?? u['name'] ?? ''}';

  void _say(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s), duration: const Duration(seconds: 2)));
  }

  /// 取关：先从列表里拿掉，失败再放回去。
  Future<void> _unfollow(_Bucket b, Map<String, dynamic> u) async {
    final name = _handleOf(u);
    final idx = b.items.indexOf(u);
    setState(() {
      b.items.remove(u);
      _handles.remove(name);
    });
    try {
      await Api.delete('/u/${Uri.encodeComponent(name)}/follow');
      _say('已取消关注 ${_nameOf(u)}');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (idx >= 0 && idx <= b.items.length) {
          b.items.insert(idx, u);
        } else {
          b.items.add(u);
        }
        _syncHandles();
      });
      _say(errorText(context, e));
    }
  }

  /// 回关。
  Future<void> _followBack(Map<String, dynamic> u) async {
    final name = _handleOf(u);
    try {
      await Api.post('/u/${Uri.encodeComponent(name)}/follow', {});
      if (!mounted) return;
      setState(() {
        _handles.add(name);
        if (_following.items.every((e) => _handleOf(e) != name)) {
          _following.items.insert(0, u);
        }
      });
      _say('已回关 ${_nameOf(u)}');
    } on ApiException catch (e) {
      _say(errorText(context, e));
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _following.loading = true;
      _followers.loading = true;
    });
    await _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关注')),
      body: Column(
        children: [
          _segmented(),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                _list(_following, following: true),
                _list(_followers, following: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 分段控件 ───────────────────────────────────────────

  Widget _segmented() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Container(
        height: 40,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(11),
        ),
        child: LayoutBuilder(
          builder: (context, cons) {
            final half = cons.maxWidth / 2;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  left: _tab == 0 ? 0 : half,
                  top: 0,
                  bottom: 0,
                  width: half,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(9),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    _seg('关注', _following.items.length, 0),
                    _seg('粉丝', _followers.items.length, 1),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _seg(String label, int count, int index) {
    final cs = Theme.of(context).colorScheme;
    final on = _tab == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _tab = index),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                  color: on ? cs.onSurface : cs.onSurfaceVariant,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 5),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    color: on ? cs.primary : cs.outline,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── 列表 ───────────────────────────────────────────────

  Widget _list(_Bucket b, {required bool following}) {
    if (b.loading && b.items.isEmpty) return const _Skeleton();
    if (b.error != null && b.items.isEmpty) {
      return _hint(
        b.error!,
        icon: Icons.cloud_off_outlined,
        action: TextButton(onPressed: _refresh, child: const Text('重试')),
      );
    }
    if (b.isEmpty) {
      return _hint(
        following ? '还没关注谁' : '还没有粉丝',
        icon: following
            ? Icons.person_add_alt_outlined
            : Icons.people_outline,
        action: TextButton(onPressed: _refresh, child: const Text('刷新')),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: b.items.length,
        separatorBuilder: (_, _) => const Divider(
          height: 1,
          indent: 68,
          endIndent: 16,
        ),
        itemBuilder: (context, i) => _tile(b.items[i], following: following),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> u, {required bool following}) {
    final cs = Theme.of(context).colorScheme;
    final name = _nameOf(u);
    final handle = '${u['handle'] ?? ''}';
    final sig = '${u['signature'] ?? ''}'.trim();
    final mutual = _handles.contains(handle);

    return InkWell(
      onTap: () => openUserPage(
        context,
        handle.isNotEmpty ? handle : '${u['name'] ?? ''}',
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(
          children: [
            CircleAvatarImg(
              url: '${u['avatar'] ?? ''}',
              name: name,
              radius: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: NameTag(
                          name: name,
                          handle: handle,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sig.isNotEmpty ? sig : 'UID ${u['uid'] ?? u['id'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (following)
              _pill(
                '已关注',
                onTap: () => _unfollow(_following, u),
                filled: false,
              )
            else if (mutual)
              _pill('互相关注', onTap: null, filled: false)
            else
              _pill('回关', onTap: () => _followBack(u), filled: true),
          ],
        ),
      ),
    );
  }

  Widget _pill(String label, {VoidCallback? onTap, required bool filled}) {
    final cs = Theme.of(context).colorScheme;
    final fg = filled ? cs.onPrimary : cs.onSurfaceVariant;
    return SizedBox(
      height: 30,
      child: filled
          ? FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 12.5),
              ),
              child: Text(label),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: fg,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                side: BorderSide(color: cs.outlineVariant),
                textStyle: const TextStyle(fontSize: 12.5),
              ),
              child: Text(label),
            ),
    );
  }

  // ── 空态 / 骨架 ────────────────────────────────────────

  Widget _hint(String text, {required IconData icon, Widget? action}) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: cs.outlineVariant),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.outline, fontSize: 13),
            ),
            if (action != null) ...[const SizedBox(height: 6), action],
          ],
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
    );
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(96, 13),
                const SizedBox(height: 7),
                bar(150, 10),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
