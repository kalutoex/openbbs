import '../widgets/app_card.dart';
import '../widgets/page_width.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../store.dart';
import '../utils.dart';

import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
import '../widgets/toast.dart';

/// 管理员：账号管理。
///
/// 只干一件事——把某个人的密码重置成随机临时密码。
/// 给那些没绑邮箱、旧设备也没留登录凭证的人用，是最后一道口子。
class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  final _q = TextEditingController();
  List<Map<String, dynamic>> _items = const [];

  /// user_id -> 云盘用量，跟 _items 一起拉回来拼着显示。
  Map<int, Map<String, dynamic>> _cloud = const {};
  bool _loading = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final items = await AppState.instance.adminUsers(_q.text.trim());
      var cloud = <int, Map<String, dynamic>>{};
      try {
        final rows = await AppState.instance.adminCloudUsage();
        cloud = {
          for (final r in rows)
            if (r['user_id'] is int) r['user_id'] as int: r,
        };
      } catch (_) {
        // 用量拿不到不影响查账号，列表照给。
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _cloud = cloud;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _err = errorText(context, e);
        _loading = false;
      });
    }
  }

  Future<void> _reset(Map<String, dynamic> u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(Lc.current.resetPassword),
        content: Text(
          Lc.current.resetPasswordConfirm(
            '${u['nickname'] ?? u['name'] ?? ''}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(Lc.current.forgetIt),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(Lc.current.reset),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final r = await AppState.instance.adminResetPw(u['id'] as int);
      if (!mounted) return;
      final pw = (r['password'] ?? '') as String;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(Lc.current.newPassword),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('给「${r['nickname'] ?? r['name']}」的新密码：'),
              const SizedBox(height: 12),
              SelectableText(
                pw,
                style: const TextStyle(
                  fontSize: 20,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: pw));
                if (c.mounted) Navigator.pop(c);
              },
              child: Text(Lc.current.copyAndClose),
            ),
          ],
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      toast(context, errorText(context, e));
    }
  }

  /// 改云盘额度。留空 / 0 = 回落到全站默认。
  Future<void> _quota(Map<String, dynamic> u) async {
    final uid = u['id'] as int;
    final info = _cloud[uid];
    final curBytes = info?['quota_bytes'];
    final curMb = curBytes is int ? (curBytes / 1024 / 1024).round() : 0;
    final ed = TextEditingController(text: curMb > 0 ? '$curMb' : '');
    final name = '${u['nickname'] ?? u['name'] ?? ''}';
    final saved = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(Lc.current.changeQuota),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontSize: 13)),
            if (info != null)
              Text(
                '${Lc.current.cloudUsage}：'
                '${bytesShort(info['used'] as int? ?? 0)} / '
                '${info['quota'] is int ? bytesShort(info['quota'] as int) : Lc.current.cloudQuotaDefault}',
                style: const TextStyle(fontSize: 12),
              ),
            const SizedBox(height: 10),
            TextField(
              autocorrect: false,
              enableSuggestions: false,
              controller: ed,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText: Lc.current.quotaMbHint,
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(Lc.current.cancel),
          ),
          FilledButton(
            onPressed: () {
              final mb = int.tryParse(ed.text.trim()) ?? 0;
              Navigator.pop(c, mb);
            },
            child: Text(Lc.current.save),
          ),
        ],
      ),
    );
    ed.dispose();
    if (saved == null || !mounted) return;
    try {
      await AppState.instance.adminSetCloudQuota(uid, saved);
      if (!mounted) return;
      toast(context, Lc.current.quotaSaved);
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      toast(context, errorText(context, e));
    }
  }

  /// 一行用量文字：1.2G / 5G。拿不到就 --。
  String _cloudText(int uid) {
    final info = _cloud[uid];
    if (info == null) return '-- / --';
    final used = info['used'] is int ? bytesShort(info['used'] as int) : '--';
    final q = info['quota'];
    final total = q is int ? bytesShort(q) : Lc.current.cloudQuotaDefault;
    return '$used / $total';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(Lc.current.accountManagement),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              autocorrect: false,
              enableSuggestions: false,
              controller: _q,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: Lc.current.searchUsername,
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _load,
                ),
              ),
            ),
          ),
        ),
      ),
      body: PageWidth(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _err != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_err!, style: TextStyle(color: cs.error)),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _load,
                      child: Text(Lc.current.retry),
                    ),
                  ],
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                itemCount: _items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final u = _items[i];
                  final mail = (u['email'] ?? '') as String;
                  return AppCard(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              (u['nickname'] ?? u['name']) as String,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (u['is_admin'] == true) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.shield_outlined,
                              size: 14,
                              color: cs.primary,
                            ),
                          ],
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            mail.isEmpty ? Lc.current.noEmail : mail,
                            style: mail.isEmpty
                                ? TextStyle(color: cs.error, fontSize: 12)
                                : const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 3),
                          InkWell(
                            onTap: () => _quota(u),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.cloud_outlined,
                                  size: 13,
                                  color: cs.outline,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  _cloudText(u['id'] as int),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.outline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      trailing: TextButton(
                        onPressed: () => _reset(u),
                        child: Text(Lc.current.resetPassword),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
