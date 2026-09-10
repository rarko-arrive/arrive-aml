#!/usr/bin/env bash
set -euo pipefail

# Setup persistent mirror worktree on Azure ML
# Fast local disk (/mnt/mirror) + persistent network storage (~/cloudfiles)
# See: docs/AZUREML-WORKTREE-PATTERN.md

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

show_usage() {
  cat << 'USAGE'
Setup Persistent Mirror Worktree

Usage:
  # From your SOT repository
  cd ~/cloudfiles/rarko/main/repo-name
  bash scripts/lib/setup-mirror-worktree.sh

  # Or specify repo name
  bash scripts/lib/setup-mirror-worktree.sh repo-name

  # List existing worktrees
  bash scripts/lib/setup-mirror-worktree.sh --list

What it does:
  - Creates /mnt/mirror/repo-name as a git worktree
  - Links to SOT in ~/cloudfiles/rarko/main/repo-name
  - You get fast git operations (<1s) with full persistence

See: docs/AZUREML-WORKTREE-PATTERN.md for complete guide
USAGE
}

list_worktrees() {
  log_info "Existing worktrees:"
  echo

  for sot in ~/cloudfiles/rarko/main/*/; do
    if [ -d "$sot/.git" ]; then
      local repo_name=$(basename "$sot")
      log_info "Repository: $repo_name"
      cd "$sot"
      git worktree list --porcelain | grep -E "^worktree|^branch" || true
      echo
    fi
  done
}

setup_mirror_worktree() {
  local REPO_NAME="${1:-}"

  # If no argument, try to detect from current directory
  if [ -z "$REPO_NAME" ]; then
    if [ -d .git ]; then
      REPO_NAME=$(basename "$(pwd)")
      log_info "Detected repository: $REPO_NAME"
    else
      log_error "Not in a git repository and no repo name provided"
      show_usage
      return 1
    fi
  fi

  local SOT="${HOME}/cloudfiles/rarko/main/${REPO_NAME}"
  local MIRROR="/mnt/mirror/${REPO_NAME}"

  log_info "Setting up mirror worktree for: $REPO_NAME"
  echo

  # Ensure /mnt/mirror directory exists
  if [ ! -d /mnt/mirror ]; then
    log_info "Creating /mnt/mirror directory..."
    sudo mkdir -p /mnt/mirror
    sudo chown "$USER:$USER" /mnt/mirror
    log_success "/mnt/mirror created"
  fi

  # Check if SOT exists
  if [ ! -d "$SOT/.git" ]; then
    log_error "Source of Truth not found: $SOT"
    echo
    log_info "First, clone your repository to the SOT location:"
    echo
    echo "  mkdir -p ~/cloudfiles/rarko/main"
    echo "  cd ~/cloudfiles/rarko/main"
    echo "  git clone git@github.com:your-org/$REPO_NAME.git"
    echo
    return 1
  fi

  # Check if mirror already exists
  if [ -d "$MIRROR" ]; then
    log_warn "Mirror already exists: $MIRROR"
    echo
    if confirm "Remove and recreate?"; then
      log_info "Removing existing mirror..."
      cd "$SOT"
      git worktree remove --force "$MIRROR" 2>/dev/null || true
      rm -rf "$MIRROR"
    else
      log_info "Keeping existing mirror"
      return 0
    fi
  fi

  # Create worktree
  log_info "Creating mirror worktree..."
  cd "$SOT"
  git worktree add "$MIRROR"

  echo
  print_separator
  log_success "Mirror worktree created!"
  echo
  log_info "Source of Truth (SOT): $SOT"
  log_info "Active Mirror:         $MIRROR"
  echo
  log_info "Next steps:"
  echo "  cd $MIRROR"
  echo "  cursor .  # or code ."
  echo "  git pull origin main"
  echo
  log_info "Test performance:"
  echo "  cd $MIRROR"
  echo "  time git status  # Should be <1 second ⚡"
  print_separator
}

main() {
  local cmd="${1:-}"

  case "$cmd" in
    --list|-l)
      list_worktrees
      ;;
    --help|-h|help)
      show_usage
      ;;
    *)
      setup_mirror_worktree "$@"
      ;;
  esac
}

main "$@"
