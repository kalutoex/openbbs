#!/bin/bash
# 从备份恢复。备份能直接还原成可跑实例，这一步就是验证。
#
#   ./restore.sh data/backups/forum_backups_20260101_0400.tar.gz
#   ./restore.sh <文件> --yes        不问直接来
#   ./restore.sh <文件> --db-only    只还数据库，不动 uploads
#   ./restore.sh --from-mirror --yes 从 backup.mirror_dir 里挑最新一份
#
# 流程：解到临时目录 → 验快照 → 现有数据打包留底 → 停站 → 覆盖 → 起站。
# 中途任何一步失败都会在覆盖前退出，旧数据不会被写坏。
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1
. "$ROOT/_cfg.sh"

say() { printf '%s\n' "$*"; }
die() { printf '✗ %s\n' "$*" >&2; exit 1; }

SRC=""
ASSUME=0
DB_ONLY=0
FROM_MIRROR=0
for a in "$@"; do
  case "$a" in
    --yes|-y) ASSUME=1 ;;
    --db-only) DB_ONLY=1 ;;
    --from-mirror) FROM_MIRROR=1 ;;
    -*) die "不认识的参数：$a" ;;
    *) SRC="$a" ;;
  esac
done

if [ "$FROM_MIRROR" = "1" ]; then
  # 镜像里挑最新的一份。本地那份坏了才走这条路，所以别问选哪份。
  MIRROR="$(cfg backup mirror_dir)"
  [ -n "$MIRROR" ] || die "没配 backup.mirror_dir，不知道镜像在哪"
  [ -d "$MIRROR" ] || die "镜像目录不存在：$MIRROR"
  SRC=$(ls -1t "$MIRROR"/forum_backups_*.tar.gz 2>/dev/null | head -1)
  if [ -z "$SRC" ]; then
    say "镜像目录 $MIRROR 里没有 forum_backups_*.tar.gz，实际有的是："
    ls -1 "$MIRROR" 2>/dev/null | sed 's/^/  /'
    exit 1
  fi
  say "== 来源：镜像 $SRC"
elif [ -z "$SRC" ]; then
  die "用法：./restore.sh <备份文件> [--yes] [--db-only]，或 ./restore.sh --from-mirror [--yes]"
fi

[ -f "$SRC" ] || die "找不到文件：$SRC"

DATA="$(cfg paths data "$ROOT/data")"
DB="$(cfg paths db "$DATA/forum.db")"
UP="$(cfg paths uploads "$DATA/uploads")"
PY="$(command -v python3)"
[ -n "$PY" ] || die "没有 python3"

say "== 检查备份"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tar -xzf "$SRC" -C "$tmp" || die "解包失败，文件可能不是本程序的备份"
[ -f "$tmp/forum.db" ] || die "包里没有 forum.db，不像 OpenBBS 的备份"
"$PY" "$ROOT/db_snapshot.py" --check "$tmp/forum.db" || die "快照自检不过，这个包装不回去"
say "  快照能打开，users / threads / replies 都查得动"
if [ -f "$tmp/uploads.tgz" ]; then
  say "  uploads 一起在包里（约 $(du -h "$tmp/uploads.tgz" | cut -f1)）"
else
  say "  包里没有 uploads，恢复后图片会缺"
fi

say ""
say "  要恢复到的位置："
say "    数据库  $DB"
say "    上传    $UP"
say "  现在库里的数据会先打包留底。"
if [ "$ASSUME" = "0" ]; then
  [ -t 0 ] || die "非交互环境请加 --yes"
  printf '继续？[y/N] '
  read -r ans || ans=""
  case "$ans" in y|Y|yes|YES) ;; *) say "算了，什么都没动"; exit 0 ;; esac
fi

say ""
say "== 先给现有数据留底"
BEFORE="$ROOT/data/backups/before_restore_$(date +%Y%m%d_%H%M%S).tar.gz"
mkdir -p "$(dirname "$BEFORE")"
stage=$(mktemp -d)
if [ -f "$DB" ]; then
  "$PY" "$ROOT/db_snapshot.py" "$DB" "$stage/forum.db" || die "现有库快照失败，先不动"
fi
tar -czf "$BEFORE" -C "$stage" . 2>/dev/null || say "  留底打包失败（继续）"
rm -rf "$stage"
say "  $BEFORE"

say ""
say "== 停站"
COMPOSE=""
if [ -f "$ROOT/docker-compose.yml" ] && command -v docker >/dev/null 2>&1; then
  if [ -n "$(docker compose -f "$ROOT/docker-compose.yml" ps -q 2>/dev/null)" ]; then
    COMPOSE="$ROOT/docker-compose.yml"
    docker compose -f "$COMPOSE" stop || say "  compose stop 没成功"
  fi
fi
if [ -z "$COMPOSE" ]; then
  "$ROOT/run.sh" --stop || say "  run.sh --stop 没成功"
fi

say ""
say "== 覆盖"
mkdir -p "$DATA" "$(dirname "$DB")"
rm -f "$DB-wal" "$DB-shm"
cp "$tmp/forum.db" "$DB" || die "拷库失败"
chmod 644 "$DB" 2>/dev/null
say "  数据库已换"
if [ "$DB_ONLY" = "0" ] && [ -f "$tmp/uploads.tgz" ]; then
  mkdir -p "$UP"
  tar -xzf "$tmp/uploads.tgz" -C "$(dirname "$UP")" || say "  uploads 解包失败，图片可能不全"
  say "  上传目录已合并"
fi

say ""
say "== 起站"
if [ -n "$COMPOSE" ]; then
  docker compose -f "$COMPOSE" start || die "起不来，看 docker compose logs"
else
  "$ROOT/run.sh"
fi

say ""
say "恢复完成。核一下：用户名密码能登、帖子数对得上、图片能打开。"
say "留底那份在 $BEFORE，确认没问题再删。"
