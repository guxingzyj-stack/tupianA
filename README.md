# 老照

给家人自用的 AI 照片补救 App。后端是 FastAPI + SQLite,移动端是 Flutter。

## 快速验收

推荐一键跑完整项目预检:

```powershell
$env:APP_TOKEN="dev-token-change-me"
powershell -ExecutionPolicy Bypass -File scripts/preflight.ps1
```

脚本会先跑后端单测,再临时启动本地后端,跑后端 smoke,再跑移动端 preflight,结束后自动关闭它启动的后端。
移动端 preflight 会额外检查适老化红线:生产界面不出现会员/付费/技术错误词,且硬编码字号不低于 16。
同时会跑后端环境预检和 Docker context 检查。本地默认允许开发配置;部署前可以打开严格环境检查:
脚本默认会优先使用 Codex bundled Python;如果要指定其他解释器,传 `-Python C:\path\to\python.exe`。

```powershell
$env:APP_TOKEN="your-long-random-token"
$env:RELAY_BASE_URL="https://your-relay.example.com/v1"
$env:RELAY_API_KEY="your-relay-key"
$env:DB_PATH="/volume/app.db"
$env:FILE_BASE="/volume/files"
powershell -ExecutionPolicy Bypass -File scripts/preflight.ps1 -StrictBackendEnv
```

也可以分开跑。

先跑后端单元测试:

```powershell
cd backend
powershell -ExecutionPolicy Bypass -File scripts/run_tests.ps1
```

先跑后端完整链路:

```powershell
cd backend
$env:APP_TOKEN="dev-token-change-me"
powershell -ExecutionPolicy Bypass -File scripts/run_local_smoke.ps1
```

再跑移动端预检:

```powershell
cd mobile
$env:APP_TOKEN="dev-token-change-me"
powershell -ExecutionPolicy Bypass -File scripts/preflight.ps1 `
  -ApiBaseUrl http://127.0.0.1:8000
```

如果只检查 Flutter 代码:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/preflight.ps1 -SkipBackendCheck
```

本地浏览器预览商业化 UI:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/start_web_preview.ps1
```

脚本会启动一个允许当前预览端口的本地后端,重新构建 Flutter Web,并输出浏览器地址。

## 真机联调

Android 模拟器访问本机后端:

```powershell
flutter run `
  --dart-define=API_BASE_URL=http://10.0.2.2:8000 `
  --dart-define=APP_TOKEN=dev-token-change-me
```

真机访问本机后端时,把 `API_BASE_URL` 换成电脑局域网 IP。部署后换成 Zeabur 的 HTTPS 地址。

## 公网部署验收

后端部署到 Zeabur 后:

```powershell
cd backend
$env:APP_TOKEN="your-token"
powershell -ExecutionPolicy Bypass -File scripts/verify_deployment.ps1 `
  -BaseUrl https://<service>.zeabur.app
```

通过后会生成 `deployment_evidence.json`,用于更新 [MVP_ACCEPTANCE.md](MVP_ACCEPTANCE.md)。
要验证 Zeabur Volume 持久化,先跑一次生成 `deployment_evidence_before_restart.json`,在 Zeabur 控制台重启服务,再用 `-CheckPersistenceFrom deployment_evidence_before_restart.json` 生成最终 `deployment_evidence.json`。
要验证“运行 1 周稳定”,用 `backend/scripts/monitor_deployment.ps1 -DurationMinutes 10080 -IntervalSeconds 300` 生成 `uptime_evidence.json`。最终检查会核对起止时间、样本数量、失败数和失败率是否与汇总字段一致。

## 最终证据检查

有部署、安装、反馈和真实使用成本证据后,跑最终 MVP 证据检查:

```powershell
python scripts/check_mvp_evidence.py
```

检查器会核对部署、Volume 持久化、1 周 uptime、Android/iOS 安装、家庭试用场景、体验红线和 30 天成本。成本检查会确认总额未超 ¥300,并核对按设备、类型、日期分组的合计是否等于总额。家庭试用场景包括:自己 10 张照片修复、家人独立完成"选图 -> 修 -> 发"、老照片修复、动态视频分享、祝福模板分享、历史记录 10 条。

开发中可以先看还缺哪些外部证据:

```powershell
python scripts/check_mvp_evidence.py --allow-pending
```

Windows 上也可以用最终门禁脚本。正式交付时不要带 `-AllowPending`:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/final_acceptance.ps1
```

本地开发阶段查看缺口:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/final_acceptance.ps1 -AllowPending -AllowLocalUrls
```

## Android 发布准备

有 Zeabur HTTPS 后端后,一条命令完成后端公网验收、Android release 构建和 APK artifact 验证:

首次发布前先生成本机 release keystore:

```powershell
cd mobile
powershell -ExecutionPolicy Bypass -File scripts/create_android_keystore.ps1
cd ..
```

```powershell
$env:APP_TOKEN="your-token"
powershell -ExecutionPolicy Bypass -File scripts/prepare_android_release.ps1 `
  -BaseUrl https://<service>.zeabur.app
```

产物在 `mobile/dist/`。连接安卓手机后安装:

```powershell
cd mobile
powershell -ExecutionPolicy Bypass -File scripts/install_android_apk.ps1 -LaunchAfterInstall
```

## 交付记录

- [MVP_ACCEPTANCE.md](MVP_ACCEPTANCE.md): v0.1 最终验收看板
- [feedback.md](feedback.md): 家庭试用反馈记录
- [backend/README.md](backend/README.md): 后端运行、Zeabur 部署和成本预算
- [mobile/README.md](mobile/README.md): 移动端运行、预检和打包
