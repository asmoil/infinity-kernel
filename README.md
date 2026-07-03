# Infinity Kernel v1.0.60

**Poco X3 Pro (vayu/bhima) | SM8150 | Linux 4.14.357**

Кастомное ядро на базе LineageOS `android_kernel_qcom_sm8150`, собранное через **CircleCI** с использованием **Neutron Clang** (tag `17062026`). Поставляется в формате **AnyKernel3**.

## Поддержка Android 11–16 QPR2+

Работает на: **AOSP**, **MIUI**, **HyperOS**, **OxygenOS** и кастомных ROM на базе AOSP.

## Multi-Root поддержка

Ядро поддерживает 5 root-решений. Выбор осуществляется через **pipeline parameters** в CircleCI при запуске билда:

| Root Solution | Repo | CI Parameter Value |
|---|---|---|
| **KernelSU-Next** | [KernelSU-Next/KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) | `kernelsu-next` (по умолчанию) |
| **ReSukiSU** | [ReSukiSU/ReSukiSU](https://github.com/ReSukiSU/ReSukiSU) | `resukisu` |
| **SukiSU-Ultra** | [SukiSU-Ultra/SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra) | `sukisu-ultra` |
| **KoWSu** | [deepongi-labs/KernelSU-KoWSU](https://github.com/deepongi-labs/KernelSU-KoWSU) | `kowsu` |
| **APatch** | [bmax121/APatch](https://github.com/bmax121/APatch) | `apatch` |
| Без root | — | `none` |

### Как выбрать root в CircleCI

При запуске билда в CircleCI UI, выберите значение параметра **`root-solution`** из выпадающего списка. По умолчанию используется `kernelsu-next`.

## Стек

- **Toolchain:** Neutron Clang `17062026` (clang-build-catalogue)
- **Root:** KernelSU-Next / ReSukiSU / SukiSU-Ultra / KoWSu / APatch
- **Stealth:** SuSFS v2.1.0
- **CI:** CircleCI (`ubuntu:24.04`, `resource_class: large`)
- **Формат:** AnyKernel3 (systemless flash)

## Оптимизации

- TCP BBR v2
- ZRAM 5 GB
- KSM (Kernel Samepage Merging)
- FSync
- I/O scheduler: BFQ / Maple
- Charging Control (5 режимов: OFF/ON/PAUSE/LIMIT/BYPASS)
- HZ_300

## Структура репозитория

```
.circleci/config.yml          — CI конфиг (v1.0.60)
arch/arm64/configs/           — Defconfig
include/linux/                — Заголовки
drivers/charging/             — Charging Control модуль
patches/                      — Патчи (apply_all.sh)
AnyKernel3/                   — Flasher (anykernel.sh + ak3-core.sh)
```

## Установка

1. Скачать ZIP из артефактов CircleCI
2. Прошить через TWRP / recovery
3. Перезагрузиться

## Сборка

```bash
# Автоматически через CircleCI — просто push в репозиторий
# Выбор root: Pipeline Settings → root-solution
```

## Лицензия

MIT