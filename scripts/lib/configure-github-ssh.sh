#!/usr/bin/env bash
set -euo pipefail

# Configure GitHub SSH authentication (idempotent)
# - Generates ~/.ssh/id_ed25519_github if missing
# - Adds a github.com block to ~/.ssh/config
# - Trusts GitHub's host keys (no first-connection prompt)
# - Uploads the key with `gh` if it is not on your account yet
# - Falls back to ssh.github.com:443 when port 22 is blocked

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/common.sh"

configure_github_ssh() {
  local SSH_DIR="${HOME}/.ssh"
  local KEY_FILE="${SSH_DIR}/id_ed25519_github"
  local CONFIG_FILE="${SSH_DIR}/config"
  local EMAIL="${1:-$(git config --global user.email 2>/dev/null || echo "${USER}@arrivelogistics.com")}"

  log_info "Configuring GitHub SSH authentication..."

  mkdir -p "$SSH_DIR"
  chmod 700 "$SSH_DIR"

  # --- key -----------------------------------------------------------------
  if [ -f "$KEY_FILE" ]; then
    log_success "SSH key already exists: $KEY_FILE"
  else
    log_info "Generating ed25519 SSH key for GitHub..."
    ssh-keygen -t ed25519 -C "$EMAIL" -f "$KEY_FILE" -N ""
    chmod 400 "$KEY_FILE"
    chmod 644 "${KEY_FILE}.pub"
    log_success "SSH key generated!"
  fi

  # --- ~/.ssh/config -------------------------------------------------------
  if [ -f "$CONFIG_FILE" ] && grep -qE "^Host github.com" "$CONFIG_FILE" 2>/dev/null; then
    log_success "GitHub entry already exists in ~/.ssh/config"
  else
    {
      echo ""
      echo "# GitHub (arrive-aml setup)"
      echo "Host github.com"
      echo "  HostName github.com"
      echo "  User git"
      echo "  IdentityFile $KEY_FILE"
      echo "  IdentitiesOnly yes"
    } >> "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    log_success "GitHub configuration added to ~/.ssh/config"
  fi

  # --- known_hosts ---------------------------------------------------------
  if ensure_github_known_hosts; then
    log_success "GitHub host keys trusted"
  else
    log_warn "Could not fetch GitHub host keys (offline?). First connection will ask to confirm."
  fi

  # --- upload key with gh if needed ---------------------------------------
  local pub_material
  pub_material="$(awk '{print $2}' "${KEY_FILE}.pub")"
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    if gh ssh-key list 2>/dev/null | grep -qF "$pub_material"; then
      log_success "SSH key is already registered on your GitHub account"
    else
      log_info "Adding SSH key to your GitHub account via gh..."
      if gh ssh-key add "${KEY_FILE}.pub" --title "arrive-aml-$(this_host)-$(date +%Y%m%d)" 2>/dev/null; then
        log_success "SSH key added to GitHub!"
      else
        log_warn "Could not add the key automatically (gh may need the admin:public_key scope)."
        log_info "Fix: gh auth refresh -h github.com -s admin:public_key   (then re-run this script)"
      fi
    fi
  else
    log_warn "gh is not authenticated - key was not uploaded automatically."
    log_info "Run: gh auth login   (choose SSH, and let it upload ${KEY_FILE}.pub)"
  fi

  # --- test ----------------------------------------------------------------
  log_info "Testing GitHub SSH connection..."
  if github_ssh_ok; then
    log_success "GitHub SSH connection successful! ($(echo "$GITHUB_SSH_OUTPUT" | head -n1))"
    return 0
  fi

  # Port 22 blocked? Try the HTTPS port.
  if [[ "$GITHUB_SSH_OUTPUT" == *"Connection timed out"* || "$GITHUB_SSH_OUTPUT" == *"Connection refused"* || "$GITHUB_SSH_OUTPUT" == *"Network is unreachable"* ]]; then
    log_warn "Port 22 to github.com appears blocked - trying ssh.github.com:443..."
    local alt
    alt="$(ssh -T -p 443 -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new \
      -i "$KEY_FILE" git@ssh.github.com 2>&1 || true)"
    if [[ "$alt" == *"successfully authenticated"* ]]; then
      sed -i.bak -E '/^Host github.com$/,/^$/{s/^  HostName github.com$/  HostName ssh.github.com\n  Port 443/}' "$CONFIG_FILE"
      rm -f "${CONFIG_FILE}.bak"
      log_success "Switched ~/.ssh/config to ssh.github.com:443 - GitHub SSH now works"
      return 0
    fi
  fi

  echo
  log_warn "GitHub SSH test failed:"
  echo "    $(echo "$GITHUB_SSH_OUTPUT" | head -n2 | tr '\n' ' ')"
  echo
  log_info "Your public key (add it at https://github.com/settings/ssh/new if missing):"
  echo
  cat "${KEY_FILE}.pub"
  echo
  return 1
}

# Run if executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  check_not_root
  configure_github_ssh "$@"
fi
