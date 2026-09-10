#!/usr/bin/env bash
set -euo pipefail

# Install GitHub CLI (gh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/common.sh"

install_gh() {
  log_info "Installing GitHub CLI (gh)..."

  if command -v gh >/dev/null 2>&1; then
    log_success "gh already installed: $(command -v gh)"
    log_info "Version: $(gh --version | head -n1)"
    return 0
  fi

  if ! is_ubuntu; then
    log_warn "This script is designed for Ubuntu. Install manually if needed."
    return 1
  fi

  log_info "Adding GitHub CLI repository..."

  # Install GitHub CLI from official repository
  sudo mkdir -p -m 755 /etc/apt/keyrings

  # Download and install GitHub CLI GPG key
  wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg

  # Add GitHub CLI repository
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null

  # Update and install
  log_info "Installing gh..."
  sudo apt-get update -qq
  sudo apt-get install -y -qq gh

  if ! command -v gh >/dev/null 2>&1; then
    log_error "gh installation failed"
    return 1
  fi

  log_success "GitHub CLI installed successfully!"
  log_info "Version: $(gh --version | head -n1)"
  echo
  log_info "Next steps:"
  log_info "  1. Authenticate: gh auth login"
  log_info "  2. Or use setup script: bash scripts/lib/configure-github-ssh.sh"
}

# Run if executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  check_not_root
  install_gh
fi
