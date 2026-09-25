#!/usr/bin/env bash
set -euo pipefail

# Configure the interactive shell for the arrive-aml workflow (idempotent)
# - merges the resolved paths (SOT, mirror, venvs) into ~/.config/arrive-aml/env
# - installs an `aml-bootstrap` command that runs scripts/bootstrap.sh from the SOT
# - quiets Azure's login errors (conda activate with conda off PATH, readonly TMOUT)
# - adds ONE managed block to ~/.bashrc: PATH, env, and an automatic restore when
#   /mnt was wiped by a VM restart (mirrors/venvs come back on login)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/common.sh"

BLOCK_START="# >>> arrive-aml (managed - do not edit, re-run scripts/lib/configure-shell.sh) >>>"
BLOCK_END="# <<< arrive-aml <<<"

# Merge the resolved paths into the env file. Keys set elsewhere (your identity
# from configure-user.sh, your own overrides) are kept.
write_env_file() {
  local sot_base="$1"
  mkdir -p "$ARRIVE_CONFIG_DIR"
  if [ ! -s "$ARRIVE_ENV_FILE" ]; then
    cat > "$ARRIVE_ENV_FILE" <<'ENV'
# arrive-aml settings for this user on this VM.
# Written by scripts/lib/configure-shell.sh and configure-user.sh; edit freely,
# then re-run 'aml-bootstrap'. Change who you are: aml-bootstrap --configure
#
# Optional switches:
#   ARRIVE_NO_AUTO_RESTORE=1   new shells do not restore /mnt after a restart
#   ARRIVE_NO_SELF_UPDATE=1    bootstrap does not fast-forward arrive-aml first
#   ARRIVE_GITHUB_ORG="..."    team GitHub org for {org} in repos.conf/skills.conf
#   ARRIVE_GIT_PROTOCOL=https  clone over https instead of ssh (default: auto)
ENV
  fi
  config_set ARRIVE_SOT_BASE "$sot_base"
  config_set MIRROR_BASE "$MIRROR_BASE"
  config_set UV_VENV_ROOT "$UV_VENV_ROOT"
  config_set ARRIVE_UV_CACHE_DIR "$ARRIVE_UV_CACHE_DIR"
  config_set CLAUDE_SKILLS_CLONE_DIR "$CLAUDE_SKILLS_CLONE_DIR"
  log_success "Updated $ARRIVE_ENV_FILE"
}

write_bootstrap_shim() {
  local sot_base="$1"
  mkdir -p "${HOME}/.local/bin"
  cat > "${HOME}/.local/bin/aml-bootstrap" <<SHIM
#!/usr/bin/env bash
# Re-run the arrive-aml VM bootstrap (safe any time).
# A login shell does this on its own when /mnt was wiped; run it to repair or refresh.
exec bash "${sot_base}/arrive-aml/scripts/bootstrap.sh" "\$@"
SHIM
  chmod +x "${HOME}/.local/bin/aml-bootstrap"
  log_success "Installed command: aml-bootstrap"
}

write_bashrc_block() {
  local rc="${HOME}/.bashrc"
  touch "$rc"
  # Remove a previous managed block
  if grep -qF "$BLOCK_START" "$rc"; then
    sed -i "/^$(printf '%s' "$BLOCK_START" | sed 's/[][\/.*^$]/\\&/g')$/,/^$(printf '%s' "$BLOCK_END" | sed 's/[][\/.*^$]/\\&/g')$/d" "$rc"
  fi
  cat >> "$rc" <<'BLOCK'
# >>> arrive-aml (managed - do not edit, re-run scripts/lib/configure-shell.sh) >>>
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH";; esac
[ -f "$HOME/.config/arrive-aml/env" ] && . "$HOME/.config/arrive-aml/env"
# uv cache on the big local disk when it exists (created by aml-bootstrap)
[ -n "${ARRIVE_UV_CACHE_DIR:-}" ] && [ -d "$ARRIVE_UV_CACHE_DIR" ] && export UV_CACHE_DIR="$ARRIVE_UV_CACHE_DIR"
# /mnt is wiped on every VM stop/start. An interactive shell restores mirrors + venvs.
if [ -n "${PS1:-}" ] && [ -z "${ARRIVE_BOOTSTRAP_RUNNING:-}" ]; then
  _arrive_login="${ARRIVE_SOT_BASE:-}/arrive-aml/scripts/lib/login-restore.sh"
  if [ -f "$_arrive_login" ]; then
    . "$_arrive_login" || true
  fi
  unset _arrive_login
fi
# <<< arrive-aml <<<
BLOCK
  log_success "Updated managed block in ~/.bashrc"
}

# Azure writes `readonly TMOUT=900` in both /etc/profile and /etc/bash.bashrc.
# Login shells source both, so the second assignment prints
# "TMOUT: readonly variable" and then idle SSH sessions die after 15 minutes.
relax_idle_timeout() {
  local f
  for f in /etc/profile /etc/bash.bashrc; do
    [ -f "$f" ] || continue
    if ! grep -q '^readonly TMOUT=' "$f"; then
      continue
    fi
    if sudo sed -i 's/^readonly TMOUT=.*$/# arrive-aml: idle logout disabled for long agent sessions (Azure default: readonly TMOUT=900)/' "$f"; then
      log_success "Disabled idle shell logout in $f"
    else
      log_warn "Could not edit $f. Login may still print: TMOUT: readonly variable"
    fi
  done
}

configure_shell() {
  log_info "Configuring shell..."
  bash "$SCRIPT_DIR/disable-conda.sh" || log_warn "Could not quiet conda in ~/.bashrc"
  relax_idle_timeout
  local sot_base
  if ! sot_base="$(detect_sot_base)"; then
    log_error "Could not determine the SOT base directory (expected ~/cloudfiles/code/Users/<you>/main)."
    log_info "Clone arrive-aml there first, or set ARRIVE_SOT_BASE."
    return 1
  fi
  write_env_file "$sot_base"
  write_bootstrap_shim "$sot_base"
  write_bashrc_block
  log_info "SOT base: $sot_base   mirrors: $MIRROR_BASE   venvs: $UV_VENV_ROOT"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  check_not_root
  configure_shell
fi
