#!/usr/bin/env bash
set -euo pipefail

# VS Code on an Azure ML compute instance
#
# A compute instance is headless: you use VS Code on your laptop and connect via
# Remote-SSH (or the Azure ML studio "VS Code (Web/Desktop)" links). VS Code then
# installs its server under ~/.vscode-server automatically. The desktop `code`
# apt package is only installed on request (--desktop) or when a display exists.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/common.sh"

vscode_server_present() {
  ls -d "${HOME}"/.vscode-server/cli/servers/*/server/bin/remote-cli/code \
        "${HOME}"/.vscode-server/bin/*/bin/remote-cli/code >/dev/null 2>&1
}

install_vscode_desktop() {
  if ! is_ubuntu; then
    log_warn "This script is designed for Ubuntu. Install manually if needed."
    return 1
  fi
  log_info "Adding Microsoft GPG key and repository..."
  sudo apt-get install -y -qq wget gpg
  wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
  sudo install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
  rm -f packages.microsoft.gpg
  echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
    | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
  log_info "Installing code..."
  apt_update_quiet
  sudo apt-get install -y -qq code
  if ! command -v code >/dev/null 2>&1; then
    log_error "VS Code installation failed"
    return 1
  fi
  log_success "VS Code installed: $(code --version | head -n1)"
}

install_vscode() {
  local want_desktop=false
  [ "${1:-}" = "--desktop" ] && want_desktop=true

  log_info "Checking Visual Studio Code..."

  if command -v code >/dev/null 2>&1; then
    log_success "VS Code CLI available: $(code --version 2>/dev/null | head -n1 || command -v code)"
    return 0
  fi

  if vscode_server_present; then
    log_success "VS Code Remote-SSH server is installed on this VM"
    log_info "Use VS Code on your laptop -> Remote-SSH -> $(this_host). The 'code' command is available inside VS Code's terminal."
    return 0
  fi

  if [ "$want_desktop" = true ] || ! is_headless; then
    install_vscode_desktop
    return $?
  fi

  log_info "This VM is headless - VS Code is used from your laptop via Remote-SSH (no install needed here)."
  log_info "  Laptop: bash scripts/setup-azureml-ssh.sh, then VS Code -> Remote-SSH -> $(this_host)"
  log_info "  Or open it from Azure ML studio: Compute -> $(this_host) -> 'VS Code (Desktop)'"
  return 0
}

# Run if executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  check_not_root
  install_vscode "$@"
fi
