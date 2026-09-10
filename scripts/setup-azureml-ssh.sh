#!/usr/bin/env bash
set -euo pipefail

# Wire an Azure ML compute instance into ~/.ssh/config for Cursor Remote SSH,
# and keep a gitignored copy at .ssh/config in this repo.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_SSH_DIR="$ROOT/.ssh"
REPO_CONFIG="$REPO_SSH_DIR/config"
EXAMPLE="$REPO_SSH_DIR/config.example"
USER_SSH_DIR="$HOME/.ssh"
USER_CONFIG="$USER_SSH_DIR/config"

echo "==> Azure ML → Cursor Remote SSH setup"
echo

if [ ! -f "$EXAMPLE" ]; then
  echo "Missing $EXAMPLE" >&2
  exit 1
fi

mkdir -p "$USER_SSH_DIR" "$REPO_SSH_DIR"
chmod 700 "$USER_SSH_DIR"

# --- Collect values ---
read -rp "SSH Host alias (short name in Cursor, e.g. rarko1): " HOST_ALIAS
HOST_ALIAS="${HOST_ALIAS// /}"
if [ -z "$HOST_ALIAS" ]; then
  echo "Alias is required." >&2
  exit 1
fi

read -rp "Public IP from Azure ML Details tab: " HOST_IP
read -rp "SSH port [50000]: " HOST_PORT
HOST_PORT="${HOST_PORT:-50000}"
read -rp "SSH user [azureuser]: " HOST_USER
HOST_USER="${HOST_USER:-azureuser}"
read -rp "Path to downloaded .pem file: " PEM_SRC
PEM_SRC="${PEM_SRC/#\~/$HOME}"
# Relative paths: try cwd, then repo .ssh/
if [ ! -f "$PEM_SRC" ] && [ -f "$ROOT/$PEM_SRC" ]; then
  PEM_SRC="$ROOT/$PEM_SRC"
fi
if [ ! -f "$PEM_SRC" ] && [ -f "$REPO_SSH_DIR/$(basename "$PEM_SRC")" ]; then
  PEM_SRC="$REPO_SSH_DIR/$(basename "$PEM_SRC")"
fi
# Resolve to absolute for clearer logs / IdentityFile
PEM_SRC="$(cd "$(dirname "$PEM_SRC")" && pwd)/$(basename "$PEM_SRC")"

if [ ! -f "$PEM_SRC" ]; then
  echo "PEM not found: $PEM_SRC" >&2
  echo "In Azure ML: Compute → your instance → Details → download the SSH key." >&2
  exit 1
fi

# Key filename is independent of the Host alias (e.g. alias rarko1, key rarko.pem).
PEM_DEFAULT="$(basename "$PEM_SRC")"
read -rp "Install key as ~/.ssh/<name> [${PEM_DEFAULT}]: " PEM_NAME
PEM_NAME="${PEM_NAME:-$PEM_DEFAULT}"
PEM_NAME="${PEM_NAME// /}"
case "$PEM_NAME" in
  *.pem) ;;
  *) PEM_NAME="${PEM_NAME}.pem" ;;
esac
if [ -z "$PEM_NAME" ] || [ "$PEM_NAME" = ".pem" ]; then
  echo "PEM name is required." >&2
  exit 1
fi

PEM_DEST="$USER_SSH_DIR/${PEM_NAME}"
# Existing keys are often chmod 400 — cp cannot overwrite those in place
if [ -e "$PEM_DEST" ]; then
  chmod u+w "$PEM_DEST" 2>/dev/null || true
  rm -f "$PEM_DEST"
fi
cp "$PEM_SRC" "$PEM_DEST"
chmod 400 "$PEM_DEST"
echo "Installed key → $PEM_DEST"

# Optional gitignored mirror in the repo (same basename)
REPO_PEM="$REPO_SSH_DIR/${PEM_NAME}"
if [ "$PEM_SRC" != "$REPO_PEM" ]; then
  if [ -e "$REPO_PEM" ]; then
    chmod u+w "$REPO_PEM" 2>/dev/null || true
    rm -f "$REPO_PEM"
  fi
  cp "$PEM_DEST" "$REPO_PEM"
  chmod 400 "$REPO_PEM"
  echo "Repo copy   → $REPO_PEM (gitignored)"
fi

# --- Host block ---
HOST_BLOCK=$(cat <<EOF

# Azure ML compute ($HOST_ALIAS) — managed by ds-cursor-demo/scripts/setup-azureml-ssh.sh
Host ${HOST_ALIAS}
    HostName ${HOST_IP}
    User ${HOST_USER}
    Port ${HOST_PORT}
    IdentityFile ${PEM_DEST}
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
    ServerAliveInterval 60
    ServerAliveCountMax 3
    ForwardAgent yes
EOF
)

write_or_replace_host() {
  local target="$1"
  local tmp
  tmp="$(mktemp)"
  if [ -f "$target" ] && grep -qE "^Host[[:space:]]+${HOST_ALIAS}([[:space:]]|$)" "$target"; then
    # Drop existing Host block for this alias (until next Host / EOF)
    awk -v alias="$HOST_ALIAS" '
      BEGIN { skip=0 }
      /^Host[[:space:]]+/ {
        if ($2 == alias) { skip=1; next }
        skip=0
      }
      skip == 0 { print }
    ' "$target" >"$tmp"
    printf '%s\n' "$HOST_BLOCK" >>"$tmp"
    mv "$tmp" "$target"
    echo "Updated Host ${HOST_ALIAS} in $target"
  else
    [ -f "$target" ] && cat "$target" >"$tmp" || : >"$tmp"
    printf '%s\n' "$HOST_BLOCK" >>"$tmp"
    mv "$tmp" "$target"
    echo "Added Host ${HOST_ALIAS} to $target"
  fi
  chmod 600 "$target"
}

write_or_replace_host "$USER_CONFIG"
# Repo copy uses ~/.ssh path for IdentityFile (portable on this Mac)
write_or_replace_host "$REPO_CONFIG"

echo
echo "==> Testing SSH (BatchMode)…"
if ssh -o BatchMode=yes -o ConnectTimeout=15 "$HOST_ALIAS" "echo OK: connected as \$(whoami)@\$(hostname)"; then
  echo
  echo "SSH works."
else
  echo
  echo "Could not connect yet. Common fixes:" >&2
  echo "  - Compute instance is Running in Azure ML" >&2
  echo "  - Public IP / port match the Details tab (IP can change after stop/start)" >&2
  echo "  - PEM matches this compute instance" >&2
  echo "  - Try: ssh -v $HOST_ALIAS" >&2
  exit 1
fi

echo
echo "=================================================================="
echo "Next: Cursor User settings (required — plain ssh is not enough)"
echo "  Merge .cursor/remote-ssh.settings.example.json into Cursor Settings JSON"
echo "  with alias \"${HOST_ALIAS}\". Minimum:"
echo
cat <<EOF
  {
    "remote.SSH.remotePlatform": { "${HOST_ALIAS}": "linux" },
    "remote.SSH.remoteServerListenOnSocket": { "${HOST_ALIAS}": true },
    "remote.SSH.localServerDownload": "always",
    "remote.SSH.showLoginTerminal": false,
    "remote.SSH.enableAgentForwarding": false
  }
EOF
echo
echo "Then:"
echo "  1. Install extension: Remote - SSH (anysphere.remote-ssh)"
echo "  2. Fully quit and reopen Cursor"
echo "  3. Cmd+Shift+P → Remote-SSH: Connect to Host… → ${HOST_ALIAS}"
echo "  4. Open your project folder on the VM (or clone the repo there)"
echo "  5. Use Agent on the right — it runs against the remote workspace"
echo
echo "If Cursor fails with Connection reset by peer but ssh works, see Setup.md"
echo "Quick check anytime:  ssh ${HOST_ALIAS}"
echo "=================================================================="
