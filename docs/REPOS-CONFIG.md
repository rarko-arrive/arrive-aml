# Repository Configuration Guide

This guide explains how to configure which repositories are automatically cloned and mirrored on Azure ML VMs.

## Overview

The `repos.conf` file defines a list of repositories to clone to the Source of Truth location (`~/cloudfiles/code/Users/<you>/main/`, derived from where arrive-aml itself lives) and optionally create fast mirror clones in `/mnt/mirror/` for fast git operations plus a uv venv on `/mnt/uv-venvs/` for repos with a `pyproject.toml`.

`scripts/bootstrap.sh` runs `setup-repos.sh` for you; `aml-bootstrap --restore` re-runs it after a VM restart.

## File Format

`repos.conf` uses a simple pipe-delimited format:

```
REPO|NAME|AUTO_MIRROR
```

- **REPO**: one of
  - `{org}/name` - a team repo; `{org}` expands to `ARRIVE_GITHUB_ORG` (the team default is set
    in one place, `ARRIVE_DEFAULT_GITHUB_ORG` in `scripts/lib/common.sh`; see
    [ORG-MOVE.md](ORG-MOVE.md) for the planned move)
  - `owner/name` - any GitHub repo
  - a full git URL (`git@github.com:owner/name.git`, `https://github.com/owner/name.git`, or another host)
- **NAME**: Directory name for the repo (default: the repo name)
- **AUTO_MIRROR**: `yes` to create the `/mnt/mirror/` clone + venv, `no` to skip (default: `yes`)

ssh vs https is chosen automatically for GitHub repos: ssh when GitHub SSH works on this VM, else
https (gh's credential helper handles the login). Force one with `ARRIVE_GIT_PROTOCOL=ssh` or
`ARRIVE_GIT_PROTOCOL=https` in `~/.config/arrive-aml/env`.

### Example

```conf
# Core repositories
{org}/arrive-aml|arrive-aml|yes
{org}/azureml-skills|azureml-skills|yes
{org}/arrive-ds|arrive-ds|yes

# Additional repos (no mirror needed)
{org}/data-pipelines|data-pipelines|no
```

## Usage

### Setup All Repos

```bash
cd ~/cloudfiles/code/Users/<you>/main/arrive-aml
bash scripts/setup-repos.sh
```

This will:
1. Clone each repo to `~/cloudfiles/code/Users/<you>/main/REPO_NAME/` (skipped if present)
2. Create or repair the mirror clone at `/mnt/mirror/REPO_NAME/` (if `AUTO_MIRROR=yes`)
3. `uv sync` into `/mnt/uv-venvs/REPO_NAME` and symlink `.venv` in the mirror (if `pyproject.toml` exists)

Options: `--only NAME` (one repo), `--add REPO` (add a personal repo, see below), `--skip-venvs`, `--skip-mirrors`, `--list`.

### List Configured Repos

```bash
bash scripts/setup-repos.sh --list
```

Shows all configured repos (team `repos.conf` first, then your personal list) with the clone URL,
the org and the protocol (ssh/https) that will be used.

### Clone Without Mirrors

```bash
bash scripts/setup-repos.sh --skip-mirrors
```

Clones repos to SOT but doesn't create mirror clones or venvs.

### One Repo Only

```bash
bash scripts/setup-repos.sh --only arrive-ds
```

## Adding Your Own Repos

Two lists are read, team first:

| File | Who | Committed? |
|------|-----|------------|
| `repos.conf` in arrive-aml | team repos, set up on every teammate's VM | yes |
| `~/.config/arrive-aml/repos.conf` | your personal repos, same format | no (per VM) |

If both list the same NAME, the team entry wins. `aml-bootstrap`, `aml-bootstrap --restore` and the
automatic restore on login all include your personal repos.

**Personal repo (just you):**

```bash
bash scripts/setup-repos.sh --add owner/name     # or a git URL
```

This records it in `~/.config/arrive-aml/repos.conf` and sets it up right away (SOT clone, mirror,
venv). The setup wizard's "extra repos" question (`aml-bootstrap --configure`) does the same.
Or edit `~/.config/arrive-aml/repos.conf` yourself and run `bash scripts/setup-repos.sh`.

**Team repo (everyone):**

1. **Edit repos.conf** (in your mirror, then open a PR):
   ```bash
   cd /mnt/mirror/arrive-aml
   vim repos.conf
   ```

2. **Add your repo**:
   ```conf
   {org}/your-repo|your-repo|yes
   ```

3. **Run setup**:
   ```bash
   bash scripts/setup-repos.sh
   ```

## Default Repositories

### arrive-aml
**Purpose**: Azure ML VM setup scripts  
**Mirror**: Yes  
**URL**: https://github.com/<team-org>/arrive-aml

Contains setup scripts, documentation, and configuration for Azure ML VMs.

### azureml-skills
**Purpose**: Claude Code skills library  
**Mirror**: Yes  
**URL**: https://github.com/<team-org>/azureml-skills

Reusable Claude Code skills for Python/Azure ML development workflows. Includes the `/work-in-repo` skill for automated development workflows.

### arrive-ds
**Purpose**: Data science utilities  
**Mirror**: Yes  
**URL**: https://github.com/<team-org>/arrive-ds

Common data science utilities, Snowflake connectors, and shared code.

## Why Mirrors?

Mirror clones provide **100x faster git operations**:

| Location | Git Status Time | Use For |
|----------|----------------|---------|
| `~/cloudfiles/code/Users/<you>/main/REPO/` | 7-30 seconds | Backup (SOT) |
| `/mnt/mirror/REPO/` | <1 second | Development |

**How it works:**
- The mirror is a full local clone with two remotes: `origin` (GitHub) and `sot` (the SOT)
- Commits in the mirror are pushed to the SOT by a background hook within seconds
- `git push` from the mirror goes to GitHub as usual
- Everything committed stays backed up

## Repository Layout

After running `setup-repos.sh`:

```
~/cloudfiles/code/Users/<you>/main/
├── arrive-aml/              ← SOT
├── azureml-skills/          ← SOT
└── arrive-ds/               ← SOT

/mnt/mirror/
├── arrive-aml/              ← Fast mirror (local clone)
├── azureml-skills/          ← Fast mirror (local clone)
└── arrive-ds/               ← Fast mirror (local clone)
```

**Always work in** `/mnt/mirror/` **for fast git operations!**

## Automation

### Include in VM Setup

`scripts/bootstrap.sh` already runs `setup-repos.sh` (step 3) after the tools; there is nothing to
add. To run the pieces by hand:

```bash
cd ~/cloudfiles/code/Users/<you>/main/arrive-aml

# 1. Run VM setup
bash scripts/setup-vm.sh --all

# 2. Setup all repos
bash scripts/setup-repos.sh
```

### For New Team Members

Share this one-liner (clones arrive-aml to their share and runs the bootstrap with its short
wizard; see [GETTING-STARTED.md](GETTING-STARTED.md)):

```bash
curl -fsSL https://raw.githubusercontent.com/<team-org>/arrive-aml/main/scripts/get-started.sh | bash
```

## Troubleshooting

### Repository Already Exists

The script skips existing repositories. To re-clone:

```bash
# Remove and re-run
rm -rf ~/cloudfiles/code/Users/<you>/main/REPO_NAME
bash scripts/setup-repos.sh
```

### Mirror Issues

```bash
# Repair or recreate one mirror (a broken dir is moved to /mnt/mirror/REPO_NAME.broken-<time>)
bash scripts/setup-repos.sh --only REPO_NAME
# or all of them
aml-bootstrap --restore
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

# If not, (re)create and upload the key
bash scripts/lib/configure-github-ssh.sh
```

https clones work without SSH once `gh auth status` shows you logged in (`gh auth setup-git` is run
for you). "Repository not found" for a team repo usually means you are not in the team org yet:
ask a teammate to add you.

## Advanced Configuration

### Per-Repo Mirror Control

Set `AUTO_MIRROR=no` for repos that don't need fast git operations:

```conf
# Documentation repo (rarely changed, no mirror needed)
{org}/docs|docs|no
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
2. **Use `{org}/name` for team repos** - one org setting, ssh/https picked per VM
3. **Enable mirrors for active repos** - Development repos benefit most
4. **Disable mirrors for static repos** - Docs/archives don't need speed
5. **Document purpose** - Add comments in repos.conf explaining each repo
6. **Keep personal repos personal** - `~/.config/arrive-aml/repos.conf` or `--add`, not the team list

## See Also

- [MIRROR-PATTERN.md](MIRROR-PATTERN.md) - Deep dive on the SOT + mirror design
- [README.md](../README.md) - Main setup guide
- [docs/CLAUDE-CODE.md](CLAUDE-CODE.md) - Claude Code integration
