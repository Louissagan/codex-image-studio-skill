#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

if [[ " ${*:-} " == *" --help "* || " ${*:-} " == *" -h "* ]]; then
  cat <<'USAGE'
Usage: bash skills/image-studio/scripts/edit-image.sh --prompt "..." --input ./input/source.png [--mask ./mask.png] [--size 1024x1024] [--quality high] [--model gpt-image-1|/rhart-image-g-2/image-to-image] [--aspect-ratio 16:9] [--resolution 1k]
USAGE
  exit 0
fi

load_image_studio_env
require_binary
require_api_env

prompt=""
inputs=()
mask=""
size="$IMAGE_STUDIO_DEFAULT_SIZE"
quality="$IMAGE_STUDIO_DEFAULT_QUALITY"
model="$IMAGE_STUDIO_IMAGE_MODEL"
if image_studio_is_runninghub; then
  model="$IMAGE_STUDIO_RUNNINGHUB_EDIT_MODEL"
fi
output_dir="$IMAGE_STUDIO_OUTPUT_DIR"
aspect_ratio="$IMAGE_STUDIO_RUNNINGHUB_ASPECT_RATIO"
resolution="$IMAGE_STUDIO_RUNNINGHUB_RESOLUTION"
metadata="true"
raw="true"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt) prompt="${2:-}"; shift 2 ;;
    --input) inputs+=("${2:-}"); shift 2 ;;
    --mask) mask="${2:-}"; shift 2 ;;
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
Usage: bash skills/image-studio/scripts/edit-image.sh --prompt "..." --input ./input/source.png [--mask ./mask.png] [--size 1024x1024] [--quality high] [--model gpt-image-1|/rhart-image-g-2/image-to-image] [--aspect-ratio 16:9] [--resolution 1k]
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
if [[ ${#inputs[@]} -eq 0 ]]; then
  printf '输入图片不存在，请检查 --input 或 --input-dir。\n' >&2
  exit 2
fi
for input in "${inputs[@]}"; do
  if [[ ! -f "$input" ]]; then
    printf '输入图片不存在，请检查 --input 或 --input-dir: %s\n' "$input" >&2
    exit 2
  fi
done
if [[ -n "$mask" && ! -f "$mask" ]]; then
  printf '输入图片不存在，请检查 --mask: %s\n' "$mask" >&2
  exit 2
fi

resolved_output="$(resolve_output_dir "$output_dir")"
ensure_output_tree "$resolved_output"

args=(
  --mode edit
  --prompt "$prompt"
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
for input in "${inputs[@]}"; do
  args+=(--input "$input")
done
if [[ -n "$mask" ]]; then
  args+=(--mask "$mask")
fi

"$BIN_PATH" "${args[@]}"
