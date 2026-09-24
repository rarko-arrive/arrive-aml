#!/usr/bin/env bash
set -euo pipefail

# ONE command to set up (or restore) an Azure ML compute instance for the
# Arrive data-science workflow. Idempotent - run it as often as you like.
#
#   bash ~/cloudfiles/code/Users/<you>/main/arrive-aml/scripts/bootstrap.sh
#
# What it does
#   0. you       who you are (name, email, GitHub) - asks only what it cannot detect
#   1. tools     scripts/setup-vm.sh --all   (git tuning, uv, gh, GitHub SSH, Docker, cloudflared, Claude Code)
#   2. shell     ~/.bashrc block, ~/.config/arrive-aml/env, `aml-bootstrap` command
#   3. repos     clone repos.conf into the SOT, local mirror clones on /mnt/mirror (auto-synced to SOT), uv venvs
#   4. skills    team Claude Code skills from skills.conf -> ~/.claude/skills
#   5. verify    scripts/verify-setup.sh
#
# After every VM stop/start (/mnt is wiped): an interactive login runs
# `aml-bootstrap --restore` for you. Run it yourself to repair or refresh.
# As an Azure ML *startup script* (runs as root): this script re-executes itself
# as the login user, and waits for the cloudfiles mount.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=scripts/lib/login-restore.sh
ARRIVE_LOGIN_RESTORE_LIBRARY=1 source "$SCRIPT_DIR/lib/login-restore.sh"

RESTORE=false
DO_TOOLS=true
DO_REPOS=true
DO_VENVS=true
DO_SKILLS=true
DO_VERIFY=true
DRY_RUN=false
RECONFIGURE=false
USER_ARGS=()

usage() {
  cat <<USAGE
Usage: bash scripts/bootstrap.sh [OPTIONS]

  (no options)     Full setup: you + tools + shell + repos/mirrors/venvs + skills + verify
  --restore        Recreate /mnt mirrors + venvs, refresh skills, verify
                   (an interactive login runs this when /mnt was wiped)
  --configure      Review/change your name, email, team org and extra repos
  --name "NAME"    Your full name for git commits (skips that question)
  --email EMAIL    Your work email (skips that question)
  --github-org ORG Team GitHub org for {org} in repos.conf (default: ${ARRIVE_DEFAULT_GITHUB_ORG})
  --yes, -y        Never ask questions (use what is saved or detected)
  --skip-tools     Do not run setup-vm.sh --all
  --skip-repos     Do not clone repos / create mirrors / venvs
  --skip-venvs     Create mirrors but no Python venvs
  --skip-skills    Do not install Claude Code skills
  --no-verify      Do not run verify-setup.sh at the end
  --dry-run        Print the plan and exit
  -h, --help       This help

Paths (override in ~/.config/arrive-aml/env):
  SOT base   : ~/cloudfiles/code/Users/<you>/main   (persistent, shared by all your VMs)
  Mirrors    : ${MIRROR_BASE}   (fast local disk - WIPED on VM stop/start)
  venvs      : ${UV_VENV_ROOT}  (fast local disk - WIPED on VM stop/start)
USAGE
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --restore) RESTORE=true; DO_TOOLS=false ;;
      --configure|--reconfigure) RECONFIGURE=true ;;
      --name|--email|--github-org)
        [ $# -ge 2 ] || { log_error "$1 needs a value"; exit 1; }
        USER_ARGS+=("$1" "$2"); shift ;;
      --yes|-y) export ARRIVE_NONINTERACTIVE=1 ;;
      --skip-tools) DO_TOOLS=false ;;
      --skip-repos) DO_REPOS=false ;;
      --skip-venvs) DO_VENVS=false ;;
      --skip-skills) DO_SKILLS=false ;;
      --no-verify) DO_VERIFY=false ;;
      --dry-run) DRY_RUN=true ;;
      -h|--help) usage; exit 0 ;;
      *) log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
  done
}

# Azure ML startup scripts run as root: hand over to the real login user.
reexec_as_login_user() {
  if [ "$EUID" -ne 0 ]; then
    return 0
  fi
  local target="${SUDO_USER:-}"
  if [ -z "$target" ] || [ "$target" = "root" ]; then
    target="$(stat -c %U "$SCRIPT_DIR" 2>/dev/null || true)"
    [ "$target" != "root" ] && [ -n "$target" ] || target="azureuser"
  fi
  if ! id "$target" >/dev/null 2>&1; then
    log_error "Running as root and cannot determine the login user. Run as the login user instead."
    exit 1
  fi
  log_info "Running as root - re-executing as $target"
  exec sudo -u "$target" -H bash "$SCRIPT_DIR/bootstrap.sh" "$@"
}

# Fast-forward this checkout from origin when it is clean, then re-exec so the
# rest of the run uses the scripts that were just pulled. A dirty tree is left
# alone. Failure (offline, diverged) continues with the scripts already here.
maybe_update_self() {
  [ "$DRY_RUN" = true ] && return 0
  [ "${ARRIVE_NO_SELF_UPDATE:-}" = "1" ] && return 0
  local repo before after
  repo="$(cd "$SCRIPT_DIR/.." && pwd)"
  git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  git -C "$repo" remote get-url origin >/dev/null 2>&1 || return 0
  before="$(git -C "$repo" rev-parse HEAD 2>/dev/null || true)"
  [ -n "$before" ] || return 0
  if ! git -C "$repo" diff --quiet --ignore-submodules 2>/dev/null \
    || ! git -C "$repo" diff --cached --quiet --ignore-submodules 2>/dev/null; then
    return 0
  fi
  if command -v timeout >/dev/null 2>&1; then
    GIT_TERMINAL_PROMPT=0 timeout 90 git -C "$repo" pull --ff-only --quiet >/dev/null 2>&1 || return 0
  else
    GIT_TERMINAL_PROMPT=0 git -C "$repo" pull --ff-only --quiet >/dev/null 2>&1 || return 0
  fi
  after="$(git -C "$repo" rev-parse HEAD 2>/dev/null || true)"
  if [ -n "$after" ] && [ "$before" != "$after" ]; then
    echo "arrive-aml updated (${before:0:7} -> ${after:0:7}); continuing with the new scripts"
    exec bash "$repo/scripts/bootstrap.sh" "$@"
  fi
}

run_step() {
  local title="$1"; shift
  echo
  print_separator
  log_info "$title"
  print_separator
  if [ "$DRY_RUN" = true ]; then
    echo "  would run: $*"
    return 0
  fi
  "$@"
}

main() {
  reexec_as_login_user "$@"
  parse_args "$@"
  export PATH="${HOME}/.local/bin:${PATH}"
  export ARRIVE_BOOTSTRAP_RUNNING=1
  # Never run from inside a mirror: --restore may replace that very directory,
  # and git cannot run at all once the cwd has been deleted.
  cd "$HOME"

  mkdir -p "$ARRIVE_STATE_DIR"
  # One restore at a time. A second login waits, then exits immediately when
  # this one already brought the mirrors back.
  exec 9>"${ARRIVE_STATE_DIR}/bootstrap.lock"
  if ! flock -n 9; then
    if [ "${ARRIVE_AUTO_RESTORE:-}" != "1" ]; then
      log_info "Another bootstrap is running; waiting..."
    fi
    flock -w 1800 9 || { log_error "Timed out waiting for the other bootstrap"; exit 1; }
  fi
  if [ "$RESTORE" = true ] && [ "${ARRIVE_AUTO_RESTORE:-}" = "1" ] && arrive_mirrors_ready; then
    exit 0
  fi

  maybe_update_self "$@"

  local log="${ARRIVE_STATE_DIR}/bootstrap-$(date +%Y%m%d-%H%M%S).log"
  exec > >(tee -a "$log") 2>&1

  echo
  print_separator
  log_info "Arrive AML bootstrap  ($(whoami)@$(this_host))  mode: $([ "$RESTORE" = true ] && echo restore || echo full)"
  log_info "log: $log"
  print_separator

  if ! is_azureml; then
    log_warn "This does not look like an Azure ML compute instance - continuing anyway."
  fi

  # cloudfiles can mount late right after a VM start
  if ! wait_for_path "$ARRIVE_ROOT/repos.conf" 300; then
    log_error "cloudfiles mount not available at $ARRIVE_ROOT after 5 minutes"
    exit 1
  fi

  local sot_base
  if ! sot_base="$(detect_sot_base)"; then
    log_error "Could not determine the SOT base. Expected: ~/cloudfiles/code/Users/<you>/main/arrive-aml"
    log_info "Move this clone there (see docs/FRESH-VM.md) or export ARRIVE_SOT_BASE=/path/to/main"
    exit 1
  fi
  log_info "SOT base: $sot_base"

  local root_use
  root_use="$(df --output=pcent / | tail -n1 | tr -dc '0-9')"
  if [ "${root_use:-0}" -ge 95 ]; then
    log_warn "OS disk is ${root_use}% full - installs may fail. Free space: rm -rf ~/uv-venvs/<old> ; uv cache clean"
  fi

  local failures=()

  # Restores (often automatic, on login) and startup scripts never ask questions.
  if [ "$RESTORE" = true ] || [ "$EUID" -eq 0 ]; then
    export ARRIVE_NONINTERACTIVE=1
  fi
  [ "$RECONFIGURE" = false ] || USER_ARGS+=(--reconfigure)
  run_step "0/5 You" bash "$SCRIPT_DIR/lib/configure-user.sh" "${USER_ARGS[@]}" || failures+=("you")
  # Pick up what the wizard saved (identity, org) for the steps below.
  # shellcheck disable=SC1090
  [ -f "$ARRIVE_ENV_FILE" ] && source "$ARRIVE_ENV_FILE"

  if [ "$DO_TOOLS" = true ]; then
    run_step "1/5 Tools (setup-vm.sh --all)" bash "$SCRIPT_DIR/setup-vm.sh" --all --no-verify || failures+=("tools")
  else
    log_info "Skipping tools"
  fi

  run_step "2/5 Shell (bashrc, env, aml-bootstrap)" bash "$SCRIPT_DIR/lib/configure-shell.sh" || failures+=("shell")

  if [ "$DO_REPOS" = true ]; then
    local repo_args=()
    [ "$DO_VENVS" = true ] || repo_args+=(--skip-venvs)
    run_step "3/5 Repositories: SOT + mirrors + venvs" bash "$SCRIPT_DIR/setup-repos.sh" "${repo_args[@]}" || failures+=("repos")
  else
    log_info "Skipping repos"
  fi

  if [ "$DO_SKILLS" = true ]; then
    run_step "4/5 Claude Code skills" bash "$SCRIPT_DIR/lib/install-claude-skills.sh" || failures+=("skills")
  else
    log_info "Skipping skills"
  fi

  local verify_rc=0
  if [ "$DO_VERIFY" = true ] && [ "$DRY_RUN" = false ]; then
    run_step "5/5 Verify" bash "$SCRIPT_DIR/verify-setup.sh" || verify_rc=$?
  fi

  echo
  print_separator
  if [ "$DRY_RUN" = true ]; then
    log_info "Dry run - nothing was changed."
  elif [ ${#failures[@]} -eq 0 ] && [ "$verify_rc" -eq 0 ]; then
    log_success "Bootstrap complete. Your VM is ready${ARRIVE_USER_NAME:+, ${ARRIVE_USER_NAME%% *}}."
  else
    log_warn "Bootstrap finished with problems: ${failures[*]:-} $([ "$verify_rc" -ne 0 ] && echo '(verification failed - see fixes above)')"
  fi
  echo
  echo "  Work here (fast git):    cd ${MIRROR_BASE}/arrive-aml"
  echo "  Python env:              source .venv/bin/activate   (or: uv run ...)"
  if command -v claude >/dev/null 2>&1 && ! claude auth status >/dev/null 2>&1; then
    echo "  Claude Code (once/VM):   claude auth login"
  fi
  echo "  Claude Code:             claude    then  /work-in-repo"
  if [ -z "${ARRIVE_USER_EMAIL:-}" ]; then
    echo "  Tell git who you are:    aml-bootstrap --configure"
  fi
  echo "  After a VM restart:      login restores mirrors automatically"
  echo "  New shell settings:      source ~/.bashrc"
  print_separator
  [ ${#failures[@]} -eq 0 ] && [ "$verify_rc" -eq 0 ]
}

main "$@"
