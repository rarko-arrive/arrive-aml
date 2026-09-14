#!/usr/bin/env bash
set -euo pipefail

# Python/uv bootstrap for THIS repo (kept for backwards compatibility).
# Creates the local-disk venv and the .venv symlink, then runs the smoke test.
#
#   bash scripts/bootstrap-azureml.sh
#
# For the full VM setup (tools + all repos + mirrors + venvs) use:
#   bash scripts/bootstrap.sh

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/scripts/lib/install-uv.sh"
bash "$ROOT/scripts/lib/setup-python-venv.sh" "$ROOT"

echo
echo "==> Smoke test: import pandas + polars from .venv"
cd "$ROOT"
UV_PROJECT_ENVIRONMENT="$(readlink -f "$ROOT/.venv")"
export UV_PROJECT_ENVIRONMENT
uv run python -c "import pandas, polars; print('ok: pandas', pandas.__version__, 'polars', polars.__version__)"
