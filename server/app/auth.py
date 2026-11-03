# -*- coding: utf-8 -*-
"""口令哈希 + 签名 cookie。全用标准库，不引第三方。"""
import hashlib, hmac, base64, os, time

from . import config

# 签名密钥位置同样交给 config，默认 server/data/secret，首次启动自动生成。
SECRET_FILE = config.path("secret")


def _secret() -> bytes:
    if not os.path.exists(SECRET_FILE):
        os.makedirs(os.path.dirname(SECRET_FILE), exist_ok=True)
        with open(SECRET_FILE, "wb") as f:
            f.write(os.urandom(32))
        os.chmod(SECRET_FILE, 0o600)
    with open(SECRET_FILE, "rb") as f:
        return f.read()


SECRET = _secret()


def hash_pw(pw: str) -> str:
    salt = os.urandom(16)
    dk = hashlib.scrypt(pw.encode("utf-8"), salt=salt, n=16384, r=8, p=1, dklen=32)
    return base64.b64encode(salt).decode() + "$" + base64.b64encode(dk).decode()


def check_pw(pw: str, stored: str) -> bool:
    try:
        s, d = stored.split("$", 1)
        salt = base64.b64decode(s)
        want = base64.b64decode(d)
        got = hashlib.scrypt(pw.encode("utf-8"), salt=salt, n=16384, r=8, p=1, dklen=32)
        return hmac.compare_digest(got, want)
    except Exception:
        return False


def make_token(uid: int) -> str:
    payload = "%d:%d" % (uid, int(time.time()))
    sig = hmac.new(SECRET, payload.encode(), hashlib.sha256).hexdigest()[:32]
    return payload + ":" + sig


def read_token(tok: str):
    try:
        uid, ts, sig = tok.split(":")
        payload = "%s:%s" % (uid, ts)
        want = hmac.new(SECRET, payload.encode(), hashlib.sha256).hexdigest()[:32]
        if not hmac.compare_digest(sig, want):
            return None
        return int(uid)
    except Exception:
        return None
