# SSH config for Azure ML

| File | Commit? | Purpose |
|------|---------|---------|
| [`config.example`](config.example) | yes | Template with placeholders |
| `config` | **no** | Your filled-in copy (gitignored) |
| `*.pem` | **no** | Private keys (never commit) |

Cursor’s Remote SSH extension reads **`~/.ssh/config`**, not this folder by itself. Use the setup script so your Mac and this repo stay aligned:

```bash
bash scripts/setup-azureml-ssh.sh
```

Then merge [../.cursor/remote-ssh.settings.example.json](../.cursor/remote-ssh.settings.example.json) into **Cursor User settings** (alias → `remotePlatform` + `remoteServerListenOnSocket`). Plain `ssh` working is not enough — Cursor needs those User settings for Azure ML.

Full walkthrough + troubleshooting: [../Setup.md](../Setup.md#connect-to-azure-ml-from-cursor).
