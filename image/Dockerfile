# odysseus-omnibus - all-in-one Odysseus appliance for Unraid.
#
# Self-contained: stage 1 builds the Odysseus app (MIT) from a fork we control
# (ODYSSEUS_REPO, a fork of pewdiepie-archdaemon/odysseus) exactly as upstream's
# own Dockerfile does; the final stage bundles ChromaDB (vector memory) +
# SearXNG (web search, JSON
# enabled) + ntfy (notifications), supervised by supervisord. One image, one
# container - no inter-container wiring.
#
# GitLab-Omnibus style: each bundled service can be turned off
# (EMBED_CHROMA / EMBED_SEARXNG / EMBED_NTFY = false) and pointed at an external
# instance via the same env vars Odysseus already uses - so you're never
# locked in.

# ===== Pinned versions - SINGLE place to bump (see MAINTAINING.md) ==========
# The Odysseus app is built from a FORK we control, not upstream directly, so
# upstream changes flow through a repo we can freeze/patch (see MAINTAINING).
# ODYSSEUS_REF is the per-channel source branch on the fork: `main` -> :latest
# (you sync manually after review), `track` -> :edge (auto-mirrors upstream).
# The build.yml workflow overrides ODYSSEUS_REF per channel; the defaults here
# are for local `docker build`. The companion pins below are the single source
# of truth (CI does NOT override them) - bump them right here.
ARG ODYSSEUS_REPO=https://github.com/KTMetcalfe/odysseus.git
ARG ODYSSEUS_REF=main
ARG NTFY_VERSION=v2.24.0
ARG SEARXNG_REF=f3fab143be3069bbcdcec9169bcf6ee030437a61
# ===========================================================================

# --- ntfy: static Go binary, just copy it ---
FROM docker.io/binwiederhier/ntfy:${NTFY_VERSION} AS ntfy

# --- stage 1: the Odysseus app (mirrors upstream Dockerfile) ---
FROM python:3.12-slim AS app
ARG ODYSSEUS_REPO
ARG ODYSSEUS_REF
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential cmake curl git nodejs npm tmux openssh-client gosu \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
RUN git clone "${ODYSSEUS_REPO}" /app \
    && git checkout "${ODYSSEUS_REF}" \
    && rm -rf /app/.git
RUN pip install --no-cache-dir -r requirements.txt
RUN mkdir -p data logs services/cache/search

# --- final stage: bundle the companion services ---
FROM app AS omnibus
ARG SEARXNG_REF

# Build deps for SearXNG's Python requirements (lxml etc.).
RUN apt-get update && apt-get install -y --no-install-recommends \
      libxml2-dev libxslt1-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Chroma server + granian (SearXNG WSGI server) + supervisor.
RUN pip install --no-cache-dir chromadb granian supervisor

# SearXNG: source-tree install (it is NOT pip-installable as a wheel - its
# setup imports msgspec at build time). Clone, pin, install requirements; run
# in-place via PYTHONPATH (see svc-searxng).
RUN git clone https://github.com/searxng/searxng.git /usr/local/searxng-src \
    && git -C /usr/local/searxng-src checkout "${SEARXNG_REF}" \
    && pip install --no-cache-dir -r /usr/local/searxng-src/requirements.txt

COPY --from=ntfy /usr/bin/ntfy /usr/local/bin/ntfy

COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY svc-odysseus svc-chroma svc-searxng svc-ntfy /usr/local/bin/
COPY searxng-settings.yml /usr/local/share/odysseus/searxng-settings.yml.template
COPY entrypoint.sh /usr/local/bin/omnibus-entrypoint.sh
RUN chmod +x /usr/local/bin/svc-odysseus /usr/local/bin/svc-chroma \
      /usr/local/bin/svc-searxng /usr/local/bin/svc-ntfy \
      /usr/local/bin/omnibus-entrypoint.sh \
    && mkdir -p /etc/supervisor/conf.d

LABEL org.opencontainers.image.source="https://github.com/KTMetcalfe/odysseus-unraid"
LABEL org.opencontainers.image.description="Odysseus all-in-one (app + chromadb + searxng + ntfy) for Unraid"
LABEL org.opencontainers.image.licenses="MIT"

EXPOSE 7000

ENTRYPOINT ["/usr/local/bin/omnibus-entrypoint.sh"]
