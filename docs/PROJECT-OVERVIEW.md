# OpenBBS 项目全貌

写于 2026-11-05，按当时仓库和线上状态盘。

## 一、是什么

一个能自己部署的轻论坛，贴吧式：帖子 + 楼中楼回复，没有版块树，只有一个「全部」流。
站点名叫「时间线」，域名 `ipv6bbs.kalutoex.dpdns.org:26016`。

同一套代码出三个形态：

| 形态 | 入口 | 说明 |
|---|---|---|
| 网页版 | `https://ipv6bbs...:26016/` | Flutter 编译成静态站，canvas 渲染，hash 路由 |
| 安卓 App | 包名 `com.kalutoex.shijianxian`，桌面名 OpenBBS | 同一个 Flutter 工程，arm64 单架构 |
| 老页面 | `/classic`、`/new`、`/login`、`/t/{tid}` | Jinja 模板，保留兼容，功能不如新版 |

## 二、两个仓库，别搞混

| 仓库 | 路径 | 内容 | 状态 |
|---|---|---|---|
| **openbbs** | `/vol1/1000/data/code/ongoing/openbbs` | Flutter 客户端（权威）+ 一份服务端副本 | 开发主仓库，48 个 commit |
| **bbs** | `/vol1/1000/data/code/ongoing/bbs` | **线上服务端**（权威）+ 旧客户端副本 | 真正在跑的就是它 |

- 线上跑的是 `bbs/server`，数据库、上传、APK、网页都在它下面。
- `openbbs/server` 是早期带过来的一份副本，**已经落后**：比线上少 11 个路由（私信全套、云盘彻底删除、图片黑名单、注册挑战）。
- 服务端改动要落到 `bbs/server`，客户端改动落到 `openbbs/lib`，两边各自提交。
- `openbbs/release.sh`、`deploy_web.sh` 的输出目标是 `../bbs/server/`，靠这条把两边缝起来。

## 三、技术栈

**服务端**：Python 3.12 + FastAPI + uvicorn + SQLite（WAL）+ Jinja2 老模板。
11 个模块 5685 行：`api.py`(3042) `config.py` `db.py` `files.py` `main.py` `sites.py` `blacklist.py` `auth.py` `mailer.py` `thumbs.py`。
无 ORM，手写 SQL；无 Redis，所有状态都在 SQLite 里。

**客户端**：Flutter（Dart），98 个文件 30218 行。
34 个页面（`lib/pages/`）、10 个组件（`lib/widgets/`）、约 20 组 `*_io.dart` / `*_web.dart` 平台分叉。
关键依赖：http、image_picker、photo_manager、flutter_image_compress、file_picker、cached_network_image、permission_handler、flutter_secure_storage、open_filex、scrollable_positioned_list、package_info_plus。

## 四、服务端能力（78 个路由）

**账号**
- 注册：邮箱验证码两段式（`/register/code` → `/register`），带人机挑战 `/register/challenge`，防脚本刷号
- 登录发 token（HMAC 签名，token 里放的是权威 user id）
- 改邮箱、改密码、会话管理
- 等级 1–99，按发帖回帖数自动升；管理员手工可设
- 黑名单：封禁是**跨站同步**的（`blacklist.synced_at`），主站封了小站也拦

**帖子**
- 发帖（标题、正文、图、附件）、编辑、删除
- 楼中楼回复，`floor_no` 楼层号，`parent_id` 指父楼
- 置顶、加精、点赞（`likes` 表，target_kind 区分帖/回复）
- 收藏、浏览历史
- 搜索：SQLite FTS5 全文索引（`threads_fts` / `replies_fts`），标题正文作者一起搜，分页
- @提到人：`/mention/suggest` 补全 + 发帖时写通知

**文件与附件**
- `/upload` 图片（限 5MB，动图 10MB）
- `/file` 通用附件（单文件上限 500MB，类型不拦，所有人可发）
- 每人每天 10 个 / 3GB 的附件额度，一帖最多 5 个
- 内容寻址存储：按 digest 落盘 `data/uploads`（现 18MB），同一文件只存一份
- 图片缩略图：`thumbs.py` 生成，Web 端用缩略图、App 端取原图
- 敏感图黑名单：可手工屏蔽某张图（`/admin/image/block`）

**私信**
- 一对一，`dm_threads` + `dm_messages`，支持图片、附件、引用（`reply_id`）
- 陌生人只能先发一条，互关后放开（防刷屏）
- 会话级状态：置顶、免打扰、隐藏到某条（`dm_state`）
- 未读数、已读回执（内部）、15 秒轮询

**云盘**（`/cloud/*`）
- 每人默认 5G（`site.json: limits.cloud_quota_mb`），管理员可按人改
- 存在 `/vol3/1000/cloud/files`，按 digest 存，账本在 `user_files` 表
- 帖子附件会进账本（`source='post'` / `'cloud'`），删帖退回私人但不退空间
- 回收站：删除进回收站仍占额度，每小时清理一次，超 7 天真删；超配额先删最旧的；无引用才删物理文件
- 下载走 `/api/file`，鉴权：帖子附件公开，私人文件只本人

**社区与治理**
- 举报（帖/回复），后台处理队列 + 未处理计数
- 功能建议（用户提，管理员改状态）
- 站点目录：`/sites` 收录别的 BBS，`/.well-known/bbs.json` 自述，跨站互挂
- 关于页、好友（`friends` 表，独立于关注）

**运维接口**
- `/app/latest`：按身份分流 stable / beta，带 notes、force_below、检查间隔
- `/meta`、`/sites`：端点自述，客户端据此发现入口

**数据库**：30 张表（含 FTS 内部表）。核心是 `users`(14) `threads`(19) `replies`(8) `likes`(21) `notifications`(28) `history`(90) `user_files`(2) `dm_*`。库文件 25KB，WAL 模式。

## 五、客户端结构

**入口与导航**：`main.dart` → `home_page.dart`（底栏三 tab：首页 / 消息 / 我的），抽屉放云盘、收藏、历史、好友、设置、站点管理。

**页面分组**
- 内容：`feed_tab`（帖子流）、`thread_page`（帖子详情+回复）、`compose_page`（发帖）、`edit_thread_page`、`thread_list_page`、`search_page`
- 消息：`messages_page`（私信+站内消息合并列表）、`chat_page`（微信式聊天）、`notice_page`（站内消息）
- 云盘：`cloud_page`、`cloud_pick_page`（发帖/发私信时选云盘文件）、`cloud_settings_page`
- 账号：`me_tab`、`user_page`、`follow_page`、`friends_page`、`login_page`、`account_security_page`、`edit_profile_page`、`banned_page`
- 管理：`admin_users_page`、`admin_reports_page`、`feature_requests_admin_page`
- 站点：`sites_page`、`site_catalog_page`、`site_feed_page`（多站浏览，IPv6 优先，不通往下回落）
- 杂项：`settings_page`、`permissions_page`、`gallery_picker_page`（自写相册多选）、`theme_color_page`、`about_page`

**平台分叉**（`*_io.dart` / `*_web.dart` 成对）
- `file_browser`：安卓内置文件浏览器，能翻整个存储，需要「所有文件访问权限」；Web 端没有，退回 `<input type=file>`
- `downloads`：安卓落 `Download/OpenBBS`，Web 走浏览器下载
- `disk_cache` / `img_cache`：安卓用文件缓存，Web 用 IndexedDB/内存
- `draft_images`：草稿图存本地，防误删
- `open_path` / `file_open`：安卓用 open_filex 调系统打开，Web 用 url_launcher

**多入口发现**（`lib/sites.dart`、`site_config.dart`）
- 内置两个入口：IPv6 直连、IPv4 中转；另有局域网 `192.168.1.212:8080`
- 每隔一段时间探测，可用集合取并集，不通的标记出来，可手动重试
- 只认「像 v6」的写法做分流，避免把普通域名误判

**其他机制**
- 强更提示：回到前台查版本，`force_below` 之下强制更新
- 图片上传统一压缩（`img_compress`），超限就丢
- 轻提示统一 1.5 秒，新的顶掉旧的
- 国际化：`l10n` 中英双份，`tool/l10n_migrate.py` 迁移脚本
- 测试：14 个文件，76 个用例，`flutter test` 全过

## 六、部署

**进程**：`bbs/server/run.sh` 起 4 个 uvicorn（单进程不能双栈）：

| 端口 | 监听 | 用途 |
|---|---|---|
| 8080 | 0.0.0.0 / :: | 明文，局域网 + 旧包 |
| 26016 | 0.0.0.0 / :: | TLS，IPv6 直连主入口 |

**入口**
- `ipv6bbs.kalutoex.dpdns.org:26016` → AAAA 灰云直连本机（DDNS 管）
- `ipv4bbs.kalutoex.dpdns.org:24016` → 樱花 frp 节点转到本机 26016（无 IPv6 网络兜底）
- 证书 `/home/060923/certs/main/`，Let's Encrypt DNS-01，续期钩子自动装

**保活与备份**
- cron `*/2` 跑 `run.sh`（挂了自动拉起，活着就跳过）
- cron 每天 03:10 跑 `backup.sh`：快照数据库 + 打包 uploads，存 `data/backups/`，留 14 份，快照先 `--check` 再落地
- 快照用 `db_snapshot.py`（机器上没装 sqlite3 命令行）

**静态资源**：`/img` 上传、`/apk` 安装包、`/static` 旧页面资源、`/` 网页版。网页开了预压缩 + gzip，`main.dart.js` 1.09MB，canvaskit 精简到 9.8MB。

## 七、发版

```bash
# 客户端
flutter build apk --release --target-platform android-arm64 -PappId=com.kalutoex.shijianxian
./release.sh beta      # 只管理员
./release.sh stable    # 所有人
```
- `release.sh` 会先校验包名，不对直接拒（安卓只认包名，装错就是第二个应用）
- 两个通道各有 `notes.txt`，按 `x.y.z+build` 行切段，接口只返回最后一版说明
- 网页：`./deploy_web.sh`，构建 + 部署 + 清 canvaskit + 换自毁 SW + 压缩 + 自检，一条命令

当前：客户端 1.4.2+108（arm64 21.8MB），stable/beta 都已入库。

## 八、数据现状（2026-11-05）

- 14 个账号，uid 连续 1–13，测试号 mtest 在 30001（预留段 30001–30050，下个正常号 14）
- 19 帖、8 回复、21 个赞、28 条通知、90 条浏览历史
- 云盘 2 个文件 21.8MB，上传目录 18MB
- APK 仓库 1.1GB（历史包全留着）

## 九、版本线

build 号一路往上（能覆盖安装），版本名从 1.5.0 收回 1.2.0 重新起算。
11-03 到 11-05 三天里推了 48 个 commit、十几个内测包，主要三波：
1. 云盘（账本、回收站、额度、后台）
2. 私聊（微信式界面、引用、附件、站内浏览器）
3. 多端入口与性能（首屏 11MB→4MB）

## 十、欠账

`待修清单.md` 记着：
- 搜索历史只能「清空」和长按删，没有左滑
- 私信靠 15 秒轮询，后台不再刷，没有推送
- 搜人走 `LIKE`，账号多了会慢
- 私信没有群聊、撤回、对方可见的已读

另外两件结构性的：
- `openbbs/server` 那份副本落后线上 11 个路由，要么同步要么删掉，现在容易改错地方
- `bbs/` 里还留着旧客户端副本，同上
