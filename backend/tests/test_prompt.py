from app.prompts.analyze_prompt import SCHEMA_VALIDATOR, fallback_analysis


def test_schema_validator_accepts_good_result():
    assert SCHEMA_VALIDATOR(
        {
            "options": [
                {"name": "更明亮", "intent": "整体提亮"},
                {"name": "更鲜艳", "intent": "色彩增强"},
                {"name": "更柔和", "intent": "柔光化"},
            ]
        }
    )


def test_schema_validator_rejects_bad_results():
    bad_results = [
        {},
        {"options": []},
        {"options": [{"name": "更明亮", "intent": "整体提亮"}]},
        {
            "options": [
                {"name": "HDR增强", "intent": "HDR"},
                {"name": "更鲜艳", "intent": "色彩增强"},
                {"name": "更柔和", "intent": "柔光化"},
            ]
        },
        {
            "options": [
                {"name": "这个名字太长", "intent": "整体提亮"},
                {"name": "更鲜艳", "intent": "色彩增强"},
                {"name": "更柔和", "intent": "柔光化"},
            ]
        },
        {
            "options": [
                {"name": "更明亮", "intent": "整体提亮"},
                {"name": "更明亮", "intent": "色彩增强"},
                {"name": "更柔和", "intent": "柔光化"},
            ]
        },
    ]
    assert all(not SCHEMA_VALIDATOR(result) for result in bad_results)


def test_fallback_analysis_is_valid_and_copied():
    first = fallback_analysis()
    second = fallback_analysis()
    first["options"][0]["name"] = "改坏"
    assert SCHEMA_VALIDATOR(second)
    assert second["options"][0]["name"] == "更明亮"
