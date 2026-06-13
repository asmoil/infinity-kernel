<h1 align="center">
  <pre>
   ██████╗ ██████╗  █████╗ ███╗   ██╗████████╗ ██████╗ ██████╗ ███████╗
  ██╔════╝ ██╔══██╗██╔══██╗████╗  ██║╚══██╔══╝██╔═══██╗██╔══██╗██╔════╝
  ██║  ███╗██████╔╝███████║██╔██╗ ██║   ██║   ██║   ██║██████╔╝█████╗
  ██║   ██║██╔══██╗██╔══██║██║╚██╗██║   ██║   ██║   ██║██╔══██╗██╔══╝
  ╚██████╔╝██║  ███████║██║  ╚████║   ██║   ╚██████╔╝██║  ██║███████╗
   ╚═════╝ ╚═╝  ╚════╝╚═╝   ╚═══╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚══════╝
  </pre>
</h1>

<p align="center">
  <b>Custom Kernel for Poco X3 Pro (vayu/bhima)</b><br>
  SM8250-AC (Snapdragon 860) &bull; Linux 4.14 &bull; Proton Clang 17
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Version-v1.0.4-blue?style=flat-square" alt="Version">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License">
  <img src="https://img.shields.io/badge/Device-vayu%20%7C%20bhima-orange?style=flat-square" alt="Device">
  <img src="https://img.shields.io/badge/SoC-SM8250--AC-red?style=flat-square" alt="SoC">
</p>

---

## Features

### Performance & Battery Balance

- **CPU Tuning** — 300Hz tick rate, optimized scheduler latency (4ms), schedutil governor with faster response
- **GPU (Adreno 618)** — Raised thermal throttle threshold to 50°C, sysfs `gpu_max_freq` control, faster idle timer
- **I/O Scheduler** — Maple (preferred) / BFQ fallback, 128KB read-ahead, FSYNC optimization
- **TCP** — BBR congestion control by default, TCP Fast Open (client+server), tuned rmem/wmem buffers
- **Memory** — ZRAM 5GB LZ4, KSM (Kernel Same-page Merging), CMA 256MB, aggressive compaction, THP MADVISE

### Charging Bypass (Gaming)

4 gaming modes with thermal monitoring and auto-resume safety:

| Mode | Pause at | Thermal Limit | Current Reduction |
|------|----------|---------------|-------------------|
| **OFF** | — | — | 0% |
| **LIGHT** | 80% | 45°C | 10% |
| **BALANCED** | 70% | 40°C | 30% |
| **EXTREME** | 60% | 35°C | 50% |
| **ULTRA** | 50% | 35°C | 70% |

- Thermal monitoring every 2 seconds with 5°C hysteresis
- Auto-resume charging below 15% (safety)
- Sysfs interface: `/sys/kernel/infinity_charging/`
- IOCTL interface: `/dev/infinity-charging`

### Cross-ROM Compatibility

Works out of the box with:

- **MIUI** (V12–V15) — automatic DSI phyd patch applied only on MIUI
- **HyperOS** — full support, no MIUI patches applied
- **AOSP Custom ROMs** — LineageOS, crDroid, PixelExperience, Evolution X, and any other

ROM detection runs automatically in `anykernel.sh` and applies ROM-specific patches only when needed.

### Root Manager Support

Compatible with 6 root managers (module signature, vermagic, and SELinux bypass):

- **KernelSU**
- **KernelSU Next**
- **Magisk**
- **APatch**
- **ReSukiSu**
- **SukiSU Ultra**

Required kernel features: `KPROBES`, `UPROBES`, `FTRACE`, `DYNAMIC_FTRACE`, `DYNAMIC_FTRACE_WITH_REGS`, `BPF_SYSCALL`, `TRACER_SNAPSHOT`.

### SUFS v1.5.7+

Systemless UFS filesystem stub — enables SUFS overlay mount capabilities for advanced root managers at the kernel level.

---

## Project Structure

```
.
├── .circleci/
│   └── config.yml                  # CI pipeline (Proton Clang 17, auto-build)
├── AnyKernel3/
│   ├── META-INF/com/google/android/
│   │   └── update-binary           # AK3 entry point
│   ├── anykernel.sh                # Flash script with ROM detection
│   ├── banner                      # ASCII art
│   └── tools/
│       ├── ak3-core.sh             # AnyKernel3 core (osm0sis)
│       ├── magiskboot              # Boot image manipulator
│       ├── magiskpolicy            # SELinux policy patcher
│       ├── busybox                 # Embedded busybox
│       ├── fec                     # Flash erase counter
│       ├── httools_static          # Hardware tools
│       ├── lptools_static          # LP partition tools
│       ├── snapshotupdater_static  # Snapshot updater
│       ├── kyriepatch.sh           # MIUI DSI patch (MIUI-only)
│       └── infinity_init.sh        # Boot init (BBR, ZRAM, KSM, etc.)
├── arch/arm64/configs/
│   └── infinity_defconfig          # Kconfig fragment (merged on vayu_defconfig)
├── patches/
│   ├── 0001-cpu-scheduler-tuning.patch
│   ├── 0002-battery-power-optimization.patch
│   ├── 0003-fsync-io-optimization.patch
│   ├── 0004-gpu-adreno618-tuning.patch
│   ├── 0005-tcp-bbr-fastopen.patch
│   ├── 0006-root-manager-support.patch
│   └── 0007-sufs-support.patch
├── drivers/charging/
│   ├── infinity_charging_control.c  # Charging bypass platform driver
│   ├── Kconfig
│   └── Makefile
├── include/linux/
│   └── infinity_charging_control.h  # Driver header
├── scripts/charging_bypass/
│   └── infinity_charging.dts        # Device tree overlay
├── LICENSE                          # MIT License
└── README.md
```

---

## How to Build

### Automatic (CircleCI)

1. Push this repo to GitHub
2. Enable CircleCI for the repository
3. CI will automatically build on push to `main`, `master`, or `dev`
4. Download `InfinityKernel-v1.0.4-vayu.zip` from CircleCI artifacts

### Manual Build

```bash
# Clone this repo
git clone https://github.com/YOUR_USER/InfinityKernel.git
cd InfinityKernel

# Clone Xiaomi kernel source
git clone --depth=1 -b vayu-r-oss \
  https://github.com/MiCode/Xiaomi_Kernel_OpenSource.git kernel_src

# Apply patches (sed-based, works on any vayu-r-oss snapshot)
bash ../patches/apply_all.sh .

# Copy defconfig
cp ../arch/arm64/configs/infinity_defconfig arch/arm64/configs/

# Copy charging driver
cp -r ../drivers/charging drivers/infinity_charging
cp ../include/linux/infinity_charging_control.h include/linux/
echo 'obj-y += infinity_charging/' >> drivers/Makefile
echo 'source "drivers/infinity_charging/Kconfig"' >> drivers/Kconfig

# Download Proton Clang 17
wget -qO proton-clang.tar.gz \
  "https://github.com/kdrag0n/proton-clang/releases/download/17.0/proton-clang-17.tar.gz"
mkdir -p proton-clang && tar -xzf proton-clang.tar.gz -C proton-clang --strip-components=1

# Build
export PATH="$PWD/proton-clang/bin:$PATH"
export ARCH=arm64 SUBARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export CC=clang CLANG_TRIPLE=aarch64-linux-gnu-

make ARCH=$ARCH O=out infinity_defconfig
make -j$(nproc) ARCH=$ARCH O=out

# Package
cp out/arch/arm64/boot/Image.gz-dtb ../AnyKernel3/
cd ../AnyKernel3
zip -r9 ../InfinityKernel-v1.0.4-vayu.zip . -x ".git*" "patch/*" "ramdisk/*" "split_img/*"
```

---

## How to Flash

1. Download `InfinityKernel-v1.0.4-vayu.zip` from [Releases](../../releases)
2. Reboot to recovery (TWRP, OrangeFox, etc.)
3. Flash the ZIP
4. Reboot

### Charging Bypass Usage

```bash
# Set gaming mode (run as root)
echo 1 > /sys/kernel/infinity_charging/charging_mode   # LIGHT
echo 2 > /sys/kernel/infinity_charging/charging_mode   # BALANCED
echo 3 > /sys/kernel/infinity_charging/charging_mode   # EXTREME
echo 4 > /sys/kernel/infinity_charging/charging_mode   # ULTRA
echo 0 > /sys/kernel/infinity_charging/charging_mode   # OFF (normal)

# Check status
cat /sys/kernel/infinity_charging/status
cat /sys/kernel/infinity_charging/battery_temp
cat /sys/kernel/infinity_charging/battery_level

# Adjust thermal limit (Celsius)
echo 38 > /sys/kernel/infinity_charging/thermal_limit

# Adjust auto-resume threshold (percentage)
echo 20 > /sys/kernel/infinity_charging/auto_resume_threshold
```

---

## Kernel Source

Base source: [MiCode/Xiaomi_Kernel_OpenSource](https://github.com/MiCode/Xiaomi_Kernel_OpenSource/tree/vayu-r-oss) (`vayu-r-oss` branch)

This repository contains only the build configuration, patches, AnyKernel3 flasher, and custom drivers. The full kernel source is cloned at build time from the Xiaomi repository.

---

## Toolchain

- **Compiler**: [Proton Clang 17](https://github.com/kdrag0n/proton-clang) by kdrag0n
- **Kernel**: Linux 4.14 (from Xiaomi OSS)
- **Format**: AnyKernel3 by osm0sis

---

## Credits

- [Xiaomi](https://github.com/MiCode) — Kernel source
- [kdrag0n](https://github.com/kdrag0n) — Proton Clang
- [osm0sis](https://github.com/osm0sis) — AnyKernel3
- [topjohnwu](https://github.com/topjohnwu) — Magisk (tools)
- [tiann](https://github.com/tiann) — KernelSU reference

---

## License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

> **Note**: The kernel source from Xiaomi is under its own license. This repository's custom code (patches, drivers, scripts, AnyKernel3 configuration) is MIT-licensed.