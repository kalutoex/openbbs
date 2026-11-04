#!/usr/bin/env bash
# 把刚打好的 arm64 包装进指定通道。
#
#   ./release.sh stable   所有人
#   ./release.sh beta     内测（管理员）
#
# 两个通道都只收 com.kalutoex.shijianxian 的包。
#
# 老用户从 1.3.1 起都在 com.kalutoex.shijianxian，两个通道都验这个包名。
# 安卓只认包名升级，包名不对就装成第二个应用，所以先验再搬。
# notes.txt 自己写，版本号和说明对不上，用户看到的是旧文案。
set -e
cd "$(dirname "$0")"

ch="${1:?用法: ./release.sh stable|beta}"
case "$ch" in
  stable) want="com.kalutoex.shijianxian" ;;
  beta) want="com.kalutoex.shijianxian" ;;
  *)
    echo "通道只能是 stable 或 beta" >&2
    exit 1
    ;;
esac

# 线上服务端跑在 bbs/server，数据目录也在那儿。
root="${OPENBBS_APK_ROOT:-../bbs/server/data/apk}"
[ -d "$root/$ch" ] || { echo "通道目录不存在：$root/$ch" >&2; exit 1; }

src="build/app/outputs/flutter-apk/app-release.apk"
[ -f "$src" ] || { echo "还没打包：$src 不存在" >&2; exit 1; }

aapt="${AAPT2:-/vol1/1000/data/code/sdks/android-sdk/build-tools/36.0.0/aapt2}"
pkg=$("$aapt" dump badging "$src" 2>/dev/null |
  sed -n "s/^package: name='\([^']*\)'.*/\1/p")
if [ "$pkg" != "$want" ]; then
  echo "包名不对：这个包是 $pkg，$ch 通道要 $want" >&2
  echo "用 flutter build apk --release -PappId=$want 重新打" >&2
  exit 1
fi

ver=$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -1)
[ -n "$ver" ] || { echo "pubspec.yaml 里没读到 version" >&2; exit 1; }

dst="$root/$ch/app-$ver.apk"
cp "$src" "$dst"
echo "已放入 $ch：$dst（$pkg）"

notes="$root/$ch/notes.txt"
if ! grep -qxF "$ver" "$notes" 2>/dev/null; then
  echo
  echo "提醒：$notes 里还没有「$ver」这一版，检查更新会显示空说明。"
fi
