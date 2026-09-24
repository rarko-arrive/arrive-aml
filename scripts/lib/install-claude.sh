#!/usr/bin/env bash
set -euo pipefail

# Install Claude Code CLI (idempotent)
# Uses the official native installer (puts `claude` in ~/.local/bin).
# Falls back to npm when node >= 18 is available.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/common.sh"

claude_auth_hint() {
  if command -v claude >/dev/null 2>&1 && claude auth status >/dev/null 2>&1; then
    log_success "Claude Code is authenticated"
  else
    log_warn "Claude Code is not authenticated yet."
    log_info "Run:  claude auth login   (works over SSH: open the printed URL on your laptop, paste the code back)"
    log_info "Or, for a long-lived token on a headless VM:  claude setup-token"
  fi
}

install_claude() {
  log_info "Installing Claude Code..."
  export PATH="${HOME}/.local/bin:${PATH}"

  if command -v claude >/dev/null 2>&1; then
    log_info "Claude Code already installed: $(claude --version 2>/dev/null || echo installed). Checking for updates..."
    # Keep it current: a new model (e.g. a new Opus) can require a newer CLI,
    # and a long-lived VM otherwise never re-checks after the first install.
    claude update >/dev/null 2>&1 || log_warn "Could not check for Claude Code updates (offline?)"
    log_success "Claude Code: $(claude --version 2>/dev/null || echo installed)"
    claude_auth_hint
    return 0
  fi

  log_info "Running the official installer (https://claude.ai/install.sh)..."
  if curl -fsSL --max-time 120 https://claude.ai/install.sh | bash; then
    export PATH="${HOME}/.local/bin:${PATH}"
  else
    log_warn "Native installer failed."
  fi

  if ! command -v claude >/dev/null 2>&1; then
    if command -v npm >/dev/null 2>&1 && command -v node >/dev/null 2>&1 \
       && [ "$(node -p 'process.versions.node.split(".")[0]')" -ge 18 ]; then
      log_info "Falling back to npm install..."
      npm install -g @anthropic-ai/claude-code >/dev/null 2>&1 || true
    fi
  fi

  if ! command -v claude >/dev/null 2>&1; then
    log_error "Claude Code installation failed."
    log_info "Manual install:  curl -fsSL https://claude.ai/install.sh | bash   then:  source ~/.bashrc"
    return 1
  fi

  add_to_path "${HOME}/.local/bin" "Claude Code and other local binaries (arrive-aml setup)"
  log_success "Claude Code installed: $(claude --version 2>/dev/null || echo installed)"
  claude_auth_hint
}

# Run if executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  check_not_root
  install_claude
fi
