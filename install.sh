#!/usr/bin/env bash

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

NAME="pair"
GITHUB_REPO="pairspaces/install"
RELEASES_API="https://api.github.com/repos/${GITHUB_REPO}/releases"
INSTALL_DIR="/usr/local/bin"
VERIFY_BINARY="${VERIFY_BINARY:-false}"

# =============================================================================
# UI Helpers
# =============================================================================

text_bold() {
  echo -e "\033[1m$1\033[0m"
}

text_title() {
  echo ""
  text_bold "$1"
  if [ "${2:-}" != "" ]; then echo "$2"; fi
}

text_error() {
  echo -e "\033[1;31m$1\033[0m"
}

abort() {
  text_error "$1"
  exit 1
}

# =============================================================================
# System Detection
# =============================================================================

detect_platform() {
  OS="$(uname -s)"
  ARCH="$(uname -m)"

  case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    arm64|aarch64) ARCH="arm64" ;;
    *) abort "Unsupported architecture: $ARCH" ;;
  esac

  case "$OS" in
    Linux) OS="linux" ;;
    Darwin) OS="darwin" ;;
    *) abort "Unsupported OS: $OS" ;;
  esac
}

# =============================================================================
# Version & URL Resolution
# =============================================================================

resolve_version_and_url() {
  local response
  # /releases/latest returns only stable releases; fall back to /releases?per_page=1
  # which includes pre-releases, so the script works before a stable release exists.
  response=$(curl -sSf "${RELEASES_API}/latest" 2>/dev/null) || \
    response=$(curl -sSf "${RELEASES_API}?per_page=1") || \
    abort "Failed to fetch latest release"

  VERSION=$(echo "$response" | grep '"tag_name"' | head -1 | cut -d'"' -f4)
  [ -n "$VERSION" ] || abort "Failed to parse release version"

  local version_stripped="${VERSION#v}"
  FILENAME="pair_${version_stripped}_${OS}_${ARCH}"
  DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/${FILENAME}"
}

# =============================================================================
# Handle Flags
# =============================================================================

UNINSTALL=false

process_args() {
  if [ $# -gt 0 ]; then
    while getopts ":ud:-:" opt; do
      case $opt in
        u)
          INSTALL_DIR="$HOME/.local/bin"
          [ "$OS" = "darwin" ] && INSTALL_DIR="$HOME/bin"

          if [ ! -d "$INSTALL_DIR" ] || [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
            abort "User bin directory '$INSTALL_DIR' doesn't exist or isn't in PATH."
          fi
          ;;
        d)
          INSTALL_DIR=$(cd "$OPTARG" && pwd)
          [ -d "$INSTALL_DIR" ] || abort "Directory '$INSTALL_DIR' does not exist."
          ;;
        -)
          case "$OPTARG" in
            uninstall) UNINSTALL=true ;;
            verify) VERIFY_BINARY=true ;;
            *) abort "Unknown long option --$OPTARG" ;;
          esac
          ;;
        \?) abort "Invalid option: -$OPTARG" ;;
        :)  abort "Option -$OPTARG requires an argument." ;;
      esac
    done
  fi
}

# =============================================================================
# Install
# =============================================================================

download_and_install() {
  cd "$(mktemp -d)"

  text_title "Downloading PairSpaces CLI"
  curl -L --proto '=https' --tlsv1.2 -sSf "$DOWNLOAD_URL" -o "$FILENAME"

  verify_binary

  text_title "Installing PairSpaces CLI" "$INSTALL_DIR/$NAME"
  if [ -w "$INSTALL_DIR" ]; then
    mv "$FILENAME" "$INSTALL_DIR/$NAME"
    chmod +x "$INSTALL_DIR/$NAME"
  else
    sudo mv "$FILENAME" "$INSTALL_DIR/$NAME"
    sudo chmod +x "$INSTALL_DIR/$NAME"
  fi

  text_title "Installation Complete" "Run '$NAME help' to get started"
  echo ""
}

# =============================================================================
# Uninstall
# =============================================================================

remove_installed_binary() {
  text_title "Uninstalling PairSpaces CLI"

  local bin_path="$INSTALL_DIR/$NAME"
  local real_user="${SUDO_USER:-$USER}"
  local real_home
  if command -v getent >/dev/null 2>&1; then
    real_home=$(getent passwd "$real_user" | cut -d: -f6)
  else
    real_home=$(eval echo "~$real_user")
  fi

  local config_dir="$real_home/.config/$NAME"

  if [ -f "$bin_path" ]; then
    if [ -w "$INSTALL_DIR" ]; then
      rm -f "$bin_path"
    else
      sudo rm -f "$bin_path"
    fi
    echo "Removed $bin_path"
  else
    echo "Binary not found at $bin_path (already removed?)"
  fi

  if [ -d "$config_dir" ]; then
    rm -rf "$config_dir"
    echo "Removed configuration: $config_dir"
  fi

  text_title "Uninstall Complete"
  exit 0
}

# =====================================================================================
# Verify binary (Linux only — macOS and Windows binaries are signed by Apple/Microsoft)
# =====================================================================================

verify_binary() {
  if [ "$VERIFY_BINARY" != "true" ] || [ "$OS" != "linux" ]; then
    return 0
  fi

  text_title "Verifying Binary"

  local base_url="https://github.com/${GITHUB_REPO}/releases/download/${VERSION}"

  curl -L --proto '=https' --tlsv1.2 -sSfO "${base_url}/${FILENAME}.pem" || abort "Failed to download PEM certificate"
  curl -L --proto '=https' --tlsv1.2 -sSfO "${base_url}/${FILENAME}.sig" || abort "Failed to download signature"

  if ! command -v cosign &>/dev/null; then
    text_title "Installing cosign"
    curl -LO https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64
    chmod +x cosign-linux-amd64
    if [ -w /usr/local/bin ]; then
      mv cosign-linux-amd64 /usr/local/bin/cosign
    else
      sudo mv cosign-linux-amd64 /usr/local/bin/cosign
    fi
  fi

  cosign verify-blob \
  --certificate "${FILENAME}.pem" \
  --signature "${FILENAME}.sig" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  --certificate-identity-regexp=".*" \
  "$FILENAME"

  echo "The PairSpaces CLI was verified successfully using cosign."
}

# =============================================================================
# Main
# =============================================================================

main() {
  detect_platform
  process_args "$@"

  if [ "$UNINSTALL" = true ]; then
    remove_installed_binary
  fi

  resolve_version_and_url
  download_and_install
}

main "$@"
