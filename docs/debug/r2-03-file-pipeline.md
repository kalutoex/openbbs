# 第 3 段排查报告：上传与下载链路

时间：2026-11-08 02:00–02:45
对象：`openbbs` commit `882cfa8`
方式：通读上传/下载两端 + 线上 Range 行为实测
基线：98 用例全过

## 一句话结论

上传做得比下载细：分片、断点、前台服务、取消都到位。
下载这边有一个会**产出坏文件**的命名问题（P1），其余是「卡住了不吭声」类的体验问题。

---

## P0

无。

---

## P1

### P1-1 下载的临时文件按「文件名」命名，同名不同文件会拼出坏包

- 位置：`downloads_io.dart:174-181`
  ```dart
  final safe = name.replaceAll(...);
  final file = File('${dir.path}/$safe');
  var have = _haveLen(file.path);   // 只看长度，不核对是哪个 URL
  ```
- 现象：临时文件名只有 `name`，没有 URL 的任何信息。于是
  1. 帖子 A 的 `image.png` 下到 40% 断网 → 半截留在 `tmp/downloads/image.png`；
  2. 去帖子 B 点它的 `image.png`（另一张图）→ `have=40%` → 发 `Range: bytes=N-` →
     服务端老老实实从 N 开始给 → 得到「前半张 A、后半张 B」的坏图，**而且显示下载成功**。
- 更糟的一种：B 的文件比那半截还小 → 服务端回 **416**（已实测：`curl -r 999999-` → `416`），
  客户端报「下载失败（416）」，之后点几次都失败——那个临时文件一直在，`have` 一直超大。
- 证据（服务端行为）：
  ```
  HTTP/1.1 206 Partial Content      accept-ranges: bytes
  HTTP/1.1 416 Range Not Satisfiable（起点超出文件长度）
  ```
- 影响：坏图/坏附件看不出来是哪一步坏的；416 那条会变成「这个文件永远下不下来」。
  触发条件很普通——同名文件在两个帖子里都有，第一次还断过网。
- 建议修法（三步，都小）：
  1. 临时文件名带 URL 摘要：`${sha1(url).substring(0,12)}_$safe`；
  2. 收到 206 时校验 `Content-Range` 的起点等于 `have`，不等就当 200 重下；
  3. 收到 416 时删掉临时文件、从 0 重来一次。

---

## P2

### P2-1 发帖/私信的附件走整包上传，500MB 失败得从头再来

- 位置：`compose_page.dart:270-280`（上限 500MB）、`api.dart` 的 `uploadFile` → `postFile`（multipart，30 分钟超时，`retryOnTimeout: false`）
- 对照：云盘走的是 `uploadFileChunked`（4MB 一片、断点续传、取消即停）。
- 现象：给帖子挂个 300MB 的包，传到 95% 断一次 → 整包重来，没有 `.part` 可续。
  用户看到的是进度条归零。
- 建议修法：这两个入口也改用 `uploadFileChunked`（服务端 `/file/chunk*` 已经支持，云盘在用），
  顺手统一 500MB 上限的判定位置。

### P2-2 下载没有超时，半开连接会一直挂着

- 位置：`downloads_io.dart:192` `final res = await client.send(req);`（无 `.timeout`）
- 对照：上传那头有 10 分钟 / 30 分钟的超时；下载整条链一个都没有。
- 现象：Wi-Fi 切 4G 的一瞬间，TCP 半开，`send` 永远不返回。界面停在「下载中 12%」，
  没有取消按钮（`file_card.dart:164` 那个入口没传 `CancelToken`），只能杀 App。
- 建议修法：`client.send(req).timeout(30s)` + 读流时「30 秒没收到字节就判定超时」；
  `FileCard` 的下载加一个取消（`cloud_page` 已经有了，照抄）。

### P2-3 网页版下载整个文件进内存

- 位置：`downloads_web.dart:47-80`（`BytesBuilder` 收全部字节，再 `Blob`）
- 现象：网页版下云盘里 1GB 的文件，浏览器标签页直接 OOM。
  手机浏览器更明显，Safari 上干脆崩。
- 建议修法：云盘大文件在 web 上走 `fetch` + `ReadableStream` + `showSaveFilePicker`（Chrome 系）；
  不支持就退回现在的做法，但先按 `contentLength` 判断，超过 200MB 提示「请用 App 下载」。

### P2-4 下载收到 401 不会触发掉登录

- 位置：`downloads_io.dart:200-203`（`throw http.ClientException('下载失败（401）')`）
- 现象：令牌过期后点下载，提示「下载失败（401）」，但 `onUnauthorized` 不会触发，
  界面还是登录态；用户不知道要重新登录，只会反复点。
- 建议修法：401 且带过 token 时，直接抛 `ApiException(..., status: 401)`，
  让 `Api` 的 `onUnauthorized` 逻辑复用（或手动调一次回调）。

---

## P3

- `downloads_io.dart:110`（`StateError('保存失败')`）、`148`（`打不开这个文件：…`）中文硬编码，
  没走 `l10n`。英文界面上会突然冒出中文。
- `file_pick_io.dart:150` 分片超时 10 分钟：TCP 卡住时用户要盯着不动的进度条等十分钟才报错。
  建议加「30 秒没有新字节即超时」。
- `downloads_io.dart:125` `_unique()` 用 `existsSync` 循环，目录里文件多时（几百个）会卡主线程。
  桌面端才有这条路径，影响有限。
- `openRemoteFile` 先记 `localDownload` 再 `openSaved`；打开失败被静默吞掉（注释是有意的），
  但用户点了下载又没打开，会觉得没反应。可考虑失败时补一句提示。

---

## 待观察

- 云盘上传没有客户端预检额度（`cloud_page` 直接 `add`）。超额度时靠服务端 400/413 兜，
  文案直接来自服务端。没实测超额度那一刻的表现，列到第 4 段一起看。
- `upload_keepalive_io.dart` 用 `MethodChannel('openbbs/keepalive')` 挂前台服务。
  Android 14 起前台服务必须声明 `foregroundServiceType`，没声明会抛异常（被这里 `catch` 吞掉
  → 上传期间进程照样被冻）。发版前在真机上验一次，属第 5 段。

---

## 本轮没查的

- 云盘页的列表/搜索/回收站交互走第 4 段（本段只看了下载与上传入口）。
- 附件在私信气泡里的布局（`file_card.dart` 的 compact 宽度）走第 4 段。
- 原生侧：`MethodChannel('openbbs/downloads')` 的 Kotlin 实现（MediaStore 落盘、重名 (1) 规则）
  不在 dart 仓库这次的范围里，没读。
- 上传队列的跨账号问题已在第 2 段记为 P1-1，本段不重复。
