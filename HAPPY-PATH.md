# Happy Path - Fresh Azure ML Compute Instance

Step-by-step for a brand-new compute instance. Total time: about 5-10 minutes, one command.

## Prerequisites

- An Azure ML compute instance (Ubuntu) in the Arrive workspace, started
- A terminal on it (Azure ML studio terminal, or SSH)
- A GitHub account in the `rarko-arrive` org

## 1. Find arrive-aml on the shared drive

`~/cloudfiles/code/Users/<you>/` is the workspace file share. It is the same on every compute
instance you own, so `arrive-aml` is normally already there:

```bash
ls ~/cloudfiles/code/Users/*/main/arrive-aml
```

If it is missing, clone it (replace `rarko` with your folder name):

```bash
mkdir -p ~/cloudfiles/code/Users/rarko/main
cd ~/cloudfiles/code/Users/rarko/main
gh auth login          # GitHub CLI is pre-installed on Azure ML images; pick SSH when asked
git clone git@github.com:rarko-arrive/arrive-aml.git
```

## 2. Run the bootstrap

```bash
bash ~/cloudfiles/code/Users/rarko/main/arrive-aml/scripts/bootstrap.sh
```

What happens (all idempotent, re-run any time):

| Step | What | Where it lands |
|------|------|----------------|
| 1 | git tuned for the network mount, uv, gh, GitHub SSH key, Docker, Claude Code | OS disk (persists) |
| 2 | `aml-bootstrap` command, `~/.config/arrive-aml/env`, bashrc block | OS disk |
| 3 | every repo in `repos.conf` cloned to the SOT, local mirror clone (+ SOT sync hooks), uv venv | SOT: cloudfiles. Mirror + venv: `/mnt` |
| 4 | team Claude Code skills (`skills.conf`) linked into `~/.claude/skills` | OS disk |
| 5 | verification - each failed check prints its fix | |

Expected tail of the output:

```
✓ arrive-aml: mirror /mnt/mirror/arrive-aml [main], venv ok
✓ azureml-skills: mirror /mnt/mirror/azureml-skills [main]
✓ arrive-ds: mirror /mnt/mirror/arrive-ds [main], venv ok
✓ All required checks passed!
✓ Bootstrap complete. Your VM is ready.
```

Then `source ~/.bashrc` (or open a new terminal).

If GitHub SSH is not set up yet, step 1 creates `~/.ssh/id_ed25519_github` and uploads it with
`gh`; if `gh` is not logged in, run `gh auth login` and re-run the bootstrap.

## 3. Sign in to Claude Code (once per VM)

```bash
claude auth login      # opens a URL - paste the code back into the terminal
```

Then in any repo: `claude` and `/work-in-repo`.

## 4. Connect your laptop (Cursor / VS Code)

On your **laptop** (not the VM):

```bash
bash scripts/setup-azureml-ssh.sh    # from your local arrive-aml clone
```

Remote-SSH to the VM and open `/mnt/mirror/<repo>`. Cursor/VS Code install their server
component on the VM automatically. Details: [docs/SSH-SETUP-FROM-LAPTOP.md](docs/SSH-SETUP-FROM-LAPTOP.md).

## 5. Work

```bash
cd /mnt/mirror/arrive-aml
git checkout -b feature/my-change
# edit, test
git add -A && git commit -m "..."
git push                              # push.autoSetupRemote is on
```

Each commit is pushed to the SOT's `.git` on cloudfiles by a background hook (remote `sot`),
so nothing is lost if `/mnt` disappears - only uncommitted edits. `bash scripts/verify-setup.sh`
reports any commit whose push did not make it (`git push sot HEAD` to retry).

## After a VM stop/start

`/mnt` is Azure's ephemeral resource disk and comes back empty. Your shell will remind you:

```bash
aml-bootstrap --restore    # recreates mirrors + venvs, refreshes skills, verifies
```

Optional: paste the same line into the compute instance's **startup script** (Azure ML studio ->
Compute -> your instance -> Startup script) as
`sudo -u azureuser -H bash /home/azureuser/cloudfiles/code/Users/rarko/main/arrive-aml/scripts/bootstrap.sh --restore`
and the restore runs on every start without you.

## Layout you end up with

```
~/cloudfiles/code/Users/rarko/main/      SOT - persistent, shared by all your VMs, slow
├── arrive-aml/    (.git database, on main, updated by every push - never edit here)
├── azureml-skills/
└── arrive-ds/

/mnt/mirror/                             per-VM local clones - fast, wiped on stop/start
├── arrive-aml/    [main]  .venv -> /mnt/uv-venvs/arrive-aml
├── azureml-skills/[main]
└── arrive-ds/     [main]  .venv -> /mnt/uv-venvs/arrive-ds

/mnt/uv-venvs/, /mnt/uv-cache/           uv venvs + cache - fast, big disk, recreated by --restore
~/.claude/skills/work-in-repo            -> ~/.claude/plugins/marketplaces/azureml-skills/skills/work-in-repo
```

## Common issues

| Issue | Fix |
|-------|-----|
| `Could not determine the SOT base` | arrive-aml must live at `~/cloudfiles/code/Users/<you>/main/arrive-aml` (or `export ARRIVE_SOT_BASE=...`) |
| `Clone failed` / `Permission denied (publickey)` | `gh auth login`, then `bash scripts/lib/configure-github-ssh.sh` |
| `! [rejected]` in `~/.local/state/arrive-aml/sot-sync.log` | Another VM pushed the same branch to the SOT first: `git pull sot <branch>` then commit again |
| Mirror exists but git errors | `aml-bootstrap --restore` moves the broken dir to `*.broken-<time>` and recreates it |
| OS disk >90% full | Delete legacy venvs: `rm -rf ~/uv-venvs/<name>`; old VS Code servers: `~/.vscode-server/cli/servers/` |
| `claude: command not found` | `bash scripts/lib/install-claude.sh && source ~/.bashrc` |

## Next

- [QUICKSTART.md](QUICKSTART.md) - one-page cheat sheet
- [docs/AZUREML-WORKTREE-PATTERN.md](docs/AZUREML-WORKTREE-PATTERN.md) - why SOT + mirror works
- [docs/REPOS-CONFIG.md](docs/REPOS-CONFIG.md) - adding repos
- [CLAUDE-SETUP.md](CLAUDE-SETUP.md) - Claude Code + skills
