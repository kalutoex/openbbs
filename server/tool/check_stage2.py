# -*- coding: utf-8 -*-
"""第 2 段自检：JWT 签发、公钥离线验签、黑名单签名与拉取。
用临时数据目录，不碰线上库。
"""
import base64
import json
import os
import sys
import tempfile

SERVER = "/vol1/1000/data/code/ongoing/openbbs/server"
TMP = tempfile.mkdtemp(prefix="obb-")
os.environ["OPENBBS_DATA_DIR"] = TMP
os.environ["OPENBBS_DB"] = os.path.join(TMP, "t.db")
sys.path.insert(0, SERVER)

from app import auth, blacklist, db  # noqa: E402

db.init()


def b64d(x):
    return base64.urlsafe_b64decode(x + "=" * (-len(x) % 4))


print("== 1. JWT 签发 / 验签 ==")
tok = auth.make_token(42)
print("   parts =", tok.count(".") + 1)
assert tok.count(".") == 2, "不是三段式 JWT"
assert auth.read_token(tok) == 42, "本机验签失败"
print("   本机验签 OK")

pub = auth.public_pem()
print("   公钥行数 =", len(pub.splitlines()))
assert pub.startswith("-----BEGIN PUBLIC KEY-----")

from cryptography.hazmat.primitives import serialization  # noqa: E402

pk = serialization.load_pem_public_key(pub.encode())
h, p, s = tok.split(".")
pk.verify(b64d(s), (h + "." + p).encode())
print("   只拿公钥离线验签 OK（B1）")

assert auth.read_token(tok, pub) == 42, "传公钥验签失败"
print("   read_token(pub_pem=) OK")

bad = tok[:-4] + ("AAAA" if not tok.endswith("AAAA") else "BBBB")
assert auth.read_token(bad) is None, "篡改的 token 居然验过了"
print("   篡改拒绝 OK")

payload = json.loads(b64d(p))
assert "exp" not in payload, "C3 要求不过期，不该有 exp"
print("   payload =", payload, "（无 exp，符合 C3）")

print("== 2. 老 token 兼容 ==")
legacy = auth._make_legacy_token(7)
assert auth.read_token(legacy) == 7
print("   老格式仍可解 =>", auth.read_token(legacy))

print("== 3. 黑名单：封 / 导出 / 验签 / 拉取 ==")
c = db.conn()
blacklist.ban(c, 42, "测试封禁")
assert blacklist.is_banned(c, 42)
print("   封禁写入 OK")

exp = blacklist.export_since(c, 0)
print("   导出条目 =", exp["items"])
assert exp["items"] and exp["sig"], "导出没签名"
canon = blacklist._canon(exp["items"])
assert auth.verify_bytes(canon, exp["sig"], pub), "签名验不过"
print("   清单签名验过 OK")

# 换一个空库模拟小站落地
TMP2 = tempfile.mkdtemp(prefix="obb-slave-")
db.DB = os.path.join(TMP2, "s.db")
db.init()
c2 = db.conn()
assert not blacklist.is_banned(c2, 42)
c2.execute("INSERT INTO blacklist(uid, ts, reason, synced_at) VALUES(?,?,?,?) "
           "ON CONFLICT(uid) DO NOTHING", (exp["items"][0]["uid"], exp["items"][0]["ts"],
                                           exp["items"][0]["reason"], 0))
c2.commit()
assert blacklist.is_banned(c2, 42)
print("   小站落库后命中 OK（模拟 pull_once 的写入路径）")

print("== 4. 反向：签错就不收 ==")
assert not auth.verify_bytes(b"[]", exp["sig"], pub), "空列表居然验过同一签名"
print("   签名与内容绑定 OK")

print("\n全部通过")
