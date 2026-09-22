#!/usr/bin/env bash
set -euo pipefail

# Install essential system tools for Azure ML development

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/common.sh"

pkg_installed() {
  [ "$(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null || true)" = "installed" ]
}

install_system_tools() {
  log_info "Installing essential system tools..."

  if ! is_ubuntu; then
    log_warn "This script is designed for Ubuntu. Your OS may not be supported."
  fi

  local packages=(
    build-essential
    git
    curl
    wget
    htop
    jq
    tree
    vim
    unzip
    ca-certificates
    gnupg
    lsb-release
  )
  local missing=() pkg
  for pkg in "${packages[@]}"; do
    pkg_installed "$pkg" || missing+=("$pkg")
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    log_success "System tools already installed"
  else
    # Only touch apt when something is missing. A re-run must not fail because
    # Azure's background apt still holds /var/lib/apt/lists/lock.
    log_info "Installing: ${missing[*]}"
    log_info "Updating package list..."
    apt_update_quiet
    apt_get install -y -qq "${missing[@]}"
    log_success "System tools installed!"
  fi

  # Verify installations
  log_info "Verifying installations..."
  verify_command git "Git"
  verify_command curl "curl"
  verify_command wget "wget"
  verify_command htop "htop"
  verify_command jq "jq"
  verify_command tree "tree"
  verify_command vim "vim"

  log_success "All system tools verified!"
}

# Run if executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  check_not_root
  install_system_tools
fi
