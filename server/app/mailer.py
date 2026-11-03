# -*- coding: utf-8 -*-
"""发验证码邮件。标准库 smtplib，配置放在 config/mail.json（600）。

配置缺失时 send_code() 抛 MailNotConfigured，接口层转成 503，
免得没配好邮件还让人以为验证码发出去了。
"""
import json
import os
import smtplib
import ssl
from email.header import Header
from email.mime.text import MIMEText

from . import config

# 邮件账号信息放在 config/mail.json，位置可由 OPENBBS_MAIL_CONFIG 覆盖。
CONFIG_FILE = config.path("mail_config")
TIMEOUT = 12


class MailNotConfigured(Exception):
    pass


class MailSendError(Exception):
    pass


def _config():
    if not os.path.exists(CONFIG_FILE):
        raise MailNotConfigured("邮件服务没配置")
    with open(CONFIG_FILE, "r", encoding="utf-8") as f:
        cfg = json.load(f)
    if not cfg.get("host") or not cfg.get("user") or not cfg.get("password"):
        raise MailNotConfigured("邮件服务没配置")
    return cfg


SUBJECT_KEYS = {
    "register": "subject_register",
    "reset": "subject_reset",
    "bind": "subject_bind",
}


def send_code(to_addr: str, code: str, minutes: int = 10,
              kind: str = "register") -> None:
    """kind: register / reset / bind —— 三种码用途不同，标题也该不同。"""
    cfg = _config()
    mail_cfg = config.get("mail")
    title = "%s %s" % (
        config.get("site", "name"),
        mail_cfg.get(SUBJECT_KEYS.get(kind, "subject_register"), "验证码"),
    )
    tpl = mail_cfg.get("body") or "你的验证码是：{code}\n\n{minutes} 分钟内有效。"
    body = tpl.replace("{code}", code).replace("{minutes}", str(minutes))
    msg = MIMEText(body, "plain", "utf-8")
    msg["Subject"] = Header(title, "utf-8")
    msg["From"] = "%s <%s>" % (
        Header(cfg.get("from_name") or mail_cfg.get("from_name")
               or config.get("site", "name"), "utf-8").encode(),
        cfg.get("from_addr") or cfg["user"],
    )
    msg["To"] = to_addr

    host, port = cfg["host"], int(cfg.get("port") or 465)
    try:
        if cfg.get("ssl", True):
            ctx = ssl.create_default_context()
            with smtplib.SMTP_SSL(host, port, timeout=TIMEOUT, context=ctx) as s:
                s.login(cfg["user"], cfg["password"])
                s.sendmail(cfg.get("from_addr") or cfg["user"], [to_addr], msg.as_string())
        else:
            with smtplib.SMTP(host, port, timeout=TIMEOUT) as s:
                s.starttls(context=ssl.create_default_context())
                s.login(cfg["user"], cfg["password"])
                s.sendmail(cfg.get("from_addr") or cfg["user"], [to_addr], msg.as_string())
    except MailNotConfigured:
        raise
    except Exception as e:  # 网络、认证、被拒收都归这类
        raise MailSendError(str(e)) from e
