#!/usr/bin/env bash
set -euo pipefail

# Install uv package manager
# Extracted and reused from bootstrap-azureml.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/common.sh"

install_uv() {
  local UV_BIN_DIR="${HOME}/.local/bin"

  log_info "Installing uv package manager..."

  # Add to PATH for this session
  export PATH="${UV_BIN_DIR}:${PATH}"

  if command -v uv >/dev/null 2>&1; then
    log_success "uv already installed: $(command -v uv)"
    log_info "Version: $(uv --version)"
    return 0
  fi

  log_info "Downloading and installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh

  # Add to PATH again after install
  export PATH="${UV_BIN_DIR}:${PATH}"

  if ! command -v uv >/dev/null 2>&1; then
    log_error "uv not found on PATH after install (expected ${UV_BIN_DIR}/uv)"
    log_error "Open a new shell or: source ~/.bashrc"
    return 1
  fi

  # Persist PATH for future shells
  add_to_path "$UV_BIN_DIR" "uv package manager (arrive-aml setup)"

  log_success "uv installed successfully!"
  log_info "Version: $(uv --version)"
}

# Run if executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  check_not_root
  install_uv
fi
