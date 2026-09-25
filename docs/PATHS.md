# Azure ML Cloudfiles Paths

## Path Structure

Azure ML compute instances use different cloudfiles mount points:

### Default Azure ML Structure
```
~/cloudfiles/code/Users/USERNAME/
```

`USERNAME` is your Azure ML folder name, written `<you>` in these docs: the folder you see
under `Users/` in Azure ML Studio -> Notebooks. `~/cloudfiles/code/Users/` lists **every user in
the workspace**, so pick your own, not just the first one that exists.

Example for `<you>`:
```
~/cloudfiles/code/Users/<you>/main/
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
~/cloudfiles/code/Users/<you>/main/
```

**Why `/main` subdirectory?**
- Keeps main branch checkouts organized
- Allows for other branches in parallel directories if needed
- Keeps the SOT (remote `sot` of every mirror) separate from experiments

## Auto-Detection

The scripts derive the SOT base from where the `arrive-aml` checkout's `.git` database
lives (`git rev-parse --git-common-dir`), so they work from the SOT and from a mirror:

1. `~/cloudfiles/code/Users/<you>/main/arrive-aml` → SOT base `~/cloudfiles/code/Users/<you>/main`
2. Override with `ARRIVE_SOT_BASE` (persisted in `~/.config/arrive-aml/env`)

Note that the Linux user is `azureuser` on every instance, while `<you>` is your Azure ML
folder name - do not use `$USER` for the cloudfiles path. `get-started.sh` guesses `<you>` from
the instance name (instance `ctracy2` -> folder `ctracy`) and asks you to confirm;
`ARRIVE_AML_USER=<you>` skips the question.

Your answers from the setup wizard are also saved on the share, in
`~/cloudfiles/code/Users/<you>/main/.arrive-aml/profile`, so your other VMs do not ask again.

## Setup Commands

### For Azure ML VMs (Default)

```bash
# First VM: clone arrive-aml to your share and run the bootstrap (one command)
curl -fsSL https://raw.githubusercontent.com/<team-org>/arrive-aml/main/scripts/get-started.sh | bash

# arrive-aml already on the shared drive (second VM): just the bootstrap
bash ~/cloudfiles/code/Users/<you>/main/arrive-aml/scripts/bootstrap.sh
```

### Result

After `setup-repos.sh`:

```
~/cloudfiles/code/Users/<you>/main/
├── .arrive-aml/profile  ← your wizard answers (read by your other VMs)
├── arrive-aml/          ← SOT (Source of Truth)
├── azureml-skills/      ← SOT
└── arrive-ds/           ← SOT

/mnt/mirror/
├── arrive-aml/          ← Fast local mirror clone
├── azureml-skills/      ← Fast local mirror clone
└── arrive-ds/           ← Fast local mirror clone
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
mkdir -p ~/cloudfiles/code/Users/<you>/main
mv /path/to/current/arrive-aml ~/cloudfiles/code/Users/<you>/main/
```

### Wizard picked the wrong folder

Set `ARRIVE_SOT_BASE="/home/azureuser/cloudfiles/code/Users/<you>/main"` in
`~/.config/arrive-aml/env` and re-run `aml-bootstrap` (wrong name or email instead:
`aml-bootstrap --configure`).

### Check Your Path

```bash
# See where cloudfiles points
ls -la ~ | grep cloudfiles

# Check your structure
ls -la ~/cloudfiles/code/Users/<you>/
```
