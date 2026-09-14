#!/usr/bin/env bash
set -euo pipefail

# Verify the Arrive AML VM setup
# Required checks fail the script (exit 1) and print the exact fix.
# Optional checks only inform (editors are used from your laptop via Remote-SSH).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/mirror.sh
source "$SCRIPT_DIR/lib/mirror.sh"

FAILED=()   # "what|fix"
NOTES=()

fail() { log_warn "$1"; FAILED+=("$1|$2"); }
note() { log_info "  $1"; NOTES+=("$1"); }

check_command() {
  local cmd="$1" name="$2" fix="$3"
  if command -v "$cmd" >/dev/null 2>&1; then
    log_success "$name: $(command -v "$cmd")"
    return 0
  fi
  fail "$name: NOT FOUND" "$fix"
  return 1
}

check_command_optional() {
  local cmd="$1" name="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    log_success "$name: $(command -v "$cmd")"
  else
    note "$name: not installed (optional)"
  fi
}

check_git_config() {
  local key="$1" expected="$2"
  local actual
  actual="$(git config --global --get "$key" 2>/dev/null || echo "")"
  if [ "$actual" = "$expected" ]; then
    log_success "$key = $actual"
  else
    fail "$key = '${actual:-unset}' (expected $expected)" "bash scripts/lib/configure-git.sh"
  fi
}

main() {
  export PATH="${HOME}/.local/bin:${PATH}"
  log_info "Verifying Arrive AML VM Setup ($(this_host))"
  echo

  log_info "=== System Tools ==="
  check_command git "Git" "bash scripts/lib/install-system-tools.sh" || true
  check_command curl "curl" "bash scripts/lib/install-system-tools.sh" || true
  check_command_optional jq "jq"
  check_command_optional htop "htop"
  check_command_optional tree "tree"
  echo

  log_info "=== Git Configuration ==="
  check_git_config core.fsmonitor false
  check_git_config feature.manyFiles true
  check_git_config gc.auto 0
  check_git_config core.ignoreStat false
  if git config --global --get-all safe.directory 2>/dev/null | grep -qx '\*'; then
    log_success "safe.directory = * (cloudfiles mount is root-owned)"
  else
    fail "safe.directory '*' missing (git refuses root-owned cloudfiles repos)" "bash scripts/lib/configure-git.sh"
  fi
  if [ -n "$(git config --global user.email 2>/dev/null)" ]; then
    log_success "user: $(git config --global user.name) <$(git config --global user.email)>"
  else
    fail "git user.email not set" "git config --global user.email you@arrivelogistics.com"
  fi
  echo

  log_info "=== Package Managers ==="
  if check_command uv "uv" "bash scripts/lib/install-uv.sh"; then
    log_info "  $(uv --version)"
  fi
  echo

  log_info "=== GitHub ==="
  if check_command gh "GitHub CLI" "bash scripts/lib/install-gh.sh"; then
    if gh auth status >/dev/null 2>&1; then
      log_success "gh authenticated"
    else
      fail "gh not authenticated" "gh auth login"
    fi
  fi
  if [ -f "${HOME}/.ssh/id_ed25519_github" ]; then
    log_success "GitHub SSH key exists"
    if github_ssh_ok; then
      log_success "GitHub SSH works ($(echo "$GITHUB_SSH_OUTPUT" | head -n1))"
    else
      fail "GitHub SSH failed: $(echo "$GITHUB_SSH_OUTPUT" | head -n1)" "bash scripts/lib/configure-github-ssh.sh"
    fi
  else
    fail "GitHub SSH key missing" "bash scripts/lib/configure-github-ssh.sh"
  fi
  echo

  log_info "=== Docker (optional) ==="
  if command -v docker >/dev/null 2>&1; then
    log_success "Docker: $(docker --version)"
    if id -nG | grep -qw docker; then
      log_success "user in docker group"
    else
      note "user not in docker group (run: sudo usermod -aG docker \$USER, then re-login)"
    fi
  else
    note "Docker not installed (bash scripts/lib/install-docker.sh)"
  fi
  echo

  log_info "=== Claude Code ==="
  if check_command claude "Claude Code" "bash scripts/lib/install-claude.sh"; then
    log_info "  $(claude --version 2>/dev/null || echo installed)"
    if claude auth status >/dev/null 2>&1; then
      log_success "Claude Code authenticated"
    else
      note "Claude Code not authenticated (run: claude auth login)"
    fi
  fi
  local skills_dir="${HOME}/.claude/skills" s broken=0 count=0
  if [ -d "$skills_dir" ]; then
    for s in "$skills_dir"/*; do
      [ -e "$s" ] || { [ -L "$s" ] && broken=$((broken + 1)); continue; }
      count=$((count + 1))
    done
  fi
  if [ -f "${ARRIVE_ROOT}/skills.conf" ] && grep -qvE '^\s*(#|$)' "${ARRIVE_ROOT}/skills.conf"; then
    if [ "$count" -gt 0 ] && [ "$broken" -eq 0 ]; then
      log_success "Claude skills linked: $(ls "$skills_dir" | tr '\n' ' ')"
    else
      fail "Claude skills missing or broken ($count ok, $broken broken)" "bash scripts/lib/install-claude-skills.sh"
    fi
  fi
  echo

  log_info "=== Editors (used from your laptop via Remote-SSH) ==="
  if ls -d "${HOME}"/.vscode-server/cli/servers/*/ >/dev/null 2>&1 || ls -d "${HOME}"/.vscode-server/bin/*/ >/dev/null 2>&1; then
    log_success "VS Code Remote-SSH server present"
  else
    note "VS Code server not present yet (connect once from your laptop)"
  fi
  if ls -d "${HOME}"/.cursor-server/bin/linux-x64/*/ >/dev/null 2>&1; then
    log_success "Cursor Remote-SSH server present"
  else
    note "Cursor server not present yet (connect once from your laptop)"
  fi
  echo

  log_info "=== Repositories: SOT + mirrors + venvs ==="
  local sot_base
  if sot_base="$(detect_sot_base)"; then
    log_success "SOT base: $sot_base"
  else
    fail "SOT base not found (expected ~/cloudfiles/code/Users/<you>/main/arrive-aml)" "see docs/FRESH-VM.md"
    sot_base=""
  fi
  if [ -d "$MIRROR_BASE" ]; then
    log_success "Mirror base: $MIRROR_BASE"
  else
    fail "$MIRROR_BASE missing (VM restarted? /mnt is wiped on stop/start)" "aml-bootstrap --restore"
  fi
  if [ -n "$sot_base" ] && [ -f "${ARRIVE_ROOT}/repos.conf" ]; then
    local url name mirror sot mir
    while IFS='|' read -r url name mirror || [ -n "${url:-}" ]; do
      url="$(trim "${url:-}")"; [ -z "$url" ] && continue; [[ "$url" == \#* ]] && continue
      name="$(trim "${name:-}")"; [ -n "$name" ] || name="$(basename "$url" .git)"
      mirror="$(trim "${mirror:-yes}")"
      sot="${sot_base}/${name}"; mir="${MIRROR_BASE}/${name}"
      if [ ! -d "$sot/.git" ]; then
        fail "$name: not cloned to SOT" "bash scripts/setup-repos.sh --only $name"
        continue
      fi
      [ "$mirror" = "yes" ] || { log_success "$name: SOT only (AUTO_MIRROR=$mirror)"; continue; }
      if mirror_is_valid "$sot" "$mir"; then
        local branch venv_msg="" unsynced
        branch="$(git -C "$mir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
        unsynced="$(mirror_unsynced_count "$mir")"
        if [ "${unsynced:-0}" -gt 0 ]; then
          fail "$name: $unsynced commit(s) on $branch not yet in the SOT" "cd $mir && git push sot HEAD   (see ~/.local/state/arrive-aml/sot-sync.log)"
        fi
        if [ ! -x "$mir/.git/hooks/arrive-aml-sync-sot" ]; then
          fail "$name: SOT sync hooks missing" "bash scripts/lib/setup-mirror-worktree.sh $name"
        fi
        if [ -f "$mir/pyproject.toml" ]; then
          if [ -x "$mir/.venv/bin/python" ]; then
            venv_msg=", venv ok"
          else
            venv_msg=", venv MISSING"
            fail "$name: .venv missing/broken in mirror" "bash scripts/lib/setup-python-venv.sh $mir"
          fi
        fi
        log_success "$name: mirror $mir [$branch]$venv_msg"
      else
        if [ -f "$mir/.git" ]; then
          fail "$name: legacy worktree mirror at $mir (slow, shared registrations)" "aml-bootstrap --restore   (converts it to a local clone)"
        else
          fail "$name: mirror missing or broken at $mir" "aml-bootstrap --restore   (or: bash scripts/setup-repos.sh --only $name)"
        fi
      fi
    done < "${ARRIVE_ROOT}/repos.conf"
  fi
  echo

  log_info "=== Disk ==="
  local root_use
  root_use="$(df --output=pcent / | tail -n1 | tr -dc '0-9')"
  if [ "${root_use:-0}" -ge 90 ]; then
    note "OS disk is ${root_use}% full. Big consumers: ~/uv-venvs (legacy venvs), ~/.vscode-server, ~/.cache/uv. venvs now live in $UV_VENV_ROOT."
  else
    log_success "OS disk ${root_use}% used"
  fi
  if [ -d /mnt ]; then
    log_success "/mnt (ephemeral local disk): $(df -h --output=avail /mnt | tail -n1 | xargs) free"
  fi
  echo

  print_separator
  if [ ${#FAILED[@]} -eq 0 ]; then
    log_success "All required checks passed!"
    [ ${#NOTES[@]} -gt 0 ] && log_info "${#NOTES[@]} optional note(s) above."
    print_separator
    exit 0
  fi
  log_warn "${#FAILED[@]} required check(s) failed:"
  local item
  for item in "${FAILED[@]}"; do
    echo "  - ${item%%|*}"
    echo "      fix: ${item#*|}"
  done
  print_separator
  exit 1
}

main "$@"
