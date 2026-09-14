# Arrive AML - Azure ML Development Environment Setup

Professional, comprehensive setup for Azure ML compute instances. One command turns a fresh VM into a fully-configured data-science environment: tuned git, uv, GitHub CLI + SSH, Docker, Claude Code + team skills, and every team repo cloned to persistent storage with a fast `/mnt/mirror` worktree and a local-disk venv.

**⭐ [The Workflow (read this first) →](summary.md)** | **📖 [Quick Start →](QUICKSTART.md)** | **🚶 [Happy Path →](HAPPY-PATH.md)** | **⚡ [Mirror Worktree Pattern →](docs/AZUREML-WORKTREE-PATTERN.md)** | **🔑 [Reuse SSH Keys →](docs/REUSE-SSH-KEY.md)**

## Quick Start

```bash
# On the compute instance. arrive-aml lives on the workspace file share, shared by all your VMs:
bash ~/cloudfiles/code/Users/<you>/main/arrive-aml/scripts/bootstrap.sh
source ~/.bashrc
```

**That's it.** Work in `/mnt/mirror/<repo>` from now on.

```bash
aml-bootstrap --restore      # after every VM stop/start: /mnt is ephemeral, this recreates mirrors + venvs
bash scripts/verify-setup.sh # every failed check prints the exact fix
```

`bootstrap.sh` runs, in order: `setup-vm.sh --all` (tools), `lib/configure-shell.sh`, `setup-repos.sh` (SOT clones, mirrors, venvs), `lib/install-claude-skills.sh`, `verify-setup.sh`. Every script is idempotent and can be run on its own.

## What Gets Installed

| Tool | Description | Flag |
|------|-------------|------|
| **Git Optimization** | 2-4x faster git on Azure network storage + worktree helper | `--git-optimize` |
| **System Tools** | git, curl, wget, htop, jq, tree, vim, build-essential | `--system-tools` |
| **uv** | Fast Python package manager | `--uv` |
| **GitHub CLI** | gh command-line tool | `--gh` |
| **GitHub SSH** | Automated SSH key setup for GitHub | `--github-ssh` |
| **Docker** | Docker Engine + docker-compose | `--docker` |
| **Claude Code** | Anthropic's Claude Code CLI (`claude`) + team skills from `skills.conf` | `--claude` |
| **VS Code** | Checks the Remote-SSH server; the editor runs on your laptop | `--vscode` |
| **Cursor** | Checks the Remote-SSH server; the editor runs on your laptop | `--cursor` |
| **Conda Disable** | Disables conda auto-activation (preserves install) | `--disable-conda` |

Beyond `setup-vm.sh`, `bootstrap.sh` also sets up repositories (`repos.conf`): SOT clone on cloudfiles, local mirror clone on `/mnt/mirror` (auto-synced to the SOT), uv venv on `/mnt/uv-venvs` with a `.venv` symlink.

## Git Performance on Azure ML

**Problem**: Azure ML uses network-mounted storage (`~/cloudfiles/code/Users/`) which makes git operations 10-100x slower than local disk due to SMB/CIFS protocol overhead.

**Solution 1 - Optimizations (Good)**: Applied automatically by setup:
- Disables expensive file monitoring (`core.fsmonitor false`)
- Optimizes index operations (`index.threads 4`, `feature.manyFiles true`)
- Disables automatic garbage collection (`gc.auto 0`)
- 15+ other network-optimized settings
- **Result**: `git status` 10-30s → **7-8s** (2-4x faster)

**Solution 2 - Local Mirror (Best)**: work in a full local clone; hooks push every commit to the persistent SOT:
```bash
cd /mnt/mirror/arrive-aml   # local clone; remotes: origin = GitHub, sot = ~/cloudfiles/.../arrive-aml
git status                  # ~5 ms
```
- **Result**: `git status` **5 ms** (measured: 5.4 s in the SOT, 3 s in a linked worktree); commits reach the SOT's `.git` on cloudfiles within seconds via the post-commit hook.
- `/mnt` is Azure's ephemeral resource disk (wiped on stop/start). `aml-bootstrap --restore` recreates every mirror and venv in about a minute; only uncommitted edits can be lost.

**Recommendation**: Always work in `/mnt/mirror/<repo>`. Never edit in the SOT. See [docs/AZUREML-WORKTREE-PATTERN.md](docs/AZUREML-WORKTREE-PATTERN.md).

## Prerequisites

- Fresh Ubuntu-based Azure ML compute instance
- Internet access
- Sudo privileges (script will prompt when needed)

## Usage Examples

### Complete Setup (Recommended)

Install everything with all default configurations:

```bash
bash scripts/setup-vm.sh --all
```

### Minimal Setup

Just git optimization and essential tools:

```bash
bash scripts/setup-vm.sh --git-optimize --system-tools --uv
```

### Selective Installation

Pick specific tools:

```bash
bash scripts/setup-vm.sh --git-optimize --docker --gh --github-ssh
```

### Interactive Mode

Answer prompts for each tool:

```bash
bash scripts/setup-vm.sh
```

### Dry Run

See what would be installed without making changes:

```bash
bash scripts/setup-vm.sh --dry-run --all
```

## Post-Installation

### Verify Setup

```bash
# Run verification script
bash scripts/verify-setup.sh

# Test git performance (should be < 1 second)
cd /mnt/mirror/arrive-aml
time git status
```

### If You Installed Docker

Log out and back in, or run:

```bash
newgrp docker
```

Then test:

```bash
docker run hello-world
```

### If You Installed GitHub SSH

Your SSH key is at `~/.ssh/id_ed25519_github.pub`. If it wasn't automatically added to GitHub:

```bash
# Show your public key
cat ~/.ssh/id_ed25519_github.pub

# Add it at: https://github.com/settings/ssh/new
```

Test connection:

```bash
ssh -T git@github.com
```

### If You Installed Claude Code

Sign in once per VM (works over SSH: open the URL on your laptop, paste the code back):

```bash
claude auth login
```

## Claude Code Skills Integration

Enhance Claude Code with azureml-skills - a collection of skills optimized for the Azure ML mirror worktree workflow.

### Step 1 + 2: Install the skills (done by bootstrap.sh)

`skills.conf` lists skill repositories. The installer clones each one to `~/.claude/plugins/marketplaces/<name>` and symlinks every `skills/<skill>` into `~/.claude/skills/`:

```bash
bash scripts/lib/install-claude-skills.sh   # idempotent; also pulls updates
```

### Step 3: Use the Skill

In any Claude Code conversation, invoke the skill:

```
/work-in-repo

"I need to add error handling to the setup-vm.sh script"
```

**What it does:**
- Automatically navigates to the fast `/mnt/mirror/` location
- Handles git operations efficiently
- Manages the SOT ↔ mirror workflow
- Commits and syncs changes automatically

### Verify Installation

```bash
ls -la ~/.claude/skills/     # work-in-repo -> .../azureml-skills/skills/work-in-repo
```

### Example Workflow

```
# In Claude Code chat:
/work-in-repo

"Update the README.md to add installation instructions 
for the Docker setup, then commit the changes"
```

The skill will:
1. Switch to `/mnt/mirror/arrive-aml` (fast disk)
2. Make the requested changes
3. Test with `git status` (<1 second!)
4. Commit and push if requested

## Python Development Setup

`bootstrap.sh` creates a uv venv for every mirrored repo that has a `pyproject.toml`. To (re)do one repo:

```bash
bash scripts/lib/setup-python-venv.sh /mnt/mirror/<repo>
# venv: /mnt/uv-venvs/<repo>  (fast, big local disk)   .venv -> symlink in the repo (gitignored)
# uv cache: /mnt/uv-cache     (UV_CACHE_DIR is exported by the bashrc block when it exists)
```

Override locations in `~/.config/arrive-aml/env` (`UV_VENV_ROOT`, `ARRIVE_UV_CACHE_DIR`, `MIRROR_BASE`).

## SSH Access from Your Laptop

Editors are not installed on the VM. Use Cursor or VS Code on your laptop with Remote-SSH; their server component installs itself under `~/.cursor-server` / `~/.vscode-server` on first connect. To configure your laptop:

```bash
# On your laptop (not the VM), run:
bash scripts/setup-azureml-ssh.sh
```

This configures your laptop's `~/.ssh/config` with the VM's connection details.

## Project Structure

```
arrive-aml/
├── README.md                       # This file
├── QUICKSTART.md / HAPPY-PATH.md   # One-page and step-by-step guides
├── Setup.md                        # Detailed troubleshooting guide
├── repos.conf                      # Repos to clone + mirror (REPO_URL|NAME|AUTO_MIRROR)
├── skills.conf                     # Claude Code skills repos (REPO_URL|NAME)
├── scripts/
│   ├── bootstrap.sh                # THE one command: tools + shell + repos + skills + verify (--restore after restart)
│   ├── setup-vm.sh                 # Tools orchestrator (--all)
│   ├── setup-repos.sh              # SOT clones, /mnt/mirror worktrees, uv venvs
│   ├── verify-setup.sh             # Verification (required vs optional, prints fixes)
│   ├── bootstrap-azureml.sh        # Python venv for this repo only (wrapper)
│   ├── setup-azureml-ssh.sh        # Laptop-side SSH configuration
│   └── lib/                        # Modular, idempotent pieces
│       ├── common.sh               # Logging, path detection, GitHub helpers
│       ├── mirror.sh               # Mirror clone logic (sot remote, sync hooks, legacy migration)
│       ├── configure-git.sh        # Git performance + safe.directory
│       ├── configure-github-ssh.sh # GitHub SSH key/config/upload/test
│       ├── configure-shell.sh      # bashrc block, ~/.config/arrive-aml/env, aml-bootstrap
│       ├── setup-python-venv.sh    # uv venv on /mnt/uv-venvs + .venv symlink
│       ├── setup-mirror-worktree.sh# Mirror for one repo
│       ├── install-claude.sh       # Claude Code CLI
│       ├── install-claude-skills.sh# Team skills -> ~/.claude/skills
│       ├── install-*.sh            # uv, gh, docker, system tools, editor server checks
│       └── disable-conda.sh        # Conda management
├── pyproject.toml                  # Python project configuration
├── .env.example                    # Environment template
└── .vscode/                        # VS Code/Cursor settings
```

## Troubleshooting

### Git Still Slow?

You are probably in the SOT on cloudfiles. Work in the mirror:

```bash
cd /mnt/mirror/<repo>            # <1s git
aml-bootstrap --restore          # if /mnt/mirror is missing (VM restarted)
bash scripts/lib/configure-git.sh  # re-apply the network-mount git settings
```

### Mirror missing or broken after a restart

`/mnt` is the ephemeral resource disk. `aml-bootstrap --restore` recreates every mirror and venv; a broken mirror directory is moved to `<mirror>.broken-<timestamp>` so nothing is lost. If the background push to the SOT failed for a commit, `verify-setup.sh` lists it; fix with `git push sot HEAD` (log: `~/.local/state/arrive-aml/sot-sync.log`).

### Docker Permission Denied?

```bash
# Add yourself to docker group
sudo usermod -aG docker $USER

# Log out and back in, or:
newgrp docker
```

### Command Not Found After Install?

```bash
# Reload shell configuration
source ~/.bashrc

# Or log out and back in
```

### Conda Still Auto-Activating?

```bash
# Re-run conda disable
bash scripts/lib/disable-conda.sh

# Then open a new shell
```

## Manual Installation

If the automated setup fails, you can run individual installers:

```bash
# Git optimization (most important!)
bash scripts/lib/configure-git.sh

# System tools
bash scripts/lib/install-system-tools.sh

# Individual tools
bash scripts/lib/install-uv.sh
bash scripts/lib/install-gh.sh
bash scripts/lib/install-docker.sh
bash scripts/lib/install-claude.sh
bash scripts/lib/install-claude-skills.sh
bash scripts/lib/install-vscode.sh    # --desktop to force the apt package (needs a display)
bash scripts/lib/install-cursor.sh    # --appimage to force the AppImage (needs a display)

# Configurations
bash scripts/lib/configure-github-ssh.sh
bash scripts/lib/configure-shell.sh
bash scripts/lib/disable-conda.sh

# Repositories
bash scripts/setup-repos.sh --only arrive-ds          # one repo: clone + mirror + venv
bash scripts/lib/setup-mirror-worktree.sh arrive-ds   # just the mirror
bash scripts/lib/setup-python-venv.sh /mnt/mirror/arrive-ds
```

## Configuration Options

All flags for `setup-vm.sh`:

```
--all              Install everything (recommended)
--system-tools     Essential system utilities
--git-optimize     Git performance optimization (CRITICAL for Azure ML)
--uv               uv package manager
--gh               GitHub CLI
--github-ssh       GitHub SSH authentication
--disable-conda    Disable conda auto-activation
--docker           Docker Engine + docker-compose
--claude           Claude Code CLI
--vscode           VS Code Remote-SSH server check
--cursor           Cursor Remote-SSH server check
--dry-run          Show what would be installed
--no-verify        Skip verification (bootstrap.sh runs it itself)
-h, --help         Show help message
```

## Why This Matters

Azure ML compute instances come with basic tools but lack:

1. **Git performance optimization** - Network storage makes git painfully slow
2. **Modern development tools** - VS Code, Cursor, Claude CLI, etc.
3. **Proper GitHub integration** - SSH keys, gh CLI
4. **Docker support** - For containerized workflows
5. **Python environment best practices** - uv for fast package management

This setup solves all of these, providing a **professional, performant development environment** in < 10 minutes.

## For More Details

- See [Setup.md](Setup.md) for detailed troubleshooting and Azure ML specifics
- Run `bash scripts/setup-vm.sh --help` for all options
- Each script in `scripts/lib/` can be run independently

## Maintenance

Re-run the bootstrap anytime to update tools, pull new repos from `repos.conf`, or refresh skills:

```bash
aml-bootstrap              # full
aml-bootstrap --restore    # after a VM stop/start
```

The scripts are **idempotent** - safe to run multiple times. Logs: `~/.local/state/arrive-aml/`.

---

**Created for**: rarko@arrivelogistics.com  
**Optimized for**: Azure ML compute instances  
**Result**: Simple, reliable, and a pleasure to use
