#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$SKILL_DIR/config/image-studio.env"
KEYCHAIN_SERVICE="${IMAGE_STUDIO_KEYCHAIN_SERVICE:-codex-image-studio}"

usage() {
  cat <<USAGE
Image Studio GUI configuration wizard for macOS.

This uses system dialogs for provider setup. API keys are entered with a
hidden input field and are stored in macOS Keychain by default.

Usage:
  bash skills/image-studio/scripts/configure-env-gui.sh

USAGE
}

is_placeholder() {
  local value="${1:-}"
  [[ -z "$value" || "$value" == replace_with_* || "$value" == *_HERE ]]
}

quote_env_value() {
  printf '%q' "${1:-}"
}

write_env_line() {
  local name="$1"
  local value="${2:-}"
  printf '%s=%s\n' "$name" "$(quote_env_value "$value")"
}

load_existing_env() {
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    . "$ENV_FILE"
  fi
}

require_gui_tools() {
  if ! command -v osascript >/dev/null 2>&1; then
    printf 'osascript is required for the GUI wizard.\n' >&2
    return 1
  fi
  if ! command -v security >/dev/null 2>&1; then
    printf 'macOS security CLI is required for Keychain storage.\n' >&2
    return 1
  fi
}

prompt_text() {
  local title="$1"
  local message="$2"
  local default_value="${3:-}"
  local hidden="${4:-false}"
  osascript - "$title" "$message" "$default_value" "$hidden" <<'APPLESCRIPT'
on run argv
  set dialogTitle to item 1 of argv
  set dialogMessage to item 2 of argv
  set defaultValue to item 3 of argv
  set hiddenInput to item 4 of argv
  try
    if hiddenInput is "true" then
      set dialogResult to display dialog dialogMessage default answer "" with title dialogTitle buttons {"Cancel", "OK"} default button "OK" cancel button "Cancel" with hidden answer
    else
      set dialogResult to display dialog dialogMessage default answer defaultValue with title dialogTitle buttons {"Cancel", "OK"} default button "OK" cancel button "Cancel"
    end if
    return text returned of dialogResult
  on error number -128
    return "__IMAGE_STUDIO_CANCEL__"
  end try
end run
APPLESCRIPT
}

prompt_provider() {
  local default_button="Relay"
  if [[ "$(printf '%s' "${IMAGE_STUDIO_PROVIDER:-}" | tr '[:upper:]' '[:lower:]')" == "runninghub" ]]; then
    default_button="Running Hub"
  fi
  osascript - "$default_button" <<'APPLESCRIPT'
on run argv
  set defaultButton to item 1 of argv
  try
    set dialogResult to display dialog "Choose an image provider." with title "Image Studio Provider" buttons {"Cancel", "Running Hub", "Relay"} default button defaultButton cancel button "Cancel"
    return button returned of dialogResult
  on error number -128
    return "__IMAGE_STUDIO_CANCEL__"
  end try
end run
APPLESCRIPT
}

prompt_storage() {
  osascript <<'APPLESCRIPT'
try
  set dialogResult to display dialog "Where should the API key be stored?" with title "Image Studio API Key" buttons {"Cancel", "Private env", "Keychain"} default button "Keychain" cancel button "Cancel"
  return button returned of dialogResult
on error number -128
  return "__IMAGE_STUDIO_CANCEL__"
end try
APPLESCRIPT
}

cancel_if_needed() {
  if [[ "${1:-}" == "__IMAGE_STUDIO_CANCEL__" ]]; then
    printf 'Configuration canceled.\n' >&2
    exit 130
  fi
}

require_value() {
  local label="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    printf '%s is required.\n' "$label" >&2
    exit 2
  fi
}

store_keychain_key() {
  local account="$1"
  local api_key="$2"
  security add-generic-password \
    -a "$account" \
    -s "$KEYCHAIN_SERVICE" \
    -w "$api_key" \
    -U >/dev/null
}

write_openai_env() {
  local base_url="$1"
  local image_model="$2"
  local size="$3"
  local quality="$4"
  local output_dir="$5"
  local timeout_seconds="$6"
  local max_retries="$7"
  local key_storage="$8"
  local api_key="${9:-}"

  {
    printf '# Image Studio private environment. Do not commit this file.\n'
    printf '# Provider: OpenAI-compatible relay / 中转站.\n\n'
    write_env_line IMAGE_STUDIO_PROVIDER openai
    write_env_line IMAGE_STUDIO_BASE_URL "$base_url"
    if [[ "$key_storage" == "keychain" ]]; then
      printf '# API key is stored in macOS Keychain, not in this file.\n'
      write_env_line IMAGE_STUDIO_API_KEY_SOURCE keychain
      write_env_line IMAGE_STUDIO_KEYCHAIN_SERVICE "$KEYCHAIN_SERVICE"
      write_env_line IMAGE_STUDIO_KEYCHAIN_ACCOUNT openai
    else
      printf '# FINAL API KEY LOCATION / 最终填写中转站 API key 的地方：\n'
      write_env_line IMAGE_STUDIO_API_KEY "$api_key"
    fi
    write_env_line IMAGE_STUDIO_IMAGE_MODEL "$image_model"
    write_env_line IMAGE_STUDIO_DEFAULT_SIZE "$size"
    write_env_line IMAGE_STUDIO_DEFAULT_QUALITY "$quality"
    write_env_line IMAGE_STUDIO_TEXT_MODEL gpt-4.1
    write_env_line IMAGE_STUDIO_API_MODE images
    write_env_line IMAGE_STUDIO_OUTPUT_DIR "$output_dir"
    write_env_line IMAGE_STUDIO_TIMEOUT_SECONDS "$timeout_seconds"
    write_env_line IMAGE_STUDIO_MAX_RETRIES "$max_retries"
  } > "$ENV_FILE"
}

write_runninghub_env() {
  local base_url="$1"
  local aspect_ratio="$2"
  local resolution="$3"
  local max_wait="$4"
  local output_dir="$5"
  local timeout_seconds="$6"
  local max_retries="$7"
  local key_storage="$8"
  local api_key="${9:-}"

  {
    printf '# Image Studio private environment. Do not commit this file.\n'
    printf '# Provider: Running Hub gpt-image-2 only.\n\n'
    write_env_line IMAGE_STUDIO_PROVIDER runninghub
    write_env_line IMAGE_STUDIO_BASE_URL "$base_url"
    if [[ "$key_storage" == "keychain" ]]; then
      printf '# API key is stored in macOS Keychain, not in this file.\n'
      write_env_line IMAGE_STUDIO_API_KEY_SOURCE keychain
      write_env_line IMAGE_STUDIO_KEYCHAIN_SERVICE "$KEYCHAIN_SERVICE"
      write_env_line IMAGE_STUDIO_KEYCHAIN_ACCOUNT runninghub
    else
      printf '# FINAL API KEY LOCATION / 最终填写 Running Hub API key 的地方：\n'
      write_env_line IMAGE_STUDIO_API_KEY "$api_key"
    fi
    write_env_line IMAGE_STUDIO_RUNNINGHUB_TEXT_MODEL /rhart-image-g-2-official/text-to-image
    write_env_line IMAGE_STUDIO_RUNNINGHUB_EDIT_MODEL /rhart-image-g-2/image-to-image
    write_env_line IMAGE_STUDIO_RUNNINGHUB_ASPECT_RATIO "$aspect_ratio"
    write_env_line IMAGE_STUDIO_RUNNINGHUB_RESOLUTION "$resolution"
    write_env_line IMAGE_STUDIO_RUNNINGHUB_MAX_WAIT_SECONDS "$max_wait"
    write_env_line IMAGE_STUDIO_IMAGE_MODEL ""
    write_env_line IMAGE_STUDIO_DEFAULT_SIZE ""
    write_env_line IMAGE_STUDIO_DEFAULT_QUALITY ""
    write_env_line IMAGE_STUDIO_TEXT_MODEL gpt-4.1
    write_env_line IMAGE_STUDIO_API_MODE images
    write_env_line IMAGE_STUDIO_OUTPUT_DIR "$output_dir"
    write_env_line IMAGE_STUDIO_TIMEOUT_SECONDS "$timeout_seconds"
    write_env_line IMAGE_STUDIO_MAX_RETRIES "$max_retries"
  } > "$ENV_FILE"
}

main() {
  if [[ " ${*:-} " == *" --help "* || " ${*:-} " == *" -h "* ]]; then
    usage
    exit 0
  fi

  require_gui_tools
  mkdir -p "$(dirname "$ENV_FILE")"
  load_existing_env

  local provider_button provider storage_button key_storage api_key output_dir timeout_seconds max_retries
  provider_button="$(prompt_provider)"
  cancel_if_needed "$provider_button"
  case "$provider_button" in
    Relay) provider="openai" ;;
    "Running Hub") provider="runninghub" ;;
    *) printf 'Unknown provider choice: %s\n' "$provider_button" >&2; exit 2 ;;
  esac

  storage_button="$(prompt_storage)"
  cancel_if_needed "$storage_button"
  case "$storage_button" in
    Keychain) key_storage="keychain" ;;
    "Private env") key_storage="env" ;;
    *) printf 'Unknown storage choice: %s\n' "$storage_button" >&2; exit 2 ;;
  esac

  api_key="$(prompt_text 'Image Studio API Key' 'Paste the provider API key. The input is hidden.' '' true)"
  cancel_if_needed "$api_key"
  require_value "API key" "$api_key"

  output_dir="$(prompt_text 'Image Studio Output Directory' 'Output directory' "${IMAGE_STUDIO_OUTPUT_DIR:-$SKILL_DIR/outputs}" false)"
  cancel_if_needed "$output_dir"
  require_value "Output directory" "$output_dir"

  timeout_seconds="$(prompt_text 'Image Studio Timeout' 'Request timeout seconds' "${IMAGE_STUDIO_TIMEOUT_SECONDS:-300}" false)"
  cancel_if_needed "$timeout_seconds"
  require_value "Timeout seconds" "$timeout_seconds"

  max_retries="$(prompt_text 'Image Studio Retries' 'Max retries' "${IMAGE_STUDIO_MAX_RETRIES:-2}" false)"
  cancel_if_needed "$max_retries"
  require_value "Max retries" "$max_retries"

  if [[ -f "$ENV_FILE" ]]; then
    local backup="$ENV_FILE.backup.$(date +%Y%m%d-%H%M%S)"
    cp "$ENV_FILE" "$backup"
    chmod 600 "$backup" 2>/dev/null || true
    printf 'Existing config backed up to: %s\n' "$backup"
  fi

  if [[ "$provider" == "openai" ]]; then
    local base_url image_model size quality
    base_url="$(prompt_text 'Relay BASE_URL' 'OpenAI-compatible relay BASE_URL / 中转站 BASE_URL' "${IMAGE_STUDIO_BASE_URL:-https://relay.example.com/v1}" false)"
    cancel_if_needed "$base_url"
    require_value "Relay BASE_URL" "$base_url"
    image_model="$(prompt_text 'Relay Image Model' 'Relay image model / 中转站图像模型名' "${IMAGE_STUDIO_IMAGE_MODEL:-gpt-image-2}" false)"
    cancel_if_needed "$image_model"
    require_value "Relay image model" "$image_model"
    size="$(prompt_text 'Relay Image Size' 'Default image size' "${IMAGE_STUDIO_DEFAULT_SIZE:-1024x1024}" false)"
    cancel_if_needed "$size"
    require_value "Default image size" "$size"
    quality="$(prompt_text 'Relay Image Quality' 'Default image quality' "${IMAGE_STUDIO_DEFAULT_QUALITY:-high}" false)"
    cancel_if_needed "$quality"
    require_value "Default image quality" "$quality"
    if [[ "$key_storage" == "keychain" ]]; then
      store_keychain_key "$provider" "$api_key"
    fi
    write_openai_env "$base_url" "$image_model" "$size" "$quality" "$output_dir" "$timeout_seconds" "$max_retries" "$key_storage" "$api_key"
  else
    local base_url aspect_ratio resolution max_wait
    base_url="$(prompt_text 'Running Hub BASE_URL' 'Running Hub base URL' "${IMAGE_STUDIO_BASE_URL:-https://www.runninghub.cn}" false)"
    cancel_if_needed "$base_url"
    require_value "Running Hub BASE_URL" "$base_url"
    aspect_ratio="$(prompt_text 'Running Hub Aspect Ratio' 'Default aspect ratio' "${IMAGE_STUDIO_RUNNINGHUB_ASPECT_RATIO:-16:9}" false)"
    cancel_if_needed "$aspect_ratio"
    require_value "Default aspect ratio" "$aspect_ratio"
    resolution="$(prompt_text 'Running Hub Resolution' 'Default resolution' "${IMAGE_STUDIO_RUNNINGHUB_RESOLUTION:-1k}" false)"
    cancel_if_needed "$resolution"
    require_value "Default resolution" "$resolution"
    max_wait="$(prompt_text 'Running Hub Max Wait' 'Max wait seconds for Running Hub tasks' "${IMAGE_STUDIO_RUNNINGHUB_MAX_WAIT_SECONDS:-1800}" false)"
    cancel_if_needed "$max_wait"
    require_value "Running Hub max wait seconds" "$max_wait"
    if [[ "$key_storage" == "keychain" ]]; then
      store_keychain_key "$provider" "$api_key"
    fi
    write_runninghub_env "$base_url" "$aspect_ratio" "$resolution" "$max_wait" "$output_dir" "$timeout_seconds" "$max_retries" "$key_storage" "$api_key"
  fi

  chmod 600 "$ENV_FILE" 2>/dev/null || true
  printf 'Configuration saved: %s\n' "$ENV_FILE"
  if [[ "$key_storage" == "keychain" ]]; then
    printf 'API key stored in macOS Keychain service=%s account=%s\n' "$KEYCHAIN_SERVICE" "$provider"
  fi
  printf 'Next check: bash %s/check-env.sh\n' "$SCRIPT_DIR"
}

main "$@"
