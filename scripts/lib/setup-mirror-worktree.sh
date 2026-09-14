#!/usr/bin/env bash
set -euo pipefail

# Create (or repair) the /mnt/mirror local clone for ONE repository.
# See docs/AZUREML-WORKTREE-PATTERN.md
#
# Usage:
#   bash scripts/lib/setup-mirror-worktree.sh REPO_NAME     # repo in the SOT base
#   bash scripts/lib/setup-mirror-worktree.sh /path/to/sot  # explicit SOT path
#   bash scripts/lib/setup-mirror-worktree.sh               # detect from cwd
#   bash scripts/lib/setup-mirror-worktree.sh --list        # show worktrees of all SOT repos

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/mirror.sh
source "$SCRIPT_DIR/mirror.sh"

show_usage() {
  sed -n '3,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

list_worktrees() {
  local sot_base
  sot_base="$(detect_sot_base)" || { log_error "SOT base not found"; return 1; }
  local sot
  for sot in "$sot_base"/*/; do
    [ -d "$sot/.git" ] || continue
    log_info "$(basename "$sot")"
    if mirror_is_valid "$sot" "${MIRROR_BASE}/$(basename "$sot")"; then
      echo "  mirror ${MIRROR_BASE}/$(basename "$sot") [$(git -C "${MIRROR_BASE}/$(basename "$sot")" rev-parse --abbrev-ref HEAD)]  unsynced: $(mirror_unsynced_count "${MIRROR_BASE}/$(basename "$sot")")"
    else
      echo "  no mirror"
    fi
  done
}

setup_mirror_worktree() {
  local arg="${1:-}" sot sot_base name

  if [ -n "$arg" ] && [ -d "$arg/.git" ]; then
    sot="$(cd "$arg" && pwd)"
  elif [ -n "$arg" ]; then
    sot_base="$(detect_sot_base)" || { log_error "SOT base not found"; return 1; }
    sot="${sot_base}/${arg}"
  else
    # detect from cwd: works from the SOT or from a mirror
    local common
    common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
    [ -n "$common" ] || { log_error "Not in a git repository and no repo given"; show_usage; return 1; }
    sot="$(stable_cloudfiles_path "$(dirname "$common")")"
  fi

  name="$(basename "$sot")"
  ensure_mirror_worktree "$sot" "${MIRROR_BASE}/${name}" || return 1

  echo
  log_info "Next: cd ${MIRROR_BASE}/${name}   (git status here is <1s)"
}

main() {
  case "${1:-}" in
    --list|-l) list_worktrees ;;
    --help|-h|help) show_usage ;;
    *) check_not_root; setup_mirror_worktree "$@" ;;
  esac
}

main "$@"
