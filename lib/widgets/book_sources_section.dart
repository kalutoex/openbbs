import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/l10n.dart';
import '../widgets/app_card.dart';
import '../widgets/toast.dart';

/// 外部书源：导入「阅读」那套 bookSource JSON，装卸开关都在这儿。
///
/// 规矩：
/// - 只存规则，不存内容。正文和图片都在源站，我们只是照着规则去取；
/// - 按账号隔离，别人导的源看不见也删不掉；
/// - 源站挂掉是常态，关掉就行，不必删——留着下次还能开。
class BookSourcesSection extends StatefulWidget {
  /// 书源类型：0 小说 / 1 有声 / 2 漫画。
  final int type;

  const BookSourcesSection({super.key, this.type = 2});

  @override
  State<BookSourcesSection> createState() => _BookSourcesSectionState();
}

class _BookSourcesSectionState extends State<BookSourcesSection> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;
  bool _busy = false;

  /// 源 id → 探测结果 {ok, via, ms, msg}。
  ///
  /// 只探地址，不跑规则：问一句有没有人应答，几秒就能给全表标上颜色。
  /// 规则对不上是另一回事，那个只能点进去才知道。
  Map<int, Map<String, dynamic>> _probe = {};
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 探一遍所有开着的源。进页面自动跑，也能手动重测。
  Future<void> _probeAll() async {
    if (_probing) return;
    setState(() => _probing = true);
    try {
      final r = await Api.post(
        '/sources/probe',
        {'type': widget.type, 'enabled': true},
        timeout: const Duration(seconds: 60),
      );
      final list = (r['list'] as List?) ?? const [];
      final m = <int, Map<String, dynamic>>{};
      for (final e in list.whereType<Map>()) {
        final id = (e['id'] as num?)?.toInt();
        if (id != null) m[id] = Map<String, dynamic>.from(e);
      }
      if (!mounted) return;
      setState(() {
        _probe = m;
        _probing = false;
      });
    } catch (_) {
      if (mounted) setState(() => _probing = false);
    }
  }

  int get _alive => _probe.values.where((p) => p['ok'] == true).length;

  Future<void> _load() async {
    try {
      final r = await Api.get('/sources', query: {'type': '${widget.type}'});
      final list = (r is Map ? r['list'] : null) as List?;
      if (!mounted) return;
      setState(() {
        _list = (list ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
      unawaited(_probeAll());
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // 书源 JSON 顶多几 MB，整份读进内存最省事：手机上拿 bytes，网页上也拿 bytes，
      // 不用为「浏览器里没有路径」再分一套实现。
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'txt'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final bytes = picked.files.first.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (mounted) toastOf(context, Lc.current.bookSourcesBadFile);
        return;
      }
      var text = utf8.decode(bytes, allowMalformed: true).trim();
      // Windows 记事本存的 JSON 开头带 BOM，不过这一关 json.decode 直接炸。
      if (text.startsWith('\uFEFF')) text = text.substring(1);
      dynamic data;
      try {
        data = json.decode(text);
      } catch (_) {
        if (mounted) toastOf(context, Lc.current.bookSourcesBadFile);
        return;
      }
      final payload = data is List ? {'sources': data} : data;
      if (payload is! Map) {
        if (mounted) toastOf(context, Lc.current.bookSourcesBadFile);
        return;
      }
      final r = await Api.post('/sources/import', Map<String, dynamic>.from(payload));
      if (!mounted) return;
      final added = r['added'] ?? 0;
      final updated = r['updated'] ?? 0;
      final skipped = r['skipped'] ?? 0;
      toastOf(
        context,
        Lc.current.bookSourcesImported(added, updated, skipped),
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) toastOf(context, e.message);
    } catch (e) {
      if (mounted) toastOf(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(Map<String, dynamic> s, bool on) async {
    final id = s['id'];
    setState(() => s['enabled'] = on);
    try {
      await Api.patch('/sources/$id', {'enabled': on});
    } catch (e) {
      if (mounted) {
        setState(() => s['enabled'] = !on);
        toastOf(context, e is ApiException ? e.message : '$e');
      }
    }
  }

  Future<void> _remove(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Lc.current.bookSourcesRemove),
        content: Text(s['name']?.toString() ?? ''),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(Lc.current.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(Lc.current.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.delete('/sources/${s['id']}');
      if (!mounted) return;
      setState(() => _list.remove(s));
      toastOf(context, Lc.current.bookSourcesRemoved);
    } on ApiException catch (e) {
      if (mounted) toastOf(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
          child: Row(
            children: [
              Icon(Icons.menu_book_outlined, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                Lc.current.bookSources,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (!_loading && _list.isNotEmpty)
                Text(
                  _probing
                      ? '探测中'
                      : '${_probe.isEmpty ? 0 : _alive}/${_list.length} 通',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              IconButton(
                tooltip: '重测连通',
                visualDensity: VisualDensity.compact,
                onPressed: _probing ? null : _probeAll,
                icon: _probing
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering, size: 19),
              ),
              const Spacer(),
              if (_busy)
                const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                TextButton.icon(
                  onPressed: _import,
                  icon: const Icon(Icons.file_open_outlined, size: 18),
                  label: Text(Lc.current.bookSourcesImport),
                ),
            ],
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: SizedBox(
              height: 18, width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )),
          )
        else if (_list.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: Text(
              Lc.current.bookSourcesEmpty,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final s in _list)
            AppCard(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 12, right: 4),
                title: Row(
                  children: [
                    Expanded(
                      // 源名长短差得离谱，状态标签跟着走，别把名字挤没了。
                      child: Text(
                        s['name']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _badge(_probe[(s['id'] as num?)?.toInt()]),
                  ],
                ),
                subtitle: Text(
                  _sub(s),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _probe[(s['id'] as num?)?.toInt()]?['ok'] == false
                        ? cs.error
                        : cs.onSurfaceVariant,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: s['enabled'] == true,
                      onChanged: (v) => _toggle(s, v),
                    ),
                    IconButton(
                      tooltip: Lc.current.delete,
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => _remove(s),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  /// 副标题：默认念地址；连不上的换成原因——地址那儿写得再全也没用。
  String _sub(Map<String, dynamic> s) {
    final p = _probe[(s['id'] as num?)?.toInt()];
    final u = s['url']?.toString() ?? '';
    if (p == null) return u;
    if (p['ok'] == true) return '$u　·　${p['ms']}ms';
    return '连不上：${p['msg'] ?? ''}';
  }

  /// v6 绿、v4 橙、断红。只走 v4 也能用，但走的是兜底隧道，
  /// 标出来是让人知道「慢或者封的时候就是这条」。
  Widget _badge(Map<String, dynamic>? p) {
    final cs = Theme.of(context).colorScheme;
    String text;
    Color fg;
    Color bg;
    if (_probing && p == null) {
      text = '…';
      fg = cs.outline;
      bg = cs.surfaceContainerHighest;
    } else if (p == null) {
      text = '未测';
      fg = cs.outline;
      bg = cs.surfaceContainerHighest;
    } else if (p['ok'] == true) {
      final v6 = p['via'] == 'v6';
      text = v6 ? 'v6' : 'v4';
      fg = v6 ? const Color(0xFF2E7D32) : const Color(0xFFE65100);
      bg = fg.withValues(alpha: .14);
    } else {
      text = '断';
      fg = cs.error;
      bg = cs.error.withValues(alpha: .14);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}
