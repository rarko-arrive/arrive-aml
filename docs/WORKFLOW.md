# The Arrive Azure ML Workflow

**One page, every scientist, every PR.** How a compute instance is set up, how it comes back
after a restart, and the loop you run for each experiment, feature or fix. Everything here is
copy-paste; every command is idempotent (safe to re-run).

---

## 0. Mental model (30 seconds)

```
GitHub  ←──── git push ────  /mnt/mirror/REPO  ──── hook: git push sot ────→  ~/cloudfiles/code/Users/<you>/main/REPO
(team)                        WHERE YOU WORK                                   SOURCE OF TRUTH (SOT)
                              local disk, git status 5 ms                      Azure Files share: slow (5 s), persistent,
                              wiped on VM stop/start                            mounted on EVERY compute instance you own
```

| | `/mnt/mirror/REPO` (mirror) | `~/cloudfiles/code/Users/<you>/main/REPO` (SOT) |
|---|---|---|
| What | Full local git clone. Remotes: `origin` = GitHub, `sot` = the SOT | The persistent `.git` database, on `main`, files updated by every push (`updateInstead`). |
| Speed | `git status` 5 ms | `git status` 5 s (60-95 ms per file operation on the share) |
| Lifetime | Gone after every VM stop/start | Forever, and shared by all your VMs |
| You | Edit, run, commit, push here | Never edit here. Treat it as a remote. |
| Python | `.venv` → `/mnt/uv-venvs/REPO` (uv) | none |

**Every commit you make in a mirror is pushed to the SOT by a git hook within seconds.**
So a `/mnt` wipe can only ever cost you *uncommitted* edits. Commit often.

---

## 1. Fresh compute instance (once per VM, ~5-10 min)

Open a terminal on the VM (Azure ML studio terminal, or SSH).

```bash
bash ~/cloudfiles/code/Users/rarko/main/arrive-aml/scripts/bootstrap.sh
source ~/.bashrc
claude auth login            # once per VM; open the URL on your laptop, paste the code back
```

Replace `rarko` with your folder under `~/cloudfiles/code/Users/`. arrive-aml is already there
because the share is common to all your VMs. If it truly is not:

```bash
mkdir -p ~/cloudfiles/code/Users/<you>/main && cd ~/cloudfiles/code/Users/<you>/main
gh auth login                # pick SSH; gh is pre-installed on Azure ML images
git clone git@github.com:rarko-arrive/arrive-aml.git
```

What `bootstrap.sh` does, in order, and where it lands:

| Step | What | Persists? |
|---|---|---|
| 1 tools | git tuned for the share, uv, gh, GitHub SSH key (uploaded via gh), Docker, cloudflared, Claude Code | yes (OS disk) |
| 2 shell | `aml-bootstrap` command, `~/.config/arrive-aml/env`, one managed block in `~/.bashrc` | yes |
| 3 repos | every repo in `repos.conf`: SOT clone → mirror clone → `uv sync` venv + `.venv` symlink | SOT yes; mirror + venv **no** |
| 4 skills | every repo in `skills.conf` → `~/.claude/skills/<skill>` (e.g. `/work-in-repo`) | yes |
| 5 verify | `verify-setup.sh`: every failed check prints its exact fix | |

You should end with:

```
✓ arrive-aml: mirror /mnt/mirror/arrive-aml [main], venv ok
✓ azureml-skills: mirror /mnt/mirror/azureml-skills [main]
✓ arrive-ds: mirror /mnt/mirror/arrive-ds [main], venv ok
✓ All required checks passed!
✓ Bootstrap complete. Your VM is ready.
```

Anything else: read the `fix:` line under the failed check, run it, re-run `aml-bootstrap`.

**Laptop side (once per VM):** `bash scripts/setup-azureml-ssh.sh` from your local clone adds
the VM to `~/.ssh/config`. Then Cursor / VS Code → Remote-SSH → the VM → open
`/mnt/mirror/<repo>`. The editors are not installed on the VM; they bring their own server.

---

## 2. After every VM stop/start (~1-2 min)

`/mnt` comes back empty. **Just SSH in.** The first interactive shell sees that the mirrors are
gone, fast-forwards `arrive-aml` itself when that checkout is clean, then re-clones every mirror
(GitHub first, SOT if offline), fetches the branches that exist only in the SOT, rebuilds the
venvs, refreshes skills and verifies. A second terminal opened while that is running waits, then
gets the same `✓ Ready` line. You do not type a restore command.

```bash
aml-bootstrap --restore    # same thing, if you want it finished before you connect, or the login restore failed
```

Set `ARRIVE_NO_AUTO_RESTORE=1` in `~/.config/arrive-aml/env` if you want the old manual behavior.

**Already done before you connect:** in Azure ML studio → Compute → your instance → *Startup script*, set

```
sudo -u azureuser -H bash /home/azureuser/cloudfiles/code/Users/<you>/main/arrive-aml/scripts/bootstrap.sh --restore
```

and the restore runs on every start, so the login shell finds the mirrors and stays quiet.
(`crontab` is not permitted for `azureuser`.)

---

## 3. The loop: one experiment / feature / PR

```bash
cd /mnt/mirror/arrive-ds                     # 1. always the mirror
git checkout main && git pull                # 2. start from current main (origin = GitHub)
git checkout -b feature/short-description    # 3. one branch per PR

# 4. work: edit in Cursor/VS Code (Remote-SSH, folder /mnt/mirror/arrive-ds), run things:
uv run python experiments/train.py           #    .venv -> /mnt/uv-venvs/arrive-ds
uv add polars                                #    dependencies: uv, never pip
uv run pytest                                #    tests

git add -A && git commit -m "feat: ..."      # 5. commit early and often -> hook pushes to sot
git push                                     # 6. -> GitHub (push.autoSetupRemote is on)
gh pr create --fill                          # 7. open the PR

# 8. review feedback: edit, commit, git push - repeat
# 9. after merge:
git checkout main && git pull && git branch -d feature/short-description
#    (the post-merge hook pushes main to the SOT, whose files update in place)
```

Or let Claude Code drive steps 1-7: in any terminal run `claude`, then `/work-in-repo` and
describe the change.

**Notebooks:** open them from `/mnt/mirror/<repo>`; pick the kernel at `<repo>/.venv/bin/python`.

**Two branches at once:** `git worktree add /mnt/mirror/arrive-ds-exp2 feature/exp2` *from the
mirror* (stays fully local and fast). Remove with `git worktree remove /mnt/mirror/arrive-ds-exp2`.

**Working from two VMs on the same branch:** the SOT is shared, so the second VM's hook push is
rejected as non-fast-forward. `git pull sot <branch>`, then commit again.

---

## 4. Check yourself anytime

```bash
bash ~/cloudfiles/code/Users/<you>/main/arrive-aml/scripts/verify-setup.sh   # or from any mirror: bash scripts/verify-setup.sh
cat ~/.local/state/arrive-aml/sot-sync.log | tail                            # every hook push, ok or FAIL
bash scripts/lib/setup-mirror-worktree.sh --list                              # mirrors + unsynced commit counts
```

`verify-setup.sh` exits non-zero only for **required** items and always prints the fix. It also
reports commits that never reached the SOT (`git push sot HEAD` retries).

---

## 5. Adding things

| Want | Do |
|---|---|
| A new team repo on every VM | add `git@github.com:rarko-arrive/NAME.git\|NAME\|yes` to `repos.conf`, run `aml-bootstrap` |
| A repo without a mirror | same line with `\|no` |
| A new Claude Code skills repo | add `REPO_URL\|NAME` to `skills.conf`, run `bash scripts/lib/install-claude-skills.sh` |
| venvs somewhere else | edit `UV_VENV_ROOT` in `~/.config/arrive-aml/env`, run `aml-bootstrap --restore` |
| Only one piece | every script in `scripts/lib/` runs standalone, e.g. `bash scripts/lib/setup-python-venv.sh /mnt/mirror/arrive-ds` |

---

## 6. When something is off

| Symptom | Cause | Fix |
|---|---|---|
| git is slow | you are in the SOT | `cd /mnt/mirror/<repo>` |
| `/mnt/mirror` missing | VM restarted, and this shell did not restore it | `aml-bootstrap --restore` (or open a new login; it runs on its own) |
| `FAIL ... -> sot` in the sync log | share unmounted, or another VM pushed first | `git push sot HEAD`, or `git pull sot <branch>` then commit |
| `Permission denied (publickey)` | key not on GitHub / gh not logged in | `gh auth login` then `bash scripts/lib/configure-github-ssh.sh` |
| `detected dubious ownership` | share is root-owned | `bash scripts/lib/configure-git.sh` (sets `safe.directory *`) |
| git does not see my edits | old `core.ignoreStat=true` flagged files assume-unchanged | `aml-bootstrap` (clears it), or `git ls-files -z \| git update-index -z --no-assume-unchanged --stdin` |
| `uv sync` fails: "Unable to determine which files to ship" | repo is not a package but declares a build backend | add `[tool.uv] package = false` to `pyproject.toml` |
| `claude: command not found` | not installed / PATH | `bash scripts/lib/install-claude.sh && source ~/.bashrc` |
| `cloudflared: command not found` | not installed / PATH | `bash scripts/lib/install-cloudflared.sh && source ~/.bashrc` |
| `/work-in-repo` not found | skills not linked | `bash scripts/lib/install-claude-skills.sh`, restart Claude Code |
| OS disk > 90% | legacy venvs, old editor servers | `rm -rf ~/uv-venvs` (13 GB; venvs are in `/mnt/uv-venvs` now), prune `~/.vscode-server/cli/servers/` |
| `Could not determine the SOT base` | arrive-aml not under `~/cloudfiles/code/Users/<you>/main/` | move it there, or `export ARRIVE_SOT_BASE=...` |
| Mirror dir exists but git errors | broken clone | `aml-bootstrap --restore` moves it to `<mirror>.broken-<time>` and re-clones |

---

## Appendix A - Why it is built this way (2026-09-14 findings)

The previous setup looped: `setup-vm.sh --all` → `verify-setup.sh` failed → "run setup again".
Investigation on `rarko1` found:

1. **GitHub SSH check was a false negative.** GitHub exits 1 on `ssh -T` even when authenticated;
   `ssh | grep -q` under `set -o pipefail` reported failure. Fixed with `github_ssh_ok` in `common.sh`.
2. **Cursor's download host (`downloader.cursor.sh`) no longer resolves**, and a compute instance is
   headless. Cursor/VS Code run on the laptop; their servers self-install under `~/.cursor-server`
   / `~/.vscode-server`. The installers now detect those servers instead.
3. **`install-claude.sh` never installed anything** - it printed instructions. It now runs the
   official installer (npm fallback) and reports login state.
4. **`core.ignoreStat true` in the git tuning hid edits from git.** 56 files were flagged
   assume-unchanged; `git status` showed a clean tree over real changes. Now forced `false`,
   flags cleared automatically.
5. **`setup-repos.sh` pointed at `~/cloudfiles/rarko/main`**, a path that does not exist. The SOT
   base is now derived from arrive-aml's own `.git` location.
6. **`/mnt` is Azure's ephemeral resource disk** (`/mnt/EPHEMERAL_DISK_DATALOSS_WARNING.txt`),
   not persistent as documented. Hence `--restore`, the bashrc reminder and the startup-script option.
7. **The OS disk (122 GB) was 98% full**; venvs and the uv cache moved to `/mnt` (600 GB).
8. **Linked worktrees were only 1.8x faster than the SOT.** Measured `git status`: SOT 5.4 s,
   `git worktree` on `/mnt` 3.0 s (its index/HEAD/refs still live on the share), local clone
   0.005 s. Worktrees also registered the same per-VM path inside the shared SOT `.git`, so one
   VM's `git worktree prune` could break another's mirror. Mirrors became local clones with the
   SOT as remote `sot` and background sync hooks; legacy worktree mirrors are migrated automatically.
9. **The repo's `pyproject.toml` declared hatchling but shipped no package**, so `uv sync` failed
   on the mirror. `[tool.uv] package = false`.
10. **Running `--restore` from inside a mirror deleted the shell's cwd**, after which every git
    call (including `git config --global` reads) failed. The scripts now `cd $HOME` first.

## Appendix B - Guarantees the scripts make

- Idempotent: every script can be re-run; nothing is deleted except a *clean* legacy worktree
  mirror. Anything with uncommitted changes is moved to `<mirror>.old-worktree-<time>` or
  `<mirror>.broken-<time>`, never removed.
- The SOT is only ever written by `git push` (hooks); `receive.denyCurrentBranch=updateInstead`
  refreshes its files when its checked-out branch is pushed. Nothing runs `git worktree prune` in a SOT.
- Verification never says "run setup again" without naming the failing check and its fix.
- All paths are configurable in `~/.config/arrive-aml/env`; nothing assumes the Linux user is
  the Azure ML user (`azureuser` vs `rarko`).
- Logs: `~/.local/state/arrive-aml/bootstrap-<time>.log`, `~/.local/state/arrive-aml/sot-sync.log`.

## Appendix C - Files that matter

| File | Role |
|---|---|
| `scripts/bootstrap.sh` | the one command (`--restore`, `--dry-run`, `--skip-*`) |
| `scripts/setup-repos.sh` | repos.conf → SOT clone, mirror clone, venv |
| `scripts/verify-setup.sh` | required vs optional checks, prints fixes |
| `scripts/lib/mirror.sh` | mirror clone, `sot` remote, sync hooks, legacy migration |
| `scripts/lib/configure-git.sh` | share-tuned git settings, `safe.directory *`, `push.autoSetupRemote` |
| `scripts/lib/configure-shell.sh` | bashrc block, env file, `aml-bootstrap`, quiet conda + idle timeout |
| `scripts/lib/login-restore.sh` | sourced by bashrc: restores `/mnt` after a restart |
| `scripts/lib/setup-python-venv.sh` | `uv sync` into `/mnt/uv-venvs/<repo>` + `.venv` symlink |
| `scripts/lib/install-claude-skills.sh` | skills.conf → `~/.claude/skills` |
| `repos.conf`, `skills.conf` | what gets installed on every VM |
| `docs/MIRROR-PATTERN.md` | the SOT/mirror design with measurements |
