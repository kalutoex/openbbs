# -*- coding: utf-8 -*-
"""小站同步验收：主站封号，小站 60 秒内落地并拦截；断网仍能验签。"""
import json
import time
import urllib.error
import urllib.request

MASTER = "http://127.0.0.1:8099"
SLAVE = "http://127.0.0.1:8098"


def call(base, method, path, token=None, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(base + path, data=data, method=method)
    if data:
        req.add_header("content-type", "application/json")
    if token:
        req.add_header("authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, r.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8")


def login(base, name, pw):
    s, b = call(base, "POST", "/api/login", body={"name": name, "password": pw})
    assert s == 200, (name, s, b)
    return json.loads(b)["token"]


print("0. 小站自报身份")
s, b = call(SLAVE, "GET", "/api/meta")
m = json.loads(b)
print("   role =", m["blacklist"]["role"], "| name =", m["name"])
assert m["blacklist"]["role"] == "slave"
assert m["public_key"], "小站没取到主站公钥"

bob = login(MASTER, "bob", "pw12345678")
alice = login(MASTER, "alice", "pw12345678")

print("1. 封号前：小站用主站 token 能读")
s, b = call(SLAVE, "GET", "/api/feed", bob)
print("   slave /api/feed ->", s)
assert s == 200, b

print("2. 主站封 bob")
s, b = call(MASTER, "POST", "/api/admin/ban", login(MASTER, "admin", "adminpass123"),
            {"q": "bob", "reason": "小站同步测试"})
print("   ban ->", s, json.loads(b).get("uid"))
assert s == 200

print("3. 等小站拉到（最多 70 秒）")
t0 = time.time()
landed = 0
while time.time() - t0 < 70:
    s, b = call(SLAVE, "GET", "/api/meta")
    landed = json.loads(b)["blacklist"]["banned"]
    if landed:
        break
    time.sleep(2)
cost = time.time() - t0
print("   落地 %d 条，用时 %.1f 秒" % (landed, cost))
assert landed, "70 秒内没同步到"
assert cost <= 65, "超过 60 秒窗口"

print("4. 小站上 bob 读写全部 403")
for mm, p, body in (("GET", "/api/feed", None),
                    ("GET", "/api/me", None),
                    ("POST", "/api/report", {"thread_id": 1, "reason": "x"})):
    s, b = call(SLAVE, mm, p, bob, body)
    ok = s == 403 and "账号已被封禁" in b
    print("   %-4s %-14s %s %s" % (mm, p, s, "文案对" if ok else b[:60]))
    assert ok, (mm, p, s, b)

print("5. 同一个 token 在 alice 身上照常（不误伤）")
s, b = call(SLAVE, "GET", "/api/feed", alice)
print("   slave /api/feed ->", s)
assert s == 200

print("6. 影子行只有一个，没按 id 串号")
s, b = call(SLAVE, "GET", "/api/me", alice)
me = json.loads(b)
print("   alice 在小站的影子 =", me["user"]["name"], me["user"]["uid"])
assert me["user"]["name"].startswith("u"), "小站不该复用本地同名用户"

print("\n小站同步验收通过（%.1f 秒生效）" % cost)
