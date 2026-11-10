import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../plat.dart';
import '../save_cover.dart';
import '../img_compress.dart';
import '../store.dart';
import '../user_hue.dart';
import '../widgets/empty_view.dart';
import '../widgets/page_width.dart';
import '../widgets/avatar.dart';
import '../widgets/post_images.dart';
import '../widgets/thread_tile.dart';
import 'edit_profile_page.dart';
import 'follow_page.dart';
import 'chat_page.dart';
import 'thread_page.dart';
import 'gallery_picker_page.dart';

import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
import '../widgets/toast.dart';

/// 用户主页：封面 + 资料区 + 帖子列表，结构照着 X 来。
class UserPage extends StatefulWidget {
  final String name;

  const UserPage({super.key, required this.name});

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  final List<Map<String, dynamic>> _items = [];
  final ScrollController _scroll = ScrollController();
  final ImagePicker _picker = ImagePicker();

  Map<String, dynamic>? _info;
  int _page = 1;
  bool _busy = false;
  bool _hasMore = true;
  bool _first = true;
  bool _acting = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 320) {
        _load();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy || !_hasMore) return;
    _busy = true;
    try {
      final d = await Api.get(
        '/u/${Uri.encodeComponent(widget.name)}',
        query: {'page': '$_page'},
      );
      final items = ((d['items'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _info = (d['user'] as Map?)?.cast<String, dynamic>() ?? _info;
        _items.addAll(items);
        _page++;
        _hasMore = items.length >= 20;
        _first = false;
        _err = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _first = false;
        _err = errorText(context, e);
      });
    } finally {
      _busy = false;
    }
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _page = 1;
      _hasMore = true;
      _first = true;
      _err = null;
    });
    await _load();
  }

  void _open(Map<String, dynamic> it) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ThreadPage(
          threadId: it['id'] as int,
          title: (it['title'] ?? '') as String,
        ),
      ),
    );
  }

  bool get _isMe {
    final me = AppState.instance.user;
    return me != null &&
        (me['name'] == widget.name || me['handle'] == widget.name);
  }

  Future<void> _edit() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditProfilePage(info: _info ?? {})),
    );
    if (ok == true && mounted) await _reload();
  }

  Future<void> _share() async {
    final h = '${(_info ?? const {})['handle'] ?? widget.name}';
    await Clipboard.setData(ClipboardData(text: '@$h'));
    if (mounted) {
      toastOf(context, Lc.current.accountCopied, floating: true);
    }
  }

  /// 关注 / 取关。
  Future<void> _toggleFollow() async {
    if (_acting) return;
    final following = (_info ?? const {})['is_following'] == true;
    setState(() => _acting = true);
    try {
      final path = '/u/${Uri.encodeComponent(widget.name)}/follow';
      final d = following ? await Api.delete(path) : await Api.post(path, {});
      if (!mounted) return;
      setState(() {
        _info = {
          ...?_info,
          'is_following': d['following'],
          'follow_count': d['follow_count'],
        };
      });
    } on ApiException catch (e) {
      if (mounted) {
        toastOf(context, errorText(context, e), floating: true);
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  /// 自己主页点封面：从相册选一张，压完传上去。
  Future<void> _pickCover() async {
    if (_acting) return;
    try {
      final XFile? f;
      if (!hasMediaStore) {
        f = await _picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1600,
          maxHeight: 1600,
        );
      } else {
        final own = await pickOwnGallery(context, maxCount: 1);
        f = own.isEmpty ? null : own.first;
      }
      if (f == null) return;
      setState(() => _acting = true);
      final src = await f.readAsBytes();
      final out = await ImgCompress.run(
        src,
        maxSide: 1600,
        quality: 82,
        sizeLimit: 600 * 1024,
      );
      final url = await Api.uploadImage(out, name: 'cover.jpg');
      await Api.patch('/me', {'cover': url});
      if (!mounted) return;
      setState(() => _info = {...?_info, 'cover': url});
      if (mounted) {
        toastOf(context, Lc.current.coverUpdated, floating: true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        toastOf(context, errorText(context, e), floating: true);
      }
    } catch (e) {
      if (mounted) {
        toastOf(context, Lc.current.coverFailed('$e'), floating: true);
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  /// 别人主页长按封面：先问一句，再存进相册。
  Future<void> _askSaveCover() async {
    final cover = '${(_info ?? const {})['cover'] ?? ''}';
    if (cover.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Lc.current.saveCover),
        content: Text(Lc.current.saveCoverConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(Lc.current.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(Lc.current.save),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final r = await http.get(Uri.parse(Api.img(cover)));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final where = await saveImageBytes(r.bodyBytes, 'openbbs-cover.jpg');
      if (mounted) {
        toastOf(context, Lc.current.savedTo(where), floating: true);
      }
    } catch (e) {
      if (mounted) {
        toastOf(context, Lc.current.saveFailed('$e'), floating: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_first) {
      return Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_err != null && _info == null) {
      return Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _err!,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.error),
            ),
          ),
        ),
      );
    }

    final info = _info ?? const <String, dynamic>{};
    return Scaffold(
      body: PageWidth(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: ListView.builder(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: _items.length + 3,
            itemBuilder: (context, i) {
              if (i == 0) return _cover(info, cs);
              if (i == 1) return _profile(info, cs);
              if (i == 2) return _tabStrip(cs);
              final it = _items[i - 3];
              return ThreadTile(
                item: it,
                onTap: () => _open(it),
                onDeleted: _load,
              );
            },
          ),
        ),
      ),
    );
  }

  /// 头像、封面点开看大图。用的是帖子里那个查看器：双指缩放、双击放大。
  void _viewLarge(String url) {
    if (url.isEmpty) return;
    openImageViewer(context, urls: [url]);
  }

  /// 封面。有图就铺图，没有就一层渐变。
  Widget _cover(Map<String, dynamic> info, ColorScheme cs) {
    final cover = '${info['cover'] ?? ''}';
    final has = cover.isNotEmpty;
    return GestureDetector(
      // 别人的封面点开看大图，自己的还是换图。
      onTap: _isMe ? _pickCover : (has ? () => _viewLarge(cover) : null),
      onLongPress: !_isMe && has ? _askSaveCover : null,
      child: SizedBox(
        height: 168,
        child: Stack(
          children: [
            Positioned.fill(
              child: has
                  ? Image.network(
                      Api.img(cover),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _gradient(cs),
                    )
                  : _gradient(cs),
            ),
            // 顶部压一层暗角，按钮在亮图上也能看清
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: .34),
                      Colors.transparent,
                    ],
                    stops: const [0, .6],
                  ),
                ),
              ),
            ),
            if (_isMe)
              Positioned(
                right: 12,
                bottom: 10,
                child: _hintPill(
                  icon: Icons.photo_camera_outlined,
                  label: has ? Lc.current.changeCover : Lc.current.addCover,
                ),
              ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                child: Row(
                  children: [
                    _roundIcon(
                      icon: Icons.arrow_back_rounded,
                      onTap: () => Navigator.of(context).maybePop(),
                      tooltip: Lc.current.back,
                    ),
                    const Spacer(),
                    _roundIcon(
                      icon: Icons.ios_share_rounded,
                      onTap: _share,
                      tooltip: Lc.current.share,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gradient(ColorScheme cs) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [cs.primaryContainer, cs.surfaceContainerHigh],
              ),
            ),
          ),
        ),
        Positioned(
          right: -30,
          top: -40,
          child: _blob(120, cs.primary.withValues(alpha: .16)),
        ),
        Positioned(
          left: 90,
          bottom: -50,
          child: _blob(90, cs.tertiary.withValues(alpha: .13)),
        ),
      ],
    );
  }

  Widget _blob(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _hintPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(fontSize: 11.5, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _roundIcon({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Material(
      color: Colors.black.withValues(alpha: .38),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onTap,
        tooltip: tooltip,
        icon: Icon(icon, size: 20, color: Colors.white),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  /// 头像压着封面，右边放主要操作，下面是资料文字。
  Widget _profile(Map<String, dynamic> info, ColorScheme cs) {
    final tt = Theme.of(context).textTheme;
    final nick = '${info['nickname'] ?? info['name'] ?? widget.name}';
    final handle = '${info['handle'] ?? ''}'.replaceFirst(RegExp(r'^@'), '');
    final avatar = '${info['avatar'] ?? ''}';
    final sig = '${info['signature'] ?? ''}';
    final level = (info['level'] as int?) ?? 1;
    final following = (info['following_count'] as int?) ?? 0;
    final followers = (info['follow_count'] as int?) ?? 0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 给压上来的头像让位
              const SizedBox(height: 54),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                nick,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tt.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 24,
                                  letterSpacing: -.3,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _levelBadge(level, cs),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '@${handle.isEmpty ? widget.name : handle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodyMedium?.copyWith(color: cs.outline),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _actionButton(cs),
                ],
              ),
              if (sig.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(sig, style: tt.bodyLarge?.copyWith(height: 1.55)),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.tag_rounded, size: 13, color: cs.outline),
                  const SizedBox(width: 5),
                  Text(
                    'UID ${info['uid'] ?? ''}',
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 13,
                    color: cs.outline,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    Lc.current.joinedAt(_since(info['created_at'])),
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _count(
                    following,
                    Lc.current.followingCount,
                    cs,
                    onTap: () => _openFollows(0),
                  ),
                  const SizedBox(width: 18),
                  _count(
                    followers,
                    Lc.current.followers,
                    cs,
                    onTap: () => _openFollows(1),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          left: 16,
          top: -46,
          child: GestureDetector(
            onTap: _isMe
                ? _edit
                : (avatar.isEmpty ? null : () => _viewLarge(avatar)),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: cs.surface,
                shape: BoxShape.circle,
              ),
              child: CircleAvatarImg(
                url: avatar,
                name: nick,
                radius: 42,
                hue: hueOfUser(info),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _actionButton(ColorScheme cs) {
    if (_isMe) {
      return OutlinedButton(
        onPressed: _acting ? null : _edit,
        style: _pill(cs),
        child: Text(Lc.current.editProfile),
      );
    }
    final following = (_info ?? const {})['is_following'] == true;
    final follow = following
        ? OutlinedButton(
            onPressed: _acting ? null : _toggleFollow,
            style: _pill(cs),
            child: Text(Lc.current.following),
          )
        : FilledButton(
            onPressed: _acting ? null : _toggleFollow,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(Lc.current.follow),
          );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        follow,
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _acting ? null : _openChat,
          style: _pill(cs),
          icon: const Icon(Icons.mail_outline_rounded, size: 16),
          label: Text(Lc.current.dmSend),
        ),
      ],
    );
  }

  void _openChat() {
    final info = _info;
    if (info == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatPage(
          peer: {
            'id': info['id'],
            'name': info['name'],
            'nickname': info['nickname'],
            'avatar': info['avatar'],
          },
        ),
      ),
    );
  }

  ButtonStyle _pill(ColorScheme cs) {
    return OutlinedButton.styleFrom(
      minimumSize: const Size(0, 38),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      side: BorderSide(color: cs.outlineVariant, width: 1.2),
    );
  }

  Widget _levelBadge(int level, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        'Lv$level',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: cs.onSecondaryContainer,
        ),
      ),
    );
  }

  /// 关注 / 粉丝数字。n 为 -1 表示对方关了公开，只留一条横线。
  Widget _count(int n, String label, ColorScheme cs, {VoidCallback? onTap}) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          n < 0 ? '—' : '$n',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: cs.outline)),
      ],
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
        child: row,
      ),
    );
  }

  /// 名单页。别人的是只读的，自己那页能顺手取关/回关。
  void _openFollows(int tab) {
    final info = _info ?? const <String, dynamic>{};
    final h = '${info['handle'] ?? ''}';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            FollowPage(name: h.isNotEmpty ? h : widget.name, initialTab: tab),
      ),
    );
  }

  /// 只留一个「帖子」标签，样子跟 X 一样，但不做假的分页。
  Widget _tabStrip(ColorScheme cs) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: cs.primary, width: 2.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.article_outlined, size: 17, color: cs.onSurface),
                    const SizedBox(width: 7),
                    Text(
                      Lc.current.post,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_items.isEmpty)
          // Column 里高度无界，EmptyView 自己要一个框。
          SizedBox(
            height: 220,
            child: EmptyView(
              icon: Icons.article_outlined,
              title: Lc.current.noPostsYet,
            ),
          ),
      ],
    );
  }
}

/// 加入时间只显示到年月，够用了。
String _since(dynamic ts) {
  final t = ts is int ? ts : int.tryParse('$ts') ?? 0;
  if (t <= 0) return Lc.current.longAgo;
  final d = DateTime.fromMillisecondsSinceEpoch(t * 1000);
  return Lc.current.yearMonth('${d.year}', '${d.month}');
}
