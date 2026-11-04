#!/bin/sh
# 容器入口：建库 → 读 site.json 的 server 段 → 起 uvicorn。
#
# 端口、监听地址、证书都在 site.json 里定，容器只负责照着起。
# 所以改端口不用碰 compose，重启容器就行。
set -eu
cd /app

CONFIG="${OPENBBS_CONFIG:-/app/config/site.json}"
export OPENBBS_CONFIG="$CONFIG"

if [ ! -f "$CONFIG" ]; then
  echo "[openbbs] 没有 $CONFIG —— 先用 ./install.sh --docker 生成一份，或挂 config 卷进来" >&2
fi

# 建库是幂等的，每次起都跑一遍，升级时会自动补列。
python - <<'PY'
import sys
sys.path.insert(0, "/app")
from app import db
db.init()
PY

read_cfg() {
  python - "$1" "$2" <<'PY'
import sys
sys.path.insert(0, "/app")
from app import config
print(config.get(sys.argv[1], sys.argv[2], "") or "")
PY
}

HOST="$(read_cfg server host)"; HOST="${HOST:-0.0.0.0}"
PORT="$(read_cfg server port)"; PORT="${PORT:-8080}"
CERT="$(read_cfg server tls_cert_dir)"

set -- uvicorn app.main:app --host "$HOST" --port "$PORT" --proxy-headers --forwarded-allow-ips '*'
if [ -n "$CERT" ] && [ -f "$CERT/fullchain.pem" ] && [ -f "$CERT/privkey.pem" ]; then
  set -- "$@" --ssl-certfile "$CERT/fullchain.pem" --ssl-keyfile "$CERT/privkey.pem"
  echo "[openbbs] HTTPS $HOST:$PORT"
else
  echo "[openbbs] HTTP  $HOST:$PORT"
fi

exec "$@"
