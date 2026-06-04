# Odysseus for Unraid (all-in-one)

An Unraid app for [PewDiePie's **Odysseus**](https://github.com/pewdiepie-archdaemon/odysseus) -
a self-hosted AI workspace (chat, autonomous agents, tools, deep research,
email, image generation, notes). Privacy-first, local-first; a self-hosted
alternative to hosted ChatGPT/Claude UIs and to tools like Open WebUI (formerly
Ollama WebUI).

Upstream ships only as a multi-service `docker compose` stack with no prebuilt
image. This repo repackages it as a **single all-in-one container** so it
installs from Community Applications in one click - the app plus its companion
services bundled together:

| | |
|---|---|
| **Image** | `ghcr.io/ktmetcalfe/odysseus-omnibus` |
| **Template** | `odysseus-omnibus.xml` |
| **Bundled** | Odysseus app (port 7000) · ChromaDB (memory) · SearXNG (web search, JSON enabled) · ntfy (notifications) |

> Odysseus does **not** include a model. Point it at your own LLM endpoint
> (Ollama / vLLM / llama.cpp / OpenAI-compatible API).

## Install

1. Install **odysseus-omnibus** from Community Applications (search "Odysseus").
2. Set **LLM Host** to your model server. The default `host.docker.internal`
   reaches the Unraid host (e.g. an Ollama on `11434`).
3. Open the WebUI at `http://SERVER-IP:7000`. If you left **Admin Password**
   blank, grab the generated one from the container log (search `password`), and
   change it in *Settings* after logging in.

No custom network, no companion containers - it's one container.

## Use your own services instead of the bundled ones

Bundled by default, but you're not locked in (GitLab-Omnibus style). To use an
external instance, set its toggle to `false` and fill the matching field:

| Turn off | Then set | Effect |
|---|---|---|
| `EMBED_CHROMA=false` | `CHROMADB_HOST` (+ `CHROMADB_PORT`) | use an external ChromaDB |
| `EMBED_SEARXNG=false` | `SEARXNG_INSTANCE` | use an external, JSON-enabled SearXNG |
| `EMBED_NTFY=false` | `NTFY_BASE_URL` | use an external ntfy |

Each disabled service simply isn't started; the app talks to your endpoint
instead. The app also degrades gracefully if a service is unreachable (memory /
search features go quiet, the app keeps running).

## GPU

You almost certainly **don't** need to give this container a GPU. Odysseus is a
front end that sends requests to a model server, so the GPU belongs to whatever
runs the model:

- **Recommended:** run Ollama / vLLM as its own container with the GPU, and
  point **LLM Host** here at it. This container stays CPU-only - nothing to do.
  (The bundled chromadb / searxng / ntfy and the local embedding fallback are
  all CPU.)
- **Only if** you use Odysseus's built-in model serving (it can install/run
  vLLM or llama.cpp inside this container) do you attach a GPU here. On Unraid:
  install the **Nvidia Driver** plugin (a one-time, host-level step needed for
  any GPU container), then add Extra Parameters `--runtime=nvidia` and env
  `NVIDIA_VISIBLE_DEVICES=<your GPU UUID>` + `NVIDIA_DRIVER_CAPABILITIES=all`.
  (AMD/ROCm instead uses `--device=/dev/dri`.) GPU params are not in the
  template by default, since they'd break installs on machines without one.

## How it's built

`image/Dockerfile` is self-contained and multi-stage:
1. **app** - builds the upstream Odysseus app exactly as upstream's Dockerfile
   does (pinned via `UPSTREAM_REF`).
2. **omnibus** - adds ChromaDB (`pip install chromadb`), a source-installed
   SearXNG (run via granian; it's not pip-installable as a wheel), and the ntfy
   binary, all supervised by **supervisord**. `image/entrypoint.sh` handles
   PUID/PGID, ownership repair, the `EMBED_*` toggles, and SearXNG secret
   generation, then execs supervisord. Per-service output streams to
   `docker logs`.

`.github/workflows/build.yml` builds and pushes
`ghcr.io/ktmetcalfe/odysseus-omnibus:latest` (multi-arch: amd64 + arm64),
weekly + on changes.

## Updating

- Template points at `:latest`; update via Unraid's *Check for Updates*.
- App version: bump `DEFAULT_UPSTREAM_REF` in the workflow (or dispatch with a
  ref); the weekly run otherwise tracks `main`.
- SearXNG: bump `SEARXNG_REF` in `image/Dockerfile` after verifying the new tag
  boots clean.

See `MAINTAINING.md` for upkeep — version bumps, local build + smoke test, and
troubleshooting.

## Credit & license

Odysseus © its authors, MIT License - see the upstream repo. This is an
independent community repackaging, not affiliated with or endorsed by the
upstream project. App bugs → upstream; Unraid/packaging issues → here.
