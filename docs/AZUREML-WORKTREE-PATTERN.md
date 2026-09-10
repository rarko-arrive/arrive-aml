# Azure ML Persistent Mirror Worktree Pattern

**The canonical workflow for efficient development on Azure ML compute instances.**

## The Problem

Azure ML's `~/cloudfiles/code/Users/` is network-mounted (SMB/CIFS), making git operations painfully slow:
- `git status`: 7-30 seconds
- `git diff`: 10-40 seconds
- IDE file watching: constant lag

**But we need persistence** - `/tmp` is fast but ephemeral (wiped on VM restart).

## The Solution: Persistent Mirror Worktree

Use **two locations** working together:

```
~/cloudfiles/rarko/main/repo-name/     ← Source of Truth (SOT) - persistent
                                          Network mount (slow but never lost)

/mnt/mirror/repo-name/                  ← Active Worktree - fast local disk
                                          Where you actually work (fast, persists across sessions)
```

`/mnt/mirror/` is **local disk that persists** - best of both worlds!

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  ~/cloudfiles/rarko/main/repo-name/  (SOT)                  │
│  - Full git repository (.git directory)                      │
│  - Network-mounted (slow)                                    │
│  - Automatically backed up by Azure                          │
│  - Accessible from laptop/other VMs                          │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ git worktree add
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  /mnt/mirror/repo-name/  (Active Worktree)                  │
│  - Linked git worktree (shared .git)                        │
│  - Local disk (fast!)                                        │
│  - Persists across VM restarts                              │
│  - Where you do all your work                               │
└─────────────────────────────────────────────────────────────┘
```

## Setup (One-Time Per Repo)

### 1. Clone to Source of Truth

```bash
# Create persistent location
mkdir -p ~/cloudfiles/rarko/main
cd ~/cloudfiles/rarko/main

# Clone your repository
git clone git@github.com:your-org/repo-name.git
cd repo-name
```

### 2. Create Mirror Worktree

```bash
# Create mirror directory
sudo mkdir -p /mnt/mirror
sudo chown $USER:$USER /mnt/mirror

# Add worktree on fast local disk
cd ~/cloudfiles/rarko/main/repo-name
git worktree add /mnt/mirror/repo-name

# Now work in the mirror
cd /mnt/mirror/repo-name
```

### 3. Test Performance

```bash
# In mirror (fast!)
cd /mnt/mirror/repo-name
time git status  # <1 second ⚡

# In SOT (slow)
cd ~/cloudfiles/rarko/main/repo-name
time git status  # 7-30 seconds 🐌
```

## Daily Workflow

### Start of Day

```bash
# Always work in the mirror
cd /mnt/mirror/repo-name

# Pull latest changes
git pull origin main

# Create feature branch
git checkout -b feature/your-feature
```

### During Development

```bash
# Work in /mnt/mirror/repo-name
cd /mnt/mirror/repo-name

# Fast git operations
git status           # <1s
git diff            # <1s
git add .
git commit -m "Changes"

# IDE/Editor works smoothly
cursor .            # Fast file watching
code .              # No lag
```

### Sync to SOT (Push to Remote)

```bash
# In mirror worktree
cd /mnt/mirror/repo-name

# Commit your work
git add .
git commit -m "Your changes"

# Push to remote (goes through SOT)
git push origin feature/your-feature
```

The push automatically syncs through the SOT's `.git` directory!

### End of Day

```bash
# Just commit and push - that's it!
git add .
git commit -m "End of day checkpoint"
git push origin feature/your-feature

# Your work is:
# ✓ In /mnt/mirror (fast local disk)
# ✓ In ~/cloudfiles (persistent network mount)
# ✓ On remote (GitHub/Azure DevOps)
```

## How Git Worktrees Work

```bash
# SOT structure
~/cloudfiles/rarko/main/repo-name/
├── .git/              # Full repository database
├── src/
└── README.md

# Mirror structure  
/mnt/mirror/repo-name/
├── .git               # Pointer to SOT's .git directory
├── src/               # Your working files
└── README.md

# They share the same .git database!
```

When you commit in `/mnt/mirror/`, it's stored in `~/cloudfiles/rarko/main/repo-name/.git/`
When you push, it uses the SOT's git database.

## Advanced: Multiple Worktrees

Work on multiple branches simultaneously:

```bash
# SOT
cd ~/cloudfiles/rarko/main/repo-name

# Create worktrees for different features
git worktree add /mnt/mirror/repo-name-feature1 feature/feature1
git worktree add /mnt/mirror/repo-name-feature2 feature/feature2
git worktree add /mnt/mirror/repo-name-hotfix hotfix/critical-bug

# Switch between them instantly
cd /mnt/mirror/repo-name-feature1   # Work on feature 1
cd /mnt/mirror/repo-name-feature2   # Switch to feature 2
cd /mnt/mirror/repo-name-hotfix     # Jump to hotfix
```

Each worktree is independent but shares the same git database - no expensive re-cloning!

## Python Virtual Environments

Keep venvs on local disk too:

```bash
# In mirror worktree
cd /mnt/mirror/repo-name

# Create venv on local disk (fast!)
uv venv .venv
source .venv/bin/activate

# Install dependencies
uv pip install -r requirements.txt

# Add to .gitignore
echo ".venv/" >> .gitignore
```

## IDE/Editor Configuration

### Cursor / VS Code

**Always open the mirror worktree:**

```bash
# Good - fast
cd /mnt/mirror/repo-name
cursor .

# Bad - slow
cd ~/cloudfiles/rarko/main/repo-name
cursor .  # Don't do this!
```

Your IDE will:
- ✓ Load files instantly
- ✓ Watch for changes without lag
- ✓ Run git operations smoothly
- ✓ Use the local disk for temporary files

### Configure Exclude Patterns

In `/mnt/mirror/repo-name/.vscode/settings.json`:

```json
{
  "files.watcherExclude": {
    "**/.git/objects/**": true,
    "**/.git/subtree-cache/**": true,
    "**/node_modules/**": true,
    "**/.venv/**": true
  },
  "search.exclude": {
    "**/.venv": true,
    "**/node_modules": true
  }
}
```

## Cleanup / Removal

### Remove a Worktree

```bash
# From the SOT
cd ~/cloudfiles/rarko/main/repo-name
git worktree remove /mnt/mirror/repo-name

# Or force remove if needed
git worktree remove --force /mnt/mirror/repo-name

# Clean up orphaned worktrees
git worktree prune
```

### Start Fresh

```bash
# Remove mirror
rm -rf /mnt/mirror/repo-name

# Re-create from SOT
cd ~/cloudfiles/rarko/main/repo-name
git worktree add /mnt/mirror/repo-name
```

## Troubleshooting

### "Already exists and is not a valid git repo"

```bash
# Clean up stale worktree
cd ~/cloudfiles/rarko/main/repo-name
git worktree prune

# Remove directory
rm -rf /mnt/mirror/repo-name

# Re-add
git worktree add /mnt/mirror/repo-name
```

### "Worktree is locked"

```bash
cd ~/cloudfiles/rarko/main/repo-name
git worktree unlock /mnt/mirror/repo-name
```

### Changes Not Syncing

```bash
# Check worktree status
cd ~/cloudfiles/rarko/main/repo-name
git worktree list

# Verify both point to same .git
cd /mnt/mirror/repo-name
cat .git  # Should point to SOT's .git
```

### /mnt/mirror/ Wiped After VM Restart

If `/mnt/mirror/` is empty after restart:

```bash
# Re-create from SOT (fast - just links, not clone)
cd ~/cloudfiles/rarko/main/repo-name
git worktree add /mnt/mirror/repo-name

# Your changes are safe in:
# 1. SOT's .git database
# 2. Remote (if you pushed)
```

## Best Practices

### ✅ Do

- **Always work in `/mnt/mirror/`** - it's fast
- **Commit often** - worktree commits go to SOT's .git
- **Push to remote regularly** - your ultimate backup
- **Open IDEs in mirror** - cursor/code in /mnt/mirror/
- **Run tests in mirror** - fast file I/O
- **Create venvs in mirror** - .venv/ on local disk

### ❌ Don't

- **Don't edit files in SOT directly** - slow and laggy
- **Don't rely only on /mnt** - always push to remote
- **Don't create worktrees in /tmp** - ephemeral
- **Don't forget to commit** - uncommitted work in mirror only

## Example: arrive-aml Repository

This repo uses the pattern:

```bash
# SOT (persistent)
~/cloudfiles/rarko/main/arrive-aml/

# Mirror (fast)
/mnt/mirror/arrive-aml/

# Daily workflow
cd /mnt/mirror/arrive-aml
git pull origin main
git checkout -b feature/new-script

# Make changes, test scripts
bash scripts/setup-vm.sh --dry-run

# Fast git operations
git add scripts/
git commit -m "Add new setup features"
git push origin feature/new-script

# Create PR from GitHub
gh pr create --title "New setup features"
```

## Integration with CI/CD

Your CI/CD can pull from the SOT:

```yaml
# .github/workflows/test.yml
jobs:
  test:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v3
        with:
          path: ~/cloudfiles/rarko/main/arrive-aml
      
      - name: Create fast worktree
        run: |
          cd ~/cloudfiles/rarko/main/arrive-aml
          git worktree add /mnt/mirror/arrive-aml-ci
      
      - name: Run tests (fast!)
        working-directory: /mnt/mirror/arrive-aml-ci
        run: |
          bash scripts/verify-setup.sh
```

## Automation Script

Save as `scripts/lib/setup-mirror-worktree.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

setup_mirror_worktree() {
  local REPO_NAME="${1:-$(basename "$(pwd)")}"
  local SOT="${HOME}/cloudfiles/rarko/main/${REPO_NAME}"
  local MIRROR="/mnt/mirror/${REPO_NAME}"
  
  log_info "Setting up mirror worktree for: $REPO_NAME"
  
  # Ensure /mnt/mirror exists
  sudo mkdir -p /mnt/mirror
  sudo chown "$USER:$USER" /mnt/mirror
  
  # Check if SOT exists
  if [ ! -d "$SOT/.git" ]; then
    log_error "Source of Truth not found: $SOT"
    log_info "Clone your repo there first:"
    log_info "  mkdir -p ~/cloudfiles/rarko/main"
    log_info "  cd ~/cloudfiles/rarko/main"
    log_info "  git clone git@github.com:org/$REPO_NAME.git"
    return 1
  fi
  
  # Create or refresh worktree
  if [ -d "$MIRROR" ]; then
    log_warn "Mirror already exists: $MIRROR"
    log_info "Remove it first: rm -rf $MIRROR"
    return 1
  fi
  
  log_info "Creating worktree..."
  cd "$SOT"
  git worktree add "$MIRROR"
  
  log_success "Mirror worktree created!"
  echo
  log_info "Source of Truth: $SOT"
  log_info "Active Mirror:   $MIRROR"
  echo
  log_info "Next steps:"
  log_info "  cd $MIRROR"
  log_info "  cursor .  # or code ."
  log_info "  git pull origin main"
  echo
  log_info "Test performance:"
  log_info "  time git status  # Should be <1 second"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  setup_mirror_worktree "$@"
fi
```

## Summary

**Persistent Mirror Worktree Pattern = Fast + Persistent + Simple**

- 📁 SOT in `~/cloudfiles/rarko/main/` - persistent, backed up
- ⚡ Mirror in `/mnt/mirror/` - fast local disk, persists across restarts
- 🔗 Git worktree links them - shared database
- 🚀 Work in mirror - 100x faster git operations
- 💾 Push to remote - ultimate persistence
- 🎯 Perfect for AI-driven iteration cycles

**The result**: Smooth, fast development with full persistence and zero manual syncing.
