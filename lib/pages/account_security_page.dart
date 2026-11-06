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
  // 改密码那块自己一套状态，和绑邮箱互不干扰。
  final _oldPw = TextEditingController();
  final _newPw = TextEditingController();
  final _newPw2 = TextEditingController();
  bool _seePw = false;
  bool _pwBusy = false;
  bool _rvBusy = false;
  String? _pwErr;
  Timer? _tick;
  int _cool = 0;
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _tick?.cancel();
    _email.dispose();
    _code.dispose();
    _oldPw.dispose();
    _newPw.dispose();
    _newPw2.dispose();
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

  Future<void> _changePw() async {
    final oldPw = _oldPw.text;
    final newPw = _newPw.text;
    if (oldPw.isEmpty) {
      setState(() => _pwErr = Lc.current.currentPasswordRequired);
      return;
    }
    if (newPw.length < 8) {
      setState(() => _pwErr = Lc.current.passwordTooShort);
      return;
    }
    if (newPw != _newPw2.text) {
      setState(() => _pwErr = Lc.current.passwordMismatch);
      return;
    }
    setState(() {
      _pwBusy = true;
      _pwErr = null;
    });
    try {
      await AppState.instance.changePassword(oldPw, newPw);
      if (!mounted) return;
      _oldPw.clear();
      _newPw.clear();
      _newPw2.clear();
      setState(() => _seePw = false);
      toast(context, Lc.current.passwordChanged);
    } on ApiException catch (e2) {
      if (mounted) setState(() => _pwErr = errorText(context, e2));
    } catch (e2) {
      if (mounted) {
        setState(() => _pwErr = Lc.current.passwordChangeFailed('$e2'));
      }
    } finally {
      if (mounted) setState(() => _pwBusy = false);
    }
  }

  Future<void> _revokeOthers() async {
    setState(() => _rvBusy = true);
    try {
      await AppState.instance.revokeOtherSessions();
      if (!mounted) return;
      toast(context, Lc.current.revokedOther);
    } on ApiException catch (e2) {
      if (mounted) {
        toast(context, Lc.current.revokeFailed(errorText(context, e2)));
      }
    } catch (e2) {
      if (mounted) toast(context, Lc.current.revokeFailed('$e2'));
    } finally {
      if (mounted) setState(() => _rvBusy = false);
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
            AppCard(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    Lc.current.changePassword,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _oldPw,
                    obscureText: !_seePw,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: Lc.current.currentPassword,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _newPw,
                    obscureText: !_seePw,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: Lc.current.newPassword,
                      helperText: Lc.current.atLeast8,
                      suffixIcon: IconButton(
                        tooltip: _seePw
                            ? Lc.current.hidePassword
                            : Lc.current.showPassword,
                        onPressed: () => setState(() => _seePw = !_seePw),
                        icon: Icon(
                          _seePw
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _newPw2,
                    obscureText: !_seePw,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: Lc.current.confirmPassword,
                    ),
                    onSubmitted: (_) => _pwBusy ? null : _changePw(),
                  ),
                  if (_pwErr != null) ...[
                    const SizedBox(height: 10),
                    Text(_pwErr!, style: TextStyle(color: cs.error)),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _pwBusy ? null : _changePw,
                    child: Text(
                      _pwBusy
                          ? Lc.current.processing
                          : Lc.current.changePassword,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            AppCard(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    Lc.current.revokeOtherDevices,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton(
                    onPressed: _rvBusy ? null : _revokeOthers,
                    style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                    child: Text(
                      _rvBusy
                          ? Lc.current.processing
                          : Lc.current.revokeOtherDevices,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
