#!/usr/bin/env bash
set -euo pipefail

# Bootstrap an Azure ML compute instance for the Arrive-Logistics DS Cursor demo:
# uv → local-disk venv (~/uv-envs/...) → .venv symlink → offline smoke test.
#
# Run on the VM after Remote-SSH into the repo:
#   bash scripts/bootstrap-azureml.sh
#
# Laptop SSH wiring is separate: bash scripts/setup-azureml-ssh.sh

REPO="arrive-aml"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UV_BIN_DIR="${HOME}/.local/bin"
UV_ENV_ROOT="${HOME}/uv-envs"
UV_PROJECT_ENVIRONMENT="${UV_ENV_ROOT}/${REPO}"

cd "$ROOT"

echo "==> Arrive AML — Azure ML bootstrap"
echo "    repo: $ROOT"
echo

# --- uv on PATH ---
export PATH="${UV_BIN_DIR}:${PATH}"

if ! command -v uv >/dev/null 2>&1; then
  echo "==> Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="${UV_BIN_DIR}:${PATH}"
else
  echo "==> uv already installed: $(command -v uv)"
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "Error: uv not found on PATH after install (expected ${UV_BIN_DIR}/uv)." >&2
  echo "Open a new shell or: source ~/.bashrc" >&2
  exit 1
fi

# Persist PATH for future interactive shells (idempotent).
if [ -f "${HOME}/.bashrc" ] && ! grep -qF "${UV_BIN_DIR}" "${HOME}/.bashrc" 2>/dev/null; then
  {
    echo ""
    echo "# uv (arrive-aml bootstrap-azureml.sh)"
    echo "export PATH=\"${UV_BIN_DIR}:\$PATH\""
  } >>"${HOME}/.bashrc"
  echo "Added ${UV_BIN_DIR} to ~/.bashrc"
fi

# --- Local-disk project env (cloudfiles mounts are slow; /mnt may wipe) ---
echo "==> Creating env at ${UV_PROJECT_ENVIRONMENT}"
mkdir -p "${UV_ENV_ROOT}"
export UV_PROJECT_ENVIRONMENT

if [ ! -f "${ROOT}/.python-version" ]; then
  echo "Error: missing ${ROOT}/.python-version" >&2
  exit 1
fi
PYTHON_VERSION="$(tr -d '[:space:]' <"${ROOT}/.python-version")"
if [ -z "${PYTHON_VERSION}" ]; then
  echo "Error: ${ROOT}/.python-version is empty" >&2
  exit 1
fi

echo "==> Ensuring Python ${PYTHON_VERSION} (from .python-version)..."
uv python install "${PYTHON_VERSION}"

echo "==> uv sync..."
uv sync

echo "==> Linking .venv → ${UV_PROJECT_ENVIRONMENT}"
ln -sfn "${UV_PROJECT_ENVIRONMENT}" "${ROOT}/.venv"

if [ ! -x "${ROOT}/.venv/bin/python" ]; then
  echo "Error: .venv/bin/python missing after sync/symlink." >&2
  exit 1
fi

echo "==> Smoke test: uv run hello"
uv run hello

echo
echo "=================================================================="
echo "Bootstrap complete."
echo
echo "  venv:    ${UV_PROJECT_ENVIRONMENT}"
echo "  symlink: ${ROOT}/.venv → ${UV_PROJECT_ENVIRONMENT}"
echo "  python:  $(${ROOT}/.venv/bin/python -V 2>&1)"
echo
echo "Next steps (Cursor Remote-SSH, this folder open):"
echo "  1. Open notebooks/DEMO.ipynb"
echo "  2. Select Kernel → Python Environments… → .venv"
echo "     (path should end with arrive-aml/.venv/bin/python)"
echo "  3. Run the first cell; use Agent with @notebooks/DEMO.ipynb"
echo
echo "Optional Snowflake: cp .env.example .env  # set SNOWFLAKE_PASSWORD"
echo "=================================================================="
