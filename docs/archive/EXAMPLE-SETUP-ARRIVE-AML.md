> **Note (2026-09):** mirrors are now full local clones with the SOT as remote `sot`
> (see [MIRROR-PATTERN.md](../MIRROR-PATTERN.md)). Where this walkthrough shows
> `git worktree add/remove/prune` against `/mnt/mirror/<repo>`, use `aml-bootstrap --restore`
> or `bash scripts/lib/setup-mirror-worktree.sh <repo>` instead. Never `git worktree prune` in a SOT.

# Example: Setting Up arrive-aml with Mirror Worktree Pattern

This is a **complete walkthrough** showing how to set up the arrive-aml repository using the canonical Azure ML workflow.

## Initial Setup (On Fresh Azure ML VM)

### Step 1: Clone to Source of Truth

```bash
# Create the SOT location
mkdir -p ~/cloudfiles/code/Users/rarko/main
cd ~/cloudfiles/code/Users/rarko/main

# Clone arrive-aml
git clone git@github.com:rarko-arrive/arrive-aml.git
cd arrive-aml

# This is your Source of Truth (SOT)
pwd
# Output: /home/azureuser/cloudfiles/code/Users/rarko/main/arrive-aml
```

**Note**: This location is:
- ✓ Persistent (network-mounted, automatically backed up)
- ✓ Accessible from your laptop via SSH
- ✗ Slow for git operations (7-30 seconds)

### Step 2: Run Initial Setup

```bash
# Still in SOT, run setup (only needs to run once)
bash scripts/setup-vm.sh --all

# This installs:
# - Git optimizations
# - Docker, gh CLI, Claude CLI, VS Code, Cursor
# - System tools (htop, jq, etc.)
# - Disables conda auto-activation

# Reload shell
source ~/.bashrc
```

### Step 3: Create Mirror Worktree

```bash
# From the SOT, create mirror on fast local disk
cd ~/cloudfiles/code/Users/rarko/main/arrive-aml
bash scripts/lib/setup-mirror-worktree.sh

# This creates:
# /mnt/mirror/arrive-aml/ ← Your active mirror clone (FAST!)
```

### Step 4: Switch to Mirror

```bash
# Always work here from now on
cd /mnt/mirror/arrive-aml

# Test performance
time git status
# Output: real 0m0.004s  ⚡ FAST!

# Compare with SOT
cd ~/cloudfiles/code/Users/rarko/main/arrive-aml
time git status
# Output: real 0m7.682s  🐌 Slow

# Go back to mirror
cd /mnt/mirror/arrive-aml
```

## Daily Workflow

### Morning: Start Working

```bash
# Navigate to mirror
cd /mnt/mirror/arrive-aml

# Pull latest changes
git pull origin main

# Create feature branch
git checkout -b feature/add-new-installer

# Open in IDE (fast!)
cursor .  # or code .
```

### During Day: Make Changes

```bash
# You're in /mnt/mirror/arrive-aml

# Create a new installer
vim scripts/lib/install-neovim.sh

# Test it
bash scripts/lib/install-neovim.sh

# Git operations are instant
git status          # <1s
git diff           # <1s
git add scripts/lib/install-neovim.sh
git commit -m "Add neovim installer"
```

### Evening: Push Changes

```bash
# Push to remote (goes through SOT's .git)
git push origin feature/add-new-installer

# Create PR
gh pr create --title "Add neovim installer" \
             --body "Adds automated neovim installation"

# Your work is now:
# ✓ In /mnt/mirror/arrive-aml (fast local disk)
# ✓ In ~/cloudfiles/code/Users/rarko/main/arrive-aml/.git (persistent)
# ✓ On GitHub (remote backup)
```

## Working on Multiple Features

```bash
# Create additional worktrees for parallel work
cd ~/cloudfiles/code/Users/rarko/main/arrive-aml

# Feature 1: New installer
git worktree add /mnt/mirror/arrive-aml-installer feature/new-installer

# Feature 2: Documentation update
git worktree add /mnt/mirror/arrive-aml-docs feature/update-docs

# Hotfix: Critical bug
git worktree add /mnt/mirror/arrive-aml-hotfix hotfix/critical-fix

# Work on each independently
cd /mnt/mirror/arrive-aml-installer
# Make changes, commit, push

cd /mnt/mirror/arrive-aml-docs
# Make changes, commit, push

cd /mnt/mirror/arrive-aml-hotfix
# Fix bug, commit, push

# List all worktrees
cd ~/cloudfiles/code/Users/rarko/main/arrive-aml
git worktree list
```

## Python Development

### Setup Virtual Environment

```bash
# In mirror (fast!)
cd /mnt/mirror/arrive-aml

# Run bootstrap script
bash scripts/bootstrap-azureml.sh

# This creates:
# /mnt/uv-venvs/arrive-aml/ ← Venv on fast local disk
# /mnt/mirror/arrive-aml/.venv ← Symlink to it
```

### Install Dependencies

```bash
cd /mnt/mirror/arrive-aml

# Activate venv
source .venv/bin/activate

# Install dependencies (fast on local disk!)
uv pip install -r requirements.txt

# Run code
python src/arriveds/hello.py
```

## IDE Configuration

### Cursor/VS Code Settings

**Always open the mirror**, not the SOT:

```bash
# ✓ Good - Open mirror (fast)
cd /mnt/mirror/arrive-aml
cursor .

# ✗ Bad - Don't open SOT (slow)
cd ~/cloudfiles/code/Users/rarko/main/arrive-aml
cursor .  # Laggy, slow file watching
```

### Workspace Settings

Create `/mnt/mirror/arrive-aml/.vscode/settings.json`:

```json
{
  "python.defaultInterpreterPath": "${workspaceFolder}/.venv/bin/python",
  "files.watcherExclude": {
    "**/.git/objects/**": true,
    "**/.venv/**": true,
    "**/node_modules/**": true
  },
  "terminal.integrated.cwd": "${workspaceFolder}"
}
```

## Testing & CI Integration

### Local Testing

```bash
cd /mnt/mirror/arrive-aml

# Run verification (fast!)
bash scripts/verify-setup.sh

# Test individual installers
bash scripts/lib/install-gh.sh

# All file I/O is fast
pytest tests/
```

### CI/CD Integration

Your GitHub Actions can use the same pattern:

```yaml
# .github/workflows/test.yml
name: Test on Azure ML

on: [push, pull_request]

jobs:
  test:
    runs-on: self-hosted  # Your Azure ML VM
    
    steps:
      - name: Checkout to SOT
        uses: actions/checkout@v3
        with:
          path: ~/cloudfiles/code/Users/rarko/main/arrive-aml
      
      - name: Create mirror worktree
        run: |
          cd ~/cloudfiles/code/Users/rarko/main/arrive-aml
          git worktree add /mnt/mirror/arrive-aml-ci || true
      
      - name: Run tests (fast!)
        working-directory: /mnt/mirror/arrive-aml-ci
        run: |
          bash scripts/verify-setup.sh
          bash scripts/setup-vm.sh --dry-run --all
```

## Handling VM Restarts

### /mnt Is Ephemeral

`/mnt` is Azure's resource disk: `/mnt/mirror` and `/mnt/uv-venvs` are **wiped on every VM
stop/start**. Your shell prints a reminder when that happened.

```bash
aml-bootstrap --restore    # recreates every mirror + venv from the SOT (about a minute)
cd /mnt/mirror/arrive-aml
```

Your work is safe in:
1. SOT's .git database (~/cloudfiles) - every commit made in the mirror lands there immediately
2. Remote (GitHub) - if you pushed

Only uncommitted edits in the mirror are lost, so commit often.

## Directory Structure Overview

After complete setup:

```
/home/azureuser/
├── cloudfiles/code/Users/rarko/main/
│   └── arrive-aml/              ← Source of Truth (SOT), on main, updated by pushes
│       ├── .git/                ← Full git database
│       ├── scripts/
│       ├── docs/
│       └── README.md
│
/mnt/uv-venvs/
│   └── arrive-aml/              ← Python venv (fast local disk, recreated by --restore)
│       └── ...
│
└── /mnt/mirror/
    └── arrive-aml/              ← Active mirror clone (WORK HERE!) [main]
        ├── .git ───┐            ← Pointer to SOT's .git
        ├── .venv ──┼──> /mnt/uv-venvs/arrive-aml/
        ├── scripts/│
        ├── docs/   │
        └── README.md
                    │
    (git database)  │
                    ↓
    ~/cloudfiles/code/Users/rarko/main/arrive-aml/.git/
```

## Cleanup & Maintenance

### Remove a Worktree

```bash
# From SOT
cd ~/cloudfiles/code/Users/rarko/main/arrive-aml
git worktree remove /mnt/mirror/arrive-aml

# Or force
git worktree remove --force /mnt/mirror/arrive-aml
```

### List All Worktrees

```bash
cd ~/cloudfiles/code/Users/rarko/main/arrive-aml
git worktree list

# Output:
# /home/azureuser/cloudfiles/code/Users/rarko/main/arrive-aml  abc123 [main]
# /mnt/mirror/arrive-aml                             abc123 [feature/new]
```

### Prune Stale Worktrees

```bash
cd ~/cloudfiles/code/Users/rarko/main/arrive-aml
git worktree prune
```

## Summary: Complete Workflow

```bash
# ONE-TIME SETUP
mkdir -p ~/cloudfiles/code/Users/rarko/main
cd ~/cloudfiles/code/Users/rarko/main
git clone git@github.com:rarko-arrive/arrive-aml.git
cd arrive-aml
bash scripts/setup-vm.sh --all
source ~/.bashrc
bash scripts/lib/setup-mirror-worktree.sh

# DAILY WORKFLOW
cd /mnt/mirror/arrive-aml    # Always work here
git pull origin main
git checkout -b feature/new-feature
cursor .                      # Open in IDE
# ... make changes ...
git add .
git commit -m "Changes"
git push origin feature/new-feature
gh pr create

# RESULT
# ✓ Fast git operations (<1s)
# ✓ Smooth IDE experience
# ✓ Full persistence
# ✓ Automatic backups
# ✓ Ready for AI-driven iteration
```

**This is the canonical pattern for Azure ML development.** 🚀
