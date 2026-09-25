# Happy Path - Fresh Azure ML Compute Instance

Step-by-step for a brand-new compute instance. Total time: about 5-10 minutes, one command.

## Prerequisites

- An Azure ML compute instance (Ubuntu) in the Arrive workspace, started
- A terminal on it (Azure ML studio terminal, or SSH)
- A GitHub account that is a member of the team GitHub org (ask a teammate to add you)

## 1. Know your folder (`<you>`)

`~/cloudfiles/code/Users/` is the workspace file share - the `Users/` folder you see in Azure ML
Studio -> Notebooks. It holds a folder for **every** user in the workspace, so make sure you use
your own: `<you>` in this page means that folder name (usually your email alias). It is the same
on every compute instance you own, so what you clone there is visible from all your VMs:

```bash
ls ~/cloudfiles/code/Users/            # everyone's folders - yours is the one named after you
```

## 2. Run the one command

```bash
curl -fsSL https://raw.githubusercontent.com/<team-org>/arrive-aml/main/scripts/get-started.sh | bash
```

It guesses your folder from the instance name (instance `ctracy2` -> folder `ctracy`) and asks you
to confirm (`ARRIVE_AML_USER=<you>` in front of `bash` skips that question), clones arrive-aml to
`~/cloudfiles/code/Users/<you>/main/arrive-aml` over https, and runs the bootstrap. A friendlier
walkthrough of the same thing: [GETTING-STARTED.md](GETTING-STARTED.md).

**Second VM** (arrive-aml is already on your share): run the bootstrap directly instead:

```bash
bash ~/cloudfiles/code/Users/<you>/main/arrive-aml/scripts/bootstrap.sh
```

**Manual fallback** (if the curl command is blocked):

```bash
mkdir -p ~/cloudfiles/code/Users/<you>/main && \
git clone https://github.com/<team-org>/arrive-aml.git ~/cloudfiles/code/Users/<you>/main/arrive-aml && \
bash ~/cloudfiles/code/Users/<you>/main/arrive-aml/scripts/bootstrap.sh
```

### The short wizard (step 0, "You")

The bootstrap first asks only what it cannot detect: your **full name** and **work email**
(suggested as `<you>@arrivelogistics.com`). It then shows a summary and asks `Look right? [Y/n]`;
answering `n` also lets you change the team GitHub org and add extra repos. Answers are looked up
in this order: saved config (`~/.config/arrive-aml/env`) -> your share profile
(`~/cloudfiles/code/Users/<you>/main/.arrive-aml/profile`, so your second VM asks nothing) ->
git config -> gh. Change them later with `aml-bootstrap --configure`, or skip the questions with
`--name "First Last" --email you@arrivelogistics.com` (`--yes` never asks).

What happens next (all idempotent, re-run any time):

| Step | What | Where it lands |
|------|------|----------------|
| 0 | who you are (name, email, GitHub) - asks only what it cannot detect | `~/.config/arrive-aml/env` + share profile |
| 1 | git tuned for the network mount, uv, gh, GitHub SSH key, Docker, cloudflared, Claude Code | OS disk (persists) |
| 2 | `aml-bootstrap` command, `~/.config/arrive-aml/env`, bashrc block | OS disk |
| 3 | every repo in `repos.conf` (+ your personal list) cloned to the SOT, local mirror clone (+ SOT sync hooks), uv venv | SOT: cloudfiles. Mirror + venv: `/mnt` |
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

**GitHub login:** in step 1, if `gh` is not logged in, the bootstrap runs `gh auth login --web`
and prints a one-time code: open https://github.com/login/device on your laptop and enter it.
It then creates `~/.ssh/id_ed25519_github`, uploads it to GitHub for you, and runs
`gh auth setup-git` so https clones work too.

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
component on the VM automatically. Details: [SSH-SETUP-FROM-LAPTOP.md](SSH-SETUP-FROM-LAPTOP.md).

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

`/mnt` is Azure's ephemeral resource disk and comes back empty. SSH in: the login shell
recreates mirrors, venvs, and skills, then prints `✓ Ready`. To run that yourself:

```bash
aml-bootstrap --restore
```

Optional: paste the same command into the compute instance's **startup script** (Azure ML studio ->
Compute -> your instance -> Startup script) as
`sudo -u azureuser -H bash /home/azureuser/cloudfiles/code/Users/<you>/main/arrive-aml/scripts/bootstrap.sh --restore`
and the restore finishes on every start, before you connect. Startup scripts never ask questions;
they use your saved answers.

## Layout you end up with

```
~/cloudfiles/code/Users/<you>/main/      SOT - persistent, shared by all your VMs, slow
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
| `Clone failed` / `Permission denied (publickey)` | `gh auth status`; not a member of the team org? ask a teammate to add you. Then `bash scripts/lib/configure-github-ssh.sh` |
| Wizard picked the wrong folder / name | `aml-bootstrap --configure` (or edit `~/.config/arrive-aml/env`) |
| verify: `git user.name/user.email not set` | `aml-bootstrap --configure` |
| `! [rejected]` in `~/.local/state/arrive-aml/sot-sync.log` | Another VM pushed the same branch to the SOT first: `git pull sot <branch>` then commit again |
| Mirror exists but git errors | `aml-bootstrap --restore` moves the broken dir to `*.broken-<time>` and recreates it |
| OS disk >90% full | Delete legacy venvs: `rm -rf ~/uv-venvs/<name>`; old VS Code servers: `~/.vscode-server/cli/servers/` |
| `claude: command not found` | `bash scripts/lib/install-claude.sh && source ~/.bashrc` |

## Next

- [README.md](../README.md) - the one-page happy path
- [docs/MIRROR-PATTERN.md](MIRROR-PATTERN.md) - why SOT + mirror works
- [REPOS-CONFIG.md](REPOS-CONFIG.md) - adding repos
- [docs/CLAUDE-CODE.md](CLAUDE-CODE.md) - Claude Code + skills
