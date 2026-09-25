# Getting started

About 15 minutes from a new compute instance to working in the team repos with Claude Code.
You answer two questions and approve one GitHub login. The rest is automatic.

## Before you start

- An Azure ML compute instance in the data-science workspace, running. Create one in
  Azure ML Studio → Compute; any size works. Name it after yourself (`ctracy1`) and the setup
  can guess your folder.
- A GitHub account that can read the team repos. `arrive-aml` is public, but `azureml-skills`
  and `arrive-ds` are private. Send your GitHub user name to the maintainer and accept the
  invitation email, or open https://github.com/rarko-arrive/arrive-ds to check. Without access,
  those two repos fail to clone and the setup tells you so. Everything else still works, and
  re-running `aml-bootstrap` after you have access fills them in.
- Your laptop's browser, for the one-time GitHub code.

## 1. Run one command

Open a terminal on the compute instance (Studio → Compute → your instance → **Terminal**,
or SSH/Cursor) and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/rarko-arrive/arrive-aml/main/scripts/get-started.sh | bash
```

## 2. Answer two questions

The setup first confirms your folder on the workspace share. This is the folder you see under
`Users/` in Studio → Notebooks, and your work lives there permanently:

```
  Your files live in a folder named after your Azure ML user, in
  /home/azureuser/cloudfiles/code/Users  (the folder you see under Users/ in Azure ML Studio → Notebooks).
  Your folder name [ctracy]:
```

Press Enter if the guess is right. The `Users/` folder lists everyone in the workspace, so make
sure it is yours. Next, you'll see:

```
  ┌────────────────────────────────────────────────────────────────┐
  │  Welcome to arrive-aml                                          │
  │  ...                                                            │
  └────────────────────────────────────────────────────────────────┘

  Your full name (for git commits): Colin Tracy
  Your work email [ctracy@arrivelogistics.com]:

    You          Colin Tracy <ctracy@arrivelogistics.com>
    Your files   ~/cloudfiles/code/Users/ctracy/main   (persistent, shared by all your VMs)
    Team repos   github.com/rarko-arrive: arrive-aml, azureml-skills, arrive-ds
    GitHub       you will log in once, in your browser

  Look right? [Y/n]:
```

Press Enter to continue. Answer `n` to change anything, including the team org and any extra
repos you want (`owner/name`).

## 3. Approve the GitHub login

A few minutes in, the setup pauses once for GitHub:

```
  GitHub login (once per VM)
  gh prints a one-time code. Open https://github.com/login/device on your
  laptop, paste the code and approve. ...
! First copy your one-time code: ABCD-1234
```

Open https://github.com/login/device on your laptop, paste the code, and approve. The VM then
uploads its own SSH key to your account and clones the team repos. You never copy a key by hand.

## 4. Done

The setup ends like this:

```
✓ Bootstrap complete. Your VM is ready, Colin.

  Work here (fast git):    cd /mnt/mirror/arrive-aml
  Claude Code (once/VM):   claude auth login
  Claude Code:             claude    then  /work-in-repo
```

Then run:

```bash
source ~/.bashrc
claude auth login
cd /mnt/mirror/arrive-ds && claude     # then type: /work-in-repo add a test for ...
```

## After that

| When | Do |
|---|---|
| Every day | Work in `/mnt/mirror/<repo>` (fast local clone). Commits reach your share in seconds, and `git push` goes to GitHub. See [WORKFLOW.md](WORKFLOW.md). |
| After a VM stop/start | Nothing. `/mnt` is wiped, and your next terminal restores the mirrors (about 1-2 minutes). |
| A second VM | `bash ~/cloudfiles/code/Users/<you>/main/arrive-aml/scripts/bootstrap.sh`. It reads your answers from your share and asks nothing except the GitHub code. |
| Wrong name, email or folder | `aml-bootstrap --configure` |
| Another repo on every VM | `bash ~/cloudfiles/code/Users/<you>/main/arrive-aml/scripts/setup-repos.sh --add owner/repo` |
| Something failed | Scroll up: every failed check prints its fix. Re-run `aml-bootstrap` at any time. More in [TROUBLESHOOTING.md](TROUBLESHOOTING.md). |
| Cursor / VS Code from your laptop | [SSH-SETUP-FROM-LAPTOP.md](SSH-SETUP-FROM-LAPTOP.md) |

## No questions (startup script, automation)

```bash
bash ~/cloudfiles/code/Users/<you>/main/arrive-aml/scripts/bootstrap.sh --yes \
  --name "First Last" --email you@arrivelogistics.com
```

`--yes` never waits for input. As an Azure ML startup script, run it as root; it switches to
`azureuser` by itself. See [FRESH-VM.md](FRESH-VM.md).
