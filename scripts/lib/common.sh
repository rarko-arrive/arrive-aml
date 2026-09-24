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

# Team defaults. {org} in repos.conf / skills.conf expands to ARRIVE_GITHUB_ORG.
# This is the ONE place to change when the team repos move to another GitHub org.
ARRIVE_DEFAULT_GITHUB_ORG="rarko-arrive"
: "${ARRIVE_GITHUB_ORG:=${ARRIVE_DEFAULT_GITHUB_ORG}}"
: "${ARRIVE_EMAIL_DOMAIN:=arrivelogistics.com}"
# Personal additions to repos.conf / skills.conf (same format, never committed)
: "${ARRIVE_EXTRA_REPOS_FILE:=${ARRIVE_CONFIG_DIR}/repos.conf}"
: "${ARRIVE_EXTRA_SKILLS_FILE:=${ARRIVE_CONFIG_DIR}/skills.conf}"
# ssh | https | auto (auto = ssh when GitHub SSH works, else https)
: "${ARRIVE_GIT_PROTOCOL:=auto}"
# Who you are. Set by scripts/lib/configure-user.sh; deliberately no defaults.
: "${ARRIVE_USER_NAME:=}"
: "${ARRIVE_USER_EMAIL:=}"
: "${ARRIVE_GITHUB_USER:=}"

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
# Config file (~/.config/arrive-aml/env), prompts, identity
# ---------------------------------------------------------------------------

# Set KEY="VALUE" in the env file (update in place or append) and in this shell.
# Usage: config_set ARRIVE_USER_NAME "Colin Tracy"
config_set() {
  local key="$1" value="$2" escaped tmp
  mkdir -p "$ARRIVE_CONFIG_DIR"
  touch "$ARRIVE_ENV_FILE"
  escaped="$(printf '%s' "$value" | sed -e 's/[\\"$`]/\\&/g')"
  tmp="$(mktemp "${ARRIVE_ENV_FILE}.XXXXXX")"
  awk -v k="$key" -v line="${key}=\"${escaped//\\/\\\\}\"" '
    index($0, k"=") == 1 { if (!done) print line; done = 1; next }
    { print }
    END { if (!done) print line }
  ' "$ARRIVE_ENV_FILE" > "$tmp"
  mv "$tmp" "$ARRIVE_ENV_FILE"
  printf -v "$key" '%s' "$value"
}

# Remove KEY from the env file (its default applies again)
config_unset() {
  local key="$1" tmp
  [ -f "$ARRIVE_ENV_FILE" ] || return 0
  tmp="$(mktemp "${ARRIVE_ENV_FILE}.XXXXXX")"
  grep -v "^${key}=" "$ARRIVE_ENV_FILE" > "$tmp" || true
  mv "$tmp" "$ARRIVE_ENV_FILE"
}

# True when we may ask questions: a terminal we can open, and nobody asked for a
# non-interactive run (startup script, --yes, automatic restore on login).
can_prompt() {
  [ "${ARRIVE_NONINTERACTIVE:-}" = "1" ] && return 1
  [ "${ARRIVE_AUTO_RESTORE:-}" = "1" ] && return 1
  (exec 3</dev/tty) 2>/dev/null
}

# Ask on the terminal (works under `curl | bash` and with stdout tee'd to a log).
# Usage: ask VAR "Your name" "default"
# (Locals are __-prefixed so they never shadow the caller's VAR.)
ask() {
  local __var="$1" __question="$2" __default="${3:-}" __answer=""
  if [ -n "$__default" ]; then
    printf '  %s [%s]: ' "$__question" "$__default" > /dev/tty
  else
    printf '  %s: ' "$__question" > /dev/tty
  fi
  IFS= read -r __answer < /dev/tty || true
  __answer="$(trim "$__answer")"
  [ -n "$__answer" ] || __answer="$__default"
  printf -v "$__var" '%s' "$__answer"
}

# Yes/no on the terminal, default yes. Usage: if ask_yes "Look right?"; then ...
ask_yes() {
  local reply=""
  ask reply "$1 [Y/n]" ""
  case "$reply" in
    [nN]|[nN][oO]) return 1 ;;
    *) return 0 ;;
  esac
}

# Write ARRIVE_USER_NAME / ARRIVE_USER_EMAIL into the global git config.
# Never invents an identity: with nothing configured, git is left alone.
apply_git_identity() {
  if [ -n "${ARRIVE_USER_NAME:-}" ] && [ "$(git config --global user.name 2>/dev/null || true)" != "$ARRIVE_USER_NAME" ]; then
    git config --global user.name "$ARRIVE_USER_NAME"
    log_success "git user.name = $ARRIVE_USER_NAME"
  fi
  if [ -n "${ARRIVE_USER_EMAIL:-}" ] && [ "$(git config --global user.email 2>/dev/null || true)" != "$ARRIVE_USER_EMAIL" ]; then
    git config --global user.email "$ARRIVE_USER_EMAIL"
    log_success "git user.email = $ARRIVE_USER_EMAIL"
  fi
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

# Workspace folder that holds every user's files. NOTE: it lists ALL users of the
# Azure ML workspace, not just you - never pick "the only folder" in it.
: "${ARRIVE_USERS_DIR:=${HOME}/cloudfiles/code/Users}"

# Best guess of your folder name under $ARRIVE_USERS_DIR from the compute
# instance name (ctracy2 -> ctracy, ctracy-gpu -> ctracy). Prints nothing if no
# folder matches. Callers confirm the guess with the user when they can.
guess_aml_user() {
  local host candidate
  host="$(this_host)"
  for candidate in "$host" "${host%%[0-9]*}" "${host%%[-_]*}" "${host%%[-_0-9]*}"; do
    [ -n "$candidate" ] || continue
    if [ -d "${ARRIVE_USERS_DIR}/${candidate}" ]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

# The folder name under $ARRIVE_USERS_DIR this setup belongs to (e.g. ctracy).
aml_user() {
  local base
  if base="$(detect_sot_base 2>/dev/null)"; then
    case "$base" in
      */code/Users/*/main) basename "$(dirname "$base")"; return 0 ;;
    esac
  fi
  guess_aml_user
}

# Source-of-truth base directory: the directory that holds all SOT repos
# (~/cloudfiles/code/Users/<aml-user>/main). Tried in order:
#   1. ARRIVE_SOT_BASE (env file / environment)
#   2. this checkout lives in the SOT itself (.../code/Users/<you>/main/arrive-aml)
#   3. this checkout is a mirror: its 'sot' remote points there
#   4. the instance name matches a user folder that already has main/arrive-aml
detect_sot_base() {
  if [ -n "${ARRIVE_SOT_BASE:-}" ]; then
    echo "$ARRIVE_SOT_BASE"
    return 0
  fi

  local root sot_url guess
  root="$(stable_cloudfiles_path "$ARRIVE_ROOT")"
  case "$root" in
    */code/Users/*/main/*)
      dirname "$root"
      return 0
      ;;
  esac

  sot_url="$(git -C "$ARRIVE_ROOT" config --get remote.sot.url 2>/dev/null || true)"
  case "$sot_url" in
    */code/Users/*/main/*)
      stable_cloudfiles_path "$(dirname "$sot_url")"
      return 0
      ;;
  esac

  if guess="$(guess_aml_user)" && [ -d "${ARRIVE_USERS_DIR}/${guess}/main/arrive-aml" ]; then
    echo "${ARRIVE_USERS_DIR}/${guess}/main"
    return 0
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
    -o StrictHostKeyChecking=accept-new git@github.com </dev/null 2>&1 || true)"
  [[ "$GITHUB_SSH_OUTPUT" == *"successfully authenticated"* ]]
}

# ssh or https for new GitHub clones. ARRIVE_GIT_PROTOCOL=auto picks ssh when
# GitHub SSH already works, else https (gh's credential helper then handles it).
# The answer is cached for the rest of the run.
github_protocol() {
  case "${ARRIVE_GIT_PROTOCOL:-auto}" in
    ssh|https) echo "$ARRIVE_GIT_PROTOCOL"; return 0 ;;
  esac
  if [ -z "${_ARRIVE_PROTOCOL_CACHE:-}" ]; then
    if [ -f "${HOME}/.ssh/id_ed25519_github" ] && github_ssh_ok; then
      _ARRIVE_PROTOCOL_CACHE=ssh
    else
      _ARRIVE_PROTOCOL_CACHE=https
    fi
  fi
  echo "$_ARRIVE_PROTOCOL_CACHE"
}

# Turn a repos.conf / skills.conf entry into a clone URL.
#   {org}/arrive-ds            -> ${ARRIVE_GITHUB_ORG}/arrive-ds (below)
#   owner/name                 -> git@github.com:owner/name.git or https://github.com/owner/name.git
#   git@github.com:owner/name  -> kept, or rewritten to https when SSH is unavailable
#   anything else (file path, other host) -> unchanged
repo_url() {
  local spec="$1" path=""
  spec="${spec//\{org\}/${ARRIVE_GITHUB_ORG}}"
  case "$spec" in
    git@github.com:*) path="${spec#git@github.com:}" ;;
    ssh://git@github.com/*) path="${spec#ssh://git@github.com/}" ;;
    https://github.com/*) path="${spec#https://github.com/}" ;;
    */*)
      if [[ "$spec" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
        path="$spec"
      fi
      ;;
  esac
  if [ -z "$path" ]; then
    echo "$spec"
    return 0
  fi
  path="${path%.git}"
  if [ "$(github_protocol)" = ssh ]; then
    echo "git@github.com:${path}.git"
  else
    echo "https://github.com/${path}.git"
  fi
}

# Directory name for an entry without an explicit NAME column
repo_name_from_spec() {
  local spec="${1%/}"
  spec="${spec##*/}"
  spec="${spec##*:}"
  echo "${spec%.git}"
}

# Print the entries of one or more pipe-separated conf files as
#   SPEC|NAME|FLAG
# skipping comments, blank lines and names already seen (first file wins).
# Missing files are ignored. Usage: read_conf_entries repos.conf ~/.config/arrive-aml/repos.conf
read_conf_entries() {
  local f spec name flag seen=" "
  for f in "$@"; do
    [ -f "$f" ] || continue
    while IFS='|' read -r spec name flag || [ -n "${spec:-}" ]; do
      spec="$(trim "${spec:-}")"
      [ -z "$spec" ] && continue
      [[ "$spec" == \#* ]] && continue
      name="$(trim "${name:-}")"
      flag="$(trim "${flag:-}")"
      [ -n "$name" ] || name="$(repo_name_from_spec "$spec")"
      case "$seen" in *" $name "*) continue ;; esac
      seen="${seen}${name} "
      printf '%s|%s|%s\n' "$spec" "$name" "$flag"
    done < "$f"
  done
}

# How a repo declares its Python environment:
#   project       pyproject.toml with a [project] table -> uv sync
#   requirements  requirements.txt (pyproject may hold only tool config) -> uv venv + uv pip install -r
#   (nothing)     not a Python project -> no venv
repo_python_kind() {
  local dir="$1"
  if [ -f "$dir/pyproject.toml" ] && grep -q '^\[project\]' "$dir/pyproject.toml"; then
    echo project
  elif [ -f "$dir/requirements.txt" ]; then
    echo requirements
  fi
}

# Team repos plus your personal additions
read_repo_entries() {
  read_conf_entries "${ARRIVE_ROOT}/repos.conf" "$ARRIVE_EXTRA_REPOS_FILE"
}

# Team skills repos plus your personal additions
read_skill_entries() {
  read_conf_entries "${ARRIVE_ROOT}/skills.conf" "$ARRIVE_EXTRA_SKILLS_FILE"
}
