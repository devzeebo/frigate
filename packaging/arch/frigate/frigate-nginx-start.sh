#!/bin/bash
# Render Frigate nginx templates and exec Frigate's vod-enabled nginx.
# Compatible with Frigate 0.17.x helpers (get_base_path.py / get_listen_settings.py).
set -euo pipefail

export PYTHONPATH="/opt/frigate${PYTHONPATH:+:$PYTHONPATH}"
export PATH="/opt/frigate/.venv/bin:/usr/local/tempio/bin:/usr/local/nginx/sbin:/usr/bin:${PATH}"
export DEFAULT_FFMPEG_VERSION="${DEFAULT_FFMPEG_VERSION:-system}"
export INCLUDED_FFMPEG_VERSIONS="${INCLUDED_FFMPEG_VERSIONS:-system}"

mkdir -p /etc/letsencrypt/www /etc/letsencrypt/live/frigate /var/run /dev/shm/nginx_cache

letsencrypt_path=/etc/letsencrypt/live/frigate
if [[ ! -f "${letsencrypt_path}/privkey.pem" || ! -f "${letsencrypt_path}/fullchain.pem" ]]; then
  echo "[INFO] No TLS certificate found. Generating a self signed certificate..."
  openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/O=FRIGATE DEFAULT CERT/CN=*" \
    -keyout "${letsencrypt_path}/privkey.pem" \
    -out "${letsencrypt_path}/fullchain.pem" 2>/dev/null
fi

cpus="$(nproc)"
if [[ "${cpus}" -gt 4 ]]; then
  cpus=4
fi
sed -i "s/worker_processes auto;/worker_processes ${cpus};/" /usr/local/nginx/conf/nginx.conf || true

# 0.17.x: separate helpers. Newer trees may ship get_nginx_settings.py instead.
tempio_bin="${TEMPIO:-/usr/local/tempio/bin/tempio}"

if [[ -f /usr/local/nginx/get_nginx_settings.py ]]; then
  python3 /usr/local/nginx/get_nginx_settings.py | \
    "${tempio_bin}" -template /usr/local/nginx/templates/base_path.gotmpl \
      -out /usr/local/nginx/conf/base_path.conf
  python3 /usr/local/nginx/get_nginx_settings.py | \
    "${tempio_bin}" -template /usr/local/nginx/templates/listen.gotmpl \
      -out /usr/local/nginx/conf/listen.conf
else
  python3 /usr/local/nginx/get_base_path.py | \
    "${tempio_bin}" -template /usr/local/nginx/templates/base_path.gotmpl \
      -out /usr/local/nginx/conf/base_path.conf
  python3 /usr/local/nginx/get_listen_settings.py | \
    "${tempio_bin}" -template /usr/local/nginx/templates/listen.gotmpl \
      -out /usr/local/nginx/conf/listen.conf
fi
# nginx.conf already has "daemon off;"; do not also pass -g or nginx exits with
# "daemon directive is duplicate".
exec nginx
