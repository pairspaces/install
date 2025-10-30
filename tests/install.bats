#!/usr/bin/env bats

load_bats_addon() {
  local formula="$1"
  local base
  base="$(brew --prefix "$formula")" || {
    echo "brew --prefix $formula failed" >&2
    exit 1
  }
  # Try common locations used by Homebrew formulae
  for cand in \
    "$base/libexec/$formula/load.bash" \
    "$base/share/$formula/load.bash" \
    "$base/lib/$formula/load.bash" \
    "$base/load.bash"
  do
    if [ -f "$cand" ]; then
      load "$cand"
      return 0
    fi
  done
  echo "Could not find load.bash for $formula under $base" >&2
  exit 1
}

# Replace the old load lines with these three:
load_bats_addon bats-support
load_bats_addon bats-assert
load_bats_addon bats-file

# These tests run the installer script in a controlled sandbox with mocked tools.
# They do NOT require sudo and do NOT touch the network.

setup() {
  # Paths
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  SCRIPT="$REPO_ROOT/install.sh"          # rename if your file is not install.sh
  RUN_DIR="$(mktemp -d)"
  BIN_DIR="$RUN_DIR/bin"                  # fake install destination for -d
  SHIM_DIR="$RUN_DIR/shims"               # shims for uname/curl/etc.
  LOG_DIR="$RUN_DIR/logs"
  mkdir -p "$BIN_DIR" "$SHIM_DIR" "$LOG_DIR"

  # Log file to capture curl URLs (so we can assert URL formation)
  CURL_LOG="$LOG_DIR/curl_calls.log"
  : > "$CURL_LOG"
  export CURL_LOG                         # <- critical so curl shim can see it

  # Provide a HOME so uninstall cleans the right .config folder
  export HOME="$RUN_DIR/home"
  mkdir -p "$HOME/.config/pair"

  # Build shims that the script will call first via PATH
  _make_uname_shim            # creates $SHIM_DIR/uname (we override via UNAME_S/UNAME_M)
  _make_curl_shim             # creates $SHIM_DIR/curl (logs URLs, fakes downloads, fakes checksums)
  _make_mv_chmod_shims        # creates $SHIM_DIR/mv, chmod (use system tools)
  _make_sha256_cosign_shims   # creates $SHIM_DIR/sha256sum & cosign default stubs
  _make_getent_shim           # creates $SHIM_DIR/getent for uninstall path

  # Prepend PATH with our shims so they win
  export PATH="$SHIM_DIR:$PATH"

  # Ensure the script doesn’t ask for sudo; we’ll only install into -d "$BIN_DIR".
  # Also force checksum OFF by default (individual tests can enable).
  export VERIFY_BINARY="false"
}

teardown() {
  # Do not override /bin/rm, so Bats can still clean up even after we delete RUN_DIR
  rm -rf "$RUN_DIR"
}

#
# ---- Helpers to create shims -------------------------------------------------
#

_make_uname_shim() {
  cat > "$SHIM_DIR/uname" <<'EOF'
#!/usr/bin/env bash
# Default passthrough unless overridden by UNAME_S / UNAME_M
case "$1" in
  -s) if [[ -n "$UNAME_S" ]]; then echo "$UNAME_S"; else /usr/bin/uname -s 2>/dev/null || /bin/uname -s; fi ;;
  -m) if [[ -n "$UNAME_M" ]]; then echo "$UNAME_M"; else /usr/bin/uname -m 2>/dev/null || /bin/uname -m; fi ;;
   *)  if [[ -n "$UNAME_S" || -n "$UNAME_M" ]]; then
         echo "${UNAME_S:-$(/usr/bin/uname -s 2>/dev/null || /bin/uname -s)}"
       else
         (/usr/bin/uname "$@" 2>/dev/null || /bin/uname "$@")
       fi
       ;;
esac
EOF
  chmod +x "$SHIM_DIR/uname"
}

_make_curl_shim() {
  cat > "$SHIM_DIR/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Log helper
log() { [[ -n "${CURL_LOG:-}" ]] && printf '%s\n' "$*" >> "$CURL_LOG" || true; }

# Extract the last arg that looks like a URL
url=""
declare -a args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  a="${args[$i]}"
  case "$a" in
    http*://*) url="$a" ;;
  esac
done
[[ -n "$url" ]] || { echo "curl shim: no URL in args $*" >&2; exit 2; }
log "$url"

# Flags we care about:
#  -sSf   : silent + fail on error
#  -O     : write output using remote name
#  -L     : follow redirects
#  -LO    : both of above
# We only emulate enough to satisfy the installer.

# When requesting latest.txt, emit the test-controlled version or 9.9.9
if [[ "$url" =~ latest\.txt$ ]]; then
  printf '%s\n' "${TEST_VERSION:-9.9.9}"
  exit 0
fi

# Generic helper to write a file named like the URL basename
download_remote_name() {
  local base
  base="$(basename "$url")"
  : > "$base"
  printf 'fake-%s\n' "$base" > "$base"
}

# Special handling for checksum artifacts so Linux checksum test can succeed
# The installer will:
#   1) download the binary FILENAME into CWD
#   2) request "pair_${VERSION}.{pem,sig}"
# We synthesize the .txt to contain lines for both amd64/arm64 that match the
# deterministic checksum of the already-downloaded "$FILENAME".
case "$url" in
  *pair_*.pem|*pair_*.sig)
    download_remote_name
    ;;
  *)
    # All other downloads (binary etc.)
    download_remote_name
    ;;
esac
EOF
  chmod +x "$SHIM_DIR/curl"
}

_make_mv_chmod_shims() {
  # Use system chmod so the installed file really becomes executable
  cat > "$SHIM_DIR/chmod" <<'EOF'
#!/usr/bin/env bash
exec /bin/chmod "$@"
EOF
  chmod +x "$SHIM_DIR/chmod"

  # Use system mv so the install actually places the file
  cat > "$SHIM_DIR/mv" <<'EOF'
#!/usr/bin/env bash
exec /bin/mv "$@"
EOF
  chmod +x "$SHIM_DIR/mv"
}

_make_sha256_cosign_shims() {
  # sha256sum: try real sha; fallback to "pairspaces"
  cat > "$SHIM_DIR/sha256sum" <<'EOF'
#!/usr/bin/env bash
file="$1"
if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$file" | awk '{print $1"  "$2}'
elif command -v /usr/bin/sha256sum >/dev/null 2>&1; then
  /usr/bin/sha256sum "$file"
else
  echo "pairspaces  $file"
fi
EOF
  chmod +x "$SHIM_DIR/sha256sum"

  # cosign: always succeed unless COSIGN_FAIL=1 is exported
  cat > "$SHIM_DIR/cosign" <<'EOF'
#!/usr/bin/env bash
[[ "${COSIGN_FAIL:-0}" = "1" ]] && exit 1 || exit 0
EOF
  chmod +x "$SHIM_DIR/cosign"
}

_make_getent_shim() {
  # Minimal getent for passwd lookups used by uninstall (works with $USER/HOME)
  cat > "$SHIM_DIR/getent" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" = "passwd" && -n "${2:-}" ]]; then
  u="$2"
  # username:x:uid:gid:gecos:home:shell
  echo "${u}:x:1000:1000:${u}:${HOME}:/bin/bash"
else
  exit 2
fi
EOF
  chmod +x "$SHIM_DIR/getent"
}

#
# ---- Convenience runner ------------------------------------------------------
#

run_install() {
  # $1: OS (linux|macos)
  # $2: ARCH (amd64|arm64)
  # OPTIONS... passed to installer (e.g., -d "$BIN_DIR")
  export UNAME_S="$([[ $1 = macos ]] && echo Darwin || echo Linux)"
  export UNAME_M="$([[ $2 = amd64 ]] && echo x86_64 || echo arm64)"

  run bash "$SCRIPT" -d "$BIN_DIR" "${@:3}"
}

#
# ---- Tests -------------------------------------------------------------------
#

@test "Linux amd64: URL formation & installs into temp -d" {
  export TEST_VERSION="1.2.3"
  run_install linux amd64
  assert_success

  # Binary exists and is executable
  assert_file_executable "$BIN_DIR/pair"

  # Check the captured curl URL used for the binary download
  download_url="$(grep -E '/linux/amd64/pair_1\.2\.3$' "$CURL_LOG" || true)"
  [ -n "$download_url" ] || fail "Expected a linux/amd64 download URL with version 1.2.3; got: $(cat "$CURL_LOG")"
}

@test "macOS arm64: URL formation & installs into temp -d" {
  export TEST_VERSION="9.9.9"
  run_install macos arm64
  assert_success

  assert_file_executable "$BIN_DIR/pair"

  download_url="$(grep -E '/macos/arm64/pair_9\.9\.9$' "$CURL_LOG" || true)"
  [ -n "$download_url" ] || fail "Expected a macos/arm64 download URL with version 9.9.9; got: $(cat "$CURL_LOG")"
}

@test "Uninstall removes binary and ~/.config/pair (no sudo)" {
  export TEST_VERSION="2.0.0"

  # First install
  run_install linux amd64
  assert_success
  assert_file_exists "$BIN_DIR/pair"

  # Create a fake config file to ensure uninstall cleans it
  mkdir -p "$HOME/.config/pair"
  echo "cfg" > "$HOME/.config/pair/config"

  # Now uninstall (use the same -d path so script removes the right binary)
  run bash "$SCRIPT" -d "$BIN_DIR" --uninstall
  assert_success

  assert_file_not_exists "$BIN_DIR/pair"
  assert_dir_not_exists "$HOME/.config/pair"
}

@test "Linux binary verification path succeeds when VERIFY_BINARY=true" {
  export TEST_VERSION="2.4.7-build"
  export VERIFY_BINARY="true"

  run_install linux amd64
  assert_success

  assert_file_executable "$BIN_DIR/pair"

  # Sanity-check that the checksum artifacts were “downloaded”
  grep -q "pair_2.4.7-build.pem" "$CURL_LOG"
  grep -q "pair_2.4.7-build.sig" "$CURL_LOG"
}