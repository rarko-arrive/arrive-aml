#!/usr/bin/env bash
set -euo pipefail

# Arrive AML VM Setup Script
# Comprehensive setup for Azure ML compute instances
#
# Usage:
#   bash scripts/setup-vm.sh --all                    # Install everything
#   bash scripts/setup-vm.sh --git-optimize --docker  # Selective install
#   bash scripts/setup-vm.sh --dry-run --all         # Show what would be installed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# shellcheck source=scripts/lib/common.sh
source "$LIB_DIR/common.sh"

# Installation flags
INSTALL_ALL=false
INSTALL_SYSTEM_TOOLS=false
INSTALL_GIT_OPTIMIZE=false
INSTALL_UV=false
INSTALL_GH=false
INSTALL_GITHUB_SSH=false
INSTALL_DISABLE_CONDA=false
INSTALL_DOCKER=false
INSTALL_CLOUDFLARED=false
INSTALL_CLAUDE=false
INSTALL_VSCODE=false
INSTALL_CURSOR=false
DRY_RUN=false
INTERACTIVE=false
RUN_VERIFY=true

# Parse command line arguments
parse_args() {
  if [ $# -eq 0 ]; then
    INTERACTIVE=true
    return
  fi

  while [ $# -gt 0 ]; do
    case "$1" in
      --all)
        INSTALL_ALL=true
        ;;
      --system-tools)
        INSTALL_SYSTEM_TOOLS=true
        ;;
      --git-optimize)
        INSTALL_GIT_OPTIMIZE=true
        ;;
      --uv)
        INSTALL_UV=true
        ;;
      --gh)
        INSTALL_GH=true
        ;;
      --github-ssh)
        INSTALL_GITHUB_SSH=true
        ;;
      --disable-conda)
        INSTALL_DISABLE_CONDA=true
        ;;
      --docker)
        INSTALL_DOCKER=true
        ;;
      --cloudflared)
        INSTALL_CLOUDFLARED=true
        ;;
      --claude)
        INSTALL_CLAUDE=true
        ;;
      --vscode)
        INSTALL_VSCODE=true
        ;;
      --cursor)
        INSTALL_CURSOR=true
        ;;
      --dry-run)
        DRY_RUN=true
        ;;
      --no-verify)
        RUN_VERIFY=false
        ;;
      -h|--help)
        show_usage
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        show_usage
        exit 1
        ;;
    esac
    shift
  done

  # If --all, enable everything
  if [ "$INSTALL_ALL" = true ]; then
    INSTALL_SYSTEM_TOOLS=true
    INSTALL_GIT_OPTIMIZE=true
    INSTALL_UV=true
    INSTALL_GH=true
    INSTALL_GITHUB_SSH=true
    INSTALL_DISABLE_CONDA=true
    INSTALL_DOCKER=true
    INSTALL_CLOUDFLARED=true
    INSTALL_CLAUDE=true
    INSTALL_VSCODE=true
    INSTALL_CURSOR=true
  fi
}

show_usage() {
  cat << EOF
Arrive AML VM Setup Script

Usage: bash scripts/setup-vm.sh [OPTIONS]

Options:
  --all              Install and configure everything (recommended)
  --system-tools     Install essential system tools (git, curl, wget, htop, jq, tree)
  --git-optimize     Optimize git for Azure network-mounted storage (CRITICAL!)
  --uv               Install uv package manager
  --gh               Install GitHub CLI (gh)
  --github-ssh       Configure GitHub SSH authentication
  --disable-conda    Disable conda auto-activation
  --docker           Install Docker Engine and docker-compose
  --cloudflared      Install cloudflared (Cloudflare tunnel client)
  --claude           Install Claude CLI
  --vscode           Check VS Code Remote-SSH server (desktop install only with a display)
  --cursor           Check Cursor Remote-SSH server (desktop install only with a display)
  --dry-run          Show what would be installed without actually installing
  --no-verify        Skip verify-setup.sh at the end (bootstrap.sh runs it itself)
  -h, --help         Show this help message

Examples:
  # Quick start - install everything:
  bash scripts/setup-vm.sh --all

  # Minimal setup - just git optimization and essential tools:
  bash scripts/setup-vm.sh --git-optimize --system-tools --uv

  # Development tools only:
  bash scripts/setup-vm.sh --git-optimize --docker --gh --github-ssh

  # Check what would be installed:
  bash scripts/setup-vm.sh --dry-run --all

Interactive Mode:
  Run without arguments for interactive prompts:
  bash scripts/setup-vm.sh
EOF
}

interactive_mode() {
  log_info "Arrive AML VM Setup - Interactive Mode"
  echo
  log_info "This script will set up your Azure ML compute instance with your preferred tools."
  log_info "Answer the following questions to customize your setup:"
  echo

  if confirm "Install essential system tools? (git, curl, wget, htop, jq, tree)"; then
    INSTALL_SYSTEM_TOOLS=true
  fi

  if confirm "Optimize git for Azure network storage? (HIGHLY RECOMMENDED - 10-50x faster)"; then
    INSTALL_GIT_OPTIMIZE=true
  fi

  if confirm "Install uv package manager?"; then
    INSTALL_UV=true
  fi

  if confirm "Install GitHub CLI (gh)?"; then
    INSTALL_GH=true
  fi

  if confirm "Configure GitHub SSH authentication?"; then
    INSTALL_GITHUB_SSH=true
  fi

  if confirm "Disable conda auto-activation?"; then
    INSTALL_DISABLE_CONDA=true
  fi

  if confirm "Install Docker and docker-compose?"; then
    INSTALL_DOCKER=true
  fi

  if confirm "Install cloudflared (public HTTPS tunnels)?"; then
    INSTALL_CLOUDFLARED=true
  fi

  if confirm "Install Claude CLI?"; then
    INSTALL_CLAUDE=true
  fi

  if confirm "Check VS Code Remote-SSH server?"; then
    INSTALL_VSCODE=true
  fi

  if confirm "Check Cursor Remote-SSH server?"; then
    INSTALL_CURSOR=true
  fi

  echo
}

show_summary() {
  log_info "Installation Summary:"
  echo
  [ "$INSTALL_SYSTEM_TOOLS" = true ] && echo "  ✓ System tools (git, curl, wget, htop, jq, tree)"
  [ "$INSTALL_GIT_OPTIMIZE" = true ] && echo "  ✓ Git performance optimization"
  [ "$INSTALL_UV" = true ] && echo "  ✓ uv package manager"
  [ "$INSTALL_GH" = true ] && echo "  ✓ GitHub CLI (gh)"
  [ "$INSTALL_GITHUB_SSH" = true ] && echo "  ✓ GitHub SSH configuration"
  [ "$INSTALL_DISABLE_CONDA" = true ] && echo "  ✓ Disable conda auto-activation"
  [ "$INSTALL_DOCKER" = true ] && echo "  ✓ Docker Engine and docker-compose"
  [ "$INSTALL_CLOUDFLARED" = true ] && echo "  ✓ cloudflared (Cloudflare tunnel)"
  [ "$INSTALL_CLAUDE" = true ] && echo "  ✓ Claude Code CLI"
  [ "$INSTALL_VSCODE" = true ] && echo "  ✓ VS Code (Remote-SSH server check)"
  [ "$INSTALL_CURSOR" = true ] && echo "  ✓ Cursor (Remote-SSH server check)"
  echo
}

run_installation() {
  log_info "Starting installation..."
  echo

  # System tools first (provides dependencies)
  if [ "$INSTALL_SYSTEM_TOOLS" = true ]; then
    bash "$LIB_DIR/install-system-tools.sh" || log_error "System tools installation failed"
  fi

  # Git optimization (critical for Azure ML)
  if [ "$INSTALL_GIT_OPTIMIZE" = true ]; then
    bash "$LIB_DIR/configure-git.sh" || log_error "Git optimization failed"
  fi

  # Disable conda before other installs
  if [ "$INSTALL_DISABLE_CONDA" = true ]; then
    bash "$LIB_DIR/disable-conda.sh" || log_warn "Conda disable failed"
  fi

  # Package managers
  if [ "$INSTALL_UV" = true ]; then
    bash "$LIB_DIR/install-uv.sh" || log_error "uv installation failed"
  fi

  # GitHub tools
  if [ "$INSTALL_GH" = true ]; then
    bash "$LIB_DIR/install-gh.sh" || log_error "gh installation failed"
  fi

  if [ "$INSTALL_GITHUB_SSH" = true ]; then
    bash "$LIB_DIR/configure-github-ssh.sh" || log_warn "GitHub SSH configuration failed"
  fi

  # Docker
  if [ "$INSTALL_DOCKER" = true ]; then
    bash "$LIB_DIR/install-docker.sh" || log_error "Docker installation failed"
  fi

  if [ "$INSTALL_CLOUDFLARED" = true ]; then
    bash "$LIB_DIR/install-cloudflared.sh" || log_error "cloudflared installation failed"
  fi

  # Development tools
  if [ "$INSTALL_CLAUDE" = true ]; then
    bash "$LIB_DIR/install-claude.sh" || log_warn "Claude Code installation failed"
  fi

  if [ "$INSTALL_VSCODE" = true ]; then
    bash "$LIB_DIR/install-vscode.sh" || log_warn "VS Code check failed"
  fi

  if [ "$INSTALL_CURSOR" = true ]; then
    bash "$LIB_DIR/install-cursor.sh" || log_warn "Cursor check failed"
  fi

  echo
  log_success "Installation complete!"
}

main() {
  check_not_root

  echo
  print_separator
  log_info "Arrive AML - Azure ML VM Setup"
  log_info "User: $(whoami)@$(hostname)"
  print_separator
  echo

  parse_args "$@"

  if [ "$INTERACTIVE" = true ]; then
    interactive_mode
  fi

  show_summary

  if [ "$DRY_RUN" = true ]; then
    log_info "Dry run mode - no changes will be made"
    exit 0
  fi

  if [ "$INTERACTIVE" = true ]; then
    if ! confirm "Proceed with installation?"; then
      log_info "Installation cancelled"
      exit 0
    fi
    echo
  fi

  run_installation

  if [ "$RUN_VERIFY" != true ]; then
    return 0
  fi

  # Run verification
  echo
  log_info "Running verification..."
  local verify_rc=0
  if [ -f "$SCRIPT_DIR/verify-setup.sh" ]; then
    bash "$SCRIPT_DIR/verify-setup.sh" || verify_rc=$?
  else
    log_warn "Verification script not found"
  fi

  echo
  print_separator
  if [ "$verify_rc" -eq 0 ]; then
    log_success "Setup complete! Your Azure ML VM is ready."
  else
    log_warn "Setup finished but verification reported problems (fixes listed above)."
  fi
  echo
  log_info "Next steps:"
  log_info "  1. Reload your shell: source ~/.bashrc"
  log_info "  2. If Docker was just installed: newgrp docker"
  log_info "  3. Repos, mirrors and venvs: bash scripts/bootstrap.sh   (or: aml-bootstrap)"
  print_separator
  return "$verify_rc"
}

main "$@"
