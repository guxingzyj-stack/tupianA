# AI 照片补救 App 后端

FastAPI + SQLite 后端,按自用版 MVP 架构实现。

## 本地运行

```powershell
cd backend
python -m pip install -r requirements.txt
python scripts/init_db.py
uvicorn app.main:app --reload
```

探活:

```powershell
Invoke-RestMethod http://localhost:8000/api/health
```

业务接口需要 `X-App-Token` 请求头,值来自 `APP_TOKEN`。

## 本地冒烟测试

先跑后端单元测试:

```powershell
cd backend
powershell -ExecutionPolicy Bypass -File scripts/run_tests.ps1
```

脚本会优先使用 Codex bundled Python,避免 Windows 系统 Python 版本过新导致依赖缺失。

启动服务后,在另一个终端运行:

```powershell
$env:APP_TOKEN="dev-token-change-me"
powershell -ExecutionPolicy Bypass -File scripts/smoke_test.ps1
```

也可以直接一键启动本地后端并跑完整 smoke:

```powershell
cd backend
$env:APP_TOKEN="dev-token-change-me"
powershell -ExecutionPolicy Bypass -File scripts/run_local_smoke.ps1
```

如果 `127.0.0.1:8000` 已经有健康的后端,脚本会复用现有服务;否则会临时启动 `uvicorn app.main:app`,跑完后自动关闭它。

脚本会在缺少 `test_images/cheetah.jpg` 时自动生成一张样例图,然后跑通:

1. `GET /api/health`
2. `PUT /api/devices/smoke-device/config` 设置测试设备高预算和高视频上限
3. `POST /api/analyze`
4. 下载基础修复图
5. 用单独设备验证预算用完时 `/api/video` 返回 429 人话提示
6. `POST /api/enhance` 三个选项
7. `POST /api/video` 创建动态图任务并轮询完成
8. `GET /api/templates` 校验 24 个模板
9. `POST /api/template/apply` 创建祝福视频任务并轮询完成
10. 下载三张结果图和两个视频到 `smoke_output/`

## Zeabur 部署

部署前先检查环境变量:

```powershell
$env:APP_TOKEN="your-long-random-token"
$env:RELAY_BASE_URL="https://your-relay.example.com/v1"
$env:RELAY_API_KEY="your-relay-key"
$env:IMAGE_EDIT_FALLBACK_BASE_URL="https://your-fallback-relay.example.com/v1"
$env:IMAGE_EDIT_FALLBACK_API_KEY="your-fallback-relay-key"
$env:IMAGE_EDIT_FALLBACK_MODEL="gpt-image-2"
$env:DB_PATH="/volume/app.db"
$env:FILE_BASE="/volume/files"
$env:PUBLIC_BASE_URL="https://<service>.zeabur.app"
python scripts/check_env.py
```

本地开发可以放宽检查:

```powershell
python scripts/check_env.py --allow-local-dev
```

检查 Docker 构建上下文:

```powershell
python scripts/check_docker_context.py
```

如果本机有 Docker,再跑真实构建:

```powershell
docker build -t lao-zhao-backend .
```

1. 在 Zeabur 创建 Project 和 Service,选择 GitHub 仓库。
2. 根目录设置为 `backend`,构建方式使用 Dockerfile。
3. 暴露端口 `8000`。
4. 添加持久化 Volume,挂载到 `/volume`。
5. 设置环境变量:
   - `RELAY_BASE_URL`
   - `RELAY_API_KEY`
   - `IMAGE_EDIT_MODEL`
   - `IMAGE_EDIT_FALLBACK_BASE_URL`
   - `IMAGE_EDIT_FALLBACK_API_KEY`
   - `IMAGE_EDIT_FALLBACK_MODEL`
   - `DB_PATH=/volume/app.db`
   - `FILE_BASE=/volume/files`
   - `PUBLIC_BASE_URL=https://<service>.zeabur.app`
   - `APP_TOKEN`
   - `STORAGE_RETENTION_HOURS=24`
   - `STORAGE_CLEANUP_INTERVAL_SECONDS=3600`
6. 部署后访问 `https://<service>.zeabur.app/api/health`。

部署后跑公网验收:

```powershell
$env:APP_TOKEN="your-token"
powershell -ExecutionPolicy Bypass -File scripts/verify_deployment.ps1 `
  -BaseUrl https://<service>.zeabur.app
```

脚本会检查公网 health、设备配置 token、完整 smoke,并写出 `deployment_evidence.json` 作为验收证据。

验证 Zeabur Volume 持久化时,先跑一次生成 marker:

```powershell
$env:APP_TOKEN="your-token"
powershell -ExecutionPolicy Bypass -File scripts/verify_deployment.ps1 `
  -BaseUrl https://<service>.zeabur.app `
  -EvidencePath deployment_evidence_before_restart.json
```

然后在 Zeabur 控制台重启服务,再跑:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/verify_deployment.ps1 `
  -BaseUrl https://<service>.zeabur.app `
  -CheckPersistenceFrom deployment_evidence_before_restart.json `
  -EvidencePath deployment_evidence.json
```

第二次会确认 SQLite 里的 marker 和 `/files/...` 文件 marker 在重启后仍可访问,并把 `volume_persistence_checked=true` 写进最终 evidence。

验证运行 1 周稳定时,保持终端或服务器任务运行:

```powershell
$env:APP_TOKEN="your-token"
powershell -ExecutionPolicy Bypass -File scripts/monitor_deployment.ps1 `
  -BaseUrl https://<service>.zeabur.app `
  -DurationMinutes 10080 `
  -IntervalSeconds 300 `
  -EvidencePath uptime_evidence.json
```

脚本会定期检查 `/api/health` 和带 token 的设备配置接口,最终写出 `uptime_evidence.json`。最终 MVP 检查要求时长至少 168 小时,失败率不超过 1%,并会核对起止时间、样本数量、失败数和失败率是否与汇总字段一致。

AI relay 没配置或调用失败时,`/api/analyze` 会按 PRD 回退到通用三选项,主流程仍可验证。

## 成本与预算

子女配置里的 `daily_budget_cny` 是服务端硬限制。后端会按设备统计最近 24 小时 job metadata 里的估算成本,超出后返回 `今天的预算用完了,明天再试`。

当前估算值:

- AI 分析: relay 已配置时 ¥0.10 / 次
- 老照片生成式修复: ¥0.50 / 次
- 让照片动起来: ¥1.00 / 次
- 祝福模板视频: ¥1.00 / 次

查看最近 30 天估算成本:

```powershell
python scripts/cost_report.py --days 30 --limit-cny 300
```

需要记录验收证据时输出 JSON:

```powershell
python scripts/cost_report.py --days 30 --limit-cny 300 --json
```

后端启动时会先清理一次超过 `STORAGE_RETENTION_HOURS` 的旧任务文件,之后按 `STORAGE_CLEANUP_INTERVAL_SECONDS` 定时清理,避免 Volume 长期堆满。
