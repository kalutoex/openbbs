# openbbs · 五段实施计划

> 目标形态：一个主站 + 若干独立小站。注册登录只在主站，小站能离线验签、被封全网生效。

---

## 前置约束

**C3（token 不过期）+ 封号口径，两者必须有黑名单同步来兜底。**

token 永不过期，就没法靠过期让封号生效，只能在接口层拦。所以第 2 段把
"主站维护全局黑名单、小站定时拉"写成强制项，不是可选项。

---

## 第 1 段 · 数据模型与命名

**目标**：把"板块"从数据层和文案层彻底拿掉，改成一站一层。

**已定**：A1 独立实例、F1 主站分配 id、N 主站叫"站"小站叫"XX站"、小站不能开小小站。

**做**

- 后端删掉板块层（`forums` 表/字段/接口），帖子直属站点
- 客户端删板块列表页，首页 = 站点列表 + 帖子流
- 全量文案：`XX吧` → `XX站`，`板块` → `站`
- 站点表加 `site_id`，由主站登记下发

**验收**：库里搜不到板块表；代码里没有 forum 这个概念；文案零残留；`flutter analyze` 零 error。

**不做**：不碰鉴权、不碰网络层、不碰部署。

---

## 第 2 段 · 身份与鉴权

**目标**：注册登录只在主站，小站离线验签，封号全网生效。

**已定**：B1 公钥离线验签、C3 token 不过期、M1 小站不放注册、E1 只存 uid、D 封号后读写全禁并明确告知。

**做**

- 主站签发 JWT，公钥随 `/meta` 下发；小站只验签，不联网
- 主站维护全局黑名单，`/blacklist?since=` 返回 `{uid, ts}` + 主站签名
- 小站每 60 秒拉一次，落地本地表
- 命中黑名单：所有接口（含读接口）返回 403，固定文案"账号已被封禁"
- 用户资料只存 uid，展示时按主站地址取

**验收**：主站封号后 60 秒内，该账号在所有小站读写全部 403；小站断外网仍能验已签发 token。

**不做**：不做 refresh、不做小站本地账号。

---

## 第 3 段 · 协议与站点清单

**目标**：让小站能自描述，客户端能自动识别。

**已定**：I1 `/meta` 报版本+能力位、H1 包内种子 + 手动导入、F1 主站登记。

**做**

- `/meta` 返回 `{api, site_id, name, capabilities[]}`
- `/.well-known/bbs.json` 按 `docs/bbs.json.example`，单站自述 `sites` 留一条
- 主站提供登记接口与目录，分配 `site_id`，查重
- 客户端按 `api` 版本开关功能，不支持就标"需更新客户端"

**验收**：新站部署后填域名即可被识别；清单三条校验规则（id 去重、缺地址丢弃、版本过高禁入）都生效。

**不做**：不做站点自动发现、不做搜索聚合。

---

## 第 4 段 · 客户端

**目标**：一个入口管多个站，自动选路，状态透明。

**已定**：H1、J2 各站自定义端口、E1、M1。

**做**

- 站点管理页：添加、删除、扫 JSON 导入（一个文件多个站）
- 每站存 `endpoints` 列表，启动时 v6 优先、失败按顺序回落
- 同 `site_id` 去重；连不上的站标灰，不弹窗骂人
- 被封 403 时全应用只显示封禁页
- 登录统一跳主站，token 全局共用

**验收**：无网启动不崩；多个站切换不需要重登；封禁账号点任何页面都出封禁提示。

**不做**：不做刷新、不做离线缓存帖子。

---

## 第 5 段 · 部署包与运维

**目标**：小站长填完数据就能起站。

**已定**：K3 Docker + tar 双形态、L3 不自动升级、O1 每日快照、J2 端口自定。

**做**

- Dockerfile + compose，卷挂 `data/`
- `install.sh`：检依赖、生成 secret、建库、打印管理员码
- `site.json` 收全部参数：站名、`site_id`、端口、证书、主站地址、公钥
- 每日 SQLite 快照，保留可配份数，一键恢复命令
- 只打印"有新版本"，不自动升

**验收**：空机器 10 分钟内起站；改端口只动 `site.json`；备份能直接恢复出可跑实例。

**不做**：不做自动升级、不做主站代管数据。

---

## 进度

| 段 | 状态 | 备注 |
|---|---|---|
| 1 数据模型与命名 | 完成 | 提交 `1d9f1c6` 去掉板块这一层 |
| 2 身份与鉴权 | 完成（资料拉取待补） | Ed25519 JWT、`/meta` 发公钥、黑名单签名增量；实测封禁 54 秒、解封 48 秒生效；断网仍可验签 |
| 3 协议与站点清单 | 完成 | `api` 升到 2；`/meta` 补全自述；`/.well-known/bbs.json`；主站目录 + 登记 + 查重；小站自动登记；三条校验在前后端各一份 |
| 4 客户端 | 完成 | 站点表 `sites_v1`；每站多入口、v6 优先按序回落；站点管理页（加/删/切/设登录站/粘贴清单/拉主站目录）；403 封禁切整页；`analyze` 0 error、51 项测试全绿 |
| 5 部署包与运维 | 未开始 | |

### 第 2 段落地细节

- **token**：EdDSA(Ed25519) JWT，payload 只有 `uid` + `iat` + 可选 `iss`，**没有 exp**（C3）。
  老格式 `uid:ts:sig` 仍可解码，平滑过渡；新签发一律 JWT。
- **密钥**：`data/jwt_key`（32 字节裸私钥，0600，首次启动生成，永不复写）。
  公钥由私钥派生，走 `/meta` 和 `/api/meta` 的 `public_key` 字段下发。
- **小站验签**：只拿公钥，纯本地算，不需要私网/联网。主站公钥验不过时再拿本机公钥试一次
  （小站自己的管理员登录走这条）。
- **身份映射**：token 里的 `uid` 是权威 id。小站按 `users.master_uid` 找影子行，
  找不到就建一条（`u<uid>`），**绝不退回本地 id** —— 否则主站 uid=2 会认成本站 id=2 的另一个人。
- **黑名单**：`blacklist(uid, ts, reason, banned, synced_at)`。
  `banned=0` 是解封墓碑，不能删行，否则小站永远收不到「解封」这条增量。
  条目列表规范化 JSON 后用主站私钥签名，小站验不过就一条都不收。
- **拦截点**：`optional_user` / `require_user`（读接口也过这两条），403 + 固定文案「账号已被封禁」。
- **配置**：`site.site_id`、`site.master_url`（空=主站）、`auth.public_key`、
  `auth.blacklist_pull_seconds`（默认 60）。
- **自检脚本**：`server/tool/`（`check_stage2.py` 纯离线、`check_e2e.py` 单站端到端、
  `check_slave.py` 主从同步、`check_unban.py` 解封传播、`check_offline.py` 断网验签）。

### 第 3 段落地细节

- **`api` 版本**：`sites.API_VERSION = 2`。1 = 只有帖子和用户，2 = 站点自述 / 清单 / 登记。
  `/meta` 的 `capabilities` 现在有 `jwt-eddsa`、`blacklist`、`meta`、`manifest`、`sites`、`register`。
- **自述形状**：`/meta` 和 `/.well-known/bbs.json` 的 `sites[i]` 是同一套字段：
  `id / name / description / url / endpoints / api / lang / icon / tags / open / contact / updated`。
  `/meta` 额外带 `site_id`、`base_url`（老名字，兼容）、`capabilities`、`public_key`、`blacklist`。
- **配置**：`site.lang / icon / tags / contact / endpoints / open`，`sites.allow_private`、
  `sites.register_per_hour_ip`。`endpoints` 空就只报 `base_url`。
- **登记**：`POST /api/sites/register`，只 `url` 必填。主站回访对方 `/meta`（先 `/api/meta` 再 `/meta`），
  按站名 slug 分配 id，中文名转不出 slug 就用 `site-<hash4>`；幂等、查重、内网默认拒绝。
- **小站自动登记**：配了 `master_url` + `base_url` 且 `site_id` 为空，后台线程去登记，
  拿到的 id 存 `sync_state.assigned_site_id`，`/meta` 立刻报出来。失败退避 5s→10s→…→5min。
- **目录**：`GET /api/sites`，格式同 `bbs.json`，客户端可直接导入；`DELETE /api/sites/{id}` 管理员摘站。
- **校验**：`server/app/sites.py: validate()` 与 `lib/site_meta.dart: parseManifest()` 同一套三条规则，
  `server/tool/check_stage3.py`（离线）和 `test/site_meta_test.dart`（客户端）各跑一遍。
- **客户端**：启动读一次自述，`api` 高于 `SiteMeta.supportedApi`（当前 2）就在首页顶部顶一条
  「请更新客户端」，只提示不拦用。`Api.loadMeta()` 先 `.well-known` 后 `/api/meta`，两次都失败静默。

### 第 4 段落地细节

- **站点表**：`lib/sites.dart` 的 `SiteEntry`（id / name / urls / api / icon / lang / master），
  运行时另有 `reachable`、`lastOk`，不落盘。存 SharedPreferences `sites_v1`（`lib/site_store.dart`），
  解析失败当空表，不抛。
- **升级不丢地址**：老版本只存 `server_base`。首次启动读到空表时，把它 + 出厂 `SiteConfig.servers`
  +（网页版）当前 origin 合成一座站写回，用户填过的地址不会丢。
- **选路**：`Api.endpoints` 是一行站的入口列表，`Api.probe()` 逐条真发 `/api/feed`，
  v6 入口 3 秒、其余 10 秒，串行，全通时稳定落在前面那条；`Api._withFailover` 在请求失败时按同一顺序换入口，
  服务器回了 `ApiException` 就不换（那不是路的问题）。切网络回前台会重探一次（5 秒节流）。
- **v6 判定**：只认三种写法——IPv6 字面量（含 `:`）、`ipv6` 开头域名、带 `-v6.` 的域名。别的域名不猜。
- **合并去重**：`mergeSites()` 先按 `id` 认，其次按地址重叠认，都对不上才追加；登录站强制唯一，
  一座都没有时第一座顶上。
- **站点管理页**（`lib/pages/sites_page.dart`，原 `server_page.dart` 已删）：一行一座站，
  左侧圆点标连通（灰=连不上、主色=通、空心=没探过），连不上的行变灰且点不动，
  标「登录站」「当前」。操作：加站、切换、设登录站、删除（确认）、粘贴清单、
  从主站拉 `GET /api/sites` 一键导入。导入结果按 `no_url / duplicate_id / api_too_new / bad_format`
  分类报「跳过几条、为什么」。
- **登录站**：注册、登录、找回密码走 `Api.postAt(loginUrls, …)`，只发登录站，站内按入口顺序回落；
  token 全局共用，换站只重新拉一次 `/me`，不用重登。
- **封禁页**：`_decode` 见 403 且 detail 含「账号已被封禁」就置 `AppState.banned`，
  `main.dart` 的 `_Root` 把整棵树换成 `banned_page.dart`，只留「退出登录」（退出清标记）。
- **空表引导**：`_Root` 在 `ready && sites.isEmpty` 时出 `setup_page.dart`，
  手填地址连不上也入表（标灰）并在原地报错，不用再去设置里找。

### 第 2 段未做

- `E1` 的「展示时按主站地址取资料」只做了影子行占位（`u<uid>`），
  昵称/头像仍是小站自己的，没走主站资料接口。等第 3 段 `/meta` 稳定后补。
