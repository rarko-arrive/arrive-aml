# Happy Path - Fresh Azure ML VM Setup

Complete step-by-step guide for setting up a fresh Azure ML compute instance.

## Prerequisites

- Azure ML compute instance (Ubuntu)
- SSH access to the VM
- GitHub account with SSH key configured

## Step-by-Step Setup

### 1. Fix Cloudfiles Ownership

```bash
# Fix ownership of your cloudfiles directory
sudo chown -R $USER:$USER ~/cloudfiles/code/Users/$USER
```

### 2. Create Main Directory Structure

```bash
# Create the main directory for repositories
mkdir -p ~/cloudfiles/code/Users/$USER/main
cd ~/cloudfiles/code/Users/$USER/main
```

### 3. Clone arrive-aml

```bash
# Clone the setup repository
git clone git@github.com:rarko-arrive/arrive-aml.git
cd arrive-aml
```

**If SSH fails**, configure GitHub SSH first:
```bash
# Run the SSH setup from arrive-aml
bash scripts/lib/configure-github-ssh.sh

# Test connection
ssh -T git@github.com
# Should show: "Hi rarko-arrive! You've successfully authenticated"
```

### 4. Run Full VM Setup (Optional but Recommended)

```bash
# Install all development tools
bash scripts/setup-vm.sh --all

# This installs:
# - Git optimization (2-4x faster)
# - System tools (curl, wget, htop, jq, tree, vim)
# - uv (Python package manager)
# - GitHub CLI (gh)
# - Docker & docker-compose
# - VS Code
# - Cursor (optional, may fail - that's OK)
```

### 5. Setup All Team Repositories

```bash
# Automatically clone and mirror all configured repos:
# - arrive-aml (this repo)
# - azureml-skills (Claude Code skills)
# - arrive-ds (data science utilities)

bash scripts/setup-repos.sh
```

**Expected output:**
```
==> Setting up repositories from repos.conf

==> Processing: arrive-aml
✓ Repository already exists at SOT
✓ Mirror created: /mnt/mirror/arrive-aml

==> Processing: azureml-skills
✓ Cloned azureml-skills
✓ Mirror created: /mnt/mirror/azureml-skills

==> Processing: arrive-ds
✓ Cloned arrive-ds
✓ Mirror created: /mnt/mirror/arrive-ds

==================================================================
✓ Repository setup complete!

Summary:
  Cloned: 2 new repositories
  Mirrors: 3 worktrees created
  Skipped: 1 existing repositories
==================================================================
```

### 6. Install Claude CLI (Optional)

```bash
# Install Claude Code CLI
curl -fsSL https://claude.ai/install.sh | sh

# Restart shell or source bashrc
source ~/.bashrc

# Verify
claude --version
```

### 7. Verify Setup

```bash
# Run the test script
cd ~/cloudfiles/code/Users/$USER/main/arrive-aml
./test-happy-path.sh
```

**All tests should pass:**
- ✅ GitHub SSH working
- ✅ Mirror directory setup
- ✅ Repository in canonical location
- ✅ Git performance acceptable
- ✅ azureml-skills accessible
- ✅ Documentation files present
- ✅ Mirror worktrees created

### 8. Install Claude Code Extension + Skills

**In VS Code or Cursor:**

1. Install Claude Code extension (Ctrl+Shift+X, search "Claude Code")
2. Sign in with Anthropic account

**Add azureml-skills marketplace:**

Edit `~/.claude/plugins/known_marketplaces.json`:
```json
{
  "azureml-skills": {
    "source": {
      "source": "github",
      "repo": "rarko-arrive/azureml-skills"
    },
    "installLocation": "/home/azureuser/.claude/plugins/marketplaces/azureml-skills",
    "lastUpdated": "2026-09-11T00:00:00.000Z"
  }
}
```

**Install the main skill:**
```bash
# In Claude Code (in your IDE):
/plugin install azureml-skills work-in-repo

# Verify:
/plugin list
```

### 9. Start Working!

**Always work in the mirrors for fast git:**
```bash
cd /mnt/mirror/arrive-aml
# Git operations are <1 second here!

# Or use Claude Code:
/work-in-repo
# Tell Claude what to do, it handles everything!
```

## What You Get

After completing the happy path:

### Repository Structure
```
~/cloudfiles/code/Users/rarko/main/
├── arrive-aml/          ← SOT (Source of Truth)
├── azureml-skills/      ← SOT (Claude skills)
└── arrive-ds/           ← SOT (Data science utils)

/mnt/mirror/
├── arrive-aml/          ← Fast mirror (100x faster git!)
├── azureml-skills/      ← Fast mirror
└── arrive-ds/           ← Fast mirror
```

### Performance Comparison

| Location | Git Status | Use For |
|----------|-----------|---------|
| `~/cloudfiles/.../main/REPO/` | 7-30 seconds | Backup only |
| `/mnt/mirror/REPO/` | <1 second | All development |

### Installed Tools

- ✅ Git (optimized for network storage)
- ✅ uv (fast Python package manager)
- ✅ GitHub CLI (gh)
- ✅ Docker & docker-compose
- ✅ Claude CLI (optional)
- ✅ VS Code / Cursor
- ✅ Claude Code extension
- ✅ azureml-skills library

## Common Issues & Fixes

### Permission Denied on Cloudfiles

```bash
sudo chown -R $USER:$USER ~/cloudfiles/code/Users/$USER
```

### GitHub SSH Not Working

```bash
# Restart SSH agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519_github

# Test
ssh -T git@github.com
```

### Repository in Wrong Location

```bash
# Move to correct location
mkdir -p ~/cloudfiles/code/Users/$USER/main
mv /old/path/arrive-aml ~/cloudfiles/code/Users/$USER/main/
```

### Mirror Worktree Issues

```bash
# Reset mirror
cd ~/cloudfiles/code/Users/$USER/main/REPO
git worktree remove --force /mnt/mirror/REPO
rm -rf /mnt/mirror/REPO
git worktree add /mnt/mirror/REPO
```

### Claude CLI Not Found

```bash
# Install manually
curl -fsSL https://claude.ai/install.sh | sh
source ~/.bashrc
```

## Quick Copy-Paste (All Commands)

```bash
# Complete setup in one go:
sudo chown -R $USER:$USER ~/cloudfiles/code/Users/$USER && \
mkdir -p ~/cloudfiles/code/Users/$USER/main && \
cd ~/cloudfiles/code/Users/$USER/main && \
git clone git@github.com:rarko-arrive/arrive-aml.git && \
cd arrive-aml && \
bash scripts/setup-vm.sh --all && \
bash scripts/setup-repos.sh && \
echo "✅ Setup complete! Read CLAUDE-SETUP.md for next steps."
```

## Next Steps

1. **Read CLAUDE-SETUP.md** - Claude Code integration
2. **Read docs/AZUREML-WORKTREE-PATTERN.md** - Deep dive on worktrees
3. **Read docs/REPOS-CONFIG.md** - Customize repos.conf
4. **Try /work-in-repo** - Experience the automated workflow!

## Documentation

- **CLAUDE-SETUP.md** - Claude Code + skills installation
- **AZURE-ML-PATHS.md** - Path structure explained
- **docs/REPOS-CONFIG.md** - Repository configuration
- **docs/AZUREML-WORKTREE-PATTERN.md** - Worktree pattern details
- **test-happy-path.sh** - Automated verification script

## Support

- **GitHub**: https://github.com/rarko-arrive/arrive-aml
- **Skills**: https://github.com/rarko-arrive/azureml-skills
- **Internal**: Ask Rick Arko (@rarko) or #data-science-infra

---

**Time to complete**: ~10 minutes  
**Result**: Fully configured Azure ML development environment with fast git operations!
