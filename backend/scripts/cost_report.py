from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.services.cost_report import estimated_cost_report


def main() -> None:
    parser = argparse.ArgumentParser(description="Summarize estimated AI costs from jobs.")
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument("--limit-cny", type=float, default=300.0)
    parser.add_argument("--json", action="store_true", help="Print JSON only.")
    args = parser.parse_args()

    if args.days < 1:
        raise SystemExit("--days must be >= 1")
    if args.limit_cny < 0:
        raise SystemExit("--limit-cny must be >= 0")

    report = estimated_cost_report(days=args.days)
    exceeded = float(report["total_estimated_cny"]) > args.limit_cny
    report["limit_cny"] = args.limit_cny
    report["over_limit"] = exceeded

    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print(f"Estimated cost in last {args.days} days: ¥{report['total_estimated_cny']:.2f}")
        print(f"Limit: ¥{args.limit_cny:.2f}")
        print(f"Counted jobs: {report['counted_jobs']}")
        print("By type:")
        for job_type, amount in report["by_type"].items():
            print(f"  - {job_type}: ¥{amount:.2f}")
        print("By device:")
        for device_id, amount in report["by_device"].items():
            print(f"  - {device_id}: ¥{amount:.2f}")
        if exceeded:
            print("Cost limit exceeded.")

    if exceeded:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
