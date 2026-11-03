#!/bin/bash
# 论坛保活：IPv4 与 IPv6 各起一个进程（uvicorn 不支持单进程双栈）。
# 项目根：/vol1/1000/data/code/ongoing/bbs/server
# 日志：$ROOT/logs/forum.log
ROOT=/vol1/1000/data/code/ongoing/bbs/server
cd "$ROOT" || exit 1
LOG=$ROOT/logs/forum.log
PY=$ROOT/.venv/bin/uvicorn
CERT=/home/060923/certs/main
mkdir -p "$ROOT/logs" "$ROOT/data"

up() {
  local host=$1 pf=$2 p
  if [ -f "$pf" ]; then
    p=$(cat "$pf" 2>/dev/null)
    if [ -n "$p" ] && kill -0 "$p" 2>/dev/null \
       && tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q uvicorn; then
      return 0
    fi
  fi
  nohup "$PY" app.main:app --host "$host" --port 8080 >> "$LOG" 2>&1 &
  echo $! > "$pf"
}

up 0.0.0.0 "$ROOT/data/forum4.pid"
up ::      "$ROOT/data/forum6.pid"

# 电脑网页版：ipv6bbs.kalutoex.dpdns.org 直连 IPv6，自带 TLS，端口 26016。
up_tls() {
  local host=$1 pf=$2 p
  if [ -f "$pf" ]; then
    p=$(cat "$pf" 2>/dev/null)
    if [ -n "$p" ] && kill -0 "$p" 2>/dev/null \
       && tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q uvicorn; then
      return 0
    fi
  fi
  nohup "$PY" app.main:app --host "$host" --port 26016 \
    --ssl-keyfile "$CERT/privkey.pem" \
    --ssl-certfile "$CERT/fullchain.pem" >> "$LOG" 2>&1 &
  echo $! > "$pf"
}

up_tls 0.0.0.0 "$ROOT/data/forum4tls.pid"
up_tls ::      "$ROOT/data/forum6tls.pid"
