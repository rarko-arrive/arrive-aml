#!/usr/bin/env bash
set -euo pipefail

# Disable conda auto-activation
# Azure ML may depend on conda, so we don't remove it - just disable auto-activation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/common.sh"

disable_conda() {
  log_info "Disabling conda auto-activation..."

  # Check if conda is installed
  if ! command -v conda >/dev/null 2>&1; then
    log_warn "conda not found - nothing to disable"
    return 0
  fi

  # Disable auto-activation via conda config
  log_info "Setting conda auto_activate_base to false..."
  conda config --set auto_activate_base false 2>/dev/null || true

  # Comment out conda init block in .bashrc
  if [ -f "${HOME}/.bashrc" ] && grep -q "# >>> conda initialize >>>" "${HOME}/.bashrc" 2>/dev/null; then
    log_info "Commenting out conda init block in ~/.bashrc..."

    # Create backup
    cp "${HOME}/.bashrc" "${HOME}/.bashrc.bak"

    # Comment out the conda init block
    sed -i.tmp '/# >>> conda initialize >>>/,/# <<< conda initialize <<</s/^/# /' "${HOME}/.bashrc"
    rm -f "${HOME}/.bashrc.tmp"

    log_success "conda init block commented out"
  else
    log_info "No conda init block found in ~/.bashrc"
  fi

  log_success "conda auto-activation disabled!"
  log_info "Note: conda is still installed and can be activated manually with: conda activate base"
  log_info "Rationale: Azure ML may have dependencies on the base conda environment"
}

# Run if executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  check_not_root
  disable_conda
fi
