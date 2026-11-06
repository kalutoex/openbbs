import '../widgets/empty_view.dart';
import '../widgets/page_width.dart';

import 'package:flutter/material.dart';

import '../cloud.dart';
import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
import '../widgets/toast.dart';

/// 从云盘里挑文件。
///
/// 发帖、编辑帖子、聊天附件都走这里，省得每次都被系统文件管理器顶出来。
/// 选中的是已经在云端的文件，直接引用 /f/<digest>，不用再传一遍。
class CloudPickPage extends StatefulWidget {
  const CloudPickPage({super.key, this.maxCount = 5});

  final int maxCount;

  @override
  State<CloudPickPage> createState() => _CloudPickPageState();
}

class _CloudPickPageState extends State<CloudPickPage> {
  final List<CloudFile> _items = [];
  final List<CloudFile> _picked = [];
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();

  bool _loading = true;
  bool _more = false;
  bool _failed = false;
  String _q = '';
  String _sort = 'time';
  int _page = 1;
  int _total = 0;

  static const _perPage = 30;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final p = await CloudApi.list(
        q: _q,
        sort: _sort,
        page: 1,
        perPage: _perPage,
      );
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(p.items);
        _total = p.total;
        _page = 1;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
      toast(context, errorText(context, e));
    }
  }

  Future<void> _loadMore() async {
    if (_more || _loading || _failed) return;
    if (_items.length >= _total) return;
    setState(() => _more = true);
    try {
      final p = await CloudApi.list(
        q: _q,
        sort: _sort,
        page: _page + 1,
        perPage: _perPage,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(p.items);
        _page += 1;
        _total = p.total;
        _more = false;
      });
    } catch (_) {
      if (mounted) setState(() => _more = false);
    }
  }

  void _toggle(CloudFile f) {
    final hit = _picked.indexWhere((x) => x.id == f.id);
    setState(() {
      if (hit >= 0) {
        _picked.removeAt(hit);
        return;
      }
      if (_picked.length >= widget.maxCount) {
        toast(context, Lc.current.attachMax('${widget.maxCount}'));
        return;
      }
      _picked.add(f);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(Lc.current.pickFromCloud),
        actions: [
          TextButton(
            onPressed: _picked.isEmpty
                ? null
                : () => Navigator.of(context).pop(List<CloudFile>.of(_picked)),
            child: Text(Lc.current.cloudPickDone('${_picked.length}')),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: PageWidth(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: Lc.current.search,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                onSubmitted: (v) {
                  _q = v.trim();
                  _load();
                },
                onChanged: (v) {
                  if (v.trim() == _q) return;
                  _q = v.trim();
                  _load();
                },
              ),
            ),
            Expanded(child: _body(cs)),
          ],
        ),
      ),
    );
  }

  Widget _body(ColorScheme cs) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_failed) {
      return EmptyView(
        icon: Icons.cloud_off_rounded,
        title: Lc.current.connectFailedPlain,
        error: true,
        action: FilledButton.tonal(
          onPressed: _load,
          child: Text(Lc.current.retry),
        ),
      );
    }
    if (_items.isEmpty) {
      return EmptyView(
        icon: Icons.cloud_outlined,
        title: Lc.current.cloudPickEmpty,
      );
    }
    return ListView.builder(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      itemCount: _items.length + (_items.length < _total ? 1 : 0),
      itemBuilder: (_, i) {
        if (i >= _items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final f = _items[i];
        final on = _picked.any((x) => x.id == f.id);
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: on
                ? cs.primaryContainer
                : cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _toggle(f),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                child: Row(
                  children: [
                    Icon(
                      _iconOf(f.name),
                      size: 22,
                      color: on ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            f.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              color: on ? cs.onPrimaryContainer : cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            f.sizeText,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: on
                                  ? cs.onPrimaryContainer.withValues(alpha: 0.7)
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      on ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 22,
                      color: on ? cs.primary : cs.outlineVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static IconData _iconOf(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.zip') || n.endsWith('.rar') || n.endsWith('.7z')) {
      return Icons.folder_zip_outlined;
    }
    if (n.endsWith('.apk')) return Icons.android;
    if (n.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (n.endsWith('.png') ||
        n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.gif') ||
        n.endsWith('.webp')) {
      return Icons.image_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }
}
