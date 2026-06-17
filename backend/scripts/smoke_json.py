from __future__ import annotations

import json
from pathlib import Path
import sys


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(
            "Usage: smoke_json.py analyze|enhance|create-job|job-result|templates|budget-error <json-path>"
        )
    mode = sys.argv[1]
    path = Path(sys.argv[2])
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    if mode == "analyze":
        names = [item["name"] for item in data["analysis"]["options"]]
        if len(names) != 3:
            raise SystemExit("Analyze response did not include exactly 3 options.")
        too_long = [name for name in names if len(name) > 5]
        if too_long:
            raise SystemExit("Option name is too long: " + ", ".join(too_long))
        print(data["job_id"])
        print(data["base_image_url"])
        print("|".join(names))
        return
    if mode == "enhance":
        print(data["result_image_url"])
        return
    if mode == "create-job":
        job_id = data.get("job_id")
        if not job_id:
            raise SystemExit("Response did not include job_id.")
        print(job_id)
        return
    if mode == "job-result":
        status = data.get("status")
        if status == "failed":
            raise SystemExit(data.get("error") or "Async job failed.")
        if status == "success":
            result_url = data.get("result_url")
            if not result_url:
                raise SystemExit("Successful job did not include result_url.")
            print(result_url)
            return
        print("")
        return
    if mode == "templates":
        categories = data.get("categories") or []
        if len(categories) != 4:
            raise SystemExit("Template catalog did not include 4 categories.")
        total = sum(len(category.get("templates") or []) for category in categories)
        if total < 24:
            raise SystemExit(f"Template catalog only included {total} templates.")
        for category in categories:
            for template in category.get("templates") or []:
                if template.get("id") == "midautumn_reunion":
                    print(template["id"])
                    return
        raise SystemExit("Template catalog did not include midautumn_reunion.")
    if mode == "budget-error":
        detail = data.get("detail")
        expected = "今天的预算用完了,明天再试"
        if detail != expected:
            raise SystemExit(f"Expected budget detail {expected!r}, got {detail!r}.")
        print(detail)
        return
    raise SystemExit(f"Unknown mode: {mode}")


if __name__ == "__main__":
    main()
