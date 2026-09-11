#!/bin/bash
# Setup all configured repositories with mirror worktrees
# Reads repos.conf and clones/mirrors each repository

set -e

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# Paths
SOT_BASE="$HOME/cloudfiles/rarko/main"
MIRROR_BASE="/mnt/mirror"
REPOS_CONF="$SCRIPT_DIR/../repos.conf"

print_separator() {
  echo "=================================================================="
}

setup_repos() {
  log_info "Setting up repositories from repos.conf"
  echo

  # Ensure base directories exist
  mkdir -p "$SOT_BASE"

  # Create /mnt/mirror if it doesn't exist
  if [ ! -d "$MIRROR_BASE" ]; then
    log_info "Creating $MIRROR_BASE directory..."
    sudo mkdir -p "$MIRROR_BASE"
    sudo chown "$USER:$USER" "$MIRROR_BASE"
    log_success "/mnt/mirror created"
  fi

  # Check if repos.conf exists
  if [ ! -f "$REPOS_CONF" ]; then
    log_error "repos.conf not found at: $REPOS_CONF"
    exit 1
  fi

  # Read repos.conf and process each repo
  local clone_count=0
  local mirror_count=0
  local skip_count=0

  while IFS='|' read -r repo_url repo_name auto_mirror || [ -n "$repo_url" ]; do
    # Skip comments and empty lines
    [[ "$repo_url" =~ ^#.*$ ]] && continue
    [[ -z "$repo_url" ]] && continue

    # Trim whitespace
    repo_url=$(echo "$repo_url" | xargs)
    repo_name=$(echo "$repo_name" | xargs)
    auto_mirror=$(echo "$auto_mirror" | xargs)

    echo
    log_info "Processing: $repo_name"

    local sot_path="$SOT_BASE/$repo_name"
    local mirror_path="$MIRROR_BASE/$repo_name"

    # Clone to SOT if doesn't exist
    if [ ! -d "$sot_path" ]; then
      log_info "Cloning $repo_name to SOT..."
      cd "$SOT_BASE"
      if git clone "$repo_url" "$repo_name"; then
        log_success "Cloned $repo_name"
        ((clone_count++))
      else
        log_error "Failed to clone $repo_name"
        continue
      fi
    else
      log_info "Repository already exists at SOT: $sot_path"
      ((skip_count++))
    fi

    # Create mirror worktree if requested
    if [ "$auto_mirror" = "yes" ]; then
      if [ ! -d "$mirror_path" ]; then
        log_info "Creating mirror worktree for $repo_name..."
        cd "$sot_path"

        # Check if worktree already registered
        if git worktree list | grep -q "$mirror_path"; then
          log_info "Worktree already registered, removing old entry..."
          git worktree remove --force "$mirror_path" 2>/dev/null || true
        fi

        # Create worktree
        if git worktree add "$mirror_path"; then
          log_success "Mirror created: $mirror_path"
          ((mirror_count++))
        else
          log_warn "Failed to create mirror for $repo_name"
        fi
      else
        log_info "Mirror already exists: $mirror_path"
      fi
    fi

  done < "$REPOS_CONF"

  # Summary
  echo
  print_separator
  log_success "Repository setup complete!"
  echo
  echo "Summary:"
  echo "  Cloned: $clone_count new repositories"
  echo "  Mirrors: $mirror_count worktrees created"
  echo "  Skipped: $skip_count existing repositories"
  echo
  echo "Locations:"
  echo "  SOT (Source of Truth): $SOT_BASE"
  echo "  Mirrors (Fast work):   $MIRROR_BASE"
  echo
  log_info "Work in mirrors for 100x faster git operations!"
  echo
  echo "Example:"
  echo "  cd $MIRROR_BASE/arrive-aml"
  echo "  git status  # <1 second!"
  print_separator
}

# Show usage
usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Setup all repositories from repos.conf with optional mirror worktrees.

Options:
  --help          Show this help message
  --list          List repositories in repos.conf
  --skip-mirrors  Clone repos but don't create mirror worktrees

Examples:
  $0                    # Setup all repos with mirrors
  $0 --list             # Show configured repos
  $0 --skip-mirrors     # Clone only, no mirrors

Configuration:
  Edit repos.conf to add/remove repositories
EOF
}

# List repos from config
list_repos() {
  log_info "Configured repositories in repos.conf:"
  echo
  printf "%-40s %-20s %-10s\n" "Repository" "Name" "Mirror"
  printf "%-40s %-20s %-10s\n" "----------" "----" "------"

  while IFS='|' read -r repo_url repo_name auto_mirror || [ -n "$repo_url" ]; do
    [[ "$repo_url" =~ ^#.*$ ]] && continue
    [[ -z "$repo_url" ]] && continue

    repo_url=$(echo "$repo_url" | xargs)
    repo_name=$(echo "$repo_name" | xargs)
    auto_mirror=$(echo "$auto_mirror" | xargs)

    printf "%-40s %-20s %-10s\n" "$repo_url" "$repo_name" "$auto_mirror"
  done < "$REPOS_CONF"
  echo
}

# Main
main() {
  check_not_root

  case "${1:-}" in
    --help)
      usage
      exit 0
      ;;
    --list)
      list_repos
      exit 0
      ;;
    --skip-mirrors)
      log_warn "Skipping mirror creation (not implemented yet)"
      setup_repos
      ;;
    "")
      setup_repos
      ;;
    *)
      log_error "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
}

main "$@"
