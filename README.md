# Infinity Kernel

Кастомное ядро для **Poco X3 Pro** (vayu/bhima) на базе **LineageOS android_kernel_qcom_sm8150** (Linux 4.14.357, SM8150).

## О проекте

Infinity Kernel — это оптимизированное ядро для Poco X3 Pro, ориентированное на производительность, стабильность и расширенные возможности управления зарядом. Включает в себя KernelSU-Next для root-доступа и SuSFS для скрытия модификаций.

### Основные возможности

- **KernelSU-Next v3.2.0** — современный root-менеджер
- **SuSFS v2.1.0** — скрытие файловой системы от обнаружения
- **Neutron Clang** — оптимизированный тулчейн для лучшей производительности
- **Управление зарядом** — 5 режимов (OFF / ON / PAUSE / LIMIT / BYPASS) через sysfs и IOCTL
- **TCP BBR** — улучшенный алгоритм управления перегрузкой TCP
- **BFQ / Maple I/O** — оптимизированные планировщики ввода-вывода
- **ZRAM 5GB + KSM** — эффективное управление памятью
- **HZ_300** — таймер 300 Гц для лучшей отзывчивости
- **AnyKernel3** — простая установка через recovery (поддержка A/B слотов)

## Структура репозитория

```
.
├── .circleci/
│   └── config.yml                # CI: CircleCI (ubuntu:24.04, Neutron Clang)
├── .gitignore
├── arch/arm64/configs/
│   └── infinity_defconfig        # Конфигурация ядра
├── drivers/charging/
│   ├── Kconfig                   # Конфиг драйвера зарядки
│   ├── Makefile
│   └── infinity_charging_control.c  # Драйвер управления зарядом
├── include/linux/
│   └── infinity_charging_control.h  # Заголовочный файл драйвера
├── patches/
│   └── apply_all.sh              # Скрипт применения патчей
└── AnyKernel3/                   # Флешер для установки
    ├── anykernel.sh              # Конфигурация AnyKernel3
    ├── tools/
    │   ├── infinity_init.sh      # Пост-установка (BBR, ZRAM, KSM, VM)
    │   └── ...                   # Утилиты AnyKernel3
    └── META-INF/com/google/android/
        ├── update-binary
        └── updater-script
```

## Сборка

Сборка полностью автоматизирована через **CircleCI** (ubuntu:24.04, glibc 2.39). При пуше в репозиторий запускается CI, который:

1. Скачивает **Neutron Clang** (tag `17062026`)
2. Получает исходники ядра из `kernel_scr/` или клонирует [LineageOS sm8150](https://github.com/LineageOS/android_kernel_qcom_sm8150)
3. Интегрирует **KernelSU-Next v3.2.0** и **SuSFS v2.1.0**
4. Применяет конфигурацию, патчи и 11 source compat fixes
5. Собирает `Image.gz-dtb`
6. Упаковывает в AnyKernel3 ZIP и выкладывает как artifact

### Локальная сборка

```bash
# Клонировать репозиторий
git clone https://github.com/<твой-юзернейм>/infinity-kernel.git
cd infinity-kernel

# Подготовить исходники ядра (если нет локального kernel_scr/)
git clone --depth=1 https://github.com/LineageOS/android_kernel_qcom_sm8150 kernel_scr

# Скачать Neutron Clang
mkdir -p $HOME/tc
curl -sL "https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/download/17062026/neutron-clang-17062026.tar.zst" -o /tmp/neutron.tar.zst
tar -xf /tmp/neutron.tar.zst -C $HOME/tc --strip-components=1

# Установить зависимости (Ubuntu 24.04)
sudo apt-get install -y bc bison build-essential flex git libelf-dev liblz4-tool \
  libncurses-dev libssl-dev libxml2-utils lzop rsync schedtool \
  squashfs-tools xsltproc zip zlib1g-dev gcc-aarch64-linux-gnu \
  binutils-aarch64-linux-gnu gcc-arm-linux-gnueabi binutils-arm-linux-gnueabi zstd

# Собрать
export PATH="$HOME/tc/bin:$PATH"
export KERNEL_SRC="kernel_scr"

# Скопировать файлы ядра
REPO_DIR="$PWD"
cp -v "$REPO_DIR/arch/arm64/configs/infinity_defconfig" "$KERNEL_SRC/arch/arm64/configs/"
cp -v "$REPO_DIR/include/linux/infinity_charging_control.h" "$KERNEL_SRC/include/linux/"
cp -rv "$REPO_DIR/drivers/charging" "$KERNEL_SRC/drivers/"
cp -rv "$REPO_DIR/patches" "$KERNEL_SRC/patches"

# Конфигурация и сборка
cd "$KERNEL_SRC"
make ARCH=arm64 vendor/sm8150_defconfig O=out
scripts/kconfig/merge_config.sh -O out/ out/.config arch/arm64/configs/infinity_defconfig
make ARCH=arm64 olddefconfig O=out
make O=out ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu- \
  CROSS_COMPILE_COMPAT=arm-linux-gnueabi- AR=llvm-ar NM=llvm-nm \
  OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
  HOSTCC=gcc HOSTCFLAGS="-Wall -Wmissing-prototypes -Wstrict-prototypes \
  -O2 -fomit-frame-pointer -std=gnu89 -Wno-error" \
  KCFLAGS="-Wno-error" -j$(nproc) Image.gz-dtb dtbs
```

## Установка

1. Скачать `infinity-kernel-v1.0.58.zip` из **CircleCI Artifacts**
2. Перенести на телефон
3. Загрузиться в recovery (TWRP / OrangeFox)
4. Установить ZIP
5. Перезагрузиться

> **Важно**: ядро поддерживает A/B слоты (`is_slot_device=1`), установка системная (`do.systemless=1`).

## Управление зарядом

Драйвер заряда доступен через sysfs после установки:

```bash
# Текущий режим
cat /sys/class/power_supply/battery/charge_ctrl_mode

# Установить режим
echo "limit" > /sys/class/power_supply/battery/charge_ctrl_mode

# Установить лимит заряда (проценты)
echo "80" > /sys/class/power_supply/battery/charge_ctrl_limit
```

| Режим | Описание |
|-------|----------|
| `on` | Обычная зарядка (по умолчанию) |
| `off` | Зарядка отключена |
| `pause` | Пауза на текущем уровне |
| `limit` | Ограничение до заданного % |
| `bypass` | Напрямую от питания (без батареи) |

## Тюнинг (автоматический при установке)

Скрипт `infinity_init.sh` автоматически настраивает при первой загрузке:

- **TCP BBR** — алгоритм конгест-контроля
- **I/O Scheduler** — Maple (приоритет) / BFQ (запасной)
- **ZRAM** — 5 GB сжатой подкачки
- **KSM** — объединение одинаковых страниц памяти
- **VM** — dirty ratios, vfs_cache_pressure, swappiness=0, min_free_kbytes=4096

## Поддерживаемые устройства

| Устройство | Кодовое имя | SoC |
|-----------|-------------|-----|
| Poco X3 Pro | vayu / bhima | Snapdragon 860 (SM8150) |

## Стек

| Компонент | Версия |
|-----------|--------|
| Ядро | Linux 4.14.357 |
| Тулчейн | Neutron Clang (17062026) |
| Root | KernelSU-Next v3.2.0 |
| Стелс | SuSFS v2.1.0 |
| Установщик | AnyKernel3 |
| CI | CircleCI (ubuntu:24.04) |

## Лицензия

MIT