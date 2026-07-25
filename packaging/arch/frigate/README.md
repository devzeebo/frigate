# Frigate Arch Linux packaging (LXC + NVIDIA)

Local PKGBUILD for installing Frigate **without Docker** on an Arch-based Proxmox LXC with an NVIDIA GPU.

This is **not** an official Frigate or Arch package. Frigate upstream supports Docker; LXC is unsupported. Use at your own risk.

## Packages built

| Package | Role |
|---------|------|
| `frigate-nginx` | Custom nginx with vod / secure-token / set-misc (Frigate recording playback) |
| `frigate` | App under `/opt/frigate`, web UI, Python venv, systemd units |

```bash
makepkg -si   # builds and installs both
```

## Prerequisites (outside the package)

### 1. Proxmox host NVIDIA driver

The LXC shares the host kernel modules. Host driver **major version must match** Arch `nvidia-utils` inside the CT (check [Arch nvidia-utils](https://archlinux.org/packages/extra/x86_64/nvidia-utils/)).

On the Proxmox host:

1. Blacklist `nouveau`, install matching NVIDIA `.run` with DKMS (or an equivalent pinned driver).
2. Ensure device nodes exist before the CT starts (lazy `/dev/nvidia-uvm` breaks binds):

```bash
# /etc/udev/rules.d/70-nvidia.rules
ACTION=="add", DEVPATH=="/bus/pci/drivers/nvidia", RUN+="/usr/bin/nvidia-modprobe -c0 -u"
```

3. Verify: `nvidia-smi` and `ls -l /dev/nvidia* /dev/nvidia-caps`.

When Arch bumps `nvidia-utils`, upgrade the host driver **before** `pacman -Syu` in the CT, or temporarily:

```text
IgnorePkg = nvidia-utils
```

in `/etc/pacman.conf` inside the LXC.

### 2. Privileged Arch LXC + GPU binds

Create a **privileged** Arch Linux container. Example `/etc/pve/lxc/<CTID>.conf` snippets (confirm `video` GID inside the CT with `getent group video`):

```text
ostype: archlinux
unprivileged: 0

dev0: /dev/nvidia0,gid=985
dev1: /dev/nvidiactl,gid=985
dev2: /dev/nvidia-modeset,gid=985
dev3: /dev/nvidia-uvm,gid=985
dev4: /dev/nvidia-uvm-tools,gid=985
dev5: /dev/nvidia-caps/nvidia-cap1,gid=985
dev6: /dev/nvidia-caps/nvidia-cap2,gid=985

startup: order=2,up=15
lxc.apparmor.profile: unconfined
lxc.cap.drop:
```

Bind-mount persistent storage:

| CT path | Purpose |
|---------|---------|
| `/config` | `config.yml`, DB, model cache |
| `/media/frigate` | recordings / clips / exports |
| `/tmp/cache` | prefer tmpfs (~1GB) |

Size `/dev/shm` for your camera count using the [Frigate shm calculator](https://docs.frigate.video/frigate/installation#calculating-required-shm-size).

### 3. NVIDIA userspace inside the LXC

```bash
pacman -Syu --needed nvidia-utils base-devel git
# Do NOT install nvidia / nvidia-dkms in the LXC (kernel is the host's)
nvidia-smi
```

## Install Frigate with makepkg

AUR packages are **not** fetched by `makepkg`. Install them first:

```bash
# AUR helper required (yay, paru, ...)
yay -S nvm go2rtc ffmpeg-full
# alternate: yay -S nvm go2rtc ffmpeg-cuda-full
```

Build-time Node comes from nvm (not pacman `nodejs`). The PKGBUILD sources
`/usr/share/nvm/init-nvm.sh` and runs `nvm install 20` / `nvm use 20` using
versions under the build user's `~/.nvm`. Node is not required at runtime.

Copy this directory into the CT (or clone the Frigate repo and `cd packaging/arch/frigate`):

```bash
cd packaging/arch/frigate
makepkg -si
```

Enable services:

```bash
sudo systemd-tmpfiles --create /usr/lib/tmpfiles.d/frigate.conf
sudo systemctl enable --now go2rtc-frigate frigate-nginx frigate
```

## Configuration

```bash
sudo cp /usr/share/frigate/config.yml.example /config/config.yml
# edit cameras, put an ONNX model under /config/model_cache/
```

NVIDIA-oriented defaults in the example:

- `ffmpeg.path: /usr` (system ffmpeg from AUR)
- `ffmpeg.hwaccel_args: preset-nvidia`
- `detectors.onnx` with pip `onnxruntime-gpu` (CUDA EP in `/opt/frigate/.venv`)

UI: port **8971** (authenticated). Internal API: **5000**. Restream: **8554**. WebRTC: **8555**.

## Layout

| Path | Notes |
|------|------|
| `/opt/frigate` | Application + `.venv` + bundled uv CPython 3.13 under `.python` |
| `/usr/local/nginx` | Frigate vod nginx |
| `/usr/local/go2rtc/create_config.py` | Builds `/dev/shm/go2rtc.yaml` |
| `/usr/lib/ffmpeg/system/bin` | Symlinks to `/usr/bin/ffmpeg` |
| `/labelmap.txt` | Default COCO labels |

Services run as **root** (same as the upstream container) so GPU and device nodes remain accessible.

## Upgrades

1. Bump `pkgver` / checksums in `PKGBUILD` (or retarget the Frigate tag).
2. `makepkg -si` again.
3. After host NVIDIA upgrades, ensure LXC `nvidia-utils` still matches before starting Frigate.

## Troubleshooting

| Symptom | Check |
|---------|--------|
| `nvidia-smi` fails in CT | Host driver, device binds, matching `nvidia-utils` |
| CUDA / ORT errors | Driver skew; `/opt/frigate/.venv/bin/python -c 'import onnxruntime as o; print(o.get_available_providers())'` |
| No recording playback | `frigate-nginx` running; vod build succeeded |
| go2rtc / live view broken | `systemctl status go2rtc-frigate`; `/dev/shm/go2rtc.yaml` |
| Frame drops / shm errors | Increase `/dev/shm` size |

## Building notes

- Nginx compile steps are ported from Frigate’s `docker/main/build_nginx.sh` (no Debian `apt`). A small GCC 15+ prototype patch is applied to nginx-vod-module (`nginx-vod-exit-process.patch`).
- Web UI build uses nvm-managed Node 20 (matches upstream `node:20`); pacman `nodejs` / `npm` are not used.
- Python deps are installed with `uv` into `/opt/frigate/.venv` from `requirements-arch.txt` (numpy, scipy, opencv, and `onnxruntime-gpu` plus NVIDIA CUDA pip libs). The venv uses uv-managed **CPython 3.13** (bundled under `/opt/frigate/.python`) because Arch’s system Python is newer than many pinned wheels (for example `tokenizers==0.20.3`). No Arch/AUR Python packages are required at runtime beyond helper scripts that call system `python3`, plus `nvidia-utils`.
- TFLite / OpenVINO wheels are omitted; this package targets NVIDIA ONNX detection.
