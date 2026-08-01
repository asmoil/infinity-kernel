#!/bin/bash
##########################################################################################
#  Infinity Kernel v2.1.3 — Build Script
#  Device: Poco X3 Pro (vayu/bhima) — Snapdragon 860 (SM8150-AC)
#  Base:   AnymoreProject/android_kernel_vayu (Linux 4.14.356+13, OPENELA upstream)
#
#  Multi-root build system (ONE BINARY for all root managers):
#    ./build.sh              # Default: kernelsu
#    ./build.sh kernelsu     # KernelSU-Next
#    ./build.sh sukisu_ultra # SukiSU-Ultra (same binary, label in log)
#    ./build.sh resukisu     # ReSukiSU (same binary, label in log)
#    ./build.sh kowsu        # KoWSu (same binary, label in log)
#    ./build.sh apatch       # APatch (same binary, label in log)
#    ./build.sh none         # No root (different binary, no CONFIG_KSU)
#    ./build.sh kernelsu 4   # Thread count (default = nproc)
#
#  v2.1.3 — ALL FIXES:
#    - CRITICAL FIX: patch 0005 no longer breaks block/Kconfig
#    - CRITICAL FIX: patch 0004 correctly places INFINITY_KERNEL before menu General setup
#    - CRITICAL FIX: ALL missing files added (scripts/, AnyKernel3/tools/, META-INF/)
#    - v2.1.2: TASK ENGINE files, git clean excludes
#    - v2.1.1: sudo -v in prerequisites + bind mount fallback
#    - CRITICAL FIX: install task_engine files (was missing → Kconfig error)
#    - CRITICAL FIX: install infinity_task_engine.h header
#    - v2.1.1: sudo -v in prerequisites + bind mount fallback
#    - v2.1.0: ALL 31 patches regenerated as proper git diffs
#    - v2.1.0: Fixed duplicate configs, broken Kconfig, missing quote
#    - SoC: Snapdragon 860 (SM8150-AC)
#
#  Copyright (c) 2024-2026 Infinity Kernel Team
#  Licensed under MIT License
##########################################################################################

set -uo pipefail

# ═══════════════════════════════════════════════════════════════════════════════
#  CONFIGURATION
# ═════════════════════════════════════════════════════════════════════════════

VERSION="2.1.4"
DEVICE="vayu"
ARCH="arm64"
KERNEL_REPO_URL="https://github.com/AnymoreProject/android_kernel_vayu"

# Multi-root: all KSU variants produce the SAME binary (same .config)
# Only ROOT_LABEL differs in log/ZIP metadata
# "none" produces a different binary (no CONFIG_KSU)
ROOT_MODE_INPUT="${1:-kernelsu}"
ROOT_MODE=""
ROOT_LABEL=""
CLONE_BRANCH="ksu"

case "$ROOT_MODE_INPUT" in
  kernelsu|ksu|kernelsu_next|kernelsu-next)
    ROOT_MODE="kernelsu"; ROOT_LABEL="KernelSU-Next"; CLONE_BRANCH="ksu" ;;
  sukisu_ultra|sukisu-ultra|sukisu|suki)
    ROOT_MODE="kernelsu"; ROOT_LABEL="SukiSU-Ultra"; CLONE_BRANCH="ksu" ;;
  resukisu|re-sukisu|resuki)
    ROOT_MODE="kernelsu"; ROOT_LABEL="ReSukiSU"; CLONE_BRANCH="ksu" ;;
  kowsu|kow)
    ROOT_MODE="kernelsu"; ROOT_LABEL="KoWSu"; CLONE_BRANCH="ksu" ;;
  apatch|apatchet)
    ROOT_MODE="kernelsu"; ROOT_LABEL="APatch"; CLONE_BRANCH="ksu" ;;
  none|noroot|no-root)
    ROOT_MODE="none"; ROOT_LABEL="None"; CLONE_BRANCH="ksu" ;;
  *)
    ROOT_MODE="kernelsu"; ROOT_LABEL="KernelSU-Next ($ROOT_MODE_INPUT)"; CLONE_BRANCH="ksu"
    warn "Unknown root mode '$ROOT_MODE_INPUT' — defaulting to kernelsu"
    ;;
esac

JOBS="${2:-$(nproc)}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KERNEL_SRC="${SCRIPT_DIR}/kernel_src"
PATCHES_DIR="${SCRIPT_DIR}/patches"
ANYKERNEL_DIR="${SCRIPT_DIR}/AnyKernel3"
OUT_DIR="${SCRIPT_DIR}/out"
WORK_DIR=""
LOG_FILE="${SCRIPT_DIR}/infinity_build.log"
CROSS_COMPILE="aarch64-linux-gnu-"
BIND_MOUNT_USED=0
KSU_OK=0
SUSFS_OK=0
KERNEL_VERSION_STRING=""

# ═══════════════════════════════════════════════════════════════════════════════
#  GLOBAL LOGGING
# ═══════════════════════════════════════════════════════════════════════════════

mkdir -p "$SCRIPT_DIR" 2>/dev/null
: > "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

# Colors
RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[1;33m'; CYN='\033[0;36m'
MGN='\033[0;35m'; BOLD='\033[1m'; RST='\033[0m'; NC='\033[0m'

info()    { echo -e "${GRN}[INFO]$(date +%H:%M:%S)${NC} $*"; }
warn()    { echo -e "${YEL}[WARN]$(date +%H:%M:%S)${NC} $*"; }
err()     { echo -e "${RED}[ERROR]$(date +%H:%M:%S)${NC} $*" >&2; }
die()     { err "$*"; exit 1; }
ok()      { echo -e "${GRN}  ✓${NC} $*"; }
step()    { echo ""; echo -e "${CYN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYN}${BOLD}  $1${NC}"; echo -e "${CYN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo ""; }
separator() { echo -e "${CYN}──────────────────────────────────────────────────────────────────────${NC}"; }

# ═════════════════════════════════════════════════════════════════════════════
#  BANNER
# ═══════════════════════════════════════════════════════════════════════════════════

print_banner() {
    echo -e "${MGN}${BOLD}"
    echo "  ╔═════════════════════════════════════════╗"
    echo "  ║                                                   ║"
    echo "  ║        ██╗  ██╗███████╗██╗   ██╗███╗   ██╗ ██████╗      ║"
    echo "  ║        ██║ ██╔╝██╔════╝╚██╗ ██╔╝████╗  ██║██╔═══██╗     ║"
    echo "  ║        █████╔╝ █████╗   ╚████╔╝ ██╔██╗ ██║██║   ██║     ║"
    echo "  ║        ██║═██╗ ██╔══╝    ╚██╔╝  ██╚██╗██║██║   ██║     ║"
    echo "  ║        ██║  ██╗███████╗   ██║   ██║ ╚████║╚██████╔╝     ║"
    echo "  ║        ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═══╝ ╚═════╝      ║"
    echo "  ║                     K E R N E L                         ║"
    echo "  ║                                                   ║"
    echo "  ║     v${VERSION}  •  Poco X3 Pro (vayu/bhima)               ║"
    echo "  ║     Root: ${ROOT_LABEL}                                         ║"
    echo "  ║     Binary: ${ROOT_MODE} (universal for all KSU managers)     ║"
    echo "  ╚═══════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    info "Infinity Kernel v${VERSION} Build System"
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    info "  Log file:     ${LOG_FILE}"
    info "  Script dir:   ${SCRIPT_DIR}"
    info "  Kernel src:   ${KERNEL_SRC}"
    info "  Device:       ${DEVICE}"
    info "  Root:         ${ROOT_MODE_INPUT} → ${ROOT_LABEL}"
    info "  Clone branch: ${CLONE_BRANCH}"
    info "  Jobs:         ${JOBS}"
    info "  Build type:    $([ "${ROOT_MODE}" = "none" ] && echo 'clean (no root)' || echo 'universal KSU binary')"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Step 0: Prerequisites
# ═════════════════════════════════════════════════════════════════════════════════════════

check_prerequisites() {
    step "Step 0: Prerequisites Check"
    local missing=0
    for tool in git make gcc aarch64-linux-gnu-gcc patch zip sudo; do
        command -v "$tool" >/dev/null 2>&1 && ok "$tool" || { err "  ✗ $tool"; missing=$((missing+1)); }
    done
    [ "$missing" -gt 0 ] && die "Missing $missing tool(s)"
    ok "All prerequisites met"

    # v2.1.1 CRITICAL: Cache sudo credentials NOW
    # Without this, sudo in bind mount step silently waits for password (invisible prompt)
    info "Pre-authenticating sudo (for bind mount)..."
    if ! sudo -v; then
        warn "sudo requires a password — please enter it now"
        if ! sudo -v; then
            warn "sudo auth failed — bind mount may not work"
            warn "Workaround: run 'sudo -v' in terminal, then re-run build.sh"
        else
            ok "sudo credentials cached (2nd attempt)"
        fi
    else
        ok "sudo credentials cached"
    fi
    echo ""
    info "System information:"
    info "  OS:      $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
    info "  Arch:    $(uname -m)"
    info "  Jobs:    ${JOBS} (nproc=$(nproc))"
    info "  GCC:     $(aarch64-linux-gnu-gcc --version 2>/dev/null | head -1)"
    info "  Git:     $(git --version 2>/dev/null | head -1)"
    info "  Date:    $(date)"
    separator
}

# ═════════════════════════════════════════════════════════════════════════════════════════
#  Step 1: AVX2 Detection
# ═══════════════════════════════════════════════════════════════════════════════════════

detect_avx2() {
    step "Step 1: AVX2 Detection"
    if grep -qE 'avx2' /proc/cpuinfo 2>/dev/null; then
        warn "AVX2 detected — Neutron Clang usable (but GCC is fine too)"
    else
        warn "No AVX2 — falling back to GCC"
    fi
    info "CROSS_COMPILE: ${CROSS_COMPILE}"
    separator
}

# ═══════════════════════════════════════════════════════════════════════════════════════════
#  Step 2: Clone / Update Kernel Source
# ═══════════════════════════════════════════════════════════════════════════════════════════

clone_kernel_source() {
    step "Step 2: Clone Kernel Source"
    if [ -d "${KERNEL_SRC}/.git" ]; then
        local cb
        cb=$(git -C "${KERNEL_SRC}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        info "Existing clone at ${KERNEL_SRC} (branch: ${cb})"
        if git -C "${KERNEL_SRC}" fetch origin "${CLONE_BRANCH}" 2>/dev/null; then
            # NOTE: fetch alone does not touch the working tree or move HEAD.
            # Without an explicit reset, repeated builds silently stay frozen
            # on whatever commit was first cloned, so patch context can drift
            # out of sync with upstream on every subsequent run.
            git -C "${KERNEL_SRC}" checkout "${CLONE_BRANCH}" 2>/dev/null || true
            if git -C "${KERNEL_SRC}" reset --hard "origin/${CLONE_BRANCH}" 2>/dev/null; then
                ok "Kernel source updated to latest origin/${CLONE_BRANCH}"
            else
                warn "reset to origin/${CLONE_BRANCH} failed — using local state"
            fi
        else
            warn "fetch failed (offline?) — using existing local state"
        fi
        ok "Kernel source ready"
    else
        info "Cloning ${KERNEL_REPO_URL} (branch: ${CLONE_BRANCH})..."
        rm -rf "${KERNEL_SRC}"
        git clone --depth=1 --branch "${CLONE_BRANCH}" \
            "${KERNEL_REPO_URL}" "${KERNEL_SRC}" 2>&1 || die "Clone failed"
        ok "Kernel source cloned"
    fi
    # Detect version
    if [ -f "${KERNEL_SRC}/Makefile" ]; then
        local kver pl sl ex
        kver=$(grep -E '^VERSION[[:space:]]*=' "${KERNEL_SRC}/Makefile" 2>/dev/null | head -1 | awk '{print $NF}')
        pl=$(grep -E '^PATCHLEVEL[[:space:]]*=' "${KERNEL_SRC}/Makefile" 2>/dev/null | head -1 | awk '{print $NF}')
        sl=$(grep -E '^SUBLEVEL[[:space:]]*=' "${KERNEL_SRC}/Makefile" 2>/dev/null | head -1 | awk '{print $NF}')
        ex=$(grep -E '^EXTRAVERSION[[:space:]]*=' "${KERNEL_SRC}/Makefile" 2>/dev/null | head -1 | sed 's/^EXTRAVERSION[[:space:]]*=[[:space:]]*//')
        KERNEL_VERSION_STRING="${kver}.${pl}.${sl}${ex}"
        info "Kernel: ${KERNEL_VERSION_STRING}"
    fi

    # Mark this exact state (post-clone/post-reset, pre-any-patch) as the
    # canonical clean baseline. apply_patches() resets here at the start of
    # every run instead of just "checkout -- ." (which only restores the
    # working tree to whatever HEAD happens to be — including a HEAD that a
    # previous run may have advanced with patch-application commits).
    if [ -d "${KERNEL_SRC}/.git" ]; then
        git -C "${KERNEL_SRC}" tag -f infinity-pristine >/dev/null 2>&1
    fi
    separator
}

# ═══════════════════════════════════════════════════════════════════════════════════════════
#  Step 2b: Repair KernelSU-Next Submodule
# ═══════════════════════════════════════════════════════════════════════════════════════

repair_kernelsu_submodule() {
    step "Step 2b: Repair KernelSU-Next Submodule"
    [ "${ROOT_MODE}" = "none" ] && { info "Skipping (root=none)"; separator; return 0; }

    local ksu_dir="${KERNEL_SRC}/KernelSU-Next"
    local ksu_kernel="${ksu_dir}/kernel"
    local ksu_symlink="${KERNEL_SRC}/drivers/kernelsu"

    if [ -d "${ksu_kernel}" ] && [ -f "${ksu_kernel}/Kconfig" ]; then
        ok "KernelSU-Next already populated"
        KSU_OK=1; separator; return 0
    fi

    warn "KernelSU-Next submodule is EMPTY — repairing..."

    # Step 1: git submodule update
    git -C "${KERNEL_SRC}" submodule update --init 2>/dev/null
    [ -f "${ksu_kernel}/Kconfig" ] && { ok "git submodule update worked"; KSU_OK=1; separator; return 0; }

    # Step 2: Clean and clone manually
    rm -rf "${ksu_dir}"
    local ksu_urls=(
        "https://github.com/negrroo/KernelSU"
        "https://github.com/KernelSU-Next/KernelSU"
        "https://github.com/tiann/KernelSU"
    )
    local ksu_branches=("main" "v3.2.0" "v3.1.0")

    for url in "${ksu_urls[@]}"; do
        [ "$KSU_OK" = "1" ] && break
        for branch in "${ksu_branches[@]}"; do
            [ "$KSU_OK" = "1" ] && break
            info "  Trying: ${url} (branch: ${branch})..."
            rm -rf "${ksu_dir}"
            if GIT_TERMINAL_PROMPT=0 git clone --depth=1 --branch "${branch}" \
                --config "credential.helper=" "${url}" "${ksu_dir}" 2>/dev/null; then
                if [ -d "${ksu_kernel}" ] && [ "$(ls -A "${ksu_kernel}" 2>/dev/null)" ]; then
                    ok "Cloned from ${url} (${branch})"
                    KSU_OK=1; break 2
                fi
            fi
            rm -rf "${ksu_dir}" 2>/dev/null
        done
    done

    if [ "$KSU_OK" = "1" ]; then
        # Recreate symlink
        rm -f "${ksu_symlink}"
        ln -sf ../KernelSU-Next/kernel "${ksu_symlink}"
        [ -f "${ksu_kernel}/Kconfig" ] && ok "Symlink verified" || { warn "Kconfig missing!"; KSU_OK=0; }
    else
        die "Failed to clone KernelSU from all URLs"
    fi
    separator
}

# ═══════════════════════════════════════════════════════════════════════════════════════════
#  Step 3: Bind Mount
# ═══════════════════════════════════════════════════════════════════════════════════════════

setup_bind_mount() {
    step "Step 3: Bind Mount Setup"
    local path="${KERNEL_SRC}"
    local needs_mount=0
    echo "$path" | grep -qE '[[:space:]]' && needs_mount=1
    [ "$(printf '%s' "$path" | LC_ALL=C grep -c '[^A-Za-z0-9 _./~:-]' 2>/dev/null)" -gt 0 ] && needs_mount=1

    if [ "$needs_mount" = "1" ]; then
        info "Path has spaces/Cyrillic — using bind mount"
        sudo umount /tmp/infinity-kbuild 2>/dev/null || true

        # v2.1.1: Verify mkdir succeeds
        if ! sudo mkdir -p /tmp/infinity-kbuild 2>/dev/null; then
            warn "sudo mkdir failed — trying without sudo"
            mkdir -p /tmp/infinity-kbuild 2>/dev/null || true
        fi

        if [ ! -d /tmp/infinity-kbuild ]; then
            # v2.1.1 CRITICAL: fallback to original path instead of dying
            warn "Cannot create /tmp/infinity-kbuild — FALLING BACK to original path"
            warn "Build may fail if path has spaces. Run 'sudo -v' first if needed."
            WORK_DIR="${KERNEL_SRC}"
            cd "${WORK_DIR}" || die "cd failed"
        elif ! sudo mount --bind "${path}" /tmp/infinity-kbuild 2>&1; then
            # v2.1.1 CRITICAL: fallback instead of die
            warn "Bind mount failed — FALLING BACK to original path"
            warn "Build may fail if path has spaces/Cyrillic characters"
            WORK_DIR="${KERNEL_SRC}"
            cd "${WORK_DIR}" || die "cd failed"
        else
            [ -f "/tmp/infinity-kbuild/Makefile" ] || { warn "Bind mount broken — falling back"; sudo umount /tmp/infinity-kbuild 2>/dev/null; WORK_DIR="${KERNEL_SRC}"; cd "${WORK_DIR}" || die "cd failed"; separator; return 0; }
            BIND_MOUNT_USED=1
            WORK_DIR="/tmp/infinity-kbuild"
            cd "${WORK_DIR}" || die "cd failed"
            ok "Bind mount: ${path} → /tmp/infinity-kbuild"
        fi
    else
        WORK_DIR="${KERNEL_SRC}"
        cd "${WORK_DIR}" || die "cd failed"
        ok "No bind mount needed"
    fi
    separator
}

# ═════════════════════════════════════════════════════════════════════════════════════════
#  Step 4: Install Custom Files
# ═════════════════════════════════════════════════════════════════════════════════════════════

install_custom_files() {
    step "Step 4: Install Custom Files"
    local kdir="${WORK_DIR}"

    # v2.1.4 CRITICAL: Add INFINITY_KERNEL menuconfig to init/Kconfig via awk
    # (patch approach unreliable — context mismatch across kernel versions)
    # Uses fragment file + awk to insert before 'menu "General setup"'
    #
    # *** BUG FIX: the old guard was `grep -q 'INFINITY_KERNEL'`, which
    # matches ANY line containing that string — including the many
    # "depends on INFINITY_KERNEL" / "default y if INFINITY_KERNEL" lines
    # that patches 0003/0006/0007/0008/... add elsewhere in this same file.
    # Once any of those patches applied, the guard saw a false-positive
    # match and skipped inserting the fragment — meaning the master
    # `menuconfig INFINITY_KERNEL` toggle itself was NEVER actually
    # defined. Every "default y if INFINITY_KERNEL" across all patches
    # then silently evaluated to n (undefined symbol), so the build would
    # succeed but almost none of Infinity Kernel's features would be
    # enabled by default. The guard must match only the DEFINITION.
    local kconfig_frag="${SCRIPT_DIR}/scripts/kconfig_infinity_fragment.txt"
    if ! grep -qE '^(menuconfig|config)[[:space:]]+INFINITY_KERNEL[[:space:]]*$' "${kdir}/init/Kconfig" 2>/dev/null; then
        if [ -f "$kconfig_frag" ]; then
            awk -v frag="$kconfig_frag" '/^menu "General setup"/ && !done { while ((getline line < frag) > 0) print line; close(frag); done=1 } { print }' "${kdir}/init/Kconfig" > "${kdir}/init/Kconfig.tmp" 2>/dev/null && \
                mv -f "${kdir}/init/Kconfig.tmp" "${kdir}/init/Kconfig" 2>/dev/null && \
                ok "INFINITY_KERNEL menuconfig added to init/Kconfig" || \
                warn "INFINITY_KERNEL insert failed"
        else
            warn "kconfig_infinity_fragment.txt not found — INFINITY_KERNEL not added!"
        fi
    else
        ok "INFINITY_KERNEL already in init/Kconfig"
    fi

    # 4b: Task Engine driver (v2.1.2 CRITICAL: was missing)
    if [ -d "${SCRIPT_DIR}/drivers/task_engine" ]; then
        mkdir -p "${kdir}/drivers/task_engine"
        cp -f "${SCRIPT_DIR}/drivers/task_engine/"*.c "${kdir}/drivers/task_engine/" 2>/dev/null
        cp -f "${SCRIPT_DIR}/drivers/task_engine/Kconfig" "${kdir}/drivers/task_engine/" 2>/dev/null
        cp -f "${SCRIPT_DIR}/drivers/task_engine/Makefile" "${kdir}/drivers/task_engine/" 2>/dev/null
        ok "Task Engine driver installed"
        # Add to drivers/Makefile (patch only adds Kconfig source, not Makefile obj)
        grep -q 'task_engine' "${kdir}/drivers/Makefile" 2>/dev/null || \
            echo 'obj-$(CONFIG_INFINITY_TASK_ENGINE) += task_engine/' >> "${kdir}/drivers/Makefile"
    fi

    # 4c: Charging driver
    if [ -d "${SCRIPT_DIR}/drivers/charging" ]; then
        mkdir -p "${kdir}/drivers/charging"
        cp -f "${SCRIPT_DIR}/drivers/charging/"*.c "${kdir}/drivers/charging/" 2>/dev/null
        cp -f "${SCRIPT_DIR}/drivers/charging/Kconfig" "${kdir}/drivers/charging/" 2>/dev/null
        cp -f "${SCRIPT_DIR}/drivers/charging/Makefile" "${kdir}/drivers/charging/" 2>/dev/null
        grep -q 'charging' "${kdir}/drivers/Kconfig" 2>/dev/null || \
            echo 'source "drivers/charging/Kconfig"' >> "${kdir}/drivers/Kconfig"
        grep -q 'charging' "${kdir}/drivers/Makefile" 2>/dev/null || \
            echo 'obj-$(CONFIG_INFINITY_CHARGING_CONTROL) += charging/' >> "${kdir}/drivers/Makefile"
        ok "Charging driver installed"
    fi

    # 4e: Headers (both charging and task engine)
    if [ -f "${SCRIPT_DIR}/include/linux/infinity_charging_control.h" ]; then
        mkdir -p "${kdir}/include/linux"
        cp -f "${SCRIPT_DIR}/include/linux/infinity_charging_control.h" "${kdir}/include/linux/" 2>/dev/null
        ok "Charging header installed"
    fi
    if [ -f "${SCRIPT_DIR}/include/linux/infinity_task_engine.h" ]; then
        mkdir -p "${kdir}/include/linux"
        cp -f "${SCRIPT_DIR}/include/linux/infinity_task_engine.h" "${kdir}/include/linux/" 2>/dev/null
        ok "Task Engine header installed"
    fi

    # 4c: infinity_defconfig
    if [ -f "${SCRIPT_DIR}/arch/arm64/configs/infinity_defconfig" ]; then
        mkdir -p "${kdir}/arch/arm64/configs"
        cp -f "${SCRIPT_DIR}/arch/arm64/configs/infinity_defconfig" "${kdir}/arch/arm64/configs/"
        ok "infinity_defconfig installed"
    fi

    # 4d: SuSFS config
    if [ -f "${SCRIPT_DIR}/scripts/susfs/sufs_config.h" ]; then
        mkdir -p "${kdir}/scripts/susfs"
        cp -f "${SCRIPT_DIR}/scripts/susfs/sufs_config.h" "${kdir}/scripts/susfs/" 2>/dev/null
    fi

    # 4e: Verify KernelSU
    if [ -L "${kdir}/drivers/kernelsu" ]; then
        info "  drivers/kernelsu → $(readlink "${kdir}/drivers/kernelsu")"
        [ -f "${kdir}/drivers/kernelsu/Kconfig" ] && ok "  Kconfig OK" || warn "  Kconfig MISSING"
    fi

    separator
}

# ══════════════════════════════════════════════════════════════════════════════════════════════════
#  Step 5: Apply Patches
# ═══════════════════════════════════════════════════════════════════════════════════════════

apply_patches() {
    step "Step 5: Apply Patches"

    local kdir="${WORK_DIR}"

    # *** CRITICAL FIX v2.0.3: Clean kernel tree before patches ***
    # Previous runs may have modified the source tree. git checkout restores it.
    if [ -d "${kdir}/.git" ]; then
        info "Cleaning kernel tree before patches..."
        if git -C "${kdir}" rev-parse infinity-pristine >/dev/null 2>&1; then
            # Reset to the recorded pristine baseline, not just "whatever
            # HEAD currently is" — a prior run may have left HEAD advanced
            # by patch-checkpoint commits (see the loop below), and a plain
            # "checkout -- ." would silently keep those instead of starting
            # from a truly clean tree.
            git -C "${kdir}" reset --hard infinity-pristine 2>/dev/null
        else
            git -C "${kdir}" checkout -- . 2>/dev/null
        fi
        git -C "${kdir}" clean -fd --exclude=KernelSU-Next --exclude=drivers/kernelsu 2>/dev/null
        ok "Tree cleaned"
    else
        warn "No .git — cannot auto-clean (first run)"
    fi
    echo ""

    if [ ! -d "${PATCHES_DIR}" ]; then
        warn "No patches directory"; separator; return 0
    fi

    local patch_files=()
    while IFS= read -r -d '' pfile; do
        patch_files+=("$pfile")
    done < <(find "${PATCHES_DIR}" -maxdepth 1 -name '*.patch' -print0 2>/dev/null | sort -z)

    local total=${#patch_files[@]}
    info "Found ${total} patch file(s)"
    echo ""

    local applied=0 failed=0
    local has_git=0
    [ -d "${kdir}/.git" ] && has_git=1

    for pf in "${patch_files[@]}"; do
        local name=$(basename "$pf")
        info "  Applying: ${name}"

        # *** FIX: Only try p1 (git diff format). ALL output suppressed. ***
        # This prevents the massive log spam from p0/p2 retries.
        if (cd "${kdir}" && patch -p1 --batch --fuzz=1 --forward \
                --no-backup-if-mismatch -i "$pf" \
                2>/dev/null); then
            ok "    ${name} — OK"
            ((applied++))
            # Checkpoint: commit so a LATER failed patch can be reverted
            # without losing every patch applied before it.
            if [ "$has_git" = "1" ]; then
                git -C "${kdir}" add -A >/dev/null 2>&1
                git -C "${kdir}" commit -q --no-verify -m "infinity-patch: ${name}" >/dev/null 2>&1
            fi
        else
            # patch(1) is not atomic: a multi-hunk patch can leave earlier
            # hunks applied even though the overall command failed. Revert
            # to the last checkpoint before trying the 3-way fallback so it
            # starts from a known-clean base rather than a half-patched one.
            if [ "$has_git" = "1" ]; then
                git -C "${kdir}" checkout -- . 2>/dev/null
                git -C "${kdir}" clean -fd --exclude=KernelSU-Next --exclude=drivers/kernelsu 2>/dev/null
            fi

            # Try git apply 3way as fallback
            if [ "$has_git" = "1" ] && git -C "${kdir}" apply --3way --whitespace=nowarn \
                    "$pf" 2>/dev/null; then
                ok "    ${name} — OK (git apply --3way)"
                ((applied++))
                git -C "${kdir}" add -A >/dev/null 2>&1
                git -C "${kdir}" commit -q --no-verify -m "infinity-patch: ${name}" >/dev/null 2>&1
            else
                # *** CRITICAL FIX: on failure, git apply --3way can leave
                # literal <<<<<<< / ======= / >>>>>>> conflict markers
                # written directly into the real source file (this is NOT
                # the same as patch(1)'s .rej files, and the old cleanup
                # below never caught it). Left in place, those markers sit
                # in whatever file the patch targeted - if that happens to
                # be a Kconfig file, the next `make defconfig` dies with a
                # cryptic "unexpected end statement" that gives no hint a
                # patch ever failed. Hard-revert to the last good checkpoint
                # so nothing from this failed attempt survives.
                if [ "$has_git" = "1" ]; then
                    git -C "${kdir}" checkout -- . 2>/dev/null
                    git -C "${kdir}" clean -fd --exclude=KernelSU-Next --exclude=drivers/kernelsu 2>/dev/null
                fi
                find "${kdir}" -name "*.rej" -delete 2>/dev/null
                find "${kdir}" -name "*.orig" -delete 2>/dev/null
                warn "    ${name} — FAILED"
                ((failed++))
            fi
        fi
        # Clean up rejects from any attempt
        find "${kdir}" -name "*.rej" -delete 2>/dev/null
        find "${kdir}" -name "*.orig" -delete 2>/dev/null
    done

    echo ""
    info "Patch result: ${applied} OK, ${failed} FAILED (of ${total})"

    if [ "$failed" -gt 0 ]; then
        warn "Some patches failed — this is NON-CRITICAL if kernel compiles"
    fi

    separator
}

# ════════════════════════════════════════════════════════════════════════════════════════════════
#  Step 6: Kernel Configuration
# ════════════════════════════════════════════════════════════════════════════════════════

configure_kernel() {
    step "Step 6: Kernel Configuration"
    local kdir="${WORK_DIR}"

    # v2.1.0: Verify Makefile is not corrupted
    if ! make -C "${kdir}" -n -f Makefile kernelversion 2>/dev/null; then
        err "Makefile is CORRUPTED — restoring via git checkout"
        git -C "${kdir}" checkout -- Makefile 2>/dev/null || true
    fi

    info "Applying base defconfig: ${DEVICE}_defconfig..."
    make -C "${kdir}" ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} \
        "${DEVICE}_defconfig" 2>&1 | tail -3
    [ $? -ne 0 ] && die "${DEVICE}_defconfig failed (check Kconfig)"
    ok "Base defconfig applied"

    echo ""
    info "Merging infinity_defconfig overlay..."
    if [ -f "${kdir}/arch/arm64/configs/infinity_defconfig" ]; then
        "${kdir}/scripts/kconfig/merge_config.sh" "${kdir}/.config" \
            "${kdir}/arch/arm64/configs/infinity_defconfig" 2>/dev/null || true
        ok "Overlay merged"
    fi

    echo ""
    info "Running olddefconfig (3 passes)..."
    for i in 1 2 3; do
        make -C "${kdir}" ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} olddefconfig 2>&1 | tail -1
    done
    ok "olddefconfig done"

    echo ""
    info "Forcing critical configs..."

    local FORCE_CFGS=(
        "CONFIG_HZ_1000=y"
        "CONFIG_NO_HZ_COMMON=y"
        "CONFIG_NO_HZ_IDLE=y"
        "CONFIG_VIRT_CPU_ACCOUNTING_GEN=y"
        "CONFIG_CONTEXT_TRACKING=y"
        "CONFIG_NO_HZ=y"
        "CONFIG_TCP_CONG_BBR=y"
        "CONFIG_DEFAULT_TCP_CONG=\"bbr\""
        "CONFIG_CPU_FREQ_DEFAULT_GOV_INTERACTIVE=y"
        "CONFIG_ZRAM=y"
        "CONFIG_ZRAM_LZ4_COMPRESS=y"
        "CONFIG_SECTION_MISMATCH_WARN_ONLY=y"
        "CONFIG_ANDROID_INTF_MSG_DEV=y"
        "CONFIG_INPUT_BOOST=y"
        "CONFIG_RCU_EXPERT=y"
        "CONFIG_CONTEXT_TRACKING_FORCE=y"
    )

    for cfg in "${FORCE_CFGS[@]}"; do
        local key="${cfg%%=*}"
        sed -i "s|^${key}=.*|${cfg}|" "${kdir}/.config" 2>/dev/null || true
        sed -i "s|^# ${key} is not set|${cfg}|" "${kdir}/.config" 2>/dev/null || true
        if ! grep -q "^${key}=" "${kdir}/.config" 2>/dev/null && \
           ! grep -q "^# ${key} is not set" "${kdir}/.config" 2>/dev/null; then
            echo "${cfg}" >> "${kdir}/.config" 2>/dev/null
        fi
    done

    ok "Critical configs forced"

    # v2.0.6 FIX: yes "" | make oldconfig to resolve CONTEXT_TRACKING_FORCE
    echo ""
    info "Running silent oldconfig (resolves new config options)..."
    yes "" | make -C "${kdir}" ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} oldconfig 2>&1 | tail -3
    ok "oldconfig done"

    separator
}

# ══════════════════════════════════════════════════════════════════════════════════════════════
#  Step 7: Multi-Root Setup (UNIVERSAL BINARY)
# ════════════════════════════════════════════════════════════════════════════════════
# ONE binary for ALL root managers. ROOT_LABEL is display-only.
# Only "none" produces a different binary (no CONFIG_KSU).

setup_root_solution() {
    step "Step 7: Multi-Root Setup (Universal Binary)"
    local kdir="${WORK_DIR}"

    if [ "${ROOT_MODE}" = "none" ]; then
        info "Root mode: NONE — no CONFIG_KSU (different binary)"
        if [ -f "${kdir}/.config" ]; then
            sed -i 's/^CONFIG_KSU=y/# CONFIG_KSU is not set/' "${kdir}/.config" 2>/dev/null || true
            sed -i 's/^CONFIG_KSU_SUSFS.*/# CONFIG_KSU_SUSFS is not set/' "${kdir}/.config" 2>/dev/null || true
            ok "CONFIG_KSU disabled"
        fi
    else
        info "Root mode: ${ROOT_LABEL} — UNIVERSAL KSU binary"
        info "  Same binary works with: KernelSU-Next, SukiSU-Ultra, ReSukiSU, KoWSu, APatch"
        echo ""
        info "Forcing KSU config (identical for ALL root modes except 'none')..."
        local ksu_cfgs=(
            "CONFIG_KSU=y"
            "CONFIG_KSU_SUSFS=y"
            "CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y"
            "CONFIG_KSU_SUSFS_SUS_PATH=y"
            "CONFIG_KSU_SUSFS_SUS_MOUNT=y"
            "CONFIG_KSU_SUSFS_TMPS_MOUNT=y"
            "CONFIG_KSU_SUSFS_TRY_UMOUNT=y"
            "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_MODULE=y"
            "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_PATH_LIST=y"
        )
        for cfg in "${ksu_cfgs[@]}"; do
            sed -i "s|^${cfg%%=*}=.*|${cfg}|" "${kdir}/.config" 2>/dev/null || true
            sed -i "s|^# ${cfg%%=*} is not set|${cfg}|" "${kdir}/.config" 2>/dev/null || true
            if ! grep -q "^${cfg%%=*}=" "${kdir}/.config" 2>/dev/null && \
               ! grep -q "^# ${cfg%%=*} is not set" "${kdir}/.config" 2>/dev/null; then
                echo "${cfg}" >> "${kdir}/.config" 2>/dev/null
            fi
        done
        ok "CONFIG_KSU + SuSFS forced (universal binary)"
    fi

    separator
}

# ══════════════════════════════════════════════════════════════════════════════════════════
#  Step 8: Apply SuSFS
# ══════════════════════════════════════════════════════════════════════════════════════════════

apply_susfs() {
    step "Step 8: Apply SuSFS"
    [ "${ROOT_MODE}" = "none" ] && { info "Skipping (root=none)"; separator; return 0; }
    local kdir="${WORK_DIR}"
    [ -f "${kdir}/.susfs_applied" ] && { ok "SuSFS already applied"; separator; return 0; }

    info "Setting up SuSFS (v2.2.0)..."
    local susfs_repos=(
        "https://github.com/ShirkNeko/susfs4ksu"
        "https://github.com/kutemeikito/susfs4ksu"
        "https://github.com/sidex15/susfs4ksu"
    )
    local susfs_branches=("main" "master" "kernel-4.14" "v2.2.0")

    local susfs_dir="" susfs_tmp="" clone_ok=0
    for repo in "${susfs_repos[@]}"; do
        [ "$clone_ok" = "1" ] && break
        for branch in "${susfs_branches[@]}"; do
            [ "$clone_ok" = "1" ] && break
            susfs_tmp=$(mktemp -d)
            rm -rf "${susfs_tmp}/susfs4ksu" 2>/dev/null
            info "  ${repo} (branch: ${branch})..."
            if GIT_TERMINAL_PROMPT=0 git clone --depth=1 --branch "${branch}" \
                "${repo}" "${susfs_tmp}/susfs4ksu" 2>/dev/null; then
                susfs_dir="${susfs_tmp}/susfs4ksu/kernel_patches"
                [ -d "$susfs_dir" ] || susfs_dir="${susfs_tmp}/susfs4ksu"
                clone_ok=1; info "  Cloned!"; break 2
            fi
            rm -rf "${susfs_tmp}" 2>/dev/null
        done
    done

    if [ "$clone_ok" = "1" ] && [ -n "$susfs_dir" ]; then
        info "SuSFS dir: ${susfs_dir}"
        # Copy new source files
        find "$susfs_dir" -type f \( -name '*.c' -o -name '*.h' \) -print0 2>/dev/null | \
            while IFS= read -r -d '' f; do
                local rel="${f#${susfs_dir}/}"
                mkdir -p "${kdir}/$(dirname "$rel")" 2>/dev/null
                cp -f "$f" "${kdir}/${rel}" 2>/dev/null
            done

        # Find patch
        local pf=""
        for candidate in \
            "${susfs_dir}/0001-suSFS-v2.2.0-for-4.14.patch" \
            "${susfs_dir}/0001-suSFS-v2.2.0.patch" \
            "${susfs_dir}/susfs-v2.2.0-for-4.14.patch" \
            "${susfs_dir}/susfs-v2.2.0.patch"; do
            [ -f "$candidate" ] && { pf="$candidate"; break; }
        done
        [ -z "$pf" ] && pf=$(ls -1 "$susfs_dir"/*susfs*.patch 2>/dev/null | head -1)

        if [ -n "$pf" ]; then
            info "Patch: $(basename "$pf")"
            local has_git=0
            [ -d "${kdir}/.git" ] && has_git=1
            # Try full patch
            if (cd "${kdir}" && patch -p1 --batch --fuzz=1 --forward \
                    --no-backup-if-mismatch -i "$pf" 2>/dev/null); then
                ok "SuSFS applied (p1)"
                SUSFS_OK=1; touch "${kdir}/.susfs_applied"
            else
                # patch(1) can partially apply a multi-hunk file before
                # failing overall; revert before falling back to per-file
                # chunks so each chunk starts from a clean base instead of
                # compounding on top of a half-applied file.
                if [ "$has_git" = "1" ]; then
                    git -C "${kdir}" checkout -- . 2>/dev/null
                    git -C "${kdir}" clean -fd --exclude=KernelSU-Next --exclude=drivers/kernelsu 2>/dev/null
                fi
                # Per-file split
                local st=$(mktemp -d)
                local applied=0
                csplit -f "${st}/p_" -z "$pf" '/^diff --git /' '{*}' 2>/dev/null || true
                for sp in "${st}"/p_*; do
                    [ -f "$sp" ] || continue
                    if (cd "${kdir}" && patch -p1 --batch --fuzz=1 --forward \
                        --no-backup-if-mismatch -i "$sp" 2>/dev/null); then
                        ((applied++))
                        if [ "$has_git" = "1" ]; then
                            git -C "${kdir}" add -A >/dev/null 2>&1
                            git -C "${kdir}" commit -q --no-verify -m "infinity-susfs-chunk" >/dev/null 2>&1
                        fi
                    elif [ "$has_git" = "1" ]; then
                        # Same partial-hunk risk per chunk - revert to the
                        # last checkpoint (prior successful chunks stay
                        # committed, only this failed chunk's mess is undone).
                        git -C "${kdir}" checkout -- . 2>/dev/null
                    fi
                    find "${kdir}" -name "*.rej" -delete 2>/dev/null
                    find "${kdir}" -name "*.orig" -delete 2>/dev/null
                done
                [ "$applied" -gt 0 ] && { ok "SuSFS partial (${applied} hunks)"; SUSFS_OK=1; touch "${kdir}/.susfs_applied"; }
                rm -rf "${st}"
            fi
        else
            warn "No SuSFS patch found"
        fi
    else
        warn "susfs4ksu clone failed — building without SuSFS"
    fi
    [ -n "$susfs_tmp" ] && rm -rf "$susfs_tmp" 2>/dev/null
    separator
}

# ════════════════════════════════════════════════════════════════════════════════════════════
#  Step 9: Compat Fixes
# ════════════════════════════════════════════════════════════════════════════════════════════

compat_fixes() {
    step "Step 9: Compat Fixes (GCC 15 + MHI)"
    local kdir="${WORK_DIR}"

    # GCC 15+ modpost: suppress section mismatch warnings
    if [ -f "${kdir}/.config" ]; then
        sed -i 's/^# CONFIG_SECTION_MISMATCH_WARN_ONLY is not set/CONFIG_SECTION_MISMATCH_WARN_ONLY=y/' "${kdir}/.config" 2>/dev/null || true
        grep -q '^CONFIG_SECTION_MISMATCH_WARN_ONLY=y' "${kdir}/.config" 2>/dev/null || \
            echo "CONFIG_SECTION_MISMATCH_WARN_ONLY=y" >> "${kdir}/.config" 2>/dev/null || true
    fi

    # v2.1.4 CRITICAL: Fix mhi_arch_qcom.c duplicate function definitions
    # The AnymoreProject kernel source has 10 mhi_arch_ functions defined TWICE.
    # GCC 15 treats this as error (not warning). Include guards in .c don't work.
    # Solution: wrap the duplicate block in #if 0.
    local mhi_file="${kdir}/drivers/bus/mhi/controllers/mhi_arch_qcom.c"
    if [ -f "${mhi_file}" ]; then
        # Count mhi_arch_ function definition lines
        local func_count
        func_count=$(grep -cE 'mhi_arch_[a-z_]+\s*\(' "$mhi_file" 2>/dev/null || echo 0)
        if [ "$func_count" -gt 10 ]; then
            info "Fixing mhi_arch_qcom.c ($func_count function defs, deduplicating)..."
            # Find line number of 11th occurrence (first duplicate)
            local redef_line
            redef_line=$(grep -nE 'mhi_arch_[a-z_]+\s*\(' "$mhi_file" | awk -F: 'NR==11{print $1}')
            if [ -n "$redef_line" ] && [ "$redef_line" -gt 1 ]; then
                local tmp_mhi=$(mktemp)
                {
                    head -n $((redef_line - 1)) "$mhi_file"
                    echo "#if 0 /* Infinity Kernel: removed duplicate mhi_arch_ function definitions */"
                    tail -n +"$redef_line" "$mhi_file"
                    echo "#endif"
                } > "$tmp_mhi"
                mv -f "$tmp_mhi" "$mhi_file"
                ok "mhi_arch_qcom.c: wrapped $(($func_count - 10)) duplicates in #if 0"
            else
                warn "mhi_arch_qcom.c: duplicates detected but could not find split point"
            fi
        fi
        # Fix MAX_MSG_SIZE if missing
        if grep -q 'MAX_MSG_SIZE' "$mhi_file" 2>/dev/null && \
           ! grep -qE '#define[[:space:]]+MAX_MSG_SIZE' "$mhi_file" 2>/dev/null; then
            info "Fixing mhi_arch_qcom.c (MAX_MSG_SIZE)..."
            sed -i '/#include/a #ifndef MAX_MSG_SIZE\n#define MAX_MSG_SIZE 4096\n#endif' "$mhi_file" 2>/dev/null || true
            ok "MAX_MSG_SIZE defined"
        fi
    fi

    ok "GCC 15+ + MHI compat applied"
    separator
}

# ════════════════════════════════════════════════════════════════════════════════════════════════════
#  Step 10: Build Kernel
# ════════════════════════════════════════════════════════════════════════════════════════════

build_kernel() {
    step "Step 10: Build Kernel"
    local kdir="${WORK_DIR}"

    local HOSTCFLAGS="-Wall -Wmissing-prototypes -Wstrict-prototypes -O2 -fomit-frame-pointer -std=gnu89"
    local KCFLAGS="-Wno-error -Wno-implicit-function-declaration -Wno-int-conversion \
-Wno-shadow -Wno-unused-function -Wno-format -Wno-array-bounds \
-Wno-address -Wno-builtin-declaration-mismatch -Wno-stringop-overflow \
-Wno-maybe-uninitialized -Wno-packed-not-aligned"

    info "Starting compilation..."
    echo ""
    local t0=$(date +%s)

    make -C "${kdir}" ARCH=${ARCH} \
        CC=${CROSS_COMPILE}gcc \
        CROSS_COMPILE=${CROSS_COMPILE} \
        CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
        AR=${CROSS_COMPILE}ar NM=${CROSS_COMPILE}nm \
        OBJCOPY=${CROSS_COMPILE}objcopy \
        OBJDUMP=${CROSS_COMPILE}objdump \
        STRIP=${CROSS_COMPILE}strip \
        HOSTCC=gcc HOSTCFLAGS="${HOSTCFLAGS}" \
        KCFLAGS="${KCFLAGS}" \
        -j"${JOBS}" Image.gz-dtb dtbs 2>&1

    local ret=$?
    local t1=$(date +%s)
    local elapsed=$((t1 - t0))

    echo ""
    info "Build time: $((elapsed / 60))m $((elapsed % 60))s (${elapsed}s)"

    if [ $ret -ne 0 ]; then
        err "Build FAILED (exit ${ret})"
        echo "=== First 30 errors ==="
        grep -iE 'error[: ]|fatal error' "${LOG_FILE}" | head -30
        die "Check: ${LOG_FILE}"
    fi

    [ -f "${kdir}/arch/${ARCH}/boot/Image.gz-dtb" ] && \
        ok "Build SUCCESS: $(du -h "${kdir}/arch/${ARCH}/boot/Image.gz-dtb" | cut -f1)"
    separator
}

# ════════════════════════════════════════════════════════════════════════════════════════════════════
#  Step 11: Package AnyKernel3 ZIP
# ══════════════════════════════════════════════════════════════════════════════════════════

package_zip() {
    step "Step 11: Package AnyKernel3 ZIP"
    local kdir="${WORK_DIR}"
    local zip_name="InfinityKernel-${VERSION}-vayu.zip"
    local staging="${OUT_DIR}/ak3_staging"

    rm -rf "${staging}"; mkdir -p "${staging}"

    # Copy AnyKernel3
    if [ -d "${ANYKERNEL_DIR}" ]; then
        (cd "${ANYKERNEL_DIR}" && find . -print0 2>/dev/null) | \
            while IFS= read -r -d '' src_item; do
                local rel="${src_item#${ANYKERNEL_DIR}/}"
                mkdir -p "$(dirname "${staging}/${rel}")"
                cp -f "${src_item}" "${staging}/${rel}" 2>/dev/null
            done
        ok "AnyKernel3 template copied"
    else
        warn "No AnyKernel3 dir — creating minimal"
        mkdir -p "${staging}/META-INF/com/google/android" "${staging}/modules"
    fi

    # Copy kernel image
    local boot="${kdir}/arch/${ARCH}/boot/Image.gz-dtb"
    [ -f "$boot" ] && cp -f "$boot" "${staging}/" && ok "Image.gz-dtb copied" || \
        die "Image.gz-dtb not found!"
    [ -f "${kdir}/arch/${ARCH}/boot/dtbo.img" ] && cp -f "${kdir}/arch/${ARCH}/boot/dtbo.img" "${staging}/" 2>/dev/null

    # Metadata
    cat > "${staging}/infinity_version.txt" << EOF
Infinity Kernel v${VERSION}
Device: Poco X3 Pro (vayu/bhima)
Base: ${KERNEL_REPO_URL} (branch: ${CLONE_BRANCH})
Kernel: ${KERNEL_VERSION_STRING:-unknown}
Root: ${ROOT_MODE} (${ROOT_LABEL})
SuSFS: ${SUSFS_OK}
Build: $(date)
GCC: $(aarch64-linux-gnu-gcc --version 2>/dev/null | head -1)
EOF
    ok "Metadata written"

    # Set permissions
    chmod +x "${staging}/anykernel.sh" 2>/dev/null
    chmod +x "${staging}/META-INF/com/google/android/update-binary" 2>/dev/null
    find "${staging}" -name "placeholder" -delete 2>/dev/null

    # Create ZIP
    mkdir -p "${OUT_DIR}"
    info "Creating ZIP..."
    (cd "${staging}" && zip -r -9 "${OUT_DIR}/${zip_name}" .) 2>&1
    [ $? -ne 0 ] && die "ZIP failed!"

    ok "ZIP: ${OUT_DIR}/${zip_name} ($(du -h "${OUT_DIR}/${zip_name}" | cut -f1))"

    # Checksums
    (cd "${OUT_DIR}" && md5sum "${zip_name}" > "${zip_name}.md5" 2>/dev/null) || true
    (cd "${OUT_DIR}" && sha256sum "${zip_name}" > "${zip_name}.sha256" 2>/dev/null) || true

    rm -rf "${staging}"
    separator
}

# ════════════════════════════════════════════════════════════════════════════════════════════════
#  Step 12: Cleanup
# ═══════════════════════════════════════════════════════════════════════════════════════════

cleanup() {
    step "Step 12: Cleanup"
    if [ "$BIND_MOUNT_USED" = "1" ]; then
        info "Unmounting bind mount..."
        sudo umount /tmp/infinity-kbuild 2>/dev/null || warn "umount failed"
        ok "Cleanup done"
    else
        info "No bind mount to clean"
    fi
    separator
}

# ════════════════════════════════════════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════════════════════════════════

main() {
    print_banner
    check_prerequisites
    detect_avx2
    clone_kernel_source
    repair_kernelsu_submodule
    setup_bind_mount
    apply_patches
    install_custom_files
    configure_kernel
    setup_root_solution
    apply_susfs
    compat_fixes
    build_kernel
    package_zip
    cleanup

    echo ""
    echo -e "${GRN}${BOLD}"
    echo "  ╔════════════════════════════════════════════════╗"
    echo "  ║                                                       ║"
    echo "  ║     Infinity Kernel v${VERSION} — BUILD COMPLETE!          ║"
    echo "  ║     Device: Poco X3 Pro (vayu/bhima)                   ║"
    echo "  ║     Root: ${ROOT_LABEL} (universal binary)               ║"
    echo "  ║                                                       ║"
    echo "  ║     ZIP: out/InfinityKernel-${VERSION}-vayu.zip          ║"
    echo "  ║                                                       ║"
    echo "  ╚═════════════════════════════════════════════════╝"
    echo -e "${NC}"
    info "Flashable: ${OUT_DIR}/InfinityKernel-${VERSION}-vayu.zip"
}

main "$@"
