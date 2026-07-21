#!/bin/sh
# Auto-reload nginx pas config/cert berubah, dengan validasi dulu.
# - Poll checksum tiap RELOAD_INTERVAL detik (no inotify, no extra package).
# - Kalau berubah: nginx -t dulu. Valid -> reload. Invalid -> skip (proxy lama jalan terus).
# Gantiin timer reload 6h; cert live dir ikut di-watch jadi renew ke-pickup.

set -u

WATCH_PATHS="/etc/nginx/nginx.conf /etc/nginx/conf.d /etc/nginx/snippets /etc/letsencrypt/live"
INTERVAL="${RELOAD_INTERVAL:-10}"

checksum() {
    # -L follow symlink biar isi cert (live -> archive) kebaca
    find -L $WATCH_PATHS -type f 2>/dev/null -exec md5sum {} + 2>/dev/null | sort | md5sum
}

echo "[reload-watcher] start; watch: $WATCH_PATHS; interval: ${INTERVAL}s"

nginx -g 'daemon off;' &
NGINX_PID=$!

last="$(checksum)"

while kill -0 "$NGINX_PID" 2>/dev/null; do
    sleep "$INTERVAL"
    cur="$(checksum)"
    [ "$cur" = "$last" ] && continue

    echo "[reload-watcher] perubahan kedeteksi, tes config..."
    if nginx -t; then
        echo "[reload-watcher] config OK -> reload"
        nginx -s reload
    else
        echo "[reload-watcher] config INVALID -> skip reload (pertahankan config lama)"
    fi
    last="$cur"
done

echo "[reload-watcher] nginx berhenti, watcher exit"
