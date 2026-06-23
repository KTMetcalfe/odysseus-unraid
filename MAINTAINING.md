# Maintaining

Notes for keeping `odysseus-omnibus` current.

## We build from a fork, not upstream directly
The image builds the Odysseus app from a **fork we control**
(`KTMetcalfe/odysseus`), not `pewdiepie-archdaemon/odysseus` directly. The fork
is a buffer: upstream is a single-maintainer repo whose default branch is `dev`
and which ships no releases/tags, so building straight off it means any bad
commit lands in our image. Routing through the fork lets us freeze, revert, or
patch before it reaches users - which is what makes auto-updating safe.

Two branches on the fork feed two image channels:

| Fork branch | Image tag | Updates | Who moves it |
|---|---|---|---|
| `main` | `:latest` | when you sync the fork after reviewing | **you, manually** |
| `track` | `:edge` | auto-mirrors upstream `main` | a sync action in the fork |

So the **stable** channel only advances when you deliberately sync the fork's
`main` from upstream (your trust gate), while the **edge** channel auto-tracks
upstream for testing what's coming. Both run through the fork; nothing builds
off `pewdiepie-archdaemon` straight.

### Fork setup (one-time)
1. Fork `pewdiepie-archdaemon/odysseus` to `KTMetcalfe/odysseus`. The Fork
   button copies `main`, so `:latest` can build immediately.
2. Create a `track` branch on the fork (from `main`). Until it exists, the
   `:edge` build is skipped (its merge step no-ops; see `build.yml`).
3. Add the auto-sync for `track` on a dedicated `automation` branch and make it
   the fork's **default branch** (scheduled Actions only run from the default
   branch, and this keeps `main` a pristine mirror). The workflow lives at
   `.github/workflows/sync-track.yml` on `automation` - copy it from
   `fork-templates/sync-track.yml` in this repo (see that folder's README for
   the exact commands). It force-mirrors `track` to upstream `main` daily on the
   fork's own built-in token (no PAT). Run it once from the Actions tab to
   populate `track`.
4. To advance **stable**, sync the fork's `main` from upstream (one-click
   *Sync fork*, since `main` carries no extra commits) when you've reviewed the
   diff, then run the omnibus `build` workflow (or wait for the weekly run).

> Order matters: create the fork (and `track`) **before** merging a change to
> `odysseus-unraid`'s `main`, or the first CI build has nothing to clone.

## Pinned versions and where they live
| Thing | File | How to bump |
|---|---|---|
| Odysseus app (source) | `image/Dockerfile` (`ODYSSEUS_REPO`) + per-channel ref from `build.yml` | advance the fork branch (`main`/`track`); not pinned to a SHA here |
| SearXNG | `image/Dockerfile` (`SEARXNG_REF`, top block) | change the commit/tag - **verify it boots first** (below) |
| ntfy | `image/Dockerfile` (`NTFY_VERSION`, top block) | bump the tag |
| chromadb | `image/Dockerfile` (`pip install chromadb`) | unpinned; pin if a release breaks the client |

The companion pins (`NTFY_VERSION`, `SEARXNG_REF`, and the `ODYSSEUS_REPO`
default) are grouped in one block at the top of `image/Dockerfile` - that block
is the single source of truth. `build.yml` does **not** override them; it only
sets the per-channel `ODYSSEUS_REF` (`main` for `:latest`, `track` for `:edge`).

The weekly workflow rebuilds both channels and also picks up base-image
(Debian/python) patches.

## Local build + smoke test (before pushing a change)
```sh
# build
docker build -t odysseus-omnibus:test image

# run with a throwaway volume
docker volume create omni-test
docker run -d --name omni -p 7797:7000 \
  -e PUID=1000 -e PGID=1000 -e ODYSSEUS_ADMIN_PASSWORD=testpass \
  -v omni-test:/app/data odysseus-omnibus:test
sleep 45

# all four services should be RUNNING
docker exec omni supervisorctl -c /etc/supervisor/supervisord.conf status

# app responds (302 = login redirect = healthy)
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:7797/

# bundled services reachable; app connected to chroma (look for "MemoryVectorStore ready")
docker exec omni python3 -c "import urllib.request,json; print('searxng', len(json.load(urllib.request.urlopen('http://127.0.0.1:8080/search?q=test&format=json',timeout=12)).get('results',[]))); print('chroma', urllib.request.urlopen('http://127.0.0.1:8000/api/v2/heartbeat',timeout=8).status)"
docker logs omni 2>&1 | grep -i "MemoryVectorStore ready"

# cleanup
docker rm -f omni && docker volume rm omni-test && docker rmi odysseus-omnibus:test
```
A bad **SearXNG** ref shows up as the `searxng` program flapping in
`supervisorctl status` and search returning nothing - that's why it's pinned and
tested before shipping.

## If upstream changes its Dockerfile
`image/Dockerfile` stage 1 mirrors upstream's build (its apt packages +
`pip install -r requirements.txt`). If upstream adds a system dependency or
changes how the app starts, reconcile stage 1 (and `image/svc-odysseus`, which
replicates the tail of upstream's entrypoint) accordingly.

## Architecture
Images are **multi-arch (amd64 + arm64)** and built in **two channels**
(`:latest`, `:edge`). The `build` job is a `channel x platform` matrix: each
arch builds on a native GitHub-hosted runner (`ubuntu-latest` /
`ubuntu-24.04-arm`) - no QEMU - then a per-channel `merge` job stitches that
channel's manifest list with `docker buildx imagetools`. `fail-fast: false`
keeps one channel building if the other's fork branch is missing.
The arm64 runner is free only in **public** repos; if you make the repo private,
drop the arm64 matrix entry (or pay for arm runners).

## Troubleshooting a running container
- `docker exec <c> supervisorctl -c /etc/supervisor/supervisord.conf status` - per-service state.
- `docker logs <c>` - all services' output is streamed here.
- To use an external service instead of a bundled one, set its `EMBED_*=false`
  and the matching `CHROMADB_HOST` / `SEARXNG_INSTANCE` / `NTFY_BASE_URL`.
