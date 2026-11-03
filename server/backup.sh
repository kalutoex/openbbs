#!/bin/bash
# 时间線论坛每日备份：SQLite 用 .backup（WAL 安全），uploads 打包。保留 14 份。
# 日志：/home/060923/.forum_backup.log
# 依赖：python3（sqlite3 模块）、tar
# 打包前先验快照：能打开、表还在，才覆盖今天的 tar。
set -u
ROOT=/vol1/1000/data/code/ongoing/bbs/server
DEST=$ROOT/data/backups
LOG=$ROOT/logs/backup.log
KEEP=30
STAMP=$(date +%Y%m%d_%H%M)
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

tar -czf "$DEST/forum_backups_$STAMP.tar.gz" -C "$tmp" . || { echo "打包失败"; exit 1; }
echo "写入 $DEST/forum_backups_$STAMP.tar.gz $(du -h "$DEST/forum_backups_$STAMP.tar.gz" | cut -f1)"

# 只留最近 KEEP 份
ls -1t "$DEST"/forum_backups_*.tar.gz "$DEST"/forum-*.tar.gz 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r f; do
  rm -f "$f"; echo "清理旧备份 $(basename "$f")"
done
echo "== 完成"
