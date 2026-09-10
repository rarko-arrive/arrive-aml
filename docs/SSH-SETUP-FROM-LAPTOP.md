# SSH Setup: Connect from Your Laptop to Azure ML VMs

**This guide is for configuring SSH access FROM your MacBook TO Azure ML compute instances.**

## Where to Run What

```
┌─────────────────────────────────────────┐
│  Your MacBook                           │
│  - Clone arrive-aml locally             │
│  - Run: setup-azureml-ssh.sh           │  ← YOU ARE HERE
│  - Configure ~/.ssh/config              │
│  - Connect via Cursor Remote-SSH        │
└─────────────────────────────────────────┘
              │
              │ SSH Connection
              ↓
┌─────────────────────────────────────────┐
│  Azure ML VM (rarko1, rarko2, etc.)    │
│  - Run: setup-vm.sh --all              │
│  - Run: setup-mirror-worktree.sh       │
│  - Do your development work             │
└─────────────────────────────────────────┘
```

## Prerequisites

### On Your MacBook

1. **arrive-aml cloned locally**:
   ```bash
   cd ~/dev  # or wherever you keep projects
   git clone git@github.com:rarko-arrive/arrive-aml.git
   cd arrive-aml
   ```

2. **SSH key (.pem file)** downloaded from Azure:
   - Azure ML Portal → Compute → Your Instance → Details
   - Download SSH key
   - Save to `~/.ssh/rarko.pem`
   - Set permissions: `chmod 400 ~/.ssh/rarko.pem`

### From Azure ML Portal

Get these details for each VM:
- **Host alias**: What you'll type (e.g., `rarko1`, `rarko2`)
- **Public IP**: From VM Details tab
- **SSH Port**: Usually `50000`
- **Username**: Usually `azureuser`

## Setup Process (On Your MacBook)

### One-Time: First VM

```bash
# On your MacBook
cd ~/dev/arrive-aml

# Run the SSH setup script
bash scripts/setup-azureml-ssh.sh

# You'll be prompted:
SSH Host alias (short name in Cursor, e.g. rarko1): rarko1
Public IP from Azure ML Details tab: 20.123.45.67
SSH port [50000]: 50000
SSH user [azureuser]: azureuser
Path to downloaded .pem file: /Users/rarko/.ssh/rarko.pem

# Script will:
# 1. Copy .pem to ~/.ssh/rarko1.pem
# 2. Set correct permissions (chmod 400)
# 3. Add entry to ~/.ssh/config
# 4. Test connection
```

### Add More VMs

Run the script again for each new VM:

```bash
# On your MacBook
bash scripts/setup-azureml-ssh.sh

# Use a different alias each time:
SSH Host alias: rarko2
Public IP: 40.234.56.78
SSH port [50000]: 50000
SSH user [azureuser]: azureuser
Path to downloaded .pem file: /Users/rarko/.ssh/rarko.pem  # Can reuse same key!
```

## Result: Your SSH Config

After setup, your `~/.ssh/config` on MacBook will have:

```ssh
# Added by arrive-aml setup-azureml-ssh.sh
Host rarko1
    HostName 20.123.45.67
    Port 50000
    User azureuser
    IdentityFile ~/.ssh/rarko1.pem
    IdentitiesOnly yes

Host rarko2
    HostName 40.234.56.78
    Port 50000
    User azureuser
    IdentityFile ~/.ssh/rarko2.pem
    IdentitiesOnly yes
```

## Connect via Cursor/VS Code

### Cursor

1. Open Cursor on your MacBook
2. `Cmd+Shift+P` → "Remote-SSH: Connect to Host"
3. Select `rarko1` (or your alias)
4. New window opens connected to the VM
5. Open folder: `/mnt/mirror/arrive-aml` (for fast git)

### VS Code

Same process:
1. `Cmd+Shift+P` → "Remote-SSH: Connect to Host"
2. Select your VM alias
3. Open your project folder

## Test Connection Manually

```bash
# On your MacBook terminal
ssh rarko1

# You should be connected:
azureuser@rarko1:~$ pwd
/home/azureuser

# Exit
exit
```

## Reuse SSH Keys Across VMs

You can use the **same .pem file** for multiple VMs:

### Option 1: Azure Generates Key Once

1. Download .pem when creating first VM (rarko1)
2. Save to `~/.ssh/rarko.pem`
3. Extract public key:
   ```bash
   ssh-keygen -y -f ~/.ssh/rarko.pem > ~/.ssh/rarko.pub
   ```
4. When creating new VMs, paste `~/.ssh/rarko.pub` into Azure's SSH key field
5. Run `setup-azureml-ssh.sh` again, point to same .pem

### Option 2: Use Your Existing Key

If you already have an SSH key:

```bash
# Use your existing key
bash scripts/setup-azureml-ssh.sh
Path to downloaded .pem file: ~/.ssh/id_ed25519

# Copy your public key
cat ~/.ssh/id_ed25519.pub

# Paste into Azure when creating VM
```

See [REUSE-SSH-KEY.md](REUSE-SSH-KEY.md) for details.

## Troubleshooting

### "Permission denied (publickey)"

```bash
# Check permissions
ls -la ~/.ssh/rarko.pem
# Should be: -r-------- (400)

# Fix if needed
chmod 400 ~/.ssh/rarko.pem
```

### "Connection timeout"

1. Verify VM is running in Azure portal
2. Check public IP hasn't changed
3. Check port is 50000
4. Test manually: `ssh -vvv rarko1`

### "Host key verification failed"

VM was recreated with same name. Remove old key:

```bash
ssh-keygen -R rarko1
# Or
ssh-keygen -R 20.123.45.67
```

### Script Runs on VM by Mistake

If you accidentally run `setup-azureml-ssh.sh` on the Azure ML VM:

```
⚠️  WARNING: This script should run on your LAPTOP/Mac, not here!
```

The script will warn you. Exit and run on your MacBook instead.

## What NOT to Do

❌ **Don't run `setup-azureml-ssh.sh` on the Azure ML VM**
- It's for your laptop, not the VM

❌ **Don't run `setup-vm.sh` on your laptop**
- That's for configuring the Azure ML VM

❌ **Don't commit .pem files to git**
- They're secrets, .gitignore excludes them

## Summary

| Script | Where to Run | Purpose |
|--------|-------------|---------|
| `setup-azureml-ssh.sh` | **Your MacBook** | Configure SSH access TO VMs |
| `setup-vm.sh` | **Azure ML VM** | Configure the VM itself |
| `setup-mirror-worktree.sh` | **Azure ML VM** | Create fast local worktree |

**Remember**: 
- Laptop scripts = configure access
- VM scripts = configure environment

After SSH is set up on your MacBook, you can connect to VMs with Cursor Remote-SSH and work in `/mnt/mirror/` for fast git operations!
