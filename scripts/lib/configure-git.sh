#!/usr/bin/env bash
set -euo pipefail

# Optimize Git for Azure ML network-mounted storage
# Azure ML uses SMB/CIFS network mounts (~/cloudfiles/code/Users/) which are
# slow for git operations. These settings optimize git for network storage.
#
# Expected improvement: 2-4x faster git operations (10-30s → 7-8s)
# For truly fast git (<1s), use worktree-helper.sh to work in /tmp
# Safe to run multiple times (idempotent)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/common.sh"

configure_git_performance() {
  log_info "Configuring Git for optimal performance on Azure ML network storage"

  if ! verify_command git "Git is not installed"; then
    log_error "Git must be installed first"
    return 1
  fi

  # Disable expensive file monitoring and watching
  log_info "Disabling file system monitoring..."
  git config --global core.fsmonitor false
  git config --global core.untrackedCache true
  git config --global core.preloadindex true

  # Optimize index operations
  log_info "Optimizing index operations..."
  git config --global index.threads 4
  git config --global index.version 4

  # Enable performance features
  log_info "Enabling performance features..."
  git config --global feature.manyFiles true
  git config --global core.commitGraph true
  git config --global pack.useSparse true

  # Disable expensive garbage collection (manual: git gc when needed)
  log_info "Disabling automatic garbage collection..."
  git config --global gc.auto 0

  # Increase buffers for network operations
  log_info "Increasing network buffers..."
  git config --global http.postBuffer 524288000
  git config --global ssh.postBuffer 524288000

  # Reduce unnecessary operations
  log_info "Reducing unnecessary operations..."
  git config --global fetch.prune true
  git config --global fetch.writeCommitGraph false
  git config --global core.fileMode false

  # Optimize pack operations
  log_info "Optimizing pack operations..."
  git config --global pack.threads 4
  git config --global pack.windowMemory 256m

  # Aggressive optimizations for network mounts
  log_info "Applying aggressive network mount optimizations..."
  git config --global core.checkStat minimal
  git config --global core.trustctime false
  git config --global core.ignoreStat true
  git config --global status.showUntrackedFiles no

  # Configure user (if not already set)
  if [ -z "$(git config --global user.name 2>/dev/null || true)" ]; then
    log_info "Setting git user.name..."
    git config --global user.name "Rick Arko"
  fi

  if [ -z "$(git config --global user.email 2>/dev/null || true)" ]; then
    log_info "Setting git user.email..."
    git config --global user.email "rarko@arrivelogistics.com"
  fi

  log_success "Git performance configuration complete!"
  log_warn "Note: Untracked files hidden by default (use 'git status -u' to show)"
  log_info "Expected: ~7-8s on network mount (down from 10-30s)"
  log_info "For sub-second git: use scripts/lib/worktree-helper.sh to work in /tmp"
  echo
}

# Run if executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  configure_git_performance

  print_separator
  echo "Git configuration applied. Test performance with:"
  echo "  cd ~/cloudfiles/code/Users/rarko/dev/arrive-aml"
  echo "  time git status  # Should be < 1 second"
  print_separator
fi
