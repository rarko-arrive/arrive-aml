# Arrive AML - Azure ML Development Environment Setup

Professional, comprehensive setup for Azure ML compute instances. Transform a fresh VM into a fully-configured development environment with a single command.

## Quick Start

```bash
# Clone this repository (or use existing clone)
git clone git@github.com:arrive-logistics/arrive-aml.git
cd arrive-aml

# Run the setup script - installs everything
bash scripts/setup-vm.sh --all

# Log out and back in (or source bashrc)
source ~/.bashrc
```

**That's it!** Your Azure ML VM is now configured with git optimization, development tools, and your preferred environment.

## What Gets Installed

| Tool | Description | Flag |
|------|-------------|------|
| **Git Optimization** | 10-50x faster git on Azure network storage (CRITICAL!) | `--git-optimize` |
| **System Tools** | git, curl, wget, htop, jq, tree, vim, build-essential | `--system-tools` |
| **uv** | Fast Python package manager | `--uv` |
| **GitHub CLI** | gh command-line tool | `--gh` |
| **GitHub SSH** | Automated SSH key setup for GitHub | `--github-ssh` |
| **Docker** | Docker Engine + docker-compose | `--docker` |
| **Claude CLI** | Anthropic Claude command-line interface | `--claude` |
| **VS Code** | Visual Studio Code (code command) | `--vscode` |
| **Cursor** | Cursor AI editor | `--cursor` |
| **Conda Disable** | Disables conda auto-activation (preserves install) | `--disable-conda` |

## Git Performance on Azure ML

**Problem**: Azure ML uses network-mounted storage (`~/cloudfiles/code/Users/`) which makes git operations 10-100x slower than local disk.

**Solution**: This setup applies 15+ git configuration optimizations specifically for network-mounted file systems:

- Disables expensive file monitoring (`core.fsmonitor false`)
- Optimizes index operations (`index.threads 4`, `feature.manyFiles true`)
- Disables automatic garbage collection (`gc.auto 0`)
- Increases network buffers
- And more...

**Expected improvement**: `git status` from 5-30 seconds → <1 second

## Prerequisites

- Fresh Ubuntu-based Azure ML compute instance
- Internet access
- Sudo privileges (script will prompt when needed)

## Usage Examples

### Complete Setup (Recommended)

Install everything with all default configurations:

```bash
bash scripts/setup-vm.sh --all
```

### Minimal Setup

Just git optimization and essential tools:

```bash
bash scripts/setup-vm.sh --git-optimize --system-tools --uv
```

### Selective Installation

Pick specific tools:

```bash
bash scripts/setup-vm.sh --git-optimize --docker --gh --github-ssh
```

### Interactive Mode

Answer prompts for each tool:

```bash
bash scripts/setup-vm.sh
```

### Dry Run

See what would be installed without making changes:

```bash
bash scripts/setup-vm.sh --dry-run --all
```

## Post-Installation

### Verify Setup

```bash
# Run verification script
bash scripts/verify-setup.sh

# Test git performance (should be < 1 second)
cd ~/cloudfiles/code/Users/rarko/dev/arrive-aml
time git status
```

### If You Installed Docker

Log out and back in, or run:

```bash
newgrp docker
```

Then test:

```bash
docker run hello-world
```

### If You Installed GitHub SSH

Your SSH key is at `~/.ssh/id_ed25519_github.pub`. If it wasn't automatically added to GitHub:

```bash
# Show your public key
cat ~/.ssh/id_ed25519_github.pub

# Add it at: https://github.com/settings/ssh/new
```

Test connection:

```bash
ssh -T git@github.com
```

### If You Installed Claude CLI

Configure with your API key:

```bash
claude configure
# Get your API key from: https://console.anthropic.com/settings/keys
```

## Python Development Setup

After the VM is configured, set up your Python environment:

```bash
# Run the Python/uv bootstrap
bash scripts/bootstrap-azureml.sh

# This creates a fast local-disk virtual environment and symlinks .venv
# (Avoids slow cloudfiles mounts for Python packages)
```

## SSH Access from Your Laptop

To connect to this Azure ML VM from your laptop with Cursor Remote-SSH:

```bash
# On your laptop (not the VM), run:
bash scripts/setup-azureml-ssh.sh
```

This configures your laptop's `~/.ssh/config` with the VM's connection details.

## Project Structure

```
arrive-aml/
├── README.md                       # This file
├── Setup.md                        # Detailed troubleshooting guide
├── scripts/
│   ├── setup-vm.sh                 # Master setup orchestrator
│   ├── verify-setup.sh             # Verification script
│   ├── bootstrap-azureml.sh        # Python environment setup
│   ├── setup-azureml-ssh.sh        # Laptop SSH configuration
│   └── lib/                        # Modular installers
│       ├── common.sh               # Shared utilities
│       ├── configure-git.sh        # Git performance optimization
│       ├── configure-github-ssh.sh # GitHub SSH setup
│       ├── disable-conda.sh        # Conda management
│       ├── install-*.sh            # Tool-specific installers
├── pyproject.toml                  # Python project configuration
├── .env.example                    # Environment template
└── .vscode/                        # VS Code/Cursor settings
```

## Troubleshooting

### Git Still Slow?

```bash
# Verify git config
git config --global --list | grep -E 'core\.fsmonitor|gc\.auto|feature\.manyFiles'

# Should see:
#   core.fsmonitor=false
#   gc.auto=0
#   feature.manyfiles=true

# Re-run git optimization if needed
bash scripts/lib/configure-git.sh
```

### Docker Permission Denied?

```bash
# Add yourself to docker group
sudo usermod -aG docker $USER

# Log out and back in, or:
newgrp docker
```

### Command Not Found After Install?

```bash
# Reload shell configuration
source ~/.bashrc

# Or log out and back in
```

### Conda Still Auto-Activating?

```bash
# Re-run conda disable
bash scripts/lib/disable-conda.sh

# Then open a new shell
```

## Manual Installation

If the automated setup fails, you can run individual installers:

```bash
# Git optimization (most important!)
bash scripts/lib/configure-git.sh

# System tools
bash scripts/lib/install-system-tools.sh

# Individual tools
bash scripts/lib/install-uv.sh
bash scripts/lib/install-gh.sh
bash scripts/lib/install-docker.sh
bash scripts/lib/install-claude.sh
bash scripts/lib/install-vscode.sh
bash scripts/lib/install-cursor.sh

# Configurations
bash scripts/lib/configure-github-ssh.sh
bash scripts/lib/disable-conda.sh
```

## Configuration Options

All flags for `setup-vm.sh`:

```
--all              Install everything (recommended)
--system-tools     Essential system utilities
--git-optimize     Git performance optimization (CRITICAL for Azure ML)
--uv               uv package manager
--gh               GitHub CLI
--github-ssh       GitHub SSH authentication
--disable-conda    Disable conda auto-activation
--docker           Docker Engine + docker-compose
--claude           Claude CLI
--vscode           Visual Studio Code
--cursor           Cursor Editor
--dry-run          Show what would be installed
-h, --help         Show help message
```

## Why This Matters

Azure ML compute instances come with basic tools but lack:

1. **Git performance optimization** - Network storage makes git painfully slow
2. **Modern development tools** - VS Code, Cursor, Claude CLI, etc.
3. **Proper GitHub integration** - SSH keys, gh CLI
4. **Docker support** - For containerized workflows
5. **Python environment best practices** - uv for fast package management

This setup solves all of these, providing a **professional, performant development environment** in < 10 minutes.

## For More Details

- See [Setup.md](Setup.md) for detailed troubleshooting and Azure ML specifics
- Run `bash scripts/setup-vm.sh --help` for all options
- Each script in `scripts/lib/` can be run independently

## Maintenance

Re-run the setup script anytime to update or add tools:

```bash
bash scripts/setup-vm.sh --all
```

The scripts are **idempotent** - safe to run multiple times.

---

**Created for**: rarko@arrivelogistics.com  
**Optimized for**: Azure ML compute instances  
**Result**: Simple, reliable, and a pleasure to use
