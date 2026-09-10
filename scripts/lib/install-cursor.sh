#!/usr/bin/env bash
set -euo pipefail

# Install Cursor Editor (optional)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/common.sh"

install_cursor() {
  log_info "Installing Cursor Editor..."

  if command -v cursor >/dev/null 2>&1; then
    log_success "Cursor already installed: $(command -v cursor)"
    return 0
  fi

  local CURSOR_DIR="${HOME}/.cursor"
  local CURSOR_BIN="${HOME}/.local/bin/cursor"

  log_info "Downloading Cursor AppImage..."
  mkdir -p "${HOME}/.local/bin"
  mkdir -p "$CURSOR_DIR"

  # Download latest Cursor AppImage with timeout
  local DOWNLOAD_URL="https://downloader.cursor.sh/linux/appImage/x64"

  log_info "Attempting download from: $DOWNLOAD_URL"
  if ! wget --timeout=60 --tries=2 -q --show-progress "$DOWNLOAD_URL" -O "${CURSOR_DIR}/cursor.AppImage" 2>&1; then
    log_warn "Failed to download Cursor AppImage"
    log_info "This is optional - you can install manually later"
    log_info "Download from: https://cursor.sh/download"
    echo
    log_info "Alternative: Use VS Code instead (already installed)"
    return 0  # Return success (optional tool)
  fi

  chmod +x "${CURSOR_DIR}/cursor.AppImage"

  # Create wrapper script
  log_info "Creating cursor command wrapper..."
  cat > "$CURSOR_BIN" << 'EOF'
#!/usr/bin/env bash
# Cursor wrapper script
exec "$HOME/.cursor/cursor.AppImage" "$@"
EOF

  chmod +x "$CURSOR_BIN"

  # Add to PATH
  add_to_path "${HOME}/.local/bin" "Cursor and other local binaries (arrive-aml setup)"

  # Add to current PATH
  export PATH="${HOME}/.local/bin:${PATH}"

  if ! command -v cursor >/dev/null 2>&1; then
    log_warn "Cursor wrapper created but not in PATH yet"
    log_info "Run: source ~/.bashrc"
    return 0
  fi

  log_success "Cursor installed successfully!"
  log_info "Location: ${CURSOR_DIR}/cursor.AppImage"
  log_info "Wrapper: $CURSOR_BIN"
  echo
  log_info "Launch with: cursor"
  log_info "Or: cursor /path/to/project"
}

# Run if executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  check_not_root
  install_cursor
fi
