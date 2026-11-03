# 配置手册

OpenBBS 不要求改代码来适配站点。能配的东西分三层：

| 层 | 谁改 | 在哪 | 改完 |
|---|---|---|---|
| 站点配置 | 站长 | `server/config/site.json` | 重启进程 |
| 环境变量 | 运维 / 容器 | 启动命令或 compose | 重启容器 |
| 构建参数 | 出客户端包的人 | `--dart-define` | 重新打包 |

优先级：**环境变量 > site.json > 程序内默认值**。

`site.json` 不存在也能跑，全部走默认。想改就先复制一份：

```bash
cp server/config/site.json.example server/config/site.json
```

---

## 一、站点配置 `server/config/site.json`

### site —— 站点身份

| 键 | 默认 | 说明 |
|---|---|---|
| `name` | OpenBBS | 站点名。邮件标题、页面标题、API 元信息都用它 |
| `description` | 一个能自己部署的轻论坛 | 简介 |
| `base_url` | 空 | 对外地址，留空则按请求推断 |

### paths —— 数据放哪

留空 = `server/data`。容器部署一般全挂卷，写绝对路径。

| 键 | 说明 |
|---|---|
| `data` | 数据根目录 |
| `db` | SQLite 文件，默认 `<data>/forum.db` |
| `uploads` | 上传的图片 |
| `apk` | 客户端安装包（stable / beta 两个子目录） |
| `secret` | 会话签名密钥，首次启动自动生成 |
| `mail_config` | 邮件账号文件，默认 `server/config/mail.json` |
| `logs` | 日志目录，默认 `server/logs` |

### limits —— 内容与账号限制

| 键 | 默认 | 说明 |
|---|---|---|
| `per_page` | 20 | 列表每页条数 |
| `floor_per_page` | 20 | 楼层每页条数 |
| `max_image_mb` | 5 | 单张图片上限 |
| `max_anim_mb` | 10 | 动图上上限 |
| `max_images` | 9 | 一帖最多几张图 |
| `max_level` | 99 | 等级上限 |
| `username_min` / `username_max` | 2 / 20 | 用户名长度 |
| `password_min` | 8 | 密码最短 |
| `title_max` | 120 | 标题字数 |
| `body_max` | 20000 | 正文和回复字数 |

### auth —— 注册与登录

| 键 | 默认 | 说明 |
|---|---|---|
| `register_open` | true | 关掉后注册接口直接 403 |
| `require_email` | true | **预留**：目前后端只提供邮箱注册这一条路径，改 false 暂时没有效果 |
| `code_ttl` | 600 | 验证码有效期（秒） |
| `code_max_tries` | 5 | 验证码最多试几次 |
| `send_cooldown` | 60 | 同一邮箱两次发码间隔 |
| `send_per_hour_email` | 3 | 单邮箱每小时发码上限 |
| `send_per_hour_ip` | 5 | 单 IP 每小时发码上限 |
| `reg_per_hour_ip` | 5 | 单 IP 每小时注册上限 |
| `login_fail_max` | 5 | 单 IP 每分钟密码错几次就拦 |
| `login_fail_window` | 60 | 上面那个窗口（秒） |

### http —— 跨源

| 键 | 默认 | 说明 |
|---|---|---|
| `cors_origins` | `[]` | 允许的完整来源，如 `["https://bbs.example.com"]`。网页和接口同域名不同端口也算跨源，要加进来 |
| `cors_origin_regex` | `http://(localhost\|127\.0\.0\.1)(:\d+)?` | 正则兜底，默认放行本机调试 |

### forums —— 首次启动建哪些板块

只在空库时生效。之后以数据库为准。

```json
"forums": [
  { "name": "chitchat", "title": "闲聊", "desc": "什么都聊" }
]
```

### admin —— 首个管理员

| 键 | 默认 | 说明 |
|---|---|---|
| `name` | admin | 首个管理员用户名 |
| `password` | 空 | **留空最安全**：首次启动随机生成，写在 `data/admin_initial.txt`（权限 600） |

### mail —— 邮件

客户端发件在 `config/mail.json`（不进版本库），这里只管文案。

| 键 | 说明 |
|---|---|
| `from_name` | 发件人显示名 |
| `subject_register` / `subject_reset` / `subject_bind` | 三种验证码的标题后缀 |
| `body` | 正文模板，支持 `{code}` `{minutes}` |

---

## 二、环境变量

容器里不方便挂配置文件时用。全部可选。

| 变量 | 覆盖 |
|---|---|
| `OPENBBS_CONFIG` | `site.json` 的路径 |
| `OPENBBS_SITE_NAME` | `site.name` |
| `OPENBBS_SITE_BASE_URL` | `site.base_url` |
| `OPENBBS_DATA_DIR` | `paths.data` |
| `OPENBBS_DB` | `paths.db` |
| `OPENBBS_UPLOAD_DIR` | `paths.uploads` |
| `OPENBBS_APK_DIR` | `paths.apk` |
| `OPENBBS_SECRET_FILE` | `paths.secret` |
| `OPENBBS_MAIL_CONFIG` | `paths.mail_config` |
| `OPENBBS_LOG_DIR` | `paths.logs` |
| `OPENBBS_CORS_ORIGINS` | `http.cors_origins`，逗号分隔 |
| `OPENBBS_REGISTER_OPEN` | `auth.register_open`，`1` / `0` |
| `OPENBBS_REQUIRE_EMAIL` | `auth.require_email` |
| `OPENBBS_ADMIN_PASSWORD` | `admin.password` |
| `OPENBBS_HOST` / `OPENBBS_PORT` | `run.sh` 监听地址 |
| `OPENBBS_CERT_DIR` | `run.sh --tls` 的证书目录 |
| `OPENBBS_KEEP` | `backup.sh` 保留几份 |

---

## 三、客户端构建参数

```bash
flutter build apk --release \
  --dart-define=BRAND=OpenBBS \
  --dart-define=REPO=https://github.com/you/openbbs \
  --dart-define=SERVERS=https://bbs.example.com,https://backup.example.com
```

| 参数 | 默认 | 说明 |
|---|---|---|
| `BRAND` | OpenBBS | 界面上显示的站名 |
| `REPO` | 空 | 关于页的项目地址，空则不显示 |
| `SERVERS` | 空 | 预置服务器，逗号分隔。第一个是主通道，第二个是备用。**全空则首次启动进设置页让用户自己填** |

`SERVERS` 只给一个也能用，选路会自动退化成单通道。

---

## 四、还没开放成配置的

这些还在代码里，按需要再抽：

**值得抽（站长可能想改）**

- 用户名/handle 的字符规则（`HANDLE_RE`、`HANDLE_RESERVED`）
- 等级公式（现在固定 `√发帖数 + 1`）
- 上传文件类型白名单（`_sniff`）
- 默认头像、站点 logo
- 关于页文案、公告
- 无邮箱注册（需要先加接口，`require_email` 才有意义）

**不必抽**

- 邮箱格式正则
- 排序规则（置顶 → 时间）
- 权限判断逻辑

---

## 五、改完怎么生效

```bash
cd server
./run.sh --stop
./run.sh          # 或 ./run.sh --tls
```

客户端改了 `--dart-define` 必须重新打包，改不了已发出去的包。
以后服务端下发品牌信息（`/api/meta`）就是为了让这件事不用重新打包。
