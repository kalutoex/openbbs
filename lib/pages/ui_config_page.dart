import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../ui_config.dart';
import '../widgets/page_width.dart';
import '../widgets/toast.dart';

import '../l10n/error_text.dart';
import '../l10n/l10n.dart';

/// 管理员：界面参数。
///
/// 卡片高度、边距、字号这些纯视觉的数字放在服务端，改完不用重新发包。
/// 这里就是一个 JSON 编辑器——参数种类会越来越多，做成表单反而要被表单绑住。
/// 键名和允许范围见服务端 UI_SPEC，写错会被打回并告诉你是哪一条。
class UiConfigPage extends StatefulWidget {
  const UiConfigPage({super.key});

  @override
  State<UiConfigPage> createState() => _UiConfigPageState();
}

class _UiConfigPageState extends State<UiConfigPage> {
  final _text = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final d = await Api.get('/ui/config');
      final vals = (d is Map && d['values'] is Map)
          ? Map<String, dynamic>.from(d['values'] as Map)
          : <String, dynamic>{};
      if (mounted) {
        setState(() {
          _text.text = const JsonEncoder.withIndent('  ').convert(vals);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = errorText(context, e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    dynamic parsed;
    try {
      parsed = jsonDecode(_text.text.trim().isEmpty ? '{}' : _text.text);
    } catch (_) {
      toast(context, Lc.current.uiConfigBadJson);
      return;
    }
    if (parsed is! Map) {
      toast(context, Lc.current.uiConfigBadJson);
      return;
    }
    setState(() => _saving = true);
    try {
      final d = await Api.post('/admin/ui/config', {
        'values': Map<String, dynamic>.from(parsed),
      });
      // 本地立刻跟着换，返回上一页就能看出差别。
      await UiConfig.refresh();
      if (!mounted) return;
      final rej = (d is Map ? d['rejected'] : null);
      if (rej is List && rej.isNotEmpty) {
        final lines = rej.map((e) => '${e['key']}: ${e['why']}').join('\n');
        toast(context, Lc.current.uiConfigRejected(rej.length, lines));
      } else {
        toast(context, Lc.current.uiConfigSaved);
      }
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _fillDefaults() {
    setState(() {
      _text.text = const JsonEncoder.withIndent('  ')
          .convert(Map<String, dynamic>.from(UiConfig.defaults));
    });
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _text.text));
    if (mounted) toast(context, Lc.current.copied);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(Lc.current.uiConfigTitle),
        actions: [
          IconButton(
            tooltip: Lc.current.uiConfigDefaults,
            onPressed: _fillDefaults,
            icon: const Icon(Icons.settings_backup_restore),
          ),
          IconButton(
            tooltip: Lc.current.copy,
            onPressed: _copy,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              ),
            )
          else
            IconButton(
              tooltip: Lc.current.save,
              onPressed: _loading ? null : _save,
              icon: const Icon(Icons.check),
            ),
        ],
      ),
      body: PageWidth(
        max: 760,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  Text(
                    Lc.current.uiConfigHint,
                    style: t.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  if (_err != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _err!,
                      style: t.textTheme.bodySmall?.copyWith(color: cs.error),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    autocorrect: false,
                    enableSuggestions: false,
                    controller: _text,
                    maxLines: null,
                    minLines: 18,
                    style: t.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      height: 1.45,
                    ),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      isDense: true,
                      hintText: '{"fileCard.height": 80}',
                      hintStyle: TextStyle(color: cs.outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          Lc.current.uiConfigKeys,
                          style: t.textTheme.bodySmall?.copyWith(
                            color: cs.outline,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
