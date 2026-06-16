#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$SKILL_DIR/config/image-studio.env"
EXAMPLE_ENV_FILE="$SKILL_DIR/config/image-studio.example.env"

usage() {
  cat <<USAGE
Image Studio Skill configuration wizard

This writes the private provider configuration file:
  $ENV_FILE

Real API keys belong only in that private file or in shell environment
variables. Never put real keys in:
  $EXAMPLE_ENV_FILE

Usage:
  bash skills/image-studio/scripts/configure-env.sh

USAGE
}

is_placeholder() {
  local value="${1:-}"
  [[ -z "$value" || "$value" == replace_with_* || "$value" == *_HERE ]]
}

quote_env_value() {
  printf '%q' "${1:-}"
}

prompt_value() {
  local label="$1"
  local default="${2:-}"
  local value=""
  if [[ -n "$default" ]]; then
    printf '%s [%s]: ' "$label" "$default" >&2
  else
    printf '%s: ' "$label" >&2
  fi
  IFS= read -r value
  printf '%s' "${value:-$default}"
}

prompt_secret() {
  local label="$1"
  local default="${2:-}"
  local value=""
  if ! is_placeholder "$default"; then
    printf '%s [press Enter to keep existing key]: ' "$label" >&2
  else
    printf '%s: ' "$label" >&2
  fi
  IFS= read -r -s value
  printf '\n' >&2
  printf '%s' "${value:-$default}"
}

prompt_required() {
  local label="$1"
  local default="${2:-}"
  local value=""
  while true; do
    value="$(prompt_value "$label" "$default")"
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return 0
    fi
    printf 'This value is required.\n' >&2
  done
}

prompt_required_secret() {
  local label="$1"
  local default="${2:-}"
  local value=""
  while true; do
    value="$(prompt_secret "$label" "$default")"
    if ! is_placeholder "$value"; then
      printf '%s' "$value"
      return 0
    fi
    printf 'API key is required.\n' >&2
    default=""
  done
}

write_env_line() {
  local name="$1"
  local value="${2:-}"
  printf '%s=%s\n' "$name" "$(quote_env_value "$value")"
}

write_common_tail() {
  local output_dir="$1"
  local timeout_seconds="$2"
  local max_retries="$3"
  write_env_line IMAGE_STUDIO_TEXT_MODEL "gpt-4.1"
  write_env_line IMAGE_STUDIO_API_MODE "images"
  write_env_line IMAGE_STUDIO_OUTPUT_DIR "$output_dir"
  write_env_line IMAGE_STUDIO_TIMEOUT_SECONDS "$timeout_seconds"
  write_env_line IMAGE_STUDIO_MAX_RETRIES "$max_retries"
}

load_existing_env() {
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    . "$ENV_FILE"
  fi
}

existing_config_is_runninghub() {
  local provider base_url
  provider="$(printf '%s' "${IMAGE_STUDIO_PROVIDER:-}" | tr '[:upper:]' '[:lower:]')"
  base_url="$(printf '%s' "${IMAGE_STUDIO_BASE_URL:-}" | tr '[:upper:]' '[:lower:]')"
  [[ "$provider" == "runninghub" || "$base_url" == *runninghub* ]]
}

existing_config_is_openai() {
  local provider base_url
  provider="$(printf '%s' "${IMAGE_STUDIO_PROVIDER:-}" | tr '[:upper:]' '[:lower:]')"
  base_url="$(printf '%s' "${IMAGE_STUDIO_BASE_URL:-}" | tr '[:upper:]' '[:lower:]')"
  [[ "$provider" == "openai" || ( -n "$base_url" && "$base_url" != *runninghub* ) ]]
}

choose_provider() {
  local existing="${IMAGE_STUDIO_PROVIDER:-runninghub}"
  local default_choice="1"
  if [[ "$(printf '%s' "$existing" | tr '[:upper:]' '[:lower:]')" == "openai" ]]; then
    default_choice="2"
  fi

  cat >&2 <<'MENU'
Choose an image provider:
  1) Running Hub gpt-image-2 (recommended for this skill)
  2) OpenAI-compatible relay / 中转站
MENU

  local choice=""
  while true; do
    printf 'Provider [%s]: ' "$default_choice" >&2
    IFS= read -r choice
    choice="${choice:-$default_choice}"
    case "$(printf '%s' "$choice" | tr '[:upper:]' '[:lower:]')" in
      1|runninghub|running-hub|rh) printf 'runninghub'; return 0 ;;
      2|openai|relay|中转站) printf 'openai'; return 0 ;;
      *) printf 'Please choose 1 or 2.\n' >&2 ;;
    esac
  done
}

write_runninghub_env() {
  local base_url api_key aspect_ratio resolution max_wait output_dir
  local base_default key_default aspect_default resolution_default wait_default
  base_default="https://www.runninghub.cn"
  key_default="${RUNNINGHUB_API_KEY:-}"
  aspect_default="16:9"
  resolution_default="1k"
  wait_default="1800"
  if existing_config_is_runninghub; then
    base_default="${IMAGE_STUDIO_BASE_URL:-$base_default}"
    key_default="${IMAGE_STUDIO_API_KEY:-$key_default}"
    aspect_default="${IMAGE_STUDIO_RUNNINGHUB_ASPECT_RATIO:-$aspect_default}"
    resolution_default="${IMAGE_STUDIO_RUNNINGHUB_RESOLUTION:-$resolution_default}"
    wait_default="${IMAGE_STUDIO_RUNNINGHUB_MAX_WAIT_SECONDS:-$wait_default}"
  fi

  base_url="$(prompt_required 'Running Hub base URL' "$base_default")"
  api_key="$(prompt_required_secret 'Running Hub API key (writes IMAGE_STUDIO_API_KEY)' "$key_default")"
  aspect_ratio="$(prompt_value 'Default aspect ratio' "$aspect_default")"
  resolution="$(prompt_value 'Default resolution' "$resolution_default")"
  max_wait="$(prompt_value 'Max wait seconds for Running Hub tasks' "$wait_default")"
  output_dir="$(prompt_value 'Output directory' "${IMAGE_STUDIO_OUTPUT_DIR:-./skills/image-studio/outputs}")"

  {
    printf '# Image Studio private environment. Do not commit this file.\n'
    printf '# Provider: Running Hub gpt-image-2 only.\n\n'
    write_env_line IMAGE_STUDIO_PROVIDER runninghub
    write_env_line IMAGE_STUDIO_BASE_URL "$base_url"
    printf '# FINAL API KEY LOCATION / 最终填写 Running Hub API key 的地方：\n'
    write_env_line IMAGE_STUDIO_API_KEY "$api_key"
    printf '# Running Hub is restricted to these two gpt-image-2 endpoints.\n'
    write_env_line IMAGE_STUDIO_RUNNINGHUB_TEXT_MODEL /rhart-image-g-2-official/text-to-image
    write_env_line IMAGE_STUDIO_RUNNINGHUB_EDIT_MODEL /rhart-image-g-2/image-to-image
    write_env_line IMAGE_STUDIO_RUNNINGHUB_ASPECT_RATIO "$aspect_ratio"
    write_env_line IMAGE_STUDIO_RUNNINGHUB_RESOLUTION "$resolution"
    write_env_line IMAGE_STUDIO_RUNNINGHUB_MAX_WAIT_SECONDS "$max_wait"
    write_env_line IMAGE_STUDIO_IMAGE_MODEL ""
    write_env_line IMAGE_STUDIO_DEFAULT_SIZE ""
    write_env_line IMAGE_STUDIO_DEFAULT_QUALITY ""
    write_common_tail "$output_dir" "${IMAGE_STUDIO_TIMEOUT_SECONDS:-300}" "${IMAGE_STUDIO_MAX_RETRIES:-2}"
  } > "$ENV_FILE"
}

write_openai_env() {
  local base_url api_key image_model size quality timeout_seconds max_retries output_dir
  local base_default key_default model_default size_default quality_default
  base_default="https://relay.example.com/v1"
  key_default=""
  model_default="gpt-image-1"
  size_default="1024x1024"
  quality_default="high"
  if existing_config_is_openai; then
    base_default="${IMAGE_STUDIO_BASE_URL:-$base_default}"
    key_default="${IMAGE_STUDIO_API_KEY:-$key_default}"
    model_default="${IMAGE_STUDIO_IMAGE_MODEL:-$model_default}"
    size_default="${IMAGE_STUDIO_DEFAULT_SIZE:-$size_default}"
    quality_default="${IMAGE_STUDIO_DEFAULT_QUALITY:-$quality_default}"
  fi

  base_url="$(prompt_required 'Relay OpenAI-compatible BASE_URL / 中转站 BASE_URL' "$base_default")"
  api_key="$(prompt_required_secret 'Relay API key (writes IMAGE_STUDIO_API_KEY) / 中转站 API key' "$key_default")"
  image_model="$(prompt_required 'Relay image model / 中转站图像模型名' "$model_default")"
  size="$(prompt_value 'Default image size' "$size_default")"
  quality="$(prompt_value 'Default image quality' "$quality_default")"
  timeout_seconds="$(prompt_value 'Request timeout seconds' "${IMAGE_STUDIO_TIMEOUT_SECONDS:-300}")"
  max_retries="$(prompt_value 'Max retries' "${IMAGE_STUDIO_MAX_RETRIES:-2}")"
  output_dir="$(prompt_value 'Output directory' "${IMAGE_STUDIO_OUTPUT_DIR:-./skills/image-studio/outputs}")"

  {
    printf '# Image Studio private environment. Do not commit this file.\n'
    printf '# Provider: OpenAI-compatible relay / 中转站.\n\n'
    write_env_line IMAGE_STUDIO_PROVIDER openai
    printf '# REQUIRED relay config / 中转站必填配置：\n'
    write_env_line IMAGE_STUDIO_BASE_URL "$base_url"
    printf '# FINAL API KEY LOCATION / 最终填写中转站 API key 的地方：\n'
    write_env_line IMAGE_STUDIO_API_KEY "$api_key"
    write_env_line IMAGE_STUDIO_IMAGE_MODEL "$image_model"
    printf '# Optional relay defaults / 中转站可选默认值：\n'
    write_env_line IMAGE_STUDIO_DEFAULT_SIZE "$size"
    write_env_line IMAGE_STUDIO_DEFAULT_QUALITY "$quality"
    write_env_line IMAGE_STUDIO_RUNNINGHUB_TEXT_MODEL /rhart-image-g-2-official/text-to-image
    write_env_line IMAGE_STUDIO_RUNNINGHUB_EDIT_MODEL /rhart-image-g-2/image-to-image
    write_env_line IMAGE_STUDIO_RUNNINGHUB_ASPECT_RATIO ""
    write_env_line IMAGE_STUDIO_RUNNINGHUB_RESOLUTION ""
    write_env_line IMAGE_STUDIO_RUNNINGHUB_MAX_WAIT_SECONDS 1800
    write_common_tail "$output_dir" "$timeout_seconds" "$max_retries"
  } > "$ENV_FILE"
}

main() {
  if [[ " ${*:-} " == *" --help "* || " ${*:-} " == *" -h "* ]]; then
    usage
    exit 0
  fi

  if [[ ! -t 0 || ! -t 1 ]]; then
    printf 'This configuration wizard is interactive. Run it in a terminal:\n' >&2
    printf '  bash %s\n' "$0" >&2
    printf 'Or copy %s to %s and edit it manually.\n' "$EXAMPLE_ENV_FILE" "$ENV_FILE" >&2
    exit 2
  fi

  mkdir -p "$(dirname "$ENV_FILE")"
  load_existing_env

  if [[ -f "$ENV_FILE" ]]; then
    local backup="$ENV_FILE.backup.$(date +%Y%m%d-%H%M%S)"
    cp "$ENV_FILE" "$backup"
    chmod 600 "$backup" 2>/dev/null || true
    printf 'Existing config backed up to: %s\n' "$backup"
  fi

  local provider
  provider="$(choose_provider)"
  if [[ "$provider" == "runninghub" ]]; then
    write_runninghub_env
  else
    write_openai_env
  fi
  chmod 600 "$ENV_FILE" 2>/dev/null || true

  printf '\nConfiguration saved:\n  %s\n' "$ENV_FILE"
  printf 'Next check:\n  bash %s/check-env.sh\n' "$SCRIPT_DIR"
}

main "$@"
