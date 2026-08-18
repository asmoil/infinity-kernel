#!/usr/bin/env bash
# Infinity Kernel v4.0.0 - Main Build Script
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

# ============================================
# Configuration
# ============================================
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
KERNEL_NAME="InfinityKernel"
VERSION="4.0.0"
DEVICE="vayu"
DEVICE_ALT="bhima"
BASE_KERNEL="https://github.com/AnymoreProject/android_kernel_vayu"
OUT_DIR="${BASE_DIR}/out"
CCACHE_DIR="${BASE_DIR}/ccache"

# Toolchain
NEUTRON_URL="https://github.com/NeutronClangToolchain/clang-build/releases/download/20250430/clang-build-20250430.tar.zst"
PROTON_URL="https://github.com/AbyzKrai/proton-clang/releases/download/20.0.0/proton-clang-20-0-0.tar.gz"

# Root
KSU_URL="https://github.com/KernelSU-Next/kernel-su-next"
KSU_TAG="v3.3.0"
APATCH_URL="https://github.com/bmax121/APatch"
APATCH_TAG="0.10.3"

# SUSFS
SUSFS_URL="https://github.com/vm03/susfs"
SUSFS_TAG="v2.2.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RST='\033[0m'

# ============================================
# Helpers
# ============================================
banner() {
    echo -e "${CYAN}"
    echo '     _  _   __   ___  _  _  ____  ____  _  _  _  _  ____  ____'
    echo '    / )( \ / _\ / __)/ )( \(___ \(  __)/ )( \( \/  )(  _ \(  __ \'
    echo '    ) __ (/    ( (__ ) \\ ( / __/ ) _) ) \\ ( / \\ \\ )   / )   / ) _) )'
    echo '    \_)(_/\_\_/ \___)\_)(/(____)(__)  \_)(_/ \_)(_/(__\_)(____)'
    echo -e "${RST}"
    echo -e "${GREEN}    ${KERNEL_NAME} v${VERSION} | ${DEVICE}/${DEVICE_ALT}${RST}"
    echo ""
}

log()  { echo -e "${GREEN}[INF]${RST} $*"; }
warn() { echo -e "${YELLOW}[WRN]${RST} $*"; }
err()  { echo -e "${RED}[ERR]${RST} $*"; exit 1; }

# ============================================
# Validate arguments
# ============================================
validate_args() {
    local valid_roots=("kernelsu" "apatch" "sukisu_ultra" "resukisu" "kowsu" "none")
    local valid_variants=("miui" "hyperos" "aosp")
    local valid_extras=("" "clean" "ziponly")

    local found=0
    for r in "${valid_roots[@]}"; do [[ "$ROOT_TYPE" == "$r" ]] && found=1 && break; done
    [[ $found -eq 0 ]] && err "Invalid root type: $ROOT_TYPE. Valid: ${valid_roots[*]}"

    found=0
    for v in "${valid_variants[@]}"; do [[ "$VARIANT" == "$v" ]] && found=1 && break; done
    [[ $found -eq 0 ]] && err "Invalid variant: $VARIANT. Valid: ${valid_variants[*]}"

    [[ -n "$EXTRA" ]] && {
        found=0
        for e in "${valid_extras[@]}"; do [[ "$EXTRA" == "$e" ]] && found=1 && break; done
        [[ $found -eq 0 ]] && err "Invalid extra: $EXTRA. Valid: clean, ziponly"
    }
}

# ============================================
# Setup toolchain
# ============================================
setup_toolchain() {
    local tc_dir="${BASE_DIR}/toolchain"
    [[ -d "$tc_dir/bin" ]] && { log "Toolchain already exists"; return 0; }

    log "Downloading Neutron Clang..."
    mkdir -p "$tc_dir"
    local tmp="${BASE_DIR}/.tc_tmp"
    mkdir -p "$tmp"
    if curl -sL "${NEUTRON_URL}" -o "${tmp}/tc.tar.zst" && which zstd &>/dev/null; then
        zstd -d "${tmp}/tc.tar.zst" -o "${tmp}/tc.tar" 2>/dev/null && \
        tar xf "${tmp}/tc.tar" -C "$tc_dir" --strip-components=1 && \
        log "Neutron Clang ready"
    elif curl -sL "${PROTON_URL}" -o "${tmp}/tc.tar.gz"; then
        tar xzf "${tmp}/tc.tar.gz" -C "$tc_dir" --strip-components=1 && \
        log "Proton Clang ready (fallback)"
    else
        # Try system clang >= 15
        local sys_ver=""
        sys_ver=$(clang --version 2>/dev/null | head -1 | rg -o '[0-9]+' | head -1) || true
        if [[ -n "$sys_ver" ]] && [[ "$sys_ver" -ge 15 ]]; then
            TC_PATH=""
            log "Using system clang ${sys_ver}"
            return 0
        fi
        err "No usable toolchain found"
    fi
    rm -rf "${tmp}"
    TC_PATH="${tc_dir}/bin"
}

# ============================================
# Setup kernel source
# ============================================
setup_kernel_source() {
    local kernel_dir="${BASE_DIR}/kernel"
    if [[ "$EXTRA" == "clean" ]]; then
        log "Cleaning kernel source..."
        make -C "$kernel_dir" mrproper 2>/dev/null || true
        return 0
    fi

    [[ -d "$kernel_dir/.git" ]] && { log "Kernel source exists, pulling..."; git -C "$kernel_dir" pull --ff-only; return 0; }

    log "Cloning kernel source..."
    git clone --depth=1 "${BASE_KERNEL}" "$kernel_dir"
}

# ============================================
# Integrate KernelSU / APatch
# ============================================
integrate_kernelsu() {
    local kdir="$1"
    local patch_dir="${BASE_DIR}/patches/00-kernelsu"
    if [[ -x "$patch_dir/integrate.sh" ]]; then
        bash "$patch_dir/integrate.sh" "$kdir" "$KSU_TAG" "$ROOT_TYPE"
    else
        # Fallback inline integration
        local ksudir="${kdir}/KernelSU"
        case "$ROOT_TYPE" in
            kernelsu)
                [[ -d "$ksudir" ]] && { log "KernelSU already integrated"; return 0; }
                log "Cloning KernelSU-Next..."
                git clone --depth=1 -b "$KSU_TAG" "$KSU_URL" "$ksudir"
                grep -q "KernelSU" "$kdir/Makefile" 2>/dev/null || \
                    sed -i '/^obj-y/a obj-y += KernelSU/' "$kdir/Makefile"
                log "KernelSU integrated"
                ;;
            apatch)
                log "APatch will be integrated via kpm module"
                ;;
            *)
                warn "Root type '$ROOT_TYPE' does not need KernelSU integration"
                ;;
        esac
    fi
}

# ============================================
# Integrate SUSFS
# ============================================
integrate_susfs() {
    local kdir="$1"
    local patch_dir="${BASE_DIR}/patches/01-susfs"
    if [[ -x "$patch_dir/integrate.sh" ]]; then
        bash "$patch_dir/integrate.sh" "$kdir" "$SUSFS_TAG" "$ROOT_TYPE"
    else
        # Fallback: only for roots that use it
        case "$ROOT_TYPE" in
            kernelsu|apatch)
                log "SUSFS will be applied via config fragment (patches/01-susfs/integrate.sh not found)"
                ;;
            *) warn "SUSFS not needed for root type '$ROOT_TYPE'" ;;
        esac
    fi
}

# ============================================
# Apply patches
# ============================================
apply_patches() {
    local kdir="$1"
    local patch_dir
    for patch_dir in "${BASE_DIR}"/patches/*/apply.sh; do
        [[ -x "$patch_dir" ]] || continue
        local name
        name=$(basename "$(dirname "$patch_dir")")
        log "Applying patch: ${name}"
        bash "$patch_dir" "$kdir" "$VARIANT" || warn "Patch ${name} failed (non-fatal)"
    done
    log "All patches applied"
}

# ============================================
# Configure kernel
# ============================================
configure_kernel() {
    local kdir="$1"
    local defconfig="vayu_defconfig"
    [[ "$VARIANT" == "aosp" ]] && defconfig="vayu_aosp_defconfig"

    log "Configuring kernel with ${defconfig}..."
    make -C "$kdir" ARCH=arm64 "$defconfig"

    # Apply fragments
    local frag
    for frag in "${BASE_DIR}/configs/fragments/infinity_base.config" \
                "${BASE_DIR}/configs/fragments/root_${ROOT_TYPE}.config" \
                "${BASE_DIR}/configs/fragments/${VARIANT}.config"; do
        [[ -f "$frag" ]] || { warn "Fragment not found: $frag"; continue; }
        log "  Merging fragment: $(basename "$frag")"
        ./scripts/kconfig/merge_config.sh -m .config "$frag" 2>/dev/null || \
            scripts/kconfig/merge_config.sh -m .config "$frag" || \
            warn "  merge_config.sh not available, skipping fragment"
    done

    make -C "$kdir" ARCH=arm64 olddefconfig
    log "Kernel configured"
}

# ============================================
# Build kernel
# ============================================
build_kernel() {
    local kdir="$1"
    local jobs
    jobs=$(nproc)

    local cc="clang" ld="ld.lld"
    [[ -n "${TC_PATH:-}" ]] && cc="${TC_PATH}/clang" && ld="${TC_PATH}/ld.lld"

    log "Building kernel with ${jobs} jobs..."
    make -C "$kdir" \
        ARCH=arm64 \
        O="${kdir}" \
        CC="${cc}" \
        LD="${ld}" \
        AR="${TC_PATH:+${TC_PATH}/}llvm-ar" \
        NM="${TC_PATH:+${TC_PATH}/}llvm-nm" \
        OBJCOPY="${TC_PATH:+${TC_PATH}/}llvm-objcopy" \
        OBJDUMP="${TC_PATH:+${TC_PATH}/}llvm-objdump" \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        -j"$jobs" \
        Image.gz dtbo.img 2>&1 | tail -20

    [[ -f "${kdir}/arch/arm64/boot/Image.gz" ]] || err "Image.gz not found!"
    log "Build successful"
}

# ============================================
# Package ZIP
# ============================================
package_zip() {
    local kdir="$1"
    local zip_dir="${OUT_DIR}/zip"
    local zip_name="${KERNEL_NAME}-${VERSION}-${ROOT_TYPE}-${VARIANT}-$(date +%Y%m%d).zip"

    log "Packaging ZIP..."
    rm -rf "$zip_dir"
    mkdir -p "$zip_dir"

    # Copy flasher contents
    cp -r "${BASE_DIR}/flasher/"* "$zip_dir/" 2>/dev/null || true
    mkdir -p "$zip_dir/tools/anykernel3"
    cp -r "${BASE_DIR}/tools/anykernel3/"* "$zip_dir/tools/anykernel3/" 2>/dev/null || true

    # Copy kernel images
    cp "${kdir}/arch/arm64/boot/Image.gz" "$zip_dir/"
    [[ -f "${kdir}/arch/arm64/boot/dtbo.img" ]] && \
        cp "${kdir}/arch/arm64/boot/dtbo.img" "$zip_dir/"

    # Prepare banner
    if [[ -f "$zip_dir/banner" ]]; then
        local build_info="$(date +%Y-%m-%d) | ${ROOT_TYPE} | ${VARIANT}"
        sed -i "s/%version%/${VERSION}/g; s/%build_info%/${build_info}/g" "$zip_dir/banner"
    fi

    mkdir -p "$OUT_DIR"
    (cd "$zip_dir" && zip -r9 "${OUT_DIR}/${zip_name}" . -x ".git/*")
    log "ZIP: ${OUT_DIR}/${zip_name}"
}

# ============================================
# Main
# ============================================
ROOT_TYPE="${1:-kernelsu}"
VARIANT="${2:-miui}"
EXTRA="${3:-}"

banner
validate_args

log "Root: $ROOT_TYPE | Variant: $VARIANT | Extra: ${EXTRA:-none}"

setup_toolchain
setup_kernel_source

KDIR="${BASE_DIR}/kernel"

if [[ "$EXTRA" == "ziponly" ]]; then
    package_zip "$KDIR"
    exit 0
fi

integrate_kernelsu "$KDIR"
integrate_susfs "$KDIR"
apply_patches "$KDIR"
configure_kernel "$KDIR"
build_kernel "$KDIR"
package_zip "$KDIR"

echo -e "${GREEN}========================================${RST}"
echo -e "${GREEN}  Build complete!${RST}"
echo -e "${GREEN}========================================${RST}"
