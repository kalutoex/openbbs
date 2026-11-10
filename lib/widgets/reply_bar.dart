import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'app_sheet.dart';

/// 统一的输入栏：帖子回复、私信共用一套。
///
/// 一行到底：左边可选一个 leading，中间输入框吃剩余宽度，右边按钮。
/// 窄屏（手表）不换行，靠把按钮压紧 + hint 单行省略来撑住，
/// 换行会让整条栏高出一大截，看着更挤。
class ReplyBar extends StatelessWidget {
  const ReplyBar({
    super.key,
    required this.controller,
    this.focusNode,
    this.hint,
    this.leading,
    this.actions = const <Widget>[],
    this.onChanged,
    this.minLines = 1,
    this.maxLines = 4,
    this.fontSize = 14,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;

  /// 占位提示。私信那边传 null，不显示文案。
  final String? hint;

  /// 输入框左边的东西（帖子是头像，私信是表情按钮）。
  final Widget? leading;

  /// 输入框右边的按钮。
  final List<Widget> actions;

  final ValueChanged<String>? onChanged;
  final int minLines;
  final int maxLines;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ?leading,
        Expanded(child: _field(cs)),
        ...actions,
      ],
    );
  }

  Widget _field(ColorScheme cs) {
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: TextField(
        autocorrect: false,
        enableSuggestions: false,
        controller: controller,
        focusNode: focusNode,
        minLines: minLines,
        maxLines: maxLines,
        textInputAction: TextInputAction.newline,
        onChanged: onChanged,
        style: TextStyle(fontSize: fontSize, height: 1.3),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          // hintText 会自己折行，窄了就是一个字一行；这里用 widget 强制单行省略。
          hint: hint == null
              ? null
              : Text(
                  hint!,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: fontSize, color: cs.outline),
                ),
        ),
      ),
    );
  }
}

/// 输入栏右侧的图标按钮。默认 IconButton 一个占 48，三个就吃掉 144，
/// 手表那种宽度只剩几十像素给输入框，所以这里统一压到 34。
class ReplyBarIcon extends StatelessWidget {
  const ReplyBarIcon({
    super.key,
    required this.icon,
    this.onPressed,
    this.color,
    this.tooltip,
    this.size = 20,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final Color? color;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      color: color,
      iconSize: size,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      icon: icon,
    );
  }
}

/// 输入栏的「+」菜单：图片 / 文件。帖子和私信共用这一套，少一个按钮的位置。
Future<void> showAttachSheet({
  required BuildContext context,
  required VoidCallback onImage,
  required VoidCallback onFile,
}) {
  return showAppSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Row(
          children: [
            _attachTile(
              ctx,
              Icons.photo_library_outlined,
              Lc.current.dmPickImage,
              () {
                Navigator.pop(ctx);
                onImage();
              },
            ),
            const SizedBox(width: 24),
            _attachTile(ctx, Icons.attach_file, Lc.current.dmPickFile, () {
              Navigator.pop(ctx);
              onFile();
            }),
          ],
        ),
      ),
    ),
  );
}

Widget _attachTile(
  BuildContext ctx,
  IconData icon,
  String label,
  VoidCallback onTap,
) {
  final cs = Theme.of(ctx).colorScheme;
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 26, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );
}
