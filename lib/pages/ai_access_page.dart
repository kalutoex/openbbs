import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets/page_width.dart';
import '../widgets/toast.dart';

/// AI 接入：把自己的账号交给一个 OneBot v11 实现（AstrBot 等）。
///
/// 页面本身只管配置。真正连出去的是服务端：它拿着这里的地址主动连过去，
/// 所以关掉 App 也不会断，人不在也能回话。
class AiAccessPage extends StatefulWidget {
  const AiAccessPage({super.key});

  @override
  State<AiAccessPage> createState() => _AiAccessPageState();
}

class _AiAccessPageState extends State<AiAccessPage> {
  final _ws = TextEditingController();
  final _token = TextEditingController();
  final _pw = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  bool _online = false;
  bool _hasToken = false;
  int _seenAt = 0;
  String _error = '';
  String _savedWs = '';

  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    // 在线状态是服务端算的，十秒刷一次就够了，别做成秒表。
    _tick = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && !_saving) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _ws.dispose();
    _token.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final d = await Api.get('/me/ai');
      final m = (d is Map && d['data'] is Map) ? d['data'] as Map : d as Map;
      if (!mounted) return;
      setState(() {
        _enabled = m['enabled'] == true;
        _hasToken = m['has_token'] == true;
        _online = m['online'] == true;
        _seenAt = (m['seen_at'] as num?)?.toInt() ?? 0;
        _error = (m['error'] ?? '').toString();
        _savedWs = (m['ws'] ?? '').toString();
        if (!silent || _ws.text.isEmpty) _ws.text = _savedWs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (!silent && mounted) {
        toastOf(context, '读取失败：$e');
      }
    }
  }

  Future<void> _save() async {
    final ws = _ws.text.trim();
    if (ws.isEmpty) {
      if (mounted) {
        toastOf(context, '先填地址');
      }
      return;
    }
    final needPw = _enabled && (ws != _savedWs || _token.text.isNotEmpty);
    if (needPw && _pw.text.isEmpty) {
      if (mounted) {
        toastOf(context, '改配置要输一次密码');
      }
      return;
    }
    setState(() => _saving = true);
    try {
      await Api.put('/me/ai', {
        'enabled': _enabled,
        'ws': ws,
        'token': _token.text.trim(),
        'pw': _pw.text,
      });
      _pw.clear();
      _token.clear();
      await _load();
      if (!mounted) return;
      if (mounted) {
        toastOf(context, _enabled ? '保存了，正在连' : '已关闭');
      }
    } catch (e) {
      if (mounted) {
        toastOf(context, '$e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _statusText {
    if (!_enabled) return '未开启';
    if (_online) return '已连接';
    if (_error.isNotEmpty) return '连不上';
    return '等待连接';
  }

  Color _statusColor(ColorScheme cs) {
    if (!_enabled) return cs.outline;
    if (_online) return const Color(0xFF3BA55D);
    if (_error.isNotEmpty) return cs.error;
    return const Color(0xFFB08A2E);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('AI 接入')),
      body: PageWidth(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: [
                  _card(cs, [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _statusColor(cs),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _statusText,
                          style: TextStyle(
                            color: _statusColor(cs),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        if (_seenAt > 0)
                          Text(
                            '上次连上 ${_ago(_seenAt)}',
                            style: TextStyle(fontSize: 12, color: cs.outline),
                          ),
                      ],
                    ),
                    if (_error.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error,
                        style: TextStyle(fontSize: 12, color: cs.error),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 12),
                  _card(cs, [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('把这个账号交给 AI'),
                      subtitle: const Text('开着的时候，别人发来的私信和帖子评论会转给 AstrBot 处理'),
                      value: _enabled,
                      onChanged: (v) => setState(() => _enabled = v),
                    ),
                    const Divider(height: 24),
                    TextField(
                      controller: _ws,
                      decoration: const InputDecoration(
                        labelText: 'AstrBot 的 WS 地址',
                        hintText: 'ws://127.0.0.1:6199/onebot/v11/ws',
                        helperText: '在 AstrBot 里加一个 aiocqhttp 适配器，把它的端口填在这儿',
                      ),
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _token,
                      obscureText: true,
                      keyboardType: TextInputType.visiblePassword,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: '访问令牌',
                        hintText: _hasToken
                            ? '已设置，不改就留空'
                            : '适配器里配的 access_token',
                      ),
                      autocorrect: false,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      autocorrect: false,
                      enableSuggestions: false,
                      controller: _pw,
                      obscureText: true,
                      keyboardType: TextInputType.visiblePassword,
                      decoration: const InputDecoration(
                        labelText: '账号密码',
                        helperText: '开启或改地址时验一次，防着别人拿到你手机就能接管',
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _card(cs, [
                    const Text(
                      '接入之后',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    _line('· 只有互相关注的人能私信她，别人的消息进不来'),
                    _line('· 她只回互关的人在帖子下面的评论'),
                    _line('· 关掉 App 不影响，连接在服务端跑'),
                    _line('· 私信内容会进 AstrBot 的模型请求，跟聊天软件里一样'),
                  ]),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('保存'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _card(ColorScheme cs, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _line(String s) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(s, style: const TextStyle(fontSize: 13, height: 1.5)),
  );

  String _ago(int ts) {
    final d = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(ts * 1000),
    );
    if (d.inSeconds < 60) return '${d.inSeconds} 秒前';
    if (d.inMinutes < 60) return '${d.inMinutes} 分钟前';
    if (d.inHours < 24) return '${d.inHours} 小时前';
    return '${d.inDays} 天前';
  }
}
