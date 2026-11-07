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

### P2-1 web 端首页每次打开抛 `UnsupportedError`

- 位置：`lib/permissions.dart:37`（`Platform.isAndroid`）、`lib/pages/home_page.dart:71`（无条件调用）
- 现象：`dart:io` 在网页端编译得过，但 `Platform` 一碰就抛 `Unsupported operation`。
  首页 `addPostFrameCallback` 里直接调 `AppPerms.firstRun()`，web 上每次回首页红一条日志，
  `perm_asked_v1` 永远写不进去，也就永远每次都想问。
- 已修：`firstRun()` 开头 `if (kIsWeb) return;`。这条本可以更早发现——第 2 段的
  `dart:io` 检查只查了 `*_io.dart` 里的引用。

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
| `flutter test --no-pub` | 104 全过 |
| web 构建 | `deploy_web.sh` 通过，首页 200，`main.dart.js` 1.2MB，feed 200 |
| canvaskit 冗余清理 | 脚本里有（skwasm/wimp/symbols） |
| 自毁 SW | 脚本里写死，没丢 |
| 旧 `main.dart.js` 备份 | 本轮补上 |
| APK 出包 | **没做**（本轮没改版本号，也不发） |
| 四入口线上回归 | **没做**，等发版前 |
| 覆盖安装 / 本地状态升级 | **没做** |

## 回滚步骤

APK：`bbs/server/data/apk-archive/` 取上一版，直接覆盖安装（同包名同签名）。

Web：

```bash
cd /vol1/1000/data/code/ongoing/bbs/server/web
cp main.dart.js.prev main.dart.js
gzip -9 -f main.dart.js
```

## 本轮没查的

- 主题：壁纸取色在 Android 11 及以下的回落、关掉取色是否即时、关「卡片染色」后还有
  哪些地方在染、深色模式逐项对比度——都要真机看，静态查不出。
- 大屏：840dp 五形态、NavigationRail 切 tab 是否丢状态、双栏旋转、键盘+双栏+聊天叠加。
- 桌面（Windows）构建。
- 更新链路：`/api/app/latest` 缺字段的降级（`fromJson` 里大部分有默认值，但要和服务端
  实际返回对一遍）、覆盖安装后登录态与已下载文件是否保留。
- 线上四入口回归、APK 出包体积。都留到你说发的时候一起做。
