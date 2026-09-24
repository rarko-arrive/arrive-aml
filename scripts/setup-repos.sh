#!/usr/bin/env bash
set -euo pipefail

# Set up all configured repositories (idempotent)
#   1. clone each repo from repos.conf (+ ~/.config/arrive-aml/repos.conf) into the
#      SOT (~/cloudfiles/code/Users/<you>/main)
#   2. create/repair its fast local mirror clone on /mnt/mirror  (AUTO_MIRROR=yes)
#   3. create/refresh its uv venv on local disk + .venv symlink in the mirror
#
# Safe to re-run after every VM restart (/mnt is wiped on stop/start).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/mirror.sh
source "$SCRIPT_DIR/lib/mirror.sh"

REPOS_CONF="${ARRIVE_ROOT}/repos.conf"
SKIP_MIRRORS=false
SKIP_VENVS=false
ONLY_REPO=""
ADD_REPO=""

usage() {
  cat <<USAGE
Usage: bash scripts/setup-repos.sh [OPTIONS]

Clone repos into the SOT, create fast mirror clones and venvs.

Options:
  --list          List the configured repositories
  --only NAME     Only process this repository
  --add REPO      Add a repo (owner/name or git URL) to your personal list
                  (~/.config/arrive-aml/repos.conf) and set it up now
  --skip-mirrors  Clone only (no /mnt/mirror clones, no venvs)
  --skip-venvs    Do not create Python venvs
  --help          Show this help

Configuration: team repos in repos.conf, yours in ${ARRIVE_EXTRA_REPOS_FILE}
Format: REPO|NAME|AUTO_MIRROR   (REPO: {org}/name, owner/name or a git URL)
USAGE
}

read_repos() {
  # prints: spec name auto_mirror, team repos first, then personal ones
  local spec name mirror
  while IFS='|' read -r spec name mirror; do
    echo "$spec $name ${mirror:-yes}"
  done < <(read_repo_entries)
}

list_repos() {
  _ARRIVE_PROTOCOL_CACHE="$(github_protocol)"
  log_info "Configured repositories (org: $ARRIVE_GITHUB_ORG, protocol: $_ARRIVE_PROTOCOL_CACHE):"
  echo
  printf "%-55s %-20s %-8s\n" "Clone URL" "Name" "Mirror"
  printf "%-55s %-20s %-8s\n" "---------" "----" "------"
  read_repos | while read -r spec name mirror; do
    printf "%-55s %-20s %-8s\n" "$(repo_url "$spec")" "$name" "$mirror"
  done
  echo
}

setup_one_repo() {
  local url name="$2" auto_mirror="$3" sot_base="$4"
  url="$(repo_url "$1")"
  local sot_path="${sot_base}/${name}"
  local mirror_path="${MIRROR_BASE}/${name}"

  echo
  log_info "Repository: $name"

  # 1. clone into SOT
  if [ -d "$sot_path/.git" ]; then
    log_success "SOT present: $sot_path"
  elif [ -e "$sot_path" ]; then
    log_error "$sot_path exists but is not a git repository - move it aside and re-run"
    return 1
  else
    log_info "Cloning $url -> $sot_path (network mount, one-time cost)..."
    if ! git clone "$url" "$sot_path"; then
      log_error "Clone failed for $name ($url)."
      log_info "  No access? Ask for it on GitHub. Auth problem? bash scripts/lib/configure-github-ssh.sh"
      return 1
    fi
    log_success "Cloned $name"
  fi

  [ "$auto_mirror" = "yes" ] || { log_info "AUTO_MIRROR=$auto_mirror - no mirror for $name"; return 0; }
  [ "$SKIP_MIRRORS" = false ] || return 0

  # 2. mirror worktree
  ensure_mirror_worktree "$sot_path" "$mirror_path" || return 1

  # 3. venv (only for Python projects)
  if [ "$SKIP_VENVS" = false ] && [ -n "$(repo_python_kind "$mirror_path")" ]; then
    bash "$SCRIPT_DIR/lib/setup-python-venv.sh" "$mirror_path" || {
      log_warn "venv setup failed for $name (continuing)"
      return 1
    }
  fi
}

setup_repos() {
  local sot_base
  if ! sot_base="$(detect_sot_base)"; then
    log_error "Could not determine the SOT base directory."
    log_info "Expected layout: ~/cloudfiles/code/Users/<your-aml-user>/main/arrive-aml"
    log_info "Clone arrive-aml there (or set ARRIVE_SOT_BASE) and re-run."
    exit 1
  fi

  if [ ! -f "$REPOS_CONF" ]; then
    log_error "repos.conf not found at: $REPOS_CONF"
    exit 1
  fi
  if [ -n "$ONLY_REPO" ] && ! read_repos | awk '{print $2}' | grep -qx "$ONLY_REPO"; then
    log_error "'$ONLY_REPO' is not in repos.conf or ${ARRIVE_EXTRA_REPOS_FILE}"
    log_info "Add it: bash scripts/setup-repos.sh --add owner/$ONLY_REPO"
    exit 1
  fi

  _ARRIVE_PROTOCOL_CACHE="$(github_protocol)"
  print_separator
  log_info "Setting up repositories (org: $ARRIVE_GITHUB_ORG, clone over $_ARRIVE_PROTOCOL_CACHE)"
  log_info "  SOT base : $sot_base"
  log_info "  Mirrors  : $MIRROR_BASE   (host: $(this_host))"
  log_info "  venvs    : $UV_VENV_ROOT"
  print_separator

  ensure_local_dir "$MIRROR_BASE"
  cd "$HOME"   # a mirror may be replaced below; never keep it as cwd

  local ok=0 failed=0 failed_names=()
  while read -r spec name mirror; do
    if [ -n "$ONLY_REPO" ] && [ "$ONLY_REPO" != "$name" ]; then
      continue
    fi
    if setup_one_repo "$spec" "$name" "$mirror" "$sot_base" </dev/null; then
      ok=$((ok + 1))
    else
      failed=$((failed + 1))
      failed_names+=("$name")
    fi
  done < <(read_repos)

  echo
  print_separator
  if [ "$failed" -eq 0 ]; then
    log_success "Repository setup complete ($ok repos)"
  else
    log_warn "Repository setup finished with problems: ${failed_names[*]}"
  fi
  echo
  echo "Work in the mirrors (fast local disk):"
  for d in "$MIRROR_BASE"/*/; do
    [ -d "$d/.git" ] && echo "  cd ${d%/}"
  done
  echo
  echo "Every commit in a mirror is pushed to the SOT in the background (log: ~/.local/state/arrive-aml/sot-sync.log)."
  echo "After a VM restart (/mnt wiped): login restores mirrors automatically (or: aml-bootstrap --restore)"
  print_separator
  [ "$failed" -eq 0 ]
}

# Append a repo to the personal list (idempotent) and select it for this run
add_repo() {
  local spec="$1" name
  name="$(repo_name_from_spec "$spec")"
  if read_repos | awk '{print $2}' | grep -qx "$name"; then
    log_info "$name is already configured"
  else
    mkdir -p "$(dirname "$ARRIVE_EXTRA_REPOS_FILE")"
    [ -f "$ARRIVE_EXTRA_REPOS_FILE" ] || printf '# Your personal repos (format: REPO|NAME|AUTO_MIRROR, see repos.conf)\n' > "$ARRIVE_EXTRA_REPOS_FILE"
    printf '%s|%s|yes\n' "$spec" "$name" >> "$ARRIVE_EXTRA_REPOS_FILE"
    log_success "Added $spec to $ARRIVE_EXTRA_REPOS_FILE"
  fi
  ONLY_REPO="$name"
}

main() {
  check_not_root
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) usage; exit 0 ;;
      --list) list_repos; exit 0 ;;
      --only) ONLY_REPO="${2:-}"; shift ;;
      --add) ADD_REPO="${2:-}"; [ -n "$ADD_REPO" ] || { usage; exit 1; }; shift ;;
      --skip-mirrors) SKIP_MIRRORS=true ;;
      --skip-venvs) SKIP_VENVS=true ;;
      *) log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
  done
  [ -z "$ADD_REPO" ] || add_repo "$ADD_REPO"
  setup_repos
}

main "$@"
