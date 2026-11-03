import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import 'user_link.dart';

/// 输入框里 @ 人：盯住光标前那个 `@xxx`，去后端要候选。
///
/// 用法：把 controller 塞给 [scan]（通常挂在 addListener 里），
/// 界面上摆一个 [MentionStrip]，点了就 [insert]。
class MentionWatcher extends ChangeNotifier {
  /// 光标前必须是行首或空白，才当成要 @ 人。
  static final _tail = RegExp(r'(?:^|[\s\u3000])@([A-Za-z0-9_]*)$');

  List<Map<String, dynamic>> hits = const [];
  int _start = -1;
  String _q = '';
  Timer? _timer;
  int _seq = 0;

  bool get active => hits.isNotEmpty;

  /// 每次文本变化都调一下，开销很小。
  void scan(TextEditingController c) {
    final sel = c.selection;
    final pos = sel.baseOffset < 0 ? c.text.length : sel.baseOffset;
    final upto = c.text.substring(0, pos.clamp(0, c.text.length));
    final m = _tail.firstMatch(upto);
    if (m == null) {
      _drop();
      return;
    }
    final q = m.group(1) ?? '';
    final start = pos - q.length - 1;
    if (q == _q && start == _start && hits.isNotEmpty) return;
    _q = q;
    _start = start;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 200), () => _fetch(q));
  }

  Future<void> _fetch(String q) async {
    final my = ++_seq;
    try {
      final d = await Api.get('/mention/suggest', query: {'q': q});
      if (my != _seq) return;
      hits = (d['items'] as List).cast<Map<String, dynamic>>();
      notifyListeners();
    } catch (_) {
      if (my != _seq) return;
      _drop();
    }
  }

  /// 把 `@x` 换成人选，补个空格好继续写。
  void insert(TextEditingController c, Map<String, dynamic> hit) {
    final handle = (hit['handle'] ?? hit['name'] ?? '') as String;
    if (handle.isEmpty) return;
    final sel = c.selection;
    final pos = sel.baseOffset < 0 ? c.text.length : sel.baseOffset;
    final start = (_start >= 0 && _start <= pos) ? _start : pos;
    final next = c.text.replaceRange(start, pos, '@$handle ');
    c.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + handle.length + 2),
    );
    _drop();
  }

  void _drop() {
    _timer?.cancel();
    _q = '';
    _start = -1;
    if (hits.isNotEmpty) {
      hits = const [];
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// 候选那一行。没人要 @ 就什么也不占。
class MentionStrip extends StatelessWidget {
  final MentionWatcher watcher;
  final TextEditingController controller;

  const MentionStrip({
    super.key,
    required this.watcher,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: watcher,
      builder: (context, _) {
        if (!watcher.active) return const SizedBox.shrink();
        return SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            itemCount: watcher.hits.length,
            separatorBuilder: (context, i) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final h = watcher.hits[i];
              final handle = (h['handle'] ?? '') as String;
              final nick = (h['nickname'] ?? '') as String;
              return ActionChip(
                visualDensity: VisualDensity.compact,
                label: Text('@$handle', style: const TextStyle(fontSize: 12)),
                tooltip: nick.isEmpty ? null : nick,
                side: BorderSide(color: cs.outlineVariant),
                onPressed: () => watcher.insert(controller, h),
              );
            },
          ),
        );
      },
    );
  }
}

/// 正文渲染：认 @handle，点得动；长按仍然能选中复制。
class RichBody extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final EditableTextContextMenuBuilder? contextMenuBuilder;

  const RichBody(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.contextMenuBuilder,
  });

  static final _re = RegExp(r'@([A-Za-z0-9_]{1,32})');

  @override
  State<RichBody> createState() => _RichBodyState();
}

class _RichBodyState extends State<RichBody> {
  final List<TapGestureRecognizer> _recs = [];

  @override
  void dispose() {
    _disposeRecs();
    super.dispose();
  }

  void _disposeRecs() {
    for (final r in _recs) {
      r.dispose();
    }
    _recs.clear();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style =
        widget.style ??
        TextStyle(fontSize: 15, height: 1.5, color: cs.onSurface);
    final text = widget.text;

    _disposeRecs();
    final spans = <InlineSpan>[];
    var at = 0;
    for (final m in RichBody._re.allMatches(text)) {
      if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
      final handle = m.group(1)!;
      final rec = TapGestureRecognizer()
        ..onTap = () => openUserPage(context, handle);
      _recs.add(rec);
      spans.add(
        TextSpan(
          text: '@$handle',
          style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
          recognizer: rec,
        ),
      );
      at = m.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));

    return SelectableText.rich(
      TextSpan(style: style, children: spans),
      maxLines: widget.maxLines,
      contextMenuBuilder: widget.contextMenuBuilder,
    );
  }
}
