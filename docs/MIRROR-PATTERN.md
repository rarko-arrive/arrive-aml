# Azure ML Mirror Pattern: SOT on cloudfiles + local clone on /mnt

## The Problem

Azure ML compute instances mount your files from Azure Files (CIFS) at `~/cloudfiles/code/Users/<you>/`
(`<you>` = your folder under `Users/` in Azure ML Studio -> Notebooks; the share holds every workspace
user's folder, so use your own).
Every file operation on that share costs 60-95 ms, so git is painfully slow there:

| Where | `git status` (arrive-aml, measured on a compute instance, 2026-09-14) |
|-------|--------------------------------------------------|
| SOT on cloudfiles | 5.4 s |
| `git worktree` on /mnt linked to the SOT's `.git` | 3.0 s (index, HEAD and refs still live on the share) |
| full local clone on /mnt | 0.005 s |

Local disk (`/mnt`, 600 GB) is fast but **ephemeral**: it is Azure's resource disk and is wiped on
every stop/start (`/mnt/EPHEMERAL_DISK_DATALOSS_WARNING.txt`). The share is persistent and is
mounted on every compute instance you own.

## The Solution

```
~/cloudfiles/code/Users/<you>/main/REPO/     ← Source of Truth (SOT): persistent, shared by all your VMs
                                               full .git database, on main, files updated by every push, never edited directly
                                               = remote "sot" of every mirror

/mnt/mirror/REPO/                            ← Mirror: a full local clone, one per compute instance
                                               remotes: origin = GitHub, sot = SOT path
                                               hooks push each commit to sot in the background
                                               where you work: git status in ~5 ms
```

- **Commit** in the mirror → `post-commit` hook runs `git push sot HEAD:<branch>` in the background
  (serialized, logged to `~/.local/state/arrive-aml/sot-sync.log`). Same for `post-merge` and
  `post-rewrite` (amend/rebase use `--force-with-lease`).
- **Push** to GitHub as always: `git push` (remote.pushDefault = origin, push.autoSetupRemote on).
- **Restart**: the next login runs `aml-bootstrap --restore`, which re-clones from GitHub (falls back to the SOT when offline),
  adds the `sot` remote, fetches the branches that only the SOT has, and fast-forwards the default
  branch to whatever the SOT has. Then it rebuilds venvs.
- **Verify**: `bash scripts/verify-setup.sh` flags commits that never reached the SOT.

All of this is `scripts/lib/mirror.sh` (`ensure_mirror_worktree` - the name is historical),
driven by `scripts/setup-repos.sh` and `scripts/bootstrap.sh`.

## Why not `git worktree add /mnt/mirror/REPO`?

The earlier version of this repo did exactly that. Two problems, both measured:

1. A linked worktree keeps its own index, HEAD and per-worktree refs inside the SOT's
   `.git/worktrees/<id>/` on the share, and every command also reads the shared refs, config and
   packs from there: about 30 share round-trips per `git status` = 3 s.
2. The SOT is one `.git` shared by all your compute instances while `/mnt/mirror/REPO` is a
   per-instance path. Each instance registers the *same path*, so from any other instance the
   registration looks "prunable"; one `git worktree prune` (or an old `setup-repos.sh`) could
   detach a live mirror on another VM.

A clone has none of that: plain remotes, per-instance state, and the SOT is touched only by the
background push. `mirror.sh` converts legacy worktree mirrors automatically (clean ones are
replaced; ones with uncommitted changes are moved to `<mirror>.old-worktree-<timestamp>`).

## Manual equivalent (what the scripts do)

```bash
SOT=~/cloudfiles/code/Users/<you>/main/arrive-aml
git -C "$SOT" config receive.denyCurrentBranch updateInstead   # SOT may receive pushes to its checked-out branch
git clone -b main git@github.com:<team-org>/arrive-aml.git /mnt/mirror/arrive-aml   # or https://github.com/<team-org>/arrive-aml.git
cd /mnt/mirror/arrive-aml
git remote add sot "$SOT"
git fetch sot                                            # branches never pushed to GitHub
git config remote.pushDefault origin
git config checkout.defaultRemote origin
# hooks: .git/hooks/post-commit|post-merge|post-rewrite -> git push sot HEAD:<branch> (background)
```

## Daily workflow

```bash
cd /mnt/mirror/arrive-aml
git checkout -b feature/your-feature
# edit, test
git add -A && git commit -m "..."        # hook pushes to sot in the background
git push                                 # GitHub
```

Multiple branches side by side: `git worktree add /mnt/mirror/arrive-aml-feature1 feature/one`
*from the mirror* - that worktree's admin files live in the mirror's local `.git`, so it stays fast.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `/mnt/mirror` missing after restart | SSH in (login restores it), or `aml-bootstrap --restore` |
| `verify-setup.sh`: "N commit(s) not yet in the SOT" | `cd /mnt/mirror/REPO && git push sot HEAD`; check `~/.local/state/arrive-aml/sot-sync.log` |
| `! [rejected]` in the sync log | Another VM pushed that branch to the SOT: `git pull sot <branch>`, then commit again |
| Mirror dir exists but git errors | `aml-bootstrap --restore` moves it to `<mirror>.broken-<timestamp>` and re-clones |
| `git checkout foo` says ambiguous | Both remotes have `foo`; `checkout.defaultRemote=origin` is set by the scripts - re-run `aml-bootstrap --restore` |
| Slow git | You are in the SOT. `cd /mnt/mirror/REPO` |

## Best Practices

- Work only in `/mnt/mirror/REPO`; treat the SOT as a remote.
- Commit often: uncommitted edits are the only thing a `/mnt` wipe can take.
- `git push` to GitHub before stopping a VM you will not restart soon.
- Never `git worktree prune` inside a SOT by hand (other instances may still have legacy registrations).
- Open Cursor/VS Code (Remote-SSH) on `/mnt/mirror/REPO`, never on the share.
