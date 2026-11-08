#!/bin/bash
# 只看有没有新版本，不下载、不升级。计划里定的是 L3：打个招呼就够了。
#
#   ./check_update.sh                 用 site.json 的 update.check_url
#   ./check_update.sh https://.../app/latest   直接指一个地址
#
# 地址留空就什么都不问，只打印当前版本。
# 退出码：0 = 已是最新或查不到，1 = 有新版本（cron 里可以靠这个发通知）。
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1
. "$ROOT/_cfg.sh"

PY="$(command -v python3)"
[ -n "$PY" ] || { echo "没有 python3"; exit 0; }

# 版本号：server/VERSION 优先（tar 形态只有 server 目录），再退回仓库根的 pubspec.yaml。
CUR="$(head -1 "$ROOT/VERSION" 2>/dev/null | tr -d '[:space:]')"
[ -n "$CUR" ] || CUR="$(sed -n 's/^version:[[:space:]]*//p' "$ROOT/../pubspec.yaml" 2>/dev/null | head -1)"
CUR="${CUR%%+*}"
CUR="${CUR:-0.0.0}"

URL="${1:-$(cfg update check_url)}"
if [ -z "$URL" ]; then
  MASTER="$(cfg site master_url)"
  [ -n "$MASTER" ] && URL="${MASTER%/}/api/app/latest"
fi

if [ -z "$URL" ]; then
  echo "当前 $CUR。没配 update.check_url 也没配 master_url，没地方问。"
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "当前 $CUR。没装 curl，查不了。"
  exit 0
fi

JSON="$(curl -fsS --max-time 8 "$URL" 2>/dev/null)"
if [ -z "$JSON" ]; then
  echo "当前 $CUR。问不到 $URL（超时或 404），下次再说。"
  exit 0
fi

printf '%s' "$JSON" | "$PY" -c '
import json, sys
cur = sys.argv[1]
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    print("当前 %s。返回的不是 JSON，跳过。" % cur)
    sys.exit(0)
new = str(d.get("version") or d.get("latest") or "").split("+")[0]
if not new:
    print("当前 %s。对方没给版本号，跳过。" % cur)
    sys.exit(0)


def key(v):
    out = []
    for part in v.split("."):
        digits = "".join(ch for ch in part if ch.isdigit())
        out.append(int(digits or 0))
    return out + [0] * (4 - len(out))


if key(new) > key(cur):
    notes = d.get("notes") or ""
    if isinstance(notes, list):
        notes = "\n".join("  · %s" % x for x in notes[:6])
    print("当前 %s，最新 %s —— 有新版本。" % (cur, new))
    if notes:
        print(notes)
    print("本站不自动升级。拿到新包后：备份 → 替换代码 → ./restore.sh 不动数据，重启即生效。")
    sys.exit(1)
print("当前 %s，已是最新。" % cur)
' "$CUR"
