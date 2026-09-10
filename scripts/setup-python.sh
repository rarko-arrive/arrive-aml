#!/usr/bin/env bash
set -euo pipefail

# Quick Python environment setup for arrive-aml
# Run this after setup-vm.sh --all

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/lib/setup-python-venv.sh" "$(dirname "$SCRIPT_DIR")"
