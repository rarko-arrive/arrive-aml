# Setup details

README is the happy path. This page covers troubleshooting and Azure ML.

## Cursor notebooks won’t run (but VS Code does)

Cursor’s marketplace often lags VS Code on the **Python** extension. Older builds (`2025.4.x` / `2025.6.x`) can fail to activate:

`Cannot read properties of undefined (reading 'onDidChangeEnvironment')`

When Python fails, Jupyter has no kernel UI. VS Code works with Python **2026.4.0**.

**Fix:** use Python **2026.4.0+** in Cursor (same major as your working VS Code install). This machine was updated to `ms-python.python@2026.4.0` via VSIX. Then:

1. `Cmd+Shift+P` → **Developer: Reload Window**
2. Open `notebooks/DEMO.ipynb` → **Select Kernel** → **Python Environments** → `.venv`
3. **Output → Jupyter** should no longer show the activation error

Keep **Python**, **Python Environments**, and **Jupyter** enabled.

## Mac bootstrap details

`scripts/bootstrap-mac.sh` will:

1. Install Homebrew if missing and hint Apple Silicon `PATH` (`/opt/homebrew`)
2. `brew install git gh uv`
3. Set safe git defaults
4. Prompt for `user.name` / `user.email` only if unset
5. Run `gh auth login` when not already authenticated
6. Verify `gh api orgs/Arrive-Logistics`

### Optional: SSH

```bash
bash scripts/github-ssh.sh
```

## Common issues

**`brew: command not found` after install**

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
```

**`gh api orgs/Arrive-Logistics` fails**

Accept the org invite / authorize SSO, then:

```bash
gh auth refresh -h github.com -s read:org
```

**`uv sync` / Python version**

```bash
uv python install 3.13
uv sync
```

**Snowflake**

```bash
cp .env.example .env   # set SNOWFLAKE_PASSWORD
uv run python -c 'from arriveds.snowflake_utils import query_sf; print(query_sf("select 1 as x"))'
```

## Connect to Azure ML from Cursor

Most DS work happens on an Azure ML **compute instances**. Cursor connects with **Remote SSH**; Agent on the right then runs against the remote folder.

### A. Gather details from Azure ML (browser)

1. Open [Azure Machine Learning studio](https://ml.azure.com) → your workspace.
2. **Compute** → **Compute instances** → your instance → start it if needed.
3. Open **Details** / **SSH** and note:
   - **Public IP address**
   - **Port** (often `50000`)
   - **Username** (usually `azureuser`)
4. **Download the SSH private key** (`.pem`) once. Keep it private.

### B. One-time SSH setup on your Mac

```bash
cd /path/to/ds-cursor-demo
bash scripts/setup-azureml-ssh.sh
```

The script will ask for alias / IP / port / PEM path, then:

- copy the key to `~/.ssh/<name>.pem` (`chmod 400`; default = downloaded filename, e.g. `rarko.pem` — not necessarily the same Host alias)
- mirror the same key under gitignored `.ssh/<name>.pem` in this repo
- add a `Host` block to **`~/.ssh/config`** (what Cursor reads)
- write a gitignored copy at `.ssh/config` in this repo
- test `ssh <alias>`

Prefer editing [`.ssh/config.example`](.ssh/config.example) by hand? Copy to `.ssh/config`, fill placeholders, then still run the script (or paste the `Host` block into `~/.ssh/config` yourself).

### C. Cursor Remote SSH settings (required for this demo)

Plain `ssh YOUR-CI-ALIAS` can work while **Cursor** still fails. Cursor’s Remote SSH (`anysphere.remote-ssh`) installs a remote server over a SOCKS tunnel; that path is flaky on Azure ML after Cursor updates, even when VS Code Remote SSH works on the same host.

Merge [`.cursor/remote-ssh.settings.example.json`](.cursor/remote-ssh.settings.example.json) into **Cursor User settings** (`Cmd+,` → open the JSON). Replace `YOUR-CI-ALIAS` with your Host alias (e.g. `rarko1`):

```json
{
  "remote.SSH.remotePlatform": {
    "YOUR-CI-ALIAS": "linux"
  },
  "remote.SSH.remoteServerListenOnSocket": {
    "YOUR-CI-ALIAS": true
  },
  "remote.SSH.localServerDownload": "always",
  "remote.SSH.showLoginTerminal": false,
  "remote.SSH.enableAgentForwarding": false
}
```

| Setting | Why |
|---------|-----|
| `remotePlatform` | Skip OS probe; Azure ML compute is Linux. |
| `remoteServerListenOnSocket` | Use Unix-socket forwarding instead of SOCKS/`-D` (closer to VS Code). |
| `localServerDownload: always` | After a Cursor update, push the server from your Mac instead of downloading on the VM. |
| `showLoginTerminal: false` | Keep **off**. `true` wraps the install in a local interactive shell (`sh-3.2$`) and breaks the handshake. |
| `enableAgentForwarding: false` | Avoid askpass/agent interference during server install. |

These are **User** settings (local Mac), not repo-committed secrets. Re-apply after switching machines.

**Do not** pick `github.com` in **Remote-SSH: Connect to Host…** — that Host is only for `git` over SSH. Use your Azure ML alias (e.g. `rarko1`).

### D. Test the connection

Replace `YOUR-CI-ALIAS` with your Host alias (e.g. `rarko1`).

**1. Terminal** — proves host / key / IP still work:

```bash
ssh YOUR-CI-ALIAS 'echo OK && hostname && whoami'
```

**2. Cursor** — after merging section C into User settings:

1. Fully quit Cursor (`Cmd+Q`) and reopen
2. `Cmd+Shift+P` → **Remote-SSH: Connect to Host…** → `YOUR-CI-ALIAS`
3. **File → Open Folder…** → project path on the VM

Success: a remote Cursor window opens and Agent works on the right.

**3. If step 1 works but Cursor still fails** — wipe the remote Cursor server and retry step 2:

```bash
ssh YOUR-CI-ALIAS 'rm -rf ~/.cursor-server ~/.cursor-remote'
```

### E. Connect in Cursor (demo flow)

1. Install extension **Remote - SSH** (`anysphere.remote-ssh`) if prompted.
2. Complete [section D](#d-test-the-connection).
3. When the new window opens, **File → Open Folder…** on the VM (clone this repo there if needed).
4. Use **Agent** on the right — it edits/runs in that remote workspace.

### F. On the VM (first time)

```bash
cd /path/to/ds-cursor-demo   # cloudfiles copy or clone with gh
bash scripts/bootstrap-azureml.sh
```

`scripts/bootstrap-azureml.sh` will:

1. Install `uv` if missing and ensure `~/.local/bin` is on `PATH`
2. Create the project env on **local disk**: `~/uv-venvs/ds-cursor-demo`  
   (`cloudfiles` / Azure Files mounts are slow; `/mnt` can be wiped on recreate)
3. `uv sync` into that path
4. Symlink repo `.venv` → the local-disk env (so Cursor’s kernel picker matches the Mac happy path)
5. Smoke-test with `uv run hello`

After that, select **Python Environments → `.venv`** the same way as on Mac. Later `uv sync` / `uv run` follow the `.venv` symlink without setting `UV_PROJECT_ENVIRONMENT` again.

### Troubleshooting SSH

| Symptom | Fix |
|---------|-----|
| Connection timed out | Instance **Running**? IP/port match Details? IP changes after stop/start — re-run the script. |
| Permission denied (publickey) | Wrong `.pem`, or `chmod 400` not set. Use the key downloaded for **this** compute. |
| Host key changed | After recreate: `ssh-keygen -R '[IP]:PORT'` then connect again. |
| Cursor can’t see host | Confirm the `Host` alias exists in `~/.ssh/config` (`cat ~/.ssh/config`). |
| `ssh` works; Cursor fails with `Connection reset by peer` / Broken pipe | Apply [section C](#c-cursor-remote-ssh-settings-required-for-this-demo), then re-run [section D](#d-test-the-connection) (including the remote server wipe if needed). |
| Cursor connects then drops; VS Code works | Azure ML VMs often lack CPU PKU. On the remote, find `~/.cursor-server/bin/linux-x64/*/bin/cursor-server` and add `export NODE_OPTIONS="--no-node-snapshot --jitless"` before the last line (re-apply after Cursor updates the remote server). |
| Log shows `sh-3.2$` then reset | `showLoginTerminal` was on — set it to `false`, quit Cursor, retry. |
| Log says authority `github.com` | Wrong host selected. Connect to your Azure ML alias, not `github.com`. |

### Troubleshooting Azure ML env

| Symptom | Fix |
|---------|-----|
| `uv: command not found` | Open a new shell, or `source ~/.bashrc` (bootstrap adds `~/.local/bin`). |
| No `.venv` / wrong kernel path | Re-run `bash scripts/bootstrap-azureml.sh`. Kernel path should end with `.venv/bin/python`. |
| Slow `uv sync` / packages on cloudfiles | Env should live under `~/uv-venvs/…`, not inside the repo mount. Re-run bootstrap. |

Never commit `.ssh/config` or `*.pem` — only `.ssh/config.example` is tracked.
