import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../store.dart';
import '../widgets/app_card.dart';
import '../widgets/page_width.dart';

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
  // 人机校验：服务端开了才出题，没开就是空串，界面上不显示。
  final _chAns = TextEditingController();
  String _chId = '';
  String _chSig = '';
  String _chQ = '';
  bool _showPw = false;
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
    _chAns.dispose();
    super.dispose();
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

  Future<void> _loadChallenge() async {
    final d = await AppState.instance.fetchChallenge();
    if (!mounted) return;
    setState(() {
      _chQ = (d?['question'] ?? '') as String;
      _chId = (d?['id'] ?? '') as String;
      _chSig = (d?['sig'] ?? '') as String;
      _chAns.clear();
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
      setState(() => _err = Lc.current.codeSendFailed('$e'));
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
        setState(() => _err = Lc.current.passwordChangeFailed('$e'));
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
        await AppState.instance.register(
          n,
          p,
          e,
          code,
          challengeId: _chId,
          challengeAnswer: _chAns.text.trim(),
          challengeSig: _chSig,
        );
      } else {
        await AppState.instance.login(n, p);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _err = errorText(context, e));
      if (_register && _chQ.isNotEmpty && e.message.contains('题')) {
        _loadChallenge();
      }
    } catch (e) {
      // 不是 ApiException 的意外（解析、存储写入失败之类）以前会漏出去，
      // _busy 停在 true，看着就是登录页一直转圈。
      if (!mounted) return;
      setState(() => _err = Lc.current.loginFailed('$e'));
    } finally {
      // 不管成没成，转圈都得停。pop 之后 mounted 为 false，不会碰已销毁的 State。
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = _reset
        ? Lc.current.resetTitle
        : (_register ? Lc.current.register : Lc.current.login);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: PageWidth(
          max: 460,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
            children: [
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.forum_rounded, size: 34, color: cs.primary),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              AppCard(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_reset) ...[
                      TextField(
                        controller: _name,
                        autocorrect: false,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: Lc.current.usernameOrEmail,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _pw,
                      obscureText: !_showPw,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: _reset
                            ? Lc.current.newPassword
                            : Lc.current.password,
                        helperText: (_register || _reset)
                            ? Lc.current.atLeast8
                            : null,
                        suffixIcon: IconButton(
                          tooltip: _showPw
                              ? Lc.current.hidePassword
                              : Lc.current.showPassword,
                          onPressed: () => setState(() => _showPw = !_showPw),
                          icon: Icon(
                            _showPw
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                        ),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                    if (_register || _reset) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: Lc.current.email,
                          hintText: _reset
                              ? Lc.current.emailUsedToRegister
                              : Lc.current.emailForCode,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _code,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: Lc.current.code,
                          suffixIcon: TextButton(
                            onPressed: (_sending || _cooldown > 0 || _busy)
                                ? null
                                : _sendCode,
                            child: Text(
                              _cooldown > 0
                                  ? '${_cooldown}s'
                                  : (_sending
                                        ? Lc.current.sending
                                        : Lc.current.getCode),
                            ),
                          ),
                        ),
                      ),
                      if (_register && _chQ.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _chAns,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: _chQ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              if (_err != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 16,
                        color: cs.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _err!,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: cs.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _reset
                            ? Lc.current.changePasswordAndLogin
                            : (_register
                                  ? Lc.current.registerAndLogin
                                  : Lc.current.login),
                      ),
              ),
              const SizedBox(height: 4),
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
                      : () {
                          setState(() {
                            _register = !_register;
                            _err = null;
                          });
                          if (_register) _loadChallenge();
                        },
                  child: Text(
                    _register
                        ? Lc.current.haveAccountLogin
                        : Lc.current.noAccountRegister,
                  ),
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
            ],
          ),
        ),
      ),
    );
  }
}
