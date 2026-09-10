# Arrive AML - Quick Start Guide

## On a Fresh Azure ML VM

```bash
# 1. Clone the repository
git clone git@github.com:rarko-arrive/arrive-aml.git
cd arrive-aml

# 2. Run setup (installs everything)
bash scripts/setup-vm.sh --all

# 3. Reload shell
source ~/.bashrc
```

**Done!** Your VM is now configured.

## Verify Everything Works

```bash
# Check installation
bash scripts/verify-setup.sh

# Test tools
docker --version
gh --version
claude --version
uv --version
```

## For Fast Git: Mirror Worktree Pattern (Recommended)

Network-mounted storage is slow for git. Use the **persistent mirror worktree pattern**:

```bash
# One-time setup: Create mirror on fast local disk
cd ~/cloudfiles/rarko/main/arrive-aml  # Your SOT
bash scripts/lib/setup-mirror-worktree.sh

# Now always work in the mirror
cd /mnt/mirror/arrive-aml  # ⚡ Fast local disk!

# Git operations are <1s instead of 7-8s
git status   # ⚡ Instant!
git pull
git checkout -b feature/my-feature

# Do your work, commit, push - all fast!
git add .
git commit -m "Changes"
git push origin feature/my-feature

# Your changes are automatically in:
# ✓ /mnt/mirror (fast local disk)
# ✓ ~/cloudfiles (persistent, backed up)
# ✓ Remote (GitHub)
```

**Why this pattern?**
- `/mnt/mirror` = fast local disk that persists across VM restarts
- Git worktree keeps it synced with persistent storage
- No manual syncing needed - just commit and push!

**[📖 Read the complete guide →](docs/AZUREML-WORKTREE-PATTERN.md)**

## Python Development

After VM setup, configure Python environment:

```bash
# Run Python/uv bootstrap
bash scripts/bootstrap-azureml.sh

# This creates a fast local-disk virtual environment
# and symlinks .venv to avoid slow network mounts
```

## Connect from Laptop (Cursor/VS Code)

On your **laptop** (not the VM):

```bash
# Configure SSH access to the VM
bash scripts/setup-azureml-ssh.sh

# Follow prompts:
# - VM alias (e.g., rarko1)
# - Public IP (from Azure portal)
# - SSH port (usually 50000)
# - .pem key path
```

Then in Cursor/VS Code: Remote-SSH → Connect to `rarko1`

## Common Tasks

### Install Individual Tools

```bash
# Just git optimization and essentials
bash scripts/setup-vm.sh --git-optimize --system-tools

# Add Docker later
bash scripts/lib/install-docker.sh

# Add GitHub tools
bash scripts/lib/install-gh.sh
bash scripts/lib/configure-github-ssh.sh
```

### Reuse SSH Key for New VMs

Extract your public key:
```bash
ssh-keygen -y -f ~/.ssh/your-key.pem > ~/.ssh/your-key.pub
cat ~/.ssh/your-key.pub  # Copy this
```

Paste into Azure when creating the new VM (SSH settings → "Use existing public key")

See [docs/REUSE-SSH-KEY.md](docs/REUSE-SSH-KEY.md) for details.

## Troubleshooting

### Git Still Slow?
```bash
# Verify config
git config --global --list | grep -E 'fsmonitor|gc.auto'

# Should see:
#   core.fsmonitor=false
#   gc.auto=0

# Use worktree helper for truly fast git
bash scripts/lib/worktree-helper.sh init
```

### Docker Permission Denied?
```bash
sudo usermod -aG docker $USER
newgrp docker  # Or log out and back in
```

### Command Not Found?
```bash
source ~/.bashrc  # Or open new shell
```

### GitHub SSH Not Working?
```bash
# Authenticate gh CLI
gh auth login

# Or manually add key to GitHub
cat ~/.ssh/id_ed25519_github.pub  # Copy this
# Add at: https://github.com/settings/ssh/new
```

## Next Steps

- Read full [README.md](README.md) for details
- Check [Setup.md](Setup.md) for troubleshooting
- Run `/help` in Claude Code for more options

---

**Result**: Professional development environment in < 10 minutes ✨
