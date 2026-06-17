from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Operation:
    type: str
    value: float = 0.0
    mask: str | None = None
    name: str | None = None


_KEYWORD_OPERATIONS: list[tuple[tuple[str, ...], list[Operation]]] = [
    (("提亮", "更亮", "明亮"), [Operation("brightness", 0.18), Operation("contrast", 0.05)]),
    (("鲜艳", "色彩增强"), [Operation("saturation", 0.24), Operation("vibrance", 0.18)]),
    (("通透", "对比"), [Operation("contrast", 0.14), Operation("clarity", 0.12)]),
    (("暖色",), [Operation("warmth", 0.12)]),
    (("天空更蓝",), [Operation("sky_blue", 0.28), Operation("brightness", 0.05)]),
    (("主体更清楚", "主体清楚"), [Operation("subject_boost", 0.18), Operation("clarity", 0.10)]),
    (("暖色草原", "纪录片感"), [Operation("warmth", 0.12), Operation("saturation", 0.12), Operation("contrast", 0.08)]),
    (("柔和",), [Operation("soft", 0.18)]),
]

_DEFAULT_OPERATIONS = [Operation("brightness", 0.12), Operation("contrast", 0.06), Operation("saturation", 0.06)]


def parse_intent(intent_str: str) -> list[Operation]:
    if not intent_str:
        return list(_DEFAULT_OPERATIONS)
    operations: list[Operation] = []
    for keywords, mapped in _KEYWORD_OPERATIONS:
        if any(keyword in intent_str for keyword in keywords):
            operations.extend(mapped)
    if not operations:
        operations.extend(_DEFAULT_OPERATIONS)
    return operations

