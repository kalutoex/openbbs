# -*- coding: utf-8 -*-
"""第 5 段自检：部署包与运维。

纯离线，不起服务、不装依赖。查的是「站长拿到手能不能按文档跑起来」：
配置段齐不齐、脚本语法过不过、镜像要拷的文件在不在、备份恢复的链路对不对。

    python3 server/tool/check_stage5.py
"""
import json
import os
import re
import subprocess
import sys
import tempfile

SERVER = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
fail = []


def ok(msg):
    print("   %s" % msg)


def bad(msg):
    print("   ✗ %s" % msg)
    fail.append(msg)


def read(p):
    with open(os.path.join(SERVER, p), "r", encoding="utf-8") as f:
        return f.read()


def check_json_example():
    print("== 1. site.json.example ==")
    p = os.path.join(SERVER, "config", "site.json.example")
    with open(p, "r", encoding="utf-8") as f:
        d = json.load(f)
    for sec, keys in (
        ("server", ["host", "port", "tls_cert_dir"]),
        ("backup", ["dir", "keep"]),
        ("update", ["check_url"]),
        ("site", ["name", "base_url", "site_id", "master_url"]),
    ):
        got = d.get(sec) or {}
        miss = [k for k in keys if k not in got]
        if miss:
            bad("%s 段缺 %s" % (sec, ", ".join(miss)))
        else:
            ok("%s 段齐全（%s）" % (sec, "、".join(keys)))
    if d.get("server", {}).get("port") != 8080:
        bad("server.port 默认不是 8080")
    return d


def check_config_priority():
    print("== 2. 改端口只动 site.json ==")
    tmp = tempfile.mkdtemp(prefix="obb5-")
    cfg = os.path.join(tmp, "site.json")
    with open(cfg, "w", encoding="utf-8") as f:
        json.dump({"server": {"port": 9100, "host": "127.0.0.1"},
                   "backup": {"keep": 7, "dir": os.path.join(tmp, "bk")}}, f)

    probe = (
        "import sys, json; sys.path.insert(0, %r);"
        "from app import config;"
        "print(json.dumps({'port': config.get('server','port'),"
        " 'host': config.get('server','host'),"
        " 'keep': config.get('backup','keep'),"
        " 'bk': config.path('backups'),"
        " 'db': config.path('db')}))" % SERVER
    )

    env = dict(os.environ, OPENBBS_CONFIG=cfg, OPENBBS_DATA_DIR=tmp)
    out = subprocess.check_output([sys.executable, "-c", probe], env=env).decode().strip()
    got = json.loads(out)
    ok("site.json 端口 %s，host %s" % (got["port"], got["host"]))
    if got["port"] != 9100 or got["host"] != "127.0.0.1":
        bad("server 段没生效：%s" % got)
    if got["keep"] != 7 or not got["bk"].endswith("bk"):
        bad("backup 段没生效：%s" % got)
    if got["db"] != os.path.join(tmp, "forum.db"):
        bad("paths.data 没跟着走：%s" % got["db"])

    # 环境变量优先于文件
    env2 = dict(env, OPENBBS_PORT="9200", OPENBBS_BACKUP_KEEP="3")
    out = subprocess.check_output([sys.executable, "-c", probe], env=env2).decode().strip()
    got2 = json.loads(out)
    if got2["port"] != 9200 or got2["keep"] != 3:
        bad("环境变量没盖过 site.json：%s" % got2)
    else:
        ok("环境变量优先（端口 %s，份数 %s）" % (got2["port"], got2["keep"]))


def check_scripts():
    print("== 3. 脚本 ==")
    for name in ("install.sh", "run.sh", "backup.sh", "restore.sh", "check_update.sh", "_cfg.sh"):
        p = os.path.join(SERVER, name)
        if not os.path.exists(p):
            bad("缺 %s" % name)
            continue
        r = subprocess.run(["bash", "-n", p], capture_output=True)
        if r.returncode != 0:
            bad("%s 语法错：%s" % (name, r.stderr.decode().strip()[:200]))
            continue
        if name != "_cfg.sh" and not os.access(p, os.X_OK):
            bad("%s 没有执行位" % name)
            continue
        ok("%s 语法过，可执行" % name)

    # 关键行为：备份文件名要带秒，否则同分钟两次会互相覆盖
    if "%H%M%S" not in read("backup.sh"):
        bad("backup.sh 的 STAMP 没到秒，同分钟两次备份会覆盖")
    else:
        ok("备份文件名精确到秒")
    if "db_snapshot.py\" --check" not in read("backup.sh"):
        bad("backup.sh 没做快照自检")
    else:
        ok("备份前验快照")
    if "--yes" not in read("restore.sh") or "before_restore" not in read("restore.sh"):
        bad("restore.sh 缺确认参数或留底")
    else:
        ok("恢复前给现有数据留底")


def check_docker():
    print("== 4. 容器 ==")
    df = read("Dockerfile")
    for f in re.findall(r"^COPY\s+([^/\n]+)\s+/app/?$", df, re.M):
        for item in f.split():
            if not os.path.exists(os.path.join(SERVER, item)):
                bad("Dockerfile 要拷的 %s 不存在" % item)
    if "VOLUME [\"/app/data\", \"/app/config\"]" not in df:
        bad("Dockerfile 没声明 data / config 卷")
    else:
        ok("data 和 config 在卷上")
    if "docker-entrypoint.sh" not in df:
        bad("Dockerfile 没用入口脚本，端口就读不到 site.json")
    else:
        ok("入口脚本读 site.json 的 server 段")

    comp = read("docker-compose.yml")
    if "./data:/app/data" not in comp or "./config:/app/config" not in comp:
        bad("compose 没挂 data / config")
    else:
        ok("compose 挂了 data 和 config")
    if "network_mode: host" not in comp:
        bad("compose 没写 host 网络，端口不会跟着 site.json 走")
    else:
        ok("host 网络，端口由 site.json 定")

    ignore = read(".dockerignore")
    for must in ("data/", "config/site.json", ".venv/"):
        if must not in ignore:
            bad(".dockerignore 漏了 %s" % must)
    else:
        ok(".dockerignore 挡住了数据和配置")


def check_update_hint():
    print("== 5. 只提示不自动升 ==")
    src = read("check_update.sh")
    for word in ("curl -fsS", "sys.exit(1)", "不自动升级"):
        if word not in src:
            bad("check_update.sh 缺「%s」" % word)
    else:
        ok("只拉版本号打印，不下载升级")

    out = subprocess.run(["bash", os.path.join(SERVER, "check_update.sh"), ""],
                         capture_output=True, env=dict(os.environ, OPENBBS_CONFIG="/nonexistent"))
    text = out.stdout.decode().strip()
    if not text.startswith("当前"):
        bad("check_update.sh 在没配地址时没打印当前版本：%r" % text[:80])
    else:
        ok(text.splitlines()[0])

    ver = read("VERSION").strip()
    if not re.match(r"^\d+\.\d+", ver):
        bad("VERSION 不是版本号：%r" % ver)
    else:
        ok("server/VERSION = %s" % ver)


def check_install_flow():
    print("== 6. install.sh 的内容 ==")
    src = read("install.sh")
    for what, word in (
        ("检 python 版本", "sys.version_info>=(3,9)"),
        ("建 venv", "-m venv"),
        ("写 site.json", "site.json"),
        ("建库", "db.init()"),
        ("生成管理码", "ensure_admin()"),
        ("--docker 模式", "--docker"),
        ("幂等备份", "site.json.bak"),
    ):
        if word not in src:
            bad("install.sh 没做「%s」" % what)
        else:
            ok(what)


def main():
    check_json_example()
    check_config_priority()
    check_scripts()
    check_docker()
    check_update_hint()
    check_install_flow()
    print()
    if fail:
        print("没过：%d 项" % len(fail))
        return 1
    print("第 5 段自检全过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
