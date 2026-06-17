# 老照 v0.1 MVP 验收看板

这份文件记录最终交付证据。只有每一项都有真实证据,才算 v0.1 MVP 完成。

## 当前本地证据快照（2026-06-16）

| 项目 | 状态 | 证据 |
|------|------|------|
| 后端单测 | 已通过 | `backend/scripts/run_tests.ps1`，40 passed |
| 后端本地部署 smoke | 已通过 | `backend/scripts/verify_deployment.ps1 -BaseUrl http://127.0.0.1:8000 -AppToken dev-token-change-me`，生成 `backend/deployment_evidence.json` |
| 主链路接口 | 已通过 | smoke 覆盖 `/api/health`、设备配置、`/api/analyze`、3 个 `/api/enhance`、`/api/templates`、模板视频任务轮询 |
| Flutter Web 构建 | 已通过 | `flutter build web --dart-define=API_BASE_URL=http://127.0.0.1:8000 --dart-define=APP_TOKEN=dev-token-change-me` |
| Web 历史页兜底 | 已通过 | Web 预览中本地 SQLite 不可用时降级为空历史页，不再显示错误态；截图 `commercial-history-empty-fixed.png` |
| Android release APK | 已生成 | `mobile/dist/lao-zhao-0.1.0-release.apk`，60,967,719 bytes |
| Android APK 校验 | 已通过 | `mobile/scripts/verify_android_artifact.ps1 -AllowPlaceholder`，SHA256 `9fe822a3bb6d2f9800943c4912aabf0968912d3b6d26c339133f771ba9070956`，apksigner v2=true，dedicated release keystore |
| Android 安装记录脚本 | 已增强 | `mobile/scripts/install_android_apk.ps1 -LaunchAfterInstall` 可安装后启动 App、截屏并把 `screenshot_path` 写入 `dist/install_evidence.json` |
| 家庭反馈记录脚本 | 已实现 | `scripts/record_feedback.py` 可追加结构化反馈；dry-run 与临时反馈文件已验证能被 `check_mvp_evidence.py` 识别 |
| MVP 证据检查 | 部分通过 | `scripts/check_mvp_evidence.py --allow-pending --allow-local-urls`: 20 passed, 6 pending, 0 failed |

当前仍缺最终交付证据：Zeabur HTTPS 部署与 Volume 重启验证、168 小时 uptime、Android 真机安装证据、iOS 真机安装证据、真实家人反馈记录。

下一步执行入口见 `FINAL_ACCEPTANCE_RUNBOOK.md`。

## 自动化验证

| 项目 | 状态 | 证据 |
|------|------|------|
| 后端单测 | 已通过 | `backend/scripts/run_tests.ps1`: 40 passed |
| 后端本地 smoke | 已通过 | `scripts/run_local_smoke.ps1`: `Smoke test passed in 2.63s` |
| 移动端分析 | 已通过 | `dart analyze`: No issues found |
| 移动端测试 | 已通过 | `flutter test`: 18 passed |
| 移动端适老化红线检查 | 已通过 | `mobile/scripts/check_elderly_red_lines.py`: scanned 36 production Dart files; no forbidden terms; no `fontSize < 16` |
| 移动端预检 | 已通过 | `scripts/preflight.ps1 -SkipBackendCheck`: now truly skips backend checks, then runs red-line check, `dart analyze`, and 18 Flutter tests |
| 全项目预检 | 已通过 | 根目录 `scripts/preflight.ps1`: auto-selected bundled Python, env check, Docker context, 40 backend tests, token-conflict fallback port, backend smoke, mobile red-line check, `dart analyze`, and 18 Flutter tests passed |
| 商业化 Web 预览脚本 | 已通过 | `scripts/start_web_preview.ps1 -SkipBuild`: verifies backend token and CORS for the current preview port, then serves `mobile/build/web` at `http://127.0.0.1:8082` |
| 最终验收门禁脚本 | 已通过 | `scripts/final_acceptance.ps1 -AllowPending -AllowLocalUrls`: wraps `check_mvp_evidence.py`; final delivery should run without `-AllowPending` |
| MVP 证据检查器 | 已通过 | `scripts/check_mvp_evidence.py --allow-pending`: reports missing deployment/install/feedback/cost evidence as pending; validates 6+ feedback records with distinct family scenario records, red-line feedback, Volume persistence source/marker consistency, 1-week uptime duration/sample consistency, Android install+launch screenshot, Android package/size/SHA256 consistency, iOS install evidence, app version consistency, deployment/uptime/Android URL consistency, and cost total/group consistency |
| 公网部署验收脚本 | 已通过 | `backend/scripts/verify_deployment.ps1` 本地两阶段模拟通过: smoke passed, restart后 DB marker 和 `/files/...` file marker 均可访问 |
| 公网 uptime 监控脚本 | 已通过 | `backend/scripts/monitor_deployment.ps1` 本地短时模拟通过; writes `uptime_evidence.json` with samples, failure rate, duration, and started/ended timestamps |
| 后端环境预检脚本 | 已通过 | strict mode fails unsafe env; `--allow-local-dev` and production-like env pass |
| 后端成本报表脚本 | 已通过 | `backend/scripts/cost_report.py --days 30 --limit-cny 300 --json` |
| Docker context check | 已通过 | `backend/scripts/check_docker_context.py`: Docker context check passed |
| Docker 构建 | 未验证 | 本机暂无 Docker |
| Android debug APK build | 已通过 | `flutter build apk --debug`: `app-debug.apk`, 171444414 bytes; artifact cleaned after verification |
| Android release build mechanics | 已通过 | `scripts/prepare_android_release.ps1 -AllowPlaceholder -SkipBackendVerify`: release APK build succeeded with dedicated release keystore; placeholder artifact cleaned after verification |
| Android install-ready APK | 未完成 | 需要 Zeabur HTTPS URL 后重新生成 `lao-zhao-0.1.0-release.apk` 和 release manifest |
| Android APK checksum | 未完成 | Placeholder signed APK SHA256 verified (`b00103ae635d27fef7642195863b746ea1703e9cdbd55d60c66e5d3c622fb629`); install-ready APK checksum still needs Zeabur HTTPS build |
| Android artifact verifier | 已通过 | `mobile/scripts/verify_android_artifact.ps1`; placeholder release verified with SHA256, manifest, dedicated keystore, `apksigner` v2=true, signer `CN=Lao Zhao`, and `.verify.json`; placeholder artifact cleaned |
| Android install helper | 已实现 | `mobile/scripts/install_android_apk.ps1`; requires `.verify.json` unless explicit skip, then writes install evidence with device model, Android version, package version, APK size, SHA256, and apksigner verification; no connected device in current environment |
| Android release preparation script | 已通过 | Syntax, missing-token guard, HTTPS guard, and redacted failure output verified; full run still needs Zeabur HTTPS backend |
| Android release signing config | 已通过 | Uses `android/key.properties` when present; secrets ignored by git; Android debug build still passes |
| Android keystore helper | 已通过 | `mobile/scripts/create_android_keystore.ps1`; real local keystore generated at ignored `mobile/android/keystore/lao-zhao-release.jks`; `key.properties` ignored |
| Android dedicated release signing | 已通过 | Placeholder release APK built with dedicated keystore; `apksigner verify --print-certs`: v2 signature true, signer `CN=Lao Zhao`, RSA 2048 |
| Zeabur 文件 URL HTTPS | 已修复 | `backend/app/storage/files.py` converts `http://*.zeabur.app` file URLs to HTTPS and supports explicit `PUBLIC_BASE_URL`; prevents Android release builds from spinning on blocked HTTP image loads |
| iOS build | 未验证 | 需要 macOS/Xcode 环境 |
| iOS install evidence helper | 已实现 | `mobile/scripts/record_ios_install_evidence.ps1`; records device model, iOS version, app version, bundle id, signing team, and optional screenshot |

## 部署验收

| 项目 | 状态 | 证据 |
|------|------|------|
| Zeabur 后端部署成功 | 未完成 | 记录公网 URL |
| Zeabur Volume 持久化 | 未完成 | 重启后 DB 和文件目录仍存在，且 marker 与重启前证据一致 |
| 公网 `/api/health` 可访问 | 未完成 | 记录响应和时间 |
| 公网 smoke 通过 | 未完成 | `backend/scripts/verify_deployment.ps1 -BaseUrl <url>` 输出和 `deployment_evidence.json` |
| 运行 1 周稳定 | 未完成 | `backend/scripts/monitor_deployment.ps1 -DurationMinutes 10080`; `uptime_evidence.json` 时长至少 168 小时、失败率 <= 1%，且样本数量/起止时间与汇总字段一致 |

## 真机验收

| 项目 | 状态 | 证据 |
|------|------|------|
| Android 真机安装 | 未完成 | 用 `mobile/scripts/install_android_apk.ps1 -LaunchAfterInstall` 安装后记录设备型号、安装包版本、非空启动截图 |
| iOS 真机安装 | 未完成 | `mobile/scripts/record_ios_install_evidence.ps1` 记录设备型号、iOS 版本、安装包版本、非空截图 |
| 自己完成 10 张照片修复 | 未完成 | 成功张数、失败原因 |
| 家人独立完成"选图 -> 修 -> 发" | 未完成 | 日期、设备、是否需要解释 |
| 家人独立完成"拍纸质老照片 -> 修复" | 未完成 | 日期、照片类型、是否需要解释 |
| 家人发出至少 1 个动态视频 | 未完成 | 日期、模板/动效、分享路径 |
| 家人发出至少 1 个祝福模板 | 未完成 | 日期、模板名、分享路径 |
| 历史记录有 10 条真实记录 | 未完成 | 历史页截图或条数 |

## 体验红线

| 红线 | 状态 | 证据 |
|------|------|------|
| 没有"点完没反应"反馈 | 未验证 | 见 `feedback.md` |
| 没有显示技术错误码 | 未验证 | 见 `feedback.md` |
| 老照片动效默认关闭 | 已实现 | 子女配置 `enable_animate_old=false`,后端也拦截 |
| AI 生成视频分享前有确认 | 已实现 | 2 秒确认弹窗测试覆盖 |
| 日预算硬限制 | 已实现 | 后端预算测试和 smoke 429 校验 |
| 月度 AI 调用成本 < ¥300 | 未验证 | 真实使用后跑 `backend/scripts/cost_report.py --days 30 --limit-cny 300` 并对照 relay 账单 |

## 下一步

1. 部署后端到 Zeabur,记录公网 URL。
2. 用公网 URL 跑后端 smoke。
3. 打 Android 包并装到自己手机。
4. 跑完整修图、老照片、视频、模板流程。
5. 给家人试用,每天记录 `feedback.md`。
