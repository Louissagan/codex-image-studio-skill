#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ "$(basename "$SKILL_DIR")" == "image-studio" && "$(basename "$(dirname "$SKILL_DIR")")" == "skills" ]]; then
  PROJECT_ROOT="$(cd "$SKILL_DIR/../.." && pwd)"
else
  PROJECT_ROOT="$SKILL_DIR"
fi
WRAPPER_DIR="$SKILL_DIR/wrapper"
BIN_DIR="$SKILL_DIR/bin"
BIN_PATH="$BIN_DIR/gptcodex-image"
THIRD_PARTY_DIR="$PROJECT_ROOT/third_party/Image-Studio"
CONFIG_SCRIPT="$SKILL_DIR/scripts/configure-env.sh"
CONFIG_GUI_SCRIPT="$SKILL_DIR/scripts/configure-env-gui.sh"
CHECK_SCRIPT="$SKILL_DIR/scripts/check-env.sh"
EXAMPLE_ENV_FILE="$SKILL_DIR/config/image-studio.example.env"
ENV_FILE="$SKILL_DIR/config/image-studio.env"
MIN_GO_VERSION="${IMAGE_STUDIO_MIN_GO_VERSION:-$(awk '/^go[[:space:]]+/ { print $2; exit }' "$WRAPPER_DIR/go.mod" 2>/dev/null || true)}"
MIN_GO_VERSION="${MIN_GO_VERSION:-1.22}"

printf 'Image Studio Skill installer\n'

version_at_least() {
  local have="$1"
  local need="$2"
  awk -v have="$have" -v need="$need" '
    BEGIN {
      split(have, h, ".")
      split(need, n, ".")
      for (i = 1; i <= 3; i++) {
        hv = h[i] + 0
        nv = n[i] + 0
        if (hv > nv) exit 0
        if (hv < nv) exit 1
      }
      exit 0
    }
  '
}

current_go_version() {
  if ! command -v go >/dev/null 2>&1; then
    return 1
  fi
  local version
  version="$(go env GOVERSION 2>/dev/null | sed 's/^go//' || true)"
  if [[ -z "$version" ]]; then
    version="$(go version | awk '{ print $3 }' | sed 's/^go//')"
  fi
  printf '%s\n' "$version"
}

find_brew() {
  if command -v brew >/dev/null 2>&1; then
    command -v brew
  elif [[ -x /opt/homebrew/bin/brew ]]; then
    printf '/opt/homebrew/bin/brew\n'
  elif [[ -x /usr/local/bin/brew ]]; then
    printf '/usr/local/bin/brew\n'
  else
    return 1
  fi
}

refresh_brew_path() {
  local brew_path="${1:-}"
  local brew_prefix=""
  if [[ -n "$brew_path" ]]; then
    brew_prefix="$("$brew_path" --prefix 2>/dev/null || true)"
  fi
  for bin_dir in \
    "${brew_prefix:+$brew_prefix/bin}" \
    /opt/homebrew/bin \
    /usr/local/bin; do
    if [[ -n "$bin_dir" && -d "$bin_dir" && ":$PATH:" != *":$bin_dir:"* ]]; then
      PATH="$bin_dir:$PATH"
    fi
  done
  export PATH
  hash -r 2>/dev/null || true
}

install_homebrew_if_allowed() {
  if [[ "${IMAGE_STUDIO_AUTO_INSTALL_HOMEBREW:-0}" != "1" ]]; then
    return 1
  fi
  if [[ "$(uname -s)" != "Darwin" ]]; then
    return 1
  fi
  if ! command -v curl >/dev/null 2>&1; then
    printf 'curl is required to bootstrap Homebrew automatically.\n' >&2
    return 1
  fi
  printf 'Homebrew not found. Installing Homebrew because IMAGE_STUDIO_AUTO_INSTALL_HOMEBREW=1...\n'
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  refresh_brew_path ""
}

install_go_with_brew() {
  local brew_path
  if ! brew_path="$(find_brew)"; then
    install_homebrew_if_allowed || return 1
    brew_path="$(find_brew)"
  fi

  refresh_brew_path "$brew_path"
  printf 'Installing or upgrading Go with Homebrew...\n'
  if "$brew_path" list --formula go >/dev/null 2>&1; then
    "$brew_path" upgrade go || true
  else
    "$brew_path" install go
  fi
  refresh_brew_path "$brew_path"
}

ensure_go() {
  local version=""
  if version="$(current_go_version)"; then
    if version_at_least "$version" "$MIN_GO_VERSION"; then
      printf 'Go: %s\n' "$(go version)"
      return 0
    fi
    printf 'Go %s is installed but Image Studio requires Go >= %s.\n' "$version" "$MIN_GO_VERSION" >&2
  else
    printf 'Go is not installed; Image Studio requires Go >= %s.\n' "$MIN_GO_VERSION" >&2
  fi

  if [[ "${IMAGE_STUDIO_AUTO_INSTALL_GO:-1}" != "1" ]]; then
    printf 'Automatic Go installation is disabled. Set IMAGE_STUDIO_AUTO_INSTALL_GO=1 or install Go manually.\n' >&2
    return 1
  fi

  if install_go_with_brew && version="$(current_go_version)" && version_at_least "$version" "$MIN_GO_VERSION"; then
    printf 'Go installed: %s\n' "$(go version)"
    return 0
  fi

  printf 'Could not automatically install a compatible Go toolchain.\n' >&2
  printf 'Install Go >= %s, or install Homebrew and rerun this script.\n' "$MIN_GO_VERSION" >&2
  printf 'To let this script bootstrap Homebrew on macOS, rerun with IMAGE_STUDIO_AUTO_INSTALL_HOMEBREW=1.\n' >&2
  return 1
}

ensure_private_env_template() {
  if [[ -f "$ENV_FILE" || ! -f "$EXAMPLE_ENV_FILE" ]]; then
    return 0
  fi
  cp "$EXAMPLE_ENV_FILE" "$ENV_FILE"
  chmod 600 "$ENV_FILE" 2>/dev/null || true
  printf 'Created private env template: %s\n' "$ENV_FILE"
}

ensure_go

mkdir -p "$BIN_DIR" \
  "$SKILL_DIR/outputs/images" \
  "$SKILL_DIR/outputs/metadata" \
  "$SKILL_DIR/outputs/logs" \
  "$SKILL_DIR/outputs/raw" \
  "$PROJECT_ROOT/third_party"

ensure_private_env_template

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

printf '\nChecking provider configuration...\n'
if bash "$CHECK_SCRIPT"; then
  printf 'Image Studio is configured and ready.\n'
  exit 0
fi

printf '\nImage Studio needs provider configuration before first use.\n'
printf 'Preferred secure setup wizard: bash %s\n' "$CONFIG_GUI_SCRIPT"
printf 'Terminal setup wizard: bash %s\n' "$CONFIG_SCRIPT"
printf 'Manual template: cp %s/config/image-studio.example.env %s/config/image-studio.env\n' "$SKILL_DIR" "$SKILL_DIR"

if [[ -t 0 && -t 1 ]]; then
  printf 'Run the configuration wizard now? [Y/n] '
  read -r answer
  case "${answer:-Y}" in
    y|Y|yes|YES|Yes)
      if command -v osascript >/dev/null 2>&1 && command -v security >/dev/null 2>&1; then
        bash "$CONFIG_GUI_SCRIPT"
      else
        bash "$CONFIG_SCRIPT"
      fi
      bash "$CHECK_SCRIPT"
      ;;
    *)
      printf 'Skipped configuration wizard. Run it later before generating images.\n'
      ;;
  esac
fi
