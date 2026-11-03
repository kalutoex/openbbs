import 'package:flutter/material.dart';

import '../api.dart';
import '../utils.dart';

import '../l10n/error_text.dart';
/// 普通用户提需求：想要什么功能写清楚，提交给管理员。
/// 下面顺带列出自己提过的，状态和回复都能看见。
class FeatureRequestPage extends StatefulWidget {
  const FeatureRequestPage({super.key});

  @override
  State<FeatureRequestPage> createState() => _FeatureRequestPageState();
}

class _FeatureRequestPageState extends State<FeatureRequestPage> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  List<Map<String, dynamic>> _mine = const [];
  bool _busy = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadMine();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _toast(Object msg) {
    if (!mounted) return;
    final t = msg is String ? msg : errorText(context, msg);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _loadMine() async {
    try {
      final d = await Api.get('/feature-requests/mine');
      if (!mounted) return;
      setState(() {
        _mine =
            ((d['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
        _loaded = true;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.length < 4) {
      _toast('标题再写清楚一点');
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await Api.post('/feature-request', {
        'title': title,
        'body': _body.text.trim(),
      });
      if (!mounted) return;
      _title.clear();
      _body.clear();
      FocusScope.of(context).unfocus();
      _toast(r['duplicate'] == true ? '这条已经提过了' : '提交好了');
      await _loadMine();
    } on ApiException catch (e) {
      _toast(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('想要的新功能')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            '想到什么功能，写在这里。管理员会看，采纳了会回一句。',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            maxLength: 60,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '一句话说清要什么',
              hintText: '比如：帖子支持收藏到不同文件夹',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _body,
            maxLength: 2000,
            maxLines: 6,
            minLines: 4,
            decoration: const InputDecoration(
              labelText: '细节（可选）',
              hintText: '为什么需要、大概怎么用',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 46,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('提交'),
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Text(
                '我提过的',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (_loaded && _mine.isNotEmpty)
                Text(
                  '${_mine.length} 条',
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (!_loaded)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_mine.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  '还没提过',
                  style: TextStyle(color: cs.outline, fontSize: 13),
                ),
              ),
            )
          else
            for (final it in _mine) _card(cs, it),
        ],
      ),
    );
  }

  Widget _card(ColorScheme cs, Map<String, dynamic> it) {
    final status = (it['status'] ?? 0) as int;
    final (label, color) = switch (status) {
      1 => ('采纳', cs.primary),
      2 => ('不做', cs.error),
      _ => ('待看', cs.outline),
    };
    final note = (it['note'] ?? '') as String;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  label,
                  style: TextStyle(fontSize: 11, color: color),
                ),
              ),
              const SizedBox(width: 8),
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
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            ),
          if (note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.subdirectory_arrow_right,
                      size: 15, color: cs.outline),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      note,
                      style: TextStyle(fontSize: 13, color: cs.primary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
