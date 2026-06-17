# 老照 v0.1 最终验收运行手册

这份手册用于把 `scripts/check_mvp_evidence.py` 里的 pending 项逐个变成真实证据。

当前本机已自动验证的部分包括: 后端 smoke、Flutter Web 构建、Android release APK 构建和 APK 签名校验。最终完成还需要公网部署、真机安装和家人试用。

## 1. Zeabur 部署与 Volume 持久化

部署后端到 Zeabur 后，拿到 HTTPS 地址，例如:

```powershell
$baseUrl = "https://your-service.zeabur.app"
$token = "你的 APP_TOKEN"
```

第一次验证部署并写入持久化 marker:

```powershell
cd backend
powershell -ExecutionPolicy Bypass -File scripts/verify_deployment.ps1 `
  -BaseUrl $baseUrl `
  -AppToken $token
```

在 Zeabur 控制台重启服务后，再运行:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/verify_deployment.ps1 `
  -BaseUrl $baseUrl `
  -AppToken $token `
  -CheckPersistenceFrom deployment_evidence.json
```

成功后，`backend/deployment_evidence.json` 应包含:

- `volume_persistence_checked: true`
- `volume_persistence.db_marker_checked: true`
- `volume_persistence.file_marker_checked: true`
- `volume_persistence.source_evidence` 指向重启前证据文件
- 重启后记录的 marker device/file URL 必须与重启前 `volume_persistence_marker` 一致

## 2. 168 小时 uptime 监控

部署稳定后运行:

```powershell
cd backend
powershell -ExecutionPolicy Bypass -File scripts/monitor_deployment.ps1 `
  -BaseUrl $baseUrl `
  -AppToken $token `
  -DurationMinutes 10080 `
  -IntervalSeconds 300
```

这会写出 `backend/uptime_evidence.json`。最终要求:

- `duration_seconds >= 604800`
- `failure_rate_percent <= 1.0`
- `monitor_passed: true`
- `started_at` / `ended_at` 覆盖至少 168 小时
- `samples` 数量、失败数和失败率要与汇总字段一致

## 3. Android 真机安装证据

用 Zeabur HTTPS 后端重新打 install-ready APK:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/prepare_android_release.ps1 `
  -BaseUrl $baseUrl `
  -AppToken $token
```

连接 Android 手机，开启 USB 调试并授权电脑:

```powershell
cd mobile
adb devices -l
```

安装、启动并截图:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install_android_apk.ps1 `
  -LaunchAfterInstall
```

如有多台设备:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install_android_apk.ps1 `
  -Serial <device-id> `
  -LaunchAfterInstall
```

成功后应生成:

- `mobile/dist/install_evidence.json`
- `mobile/dist/android_launch.png`（必须是非空截图文件）

最终检查会确认 APK manifest 版本等于 `mobile/pubspec.yaml` 的完整版本号，并确认真机安装版本等于 `+` 前面的版本名；同时核对安装记录、manifest、verify 证据里的包名、APK 大小和 SHA256 是否一致。

## 4. iOS 真机安装证据

在 macOS/Xcode 中安装到 iPhone 后，回到项目目录记录:

```powershell
cd mobile
powershell -ExecutionPolicy Bypass -File scripts/record_ios_install_evidence.ps1 `
  -DeviceModel "iPhone 15" `
  -IosVersion "18.5" `
  -AppVersion "0.1.0+1" `
  -DeviceName "家人手机" `
  -SigningTeam "Apple Team Name" `
  -ScreenshotPath "C:\path\to\ios-install-screenshot.png"
```

成功后应生成:

- `mobile/dist/ios_install_evidence.json`
- `ScreenshotPath` 指向的截图文件必须存在且非空

最终检查会确认 `AppVersion` 等于 `mobile/pubspec.yaml` 的完整版本号，例如 `0.1.0+1`。

## 5. 家人试用反馈

每次真实试用后，用脚本追加一条结构化记录。

最终检查至少需要 6 条真实记录，并且以下 5 个家人场景必须分别来自不同记录: 主流程发家人、纸质老照片修复、动态视频分享、祝福模板分享、历史记录 10 条。自己 10 张照片修复可以单独汇总成 1 条。

自己完成 10 张照片修复:

```powershell
python scripts/record_feedback.py `
  --user "自己" `
  --kind "照片修复" `
  --scene "自测 10 张照片修复" `
  --success-count 10 `
  --independent 是 `
  --needs-explanation 否 `
  --sent 否 `
  --technical-error 否 `
  --dead-tap 否 `
  --decision "通过"
```

家人独立完成主流程:

```powershell
python scripts/record_feedback.py `
  --user "王奶奶" `
  --device "小米 14" `
  --kind "照片修复" `
  --scene "选图 -> 修 -> 发家人" `
  --independent 是 `
  --needs-explanation 否 `
  --sent 是 `
  --technical-error 否 `
  --dead-tap 否 `
  --decision "通过"
```

还需要分别记录:

- `--kind "老照片修复"`，家人独立完成纸质老照片修复
- `--kind "动态视频"`，家人发出至少一个动态视频
- `--kind "祝福模板"`，家人发出至少一个祝福模板
- `--kind "历史记录" --history-count 10`，历史记录达到 10 条

## 6. 最终检查

所有证据齐后运行:

```powershell
python scripts/check_mvp_evidence.py
```

Windows 上推荐使用最终门禁脚本:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/final_acceptance.ps1
```

如果还想在最终证据检查前同时跑完整本地预检:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/final_acceptance.ps1 -RunPreflight
```

本地模拟检查可使用:

```powershell
python scripts/check_mvp_evidence.py --allow-local-urls
```

或:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/final_acceptance.ps1 -AllowPending -AllowLocalUrls
```

最终交付标准是:

```text
0 failed, 0 pending
```

检查器还会确认 `deployment_evidence.json`、`uptime_evidence.json` 和 Android 安装证据里的后端 URL 指向同一个部署地址。
