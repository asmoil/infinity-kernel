#!/bin/bash
##########################################################################################
#  Infinity Kernel Build Script
#  Device: Poco X3 Pro (vayu/bhima) - Snapdragon 732G
#  AnyKernel3 flashable ZIP output
#
#  Usage:
#    ./build.sh                          # Build with defaults
#    ./build.sh /path/to/kernel/source   # Build with custom kernel source
#    ./build.sh -c                       # Clean build
#    ./build.sh -r <root_manager>        # Inject root manager (ksu/magisk/apatch)
##########################################################################################

set -e

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Project paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="${PROJECT_DIR}/out"
ANYKERNEL_DIR="${PROJECT_DIR}/AnyKernel3"
DOWNLOAD_DIR="${PROJECT_DIR}/../download"

# Build configuration
DEFCONFIG="infinity_defconfig"
ARCH="arm64"
CROSS_COMPILE=""
CLANG_TRIPLE=""
CCACHE=""
CLEAN_BUILD=0
VERBOSE=0
JOBS=$(nproc)
ROOT_MANAGER=""
KERNEL_VERSION="1.0"

# Toolchain paths (adjust these to your environment)
# Proton Clang (recommended)
PROTON_CLANG_PATH="$HOME/proton-clang"
# AOSP Clang
AOSP_CLANG_PATH="$HOME/Android/CLANG"
# GCC cross-compiler
GCC_PATH="$HOME/Android/GCC"

# ==============================================================================
# FUNCTIONS
# ==============================================================================

print_banner() {
    echo -e "${PURPLE}"
    echo "  ╔═══════════════════════════════════════════════════════╗"
    echo "  ║                                                       ║"
    echo "  ║        ██╗  ██╗███████╗██╗   ██╗███╗   ██╗ ██████╗    ║"
    echo "  ║        ██║ ██╔╝██╔════╝╚██╗ ██╔╝████╗  ██║██╔═══██╗   ║"
    echo "  ║        █████╔╝ █████╗   ╚████╔╝ ██╔██╗ ██║██║   ██║   ║"
    echo "  ║        ██╔═██╗ ██╔══╝    ╚██╔╝  ██║╚██╗██║██║   ██║   ║"
    echo "  ║        ██║  ██╗███████╗   ██║   ██║ ╚████║╚██████╔╝   ║"
    echo "  ║        ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═══╝ ╚═════╝    ║"
    echo "  ║                   K E R N E L                       ║"
    echo "  ║                                                       ║"
    echo "  ║     Poco X3 Pro | Performance + Battery Balance      ║"
    echo "  ║     AnyKernel3 | Charging Bypass | Root Support       ║"
    echo "  ║                                                       ║"
    echo "  ╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

detect_toolchain() {
    log_info "Detecting toolchain..."

    # Priority: Proton Clang > AOSP Clang > GCC
    if [ -d "$PROTON_CLANG_PATH" ]; then
        export PATH="$PROTON_CLANG_PATH/bin:$PATH"
        CROSS_COMPILE="aarch64-linux-gnu-"
        CLANG_TRIPLE="aarch64-linux-gnu-"
        CC="clang"
        LD="ld.lld"
        AR="llvm-ar"
        NM="llvm-nm"
        OBJCOPY="llvm-objcopy"
        OBJDUMP="llvm-objdump"
        STRIP="llvm-strip"
        log_ok "Using Proton Clang: $PROTON_CLANG_PATH"
    elif [ -d "$AOSP_CLANG_PATH" ]; then
        export PATH="$AOSP_CLANG_PATH/bin:$PATH"
        CROSS_COMPILE="aarch64-linux-gnu-"
        CLANG_TRIPLE="aarch64-linux-gnu-"
        CC="clang"
        LD="ld.lld"
        AR="llvm-ar"
        NM="llvm-nm"
        OBJCOPY="llvm-objcopy"
        OBJDUMP="llvm-objdump"
        STRIP="llvm-strip"
        log_ok "Using AOSP Clang: $AOSP_CLANG_PATH"
    elif [ -d "$GCC_PATH" ]; then
        export PATH="$GCC_PATH/bin:$PATH"
        CROSS_COMPILE="aarch64-linux-android-"
        CC="${CROSS_COMPILE}gcc"
        log_ok "Using GCC: $GCC_PATH"
    else
        # Try system toolchain
        if command -v aarch64-linux-gnu-gcc &>/dev/null; then
            CROSS_COMPILE="aarch64-linux-gnu-"
            CC="${CROSS_COMPILE}gcc"
            log_ok "Using system GCC"
        elif command -v aarch64-linux-android-gcc &>/dev/null; then
            CROSS_COMPILE="aarch64-linux-android-"
            CC="${CROSS_COMPILE}gcc"
            log_ok "Using system Android GCC"
        elif command -v clang &>/dev/null; then
            CC="clang"
            log_ok "Using system clang"
        else
            log_error "No suitable toolchain found!"
            log_error "Install one of:"
            log_error "  1. Proton Clang: https://github.com/kdrag0n/proton-clang"
            log_error "  2. AOSP Clang:  Prebuilt from Android source"
            log_error "  3. Cross GCC:   sudo apt install gcc-aarch64-linux-gnu"
            exit 1
        fi
    fi

    # Enable ccache if available
    if command -v ccache &>/dev/null; then
        CCACHE="ccache "
        log_ok "CCache enabled"
    fi
}

check_kernel_source() {
    local kernel_dir="$1"

    if [ ! -d "$kernel_dir" ]; then
        log_error "Kernel source not found: $kernel_dir"
        return 1
    fi

    if [ ! -f "$kernel_dir/Makefile" ]; then
        log_error "Not a valid kernel source (missing Makefile): $kernel_dir"
        return 1
    fi

    log_ok "Kernel source verified: $kernel_dir"
    return 0
}

apply_patches() {
    local kernel_dir="$1"

    local patches_dir="${PROJECT_DIR}/patches"
    local patch_count=$(find "$patches_dir" -name "*.patch" -type f 2>/dev/null | wc -l)

    if [ "$patch_count" -eq 0 ]; then
        log_warn "No patches to apply"
        return 0
    fi

    log_info "Applying $patch_count Infinity Kernel patches..."

    local applied=0
    local failed=0

    for patch_file in $(find "$patches_dir" -name "*.patch" -type f | sort); do
        local patch_name=$(basename "$patch_file")

        if cd "$kernel_dir" && git apply --3way --fuzz=3 "$patch_file" 2>/dev/null; then
            log_ok "  $patch_name"
            ((applied++))
        elif cd "$kernel_dir" && patch -p1 --fuzz=3 --no-backup-if-mismatch < "$patch_file" 2>/dev/null; then
            log_ok "  $patch_name (patch cmd)"
            ((applied++))
        else
            log_warn "  $patch_name - FAILED (may need manual resolution)"
            ((failed++))
        fi
    done

    # Copy custom files
    log_info "Installing custom Infinity Kernel files..."

    # Charging driver
    if [ -d "${PROJECT_DIR}/drivers/charging" ]; then
        mkdir -p "${kernel_dir}/drivers/charging"
        cp "${PROJECT_DIR}/drivers/charging/"*.c "${kernel_dir}/drivers/charging/" 2>/dev/null || true
        cp "${PROJECT_DIR}/drivers/charging/Makefile" "${kernel_dir}/drivers/charging/" 2>/dev/null || true
        log_ok "  Charging control driver installed"
    fi

    # Header files
    if [ -f "${PROJECT_DIR}/include/linux/infinity_charging_control.h" ]; then
        cp "${PROJECT_DIR}/include/linux/infinity_charging_control.h" \
           "${kernel_dir}/include/linux/" 2>/dev/null
        log_ok "  Header files installed"
    fi

    # Defconfig
    if [ -f "${PROJECT_DIR}/arch/arm64/configs/infinity_defconfig" ]; then
        mkdir -p "${kernel_dir}/arch/arm64/configs/"
        cp "${PROJECT_DIR}/arch/arm64/configs/infinity_defconfig" \
           "${kernel_dir}/arch/arm64/configs/" 2>/dev/null
        log_ok "  Defconfig installed"
    fi

    log_info "Patches applied: $applied, Failed: $failed"
    return $failed
}

build_kernel() {
    local kernel_dir="$1"

    cd "$kernel_dir"

    # Set environment
    export ARCH=$ARCH
    export CROSS_COMPILE=$CROSS_COMPILE
    export SUBARCH=$ARCH

    if [ -n "$CLANG_TRIPLE" ]; then
        export CLANG_TRIPLE=$CLANG_TRIPLE
    fi

    # Clean if requested
    if [ "$CLEAN_BUILD" -eq 1 ]; then
        log_info "Cleaning kernel..."
        make mrproper 2>/dev/null || true
    fi

    # Apply defconfig
    log_info "Applying defconfig: $DEFCONFIG"
    make $DEFCONFIG

    # Build
    log_info "Building Infinity Kernel..."
    log_info "  ARCH=$ARCH"
    log_info "  JOBS=$JOBS"
    log_info "  CC=${CCACHE}${CC}"

    if [ -n "$CC" ] && [[ "$CC" == *"clang"* ]]; then
        # Clang build
        make -j"$JOBS" \
            CC="${CCACHE}${CC}" \
            LD="${LD:-ld.lld}" \
            AR="${AR:-llvm-ar}" \
            NM="${NM:-llvm-nm}" \
            OBJCOPY="${OBJCOPY:-llvm-objcopy}" \
            OBJDUMP="${OBJDUMP:-llvm-objdump}" \
            STRIP="${STRIP:-llvm-strip}" \
            2>&1 | tee "${OUT_DIR}/build.log"
    else
        # GCC build
        make -j"$JOBS" \
            CC="${CCACHE}${CROSS_COMPILE}gcc" \
            2>&1 | tee "${OUT_DIR}/build.log"
    fi

    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        log_error "Kernel build FAILED! Check build.log for details."
        exit 1
    fi

    log_ok "Kernel built successfully!"
}

create_anykernel_zip() {
    local kernel_dir="$1"
    local zip_name="InfinityKernel-v${KERNEL_VERSION}-vayu-$(date +%Y%m%d-%H%M%S).zip"
    local staging="${OUT_DIR}/anykernel_staging"

    log_info "Creating AnyKernel3 ZIP: $zip_name"

    # Clean staging
    rm -rf "$staging"
    mkdir -p "$staging"

    # Copy AnyKernel3 template
    cp -r "${ANYKERNEL_DIR}/"* "$staging/"

    # Create kernel directory and copy kernel image
    mkdir -p "$staging/kernel"

    # Detect kernel image format
    if [ -f "${kernel_dir}/arch/${ARCH}/boot/Image.gz-dtb" ]; then
        cp "${kernel_dir}/arch/${ARCH}/boot/Image.gz-dtb" "$staging/kernel/"
        log_ok "  Using Image.gz-dtb"
    elif [ -f "${kernel_dir}/arch/${ARCH}/boot/Image.gz" ]; then
        cp "${kernel_dir}/arch/${ARCH}/boot/Image.gz" "$staging/kernel/"
        log_ok "  Using Image.gz"
    elif [ -f "${kernel_dir}/arch/${ARCH}/boot/Image" ]; then
        cp "${kernel_dir}/arch/${ARCH}/boot/Image" "$staging/kernel/"
        log_ok "  Using Image (uncompressed)"
    else
        log_error "  No kernel image found in arch/${ARCH}/boot/"
        exit 1
    fi

    # Copy DTB files if present
    if [ -f "${kernel_dir}/arch/${ARCH}/boot/dts/qcom/sm7325-poco-vayu.dtb" ]; then
        mkdir -p "$staging/dtb"
        cp "${kernel_dir}/arch/${ARCH}/boot/dts/qcom/"*.dtb "$staging/dtb/" 2>/dev/null || true
        log_ok "  DTB files copied"
    fi

    # Copy DTBO if present
    if [ -f "${kernel_dir}/arch/${ARCH}/boot/dtbo.img" ]; then
        cp "${kernel_dir}/arch/${ARCH}/boot/dtbo.img" "$staging/"
        log_ok "  DTBO copied"
    fi

    # Inject root manager if specified
    if [ -n "$ROOT_MANAGER" ]; then
        case "$ROOT_MANAGER" in
            ksu|kernelsu)
                log_info "  Injecting KernelSU support..."
                # KernelSU is built into the kernel via KCONFIG
                # The AnyKernel script preserves KSU ramdisk modifications
                ;;
            magisk)
                log_info "  Preserving Magisk ramdisk..."
                # Magisk patches ramdisk - our AnyKernel script preserves it
                ;;
            apatch|sukisu|sukisu_ultra)
                log_info "  Preserving APatch/Sukisu ramdisk..."
                ;;
            *)
                log_warn "  Unknown root manager: $ROOT_MANAGER"
                ;;
        esac
    fi

    # Set permissions
    chmod +x "$staging/anykernel.sh" 2>/dev/null || true
    chmod +x "$staging/META-INF/com/google/android/update-binary" 2>/dev/null || true
    chmod +x "$staging/tools/infinity_init.sh" 2>/dev/null || true

    # Create ZIP
    cd "$staging"
    zip -r -9 "${OUT_DIR}/$zip_name" . -x ".git/*"

    # Calculate hash
    cd "$OUT_DIR"
    md5sum "$zip_name" > "${zip_name}.md5sum"
    sha256sum "$zip_name" > "${zip_name}.sha256"

    log_ok "AnyKernel ZIP created: ${OUT_DIR}/$zip_name"
    log_ok "MD5:    $(cat ${zip_name}.md5sum | cut -d' ' -f1)"
    log_ok "SHA256: $(cat ${zip_name}.sha256 | cut -d' ' -f1)"
}

# ==============================================================================
# MAIN
# ==============================================================================

print_banner

# Parse arguments
KERNEL_SOURCE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--clean)
            CLEAN_BUILD=1
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -j|--jobs)
            JOBS="$2"
            shift 2
            ;;
        -r|--root)
            ROOT_MANAGER="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS] [KERNEL_SOURCE_DIR]"
            echo ""
            echo "Options:"
            echo "  -c, --clean              Clean build (make mrproper)"
            echo "  -v, --verbose            Verbose output"
            echo "  -j, --jobs N             Number of parallel jobs (default: $(nproc))"
            echo "  -r, --root <manager>     Root manager: ksu, magisk, apatch"
            echo "  -h, --help               Show this help"
            echo ""
            echo "Example:"
            echo "  $0 ~/android/kernel/xiaomi-vayu"
            echo "  $0 -c -r ksu ~/android/kernel/xiaomi-vayu"
            echo "  $0 -j8 ~/android/kernel/xiaomi-vayu"
            exit 0
            ;;
        *)
            KERNEL_SOURCE="$1"
            shift
            ;;
    esac
done

# Create output directory
mkdir -p "$OUT_DIR"

# Detect toolchain
detect_toolchain

# If no kernel source specified, try to find it
if [ -z "$KERNEL_SOURCE" ]; then
    # Try common locations
    for path in \
        "$HOME/android/kernel/xiaomi-vayu" \
        "$HOME/android/kernel/vayu" \
        "$HOME/kernel/xiaomi-vayu" \
        "$HOME/LineageOS/kernel/xiaomi/vayu" \
        "$HOME/LineageOS/android_kernel_xiaomi_vayu"; do
        if check_kernel_source "$path" 2>/dev/null; then
            KERNEL_SOURCE="$path"
            break
        fi
    done

    if [ -z "$KERNEL_SOURCE" ]; then
        log_error "No kernel source directory specified or found!"
        log_error ""
        log_error "Please specify the kernel source directory:"
        log_error "  $0 /path/to/kernel/source"
        log_error ""
        log_error "Clone the Poco X3 Pro kernel source first:"
        log_error "  git clone https://github.com/XiaomiKernel-Devices/android_kernel_xiaomi_vayu.git"
        exit 1
    fi
fi

# Verify kernel source
check_kernel_source "$KERNEL_SOURCE"

# Apply patches
log_info "========================================="
log_info "  Step 1: Applying Infinity Patches"
log_info "========================================="
apply_patches "$KERNEL_SOURCE"

# Build kernel
log_info "========================================="
log_info "  Step 2: Building Infinity Kernel"
log_info "========================================="
build_kernel "$KERNEL_SOURCE"

# Create AnyKernel ZIP
log_info "========================================="
log_info "  Step 3: Creating AnyKernel3 ZIP"
log_info "========================================="
create_anykernel_zip "$KERNEL_SOURCE"

# Done!
echo ""
echo -e "${GREEN}${BOLD}"
echo "  ╔═══════════════════════════════════════════╗"
echo "  ║   INFINITY KERNEL BUILD COMPLETE!         ║"
echo "  ╚═══════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "Output: ${CYAN}${OUT_DIR}/$(ls -t ${OUT_DIR}/*.zip 2>/dev/null | head -1 | xargs basename)${NC}"
echo ""
echo -e "${YELLOW}Flash via TWRP/Recovery:${NC}"
echo -e "  1. Transfer ZIP to device"
echo -e "  2. Boot to recovery"
echo -e "  3. Flash the ZIP"
echo -e "  4. Reboot"
echo ""
echo -e "${YELLOW}Control charging bypass:${NC}"
echo -e "  echo 1 > /sys/devices/platform/.../infinity_charging/bypass_enable"
echo -e "  echo 3 > /sys/devices/platform/.../infinity_charging/gaming_mode"
echo ""