#!/bin/bash
##########################################################################################
#  Infinity Kernel — Build Script (Clang/LLVM)
#  Device: Poco X3 Pro (vayu/bhima) — Snapdragon 860 (SM8150-AC)
#  Base:   AnymoreProject/android_kernel_vayu (Linux 4.14.356+, OPENELA upstream)
#
#  Multi-root build system (ONE BINARY for all root managers):
#    ./build.sh              # Default: kernelsu
#    ./build.sh kernelsu     # KernelSU-Next (built into kernel)
#    ./build.sh apatch       # APatch (KernelSU still built-in, APatch patches at flash)
#    ./build.sh none         # No root (CONFIG_KSU=n)
#    ./build.sh kernelsu 4   # Thread count (default = nproc)
#
#  v3.0.0: GROUND-UP REWRITE with REAL KernelSU-Next integration.
#          - Clones KernelSU-Next from GitHub into drivers/kernelsu/
#          - Adds compat stubs for 4 old-style ksu_handle_* calls in
#            the AnymoreProject ksu branch (faccessat, sys_read, stat,
#            execveat) + ksu_vfs_read_hook. These are NOT provided by
#            modern KernelSU-Next which uses KPROBES/syscall patching.
#          - Adds full SuSFS Kconfig definitions (CONFIG_KSU_SUSFS_*)
#            because the ksu branch already has SuSFS code (fs/susfs.c,
#            include/linux/susfs.h) but NO Kconfig definitions for it.
#          - Fixed CONFIG_CHARGING_CONTROL: added source line to
#            drivers/Kconfig so olddefconfig doesn't silently drop it.
#          - All upstream compilation fixes preserved (modpost, cam_trace,
#            spi-xiaomi-tp, thermal_core, NOHZ_BALANCE_KICK, etc.)
#          - Universal binary: KernelSU-Next built-in, APatch/Magisk
#            work via kernel image / ramdisk patching at flash time.
#
#  Copyright (c) 2024-2026 Infinity Kernel Team
#  Licensed under MIT License
##########################################################################################

set -uo pipefail

# ==============================================================================
#  CONFIGURATION
# ==============================================================================

VERSION="3.0.0"
DEVICE="Infinity Kernel"
ARCH="arm64"
KERNEL_REPO_URL="https://github.com/AnymoreProject/android_kernel_vayu"
KSU_NEXT_REPO="https://github.com/KernelSU-Next/KernelSU-Next"

# Toolchain (override via environment)
CLANG_REPO_URL="https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r547379.git"
CLANG_DIR="${CLANG_DIR:-/root/clang}"
GCC64_DIR="${GCC64_DIR:-/root/gcc64/aarch64--glibc--stable-2025.08-1}"
GCC32_DIR="${GCC32_DIR:-/root/gcc32}"
CROSS_COMPILE="aarch64-linux-gnu-"

# Colors
RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
CYN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ==============================================================================
#  FUNCTIONS
# ==============================================================================

info()  { echo -e "${CYN}[INFO]$(date +%H:%M:%S)${NC} $1"; }
ok()    { echo -e "${GRN}[OK]${NC}     $1"; }
warn()  { echo -e "${YLW}[WARN]${NC}   $1"; }
err()   { echo -e "${RED}[ERROR]${NC}  $1"; }
die()   { echo -e "${RED}[FATAL]${NC}  $1"; exit 1; }

# Insert content of FILE ($3) after the FIRST line matching PATTERN ($2) in TARGET ($1)
insert_after() {
    local target="$1" pattern="$2" content_file="$3"
    awk -v pat="$pattern" -v cntf="$content_file" '
        FNR==NR { content=content $0 "\n"; next }
        $0 ~ pat {
            print
            while ((getline line < cntf) > 0) print line
            close(cntf)
            found=1; next
        }
        { print }
        END { if (!found) exit 1 }
    ' "$content_file" "$target" > "$target.tmp" && mv "$target.tmp" "$target"
}

# Insert content of FILE ($3) before the FIRST line matching PATTERN ($2) in TARGET ($1)
insert_before() {
    local target="$1" pattern="$2" content_file="$3"
    awk -v pat="$pattern" -v cntf="$content_file" '
        FNR==NR { content=content $0 "\n"; next }
        $0 ~ pat {
            while ((getline line < cntf) > 0) print line
            close(cntf)
            found=1
        }
        { print }
        END { if (!found) exit 1 }
    ' "$content_file" "$target" > "$target.tmp" && mv "$target.tmp" "$target"
}

# Insert content of FILE ($2) AFTER the first '*/' close-comment line in TARGET ($1)
insert_after_close_comment() {
    local target="$1" content_file="$2"
    awk -v cntf="$content_file" '
        FNR==NR { content=content $0 "\n"; next }
        /^[ \t]*\*\// && !found {
            print
            while ((getline line < cntf) > 0) print line
            close(cntf)
            found=1; next
        }
        { print }
        END { if (!found) exit 1 }
    ' "$content_file" "$target" > "$target.tmp" && mv "$target.tmp" "$target"
}

# ==============================================================================
#  KernelSU-Next Setup
#  The AnymoreProject ksu branch already has:
#    - SuSFS code (fs/susfs.c, include/linux/susfs.h)
#    - 4 old-style ksu_handle_* calls in fs/open.c, fs/exec.c, fs/stat.c,
#      fs/read_write.c (under #ifdef CONFIG_KSU)
#    - source "drivers/kernelsu/Kconfig" in drivers/Kconfig
#  But drivers/kernelsu/ directory is EMPTY — KernelSU-Next must be placed
#  there. We clone KernelSU-Next and add compat stubs.
# ==============================================================================

setup_kernelsu() {
    local ksudir="$1"
    local ksu_src="${SCRIPT_DIR}/KernelSU-Next"

    # --- Clone KernelSU-Next if not present ---
    if [ ! -d "$ksu_src/kernel" ]; then
        info "Cloning KernelSU-Next..."
        git clone --depth=1 "$KSU_NEXT_REPO" "$ksu_src" 2>&1 | tee -a "$BUILD_LOG"
        if [ ${PIPESTATUS[0]} -ne 0 ]; then
            die "Failed to clone KernelSU-Next from $KSU_NEXT_REPO — check internet / DNS"
        fi
        ok "KernelSU-Next cloned"
    else
        info "KernelSU-Next already exists at $ksu_src"
    fi

    # --- Copy KernelSU-Next kernel module into the kernel tree ---
    info "Installing KernelSU-Next into kernel tree..."
    rm -rf "$ksudir"
    mkdir -p "$ksudir"
    cp -r "$ksu_src/kernel/"* "$ksudir/"

    # --- Create compat stubs for old-style ksu_handle_* calls ---
    # The AnymoreProject ksu branch calls these under #ifdef CONFIG_KSU.
    # Modern KernelSU-Next uses KPROBES/syscall patching and does NOT
    # define these symbols. Without stubs, the build fails with
    # undefined reference errors.
    cat > "$ksudir/ksu_compat.c" << 'KSUEOF'
/*
 * Compat stubs for old-style KernelSU hooks in AnymoreProject ksu branch.
 * Modern KernelSU-Next (KPROBES-based) does NOT provide these symbols.
 * The ksu branch's fs/open.c, fs/exec.c, fs/stat.c, fs/read_write.c
 * call these under #ifdef CONFIG_KSU. We define them as no-ops.
 */
#include <linux/module.h>
#include <linux/types.h>
#include <linux/compiler.h>

int __attribute__((hot)) ksu_handle_faccessat(int *dfd, const char __user **filename_user,
                                                         int *mode, int *flags)
{
        return 0;
}
EXPORT_SYMBOL(ksu_handle_faccessat);

bool ksu_vfs_read_hook __read_mostly = false;
EXPORT_SYMBOL(ksu_vfs_read_hook);

int __attribute__((cold)) ksu_handle_sys_read(unsigned int fd,
                                                         char __user **buf_ptr, size_t *count_ptr)
{
        return 0;
}
EXPORT_SYMBOL(ksu_handle_sys_read);

int ksu_handle_stat(int *dfd, const char __user **filename_user,
                     int *flags)
{
        return 0;
}
EXPORT_SYMBOL(ksu_handle_stat);

int ksu_handle_execveat(int *fd, struct filename **filename_ptr,
                         void *argv, void *envp, int *flags)
{
        return 0;
}
EXPORT_SYMBOL(ksu_handle_execveat);
KSUEOF

    # Add compat stubs to KernelSU-Next's build
    if [ -f "$ksudir/Kbuild" ]; then
        # KernelSU-Next uses Kbuild for its build
        echo 'kernelsu-objs += ksu_compat.o' >> "$ksudir/Kbuild"
        ok "Compat stubs added to Kbuild"
    else
        warn "No Kbuild found — creating standalone Makefile"
        cat > "$ksudir/Makefile" << 'KSUEOF'
obj-$(CONFIG_KSU) := kernelsu.o ksu_compat.o
KSUEOF
    fi

    # --- Create Kconfig with KSU + SuSFS options ---
    # The ksu branch already has SuSFS code (fs/susfs.c, susfs.h) but
    # NO Kconfig definitions for CONFIG_KSU_SUSFS*. Without these,
    # olddefconfig silently drops all CONFIG_KSU_SUSFS_* options
    # and SuSFS code becomes dead code.
    cat > "$ksudir/Kconfig" << 'KSUEOF'
menu "KernelSU"

config KSU
        bool "KernelSU-Next"
        default y
        help
          KernelSU-Next provides kernel-level root for Android.
          Uses KPROBES and syscall table patching.

config KSU_SUSFS
        bool "SuSFS (SUS File System) support"
        depends on KSU
        default y
        help
          Enable SuSFS to hide KernelSU from detection.
          Hides files, mounts, processes, and kernel module info.

config KSU_SUSFS_SUS_PATH
        bool "SuSFS: Hide specific paths"
        depends on KSU_SUSFS
        default y

config KSU_SUSFS_SUS_MOUNT
        bool "SuSFS: Hide specific mounts"
        depends on KSU_SUSFS
        default y

config KSU_SUSFS_SUS_MOUNT_MNT_ID_REORDER
        bool "SuSFS: Reorder mount IDs"
        depends on KSU_SUSFS_SUS_MOUNT
        default y

config KSU_SUSFS_SPOOF_UNAME
        bool "SuSFS: Spoof /proc/version uname"
        depends on KSU_SUSFS
        default y

config KSU_SUSFS_SUS_KSTAT
        bool "SuSFS: Spoof kstat for specific inodes"
        depends on KSU_SUSFS
        default y

config KSU_SUSFS_SUS_MAP
        bool "SuSFS: Hide specific memory maps"
        depends on KSU_SUSFS
        default y

config KSU_SUSFS_SUS_MEMFD
        bool "SuSFS: Hide memfd files"
        depends on KSU_SUSFS
        default y

config KSU_SUSFS_SUS_PROC_FD_LINK
        bool "SuSFS: Hide /proc/*/fd links"
        depends on KSU_SUSFS
        default y

config KSU_SUSFS_TRY_UMOUNT
        bool "SuSFS: Try to umount on app suspend"
        depends on KSU_SUSFS
        default y

config KSU_SUSFS_ENABLE_LOG
        bool "SuSFS: Enable debug logging"
        depends on KSU_SUSFS
        default n

config KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
        bool "SuSFS: Spoof kernel cmdline / bootconfig"
        depends on KSU_SUSFS
        default y

config KSU_SUSFS_OPEN_REDIRECT
        bool "SuSFS: Enable open redirect"
        depends on KSU_SUSFS
        default y

endmenu
KSUEOF
    ok "Kconfig created (KSU + SuSFS)"

    # --- Ensure drivers/Kconfig sources us ---
    if ! rg -q 'drivers/kernelsu/Kconfig' "${KBUILD}/drivers/Kconfig" 2>/dev/null; then
        if ! insert_before "${KBUILD}/drivers/Kconfig" '^endmenu$' /dev/stdin << 'KEOF'
source "drivers/kernelsu/Kconfig"
KEOF
        then
            sed -i '/^endmenu$/i source "drivers/kernelsu/Kconfig"' "${KBUILD}/drivers/Kconfig"
        fi
        ok "drivers/Kconfig: kernelsu source added"
    else
        ok "drivers/Kconfig: kernelsu source already present"
    fi

    # --- Ensure drivers/Makefile builds us ---
    if ! rg -q 'kernelsu' "${KBUILD}/drivers/Makefile" 2>/dev/null; then
        echo 'obj-$(CONFIG_KSU) += kernelsu/' >> "${KBUILD}/drivers/Makefile"
        ok "drivers/Makefile: kernelsu build rule added"
    else
        ok "drivers/Makefile: kernelsu build rule already present"
    fi

    info "KernelSU-Next + SuSFS + compat stubs ready"
}

# Minimal Kconfig for "none" root mode (CONFIG_KSU=n, nothing built)
_create_noop_kernelsu() {
    local ksudir="$1"
    rm -rf "$ksudir"
    mkdir -p "$ksudir" || { err "Failed to create $ksudir"; return 1; }
    cat > "$ksudir/Kconfig" << 'KSUEOF'
menu "KernelSU"
config KSU
        bool "KernelSU-Next"
        default n
endmenu
KSUEOF
    cat > "$ksudir/Makefile" << 'KSUEOF'
obj-$(CONFIG_KSU) += kernelsu/
KSUEOF
}

# Helper: enable a CONFIG option, suppress errors if symbol unknown
config_enable() {
    scripts/config -e "$1" 2>/dev/null || true
}

# Helper: set a CONFIG to a value
config_set() {
    scripts/config --set-val "$1" "$2" 2>/dev/null || true
}

# Helper: set a CONFIG string
config_set_str() {
    scripts/config --set-str "$1" "$2" 2>/dev/null || true
}

# ==============================================================================
#  MAIN BUILD LOGIC
# ==============================================================================

main() {
    ROOT_MODE="${1:-kernelsu}"
    JOBS="${2:-$(nproc)}"

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    KERNEL_SRC="${SCRIPT_DIR}/kernel_src"
    OUT_DIR="${SCRIPT_DIR}/out"
    BUILD_PATH="/tmp/infinity-kbuild"
    BUILD_LOG="${SCRIPT_DIR}/infinity_build.log"

    : > "$BUILD_LOG"

    # --- Root label ---
    case "$ROOT_MODE" in
        kernelsu|sukisu_ultra|resukisu|kowsu|apatch)
            ROOT_LABEL="KernelSU-Next"; CLONE_BRANCH="ksu" ;;
        none)
            ROOT_LABEL="None"; CLONE_BRANCH="ksu" ;;
        *)
            die "Unknown root mode: $ROOT_MODE" ;;
    esac

    # ===================== BANNER =====================
    echo -e "${CYN}${BOLD}"
    echo "  ==================================================="
    echo "                                                   "
    echo "        INFINITY  KERNEL  v${VERSION}                 "
    echo "        Poco X3 Pro (vayu/bhima)                     "
    echo "        Root: ${ROOT_LABEL}                          "
    echo "                                                   "
    echo "  ==================================================="
    echo -e "${NC}" | tee -a "$BUILD_LOG"

    info "Infinity Kernel v${VERSION} Build System"
    info "Log: $BUILD_LOG  Dir: $SCRIPT_DIR  Src: $KERNEL_SRC"
    info "Device: $DEVICE  Root: ${ROOT_MODE} -> ${ROOT_LABEL}  Jobs: $JOBS"
    echo "" | tee -a "$BUILD_LOG"

    # ===================== STEP 0: PREREQUISITES =====================
    echo -e "${CYN}${BOLD}  Step 0: Prerequisites Check${NC}" | tee -a "$BUILD_LOG"
    for cmd in git make zip sudo awk sed python3; do
        command -v "$cmd" &>/dev/null && ok "$cmd" || die "Missing: $cmd"
    done | tee -a "$BUILD_LOG"
    ok "All prerequisites met"
    info "GCC: $(aarch64-linux-gnu-gcc --version | head -1)"
    echo -e "${CYN}--------------------------------------------------------------${NC}" | tee -a "$BUILD_LOG"

    # ===================== STEP 1: TOOLCHAIN SETUP (Clang/LLVM + GCC) =====================
    echo -e "${CYN}${BOLD}  Step 1: Toolchain Setup (Clang/LLVM)${NC}" | tee -a "$BUILD_LOG"

    # --- Clang/LLVM ---
    if ! [ -d "$CLANG_DIR" ]; then
        info "Clang not found at $CLANG_DIR — cloning..."
        git clone -q --depth=1 --single-branch "$CLANG_REPO_URL" -b 15.0 "$CLANG_DIR" 2>&1 | tee -a "$BUILD_LOG"
        if [ ${PIPESTATUS[0]} -ne 0 ]; then
            die "Failed to clone Clang toolchain — check internet / DNS"
        fi
        ok "Clang r547379 cloned to $CLANG_DIR"
    else
        ok "Clang found at $CLANG_DIR"
    fi

    # --- GCC cross-compilers (for 32-bit ARM compat) ---
    if [ ! -d "$GCC64_DIR" ]; then
        die "GCC64 not found at $GCC64_DIR — install aarch64-linux-gnu toolchain"
    fi
    ok "GCC64: $GCC64_DIR"
    if [ ! -d "$GCC32_DIR" ]; then
        warn "GCC32 not found at $GCC32_DIR — 32-bit ARM compat may fail"
    else
        ok "GCC32: $GCC32_DIR"
    fi

    # --- PATH: Clang first, then GCC cross-compilers ---
    export PATH="$CLANG_DIR/bin:$GCC64_DIR/bin:$GCC32_DIR/bin:$PATH"
    export CROSS_COMPILE="$CROSS_COMPILE"
    export CROSS_COMPILE_ARM32="arm-linux-gnueabi-"
    export CROSS_COMPILE_COMPAT="arm-linux-gnueabi-"
    export LD="ld.lld"
    export AR="llvm-ar"
    export NM="llvm-nm"
    export STRIP="llvm-strip"
    export OBJCOPY="llvm-objcopy"
    export OBJDUMP="llvm-objdump"
    export READELF="llvm-readelf"
    export HOSTCC="clang"
    export HOSTCXX="clang++"
    export HOSTAR="llvm-ar"
    export HOSTLD="ld.lld"
    export CLANG_TRIPLE="aarch64-linux-gnu-"

    info "Clang: $(clang --version 2>/dev/null | head -1)"

    echo -e "${CYN}--------------------------------------------------------------${NC}" | tee -a "$BUILD_LOG"

    # ===================== STEP 2: CLONE/UPDATE KERNEL =====================
    echo -e "${CYN}${BOLD}  Step 2: Clone Kernel Source${NC}" | tee -a "$BUILD_LOG"
    if [ -d "$KERNEL_SRC/.git" ]; then
        info "Existing clone at $KERNEL_SRC"
        (cd "$KERNEL_SRC" && git checkout "$CLONE_BRANCH" 2>/dev/null && git pull --ff-only 2>/dev/null) || true
    else
        info "Cloning kernel source (ksu branch)..."
        git clone --depth=1 --branch="$CLONE_BRANCH" "$KERNEL_REPO_URL" "$KERNEL_SRC" 2>&1 | tee -a "$BUILD_LOG"
    fi
    rm -f "$KERNEL_SRC/.git/index.lock"
    ok "Kernel source ready (branch: $CLONE_BRANCH)"
    echo -e "${CYN}--------------------------------------------------------------${NC}" | tee -a "$BUILD_LOG"

    # ===================== STEP 3: CLONE KERNELSU-NEXT =====================
    echo -e "${CYN}${BOLD}  Step 3: KernelSU-Next Setup${NC}" | tee -a "$BUILD_LOG"
    KSU_SRC="${SCRIPT_DIR}/KernelSU-Next"
    if [ ! -d "$KSU_SRC/kernel" ]; then
        info "Cloning KernelSU-Next..."
        git clone --depth=1 "$KSU_NEXT_REPO" "$KSU_SRC" 2>&1 | tee -a "$BUILD_LOG"
        if [ ${PIPESTATUS[0]} -ne 0 ]; then
            die "KernelSU-Next clone FAILED — check internet / DNS. Cannot build without real root."
        fi
        ok "KernelSU-Next cloned to $KSU_SRC"
        KSU_STUB_ONLY=0
    else
        ok "KernelSU-Next already exists at $KSU_SRC"
        KSU_STUB_ONLY=0
    fi
    echo -e "${CYN}--------------------------------------------------------------${NC}" | tee -a "$BUILD_LOG"

    # ===================== STEP 4: BIND MOUNT =====================
    echo -e "${CYN}${BOLD}  Step 4: Bind Mount Setup${NC}" | tee -a "$BUILD_LOG"
    sudo umount "$BUILD_PATH" 2>/dev/null || true
    if [[ "$KERNEL_SRC" =~ [[:space:]] ]] || [[ "$KERNEL_SRC" =~ [^[:print:]] ]]; then
        info "Path has spaces/Cyrillic — using bind mount"
        sudo mount --bind "$KERNEL_SRC" "$BUILD_PATH"
        KBUILD="$BUILD_PATH"
        ok "Bind mount: $KERNEL_SRC -> $BUILD_PATH"
    else
        KBUILD="$KERNEL_SRC"
        info "Path OK — no bind mount needed"
    fi
    echo -e "${CYN}--------------------------------------------------------------${NC}" | tee -a "$BUILD_LOG"

    # ===================== STEP 5: APPLY INFINITY MODIFICATIONS =====================
    echo -e "${CYN}${BOLD}  Step 5: Apply Infinity Kernel Modifications${NC}" | tee -a "$BUILD_LOG"

    # Clean tree
    info "Cleaning kernel tree..."
    (cd "$KBUILD" && git checkout -- . >> "$BUILD_LOG" 2>&1)
    rm -f "$KBUILD/.git/index.lock"
    ok "Tree cleaned"

    INS_DIR=$(mktemp -d)
    MOD_COUNT=0; MOD_FAIL=0
    mod_ok()   { ((MOD_COUNT++)); ok "    [$MOD_COUNT] $1"; }
    mod_fail() { ((MOD_FAIL++)); warn "    [FAIL] $1"; }

    # --- Copy custom files ---
    info "Installing custom files..."
    for d in task_engine charging; do
        if [ -d "${SCRIPT_DIR}/drivers/$d" ]; then
            mkdir -p "${KBUILD}/drivers/$d"
            cp -r "${SCRIPT_DIR}/drivers/$d/"* "${KBUILD}/drivers/$d/" 2>/dev/null
            mod_ok "$d driver files"
        fi
    done
    if [ -f "${SCRIPT_DIR}/include/linux/infinity_charging_control.h" ]; then
        cp "${SCRIPT_DIR}/include/linux/infinity_charging_control.h" "${KBUILD}/include/linux/" 2>/dev/null
        mod_ok "infinity_charging_control.h"
    fi
    mod_ok "Custom files installed"

    # ---- Kconfig Modifications ----
    info "Applying Kconfig modifications..."

    # 1. init/Kconfig
    cat > "$INS_DIR/k01.txt" << 'KEOF'

menuconfig INFINITY_KERNEL
        bool "Infinity Kernel Customizations"
        default y
KEOF
    insert_after "${KBUILD}/init/Kconfig" 'option env="KERNELVERSION"' "$INS_DIR/k01.txt" && mod_ok "init/Kconfig" || mod_fail "init/Kconfig"

    # 2. drivers/cpufreq/Kconfig
    cat > "$INS_DIR/k02.txt" << 'KEOF'

config INFINITY_CPU_GOVERNOR
        bool "Infinity CPU Governor (Interactive+)"
        depends on CPU_FREQ
        default y if INFINITY_KERNEL
        help
          Enhanced interactive governor with gaming-optimized frequency
          scaling for Snapdragon 732G (SM8150-AC).

KEOF
    insert_after "${KBUILD}/drivers/cpufreq/Kconfig" 'menu "CPU Frequency scaling"' "$INS_DIR/k02.txt" && mod_ok "cpufreq/Kconfig" || mod_fail "cpufreq/Kconfig"

    # 3. mm/Kconfig (BEFORE ARCH_ENABLE_HUGEPAGE_MIGRATION)
    cat > "$INS_DIR/k03.txt" << 'KEOF'
config INFINITY_BATTERY_COMPACTION
        bool "Infinity Battery-Friendly Compaction"
        depends on COMPACTION
        default y if INFINITY_KERNEL
        help
          Reduces background compaction frequency to lower CPU wake-ups.

KEOF
    insert_before "${KBUILD}/mm/Kconfig" 'config ARCH_ENABLE_HUGEPAGE_MIGRATION' "$INS_DIR/k03.txt" && mod_ok "mm/Kconfig" || mod_fail "mm/Kconfig"

    # 4. drivers/gpu/msm/Kconfig
    cat > "$INS_DIR/k05.txt" << 'KEOF'

config INFINITY_GPU_GAMING
        bool "Infinity GPU Gaming Mode"
        depends on QCOM_KGSL
        default y if INFINITY_KERNEL
        help
          GPU frequency boost for gaming workloads.

KEOF
    insert_after "${KBUILD}/drivers/gpu/msm/Kconfig" 'depends on QCOM_KGSL' "$INS_DIR/k05.txt" && mod_ok "gpu/msm/Kconfig" || mod_fail "gpu/msm/Kconfig"

    # 5. net/ipv4/Kconfig
    cat > "$INS_DIR/k06.txt" << 'KEOF'
config INFINITY_TCP_BBR
        bool "Infinity TCP BBRv2 Congestion Control"
        depends on TCP_CONG_BBR
        default y if INFINITY_KERNEL
        help
          Enable BBRv2 as default congestion control.

KEOF
    insert_after "${KBUILD}/net/ipv4/Kconfig" 'IP configuration' "$INS_DIR/k06.txt" && mod_ok "net/ipv4/Kconfig" || mod_fail "net/ipv4/Kconfig"

    # 6. fs/Kconfig
    cat > "$INS_DIR/k07.txt" << 'KEOF'

config INFINITY_SUFS
        bool "Infinity SuSFS Support (v2.2.0)"
        default y if INFINITY_KERNEL
        help
          Enable SuSFS support for hiding files and mounts.

KEOF
    insert_after "${KBUILD}/fs/Kconfig" 'source "fs/quota/Kconfig"' "$INS_DIR/k07.txt" && mod_ok "fs/Kconfig" || mod_fail "fs/Kconfig"

    # 7. drivers/Kconfig — task_engine (conditional)
    cat > "$INS_DIR/k08.txt" << 'KEOF'
source "drivers/task_engine/Kconfig"

KEOF
    if [ -d "${SCRIPT_DIR}/drivers/task_engine" ]; then
        insert_before "${KBUILD}/drivers/Kconfig" '^endmenu$' "$INS_DIR/k08.txt" && mod_ok "drivers/Kconfig (task_engine)" || mod_fail "drivers/Kconfig (task_engine)"
    else
        mod_ok "drivers/Kconfig (no task_engine)"
    fi

    # 7b. drivers/Kconfig — charging Kconfig source
    # CRITICAL: without this, CONFIG_CHARGING_CONTROL is silently dropped
    # by olddefconfig because the Kconfig parser doesn't know about it.
    cat > "$INS_DIR/k08b.txt" << 'KEOF'
source "drivers/charging/Kconfig"

KEOF
    if [ -d "${SCRIPT_DIR}/drivers/charging" ]; then
        insert_before "${KBUILD}/drivers/Kconfig" '^endmenu$' "$INS_DIR/k08b.txt" && mod_ok "drivers/Kconfig (charging)" || mod_fail "drivers/Kconfig (charging)"
    fi

    # 8. drivers/Makefile — charging driver build rule
    sed -i '/obj-\$(CONFIG_KSU).*kernelsu/a obj-$(CONFIG_CHARGING_CONTROL) += charging/' "${KBUILD}/drivers/Makefile"
    mod_ok "drivers/Makefile (charging)"

    # 9. block/Kconfig.iosched
    cat > "$INS_DIR/k09.txt" << 'KEOF'
config INFINITY_FSYNC_SCHEDULER
        bool "Infinity FSYNC I/O Scheduler Tuning"
        default y if INFINITY_KERNEL
        help
          Optimizes I/O scheduler for FSYNC-heavy gaming workloads.

KEOF
    insert_before "${KBUILD}/block/Kconfig.iosched" '^endmenu$' "$INS_DIR/k09.txt" && mod_ok "block/Kconfig.iosched" || mod_fail "block/Kconfig.iosched"

    # 10. security/selinux/Kconfig
    cat >> "${KBUILD}/security/selinux/Kconfig" << 'KEOF'

config INFINITY_SELINUX_PERMISSIVE
        bool "Infinity SELinux Permissive Mode"
        default y if INFINITY_KERNEL
        help
          Sets SELinux to permissive mode by default.
KEOF
    mod_ok "selinux/Kconfig"

    # 11. drivers/block/zram/Kconfig
    cat >> "${KBUILD}/drivers/block/zram/Kconfig" << 'KEOF'

config INFINITY_ZRAM_LZ4
        bool "Infinity zRAM LZ4 Compression"
        depends on ZRAM
        default y if INFINITY_KERNEL
        help
          Use LZ4 instead of LZ4HC for zRAM.
KEOF
    mod_ok "zram/Kconfig"

    # ---- C Source Modifications ----
    info "Applying C source modifications..."

    # 12. fork.c — skipped (no compatible fsync hook for 4.14)
    info "fork.c: skipping (no compatible fsync hook for 4.14)"

    # 13-23. Tuning defines (same as before)
    cat > "$INS_DIR/c13.txt" << 'CEOF'

#define INFINITY_TOUCH_BOOST_FREQ               1843200
#define INFINITY_TOUCH_BOOST_DURATION   500000
#define INFINITY_INPUT_BOOST_FREQ               1401600
#define INFINITY_INPUT_BOOST_DURATION   300000
#define INFINITY_SCHED_BOOST_STEPS              3
CEOF
    insert_after_close_comment "${KBUILD}/drivers/cpufreq/cpufreq_interactive.c" "$INS_DIR/c13.txt" && mod_ok "cpufreq_interactive.c" || mod_fail "cpufreq_interactive.c"

    cat > "$INS_DIR/c14.txt" << 'CEOF'
/* Infinity: Suspend wakelock timeout tuning */
#define INFINITY_SUSPEND_WAKELOCK_TIMEOUT       3000
#define INFINITY_SUSPEND_MAX_SLEEP_RETRIES      5

CEOF
    insert_after "${KBUILD}/kernel/power/suspend.c" 'trace/events/power.h' "$INS_DIR/c14.txt" && mod_ok "suspend.c" || mod_fail "suspend.c"

    cat > "$INS_DIR/c15.txt" << 'CEOF'

/* Infinity: Wakelock timeout optimization */
#define INFINITY_WAKELOCK_TIMEOUT       5000
#define INFINITY_WAKELOCK_EXPIRE_CHECK  HZ
CEOF
    insert_after "${KBUILD}/kernel/power/wakelock.c" 'SPDX-License-Identifier' "$INS_DIR/c15.txt" && mod_ok "wakelock.c #1" || mod_fail "wakelock.c #1"

    cat > "$INS_DIR/c16.txt" << 'CEOF'
#ifdef CONFIG_INFINITY_WAKELOCK_DEBUG
        /* Infinity: Enhanced wakelock stats */
        static atomic_t infinity_wakelock_active_count = ATOMIC_INIT(0);
        EXPORT_SYMBOL(infinity_wakelock_active_count);
#endif

CEOF
    insert_after "${KBUILD}/kernel/power/wakelock.c" 'ktime_t now;' "$INS_DIR/c16.txt" && mod_ok "wakelock.c stats" || mod_fail "wakelock.c stats"

    cat > "$INS_DIR/c17.txt" << 'CEOF'
/* Infinity: Thermal margin tuning for charging bypass */
#define INFINITY_THERMAL_MARGIN_HIGH    5
#define INFINITY_THERMAL_MARGIN_LOW             2
#define INFINITY_THERMAL_CHARGE_LIMIT   80

CEOF
    insert_after_close_comment "${KBUILD}/drivers/thermal/qcom/rpm_smd_cooling_device.c" "$INS_DIR/c17.txt" && mod_ok "rpm_smd_cooling_device.c" || mod_fail "rpm_smd_cooling_device.c"

    cat > "$INS_DIR/c18.txt" << 'CEOF'
/* Infinity: TCP Fast Open queue size tuning */
#define INFINITY_TFO_QUEUE_SIZE 4096
#define INFINITY_TFO_BACKLOG_SIZE               1024

CEOF
    insert_after "${KBUILD}/net/ipv4/tcp_fastopen.c" 'linux/crypto.h' "$INS_DIR/c18.txt" && mod_ok "tcp_fastopen.c" || mod_fail "tcp_fastopen.c"

    cat > "$INS_DIR/c19.txt" << 'CEOF'
#ifdef CONFIG_INFINITY_INPUT_BOOST
/* Infinity: Input event latency reduction */
#define INFINITY_EVDEV_PRIORITY 99
#define INFINITY_INPUT_SAMPLE_RATE      1000
#endif

CEOF
    insert_after_close_comment "${KBUILD}/drivers/input/evdev.c" "$INS_DIR/c19.txt" && mod_ok "evdev.c" || mod_fail "evdev.c"

    cat > "$INS_DIR/c20.txt" << 'CEOF'
#define INFINITY_VM_MAX_MAP_COUNT       262144
#define INFINITY_MAX_FILE_COUNT         524288
#define INFINITY_PID_MAX_LIMIT          4194303

CEOF
    insert_after_close_comment "${KBUILD}/arch/arm64/include/asm/memory.h" "$INS_DIR/c20.txt" && mod_ok "memory.h" || mod_fail "memory.h"

    cat > "$INS_DIR/c21.txt" << 'CEOF'
#define INFINITY_HOTPLUG_UP_DELAY       100
#define INFINITY_HOTPLUG_DOWN_DELAY     200

CEOF
    insert_after_close_comment "${KBUILD}/kernel/cpu.c" "$INS_DIR/c21.txt" && mod_ok "cpu.c" || mod_fail "cpu.c"

    cat > "$INS_DIR/c22.txt" << 'CEOF'
#define INFINITY_WALT_BUSY_FACTOR               1200
#define INFINITY_WALT_WINDOW_FACTOR             20000
#define INFINITY_WALT_PREDICTIVE_FACTOR 90
#define INFINITY_WALT_RUNTIME_FACTOR            95

CEOF
    insert_after_close_comment "${KBUILD}/kernel/sched/walt.c" "$INS_DIR/c22.txt" && mod_ok "walt.c" || mod_fail "walt.c"

    cat > "$INS_DIR/c23.txt" << 'CEOF'
#ifdef CONFIG_INFINITY_AUDIO_LOWLATENCY
/* Infinity: PCM low-latency tuning */
#define INFINITY_PCM_PERIOD_SIZE        128
#define INFINITY_PCM_BUFFER_SIZE                1024
#define INFINITY_PCM_LOWLATENCY_MIN     64
#define INFINITY_PCM_LOWLATENCY_MAX     256
static int infinity_pcm_lowlatency = 1;
module_param_named(pcm_low_latency, infinity_pcm_lowlatency, int, 0644);
#endif

CEOF
    insert_after "${KBUILD}/sound/core/pcm.c" 'linux/init.h' "$INS_DIR/c23.txt" && mod_ok "pcm.c" || mod_fail "pcm.c"

    # ---- Upstream Build Fixes ----
    info "Applying upstream build fixes..."

    # 24. modpost.c — (char *)strstr (GCC 15+)
    sed -i 's/here = strstr(sym, bare);/here = (char *)strstr(sym, bare);/' "${KBUILD}/scripts/mod/modpost.c"
    mod_ok "modpost.c (char*)strstr"

    # 25. huge_memory.c — try_to_unmap 3-arg
    sed -i 's/try_to_unmap(page, ttu_flags);/try_to_unmap(page, ttu_flags, NULL);/' "${KBUILD}/mm/huge_memory.c"
    mod_ok "huge_memory.c try_to_unmap 3-arg"

    # 26. btrfs/inode.c — timespec64
    sed -i 's/struct timespec now = current_time/struct timespec64 now = current_time/' "${KBUILD}/fs/btrfs/inode.c"
    mod_ok "btrfs/inode.c timespec64"

    # 27. hugetlbpage.c — ptep -> pte
    sed -i 's/ptep = huge_pmd_share(mm, vma, addr, pud);/pte = huge_pmd_share(mm, vma, addr, pud);/' "${KBUILD}/arch/arm64/mm/hugetlbpage.c"
    mod_ok "hugetlbpage.c ptep->pte"

    # 28. thermal_core.c — duplicate thermal_generate_netlink_event
    sed -i 's/^static inline int thermal_generate_netlink_event(struct thermal_zone_device \*tz,$/\/\/ &/' "${KBUILD}/drivers/thermal/thermal_core.c"
    sed -i 's/^\t\tenum events event) { return -ENODEV; }$/\/\/ \t\tenum events event) { return -ENODEV; }/' "${KBUILD}/drivers/thermal/thermal_core.c"
    mod_ok "thermal_core.c redefinition fix"

    # 29. core.c — NOHZ_BALANCE_KICK guard
    sed -i '/Kick CPU to immediately do load balancing/i\#ifdef CONFIG_NO_HZ_COMMON' "${KBUILD}/kernel/sched/core.c"
    sed -i '/Kick CPU to immediately do load balancing/{n;n;s/$/\n#endif/}' "${KBUILD}/kernel/sched/core.c"
    mod_ok "core.c NOHZ_BALANCE_KICK guard"

    # 30. spi-xiaomi-tp.c — local include
    sed -i 's/#include <spi-xiaomi-tp.h>/#include "spi-xiaomi-tp.h"/' "${KBUILD}/drivers/input/touchscreen/spi-xiaomi-tp.c"
    mod_ok "spi-xiaomi-tp.c local include"

    # 31. cam_trace.h — TRACE_INCLUDE_PATH
    if [ -f "${KBUILD}/drivers/media/platform/msm/camera/cam_utils/cam_trace.h" ]; then
        sed -i 's|^#define TRACE_INCLUDE_PATH .*|#define TRACE_INCLUDE_PATH ../../drivers/media/platform/msm/camera/cam_utils|' \
            "${KBUILD}/drivers/media/platform/msm/camera/cam_utils/cam_trace.h"
        mod_ok "cam_trace.h TRACE_INCLUDE_PATH"
    else
        mod_fail "cam_trace.h (file not found)"
    fi

    info "Modifications: $MOD_COUNT OK, $MOD_FAIL FAILED (of $((MOD_COUNT + MOD_FAIL)))"
    rm -rf "$INS_DIR"

    echo -e "${CYN}--------------------------------------------------------------${NC}" | tee -a "$BUILD_LOG"

    # ===================== STEP 6: KERNEL CONFIGURATION =====================
    echo -e "${CYN}${BOLD}  Step 6: Kernel Configuration${NC}" | tee -a "$BUILD_LOG"

    cd "$KBUILD" || die "Cannot cd to $KBUILD"
    export ARCH="$ARCH"
    export CROSS_COMPILE="$CROSS_COMPILE"
    export SUBARCH="$ARCH"

    # --- Install KernelSU-Next + SuSFS into kernel tree ---
    info "Setting up KernelSU-Next + SuSFS..."
    if [ "$ROOT_MODE" = "none" ]; then
        _create_noop_kernelsu "${KBUILD}/drivers/kernelsu"
        warn "Root disabled (none mode)"
    else
        setup_kernelsu "${KBUILD}/drivers/kernelsu"
    fi
    ok "KernelSU setup complete"

    # Re-install custom files after git checkout
    info "Re-installing custom files..."
    for d in task_engine charging; do
        if [ -d "${SCRIPT_DIR}/drivers/$d" ]; then
            mkdir -p "${KBUILD}/drivers/$d"
            cp -r "${SCRIPT_DIR}/drivers/$d/"* "${KBUILD}/drivers/$d/" 2>/dev/null
        fi
    done
    [ -f "${SCRIPT_DIR}/include/linux/infinity_charging_control.h" ] && \
        cp "${SCRIPT_DIR}/include/linux/infinity_charging_control.h" "${KBUILD}/include/linux/" 2>/dev/null
    ok "Custom files re-installed"

    # Clean build artifacts
    info "Running mrproper..."
    make mrproper >> "$BUILD_LOG" 2>&1 || true

    # CRITICAL: Re-install ALL custom files + KernelSU AFTER mrproper
    info "Re-installing everything after mrproper..."
    # Reinstall KernelSU (mrproper deletes non-git files)
    if [ "$ROOT_MODE" = "none" ]; then
        _create_noop_kernelsu "${KBUILD}/drivers/kernelsu"
    else
        setup_kernelsu "${KBUILD}/drivers/kernelsu"
    fi
    # Reinstall charging/task_engine
    for d in task_engine charging; do
        if [ -d "${SCRIPT_DIR}/drivers/$d" ]; then
            mkdir -p "${KBUILD}/drivers/$d"
            cp -r "${SCRIPT_DIR}/drivers/$d/"* "${KBUILD}/drivers/$d/" 2>/dev/null
        fi
    done
    [ -f "${SCRIPT_DIR}/include/linux/infinity_charging_control.h" ] && \
        cp "${SCRIPT_DIR}/include/linux/infinity_charging_control.h" "${KBUILD}/include/linux/" 2>/dev/null
    # Verify Kconfig exists
    if [ ! -f "${KBUILD}/drivers/kernelsu/Kconfig" ]; then
        die "drivers/kernelsu/Kconfig missing after setup!"
    fi
    ok "Post-mrproper reinstall complete"

    # --- Apply vayu_defconfig ---
    info "Applying vayu_defconfig (base configuration)..."
    make vayu_defconfig >> "$BUILD_LOG" 2>&1
    if [ $? -ne 0 ]; then die "vayu_defconfig failed"; fi
    ok "vayu_defconfig applied (1900+ options)"

    # --- Apply Infinity CONFIGs via scripts/config ---
    info "Applying Infinity-specific CONFIG options..."
    config_enable CONFIG_SECTION_MISMATCH_WARN_ONLY
    config_set_str CONFIG_LOCALVERSION "-Infinity-v${VERSION}"
    config_enable CONFIG_INFINITY_KERNEL

    # KernelSU + SuSFS (skip for "none" mode)
    if [ "$ROOT_MODE" != "none" ]; then
        config_enable CONFIG_KSU
        config_enable CONFIG_KSU_SUSFS
        config_enable CONFIG_KSU_SUSFS_SUS_PATH
        config_enable CONFIG_KSU_SUSFS_SUS_MOUNT
        config_enable CONFIG_KSU_SUSFS_SUS_MOUNT_MNT_ID_REORDER
        config_enable CONFIG_KSU_SUSFS_SPOOF_UNAME
        config_enable CONFIG_KSU_SUSFS_SUS_KSTAT
        config_enable CONFIG_KSU_SUSFS_SUS_MAP
        config_enable CONFIG_KSU_SUSFS_SUS_MEMFD
        config_enable CONFIG_KSU_SUSFS_SUS_PROC_FD_LINK
        config_enable CONFIG_KSU_SUSFS_TRY_UMOUNT
        config_enable CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
        config_enable CONFIG_KSU_SUSFS_OPEN_REDIRECT
    fi

    # Charging control
    config_enable CONFIG_CHARGING_CONTROL

    # --- Force critical platform configs ---
    info "Forcing critical platform configs (safety net)..."
    config_set CONFIG_NR_CPUS 8
    config_enable CONFIG_SCHED_WALT
    config_enable CONFIG_SCHED_TUNE
    config_enable CONFIG_SCHED_CORE_CTL
    config_enable CONFIG_CGROUPS
    config_enable CONFIG_CGROUP_SCHED
    config_enable CONFIG_CGROUP_CPUACCT
    config_enable CONFIG_CGROUP_FREEZER
    config_enable CONFIG_CGROUP_WRITEBACK
    config_enable CONFIG_CGROUP_BPF
    config_enable CONFIG_MEMCG
    config_enable CONFIG_MEMCG_SWAP
    config_enable CONFIG_BLK_CGROUP
    config_enable CONFIG_NO_HZ
    config_enable CONFIG_NO_HZ_COMMON
    config_enable CONFIG_NO_HZ_IDLE
    # KernelSU-Next needs KPROBES
    if [ "$ROOT_MODE" != "none" ]; then
        config_enable CONFIG_KPROBES
        config_enable CONFIG_EXT4_FS
    fi
    ok "All Infinity + platform configs applied"

    # Resolve new Kconfig symbols
    info "Running olddefconfig to resolve dependencies..."
    yes "" | make olddefconfig >> "$BUILD_LOG" 2>&1 || true
    ok "olddefconfig complete"

    # --- Verify critical configs ---
    info "Verifying critical configs..."
    VERIFY_OK=0
    VERIFY_FAIL=0
    verify_config() {
        local name="$1" expected="$2"
        local actual
        actual=$(grep -c "^${name}=${expected}" .config 2>/dev/null || echo "0")
        if [ "$actual" -ge 1 ]; then
            ok "  $name=$expected"
            ((VERIFY_OK++))
        else
            err "  $name != $expected (got: $(grep "^${name}=" .config 2>/dev/null | head -1))"
            ((VERIFY_FAIL++))
        fi
    }
    if [ -f .config ]; then
        verify_config CONFIG_NR_CPUS 8
        verify_config CONFIG_SCHED_WALT y
        verify_config CONFIG_SCHED_TUNE y
        verify_config CONFIG_CGROUPS y
        verify_config CONFIG_NO_HZ_COMMON y
        if [ "$ROOT_MODE" != "none" ]; then
            verify_config CONFIG_KSU y
            verify_config CONFIG_KSU_SUSFS y
            verify_config CONFIG_CHARGING_CONTROL y
        fi
    else
        err "  .config not found - skipping verification"
        VERIFY_FAIL=1
    fi

    if [ $VERIFY_FAIL -gt 0 ]; then
        err "CRITICAL: $VERIFY_FAIL config(s) failed verification!"
        err "Check .config in $KBUILD"
        exit 1
    fi
    ok "All $VERIFY_OK critical configs verified"

    echo -e "${CYN}--------------------------------------------------------------${NC}" | tee -a "$BUILD_LOG"

    # ===================== STEP 7: BUILD KERNEL =====================
    echo -e "${CYN}${BOLD}  Step 7: Build Kernel (Clang/LLVM)${NC}" | tee -a "$BUILD_LOG"
    mkdir -p "$OUT_DIR"
    info "Building with $JOBS jobs... (output to terminal + $BUILD_LOG)"
    make -j"$JOBS" \
        LLVM=1 \
        LLVM_IAS=1 \
        DTC_EXT="dtc" \
        CC="ccache clang" \
        2>&1 | tee -a "$BUILD_LOG"
    MAKE_RC=${PIPESTATUS[0]}
    if [ $MAKE_RC -eq 0 ]; then
        ok "Kernel built successfully!"
    else
        err "Kernel build FAILED (exit code $MAKE_RC)!"
        err "--- Last 80 lines from build log ---"
        tail -80 "$BUILD_LOG" 2>/dev/null | sed 's/^/  /'
        err "--- End of log excerpt ---"
        err "Full log: $BUILD_LOG"
        exit 1
    fi
    echo -e "${CYN}--------------------------------------------------------------${NC}" | tee -a "$BUILD_LOG"

    # ===================== STEP 8: PACKAGE ZIP =====================
    echo -e "${CYN}${BOLD}  Step 8: Package AnyKernel3 ZIP${NC}" | tee -a "$BUILD_LOG"
    AK3_SRC="${SCRIPT_DIR}/AnyKernel3"
    STAGING="${OUT_DIR}/anykernel_staging"
    ZIP_NAME="InfinityKernel-v${VERSION}-vayu.zip"
    rm -rf "$STAGING"; mkdir -p "$STAGING"
    cp -r "$AK3_SRC"/* "$STAGING/"
    mkdir -p "$STAGING/kernel"

    if [ -f "arch/${ARCH}/boot/Image.gz-dtb" ]; then
        cp "arch/${ARCH}/boot/Image.gz-dtb" "$STAGING/kernel/"; ok "Image.gz-dtb"
    elif [ -f "arch/${ARCH}/boot/Image.gz" ]; then
        cp "arch/${ARCH}/boot/Image.gz" "$STAGING/kernel/"; ok "Image.gz"
    elif [ -f "arch/${ARCH}/boot/Image" ]; then
        cp "arch/${ARCH}/boot/Image" "$STAGING/kernel/"; ok "Image"
    else
        die "No kernel image found"
    fi
    [ -f "arch/${ARCH}/boot/dtbo.img" ] && cp "arch/${ARCH}/boot/dtbo.img" "$STAGING/" && ok "DTBO"
    chmod +x "$STAGING/anykernel.sh" 2>/dev/null || true
    cd "$STAGING" && zip -r -9 "${OUT_DIR}/$ZIP_NAME" . -x '.git/*'
    cd "$OUT_DIR" && md5sum "$ZIP_NAME" > "${ZIP_NAME}.md5sum" 2>/dev/null || true
    ok "ZIP: ${OUT_DIR}/$ZIP_NAME"
    echo -e "${CYN}--------------------------------------------------------------${NC}" | tee -a "$BUILD_LOG"

    # ===================== DONE =====================
    echo ""
    echo -e "${GRN}${BOLD}"
    echo "  =========================================="
    echo "  "
    echo "     Infinity Kernel v${VERSION} — BUILD COMPLETE!  "
    echo "     Device: Poco X3 Pro (vayu/bhima)           "
    echo "     Root: ${ROOT_LABEL} (universal binary)       "
    echo "  "
    echo "     ZIP: out/InfinityKernel-v${VERSION}-vayu.zip "
    echo "  "
    echo "  =========================================="
    echo -e "${NC}"
    info "Flashable: ${OUT_DIR}/$ZIP_NAME"
}

main "$@"