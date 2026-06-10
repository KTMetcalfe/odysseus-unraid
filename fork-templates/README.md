# Fork templates

These files do **not** run here. They belong in the Odysseus **fork**
(`KTMetcalfe/odysseus`) that the omnibus image builds from. They live in this
repo only so they're version-controlled and easy to copy.

## Fork branch layout

The fork keeps the sync automation off the branches we build from, so those
stay clean mirrors of upstream:

| Branch | Role | How it moves |
|---|---|---|
| `automation` (**default**) | hosts `sync-track.yml` | rarely; edit when the workflow changes |
| `main` | source for omnibus `:latest` | one-click **Sync fork** from upstream, after review |
| `track` | source for omnibus `:edge` | force-mirrored to upstream `main` by the workflow |

`automation` is the **default branch** because scheduled GitHub Actions only
run from the default branch. Keeping the workflow there (not on `main`) lets
`main` stay a pristine, one-click-syncable mirror of upstream.

> **Gotcha - the "N commits behind ...:dev" banner is cosmetic.** GitHub's
> ahead/behind banner compares against the *upstream parent's* default branch,
> which is `dev` - a different line from `main`. It does not reflect `main` or
> `track`, and nothing here builds from the default branch. To sync stable,
> switch the fork's branch dropdown to **`main`** first, *then* hit *Sync fork*
> (there it compares against upstream `main` and reads "up to date").

## `sync-track.yml`

Force-mirrors the fork's `track` branch to upstream
`pewdiepie-archdaemon/odysseus@main`. `track` feeds the omnibus `:edge` image
(see `../.github/workflows/build.yml`), so this is the automation behind the
auto-tracking channel.

**Install it in the fork (one-time):**

```sh
# from a clone of KTMetcalfe/odysseus
git checkout -b automation
mkdir -p .github/workflows
cp /path/to/odysseus-unraid/fork-templates/sync-track.yml .github/workflows/
git add .github/workflows/sync-track.yml
git commit -m "ci: mirror upstream main into track for omnibus :edge"
git push -u origin automation
# then in GitHub: Settings -> Branches -> set default branch to `automation`
```

It runs on the fork's own `GITHUB_TOKEN` (no PAT needed) because force-pushing
to a branch of the same repo only needs `contents: write`. After installing,
trigger it once via the Actions tab (*Run workflow*) so `track` is populated
immediately; thereafter it runs daily.

> `track` is a throwaway mirror - it is **force-updated** to upstream `main` on
> every run. Never commit to it directly. Your reviewed/stable line is the
> fork's `main`, which you advance with **Sync fork**.
