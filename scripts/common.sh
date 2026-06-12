#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$SKILL_DIR/../.." && pwd)"
BIN_PATH="$SKILL_DIR/bin/gptcodex-image"
ENV_FILE="$SKILL_DIR/config/image-studio.env"
EXAMPLE_ENV_FILE="$SKILL_DIR/config/image-studio.example.env"

load_image_studio_env() {
  local shell_base_url="${IMAGE_STUDIO_BASE_URL:-}"
  local shell_api_key="${IMAGE_STUDIO_API_KEY:-}"
  local shell_text_model="${IMAGE_STUDIO_TEXT_MODEL:-}"
  local shell_image_model="${IMAGE_STUDIO_IMAGE_MODEL:-}"
  local shell_api_mode="${IMAGE_STUDIO_API_MODE:-}"
  local shell_output_dir="${IMAGE_STUDIO_OUTPUT_DIR:-}"
  local shell_default_size="${IMAGE_STUDIO_DEFAULT_SIZE:-}"
  local shell_default_quality="${IMAGE_STUDIO_DEFAULT_QUALITY:-}"
  local shell_timeout_seconds="${IMAGE_STUDIO_TIMEOUT_SECONDS:-}"
  local shell_max_retries="${IMAGE_STUDIO_MAX_RETRIES:-}"

  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    . "$ENV_FILE"
  fi

  IMAGE_STUDIO_BASE_URL="${shell_base_url:-${IMAGE_STUDIO_BASE_URL:-}}"
  IMAGE_STUDIO_API_KEY="${shell_api_key:-${IMAGE_STUDIO_API_KEY:-}}"
  IMAGE_STUDIO_TEXT_MODEL="${shell_text_model:-${IMAGE_STUDIO_TEXT_MODEL:-gpt-4.1}}"
  IMAGE_STUDIO_IMAGE_MODEL="${shell_image_model:-${IMAGE_STUDIO_IMAGE_MODEL:-gpt-image-1}}"
  IMAGE_STUDIO_API_MODE="${shell_api_mode:-${IMAGE_STUDIO_API_MODE:-images}}"
  IMAGE_STUDIO_OUTPUT_DIR="${shell_output_dir:-${IMAGE_STUDIO_OUTPUT_DIR:-$SKILL_DIR/outputs}}"
  IMAGE_STUDIO_DEFAULT_SIZE="${shell_default_size:-${IMAGE_STUDIO_DEFAULT_SIZE:-1024x1024}}"
  IMAGE_STUDIO_DEFAULT_QUALITY="${shell_default_quality:-${IMAGE_STUDIO_DEFAULT_QUALITY:-high}}"
  IMAGE_STUDIO_TIMEOUT_SECONDS="${shell_timeout_seconds:-${IMAGE_STUDIO_TIMEOUT_SECONDS:-300}}"
  IMAGE_STUDIO_MAX_RETRIES="${shell_max_retries:-${IMAGE_STUDIO_MAX_RETRIES:-2}}"

  export IMAGE_STUDIO_BASE_URL
  export IMAGE_STUDIO_API_KEY
  export IMAGE_STUDIO_TEXT_MODEL
  export IMAGE_STUDIO_IMAGE_MODEL
  export IMAGE_STUDIO_API_MODE
  export IMAGE_STUDIO_OUTPUT_DIR
  export IMAGE_STUDIO_DEFAULT_SIZE
  export IMAGE_STUDIO_DEFAULT_QUALITY
  export IMAGE_STUDIO_TIMEOUT_SECONDS
  export IMAGE_STUDIO_MAX_RETRIES
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
    printf '请先运行: bash skills/image-studio/scripts/install.sh\n' >&2
    return 1
  fi
}

require_api_env() {
  if [[ -z "$IMAGE_STUDIO_BASE_URL" ]]; then
    printf '缺少 IMAGE_STUDIO_BASE_URL。请配置 %s\n' "$ENV_FILE" >&2
    return 1
  fi
  if [[ -z "$IMAGE_STUDIO_API_KEY" || "$IMAGE_STUDIO_API_KEY" == "replace_with_your_api_key" ]]; then
    printf '缺少 IMAGE_STUDIO_API_KEY。请配置 %s\n' "$ENV_FILE" >&2
    return 1
  fi
  if [[ -z "$IMAGE_STUDIO_IMAGE_MODEL" ]]; then
    printf '缺少 IMAGE_STUDIO_IMAGE_MODEL。请配置 %s\n' "$ENV_FILE" >&2
    return 1
  fi
}

print_config_hint() {
  printf '独立配置文件: %s\n' "$ENV_FILE"
  printf '示例配置文件: %s\n' "$EXAMPLE_ENV_FILE"
}
