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

### Symbolic Link
`~/cloudfiles` is typically a symlink to:
```
/mnt/batch/tasks/shared/LS_root/mounts/clusters/VMNAME/
```

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

The `setup-repos.sh` script automatically detects your cloudfiles structure:

1. Checks if `~/cloudfiles/code/Users/$USER` exists (Azure ML default)
2. Falls back to `~/cloudfiles/rarko/main` (custom structure)
3. Creates the directory structure if it doesn't exist

## Setup Commands

### For Azure ML VMs (Default)

```bash
# Ensure proper ownership
sudo chown -R $USER:$USER ~/cloudfiles/code/Users/$USER

# Create main directory
mkdir -p ~/cloudfiles/code/Users/$USER/main

# Clone arrive-aml
cd ~/cloudfiles/code/Users/$USER/main
git clone git@github.com:rarko-arrive/arrive-aml.git
cd arrive-aml

# Setup all repos
bash scripts/setup-repos.sh
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

### Permission Denied

```bash
# Fix ownership
sudo chown -R $USER:$USER ~/cloudfiles/code/Users/$USER
```

### Wrong Path Structure

If you cloned to the wrong location:

```bash
# Move to correct location
mkdir -p ~/cloudfiles/code/Users/$USER/main
mv /path/to/current/arrive-aml ~/cloudfiles/code/Users/$USER/main/
```

### Check Your Path

```bash
# See where cloudfiles points
ls -la ~ | grep cloudfiles

# Check your structure  
ls -la ~/cloudfiles/code/Users/$USER/
```

## Documentation Updates Needed

Files that reference the old `~/cloudfiles/rarko/main` path:
- ✅ `scripts/setup-repos.sh` - Now auto-detects
- ⚠️ `test-happy-path.sh` - Shows actual path
- ⚠️ Documentation - Shows Azure ML default

The scripts now auto-detect and use the correct path!
