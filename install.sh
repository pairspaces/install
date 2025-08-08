#!/usr/bin/env bash

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

NAME="pair"
ENV="build"
BASE_URL="https://downloads.pairspaces.com/$ENV"
INSTALL_DIR="/usr/local/bin"
VERIFY_CHECKSUM="${VERIFY_CHECKSUM:-false}"

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
    Darwin) OS="macos" ;;
    *) abort "Unsupported OS: $OS" ;;
  esac
}

# =============================================================================
# Version & URL Resolution
# =============================================================================

resolve_version_and_url() {
  VERSION=$(curl -sSf "${BASE_URL}/latest.txt") || abort "Failed to fetch latest version"
  FILENAME="${NAME}_${VERSION}"
  DOWNLOAD_URL="${BASE_URL}/${OS}/${ARCH}/${FILENAME}"
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
          [ "$OS" = "macos" ] && INSTALL_DIR="$HOME/bin"

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
            verify) VERIFY_CHECKSUM=true ;;
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
# Permissions Check
# =============================================================================

check_install_permissions() {
  if [ ! -w "$INSTALL_DIR" ]; then
    echo ""
    echo "This script needs sudo to write to: $INSTALL_DIR"
    read -rp "Do you want to proceed with sudo? [Y/n] " answer
    case "${answer:-Y}" in
      [Yy]* )
        echo ""
        exec sudo "$0" "$@"
        ;;
      * )
        echo "Aborted by user."
        exit 1
        ;;
    esac
  fi
}

# =============================================================================
# Install
# =============================================================================

download_and_install() {
  cd "$(mktemp -d)"

  text_title "Downloading PairSpaces CLI"
  curl -LO --proto '=https' --tlsv1.2 -sSf "$DOWNLOAD_URL"

  verify_checksum

  text_title "Installing PairSpaces CLI" "$INSTALL_DIR/$NAME"
  chmod +x "$FILENAME"
  mv "$FILENAME" "$INSTALL_DIR/$NAME"

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
    rm -f "$bin_path"
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

# =============================================================================
# Verify checksum (Linux only)
# =============================================================================

verify_checksum() {
  if [ "$VERIFY_CHECKSUM" != "true" ] || [ "$OS" != "linux" ]; then
    return 0
  fi

  text_title "Verifying Checksum"

  local checksum_base="${BASE_URL}/pair_${VERSION}_checksums"

  curl -sSfO "${checksum_base}.txt"      || abort "Failed to download checksum file"
  curl -sSfO "${checksum_base}.txt.pem"  || abort "Failed to download PEM certificate"
  curl -sSfO "${checksum_base}.txt.sig"  || abort "Failed to download signature"

  if ! command -v cosign &>/dev/null; then
    text_title "Installing cosign"
    curl -LO https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64
    chmod +x cosign-linux-amd64
    mv cosign-linux-amd64 /usr/local/bin/cosign
  fi

  cosign verify-blob \
    --certificate "pair_${VERSION}_checksums.txt.pem" \
    --signature "pair_${VERSION}_checksums.txt.sig" \
    --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
    --certificate-identity-regexp=".*" \
    "pair_${VERSION}_checksums.txt" || abort "Checksum file signature invalid"

  local actual
  actual=$(sha256sum "$FILENAME" | awk '{print $1}')
  local expected
  expected=$(grep "linux/$ARCH/$FILENAME" "pair_${VERSION}_checksums.txt" | awk '{print $1}')

  if [ "$actual" != "$expected" ]; then
    abort "Checksum mismatch: expected $expected, got $actual"
  fi

  echo "The PairSpaces CLI was verified successfully using cosign."
}

# =============================================================================
# Main
# =============================================================================

main() {
  detect_platform
  process_args "$@"
  
  if [ "$UNINSTALL" = true ]; then
    check_install_permissions "$@"
    remove_installed_binary
  fi

  check_install_permissions "$@"
  resolve_version_and_url
  download_and_install
}

main "$@"