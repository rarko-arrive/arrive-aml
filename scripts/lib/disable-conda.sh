#!/usr/bin/env bash
set -euo pipefail

# Disable conda auto-activation
# Azure ML may depend on conda, so we don't remove it - just disable auto-activation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/common.sh"

# Azure's image leaves `conda activate azureml_py38` AFTER the init block.
# Commenting out only the init block removes conda from PATH, so the next
# login runs a command that does not exist. Scrub bashrc even when `conda`
# itself is not currently on PATH (that is the broken state we are fixing).
quiet_conda_bashrc() {
  local rc="${HOME}/.bashrc"
  [ -f "$rc" ] || return 0

  if ! grep -q "conda initialize" "$rc" && ! grep -qE '^[[:space:]]*conda[[:space:]]' "$rc"; then
    log_info "No conda auto-activation in ~/.bashrc"
    return 0
  fi

  cp "$rc" "${rc}.bak"

  # Collapse '# # # >>> conda' left by older runs of this script back to one comment.
  sed -i '/conda initialize >>>/,/conda initialize <<</ s/^\(# \)\{2,\}/# /' "$rc"

  # Comment the init block once. Already-commented lines stay as they are,
  # so re-running does not stack another '# ' on every line.
  sed -i '/# >>> conda initialize >>>/,/# <<< conda initialize <<</ { /^[[:space:]]*#/! s/^/# /; }' "$rc"

  # Azure's activate line sits outside the init block.
  if grep -qE '^[[:space:]]*conda[[:space:]]' "$rc"; then
    sed -i -E 's/^[[:space:]]*conda[[:space:]].*/# arrive-aml: &/' "$rc"
    log_success "Commented conda commands in ~/.bashrc (they ran on every login with conda off PATH)"
  else
    log_success "conda init in ~/.bashrc is already quiet"
  fi
}

disable_conda() {
  log_info "Disabling conda auto-activation..."

  if command -v conda >/dev/null 2>&1; then
    log_info "Setting conda auto_activate_base to false..."
    conda config --set auto_activate_base false 2>/dev/null || true
  else
    log_info "conda is not on PATH - still checking ~/.bashrc for leftover activate lines"
  fi

  quiet_conda_bashrc

  log_success "conda will not auto-activate in new shells"
  log_info "The Anaconda install is unchanged. Activate it by hand when you need it: source /anaconda/etc/profile.d/conda.sh && conda activate azureml_py38"
}

# Run if executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  check_not_root
  disable_conda
fi
