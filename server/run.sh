#!/bin/bash
# OpenBBS 启动脚本。
#
#   ./run.sh              明文起在 0.0.0.0:8080
#   ./run.sh --tls        带 HTTPS，证书路径用下面两个环境变量给
#   OPENBBS_HOST / OPENBBS_PORT / OPENBBS_CERT_DIR 都可以覆盖
#
# 不传 --tls 又没配证书，就当纯 HTTP 跑。放在 nginx 后面的部署走这个模式。
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

LOG_DIR="${OPENBBS_LOG_DIR:-$ROOT/logs}"
mkdir -p "$LOG_DIR" "$ROOT/data"
LOG="$LOG_DIR/forum.log"

HOST="${OPENBBS_HOST:-0.0.0.0}"
PORT="${OPENBBS_PORT:-8080}"
CERT_DIR="${OPENBBS_CERT_DIR:-}"
PIDFILE="$ROOT/data/forum.pid"

TLS=0
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
