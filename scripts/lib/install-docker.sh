#!/usr/bin/env bash
set -euo pipefail

# Install Docker Engine and docker-compose

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/common.sh"

install_docker() {
  log_info "Installing Docker Engine and docker-compose..."

  if command -v docker >/dev/null 2>&1; then
    log_success "Docker already installed: $(docker --version)"
  else
    if ! is_ubuntu; then
      log_warn "This script is designed for Ubuntu. Install manually if needed."
      return 1
    fi

    log_info "Removing old Docker packages if present..."
    sudo apt-get remove -y -qq docker docker-engine docker.io containerd runc 2>/dev/null || true

    log_info "Installing Docker prerequisites..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq \
      ca-certificates \
      curl \
      gnupg \
      lsb-release

    log_info "Adding Docker's official GPG key..."
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    log_info "Setting up Docker repository..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    log_info "Installing Docker Engine..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin

    log_success "Docker Engine installed!"
  fi

  # Add current user to docker group
  log_info "Adding ${USER} to docker group..."
  if groups | grep -q docker; then
    log_success "User already in docker group"
  else
    sudo usermod -aG docker "${USER}"
    log_success "User added to docker group"
    log_warn "You'll need to log out and back in for group membership to take effect"
    log_warn "Or run: newgrp docker"
  fi

  # Install docker-compose (standalone, for compatibility)
  if command -v docker-compose >/dev/null 2>&1; then
    log_success "docker-compose already installed: $(docker-compose --version)"
  else
    log_info "Installing docker-compose..."
    local DOCKER_COMPOSE_VERSION="v2.24.1"
    sudo curl -SL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
      -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    log_success "docker-compose installed!"
  fi

  # Start Docker service
  log_info "Starting Docker service..."
  sudo systemctl enable docker --now || log_warn "Could not enable Docker service"

  # Verify installation
  log_info "Verifying Docker installation..."
  docker --version
  docker-compose --version

  log_success "Docker installation complete!"
  echo
  log_info "Test with: docker run hello-world"
}

# Run if executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  check_not_root
  install_docker
fi
