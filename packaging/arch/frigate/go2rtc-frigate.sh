#!/bin/bash
# Prepare Frigate go2rtc config and exec system go2rtc.
set -euo pipefail

export PYTHONPATH="/opt/frigate${PYTHONPATH:+:$PYTHONPATH}"
export PATH="/opt/frigate/.venv/bin:/usr/local/tempio/bin:/usr/local/ffmpeg:/usr/bin:${PATH}"
export DEFAULT_FFMPEG_VERSION="${DEFAULT_FFMPEG_VERSION:-system}"
export INCLUDED_FFMPEG_VERSIONS="${INCLUDED_FFMPEG_VERSIONS:-system}"

ffmpeg_path="$(python3 /usr/local/ffmpeg/get_ffmpeg_path.py)"
LIBAVFORMAT_VERSION_MAJOR="$("$ffmpeg_path" -version | grep -Po 'libavformat\W+\K\d+' || true)"
export LIBAVFORMAT_VERSION_MAJOR

if [[ -f /dev/shm/go2rtc.yaml ]]; then
  rm -f /dev/shm/go2rtc.yaml
fi

python3 /usr/local/go2rtc/create_config.py

homekit_config="/config/go2rtc_homekit.yml"
if [[ ! -f "${homekit_config}" ]]; then
  : > "${homekit_config}"
fi

go2rtc_bin="/usr/bin/go2rtc"
if [[ -x /config/go2rtc ]]; then
  go2rtc_bin="/config/go2rtc"
fi

exec "${go2rtc_bin}" -config="${homekit_config}" -config=/dev/shm/go2rtc.yaml
