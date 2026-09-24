# Testing arrive-aml as a brand-new user

First real tester: **Colin Tracy** (`ctracy@arrivelogistics.com`, AML folder `ctracy`).
This page has two parts: what was tested automatically before the PR, and the checklist Colin
runs on his own compute instance. His setup guide is [GETTING-STARTED.md](GETTING-STARTED.md).

## Part 1: automated (done before review)

### Sandbox simulation: `bash tests/sandbox-new-user.sh`

This runs the whole new-user flow as Colin, on any VM, without touching the real user's setup.
It builds a throwaway HOME, a fake workspace share (`cloudfiles/code/Users/ctracy`, next to a
decoy `someone-else`), a fake `/mnt`, and a fake GitHub made of local bare repos (routed with
`git url.insteadOf`). The repos under test come from the current working tree, uncommitted
changes included. The wizard is answered over a real pseudo-terminal (`tests/lib/drive_tty.py`)
exactly as a person would, and `gh` is stubbed because we can't log in as Colin.

Result on the maintainer's compute instance, 2026-09-24: **64 passed, 0 failed** (~10 s with a warm uv cache).

| # | Scenario | What is checked |
|---|---|---|
| 1 | `get-started.sh` on an empty share | folder guessed from instance `ctracy1` → `ctracy`; welcome banner; email suggested as `ctracy@arrivelogistics.com`; arrive-aml cloned to *his* share; nothing written to another user's folder |
| 2 | Identity | git `user.name`/`user.email` = Colin; env file holds name + SOT; team org **not** pinned; profile saved on his share |
| 3 | Repos | arrive-aml, azureml-skills, arrive-ds: SOT clone, mirror clone, `sot` remote, sync hooks; venv; `/work-in-repo` skill linked; `aml-bootstrap` shim; bashrc block |
| 4 | Daily loop | a commit in the mirror is authored by Colin and reaches the SOT through the hook |
| 5 | VM restart | `/mnt` wiped → `--restore` brings back every mirror, the SOT-only branch and the venv |
| 6 | Re-runs | a second run on a terminal asks nothing; `--yes` with no terminal never blocks |
| 7 | Second VM, same share | identity read from the share profile, no questions, git identity set |
| 8 | GitHub login | device-code explanation shown, `gh auth login` run, GitHub user saved |
| 9 | Personal repo | `setup-repos.sh --add someorg/extra-repo` mirrors it (including a requirements.txt-only repo's venv), records it only in his `~/.config/arrive-aml/repos.conf`; login auto-restore notices when it is missing |
| 10 | Changing your mind | `--configure` pre-fills current answers; answering `n` asks again; extra repos from the wizard are recorded; `--github-org` pins, and returning to the default unpins; a bad `--email` is rejected |
| 11 | No trace of anyone else | no other person's name, email, folder or VM in any generated file; the real user's git config, env and skills are unchanged |
| 12 | `verify-setup.sh` as Colin | identity and all mirrors pass. The only remaining failure is the SSH key, which needs a real GitHub account |

### Static checks: `bash tests/lint.sh`

These checks passed: `bash -n` on all 32 scripts, no shellcheck errors, and no user-specific
names, emails, folders or VMs anywhere in code or docs. The team org appears only in the files
listed in [ORG-MOVE.md](ORG-MOVE.md).

### Existing user on a real VM (the maintainer's)

- `bootstrap.sh --dry-run`: plan printed, nothing changed.
- Full `bootstrap.sh` on a real terminal with **no answers typed**: the existing identity was detected
  with no question asked, all required checks passed, and it ended with `✓ Bootstrap complete. Your VM is ready, Rick.`
  The global git identity is unchanged, compared with a backup taken beforehand.
- The only additions were the identity keys in `~/.config/arrive-aml/env`, the share profile, and
  gh's credential helper from `gh auth setup-git`.
- `verify-setup.sh`: all required checks passed.

### Found and fixed while testing

- The wizard's final "Look right?" crashed, because `ask` and `ask_yes` both used a local named
  `answer`, so nothing was saved. The sandbox caught it.
- `github_ssh_ok` swallowed the rest of `repos.conf` when it was called inside a `while read` loop:
  `ssh` read stdin, so `--list` showed one repo instead of three.
- `verify-setup.sh` reported "32 commits not yet in the SOT" for a new branch with no commits of its own.
- Repos whose `pyproject.toml` holds only tool config, with deps in `requirements.txt` (Airflow/Astro
  style, e.g. de-airflow), failed venv setup. They now get a venv from `requirements.txt`.
- `detect_sot_base` fell back to "the only `Users/*/main/arrive-aml`", but the share lists every
  workspace user, so it would fail or pick the wrong person once a second user cloned arrive-aml.

## Part 2: Colin on his own compute instance

**Before you start:** the maintainer needs your GitHub user name to invite you to the private
`azureml-skills` and `arrive-ds` repos. Accept the invitation emails first.

Follow [GETTING-STARTED.md](GETTING-STARTED.md), with these values:

| Asked | Answer |
|---|---|
| Your folder name | `ctracy` (press Enter if it is suggested) |
| Your full name | `Colin Tracy` |
| Your work email | `ctracy@arrivelogistics.com` (press Enter if it is suggested) |
| Look right? | Enter |
| GitHub | open https://github.com/login/device on your laptop, paste the code, approve |

Then tick each box. If one fails, copy the last 30 lines of the terminal into the PR.

- [ ] **Setup:** `curl -fsSL https://raw.githubusercontent.com/rarko-arrive/arrive-aml/main/scripts/get-started.sh | bash`
      ends with `✓ Bootstrap complete. Your VM is ready, Colin.`
      **Until this PR merges**, use the branch version instead:
      ```bash
      curl -fsSL https://raw.githubusercontent.com/rarko-arrive/arrive-aml/feature/user-configurable-setup/scripts/get-started.sh \
        | ARRIVE_AML_BRANCH=feature/user-configurable-setup bash
      ```
      After the merge, go back to main with `git -C ~/cloudfiles/code/Users/ctracy/main/arrive-aml switch main && aml-bootstrap`.
- [ ] It asked only the questions above, and each suggestion was right. Note any that were wrong.
- [ ] `source ~/.bashrc && git config --global user.email` prints `ctracy@arrivelogistics.com`
- [ ] `bash ~/cloudfiles/code/Users/ctracy/main/arrive-aml/scripts/verify-setup.sh` ends `All required checks passed!`
- [ ] `ls /mnt/mirror` shows `arrive-aml azureml-skills arrive-ds`
- [ ] `cd /mnt/mirror/arrive-ds && time git status` takes well under a second
- [ ] `claude auth login`, then `claude` in `/mnt/mirror/arrive-ds`, and type
      `/work-in-repo add a small pytest for one utility function (don't open a PR)`. Claude branches,
      tests, commits as you, and `git log -1 --format='%an <%ae>'` shows you.
- [ ] `/aml-doctor check my VM`: Claude runs the checks and reports all green.
- [ ] **Restart test:** stop and start the instance in Studio, then open a new terminal. It prints
      `↻ /mnt was wiped on restart. Restoring…` and then `✓ Ready`. Your test branch is back:
      `git -C /mnt/mirror/arrive-ds branch -a | grep sot/`
- [ ] **Re-run test:** `aml-bootstrap` asks nothing and ends `✓ Bootstrap complete`.
- [ ] **Optional second VM:** create a second instance, then run
      `bash ~/cloudfiles/code/Users/ctracy/main/arrive-aml/scripts/bootstrap.sh`. It asks nothing except the GitHub code.
- [ ] Anything confusing or not enjoyable: write one line about it in the PR, even if it worked.

Clean-up afterwards (optional): delete the test branch with `git -C /mnt/mirror/arrive-ds push sot --delete <branch>`
and `git branch -D <branch>`.
