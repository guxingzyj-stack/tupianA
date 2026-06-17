from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any


CATALOG_PATH = Path(__file__).with_name("templates.json")


@lru_cache(maxsize=1)
def load_template_catalog() -> dict[str, Any]:
    return json.loads(CATALOG_PATH.read_text(encoding="utf-8"))


def find_template(template_id: str) -> dict[str, Any] | None:
    catalog = load_template_catalog()
    for category in catalog.get("categories", []):
        for template in category.get("templates", []):
            if template.get("id") == template_id:
                item = dict(template)
                item["category_id"] = category.get("id")
                item["category_name"] = category.get("name")
                return item
    return None
