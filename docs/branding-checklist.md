# 品牌可换 —— 清单

统计时间：2026-11-03。目标：把写死的「时间線」收敛成一个可配置的 Brand 对象。

## A. 应用内品牌名（代码里，可改成接口下发）

| # | 位置 | 显示在哪 |
|---|---|---|
| A1 | `lib/main.dart:117` | 系统任务切换器里的标题 |
| A2 | `lib/pages/feed_tab.dart:187` | 时间线页顶部标题 |
| A3 | `lib/pages/me_tab.dart:245` | 「我的」页用户名旁 |
| A4 | `lib/pages/me_tab.dart:246` | 版本行 `时间線 · 1.3.40 (84)` |
| A5 | `lib/pages/about_page.dart:22` | 关于页大标题 |
| A6 | `lib/pages/about_page.dart:42` | 开源许可页标题 |
| A7 | `lib/pages/setup_page.dart:65` | 首次配置服务器页 |
| A8 | `lib/pages/settings_page.dart:230` | 设置项「关于时间線」 |
| A9 | `lib/widgets/app_drawer.dart:395` | 抽屉头部 |
| A10 | `lib/save_cover_io.dart:16` | 存图时的相册名 |

十处，全部是界面文案，没有逻辑依赖。改成一个 `Brand.name` 即可。

## B. 系统层（编译期写死，接口改不了）

| # | 位置 | 内容 | 备注 |
|---|---|---|---|
| B1 | `android/app/src/main/AndroidManifest.xml:17` | `android:label` | 桌面名字。运行时改不了，多品牌要预置 `activity-alias` |
| B2 | `android/app/src/main/res/mipmap-*/ic_launcher.png` | 桌面图标 | 同上，每套图标一套资源 |
| B3 | `android/app/build.gradle:27` | `applicationId com.kalutoex.shijianxian` | 两个部署装同一台手机会互相覆盖，换品牌必须换包名 |
| B4 | `web/index.html:32` | `<title>` | 网页标签标题 |
| B5 | `web/index.html:26` | `apple-mobile-web-app-title` | iOS 加到主屏幕后的名字 |
| B6 | `web/manifest.json:2-3` | `name` / `short_name` | PWA 名字 |

## C. 功能名「时间线」（指的是信息流这个功能，不跟品牌走）

| # | 位置 | 内容 |
|---|---|---|
| C1 | `lib/widgets/app_drawer.dart:139` | 抽屉菜单项「时间线」 |
| C2 | `lib/pages/settings_page.dart:93`、`363` | 设置项「时间线排序」 |
| C3 | `lib/pages/settings_page.dart:379` | 启动落点选项 |
| C4 | `lib/pages/settings_page.dart:312` | tab 标题映射 |

默认不跟品牌变。要不要也开放给部署者改，另说。

## D. 注释（不用动）

`store.dart:79/82/88/191`、`home_page.dart:27/169`、`feed_tab.dart:10`、`thread_tile.dart:12`。

## 其他事实

- 仓库里**没有 ios 目录**，iOS 工程还没建。
- 客户端**没有本地通知**，所以通知渠道名这一项暂时不存在。以后加推送会多出 c1 处（Android 通知渠道名会显示在系统设置里）。
- 后端**不下发任何站点名**，`时间線` 只存在于客户端。所以品牌这件事现在是纯客户端的事，加接口是新增，不是迁移。

## 结论

真正要动的是 **A 组 10 处 + B 组 6 处**。

- A 组：一次清完，半小时的量。
- B 组：单品牌无所谓；多品牌要做构建参数（flavor），每套一份 label/图标/包名。
