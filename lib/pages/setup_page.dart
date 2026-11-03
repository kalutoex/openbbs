import 'package:flutter/material.dart';

import '../api.dart';
import '../store.dart';
import 'home_page.dart';

/// 首次启动：填服务器地址。
class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _ctrl = TextEditingController(text: Api.base);
  bool _busy = false;
  String? _err;

  Future<void> _save() async {
    final v = _ctrl.text.trim();
    if (v.isEmpty) {
      setState(() => _err = '填一下地址');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    await AppState.instance.setBase(v);
    try {
      await Api.get('/forums');
      if (!mounted) return;
      Navigator.of(context)
          .pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _err = e.message;
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.forum_rounded, size: 64, color: cs.primary),
                const SizedBox(height: 16),
                Text(
                  '时间線',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  '填一下服务器地址',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _ctrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: '服务器',
                    hintText: 'http://192.168.1.10:8080',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_err != null) ...[
                  const SizedBox(height: 12),
                  Text(_err!, style: TextStyle(color: cs.error)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('连上去'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
