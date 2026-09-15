#!/usr/bin/env bash
set -euo pipefail

# Install cloudflared (Cloudflare tunnel client).
# Used by apps such as etp-explanations `make share` to mint a public HTTPS URL.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/common.sh"

cloudflared_linux_asset() {
  case "$(uname -m)" in
    x86_64|amd64) echo "cloudflared-linux-amd64" ;;
    aarch64|arm64) echo "cloudflared-linux-arm64" ;;
    *) return 1 ;;
  esac
}

install_cloudflared() {
  local bin_dir="${HOME}/.local/bin"
  export PATH="${bin_dir}:${PATH}"

  log_info "Installing cloudflared..."

  if command -v cloudflared >/dev/null 2>&1; then
    log_success "cloudflared already installed: $(command -v cloudflared)"
    log_info "Version: $(cloudflared --version 2>/dev/null | head -n1)"
    return 0
  fi

  if [ "$(uname -s)" = "Darwin" ]; then
    if ! command -v brew >/dev/null 2>&1; then
      log_error "Homebrew is required on macOS. Then: brew install cloudflared"
      return 1
    fi
    brew install cloudflared
    log_success "cloudflared installed via Homebrew"
    log_info "Version: $(cloudflared --version 2>/dev/null | head -n1)"
    return 0
  fi

  local asset dest tmp
  if ! asset="$(cloudflared_linux_asset)"; then
    log_error "Unsupported architecture: $(uname -m). See https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/"
    return 1
  fi

  mkdir -p "$bin_dir"
  dest="${bin_dir}/cloudflared"
  tmp="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" RETURN

  log_info "Downloading ${asset} from GitHub releases..."
  if ! curl -fsSL --retry 3 -o "$tmp" \
    "https://github.com/cloudflare/cloudflared/releases/latest/download/${asset}"; then
    log_error "Failed to download cloudflared"
    return 1
  fi
  if ! chmod +x "$tmp"; then
    log_error "Downloaded cloudflared is not executable"
    return 1
  fi
  # A failed GitHub HTML error page would still be marked +x; require an ELF binary.
  if command -v file >/dev/null 2>&1 && ! file "$tmp" | grep -qi 'elf'; then
    log_error "Download did not look like a Linux binary ($(file "$tmp"))"
    return 1
  fi
  mv "$tmp" "$dest"
  trap - RETURN

  add_to_path "$bin_dir" "cloudflared (arrive-aml setup)"

  if ! command -v cloudflared >/dev/null 2>&1; then
    log_error "cloudflared not on PATH after install (expected ${dest})"
    log_error "Open a new shell or: source ~/.bashrc"
    return 1
  fi

  log_success "cloudflared installed: ${dest}"
  log_info "Version: $(cloudflared --version 2>/dev/null | head -n1)"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  check_not_root
  install_cloudflared
fi
