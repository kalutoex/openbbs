import 'package:flutter/material.dart';

import '../api.dart';
import '../store.dart';

import '../l10n/l10n.dart';
/// 服务器选路：自动 / 仅 IPv6 / 仅 IPv4 / 手动。
class ServerPage extends StatefulWidget {
  const ServerPage({super.key});

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  late ServerMode _mode = AppState.instance.serverMode;
  late final TextEditingController _ctrl = TextEditingController(
    text: Api.base == Api.chIpv6 || Api.base == Api.chIpv4 ? '' : Api.base,
  );
  bool _busy = false;
  String? _msg;
  bool _ok = false;

  Future<void> _save() async {
    final v = _ctrl.text.trim();
    if (_mode == ServerMode.manual) {
      if (v.isEmpty) {
        setState(() {
          _ok = false;
          _msg = Lc.current.manualNeedsAddress;
        });
        return;
      }
      await AppState.instance.setBase(v);
    } else {
      await AppState.instance.setServerMode(_mode);
    }

    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await Api.get('/feed');
      setState(() {
        _ok = true;
        _msg = Lc.current.serverOkUsing('${Api.base}');
      });
    } catch (e) {
      setState(() {
        _ok = false;
        _msg = Lc.current.connectFailedBody('${e}');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
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
      appBar: AppBar(title: Text(Lc.current.server)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          RadioGroup<ServerMode>(
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v ?? ServerMode.auto),
            child: Column(
              children: [
                RadioListTile<ServerMode>(
                  value: ServerMode.auto,
                  title: Text(Lc.current.auto),
                  subtitle: Text(Lc.current.ipv6FirstHint),
                ),
                RadioListTile<ServerMode>(
                  value: ServerMode.ipv6,
                  title: Text(Lc.current.channelIpv6),
                  subtitle: Text(Api.chIpv6),
                ),
                RadioListTile<ServerMode>(
                  value: ServerMode.ipv4,
                  title: Text(Lc.current.channelIpv4),
                  subtitle: Text(Api.chIpv4),
                ),
                RadioListTile<ServerMode>(
                  value: ServerMode.manual,
                  title: Text(Lc.current.manual),
                  subtitle: Text(Lc.current.enterManually),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            enabled: _mode == ServerMode.manual,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: Lc.current.serverAddress,
              hintText: 'http://192.168.1.10:8080',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(Lc.current.saveAndTest),
          ),
          if (_msg != null) ...[
            const SizedBox(height: 14),
            Text(
              _msg!,
              style: TextStyle(color: _ok ? cs.primary : cs.error),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            Lc.current.currentExit('${Api.base}'),
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
