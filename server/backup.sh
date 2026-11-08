#!/bin/bash
# 时间線论坛每日备份：SQLite 用 .backup（WAL 安全），uploads 打包。保留 30 份。
# 本地存一份，再往另一块盘复制一份 —— 同一块盘坏了就等于没备份。
# 日志：$ROOT/logs/backup.log
# 依赖：python3（sqlite3 模块）、tar
# 打包前先验快照：能打开、表还在，才覆盖今天的 tar。
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ROOT/_cfg.sh"
# 目录和份数都读 config/site.json，读不到就用默认（跟以前一样）。
DEST="$(cfg backup dir)"; DEST="${DEST:-$ROOT/data/backups}"
KEEP="$(cfg backup keep)"; KEEP="${KEEP:-30}"
# 镜像目录：另一块盘上的第二份。BACKUP_OFF 优先，方便临时试跑、不打扰线上配置。
MIRROR="${BACKUP_OFF:-$(cfg backup mirror_dir)}"
MKEEP="$(cfg backup mirror_keep)"; MKEEP="${MKEEP:-14}"
LOG=$ROOT/logs/backup.log
STAMP=$(date +%Y%m%d_%H%M%S)  # 精确到秒：同一分钟跑两次不许互相覆盖
mkdir -p "$DEST"

exec >> "$LOG" 2>&1
echo "== $(date '+%F %T') 开始"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if ! python3 "$ROOT/db_snapshot.py" "$ROOT/data/forum.db" "$tmp/forum.db"; then
  echo "数据库备份失败"; exit 1
fi

if ! python3 "$ROOT/db_snapshot.py" --check "$tmp/forum.db"; then
  echo "快照自检失败，本次不写备份"; exit 1
fi

if [ -d "$ROOT/data/uploads" ]; then
  tar -czf "$tmp/uploads.tgz" -C "$ROOT/data" uploads || echo "上传目录打包失败（继续）"
fi

# 快照是完整的单文件，wal/shm 是打开时顺手建的，别打进包里误导还原
rm -f "$tmp/forum.db-wal" "$tmp/forum.db-shm"

tar -czf "$DEST/forum_backups_$STAMP.tar.gz" -C "$tmp" . || { echo "打包失败"; exit 1; }
echo "写入 $DEST/forum_backups_$STAMP.tar.gz $(stat -c %s "$DEST/forum_backups_$STAMP.tar.gz") 字节"

# 只留最近 KEEP 份
ls -1t "$DEST"/forum_backups_*.tar.gz "$DEST"/forum-*.tar.gz 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r f; do
  rm -f "$f"; echo "清理旧备份 $(basename "$f")"
done
# ---------------------------------------------------------------- 镜像
# 主备份已经落地、旧份也清完了，这一段只管往另一块盘再放一份。
# 镜像失败不许动本地那份，只影响退出码。
mirror() {
  local src=$1 f dst a b mnt1 mnt2
  if [ -z "$MIRROR" ]; then
    echo "未配置异地镜像，跳过"
    return 0
  fi
  if ! mkdir -p "$MIRROR"; then
    echo "!! [镜像] 建不了目录 $MIRROR"
    return 2
  fi
  # 同一块盘上复制一份不算备份。站长配了就照做，提醒一句。
  mnt1=$(df -P "$DEST" 2>/dev/null | tail -1 | awk '{print $6}')
  mnt2=$(df -P "$MIRROR" 2>/dev/null | tail -1 | awk '{print $6}')
  if [ -n "$mnt1" ] && [ "$mnt1" = "$mnt2" ]; then
    echo "!! [镜像] 注意：$MIRROR 和备份目录在同一块盘（$mnt1），盘坏了两份一起没"
  fi
  dst="$MIRROR/$(basename "$src")"
  if ! cp -a "$src" "$dst"; then
    echo "!! [镜像] 复制失败：$dst"
    return 2
  fi
  # 哈希对不上就当没写：留一份坏的镜像比没有更危险
  a=$(sha256sum "$src" | awk '{print $1}')
  b=$(sha256sum "$dst" 2>/dev/null | awk '{print $1}')
  if [ "$a" != "$b" ]; then
    echo "!! [镜像] 哈希对不上，删掉镜像那份：$dst"
    rm -f "$dst"
    return 2
  fi
  echo "[镜像] 写入 $dst $(stat -c %s "$dst") 字节 sha256 $(printf %s "$a" | cut -c1-12)…"
  ls -1t "$MIRROR"/forum_backups_*.tar.gz 2>/dev/null | tail -n +$((MKEEP + 1)) | while read -r f; do
    rm -f "$f"; echo "[镜像] 清理旧份 $(basename "$f")"
  done
  return 0
}

mirror "$DEST/forum_backups_$STAMP.tar.gz"
if [ $? -eq 0 ]; then
  if [ -n "$MIRROR" ]; then
    echo "== 完成（本地 + 镜像）"
  else
    echo "== 完成（只有本地）"
  fi
  exit 0
fi
echo "== 完成（只有本地，镜像这轮没成）"
exit 2
