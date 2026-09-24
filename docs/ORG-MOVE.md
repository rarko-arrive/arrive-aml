# Moving the team repos to another GitHub org

The team repos (arrive-aml, azureml-skills, arrive-ds) live in `rarko-arrive` today and will move
to [`Arrive-Logistics`](https://github.com/Arrive-Logistics). The org name appears in code in one place.
Every VM picks up the new name the next time it runs `aml-bootstrap`.

## Checklist

1. **Transfer the repos** on GitHub: Settings → Transfer, one repo at a time. Give the data-science
   team at least read access to all three. GitHub redirects the old URLs, so existing clones keep
   working while you finish the rest.
2. **Flip the default** in `scripts/lib/common.sh`:
   ```bash
   ARRIVE_DEFAULT_GITHUB_ORG="Arrive-Logistics"
   ```
   `repos.conf` and `skills.conf` use `{org}`, so no entry changes.
3. **Update the four remaining mentions** (`bash tests/lint.sh` lists them):
   - `scripts/get-started.sh`: the `ORG=` default and the URL in the header comment
   - `README.md` and `docs/GETTING-STARTED.md`: the `curl ... get-started.sh` one-liner
   - `pyproject.toml`: the `arriveds` source URL. Then run `uv lock` and commit `uv.lock`.
4. **The one-liner needs a login once the repos are private.** `raw.githubusercontent.com` does
   not serve private repos anonymously. Change the first-run instructions to:
   ```bash
   gh auth login --web -s admin:public_key
   gh api repos/Arrive-Logistics/arrive-aml/contents/scripts/get-started.sh -H 'Accept: application/vnd.github.raw' | bash
   ```
   `get-started.sh` clones over https, which works after `gh auth login` because it runs
   `gh auth setup-git`. If gh's credential helper isn't set yet, run `gh auth setup-git` first.
5. **Merge, then run `aml-bootstrap`** on one VM. `verify-setup.sh` notes any mirror whose `origin`
   still points at the old org. Switching is optional, because redirects keep working:
   ```bash
   git -C /mnt/mirror/arrive-ds remote set-url origin git@github.com:Arrive-Logistics/arrive-ds.git
   ```
   The SOT clones on the share keep their old `origin` URL. That is harmless for the same reason.

## Who is affected

- **Everyone on the team default:** nothing to do. The wizard only saves `ARRIVE_GITHUB_ORG` to
  `~/.config/arrive-aml/env` when someone chose a different org, so the new default reaches everyone else.
- **Anyone who pinned an org** (`aml-bootstrap --github-org X`, or answered the wizard's org question):
  their choice stays. To return to the team default, run `aml-bootstrap --configure` and accept the default.
