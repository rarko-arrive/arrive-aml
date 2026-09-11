# Repository Configuration Guide

This guide explains how to configure which repositories are automatically cloned and mirrored on Azure ML VMs.

## Overview

The `repos.conf` file defines a list of repositories to clone to the Source of Truth location (`~/cloudfiles/rarko/main/`) and optionally create mirror worktrees in `/mnt/mirror/` for fast git operations.

## File Format

`repos.conf` uses a simple pipe-delimited format:

```
REPO_URL|REPO_NAME|AUTO_MIRROR
```

- **REPO_URL**: SSH git URL (e.g., `git@github.com:user/repo.git`)
- **REPO_NAME**: Directory name for the repo
- **AUTO_MIRROR**: `yes` to create `/mnt/mirror/` worktree, `no` to skip

### Example

```conf
# Core repositories
git@github.com:rarko-arrive/arrive-aml.git|arrive-aml|yes
git@github.com:rarko-arrive/azureml-skills.git|azureml-skills|yes
git@github.com:rarko-arrive/arrive-ds.git|arrive-ds|yes

# Additional repos (no mirror needed)
git@github.com:rarko-arrive/data-pipelines.git|data-pipelines|no
```

## Usage

### Setup All Repos

```bash
cd ~/cloudfiles/rarko/main/arrive-aml
bash scripts/setup-repos.sh
```

This will:
1. Clone each repo to `~/cloudfiles/rarko/main/REPO_NAME/`
2. Create mirror worktree at `/mnt/mirror/REPO_NAME/` (if `AUTO_MIRROR=yes`)
3. Skip repos that already exist

### List Configured Repos

```bash
bash scripts/setup-repos.sh --list
```

Shows all repos configured in `repos.conf`.

### Clone Without Mirrors

```bash
bash scripts/setup-repos.sh --skip-mirrors
```

Clones repos to SOT but doesn't create mirror worktrees.

## Adding Your Own Repos

1. **Edit repos.conf**:
   ```bash
   cd ~/cloudfiles/rarko/main/arrive-aml
   vim repos.conf
   ```

2. **Add your repo**:
   ```conf
   git@github.com:your-org/your-repo.git|your-repo|yes
   ```

3. **Run setup**:
   ```bash
   bash scripts/setup-repos.sh
   ```

## Default Repositories

### arrive-aml
**Purpose**: Azure ML VM setup scripts  
**Mirror**: Yes  
**URL**: https://github.com/rarko-arrive/arrive-aml

Contains setup scripts, documentation, and configuration for Azure ML VMs.

### azureml-skills
**Purpose**: Claude Code skills library  
**Mirror**: Yes  
**URL**: https://github.com/rarko-arrive/azureml-skills

Reusable Claude Code skills for Python/Azure ML development workflows. Includes the `/work-in-repo` skill for automated development workflows.

### arrive-ds
**Purpose**: Data science utilities  
**Mirror**: Yes  
**URL**: https://github.com/rarko-arrive/arrive-ds

Common data science utilities, Snowflake connectors, and shared code.

## Why Mirror Worktrees?

Mirror worktrees provide **100x faster git operations**:

| Location | Git Status Time | Use For |
|----------|----------------|---------|
| `~/cloudfiles/rarko/main/REPO/` | 7-30 seconds | Backup (SOT) |
| `/mnt/mirror/REPO/` | <1 second | Development |

**How it works:**
- Both locations share the same `.git` database
- Commits in mirror automatically sync to SOT
- Pushes to remote work from either location
- Everything stays backed up

## Repository Layout

After running `setup-repos.sh`:

```
~/cloudfiles/rarko/main/
├── arrive-aml/              ← SOT
├── azureml-skills/          ← SOT
└── arrive-ds/               ← SOT

/mnt/mirror/
├── arrive-aml/              ← Fast mirror (worktree)
├── azureml-skills/          ← Fast mirror (worktree)
└── arrive-ds/               ← Fast mirror (worktree)
```

**Always work in** `/mnt/mirror/` **for fast git operations!**

## Automation

### Include in VM Setup

Add to your VM setup workflow:

```bash
# 1. Clone arrive-aml
git clone git@github.com:rarko-arrive/arrive-aml.git ~/cloudfiles/rarko/main/arrive-aml
cd ~/cloudfiles/rarko/main/arrive-aml

# 2. Run VM setup
bash scripts/setup-vm.sh --all

# 3. Setup all repos
bash scripts/setup-repos.sh
```

### For New Team Members

Share this one-liner:

```bash
git clone git@github.com:rarko-arrive/arrive-aml.git ~/cloudfiles/rarko/main/arrive-aml && \
cd ~/cloudfiles/rarko/main/arrive-aml && \
bash scripts/setup-vm.sh --all && \
bash scripts/setup-repos.sh
```

## Troubleshooting

### Repository Already Exists

The script skips existing repositories. To re-clone:

```bash
# Remove and re-run
rm -rf ~/cloudfiles/rarko/main/REPO_NAME
bash scripts/setup-repos.sh
```

### Mirror Worktree Issues

```bash
# Remove and recreate mirror
cd ~/cloudfiles/rarko/main/REPO_NAME
git worktree remove --force /mnt/mirror/REPO_NAME
rm -rf /mnt/mirror/REPO_NAME
git worktree add /mnt/mirror/REPO_NAME
```

### Permission Denied on /mnt/mirror

```bash
sudo mkdir -p /mnt/mirror
sudo chown $USER:$USER /mnt/mirror
```

### SSH Authentication Failed

Ensure your SSH key is added to GitHub:

```bash
# Test SSH
ssh -T git@github.com

# Should show: "Hi USERNAME! You've successfully authenticated"

# If not, add key
ssh-add ~/.ssh/id_ed25519_github
```

## Advanced Configuration

### Per-Repo Mirror Control

Set `AUTO_MIRROR=no` for repos that don't need fast git operations:

```conf
# Documentation repo (rarely changed, no mirror needed)
git@github.com:rarko-arrive/docs.git|docs|no
```

### Multiple Environments

Create different config files for different teams:

```bash
# Data science team
cp repos.conf repos-ds.conf

# ML engineering team  
cp repos.conf repos-mle.conf

# Use specific config
bash scripts/setup-repos.sh --config repos-ds.conf
```

(Note: `--config` flag not yet implemented, but can be added)

## Best Practices

1. **Keep repos.conf in version control** - Share team setup
2. **Use SSH URLs** - Easier authentication than HTTPS
3. **Enable mirrors for active repos** - Development repos benefit most
4. **Disable mirrors for static repos** - Docs/archives don't need speed
5. **Document purpose** - Add comments in repos.conf explaining each repo

## See Also

- [AZUREML-WORKTREE-PATTERN.md](AZUREML-WORKTREE-PATTERN.md) - Deep dive on worktrees
- [README.md](../README.md) - Main setup guide
- [CLAUDE-SETUP.md](../CLAUDE-SETUP.md) - Claude Code integration
