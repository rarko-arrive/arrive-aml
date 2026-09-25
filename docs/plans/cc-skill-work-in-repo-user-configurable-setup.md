# Plan: arrive-aml for any user (guided setup, nothing hard-coded)

**Date**: 2026-09-24 · **Branch**: feature/user-configurable-setup (arrive-aml + azureml-skills) · **Skill**: work-in-repo · **Status**: Complete, awaiting review and Colin's run

## Objective
Keep the same defaults but stop assuming the author. Any data scientist runs one command,
answers two pre-filled questions, and gets a working VM, including restore after restarts, a
second VM, and personal repos. The skills are generalized to match.

## Approach
1. Moved every user-specific value into `~/.config/arrive-aml/env`. `config_set` merges keys; the
   team defaults live in one block in `common.sh`, and `{org}` in `repos.conf`/`skills.conf` expands to
   `ARRIVE_GITHUB_ORG`.
2. Wizard (`configure-user.sh`, bootstrap step 0): detect first (config → share profile → git → gh), ask
   only for what is missing, confirm, and save to the env file and the share profile. Never prompt
   without a terminal.
3. GitHub device-code login inside `configure-github-ssh.sh`, plus `gh auth setup-git`, so https
   clones work before SSH does.
4. `get-started.sh` for an empty share, and `setup-repos.sh --add` for personal repos.
5. Tests: `tests/lint.sh` (syntax, shellcheck, no personal values) and `tests/sandbox-new-user.sh`
   (the whole flow as Colin, over a real pty, against a fake share and fake GitHub).
6. Rewrote `work-in-repo`, added `aml-doctor`, consolidated the skills repo docs, and compared the new skills
   with the old ones on three prompts.

## Changes (high level)
- `scripts/lib/common.sh`: team defaults; `config_set`/`config_unset`, `can_prompt`/`ask`/`ask_yes`,
  `apply_git_identity`, `guess_aml_user`/`aml_user`, a more robust `detect_sot_base`, `github_protocol`,
  `repo_url`, `read_conf_entries`/`read_repo_entries`/`read_skill_entries`, `repo_python_kind`
- New: `scripts/lib/configure-user.sh`, `scripts/get-started.sh`, `tests/*`, `docs/GETTING-STARTED.md`,
  `docs/ORG-MOVE.md`, `docs/TESTING-NEW-USER.md`
- `bootstrap.sh`: step 0 plus `--configure/--name/--email/--github-org/--yes`; personalized summary
- `configure-git.sh`: the hard-coded identity is gone. `configure-shell.sh`: merges instead of overwriting
- `setup-repos.sh`, `install-claude-skills.sh`, `verify-setup.sh`, `login-restore.sh`: use the merged
  team + personal lists
- `mirror.sh`: the unsynced count for new branches is fixed. `setup-python-venv.sh`: handles requirements.txt-only repos
- All docs: `<you>` / `my-aml-vm` / `{org}` in place of personal values; removed stale ds-cursor-demo sections

## Testing
- `bash tests/sandbox-new-user.sh`: 64/64
- `bash tests/lint.sh`: clean
- Real VM: `--dry-run`; full bootstrap on a pty with no answers (silent, rc 0, git identity unchanged);
  `verify-setup.sh` green
- Skills, plan-only runs, new vs old: work-in-repo 8/8 vs 6/8 and 7/8 vs 4/8; aml-doctor 4/4 vs 3/4 (no skill)

## Lessons learned / gotchas
- `~/cloudfiles/code/Users/` lists every workspace user, and the folders are world-writable. Never
  pick "the only folder", and never `source` files from the share: `profile_get` parses them as data.
- In `while read ... done < <(list)`, anything that reads stdin (ssh!) eats the list. Use `</dev/null`.
- Bash `local` names in helpers that take a variable name must not collide with the caller's (`__` prefix).
- A pty-driven sandbox found two bugs that `bash -n` and a dry run could not.

## Next steps
- [ ] Colin runs Part 2 of docs/TESTING-NEW-USER.md on his own VM (he needs repo invites first)
- [ ] Merge the azureml-skills PR together with this one (work-in-repo relies on `setup-repos.sh --add`)
- [ ] Org move to Arrive-Logistics: follow docs/ORG-MOVE.md
- [ ] Separate hardening: bashrc sources `login-restore.sh` from the share, which any workspace user can write
