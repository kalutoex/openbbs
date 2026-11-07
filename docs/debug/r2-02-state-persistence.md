# 第 2 段排查报告：状态、持久化与生命周期

时间：2026-11-08 01:10–01:55
对象：`openbbs` commit `882cfa8`
方式：通读 `store.dart` + 各持久化模块，逐条核对 key 作用域与清理路径
基线：98 用例全过（含第 1 段新增两条）

## 一句话结论

「该记住的都记住了」，问题在**作用域**：读到的位置、草稿、消息游标、上传队列这四样，
key 里都没带账号或站点，换号换站时会串。其中上传队列那条会把文件传到另一个账号名下，
是本段唯一要优先修的。

---

## P0

无。

---

## P1

### P1-1 上传队列不认账号，切号后接着往新账号里传

- 位置：`upload_manager.dart:76`（`_key = 'cloud_upload_queue'`，全局一个）、`225`（`_run` 直接用当前 `Api.token`）、
  `153`（`add` 不记账号）、`354`（`_persist` 不写账号）
- 现象：A 账号在传 20 个文件，中途切到 B 账号（`switchAccount`）。队列还在，`_pump` 继续跑，
  `Api.uploadFileChunked` 用的是**当前 token**，分片直接落进 B 的云盘。
  已有的 `uploadId`（服务端 .part）也是按 id 接的，不会报错，就这么传完了。
- 影响：文件出现在别人的云盘里。触发条件窄（必须在上传中切号），后果重。
- 建议修法：`UploadJob` 加 `owner`（账号 uid），`add` 时写入、`_persist` 落盘；
  `_run` 开头比对当前 uid，不一致就把该 job 标 `failed`，文案「账号已切换，重新添加」。
  顺手在 `switchAccount` / `logout` 里调一次 `UploadManager.instance.onAccountChanged(uid)`。

---

## P2

### P2-1 消息游标不清，切号后新消息不弹通知

- 位置：`poller.dart:31-32`（`notify_cursor_dm` / `notify_cursor_nt`，不带账号）、`224`（`reset()` 定义了却从没被调用）
- 证据：`grep -rn 'Poller.instance.reset' lib` 无结果。
- 现象：切号后 `_dm/_nt` 还是上个账号的 id。新账号的消息 id 比它小 → `fresh` 永远是空，
  系统通知一条不弹（角标是服务端给的 `total`，所以数字对得上，更容易让人以为只是没弹）。
  反过来如果 id 更大，会把上个账号之后的新消息一次性弹出来。
- 建议修法：`reset()` 里带上账号，`switchAccount` / `logout` 里调用；`_kDm` 改成 `notify_cursor_dm_<uid>` 更彻底。

### P2-2 阅读位置不带站点，跨站跳错楼层

- 位置：`read_pos.dart:13`（`thread_read_pos_v1`，一个 JSON 装所有帖子）、`thread_page.dart:151/163`
- 现象：站点 A 的 56 号帖读到 87 层，切到站点 B 点开 56 号帖，直接落到 87 层。
  B 站这个帖子可能只有 12 层——落不到，或者落到一个完全无关的楼层。
- 建议修法：key 里带站点 id（`read_pos_v1_<siteKey>`），或 JSON 再套一层站点。

### P2-3 草稿不带账号，换个号能看到上一个人的草稿

- 位置：`compose_page.dart:33`（`_draftKey = 'site'`，写死一份）、`chat_page.dart:127`（`dm_draft_<peerId>`）
- 说明：「跟选哪座站无关」是有意的（一个草稿可以发到任意站），这条不反对。
  但**账号**也没带：A 写一半退出登录，B 登录后打开发帖页，标题正文图片全在。
  私信草稿同理，`peerId` 是每座站各自的编号，跟账号更没关系。
- 建议修法：slot 拼上 `u<uid>`；退出登录时按 uid 各留各的（用户下次登录还能找回自己的）。

### P2-4 队列恢复后不校验登录态，会一直失败占着队列

- 位置：`upload_manager.dart:116-150`（`init` 无条件 `_pump()`）
- 现象：上次没传完就退出了，冷启动时恢复了队列并自动开传；如果这会儿是未登录（或令牌过期），
  每个 job 都吃 401，全部 `failed`，界面上排一排红字。用户得手动清。
- 建议修法：`init` 里判断 `AppState.instance.loggedIn` 和 job 的 owner，不匹配就先挂着不传。

### P2-5 多账号的 token 在 prefs 里也有一份明文

- 位置：`accounts.dart:72-115`（`AccountStore` 双写：`p.setString(_key, raw)` 里含每个账号的 token）、
  `token_store.dart:42`（同一个 token 在 prefs 也写一份）
- 说明：注释写着「token 属于敏感数据，安卓走 Keystore」，实际 Keystore 和 prefs 各一份。
  Keystore 的意义就没了——`/data/data/.../shared_prefs` 里能直接读到。
- 影响：本机取证、备份还原、调试工具都能读到。不是远程风险，属于「本该更严」。
- 建议修法：prefs 那份只留 `uid/nickname/avatar/hue`，token 只进 secure storage；
  读不到 secure 就当没登录过（现在这套双写是为了「读不出来别把人踢下线」，取舍可以再定）。

### P2-6 退出登录只清了 token，别的一样没清

- 位置：`store.dart:959-967`
- 没清的：上传队列（P2-4）、阅读位置、草稿（P2-3）、poller 游标（P2-1）、`accounts` 列表（这个该留）、`banned`（清了）。
- 影响：换号之后还带着上一个人的痕迹。多数是串数据，个别是隐私。
- 建议修法：`logout` 里统一调一遍各模块的 `onAccountChanged` / `reset`。

### P2-7 冷启动串行探所有站，拖慢首屏

- 位置：`store.dart:429-451`（`probeSites` 逐站 `await`，`_boot` 里 `unawaited`）、`api.dart:114-116`（每条入口 3s / 10s）
- 算式：三座站 × 两条入口 = 最坏 3 站 × 13s = 39s 的后台网络占用。
  首屏 feed 和它抢连接，弱网下表现为「首页转圈，站点页倒是早就亮了」。
- 建议修法：`Future.wait` 并发探，或只探当前站 + 上次打开的站。

### P2-8 轮询失败全吞，没有任何日志

- 位置：`poller.dart:88`（`catch (_) { _fails++; }`），内含 `d as Map`、`(m['dm'] as Map)` 两处强转
- 现象：服务端字段一改（比如 `dm` 变成数组），这里每天静默失败 17000 次，角标永远不动，
  控制台一句话没有。排查时只能靠猜。
- 建议修法：`catch` 里 `debugPrint` 一次（限流，别每 5 秒刷屏）。

---

## P3

- `store.dart:451` 注释写「main() 里在 runApp **之前** await 它」，
  实际 `main.dart:35` 是先 `runApp` 再 `unawaited(_boot())`。注释过时，行为是启动会闪一帧默认色。
  代码没错（先画帧是对的），注释要改，免得下一个人照着注释改回去又白屏。
- `img_cache_io.dart:11` `_pool` 只增不减：切过的每个账号都留一个 `CacheManager`（含计时器）。
  账号不多无所谓，属于洁癖级。
- `poller.dart` `_p?.remove` 依赖 `start()` 先跑完；`reset()` 在 `start()` 之前被调用就什么也不做。
  现在没人调用它，接上时注意顺序。
- `local_downloads` 不带账号。文件确实在本机、跟账号无关，可以接受；
  但 `cloudId` 是某座站的云盘 id，换站后「已下载」标记可能对到同 id 的另一份文件。低频。
- `img_size_store` 上限 800 条、`DiskCache` 7 天过期，都会静默丢数据。属于设计，不是问题。

---

## 待观察

- `DiskCache` 的 7 天 TTL：用户可能期望「离线也能翻旧帖」，一周没开的站会直接没缓存。
  没实测他会不会撞上，先记着。
- `accounts` 列表保留废 token 的表现已确认有兜底（`switchAccount` 失败会摘掉账号并落到下一个），
  不列问题。但摘掉时没有提示，「点了账号没反应」的观感可以再打磨。

---

## 本轮没查的

- 上传状态机的细节（速度计算、前台服务、通知栏）留给第 3 段。
- 下载落点 / MediaStore / 索引一致性留给第 3 段。
- 各页面的刷新时机（切回来要不要重新拉）留给第 4 段。
- 设置页各开关的落盘只核了 key，没逐个点验。

## 结论与建议

本段**没有改代码**：P1-1 和 P2-1/2/3 都要动存储格式（key 加作用域），
连带要做老数据迁移（至少别把用户草稿弄丢）。这类改动一次做完、一次回归更稳，
建议和第 5 段的收尾一起做，改动清单：

1. `UploadJob.owner` + `switchAccount` / `logout` 钩子（P1-1）
2. `Poller` 游标按 uid 分，`reset()` 接上（P2-1）
3. `ReadPos` key 按站点分（P2-2）
4. 草稿 slot 按 uid 分（P2-3）
5. `logout` 统一清理入口（P2-6）
