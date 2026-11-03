# -*- coding: utf-8 -*-
"""站点配置。

优先级：环境变量 > config/site.json > 这里的默认值。

对外交付的东西，路径、限制、开关都不该写死在代码里。
部署的人改 site.json，容器里用环境变量覆盖，两者都不碰代码。

配置在启动时读一次，改完要重启。
"""
import json
import os

# server/app/config.py → server/
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_FILE = os.environ.get("OPENBBS_CONFIG") or os.path.join(ROOT, "config", "site.json")

DEFAULTS = {
    "site": {
        "name": "OpenBBS",
        "description": "一个能自己部署的轻论坛",
        "base_url": "",
        # 主站登记的站点 id。空 = 这台就是主站（或还没登记）。
        "site_id": "",
        # 主站地址。空 = 本机即主站，签发自签，黑名单直接读本地表。
        "master_url": "",
        # 以下是清单里对外自述的字段，站点自己填。
        "lang": "zh-Hans",
        "icon": "",
        "tags": [],
        "contact": "",
        # 多个入口（v6 直连、v4 中转…）。空则只报 base_url。
        "endpoints": [],
        # 是否开放注册。清单里给客户端看的。
        "open": True,
    },
    "sites": {
        # 登记接口会回访对方地址。默认不许回访内网，免得被拿来探内网。
        # 本机测试时打开。
        "allow_private": False,
        # 同一 IP 每小时最多登记几次。0 = 不限。
        "register_per_hour_ip": 10,
    },
    "paths": {
        # 空字符串 = 落在 server/data 下，开箱即用。
        "data": "",
        "db": "",
        "uploads": "",
        "apk": "",
        "secret": "",
        "mail_config": "",
        "logs": "",
    },
    "limits": {
        "per_page": 20,
        "floor_per_page": 20,
        "max_image_mb": 5,
        "max_anim_mb": 10,
        "max_images": 9,
        "max_level": 99,
        "username_min": 2,
        "username_max": 20,
        "password_min": 8,
        "title_max": 120,
        "body_max": 20000,
    },
    "auth": {
        "register_open": True,
        # 小站（M1）不放注册，账号只在主站建。
        "require_email": True,
        # 黑名单拉取间隔（秒）。主站自己不用。
        "blacklist_pull_seconds": 60,
        # 小站的验签公钥。空 + 配了 master_url 时，首次从主站 /meta 取回来存这里。
        "public_key": "",
        "code_ttl": 600,
        "code_max_tries": 5,
        "send_cooldown": 60,
        "send_per_hour_email": 3,
        "send_per_hour_ip": 5,
        "reg_per_hour_ip": 5,
        "login_fail_max": 5,
        "login_fail_window": 60,
    },
    "http": {
        "cors_origins": [],
        "cors_origin_regex": r"http://(localhost|127\.0\.0\.1)(:\d+)?",
    },
    "update": {
        # 关掉后 /app/latest 直接 404，客户端自动检查会静默跳过。
        "enabled": True,
        # 客户端多久自动查一次（小时）。0 = 每次启动都查。
        "check_hours": 24,
        # 点过「以后再说」之后隔多久再弹（小时）。0 = 每次启动都弹。
        "remind_hours": 24,
        # 客户端 build 低于这个数就必须更新，弹窗关不掉。0 = 不强制。
        "force_below": 0,
        # 弹窗文案，可用 {version} {current} {notes} {size}。留空由客户端自己拼。
        "title": "发现新版本 {version}",
        "message": "当前版本 {current}，最新 {version}。\n\n{notes}",
    },
    "admin": {
        "name": "admin",
        # 空 = 首次启动生成随机密码，写进 data/admin_initial.txt，只给部署的人看。
        "password": "",
    },
    "mail": {
        "from_name": "OpenBBS",
        "subject_register": "注册验证码",
        "subject_reset": "找回密码验证码",
        "subject_bind": "绑定邮箱验证码",
        "body": "你的验证码是：{code}\n\n{minutes} 分钟内有效。不是你自己操作的就忽略这封邮件。",
    },
}

# 环境变量覆盖表：OPENBBS_<KEY> → 配置里的路径。
_ENV_MAP = {
    "OPENBBS_SITE_NAME": ("site", "name"),
    "OPENBBS_SITE_BASE_URL": ("site", "base_url"),
    "OPENBBS_SITE_ID": ("site", "site_id"),
    "OPENBBS_MASTER_URL": ("site", "master_url"),
    "OPENBBS_SITE_LANG": ("site", "lang"),
    "OPENBBS_SITE_ICON": ("site", "icon"),
    "OPENBBS_SITE_TAGS": ("site", "tags"),
    "OPENBBS_SITE_CONTACT": ("site", "contact"),
    "OPENBBS_SITES_ALLOW_PRIVATE": ("sites", "allow_private"),
    "OPENBBS_SITES_REGISTER_PER_HOUR_IP": ("sites", "register_per_hour_ip"),
    "OPENBBS_PUBLIC_KEY": ("auth", "public_key"),
    "OPENBBS_BLACKLIST_PULL_SECONDS": ("auth", "blacklist_pull_seconds"),
    "OPENBBS_DATA_DIR": ("paths", "data"),
    "OPENBBS_DB": ("paths", "db"),
    "OPENBBS_UPLOAD_DIR": ("paths", "uploads"),
    "OPENBBS_APK_DIR": ("paths", "apk"),
    "OPENBBS_SECRET_FILE": ("paths", "secret"),
    "OPENBBS_MAIL_CONFIG": ("paths", "mail_config"),
    "OPENBBS_LOG_DIR": ("paths", "logs"),
    "OPENBBS_CORS_ORIGINS": ("http", "cors_origins"),
    "OPENBBS_REGISTER_OPEN": ("auth", "register_open"),
    "OPENBBS_REQUIRE_EMAIL": ("auth", "require_email"),
    "OPENBBS_UPDATE_ENABLED": ("update", "enabled"),
    "OPENBBS_UPDATE_CHECK_HOURS": ("update", "check_hours"),
    "OPENBBS_UPDATE_REMIND_HOURS": ("update", "remind_hours"),
    "OPENBBS_UPDATE_FORCE_BELOW": ("update", "force_below"),
    "OPENBBS_ADMIN_PASSWORD": ("admin", "password"),
}

_cache = None


def _merge(base, over):
    for k, v in (over or {}).items():
        if isinstance(v, dict) and isinstance(base.get(k), dict):
            _merge(base[k], v)
        else:
            base[k] = v
    return base


def _coerce(key, raw):
    """环境变量都是字符串，按配置里默认值的类型转一下。"""
    path = ".".join(key)
    cur = _raw_get(DEFAULTS, key)
    if isinstance(cur, bool):
        return raw.strip().lower() in ("1", "true", "yes", "on")
    if isinstance(cur, int):
        try:
            return int(raw)
        except ValueError:
            return cur
    if isinstance(cur, list):
        return [x.strip() for x in raw.split(",") if x.strip()]
    return raw


def _raw_get(d, keys):
    for k in keys:
        if not isinstance(d, dict) or k not in d:
            return None
        d = d[k]
    return d


def load():
    global _cache
    if _cache is not None:
        return _cache

    cfg = json.loads(json.dumps(DEFAULTS))
    try:
        with open(CONFIG_FILE, "r", encoding="utf-8") as f:
            _merge(cfg, json.load(f))
    except FileNotFoundError:
        pass
    except Exception as e:  # 配置写坏了不该把站拖死，退回默认并留个痕迹
        print("配置读不了，用默认值：%s" % e)

    for env, key in _ENV_MAP.items():
        raw = os.environ.get(env)
        if raw:
            node = cfg
            for k in key[:-1]:
                node = node.setdefault(k, {})
            node[key[-1]] = _coerce(key, raw)

    _cache = cfg
    return cfg


def get(section, key=None, default=None):
    cfg = load()
    node = cfg.get(section)
    if key is None:
        return node if node is not None else default
    if not isinstance(node, dict):
        return default
    v = node.get(key, default)
    return default if v is None else v


# ---------------------------------------------------------------- 路径
# 全部基于项目根算，不写死任何人的家目录。


def path(name):
    """name: data / db / uploads / apk / secret / mail_config / logs"""
    data = get("paths", "data") or os.path.join(ROOT, "data")
    defaults = {
        "data": data,
        "db": os.path.join(data, "forum.db"),
        "uploads": os.path.join(data, "uploads"),
        "apk": os.path.join(data, "apk"),
        "secret": os.path.join(data, "secret"),
        "logs": os.path.join(ROOT, "logs"),
        "mail_config": os.path.join(ROOT, "config", "mail.json"),
    }
    return get("paths", name) or defaults[name]


def ensure_dirs():
    for k in ("data", "uploads", "apk", "logs"):
        os.makedirs(path(k), exist_ok=True)


def public():
    """能公开给客户端的部分：只放站点信息，不放路径和限制细节。"""
    cfg = load()
    return {
        "name": cfg["site"]["name"],
        "description": cfg["site"]["description"],
        "base_url": cfg["site"]["base_url"],
        "site_id": cfg["site"]["site_id"],
        # 主站地址只给出「是不是主站」，具体地址放 /meta
        "is_master": not cfg["site"]["master_url"],
        "register_open": cfg["auth"]["register_open"],
        "require_email": cfg["auth"]["require_email"],
        "limits": {
            "per_page": cfg["limits"]["per_page"],
            "max_images": cfg["limits"]["max_images"],
            "max_image_mb": cfg["limits"]["max_image_mb"],
            "username_min": cfg["limits"]["username_min"],
            "username_max": cfg["limits"]["username_max"],
            "password_min": cfg["limits"]["password_min"],
        },
    }
