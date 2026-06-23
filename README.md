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

Odysseus runs fine CPU-only, but it has two GPU-aware features, so you may want
to expose your NVIDIA GPU to the container:

- **Hardware scanning.** Odysseus inspects the hardware it can see to give
  hardware-aware model recommendations. Without GPU passthrough it only sees the
  CPU and RAM, so its suggestions assume no GPU - even if a separate Ollama is
  doing the actual inference.
- **Built-in model serving.** Its Cookbook can install and run vLLM or
  llama.cpp *inside* this container, which needs the GPU to run models.

(If you point **LLM Host** at a separate Ollama/vLLM container that owns the
GPU, inference already happens there; passing a GPU here is then only for the
hardware scan, and is optional.)

To expose an NVIDIA GPU on Unraid:
1. Install the **Nvidia Driver** plugin from Community Apps (one-time,
   host-level; needed for any GPU container).
2. On this container, add **Extra Parameters** `--gpus=all` (or the
   Unraid-native `--runtime=nvidia`) and env vars
   `NVIDIA_VISIBLE_DEVICES=all` (or a specific GPU UUID) and
   `NVIDIA_DRIVER_CAPABILITIES=all`.

(AMD/ROCm instead uses `--device=/dev/dri`.) These aren't in the template by
default, since they'd break installs on boxes without a GPU or the driver.

## How it's built

The Odysseus app is built from a **fork we control**
(`KTMetcalfe/odysseus`), not upstream directly - a buffer so upstream changes
only reach the image once we've let them through (see `MAINTAINING.md`).

`image/Dockerfile` is self-contained and multi-stage:
1. **app** - builds the Odysseus app from the fork exactly as upstream's
   Dockerfile does (source + ref via `ODYSSEUS_REPO` / `ODYSSEUS_REF`).
2. **omnibus** - adds ChromaDB (`pip install chromadb`), a source-installed
   SearXNG (run via granian; it's not pip-installable as a wheel), and the ntfy
   binary, all supervised by **supervisord**. `image/entrypoint.sh` handles
   PUID/PGID, ownership repair, the `EMBED_*` toggles, and SearXNG secret
   generation, then execs supervisord. Per-service output streams to
   `docker logs`.

`.github/workflows/build.yml` builds and pushes two multi-arch (amd64 + arm64)
channels, weekly + on changes:

| Tag | Built from | For |
|---|---|---|
| `ghcr.io/ktmetcalfe/odysseus-omnibus:latest` | **fork** `main` (you Sync-fork after review) | normal installs |
| `ghcr.io/ktmetcalfe/odysseus-omnibus:edge` | **upstream** `main` directly (no review) | early testing |

Only `:latest` routes through the fork, which acts as a review buffer for the
stable channel. `:edge` builds straight from upstream by design.

## Updating

- Template points at `:latest`; update via Unraid's *Check for Updates*. Pin a
  container to `:edge` to ride upstream directly instead.
- App version (stable): *Sync fork* the fork's `main` from upstream after
  reviewing, then rebuild. The `:edge` channel tracks upstream automatically.
- SearXNG / ntfy: bump `SEARXNG_REF` / `NTFY_VERSION` in the pins block at the
  top of `image/Dockerfile` (verify SearXNG boots clean first).

See `MAINTAINING.md` for upkeep - the fork model, version bumps, local build +
smoke test, and troubleshooting.

## Credit & license

Odysseus © its authors, **AGPL-3.0-or-later** (relicensed from MIT upstream in
June 2026) - see the upstream repo. Bundled components keep their own licenses:
SearXNG (AGPL-3.0), ntfy (Apache-2.0), ChromaDB (Apache-2.0). The image as a
whole is therefore effectively AGPL-3.0: fine for self-hosting, but if you
expose a *modified* build to others over a network, AGPL asks you to offer that
source. This is an independent community repackaging, not affiliated with or
endorsed by the upstream project. App bugs → upstream; Unraid/packaging issues
→ here.
