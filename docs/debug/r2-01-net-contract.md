# 第 1 段排查报告：网络层与接口契约

时间：2026-11-08 00:20–01:05
对象：`openbbs`（Flutter 客户端）commit `8b437c6`，版本 1.5.33+143
方式：通读 `api.dart` 及周边 + 线上接口实测 + 两个临时复现测试
基线：`flutter analyze --no-pub` 0 issue；`flutter test --no-pub` 96 用例全过

## 一句话结论

网络层整体是稳的：换路、幂等号、401 清登录这几条主路径都跑得通，也有测试兜着。
真正的问题集中在**冷启动救援这一段**：探到活路却不换过去，服务端答了话也当成连不上。
另外分片上传不吃换路、页面重试不带幂等号两处，是上一波修复留下的缺口。

---

## P0

无。

---

## P1

### P1-1 冷启动救援：探到活路，重发还打旧路

- 位置：`lib/api.dart:634-695`（`get` 的 rescue 分支），关键行 `673`：`final ok = await probe();`
- 现象：首轮请求两条入口都连不上 → 进救援 → `probe()` 探到某条入口通了（并写进 `lastGood`）
  → 紧接着重发，但 `_uri(path)` 用的还是 `Api.base`，而 `base` 从头到尾没被改成 `ok`。
  重发照样打到那条死路，最后仍报「连不上服务器」。
  单入口站没事（base 就是那条），**v6+v4 双入口站才会踩**——阿尔的手机就是这种配置。
- 证据：`test/_r2_probe_bug_test.dart`（临时，未提交）
  ```
  00:00 +1: All tests passed.
  ```
  断言内容：`hits == 2`（首轮 1 次 + probe 1 次，重发 0 次）、`Api.base` 仍是死路。
  也就是说 probe 白探了。
- 影响：切网 / 锁屏回来后第一次拉列表，用户看一眼「连不上服务器」，再点一次才好。
  也就是说上一波专门为这个场景加的救援，在多入口站上是空转。
- 建议修法：`probe()` 返回非空时先 `Api.base = ok; lastGood = ok; onChannelChanged?.call(ok);` 再重发。
  顺便给 `probeAt` 加一句注释说明「只记 lastGood，不动 base」，免得下次又漏。

### P1-2 救援里的重发把 401 / 403 / 500 吞成「连不上服务器」

- 位置：`lib/api.dart:671-690`，整个救援块外面套着 `catch (_) {}`
- 现象：救援重发拿到的响应如果让 `_decode` 抛 `ApiException`（401「请先登录」、403、500 都算），
  这个异常被 `catch (_)` 吃掉，然后统一抛 `connectFailed`。
  用户看到「连不上服务器」，实际是令牌废了或者服务器 500。
  401 那条还会顺带触发 `onUnauthorized` 清登录态——用户眼里就是「莫名其妙掉登录，还说连不上」。
- 证据：`test/_r2_probe_bug2_test.dart`（临时，未提交）
  ```
  00:00 +1: All tests passed.
  ```
  该用例让第 3 次请求（救援重发）返回 401 + `{"detail":"请先登录"}`，
  客户端抛出的 `code` 实际是 `connectFailed`。
- 影响：掉登录时错误原因被错误掩盖；排查线上问题时会被带偏。
- 建议修法：`catch (e)` 里判断 `if (e is ApiException) rethrow;`，只把真正的连接层异常转成 `connectFailed`。

---

## P2

### P2-1 断网时首屏最长要等近一分钟才出错误

- 位置：`api.dart:634`（15s 超时）、`api.dart:207-243`（`_withFailover` 逐条跑，每条 15s）、
  `api.dart:668-690`（救援：0.4s + probe 13s + 重发 15s）
- 算式：两条入口 15s + 15s = 30s；救援再来 0.4 + (3+10) + 15 ≈ 28.4s，**合计约 58s**。
  （v6 入口 3s、v4 入口 10s，见 `api.dart:114-116`；黑洞地址实测 3s 超时，`curl` exit 28）
- 影响：界面不是白屏（`runApp` 在前，`_boot` 是 unawaited），但列表会长时间停在加载态，
  用户以为卡死。有绕路：杀掉重开、或者点别的页。
- 建议修法：救援重发那次用短超时（比如 6s），或者把救援整体包一个总预算（10s）超了就报错。

### P2-2 连接失败的文案把底层异常英文原文拼给用户看

- 位置：`api.dart:692`（`connectFailed('$e')`）+ `lib/l10n/error_text.dart:25`（`l.connectFailed(error.detail)`
  + `app_zh.arb:96`「连不上服务器：{v1}」）
- 实际长相：`连不上服务器：ClientException with SocketException: Connection failed
  (OS Error: Network is unreachable, errno = 101), address = ipv6bbs..., port = 26016, uri = https://...`
- 影响：一行里半屏英文，阿尔明确不喜欢小字说明和废话。信息对用户没用，对排查也没用（日志里有）。
- 建议修法：界面用 `connectFailedPlain`（已有这个 key），`detail` 只进 debugPrint。

### P2-3 分片上传不吃换路，一条入口死就整单失败

- 位置：`api.dart:344`、`api.dart:437`（`retryOnTimeout: false`），`upload_manager.dart:262-278`（失败不自动重试）
- 现状：每条分片都走 `retryOnTimeout: false`，超时直接抛；`UploadManager` 记 `failed`，等用户点重试。
  用户点重试会从断点继续，那一轮 `_withFailover` 会换到另一条入口——所以有绕路，归 P2。
- 但注释给的理由不成立：`postChunkRange` 是从文件读固定区间重发，**重发同一片是安全的**，
  「分片自己对 offset，重发没意义」这句与实现不符。
- 影响：v6 断掉时（阿尔遇过一次 26016 空监听），大文件正在传会直接失败，得回来点一次重试。
- 建议修法：分片也允许 `retryOnTimeout: true`，反正服务端按 offset 接；
  或者最小改动：失败后自动重试一次（换入口）。

### P2-4 页面层「再发一次」会换新的幂等号，可能发出两条

- 位置：`api.dart:697`（每次 `post` 都 `newRequestId()`）、`compose_page.dart:553`、`thread_page.dart:534`
- 现象：`_withFailover` 内部的换路/重发确实共用同一个号（`api_idempotency_test` 覆盖了）。
  但请求已经到达服务端、响应丢在路上的情况下，页面弹错 → 用户再点提交 → **新号** → 服务端当新请求执行。
  发帖、回帖都会变成两条。
- 触发条件苛刻（要请求到站、响应丢失），但后果是用户可见的重复内容，且上一波专门修过同类问题。
- 建议修法：`Api.post` 加可选参数 `rid`；`compose_page` / `thread_page` 在一次提交的生命周期里持有这个号，
  成功后才丢。改动很小，测试好写。

### P2-5 断网提示条只在四个方法里更新

- 位置：`api.dart:57`、`61`（`_netOk`/`_netBad`），调用点只有 `get` / `post` / `delete` / `patch`
- 未覆盖：`postAt`、`getAt`（登录、注册、站点目录、测速）、`uploadImage`、`uploadFile*`、`dropChunks`
- 影响：站点管理页探测、登录页、上传时断网，顶部那条提示条不亮；上传失败只有卡片上的红字。
- 建议修法：`postAt` / `getAt` 成败时调一下，上传失败时 `_netBad()` 一次。

### P2-6 422 的具体字段错误被吞成「请求失败（422）」

- 位置：`api.dart:594-607`（只认 `detail` 是 String）
- 现状：FastAPI 校验错误返回 `{"detail":[{...}]}` 是数组，`d is String` 不成立 → 落 `requestFailed(422)`。
- 影响：客户端自己构造 body 出错时（比如某天服务端加了必填字段），用户和排查者都看不到是哪个字段。
- 建议修法：`detail` 是 List 时取第一条的 `msg`，拼进文案；不要原样吐 JSON。

---

## P3

- `api.dart:282` `if (last is ApiException) throw last;` 是死代码：`ApiException` 在上面就 rethrow 了，`last` 不可能是它。
- `api.dart` `img()`：`base` 为空时返回 `/img/...` 相对地址。安卓上 `Image.network` 会直接抛，web 上正常。
  冷启动 base 不会为空（`main.dart:29` 先铺默认值），但单测和异常路径下会碰到。
- `api.dart:94-107` `setEndpoints` 不保证 `base` 在新的集合里。目前三个调用点都手动兜了，
  属于「靠调用方记得」的设计坑，建议加一句 `if (!out.contains(base)) base = out.isEmpty ? '' : out.first;`。
- `disk_cache_io.dart:53` 写缓存不是原子写（直接 `writeAsString` 覆盖），并发写同一 key 可能互相截断。
  读侧有容错（`read` 里 `catch` 返回 null），代价是丢一次缓存，不列问题级。
- `token_store.dart:52-60` `clear()` 先删 prefs 再删 secure，secure 删除失败被 `catch` 吞掉。
  下次启动 `read()` 优先读 secure，会把废令牌读回来 → 闪一下「已登录」。概率低，列在这里备查。

---

## 待观察

- `probeAt` 以「HTTP 200」判定入口通。若入口被运营商门户页劫持（200 + HTML），会被判为通，
  随后请求全失败。没有实测样本，暂不下结论；验法：用 200 返回 HTML 的本地服务端跑一次 `probe()`。
- `_decode` 靠中文字面量 `请先登录` / `账号已被封禁` 认状态（`api.dart:83-88`）。
  服务端文案一改，客户端就不清登录、不切封禁页。服务端目前写死中文（`app/api.py:213`、`blacklist.py:24`），
  属于契约耦合，建议后端加机器可读字段（如 `code`），前端再换判据。这条写进下轮和后端一起说。

---

## 疑似后端

无。顺手验了三个只读行为，均符合预期：

- `POST /api/threads` 无令牌 → `401 {"detail":"请先登录"}`（String，客户端能认）
- `GET /api/notify/poll` 无令牌 → `401 {"detail":"请先登录"}`
- `GET /api/feed?per_page=abc` → 200（非法值被忽略，不报 422）

---

## 本轮没查的

- `sites.dart`（354 行）的合并/去重逻辑只扫了一遍，没做用例级验证——留给第 2 段「多站隔离」。
- `site_store.dart`（38 行）、`site_config.dart`（48 行）只看了签名。
- `probeReport` / `speedTest` 的界面表现（站点页那一屏）走第 4 段。
- 上传的三条路径只看了 `api.dart` 侧，`UploadManager` 状态机走第 3 段。
- 未在真机上跑弱网（`iptables DROP`）实测，本段证据全部来自代码 + 本地假服务端。

## 临时文件

`test/_r2_probe_bug_test.dart`、`test/_r2_probe_bug2_test.dart` —— 复现用，未提交。
建议修 P1-1 / P1-2 时把它们改成正式回归用例（合成 `test/api_rescue_test.dart`）。
