# Azure ML Skills Library - Publishing Instructions

## 📍 Repository Location

The `azureml-skills` repository is saved at:
- **Primary**: `~/cloudfiles/rarko/main/azureml-skills/`
- **Backup**: `~/azureml-skills/`

## 📝 Create the GitHub Repository

### 1. Create the Repo on GitHub

Go to: https://github.com/new

- **Repository name**: `azureml-skills`
- **Description**: `Reusable Claude Code skills for Python/Azure ML development workflows`
- **Visibility**: Public (so anyone with git access can install)
- **DO NOT** initialize with README, .gitignore, or license (we already have these)

### 2. Push the Repository

```bash
cd ~/cloudfiles/rarko/main/azureml-skills

# Verify remote is set
git remote -v
# Should show: git@github.com:rarko-arrive/azureml-skills.git

# Push to GitHub
git push -u origin main
```

## 📦 Installation Instructions (For Anyone)

Once pushed, anyone can install it!

### Quick Install Guide

1. **Add the marketplace** (edit `~/.claude/plugins/known_marketplaces.json`):

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

2. **Install the skill**:

```bash
/plugin install azureml-skills work-in-repo
```

3. **Use it**:

```bash
/work-in-repo
```

## 📚 What's Included

The repository at `~/cloudfiles/rarko/main/azureml-skills/` contains:

- ✅ `.claude-plugin/plugin.json` - Marketplace metadata
- ✅ `skills/work-in-repo/SKILL.md` - Complete 8-step workflow
- ✅ `skills/work-in-repo/references/worktree-commands.md` - Git worktree reference
- ✅ `QUICKSTART.md` - 5-minute intern-friendly guide
- ✅ `CHEATSHEET.md` - Daily reference
- ✅ `README.md` - Full documentation
- ✅ `INSTALL.md` - Detailed installation guide
- ✅ `LICENSE` - MIT License

## 🚀 Usage on rarko2 (Or Any Azure ML VM)

### First Time Setup

```bash
# 1. Add marketplace (edit ~/.claude/plugins/known_marketplaces.json)
# Add the JSON block shown above

# 2. Install skill
/plugin install azureml-skills work-in-repo

# 3. Verify
/plugin list
# Should show: work-in-repo (azureml-skills)
```

### Daily Workflow

```bash
# Just use the skill!
/work-in-repo

# Then tell Claude what you want to do:
# - "Add pytest infrastructure"
# - "Create a data pipeline"
# - "Fix bug in X"
```

Claude will automatically:
1. ✅ Setup mirror worktree if needed (`/mnt/mirror/REPO_NAME/`)
2. ✅ Work on fast local disk (100x faster git operations!)
3. ✅ Run tests
4. ✅ Commit with proper attribution
5. ✅ Push to remote
6. ✅ Save hardened plan to `.ai/plans/`

## 🔄 Repository Structure

```
~/cloudfiles/rarko/main/azureml-skills/
├── .claude-plugin/
│   └── plugin.json          # rarko-arrive/azureml-skills
├── skills/
│   └── work-in-repo/
│       ├── SKILL.md
│       └── references/
│           └── worktree-commands.md
├── CHEATSHEET.md
├── QUICKSTART.md
├── README.md
├── INSTALL.md
└── LICENSE

Git remote: git@github.com:rarko-arrive/azureml-skills.git
```

## 💡 Quick Commands

```bash
# Navigate to repo
cd ~/cloudfiles/rarko/main/azureml-skills

# Check status
git status

# Push to GitHub (after creating repo)
git push -u origin main

# View files
ls -la

# Read documentation
cat QUICKSTART.md
cat INSTALL.md
```

## 🐛 Troubleshooting

### Can't find the repository

```bash
# It's here:
ls -la ~/cloudfiles/rarko/main/azureml-skills/

# Or backup:
ls -la ~/azureml-skills/
```

### Skills not installing

```bash
# Verify marketplace registration
cat ~/.claude/plugins/known_marketplaces.json | grep azureml-skills

# Reinstall
/plugin install azureml-skills work-in-repo
```

### Mirror worktree issues

```bash
# Reset mirror
cd ~/cloudfiles/rarko/main/REPO_NAME
git worktree remove --force /mnt/mirror/REPO_NAME
rm -rf /mnt/mirror/REPO_NAME
git worktree add /mnt/mirror/REPO_NAME
```

## 📞 Support

- **GitHub**: https://github.com/rarko-arrive/azureml-skills
- **Issues**: https://github.com/rarko-arrive/azureml-skills/issues
- **Internal**: Ask Rick Arko (@rarko)

---

**Next Step**: Create the GitHub repo and run:
```bash
cd ~/cloudfiles/rarko/main/azureml-skills && git push -u origin main
```
