from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Operation:
    type: str
    value: float = 0.0
    mask: str | None = None
    name: str | None = None


_KEYWORD_OPERATIONS: list[tuple[tuple[str, ...], list[Operation]]] = [
    (
        ("提亮", "更亮", "明亮"),
        [Operation("brightness", 0.34), Operation("contrast", 0.16), Operation("clarity", 0.12)],
    ),
    (
        ("鲜艳", "色彩增强"),
        [Operation("saturation", 0.42), Operation("vibrance", 0.30), Operation("contrast", 0.12)],
    ),
    (("通透", "对比"), [Operation("contrast", 0.24), Operation("clarity", 0.22)]),
    (("暖色",), [Operation("warmth", 0.18), Operation("saturation", 0.10)]),
    (
        ("天空更蓝",),
        [Operation("sky_blue", 0.38), Operation("brightness", 0.10), Operation("clarity", 0.10)],
    ),
    (("主体更清楚", "主体清楚"), [Operation("subject_boost", 0.28), Operation("clarity", 0.20)]),
    (
        ("暖色草原", "纪录片感"),
        [Operation("warmth", 0.18), Operation("saturation", 0.22), Operation("contrast", 0.14)],
    ),
    (("柔和", "柔光"), [Operation("soft", 0.34), Operation("brightness", 0.08)]),
]

_DEFAULT_OPERATIONS = [
    Operation("brightness", 0.24),
    Operation("contrast", 0.12),
    Operation("saturation", 0.12),
    Operation("clarity", 0.10),
]


def parse_intent(intent_str: str) -> list[Operation]:
    if not intent_str:
        return list(_DEFAULT_OPERATIONS)
    operations: list[Operation] = []
    lowers_contrast = "降低对比" in intent_str or "低对比" in intent_str
    for keywords, mapped in _KEYWORD_OPERATIONS:
        if lowers_contrast and "对比" in keywords:
            continue
        if any(keyword in intent_str for keyword in keywords):
            operations.extend(mapped)
    if not operations:
        operations.extend(_DEFAULT_OPERATIONS)
    return operations
