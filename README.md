# Infinity Kernel

<p align="center">
  <b>Infinity Kernel</b> — кастомное ядро для Poco X3 Pro (vayu/bhima)<br>
  Оптимизация производительности + батарея | AnyKernel3 | Charging Bypass | Root Support
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Device-Poco_X3_Pro_(vayu/bhima)-blue">
  <img src="https://img.shields.io/badge/Kernel-4.14.180-green">
  <img src="https://img.shields.io/badge/CI-CircleCI-orange">
  <img src="https://img.shields.io/badge/License-GPL--2.0-lightgrey">
</p>

---

## Как использовать этот репозиторий

Это **форк** [MiCode/Xiaomi_Kernel_OpenSource](https://github.com/MiCode/Xiaomi_Kernel_OpenSource/tree/vayu-r-oss) (ветка `vayu-r-oss`, kernel 4.14.180).

### Быстрый старт

1. **Fork** этого репозитория на GitHub
2. Включите **CircleCI** в настройках репозитория (Settings → Integrations → CircleCI)
3. Сделайте push в ветку `main` или `vayu-r-oss` — сборка запустится автоматически
4. Скачайте готовый AnyKernel3 ZIP из **Artifacts** в CircleCI

### Локальная сборка

```bash
# 1. Клонируйте этот репозиторий
git clone https://github.com/YOUR_USERNAME/InfinityKernel.git
cd InfinityKernel

# 2. Установите toolchain
sudo apt install gcc-aarch64-linux-gnu make bc bison flex libssl-dev libelf-dev

# Или скачайте Proton Clang (рекомендуется):
wget https://github.com/kdrag0n/proton-clang/releases/download/17.0.2/proton-clang-17.0.2.tar.xz
tar -xf proton-clang-17.0.2.tar.xz
export PATH="$PWD/proton-clang/bin:$PATH"

# 3. Примените патчи
git apply --3way infinity-kernel/patches/*.patch

# 4. Установите кастомные файлы
cp infinity-kernel/drivers/charging/* drivers/charging/
cp infinity-kernel/include/linux/infinity_charging_control.h include/linux/
cp infinity-kernel/arch/arm64/configs/infinity_defconfig arch/arm64/configs/
echo 'source "drivers/charging/Kconfig"' >> drivers/Kconfig
echo 'obj-$(CONFIG_INFINITY_CHARGING_CONTROL)	+= charging/' >> drivers/Makefile

# 5. Соберите
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CLANG_TRIPLE=aarch64-linux-gnu- \
  CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm \
  OBJCOPY=llvm-objcopy STRIP=llvm-strip \
  infinity_defconfig -j$(nproc)

# 6. Результат: arch/arm64/boot/Image.gz
```

## Структура Infinity Kernel модификаций

Все кастомные файлы находятся в директории `infinity-kernel/`:

```
infinity-kernel/
├── arch/arm64/configs/
│   └── infinity_defconfig           # Конфигурация ядра
├── drivers/charging/
│   ├── Kconfig                      # Конфиг драйвера зарядки
│   ├── Makefile
│   ├── infinity_charging_control.c  # Драйвер (charging bypass)
│   └── infinity_charging_control.h  # (в include/linux/)
├── include/linux/
│   └── infinity_charging_control.h  # Public API
├── AnyKernel3/                      # Шаблон flashable ZIP
│   ├── META-INF/com/google/android/
│   ├── anykernel.sh
│   └── tools/infinity_init.sh       # Boot-тюнинг скрипт
├── patches/                         # Git patches (6 штук)
│   ├── 0001-INFINITY-cpu-performance-tuning.patch
│   ├── 0002-INFINITY-battery-optimization.patch
│   ├── 0003-INFINITY-fsync-io-scheduler.patch
│   ├── 0004-INFINITY-gpu-gaming-tweaks.patch
│   ├── 0005-INFINITY-network-bbr-fastopen.patch
│   └── 0006-INFINITY-root-manager-support.patch
└── scripts/
    ├── charging_bypass/
    │   └── infinity_charging.dts    # Device Tree overlay
    └── sufs/
        └── sufs_config.h            # SUFS конфигурация
```

## Функции

### Производительность
- **CPU**: Ondemand с оптимизированными порогами (65%/30%), input boost
- **GPU**: Min freq lock, thermal headroom, touch boost (Adreno 618)
- **I/O**: FSYNC, Kyber/MQ-deadline с низкими latency target
- **Сеть**: BBR congestion control, TCP Fast Open, somaxconn=4096

### Батарея
- **ZRAM**: 5GB с LZ4 компрессией
- **KSM**: Smart scanning intervals
- **VM**: dirty_ratio=15, vfs_cache_pressure=50, watermark tuning
- **Компакция**: proactiveness=20

### Charging Bypass (Gaming Mode)
- 4 режима: off / low (50% ток) / medium (мин. ток) / high (полный bypass)
- Авто-thermal cooldown при 45°C, resume при 40°C
- Безопасность: авто-зарядка при <15%
- Sysfs: `/sys/devices/platform/.../infinity_charging/`

### Root Manager Support
| Root | Поддержка |
|---|---|
| **KernelSU** | Kprobes/uprobes/ftrace экспортированы |
| **Magisk** | Ramdisk сохраняется в AnyKernel |
| **APatch (Sukisu Ultra)** | KernelPatch совместимость |
| **Resukisu** | Через KSU fork |

### SUFS
- OverlayFS, SquashFS (ZSTD/LZ4/LZO/XZ), F2FS с компрессией, NTFS3

## CircleCI

- **Полная сборка**: push в `main` или `vayu-r-oss` (AnyKernel3 ZIP артефакт)
- **Тест сборки**: push в другие ветки (только компиляция)
- **Resource class**: `large` (8 vCPU)
- **Toolchain**: Proton Clang 17 с ccache

## Управление

```bash
# Charging bypass
echo 1 > /sys/devices/platform/.../infinity_charging/bypass_enable
echo 3 > /sys/devices/platform/.../infinity_charging/gaming_mode

# GPU tuning
echo 500 > /sys/module/kgsl/parameters/infinity_min_freq_mhz
echo 1000 > /sys/module/kgsl/parameters/infinity_thermal_headroom_mc

# CPU boost
echo 1785600 > /sys/module/cpufreq/parameters/input_boost_freq
```

## Лицензия

GPL-2.0 (ядро Linux + модификации Xiaomi)

## Ссылки

- [Оригинальное ядро](https://github.com/MiCode/Xiaomi_Kernel_OpenSource/tree/vayu-r-oss)
- [AnyKernel3](https://github.com/osm0sis/AnyKernel3)
- [KernelSU](https://github.com/tiann/KernelSU)
- [Magisk](https://github.com/topjohnwu/Magisk)
- [APatch](https://github.com/bmax121/APatch)