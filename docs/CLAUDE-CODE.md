# Claude Code + Azure ML Skills Setup

How Claude Code and the team skills library (`azureml-skills`) are installed on Azure ML VMs.

## TL;DR

Everything below is done by `bash scripts/bootstrap.sh`. To (re)do just this part:

```bash
bash scripts/lib/install-claude.sh          # installs `claude` into ~/.local/bin if missing
bash scripts/lib/install-claude-skills.sh   # clones/updates skills.conf repos, links skills
claude auth login                           # once per VM (or: claude setup-token)
```

## How skills are installed

`skills.conf` lists skill repositories (`REPO_URL|NAME`). For each one the installer:

1. clones it to `~/.claude/plugins/marketplaces/<NAME>` (OS disk, persists) or `git pull --ff-only`s it
2. symlinks every `skills/<skill>/` that has a `SKILL.md` into `~/.claude/skills/<skill>`

`azureml-skills` is a plugin repo with a `skills/` folder (not a marketplace), so this symlink
approach is what makes `/work-in-repo` available. No JSON editing is needed.

```bash
ls -la ~/.claude/skills/
# work-in-repo -> /home/azureuser/.claude/plugins/marketplaces/azureml-skills/skills/work-in-repo
```

## Using it

In Claude Code (`claude` in a terminal, or the Claude Code extension in Cursor/VS Code):

```
/work-in-repo
```

Then say what you want done. The skill works in `/mnt/mirror/<repo>`, creates a feature
branch, makes the change, runs tests, commits with attribution, pushes, and saves the plan
under `.ai/plans/`.

## Claude Code extension (Cursor / VS Code on your laptop)

Install the "Claude Code" extension in your **laptop** editor. When connected via Remote-SSH it
uses the `claude` binary on the VM, so the VM-side install and login above are what matter.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `/work-in-repo` not found | `bash scripts/lib/install-claude-skills.sh` then restart Claude Code |
| `claude: command not found` | `bash scripts/lib/install-claude.sh && source ~/.bashrc` |
| Not logged in | `claude auth login` (headless: open the URL on your laptop, paste the code) |
| Skills repo out of date | `bash scripts/lib/install-claude-skills.sh` (does `git pull --ff-only`) |
| Mirror broken or missing | `aml-bootstrap --restore` |

## Adding another skills repo

Append to `skills.conf`:

```
git@github.com:rarko-arrive/another-skills.git|another-skills
```

and run `bash scripts/lib/install-claude-skills.sh`.

## Resources

- Skills library: https://github.com/rarko-arrive/azureml-skills
- Worktree pattern: [docs/MIRROR-PATTERN.md](MIRROR-PATTERN.md)
- Setup: [README.md](../README.md), [FRESH-VM.md](FRESH-VM.md)
