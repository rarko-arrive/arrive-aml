# Arrive AML - Quick Start

One command turns a fresh Azure ML compute instance into the full Arrive data-science
environment: tuned git, uv, GitHub CLI + SSH, Docker, Claude Code + team skills, every
team repo cloned to persistent storage with a fast `/mnt/mirror` worktree and a local-disk
uv venv.

## Fresh VM (once)

`~/cloudfiles/code/Users/<you>/` is an Azure Files share that every compute instance in the
workspace mounts, so `arrive-aml` is usually already there. If it is not:

```bash
mkdir -p ~/cloudfiles/code/Users/$AML_USER/main   # AML_USER = your folder under Users/
cd ~/cloudfiles/code/Users/$AML_USER/main
git clone git@github.com:rarko-arrive/arrive-aml.git   # needs a GitHub SSH key: see below
```

Then, on the VM:

```bash
bash ~/cloudfiles/code/Users/$AML_USER/main/arrive-aml/scripts/bootstrap.sh
source ~/.bashrc
```

**Done.** Work in `/mnt/mirror/<repo>` from now on.

> First time on GitHub from this VM? `bash scripts/setup-vm.sh --gh --github-ssh` creates
> `~/.ssh/id_ed25519_github`, uploads it with `gh` (run `gh auth login` first) and verifies it.

## After every VM stop/start

`/mnt` is the ephemeral resource disk: mirrors and venvs are gone after a restart. Your
commits are safe (they live in the SOT's `.git` on cloudfiles). Recreate in about a minute:

```bash
aml-bootstrap --restore
```

Your shell prints a reminder when `/mnt/mirror` is missing.

## Daily workflow

```bash
cd /mnt/mirror/arrive-aml        # fast local disk, <1s git
git checkout -b feature/thing    # branch, work, commit, push as usual
uv run python script.py          # .venv -> /mnt/uv-venvs/arrive-aml
claude                            # then /work-in-repo
```

| Location | `git status` | Use for |
|----------|--------------|---------|
| `~/cloudfiles/code/Users/<you>/main/REPO` (SOT) | 7-30 s | Holds the `.git` database. Do not edit here. |
| `/mnt/mirror/REPO` | <1 s | All development |

## Connect from your laptop (Cursor / VS Code)

Editors are not installed on the VM: use Cursor or VS Code on your laptop with Remote-SSH.
Their server component installs itself under `~/.cursor-server` / `~/.vscode-server` on first
connect. On your **laptop**:

```bash
bash scripts/setup-azureml-ssh.sh      # adds the VM to ~/.ssh/config (asks for IP, port, .pem)
```

Then Remote-SSH -> `rarko1` -> open `/mnt/mirror/<repo>`.

## Adding repos and skills

- `repos.conf` - `REPO_URL|NAME|AUTO_MIRROR` per line, then `bash scripts/setup-repos.sh`
- `skills.conf` - `REPO_URL|NAME` per line, then `bash scripts/lib/install-claude-skills.sh`

## Verify / troubleshoot

```bash
bash scripts/verify-setup.sh          # every failed check prints the exact fix
bash scripts/bootstrap.sh --dry-run   # show the plan
```

Common fixes:

| Symptom | Fix |
|---------|-----|
| `git` slow | You are in the SOT. `cd /mnt/mirror/<repo>` |
| `/mnt/mirror` missing | `aml-bootstrap --restore` |
| GitHub SSH fails | `gh auth login` then `bash scripts/lib/configure-github-ssh.sh` |
| `command not found` after install | `source ~/.bashrc` |
| Docker permission denied | `newgrp docker` (or log out/in) |
| OS disk full | old venvs in `~/uv-venvs/` can be deleted; venvs now live in `/mnt/uv-venvs` |

More: [HAPPY-PATH.md](HAPPY-PATH.md), [docs/AZUREML-WORKTREE-PATTERN.md](docs/AZUREML-WORKTREE-PATTERN.md), [Setup.md](Setup.md).
