#!/usr/bin/env bash
set -euo pipefail

# Verify Arrive AML VM setup
# Checks that all installed tools are working correctly

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# shellcheck source=scripts/lib/common.sh
source "$LIB_DIR/common.sh"

FAILED_CHECKS=()

check_command() {
  local cmd="$1"
  local name="$2"

  if command -v "$cmd" >/dev/null 2>&1; then
    log_success "$name: $(command -v $cmd)"
    return 0
  else
    log_warn "$name: NOT FOUND"
    FAILED_CHECKS+=("$name")
    return 1
  fi
}

check_git_config() {
  local key="$1"
  local expected="$2"
  local name="$3"

  local actual
  actual=$(git config --global --get "$key" 2>/dev/null || echo "")

  if [ "$actual" = "$expected" ]; then
    log_success "$name: $actual"
    return 0
  else
    log_warn "$name: $actual (expected: $expected)"
    FAILED_CHECKS+=("Git config: $name")
    return 1
  fi
}

main() {
  log_info "Verifying Arrive AML VM Setup"
  echo

  log_info "=== System Tools ==="
  check_command git "Git"
  check_command curl "curl"
  check_command wget "wget"
  check_command htop "htop"
  check_command jq "jq"
  check_command tree "tree"
  echo

  log_info "=== Package Managers ==="
  check_command uv "uv"
  if command -v uv >/dev/null 2>&1; then
    log_info "  Version: $(uv --version)"
  fi
  echo

  log_info "=== GitHub Tools ==="
  check_command gh "GitHub CLI"
  if command -v gh >/dev/null 2>&1; then
    log_info "  Version: $(gh --version | head -n1)"
    if gh auth status >/dev/null 2>&1; then
      log_success "  Authenticated"
    else
      log_warn "  Not authenticated (run: gh auth login)"
    fi
  fi

  # Check GitHub SSH
  if [ -f "${HOME}/.ssh/id_ed25519_github" ]; then
    log_success "GitHub SSH key exists"
    if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
      log_success "GitHub SSH connection works"
    else
      log_warn "GitHub SSH connection failed"
      FAILED_CHECKS+=("GitHub SSH")
    fi
  else
    log_warn "GitHub SSH key not found"
  fi
  echo

  log_info "=== Docker ==="
  check_command docker "Docker"
  if command -v docker >/dev/null 2>&1; then
    log_info "  Version: $(docker --version)"
    if groups | grep -q docker; then
      log_success "  User in docker group"
    else
      log_warn "  User NOT in docker group (run: sudo usermod -aG docker $USER)"
      FAILED_CHECKS+=("Docker group")
    fi
  fi

  check_command docker-compose "docker-compose"
  if command -v docker-compose >/dev/null 2>&1; then
    log_info "  Version: $(docker-compose --version)"
  fi
  echo

  log_info "=== Development Tools ==="
  check_command claude "Claude CLI"
  if command -v claude >/dev/null 2>&1; then
    log_info "  Version: $(claude --version 2>/dev/null || echo 'installed')"
  fi

  check_command code "VS Code"
  if command -v code >/dev/null 2>&1; then
    log_info "  Version: $(code --version | head -n1)"
  fi

  check_command cursor "Cursor"
  echo

  log_info "=== Git Configuration ==="
  if command -v git >/dev/null 2>&1; then
    check_git_config "core.fsmonitor" "false" "core.fsmonitor"
    check_git_config "core.untrackedCache" "true" "core.untrackedCache"
    check_git_config "feature.manyFiles" "true" "feature.manyFiles"
    check_git_config "gc.auto" "0" "gc.auto"
    check_git_config "user.name" "Rick Arko" "user.name"
    check_git_config "user.email" "rarko@arrivelogistics.com" "user.email"
  fi
  echo

  log_info "=== Conda ==="
  if command -v conda >/dev/null 2>&1; then
    local auto_activate
    auto_activate=$(conda config --get auto_activate_base 2>/dev/null | grep -o 'True\|False' || echo "unknown")
    if [ "$auto_activate" = "False" ]; then
      log_success "Conda auto-activation: disabled"
    else
      log_warn "Conda auto-activation: $auto_activate"
    fi
  else
    log_info "Conda: not installed"
  fi
  echo

  log_info "=== Python Environment ==="
  if [ -f "${HOME}/.local/bin/uv" ]; then
    log_success "uv in ~/.local/bin"
  fi

  if [ -d "${HOME}/uv-envs" ]; then
    log_success "uv-envs directory exists: ${HOME}/uv-envs"
  fi
  echo

  # Summary
  print_separator
  if [ ${#FAILED_CHECKS[@]} -eq 0 ]; then
    log_success "All checks passed!"
    print_separator
    exit 0
  else
    log_warn "Some checks failed:"
    for check in "${FAILED_CHECKS[@]}"; do
      echo "  - $check"
    done
    print_separator
    log_info "Run setup again to fix missing components: bash scripts/setup-vm.sh --all"
    exit 1
  fi
}

main
