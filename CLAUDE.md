# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is **arrive-aml**: an Azure ML compute instance setup automation system. One command (`scripts/bootstrap.sh`) transforms a fresh Ubuntu compute instance into a fully-configured data-science environment: optimized git, uv, Docker, GitHub CLI + SSH, Claude Code + team skills, and every team repo cloned to persistent storage with a fast `/mnt/mirror` worktree and a local-disk uv venv.

## Critical Architecture: Persistent Mirror Worktree Pattern

Azure ML uses network-mounted storage (`~/cloudfiles/code/Users/`) via SMB/CIFS, making git operations 10-100x slower than local disk. This repository implements a **two-location architecture**:

```
~/cloudfiles/code/Users/rarko/main/REPO/  ← Source of Truth (SOT)
                                          - Network mount (slow: 7-30s git status)
                                          - Persistent; the SAME share is mounted on every
                                            compute instance the user owns
                                          - Full .git database; HEAD is detached (never edit here)

/mnt/mirror/REPO/                        ← Active Worktree (one per compute instance)
                                          - Local disk (fast: <1s git status)
                                          - Git worktree linked to SOT's .git, on the default branch
                                          - Where all development happens
                                          - /mnt is Azure's EPHEMERAL resource disk: wiped on stop/start
```

**Key insight**: Both locations share the same `.git` database via `git worktree add`. Commits in the mirror are stored in SOT's `.git/` immediately. This is NOT a sync script - it's native git functionality.

**Multi-VM rules** (implemented in `scripts/lib/mirror.sh`): worktree registrations are locked with `--reason host=<instance>` so one VM's `git worktree prune` can never destroy another VM's mirror; a stale registration from this host is removed before re-creating; if another VM already holds the default branch the new mirror starts detached. `/mnt` wipes are expected: `aml-bootstrap --restore` recreates mirrors and venvs in about a minute.

## Directory Structure

```
scripts/
├── bootstrap.sh             # THE entry point: tools → shell → repos/mirrors/venvs → skills → verify
│                            #   --restore = after a VM stop/start (skips tools)
├── setup-vm.sh              # Tools orchestrator (--all); --no-verify when called from bootstrap
├── setup-repos.sh           # repos.conf → SOT clone + mirror worktree + uv venv per repo
├── verify-setup.sh          # Required vs optional checks; prints the fix for each failure
├── bootstrap-azureml.sh     # Python venv for this repo only (thin wrapper)
├── setup-azureml-ssh.sh     # Laptop SSH config for Remote-SSH (run on the laptop)
└── lib/                     # Modular pieces (all idempotent)
    ├── common.sh            # Logging, detect_sot_base, this_host, github_ssh_ok, ensure_local_dir, trim
    ├── mirror.sh            # ensure_mirror_worktree + stale-registration cleanup (source only)
    ├── configure-git.sh     # Network-optimized git settings + safe.directory * + push.autoSetupRemote
    ├── configure-github-ssh.sh  # Key, ~/.ssh/config, known_hosts, gh upload, port-443 fallback
    ├── configure-shell.sh   # ~/.bashrc managed block, ~/.config/arrive-aml/env, `aml-bootstrap` shim
    ├── setup-python-venv.sh # uv sync into /mnt/uv-venvs/<repo> + .venv symlink
    ├── setup-mirror-worktree.sh # Mirror for one repo (wrapper over mirror.sh)
    ├── install-claude.sh    # Claude Code CLI via official installer (npm fallback)
    ├── install-claude-skills.sh # skills.conf repos → ~/.claude/skills symlinks
    ├── install-vscode.sh / install-cursor.sh  # Detect Remote-SSH servers; desktop install is opt-in
    ├── install-*.sh         # docker, gh, uv, system tools
    └── worktree-helper.sh   # Legacy /tmp copy helper (superseded by mirrors)

docs/
├── AZUREML-WORKTREE-PATTERN.md  # Deep dive on worktree architecture
├── REPOS-CONFIG.md              # How to configure repos.conf
└── *.md                         # Setup guides
```

## Repository Configuration System

`repos.conf` defines which repositories to clone and mirror:

```
REPO_URL|REPO_NAME|AUTO_MIRROR
git@github.com:rarko-arrive/arrive-aml.git|arrive-aml|yes
```

`scripts/setup-repos.sh` parses this file and, per repo:
1. Clones it to the SOT base (derived from where this arrive-aml checkout's `.git` lives: `~/cloudfiles/code/Users/<aml-user>/main`; override with `ARRIVE_SOT_BASE`)
2. Creates or repairs the mirror worktree at `/mnt/mirror/REPO_NAME/` (if AUTO_MIRROR=yes)
3. Runs `uv sync` into `/mnt/uv-venvs/REPO_NAME` and symlinks `.venv` in the mirror (if `pyproject.toml` exists)

Default repos: arrive-aml (this repo), azureml-skills (Claude Code skills), arrive-ds (data science utilities)

`skills.conf` (`REPO_URL|NAME`) lists Claude Code skill repos; `scripts/lib/install-claude-skills.sh` clones them to `~/.claude/plugins/marketplaces/<NAME>` and symlinks `skills/*` into `~/.claude/skills/`. azureml-skills is a plugin repo with a `skills/` folder, not a marketplace, so `/plugin install` does not apply.

## Common Development Tasks

### Initial Setup (Fresh VM)
```bash
# Complete setup in one command (tools + shell + repos/mirrors/venvs + skills + verify)
bash ~/cloudfiles/code/Users/rarko/main/arrive-aml/scripts/bootstrap.sh
source ~/.bashrc

# After every VM stop/start (/mnt wiped): recreate mirrors + venvs
aml-bootstrap --restore
```

### Python Environment Setup
```bash
# Done by bootstrap for every mirrored repo with a pyproject.toml. For one repo:
bash scripts/lib/setup-python-venv.sh /mnt/mirror/arrive-aml
# venv: /mnt/uv-venvs/arrive-aml, .venv symlink in the repo, uv cache /mnt/uv-cache

# Activate
source .venv/bin/activate   # or: uv run ...
```

The project uses **uv** for Python package management (pyproject.toml). Virtual environments MUST be on local disk (not cloudfiles) for acceptable performance; they live on `/mnt` (600 GB, fast) rather than the 120 GB OS disk, which was 98% full. Legacy venvs in `~/uv-venvs/` can be deleted.

### Working with Mirrors
```bash
# ALWAYS work in the mirror for fast git
cd /mnt/mirror/arrive-aml

# Regular git workflow works normally
git status    # <1 second
git pull
git checkout -b feature/new-setup
# make changes
git add scripts/
git commit -m "Add feature"
git push origin feature/new-setup
```

### Verifying Setup
```bash
# Run verification script
bash scripts/verify-setup.sh

# Check git performance
time git status  # Should be <1s in mirror, 7-30s in SOT
```

## Git Performance Optimization

`scripts/lib/configure-git.sh` applies 15+ settings optimized for network storage:
- Disables fsmonitor (expensive on network mounts)
- Disables automatic garbage collection
- Enables manyFiles feature
- Sets status.showUntrackedFiles=no (use -u to show)
- Configures user (Rick Arko <rarko@arrivelogistics.com>)

**Why this matters**: Without these settings, `git status` takes 10-30 seconds on Azure ML. With them: 7-8 seconds. With mirror worktree: <1 second.

## Script Design Philosophy

All scripts in `scripts/lib/` are:
- **Idempotent**: Safe to run multiple times
- **Modular**: Can be run independently
- **Verbose**: Use common.sh logging (log_info, log_success, log_error)
- **Non-interactive by default**: Use flags like `--all` to skip prompts
- **Dry-run capable**: `--dry-run` shows what would happen

## Key Non-Obvious Patterns

1. **/mnt is ephemeral** - `/mnt` is Azure's resource disk (`/mnt/EPHEMERAL_DISK_DATALOSS_WARNING.txt`); mirrors, venvs and the uv cache vanish on every stop/start. Commits are safe (in the SOT's `.git`). `aml-bootstrap --restore` recreates everything; the bashrc block prints a reminder when `/mnt/mirror` is missing. The SOT is shared by all of the user's compute instances, so never run `git worktree prune` in a SOT by hand.

2. **Multiple worktrees pattern** - Can create multiple mirrors from same SOT for parallel work on different branches:
   ```bash
   git worktree add /mnt/mirror/arrive-aml-feature1 feature/one
   git worktree add /mnt/mirror/arrive-aml-feature2 feature/two
   ```

3. **Python venv symlink** - `.venv` symlinks to `/mnt/uv-venvs/PROJECT_NAME` so it's on fast local disk but repo-relative for IDE integration. Paths are configurable in `~/.config/arrive-aml/env`.

4. **SSH key naming** - Uses `id_ed25519_github` (not default `id_ed25519`) to avoid conflicts with other SSH keys. Configured in `~/.ssh/config`.

5. **Conda is disabled, not removed** - `scripts/lib/disable-conda.sh` comments out conda init in bashrc but keeps installation intact (Azure ML managed).

6. **Compute instances are headless** - Cursor and VS Code run on the laptop and connect via Remote-SSH; their servers self-install under `~/.cursor-server` / `~/.vscode-server`. `install-cursor.sh` / `install-vscode.sh` only detect those servers (desktop installs are opt-in flags).

7. **`ssh -T git@github.com` exits 1 on success** - always test via `github_ssh_ok` in common.sh; a `ssh | grep -q` pipeline under `set -o pipefail` reports a false failure.

8. **Never set `core.ignoreStat true`** - it flags every tracked file assume-unchanged, so `git status`, `git add -A` and `git commit -a` silently ignore edits. An earlier version of configure-git.sh did this; it now forces `false` and `mirror.sh` clears the flags (`git update-index --no-assume-unchanged`).

9. **The cloudfiles mount is root-owned CIFS** - `configure-git.sh` sets `safe.directory *`; without it git refuses every repo on the mount. `chown` on the mount is a no-op.

## Testing Changes

When modifying setup scripts:
1. `bash -n` every script; test with `--dry-run` first: `bash scripts/bootstrap.sh --dry-run`
2. Test individual pieces: `bash scripts/lib/install-docker.sh`, `bash scripts/setup-repos.sh --only arrive-ds`
3. Verify with: `bash scripts/verify-setup.sh` (exit 1 only on required failures)
4. Test the restart path: `bash scripts/bootstrap.sh --restore`
5. Test happy path: `bash test-happy-path.sh`

## Integration Points

- **azureml-skills repo**: Claude Code skills that consume this setup (e.g., `/work-in-repo` skill)
- **arrive-ds repo**: Data science utilities, depends on this setup working
- **Cursor/VS Code Remote-SSH**: `scripts/setup-azureml-ssh.sh` configures laptop side

## When Helping Users

- If user reports slow git: Check they're working in `/mnt/mirror/`, not SOT
- If Python packages install slowly: Ensure venv is at `/mnt/uv-venvs/`, not in repo or on cloudfiles
- If mirror worktree missing after VM restart: `aml-bootstrap --restore`
- If setup fails: `bash scripts/verify-setup.sh` names the failing check and the fix; run that single script from `scripts/lib/`
- Always work in mirrors, always commit and push regularly (mirror is local disk, wiped on stop/start)

## Documentation Hierarchy

- **README.md**: User-facing quick start
- **QUICKSTART.md**: One-page copy-paste guide (bootstrap + restore + daily workflow)
- **HAPPY-PATH.md**: Step-by-step setup for fresh VM, including the startup-script option
- **CLAUDE-SETUP.md**: Claude Code extension + skills integration
- **AZURE-ML-PATHS.md**: Path structure explanation
- **docs/AZUREML-WORKTREE-PATTERN.md**: Deep technical dive on worktree pattern
- **Setup.md**: Detailed troubleshooting

Read AZUREML-WORKTREE-PATTERN.md for complete architectural understanding of the mirror pattern.
