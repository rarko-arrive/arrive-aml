# Example: Setting Up arrive-aml with Mirror Worktree Pattern

This is a **complete walkthrough** showing how to set up the arrive-aml repository using the canonical Azure ML workflow.

## Initial Setup (On Fresh Azure ML VM)

### Step 1: Clone to Source of Truth

```bash
# Create the SOT location
mkdir -p ~/cloudfiles/rarko/main
cd ~/cloudfiles/rarko/main

# Clone arrive-aml
git clone git@github.com:rarko-arrive/arrive-aml.git
cd arrive-aml

# This is your Source of Truth (SOT)
pwd
# Output: /home/azureuser/cloudfiles/rarko/main/arrive-aml
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
cd ~/cloudfiles/rarko/main/arrive-aml
bash scripts/lib/setup-mirror-worktree.sh

# This creates:
# /mnt/mirror/arrive-aml/ ← Your active worktree (FAST!)
```

### Step 4: Switch to Mirror

```bash
# Always work here from now on
cd /mnt/mirror/arrive-aml

# Test performance
time git status
# Output: real 0m0.004s  ⚡ FAST!

# Compare with SOT
cd ~/cloudfiles/rarko/main/arrive-aml
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
# ✓ In ~/cloudfiles/rarko/main/arrive-aml/.git (persistent)
# ✓ On GitHub (remote backup)
```

## Working on Multiple Features

```bash
# Create additional worktrees for parallel work
cd ~/cloudfiles/rarko/main/arrive-aml

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
cd ~/cloudfiles/rarko/main/arrive-aml
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
# ~/uv-envs/arrive-aml/ ← Venv on local disk (fast!)
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
cd ~/cloudfiles/rarko/main/arrive-aml
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
          path: ~/cloudfiles/rarko/main/arrive-aml
      
      - name: Create mirror worktree
        run: |
          cd ~/cloudfiles/rarko/main/arrive-aml
          git worktree add /mnt/mirror/arrive-aml-ci || true
      
      - name: Run tests (fast!)
        working-directory: /mnt/mirror/arrive-aml-ci
        run: |
          bash scripts/verify-setup.sh
          bash scripts/setup-vm.sh --dry-run --all
```

## Handling VM Restarts

### /mnt Persistence

Good news: `/mnt/mirror` **persists across VM restarts**!

```bash
# After VM restart, your mirror is still there
cd /mnt/mirror/arrive-aml
git status  # Still works!
```

### If Mirror Gets Wiped

In rare cases, if `/mnt/mirror` is wiped:

```bash
# Re-create from SOT (fast - just links)
cd ~/cloudfiles/rarko/main/arrive-aml
git worktree add /mnt/mirror/arrive-aml

# Your work is safe in:
# 1. SOT's .git database (~/cloudfiles)
# 2. Remote (GitHub) - if you pushed
```

## Directory Structure Overview

After complete setup:

```
/home/azureuser/
├── cloudfiles/rarko/main/
│   └── arrive-aml/              ← Source of Truth (SOT)
│       ├── .git/                ← Full git database
│       ├── scripts/
│       ├── docs/
│       └── README.md
│
├── uv-envs/
│   └── arrive-aml/              ← Python venv (local disk)
│       └── ...
│
└── /mnt/mirror/
    └── arrive-aml/              ← Active worktree (WORK HERE!)
        ├── .git ───┐            ← Pointer to SOT's .git
        ├── .venv ──┼──> ~/uv-envs/arrive-aml/
        ├── scripts/│
        ├── docs/   │
        └── README.md
                    │
    (git database)  │
                    ↓
    ~/cloudfiles/rarko/main/arrive-aml/.git/
```

## Cleanup & Maintenance

### Remove a Worktree

```bash
# From SOT
cd ~/cloudfiles/rarko/main/arrive-aml
git worktree remove /mnt/mirror/arrive-aml

# Or force
git worktree remove --force /mnt/mirror/arrive-aml
```

### List All Worktrees

```bash
cd ~/cloudfiles/rarko/main/arrive-aml
git worktree list

# Output:
# /home/azureuser/cloudfiles/rarko/main/arrive-aml  abc123 [main]
# /mnt/mirror/arrive-aml                             abc123 [feature/new]
```

### Prune Stale Worktrees

```bash
cd ~/cloudfiles/rarko/main/arrive-aml
git worktree prune
```

## Summary: Complete Workflow

```bash
# ONE-TIME SETUP
mkdir -p ~/cloudfiles/rarko/main
cd ~/cloudfiles/rarko/main
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
