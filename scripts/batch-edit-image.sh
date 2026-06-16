#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

if [[ " ${*:-} " == *" --help "* || " ${*:-} " == *" -h "* ]]; then
  cat <<'USAGE'
Usage: bash skills/image-studio/scripts/batch-edit-image.sh --prompt "..." --input-dir ./input/images [--model /rhart-image-g-2/image-to-image] [--aspect-ratio 16:9] [--resolution 1k] [--output-dir ./skills/image-studio/outputs/batch]
USAGE
  exit 0
fi

load_image_studio_env
require_binary
require_api_env

prompt=""
input_dir=""
size="$IMAGE_STUDIO_DEFAULT_SIZE"
quality="$IMAGE_STUDIO_DEFAULT_QUALITY"
model="$IMAGE_STUDIO_IMAGE_MODEL"
if image_studio_is_runninghub; then
  model="$IMAGE_STUDIO_RUNNINGHUB_EDIT_MODEL"
fi
output_dir="$IMAGE_STUDIO_OUTPUT_DIR/batch"
aspect_ratio="$IMAGE_STUDIO_RUNNINGHUB_ASPECT_RATIO"
resolution="$IMAGE_STUDIO_RUNNINGHUB_RESOLUTION"
metadata="true"
raw="true"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt) prompt="${2:-}"; shift 2 ;;
    --input-dir) input_dir="${2:-}"; shift 2 ;;
    --size) size="${2:-}"; shift 2 ;;
    --quality) quality="${2:-}"; shift 2 ;;
    --aspect-ratio) aspect_ratio="${2:-}"; shift 2 ;;
    --resolution) resolution="${2:-}"; shift 2 ;;
    --model) model="${2:-}"; shift 2 ;;
    --output-dir) output_dir="${2:-}"; shift 2 ;;
    --metadata) metadata="true"; shift ;;
    --no-metadata) metadata="false"; shift ;;
    --raw) raw="true"; shift ;;
    --no-raw) raw="false"; shift ;;
    -h|--help)
      cat <<'USAGE'
Usage: bash skills/image-studio/scripts/batch-edit-image.sh --prompt "..." --input-dir ./input/images [--model /rhart-image-g-2/image-to-image] [--aspect-ratio 16:9] [--resolution 1k] [--output-dir ./skills/image-studio/outputs/batch]
USAGE
      exit 0
      ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [[ -z "$prompt" ]]; then
  printf '--prompt is required\n' >&2
  exit 2
fi
if [[ -z "$input_dir" || ! -d "$input_dir" ]]; then
  printf '输入图片不存在，请检查 --input 或 --input-dir。\n' >&2
  exit 2
fi

resolved_output="$(resolve_output_dir "$output_dir")"
ensure_output_tree "$resolved_output"

success=0
failed=0
batch_log="$resolved_output/logs/batch-$(date +%Y%m%d-%H%M%S).log"
: > "$batch_log"

while IFS= read -r image; do
  args=(
    --mode edit
    --prompt "$prompt"
    --input "$image"
    --provider "$IMAGE_STUDIO_PROVIDER"
    --model "$model"
    --base-url "$IMAGE_STUDIO_BASE_URL"
    --api-key "$IMAGE_STUDIO_API_KEY"
    --output-dir "$resolved_output"
    --metadata="$metadata"
    --raw="$raw"
    --timeout "$IMAGE_STUDIO_TIMEOUT_SECONDS"
    --max-retries "$IMAGE_STUDIO_MAX_RETRIES"
    --runninghub-max-wait "$IMAGE_STUDIO_RUNNINGHUB_MAX_WAIT_SECONDS"
  )
  if image_studio_is_runninghub; then
    [[ -n "$aspect_ratio" ]] && args+=(--aspect-ratio "$aspect_ratio")
    [[ -n "$resolution" ]] && args+=(--resolution "$resolution")
  else
    args+=(--size "$size" --quality "$quality")
  fi

  if "$BIN_PATH" "${args[@]}" >> "$batch_log" 2>&1; then
    success=$((success + 1))
  else
    failed=$((failed + 1))
    printf 'FAILED %s\n' "$image" >> "$batch_log"
  fi
done < <(find "$input_dir" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) | sort)

printf '成功数量: %d\n' "$success"
printf '失败数量: %d\n' "$failed"
printf '输出目录: %s\n' "$resolved_output"
printf '批处理日志: %s\n' "$batch_log"

if [[ "$success" -eq 0 && "$failed" -eq 0 ]]; then
  printf '输入图片不存在，请检查 --input 或 --input-dir。\n' >&2
  exit 2
fi
