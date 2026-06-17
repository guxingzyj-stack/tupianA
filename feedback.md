# 老照家庭试用反馈

记录真实使用问题。每天问家人两个问题:

1. 今天有没有想用但不会用的地方?
2. 哪一步觉得不舒服?

## 记录格式

```text
日期:
使用人:
设备:
记录类型: 照片修复 / 老照片修复 / 动态视频 / 祝福模板 / 历史记录
场景:
成功数量:
历史记录条数:
是否独立完成:
是否需要解释:
是否发出:
遇到的问题:
看到的提示:
是否出现技术错误:
是否点完没反应:
处理决定:
```

记录要求:

- 自己修照片可以用 `记录类型: 照片修复`, `使用人: 自己`, `成功数量: 10` 一次汇总。
- 家人独立完成主流程时,写 `记录类型: 照片修复`, `是否独立完成: 是`, `是否需要解释: 否`, `是否发出: 是`。
- 老照片、动态视频、祝福模板分别用对应的 `记录类型`。
- 历史记录条数用 `记录类型: 历史记录`, `历史记录条数: 10`。
- 最终验收至少需要 6 条真实记录；主流程、老照片、动态视频、祝福模板、历史记录这 5 个家人场景必须分开记录。

## 快速记录命令

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

自己完成 10 张照片修复可以记录为:

```powershell
python scripts/record_feedback.py `
  --user "自己" `
  --kind "照片修复" `
  --scene "自测 10 张照片修复" `
  --success-count 10 `
  --independent 是 `
  --needs-explanation 否 `
  --sent 否 `
  --decision "通过"
```

## 反馈记录

### 2026-06-16

暂无真实家庭试用记录。

## 检查方式

有真实记录后运行:

```powershell
python scripts/check_mvp_evidence.py --allow-pending
```

如果记录里出现技术错误或点完没反应,脚本会标红。
