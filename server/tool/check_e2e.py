# -*- coding: utf-8 -*-
"""端到端：封号 → 该账号读写全部 403 → 解封恢复。"""
import json
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8099"


def call(method, path, token=None, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    if data:
        req.add_header("content-type", "application/json")
    if token:
        req.add_header("authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, r.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8")


alice = json.load(open("/tmp/alice.json"))["token"]
admin = json.load(open("/tmp/admin.json"))["token"]

print("1. 封号前 alice 读接口")
for p in ("/api/feed", "/api/me", "/api/search?q="):
    s, b = call("GET", p, alice)
    print("   %-18s %s" % (p, s))
    assert s == 200, (p, s, b)

print("2. admin 封 alice")
s, b = call("POST", "/api/admin/ban", admin, {"q": "alice", "reason": "端到端测试"})
print("   ban ->", s, b[:120])
assert s == 200, b

print("3. 封号后 alice 读写（全 403 + 固定文案）")
for m, p, body in (("GET", "/api/feed", None),
                   ("GET", "/api/me", None),
                   ("GET", "/api/search?q=", None),
                   ("POST", "/api/report", {"thread_id": 1, "reason": "x"})):
    s, b = call(m, p, alice, body)
    ok = s == 403 and "账号已被封禁" in b
    print("   %-4s %-18s %s %s" % (m, p, s, "文案对" if ok else b[:80]))
    assert ok, (m, p, s, b)

print("4. admin 自己不受影响")
s, b = call("GET", "/api/me", admin)
print("   admin /api/me ->", s)
assert s == 200

print("5. 拉一次增量清单（模拟小站）")
s, b = call("GET", "/api/blacklist?since=0")
d = json.loads(b)
print("   items =", d["items"], "sig len =", len(d["sig"]))
assert d["items"] and d["sig"]

print("6. 解封，alice 恢复")
s, b = call("POST", "/api/admin/unban", admin, {"q": "alice"})
print("   unban ->", s)
s, b = call("GET", "/api/feed", alice)
print("   alice /api/feed ->", s)
assert s == 200

print("\n端到端全部通过")
