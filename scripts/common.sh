#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ "$(basename "$SKILL_DIR")" == "image-studio" && "$(basename "$(dirname "$SKILL_DIR")")" == "skills" ]]; then
  PROJECT_ROOT="$(cd "$SKILL_DIR/../.." && pwd)"
else
  PROJECT_ROOT="$SKILL_DIR"
fi
BIN_PATH="$SKILL_DIR/bin/gptcodex-image"
ENV_FILE="$SKILL_DIR/config/image-studio.env"
EXAMPLE_ENV_FILE="$SKILL_DIR/config/image-studio.example.env"
CONFIG_SCRIPT="$SKILL_DIR/scripts/configure-env.sh"
CONFIG_GUI_SCRIPT="$SKILL_DIR/scripts/configure-env-gui.sh"

load_image_studio_env() {
  local shell_base_url="${IMAGE_STUDIO_BASE_URL:-}"
  local shell_api_key="${IMAGE_STUDIO_API_KEY:-}"
  local shell_api_key_source="${IMAGE_STUDIO_API_KEY_SOURCE:-}"
  local shell_keychain_service="${IMAGE_STUDIO_KEYCHAIN_SERVICE:-}"
  local shell_keychain_account="${IMAGE_STUDIO_KEYCHAIN_ACCOUNT:-}"
  local shell_runninghub_api_key="${RUNNINGHUB_API_KEY:-}"
  local shell_provider="${IMAGE_STUDIO_PROVIDER:-}"
  local shell_text_model="${IMAGE_STUDIO_TEXT_MODEL:-}"
  local shell_image_model="${IMAGE_STUDIO_IMAGE_MODEL:-}"
  local shell_api_mode="${IMAGE_STUDIO_API_MODE:-}"
  local shell_output_dir="${IMAGE_STUDIO_OUTPUT_DIR:-}"
  local shell_default_size="${IMAGE_STUDIO_DEFAULT_SIZE:-}"
  local shell_default_quality="${IMAGE_STUDIO_DEFAULT_QUALITY:-}"
  local shell_runninghub_aspect_ratio="${IMAGE_STUDIO_RUNNINGHUB_ASPECT_RATIO:-}"
  local shell_runninghub_resolution="${IMAGE_STUDIO_RUNNINGHUB_RESOLUTION:-}"
  local shell_runninghub_text_model="${IMAGE_STUDIO_RUNNINGHUB_TEXT_MODEL:-}"
  local shell_runninghub_edit_model="${IMAGE_STUDIO_RUNNINGHUB_EDIT_MODEL:-}"
  local shell_runninghub_max_wait_seconds="${IMAGE_STUDIO_RUNNINGHUB_MAX_WAIT_SECONDS:-}"
  local shell_timeout_seconds="${IMAGE_STUDIO_TIMEOUT_SECONDS:-}"
  local shell_max_retries="${IMAGE_STUDIO_MAX_RETRIES:-}"

  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    . "$ENV_FILE"
  fi

  IMAGE_STUDIO_BASE_URL="${shell_base_url:-${IMAGE_STUDIO_BASE_URL:-}}"
  IMAGE_STUDIO_API_KEY="${shell_api_key:-${IMAGE_STUDIO_API_KEY:-}}"
  IMAGE_STUDIO_API_KEY_SOURCE="${shell_api_key_source:-${IMAGE_STUDIO_API_KEY_SOURCE:-}}"
  IMAGE_STUDIO_KEYCHAIN_SERVICE="${shell_keychain_service:-${IMAGE_STUDIO_KEYCHAIN_SERVICE:-codex-image-studio}}"
  IMAGE_STUDIO_KEYCHAIN_ACCOUNT="${shell_keychain_account:-${IMAGE_STUDIO_KEYCHAIN_ACCOUNT:-}}"
  IMAGE_STUDIO_PROVIDER="${shell_provider:-${IMAGE_STUDIO_PROVIDER:-auto}}"
  IMAGE_STUDIO_TEXT_MODEL="${shell_text_model:-${IMAGE_STUDIO_TEXT_MODEL:-gpt-4.1}}"
  IMAGE_STUDIO_API_MODE="${shell_api_mode:-${IMAGE_STUDIO_API_MODE:-images}}"
  IMAGE_STUDIO_OUTPUT_DIR="${shell_output_dir:-${IMAGE_STUDIO_OUTPUT_DIR:-$SKILL_DIR/outputs}}"
  IMAGE_STUDIO_RUNNINGHUB_ASPECT_RATIO="${shell_runninghub_aspect_ratio:-${IMAGE_STUDIO_RUNNINGHUB_ASPECT_RATIO:-}}"
  IMAGE_STUDIO_RUNNINGHUB_RESOLUTION="${shell_runninghub_resolution:-${IMAGE_STUDIO_RUNNINGHUB_RESOLUTION:-}}"
  IMAGE_STUDIO_RUNNINGHUB_TEXT_MODEL="${shell_runninghub_text_model:-${IMAGE_STUDIO_RUNNINGHUB_TEXT_MODEL:-/rhart-image-g-2-official/text-to-image}}"
  IMAGE_STUDIO_RUNNINGHUB_EDIT_MODEL="${shell_runninghub_edit_model:-${IMAGE_STUDIO_RUNNINGHUB_EDIT_MODEL:-/rhart-image-g-2/image-to-image}}"
  IMAGE_STUDIO_RUNNINGHUB_MAX_WAIT_SECONDS="${shell_runninghub_max_wait_seconds:-${IMAGE_STUDIO_RUNNINGHUB_MAX_WAIT_SECONDS:-1800}}"
  IMAGE_STUDIO_TIMEOUT_SECONDS="${shell_timeout_seconds:-${IMAGE_STUDIO_TIMEOUT_SECONDS:-300}}"
  IMAGE_STUDIO_MAX_RETRIES="${shell_max_retries:-${IMAGE_STUDIO_MAX_RETRIES:-2}}"

  if image_studio_is_runninghub && [[ -n "${shell_runninghub_api_key:-${RUNNINGHUB_API_KEY:-}}" ]]; then
    if [[ -z "$IMAGE_STUDIO_API_KEY" || "$IMAGE_STUDIO_API_KEY" == replace_with_* ]]; then
      IMAGE_STUDIO_API_KEY="${shell_runninghub_api_key:-${RUNNINGHUB_API_KEY:-}}"
    fi
  fi

  if image_studio_is_placeholder "$IMAGE_STUDIO_API_KEY"; then
    local keychain_api_key=""
    keychain_api_key="$(image_studio_read_keychain_api_key || true)"
    if [[ -n "$keychain_api_key" ]]; then
      IMAGE_STUDIO_API_KEY="$keychain_api_key"
    fi
  fi

  if image_studio_is_runninghub; then
    IMAGE_STUDIO_IMAGE_MODEL="${shell_image_model:-${IMAGE_STUDIO_IMAGE_MODEL:-}}"
    if [[ -z "$shell_image_model" && "${IMAGE_STUDIO_IMAGE_MODEL:-}" == gpt-image-* ]]; then
      IMAGE_STUDIO_IMAGE_MODEL=""
    fi
    IMAGE_STUDIO_DEFAULT_SIZE="${shell_default_size:-${IMAGE_STUDIO_DEFAULT_SIZE:-}}"
    if [[ -z "$shell_default_size" && "${IMAGE_STUDIO_DEFAULT_SIZE:-}" == "1024x1024" ]]; then
      IMAGE_STUDIO_DEFAULT_SIZE=""
    fi
    IMAGE_STUDIO_DEFAULT_QUALITY="${shell_default_quality:-${IMAGE_STUDIO_DEFAULT_QUALITY:-}}"
    if [[ -z "$shell_default_quality" && "${IMAGE_STUDIO_DEFAULT_QUALITY:-}" == "high" ]]; then
      IMAGE_STUDIO_DEFAULT_QUALITY=""
    fi
  else
    IMAGE_STUDIO_IMAGE_MODEL="${shell_image_model:-${IMAGE_STUDIO_IMAGE_MODEL:-gpt-image-2}}"
    IMAGE_STUDIO_DEFAULT_SIZE="${shell_default_size:-${IMAGE_STUDIO_DEFAULT_SIZE:-1024x1024}}"
    IMAGE_STUDIO_DEFAULT_QUALITY="${shell_default_quality:-${IMAGE_STUDIO_DEFAULT_QUALITY:-high}}"
  fi

  export IMAGE_STUDIO_BASE_URL
  export IMAGE_STUDIO_API_KEY
  export IMAGE_STUDIO_API_KEY_SOURCE
  export IMAGE_STUDIO_KEYCHAIN_SERVICE
  export IMAGE_STUDIO_KEYCHAIN_ACCOUNT
  export IMAGE_STUDIO_PROVIDER
  export IMAGE_STUDIO_TEXT_MODEL
  export IMAGE_STUDIO_IMAGE_MODEL
  export IMAGE_STUDIO_API_MODE
  export IMAGE_STUDIO_OUTPUT_DIR
  export IMAGE_STUDIO_DEFAULT_SIZE
  export IMAGE_STUDIO_DEFAULT_QUALITY
  export IMAGE_STUDIO_RUNNINGHUB_ASPECT_RATIO
  export IMAGE_STUDIO_RUNNINGHUB_RESOLUTION
  export IMAGE_STUDIO_RUNNINGHUB_TEXT_MODEL
  export IMAGE_STUDIO_RUNNINGHUB_EDIT_MODEL
  export IMAGE_STUDIO_RUNNINGHUB_MAX_WAIT_SECONDS
  export IMAGE_STUDIO_TIMEOUT_SECONDS
  export IMAGE_STUDIO_MAX_RETRIES
}

image_studio_is_runninghub() {
  local provider
  provider="$(printf '%s' "${IMAGE_STUDIO_PROVIDER:-auto}" | tr '[:upper:]' '[:lower:]')"
  local base_url
  base_url="$(printf '%s' "${IMAGE_STUDIO_BASE_URL:-}" | tr '[:upper:]' '[:lower:]')"
  [[ "$provider" == "runninghub" || ( "$provider" == "auto" && "$base_url" == *runninghub* ) ]]
}

resolve_output_dir() {
  local dir="$1"
  if [[ "$dir" == /* ]]; then
    printf '%s\n' "$dir"
  elif [[ "$dir" == ./* ]]; then
    printf '%s/%s\n' "$PROJECT_ROOT" "${dir#./}"
  else
    printf '%s/%s\n' "$PROJECT_ROOT" "$dir"
  fi
}

ensure_output_tree() {
  local output_dir="$1"
  mkdir -p "$output_dir/images" "$output_dir/metadata" "$output_dir/logs" "$output_dir/raw"
}

require_binary() {
  if [[ ! -x "$BIN_PATH" ]]; then
    printf '缺少 Image Studio CLI: %s\n' "$BIN_PATH" >&2
    printf '请先运行: bash %s/scripts/install.sh\n' "$SKILL_DIR" >&2
    return 1
  fi
}

image_studio_is_placeholder() {
  local value="${1:-}"
  [[ -z "$value" || "$value" == replace_with_* || "$value" == *_HERE ]]
}

image_studio_read_keychain_api_key() {
  local source service account
  source="$(printf '%s' "${IMAGE_STUDIO_API_KEY_SOURCE:-}" | tr '[:upper:]' '[:lower:]')"
  service="${IMAGE_STUDIO_KEYCHAIN_SERVICE:-codex-image-studio}"
  account="${IMAGE_STUDIO_KEYCHAIN_ACCOUNT:-}"

  if [[ -z "$account" ]]; then
    if image_studio_is_runninghub; then
      account="runninghub"
    else
      account="openai"
    fi
  fi

  if [[ "$source" != "keychain" && -z "${IMAGE_STUDIO_KEYCHAIN_ACCOUNT:-}" ]]; then
    return 1
  fi
  if ! command -v security >/dev/null 2>&1; then
    return 1
  fi

  security find-generic-password -a "$account" -s "$service" -w 2>/dev/null
}

require_api_env() {
  if [[ -z "$IMAGE_STUDIO_BASE_URL" ]]; then
    printf '缺少 IMAGE_STUDIO_BASE_URL。请配置 %s\n' "$ENV_FILE" >&2
    print_setup_hint >&2
    return 1
  fi
  if image_studio_is_placeholder "$IMAGE_STUDIO_API_KEY"; then
    printf '缺少 IMAGE_STUDIO_API_KEY。请配置 %s\n' "$ENV_FILE" >&2
    print_setup_hint >&2
    return 1
  fi
}

print_config_hint() {
  printf 'Provider: %s\n' "${IMAGE_STUDIO_PROVIDER:-auto}"
  printf '独立配置文件: %s\n' "$ENV_FILE"
  printf '示例配置文件: %s\n' "$EXAMPLE_ENV_FILE"
}

print_setup_hint() {
  printf 'Image Studio provider configuration is incomplete.\n'
  printf 'Preferred secure setup wizard: bash %s\n' "$CONFIG_GUI_SCRIPT"
  printf 'Interactive setup wizard: bash %s\n' "$CONFIG_SCRIPT"
  printf 'Manual template: cp %s %s\n' "$EXAMPLE_ENV_FILE" "$ENV_FILE"
  printf 'Then edit the private env file or use Keychain-backed GUI setup: %s\n' "$ENV_FILE"
  printf 'Then verify: bash %s/scripts/check-env.sh\n' "$SKILL_DIR"
}
