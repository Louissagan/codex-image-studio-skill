#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

load_image_studio_env

status=0

if [[ -f "$ENV_FILE" ]]; then
  printf 'OK   private env file exists: %s\n' "$ENV_FILE"
else
  printf 'WARN private env file is missing: %s\n' "$ENV_FILE" >&2
fi

check_nonempty() {
  local name="$1"
  local value="${!name:-}"
  if [[ -z "$value" ]]; then
    printf 'FAIL %s is not set\n' "$name" >&2
    status=1
  elif [[ "$name" == "IMAGE_STUDIO_API_KEY" ]] && image_studio_is_placeholder "$value"; then
    printf 'FAIL %s still uses the example placeholder\n' "$name" >&2
    status=1
  else
    printf 'OK   %s\n' "$name"
  fi
}

check_nonempty IMAGE_STUDIO_BASE_URL
check_nonempty IMAGE_STUDIO_API_KEY
check_nonempty IMAGE_STUDIO_PROVIDER
check_nonempty IMAGE_STUDIO_OUTPUT_DIR

case "$(printf '%s' "$IMAGE_STUDIO_PROVIDER" | tr '[:upper:]' '[:lower:]')" in
  auto|openai|runninghub)
    printf 'OK   IMAGE_STUDIO_PROVIDER value is supported\n'
    ;;
  *)
    printf 'FAIL IMAGE_STUDIO_PROVIDER must be auto, openai, or runninghub\n' >&2
    status=1
    ;;
esac

if image_studio_is_runninghub; then
  printf 'OK   Running Hub mode detected\n'
  check_nonempty IMAGE_STUDIO_RUNNINGHUB_TEXT_MODEL
  check_nonempty IMAGE_STUDIO_RUNNINGHUB_EDIT_MODEL
  if [[ "$IMAGE_STUDIO_RUNNINGHUB_TEXT_MODEL" != "/rhart-image-g-2-official/text-to-image" ]]; then
    printf 'FAIL IMAGE_STUDIO_RUNNINGHUB_TEXT_MODEL must be /rhart-image-g-2-official/text-to-image\n' >&2
    status=1
  else
    printf 'OK   IMAGE_STUDIO_RUNNINGHUB_TEXT_MODEL=%s\n' "$IMAGE_STUDIO_RUNNINGHUB_TEXT_MODEL"
  fi
  if [[ "$IMAGE_STUDIO_RUNNINGHUB_EDIT_MODEL" != "/rhart-image-g-2/image-to-image" ]]; then
    printf 'FAIL IMAGE_STUDIO_RUNNINGHUB_EDIT_MODEL must be /rhart-image-g-2/image-to-image\n' >&2
    status=1
  else
    printf 'OK   IMAGE_STUDIO_RUNNINGHUB_EDIT_MODEL=%s\n' "$IMAGE_STUDIO_RUNNINGHUB_EDIT_MODEL"
  fi
  [[ -n "${IMAGE_STUDIO_RUNNINGHUB_ASPECT_RATIO:-}" ]] && printf 'OK   IMAGE_STUDIO_RUNNINGHUB_ASPECT_RATIO=%s\n' "$IMAGE_STUDIO_RUNNINGHUB_ASPECT_RATIO"
  [[ -n "${IMAGE_STUDIO_RUNNINGHUB_RESOLUTION:-}" ]] && printf 'OK   IMAGE_STUDIO_RUNNINGHUB_RESOLUTION=%s\n' "$IMAGE_STUDIO_RUNNINGHUB_RESOLUTION"
  printf 'OK   IMAGE_STUDIO_RUNNINGHUB_MAX_WAIT_SECONDS=%s\n' "$IMAGE_STUDIO_RUNNINGHUB_MAX_WAIT_SECONDS"
else
  check_nonempty IMAGE_STUDIO_IMAGE_MODEL
fi

if [[ -x "$BIN_PATH" ]]; then
  printf 'OK   CLI binary: %s\n' "$BIN_PATH"
else
  printf 'FAIL CLI binary missing or not executable: %s\n' "$BIN_PATH" >&2
  status=1
fi

resolved_output="$(resolve_output_dir "$IMAGE_STUDIO_OUTPUT_DIR")"
if mkdir -p "$resolved_output/images" "$resolved_output/metadata" "$resolved_output/logs" "$resolved_output/raw"; then
  printf 'OK   outputs directory: %s\n' "$resolved_output"
else
  printf 'FAIL outputs directory cannot be created: %s\n' "$resolved_output" >&2
  status=1
fi

write_test="$resolved_output/.image-studio-write-test"
if printf 'ok' > "$write_test" 2>/dev/null; then
  rm -f "$write_test"
  printf 'OK   current output directory is writable\n'
else
  printf 'FAIL 输出目录不可写，请检查权限。\n' >&2
  status=1
fi

print_config_hint
if [[ "$status" -ne 0 ]]; then
  printf '\n' >&2
  print_setup_hint >&2
fi
exit "$status"
