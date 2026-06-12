#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

load_image_studio_env

status=0

check_nonempty() {
  local name="$1"
  local value="${!name:-}"
  if [[ -z "$value" ]]; then
    printf 'FAIL %s is not set\n' "$name" >&2
    status=1
  elif [[ "$name" == "IMAGE_STUDIO_API_KEY" && "$value" == "replace_with_your_api_key" ]]; then
    printf 'FAIL %s still uses the example placeholder\n' "$name" >&2
    status=1
  else
    printf 'OK   %s\n' "$name"
  fi
}

check_nonempty IMAGE_STUDIO_BASE_URL
check_nonempty IMAGE_STUDIO_API_KEY
check_nonempty IMAGE_STUDIO_IMAGE_MODEL
check_nonempty IMAGE_STUDIO_OUTPUT_DIR

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
exit "$status"
