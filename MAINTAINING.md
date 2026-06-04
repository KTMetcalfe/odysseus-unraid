# Maintaining

Notes for keeping `odysseus-omnibus` current.

## Pinned versions and where they live
| Thing | File | How to bump |
|---|---|---|
| Odysseus app | `.github/workflows/build.yml` (`DEFAULT_UPSTREAM_REF`) | change ref, or *Run workflow* with a ref; weekly run otherwise tracks `main` |
| SearXNG | `image/Dockerfile` (`SEARXNG_REF`) | change the commit/tag — **verify it boots first** (below) |
| ntfy | `image/Dockerfile` (`FROM …/ntfy:vX.Y.Z`) | bump the tag |
| chromadb | `image/Dockerfile` (`pip install chromadb`) | unpinned; pin if a release breaks the client |

The weekly workflow rebuilds and also picks up base-image (Debian/python) patches.

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
`supervisorctl status` and search returning nothing — that's why it's pinned and
tested before shipping.

## If upstream changes its Dockerfile
`image/Dockerfile` stage 1 mirrors upstream's build (its apt packages +
`pip install -r requirements.txt`). If upstream adds a system dependency or
changes how the app starts, reconcile stage 1 (and `image/svc-odysseus`, which
replicates the tail of upstream's entrypoint) accordingly.

## Architecture
Images are **multi-arch (amd64 + arm64)**. The workflow builds each arch on a
native GitHub-hosted runner (`ubuntu-latest` / `ubuntu-24.04-arm`) — no QEMU —
then a `merge` job stitches the manifest list with `docker buildx imagetools`.
The arm64 runner is free only in **public** repos; if you make the repo private,
drop the arm64 matrix entry (or pay for arm runners).

## Troubleshooting a running container
- `docker exec <c> supervisorctl -c /etc/supervisor/supervisord.conf status` — per-service state.
- `docker logs <c>` — all services' output is streamed here.
- To use an external service instead of a bundled one, set its `EMBED_*=false`
  and the matching `CHROMADB_HOST` / `SEARXNG_INSTANCE` / `NTFY_BASE_URL`.
