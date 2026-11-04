#!/bin/bash
# 读 config/site.json 的小工具，被 run.sh / backup.sh / restore.sh / check_update.sh source。
#
# 只依赖 python3 的 json，不需要 venv、不需要装依赖——部署脚本跑在裸机上也得能用。
# 文件不在、键为空、JSON 写坏了，一律当没配，返回空串，不报错。

OPENBBS_ROOT="${OPENBBS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

_cfg_py() {
  if [ -x "$OPENBBS_ROOT/.venv/bin/python" ]; then
    printf '%s' "$OPENBBS_ROOT/.venv/bin/python"
  else
    command -v python3 2>/dev/null
  fi
}

# cfg <section> <key> [默认值]
cfg() {
  local py out
  py="$(_cfg_py)"
  if [ -z "$py" ]; then
    printf '%s' "${3:-}"
    return
  fi
  out="$("$py" - "$OPENBBS_ROOT/config/site.json" "$1" "$2" <<'PY' 2>/dev/null
import json, sys
path, sec, key = sys.argv[1:4]
try:
    with open(path, "r", encoding="utf-8") as f:
        d = json.load(f)
except Exception:
    sys.exit(0)
node = d.get(sec)
if not isinstance(node, dict):
    sys.exit(0)
v = node.get(key)
if v is None or v == "" or v == []:
    sys.exit(0)
print(v)
PY
)"
  if [ -z "$out" ]; then
    printf '%s' "${3:-}"
  else
    printf '%s' "$out"
  fi
}
