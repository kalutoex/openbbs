import 'dart:async';

import '../widgets/page_width.dart';
import '../widgets/app_card.dart';

import 'package:flutter/material.dart';

import '../api.dart';
import '../store.dart';

import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
import '../widgets/toast.dart';

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
      setState(() => _err = Lc.current.fillEmailFirst);
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
      toast(context, Lc.current.codeSentCheckEmail);
    } on ApiException catch (e2) {
      if (mounted) setState(() => _err = errorText(context, e2));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _bind() async {
    final e = _email.text.trim();
    final c = _code.text.trim();
    if (e.isEmpty || c.isEmpty) {
      setState(() => _err = Lc.current.emailAndCodeRequired);
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
      toast(context, Lc.current.emailBound);
    } on ApiException catch (e2) {
      if (mounted) setState(() => _err = errorText(context, e2));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bound = _bound;

    return Scaffold(
      appBar: AppBar(title: Text(Lc.current.accountSecurity)),
      body: PageWidth(
        max: 520,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
                          Lc.current.noEmailWarning,
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
                    Lc.current.emailBoundHint,
                    style: TextStyle(color: cs.onSecondaryContainer),
                  ),
                ),
              ),
            const SizedBox(height: 22),
            AppCard(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    bound.isEmpty
                        ? Lc.current.bindEmail
                        : Lc.current.changeEmail,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(labelText: Lc.current.email),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _code,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          decoration: InputDecoration(
                            labelText: Lc.current.code,
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: _busy || _cool > 0 ? null : _send,
                          child: Text(
                            _cool > 0 ? '${_cool}s' : Lc.current.sendCode,
                          ),
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
                    child: Text(
                      _busy
                          ? Lc.current.processing
                          : (bound.isEmpty
                                ? Lc.current.bind
                                : Lc.current.rebind),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text(
              Lc.current.bindEmailWhy,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
