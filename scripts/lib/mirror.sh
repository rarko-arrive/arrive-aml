#!/usr/bin/env bash
# Mirror helpers - source this file (it does not run anything).
#
# Pattern (see docs/MIRROR-PATTERN.md):
#   SOT     ~/cloudfiles/code/Users/<you>/main/REPO   persistent Azure Files share, slow
#           (60-95 ms per file operation), shared by ALL of your compute instances.
#           Holds the full .git database, checked out on the default branch and kept
#           current by pushes (receive.denyCurrentBranch=updateInstead). Nobody edits here.
#   mirror  /mnt/mirror/REPO   a FULL LOCAL CLONE on the fast local disk (git status
#           ~5 ms). remotes:  origin = GitHub,  sot = the SOT path.
#           Hooks push every commit to the SOT in the background, so the persistent
#           copy is always current. /mnt is wiped on stop/start: `aml-bootstrap
#           --restore` re-clones (GitHub first, SOT fallback) and re-fetches SOT branches.
#
# Why not `git worktree`? A linked worktree keeps its index/HEAD/refs in the SOT's
# .git on the share: still ~3 s per git command, plus cross-instance worktree
# registration hazards. A clone is plain git: fast, per-instance, no shared state.

# shellcheck source=scripts/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

SYNC_LOG="${ARRIVE_STATE_DIR}/sot-sync.log"

# Default branch of a repo: origin/HEAD, else main, else master, else current.
repo_default_branch() {
  local repo="$1" ref=""
  ref="$(git -C "$repo" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [ -n "$ref" ]; then echo "${ref#origin/}"; return 0; fi
  if git -C "$repo" show-ref -q --verify refs/heads/main; then echo main; return 0; fi
  if git -C "$repo" show-ref -q --verify refs/heads/master; then echo master; return 0; fi
  git -C "$repo" rev-parse --abbrev-ref HEAD
}

# Undo the damage of a past core.ignoreStat=true: files flagged assume-unchanged
# ("h" in ls-files -v) are invisible to git status/add -A/commit -a.
clear_assume_unchanged() {
  local repo="$1" n
  n="$(git -C "$repo" ls-files -v 2>/dev/null | grep -c '^h' || true)"
  [ "${n:-0}" -gt 0 ] || return 0
  log_warn "$repo: $n files were marked assume-unchanged (old core.ignoreStat=true) - clearing"
  git -C "$repo" ls-files -z | git -C "$repo" update-index -z --no-assume-unchanged --stdin
}

# Remove worktree registrations in the SOT that point at $mirror (legacy pattern).
# Registrations locked by another instance are left alone.
remove_mirror_worktree_registration() {
  local sot="$1" mirror="$2" common host dir gitdir locked
  common="$(git -C "$sot" rev-parse --path-format=absolute --git-common-dir)"
  host="$(this_host)"
  [ -d "$common/worktrees" ] || return 0
  for dir in "$common"/worktrees/*/; do
    [ -f "$dir/gitdir" ] || continue
    gitdir="$(tr -d '\r\n' < "$dir/gitdir")"
    [ "$gitdir" = "$mirror/.git" ] || continue
    locked=""
    [ -f "$dir/locked" ] && locked="$(tr -d '\r\n' < "$dir/locked")"
    if [ -n "$locked" ] && [ "$locked" != "host=$host" ]; then
      continue
    fi
    log_info "Removing legacy worktree registration '$(basename "$dir")'"
    rm -rf "$dir"
  done
}

# True when $mirror is a local clone whose 'sot' remote is $sot
mirror_is_valid() {
  local sot="$1" mirror="$2" url
  [ -d "$mirror/.git" ] || return 1
  url="$(git -C "$mirror" remote get-url sot 2>/dev/null || true)"
  [ -n "$url" ] || return 1
  [ "$url" -ef "$sot" ]
}

# Commits on the current branch that have not reached the SOT yet (0 when in sync)
mirror_unsynced_count() {
  local mirror="$1" branch
  branch="$(git -C "$mirror" symbolic-ref -q --short HEAD 2>/dev/null || true)"
  [ -n "$branch" ] || { echo 0; return 0; }
  if git -C "$mirror" show-ref -q --verify "refs/remotes/sot/$branch"; then
    git -C "$mirror" rev-list --count "sot/$branch..HEAD" 2>/dev/null || echo 0
  else
    git -C "$mirror" rev-list --count HEAD 2>/dev/null || echo 0
  fi
}

# Install the hooks that keep the SOT current after every commit/merge/rewrite.
install_sot_sync_hooks() {
  local mirror="$1" hooks
  hooks="$(git -C "$mirror" rev-parse --path-format=absolute --git-path hooks)"
  mkdir -p "$hooks" "$ARRIVE_STATE_DIR"
  cat > "$hooks/arrive-aml-sync-sot" <<'HOOK'
#!/usr/bin/env bash
# arrive-aml: push the current branch to the persistent SOT copy (cloudfiles) in the
# background. Runs from post-commit, post-merge and post-rewrite. Serialized with flock.
# Log: ~/.local/state/arrive-aml/sot-sync.log   Manual: git push sot HEAD
kind="$(basename "${0##*/}")"; [ -n "${ARRIVE_HOOK_KIND:-}" ] && kind="$ARRIVE_HOOK_KIND"
branch="$(git symbolic-ref -q --short HEAD)" || exit 0
git remote get-url sot >/dev/null 2>&1 || exit 0
state="${HOME}/.local/state/arrive-aml"; mkdir -p "$state"
log="$state/sot-sync.log"; lock="$state/sot-sync.$(basename "$(git rev-parse --show-toplevel)").lock"
force=""; [ "$kind" = "post-rewrite" ] && force="--force-with-lease"
(
  exec 9>"$lock"; flock 9
  if out="$(git push -q $force sot "HEAD:refs/heads/$branch" 2>&1)"; then
    printf '%s ok   %s %s -> sot\n' "$(date '+%F %T')" "$(basename "$PWD")" "$branch" >> "$log"
  else
    printf '%s FAIL %s %s -> sot: %s\n' "$(date '+%F %T')" "$(basename "$PWD")" "$branch" "$(echo "$out" | tr '\n' ' ')" >> "$log"
  fi
) >/dev/null 2>&1 &
disown 2>/dev/null || true
exit 0
HOOK
  chmod +x "$hooks/arrive-aml-sync-sot"
  local h
  for h in post-commit post-merge post-rewrite; do
    printf '#!/usr/bin/env bash\nARRIVE_HOOK_KIND=%s exec "$(dirname "$0")/arrive-aml-sync-sot" "$@"\n' "$h" > "$hooks/$h"
    chmod +x "$hooks/$h"
  done
}

# Remotes, upstream and config for a mirror clone
configure_mirror_clone() {
  local sot="$1" mirror="$2" branch="$3" github_url="$4"
  local sot_url
  sot_url="$(stable_cloudfiles_path "$sot")"

  if git -C "$mirror" remote get-url sot >/dev/null 2>&1; then
    git -C "$mirror" remote set-url sot "$sot_url"
  else
    git -C "$mirror" remote add sot "$sot_url"
  fi
  if [ -n "$github_url" ]; then
    if git -C "$mirror" remote get-url origin >/dev/null 2>&1; then
      git -C "$mirror" remote set-url origin "$github_url"
    else
      git -C "$mirror" remote add origin "$github_url"
    fi
  fi
  git -C "$mirror" config remote.pushDefault origin
  git -C "$mirror" config checkout.defaultRemote origin
  git -C "$mirror" config remote.sot.tagOpt --no-tags
  if git -C "$mirror" show-ref -q --verify "refs/remotes/origin/$branch" && \
     git -C "$mirror" show-ref -q --verify "refs/heads/$branch"; then
    git -C "$mirror" branch -q --set-upstream-to="origin/$branch" "$branch" 2>/dev/null || true
  fi
  install_sot_sync_hooks "$mirror"
}

# Make the SOT a push target that keeps its working tree current:
#  - receive.denyCurrentBranch=updateInstead lets the mirror push the branch the SOT has
#    checked out (git refuses that by default) and updates the SOT's files as part of the push
#  - a detached SOT (left by older versions of these scripts) is put back on the default branch
prepare_sot() {
  local sot="$1" branch="$2"
  git -C "$sot" config receive.denyCurrentBranch updateInstead
  if ! git -C "$sot" symbolic-ref -q HEAD >/dev/null 2>&1; then
    if [ -n "$(git -C "$sot" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
      log_warn "SOT $sot is detached and has uncommitted changes - leaving it; commit them from the mirror"
    elif git -C "$sot" show-ref -q --verify "refs/heads/$branch"; then
      log_info "SOT was detached - checking out '$branch' (slow share, one-time)"
      git -C "$sot" checkout -q "$branch"
    fi
  fi
}

# Ensure a fast local mirror clone exists for the SOT repo. Idempotent.
# Usage: ensure_mirror_worktree SOT_REPO_PATH MIRROR_PATH   (name kept for callers)
ensure_mirror_worktree() {
  local sot="$1" mirror="$2"
  local branch github_url bak

  if [ ! -d "$sot/.git" ]; then
    log_error "Source of Truth not found: $sot"
    return 1
  fi

  ensure_local_dir "$(dirname "$mirror")"
  clear_assume_unchanged "$sot"
  branch="$(repo_default_branch "$sot")"
  github_url="$(git -C "$sot" remote get-url origin 2>/dev/null || true)"

  if [ -e "$mirror" ]; then
    if mirror_is_valid "$sot" "$mirror"; then
      configure_mirror_clone "$sot" "$mirror" "$branch" "$github_url"
      clear_assume_unchanged "$mirror"
      prepare_sot "$sot" "$branch"
      log_success "Mirror OK: $mirror ($(git -C "$mirror" rev-parse --abbrev-ref HEAD 2>/dev/null))"
      return 0
    fi
    if [ -f "$mirror/.git" ]; then
      # legacy linked worktree: its commits already live in the SOT
      if [ -z "$(git -C "$mirror" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
        log_info "Replacing legacy worktree mirror with a local clone: $mirror"
        rm -rf "$mirror"
      else
        bak="${mirror}.old-worktree-$(date +%Y%m%d%H%M%S)"
        log_warn "$mirror is a legacy worktree WITH uncommitted changes - moving it to $bak"
        mv "$mirror" "$bak"
      fi
      remove_mirror_worktree_registration "$sot" "$mirror"
    else
      bak="${mirror}.broken-$(date +%Y%m%d%H%M%S)"
      log_warn "$mirror is not a valid mirror of $sot - moving it to $bak (your files are kept)"
      mv "$mirror" "$bak"
    fi
  else
    remove_mirror_worktree_registration "$sot" "$mirror"
  fi

  prepare_sot "$sot" "$branch"

  log_info "Cloning mirror: $mirror (branch: $branch)"
  if [ -n "$github_url" ] && git clone -q -b "$branch" "$github_url" "$mirror" 2>/dev/null; then
    log_info "  cloned from GitHub; fetching branches only the SOT has (slow share, be patient)..."
    configure_mirror_clone "$sot" "$mirror" "$branch" "$github_url"
    git -C "$mirror" fetch -q sot 2>/dev/null || log_warn "  could not fetch from the SOT (will retry on next bootstrap)"
    # fast-forward the default branch to whatever the SOT has (commits not pushed to GitHub yet)
    if git -C "$mirror" show-ref -q --verify "refs/remotes/sot/$branch"; then
      git -C "$mirror" merge -q --ff-only "sot/$branch" 2>/dev/null || true
    fi
  else
    log_info "  GitHub unavailable - cloning from the SOT over the share (slow, one-time)..."
    rm -rf "$mirror"
    git clone -q --no-local -b "$branch" "$sot" "$mirror" || { log_error "clone failed for $mirror"; return 1; }
    git -C "$mirror" remote rename origin sot
    configure_mirror_clone "$sot" "$mirror" "$branch" "$github_url"
    [ -n "$github_url" ] && git -C "$mirror" fetch -q origin 2>/dev/null || true
  fi

  log_success "Mirror ready: $mirror [$branch]  (origin=GitHub, sot=$(stable_cloudfiles_path "$sot"))"
}

# Print the remotes/branches of a mirror (for --list)
list_repo_worktrees() {
  local repo="$1"
  git -C "$repo" worktree list 2>/dev/null || true
}
