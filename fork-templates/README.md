# Fork templates

These files do **not** run here. They belong in the Odysseus **fork**
(`KTMetcalfe/odysseus`) that the omnibus image builds from. They live in this
repo only so they're version-controlled and easy to copy.

## `sync-track.yml`

Keeps the fork's `track` branch mirrored to upstream
`pewdiepie-archdaemon/odysseus@main`. `track` feeds the omnibus `:edge` image
(see `../.github/workflows/build.yml`), so this is the automation behind the
auto-tracking channel.

**Install it in the fork:**

```sh
# from a clone of KTMetcalfe/odysseus
mkdir -p .github/workflows
cp /path/to/odysseus-unraid/fork-templates/sync-track.yml .github/workflows/
git add .github/workflows/sync-track.yml
git commit -m "ci: mirror upstream main into track for omnibus :edge"
git push
```

It runs on the fork's own `GITHUB_TOKEN` (no PAT needed) because force-pushing
to a branch of the same repo only needs `contents: write`. After installing,
trigger it once via the Actions tab (*Run workflow*) so `track` is populated
immediately; thereafter it runs daily.

> `track` is a throwaway mirror - it is **force-updated** to upstream `main` on
> every run. Never commit to it directly. Your reviewed/stable line is the
> fork's `main`, which you advance manually.
