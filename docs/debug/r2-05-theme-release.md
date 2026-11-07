# 第 5 段报告：主题、多端适配与发版收口

> 状态：**未收口**。这轮做完了「代码能查的部分」，需要眼睛和真机的部分没做，
> 清单在最后。报告按第 1 段格式，只写有证据的。

## 结论

- 静态项（多端分叉、版本号同源、图标别名、发版脚本）逐条过了，只发现一处真问题，
  已修：web 端首页每次打开都抛一次 `UnsupportedError`。
- 版本号三处同源，`android/app/build.gradle.kts:37-38` 读 `flutter.versionCode/Name`，
  设置页与关于页走 `package_info_plus` 运行时读同一份，不存在手写第二份。
- 8 套图标在 `app_icon.dart:18-27`、清单 `AndroidManifest.xml:57-148` 一一对上；
  别名找不到时原生回 `iconFailed`，`theme_color_page.dart:199` 接住并给提示，不白屏。

## P2

### P2-2 更新包没有下载地址时，会拿到一个网页存成 .apk

- 位置：`lib/update.dart:113`（`Uri.parse('${Api.base}${r.url}')`）
- 现象：`/api/app/latest` 的 `url` 为空（服务端还没放包、字段写错），拼出来就是论坛首页。
  200、有内容、`contentLength` 也正常，下载进度条一路走到 100%，存成 `openbbs-x.y.z.apk`，
  交给系统安装器才报「解析包出错」。用户看到的错误在最后一步，根因在最前面。
- 已修：`url` 为空直接抛 `downloadFailed`（放在建临时目录之前）；另外拦 `text/html`
  响应，地址被重定向到网页的情况一起挡住。
- 回归：`test/update_test.dart` 加一条「没有下载地址时不拼首页，直接报错」。

### P2-1 web 端首页每次打开抛 `UnsupportedError`

- 位置：`lib/permissions.dart:37`（`Platform.isAndroid`）、`lib/pages/home_page.dart:71`（无条件调用）
- 现象：`dart:io` 在网页端编译得过，但 `Platform` 一碰就抛 `Unsupported operation`。
  首页 `addPostFrameCallback` 里直接调 `AppPerms.firstRun()`，web 上每次回首页红一条日志，
  `perm_asked_v1` 永远写不进去，也就永远每次都想问。
- 已修：`firstRun()` 开头 `if (kIsWeb) return;`。这条本可以更早发现——第 2 段的
  `dart:io` 检查只查了 `*_io.dart` 里的引用。

### P2-3 拖窗口跨 840，整个 tab 页重建

- 位置：`lib/pages/home_page.dart:202`（`body: wide ? Row(rail, content) : content`）
- 现象：窄屏时 `content` 是 `Scaffold.body` 的直接孩子，宽屏时变成
  `Row > Expanded > content`。父链一变，Element 不复用，`FeedTab` 等页面
  State 全部重来：滚动位置归零、列表重新拉一遍、没发出去的草稿没了。
  桌面和网页拖窗口、平板分屏调整都会踩到。
- 已修：`body` 结构固定成 `Row`，三个孩子位置不变，窄屏时前两个是
  `SizedBox.shrink()`，`Expanded` 始终在第三位。
- 回归：`test/smoke_test.dart` 加一条「窗口从窄拖到宽，时间线页的 State 不重建」，
  比对 resize 前后 `FeedTab` 的 Element 是否同一个。

## 主题（静态部分，已核）

- 优先级链 `main.dart:184-198`：`DynamicColorBuilder` 在不支持的平台给 `null`，
  `useDyn` 自动为假，直接落回自选 hue。Android 11 以下、桌面、web 都走这条路，不需要额外分支。
- 关掉壁纸取色即时生效：`useDynamicColor` 在 `_themeKeys`（`main.dart:169-175`）里，
  同一个 Listenable 还挂着 `themeMode`、`accentHue`、`localeCode`，切了立刻重算，
  `themeAnimationDuration: Duration.zero` 不补间。
- hue 的默认值是 `defaultHue`（非 0，见 `store.dart:212`），存盘存 double、
  读回来过 `normalizeHue`。0 是合法色相（红），不会被当成「没设过」，不存在
  「所有人一个色」的坑。新用户随机 hue 由服务端下发，客户端 `_applyHue` 接收。
- 卡片染色只有一个入口 `hueCardTint`（`user_hue.dart:118`），用点三处：
  `thread_tile.dart:116`、`thread_page.dart:1237`、`thread_page.dart:1789`。
  唯一的例外是 `messages_page.dart:404` 直接调 `hueCardBg`——**注释写明是故意的**：
  会话卡跟着对方走色，不进彩蛋里的开关，用来区分是谁的对话。不算漏，记在这里备查。
- 全库硬编码颜色只有 3 处（`cloud_page.dart:879` 的容量条绿、`chat_page.dart:726-727`
  的输入框深浅色），都不受卡片开关影响，也不是主题色，属正常。

## P3

- `lib/update.dart:91`（`File(...)`）：web 上不可用，但唯一调用方
  `update_prompt.dart:50` 有 `if (kIsWeb) return;`，当前不可达。属于「靠调用方守规矩」，
  谁哪天把 web 的更新入口做回来就会踩。记着，不动。
- `lib/upload_manager.dart:152`（`File(path).existsSync()`）：依赖 `PickedFile.path` 在
  web 上为空串提前 `continue`。同上，能跑，但脆弱。
- `deploy_web.sh` 原来直接 `cp` 覆盖，线上没有上一版可退。已补：`main.dart.js.prev`
  留一份，回滚三步写进脚本注释。

## 发版检查单

| 项 | 结果 |
|---|---|
| `flutter analyze --no-pub` | 0 issue |
| `flutter test --no-pub` | 106 全过 |
| web 构建 | `deploy_web.sh` 通过，首页 200，`main.dart.js` 1.2MB，feed 200 |
| canvaskit 冗余清理 | 脚本里有（skwasm/wimp/symbols） |
| 自毁 SW | 脚本里写死，没丢 |
| 旧 `main.dart.js` 备份 | 本轮补上 |
| APK 出包 | 能出，23.9MB（1.5.26 是 23.7MB，同量级，没带调试符号） |
| 版本号 | 没动，仍 1.5.33+143 |
| 四入口线上回归 | **没做**，等发版前 |
| 覆盖安装 / 本地状态升级 | **没做** |

构建时 `share_plus` 的镜像缓存又被清了（`Package not available ... pub.flutter-io.cn`），
按 `docs/DEPLOY.md` 第八节重塞一遍就好；这次从 `hosted/pub.dev` 拷回
`hosted/pub.flutter-io.cn` 后 `pub get --offline` 过。


## 回滚步骤

APK：`bbs/server/data/apk-archive/` 取上一版，直接覆盖安装（同包名同签名）。

Web：

```bash
cd /vol1/1000/data/code/ongoing/bbs/server/web
cp main.dart.js.prev main.dart.js
gzip -9 -f main.dart.js
```

## 本轮没查的

- 主题：壁纸取色在 Android 11 及以下的回落实测、关掉取色后「立刻」变（代码上是即时，
  要眼睛确认没有残影）、深色模式逐项对比度——都要真机看，静态查不出。
- 大屏：840dp 五形态的实际观感、双栏详情旋转后右栏、键盘+双栏+聊天页叠加的高度计算。
  代码层面已核：`PageWidth` 37 处使用、`showAppSheet` 宽屏收窄 560、
  `FadeIndexedStack` 切 tab 保状态。
- 桌面（Windows）构建。
- 覆盖安装后登录态与已下载文件是否保留（要旧版 APK 造数据）。
- 线上四入口回归。留到你说发的时候一起做。
