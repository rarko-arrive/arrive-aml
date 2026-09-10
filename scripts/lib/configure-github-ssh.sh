#!/usr/bin/env bash
set -euo pipefail

# Configure GitHub SSH authentication
# Generates SSH key, configures ~/.ssh/config, and adds key to GitHub

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/common.sh"

configure_github_ssh() {
  local SSH_DIR="${HOME}/.ssh"
  local KEY_FILE="${SSH_DIR}/id_ed25519_github"
  local CONFIG_FILE="${SSH_DIR}/config"
  local EMAIL="${1:-rarko@arrivelogistics.com}"

  log_info "Configuring GitHub SSH authentication..."

  # Create .ssh directory if it doesn't exist
  mkdir -p "$SSH_DIR"
  chmod 700 "$SSH_DIR"

  # Generate SSH key if it doesn't exist
  if [ -f "$KEY_FILE" ]; then
    log_success "SSH key already exists: $KEY_FILE"
  else
    log_info "Generating ed25519 SSH key for GitHub..."
    ssh-keygen -t ed25519 -C "$EMAIL" -f "$KEY_FILE" -N ""
    chmod 400 "$KEY_FILE"
    chmod 644 "${KEY_FILE}.pub"
    log_success "SSH key generated!"
  fi

  # Configure SSH config file
  log_info "Configuring ~/.ssh/config for GitHub..."

  if [ -f "$CONFIG_FILE" ] && grep -q "Host github.com" "$CONFIG_FILE" 2>/dev/null; then
    log_success "GitHub entry already exists in ~/.ssh/config"
  else
    # Create or append to config
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

  # Start ssh-agent and add key
  log_info "Adding key to ssh-agent..."
  eval "$(ssh-agent -s)" > /dev/null
  ssh-add "$KEY_FILE" 2>/dev/null || true

  # Try to add key to GitHub automatically via gh CLI
  if command -v gh >/dev/null 2>&1; then
    log_info "Attempting to add SSH key to GitHub via gh CLI..."

    # Check if already authenticated
    if gh auth status >/dev/null 2>&1; then
      log_info "Adding SSH key to GitHub account..."
      gh ssh-key add "${KEY_FILE}.pub" --title "arrive-aml-$(hostname)-$(date +%Y%m%d)" 2>/dev/null && \
        log_success "SSH key added to GitHub!" || \
        log_warn "Could not add key automatically. Add manually (see below)."
    else
      log_warn "gh CLI not authenticated. Authenticate first: gh auth login"
    fi
  fi

  # Show public key for manual addition
  echo
  print_separator
  log_info "Your SSH public key (copy this to GitHub if not added automatically):"
  echo
  cat "${KEY_FILE}.pub"
  echo
  log_info "Add it at: https://github.com/settings/ssh/new"
  print_separator
  echo

  # Test connection
  log_info "Testing GitHub SSH connection..."
  if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    log_success "GitHub SSH connection successful!"
  else
    log_warn "GitHub SSH test failed. Make sure your public key is added to GitHub."
    log_info "Visit: https://github.com/settings/keys"
  fi
}

# Run if executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  check_not_root
  configure_github_ssh "$@"
fi
