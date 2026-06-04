#!/bin/sh
# odysseus-omnibus PID1.
#
# 1. PUID/PGID + ownership repair on the data volume (Unraid footgun fix).
# 2. Decide which bundled services to run (EMBED_CHROMA/SEARXNG/NTFY, default
#    true) and, for each, default the env var Odysseus uses to the loopback
#    endpoint - UNLESS the user already pointed it at an external instance.
#    Turn a service off to use an external one (the Omnibus escape hatch).
# 3. Generate supervisord program configs for the enabled services.
# 4. exec supervisord (PID1), which runs each service; the app + chroma +
#    searxng are dropped to PUID:PGID via gosu, output streamed to docker logs.
set -e

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
CONFD=/etc/supervisor/conf.d
SEARXNG_SETTINGS_PATH="${SEARXNG_SETTINGS_PATH:-/app/data/searxng/settings.yml}"

EMBED_CHROMA="${EMBED_CHROMA:-true}"
EMBED_SEARXNG="${EMBED_SEARXNG:-true}"
EMBED_NTFY="${EMBED_NTFY:-true}"

log() { echo "[omnibus] $*"; }

# --- users / ownership (mirrors the upstream app entrypoint) ---
if ! getent group "$PGID" >/dev/null 2>&1; then
    groupadd -g "$PGID" odysseus
fi
if ! getent passwd "$PUID" >/dev/null 2>&1; then
    useradd -u "$PUID" -g "$PGID" -M -s /bin/sh -d /app odysseus
fi

mkdir -p /app/data /app/logs /app/data/chroma /app/data/searxng /app/data/ntfy
for dir in /app /app/data /app/logs; do
    if [ -d "$dir" ]; then
        find "$dir" -not -uid "$PUID" -print0 2>/dev/null \
            | xargs -0 -r chown "$PUID:$PGID" 2>/dev/null || true
    fi
done

# --- supervisord program writer ---
rm -f "$CONFD"/*.conf
write_program() {
    # $1 name  $2 command  $3 priority
    cat > "$CONFD/$1.conf" <<EOF
[program:$1]
command=$2
autostart=true
autorestart=true
startsecs=3
stopwaitsecs=15
priority=$3
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF
}

# --- bundled services + auto-wiring ---
if [ "$EMBED_CHROMA" = "true" ]; then
    export CHROMADB_HOST="${CHROMADB_HOST:-127.0.0.1}"
    export CHROMADB_PORT="${CHROMADB_PORT:-8000}"
    write_program chroma "gosu $PUID:$PGID /usr/local/bin/svc-chroma" 10
    log "ChromaDB: embedded on ${CHROMADB_HOST}:${CHROMADB_PORT}"
else
    log "ChromaDB: external (CHROMADB_HOST=${CHROMADB_HOST:-unset})"
fi

if [ "$EMBED_SEARXNG" = "true" ]; then
    export SEARXNG_INSTANCE="${SEARXNG_INSTANCE:-http://127.0.0.1:8080}"
    export SEARXNG_SETTINGS_PATH
    # Render settings.yml + secret on first boot (idempotent).
    if [ ! -s "$SEARXNG_SETTINGS_PATH" ] || grep -q '__SEARXNG_SECRET__' "$SEARXNG_SETTINGS_PATH" 2>/dev/null; then
        secret="${SEARXNG_SECRET:-}"
        [ -z "$secret" ] && secret="$(python -c 'import secrets; print(secrets.token_urlsafe(48))')"
        sed "s|__SEARXNG_SECRET__|$secret|g" \
            /usr/local/share/odysseus/searxng-settings.yml.template > "$SEARXNG_SETTINGS_PATH"
    fi
    write_program searxng "gosu $PUID:$PGID /usr/local/bin/svc-searxng" 10
    log "SearXNG: embedded on ${SEARXNG_INSTANCE}"
else
    log "SearXNG: external (SEARXNG_INSTANCE=${SEARXNG_INSTANCE:-unset})"
fi

if [ "$EMBED_NTFY" = "true" ]; then
    export NTFY_BASE_URL="${NTFY_BASE_URL:-http://127.0.0.1:8091}"
    write_program ntfy "gosu $PUID:$PGID /usr/local/bin/svc-ntfy" 10
    log "ntfy: embedded on ${NTFY_BASE_URL}"
else
    log "ntfy: external (NTFY_BASE_URL=${NTFY_BASE_URL:-unset})"
fi

# Re-chown the freshly written settings so the app user can read them.
chown -R "$PUID:$PGID" /app/data/searxng /app/data/ntfy /app/data/chroma 2>/dev/null || true

# Always run the app last (after deps have a head start).
write_program odysseus "gosu $PUID:$PGID /usr/local/bin/svc-odysseus" 50

# First-time app setup as the app user (idempotent; never blocks startup).
gosu "$PUID:$PGID" python /app/setup.py || true

log "starting supervisord"
exec supervisord -c /etc/supervisor/supervisord.conf
