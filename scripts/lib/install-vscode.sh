#!/usr/bin/env bash
set -euo pipefail

# Install Visual Studio Code CLI (code command)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/common.sh"

install_vscode() {
  log_info "Installing Visual Studio Code..."

  if command -v code >/dev/null 2>&1; then
    log_success "VS Code already installed: $(code --version | head -n1)"
    return 0
  fi

  if ! is_ubuntu; then
    log_warn "This script is designed for Ubuntu. Install manually if needed."
    return 1
  fi

  log_info "Adding Microsoft GPG key and repository..."

  # Install prerequisites
  sudo apt-get install -y -qq wget gpg

  # Download and install Microsoft GPG key
  wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
  sudo install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
  rm -f packages.microsoft.gpg

  # Add VS Code repository
  echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
    | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null

  # Install VS Code
  log_info "Installing code..."
  sudo apt-get update -qq
  sudo apt-get install -y -qq code

  if ! command -v code >/dev/null 2>&1; then
    log_error "VS Code installation failed"
    return 1
  fi

  log_success "VS Code installed successfully!"
  log_info "Version: $(code --version | head -n1)"
}

# Run if executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  check_not_root
  install_vscode
fi
