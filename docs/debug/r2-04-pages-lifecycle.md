# 第 4 段排查报告：页面交互与生命周期

时间：2026-11-08 02:50–03:40
对象：`openbbs` commit `9de338a`
方式：按问题类型扫（加载三态 / 分页 / 键盘 / 定时器 / 生命周期），重点页通读
范围：`lib/pages/` 37 个页面，重点 `chat_page`(2264) `thread_page`(2117) `feed_tab` `messages_page`

## 一句话结论

大部分页面的三态做得比预期好：`thread_page` 和 `feed_tab` 出错只挂一条细横条，列表不动。
但**私聊页反过来**——一次网络抖动就把整屏消息换成一个「连接不上」的空页面。这是本段最该修的一条。

---

## P1

### P1-1 私聊页轮询失败会把整屏消息清掉

- 位置：`chat_page.dart:141`（15 秒轮询）、`chat_page.dart:284`（失败写 `_err`）、`chat_page.dart:995`（`if (_err != null) return EmptyView(...)`）
- 触发：打开某个会话，进电梯 / 地铁过隧道 / 切一次 Wi-Fi，15 秒内必然撞上一次失败。
- 现象：已经读到的几十条消息**整屏消失**，换成云朵图标 + 「网络好像不通」+ 重试按钮。
  重试走的是 `_load(initial: true)`，`_unreadFromId` 那根「上次离开之后」的分隔线会重新算，位置也贴底。
- 为什么是 P1：这是最常用的页面之一，触发条件是最常见的网络抖动，后果是「我以为聊天记录没了」。
  对比 `thread_page.dart:1135` 的处理——出错只在顶部挂一条 errorContainer 细条，列表原样留着，这才是对的。
- 建议修法：`_err` 只在 `_msgs.isEmpty` 时整页报错；有数据时在列表顶部插一条细条，
  并让轮询继续（下个 15 秒成功就自动消掉）。

---

## P2

### P2-1 消息页是同一套写法

- 位置：`messages_page.dart:362`
- 别的都和 P1-1 一样，只是 `_load` 由下拉刷新和进入页面触发，频率低一些。一起改。

### P2-2 私聊页每 15 秒整表替换，且在后台照跑

- 位置：`chat_page.dart:141-144`、`chat_page.dart` 的 `_load()`：`_msgs..clear()..addAll(list)`
- 现象：
  - 每 15 秒把整个列表清空再灌进去，`ListView` 全部 item 重建。滚动位置靠 `_isBottom()` 兜着，
    但正在长按选字、正在看某张图时会被打断；
  - `_poll` 是 `Timer.periodic`，**没有跟随前后台暂停**。人能看到的会话页在后台还在每 15 秒发一次
    请求，而全局 `Poller`（`poller.dart:59`）在后台已经降到 60 秒了。等于后台反而更勤。
- 建议修法：
  1. 拿到 list 后只 append `id > prevLast` 的新消息，不做整表替换；
  2. `didChangeAppLifecycleState` 里 `_poll` 暂停 / 恢复（这个类已经 `with WidgetsBindingObserver` 并实现了 `didChangeMetrics`，加两行就行）。

### P2-3 `_bubbleKeys` 只增不减

- 位置：`chat_page.dart:100`、`1301`（`putIfAbsent`），`dispose` 与 `_load` 都不清理
- 现象：一个几千条消息的老会话，这张表就有几千个 `GlobalKey`，永不释放。
  单个占不了多少，但会话页开开关关、账号长期使用会一直涨。
- 建议修法：`_load` 里按当前 `_msgs` 的 id 集合把多余的 key 删掉。

### P2-4 楼层阅读位置只在滚动停下时保存，退出不补存

- 位置：`thread_page.dart:134-137`（700ms 防抖调 `_savePos`）、`dispose()` 只 `_posTimer?.cancel()`
- 现象：滚到第 80 楼，700ms 内按返回 / 切页面 → 这次位置不保存，下次进来还是上一次的位置。
  滚得快的用户（甩一下再退出）复现率不低。
- 建议修法：`dispose()` 里（以及 `PopScope` 里）无条件 `_savePos()` 一次。
  注意第 2 段的 P2-3（`thread_read_pos_v1` 不带站点）也在同一处，第 5 段一起改。

---

## P3

- `chat_page.dart:2145` 图片查看器用裸 `Image.network`，没有 `loadingBuilder`/`errorBuilder`。
  加载中一片黑，加载失败还是黑，用户分不清「在加载」和「坏了」。全项目就这一处和
  `user_page.dart:300` 没用统一的图片组件。
- `login_page.dart:50-61` 验证码倒计时是本地 `Timer.periodic` 一直减。进程被系统冻结再回来，
  倒计时数字和实际可再发的时间对不上（可能显示 30 秒但其实能点）。建议记一个截止时间戳来算。
- `search_page.dart:132` 每次搜帖子前都先 `GET /u/<词>` 试一下是不是某个人，多一个完整往返。
  搜常见词（「flutter」「图片」）时这段延迟白担。可以只在该词像用户名时（无空格、长度合理）才试。
- `feed_tab` 切 tab 时 `_err` 与列表状态在同一份 State 里（`feed_tab.dart:34`），
  一个 tab 失败会串到另一个 tab 的顶部横条上。影响很小，记录一下。

---

## 做得对的地方（不用动）

- `thread_page` / `feed_tab` 的错误展示是「顶部细条 + 列表保留」，是本项目里正确的范式。
- `chat_page.dart:172-182` `didChangeMetrics` 在键盘弹出后贴底，且判断 `_atBottom` 不打断翻旧消息的人。
- `chat_page.dart:1017` 那段注释点明了「只看 dragDetails 才收键盘」，因为这个坑踩过（跳底会误收键盘）——
  现在这样是对的，别改成 `ScrollStartNotification` 一律收。
- `search_page.dart:153` 用 `_seq` 挡「旧词的结果回来塞进新词列表」，这个竞态处理了。
- 所有页面级 `Timer` 在 `dispose` 里都有 `cancel`（逐个核过：chat / compose / thread / cloud / login）。

---

## 本轮没查的

- 云盘页 1214 行只看了下载与上传入口，列表/搜索/回收站/多选交互没细读。
- `sites_page` / `site_catalog_page` / `ui_config_page` 这类配置页只看有没有基本防护，交互细节没查。
- 手势层：双击标题回顶、图片 Hero 转场、下拉刷新手感，属于主观体验，不在这轮「找错」范围。
- 深链接 / 通知点进来落到哪个页面：需要真机点通知才能验，代码里只见 `notify_io.dart` 转发，没验端到端。
