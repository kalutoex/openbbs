import 'package:flutter/material.dart';

import '../api.dart';
import '../store.dart';
import '../utils.dart';

/// 管理员看需求单。采纳或者不做，顺手回一句话给提交人。
class FeatureRequestsAdminPage extends StatefulWidget {
  const FeatureRequestsAdminPage({super.key});

  @override
  State<FeatureRequestsAdminPage> createState() =>
      _FeatureRequestsAdminPageState();
}

class _FeatureRequestsAdminPageState extends State<FeatureRequestsAdminPage> {
  final List<Map<String, dynamic>> _items = [];
  int _page = 1;
  int _total = 0;
  bool _done = false;
  bool _first = true;
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      if (reset) {
        _page = 1;
        _err = null;
      }
    });
    try {
      final r = await Api.get('/admin/feature-requests', query: {
        'page': '$_page',
        'done': '$_done',
      });
      final items =
          ((r['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
      setState(() {
        if (reset) _items.clear();
        _items.addAll(items);
        _total = (r['total'] ?? 0) as int;
        _first = false;
        if (!_done) AppState.instance.setFeatureOpen(_total);
      });
    } on ApiException catch (e) {
      setState(() {
        _err = e.message;
        _first = false;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handle(Map<String, dynamic> it, int status) async {
    final id = it['id'] as int;
    final ctrl = TextEditingController(
      text: (it['note'] ?? '') as String,
    );
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(switch (status) {
          1 => '采纳这条？',
          2 => '不做这条？',
          _ => '退回待看？',
        }),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (it['title'] ?? '') as String,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLength: 200,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: '回一句（可选）',
                hintText: '排期中 / 做不了，原因是……',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (go != true) {
      ctrl.dispose();
      return;
    }
    final note = ctrl.text.trim();
    ctrl.dispose();
    try {
      await Api.post(
        '/admin/feature-requests/$id?status=$status'
        '&note=${Uri.encodeQueryComponent(note)}',
        const {},
      );
      if (!mounted) return;
      setState(() {
        _items.removeWhere((e) => e['id'] == id);
        _total = _total > 0 ? _total - 1 : 0;
      });
      if (!_done) AppState.instance.setFeatureOpen(_total);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch (status) {
            1 => '已采纳',
            2 => '已标记不做',
            _ => '已退回待看',
          }),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_done
            ? '需求 · 已处理'
            : (_total > 0 ? '需求（$_total）' : '需求')),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _done = !_done;
                _first = true;
              });
              _load(reset: true);
            },
            child: Text(_done ? '看待看' : '看已处理'),
          ),
          IconButton(
            onPressed: () => _load(reset: true),
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: _first
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(cs),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_err != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_err!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => _load(reset: true),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(child: Text(_done ? '还没处理过' : '没有待看的需求'));
    }
    return ListView.separated(
      itemCount: _items.length + 1,
      separatorBuilder: (_, i) => i < _items.length - 1
          ? const Divider(height: 1, indent: 16, endIndent: 16)
          : const SizedBox.shrink(),
      itemBuilder: (ctx, i) {
        if (i == _items.length) {
          if (_items.length >= _total) return const SizedBox(height: 24);
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: TextButton(
                onPressed: () {
                  _page++;
                  _load();
                },
                child: const Text('加载更多'),
              ),
            ),
          );
        }
        final it = _items[i];
        final status = (it['status'] ?? 0) as int;
        final note = (it['note'] ?? '') as String;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (_done)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: (status == 1 ? cs.primary : cs.error)
                                .withValues(alpha: 0.5),
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          status == 1 ? '采纳' : '不做',
                          style: TextStyle(
                            fontSize: 11,
                            color: status == 1 ? cs.primary : cs.error,
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      (it['title'] ?? '') as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    timeAgo((it['created_at'] ?? 0) as int),
                    style: TextStyle(fontSize: 11, color: cs.outline),
                  ),
                ],
              ),
              if ((it['body'] ?? '') != '')
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    (it['body'] ?? '') as String,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
              if (note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '回复：$note',
                    style: TextStyle(fontSize: 12, color: cs.primary),
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                '提交人：${(it['author'] ?? '')}',
                style: TextStyle(fontSize: 11, color: cs.outline),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: _done
                    ? [
                        TextButton(
                          onPressed: () => _handle(it, 0),
                          child: const Text('退回待看'),
                        ),
                        const SizedBox(width: 8),
                      ]
                    : [
                        TextButton(
                          style: TextButton.styleFrom(
                              foregroundColor: cs.error),
                          onPressed: () => _handle(it, 2),
                          child: const Text('不做'),
                        ),
                        const SizedBox(width: 4),
                        FilledButton.tonal(
                          onPressed: () => _handle(it, 1),
                          child: const Text('采纳'),
                        ),
                        const SizedBox(width: 8),
                      ],
              ),
            ],
          ),
        );
      },
    );
  }
}
