# OpenBBS

一个能自己部署的轻论坛。服务端 FastAPI + SQLite，客户端 Flutter（Android / Windows / Web）。

## 自己开一座

```bash
cd server
./install.sh     # 检依赖、写配置、建库、打印管理码
./run.sh         # 起站
```

十分钟，详见 [docs/DEPLOY.md](docs/DEPLOY.md)。配置全在 `server/config/site.json`，
每一项见 [docs/CONFIG.md](docs/CONFIG.md)。

| 日常 | 命令 |
|---|---|
| 起 / 停 | `./run.sh` / `./run.sh --stop` |
| 立刻备份 | `./backup.sh`（建议挂 cron，默认留 30 份） |
| 从备份恢复 | `./restore.sh data/backups/<文件>.tar.gz` |
| 看有没有新版本 | `./check_update.sh`（只提示，不自动升） |
| 容器跑 | `./install.sh --docker && docker compose up -d --build` |

改端口、上证书、接主站，都只改 `site.json` 的 `site` / `server` 两段，重启生效。

## 客户端

```bash
flutter pub get
flutter build apk --release
flutter run -d windows
```

打包后可用 `./release.sh stable` 放进服务端的更新通道。测试：

```bash
flutter test
flutter analyze
```

各段设计与落地细节在 [docs/PLAN-5-STEPS.md](docs/PLAN-5-STEPS.md)。
