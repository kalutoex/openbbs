#!/usr/bin/env bash
# 把刚打好的 arm64 包装进指定通道。
#
#   ./release.sh beta     内测：只有管理员能收到
#   ./release.sh stable   稳定：所有人都会收到
#
# 只负责搬文件，notes.txt 自己写——版本号和说明对不上，用户看到的就是旧文案。
set -e
cd "$(dirname "$0")"

ch="${1:?用法: ./release.sh beta|stable}"
case "$ch" in
  beta | stable) ;;
  *)
    echo "通道只能是 beta 或 stable" >&2
    exit 1
    ;;
esac

src="build/app/outputs/flutter-apk/app-release.apk"
[ -f "$src" ] || { echo "还没打包：$src 不存在" >&2; exit 1; }

ver=$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -1)
[ -n "$ver" ] || { echo "pubspec.yaml 里没读到 version" >&2; exit 1; }

dst="server/data/apk/$ch/app-$ver.apk"
cp "$src" "$dst"
echo "已放入 $ch：$dst"

notes="server/data/apk/$ch/notes.txt"
if ! grep -qxF "$ver" "$notes" 2>/dev/null; then
  echo
  echo "提醒：$notes 里还没有「$ver」这一版，检查更新会显示空说明。"
fi
