import 'dart:async';

import 'package:flutter/material.dart';

import '../cloud.dart';
import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
import '../trash.dart';
import '../utils.dart';
import '../widgets/empty_view.dart';
import '../widgets/file_card.dart';
import '../widgets/page_width.dart';
import '../widgets/toast.dart';

/// 管理员回收站：我以管理员身份删掉的普通用户内容。
///
/// 原主人那边什么都看不到（不进他的回收站、不占他的额度），
/// 所以这条线只有管理员看得到，也就只能在这儿捞回来。
class AdminTrashPage extends StatefulWidget {
  const AdminTrashPage({super.key});

  @override
  State<AdminTrashPage> createState() => _AdminTrashPageState();
}

typedef _Item = ({String kind, int id, String title, int ownerId,
    String ownerName, String ownerHandle, int deletedAt, String sub});

class _AdminTrashPageState extends State<AdminTrashPage> {
  List<_Item>? _items;
  bool _failed = false;
  bool _busy = false;

  /// all / thread / file
  String _kind = 'all';
  int _owner = 0;
  bool _showFilters = false;

  final TextEditingController _search = TextEditingController();
  String _q = '';
  Timer? _debounce;

  /// 见过的原主人。筛选面板从这儿出，不额外打接口。
  final Map<int, String> _owners = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      if (_items == null) _failed = false;
    });
    final out = <_Item>[];
    try {
      if (_kind != 'file') {
        for (final t in await TrashApi.adminThreads(q: _q, owner: _owner)) {
          _owners[t.ownerId] = t.ownerName.isNotEmpty
              ? t.ownerName
              : t.ownerHandle;
          out.add((
            kind: 'thread',
            id: t.id,
            title: t.title,
            ownerId: t.ownerId,
            ownerName: t.ownerName,
            ownerHandle: t.ownerHandle,
            deletedAt: t.deletedAt,
            sub: Lc.current.repliesCount('${t.replyCount}'),
          ));
        }
      }
      if (_kind != 'thread') {
        for (final f in await TrashApi.adminCloud(q: _q, owner: _owner)) {
          _owners[f.ownerId] = f.ownerName.isNotEmpty
              ? f.ownerName
              : f.ownerHandle;
          out.add((
            kind: 'file',
            id: f.file.id,
            title: f.file.name,
            ownerId: f.ownerId,
            ownerName: f.ownerName,
            ownerHandle: f.ownerHandle,
            deletedAt: f.deletedAt,
            sub: bytesText(f.file.size),
          ));
        }
      }
      out.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
      if (!mounted) return;
      setState(() {
        _items = out;
        _busy = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  Future<void> _restore(_Item it) async {
    try {
      if (it.kind == 'thread') {
        await TrashApi.restoreThread(it.id);
      } else {
        await TrashApi.adminRestoreCloud(it.id);
      }
      if (!mounted) return;
      setState(() => _items?.removeWhere((x) => x.kind == it.kind && x.id == it.id));
      toast(context, Lc.current.restored);
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    }
  }

  Future<void> _purge(_Item it) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Lc.current.deleteForever),
        content: Text(Lc.current.deleteForeverHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(Lc.current.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(Lc.current.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (it.kind == 'thread') {
        await TrashApi.purgeThread(it.id);
      } else {
        await TrashApi.adminPurgeCloud(it.id);
      }
      if (!mounted) return;
      setState(() => _items?.removeWhere((x) => x.kind == it.kind && x.id == it.id));
      toast(context, Lc.current.deletedForever);
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    }
  }

  Future<void> _pickOwner() async {
    final ids = _owners.keys.toList()..sort();
    final v = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: Text(Lc.current.allOwners),
              selected: _owner == 0,
              onTap: () => Navigator.pop(ctx, 0),
            ),
            for (final id in ids)
              ListTile(
                title: Text(_owners[id] ?? '#$id'),
                selected: _owner == id,
                onTap: () => Navigator.pop(ctx, id),
              ),
          ],
        ),
      ),
    );
    if (v == null || !mounted) return;
    setState(() => _owner = v);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = _items;
    return Scaffold(
      appBar: AppBar(
        title: Text(Lc.current.adminTrash),
        actions: [
          IconButton(
            tooltip: Lc.current.filter,
            icon: Icon(
              _showFilters ? Icons.filter_alt : Icons.filter_alt_outlined,
            ),
            onPressed: () => setState(() => _showFilters = !_showFilters),
          ),
          IconButton(
            tooltip: Lc.current.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: PageWidth(
        child: Column(
          children: [
            if (_showFilters)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        hintText: Lc.current.search,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        _debounce?.cancel();
                        setState(() => _q = v);
                        _debounce = Timer(
                          const Duration(milliseconds: 350),
                          _load,
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(Lc.current.allKinds),
                          selected: _kind == 'all',
                          onSelected: (_) {
                            if (_kind == 'all') return;
                            setState(() => _kind = 'all');
                            _load();
                          },
                        ),
                        ChoiceChip(
                          label: Text(Lc.current.trashThreadsTab),
                          selected: _kind == 'thread',
                          onSelected: (_) {
                            if (_kind == 'thread') return;
                            setState(() => _kind = 'thread');
                            _load();
                          },
                        ),
                        ChoiceChip(
                          label: Text(Lc.current.trashFilesTab),
                          selected: _kind == 'file',
                          onSelected: (_) {
                            if (_kind == 'file') return;
                            setState(() => _kind = 'file');
                            _load();
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.person_outline, size: 18),
                          label: Text(
                            _owner == 0
                                ? Lc.current.allOwners
                                : (_owners[_owner] ?? '#$_owner'),
                          ),
                          onPressed: _pickOwner,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: items == null
                    ? Center(
                        child: _failed
                            ? TextButton(
                                onPressed: _load,
                                child: Text(Lc.current.notConnectedTapRetry),
                              )
                            : const CircularProgressIndicator(),
                      )
                    : items.isEmpty
                    ? EmptyView(
                        icon: Icons.admin_panel_settings_outlined,
                        title: Lc.current.adminTrashEmpty,
                        hint: Lc.current.adminTrashHint,
                      ).scrollable()
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final it = items[i];
                          final who = it.ownerName.isNotEmpty
                              ? it.ownerName
                              : (it.ownerHandle.isNotEmpty
                                    ? '@${it.ownerHandle}'
                                    : '#${it.ownerId}');
                          return ListTile(
                            leading: Icon(
                              it.kind == 'thread'
                                  ? Icons.article_outlined
                                  : fileIconFor(it.title),
                              color: cs.outline,
                            ),
                            title: Text(
                              it.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '$who · ${it.sub} · ${timeAgo(it.deletedAt)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: () => _restore(it),
                                  child: Text(Lc.current.restore),
                                ),
                                IconButton(
                                  tooltip: Lc.current.deleteForever,
                                  icon: Icon(
                                    Icons.delete_forever,
                                    color: cs.error,
                                  ),
                                  onPressed: () => _purge(it),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
