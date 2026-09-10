#!/usr/bin/env bash
# Common utilities for arrive-aml setup scripts
# Source this file: source "$(dirname "$0")/lib/common.sh"

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
  echo -e "${BLUE}==> $*${NC}"
}

log_success() {
  echo -e "${GREEN}✓ $*${NC}"
}

log_warn() {
  echo -e "${YELLOW}⚠ $*${NC}"
}

log_error() {
  echo -e "${RED}✗ $*${NC}" >&2
}

# Verify a command exists
# Usage: verify_command git "Git is not installed"
verify_command() {
  local cmd="$1"
  local message="${2:-$cmd is not available}"

  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_warn "$message"
    return 1
  fi
  return 0
}

# Add a directory to PATH in ~/.bashrc (idempotent)
# Usage: add_to_path "/path/to/bin" "comment"
add_to_path() {
  local dir="$1"
  local comment="${2:-Added by arrive-aml setup}"

  if [ ! -f "${HOME}/.bashrc" ]; then
    log_warn "~/.bashrc not found, creating it"
    touch "${HOME}/.bashrc"
  fi

  # Check if already in .bashrc
  if grep -qF "$dir" "${HOME}/.bashrc" 2>/dev/null; then
    log_info "$dir already in ~/.bashrc"
    return 0
  fi

  {
    echo ""
    echo "# $comment"
    echo "export PATH=\"${dir}:\$PATH\""
  } >> "${HOME}/.bashrc"

  log_success "Added $dir to ~/.bashrc PATH"
}

# Check if running as root (warn if so)
check_not_root() {
  if [ "$EUID" -eq 0 ]; then
    log_error "This script should NOT be run as root (sudo)"
    log_error "Run as a regular user. The script will prompt for sudo when needed."
    exit 1
  fi
}

# Confirm action (for interactive mode)
# Usage: if confirm "Install Docker?"; then ...; fi
confirm() {
  local prompt="$1"
  local response

  read -rp "$prompt (y/N): " response
  case "$response" in
    [yY][eE][sS]|[yY])
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Get OS information
get_os_info() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "$ID"
  else
    echo "unknown"
  fi
}

# Check if running on Ubuntu
is_ubuntu() {
  [ "$(get_os_info)" = "ubuntu" ]
}

# Print separator line
print_separator() {
  echo "=================================================================="
}
