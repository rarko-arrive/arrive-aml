#!/usr/bin/env bash
set -euo pipefail

# Who is this VM for? (idempotent; the first step of scripts/bootstrap.sh)
#
# Detects your name, email and GitHub user from what is already known, asks only
# for what is missing, and saves the answers to ~/.config/arrive-aml/env (this VM)
# and <SOT base>/.arrive-aml/profile (your share, so your other VMs ask nothing).
#
#   bash scripts/lib/configure-user.sh                # ask only if something is missing
#   bash scripts/lib/configure-user.sh --reconfigure  # review / change every answer
#   bash scripts/lib/configure-user.sh --yes --name "Colin Tracy" --email ctracy@arrivelogistics.com
#
# Without a terminal (startup script, --yes, login auto-restore) it never waits
# for input: it uses what it can detect and never invents an identity.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/common.sh"

RECONFIGURE=false
OPT_NAME=""
OPT_EMAIL=""
OPT_ORG=""

usage() {
  sed -n '4,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

profile_file() {
  local base
  base="$(detect_sot_base 2>/dev/null)" || return 1
  echo "${base}/.arrive-aml/profile"
}

# Read KEY from the profile without executing it (the share is writable by the
# whole workspace, so it is parsed as data, never sourced).
profile_get() {
  local key="$1" file
  file="$(profile_file)" || return 0
  [ -f "$file" ] || return 0
  sed -n "s/^${key}=\"\\(.*\\)\"\$/\\1/p" "$file" | head -n1 | sed -e 's/\\\(.\)/\1/g'
}

save_profile() {
  local file
  file="$(profile_file)" || return 0
  mkdir -p "$(dirname "$file")" 2>/dev/null || return 0
  {
    echo "# arrive-aml profile (written by scripts/lib/configure-user.sh; read by your other VMs)"
    printf 'ARRIVE_USER_NAME="%s"\n' "$(printf '%s' "$ARRIVE_USER_NAME" | sed -e 's/[\\"$`]/\\&/g')"
    printf 'ARRIVE_USER_EMAIL="%s"\n' "$(printf '%s' "$ARRIVE_USER_EMAIL" | sed -e 's/[\\"$`]/\\&/g')"
    [ -z "$ARRIVE_GITHUB_USER" ] || printf 'ARRIVE_GITHUB_USER="%s"\n' "$ARRIVE_GITHUB_USER"
    [ "$ARRIVE_GITHUB_ORG" = "$ARRIVE_DEFAULT_GITHUB_ORG" ] || printf 'ARRIVE_GITHUB_ORG="%s"\n' "$ARRIVE_GITHUB_ORG"
  } > "$file" 2>/dev/null || true
}

gh_ready() {
  command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1
}

valid_email() {
  [[ "$1" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]
}

# First non-empty argument
first() {
  local v
  for v in "$@"; do
    [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  done
  return 0
}

team_repo_names() {
  read_repo_entries | cut -d'|' -f2 | paste -sd, - | sed 's/,/, /g'
}

welcome() {
  cat > /dev/tty <<WELCOME

  ┌────────────────────────────────────────────────────────────────┐
  │  Welcome to arrive-aml                                          │
  │  This turns your compute instance into a ready-to-go workbench: │
  │  fast git, uv, Docker, GitHub, Claude Code + the team skills,   │
  │  and every team repo cloned and ready to work on.               │
  │                                                                 │
  │  Two questions now, one GitHub login in your browser later,     │
  │  then about 10 minutes of installing. Press Enter to accept     │
  │  the suggestion in [brackets].                                  │
  └────────────────────────────────────────────────────────────────┘

WELCOME
}

summary() {
  local base
  base="$(detect_sot_base 2>/dev/null || echo '?')"
  cat > /dev/tty <<SUMMARY

    You          ${ARRIVE_USER_NAME} <${ARRIVE_USER_EMAIL}>
    Your files   $(stable_cloudfiles_path "$base")   (persistent, shared by all your VMs)
    Team repos   github.com/${ARRIVE_GITHUB_ORG}: $(team_repo_names)
    GitHub       $( [ -n "$ARRIVE_GITHUB_USER" ] && echo "@${ARRIVE_GITHUB_USER}" || echo "you will log in once, in your browser" )

SUMMARY
}

ask_identity() {
  local name email tries=0
  ask name "Your full name (for git commits)" "$ARRIVE_USER_NAME"
  while [ -z "$name" ] && [ "$tries" -lt 3 ]; do
    tries=$((tries + 1))
    ask name "Your full name, e.g. Colin Tracy" ""
  done
  tries=0
  ask email "Your work email" "$(first "$ARRIVE_USER_EMAIL" "$SUGGESTED_EMAIL")"
  while ! valid_email "$email" && [ "$tries" -lt 3 ]; do
    tries=$((tries + 1))
    printf '  That does not look like an email address.\n' > /dev/tty
    ask email "Your work email" "$SUGGESTED_EMAIL"
  done
  ARRIVE_USER_NAME="$name"
  ARRIVE_USER_EMAIL="$email"
}

ask_everything() {
  local org extra
  ask_identity
  ask org "Team GitHub org" "$ARRIVE_GITHUB_ORG"
  ARRIVE_GITHUB_ORG="${org:-$ARRIVE_GITHUB_ORG}"
  ask extra "Extra repos to set up too (owner/name ..., Enter for none)" ""
  if [ -n "$extra" ]; then
    local r
    for r in $extra; do
      EXTRA_REPOS+=("$r")
    done
  fi
}

add_extra_repos() {
  local r name
  [ "${#EXTRA_REPOS[@]}" -gt 0 ] || return 0
  mkdir -p "$(dirname "$ARRIVE_EXTRA_REPOS_FILE")"
  [ -f "$ARRIVE_EXTRA_REPOS_FILE" ] || printf '# Your personal repos (format: REPO|NAME|AUTO_MIRROR, see repos.conf)\n' > "$ARRIVE_EXTRA_REPOS_FILE"
  for r in "${EXTRA_REPOS[@]}"; do
    name="$(repo_name_from_spec "$r")"
    if read_repo_entries | cut -d'|' -f2 | grep -qx "$name"; then
      continue
    fi
    printf '%s|%s|yes\n' "$r" "$name" >> "$ARRIVE_EXTRA_REPOS_FILE"
    log_success "Added $r to your repos ($ARRIVE_EXTRA_REPOS_FILE)"
  done
}

save() {
  config_set ARRIVE_USER_NAME "$ARRIVE_USER_NAME"
  config_set ARRIVE_USER_EMAIL "$ARRIVE_USER_EMAIL"
  [ -z "$ARRIVE_GITHUB_USER" ] || config_set ARRIVE_GITHUB_USER "$ARRIVE_GITHUB_USER"
  # Only pin the org when it differs from the team default, so a later change of
  # the default (repos moving org) reaches everyone automatically.
  if [ "$ARRIVE_GITHUB_ORG" = "$ARRIVE_DEFAULT_GITHUB_ORG" ]; then
    config_unset ARRIVE_GITHUB_ORG
  else
    config_set ARRIVE_GITHUB_ORG "$ARRIVE_GITHUB_ORG"
  fi
  save_profile
  if command -v git >/dev/null 2>&1; then
    apply_git_identity
  fi
}

configure_user() {
  local had_saved="${ARRIVE_USER_NAME:+yes}"
  EXTRA_REPOS=()

  local gh_name="" gh_login=""
  if gh_ready; then
    gh_login="$(gh api user -q .login 2>/dev/null || true)"
    gh_name="$(gh api user -q '.name // empty' 2>/dev/null || true)"
  fi

  ARRIVE_USER_NAME="$(first "$OPT_NAME" "$ARRIVE_USER_NAME" "$(profile_get ARRIVE_USER_NAME)" \
    "$(git config --global user.name 2>/dev/null || true)" "$gh_name")"
  ARRIVE_USER_EMAIL="$(first "$OPT_EMAIL" "$ARRIVE_USER_EMAIL" "$(profile_get ARRIVE_USER_EMAIL)" \
    "$(git config --global user.email 2>/dev/null || true)")"
  ARRIVE_GITHUB_USER="$(first "$gh_login" "$ARRIVE_GITHUB_USER" "$(profile_get ARRIVE_GITHUB_USER)")"
  local profile_org
  profile_org="$(profile_get ARRIVE_GITHUB_ORG)"
  if [ -n "$OPT_ORG" ]; then
    ARRIVE_GITHUB_ORG="$OPT_ORG"
  elif [ "$ARRIVE_GITHUB_ORG" = "$ARRIVE_DEFAULT_GITHUB_ORG" ] && [ -n "$profile_org" ]; then
    ARRIVE_GITHUB_ORG="$profile_org"
  fi
  local user
  user="$(aml_user 2>/dev/null || true)"
  SUGGESTED_EMAIL=""
  [ -z "$user" ] || SUGGESTED_EMAIL="${user}@${ARRIVE_EMAIL_DOMAIN}"

  local complete=false
  if [ -n "$ARRIVE_USER_NAME" ] && valid_email "$ARRIVE_USER_EMAIL"; then
    complete=true
  fi

  if [ "$complete" = true ] && { [ "$RECONFIGURE" = false ] || ! can_prompt; }; then
    save
    log_success "Setting up for ${ARRIVE_USER_NAME} <${ARRIVE_USER_EMAIL}>${ARRIVE_GITHUB_USER:+ · GitHub @${ARRIVE_GITHUB_USER}} · org ${ARRIVE_GITHUB_ORG}"
    [ -n "$had_saved" ] || log_info "  (detected; change any time: aml-bootstrap --configure)"
    return 0
  fi

  if ! can_prompt; then
    if [ -n "$ARRIVE_USER_NAME" ] || [ -n "$ARRIVE_USER_EMAIL" ]; then
      valid_email "$ARRIVE_USER_EMAIL" || ARRIVE_USER_EMAIL=""
      [ -z "$ARRIVE_USER_NAME" ] || config_set ARRIVE_USER_NAME "$ARRIVE_USER_NAME"
      [ -z "$ARRIVE_USER_EMAIL" ] || config_set ARRIVE_USER_EMAIL "$ARRIVE_USER_EMAIL"
      apply_git_identity
    fi
    log_warn "Your name/email for git commits are not set yet (no terminal to ask)."
    log_info "  Fix: aml-bootstrap --configure    (or: --name \"First Last\" --email ${SUGGESTED_EMAIL:-you@${ARRIVE_EMAIL_DOMAIN}})"
    return 0
  fi

  [ -n "$had_saved" ] || welcome
  if [ "$RECONFIGURE" = true ]; then
    ask_everything
  else
    ask_identity
  fi
  while true; do
    summary
    if ask_yes "Look right?"; then
      break
    fi
    ask_everything
  done
  save
  add_extra_repos
  log_success "Saved. Setting up for ${ARRIVE_USER_NAME} <${ARRIVE_USER_EMAIL}>"
}

main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --reconfigure|--configure) RECONFIGURE=true ;;
      --yes|-y) export ARRIVE_NONINTERACTIVE=1 ;;
      --name) OPT_NAME="${2:-}"; shift ;;
      --email) OPT_EMAIL="${2:-}"; shift ;;
      --github-org) OPT_ORG="${2:-}"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
  done
  if [ -n "$OPT_EMAIL" ] && ! valid_email "$OPT_EMAIL"; then
    log_error "--email '$OPT_EMAIL' is not an email address"
    exit 1
  fi
  configure_user
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  check_not_root
  main "$@"
fi
