# -*- coding: utf-8 -*-
"""主站停掉之后，小站还能不能验已签发的 token（B1）。"""
import json
import urllib.error
import urllib.request

SLAVE = "http://127.0.0.1:8098"
MASTER = "http://127.0.0.1:8099"


def get(base, path, token=None):
    req = urllib.request.Request(base + path)
    if token:
        req.add_header("authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=8) as r:
            return r.status, r.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8")
    except Exception as e:
        return 0, str(e)


tok = json.load(open("/tmp/bob.tok"))["token"]

s, _ = get(MASTER, "/api/meta")
print("主站状态：", s, "（0 = 已停）")
assert s == 0, "主站还活着，先停掉再跑这个"

s, b = get(SLAVE, "/api/me", tok)
print("小站 /api/me ->", s)
print("   身份 =", json.loads(b)["user"]["name"] if s == 200 else b[:80])
assert s == 200, "断网后验不了已签发的 token，B1 不成立"

print("\n离线验签通过：断网后小站仍认主站签的 token")
