#!/usr/bin/env bash
set -euo pipefail

# Install Claude CLI
# Requires Node.js/npm

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/common.sh"

install_node_if_needed() {
  if command -v node >/dev/null 2>&1; then
    log_success "Node.js already installed: $(node --version)"
    return 0
  fi

  log_info "Node.js not found. Installing Node.js via NodeSource..."

  if ! is_ubuntu; then
    log_error "Auto-install only supported on Ubuntu. Install Node.js manually."
    return 1
  fi

  # Install Node.js 20.x LTS
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y -qq nodejs

  log_success "Node.js installed: $(node --version)"
}

install_claude() {
  log_info "Installing Claude CLI..."

  # Ensure Node.js is installed
  install_node_if_needed || return 1

  # Check if claude is already installed
  if command -v claude >/dev/null 2>&1; then
    log_success "Claude CLI already installed: $(claude --version)"
    return 0
  fi

  log_info "Installing Claude CLI via npm..."
  sudo npm install -g @anthropic-ai/claude-cli

  if ! command -v claude >/dev/null 2>&1; then
    log_error "Claude CLI installation failed"
    return 1
  fi

  log_success "Claude CLI installed successfully!"
  log_info "Version: $(claude --version)"
  echo
  log_info "Next steps:"
  log_info "  1. Get API key from: https://console.anthropic.com/settings/keys"
  log_info "  2. Configure: claude configure"
}

# Run if executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  check_not_root
  install_claude
fi
