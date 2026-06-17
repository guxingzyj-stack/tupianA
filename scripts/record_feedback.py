from __future__ import annotations

import argparse
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_FEEDBACK = ROOT / "feedback.md"


def yes_no(value: str) -> str:
    normalized = value.strip()
    if normalized in {"是", "否"}:
        return normalized
    lowered = normalized.lower()
    if lowered in {"yes", "y", "true", "1"}:
        return "是"
    if lowered in {"no", "n", "false", "0"}:
        return "否"
    return normalized


def append_record(args: argparse.Namespace) -> str:
    record_date = args.date or date.today().isoformat()
    title = args.title or f"{record_date} {args.user} {args.kind}"
    fields = [
        ("日期", record_date),
        ("使用人", args.user),
        ("设备", args.device),
        ("记录类型", args.kind),
        ("场景", args.scene),
        ("成功数量", str(args.success_count)),
        ("历史记录条数", str(args.history_count)),
        ("是否独立完成", yes_no(args.independent)),
        ("是否需要解释", yes_no(args.needs_explanation)),
        ("是否发出", yes_no(args.sent)),
        ("遇到的问题", args.issue),
        ("看到的提示", args.prompt_seen),
        ("是否出现技术错误", yes_no(args.technical_error)),
        ("是否点完没反应", yes_no(args.dead_tap)),
        ("处理决定", args.decision),
    ]
    body = "\n".join(f"{name}: {value}" for name, value in fields)
    return f"\n### {title}\n\n{body}\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Append a structured family trial feedback record.")
    parser.add_argument("--feedback", type=Path, default=DEFAULT_FEEDBACK)
    parser.add_argument("--date", default="")
    parser.add_argument("--title", default="")
    parser.add_argument("--user", required=True, help="例如: 自己 / 王奶奶")
    parser.add_argument("--device", default="")
    parser.add_argument(
        "--kind",
        required=True,
        choices=["照片修复", "老照片修复", "动态视频", "祝福模板", "历史记录"],
    )
    parser.add_argument("--scene", default="")
    parser.add_argument("--success-count", type=int, default=1)
    parser.add_argument("--history-count", type=int, default=0)
    parser.add_argument("--independent", default="否")
    parser.add_argument("--needs-explanation", default="是")
    parser.add_argument("--sent", default="否")
    parser.add_argument("--issue", default="无")
    parser.add_argument("--prompt-seen", default="")
    parser.add_argument("--technical-error", default="否")
    parser.add_argument("--dead-tap", default="否")
    parser.add_argument("--decision", default="继续观察")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    record = append_record(args)
    if args.dry_run:
        print(record.strip())
        return 0

    feedback_path = args.feedback
    feedback_path.parent.mkdir(parents=True, exist_ok=True)
    if not feedback_path.exists():
        feedback_path.write_text("# 老照家庭试用反馈\n\n## 反馈记录\n", encoding="utf-8")
    with feedback_path.open("a", encoding="utf-8") as file:
        file.write(record)
    print(f"Feedback record appended: {feedback_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
