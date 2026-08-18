```
  ███╗   ██╗███████╗██╗  ██╗██╗   ██╗███████╗
  ████╗  ██║██╔════╝╚██╗██╔╝██║   ██║██╔════╝
  ██╔██╗ ██║█████╗   ╚███╔╝ ██║   ██║███████╗
  ██║╚██╗██║██╔══╝   ██╔██╗ ██║   ██║╚════██║
  ██║ ╚████║███████╗██╔╝ ██╗╚██████╔╝███████║
  ╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝

   K E R N E L   v 4 . 0 . 0
```

# Infinity Kernel
**Custom Kernel for POCO X3 Pro (vayu/bhima) — SM8150 — Linux 4.14.357+**

<p align="center">
  <img src="https://img.shields.io/badge/Version-v4.0.0-blue?style=flat-square" alt="Version">
  <img src="https://img.shields.io/badge/Device-vayu%20%7C%20bhima-orange?style=flat-square" alt="Device">
  <img src="https://img.shields.io/badge/SoC-SM8150-red?style=flat-square" alt="SoC">
  <img src="https://img.shields.io/badge/Android-11--17-blue?style=flat-square" alt="Android">
  <img src="https://img.shields.io/badge/License-GPL--2.0-green?style=flat-square" alt="License">
</p>

<p align="center">
  <b>One kernel. Six root managers. Every ROM. Zero compromise.</b>
</p>

---

## Features

### 🚀 Root Management (Multi-Root)

One universal kernel binary — root type is selected at build time.

| Command | Root | Description |
|---------|------|-------------|
| `./build.sh kernelsu` | KernelSU-Next v3.3.0 | In-kernel root, auto-clone from GitHub |
| `./build.sh apatch` | APatch | Patches boot image at flash time |
| `./build.sh sukisu_ultra` | SuKisu Ultra | Kernel-level root |
| `./build.sh resukisu` | ReSUKISU | KernelSU fork with extra features |
| `./build.sh kowsu` | KoWSU | KernelSU fork for gaming |
| `./build.sh none` | No root | Clean, hardened build |

### 🛡️ SuSFS v2.2.0 — Anti-Detection

14 configurable options to hide root artifacts from detection:

| Option | Description |
|--------|-------------|
| `SUS_PATH` | Hides files/directories by path from filesystem enumeration |
| `SUS_MOUNT` | Hides mount points from `/proc/mounts` and `/proc/self/mountinfo` |
| `TRY_MOUNT` | Attempts to mount but hides it from userspace mount lists |
| `SUS_KSTAT` | Removes kstat entries for hidden paths from `stat()` family calls |
| `SUS_MAPS` | Filters `/proc/*/maps` to remove memory mappings of hidden binaries |
| `SUS_OVERLAY` | Hides overlayfs layers used by root managers |
| `SUS_PAGE` | Blocks access to hidden files via `/proc/*/page_idle` |
| `SUS_INODE` | Removes inode references from `/proc/*/fd` for hidden files |
| `SUS_FD` | Hides file descriptors pointing to hidden paths in fd listings |
| `SUS_DB` | Hides root-related entries from database-style file access patterns |
| `ENABLE_LOG` | Enables kernel log output for SuSFS operations (debug) |
| `SUSURE` | SuSFS reverse engineering protection — hides kernel module symbols |
| `AUTO_HIDE` | Automatically hides all known root manager paths and mounts |
| `SUS_MEMFD` | Hides memfd_create entries used for in-memory executables |

### 🎮 NTsync — Windows Game Compatibility

Backport from Linux 6.14. Provides the ntsync driver at `/dev/ntsync` with 7 ioctls:

- **CREATE_SEM** — Create a semaphore object
- **CREATE_MUTEX** — Create a mutex object
- **CREATE_EVENT** — Create an event object
- **WAIT_ANY** — Wait for any of a set of objects
- **WAIT_ALL** — Wait for all of a set of objects
- **SIGNAL** — Signal an object
- **RESET** — Reset an event object

Moves Wine/Proton event synchronization from userspace (esync/fsync) to kernel, reducing CPU overhead and improving FPS in Windows games running via emulation (Waydroid, Wine on ARM).

### ⚡ Performance

- **BORE Scheduler v5.1.0** — Burst-aware CPU scheduling; better responsiveness and interactivity than CFS for interactive workloads
- **EFFCPU** — Custom frequency table that caps max frequency for efficiency gains (2640 MHz vs 2840 MHz Gold, 1640 MHz vs 1766 MHz Silver). Toggle via `/sys/devices/system/cpu/effcpu/enable`
- **`-mcpu=kryo`** — Clang pipeline-aware instruction scheduling tuned for Kryo 485 cores (SM8150)
- **FullLTO / ThinLTO** — Link-time optimization produces a smaller and faster kernel binary
- **TCP BBR** — Set as default congestion control for improved network throughput
- **zRAM 5 GB LZ4** — Compressed swap with LZ4 algorithm and `copy_page` optimization
- **FSYNC** — Optimized `f2fs`/`ext4` sync operations for reduced I/O latency

### 🎨 Display

- **KCAL** — Per-channel RGB control, saturation, hue, contrast, and gamma adjustment via `/sys/devices/virtual/kcal/ctrl/`
- **CABC** — Content Adaptive Backlight Control with 5 modes (`off` / `on` / `ui` / `video` / `still_image`) via `/sys/class/backlight/panel/cabc`
- **HBM** — High Brightness Mode providing up to +15% brightness boost via `/sys/class/backlight/panel/hbm`

### 🔋 Charging Bypass

Control charging behavior via `/sys/class/power_supply/battery/charging_bypass`:

| Mode | Value | Description |
|------|-------|-------------|
| OFF | `0` | Normal charging behavior |
| ON | `1` | Direct power, bypasses battery charging |
| AUTO | `2` | Automatically enables bypass at threshold temperature |

Thermal cooldown uses 2 °C hysteresis. Configure the threshold (default 42 °C) via `/sys/class/power_supply/battery/charging_bypass_threshold`.

### 🔊 Sound Control

Gain control exposed through sysfs:

| Path | Description | Range |
|------|-------------|-------|
| `/sys/class/codec/sound_ctrl/eargain` | Earpiece gain | 0–31 |
| `/sys/class/codec/sound_ctrl/headphone_gain` | Headphone gain | 0–31 |
| `/sys/kernel/sound_control/call_mic_gain` | Call microphone gain | 0–31 |
| `/sys/kernel/sound_control/speaker_gain` | Speaker gain | 0–31 |

### 📱 Cross-ROM Support

| ROM | Variant | Notes |
|-----|---------|-------|
| MIUI V12–V15 | `miui` | Default variant, dtbo required |
| HyperOS / OxygenOS | `hyperos` | Use HyperOS-labeled build + dtbo |
| AOSP / LineageOS / crDroid / PE | `aosp` | Works out of the box |

Android 11 through Android 17 supported.

### 🔧 Optimizations & Fixes

- **ext4**: `cond_resched` in heavy loops, optimized double fsync
- **Memory**: swappiness=100, memcg swappiness fix
- **Thermal**: simple thermal governor with per-zone user control
- **MMC/SDIO**: deep sleep fix
- **WiFi**: legacy GTK status prefix support
- **7 upstream fixes**:
  1. `modpost` LTO symbol resolution
  2. `thermal_core` NULL pointer dereference
  3. `cam_trace` `%pK` format specifier
  4. SPI touchscreen probe deferral
  5. `clk-cpu-osm` 300 MHz floor frequency
  6. WLAN GTK legacy handling
  7. `alarmtimer` argument order correction

---

## Project Structure

```
.
├── build.sh                     # Main build script (multi-root, toolchain auto-download)
├── Makefile                     # Convenience targets
├── .github/workflows/build.yml  # GitHub Actions CI
├── configs/fragments/           # Kconfig fragments (merged via merge_config.sh)
│   ├── infinity_base.config     # Base: BORE, BBR, zRAM, Android, SELinux
│   ├── root_kernelsu.config     # KernelSU + SuSFS 14 options
│   ├── root_apatch.config       # APatch + SuSFS
│   ├── root_none.config         # Hardened, no modules
│   ├── miui.config              # MIUI-specific
│   ├── hyperos.config           # HyperOS/OxygenOS
│   └── aosp.config              # AOSP/LineageOS
├── flasher/                     # AnyKernel3 flasher
│   ├── anykernel.sh             # Safe flash: A/B detection, truncate, dd, verify
│   └── banner
├── patches/                     # 18 idempotent patch scripts
│   ├── 00-kernelsu/             # KernelSU-Next + APatch integration
│   ├── 01-susfs/                # SuSFS anti-detection
│   ├── 02-ntsync/               # NTsync driver (backport 6.14)
│   ├── 03-scheduler-bore/       # BORE Scheduler v5.1.0
│   ├── 04-cpu-governor/         # EFFCPU + Kryo 485 optimization
│   ├── 05-kcal/                 # Color control (RGB/gamma/contrast)
│   ├── 06-cabc-hbm/             # CABC + High Brightness Mode
│   ├── 07-charging-bypass/      # Charging bypass (off/auto + thermal)
│   ├── 08-sound-control/        # Audio gain control
│   ├── 09-zram/                 # zRAM 5GB LZ4 + copy_page
│   ├── 10-thermal/              # Simple thermal governor
│   ├── 11-ext4/                 # ext4 fsync optimization
│   ├── 12-mm/                   # Memory management tuning
│   ├── 13-tcp-bbr/              # TCP BBR default
│   ├── 14-mmc-fix/              # MMC/SDIO deep sleep fix
│   ├── 15-wifi-fix/             # WiFi WMI legacy GTK fix
│   ├── 16-upstream-fixes/       # 7 upstream fixes
│   └── 17-lto/                  # FullLTO / ThinLTO
├── tools/
└── out/                         # Build output (gitignored)
```

---

## Quick Start

### Build

```bash
git clone https://github.com/YOUR_USER/infinity-kernel.git
cd infinity-kernel

# Default: KernelSU-Next for MIUI
./build.sh kernelsu miui

# APatch for HyperOS
./build.sh apatch hyperos

# No root for AOSP
./build.sh none aosp

# Clean rebuild
./build.sh kernelsu miui clean

# Or use Makefile
make kernelsu VARIANT=hyperos
```

The build script automatically:

1. Downloads Clang/LLVM (Neutron 24.0 or Proton)
2. Clones kernel source from AnymoreProject/android_kernel_vayu
3. Integrates KernelSU-Next and/or SuSFS from GitHub
4. Applies all 18 patches in order
5. Merges Kconfig fragments
6. Builds `Image.gz` + `dtbo`
7. Packages AnyKernel3 ZIP to `out/`

### Flash

1. Download the ZIP from [Releases](../../releases) (or grab it from `out/` after building)
2. Reboot to recovery (OrangeFox / TWRP)
3. Flash the ZIP
4. Reboot

> **MIUI**: Flash the regular build + `dtbo.img`
> **HyperOS / OxygenOS**: Use the HyperOS-labeled build + `dtbo.img`

---

## Sysfs Interface

| Path | Description | Values |
|------|-------------|--------|
| `/sys/devices/system/cpu/effcpu/enable` | EFFCPU mode | `0` = stock, `1` = efficiency |
| `/sys/devices/virtual/kcal/ctrl/rgb_r` | Red channel | 0–256 |
| `/sys/devices/virtual/kcal/ctrl/rgb_g` | Green channel | 0–256 |
| `/sys/devices/virtual/kcal/ctrl/rgb_b` | Blue channel | 0–256 |
| `/sys/devices/virtual/kcal/ctrl/saturation` | Saturation | 0–256 |
| `/sys/devices/virtual/kcal/ctrl/hue` | Hue shift | 0–256 |
| `/sys/devices/virtual/kcal/ctrl/contrast` | Contrast | 0–256 |
| `/sys/devices/virtual/kcal/ctrl/gamma` | Gamma | 0–256 |
| `/sys/devices/virtual/kcal/ctrl/values` | Read all values | — |
| `/sys/class/backlight/panel/cabc` | CABC mode | `0` = off, `1` = on, `2` = ui, `3` = video, `4` = still |
| `/sys/class/backlight/panel/hbm` | HBM | `0` = off, `1` = on |
| `/sys/class/power_supply/battery/charging_bypass` | Charging mode | `0` = off, `1` = on, `2` = auto |
| `/sys/class/power_supply/battery/charging_bypass_threshold` | Thermal threshold | millidegrees (default `42000`) |
| `/sys/class/codec/sound_ctrl/eargain` | Earpiece gain | 0–31 |
| `/sys/class/codec/sound_ctrl/headphone_gain` | Headphone gain | 0–31 |
| `/sys/kernel/sound_control/call_mic_gain` | Mic gain | 0–31 |
| `/sys/kernel/sound_control/speaker_gain` | Speaker gain | 0–31 |

---

## Toolchain

| Type | Details |
|------|---------|
| **Primary** | [Neutron Clang 24.0](https://github.com/Neutron-Toolchains/clang) (auto-downloaded) |
| **Fallback** | [Proton Clang](https://github.com/kdrag0n/proton-clang) |
| **System** | Any Clang >= 15 |
| **LTO** | ThinLTO (default) / FullLTO (optional) |

---

## Disclaimer

> **Infinity Kernel is provided as-is, without any warranty.** Flashing a custom kernel carries risks including but not limited to: bootloops, data loss, device bricking, and security implications. You are solely responsible for any consequences of using this software. Always maintain a backup of your stock boot image and dtbo before flashing.

> **Charging Bypass** (bypass mode) feeds power directly to the system, skipping the battery. Prolonged use at high loads without periodic battery charging may accelerate battery aging. Use auto mode for a balanced approach.

---

## Changelog

### v4.0.0
- Complete rewrite: patch-based build system
- Added: NTsync driver (backport from Linux 6.14)
- Added: BORE Scheduler v5.1.0
- Added: EFFCPU frequency management
- Added: KCAL color control
- Added: CABC + HBM display controls
- Added: Sound gain control (4 channels)
- Added: Simple thermal governor
- Added: FullLTO / ThinLTO support
- Added: Multi-root build system (6 root managers)
- Added: SuSFS v2.2.0 with 14 anti-detection options
- Added: TCP BBR as default congestion control
- Improved: AnyKernel3 flasher (safe dd, A/B detection, verify)
- Improved: Cross-ROM support (MIUI / HyperOS / AOSP)
- Fixed: 7 upstream fixes (modpost, thermal, cam_trace, SPI, clk, WLAN, alarmtimer)
- Fixed: MMC/SDIO deep sleep
- Fixed: WiFi WMI legacy GTK
- Optimized: ext4 fsync, zRAM 5GB LZ4, memory management
- Toolchain: Neutron Clang 24.0 / Proton Clang
- CI: GitHub Actions with 4-configuration matrix

---

## Credits

- [AnymoreProject](https://github.com/AnymoreProject) — Base kernel source
- [KernelSU-Next](https://github.com/KernelSU-Next) — In-kernel root
- [vm03](https://github.com/vm03) — SuSFS
- [Neutron-Toolchains](https://github.com/Neutron-Toolchains) — Clang/LLVM
- [kdrag0n](https://github.com/kdrag0n) — Proton Clang
- [osm0sis](https://github.com/osm0sis) — AnyKernel3
- [topjohnwu](https://github.com/topjohnwu) — Magisk (magiskboot)
- [OpenELA](https://openela.org) — Enterprise Linux kernel support model

## License

Kernel source is licensed under [GPLv2](https://www.gnu.org/licenses/gpl-2.0.html). Project patches, scripts, and build system are also under GPLv2.
