import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../store.dart';

/// 账号安全：绑定或换绑邮箱。
///
/// 早一批账号注册时还没有邮箱这回事，忘了密码就只能找管理员。
/// 这里让人自己补一个，补上之后走「忘记密码」那条路就能自救。
class AccountSecurityPage extends StatefulWidget {
  const AccountSecurityPage({super.key});

  @override
  State<AccountSecurityPage> createState() => _AccountSecurityPageState();
}

class _AccountSecurityPageState extends State<AccountSecurityPage> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  Timer? _tick;
  int _cool = 0;
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _tick?.cancel();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _bound => (AppState.instance.user?['email'] as String?) ?? '';

  void _startCool(int secs) {
    _tick?.cancel();
    setState(() => _cool = secs);
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _cool = _cool > 0 ? _cool - 1 : 0);
      if (_cool == 0) t.cancel();
    });
  }

  Future<void> _send() async {
    final e = _email.text.trim();
    if (e.isEmpty) {
      setState(() => _err = '先填邮箱');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final cd = await AppState.instance.requestBindCode(e);
      if (!mounted) return;
      _startCool(cd);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('验证码发出去了，去邮箱里看看')),
      );
    } on ApiException catch (e2) {
      if (mounted) setState(() => _err = e2.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _bind() async {
    final e = _email.text.trim();
    final c = _code.text.trim();
    if (e.isEmpty || c.isEmpty) {
      setState(() => _err = '邮箱和验证码都要填');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await AppState.instance.bindEmail(e, c);
      if (!mounted) return;
      _code.clear();
      _email.clear();
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('绑好了')));
    } on ApiException catch (e2) {
      if (mounted) setState(() => _err = e2.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bound = _bound;

    return Scaffold(
      appBar: AppBar(title: const Text('账号安全')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (bound.isEmpty)
            Card(
              color: cs.errorContainer,
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: cs.onErrorContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '这个账号还没绑邮箱。忘了密码的话，现在只能找管理员重置。',
                        style: TextStyle(color: cs.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              color: cs.secondaryContainer,
              elevation: 0,
              child: ListTile(
                leading: Icon(
                  Icons.mark_email_read_outlined,
                  color: cs.onSecondaryContainer,
                ),
                title: Text(
                  bound,
                  style: TextStyle(color: cs.onSecondaryContainer),
                ),
                subtitle: Text(
                  '已绑定，忘了密码可以自己重置',
                  style: TextStyle(color: cs.onSecondaryContainer),
                ),
              ),
            ),
          const SizedBox(height: 22),
          Text(
            bound.isEmpty ? '绑定邮箱' : '换一个邮箱',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: '邮箱',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: '验证码',
                    counterText: '',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: _busy || _cool > 0 ? null : _send,
                  child: Text(_cool > 0 ? '${_cool}s' : '发送验证码'),
                ),
              ),
            ],
          ),
          if (_err != null) ...[
            const SizedBox(height: 10),
            Text(_err!, style: TextStyle(color: cs.error)),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _bind,
            child: Text(_busy ? '处理中…' : (bound.isEmpty ? '绑定' : '换绑')),
          ),
          const SizedBox(height: 22),
          Text(
            '绑了之后，忘记密码不用找人：登录页点「忘记密码」，收个验证码就能改。',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
