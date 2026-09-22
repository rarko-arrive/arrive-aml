# Sourced from the managed ~/.bashrc block on interactive shells.
# Bring /mnt mirrors and venvs back after a VM restart, without a manual command.
#
# This file runs inside the user's shell. Do not enable set -e or set -u here,
# and do not source common.sh (that would turn those options on for the session).

_arrive_trim() {
  local v="$*"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  printf '%s' "$v"
}

# True when every AUTO_MIRROR=yes repo from repos.conf has a local clone.
# A .git file (legacy linked worktree) does not count: restore replaces it.
arrive_mirrors_ready() {
  local base="${MIRROR_BASE:-/mnt/mirror}"
  local conf=""
  if [ -n "${ARRIVE_SOT_BASE:-}" ] && [ -f "${ARRIVE_SOT_BASE}/arrive-aml/repos.conf" ]; then
    conf="${ARRIVE_SOT_BASE}/arrive-aml/repos.conf"
  elif [ -n "${ARRIVE_ROOT:-}" ] && [ -f "${ARRIVE_ROOT}/repos.conf" ]; then
    conf="${ARRIVE_ROOT}/repos.conf"
  else
    return 1
  fi
  [ -d "$base" ] || return 1

  local url name mirror any=0
  while IFS='|' read -r url name mirror || [ -n "${url:-}" ]; do
    url="$(_arrive_trim "${url:-}")"
    [ -z "$url" ] && continue
    case "$url" in
      \#*) continue ;;
    esac
    name="$(_arrive_trim "${name:-}")"
    mirror="$(_arrive_trim "${mirror:-yes}")"
    [ -n "$name" ] || name="$(basename "$url" .git)"
    [ "$mirror" = "yes" ] || continue
    any=1
    [ -d "$base/$name/.git" ] || return 1
  done < "$conf"
  [ "$any" -eq 1 ]
}

arrive_auto_restore() {
  case $- in
    *i*) ;;
    *) return 0 ;;
  esac
  [ "${ARRIVE_NO_AUTO_RESTORE:-}" = "1" ] && return 0
  [ -n "${ARRIVE_BOOTSTRAP_RUNNING:-}" ] && return 0
  command -v aml-bootstrap >/dev/null 2>&1 || return 0
  arrive_mirrors_ready && return 0

  local state="${HOME}/.local/state/arrive-aml"
  mkdir -p "$state" 2>/dev/null || return 0

  # A failed restore must not replay on every new terminal.
  local failed="$state/restore-failed"
  if [ -f "$failed" ]; then
    local now mtime age
    now="$(date +%s)"
    mtime="$(stat -c %Y "$failed" 2>/dev/null || echo 0)"
    age=$((now - mtime))
    if [ "$age" -lt 600 ]; then
      printf '\033[1;33m⚠ Mirror restore failed recently. Retry: aml-bootstrap --restore\033[0m\n'
      local latest
      latest="$(ls -1t "$state"/bootstrap-*.log 2>/dev/null | head -1)"
      [ -n "$latest" ] && printf '  log: %s\n' "$latest"
      return 0
    fi
  fi

  local lock="$state/bootstrap.lock"
  if ! flock -n "$lock" true 2>/dev/null; then
    printf '\033[1;36m↻ Restoring mirrors after restart (already running in another shell)…\033[0m\n'
  else
    printf '\033[1;36m↻ /mnt was wiped on restart. Restoring mirrors and venvs…\033[0m\n'
  fi

  if ARRIVE_BOOTSTRAP_RUNNING=1 ARRIVE_AUTO_RESTORE=1 aml-bootstrap --restore; then
    rm -f "$failed"
    if arrive_mirrors_ready; then
      printf '\033[1;32m✓ Ready.  cd %s/arrive-aml\033[0m\n' "${MIRROR_BASE:-/mnt/mirror}"
    fi
  else
    touch "$failed"
    printf '\033[1;33m⚠ Restore did not finish. Retry: aml-bootstrap --restore\033[0m\n'
    local latest
    latest="$(ls -1t "$state"/bootstrap-*.log 2>/dev/null | head -1)"
    [ -n "$latest" ] && printf '  log: %s\n' "$latest"
  fi
  return 0
}

if [ "${BASH_SOURCE[0]}" != "${0}" ] && [ "${ARRIVE_LOGIN_RESTORE_LIBRARY:-}" != "1" ]; then
  case $- in
    *i*) arrive_auto_restore ;;
  esac
fi
