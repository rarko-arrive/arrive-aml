#!/usr/bin/env bash
set -euo pipefail

# First command on a brand-new compute instance (nothing cloned yet):
#
#   curl -fsSL https://raw.githubusercontent.com/rarko-arrive/arrive-aml/main/scripts/get-started.sh | bash
#
# 1. finds your folder on the workspace share (~/cloudfiles/code/Users/<you>)
# 2. clones arrive-aml into <you>/main/arrive-aml (https - no SSH key needed yet)
# 3. runs scripts/bootstrap.sh, which asks who you are and sets everything up
#
# Already have arrive-aml on your share (e.g. a second VM)? This just runs bootstrap.
# Options are passed on to bootstrap.sh (e.g. --name "First Last" --email you@...).
# Environment: ARRIVE_AML_USER=<folder>  ARRIVE_GITHUB_ORG=<org>  ARRIVE_AML_URL=<clone url>
#              ARRIVE_AML_BRANCH=<branch>  (test an unmerged branch; default: the repo's default branch)
#
# Standalone on purpose: it runs before any other arrive-aml file exists.

ORG="${ARRIVE_GITHUB_ORG:-rarko-arrive}"
URL="${ARRIVE_AML_URL:-https://github.com/${ORG}/arrive-aml.git}"
USERS_DIR="${ARRIVE_USERS_DIR:-${HOME}/cloudfiles/code/Users}"
BRANCH="${ARRIVE_AML_BRANCH:-}"

say()  { printf '\033[0;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[0;32m✓ %s\033[0m\n' "$*"; }
die()  { printf '\033[0;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
tty_ok() { (exec 3</dev/tty) 2>/dev/null; }

instance_name() {
  local n=""
  [ -f "${HOME}/cloudfiles/.nbvm" ] && n="$(sed -n 's/^instance=//p' "${HOME}/cloudfiles/.nbvm" | head -n1)"
  echo "${n:-${CI_NAME:-$(hostname -s 2>/dev/null || hostname)}}"
}

# ctracy2 -> ctracy, ctracy-gpu -> ctracy (only when that folder exists)
guess_user() {
  local host c
  host="$(instance_name)"
  for c in "$host" "${host%%[0-9]*}" "${host%%[-_]*}" "${host%%[-_0-9]*}"; do
    [ -n "$c" ] && [ -d "$USERS_DIR/$c" ] && { echo "$c"; return 0; }
  done
  return 1
}

pick_user() {
  if [ -n "${ARRIVE_AML_USER:-}" ]; then
    echo "$ARRIVE_AML_USER"
    return 0
  fi
  local guess="" answer=""
  guess="$(guess_user || true)"
  if ! tty_ok; then
    [ -n "$guess" ] || die "Cannot tell which folder in $USERS_DIR is yours. Re-run with ARRIVE_AML_USER=<your folder>."
    echo "$guess"
    return 0
  fi
  {
    echo
    echo "  Your files live in a folder named after your Azure ML user, in"
    echo "  $USERS_DIR  (the folder you see under Users/ in Azure ML Studio → Notebooks)."
  } > /dev/tty
  while true; do
    if [ -n "$guess" ]; then
      printf '  Your folder name [%s]: ' "$guess" > /dev/tty
    else
      printf '  Your folder name (e.g. your email alias): ' > /dev/tty
    fi
    IFS= read -r answer < /dev/tty || true
    answer="${answer//[[:space:]]/}"
    answer="${answer:-$guess}"
    if [ -n "$answer" ] && [ -d "$USERS_DIR/$answer" ]; then
      echo "$answer"
      return 0
    fi
    [ -z "$answer" ] || printf '  No folder %s/%s. Open Azure ML Studio → Notebooks once to create it, or check the spelling.\n' "$USERS_DIR" "$answer" > /dev/tty
  done
}

main() {
  [ "$EUID" -ne 0 ] || die "Run this as your normal user (azureuser), not with sudo."
  command -v git >/dev/null 2>&1 || die "git is missing (sudo apt-get install -y git)"
  [ -d "$USERS_DIR" ] || die "$USERS_DIR not found. Is this an Azure ML compute instance with the workspace share mounted?"

  local user main_dir repo
  user="$(pick_user)"
  main_dir="$USERS_DIR/$user/main"
  repo="$main_dir/arrive-aml"
  say "Your persistent folder: $main_dir"

  # The share is root-owned CIFS: git refuses it without this (configure-git.sh sets it too).
  if ! git config --global --get-all safe.directory 2>/dev/null | grep -qx '\*'; then
    git config --global --add safe.directory '*'
  fi

  if [ -d "$repo/.git" ]; then
    ok "arrive-aml already on your share: $repo"
    if [ -n "$BRANCH" ]; then
      git -C "$repo" fetch -q origin "$BRANCH" && git -C "$repo" switch -q "$BRANCH" \
        || die "Could not switch $repo to $BRANCH"
    fi
  elif [ -e "$repo" ]; then
    die "$repo exists but is not a git clone. Move it aside and re-run."
  else
    mkdir -p "$main_dir"
    say "Cloning arrive-aml (one-time, the share is slow - about a minute)..."
    GIT_TERMINAL_PROMPT=0 git clone -q ${BRANCH:+-b "$BRANCH"} "$URL" "$repo" \
      || die "Clone of $URL failed. Private repo? Run 'gh auth login' first, or clone it yourself to $repo."
    ok "Cloned to $repo"
  fi

  export ARRIVE_SOT_BASE="$main_dir"
  # stdin may be the curl pipe; bootstrap asks its questions on /dev/tty.
  exec bash "$repo/scripts/bootstrap.sh" "$@" </dev/null
}

main "$@"
