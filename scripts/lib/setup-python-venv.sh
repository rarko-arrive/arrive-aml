#!/usr/bin/env bash
set -euo pipefail

# Set up the uv virtual environment for a project (idempotent)
#
# The venv lives on fast local disk (UV_VENV_ROOT, default /mnt/uv-venvs) and
# the project gets a `.venv` symlink pointing at it, so IDEs and `uv run` just
# work while nothing heavy sits on the slow cloudfiles mount or fills the OS disk.
#
# Usage: bash scripts/lib/setup-python-venv.sh [PROJECT_ROOT]
#   PROJECT_ROOT defaults to the arrive-aml checkout this script belongs to.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/common.sh"

setup_python_venv() {
  local REPO_ROOT
  REPO_ROOT="$(cd "${1:-$ARRIVE_ROOT}" && pwd)"
  local REPO_NAME
  REPO_NAME="$(basename "$REPO_ROOT")"
  local VENV_PATH="${UV_VENV_ROOT}/${REPO_NAME}"
  local VENV_LINK="${REPO_ROOT}/.venv"

  log_info "Python environment for: $REPO_NAME"

  if [ ! -f "${REPO_ROOT}/pyproject.toml" ]; then
    log_info "No pyproject.toml in $REPO_ROOT - skipping venv"
    return 0
  fi

  export PATH="${HOME}/.local/bin:${PATH}"
  if ! command -v uv >/dev/null 2>&1; then
    log_error "uv not found. Run: bash scripts/lib/install-uv.sh"
    return 1
  fi

  ensure_local_dir "$UV_VENV_ROOT"
  ensure_local_dir "$ARRIVE_UV_CACHE_DIR"
  export UV_CACHE_DIR="$ARRIVE_UV_CACHE_DIR"
  export UV_PROJECT_ENVIRONMENT="$VENV_PATH"

  if [ -f "${REPO_ROOT}/.python-version" ]; then
    local py
    py="$(tr -d '[:space:]' < "${REPO_ROOT}/.python-version")"
    if [ -n "$py" ]; then
      log_info "Ensuring Python ${py} (from .python-version)..."
      uv python install "$py" >/dev/null 2>&1 || uv python install "$py"
    fi
  fi

  log_info "uv sync -> $VENV_PATH"
  (cd "$REPO_ROOT" && uv sync)

  # .venv symlink in the project (gitignored), replacing any real venv on the mount
  if [ -L "$VENV_LINK" ]; then
    ln -sfn "$VENV_PATH" "$VENV_LINK"
  elif [ -d "$VENV_LINK" ]; then
    local bak="${VENV_LINK}.bak-$(date +%Y%m%d%H%M%S)"
    log_warn ".venv is a real directory on the mount - moving it to $bak (delete it when happy)"
    mv "$VENV_LINK" "$bak"
    ln -s "$VENV_PATH" "$VENV_LINK"
  else
    ln -s "$VENV_PATH" "$VENV_LINK"
  fi

  if [ ! -x "${VENV_LINK}/bin/python" ]; then
    log_error ".venv/bin/python not found after setup"
    return 1
  fi

  # .env from template (never overwrite an existing .env)
  if [ ! -f "${REPO_ROOT}/.env" ] && [ -f "${REPO_ROOT}/.env.example" ]; then
    cp "${REPO_ROOT}/.env.example" "${REPO_ROOT}/.env"
    log_info "Created .env from .env.example"
  fi
  if [ -f "${REPO_ROOT}/.env" ] && grep -q "^UV_PROJECT_ENVIRONMENT=" "${REPO_ROOT}/.env"; then
    sed -i "s|^UV_PROJECT_ENVIRONMENT=.*|UV_PROJECT_ENVIRONMENT=${VENV_PATH}|" "${REPO_ROOT}/.env"
  fi

  log_success "venv ready: ${VENV_LINK} -> ${VENV_PATH} ($("${VENV_LINK}/bin/python" -V 2>&1))"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  check_not_root
  setup_python_venv "$@"
fi
