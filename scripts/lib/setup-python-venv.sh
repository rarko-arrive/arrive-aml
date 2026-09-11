#!/usr/bin/env bash
set -euo pipefail

# Setup Python virtual environment for arrive-aml
# Creates venv on fast local disk (~/uv-envs/) and symlinks to .venv

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

setup_python_venv() {
  local REPO_ROOT="${1:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
  local REPO_NAME="$(basename "$REPO_ROOT")"
  local UV_BIN_DIR="${HOME}/.local/bin"
  local UV_ENV_ROOT="${HOME}/uv-envs"
  local UV_PROJECT_ENVIRONMENT="${UV_ENV_ROOT}/${REPO_NAME}"
  local VENV_LINK="${REPO_ROOT}/.venv"

  log_info "Setting up Python virtual environment for: $REPO_NAME"

  cd "$REPO_ROOT"

  # Check if uv is installed
  if ! command -v uv >/dev/null 2>&1; then
    log_error "uv not found. Run: bash scripts/setup-vm.sh --uv"
    return 1
  fi

  # Check for .python-version
  if [ ! -f "${REPO_ROOT}/.python-version" ]; then
    log_error "Missing ${REPO_ROOT}/.python-version"
    return 1
  fi

  local PYTHON_VERSION="$(tr -d '[:space:]' <"${REPO_ROOT}/.python-version")"
  if [ -z "${PYTHON_VERSION}" ]; then
    log_error "${REPO_ROOT}/.python-version is empty"
    return 1
  fi

  log_info "Python version: $PYTHON_VERSION"

  # Create venv directory on local disk (fast!)
  log_info "Creating venv at: ${UV_PROJECT_ENVIRONMENT}"
  mkdir -p "${UV_ENV_ROOT}"

  # Install Python if needed
  log_info "Ensuring Python ${PYTHON_VERSION}..."
  uv python install "${PYTHON_VERSION}"

  # Create/sync venv
  export UV_PROJECT_ENVIRONMENT
  log_info "Running uv sync..."
  uv sync

  # Create symlink in repo
  if [ -L "$VENV_LINK" ]; then
    log_info ".venv symlink already exists"
  elif [ -e "$VENV_LINK" ]; then
    log_warn ".venv exists but is not a symlink. Backing up..."
    mv "$VENV_LINK" "${VENV_LINK}.bak"
    ln -sfn "${UV_PROJECT_ENVIRONMENT}" "$VENV_LINK"
  else
    log_info "Creating .venv symlink..."
    ln -sfn "${UV_PROJECT_ENVIRONMENT}" "$VENV_LINK"
  fi

  # Verify
  if [ ! -x "${VENV_LINK}/bin/python" ]; then
    log_error ".venv/bin/python not found after setup"
    return 1
  fi

  # Create .env if missing
  if [ ! -f "${REPO_ROOT}/.env" ] && [ -f "${REPO_ROOT}/.env.example" ]; then
    log_info "Creating .env from .env.example..."
    cp "${REPO_ROOT}/.env.example" "${REPO_ROOT}/.env"

    # Update UV_PROJECT_ENVIRONMENT in .env
    if grep -q "^UV_PROJECT_ENVIRONMENT=" "${REPO_ROOT}/.env"; then
      sed -i "s|^UV_PROJECT_ENVIRONMENT=.*|UV_PROJECT_ENVIRONMENT=${UV_PROJECT_ENVIRONMENT}|" "${REPO_ROOT}/.env"
    else
      echo "UV_PROJECT_ENVIRONMENT=${UV_PROJECT_ENVIRONMENT}" >> "${REPO_ROOT}/.env"
    fi

    log_success ".env created and configured"
  fi

  log_success "Python virtual environment ready!"
  echo
  log_info "Location: ${UV_PROJECT_ENVIRONMENT}"
  log_info "Symlink:  ${VENV_LINK} → ${UV_PROJECT_ENVIRONMENT}"
  log_info "Python:   $(${VENV_LINK}/bin/python -V 2>&1)"
  echo
  log_info "VS Code will now find the interpreter automatically"
  log_info "Activate with: source .venv/bin/activate"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  check_not_root
  setup_python_venv "$@"
fi
