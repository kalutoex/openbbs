import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../downloads.dart';
import '../l10n/l10n.dart';
import '../widgets/toast.dart';

/// 云服务设置：下载的文件到底存哪，下完要不要自动打开，残留的下载要不要清。
///
/// 这一页就是「文件下到哪了」这个问题的答案页面，所以位置那行要一直可见，
/// 不能藏在二级菜单里。
class CloudSettingsPage extends StatefulWidget {
  const CloudSettingsPage({super.key});

  @override
  State<CloudSettingsPage> createState() => _CloudSettingsPageState();
}

class _CloudSettingsPageState extends State<CloudSettingsPage> {
  String _where = '';
  bool _autoOpen = true;
  int _cache = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final where = await DownloadPrefs.label();
    final auto = await DownloadPrefs.autoOpen();
    final cache = await downloadCacheSize();
    if (!mounted) return;
    setState(() {
      _where = where;
      _autoOpen = auto;
      _cache = cache;
      _loading = false;
    });
  }

  Future<void> _pick() async {
    try {
      final dir = await pickDownloadDir();
      if (dir == null) return;
      await _load();
      if (mounted) toast(context, Lc.current.savedTo(dir));
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Future<void> _reset() async {
    await resetDownloadDir();
    await _load();
    if (mounted) toast(context, Lc.current.downloadDirReset);
  }

  Future<void> _clearCache() async {
    await clearDownloadCache();
    await _load();
    if (mounted) toast(context, Lc.current.cacheCleared);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(Lc.current.cloudSettings)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    Lc.current.cloudSettingsIntro,
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ),
                if (!kIsWeb) ...[
                  const Divider(height: 32),
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(Lc.current.downloadLocation),
                    subtitle: Text(
                      _where.isEmpty ? Lc.current.downloadLocationDefault : _where,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pick,
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings_backup_restore),
                    title: Text(Lc.current.downloadLocationReset),
                    subtitle: Text(Lc.current.downloadLocationDefaultHint),
                    onTap: _reset,
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.open_in_new),
                    title: Text(Lc.current.downloadAutoOpen),
                    subtitle: Text(Lc.current.downloadAutoOpenHint),
                    value: _autoOpen,
                    onChanged: (v) async {
                      setState(() => _autoOpen = v);
                      await DownloadPrefs.setAutoOpen(v);
                    },
                  ),
                  const Divider(height: 32),
                  ListTile(
                    leading: const Icon(Icons.cleaning_services_outlined),
                    title: Text(Lc.current.downloadCache),
                    subtitle: Text(
                      _cache > 0
                          ? Lc.current.downloadCacheUsed(sizeText(_cache))
                          : Lc.current.downloadCacheEmpty,
                    ),
                    trailing: _cache > 0
                        ? TextButton(
                            onPressed: _clearCache,
                            child: Text(Lc.current.clear),
                          )
                        : null,
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Text(
                      Lc.current.downloadByBrowser,
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
    );
  }
}
