#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$SKILL_DIR/../.." && pwd)"
WRAPPER_DIR="$SKILL_DIR/wrapper"
BIN_DIR="$SKILL_DIR/bin"
BIN_PATH="$BIN_DIR/gptcodex-image"
THIRD_PARTY_DIR="$PROJECT_ROOT/third_party/Image-Studio"

printf 'Image Studio Skill installer\n'

if ! command -v go >/dev/null 2>&1; then
  printf 'Go 未安装。请先安装 Go，然后重新运行本脚本。\n' >&2
  exit 1
fi

printf 'Go: %s\n' "$(go version)"

mkdir -p "$BIN_DIR" \
  "$SKILL_DIR/outputs/images" \
  "$SKILL_DIR/outputs/metadata" \
  "$SKILL_DIR/outputs/logs" \
  "$SKILL_DIR/outputs/raw" \
  "$PROJECT_ROOT/third_party"

if [[ -d "$THIRD_PARTY_DIR/go-cli" ]]; then
  printf 'Found Image-Studio go-cli: %s\n' "$THIRD_PARTY_DIR/go-cli"
else
  printf 'Image-Studio go-cli not found locally. Attempting sparse clone...\n'
  rm -rf "$THIRD_PARTY_DIR"
  if git clone --depth 1 --filter=blob:none --sparse https://github.com/RoseKhlifa/Image-Studio.git "$THIRD_PARTY_DIR"; then
    git -C "$THIRD_PARTY_DIR" sparse-checkout set go-cli || true
    printf 'Sparse clone ready: %s\n' "$THIRD_PARTY_DIR/go-cli"
  else
    printf 'Warning: could not clone Image-Studio. Continuing with bundled local wrapper.\n' >&2
  fi
fi

if [[ -d "$THIRD_PARTY_DIR/go-cli/cmd/gptcodex-image" ]]; then
  printf 'Upstream CLI path: %s\n' "$THIRD_PARTY_DIR/go-cli/cmd/gptcodex-image"
else
  printf 'Upstream CLI path: unavailable; using local wrapper source.\n'
fi

printf 'Building local wrapper: %s\n' "$BIN_PATH"
(cd "$WRAPPER_DIR" && go build -o "$BIN_PATH" .)
chmod +x "$BIN_PATH"

printf 'Install complete.\n'
printf 'Binary: %s\n' "$BIN_PATH"
printf 'Check: %s --help\n' "$BIN_PATH"
