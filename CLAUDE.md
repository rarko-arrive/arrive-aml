# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is **arrive-aml**: an Azure ML compute instance setup automation system. One command (`scripts/bootstrap.sh`) transforms a fresh Ubuntu compute instance into a fully-configured data-science environment: optimized git, uv, Docker, cloudflared, GitHub CLI + SSH, Claude Code + team skills, and every team repo cloned to persistent storage with a fast `/mnt/mirror` worktree and a local-disk uv venv.

## Critical Architecture: Persistent Mirror Worktree Pattern

Azure ML uses network-mounted storage (`~/cloudfiles/code/Users/`) via SMB/CIFS, making git operations 10-100x slower than local disk. This repository implements a **two-location architecture**:

```
~/cloudfiles/code/Users/<you>/main/REPO/  ← Source of Truth (SOT)
                                          - Network mount (slow: 7-30s git status)
                                          - Persistent; the SAME share is mounted on every
                                            compute instance the user owns
                                          - Full .git database, checked out on main and updated by pushes
                                            (receive.denyCurrentBranch=updateInstead); never edit here

/mnt/mirror/REPO/                        ← Active mirror (one per compute instance)
                                          - Local disk: FULL CLONE, git status ~5 ms
                                          - remotes: origin = GitHub, sot = the SOT path
                                          - post-commit/merge/rewrite hooks push the branch to
                                            the SOT in the background (log: ~/.local/state/arrive-aml/sot-sync.log)
                                          - Where all development happens
                                          - /mnt is Azure's EPHEMERAL resource disk: wiped on stop/start
```

**Key insight**: the mirror is plain git - a local clone with two remotes. Every commit is pushed to the SOT's `.git` by a hook within seconds, so the persistent copy is always current, and `git push` goes to GitHub as usual. Measured on a compute instance: `git status` 5.4 s in the SOT, 3.0 s in a linked worktree (its index/HEAD/refs still live on the share, 60-95 ms per file op), 0.005 s in the clone. That is why linked worktrees were dropped; `mirror.sh` migrates legacy worktree mirrors automatically and removes their registrations from the SOT.

`/mnt` wipes are expected: the next interactive login runs `aml-bootstrap --restore`, which re-clones (GitHub first, SOT fallback), fetches the branches only the SOT has, and rebuilds venvs. Only uncommitted edits (and commits whose background push failed - `verify-setup.sh` reports those) can be lost.

## Directory Structure

```
scripts/
├── get-started.sh           # First run on an empty share: clone arrive-aml into <you>/main, exec bootstrap
├── bootstrap.sh             # THE entry point: you → tools → shell → repos/mirrors/venvs → skills → verify
│                            #   --configure = change your answers; --yes = never prompt
│                            #   --restore = after a VM stop/start (skips tools)
├── setup-vm.sh              # Tools orchestrator (--all); --no-verify when called from bootstrap
├── setup-repos.sh           # repos.conf (+ personal list) → SOT clone + mirror clone + uv venv; --add owner/repo
├── verify-setup.sh          # Required vs optional checks; prints the fix for each failure
├── bootstrap-azureml.sh     # Python venv for this repo only (thin wrapper)
├── setup-azureml-ssh.sh     # Laptop SSH config for Remote-SSH (run on the laptop)
└── lib/                     # Modular pieces (all idempotent)
    ├── common.sh            # Logging, team defaults, config_set, ask/can_prompt, apply_git_identity,
    │                        #   detect_sot_base, aml_user, repo_url, read_repo_entries, github_ssh_ok
    ├── configure-user.sh    # Wizard: detect/ask name, email, GitHub; saves env + share profile
    ├── mirror.sh            # ensure_mirror_worktree (local clone + sot remote + sync hooks; source only)
    ├── configure-git.sh     # Network-optimized git settings + safe.directory * + push.autoSetupRemote
    ├── configure-github-ssh.sh  # Key, ~/.ssh/config, known_hosts, gh upload, port-443 fallback
    ├── configure-shell.sh   # ~/.bashrc managed block, ~/.config/arrive-aml/env, `aml-bootstrap` shim
    ├── setup-python-venv.sh # uv sync into /mnt/uv-venvs/<repo> + .venv symlink
    ├── setup-mirror-worktree.sh # Mirror for one repo (wrapper over mirror.sh)
    ├── install-claude.sh    # Claude Code CLI via official installer (npm fallback)
    ├── install-claude-skills.sh # skills.conf repos → ~/.claude/skills symlinks
    ├── install-vscode.sh / install-cursor.sh  # Detect Remote-SSH servers; desktop install is opt-in
    ├── install-*.sh         # docker, cloudflared, gh, uv, system tools
    └── worktree-helper.sh   # Legacy /tmp copy helper (superseded by mirrors)

docs/
├── WORKFLOW.md          # THE page scientists repeat: setup, restore, per-PR loop, fixes, why
├── FRESH-VM.md          # Step-by-step first setup (new VM / new user / startup script)
├── MIRROR-PATTERN.md    # SOT + local clone design with measurements
├── REPOS-CONFIG.md      # repos.conf
├── CLAUDE-CODE.md       # Claude Code + skills.conf
├── PATHS.md             # Azure ML mount layout
├── TROUBLESHOOTING.md   # Cursor/VS Code/notebook/SSH oddities
├── SSH-SETUP-FROM-LAPTOP.md, REUSE-SSH-KEY.md
└── archive/             # historical narratives (not maintained)
```

## Repository Configuration System

`repos.conf` defines which repositories to clone and mirror:

```
REPO|NAME|AUTO_MIRROR
{org}/arrive-aml|arrive-aml|yes
```

`{org}` expands to `ARRIVE_GITHUB_ORG` (team default `ARRIVE_DEFAULT_GITHUB_ORG` in `common.sh`, the one place to change on an org move - see docs/ORG-MOVE.md). REPO may also be `owner/name` or a full git URL; `repo_url` picks ssh or https (`ARRIVE_GIT_PROTOCOL=auto|ssh|https`). Personal repos go in `~/.config/arrive-aml/repos.conf` (same format; `setup-repos.sh --add owner/name` appends there). `read_repo_entries` merges both lists (team first, duplicates by name skipped); every consumer (setup-repos, verify-setup, login-restore) uses the merged list.

`scripts/setup-repos.sh` processes the merged list and, per repo:
1. Clones it to the SOT base (`~/cloudfiles/code/Users/<aml-user>/main`; `detect_sot_base` tries `ARRIVE_SOT_BASE`, then this checkout's own path, then the mirror's `sot` remote, then a folder matching the instance name)
2. Creates or repairs the mirror clone at `/mnt/mirror/REPO_NAME/` (if AUTO_MIRROR=yes)
3. Runs `uv sync` into `/mnt/uv-venvs/REPO_NAME` and symlinks `.venv` in the mirror (if `pyproject.toml` exists)

Default repos: arrive-aml (this repo), azureml-skills (Claude Code skills), arrive-ds (data science utilities)

`skills.conf` (`REPO|NAME`, plus personal `~/.config/arrive-aml/skills.conf`) lists Claude Code skill repos; `scripts/lib/install-claude-skills.sh` clones them to `~/.claude/plugins/marketplaces/<NAME>` and symlinks `skills/*` into `~/.claude/skills/`. azureml-skills is a plugin repo with a `skills/` folder, not a marketplace, so `/plugin install` does not apply.

## Common Development Tasks

### Initial Setup (Fresh VM)
```bash
# New user, empty share: clone arrive-aml into ~/cloudfiles/code/Users/<you>/main and bootstrap
curl -fsSL https://raw.githubusercontent.com/<team-org>/arrive-aml/main/scripts/get-started.sh | bash
# arrive-aml already on your share (another VM): complete setup in one command
bash ~/cloudfiles/code/Users/<you>/main/arrive-aml/scripts/bootstrap.sh
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
git status    # ~5 ms
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
- Applies the user's identity from `~/.config/arrive-aml/env` (`apply_git_identity`); never a hard-coded default

**Why this matters**: Without these settings, `git status` takes 10-30 seconds on Azure ML. With them: 7-8 seconds. With mirror worktree: <1 second.

## Script Design Philosophy

All scripts in `scripts/lib/` are:
- **Idempotent**: Safe to run multiple times
- **Modular**: Can be run independently
- **Verbose**: Use common.sh logging (log_info, log_success, log_error)
- **Non-interactive by default**: Use flags like `--all` to skip prompts. The only questions come from `configure-user.sh` (and gh's device login); they use `ask`/`can_prompt` from common.sh, read from `/dev/tty`, and never run when `ARRIVE_NONINTERACTIVE=1` (`--yes`, `--restore`, root/startup script) or on login auto-restore
- **Dry-run capable**: `--dry-run` shows what would happen

## Key Non-Obvious Patterns

1. **/mnt is ephemeral** - `/mnt` is Azure's resource disk (`/mnt/EPHEMERAL_DISK_DATALOSS_WARNING.txt`); mirrors, venvs and the uv cache vanish on every stop/start. Commits are safe once the sync hook pushed them to the SOT (seconds). The bashrc block sources `scripts/lib/login-restore.sh`, which runs `aml-bootstrap --restore` when the mirrors are missing (one restore at a time; a failure backs off for 10 minutes). Bootstrap also fast-forwards a clean arrive-aml checkout from origin before doing the work, then re-execs so it runs the scripts just pulled. The SOT is shared by all of the user's compute instances (it is a plain repo on `main`, acting as a local remote that also updates its working tree on push).

2. **Parallel branches** - the mirror is a normal clone, so `git worktree add /mnt/mirror/arrive-aml-feature1 feature/one` from the mirror works and stays fully local (its admin files live in the mirror's `.git`, not on the share).

3. **Python venv symlink** - `.venv` symlinks to `/mnt/uv-venvs/PROJECT_NAME` so it's on fast local disk but repo-relative for IDE integration. Paths are configurable in `~/.config/arrive-aml/env`.

4. **SSH key naming** - Uses `id_ed25519_github` (not default `id_ed25519`) to avoid conflicts with other SSH keys. Configured in `~/.ssh/config`.

5. **Conda is disabled, not removed** - `scripts/lib/disable-conda.sh` comments out conda init and any leftover `conda activate` line in bashrc (Azure leaves `conda activate azureml_py38` outside the init block; commenting out only the init block takes conda off PATH and the next login errors). The Anaconda install stays. `configure-shell.sh` also removes Azure's duplicate `readonly TMOUT=900` so login does not error and idle SSH sessions are not killed after 15 minutes.

6. **Compute instances are headless** - Cursor and VS Code run on the laptop and connect via Remote-SSH; their servers self-install under `~/.cursor-server` / `~/.vscode-server`. `install-cursor.sh` / `install-vscode.sh` only detect those servers (desktop installs are opt-in flags).

7. **`ssh -T git@github.com` exits 1 on success** - always test via `github_ssh_ok` in common.sh; a `ssh | grep -q` pipeline under `set -o pipefail` reports a false failure.

8. **Never set `core.ignoreStat true`** - it flags every tracked file assume-unchanged, so `git status`, `git add -A` and `git commit -a` silently ignore edits. An earlier version of configure-git.sh did this; it now forces `false` and `mirror.sh` clears the flags (`git update-index --no-assume-unchanged`).

9. **The cloudfiles mount is root-owned CIFS** - `configure-git.sh` sets `safe.directory *`; without it git refuses every repo on the mount. `chown` on the mount is a no-op.

10. **Nothing user-specific in code** - identity, org and personal repos live in `~/.config/arrive-aml/env` (written with `config_set`, which merges; never overwrite the file) and `~/.config/arrive-aml/repos.conf`. The wizard also writes `<SOT base>/.arrive-aml/profile` so a user's next VM asks nothing; that share is writable by the whole workspace, so it is parsed as data (`profile_get`), never sourced. The org is only pinned in the env file when it differs from the team default, so changing `ARRIVE_DEFAULT_GITHUB_ORG` reaches everyone. `tests/lint.sh` fails on any personal name/folder/VM in code or docs.

11. **`~/cloudfiles/code/Users/` lists every workspace user** - never pick "the only folder" there. `guess_aml_user` matches the instance name (`ctracy2` → `ctracy`) and the wizard/get-started confirm it.

12. **Anything inside `while read ... done < <(list)` must not read stdin** - `ssh` (e.g. `github_ssh_ok`) and some tools swallow the rest of the list. Redirect `</dev/null` in the loop body.

## Testing Changes

When modifying setup scripts:
1. `bash tests/lint.sh` (bash -n, shellcheck errors, no user-specific values), then `bash scripts/bootstrap.sh --dry-run`
2. `bash tests/sandbox-new-user.sh`: the whole new-user flow (get-started → wizard over a pty → bootstrap → mirrors → commit sync → /mnt wipe + restore → second VM → --add) for a simulated user in a throwaway HOME/share/fake GitHub; never touches your real setup
3. Test individual pieces: `bash scripts/lib/install-docker.sh`, `bash scripts/setup-repos.sh --only arrive-ds`
4. Verify with: `bash scripts/verify-setup.sh` (exit 1 only on required failures)
5. Test the restart path: `bash scripts/bootstrap.sh --restore`
6. Docs: README.md is the one-screen happy path; anything longer goes under `docs/` and is linked from the README table

## Integration Points

- **azureml-skills repo**: Claude Code skills that consume this setup (e.g., `/work-in-repo` skill)
- **arrive-ds repo**: Data science utilities, depends on this setup working
- **Cursor/VS Code Remote-SSH**: `scripts/setup-azureml-ssh.sh` configures laptop side

## When Helping Users

- If user reports slow git: Check they're working in `/mnt/mirror/`, not SOT
- If Python packages install slowly: Ensure venv is at `/mnt/uv-venvs/`, not in repo or on cloudfiles
- If mirror worktree missing after VM restart: `aml-bootstrap --restore`
- If git commits have the wrong author or the wizard guessed the wrong folder: `aml-bootstrap --configure`
- If setup fails: `bash scripts/verify-setup.sh` names the failing check and the fix; run that single script from `scripts/lib/`
- Always work in mirrors, always commit and push regularly (mirror is local disk, wiped on stop/start)

## Documentation Hierarchy

- **README.md**: one screen - the command, the restore, the daily loop, a table linking to docs/
- **docs/GETTING-STARTED.md**: the friendly first-run walkthrough (what the wizard asks, what done looks like)
- **docs/TESTING-NEW-USER.md**: how a change is tested as a brand-new user (sandbox + real-VM checklist)
- **docs/ORG-MOVE.md**: checklist for moving the team repos to another GitHub org
- **docs/WORKFLOW.md**: the canonical page every scientist repeats per PR (setup, restore, loop, self-checks, all fixes, why it is built this way)
- **docs/FRESH-VM.md**: step-by-step for a new VM / new user, incl. the Azure ML startup-script option
- **docs/MIRROR-PATTERN.md**: SOT + local clone architecture with the measurements behind it
- **docs/REPOS-CONFIG.md**, **docs/CLAUDE-CODE.md**: repos.conf and skills.conf
- **docs/PATHS.md**, **docs/TROUBLESHOOTING.md**, **docs/SSH-SETUP-FROM-LAPTOP.md**, **docs/REUSE-SSH-KEY.md**
- **docs/archive/**: superseded narratives kept for history; do not update, do not link

Read docs/MIRROR-PATTERN.md for complete architectural understanding of the mirror pattern.
