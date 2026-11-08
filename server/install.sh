#!/bin/bash
# OpenBBS 一键部署。空机器上跑这一条，剩下填几行就好。
#
#   ./install.sh                       交互问答
#   ./install.sh --name 我的站 --port 8092 --url https://bbs.example.com --yes
#   ./install.sh --master https://bbs.master.example --yes   小站，去主站登记
#   ./install.sh --docker              只生成 site.json 和目录，不装 venv（容器用）
#
# 干的事：检依赖 → 建 config/site.json → 建 venv 装依赖 → 建库 → 生成管理码 → 打印下一步。
# 幂等：重复跑不会覆盖已经填好的值，site.json 只补缺的键。
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1

NAME=""
PORT=""
URL=""
MASTER=""
HOST="0.0.0.0"
CERT=""
YES=0
DOCKER=0
PIP_INDEX="${OPENBBS_PIP_INDEX:-}"

say() { printf '%s\n' "$*"; }
die() { printf '✗ %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    --url) URL="${2:-}"; shift 2 ;;
    --master) MASTER="${2:-}"; shift 2 ;;
    --host) HOST="${2:-}"; shift 2 ;;
    --cert) CERT="${2:-}"; shift 2 ;;
    --pip-index) PIP_INDEX="${2:-}"; shift 2 ;;
    --yes|-y) YES=1; shift ;;
    --docker) DOCKER=1; shift ;;
    --help|-h) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "不认识的参数：$1" ;;
  esac
done

# ---------------------------------------------------------------- 1 依赖
say "== 检查依赖"
PYBIN="$(command -v python3 || true)"
[ -n "$PYBIN" ] || die "没有 python3。先装：apt install python3 python3-venv"
PYVER="$("$PYBIN" -c 'import sys;print("%d.%d"%sys.version_info[:2])')"
"$PYBIN" -c 'import sys;sys.exit(0 if sys.version_info>=(3,9) else 1)' \
  || die "python $PYVER 太老，要 3.9 以上"

if [ "$DOCKER" = "0" ]; then
  "$PYBIN" -c 'import venv' 2>/dev/null || die "缺 venv 模块：apt install python3-venv"
fi
command -v tar >/dev/null 2>&1 || die "没有 tar"
say "  python $PYVER，tar 有，venv 有"

# ---------------------------------------------------------------- 2 问答
ask() {
  # ask <变量名> <提示> <默认值>
  local __v="$1" __msg="$2" __def="${3:-}" __ans=""
  if [ "$YES" = "1" ] || [ ! -t 0 ]; then
    printf -v "$__v" '%s' "$__def"
    return
  fi
  if [ -n "$__def" ]; then
    printf '%s [%s]: ' "$__msg" "$__def"
  else
    printf '%s: ' "$__msg"
  fi
  read -r __ans || __ans=""
  [ -z "$__ans" ] && __ans="$__def"
  printf -v "$__v" '%s' "$__ans"
}

[ -z "$NAME" ] && ask NAME "站名" "OpenBBS"
[ -z "$PORT" ] && ask PORT "端口" "8092"
[ -z "$MASTER" ] && ask MASTER "主站地址（这台当主站就留空）" ""
[ -z "$URL" ] && ask URL "本站对外地址（含 http(s)://，留空按主机名猜）" ""

case "$PORT" in
  ''|*[!0-9]*) die "端口要数字：$PORT" ;;
esac
[ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || die "端口超范围：$PORT"

# 版本号落一份在 server/ 里：tar 形态部署只有这个目录，check_update.sh 靠它。
if [ ! -s VERSION ] && [ -f ../pubspec.yaml ]; then
  sed -n 's/^version:[[:space:]]*//p' ../pubspec.yaml | head -1 | cut -d+ -f1 > VERSION
fi

# ---------------------------------------------------------------- 3 site.json
say "== 写 config/site.json"
mkdir -p config data logs
if [ -f config/site.json ]; then
  cp config/site.json "config/site.json.bak.$(date +%Y%m%d_%H%M%S)"
  say "  已有 site.json，先备份了一份；只补缺的键，不动你填过的值"
fi

"$PYBIN" - "$ROOT" "$NAME" "$PORT" "$URL" "$MASTER" "$HOST" "$CERT" <<'PY'
import json, os, sys
root, name, port, url, master, host, cert = sys.argv[1:8]
ex = os.path.join(root, "config", "site.json.example")
path = os.path.join(root, "config", "site.json")

base = {}
if os.path.exists(ex):
    with open(ex, "r", encoding="utf-8") as f:
        base = json.load(f)
elif os.path.exists(path):
    with open(path, "r", encoding="utf-8") as f:
        base = json.load(f)


def strip(d):
    """去掉 _说明 这类注释键，真实配置里不留噪音。"""
    if isinstance(d, dict):
        return {k: strip(v) for k, v in d.items() if not str(k).startswith("_")}
    if isinstance(d, list):
        return [strip(x) for x in d]
    return d


cfg = strip(base)
cfg.setdefault("site", {})
cfg.setdefault("server", {})

if os.path.exists(path):
    # 已有配置：以它为底，空的才补。
    with open(path, "r", encoding="utf-8") as f:
        cur = json.load(f)
    cur.setdefault("site", {})
    cur.setdefault("server", {})
    for sec, key, val in (
        ("site", "name", name),
        ("site", "base_url", url),
        ("site", "master_url", master),
        ("server", "host", host),
        ("server", "port", int(port)),
    ):
        if val not in ("", None) and not cur[sec].get(key):
            cur[sec][key] = val
    if cert:
        cur["server"]["tls_cert_dir"] = cert
    cfg = cur
else:
    s = cfg.setdefault("site", {})
    s["name"] = name or s.get("name") or "OpenBBS"
    s["base_url"] = url
    s["master_url"] = master
    srv = cfg.setdefault("server", {})
    srv["host"] = host
    srv["port"] = int(port)
    if cert:
        srv["tls_cert_dir"] = cert

# backup 段的键写在明面上，站长看得见有镜像这回事；
# 镜像路径不替他猜（猜错了就是往错盘写），留空 = 只用本地一份。
b = cfg.setdefault("backup", {})
b.setdefault("dir", "")
b.setdefault("keep", 30)
b.setdefault("mirror_dir", "")
b.setdefault("mirror_keep", 14)

with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
    f.write("\n")
os.chmod(path, 0o644)
print("  %s" % path)
PY
[ -f config/site.json ] || die "site.json 没写出来"

# ---------------------------------------------------------------- 4 依赖装进 venv
if [ "$DOCKER" = "1" ]; then
  say "== 容器部署，跳过 venv（镜像里已经装好）"
else
  say "== 建虚拟环境"
  if [ ! -x .venv/bin/python ]; then
    "$PYBIN" -m venv .venv || die "建 venv 失败"
  fi
  VPY="$ROOT/.venv/bin/python"
  IDX=()
  [ -n "$PIP_INDEX" ] && IDX=(--index-url "$PIP_INDEX")
  "$VPY" -m pip install -q --upgrade pip ${IDX[@]+"${IDX[@]}"} || say "  pip 升级失败，继续"
  "$VPY" -m pip install -q ${IDX[@]+"${IDX[@]}"} -r requirements.txt || die "装依赖失败，看上面的报错"
  say "  依赖装好了"
fi

# ---------------------------------------------------------------- 5 密钥、库、管理员
if [ "$DOCKER" = "1" ]; then
  say "== 容器部署：库和密钥交给容器首次启动时建"
else
  say "== 初始化"
  RUNPY="python3"
  [ -x "$ROOT/.venv/bin/python" ] && RUNPY="$ROOT/.venv/bin/python"

  "$RUNPY" - "$ROOT" <<'PY' || die "初始化失败"
import os, sys
sys.path.insert(0, sys.argv[1])
from app import auth, db
db.init()
print("  数据库 %s" % db.DB)
k = auth._ensure_key()
print("  签名密钥 %s" % ("已生成" if k else "缺 cryptography，走 HMAC 兜底"))
print("  公钥\n%s" % auth.public_pem())
PY

  say "== 管理员"
  "$RUNPY" - "$ROOT" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
from app import api
api.ensure_admin()
PY
fi

# ---------------------------------------------------------------- 6 打印下一步
URL_SHOW="${URL:-}"
if [ -z "$URL_SHOW" ]; then
  IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
  URL_SHOW="http://${IP:-127.0.0.1}:$PORT"
fi

cat <<EOF

== 好了

  站点         $NAME
  地址         $URL_SHOW
  配置         $ROOT/config/site.json   （改端口、证书、主站都改这里）
  数据         $ROOT/data
  管理码       $ROOT/data/admin_initial.txt

  起站         ./run.sh
  看日志       tail -f logs/forum.log
  停           ./run.sh --stop
  立刻备份     ./backup.sh
  从备份恢复   ./restore.sh data/backups/<文件>.tar.gz

  每日备份挂 cron（保留份数在 site.json 的 backup.keep）：
    0 4 * * * $ROOT/backup.sh

EOF
