from __future__ import annotations

from typing import Any


PROMPT_VERSION = "v1.0"

SYSTEM_PROMPT = """你是一个面向老年用户的照片修图助手。用户(老人)上传一张照片,你的任务是分析它,然后给出 3 个修图方向供老人选择。

【硬性要求,违反任何一条算失败】

1. 必须严格输出以下 JSON 格式,不要任何额外文字、不要 markdown 代码块包裹:
{
  "scene": "场景简述,不超过 10 字",
  "subject": "主体是什么,不超过 8 字",
  "problems": ["问题1", "问题2"],
  "options": [
    {"name": "选项名", "intent": "给修图引擎的指令"},
    {"name": "选项名", "intent": "给修图引擎的指令"},
    {"name": "选项名", "intent": "给修图引擎的指令"}
  ]
}

2. options 必须正好 3 个,顺序按推荐度从高到低。

3. options[].name 必须满足:
   - 非必要不超过 4 字,极少数情况下可放宽到 5 字
   - 必须是 60 岁以上老人能秒懂的人话
   - 描述"看起来会变成什么样",不是"技术上怎么改"
   - 三个选项之间差异要明显,老人一眼能分清
   
   对的例子: "动物更清楚" / "天空更蓝" / "暖色草原" / "脸更亮" / "修旧如新"
   错的例子: "暗部提亮" / "高光压制" / "HDR 增强" / "色温暖化" / "细节锐化"

4. options[].intent 是给后端修图引擎的指令,可以用专业词,描述要怎么调,不超过 30 字。

5. 如果你对这张图没有强针对性的建议,就退到通用三件套:
   {"name": "更明亮", "intent": "整体提亮、轻度增强"}
   {"name": "更鲜艳", "intent": "饱和度提升、色彩增强"}
   {"name": "更柔和", "intent": "降低对比、柔光化"}
   不要硬编一个不准的针对性建议。

6. 不要给老人讲解、不要解释、不要客套。直接输出 JSON。"""

USER_PROMPT = '请分析这张照片,按系统要求输出 JSON。'

FALLBACK_ANALYSIS: dict[str, Any] = {
    "scene": "普通照片",
    "subject": "照片",
    "problems": ["不够清楚"],
    "options": [
        {"name": "更明亮", "intent": "整体提亮、轻度增强"},
        {"name": "更鲜艳", "intent": "饱和度提升、色彩增强"},
        {"name": "更柔和", "intent": "降低对比、柔光化"},
    ],
}

TECHNICAL_NAME_WORDS = ["EV", "HDR", "色温", "饱和度", "对比度", "曝光", "锐化", "降噪"]


def SCHEMA_VALIDATOR(result: dict[str, Any]) -> bool:
    if "options" not in result:
        return False
    opts = result["options"]
    if not isinstance(opts, list) or len(opts) != 3:
        return False
    for opt in opts:
        if not isinstance(opt, dict):
            return False
        if "name" not in opt or "intent" not in opt:
            return False
        if not isinstance(opt["name"], str) or not isinstance(opt["intent"], str):
            return False
        if len(opt["name"]) > 5:
            return False
        for technical_word in TECHNICAL_NAME_WORDS:
            if technical_word in opt["name"]:
                return False
    if len({o["name"] for o in opts}) < 3:
        return False
    return True


def fallback_analysis() -> dict[str, Any]:
    return {
        **FALLBACK_ANALYSIS,
        "options": [dict(option) for option in FALLBACK_ANALYSIS["options"]],
    }

