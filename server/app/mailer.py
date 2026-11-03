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

CONFIG_FILE = "/vol1/1000/data/code/ongoing/bbs/server/config/mail.json"
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


def send_code(to_addr: str, code: str, minutes: int = 10) -> None:
    cfg = _config()
    title = "时间線 注册验证码"
    body = (
        "你的注册验证码是：\n\n"
        f"        {code}\n\n"
        f"{minutes} 分钟内有效，只能用一次。\n"
        "不是你本人操作的话，忽略这封邮件就行。\n"
    )
    msg = MIMEText(body, "plain", "utf-8")
    msg["Subject"] = Header(title, "utf-8")
    msg["From"] = "%s <%s>" % (
        Header(cfg.get("from_name") or "时间線", "utf-8").encode(),
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
