import 'package:flutter/material.dart';

import '../api.dart';
import '../site_config.dart';
import '../store.dart';

import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
/// 首次启动：站点表是空的，先要一个地址。
///
/// 包里有出厂种子，导入过清单也不会走到这儿。真走到这儿说明一个地址都没有，
/// 手填一个就能开始——连上之后由站点表接管，这里不再管选路。
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
      setState(() => _err = Lc.current.fillAddress);
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final ok = await AppState.instance.setBase(v);
      if (!mounted) return;
      if (!ok) {
        // 连不上也入表了，标灰；人在这儿能改地址再试，不用去设置里找。
        setState(() {
          _busy = false;
          _err = Lc.current.connectFailedBody(v);
        });
        return;
      }
      // 不用自己跳页：站点表一有站，外层就换成首页了。
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _err = errorText(context, e);
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
                  SiteConfig.brand,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  Lc.current.siteEmptyHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _ctrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: Lc.current.serverAddress,
                    hintText: 'http://192.168.1.10:8080',
                    helperText: Lc.current.siteAddHint,
                    helperMaxLines: 3,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _busy ? null : _save(),
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
                      : Text(Lc.current.connect),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
