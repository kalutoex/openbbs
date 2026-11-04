# -*- coding: utf-8 -*-
"""身份与签名。

主站用 Ed25519 私钥签发 JWT，公钥随 /meta 下发；
小站只验签、不需要私钥、不联网。

两条硬约束（PLAN-5-STEPS 第 2 段）：

  C3  token 不过期 —— 所以没法靠过期让封号生效，
      作废只能在接口层拦，见 blacklist。
  B1  公钥离线验签 —— 小站断网也能验已签发的 token。

旧格式 token（`uid:ts:sig`，本机 HMAC）保留解码能力，
平滑过渡用；新签发一律走 JWT。
"""
import base64
import hashlib
import hmac
import json
import os
import time

from . import config

try:
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric.ed25519 import (
        Ed25519PrivateKey, Ed25519PublicKey)
    _HAVE_ED = True
except Exception:  # pragma: no cover - 没装 cryptography 时退回 HMAC
    _HAVE_ED = False

# 私钥文件：32 字节裸私钥。和老的 HMAC secret 分开存，互不影响。
KEY_FILE = os.path.join(config.path("data"), "jwt_key")
LEGACY_SECRET_FILE = config.path("secret")

_priv = None


# ---------------------------------------------------------------- 私钥 / 公钥

def _read_raw(path: str) -> bytes:
    with open(path, "rb") as f:
        return f.read()


def _ensure_key():
    """首次启动生成密钥对。已存在就读，绝不覆盖（覆盖等于让所有 token 失效）。"""
    global _priv
    if _priv is not None:
        return _priv
    if not _HAVE_ED:
        return None
    if os.path.exists(KEY_FILE):
        try:
            _priv = Ed25519PrivateKey.from_private_bytes(_read_raw(KEY_FILE))
            return _priv
        except Exception:
            pass
    os.makedirs(os.path.dirname(KEY_FILE), exist_ok=True)
    _priv = Ed25519PrivateKey.generate()
    raw = _priv.private_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PrivateFormat.Raw,
        encryption_algorithm=serialization.NoEncryption())
    with open(KEY_FILE, "wb") as f:
        f.write(raw)
    os.chmod(KEY_FILE, 0o600)
    return _priv


def public_pem() -> str:
    """主站对外公布的验签公钥。小站拿这个就能离线验签。"""
    k = _ensure_key()
    if k is None:
        return ""
    pem = k.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo)
    return pem.decode("ascii")


def _load_public_pem(pem: str):
    """验签用：优先用配置里给的公钥（小站），没给就用本机私钥推出来（主站）。"""
    if pem:
        try:
            return serialization.load_pem_public_key(pem.encode("ascii"))
        except Exception:
            return None
    k = _ensure_key()
    return k.public_key() if k is not None else None


# 小站运行中从主站 /meta 取回来的公钥。取到之前验不了主站 token，先当匿名。
_master_pub = ""


def set_master_pub(pem: str) -> None:
    global _master_pub
    if pem:
        _master_pub = pem


def verify_pem() -> str:
    """当前该拿哪把公钥验签。

    主站：自己的。
    小站：主站 /meta 给的（配置里写了就用配置的，省一次请求）。
    """
    cfg_pub = config.get("auth", "public_key") or ""
    if cfg_pub:
        return cfg_pub
    if config.get("site", "master_url"):
        return _master_pub
    return public_pem()


# ---------------------------------------------------------------- JWT

def _b64e(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def _b64d(s: str) -> bytes:
    pad = "=" * (-len(s) % 4)
    return base64.urlsafe_b64decode(s + pad)


def _site_id() -> str:
    return str(config.get("site", "site_id") or "")


def make_token(uid: int) -> str:
    """签发。没有 exp —— C3 定的不过期。"""
    header = {"alg": "EdDSA", "typ": "JWT"}
    payload = {"uid": int(uid), "iat": int(time.time())}
    sid = _site_id()
    if sid:
        payload["iss"] = sid
    h = _b64e(json.dumps(header, separators=(",", ":"), sort_keys=True).encode())
    p = _b64e(json.dumps(payload, separators=(",", ":"), sort_keys=True).encode())
    msg = ("%s.%s" % (h, p)).encode("ascii")
    k = _ensure_key()
    if k is None:
        return _make_legacy_token(uid)
    sig = k.sign(msg)
    return "%s.%s.%s" % (h, p, _b64e(sig))


def read_token(tok: str, pub_pem: str = ""):
    """验签取 uid。JWT 优先，认不出来再按老格式试一遍。

    pub_pem 留给小站：传主站 /meta 给的公钥即可离线验签。
    不传就按本机角色自动选（见 verify_pem）。
    主站公钥验不过时再拿本机公钥试一次 —— 小站自己的管理员登录走这条。
    """
    if not tok:
        return None
    if tok.count(".") == 2:
        try:
            h, p, s = tok.split(".")
            header = json.loads(_b64d(h))
            if header.get("alg") != "EdDSA":
                return None
            msg = ("%s.%s" % (h, p)).encode("ascii")
            sig = _b64d(s)
            for cand in (pub_pem, verify_pem(), public_pem()):
                pub = _load_public_pem(cand) if cand else None
                if pub is None:
                    continue
                try:
                    pub.verify(sig, msg)
                    payload = json.loads(_b64d(p))
                    uid = payload.get("uid")
                    return int(uid) if uid is not None else None
                except Exception:
                    continue
            return None
        except Exception:
            return None
    return _read_legacy_token(tok)


# ---------------------------------------------------------------- 老格式（兼容用）

def _legacy_secret() -> bytes:
    if not os.path.exists(LEGACY_SECRET_FILE):
        os.makedirs(os.path.dirname(LEGACY_SECRET_FILE), exist_ok=True)
        with open(LEGACY_SECRET_FILE, "wb") as f:
            f.write(os.urandom(32))
        os.chmod(LEGACY_SECRET_FILE, 0o600)
    return _read_raw(LEGACY_SECRET_FILE)


def _make_legacy_token(uid: int) -> str:
    payload = "%d:%d" % (uid, int(time.time()))
    sig = hmac.new(_legacy_secret(), payload.encode(), hashlib.sha256).hexdigest()[:32]
    return payload + ":" + sig


def _read_legacy_token(tok: str):
    try:
        uid, ts, sig = tok.split(":")
        payload = "%s:%s" % (uid, ts)
        want = hmac.new(_legacy_secret(), payload.encode(), hashlib.sha256).hexdigest()[:32]
        if not hmac.compare_digest(sig, want):
            return None
        return int(uid)
    except Exception:
        return None


# ---------------------------------------------------------------- 通用签名
# 黑名单清单等数据用同一套密钥签名，小站验签即可。

def hmac_hex(data: bytes) -> str:
    """固定密钥的 HMAC-SHA256 十六进制摘要。验证码等短哈希用它，不参与对外签名。"""
    return hmac.new(_legacy_secret(), data, hashlib.sha256).hexdigest()


def sign_bytes(data: bytes) -> str:
    k = _ensure_key()
    if k is None:
        return ""
    return _b64e(k.sign(data))


def verify_bytes(data: bytes, sig_b64: str, pub_pem: str = "") -> bool:
    pub = _load_public_pem(pub_pem)
    if pub is None or not sig_b64:
        return False
    try:
        pub.verify(_b64d(sig_b64), data)
        return True
    except Exception:
        return False


# ---------------------------------------------------------------- 口令

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
