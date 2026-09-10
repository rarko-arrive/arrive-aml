#!/usr/bin/env bash
set -euo pipefail

# Check for Claude Code CLI
# Note: Claude Code is typically pre-installed on Azure ML VMs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/common.sh"

install_claude() {
  log_info "Checking for Claude Code..."

  # Check if claude is already installed (Claude Code)
  if command -v claude >/dev/null 2>&1; then
    local version=$(claude --version 2>/dev/null || echo "installed")
    log_success "Claude Code already installed: $version"
    return 0
  fi

  log_warn "Claude Code not found"
  log_info "Claude Code is the official CLI from Anthropic"
  log_info "It's typically pre-installed on Azure ML VMs"
  echo
  log_info "If you need to install it manually:"
  echo
  echo "  Option 1 - Install via curl (Linux/macOS):"
  echo "    curl -fsSL https://claude.ai/install.sh | sh"
  echo
  echo "  Option 2 - Download from official site:"
  echo "    Visit: https://claude.ai/download"
  echo
  echo "  Option 3 - Check if already available:"
  echo "    which claude"
  echo "    \$HOME/.local/bin/claude --version"
  echo
  log_info "After installation, authenticate with:"
  log_info "  claude auth login"

  # Return success (non-critical tool)
  return 0
}

# Run if executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  check_not_root
  install_claude
fi
