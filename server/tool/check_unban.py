# -*- coding: utf-8 -*-
"""解封传播 + 小站断网仍能验已签发 token。"""
import json
import time
import urllib.error
import urllib.request

MASTER = "http://127.0.0.1:8099"
SLAVE = "http://127.0.0.1:8098"


def call(base, method, path, token=None, body=None, timeout=8):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(base + path, data=data, method=method)
    if data:
        req.add_header("content-type", "application/json")
    if token:
        req.add_header("authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read().decode("utf-8")
    except (urllib.error.HTTPError, urllib.error.URLError, OSError) as e:
        if isinstance(e, urllib.error.HTTPError):
            return e.code, e.read().decode("utf-8")
        return 0, str(e)


def login(name, pw):
    s, b = call(MASTER, "POST", "/api/login", body={"name": name, "password": pw})
    assert s == 200, (name, s, b)
    return json.loads(b)["token"]


bob = login("bob", "pw12345678")
admin = login("admin", "adminpass123")

print("1. 当前 bob 在小站是封的")
s, _ = call(SLAVE, "GET", "/api/feed", bob)
print("   ->", s)
assert s == 403

print("2. 主站解封（banned=0 墓碑，增量会带出去）")
s, b = call(MASTER, "POST", "/api/admin/unban", admin, {"q": "bob"})
print("   unban ->", s)
assert s == 200
s, b = call(MASTER, "GET", "/api/blacklist?since=0")
print("   主站清单 =", json.loads(b)["items"])

print("3. 等小站拉到解封（最多 70 秒）")
t0 = time.time()
while time.time() - t0 < 70:
    s, _ = call(SLAVE, "GET", "/api/feed", bob)
    if s == 200:
        break
    time.sleep(2)
cost = time.time() - t0
print("   bob 恢复读权限，用时 %.1f 秒（状态 %s）" % (cost, s))
assert s == 200, "解封没传到小站"

print("4. 停掉主站，确认小站断网也能验已签发的 token")
print("   请手动停 8099 后运行：python3 tool/check_offline.py")
print("\n解封传播验收通过（%.1f 秒）" % cost)
