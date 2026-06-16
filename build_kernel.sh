#!/usr/bin/env bash
# ================================================================
#  build_kernel.sh  –  LawRun vayu  ·  KernelSU Next + SUSFS
#  Linux 4.14  ·  SM8150  ·  POCO X3 Pro (vayu / bhima)
#
#  Работает в двух режимах:
#    LOCAL:  запустить из директории ядра
#            ANYKERNEL_DIR=/path/to/this/repo ./build_kernel.sh
#    CI:     запустить из директории AnyKernel3 (CircleCI checkout)
#            KERNEL_DIR будет задан env-переменной или автоклонирован
# ================================================================
set -euo pipefail

# ── Directories ───────────────────────────────────────────────
# ANYKERNEL_DIR = каталог с anykernel.sh (этот репозиторий)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANYKERNEL_DIR="${ANYKERNEL_DIR:-$SCRIPT_DIR}"

# KERNEL_DIR = корень исходников ядра (с Makefile)
# Если не задан явно — используем pwd, иначе клонируем
KERNEL_DIR="${KERNEL_DIR:-$(pwd)}"
OUT_DIR="${OUT_DIR:-$KERNEL_DIR/out}"

# Kernel source — переопределить через env если нужен другой форк
KERNEL_SOURCE_URL="${KERNEL_SOURCE_URL:-https://github.com/negrroo/LawRun_xiaomi_sm8150_vayu}"
KERNEL_SOURCE_BRANCH="${KERNEL_SOURCE_BRANCH:-master}"

DEFCONFIG="vayu_defconfig"
ARCH="arm64"
JOBS=$(nproc --all)

# ── Toolchain ─────────────────────────────────────────────────
if [ -z "${CLANG_PATH:-}" ]; then
  for p in \
    /usr/lib/llvm-17/bin \
    /usr/lib/llvm-16/bin \
    /usr/lib/llvm-14/bin \
    /opt/toolchains/clang/bin; do
    [ -x "$p/clang" ] && { CLANG_PATH="$p"; break; }
  done
fi
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
CROSS_COMPILE_COMPAT="${CROSS_COMPILE_COMPAT:-arm-linux-gnueabi-}"

# ── Helpers ───────────────────────────────────────────────────
info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[ OK ]\033[0m  $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
die()   { echo -e "\033[1;31m[FAIL]\033[0m  $*"; exit 1; }

# ================================================================
# Step 0: Клонировать исходники ядра (если не найдены)
# ================================================================
clone_kernel_source() {
  # Если KERNEL_DIR совпадает с ANYKERNEL_DIR — это CI-режим,
  # ядро надо клонировать в отдельную папку рядом
  if [ "$KERNEL_DIR" = "$ANYKERNEL_DIR" ]; then
    KERNEL_DIR="$(dirname "$ANYKERNEL_DIR")/kernel_src"
    OUT_DIR="$KERNEL_DIR/out"
    info "CI mode: KERNEL_DIR → $KERNEL_DIR"
  fi

  if [ -f "$KERNEL_DIR/Makefile" ]; then
    info "Kernel source: found at $KERNEL_DIR"
    return
  fi

  info "Kernel source не найден — клонируем..."
  info "URL:    $KERNEL_SOURCE_URL"
  info "Branch: $KERNEL_SOURCE_BRANCH"

  mkdir -p "$(dirname "$KERNEL_DIR")"

  # GIT_TERMINAL_PROMPT=0  → запрет интерактивного логина (критично для CI)
  # credential.helper=""   → отключить системный credential helper
  # Без этого git в non-TTY окружении (CircleCI) зависает на вводе пароля
  info "git clone (no-auth, depth=1, branch=$KERNEL_SOURCE_BRANCH) …"
  if ! GIT_TERMINAL_PROMPT=0 git clone \
       --depth=1 \
       --config "credential.helper=" \
       --branch "$KERNEL_SOURCE_BRANCH" \
       "$KERNEL_SOURCE_URL" \
       "$KERNEL_DIR" 2>&1; then

    warn "Клон ветки '$KERNEL_SOURCE_BRANCH' не удался — пробуем default branch …"
    rm -rf "$KERNEL_DIR"
    GIT_TERMINAL_PROMPT=0 git clone \
      --depth=1 \
      --config "credential.helper=" \
      "$KERNEL_SOURCE_URL" \
      "$KERNEL_DIR" \
    || die "Не удалось клонировать ядро из $KERNEL_SOURCE_URL
  Проверьте:
    1. Репозиторий публичный (github.com > Settings > Visibility: Public)
    2. Ветка существует: git ls-remote --heads $KERNEL_SOURCE_URL
  Переопределить через env:
    export KERNEL_SOURCE_URL=https://github.com/negrroo/LawRun_xiaomi_sm8150_vayu
    export KERNEL_SOURCE_BRANCH=master"
  fi

  ok "Kernel source клонирован."
}

# ================================================================
# Step 1: KernelSU Next
# ================================================================
setup_ksu() {
  info "Setting up KernelSU Next …"

  local ksu_dir="$KERNEL_DIR/KernelSU"

  if [ -d "$ksu_dir/kernel" ]; then
    info "KernelSU Next: уже присутствует."
    return
  fi

  info "Cloning KernelSU Next …"
  # Попробуем как submodule, иначе — прямой clone
  GIT_TERMINAL_PROMPT=0 git -C "$KERNEL_DIR" submodule update --init --recursive 2>/dev/null || \
  GIT_TERMINAL_PROMPT=0 git clone --depth=1 \
    --config "credential.helper=" \
    https://github.com/KernelSU-Next/KernelSU \
    "$ksu_dir" \
    || die "Не удалось клонировать KernelSU Next"

  # Запускаем setup.sh если он есть (прописывает хуки в Makefile)
  if [ -f "$ksu_dir/kernel/setup.sh" ]; then
    bash "$ksu_dir/kernel/setup.sh" -o "$ksu_dir" 2>/dev/null || true
  fi

  ok "KernelSU Next ready."
}

# ================================================================
# Step 2: SUSFS 1.5.5 MOD legacy patch  (Linux 4.14)
# ================================================================

# Загрузить патч автоматически — несколько источников
download_susfs_patch() {
  local target="$1"
  mkdir -p "$(dirname "$target")"

  info "Автозагрузка SUSFS patch для Linux 4.14 …"

  # ── Источник A: клонируем susfs4ksu и берём патч ─────────────
  local tmp_repo
  tmp_repo=$(mktemp -d)
  if GIT_TERMINAL_PROMPT=0 git clone --depth=1 \
       --config "credential.helper=" \
       https://github.com/sidex15/susfs4ksu-begonia.git \
       "$tmp_repo/repo" 2>/dev/null; then

    # Ищем любой патч для 4.14 в kernel_patches/
    local found
    # Приоритет: явные имена, потом glob
    for candidate in \
      "$tmp_repo/repo/kernel_patches/50_add_susfs_in_kernel-4.14.patch" \
      "$tmp_repo/repo/kernel_patches/add_susfs_in_kernel-4.14.patch" \
      $(find "$tmp_repo/repo/kernel_patches" -name "*4.14*.patch" 2>/dev/null | sort | head -1) \
      $(find "$tmp_repo/repo/kernel_patches" -name "*4.14*"       2>/dev/null | sort | head -1)
    do
      if [ -f "$candidate" ] && grep -q "susfs" "$candidate" 2>/dev/null; then
        found="$candidate"
        break
      fi
    done

    if [ -n "$found" ]; then
      cp "$found" "$target"
      rm -rf "$tmp_repo"
      ok "SUSFS patch: $(basename "$found")  (из susfs4ksu репозитория)"
      return 0
    fi
    warn "susfs4ksu клонирован, но патч для 4.14 не найден в kernel_patches/"
  else
    warn "Не удалось клонировать susfs4ksu — пробуем прямые URL"
  fi
  rm -rf "$tmp_repo"

  # ── Источник B: прямые URL известных релизов ─────────────────
  local urls=(
    "https://raw.githubusercontent.com/sidex15/susfs4ksu/main/kernel_patches/50_add_susfs_in_kernel-4.14.patch"
    "https://raw.githubusercontent.com/sidex15/susfs4ksu/main/kernel_patches/add_susfs_in_kernel-4.14.patch"
    "https://raw.githubusercontent.com/sidex15/susfs4ksu/kernel-4.14/kernel_patches/add_susfs_in_kernel.patch"
  )
  for url in "${urls[@]}"; do
    if curl -fsSL --retry 3 --retry-delay 2 -o "$target" "$url" 2>/dev/null; then
      if [ -s "$target" ] && grep -q "susfs" "$target" 2>/dev/null; then
        ok "SUSFS patch загружен: $url"
        return 0
      fi
      rm -f "$target"
    fi
  done

  # ── Источник не найден ─────────────────────────────────────────
  die "Не удалось загрузить SUSFS patch для Linux 4.14.

  Положите патч вручную:
    mkdir -p $KERNEL_DIR/patches
    cp /path/to/susfs-4.14.patch \\
       $KERNEL_DIR/patches/susfs-1.5.5-mod-linux-4.14.patch

  Или укажите рабочий URL репозитория:
    export SUSFS_PATCH_URL=https://raw.githubusercontent.com/...
  и перезапустите скрипт."
}

apply_susfs_patch() {
  info "SUSFS 1.5.5 MOD legacy patch …"

  SUSFS_MARKER="$KERNEL_DIR/.susfs_applied"
  if [ -f "$SUSFS_MARKER" ]; then
    info "SUSFS: уже применён (найден маркер $SUSFS_MARKER)"
    return
  fi

  SUSFS_PATCH="${SUSFS_PATCH:-$KERNEL_DIR/patches/susfs-1.5.5-mod-linux-4.14.patch}"

  # ── Автозагрузка если файла нет ──────────────────────────────
  if [ ! -f "$SUSFS_PATCH" ]; then
    download_susfs_patch "$SUSFS_PATCH"
  else
    info "SUSFS patch найден: $SUSFS_PATCH"
  fi

  # ── Минимальная валидация ─────────────────────────────────────
  if ! grep -q "susfs" "$SUSFS_PATCH" 2>/dev/null; then
    die "Файл '$SUSFS_PATCH' не содержит SUSFS-кода. Патч повреждён."
  fi

  # ── Применить ────────────────────────────────────────────────
  info "Применяем патч …"
  cd "$KERNEL_DIR"
  # --forward: пропустить если хотя бы частично уже применён
  # --reject-file: сохранить отклонённые хаймы для отладки
  if ! patch -p1 --forward < "$SUSFS_PATCH"; then
    # Проверяем — может уже частично применён
    if patch -p1 --dry-run --forward < "$SUSFS_PATCH" 2>&1 | grep -q "Reversed"; then
      warn "Патч уже применён (reverse-check пройден) — продолжаем."
    else
      die "SUSFS patch не применился. Проверьте .rej файлы в $KERNEL_DIR"
    fi
  fi

  touch "$SUSFS_MARKER"
  ok "SUSFS patch применён."
}

# ================================================================
# Step 3: Слияние конфига
# ================================================================
merge_config() {
  info "Merging KSU+SUSFS config …"
  cd "$KERNEL_DIR"

  local fragment="$ANYKERNEL_DIR/kernel_config/vayu_ksu_susfs.config"
  [ -f "$fragment" ] || die "Не найден конфиг-фрагмент: $fragment"

  make O="$OUT_DIR" ARCH=$ARCH $DEFCONFIG
  scripts/kconfig/merge_config.sh -m -O "$OUT_DIR" \
    "$OUT_DIR/.config" \
    "$fragment"

  yes "" | make O="$OUT_DIR" ARCH=$ARCH olddefconfig
  ok "Config merged."
}

# ================================================================
# Step 4: Сборка ядра
# ================================================================
build_kernel() {
  info "Building kernel (jobs: $JOBS) …"

  local build_flags=(
    O="$OUT_DIR"
    ARCH="$ARCH"
    -j"$JOBS"
  )

  if [ -n "${CLANG_PATH:-}" ] && [ -x "$CLANG_PATH/clang" ]; then
    info "Compiler: Clang ($CLANG_PATH)"
    build_flags+=(
      CC="$CLANG_PATH/clang"
      CLANG_TRIPLE="aarch64-linux-gnu-"
      CROSS_COMPILE="$CROSS_COMPILE"
      CROSS_COMPILE_COMPAT="$CROSS_COMPILE_COMPAT"
      LD="$CLANG_PATH/ld.lld"
      AR="$CLANG_PATH/llvm-ar"
      NM="$CLANG_PATH/llvm-nm"
      OBJCOPY="$CLANG_PATH/llvm-objcopy"
      OBJDUMP="$CLANG_PATH/llvm-objdump"
      STRIP="$CLANG_PATH/llvm-strip"
    )
  else
    warn "Clang не найден — пытаемся установить LLVM/Clang"
    if command -v clang >/dev/null 2>&1; then
      build_flags+=(CC="clang" LD="ld.lld")
    else
      echo "ERROR: clang toolchain not found"
      exit 1
    fi
    build_flags+=(
      CROSS_COMPILE="$CROSS_COMPILE"
      CROSS_COMPILE_COMPAT="$CROSS_COMPILE_COMPAT"
    )
  fi

  cd "$KERNEL_DIR"
  make "${build_flags[@]}" Image.gz-dtb dtbs

  local img="$OUT_DIR/arch/arm64/boot/Image.gz-dtb"
  [ -f "$img" ] || die "Ядро не собралось: $img не найден"
  ok "Kernel: $img  ($(du -sh "$img" | cut -f1))"
}

# ================================================================
# Step 5: Упаковка AnyKernel3 ZIP
# ================================================================
pack_zip() {
  info "Packing AnyKernel3 flash ZIP …"

  [ -f "$ANYKERNEL_DIR/anykernel.sh" ] || \
    die "anykernel.sh не найден в $ANYKERNEL_DIR"

  cp -v "$OUT_DIR/arch/arm64/boot/Image.gz-dtb" "$ANYKERNEL_DIR/Image.gz-dtb"

  local ts zip_name zip_out
  ts=$(date +%Y%m%d_%H%M)
  zip_name="TurboOS_KSU_SUSFS_vayu_A13-A16_${ts}.zip"
  zip_out="$ANYKERNEL_DIR/$zip_name"

  cd "$ANYKERNEL_DIR"
  zip -r9 "$zip_out" \
    anykernel.sh \
    Image.gz-dtb \
    META-INF/ \
    tools/ \
    modules/ \
    patch/ \
    ramdisk/ \
    -x "*.git*" \
    -x "kernel_config/*" \
    -x "build_kernel.sh" \
    -x "*.placeholder" \
    -x "*.md" \
    -x ".circleci/*" \
    -x "SUSFS_FIX_README.md"

  ok "ZIP: $zip_out  ($(du -sh "$zip_out" | cut -f1))"

  # Для CircleCI — сохраняем путь в файл для шага store_artifacts
  echo "$zip_out" > "$ANYKERNEL_DIR/.last_zip_path"
}

# ================================================================
# Main
# ================================================================
main() {
  info "=== LawRun vayu  KSU+SUSFS build ==="
  info "ANYKERNEL_DIR: $ANYKERNEL_DIR"
  info "KERNEL_DIR:    $KERNEL_DIR (до клонирования может измениться)"
  echo ""

  clone_kernel_source   # клонировать если нет
  info "KERNEL_DIR (final): $KERNEL_DIR"

  setup_ksu
  apply_susfs_patch
  merge_config
  build_kernel
  pack_zip

  ok "=== All done! ==="
}

main "$@"

# CI non-interactive config
export KCONFIG_NONINTERACTIVE=1
