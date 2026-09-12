# Claude Code + Azure ML Skills Setup

Quick reference for installing Claude Code and the azureml-skills library on Azure ML VMs.

## Prerequisites

✅ Run `bash scripts/setup-vm.sh --all` first (installs Claude CLI and other tools)

## Step 1: Install Claude Code Extension

### In VS Code or Cursor:
1. Open Extensions (Ctrl+Shift+X)
2. Search for "Claude Code"
3. Click Install
4. Sign in with your Anthropic account

### Via Command Line:
```bash
# VS Code
code --install-extension anthropic.claude-code

# Cursor  
cursor --install-extension anthropic.claude-code
```

## Step 2: Register Azure ML Skills Marketplace

Edit `~/.claude/plugins/known_marketplaces.json` and add:

```json
{
  "claude-plugins-official": {
    ...existing content if any...
  },
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

**If file doesn't exist**, create it with just:
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

## Step 3: Install the Main Skill

In Claude Code (in your IDE), type:

```bash
/plugin install azureml-skills work-in-repo
```

Verify it's installed:
```bash
/plugin list
```

You should see: `work-in-repo (azureml-skills)`

## Step 4: Start Using It!

### Basic Usage

Open Claude Code and type:
```bash
/work-in-repo
```

Then tell Claude what you want to do:
- "Add pytest infrastructure to this project"
- "Create a new data processing module"
- "Fix the bug in utils.py"
- "Add type hints and docstrings to all functions"

### What Happens Automatically

Claude will:
1. ✅ Ensure repo is in SOT location (`~/cloudfiles/rarko/main/REPO/`)
2. ✅ Create mirror worktree (`/mnt/mirror/REPO/`)
3. ✅ Create feature branch
4. ✅ Make your requested changes
5. ✅ Run tests to verify
6. ✅ Commit with proper message and attribution
7. ✅ Push to GitHub
8. ✅ Save detailed plan to `.ai/plans/cc-skill-work-in-repo-*.md`

### Example Session

```
You: /work-in-repo

Claude: What would you like to work on?

You: Add pytest infrastructure with fixtures for Azure ML workspace testing

Claude: I'll set up the mirror worktree and add pytest infrastructure...

[Claude works...]

✅ Done! Created:
- tests/conftest.py with Azure ML fixtures
- tests/test_example.py with sample tests
- pytest.ini configuration
- Updated pyproject.toml with test dependencies

Committed and pushed to feature/add-pytest-infrastructure
Plan saved to .ai/plans/cc-skill-work-in-repo-add-pytest-infrastructure.md
```

## Performance Benefits

| Location | Git Status Time | Use For |
|----------|----------------|---------|
| `~/cloudfiles/rarko/main/REPO/` | 7-30 seconds | Backup only (SOT) |
| `/mnt/mirror/REPO/` | <1 second | All development work |

**Result**: 100x faster development workflow!

## Troubleshooting

### Skills not showing up

```bash
# Check marketplace registration
cat ~/.claude/plugins/known_marketplaces.json | grep azureml-skills

# If not found, add it (see Step 2 above)

# Then reinstall
/plugin install azureml-skills work-in-repo
```

### Mirror worktree issues

```bash
# Reset mirror
cd ~/cloudfiles/rarko/main/REPO
git worktree remove --force /mnt/mirror/REPO
rm -rf /mnt/mirror/REPO

# Then use /work-in-repo again and it will recreate
```

### Claude CLI not found

```bash
# Reinstall Claude CLI
bash scripts/setup-vm.sh --claude

# Or manually
curl -fsSL https://claude.ai/install.sh | sh
```

## Additional Skills (Coming Soon)

- `/python-testing` - Setup pytest infrastructure
- `/package-scaffolding` - Create proper Python package structure
- `/env-validation` - Environment variable validation
- `/azureml-jobs` - Azure ML job creation
- `/data-pipelines` - Snowflake → processing workflows

## Resources

- **Skills Library**: https://github.com/rarko-arrive/azureml-skills
- **Worktree Pattern**: [docs/AZUREML-WORKTREE-PATTERN.md](docs/AZUREML-WORKTREE-PATTERN.md)
- **Claude Code Docs**: https://claude.ai/code
- **Arrive AML Setup**: [README.md](README.md)

## Quick Copy-Paste Blocks

### Full Marketplace JSON (for ~/.claude/plugins/known_marketplaces.json)
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

### Install Command
```bash
/plugin install azureml-skills work-in-repo
```

### Verify Command
```bash
/plugin list
```

### Use Command
```bash
/work-in-repo
```

---

**Questions?** Ask Rick Arko (@rarko) or check #data-science-infra on Slack.
