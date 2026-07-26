# Infinity Kernel v1.0.104

**Poco X3 Pro (vayu/bhima) | SM8150 | Linux 4.14.357**

Кастомное ядро на базе LineageOS `android_kernel_xiaomi_sm8150` (branch `lineage-18.1`), собираемое через локальный `build.sh` или **CircleCI** с использованием **Neutron Clang** (tag `17062026`, fallback на GCC 15.2.0 при отсутствии AVX2) и **AnyKernel3** для systemless-установки.

## Поддержка Android 11–16 QPR2+

Работает на: **AOSP**, **MIUI**, **HyperOS**, **OxygenOS**, **LineageOS**, **PixelOS**, **EvolutionX** и любых ROM на базе AOSP Android 11+.

## Multi-Root поддержка

Ядро поддерживает 7 root-решений. Все KernelSU-форки используют **одинаковый** kernel-side протокол (`ksu_*` hooks), поэтому один ZIP работает с любым SU-менеджером. APatch имеет другой механизм и требует отдельной сборки.

| Root Solution | CLI алиасы | Repo | Описание |
|---|---|---|---|
| **KernelSU-Next** (по умолчанию) | `kernelsu`, `kernelsu_next`, `ksu` | [KernelSU-Next/KernelSU](https://github.com/KernelSU-Next/KernelSU) | Самый актуальный форк KSU |
| **ReSukiSU** | `resukisu`, `re-sukisu`, `resuki` | [ReSukiSU/ReSukiSU](https://github.com/ReSukiSU/ReSukiSU) | Форк с расширенными stealth-функциями |
| **SukiSU-Ultra** | `sukisu`, `sukisu_ultra`, `suki` | [SukiSU-Ultra/SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra) | Оптимизированный форк |
| **KoWSu** | `kowsu`, `kow` | [deepongi-labs/KernelSU-KoWSU](https://github.com/deepongi-labs/KernelSU-KoWSU) | Минималистичный форк |
| **APatch** | `apatch` | [bmax121/APatch](https://github.com/bmax121/APatch) | Альтернативный root (модульный) |
| Без root | `none`, `no-root`, `noroot` | — | Чистое ядро без SU |

### Команды запуска

```bash
./build.sh                    # по умолчанию: kernelsu (для всех KSU-менеджеров)
./build.sh kernelsu           # явно
./build.sh sukisu_ultra       # SukiSU-Ultra (тот же kernel-side, другой label в логе)
./build.sh resukisu           # ReSukiSU
./build.sh kowsu              # KoWSu
./build.sh apatch             # APatch (отдельная сборка)
./build.sh none               # без root
./build.sh kernelsu 4         # явно указать число потоков (по умолчанию = nproc)
```

## Стек

- **Toolchain:** Neutron Clang `17062026` (clang-build-catalogue)
  - Fallback на GCC 15.2.0 (`aarch64-linux-gnu-gcc`) если CPU не поддерживает AVX2
- **Root:** KernelSU-Next / ReSukiSU / SukiSU-Ultra / KoWSu / APatch / none
- **Stealth:** SuSFS v2.2.0 (`CONFIG_KSU_SUSFS*` — sus_path, sus_mount, spoof_uname, sus_kstat, sus_maps, sus_memfd, sus_proc_fd_link)
- **CI:** CircleCI (`ubuntu:24.04`, `resource_class: large`)
- **Формат:** AnyKernel3 (systemless flash через TWRP/OrangeFox recovery)

## Оптимизации

Все 25 патчей из `patches/` применяются автоматически:

### CPU
- CPU performance tuning (большая/маленькая архитектура, Prime core)
- Scheduler big.LITTLE touch-boost для геймминга
- CPU scheduler tuning (EAS / WALT)
- CPU tuning optimizations

### Battery / Power
- Battery optimization (doze, wakelocks, wakeup_sources)
- Battery power optimization (smb5-lib, charger)
- WakeLock battery optimization

### I/O / GPU
- FSync + I/O scheduler (BFQ / Maple)
- GPU Adreno 620 tuning (Adreno618 для gaming)
- GPU gaming tweaks

### Network
- TCP BBR v1 + FastOpen
- TCP BBR v2 (advanced congestion control)
- Network BBR + TCP Fast Open

### Memory
- 8GB VM optimization (zram, swap, ksm)
- Memory low-latency для gaming

### Audio / Input
- Audio low-latency gaming (wcd-mbhc-v2, pcm512x)
- Input latency gaming (touchscreen, touchboost)

### Root / Stealth
- Root manager support (KernelSU + все форки)
- SuSFS support (sus_path, sus_mount, sus_kstat, sus_maps, sus_memfd, spoof_uname)

## Charging Control

Кастомный модуль `drivers/charging/infinity_charging_control.c` с 5 режимами:
- **OFF** — зарядка отключена
- **ON** — нормальная зарядка
- **PAUSE** — пауза зарядки (для bypass)
- **LIMIT** — ограничение по уровню (например, до 80%)
- **BYPASS** — bypass зарядки (питание от USB без зарядки батареи)

Управление через sysfs: `/sys/class/infinity/charging/mode`

## Дополнительные возможности

- **HZ_300** — частота таймера для баланса производительность/батарея
- **ZRAM 5 GB** — сжатие памяти (LZ4)
- **KSM** — Kernel Samepage Merging (дедупликация памяти)
- **CPU masks:** LITTLE=0x0F (CPU0-3 A55), BIG=0x70 (CPU4-6 A76), PRIME=0x80 (CPU7 A76)
- **CONFIG_SECTION_MISMATCH_WARN_ONLY=y** — для совместимости с GCC 15

## Структура репозитория

```
build.sh                      — Главный скрипт сборки (v1.0.104, ~1900 строк)
build_kernel.sh               — Альтернативный скрипт сборки (для CI)
arch/arm64/configs/           — infinity_defconfig
include/linux/                — Заголовки (infinity_charging_control.h)
drivers/charging/             — Charging Control модуль
patches/                      — 24 патча + apply_all.sh
  0001-cpu-*.patch            — CPU оптимизации
  0002-battery-*.patch        — Battery/power оптимизации
  0003-fsync-*.patch          — FSync + I/O scheduler
  0004-gpu-*.patch            — GPU Adreno tuning
  0005-network-*.patch        — TCP BBR + FastOpen
  0006-root-*.patch           — Root manager support
  0007-susfs-*.patch          — SuSFS stealth
  0008-scheduler-*.patch      — Scheduler touch-boost
  0009-input-*.patch          — Input latency gaming
  0010-memory-*.patch         — Memory 8GB VM
  0011-wakelock-*.patch       — WakeLock battery
  0012-audio-*.patch          — Audio low-latency
scripts/                      — Вспомогательные скрипты
  apply_patches.sh            — Альтернативный applyer
  charging_bypass/            — DTS для bypass зарядки
  sufs/                       — SuFS конфигурация
AnyKernel3/                   — Flasher (anykernel.sh + ak3-core.sh + tools/)
  tools/                      — busybox, magiskboot, magiskpolicy, fec, ...
  modules/                    — placeholder для модулей
  ramdisk/                    — placeholder для ramdisk-патчей
  patch/                      — placeholder для overlay-патчей
.circleci/config.yml          — CI конфигурация
.github/workflows/build.yml   — GitHub Actions (опционально)
```

## Установка

### Через recovery (рекомендуется)

1. Скачать `InfinityKernel-1.0.104-vayu.zip` из `out/`
2. Скопировать на устройство
3. Загрузиться в TWRP / OrangeFox / любой recovery
4. Flash ZIP
5. Перезагрузка

### Через fastboot

```bash
fastboot flash boot boot.img
fastboot reboot
```

`boot.img` генерируется скриптом автоматически (требуется `mkbootimg`).

## Сборка локально

### Требования

- Ubuntu 22.04 / 24.04 / 26.04 LTS
- ~10 GB свободного места
- `sudo` права (для bind mount и apt-get install)
- Internet (для git clone kernel source + SuSFS + KernelSU + Neutron Clang)

### Запуск

```bash
# 1. Распаковать релизный ZIP в любую папку (даже с пробелами/Cyrillic)
cd ~/Рабочий стол/infinity-kernel

# 2. Запустить сборку
./build.sh kernelsu

# 3. Дождаться завершения (30-90 минут в зависимости от CPU)
# 4. Забрать результат:
#    - out/InfinityKernel-1.0.104-vayu.zip  (для recovery)
#    - boot.img                              (для fastboot)
# 5. Лог сборки: infinity_build.log
```

### Особенности путей с пробелами

Скрипт поддерживает пути с пробелами и Cyrillic (например, `~/Рабочий стол/infinity-kernel`) через **bind mount**:
- Источник остаётся в папке пользователя
- Сборка выполняется через `/tmp/infinity-kbuild` (без пробелов)
- `getcwd()` возвращает путь монтирования — `$(CURDIR)` корректно работает в sub-Makefiles
- Автоматический cleanup через trap при выходе

### Neutron Clang vs GCC

Скрипт автоматически определяет поддержку **AVX2** на CPU:
- **AVX2 поддерживается** → Neutron Clang (быстрее, оптимизирован под ARM)
- **AVX2 НЕ поддерживается** (старые CPU, например i5-3337U) → GCC 15.2.0

На CPU без AVX2 Neutron Clang падает с `Illegal instruction (core dumped)`, поэтому fallback на GCC обязателен.

## Совместимость с GCC 15

Linux 4.14 написан для GCC 6-9. GCC 15 включает новые warnings, которые ломают сборку. Скрипт применяет 22 compat-фикса:

1. `filter.h` — `compat_sock_fprog` под `CONFIG_COMPAT`
2. `hugetlbpage.c` — `ptep` → `pte`
3. `huge_memory.c` — `try_to_unmap(page, ttu_flags, NULL)`
4. `khugepaged.c` — `atomic_long_dec(&mm->nr_ptes)`
5. `sock.c` — `compat_timeval` (с `#ifndef` guard)
6. `net/compat.c` — обёрнут в `#ifdef CONFIG_COMPAT`
7. `fs/compat.c` — обёрнут в `#ifdef CONFIG_COMPAT`
8. `task_mmu.c` — `pmd_t` pointer cast
9. `fault-inject.c` — `should_fail_ex` signature
10. `pinctrl` includes (targeted)
11. `iommu-debug.c` stub
12. `KCFLAGS` для suppression warnings
13. `modpost.c` — `#pragma GCC diagnostic ignored "-Wstringop-overflow"`
14. `compiler_types.h` — `__has_attribute` guard
15. `lpm-levels.c` — missing includes
16. `sde_crtc.c` — `CLKFLAG_NORETAIN_MEM`/`CLKFLAG_RETAIN_MEM` defines
17. `dma-mapping.c` — `__maybe_unused` для static functions
18. `thread_info.h` — strip `__compiletime_error` (GCC 15 false positive)
19. `wcd-mbhc-v2.c` — `->input_dev` → `NULL` (Qualcomm techpack compat)
20. `hid-trace.h` — `CFLAGS_hid-trace.o += -I$(src)` (trace include path)
21. `ipa_v3/Makefile` — `ccflags-y += -I$(src)` (ipa_i.h parent-dir include)
22. `fs/open.c` — Manual SuSFS Hunk #3 injection (faccessat sus_path)

Дополнительно в `KCFLAGS`:
```
-Wno-error -Wno-implicit-function-declaration -Wno-int-conversion
-Wno-shadow -Wno-unused-function -Wno-format -Wno-array-bounds
-Wno-address -Wno-builtin-declaration-mismatch -Wno-stringop-overflow
-Wno-maybe-uninitialized -Wno-packed-not-aligned
```

## Логирование

Полный лог пишется в `infinity_build.log` через `exec > >(tee -a) 2>&1` — весь stdout/stderr дублируется и в терминал, и в файл. Лог содержит:
- Все шаги (Step 0-14)
- Все применённые патчи (Step 9)
- Все compat-фиксы (Step 10, Fix 1-22)
- Все warnings/error компиляции
- Финальный статус и пути к артефактам

## История версий

| Версия | Ключевые изменения |
|---|---|
| **v1.0.104** | Fix: patches/ absolute path, CONFIG_SECTION_MISMATCH_WARN_ONLY, cleanup Fix 21 |
| v1.0.103 | Восстановлен полный репо (patches/, scripts/, полный AnyKernel3/) |
| v1.0.102 | Manual injection SuSFS Hunk #3 (faccessat) для SM8150 |
| v1.0.101 | Fix ipa_i.h parent-dir include (ipa_v3/Makefile) |
| v1.0.100 | Fix compat_timeval redefinition + hid-trace.h include |
| v1.0.99 | Bind mount (решение проблемы путей с пробелами) |
| v1.0.97 | Multi-root CLI: kernelsu/resukisu/sukisu/kowsu/apatch/none |
| v1.0.96 | CONFIG_KSU_SUSFS* name fix |
| v1.0.95 | In-tree build (без O=out) |
| v1.0.94 | Removed set -e silent-exit bug |

## Устранение проблем

### `Patches: 0 applied, 0 failed`
Проверьте, что папка `patches/` существует рядом с `build.sh`. v1.0.104 использует абсолютный путь `$SCRIPT_DIR/patches/`, так что патчи найдутся независимо от CWD.

### `FATAL: modpost: Section mismatches detected`
v1.0.104 форсирует `CONFIG_SECTION_MISMATCH_WARN_ONLY=y`. Если ошибка осталась — проверьте `.config` после сборки.

### `Bind mount failed`
Запустите вручную: `sudo mount --bind "$PWD/kernel_src" /tmp/infinity-kbuild`, затем `./build.sh kernelsu`.

### `Illegal instruction (core dumped)` на Neutron Clang
CPU без AVX2. Скрипт автоматически определит это и переключится на GCC 15.2.0.

### `ipa_i.h: No such file or directory`
Fix 21b добавляет `ccflags-y += -I$(src)` в `drivers/platform/msm/ipa/ipa_v3/Makefile`. Если ошибка остаётся — проверьте, что Makefile существует и патч применился (смотрите лог).

### `SuSFS Hunk #3 FAILED at fs/open.c`
v1.0.102+ автоматически впрыскивает sus_path-блок в `SYSCALL_DEFINE3(faccessat)` через head/tail+heredoc. См. Step 10.7c в логе.

## Лицензия

MIT
