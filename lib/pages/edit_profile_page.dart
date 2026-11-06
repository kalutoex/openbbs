import '../widgets/page_width.dart';
import '../widgets/app_card.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../plat.dart';
import '../img_compress.dart';
import '../store.dart';
import 'gallery_picker_page.dart';

import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
import '../widgets/toast.dart';

/// 改自己的昵称、@标识、签名、头像。
class EditProfilePage extends StatefulWidget {
  final Map<String, dynamic> info;

  const EditProfilePage({super.key, required this.info});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late final TextEditingController _nick = TextEditingController(
    text:
        (AppState.instance.user?['nickname'] ?? widget.info['nickname'] ?? '')
            as String,
  );
  late final TextEditingController _tag = TextEditingController(
    text:
        (AppState.instance.user?['handle'] ?? widget.info['handle'] ?? '')
            as String,
  );
  late final TextEditingController _sig = TextEditingController(
    text:
        (AppState.instance.user?['signature'] ?? widget.info['signature'] ?? '')
            as String,
  );
  late final TextEditingController _avatar = TextEditingController(
    text:
        (AppState.instance.user?['avatar'] ?? widget.info['avatar'] ?? '')
            as String,
  );

  final ImagePicker _picker = ImagePicker();
  bool _busy = false;
  bool _picking = false;
  String? _err;

  void _snack(String msg) {
    if (!mounted) return;
    toast(context, msg, floating: true);
  }

  /// 选图 -> 压到 100KB 左右 -> 传到 /upload -> 填进 _avatar。
  Future<void> _pickAvatar() async {
    if (_picking || _busy) return;
    try {
      final XFile? f;
      if (!hasMediaStore) {
        f = await _picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
        );
      } else {
        final own = await pickOwnGallery(context, maxCount: 1);
        f = own.isEmpty ? null : own.first;
      }
      if (f == null) return;
      setState(() => _picking = true);
      final src = await f.readAsBytes();
      var out = await ImgCompress.run(
        src,
        maxSide: 512,
        quality: 80,
        sizeLimit: 100 * 1024,
      );
      if (out.length > 100 * 1024) {
        out = await ImgCompress.run(
          src,
          maxSide: 320,
          quality: 70,
          sizeLimit: 100 * 1024,
        );
      }
      final url = await Api.uploadImage(out, name: 'avatar.jpg');
      // 头像传完就直接落到账号上，不用等点保存；昵称签名还是走保存。
      final d = await Api.patch('/me', {'avatar': url});
      final u = d is Map ? d['user'] : null;
      if (u is Map<String, dynamic>) AppState.instance.applyUser(u);
      if (!mounted) return;
      setState(() => _avatar.text = url);
      _snack(Lc.current.avatarUpdated(ImgCompress.kb(out.length)));
    } on ApiException catch (e) {
      _snack(errorText(context, e));
    } catch (e) {
      _snack(Lc.current.uploadFailedWith('$e'));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Widget _avatarPicker(ColorScheme cs) {
    final url = _avatar.text.trim();
    final nick = _nick.text.trim();
    return Row(
      children: [
        GestureDetector(
          onTap: _pickAvatar,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: cs.primaryContainer,
                backgroundImage: url.isEmpty
                    ? null
                    : NetworkImage(Api.img(url)),
                child: url.isEmpty
                    ? Text(
                        nick.isEmpty ? '?' : nick.characters.first,
                        style: TextStyle(
                          fontSize: 24,
                          color: cs.onPrimaryContainer,
                        ),
                      )
                    : null,
              ),
              if (_picking)
                Container(
                  width: 68,
                  height: 68,
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: (_busy || _picking) ? null : _pickAvatar,
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: Text(Lc.current.chooseFromAlbum),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              Text(
                Lc.current.compressNote,
                style: TextStyle(fontSize: 12, color: cs.outline),
              ),
            ],
          ),
        ),
        if (url.isNotEmpty)
          TextButton(
            onPressed: _picking
                ? null
                : () => setState(() => _avatar.text = ''),
            style: TextButton.styleFrom(
              foregroundColor: cs.outline,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(Lc.current.clear),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _nick.dispose();
    _tag.dispose();
    _sig.dispose();
    _avatar.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nick = _nick.text.trim();
    if (nick.isEmpty) {
      setState(() => _err = Lc.current.nicknameRequired);
      return;
    }
    final tag = _tag.text.trim().replaceFirst(RegExp(r'^@'), '').toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{3,16}$').hasMatch(tag)) {
      setState(() => _err = Lc.current.handleInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final d = await Api.patch('/me', {
        'nickname': nick,
        'handle': tag,
        'signature': _sig.text.trim(),
        'avatar': _avatar.text.trim(),
      });
      final u = d is Map ? d['user'] : null;
      if (u is Map<String, dynamic>) {
        AppState.instance.applyUser(u);
      } else {
        await AppState.instance.refreshUser();
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _err = errorText(context, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(Lc.current.editProfileTitle),
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(Lc.current.save),
          ),
        ],
      ),
      body: PageWidth(
        max: 520,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _avatarPicker(cs),
            const SizedBox(height: 14),
            AppCard(
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _nick,
                    maxLength: 20,
                    decoration: InputDecoration(
                      labelText: Lc.current.nickname,
                      helperText: Lc.current.nicknameMax,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _tag,
                    maxLength: 16,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[a-zA-Z0-9_]'),
                      ),
                    ],
                    decoration: InputDecoration(
                      labelText: Lc.current.handle,
                      prefixText: '@',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _sig,
                    maxLength: 80,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: Lc.current.bio,
                      helperText: Lc.current.bioHint,
                      alignLabelWithHint: true,
                    ),
                  ),
                  if (_err != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _err!,
                      style: TextStyle(color: cs.error, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
