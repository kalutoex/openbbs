# -*- coding: utf-8 -*-
"""第 3 段自检：站点自述、清单三条校验、登记与查重。
纯离线：回访 /meta 用假数据替换，不碰网络、不碰线上库。
"""
import json
import os
import sys
import tempfile

SERVER = "/vol1/1000/data/code/ongoing/openbbs/server"
TMP = tempfile.mkdtemp(prefix="obb3-")
os.environ["OPENBBS_DATA_DIR"] = TMP
os.environ["OPENBBS_DB"] = os.path.join(TMP, "t.db")
os.environ["OPENBBS_SITE_NAME"] = "时间線"
os.environ["OPENBBS_SITE_BASE_URL"] = "https://bbs.example.com:26016"
os.environ["OPENBBS_SITE_TAGS"] = "综合,技术"
sys.path.insert(0, SERVER)

from app import config, db, sites  # noqa: E402

db.init()
print("临时库：", config.path("db"))

print("== 1. 本机自述 ==")
me = sites.self_site()
print("   ", json.dumps(me, ensure_ascii=False))
assert me["api"] == sites.API_VERSION == 2, "api 版本不对"
assert me["name"] == "时间線"
assert me["url"] == "https://bbs.example.com:26016"
assert me["endpoints"][0]["url"] == me["url"], "没配 endpoints 时应把 base_url 当唯一入口"
assert me["tags"] == ["综合", "技术"], "tags 没读进来"
assert me["id"] == "", "site_id 没填就该是空"

wk = sites.well_known()
assert wk["schema"] == 1 and len(wk["sites"]) == 1
print("   /.well-known/bbs.json -> schema=%s，sites=%d 条" % (wk["schema"], len(wk["sites"])))

print("== 2. 清单校验：三条规则 ==")
bad = {
    "schema": 1,
    "sites": [
        {"id": "ok", "name": "好的", "url": "https://a.example", "api": 2},
        {"id": "nourl", "name": "没地址", "api": 2},                      # 缺地址
        {"id": "nourl2", "name": "只有空入口", "endpoints": [{"note": "x"}], "api": 2},
        {"id": "dup", "name": "重复一", "url": "https://b.example", "api": 2},
        {"id": "dup", "name": "重复二", "url": "https://c.example", "api": 2},
        {"id": "future", "name": "太新", "url": "https://d.example", "api": 99},
        {"id": "old", "name": "老版本", "url": "https://e.example", "api": 1},
        {"name": "没 id", "url": "https://f.example", "api": 2},
        "不是对象",
    ],
}
keep, dropped = sites.validate(bad)
print("   收下：", [k["id"] or k["url"] for k in keep])
print("   丢掉：", dropped)
reasons = [d["reason"] for d in dropped]
assert "no_url" in reasons, "缺地址没丢"
assert reasons.count("duplicate_id") == 1, "id 去重不对"
assert any(d["reason"] == "api_too_new" and d["id"] == "future" for d in dropped), "高版本没拦住"
assert any(k["id"] == "old" for k in keep), "老版本该放行"
assert any(k["url"] == "https://f.example" for k in keep), "没 id 的该保留（客户端自己标未登记）"

print("== 3. 登记：分配 / 幂等 / 查重 ==")
META = {}


def fake_fetch(url):
    return META.get(url)


sites.fetch_meta = fake_fetch

META["https://a.example"] = {"api": 2, "site_id": "", "name": "A 站",
                             "description": "甲", "endpoints": [], "tags": ["技术"]}
c = db.conn()
it, created, need_config = sites.register(c, {"url": "https://a.example"})
print("   首次登记 ->", it["id"], "created =", created, "need_config =", need_config)
assert created
assert sites._SITE_ID.match(it["id"]), "分配的 id 不合规：%s" % it["id"]
assert need_config, "对方没 id，应该提示回填"

# 幂等：同地址再登记一次
it2, created2, _ = sites.register(c, {"url": "https://a.example"})
assert it2["id"] == it["id"] and not created2, "同地址重复登记不该换 id"
print("   重复登记 -> 同一个 id =", it2["id"], "（created=False）")

# 抢 id：另一座站自称同一个 id
META["https://b.example"] = {"api": 2, "site_id": it["id"], "name": "B 站"}
try:
    sites.register(c, {"url": "https://b.example"})
    raise AssertionError("id 被占居然登记成功")
except sites.ConflictError as e:
    print("   抢 id 被拒 ->", e)

# 同地址换 id
META["https://a.example"]["site_id"] = "another"
try:
    sites.register(c, {"url": "https://a.example", "site_id": "another"})
    raise AssertionError("同地址换 id 居然成功")
except sites.ConflictError as e:
    print("   同地址换 id 被拒 ->", e)
META["https://a.example"]["site_id"] = ""

# 没 id 的两座同名站：自动加序号
META["https://c.example"] = {"api": 2, "site_id": "", "name": "同名站"}
META["https://d.example"] = {"api": 2, "site_id": "", "name": "同名站"}
one, _, _ = sites.register(c, {"url": "https://c.example"})
two, _, _ = sites.register(c, {"url": "https://d.example"})
print("   同名站 ->", one["id"], "/", two["id"])
assert one["id"] != two["id"], "同名没加序号"

# 对方有合法 id：沿用，且不用回填
META["https://e.example"] = {"api": 2, "site_id": "kalutoex", "name": "时间線"}
three, created3, need3 = sites.register(c, {"url": "https://e.example"})
print("   自带 id ->", three["id"], "need_config =", need3)
assert three["id"] == "kalutoex" and created3 and not need3

# 地址没响应
try:
    sites.register(c, {"url": "https://ghost.example"})
    raise AssertionError("没响应的站居然登记成功")
except ValueError as e:
    print("   无响应被拒 ->", e)

print("== 4. 主站目录 ==")
cat = sites.catalog(c)
print("   条目：", [(s["id"], s["name"], s["api"]) for s in cat["sites"]])
assert len(cat["sites"]) == 4, "目录条数不对：%d" % len(cat["sites"])
assert all(s["endpoints"] for s in cat["sites"]), "目录里有缺地址的条目"
ids = [s["id"] for s in cat["sites"]]
assert len(ids) == len(set(ids)), "目录里有重复 id"

print("== 5. 目录能被自己的校验规则吃回去 ==")
keep2, dropped2 = sites.validate(cat)
assert len(keep2) == len(cat["sites"]) and not dropped2, dropped2
print("   平台导出 → 平台导入，零丢失")

c.close()
print("\n第 3 段离线自检全部通过")
