# Azure ML Cloudfiles Paths

## Path Structure

Azure ML compute instances use different cloudfiles mount points:

### Default Azure ML Structure
```
~/cloudfiles/code/Users/USERNAME/
```

Example for user `rarko`:
```
~/cloudfiles/code/Users/rarko/main/
├── arrive-aml/
├── azureml-skills/
└── arrive-ds/
```

### Mount Points
`~/cloudfiles/code` is the workspace's Azure Files share (CIFS). The same share is also
mounted at
```
/mnt/batch/tasks/shared/LS_root/mounts/clusters/VMNAME/code
```
Both paths point at the same files. The share is mounted on **every compute instance you
own**, so a repo cloned there is visible from all of them. Files appear root-owned
(`chown` is a no-op on this mount); `configure-git.sh` sets `safe.directory *` so git accepts them.

## Canonical Location for Repositories

All team repositories should be in:
```
~/cloudfiles/code/Users/$USER/main/
```

**Why `/main` subdirectory?**
- Keeps main branch checkouts organized
- Allows for other branches in parallel directories if needed
- Matches git worktree best practices

## Auto-Detection

The scripts derive the SOT base from where the `arrive-aml` checkout's `.git` database
lives (`git rev-parse --git-common-dir`), so they work from the SOT and from a mirror:

1. `~/cloudfiles/code/Users/<aml-user>/main/arrive-aml` → SOT base `~/cloudfiles/code/Users/<aml-user>/main`
2. Override with `ARRIVE_SOT_BASE` (persisted in `~/.config/arrive-aml/env`)

Note that the Linux user is `azureuser` on every instance, while `<aml-user>` is your Azure ML
folder name (e.g. `rarko`) - do not use `$USER` for the cloudfiles path.

## Setup Commands

### For Azure ML VMs (Default)

```bash
# Clone arrive-aml (only if it is not already on the shared drive)
mkdir -p ~/cloudfiles/code/Users/rarko/main
cd ~/cloudfiles/code/Users/rarko/main
git clone git@github.com:rarko-arrive/arrive-aml.git

# Everything else
bash arrive-aml/scripts/bootstrap.sh
```

### Result

After `setup-repos.sh`:

```
~/cloudfiles/code/Users/rarko/main/
├── arrive-aml/          ← SOT (Source of Truth)
├── azureml-skills/      ← SOT
└── arrive-ds/           ← SOT

/mnt/mirror/
├── arrive-aml/          ← Fast mirror worktree
├── azureml-skills/      ← Fast mirror worktree
└── arrive-ds/           ← Fast mirror worktree
```

## Working Directory

**Always work in the mirror for fast git:**
```bash
cd /mnt/mirror/arrive-aml
# Git commands are <1 second here!
```

## Troubleshooting

### "detected dubious ownership" from git

```bash
bash scripts/lib/configure-git.sh    # sets safe.directory *
```

### Wrong Path Structure

If you cloned to the wrong location:

```bash
# Move to correct location
mkdir -p ~/cloudfiles/code/Users/rarko/main
mv /path/to/current/arrive-aml ~/cloudfiles/code/Users/rarko/main/
```

### Check Your Path

```bash
# See where cloudfiles points
ls -la ~ | grep cloudfiles

# Check your structure
ls -la ~/cloudfiles/code/Users/rarko/
```
