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

# 端口上已经有同一个应用在跑（手工起的、或 pid 文件丢了）就接管它的 pid。
# 不接管的话 pid 文件会指向刚退出的小进程，cron 每两分钟白起四个、日志刷 bind 失败。
adopt() {
  local host=$1 port=$2 pf=$3 d p cmd
  for d in /proc/[0-9]*; do
    p=${d#/proc/}
    cmd=$( { tr '\0' ' ' < "$d/cmdline"; } 2>/dev/null ) || continue
    case "$cmd" in
      *uvicorn*app.main:app*"--host $host --port $port"*) echo "$p" > "$pf"; return 0 ;;
    esac
  done
  return 1
}

# 进程活着不等于还在服务。旧进程可能卡在一条死连接上，
# 监听已经关了、端口空着没人接手，光看 pid 会一直以为它好着。
# 2026-11-07 就是这么坏的：IPv6 的 26016 空了六个小时没人发现。
serving() {
  ss -tln 2>/dev/null | grep -qF -- "$1"
}

# ss 里 IPv6 地址是带方括号的：[::1]:8080、[::]:26016。
listen_pat() {
  case "$1" in
    *:*) echo "[$1]:$2" ;;
    *) echo "$1:$2" ;;
  esac
}

up() {
  local host=$1 pf=$2 p cmd
  if [ -f "$pf" ]; then
    p=$(cat "$pf" 2>/dev/null)
    cmd=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)
    if [ -n "$p" ] && kill -0 "$p" 2>/dev/null && echo "$cmd" | grep -q uvicorn; then
      # 局域网地址是 DHCP 拨的，可能变；地址变了就换，别让旧进程继续占着。
      echo "$cmd" | grep -qF -- "--host $host --port 8080" \
        && serving "$(listen_pat "$host" 8080)" && return 0
      kill "$p" 2>/dev/null
      sleep 1
      kill -9 "$p" 2>/dev/null
      sleep 1
    fi
  fi
  adopt "$host" 8080 "$pf" && return 0
  nohup "$PY" app.main:app --host "$host" --port 8080 >> "$LOG" 2>&1 &
  echo $! > "$pf"
}

# restore.sh 覆盖库之前要真停站，不然老进程还攥着旧文件。
case "${1:-}" in
  --stop)
    for pf in "$ROOT"/data/forum*.pid; do
      [ -f "$pf" ] || continue
      p=$(cat "$pf" 2>/dev/null)
      [ -n "$p" ] && kill "$p" 2>/dev/null && echo "停掉 $p"
      rm -f "$pf"
    done
    exit 0
    ;;
esac

# 明文 8080 只留给本机与局域网调试：绑在当前局域网地址上，公网 IPv4/IPv6 都落不进来。
# 历史用途是 share 域名的反代，share 已在 11-02 删掉，端口没跟着收（docs/debug/05 的 P2）。
LAN_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p')
LAN_IP=${LAN_IP:-127.0.0.1}
up "$LAN_IP" "$ROOT/data/forum4.pid"
up ::1      "$ROOT/data/forum6.pid"

# 电脑网页版：ipv6bbs.kalutoex.dpdns.org 直连 IPv6，自带 TLS，端口 26016。
up_tls() {
  local host=$1 pf=$2 p
  local pat
  pat=$(listen_pat "$host" 26016)
  if [ -f "$pf" ]; then
    p=$(cat "$pf" 2>/dev/null)
    if [ -n "$p" ] && kill -0 "$p" 2>/dev/null \
       && tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q uvicorn; then
      serving "$pat" && return 0
      kill "$p" 2>/dev/null
      sleep 1
      kill -9 "$p" 2>/dev/null
      sleep 1
    fi
  fi
  adopt "$host" 26016 "$pf" && return 0
  nohup "$PY" app.main:app --host "$host" --port 26016 \
    --ssl-keyfile "$CERT/privkey.pem" \
    --ssl-certfile "$CERT/fullchain.pem" >> "$LOG" 2>&1 &
  echo $! > "$pf"
}

up_tls 0.0.0.0 "$ROOT/data/forum4tls.pid"
up_tls ::      "$ROOT/data/forum6tls.pid"
