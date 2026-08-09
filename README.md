# Infinity Kernel

<p align="center">
  <b>Infinity Kernel v3.0.0</b> — кастомное ядро для Poco X3 Pro (vayu/bhima)<br>
  Clang/LLVM r547379 | KernelSU-Next + SuSFS | AnyKernel3 | Charging Bypass
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Device-Poco_X3_Pro_(vayu/bhima)-blue">
  <img src="https://img.shields.io/badge/Kernel-4.14.356+-green">
  <img src="https://img.shields.io/badge/Toolchain-Clang_LLVM_r547379_(15.0)-orange">
  <img src="https://img.shields.io/badge/Root-KernelSU_Next_+_SuSFS-red">
  <img src="https://img.shields.io/badge/License-MIT-lightgrey">
</p>

---

## Возможности

- **Clang/LLVM r547379 (branch 15.0)** — основной тулчейн вместо GCC
- **KernelSU-Next** — авто-клон из GitHub, встроен в ядро
- **SuSFS** — 14 опций антидетекта (скрытие файлов, маунтов, процессов, модулей)
- **Мульти-рут поддержка** — один универсальный бинарник для всех менеджеров:
  - `./build.sh kernelsu` — KernelSU-Next (дефолт)
  - `./build.sh apatch` — APatch (патчит образ при прошивке)
  - `./build.sh sukisu_ultra` — SuKisu Ultra
  - `./build.sh resukisu` — ReSUKISU
  - `./build.sh kowsu` — KoWSU
  - `./build.sh none` — без рута
- **Charging Bypass** — 4 режима (off/low/medium/high), авто-thermal cooldown
- **Infinity моды** — CPU governor, GPU gaming, TCP BBR, FSYNC, zRAM LZ4, VM tuning
- **7 upstream фиксов** — modpost, thermal_core, cam_trace, spi-xiaomi-tp и др.

## Быстрый старт

### GitHub Actions / CI

1. **Fork** этого репозитория
2. Включите **GitHub Actions** (Settings → Actions → General → Allow all actions)
3. Сделайте push — сборка запустится автоматически
4. Скачайте ZIP из **Artifacts**

### Локальная сборка

```bash
# 1. Клонируйте
 git clone https://github.com/asmoil/infinity-kernel.git
 cd infinity-kernel

# 2. Установите зависимости
 sudo apt install git make zip bc bison flex libssl-dev libelf-dev \
   python3 ccache aarch64-linux-gnu-gcc arm-linux-gnueabi-gcc sudo

# 3. Запустите сборку (дефолт: kernelsu, auto nproc)
 ./build.sh

# С указанием рут-менеджера и кол-ва потоков:
 ./build.sh apatch 8
 ./build.sh none 4

# Результат: out/InfinityKernel-v3.0.0-vayu.zip
```

## Структура репозитория

```
infinity-kernel/
├── build.sh                  # Основной билд-скрипт (Clang/LLVM, мульти-рут)
├── AnyKernel3/               # Шаблон flashable ZIP
│   ├── anykernel.sh          # AnyKernel3 flash script
│   ├── tools/
│   │   ├── ak3-core.sh       # AnyKernel3 core
│   │   ├── infinity_init.sh  # Boot-тюнинг (BBR, zRAM, KSM, VM)
│   │   ├── magiskboot        # Ramdisk unpack/pack
│   │   ├── magiskpolicy      # SELinux patcher
│   │   └── busybox           # Embedded busybox
│   ├── modules/              # Kernel modules (placeholder)
│   ├── patch/                # Patches (placeholder)
│   └── ramdisk/              # Ramdisk overrides (placeholder)
├── drivers/
│   └── charging/             # Charging Bypass драйвер
│       ├── Kconfig
│       ├── Makefile
│       └── infinity_charging_control.c
├── include/linux/
│   └── infinity_charging_control.h
├── arch/arm64/configs/
│   └── infinity_defconfig    # Базовый дефконфиг
├── patches/
│   └── apply_all.sh          # Скрипт применения патчей
├── scripts/
│   └── charging_bypass/
│       └── infinity_charging.dts
├── infinity-kernel/          # Legacy патчи и старые файлы
│   ├── patches/              # Git patches (9 штук)
│   ├── drivers/
│   │   ├── charging/
│   │   └── task_engine/
│   ├── include/linux/
│   └── scripts/
├── .github/                  # GitHub Actions / Issue templates
├── .circleci/                # CircleCI конфиг
├── .gitignore
├── LICENSE
└── README.md
```

## Управление (из системы)

```bash
# Charging bypass
echo 1 > /sys/devices/platform/.../infinity_charging/bypass_enable
echo 3 > /sys/devices/platform/.../infinity_charging/gaming_mode

# TCP BBR
echo bbr > /proc/sys/net/ipv4/tcp_congestion_control

# ZRAM (автоматически через infinity_init.sh)
cat /sys/block/zram0/comp_algorithm  # lz4
```

## Требования к сборке

| Компонент | Версия / источник |
|---|---|
| **OS** | Ubuntu 22.04+ / Debian 12+
| **Clang/LLVM** | r547379 branch 15.0 (авто-клон из crdroidandroid) |
| **GCC64** | aarch64-linux-gnu (для 32-bit ARM compat) |
| **GCC32** | arm-linux-gnueabi (для 32-bit ARM compat) |
| **Kernel source** | AnymoreProject/android_kernel_vayu (branch ksu, авто-клон) |
| **KernelSU-Next** | Auto-clone из GitHub |

## Основание

- [AnymoreProject/android_kernel_vayu](https://github.com/AnymoreProject/android_kernel_vayu) — ядро Linux 4.14.356+ (OPENELA upstream)
- [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next)
- [AnyKernel3](https://github.com/osm0sis/AnyKernel3)

## Лицензия

MIT License

## Автор

**Volchenok** — [github.com/asmoil/infinity-kernel](https://github.com/asmoil/infinity-kernel)
