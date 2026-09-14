#!/usr/bin/env bash
# Mirror worktree helpers - source this file (it does not run anything).
#
# Pattern: the repo's .git database lives in the SOT on ~/cloudfiles (slow,
# persistent, shared by ALL of your compute instances). Each compute instance
# gets its own worktree on /mnt/mirror (fast, local, wiped on stop/start).
#
# Rules implemented here:
#  * The default branch is checked out in the mirror. The SOT is a database,
#    so its HEAD is detached to free the branch (nobody works in the SOT).
#  * Worktree registrations are locked with reason "host=<instance>" so that a
#    `git worktree prune` run on another instance never deletes a live mirror.
#  * Registrations left behind by a /mnt wipe on THIS host are removed before
#    re-creating the mirror; other hosts' registrations are left alone.

# shellcheck source=scripts/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# Default branch of a repo: origin/HEAD, else main, else master, else current.
repo_default_branch() {
  local repo="$1" ref=""
  ref="$(git -C "$repo" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [ -z "$ref" ] && git -C "$repo" remote get-url origin >/dev/null 2>&1; then
    git -C "$repo" remote set-head origin -a >/dev/null 2>&1 || true
    ref="$(git -C "$repo" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  fi
  if [ -n "$ref" ]; then
    echo "${ref#origin/}"
    return 0
  fi
  if git -C "$repo" show-ref -q --verify refs/heads/main; then echo main; return 0; fi
  if git -C "$repo" show-ref -q --verify refs/heads/master; then echo master; return 0; fi
  git -C "$repo" rev-parse --abbrev-ref HEAD
}

# Print the worktree path that has $2 checked out (empty if none).
branch_holder() {
  local repo="$1" branch="$2"
  git -C "$repo" worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/$branch" '
    /^worktree /{wt=substr($0,10)}
    /^branch /{ if ($2==b) print wt }'
}

# Remove worktree registrations for $mirror that are dead on this host.
# A registration is considered ours when it is unlocked (legacy) or locked with
# "host=<this host>". Registrations locked by another host are never touched.
cleanup_stale_mirror_registration() {
  local sot="$1" mirror="$2"
  local common host dir gitdir locked id live_id=""
  common="$(git -C "$sot" rev-parse --path-format=absolute --git-common-dir)"
  host="$(this_host)"
  [ -d "$common/worktrees" ] || return 0

  if [ -f "$mirror/.git" ]; then
    live_id="$(sed -n 's#^gitdir: .*/worktrees/##p' "$mirror/.git" | head -n1)"
  fi

  for dir in "$common"/worktrees/*/; do
    [ -f "$dir/gitdir" ] || continue
    id="$(basename "$dir")"
    gitdir="$(tr -d '\r\n' < "$dir/gitdir")"
    [ "$gitdir" = "$mirror/.git" ] || continue
    [ "$id" = "$live_id" ] && continue

    locked=""
    [ -f "$dir/locked" ] && locked="$(tr -d '\r\n' < "$dir/locked")"
    if [ -n "$locked" ] && [ "$locked" != "host=$host" ]; then
      log_info "Keeping worktree registration '$id' (owned by another instance: $locked)"
      continue
    fi
    log_info "Removing stale worktree registration '$id' for $mirror"
    rm -rf "$dir"
  done
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

# True when $mirror is a healthy worktree whose database is $sot/.git
mirror_is_valid() {
  local sot="$1" mirror="$2" common
  [ -f "$mirror/.git" ] || return 1
  common="$(git -C "$mirror" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  [ -n "$common" ] || return 1
  [ "$common" -ef "$sot/.git" ]
}

# Ensure a mirror worktree exists for the SOT repo. Idempotent.
# Usage: ensure_mirror_worktree SOT_REPO_PATH MIRROR_PATH
ensure_mirror_worktree() {
  local sot="$1" mirror="$2"
  local host branch holder sot_real bak

  if [ ! -d "$sot/.git" ]; then
    log_error "Source of Truth not found: $sot"
    return 1
  fi

  host="$(this_host)"
  ensure_local_dir "$(dirname "$mirror")"
  clear_assume_unchanged "$sot"

  if [ -e "$mirror" ]; then
    if mirror_is_valid "$sot" "$mirror"; then
      clear_assume_unchanged "$mirror"
      log_success "Mirror OK: $mirror ($(git -C "$mirror" rev-parse --abbrev-ref HEAD 2>/dev/null))"
      return 0
    fi
    bak="${mirror}.broken-$(date +%Y%m%d%H%M%S)"
    log_warn "$mirror is not a valid worktree of $sot - moving it to $bak (your files are kept)"
    mv "$mirror" "$bak"
  fi

  cleanup_stale_mirror_registration "$sot" "$mirror"

  branch="$(repo_default_branch "$sot")"
  holder="$(branch_holder "$sot" "$branch")"
  sot_real="$(cd "$sot" && pwd -P)"

  if [ -n "$holder" ] && [ "$(cd "$holder" 2>/dev/null && pwd -P)" = "$sot_real" ]; then
    # The SOT is a database, not a workplace: detach it so the mirror can own the branch.
    if [ -n "$(git -C "$sot" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
      log_warn "SOT has uncommitted changes on '$branch' - leaving SOT as is; mirror starts detached"
    else
      log_info "Detaching SOT HEAD so '$branch' can live in the mirror (SOT keeps the full .git database)"
      git -C "$sot" checkout -q --detach
      holder=""
    fi
  fi

  log_info "Creating mirror worktree: $mirror (branch: $branch, owner: host=$host)"
  if [ -z "$holder" ]; then
    git -C "$sot" worktree add --lock --reason "host=$host" "$mirror" "$branch"
  else
    log_warn "'$branch' is checked out elsewhere ($holder) - creating a detached mirror"
    git -C "$sot" worktree add --lock --reason "host=$host" --detach "$mirror" "$branch"
    log_info "Start work with: cd $mirror && git checkout -b feature/<name>"
  fi

  log_success "Mirror created: $mirror"
}

# Print all mirrors registered for a SOT repo (path + branch), one per line.
list_repo_worktrees() {
  local repo="$1"
  git -C "$repo" worktree list 2>/dev/null || true
}
