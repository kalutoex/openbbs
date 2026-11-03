# -*- coding: utf-8 -*-
"""为端到端测试准备一个临时库：admin + 一个普通用户。"""
import os
import sys
import tempfile

SERVER = "/vol1/1000/data/code/ongoing/openbbs/server"
TMP = "/tmp/obb-live"
os.makedirs(TMP, exist_ok=True)
os.environ["OPENBBS_DATA_DIR"] = TMP
os.environ["OPENBBS_DB"] = os.path.join(TMP, "t.db")
os.environ["OPENBBS_ADMIN_PASSWORD"] = "adminpass123"
sys.path.insert(0, SERVER)

from app import api, auth, db  # noqa: E402

db.init()
api.seed()

c = db.conn()
for name in ("alice", "bob"):
    row = c.execute("SELECT id FROM users WHERE name=?", (name,)).fetchone()
    if not row:
        c.execute("INSERT INTO users(name, pw, created_at) VALUES(?,?,1)",
                  (name, auth.hash_pw("pw12345678")))
c.commit()
for r in c.execute("SELECT id, name, uid, master_uid FROM users").fetchall():
    print(r["id"], r["name"], r["uid"], r["master_uid"])
print("admin pw file:", os.path.join(TMP, "admin_initial.txt"))
c.close()
