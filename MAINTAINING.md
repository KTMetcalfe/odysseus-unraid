# Maintaining

Notes for keeping `odysseus-omnibus` current.

## Two channels, two sources
The image ships in two channels with **different sources** (set per-channel in
`build.yml`'s matrix):

| Image tag | Source | Updates | Who moves it |
|---|---|---|---|
| `:latest` | **fork** `KTMetcalfe/odysseus@main` | when you Sync-fork after reviewing | **you, manually** |
| `:edge` | **upstream** `pewdiepie-archdaemon/odysseus@main` | every build (no review) | upstream |

Only `:latest` routes through the fork. The fork is a **buffer** for the stable
channel: upstream is a single-maintainer repo whose default branch is `dev` and
which ships no releases/tags, so a bad commit could otherwise land straight in
the stable image. Syncing the fork's `main` is your deliberate trust gate.

`:edge` is the deliberately-unreviewed channel, so it builds **straight from
upstream** - the fork buffer would add nothing there. (An earlier design mirrored
upstream into a fork `track` branch, but GitHub blocks the built-in Actions token
from pushing the workflow files upstream ships, so that auto-sync wasn't viable
without a PAT - and edge gains nothing from the fork anyway.)

### Fork setup (one-time)
1. Fork `pewdiepie-archdaemon/odysseus` to `KTMetcalfe/odysseus`. The Fork
   button copies `main`, which is all `:latest` needs. Keep `main` as the fork's
   default branch.
2. To advance **stable**, Sync-fork the fork's `main` from upstream (one-click,
   since `main` carries no extra commits) when you've reviewed the diff, then run
   the omnibus `build` workflow (or wait for the weekly run).

No `track` branch, `automation` branch, or sync workflow is needed.

> Order matters: create the fork **before** merging a change to
> `odysseus-unraid`'s `main`, or the first `:latest` build has nothing to clone.

## Pinned versions and where they live
| Thing | File | How to bump |
|---|---|---|
| Odysseus app (source) | per-channel `repo`/`ref` in `build.yml` | `:latest` advances when you Sync-fork; `:edge` tracks upstream `main` automatically |
| SearXNG | `image/Dockerfile` (`SEARXNG_REF`, top block) | change the commit/tag - **verify it boots first** (below) |
| ntfy | `image/Dockerfile` (`NTFY_VERSION`, top block) | bump the tag |
| chromadb | `image/Dockerfile` (`pip install chromadb`) | unpinned; pin if a release breaks the client |

The companion pins (`NTFY_VERSION`, `SEARXNG_REF`) and the default
`ODYSSEUS_REPO` are grouped in one block at the top of `image/Dockerfile` - that
block is the single source of truth for local builds. `build.yml` overrides
`ODYSSEUS_REPO`/`ODYSSEUS_REF` per channel but does **not** touch the companion
pins.

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
keeps one channel building if the other's source is unavailable.
The arm64 runner is free only in **public** repos; if you make the repo private,
drop the arm64 matrix entry (or pay for arm runners).

## Troubleshooting a running container
- `docker exec <c> supervisorctl -c /etc/supervisor/supervisord.conf status` - per-service state.
- `docker logs <c>` - all services' output is streamed here.
- To use an external service instead of a bundled one, set its `EMBED_*=false`
  and the matching `CHROMADB_HOST` / `SEARXNG_INSTANCE` / `NTFY_BASE_URL`.
