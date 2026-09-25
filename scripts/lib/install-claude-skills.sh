#!/usr/bin/env bash
set -euo pipefail

# Install team Claude Code skills (idempotent)
# Reads skills.conf (REPO|NAME) plus ~/.config/arrive-aml/skills.conf, clones/updates each skills repo on the OS
# disk and symlinks every skills/<skill> directory into ~/.claude/skills/ so the
# skills are available as /<skill> in Claude Code on this VM.
#
# This is what the azureml-skills repo actually needs (it is a plugin repo with
# a skills/ folder, not a plugin marketplace), so no JSON editing is required.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/common.sh"

SKILLS_CONF="${ARRIVE_ROOT}/skills.conf"
CLAUDE_SKILLS_DIR="${HOME}/.claude/skills"

install_skills_repo() {
  local url name="$2"
  url="$(repo_url "$1")"
  local dest="${CLAUDE_SKILLS_CLONE_DIR}/${name}"

  if [ -d "$dest/.git" ]; then
    log_info "Updating $name..."
    if git -C "$dest" pull -q --ff-only 2>/dev/null; then
      log_success "$name up to date ($(git -C "$dest" log -1 --format=%h))"
    else
      log_warn "Could not fast-forward $name (offline or local changes) - using existing checkout"
    fi
  else
    log_info "Cloning $name -> $dest"
    mkdir -p "$CLAUDE_SKILLS_CLONE_DIR"
    if ! git clone -q "$url" "$dest"; then
      log_error "Failed to clone $url (no access, or GitHub auth not set up: bash scripts/lib/configure-github-ssh.sh)"
      return 1
    fi
    log_success "Cloned $name"
  fi

  local skill_dir skill link count=0
  if [ -d "$dest/skills" ]; then
    for skill_dir in "$dest"/skills/*/; do
      [ -f "$skill_dir/SKILL.md" ] || continue
      skill="$(basename "$skill_dir")"
      link="${CLAUDE_SKILLS_DIR}/${skill}"
      if [ -L "$link" ]; then
        ln -sfn "${skill_dir%/}" "$link"
      elif [ -e "$link" ]; then
        log_warn "~/.claude/skills/$skill exists and is not a symlink - leaving it alone"
        continue
      else
        ln -s "${skill_dir%/}" "$link"
      fi
      count=$((count + 1))
    done
  elif [ -f "$dest/SKILL.md" ]; then
    ln -sfn "$dest" "${CLAUDE_SKILLS_DIR}/${name}"
    count=1
  fi
  log_success "$count skill(s) from $name linked into ~/.claude/skills/"
}

install_claude_skills() {
  log_info "Installing Claude Code skills from skills.conf (+ ${ARRIVE_EXTRA_SKILLS_FILE})..."
  mkdir -p "$CLAUDE_SKILLS_DIR"

  if [ ! -f "$SKILLS_CONF" ]; then
    log_warn "skills.conf not found at $SKILLS_CONF - nothing to install"
    return 0
  fi

  _ARRIVE_PROTOCOL_CACHE="$(github_protocol)"
  local spec name failed=0
  while IFS='|' read -r spec name _; do
    install_skills_repo "$spec" "$name" </dev/null || failed=1
  done < <(read_skill_entries)

  echo
  log_info "Available skills: $(ls "$CLAUDE_SKILLS_DIR" 2>/dev/null | sed 's#^#/#' | tr '\n' ' ')"
  [ "$failed" -eq 0 ]
}

# Run if executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  check_not_root
  install_claude_skills
fi
