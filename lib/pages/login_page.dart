import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../store.dart';

import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _name = TextEditingController();
  final _pw = TextEditingController();
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _register = false;
  bool _reset = false;
  bool _busy = false;
  bool _sending = false;
  int _cooldown = 0;
  Timer? _tick;
  String? _err;

  @override
  void dispose() {
    _tick?.cancel();
    _name.dispose();
    _pw.dispose();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _useToken() async {
    final ctl = TextEditingController();
    final tok = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(Lc.current.pasteCredential),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          decoration: InputDecoration(hintText: Lc.current.credentialHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(Lc.current.forgetIt),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, ctl.text),
            child: Text(Lc.current.restore),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (tok == null || tok.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final ok = await AppState.instance.useToken(tok);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _err = Lc.current.credentialInvalid);
      }
    } catch (e) {
      if (mounted) setState(() => _err = Lc.current.restoreFailed('${e}'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startCooldown(int secs) {
    _tick?.cancel();
    setState(() => _cooldown = secs);
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _cooldown = _cooldown > 0 ? _cooldown - 1 : 0);
      if (_cooldown == 0) t.cancel();
    });
  }

  Future<void> _sendCode() async {
    final e = _email.text.trim();
    if (e.isEmpty) {
      setState(() => _err = Lc.current.fillEmailFirst);
      return;
    }
    setState(() {
      _sending = true;
      _err = null;
    });
    try {
      final wait = _reset
          ? await AppState.instance.requestResetCode(e)
          : await AppState.instance.requestCode(e);
      if (!mounted) return;
      _startCooldown(wait);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _err = errorText(context, e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = Lc.current.codeSendFailed('${e}'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _submit() async {
    final n = _name.text.trim();
    final p = _pw.text;
    final e = _email.text.trim();
    final code = _code.text.trim();
    if (_reset) {
      if (p.length < 8) {
        setState(() => _err = Lc.current.passwordTooShort);
        return;
      }
      if (e.isEmpty || code.isEmpty) {
        setState(() => _err = Lc.current.emailAndCodeRequired);
        return;
      }
      setState(() {
        _busy = true;
        _err = null;
      });
      try {
        await AppState.instance.resetPassword(e, code, p);
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() => _err = errorText(context, e));
      } catch (e) {
        if (!mounted) return;
        setState(() => _err = Lc.current.passwordChangeFailed('${e}'));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    if (n.isEmpty || p.isEmpty) {
      setState(() => _err = Lc.current.fillUserAndPassword);
      return;
    }
    if (_register && (e.isEmpty || code.isEmpty)) {
      setState(() => _err = Lc.current.emailAndCodeRequired);
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      if (_register) {
        await AppState.instance.register(n, p, e, code);
      } else {
        await AppState.instance.login(n, p);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _err = errorText(context, e));
    } catch (e) {
      // 不是 ApiException 的意外（解析、存储写入失败之类）以前会漏出去，
      // _busy 停在 true，看着就是登录页一直转圈。
      if (!mounted) return;
      setState(() => _err = Lc.current.loginFailed('${e}'));
    } finally {
      // 不管成没成，转圈都得停。pop 之后 mounted 为 false，不会碰已销毁的 State。
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_reset ? Lc.current.resetTitle : (_register ? Lc.current.register : Lc.current.login)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          children: [
            Icon(Icons.forum_rounded, size: 56, color: cs.primary),
            const SizedBox(height: 24),
            if (!_reset) ...[
              TextField(
                controller: _name,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: Lc.current.username,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: _pw,
              obscureText: true,
              decoration: InputDecoration(
                labelText: _reset ? Lc.current.newPassword : Lc.current.password,
                helperText: (_register || _reset) ? Lc.current.atLeast8 : null,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_register || _reset) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: Lc.current.email,
                  hintText: _reset ? Lc.current.emailUsedToRegister : Lc.current.emailForCode,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: Lc.current.code,
                  border: const OutlineInputBorder(),
                  suffixIcon: TextButton(
                    onPressed: (_sending || _cooldown > 0 || _busy)
                        ? null
                        : _sendCode,
                    child: Text(
                      _cooldown > 0
                          ? '${_cooldown}s'
                          : (_sending ? Lc.current.sending : Lc.current.getCode),
                    ),
                  ),
                ),
              ),
            ],
            if (_err != null) ...[
              const SizedBox(height: 12),
              Text(_err!, style: TextStyle(color: cs.error, fontSize: 13)),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_reset ? Lc.current.changePasswordAndLogin : (_register ? Lc.current.registerAndLogin : Lc.current.login)),
            ),
            const SizedBox(height: 6),
            if (_reset)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _reset = false;
                        _err = null;
                      }),
                child: Text(Lc.current.backToLogin),
              )
            else ...[
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _register = !_register;
                        _err = null;
                      }),
                child: Text(_register ? Lc.current.haveAccountLogin : Lc.current.noAccountRegister),
              ),
              if (!_register)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _reset = true;
                          _err = null;
                        }),
                  child: Text(Lc.current.forgotPasswordQuestion),
                ),
            ],
            if (!_register && !_reset)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton.icon(
                  onPressed: _busy ? null : _useToken,
                  icon: const Icon(Icons.key_outlined, size: 16),
                  label: Text(Lc.current.restoreWithCredential),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
