#!/usr/bin/env bash
set -euo pipefail

# Cursor on an Azure ML compute instance
#
# A compute instance is headless: you use Cursor on your laptop and connect with
# Remote-SSH. Cursor then installs its own server under ~/.cursor-server on the
# VM automatically - nothing to download here. This script only reports that
# state. Downloading the desktop AppImage is opt-in (--appimage) for machines
# that actually have a display.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/common.sh"

cursor_server_version() {
  local latest
  latest="$(ls -td "${HOME}"/.cursor-server/bin/linux-x64/*/ 2>/dev/null | head -n1)"
  [ -n "$latest" ] || return 1
  "${latest}bin/remote-cli/cursor" --version 2>/dev/null | head -n1 || echo "present"
}

install_cursor_appimage() {
  local CURSOR_DIR="${HOME}/.cursor"
  local CURSOR_BIN="${HOME}/.local/bin/cursor"
  # The old downloader.cursor.sh host no longer resolves; this API redirects to the current build.
  local DOWNLOAD_URL="https://api2.cursor.sh/updates/download/golden/linux-x64/cursor/latest"

  mkdir -p "${HOME}/.local/bin" "$CURSOR_DIR"
  log_info "Downloading Cursor AppImage from $DOWNLOAD_URL ..."
  if ! curl -fL --max-time 600 --retry 2 -o "${CURSOR_DIR}/cursor.AppImage" "$DOWNLOAD_URL"; then
    log_warn "Download failed. Get it manually from https://cursor.com/downloads"
    return 1
  fi
  chmod +x "${CURSOR_DIR}/cursor.AppImage"
  cat > "$CURSOR_BIN" <<'WRAP'
#!/usr/bin/env bash
exec "$HOME/.cursor/cursor.AppImage" --no-sandbox "$@"
WRAP
  chmod +x "$CURSOR_BIN"
  add_to_path "${HOME}/.local/bin" "Cursor and other local binaries (arrive-aml setup)"
  log_success "Cursor AppImage installed: ${CURSOR_DIR}/cursor.AppImage (wrapper: $CURSOR_BIN)"
}

install_cursor() {
  local want_appimage=false
  [ "${1:-}" = "--appimage" ] && want_appimage=true

  log_info "Checking Cursor..."

  if command -v cursor >/dev/null 2>&1; then
    log_success "Cursor CLI available: $(command -v cursor)"
    return 0
  fi

  local v
  if v="$(cursor_server_version)"; then
    log_success "Cursor Remote-SSH server is installed on this VM (v$v)"
    log_info "Use Cursor on your laptop -> Remote-SSH -> $(this_host). The 'cursor' command is available inside Cursor's terminal."
    return 0
  fi

  if [ "$want_appimage" = true ] || ! is_headless; then
    install_cursor_appimage
    return $?
  fi

  log_info "This VM is headless - Cursor is used from your laptop via Remote-SSH (no install needed here)."
  log_info "  1. On your laptop: bash scripts/setup-azureml-ssh.sh   (adds this VM to ~/.ssh/config)"
  log_info "  2. Cursor -> Remote-SSH -> $(this_host) -> open /mnt/mirror/<repo>"
  log_info "  Cursor installs its server under ~/.cursor-server on first connect."
  return 0
}

# Run if executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  check_not_root
  install_cursor "$@"
fi
