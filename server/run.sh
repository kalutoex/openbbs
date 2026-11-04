#!/bin/bash
# OpenBBS 启动脚本。
#
#   ./run.sh              默认明文起在 0.0.0.0:8092（可用 site.json 改）
#   ./run.sh --tls        强制 HTTPS，证书目录见 server.tls_cert_dir
#   ./run.sh --stop       停
#
# 端口、监听地址、证书目录都从 config/site.json 的 server 段读；
# 环境变量 OPENBBS_HOST / OPENBBS_PORT / OPENBBS_CERT_DIR 覆盖它。
# 配了 tls_cert_dir 就自动开 TLS，不用再传 --tls。
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1

PY="$ROOT/.venv/bin/uvicorn"
[ -x "$PY" ] || PY="$(command -v uvicorn)"
if [ -z "$PY" ]; then
  echo "找不到 uvicorn。先建虚拟环境："
  echo "  python3 -m venv .venv && ./.venv/bin/pip install -r requirements.txt"
  exit 1
fi

. "$ROOT/_cfg.sh"

LOG_DIR="${OPENBBS_LOG_DIR:-$ROOT/logs}"
mkdir -p "$LOG_DIR" "$ROOT/data"
LOG="$LOG_DIR/forum.log"

HOST="${OPENBBS_HOST:-$(cfg server host)}"
HOST="${HOST:-0.0.0.0}"
PORT="${OPENBBS_PORT:-$(cfg server port)}"
PORT="${PORT:-8092}"
CERT_DIR="${OPENBBS_CERT_DIR:-$(cfg server tls_cert_dir)}"
PIDFILE="$ROOT/data/forum.pid"

TLS=0
[ -n "$CERT_DIR" ] && TLS=1
for arg in "$@"; do
  if [ "$arg" = "--stop" ]; then
    if [ -f "$PIDFILE" ]; then
      kill "$(cat "$PIDFILE")" 2>/dev/null && echo "已停" || echo "进程不在了，清掉 pid 文件"
      rm -f "$PIDFILE"
    else
      echo "没在跑"
    fi
    exit 0
  fi
  [ "$arg" = "--tls" ] && TLS=1
done

if [ "$TLS" = "1" ]; then
  if [ -z "$CERT_DIR" ] || [ ! -f "$CERT_DIR/fullchain.pem" ] || [ ! -f "$CERT_DIR/privkey.pem" ]; then
    echo "开了 --tls 但没找到证书。设 OPENBBS_CERT_DIR 指向含 fullchain.pem / privkey.pem 的目录。"
    exit 1
  fi
  EXTRA=(--ssl-certfile "$CERT_DIR/fullchain.pem" --ssl-keyfile "$CERT_DIR/privkey.pem")
  echo "HTTPS  $HOST:$PORT"
else
  EXTRA=()
  echo "HTTP   $HOST:$PORT"
fi

# 已经在跑就不重复起。
if [ -f "$PIDFILE" ]; then
  OLD=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "$OLD" ] && kill -0 "$OLD" 2>/dev/null; then
    echo "已经在跑了，pid $OLD。要重启先 ./run.sh --stop"
    exit 0
  fi
fi

nohup "$PY" app.main:app --host "$HOST" --port "$PORT" "${EXTRA[@]}" >> "$LOG" 2>&1 &
echo $! > "$PIDFILE"
echo "pid $(cat "$PIDFILE")，日志 $LOG"
