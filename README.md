# redroid + ws-scrcpy

Run Android 12 in a Docker container. Control it from a web browser.

redroid (Remote Android) runs Android in a Linux container. It has no web
interface of its own. This project adds ws-scrcpy, which is a web client for
scrcpy. The result is a live Android screen in a browser tab with touch,
keyboard, and mouse control.

## Contents

1. [Overview](#overview)
2. [Repository layout](#repository-layout)
3. [Requirements](#requirements)
4. [Critical: the kernel binder warning](#critical-the-kernel-binder-warning)
5. [Quick start](#quick-start)
6. [Android display settings](#android-display-settings)
7. [Access the web viewer](#access-the-web-viewer)
8. [How it works](#how-it-works)
9. [Troubleshooting](#troubleshooting)
10. [Security](#security)
11. [Notes and limits](#notes-and-limits)
12. [References](#references)

## Overview

The stack has two containers:

* **redroid** boots Android 12 and listens for adb on port 5555.
* **ws-scrcpy** connects to redroid over adb and serves an HTML5 client on
  port 8000.

The browser receives an H264 video stream. It sends touch and key events back
to the device. No local scrcpy install is necessary. The viewer runs in the
browser.

```
+-------------------+        adb        +------------------+     HTTP/WS     +---------+
|  android (redroid)| <---------------> |    ws-scrcpy     | <-------------> | browser |
|  Android 12       |     tcp:5555      |  node + scrcpy   |    tcp:8000     |  H264   |
+-------------------+                   +------------------+                 +---------+
```

## Repository layout

```
.
├── docker-compose.yml       # the two services
├── README.md                # this file
├── .gitignore               # ignores data/
└── ws-scrcpy/
    ├── Dockerfile           # builds the viewer image
    └── entrypoint.sh        # waits for redroid, then starts ws-scrcpy
```

The Android data partition is stored in `data/`. Git ignores this directory.
The directory holds user data, for example apps and accounts.

## Requirements

* A Linux host. The kernel MUST supply the classic Android binder driver. See
  the next section.
* Docker Engine and Docker Compose.
* About 5 GB of free disk space for the two images and the data partition.
* Optional: a browser with WebCodecs support for the best video. Chromium
  works well. Firefox is slower but works.
* Optional: `adb` and `scrcpy` on the host for command-line access and a
  fallback viewer.

You do not need a GPU. The container uses software rendering by default.

## Critical: the kernel binder warning

Android uses binder for all inter-process communication. Every Android
service opens `/dev/binder` at startup. Redroid therefore needs a kernel with a
working binder driver.

There are two binder drivers in the mainline kernel:

* **classic** binder, `CONFIG_ANDROID_BINDER_IPC=y`. Stable. Use this one.
* **Rust** binder, `CONFIG_ANDROID_BINDER_IPC_RUST=y`. New. Do NOT use it.

### The Rust binder panics

The Rust binder driver has a bug in its open path. When a process opens a
binder device, the driver calls `mmgrab` with a bad pointer. The kernel writes
to address 1, which causes a fatal page fault. The kernel then panics.

Observed trace:

```
BUG: unable to handle page fault
#PF: supervisor write access in kernel mode
#PF: error_code(0x0002) - not-present page
CR2: 0000000000000001
RIP: 0010:rust_helper_mmgrab+0x4/0x10
Call Trace:
 rust_binder_open
 do_dentry_open
 vfs_open
 path_openat
 __x64_sys_openat
Kernel panic - not syncing: Fatal exception
```

If the redroid container starts at boot on such a kernel, the host panics in a
loop. Keep `restart: "no"` in `docker-compose.yml` while a Rust-binder kernel
is installed.

### Check your kernel

Run this command:

```bash
zgrep -i ANDROID_BINDER /proc/config.gz
```

The correct result:

```
CONFIG_ANDROID_BINDER_IPC=y
CONFIG_ANDROID_BINDERFS=y
```

The bad result is `CONFIG_ANDROID_BINDER_IPC_RUST=y`.

### Which kernel to use

Linux distributions moved to the Rust binder at different times. On Arch
Linux the switch happened at kernel 6.18. Verified results:

| Kernel package | Binder | Result |
|---|---|---|
| `linux` 6.17.9 | classic | Works |
| `linux-lts` 6.12.75 | classic | Works |
| `linux` 6.18 and later | Rust | Panics |
| `linux` 7.0, 7.1, 7.2 | Rust | Panics |

For Arch, install the newest kernel with the classic binder from the archive:

```bash
curl -O https://archive.archlinux.org/packages/l/linux/linux-6.17.9.arch1-1-x86_64.pkg.tar.zst
sudo pacman -U linux-6.17.9.arch1-1-x86_64.pkg.tar.zst
```

Then pin the version, so an update cannot replace it:

```
# /etc/pacman.conf
IgnorePkg = linux linux-headers
```

Then update the boot loader and reboot:

```bash
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo reboot
```

You do not need an `ashmem` driver. The compose file sets
`androidboot.use_memfd=1`, so Android uses `memfd` for shared memory.

You do not need a host binderfs setup. Redroid mounts its own binderfs inside
the container.

## Quick start

1. Make sure that your kernel has the classic binder. See the section above.
2. Start the stack:

```bash
git clone https://github.com/x1nx3r/redroid-ws-scrcpy.git
cd redroid-ws-scrcpy
docker compose up -d
```

3. The first start of ws-scrcpy runs a webpack build. Wait about two minutes.
4. Open <http://localhost:8000>.
5. Click the device in the page. The device name is `redroid:5555`.
6. If the video does not start, change the player. Use WebCodecs in Chromium
   first. Use MSE or TinyH264 as a fallback.

Check the state at any time:

```bash
docker compose ps
docker compose logs --tail=30 ws-scrcpy
adb connect localhost:5555
adb devices
```

The Android boot takes about 30 to 60 seconds. `adb devices` shows `offline`
until the boot completes.

## Android display settings

The `command` section of the redroid service sets the Android display. Edit
`docker-compose.yml` to change the values.

| Parameter | Meaning | Default in this repo |
|---|---|---|
| `androidboot.redroid_width` | Display width in pixels | 720 |
| `androidboot.redroid_height` | Display height in pixels | 1280 |
| `androidboot.redroid_dpi` | Display density | 320 |
| `androidboot.redroid_fps` | Frame rate | 30 |
| `androidboot.redroid_gpu_mode` | `guest` = software, `host` = GPU | host |
| `androidboot.redroid_gpu_node` | Render node for `host` mode | /dev/dri/renderD128 |
| `androidboot.use_memfd` | Use `memfd` instead of `ashmem` | 1 |

For GPU acceleration, set `androidboot.redroid_gpu_mode=host`. This needs a
compatible host GPU driver and mesa. It does not work with the NVIDIA
proprietary driver.

After you change a value, apply it:

```bash
docker compose down
docker compose up -d
```

## Access the web viewer

The viewer listens on all interfaces. Replace `<host-ip>` with the address of
your machine.

* Same machine: `http://localhost:8000`
* Local network: `http://<host-ip>:8000`
* VPN or overlay network: `http://<vpn-ip>:8000`

If a remote address does not load, the host firewall blocks port 8000. Use
`firewalld` as an example:

```bash
sudo firewall-cmd --add-port=8000/tcp --permanent
sudo firewall-cmd --reload
```

Only open the port on a trusted network. See the Security section.

To stop or remove the stack:

```bash
docker compose stop      # stop the containers
docker compose down      # stop and remove the containers
```

The `data/` directory keeps the Android data after `docker compose down`.

## How it works

### redroid service

* Image: `redroid/redroid:12.0.0_64only-latest`.
* The container runs in privileged mode. Binder needs this.
* Port 5555 is published for adb.
* `./data` is mounted on `/data`. This is the Android data partition.
* At startup, the container mounts a binderfs and creates `binder`,
  `hwbinder`, and `vndbinder`. It then makes the standard symlinks in `/dev`.

### ws-scrcpy service

* The image is built from `ws-scrcpy/Dockerfile`. It contains node, adb, and
  a clone of <https://github.com/NetrisTV/ws-scrcpy>.
* `entrypoint.sh` starts the adb server. It waits for `redroid:5555`. It then
  runs `adb connect`. It starts ws-scrcpy last.
* ws-scrcpy runs a webpack build on the first start. Later starts are faster.
* Port 8000 is published for the browser.

## Troubleshooting

### The redroid container exits immediately

The kernel has no usable binder driver. Check the kernel config. See the
binder section.

### The container runs, but adb shows `offline`

Wait. The Android boot takes 30 to 60 seconds. Retry the connection:

```bash
adb disconnect localhost:5555
adb connect localhost:5555
```

### Logcat shows "Binder driver could not be opened"

Android cannot open the binder device. The kernel binder driver is missing or
wrong. Check the kernel config.

### The host panics with `rust_helper_mmgrab`

The kernel uses the Rust binder. Install a kernel with the classic binder. See
the binder section.

### The browser shows an error, and port 8000 is closed

The ws-scrcpy webpack build is still running. Wait two minutes and check the
logs:

```bash
docker compose logs -f ws-scrcpy
```

### The video does not start

Change the player in the ws-scrcpy interface. Use WebCodecs in Chromium first.
Use MSE or TinyH264 as a fallback.

### The Git clone fails in the image build

The build needs CA certificates for HTTPS. The Dockerfile installs
`ca-certificates`. Do not remove that line.

## Security

* ws-scrcpy has **no authentication and no TLS**. Any client that reaches
  port 8000 controls the device.
* The redroid adb port has no authentication. The redroid documentation warns
  that an exposed adb port can compromise the container and the host.
* Do not expose ports 5555 or 8000 to the internet.
* Use a firewall. Prefer a VPN or an overlay network for remote access.

## Notes and limits

* This repo uses host GPU rendering (`gpu_mode=host`) through mesa. It needs a
  render node such as `/dev/dri/renderD128`. If the GPU path fails, set
  `gpu_mode=guest` to fall back to software rendering. Inside the container,
  `dumpsys SurfaceFlinger` must show a real GPU, for example
  `AMD Radeon Graphics (radeonsi)`, not ANGLE.
* ws-scrcpy uses an old scrcpy server (v1.19). Newer devices may work better
  with other clients.
* Fallback viewer on the host: `scrcpy -s localhost:5555`.
* The `_64only` image runs 64-bit Android only. It needs an x86_64 host.
  For an arm64 host, use `redroid/redroid:12.0.0-latest` and remove `_64only`.

## References

* redroid documentation: <https://github.com/remote-android/redroid-doc>
* ws-scrcpy: <https://github.com/NetrisTV/ws-scrcpy>
* scrcpy: <https://github.com/Genymobile/scrcpy>
* Binderfs kernel documentation:
  <https://www.kernel.org/doc/html/latest/admin-guide/binderfs.html>

## License

redroid is under the Apache License 2.0. ws-scrcpy is under the MIT License.
This repository contains only configuration files and a short entrypoint
script. Obey the licenses of the two upstream projects.
