# Mirror Worktree Workflow - Complete Guide

**Canonical end-to-end workflow for working efficiently on Azure ML with the mirror worktree pattern.**

This document provides reproducible commands for the complete development cycle: setup → work → commit → push.

## Overview

The mirror worktree pattern solves Azure ML's slow git performance by creating a local disk worktree that shares the same `.git` database as your network-mounted Source of Truth (SOT).

**Performance improvement**: `git status` goes from 7-30 seconds → <1 second

## Prerequisites

- Azure ML compute instance
- Repository cloned to SOT: `~/cloudfiles/code/Users/rarko/main/REPO_NAME/`
- Local mount point: `/mnt/mirror/` (or `/mnt/batch/` on some VMs)
- Sudo access (one-time, to create `/mnt/mirror/`)

## Complete Workflow

### Step 1: Setup Mirror Worktree (One-Time)

```bash
# Create mirror mount point (one-time, requires sudo)
sudo mkdir -p /mnt/mirror
sudo chown $USER:$USER /mnt/mirror

# Navigate to SOT
cd ~/cloudfiles/code/Users/rarko/main/arrive-aml

# Create mirror worktree
git worktree add /mnt/mirror/arrive-aml

# Navigate to mirror
cd /mnt/mirror/arrive-aml

# Verify it works
time git status  # Should be <1 second
```

**What this does:**
- Creates a new worktree at `/mnt/mirror/arrive-aml`
- Shares the same `.git` database as SOT
- All commits in mirror → stored in SOT's `.git/`
- Pushes work from either location

### Step 2: Create Feature Branch

```bash
cd /mnt/mirror/arrive-aml

# Pull latest
git pull origin main

# Create and checkout feature branch
git checkout -b feature/polish-and-simplify

# Verify branch
git branch -vv
```

### Step 3: Work on Changes

**All development happens in the mirror for fast git operations:**

```bash
cd /mnt/mirror/arrive-aml

# Make changes to files
# ... edit files ...

# Fast git status (<1s)
git status

# View changes
git diff
git diff --cached  # For staged changes
```

**Example - Remove temporary files:**

```bash
cd /mnt/mirror/arrive-aml
git rm git-fix.md instruct.md result.md
```

**Example - Move files:**

```bash
cd /mnt/mirror/arrive-aml
git mv AZURE-ML-PATHS.md CLAUDE-SETUP.md Setup.md docs/
```

**Example - Edit files:**

```bash
cd /mnt/mirror/arrive-aml
# Use your editor or Edit tool
vim pyproject.toml
```

### Step 4: Stage and Commit

```bash
cd /mnt/mirror/arrive-aml

# Review changes
git status
git diff

# Stage specific files (prefer over git add -A)
git add pyproject.toml
git add docs/

# Or stage all tracked changes
git add -u

# Commit with descriptive message
git commit -m "refactor: Clean up repo structure and fix dependencies

- Remove temporary files (git-fix.md, instruct.md, result.md)
- Move detailed docs to docs/ directory (AZURE-ML-PATHS.md, CLAUDE-SETUP.md, Setup.md)
- Fix arriveds dependency to be truly optional
- Update all documentation references

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"

# Verify commit
git log -1
```

### Step 5: Push to Remote

```bash
cd /mnt/mirror/arrive-aml

# Push feature branch
git push origin feature/polish-and-simplify

# Or push with upstream tracking
git push -u origin feature/polish-and-simplify
```

**What happens:**
1. Push from mirror uses SOT's `.git` database
2. Changes are immediately in SOT
3. Remote receives the push
4. Work is fully backed up (local disk + network mount + remote)

### Step 6: Verify Sync to SOT

```bash
# Check SOT has the changes
cd ~/cloudfiles/code/Users/rarko/main/arrive-aml
git log -1  # Should show your latest commit
git status  # Clean (may take 7-30s)

# Check mirror
cd /mnt/mirror/arrive-aml
git status  # Clean (<1s)
```

### Step 7: Create Pull Request (Optional)

```bash
cd /mnt/mirror/arrive-aml

# Using GitHub CLI
gh pr create \
  --title "Polish repo structure and fix dependencies" \
  --body "$(cat <<'EOF'
## Summary
- Remove temporary working files
- Consolidate documentation into docs/ directory
- Fix arriveds dependency to be truly optional
- Update all documentation references

## Changes
- Removed: git-fix.md, instruct.md, result.md
- Moved to docs/: AZURE-ML-PATHS.md, CLAUDE-SETUP.md, Setup.md
- Fixed: pyproject.toml to remove [tool.uv.sources] causing build errors

## Test Plan
- [ ] Verify setup works without arriveds: `uv pip install -e .`
- [ ] Check all doc links work
- [ ] Run verification script: `bash scripts/verify-setup.sh`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

## Common Operations

### Check Worktree Status

```bash
# From either SOT or mirror
git worktree list

# Output shows:
# /path/to/sot           abc1234 [main]
# /mnt/mirror/repo       def5678 [feature/branch]
```

### Switch Branches in Mirror

```bash
cd /mnt/mirror/arrive-aml

# Switch to existing branch
git checkout main

# Create new branch
git checkout -b feature/new-feature
```

### Sync Latest from Main

```bash
cd /mnt/mirror/arrive-aml

# Pull latest main
git checkout main
git pull origin main

# Switch back to feature branch and rebase
git checkout feature/polish-and-simplify
git rebase main
```

### Remove Mirror Worktree (Cleanup)

```bash
# From SOT
cd ~/cloudfiles/code/Users/rarko/main/arrive-aml

# Remove worktree
git worktree remove /mnt/mirror/arrive-aml

# Or force remove if there are uncommitted changes
git worktree remove --force /mnt/mirror/arrive-aml

# Clean up directory
rm -rf /mnt/mirror/arrive-aml
```

### Recreate Mirror (If Corrupted)

```bash
# Remove old mirror
cd ~/cloudfiles/code/Users/rarko/main/arrive-aml
git worktree remove --force /mnt/mirror/arrive-aml
rm -rf /mnt/mirror/arrive-aml

# Create fresh mirror
git worktree add /mnt/mirror/arrive-aml

# Or on specific branch
git worktree add /mnt/mirror/arrive-aml feature/branch-name
```

## Performance Comparison

| Operation | SOT (Network Mount) | Mirror (Local Disk) | Speedup |
|-----------|---------------------|---------------------|---------|
| `git status` | 7-30 seconds | <1 second | 10-100x |
| `git diff` | 5-15 seconds | <0.5 seconds | 15-30x |
| `git add .` | 10-20 seconds | <1 second | 15-30x |
| `git commit` | 2-5 seconds | <0.5 seconds | 5-10x |

## Troubleshooting

### Mirror Shows Different Content Than SOT

**Symptom**: Files in `/mnt/mirror/` differ from `~/cloudfiles/`

**Cause**: File system caching or uncommitted changes

**Fix**:
```bash
cd /mnt/mirror/arrive-aml

# Check for uncommitted changes
git status -u

# If different from SOT, reset hard
git reset --hard HEAD

# Or copy specific file from SOT
cp ~/cloudfiles/code/Users/rarko/main/arrive-aml/FILE /mnt/mirror/arrive-aml/FILE
```

### "Fatal: /mnt/mirror/arrive-aml is not a git repository"

**Fix**:
```bash
# Recreate the worktree
cd ~/cloudfiles/code/Users/rarko/main/arrive-aml
git worktree remove --force /mnt/mirror/arrive-aml
rm -rf /mnt/mirror/arrive-aml
git worktree add /mnt/mirror/arrive-aml
```

### Push Fails: "Permission denied"

**Fix**:
```bash
# Verify SSH key is loaded
ssh -T git@github.com

# If not working, add key
ssh-add ~/.ssh/id_ed25519_github
```

### Disk Space Full on /mnt/mirror

**Cause**: `/mnt/mirror` is on local disk (limited space)

**Fix**:
```bash
# Remove old worktrees
git worktree list  # Find what's there
git worktree remove /mnt/mirror/old-repo

# Or clean up build artifacts in mirror
cd /mnt/mirror/arrive-aml
rm -rf .venv node_modules __pycache__
```

## Best Practices

1. **Always work in mirror** - Never work in SOT for active development
2. **Commit and push frequently** - Mirror is on local disk, not backed up directly
3. **Use specific git add** - `git add file1 file2` instead of `git add -A`
4. **Check git status regularly** - Fast in mirror, shows what will be committed
5. **Keep mirror clean** - Remove unused worktrees to save disk space
6. **One mirror per feature** - Create multiple mirrors for parallel work on different branches

## Advanced: Multiple Mirrors

Work on multiple features in parallel:

```bash
cd ~/cloudfiles/code/Users/rarko/main/arrive-aml

# Create multiple mirrors
git worktree add /mnt/mirror/arrive-aml-feature1 feature/feature1
git worktree add /mnt/mirror/arrive-aml-feature2 feature/feature2
git worktree add /mnt/mirror/arrive-aml-bugfix main  # For hotfixes

# Work in each independently
cd /mnt/mirror/arrive-aml-feature1
# ... make changes ...
git commit -m "Add feature 1"

cd /mnt/mirror/arrive-aml-feature2
# ... make changes ...
git commit -m "Add feature 2"
```

## Quick Reference

```bash
# Setup
sudo mkdir -p /mnt/mirror && sudo chown $USER:$USER /mnt/mirror
cd ~/cloudfiles/code/Users/rarko/main/arrive-aml
git worktree add /mnt/mirror/arrive-aml

# Daily workflow
cd /mnt/mirror/arrive-aml
git checkout -b feature/name
# ... make changes ...
git add file1 file2
git commit -m "message"
git push origin feature/name

# Cleanup
cd ~/cloudfiles/code/Users/rarko/main/arrive-aml
git worktree remove /mnt/mirror/arrive-aml
```

## Related Documentation

- [AZUREML-WORKTREE-PATTERN.md](AZUREML-WORKTREE-PATTERN.md) - Deep technical dive
- [REPOS-CONFIG.md](REPOS-CONFIG.md) - Automated setup for multiple repos
- [AZURE-ML-PATHS.md](AZURE-ML-PATHS.md) - Path structure explanation
