#!/bin/bash
# OpenBBS 每日备份：SQLite 走 .backup（WAL 安全），uploads 打包，只留最近 N 份。
#
#   ./backup.sh            备份到 data/backups
#   OPENBBS_KEEP=7 ./backup.sh
#
# 建议挂 cron：0 4 * * * /path/to/server/backup.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${OPENBBS_BACKUP_DIR:-$ROOT/data/backups}"
LOG="${OPENBBS_LOG_DIR:-$ROOT/logs}/backup.log"
KEEP="${OPENBBS_KEEP:-30}"
STAMP=$(date +%Y%m%d_%H%M)
DB="${OPENBBS_DB:-$ROOT/data/forum.db}"
UP="${OPENBBS_UPLOAD_DIR:-$ROOT/data/uploads}"

mkdir -p "$DEST" "$(dirname "$LOG")"

exec >> "$LOG" 2>&1
echo "== $(date '+%F %T') 开始"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if ! python3 "$ROOT/db_snapshot.py" "$DB" "$tmp/forum.db"; then
  echo "数据库备份失败"; exit 1
fi

if ! python3 "$ROOT/db_snapshot.py" --check "$tmp/forum.db"; then
  echo "快照自检失败，本次不写备份"; exit 1
fi

if [ -d "$UP" ]; then
  tar -czf "$tmp/uploads.tgz" -C "$(dirname "$UP")" "$(basename "$UP")" || echo "上传目录打包失败（继续）"
fi

tar -czf "$DEST/forum_backups_$STAMP.tar.gz" -C "$tmp" . || { echo "打包失败"; exit 1; }
echo "写入 $DEST/forum_backups_$STAMP.tar.gz $(du -h "$DEST/forum_backups_$STAMP.tar.gz" | cut -f1)"

ls -1t "$DEST"/forum_backups_*.tar.gz 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r f; do
  rm -f "$f"; echo "清理旧备份 $(basename "$f")"
done
echo "== 完成"
