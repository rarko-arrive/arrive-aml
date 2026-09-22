#!/usr/bin/env bash
# Common utilities for arrive-aml setup scripts
# Source this file: source "$(dirname "$0")/lib/common.sh"

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths and defaults (override via ~/.config/arrive-aml/env or the environment)
# ---------------------------------------------------------------------------
ARRIVE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARRIVE_CONFIG_DIR="${ARRIVE_CONFIG_DIR:-${HOME}/.config/arrive-aml}"
ARRIVE_ENV_FILE="${ARRIVE_CONFIG_DIR}/env"
ARRIVE_STATE_DIR="${HOME}/.local/state/arrive-aml"

# shellcheck disable=SC1090
[ -f "$ARRIVE_ENV_FILE" ] && source "$ARRIVE_ENV_FILE"

# Fast local disk. NOTE: on Azure ML compute instances /mnt is the EPHEMERAL
# resource disk - it is wiped on every stop/start. Everything placed there must
# be reproducible with `scripts/bootstrap.sh --restore`.
: "${MIRROR_BASE:=/mnt/mirror}"
: "${UV_VENV_ROOT:=/mnt/uv-venvs}"
: "${ARRIVE_UV_CACHE_DIR:=/mnt/uv-cache}"
# Where Claude Code skills repos are cloned (OS disk - persists)
: "${CLAUDE_SKILLS_CLONE_DIR:=${HOME}/.claude/plugins/marketplaces}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
  echo -e "${BLUE}==> $*${NC}"
}

log_success() {
  echo -e "${GREEN}✓ $*${NC}"
}

log_warn() {
  echo -e "${YELLOW}⚠ $*${NC}"
}

log_error() {
  echo -e "${RED}✗ $*${NC}" >&2
}

# Verify a command exists
# Usage: verify_command git "Git is not installed"
verify_command() {
  local cmd="$1"
  local message="${2:-$cmd is not available}"

  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_warn "$message"
    return 1
  fi
  return 0
}

# Add a directory to PATH in ~/.bashrc (idempotent)
# Usage: add_to_path "/path/to/bin" "comment"
add_to_path() {
  local dir="$1"
  local comment="${2:-Added by arrive-aml setup}"

  if [ ! -f "${HOME}/.bashrc" ]; then
    log_warn "~/.bashrc not found, creating it"
    touch "${HOME}/.bashrc"
  fi

  # Check if already in .bashrc
  if grep -qF "$dir" "${HOME}/.bashrc" 2>/dev/null; then
    return 0
  fi

  {
    echo ""
    echo "# $comment"
    echo "export PATH=\"${dir}:\$PATH\""
  } >> "${HOME}/.bashrc"

  log_success "Added $dir to ~/.bashrc PATH"
}

# Check if running as root (warn if so)
check_not_root() {
  if [ "$EUID" -eq 0 ]; then
    log_error "This script should NOT be run as root (sudo)"
    log_error "Run as a regular user. The script will prompt for sudo when needed."
    exit 1
  fi
}

# Confirm action (for interactive mode)
# Usage: if confirm "Install Docker?"; then ...; fi
confirm() {
  local prompt="$1"
  local response

  read -rp "$prompt (y/N): " response
  case "$response" in
    [yY][eE][sS]|[yY])
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Get OS information
get_os_info() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "$ID"
  else
    echo "unknown"
  fi
}

# Check if running on Ubuntu
is_ubuntu() {
  [ "$(get_os_info)" = "ubuntu" ]
}

# Trim leading/trailing whitespace (pure bash - xargs breaks on apostrophes)
trim() {
  local v="$*"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  printf '%s' "$v"
}

# Print separator line
print_separator() {
  echo "=================================================================="
}

# ---------------------------------------------------------------------------
# Azure ML environment helpers
# ---------------------------------------------------------------------------

# True on an Azure ML compute instance
is_azureml() {
  [ -f "${HOME}/cloudfiles/.nbvm" ] || [ -d /mnt/azmnt ] || [ -d "${HOME}/cloudfiles/code/Users" ]
}

# True when there is no graphical display (always the case on a compute instance)
is_headless() {
  [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]
}

# Stable name of this compute instance (used to tag per-host git worktrees)
this_host() {
  local name=""
  if [ -f "${HOME}/cloudfiles/.nbvm" ]; then
    name="$(sed -n 's/^instance=//p' "${HOME}/cloudfiles/.nbvm" | head -n1)"
  fi
  [ -n "$name" ] || name="$(hostname -s 2>/dev/null || hostname)"
  echo "$name"
}

# Create a directory on a root-owned parent (e.g. /mnt) and hand it to the user.
# Usage: ensure_local_dir /mnt/mirror
ensure_local_dir() {
  local dir="$1"
  if [ -d "$dir" ]; then
    if [ ! -w "$dir" ]; then
      sudo chown "$USER:$USER" "$dir"
    fi
    return 0
  fi
  if mkdir -p "$dir" 2>/dev/null; then
    return 0
  fi
  sudo mkdir -p "$dir"
  sudo chown "$USER:$USER" "$dir"
}

# Rewrite a resolved cloudfiles path back to the stable ~/cloudfiles form.
# /mnt/batch/tasks/shared/LS_root/mounts/clusters/HOST/code/Users/x -> ~/cloudfiles/code/Users/x
stable_cloudfiles_path() {
  local p="$1"
  case "$p" in
    */mounts/clusters/*/code/*)
      local rest="${p#*/mounts/clusters/*/code/}"
      local candidate="${HOME}/cloudfiles/code/${rest}"
      if [ -e "$candidate" ]; then
        echo "$candidate"
        return 0
      fi
      ;;
  esac
  echo "$p"
}

# Source-of-truth base directory: the directory that holds all SOT repos
# (~/cloudfiles/code/Users/<aml-user>/main). Derived from where THIS arrive-aml
# checkout's git database lives, so it works from the SOT and from a mirror.
# Override with ARRIVE_SOT_BASE.
detect_sot_base() {
  if [ -n "${ARRIVE_SOT_BASE:-}" ]; then
    echo "$ARRIVE_SOT_BASE"
    return 0
  fi

  local common sot_repo
  common="$(git -C "$ARRIVE_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [ -n "$common" ]; then
    sot_repo="$(dirname "$common")"
    case "$sot_repo" in
      */code/Users/*)
        stable_cloudfiles_path "$(dirname "$sot_repo")"
        return 0
        ;;
    esac
  fi

  # Fallback: a single user directory under cloudfiles that already has main/
  local users_dir="${HOME}/cloudfiles/code/Users"
  if [ -d "$users_dir" ]; then
    local candidates=()
    local d
    for d in "$users_dir"/*/main; do
      [ -d "$d/arrive-aml" ] && candidates+=("$d")
    done
    if [ "${#candidates[@]}" -eq 1 ]; then
      echo "${candidates[0]}"
      return 0
    fi
  fi

  return 1
}

# Wait for a path to appear (cloudfiles can mount late during VM start-up)
wait_for_path() {
  local path="$1"
  local timeout="${2:-300}"
  local waited=0
  while [ ! -e "$path" ]; do
    if [ "$waited" -ge "$timeout" ]; then
      return 1
    fi
    sleep 5
    waited=$((waited + 5))
  done
  return 0
}

# Run apt-get, waiting while another apt/dpkg holds the lock.
# Azure ML often runs apt in the background right after boot; failing the
# whole bootstrap on that lock is a false error when the tools are already there.
# Usage: apt_get update -qq
#        apt_get install -y -qq git curl
apt_get() {
  local attempt=0
  local max_attempts=90 # 90 * 5s = 7.5 minutes
  local err rc holder
  while true; do
    err="$(mktemp)"
    if sudo DEBIAN_FRONTEND=noninteractive apt-get "$@" >"$err" 2>&1; then
      if [ "${1:-}" = "update" ]; then
        # The Azure ML image ships duplicate apt sources; those warnings are noise.
        grep -Ev '^W: ' "$err" >&2 || true
      else
        cat "$err"
      fi
      rm -f "$err"
      return 0
    fi
    rc=$?
    if grep -qE 'Could not get lock|Unable to lock directory|Unable to acquire the dpkg frontend lock|is another process using it' "$err"; then
      attempt=$((attempt + 1))
      if [ "$attempt" -ge "$max_attempts" ]; then
        cat "$err" >&2
        rm -f "$err"
        log_error "apt stayed locked for $((max_attempts * 5 / 60)) minutes"
        return "$rc"
      fi
      if [ "$attempt" -eq 1 ] || [ $((attempt % 6)) -eq 0 ]; then
        holder="$(sed -n 's/.*held by process \([0-9][0-9]*\) (\([^)]*\)).*/process \1 (\2)/p' "$err" | head -1)"
        log_info "apt is locked${holder:+ by $holder}. Waiting for it to finish..."
      fi
      rm -f "$err"
      sleep 5
      continue
    fi
    cat "$err" >&2
    rm -f "$err"
    return "$rc"
  done
}

# Run apt-get update, hiding the noisy duplicate-source warnings the Azure ML
# image ships with (real errors still print).
apt_update_quiet() {
  apt_get update -qq
}

# ---------------------------------------------------------------------------
# GitHub helpers
# ---------------------------------------------------------------------------

# Make sure github.com host keys are trusted (fresh VMs have no known_hosts).
# Fetches fingerprints over HTTPS from the GitHub API; falls back to ssh-keyscan.
ensure_github_known_hosts() {
  local known="${HOME}/.ssh/known_hosts"
  mkdir -p "${HOME}/.ssh"
  chmod 700 "${HOME}/.ssh"
  touch "$known"
  if ssh-keygen -F github.com -f "$known" >/dev/null 2>&1; then
    return 0
  fi
  local keys
  keys="$(curl -fsSL --max-time 15 https://api.github.com/meta 2>/dev/null \
    | (command -v jq >/dev/null 2>&1 && jq -r '.ssh_keys[]' || sed -n 's/.*"\(ssh-[a-z0-9-]* [A-Za-z0-9+/=]*\)".*/\1/p') || true)"
  if [ -n "$keys" ]; then
    while IFS= read -r k; do
      [ -n "$k" ] && echo "github.com $k" >> "$known"
    done <<< "$keys"
  else
    ssh-keyscan -T 10 github.com >> "$known" 2>/dev/null || true
  fi
  ssh-keygen -F github.com -f "$known" >/dev/null 2>&1
}

# GitHub SSH test that is immune to `set -o pipefail`.
# GitHub always exits 1 on `ssh -T` (no shell access), so grep on the message.
# Sets GITHUB_SSH_OUTPUT for callers that want to show the reason on failure.
github_ssh_ok() {
  GITHUB_SSH_OUTPUT="$(ssh -T -o BatchMode=yes -o ConnectTimeout=15 \
    -o StrictHostKeyChecking=accept-new git@github.com 2>&1 || true)"
  [[ "$GITHUB_SSH_OUTPUT" == *"successfully authenticated"* ]]
}
