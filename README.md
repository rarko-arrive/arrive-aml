# arrive-aml

**One command turns an Azure ML compute instance into the Arrive data-science workbench.**
Tuned git, uv, GitHub CLI + SSH, Docker, cloudflared, Claude Code with the team skills, and every team repo
ready to work on: persistent copy on the share, fast local mirror on `/mnt`, uv venv per repo.

## Set up a VM

```bash
bash ~/cloudfiles/code/Users/rarko/main/arrive-aml/scripts/bootstrap.sh
source ~/.bashrc
claude auth login        # once per VM
```

Takes 5-10 minutes, safe to re-run, ends with `✓ Bootstrap complete`. If a check fails, it prints
the fix. `~/cloudfiles/code/Users/rarko/` is the workspace share, so `arrive-aml` is already on
every VM you own. (Other user or fresh share: [docs/FRESH-VM.md](docs/FRESH-VM.md).)

## After every VM stop/start

`/mnt` comes back empty. The next SSH session restores mirrors and venvs on its own (~1-2 min)
and then prints `✓ Ready`. Nothing committed is ever lost: every commit in a mirror is pushed
to the persistent copy by a hook within seconds.

```bash
aml-bootstrap --restore  # same restore, if you want it done before you connect or a login restore failed
```

## Work

```bash
cd /mnt/mirror/arrive-ds                   # always the mirror: git status ~5 ms
git checkout main && git pull
git checkout -b feature/my-change
uv run python experiments/train.py         # .venv -> /mnt/uv-venvs/arrive-ds
git add -A && git commit -m "feat: ..."    # hook syncs to the persistent copy
git push && gh pr create --fill            # -> GitHub
```

Or let Claude drive it: `claude` → `/work-in-repo`.
From your laptop: Cursor / VS Code → Remote-SSH → the VM → open `/mnt/mirror/<repo>`
([laptop SSH setup](docs/SSH-SETUP-FROM-LAPTOP.md)).

## How it fits together

```
GitHub  ←─ git push ─  /mnt/mirror/REPO  ─ hook: git push sot ─→  ~/cloudfiles/code/Users/rarko/main/REPO
                       work here (fast, per VM,                    source of truth (persistent, slow,
                       wiped on restart)                           shared by all your VMs, on main)
```

| | Mirror `/mnt/mirror/REPO` | Source of truth `~/cloudfiles/.../main/REPO` |
|---|---|---|
| `git status` | 5 ms | 5 s |
| Survives restart | no (next login restores it) | yes |
| You | edit, run, commit, push | never edit; it is a remote named `sot` |

## Docs

| Read when | Page |
|---|---|
| You want the full loop, self-checks, and every fix in one place | [docs/WORKFLOW.md](docs/WORKFLOW.md) |
| Brand-new VM or new user, step by step | [docs/FRESH-VM.md](docs/FRESH-VM.md) |
| Why SOT + local clone, with measurements | [docs/MIRROR-PATTERN.md](docs/MIRROR-PATTERN.md) |
| Add a repo to every VM | [docs/REPOS-CONFIG.md](docs/REPOS-CONFIG.md) (`repos.conf`) |
| Claude Code + `/work-in-repo` skills | [docs/CLAUDE-CODE.md](docs/CLAUDE-CODE.md) (`skills.conf`) |
| Connect Cursor / VS Code from your laptop | [docs/SSH-SETUP-FROM-LAPTOP.md](docs/SSH-SETUP-FROM-LAPTOP.md), [docs/REUSE-SSH-KEY.md](docs/REUSE-SSH-KEY.md) |
| Where things live on Azure ML | [docs/PATHS.md](docs/PATHS.md) |
| Something odd (Cursor notebooks, kernels, SSH) | [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) |

## Scripts

Everything is idempotent and runs standalone; `bootstrap.sh` just runs them in order.

| Script | Does |
|---|---|
| `scripts/bootstrap.sh` | the one command (`--restore`, `--dry-run`, `--skip-tools/-repos/-venvs/-skills`) |
| `scripts/setup-vm.sh --all` | tools: git tuning, uv, gh, GitHub SSH, Docker, cloudflared, Claude Code |
| `scripts/setup-repos.sh` | `repos.conf` → SOT clone, mirror clone + sync hooks, uv venv (`--only NAME`) |
| `scripts/verify-setup.sh` | every check, every fix; exit 1 only on required failures |
| `scripts/lib/*.sh` | one concern each: `configure-git.sh`, `configure-github-ssh.sh`, `setup-python-venv.sh`, `install-claude-skills.sh`, ... |
| `scripts/setup-azureml-ssh.sh` | run on your **laptop**: adds the VM to `~/.ssh/config` |

Paths are configurable in `~/.config/arrive-aml/env` (`MIRROR_BASE`, `UV_VENV_ROOT`, `ARRIVE_SOT_BASE`).
Logs: `~/.local/state/arrive-aml/`.

---
Maintained by rarko@arrivelogistics.com · Arrive Logistics Data Science
