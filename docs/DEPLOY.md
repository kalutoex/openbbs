# 部署

给站长看的。目标：一台空机器，十分钟出站，之后只改 `site.json`。

---

## 一、挑一种跑法

| 形态 | 适合 | 命令 |
|---|---|---|
| 直接跑 | 有 python3.9+ 的 Linux / NAS | `./install.sh` 然后 `./run.sh` |
| Docker | 有 docker，不想碰 python 环境 | `./install.sh --docker` 然后 `docker compose up -d` |
| tar 包 | 离线机器，或想自己摆目录 | 解包到任意目录，同上 |

三种形态的数据都只在 `data/`，配置都只在 `config/site.json`。换机器就是搬这两个目录。

---

## 二、十分钟流程

```bash
# 1 拿代码（或者解 tar 包）
cd openbbs/server

# 2 一条命令：检依赖、写 site.json、装依赖、建库、生成管理码
./install.sh

# 3 起站
./run.sh

# 4 看一眼
curl -s [::1]:8080/api/meta | head
```

`install.sh` 会问站名、端口、主站地址、对外地址，回车就取默认值。全程可以无交互：

```bash
./install.sh --name 时间線 --port 8080 \
             --url https://bbs.example.com \
             --master https://bbs.example.com \
             --yes
```

管理码在 `data/admin_initial.txt`，登录后改掉。重复跑 `install.sh` 不会覆盖你填过的值，
只会补缺的键，旧 `site.json` 会先备份成 `site.json.bak.<时间>`。

依赖装得慢就先设个源：

```bash
OPENBBS_PIP_INDEX=https://pypi.tuna.tsinghua.edu.cn/simple ./install.sh --yes
```

---

## 三、Docker

```bash
./install.sh --docker --name 时间線 --port 8080 --url https://bbs.example.com --yes
docker compose up -d --build
docker compose logs -f
```

- 默认 `network_mode: host`：端口就是 `site.json` 里的 `server.port`，改端口不用改 compose，重启容器即可。IPv6 也能直接连。
- 不想用 host 网络（Docker Desktop 之类）：把 compose 里的 `network_mode` 换成 `ports: ["8080:8080"]`，两边端口跟 `site.json` 对上。
- 卷：`./data`、`./config`、`./logs`。删容器不删数据。

---

## 四、端口、HTTPS、主站

全在 `config/site.json`，改完重启。

```json
{
  "site": {
    "name": "时间線",
    "base_url": "https://bbs.example.com",
    "master_url": ""
  },
  "server": {
    "host": "0.0.0.0",
    "port": 8080,
    "tls_cert_dir": ""
  }
}
```

- **改端口**：只改 `server.port`。`run.sh` 和容器都读它。
- **自己终止 TLS**：`tls_cert_dir` 指向含 `fullchain.pem` + `privkey.pem` 的目录，自动开 HTTPS。
- **前面有 nginx**：`tls_cert_dir` 留空，让 nginx 终止；`host` 可以改 `127.0.0.1` 不让外网直连。
- **这台是主站**：`master_url` 留空。
- **这台是小站**：填主站的 `master_url`，`site_id` 留空，启动后自动去登记。

注册要邮箱验证码的话，`config/mail.json` 里配 SMTP。没有邮件服务就把 `auth.require_email` 关掉。

---

## 五、备份与恢复

每天一次，SQLite 用 `.backup`（WAL 里没落盘的也带上），uploads 一起打包：

```bash
0 4 * * * /path/to/server/backup.sh
```

保留份数和目录在 `site.json` 的 `backup` 段：

```json
"backup": { "dir": "/mnt/backup/openbbs", "keep": 30 }
```

手动跑、立刻跑都行：`./backup.sh`。日志在 `logs/backup.log`。

恢复：

```bash
./restore.sh data/backups/forum_backups_20261103_040000.tar.gz
```

脚本先解包验快照（核心表查得动才算过），再把现有数据打包留底，然后停站、换库、起站。
任何一步失败都在覆盖前退出，旧数据不会被写坏。`--db-only` 只还数据库不动图片。

---

## 六、升级

不自动升级，只提示：

```bash
./check_update.sh
```

有新版会打印版本号和说明，然后自己决定什么时候换。换的时候：

1. `./backup.sh`
2. 替换代码目录（`data/`、`config/` 不动）
3. `./run.sh --stop` → `./run.sh`

数据库结构升级在启动时自动补列，不用手工迁移。

也可以把它挂进 cron，只收提示：

```bash
0 9 * * * /path/to/server/check_update.sh
```

有新版本时退出码是 1，接通知脚本用得上。

---

## 七、出问题先看这三处

| 现象 | 看哪 |
|---|---|
| 起不来 | `logs/forum.log` 最后 30 行；`./run.sh` 前台会直接报端口占用 |
| 8080 没响应 | `ss -ltnp \| grep 8080`；`data/forum.pid` 里的 pid 还在不在 |
| 图片 404 | `data/uploads` 权限；换机器时有没有一起搬 |
| 备份失败 | `logs/backup.log`；快照自检不过会明确写「本次不写备份」 |
| 容器起不来 | `docker compose logs --tail 50`；多半是 `config/site.json` 没挂进去 |

健康检查地址：`/api/meta`，返回 200 就是活的。

## 八、加新依赖：镜像缺包体的坑

`PUB_HOSTED_URL=https://pub.flutter-io.cn` 的元数据是全的，但个别包的 tar 包镜像没同步，
表现为 `flutter pub get` 一路解析成功，最后报：

```
Package not available (could not find package share_plus at https://pub.flutter-io.cn).
```

看到这句别怀疑版本号或拼写，八成是包体 404。验证：

```
flutter pub get -v 2>&1 | grep "HTTP response 404"
```

回源单独下一次，塞进镜像缓存，再离线解析：

```
PUB_HOSTED_URL=https://pub.dev flutter pub get      # 包体落到 hosted/pub.dev/
cp -r ~/.pub-cache/hosted/pub.dev/<包>-<版本> ~/.pub-cache/hosted/pub.flutter-io.cn/
flutter pub get --offline                            # 让 package_config 指回镜像
flutter build apk --no-pub                           # 关键：别让 build 再去解析，失败会把刚塞的目录清掉
```

`deploy_web.sh` 里的 `flutter build web` 已经带 `--no-pub`，原因同上。
