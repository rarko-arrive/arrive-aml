#!/usr/bin/env bash
set -euo pipefail

# Install essential system tools for Azure ML development

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/common.sh"

install_system_tools() {
  log_info "Installing essential system tools..."

  if ! is_ubuntu; then
    log_warn "This script is designed for Ubuntu. Your OS may not be supported."
  fi

  # Update package list
  log_info "Updating package list..."
  sudo apt-get update -qq

  # Install tools
  log_info "Installing: build-essential, git, curl, wget, htop, jq, tree, vim"
  sudo apt-get install -y -qq \
    build-essential \
    git \
    curl \
    wget \
    htop \
    jq \
    tree \
    vim \
    unzip \
    ca-certificates \
    gnupg \
    lsb-release

  log_success "System tools installed!"

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
