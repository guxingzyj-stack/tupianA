#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8000}"
APP_TOKEN="${APP_TOKEN:-dev-token-change-me}"
IMAGE_PATH="${IMAGE_PATH:-test_images/cheetah.jpg}"
OUTPUT_DIR="${OUTPUT_DIR:-smoke_output}"

if [[ ! -f "$IMAGE_PATH" ]]; then
  python scripts/make_test_image.py "$IMAGE_PATH"
fi

mkdir -p "$OUTPUT_DIR"
started_at="$(python - <<'PY'
import time
print(time.time())
PY
)"

curl -fsS "$BASE_URL/api/health" >/dev/null

curl -fsS \
  -X PUT \
  -H "Content-Type: application/json" \
  -H "X-App-Token: $APP_TOKEN" \
  -d '{"daily_budget_cny":500,"daily_video_limit":100,"enable_video":true,"enable_animate_old":true}' \
  "$BASE_URL/api/devices/smoke-device/config" >/dev/null

ANALYZE_JSON="$OUTPUT_DIR/analyze.json"
python - "$IMAGE_PATH" > "$OUTPUT_DIR/payload.json" <<'PY'
import base64, json, sys
path = sys.argv[1]
with open(path, "rb") as f:
    image = base64.b64encode(f.read()).decode("ascii")
print(json.dumps({"device_id": "smoke-device", "image": image}, ensure_ascii=False))
PY

curl -fsS \
  -H "Content-Type: application/json" \
  -H "X-App-Token: $APP_TOKEN" \
  -d @"$OUTPUT_DIR/payload.json" \
  "$BASE_URL/api/analyze" > "$ANALYZE_JSON"

mapfile -t ANALYZE_INFO < <(python scripts/smoke_json.py analyze "$ANALYZE_JSON")
JOB_ID="${ANALYZE_INFO[0]}"
BASE_IMAGE_URL="${ANALYZE_INFO[1]}"
OPTION_NAMES="${ANALYZE_INFO[2]//|/, }"

curl -fsS "$BASE_IMAGE_URL" -o "$OUTPUT_DIR/base.jpg"

curl -fsS \
  -X PUT \
  -H "Content-Type: application/json" \
  -H "X-App-Token: $APP_TOKEN" \
  -d '{"daily_budget_cny":0,"daily_video_limit":100,"enable_video":true}' \
  "$BASE_URL/api/devices/smoke-budget-device/config" >/dev/null
python - "$BASE_IMAGE_URL" > "$OUTPUT_DIR/budget_video_payload.json" <<'PY'
import json, sys
print(json.dumps({
    "device_id": "smoke-budget-device",
    "image_url": sys.argv[1],
    "motion": "slow_zoom",
}, ensure_ascii=False))
PY
BUDGET_STATUS="$(
  curl -sS \
    -H "Content-Type: application/json" \
    -H "X-App-Token: $APP_TOKEN" \
    -d @"$OUTPUT_DIR/budget_video_payload.json" \
    "$BASE_URL/api/video" \
    -o "$OUTPUT_DIR/budget_video_error.json" \
    -w "%{http_code}"
)"
if [[ "$BUDGET_STATUS" != "429" ]]; then
  echo "Expected budget check to return 429, got $BUDGET_STATUS" >&2
  exit 1
fi
python scripts/smoke_json.py budget-error "$OUTPUT_DIR/budget_video_error.json" >/dev/null

for index in 0 1 2; do
  RESPONSE="$OUTPUT_DIR/enhance_$index.json"
  curl -fsS \
    -H "Content-Type: application/json" \
    -H "X-App-Token: $APP_TOKEN" \
    -d "{\"job_id\":\"$JOB_ID\",\"option_index\":$index}" \
    "$BASE_URL/api/enhance" > "$RESPONSE"
  RESULT_URL="$(python scripts/smoke_json.py enhance "$RESPONSE")"
  curl -fsS "$RESULT_URL" -o "$OUTPUT_DIR/option_$((index + 1)).jpg"
done

wait_job() {
  local job_id="$1"
  local target="$2"
  for attempt in $(seq 0 99); do
    local status_json="$OUTPUT_DIR/job_${job_id}_${attempt}.json"
    curl -fsS \
      -H "X-App-Token: $APP_TOKEN" \
      "$BASE_URL/api/jobs/$job_id" > "$status_json"
    local result_url
    result_url="$(python scripts/smoke_json.py job-result "$status_json")"
    if [[ -n "$result_url" ]]; then
      curl -fsS "$result_url" -o "$target"
      return 0
    fi
    sleep 0.25
  done
  echo "Async job did not finish: $job_id" >&2
  return 1
}

VIDEO_CREATE_JSON="$OUTPUT_DIR/video_create.json"
python - "$BASE_IMAGE_URL" > "$OUTPUT_DIR/video_payload.json" <<'PY'
import json, sys
print(json.dumps({
    "device_id": "smoke-device",
    "image_url": sys.argv[1],
    "motion": "slow_zoom",
}, ensure_ascii=False))
PY
curl -fsS \
  -H "Content-Type: application/json" \
  -H "X-App-Token: $APP_TOKEN" \
  -d @"$OUTPUT_DIR/video_payload.json" \
  "$BASE_URL/api/video" > "$VIDEO_CREATE_JSON"
VIDEO_JOB_ID="$(python scripts/smoke_json.py create-job "$VIDEO_CREATE_JSON")"
wait_job "$VIDEO_JOB_ID" "$OUTPUT_DIR/video.mp4"

CATALOG_JSON="$OUTPUT_DIR/templates.json"
curl -fsS \
  -H "X-App-Token: $APP_TOKEN" \
  "$BASE_URL/api/templates" > "$CATALOG_JSON"
TEMPLATE_ID="$(python scripts/smoke_json.py templates "$CATALOG_JSON")"
TEMPLATE_CREATE_JSON="$OUTPUT_DIR/template_create.json"
python - "$IMAGE_PATH" "$TEMPLATE_ID" > "$OUTPUT_DIR/template_payload.json" <<'PY'
import base64, json, sys
with open(sys.argv[1], "rb") as f:
    image = base64.b64encode(f.read()).decode("ascii")
print(json.dumps({
    "device_id": "smoke-device",
    "template_id": sys.argv[2],
    "text_index": 0,
    "image": image,
}, ensure_ascii=False))
PY
curl -fsS \
  -H "Content-Type: application/json" \
  -H "X-App-Token: $APP_TOKEN" \
  -d @"$OUTPUT_DIR/template_payload.json" \
  "$BASE_URL/api/template/apply" > "$TEMPLATE_CREATE_JSON"
TEMPLATE_JOB_ID="$(python scripts/smoke_json.py create-job "$TEMPLATE_CREATE_JSON")"
wait_job "$TEMPLATE_JOB_ID" "$OUTPUT_DIR/template.mp4"

ended_at="$(python - <<'PY'
import time
print(time.time())
PY
)"
elapsed="$(python - "$started_at" "$ended_at" <<'PY'
import sys
print(f"{float(sys.argv[2]) - float(sys.argv[1]):.2f}s")
PY
)"

echo "Smoke test passed in $elapsed"
echo "Options: $OPTION_NAMES"
echo "Outputs:"
echo "  $OUTPUT_DIR/base.jpg"
echo "  $OUTPUT_DIR/option_1.jpg"
echo "  $OUTPUT_DIR/option_2.jpg"
echo "  $OUTPUT_DIR/option_3.jpg"
echo "  $OUTPUT_DIR/video.mp4"
echo "  $OUTPUT_DIR/template.mp4"
