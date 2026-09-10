#!/usr/bin/env bash
set -euo pipefail

# Helper for working in fast local disk and syncing to network mount
# Azure Files is too slow for interactive git - work locally instead

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

show_usage() {
  cat << 'USAGE'
Work in fast local disk (/tmp) and sync to network mount

Usage:
  # Create local worktree
  bash scripts/lib/worktree-helper.sh init

  # Sync changes back to network mount
  bash scripts/lib/worktree-helper.sh sync

  # Status
  bash scripts/lib/worktree-helper.sh status

Why? Azure Files network mount is 10-50x slower than local disk for git.
Even with optimizations, git status takes 7+ seconds on the network mount.
USAGE
}

init_worktree() {
  local NETWORK_DIR="$(pwd)"
  local PROJECT_NAME="$(basename "$NETWORK_DIR")"
  local LOCAL_DIR="/tmp/worktree-$PROJECT_NAME"
  
  log_info "Setting up local worktree for fast git operations"
  
  if [ -d "$LOCAL_DIR" ]; then
    log_warn "Local worktree already exists: $LOCAL_DIR"
    return 1
  fi
  
  log_info "Copying $NETWORK_DIR to $LOCAL_DIR"
  cp -r "$NETWORK_DIR" "$LOCAL_DIR"
  
  # Save network path for syncing
  echo "$NETWORK_DIR" > "$LOCAL_DIR/.network-path"
  
  log_success "Local worktree created: $LOCAL_DIR"
  log_info "cd $LOCAL_DIR"
  
  # Test git performance
  cd "$LOCAL_DIR"
  log_info "Testing git performance in local disk..."
  time git status
}

sync_worktree() {
  local LOCAL_DIR="$(pwd)"
  
  if [ ! -f ".network-path" ]; then
    log_error "Not in a worktree directory (missing .network-path)"
    log_info "Run: bash scripts/lib/worktree-helper.sh init"
    return 1
  fi
  
  local NETWORK_DIR="$(cat .network-path)"
  
  log_info "Syncing changes from local to network mount..."
  log_info "  From: $LOCAL_DIR"
  log_info "  To:   $NETWORK_DIR"
  
  rsync -av --delete \
    --exclude='.git' \
    --exclude='.network-path' \
    "$LOCAL_DIR/" "$NETWORK_DIR/"
  
  log_success "Sync complete!"
}

show_status() {
  if [ -f ".network-path" ]; then
    log_info "In local worktree: $(pwd)"
    log_info "Network mount: $(cat .network-path)"
  else
    log_info "Not in a local worktree"
    log_info "Run: bash scripts/lib/worktree-helper.sh init"
  fi
}

main() {
  local cmd="${1:-}"
  
  case "$cmd" in
    init)
      init_worktree
      ;;
    sync)
      sync_worktree
      ;;
    status)
      show_status
      ;;
    -h|--help|"")
      show_usage
      ;;
    *)
      log_error "Unknown command: $cmd"
      show_usage
      exit 1
      ;;
  esac
}

main "$@"
