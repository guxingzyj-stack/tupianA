from __future__ import annotations

import json
import re
from typing import Any

import httpx

from app.adapters.base import AdapterFailure
from app.config import Settings, get_settings
from app.prompts.analyze_prompt import SCHEMA_VALIDATOR, SYSTEM_PROMPT, USER_PROMPT


_CODE_FENCE_RE = re.compile(r"^```(?:json)?\s*|\s*```$", re.IGNORECASE | re.MULTILINE)


class ClaudeAdapter:
    def __init__(
        self,
        settings: Settings | None = None,
        *,
        relay_base_url: str | None = None,
        relay_api_key: str | None = None,
        ai_model: str | None = None,
    ):
        self.settings = settings or get_settings()
        self.relay_base_url = relay_base_url or self.settings.relay_base_url
        self.relay_api_key = relay_api_key or self.settings.relay_api_key
        self.ai_model = ai_model or self.settings.ai_model

    async def analyze(self, image_b64: str | None = None, image_url: str | None = None) -> dict[str, Any]:
        if not self.relay_base_url or not self.relay_api_key:
            raise AdapterFailure("relay is not configured")
        if not image_b64 and not image_url:
            raise AdapterFailure("image is required")

        user_content: list[dict[str, Any]] = [{"type": "text", "text": USER_PROMPT}]
        if image_url:
            user_content.append({"type": "image_url", "image_url": {"url": image_url}})
        else:
            user_content.append(
                {
                    "type": "image_url",
                    "image_url": {"url": f"data:image/jpeg;base64,{image_b64}"},
                }
            )

        payload = {
            "model": self.ai_model,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": user_content},
            ],
            "temperature": 0.2,
        }

        try:
            async with httpx.AsyncClient(
                base_url=self.relay_base_url.rstrip("/"),
                timeout=httpx.Timeout(30.0),
                headers={"Authorization": f"Bearer {self.relay_api_key}"},
            ) as client:
                response = await client.post("/chat/completions", json=payload)
                response.raise_for_status()
                data = response.json()
        except Exception as exc:
            raise AdapterFailure("relay request failed") from exc

        try:
            content = data["choices"][0]["message"]["content"]
            parsed = _parse_json_content(content)
        except Exception as exc:
            raise AdapterFailure("relay response is not valid JSON") from exc

        if not SCHEMA_VALIDATOR(parsed):
            raise AdapterFailure("relay response failed schema validation")
        return parsed


def _parse_json_content(content: Any) -> dict[str, Any]:
    if isinstance(content, list):
        text = "".join(part.get("text", "") for part in content if isinstance(part, dict))
    else:
        text = str(content)
    cleaned = _CODE_FENCE_RE.sub("", text.strip()).strip()
    return json.loads(cleaned)
