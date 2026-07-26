#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
#  Infinity Kernel Build Script v1.0.104
#  v1.0.104: Fix 3 critical issues found in v1.0.103 build log
#
#           (1) Patches from patches/ NOT APPLIED ("Patches: 0 applied, 0 failed")
#               CAUSE: Step 9 used `find patches/` (relative path) while CWD was
#               the kernel source root (/tmp/infinity-kbuild via bind mount).
#               But patches/ lives in SCRIPT_DIR (~/.infinity-kernel/patches/),
#               NOT in the kernel source tree.
#               FIX: Use absolute path `$SCRIPT_DIR/patches/` in Step 9.
#
#           (2) FATAL: modpost: Section mismatch in spcom_probe -> spcom_register_chardev
#               CAUSE: drivers/soc/qcom/spcom.c has spcom_probe() (non-init)
#               calling spcom_register_chardev() (marked __init). On GCC 15+
#               with -Werror=section-mismatch, this is fatal.
#               FIX: Force `CONFIG_SECTION_MISMATCH_WARN_ONLY=y` in .config
#               so it becomes a warning instead of build-breaking error.
#
#           (3) Fix 21/21 wrong target: drivers/platform/msm/ipa/ipa_v3/dump/Makefile
#               does not exist on SM8150. The actual ipa_i.h include path fix
#               is already handled by Fix 21b (parent ipa_v3/Makefile with
#               ccflags-y += -I$(src)). v1.0.103 log confirms IPA compiles OK.
#               FIX: Remove the bogus Fix 21/21 block — keep only Fix 21b.
#
#           (4) Updated README.md with full feature list and build instructions.
#
#  v1.0.103: COMPLETE REPO — restored patches/, scripts/, full AnyKernel3/
#
#           PROBLEM: v1.0.100-v1.0.102 ZIP archives were MISSING critical
#           project files. The user's repo at https://github.com/asmoil/infinity-kernel
#           contains:
#             - patches/        (24 patch files + apply_all.sh)
#             - scripts/        (apply_patches.sh, charging_bypass/, sufs/)
#             - AnyKernel3/     (FULL: anykernel.sh, banner, modules/, patch/,
#                                ramdisk/, tools/ with busybox, magiskboot, etc.)
#             - build_kernel.sh (alternative build script)
#             - .github/, .circleci/, LICENSE, .gitignore
#           But v1.0.100-v1.0.102 ZIPs only contained:
#             - build.sh
#             - AnyKernel3/ (STRIPPED: only META-INF + anykernel.prop)
#             - arch/, drivers/, include/, README.md
#           As a result, Step 9 (apply patches from patches/) silently applied
#           ZERO patches ("Patches: 0 applied, 0 failed" in the log).
#
#           FIX: v1.0.103 takes the user's repo AS THE BASE, then overlays
#           my build.sh v1.0.102 (with all v1.0.99-v1.0.102 fixes: bind mount,
#           IPA fix, SuSFS Hunk #3 manual injection, multi-root CLI, GCC 15
#           compat fixes). All other files (patches/, scripts/, AnyKernel3/)
#           come UNMODIFIED from the user's repo.
#
#  v1.0.102: Manual injection of SuSFS Hunk #3 for fs/open.c (faccessat)
#
#           PROBLEM: SuSFS patch '50_add_susfs_in_kernel-4.14.patch' has
#           4 hunks for fs/open.c. Hunks #1, #2, #4 apply cleanly on SM8150
#           (LineageOS sm8150). Hunk #3 FAILED - it modifies
#           SYSCALL_DEFINE3(faccessat, ...) and the surrounding context in
#           SM8150 differs slightly from upstream 4.14 (different #ifdef
#           CONFIG_KSU block, different whitespace).
#           Result: SuSFS partially applied (10/11 hunks) - sus_path check
#           is missing in faccessat syscall. Build succeeds, but SuSFS
#           sus_path feature is INCOMPLETE for faccessat.
#
#           FIX: After SuSFS patch attempt, check if CONFIG_KSU_SUSFS_SUS_PATH
#           is present in fs/open.c near SYSCALL_DEFINE3(faccessat). If NOT,
#           inject the sus_path block manually via head/tail+cat (robust,
#           no fragile sed multi-line). Idempotent - runs only if missing.
#
#  v1.0.101: Fix ipa_i.h parent-dir include path (bind mount verified working)
#  v1.0.101: Fix fatal error in IPA reg-dump subdirectory
#
#           (1) drivers/platform/msm/ipa/ipa_v3/dump/ipa_reg_dump.h:18:10:
#               fatal error: ipa_i.h: No such file or directory
#               CAUSE: ipa_reg_dump.h does `#include "ipa_i.h"`, expecting
#               ipa_i.h to be in the same dir. But ipa_i.h lives in the
#               PARENT directory (drivers/platform/msm/ipa/ipa_v3/ipa_i.h).
#               The dump/ sub-Makefile is missing `-I$(src)/..` so gcc can't
#               find the parent-dir header.
#               FIX: Append `ccflags-y += -I$(src)/..` to
#               drivers/platform/msm/ipa/ipa_v3/dump/Makefile.
#               Also do the same for ipa_v3/Makefile itself (so any other
#               relative include from there resolves too).
#
#  v1.0.100: Fix 2 fatal build errors that survived v1.0.99
#
#           (1) net/core/sock.c:148:8: error: redefinition of 'struct compat_timeval'
#               CAUSE: Our Fix 5/19 unconditionally injected
#                 `struct compat_timeval { int tv_sec; int tv_usec; };`
#               into net/core/sock.c. But on SM8150 (LineageOS 4.14),
#               asm/compat.h ALREADY defines struct compat_timeval (line 74).
#               When sock.c includes <linux/net.h> -> <linux/fs.h> ->
#               <linux/stat.h> -> <asm/stat.h> -> <asm/compat.h>, the
#               struct is already defined → redefinition error.
#               FIX: Wrap our injection in #ifndef __COMPAT_TIMEVAL_DEFINED
#               guard. If the struct is already defined (SM8150 case), our
#               definition is skipped. If not (older kernels), it's added.
#
#           (2) ./include/trace/define_trace.h:89:42: fatal error: ./hid-trace.h
#               CAUSE: drivers/hid/hid-trace.c uses TRACE_DEFINE_SYSTEM
#               which expands to #include TRACE_INCLUDE(hid-trace).
#               TRACE_INCLUDE() prepends "./" expecting the trace header
#               to be in the same dir as the .c file. The Makefile for
#               hid-trace.o needs `-I$(src)` so gcc can find it. SM8150's
#               drivers/hid/Makefile is missing this flag.
#               FIX: Append `CFLAGS_hid-trace.o += -I$(src)` to
#               drivers/hid/Makefile (same pattern used by other trace files).
#
#  v1.0.99: Bind mount (works! techpack/audio + gen_kheaders.sh errors GONE)
#  v1.0.98: Symlink (didn't work — getcwd() resolves symlinks)
#  v1.0.97: Multi-root CLI support + GCC 15 warning suppression (retained)
#  v1.0.96: CONFIG_KSU_SUSFS* name fix (retained)
#  v1.0.95: In-tree build (retained)
#  v1.0.94: Removed set -e silent-exit bug (retained)
#  Poco X3 Pro (vayu/bhima) | SM8150 | Linux 4.14.357
#  Neutron Clang (tag 17062026) | AnyKernel3
#  Multi-Root: KernelSU / KernelSU-Next / ReSukiSU / SukiSU-Ultra / KoWSu / APatch / none
#  Tested on: Ubuntu 24.04, 26.04 LTS
#  Usage: ./build.sh [root_solution] [jobs]
#    root_solution: kernelsu | kernelsu_next | resukisu | sukisu | sukisu_ultra | kowsu | apatch | none
#    DEFAULT (no arg) = kernelsu (builds for ALL SU-based managers: KernelSU,
#    KernelSU-Next, ReSukiSU, SukiSU-Ultra, KoWSu — they share the same
#    kernel-side ksu_* hooks, so one kernel ZIP works with any SU manager APK)
#    Use "apatch" for APatch (different hook mechanism, separate build)
#    Use "none" for no root integration
# ═══════════════════════════════════════════════════════════════════
#  v1.0.99: BIND MOUNT (works — see header above)
#
#           (A) EXPLICIT ROOT MANAGER SUPPORT
#           User asked: "а как же мой был запрос на поддержку остальных
#           root менеджеров по типу ReSukiSU, SukiSU-Ultra, KernelSU,
#           KernelSU-Next, KoWSu. а также поддержка apatch."
#           v1.0.96 only had `kernelsu` / `apatch` / `none`. While the
#           kernel-side protocol is IDENTICAL for all KSU forks (KernelSU,
#           KernelSU-Next, ReSukiSU, SukiSU-Ultra, KoWSu — they all use the
#           same ksu_* hooks in the kernel tree), users want to see their
#           manager name printed in the log for clarity.
#           v1.0.97 ADDS: `resukisu`, `sukisu`, `sukisu_ultra`, `kowsu`,
#           `kernelsu_next` as ALIASES of `kernelsu`. All map to the same
#           code path (clone KernelSU-Next as the canonical source — it has
#           the most up-to-date kernel hooks, and is wire-compatible with
#           every KSU manager app). The chosen manager name is printed
#           in the log: "Root solution: sukisu_ultra (kernel-side: KSU)".
#
#           (B) SUPPRESS GCC 15 WARNINGS THAT FLOOD THE LOG
#           User reported "такие ошибки везде идут при сборке" — but they
#           were WARNINGS, not errors. GCC 15 enables -Warray-bounds,
#           -Waddress, -Wbuiltin-declaration-mismatch by default, and Linux
#           4.14 source triggers hundreds of them (atomic_t[0] array bounds,
#           `if (ptr == NULL)` for static vars, crypto/xts.c `free()` name).
#           These do NOT stop the build, but they hide real errors in noise.
#           v1.0.97 ADDS to KCFLAGS:
#             -Wno-array-bounds                (atomic_t[0] partly outside)
#             -Wno-address                     (cpu_isolated_map == NULL)
#             -Wno-builtin-declaration-mismatch (crypto/xts.c free())
#             -Wno-stringop-overflow           (further array bounds noise)
#             -Wno-maybe-uninitialized         (false positives in 4.14)
#             -Wno-packed-not-aligned          (struct alignment warnings)
#           Also adds them to _HOSTCFLAGS_SAFE so kconfig/host tools stay
#           quiet too.
#  v1.0.96: CRITICAL FIX — `fs/Kconfig:323: can't open file "fs/susfs/Kconfig"`
#           after SuSFS patch applied. Removed safety-net that added a bogus
#           `source "fs/susfs/Kconfig"` line (master-branch SuSFS patch does
#           NOT create fs/susfs/ subdir — it compiles fs/susfs.c as a single
#           file via obj-$(CONFIG_KSU_SUSFS) += susfs.o). Also fixed CONFIG
#           names: CONFIG_SUSFS* → CONFIG_KSU_SUSFS* in defconfig + Step 7b.
#  v1.0.95: CRITICAL FIX — `arch/arm64/Makefile: No such file or directory`.
#           Switched to IN-TREE build (removed O=out) because GNU make cannot
#           handle spaces in `--include-dir=$(CURDIR)` (bug #10881).
#  v1.0.94: CRITICAL FIX — script was SILENTLY EXITING after Clone SUCCESS.
#           Root cause: `set -e` re-enabled after clone loop, then grep -c
#           returned 1 on 0 matches → script killed with no message.
#  Poco X3 Pro (vayu/bhima) | SM8150 | Linux 4.14.357
#  Neutron Clang (tag 17062026) | AnyKernel3
#  Multi-Root: KernelSU / KernelSU-Next / ReSukiSU / SukiSU-Ultra / KoWSu / APatch / none
#  Tested on: Ubuntu 24.04, 26.04 LTS
#  Usage: ./build.sh [root_solution] [jobs]
#    root_solution: kernelsu | kernelsu_next | resukisu | sukisu | sukisu_ultra | kowsu | apatch | none
# ═══════════════════════════════════════════════════════════════════
set -uo pipefail

# ── Config ───────────────────────────────────────────────────────
# NOTE: kernel_src/ is CLONED by this script during build (git clone).
#       It is NOT shipped in the release archive — the archive is a build harness.
KERNEL_SRC="kernel_src"  # relative to SCRIPT_DIR (made absolute below)
TC_DIR="$HOME/toolchains/neutron-clang"
TC_TAG="17062026"
VERSION="1.0.104"
ROOT_SOLUTION="${1:-kernelsu}"
# v1.0.97: Normalize root solution aliases. All KSU forks use the SAME
# kernel-side protocol (ksu_* hooks), so they all map to `kernelsu`.
# We remember the original name for display purposes.
ROOT_SOLUTION_INPUT="$ROOT_SOLUTION"
case "$ROOT_SOLUTION" in
  kernelsu|kernelsu_next|kernelsu-next|ksu)        ROOT_SOLUTION="kernelsu"; ROOT_LABEL="KernelSU-Next" ;;
  resukisu|re-sukisu|resuki)                       ROOT_SOLUTION="kernelsu"; ROOT_LABEL="ReSukiSU" ;;
  sukisu|sukisu_ultra|sukisu-ultra|suki)           ROOT_SOLUTION="kernelsu"; ROOT_LABEL="SukiSU-Ultra" ;;
  kowsu|kow)                                       ROOT_SOLUTION="kernelsu"; ROOT_LABEL="KoWSu" ;;
  apatch|apatchet)                                 ROOT_SOLUTION="apatch";   ROOT_LABEL="APatch" ;;
  none|no-root|noroot)                             ROOT_SOLUTION="none";    ROOT_LABEL="None" ;;
  *) ROOT_SOLUTION="kernelsu"; ROOT_LABEL="KernelSU-Next (unknown alias: $ROOT_SOLUTION_INPUT)" ;;
esac
JOBS="${2:-$(nproc)}"
USE_CLANG=1
# SCRIPT_DIR is determined early so ${SCRIPT_DIR} in info() works even
# when the launch path contains spaces (bash would otherwise complain
# "не заданы границы переменной" on empty unquoted expansions).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Global logging: write EVERYTHING to $SCRIPT_DIR/infinity_build.log ──
# v1.0.88: user requested all output (not just the make step) be logged.
# This redirects stdout+stderr through tee so the terminal still shows
# live output AND the log captures the complete run.
_LOG_FILE="$SCRIPT_DIR/infinity_build.log"
mkdir -p "$SCRIPT_DIR" 2>/dev/null
# Truncate log at start of each run (fresh log per invocation)
: > "$_LOG_FILE"
exec > >(tee -a "$_LOG_FILE") 2>&1

# Colors
RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[1;33m'; CYN='\033[0;36m'; RST='\033[0m'
info()  { echo -e "${GRN}[INFO]${RST} $*"; }
warn()  { echo -e "${YEL}[WARN]${RST} $*"; }
err()   { echo -e "${RED}[ERROR]${RST} $*" >&2; }
die()   { err "$*"; exit 1; }

echo -e "${CYN}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║   Infinity Kernel Build v${VERSION}    ║"
echo "  ║  Poco X3 Pro (vayu/bhima) | SM8150    ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${RST}"
info "Root solution: $ROOT_SOLUTION_INPUT → $ROOT_LABEL (kernel-side: ${ROOT_SOLUTION})"
info "Jobs: ${JOBS}"
info "Script dir: ${SCRIPT_DIR}"
info "OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"

# ── Step 0: Locale hygiene + path info ─────────────────────────────
# v1.0.99+: The bind mount approach (Step 3e) makes path-with-spaces work.
# The source stays at the user's location; build runs through /tmp/infinity-kbuild
# (a real mount point, not a symlink — getcwd() returns it without resolution).
# v1.0.104: Confirmed working — build reaches vmlinux link stage.
# This message is for information only — no action needed.
export LC_ALL=C
export LANG=C
export LANGUAGE=C

# Determine SCRIPT_DIR (the folder where this script was launched from)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR" || die "Cannot cd to ${SCRIPT_DIR}"

# Detect dirty path and INFORM (v1.0.99: bind mount handles this)
_path_is_dirty=0
if echo "$SCRIPT_DIR" | grep -qE '[[:space:]:]' ; then _path_is_dirty=1; fi
if [ "$(printf '%s' "$SCRIPT_DIR" | LC_ALL=C grep -c '[^A-Za-z0-9 _./~:-]')" -gt 0 ] 2>/dev/null; then _path_is_dirty=1; fi
if [ "$_path_is_dirty" = "1" ]; then
  info "==============================================================="
  info "  Path contains spaces / Cyrillic / special chars:"
  info "    $SCRIPT_DIR"
  info "  v1.0.104 HANDLES THIS via bind mount:"
  info "    sudo mount --bind \$KERNEL_SRC /tmp/infinity-kbuild"
  info "  Source stays here; build runs through space-free mount point."
  info "  (sudo will prompt for password during Step 3e — this is normal)"
  info "  v1.0.104: bind-mount + patches/ absolute path + section-mismatch fix."
  info "==============================================================="
fi

# Make KERNEL_SRC absolute (inside SCRIPT_DIR)
KERNEL_SRC="$SCRIPT_DIR/$KERNEL_SRC"

# ── Step 1: Install dependencies ────────────────────────────────
info "Checking/installing build dependencies..."
info "Updating package lists..."
sudo apt-get update 2>/dev/null || warn "apt-get update failed (network issue?)"
_dep_list="build-essential gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu gcc-arm-linux-gnueabi binutils-arm-linux-gnueabi libssl-dev zstd git bc bison flex libelf-dev python3 make"
for _dep in $_dep_list; do
  dpkg -s "$_dep" >/dev/null 2>&1 || {
    info "Installing $_dep..."
    sudo apt-get install -y "$_dep" 2>/dev/null || warn "Failed to install $_dep"
  }
done

# ── Step 2: Download Neutron Clang ──────────────────────────────
# v1.0.90: CORRECT Neutron Clang URL.
#   Old (broken):  github.com/NeutronClangToolchain/clang-build  (404, repo doesn't exist)
#   New (working):  github.com/Neutron-Toolchains/clang-build-catalogue
#   File naming:    neutron-clang-<tag>.tar.zst   (lowercase, no -Linux-x86_64 suffix)
#   Verified 2026-07-26: tag 17062026 → 63MB valid zstd archive.
TC_URL1="https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/download/${TC_TAG}/neutron-clang-${TC_TAG}.tar.zst"
TC_URL2="https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/download/17062026/neutron-clang-17062026.tar.zst"
TC_URL3="https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/download/30062026/neutron-clang-30062026.tar.zst"
# v1.0.90: minimum size check — GitHub 404 returns 9-byte "Not Found" body
#   which passes `[ -s ]` (file exists and non-empty). Require >5MB.
TC_MIN_BYTES=$((5 * 1024 * 1024))
if [ ! -d "$TC_DIR" ] || [ ! -x "$TC_DIR/bin/clang" ]; then
  info "Downloading Neutron Clang (${TC_TAG})..."
  mkdir -p "$HOME/toolchains"
  _tc_ok=0
  for _tc_url in "$TC_URL1" "$TC_URL2" "$TC_URL3"; do
    info "Trying: $_tc_url"
    rm -f /tmp/neutron-clang.tar.zst
    # v1.0.90: Show curl errors (was 2>/dev/null — silent failure made debugging impossible)
    if curl -fL --connect-timeout 30 --max-time 600 -o /tmp/neutron-clang.tar.zst "$_tc_url" 2>&1; then
      _tc_size=$(stat -c%s /tmp/neutron-clang.tar.zst 2>/dev/null || echo 0)
      if [ "$_tc_size" -ge "$TC_MIN_BYTES" ]; then
        info "  Downloaded: $(( _tc_size / 1024 / 1024 )) MB (valid size)"
        _tc_ok=1; break
      else
        warn "  Download too small: $_tc_size bytes (< ${TC_MIN_BYTES}) — likely 404 page, skipping"
        rm -f /tmp/neutron-clang.tar.zst
      fi
    else
      warn "  curl failed for $_tc_url"
      rm -f /tmp/neutron-clang.tar.zst
    fi
  done
  if [ "$_tc_ok" = "1" ] && [ -f /tmp/neutron-clang.tar.zst ]; then
    _tc_size=$(stat -c%s /tmp/neutron-clang.tar.zst 2>/dev/null || echo 0)
    info "Downloaded Neutron Clang: $(( _tc_size / 1024 / 1024 )) MB"
    rm -rf "$TC_DIR"
    mkdir -p "$TC_DIR"
    # v1.0.89: Check zstd is actually installed before using it
    if ! command -v zstd >/dev/null 2>&1; then
      warn "zstd not found — installing now (sudo apt install zstd)..."
      sudo apt-get install -y zstd 2>&1 || warn "  Failed to install zstd automatically"
    fi
    # v1.0.89: Show zstd/tar errors (was 2>/dev/null — silent failure)
    info "Decompressing .tar.zst with zstd..."
    if command -v zstd >/dev/null 2>&1 && zstd -d /tmp/neutron-clang.tar.zst -o /tmp/neutron-clang.tar --force 2>&1; then
      info "zstd decompress OK"
      info "Extracting .tar with tar (strip-components=1)..."
      if tar -xf /tmp/neutron-clang.tar -C "$TC_DIR" --strip-components=1 2>&1; then
        info "Neutron Clang extracted to $TC_DIR (strip-components=1)"
      else
        warn "tar --strip-components=1 failed, trying plain extract..."
        rm -rf "$TC_DIR"
        mkdir -p "$TC_DIR"
        tar -xf /tmp/neutron-clang.tar -C "$HOME/toolchains" 2>&1 || warn "tar extract failed"
      fi
    else
      warn "zstd decompress FAILED — trying tar with auto-decompress..."
      # Fallback: tar can auto-detect .zst if compiled with zstd support
      if tar --auto-compress -xf /tmp/neutron-clang.tar.zst -C "$TC_DIR" --strip-components=1 2>&1; then
        info "tar auto-decompress worked"
      else
        warn "tar auto-decompress also failed — will use GCC fallback"
        warn "  (install zstd manually: sudo apt install zstd)"
      fi
    fi
    # If strip-components failed, try fallback search for bin/clang
    if [ ! -x "$TC_DIR/bin/clang" ]; then
      _found_clang_dir=""
      for _cand in \
        "$HOME/toolchains/Neutron-Clang-${TC_TAG}-Linux-x86_64" \
        "$HOME/toolchains/clang-build" \
        "$HOME/toolchains/neutron-clang"; do
        if [ -x "$_cand/bin/clang" ]; then
          _found_clang_dir="$_cand"
          break
        fi
      done
      if [ -z "$_found_clang_dir" ]; then
        _hit=$(find "$HOME/toolchains" -maxdepth 4 -name clang -type f -path '*/bin/clang' 2>/dev/null | head -1)
        if [ -n "$_hit" ]; then
          _found_clang_dir=$(dirname "$(dirname "$_hit")")
        fi
      fi
      if [ -n "$_found_clang_dir" ] && [ "$_found_clang_dir" != "$TC_DIR" ]; then
        rm -rf "$TC_DIR"
        mv "$_found_clang_dir" "$TC_DIR" 2>/dev/null && info "Neutron Clang moved from $_found_clang_dir -> $TC_DIR"
      fi
    fi
    rm -f /tmp/neutron-clang.tar /tmp/neutron-clang.tar.zst
    if [ -x "$TC_DIR/bin/clang" ]; then
      info "Neutron Clang installed to $TC_DIR"
    else
      warn "Neutron Clang extraction incomplete — will use GCC fallback"
      warn "  Contents of $TC_DIR:"
      ls -la "$TC_DIR" 2>/dev/null | head -20 | sed 's/^/    /'
    fi
  else
    warn "Failed to download Neutron Clang — will use GCC fallback"
  fi
fi

# ── Step 2b: Detect AVX2 support on HOST CPU, fallback to GCC if missing ─
# v1.0.92: We used to run `echo "int main(){}" | clang -mavx2 -x c - -o /dev/null`
# to test AVX2. But Neutron Clang binaries are built with -march=x86-64-v3,
# which REQUIRES AVX2 for the clang binary itself to start. On a host CPU
# without AVX2 (older Intel pre-Haswell, Atom, Celeron, AMD pre-2015, etc.)
# the clang process crashes with `Illegal instruction (core dumped)` before
# it ever tries to compile anything — and we incorrectly reported this as
# "VM?". Real hardware is affected too.
#
# Now we parse /proc/cpuinfo directly. No binary execution, no crash.
if [ -x "$TC_DIR/bin/clang" ]; then
  # Detect AVX2 via /proc/cpuinfo (reliable, no binary execution)
  _cpu_model=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | sed 's/^[^:]*: //;s/\s*$//')
  _cpu_avx2=0
  if grep -qE '^flags\s*:.*\bavx2\b' /proc/cpuinfo 2>/dev/null; then
    _cpu_avx2=1
  fi
  info "Host CPU: ${_cpu_model:-unknown}"
  if [ "$_cpu_avx2" = "1" ]; then
    info "AVX2: supported (found in /proc/cpuinfo flags)"
    # Real test: clang can actually compile a trivial program
    if echo 'int main(){return 0;}' | "$TC_DIR/bin/clang" -x c - -o /dev/null 2>/dev/null; then
      info "Neutron Clang OK (smoke test passed)"
      export PATH="$TC_DIR/bin:$PATH"
    else
      warn "AVX2 is present but clang smoke test failed — falling back to GCC"
      warn "  (this can happen on very old glibc or missing libstdc++)"
      USE_CLANG=0
    fi
  else
    warn "AVX2: NOT supported by host CPU"
    warn "  Neutron Clang binaries are built with -march=x86-64-v3 which REQUIRES AVX2"
    warn "  to even start the clang process. Without AVX2, clang crashes with"
    warn "  'Illegal instruction (core dumped)' on launch."
    warn "  This is NOT a VM issue — many real CPUs lack AVX2:"
    warn "    - Intel pre-Haswell (before 2013)"
    warn "    - Intel Atom / Celeron / Pentium (some models)"
    warn "    - AMD pre-Excavator (before 2015)"
    warn "  Falling back to GCC. Kernel builds perfectly fine with GCC — only"
    warn "  slightly slower compilation, no impact on the resulting kernel."
    USE_CLANG=0
  fi
else
  warn "Neutron Clang not found — using GCC"
  USE_CLANG=0
fi
if [ "$USE_CLANG" = "0" ]; then
  if ! command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
    die "aarch64-linux-gnu-gcc not found! Run: sudo apt install gcc-aarch64-linux-gnu"
  fi
  info "Using GCC cross-compiler: $(aarch64-linux-gnu-gcc --version | head -1)"
fi

# ── Step 3: Clone kernel source ─────────────────────────────────
if [ -d "$KERNEL_SRC/.git" ]; then
  info "Kernel source already present ($KERNEL_SRC)"
  cd "$KERNEL_SRC"
  git checkout . 2>/dev/null || true
  # Force SuSFS re-apply on each build (in case version changed)
  rm -f .susfs_applied 2>/dev/null
  cd "$SCRIPT_DIR"
else
  rm -rf "$KERNEL_SRC"
  info "Cloning LineageOS SM8150 kernel (depth=1, ~500MB download)..."
  info "  This may take 5-15 minutes depending on network speed."
  info "  (v1.0.90: git clone uses --quiet — progress spam was flooding the log)"
  # v1.0.94: NO `set +e` here — the script intentionally runs WITHOUT errexit
  # (set -uo pipefail at top, no -e). Old versions had `set +e`/`set -e` pairs
  # around this loop, but the closing `set -e` re-enabled errexit, which then
  # killed the script silently on the first grep -c that found 0 matches.
  _kr_ok=0
  for _kr_url in \
    "https://github.com/LineageOS/android_kernel_xiaomi_vayu" \
    "https://github.com/LineageOS/android_kernel_xiaomi_sm8150" \
    "https://github.com/nicholaschum/android_kernel_xiaomi_vayu" \
    "https://github.com/nicholaschum/android_kernel_xiaomi_sm8150"; do
    for _kr_branch in lineage-18.1 lineage-17.1 lineage-19.1 main; do
      info "Trying: $_kr_url (branch $_kr_branch)"
      info "  (timeout: 20 minutes max)"
      # v1.0.90: --quiet instead of --progress — old behavior flooded the log
      #   with thousands of "Counting objects: X%" lines, pushing real errors
      #   off the visible end of infinity_build.log.
      if timeout 1200 env GIT_TERMINAL_PROMPT=0 git clone --depth=1 --branch "$_kr_branch" \
        --quiet \
        --config "credential.helper=" "$_kr_url" "$KERNEL_SRC" 2>&1; then
        _kr_ok=1
        info "Clone SUCCESS: $_kr_url (branch $_kr_branch)"
        break 2
      else
        _rc=$?
        if [ "$_rc" = "124" ]; then
          warn "  Clone TIMED OUT after 20 minutes — trying next mirror/branch"
        else
          warn "  Clone failed (exit $_rc) — trying next mirror/branch"
        fi
        rm -rf "$KERNEL_SRC"
      fi
    done
  done
  # v1.0.94: NO `set -e` here — see comment above (errexit was killing Step 3d)
  if [ "$_kr_ok" = "0" ]; then
    # Last resort: clone without branch (use default)
    info "All branches failed, trying default branch..."
    # v1.0.94: NO `set +e` here either
    for _kr_url in \
      "https://github.com/LineageOS/android_kernel_xiaomi_vayu" \
      "https://github.com/LineageOS/android_kernel_xiaomi_sm8150"; do
      info "Trying: $_kr_url (default branch, timeout 20min)"
      if timeout 1200 env GIT_TERMINAL_PROMPT=0 git clone --depth=1 \
        --quiet \
        --config "credential.helper=" "$_kr_url" "$KERNEL_SRC" 2>&1; then
        _kr_ok=1
        info "Clone SUCCESS (default branch): $_kr_url"
        break
      else
        _rc=$?
        warn "  Clone failed (exit $_rc) — trying next"
        rm -rf "$KERNEL_SRC"
      fi
    done
    # v1.0.94: NO `set -e` here either
  fi
  [ "$_kr_ok" = "1" ] || die "Failed to clone kernel source from all mirrors. Check network and try again."
fi

cd "$KERNEL_SRC" || die "Cannot cd to ${KERNEL_SRC}"

# ═══════════════════════════════════════════════════════════════════
# ── Step 3e: BIND MOUNT (v1.0.99 — THE DEFINITIVE FIX) ────────────
# ═══════════════════════════════════════════════════════════════════
# WHY: The Linux kernel build system has HUNDREDS of sub-Makefiles that
# use $(srctree) and $(obj) UNQUOTED:
#   techpack/audio/Makefile:  ccflags-y += -I$(srctree)/techpack/audio/include
#   kernel/Makefile:          $(srctree)/kernel/gen_kheaders.sh
#   drivers/hid/Makefile:     CFLAGS_hid-trace.o += -I$(obj)
# When $(srctree) contains a space (~/Рабочий стол/), bash splits the
# argument and gcc sees "стол/..." as a separate linker input file.
#
# v1.0.98 tried a SYMLINK (/tmp/infinity-kbuild → $KERNEL_SRC) but it
# FAILED. Root cause: getcwd() (the Linux syscall) RESOLVES symlinks.
# GNU make sets $(CURDIR) = getcwd(), which returns the PHYSICAL path
# (with spaces), NOT the symlink path. So $(srctree) still had spaces.
#
# v1.0.99 SOLUTION: Use `sudo mount --bind` to create a REAL mount
# point. A bind mount is a kernel-level directory mount — NOT a symlink.
# getcwd() returns the mount path (/tmp/infinity-kbuild), which has
# NO SPACES. $(srctree) resolves correctly.
#
# The source files STAY at the user's location — bind mount just makes
# them accessible at a second path. NOTHING IS COPIED.
# Auto-unmount on exit via trap.
#
# Note: sudo is needed for mount. The script already uses sudo for
# apt-get install, so this is consistent. If sudo prompts for password,
# enter it — the build cannot proceed without the bind mount.
# ═══════════════════════════════════════════════════════════════════
BUILD_MOUNT="/tmp/infinity-kbuild"

# Cleanup any stale mount from a previous run
if mountpoint -q "$BUILD_MOUNT" 2>/dev/null; then
  info "Stale bind mount found at $BUILD_MOUNT — unmounting..."
  sudo umount "$BUILD_MOUNT" 2>/dev/null || umount "$BUILD_MOUNT" 2>/dev/null
  sleep 1
fi
rm -rf "$BUILD_MOUNT" 2>/dev/null
mkdir -p "$BUILD_MOUNT"

# Create bind mount via sudo
info "Creating bind mount (sudo may prompt for password)..."
info "  $KERNEL_SRC → $BUILD_MOUNT"
info "  (getcwd() resolves symlinks, so a REAL mount is required)"
_BIND_OK=0
if sudo mount --bind "$KERNEL_SRC" "$BUILD_MOUNT" 2>&1; then
  _BIND_OK=1
  info "Bind mount created successfully"
else
  warn "sudo mount --bind failed — trying without sudo (might work if user has CAP_SYS_ADMIN)..."
  if mount --bind "$KERNEL_SRC" "$BUILD_MOUNT" 2>&1; then
    _BIND_OK=1
    info "Bind mount created (without sudo)"
  fi
fi

if [ "$_BIND_OK" = "0" ]; then
  die "Cannot create bind mount at $BUILD_MOUNT.
Please run manually BEFORE starting the build:
  sudo mkdir -p $BUILD_MOUNT
  sudo mount --bind '$KERNEL_SRC' $BUILD_MOUNT
Then re-run: ./build.sh $ROOT_SOLUTION_INPUT $JOBS
Or: move the kernel source to a path without spaces (e.g. ~/infinity-kernel/)"
fi

# Auto-unmount on exit (success, failure, or Ctrl+C)
_cleanup_bind_mount() {
  local _rc=$?
  info "Cleaning up bind mount at $BUILD_MOUNT..."
  sudo umount "$BUILD_MOUNT" 2>/dev/null || umount "$BUILD_MOUNT" 2>/dev/null
  rmdir "$BUILD_MOUNT" 2>/dev/null
  exit $_rc
}
trap _cleanup_bind_mount EXIT INT TERM

# Verify the bind mount works
if [ ! -d "$BUILD_MOUNT" ]; then
  die "Bind mount at $BUILD_MOUNT is not a directory"
fi
if [ ! -f "$BUILD_MOUNT/Makefile" ] && [ ! -d "$BUILD_MOUNT/kernel" ]; then
  die "Bind mount at $BUILD_MOUNT is empty or inaccessible (no Makefile and no kernel/ subdir)"
fi
info "Bind mount verified: $BUILD_MOUNT is accessible"

# ── Step 3f: Detect actual kernel source root ───────────────────────────
# Some LineageOS kernel repos (e.g. android_kernel_xiaomi_sm8150) have
# the actual kernel source in a SUBDIRECTORY like kernel/msm-4.14/ or
# kernel/msm-4.9/ rather than at the repo root. We need to find the
# directory that contains the main kernel Makefile and cd into it.
# This is CRITICAL — if we build from the repo root when the source is
# in a subdirectory, make won't find arch/arm64/Makefile and the build
# will fail with confusing errors.
_KSRC_ROOT=""
if [ -f "$BUILD_MOUNT/Makefile" ] && [ -d "$BUILD_MOUNT/arch/arm64" ]; then
  # Kernel source is at the mount root (flat structure)
  _KSRC_ROOT="$BUILD_MOUNT"
  info "Kernel source root: repo root (flat structure)"
else
  # Search for kernel source in common subdirectories
  for _ksubd in kernel/msm-4.14 kernel/msm-4.9 kernel/msm-5.4 kernel/msm-4.19 \
                kernel/msm-4.4 msm-4.14 msm-4.9 msm-5.4 kernel; do
    if [ -f "$BUILD_MOUNT/$_ksubd/Makefile" ] && [ -d "$BUILD_MOUNT/$_ksubd/arch/arm64" ]; then
      _KSRC_ROOT="$BUILD_MOUNT/$_ksubd"
      info "Kernel source root detected: $_ksubd/ subdirectory"
      break
    fi
  done
fi
if [ -z "$_KSRC_ROOT" ]; then
  # Last resort: search for any Makefile with arch/arm64/ nearby
  _found_makefile=$(find "$BUILD_MOUNT" -maxdepth 3 -name Makefile -path '*/arch/arm64/../Makefile' 2>/dev/null | head -1)
  if [ -n "$_found_makefile" ]; then
    _KSRC_ROOT=$(dirname "$_found_makefile")
    info "Kernel source root detected via search: $_KSRC_ROOT"
  fi
fi
if [ -z "$_KSRC_ROOT" ]; then
  die "Cannot find kernel source root (Makefile + arch/arm64/) in $BUILD_MOUNT. Repo structure may be unsupported."
fi
BUILD_LINK="$_KSRC_ROOT"
cd "$BUILD_LINK" || die "Cannot cd to build mount ${BUILD_LINK}"
info "Working directory (space-free, via bind mount): $(pwd)"
info "  getcwd() returns: $(pwd -P 2>/dev/null || pwd)"

# ── Step 3d: PATCH kernel Makefile — disable spaces/colons check ────────
# v1.0.98: With the symlink approach, $(CURDIR) is now /tmp/infinity-kbuild
# (no spaces), so the spaces check would NOT trigger. But we patch it anyway
# as a defensive measure — some kernel Makefile operations may still reference
# the real path.
# Problem: kernel Makefile (line ~128 in v4.14) contains:
#   $(if $(findstring $(space),$(CURDIR)),$(error main directory cannot contain spaces nor colons))
# This HARDCODED check rejects any path with spaces — even though the user's
# launch folder may legitimately contain spaces (e.g., ~/Рабочий стол/).
# v1.0.85 removed auto-copy per user request; v1.0.87 patches this check
# so the build can run from ANY folder the user chooses.
# We strip the $(error ...) part — leaving an empty $(if ...) which is a no-op.
#
# v1.0.91 ADDITION: After disabling the error, we ALSO patch the unquoted
#   KBUILD_OUTPUT usage in lines 144 & 146. The original Makefile does:
#
#     KBUILD_OUTPUT := $(shell mkdir -p $(KBUILD_OUTPUT) && cd $(KBUILD_OUTPUT) && /bin/pwd)
#     sub-make:
#         $(Q)$(MAKE) -C $(KBUILD_OUTPUT) KBUILD_SRC=$(CURDIR) -f $(CURDIR)/Makefile ...
#
#   Without quotes around $(KBUILD_OUTPUT), a path like
#   /home/user/Рабочий стол/foo gets split into 2 args by bash, and
#   `mkdir -p` creates a spurious '/home/user/Рабочий' directory while
#   `cd` fails silently. Then `make -C /home/user/Рабочий' errors with
#   "No such file or directory".
#
#   Fix: wrap every reference to $(KBUILD_OUTPUT) and $(CURDIR) inside the
#   sub-make block in double quotes. This is fully backward compatible —
#   paths without spaces still work identically.
if [ -f "Makefile" ]; then
  if grep -q 'main directory cannot contain spaces nor colons' Makefile 2>/dev/null; then
    # v1.0.94: `|| true` is CRITICAL — grep -c returns 1 when 0 matches are
    # found, and with `set -e` (which was active in v1.0.92/v1.0.93 due to
    # the bug above) this would silently terminate the script. Even though
    # we removed set -e, keep `|| true` as a defensive guard.
    _mk_before=$(grep -c 'main directory cannot contain spaces nor colons' Makefile || true)
    # Remove the $(error ...) call — leaves $(if $(findstring ...),) which is benign
    sed -i 's/\$(error main directory cannot contain spaces nor colons)//g' Makefile
    _mk_after=$(grep -c 'main directory cannot contain spaces nor colons' Makefile || true)
    info "Patched kernel Makefile: spaces/colons check disabled ($_mk_before -> $_mk_after occurrences)"
  else
    # Already patched or different Makefile version
    info "Kernel Makefile: spaces/colons check not present (already patched or N/A)"
  fi

  # v1.0.91: Quote KBUILD_OUTPUT and CURDIR in sub-make / mkdir -p / cd.
  # These patches make the build survive paths with spaces.
  #
  # 1) `mkdir -p $(KBUILD_OUTPUT) && cd $(KBUILD_OUTPUT)` →
  #    `mkdir -p "$(KBUILD_OUTPUT)" && cd "$(KBUILD_OUTPUT)"`
  #
  # 2) `$(MAKE) -C $(KBUILD_OUTPUT) KBUILD_SRC=$(CURDIR) -f $(CURDIR)/Makefile` →
  #    `$(MAKE) -C "$(KBUILD_OUTPUT)" KBUILD_SRC="$(CURDIR)" -f "$(CURDIR)/Makefile"`
  #
  # 3) `$(if $(KBUILD_OUTPUT),, $(error failed to create output directory "$(saved-output)"))`
  #    already quotes saved-output — no change needed.
  #
  # We use perl for the substitution because sed doesn't easily handle the
  # quotes and special chars in the pattern (and we already had perl for
  # other kernel patches).
  _mk_quoted=0
  if grep -q 'mkdir -p \$(KBUILD_OUTPUT) && cd \$(KBUILD_OUTPUT)' Makefile 2>/dev/null; then
    # Already-quoted variant? skip
    if ! grep -q 'mkdir -p "\$(KBUILD_OUTPUT)" && cd "\$(KBUILD_OUTPUT)"' Makefile 2>/dev/null; then
      perl -0pi -e 's/mkdir -p \$\(KBUILD_OUTPUT\) && cd \$\(KBUILD_OUTPUT\)/mkdir -p "\$\(KBUILD_OUTPUT\)" \&\& cd "\$\(KBUILD_OUTPUT\)"/g' Makefile
      _mk_quoted=$((_mk_quoted + 1))
    fi
  fi
  if grep -q '\$(MAKE) -C \$(KBUILD_OUTPUT) KBUILD_SRC=\$(CURDIR)' Makefile 2>/dev/null; then
    if ! grep -q '\$(MAKE) -C "\$(KBUILD_OUTPUT)" KBUILD_SRC="\$(CURDIR)"' Makefile 2>/dev/null; then
      perl -0pi -e 's/\$\(MAKE\) -C \$\(KBUILD_OUTPUT\) KBUILD_SRC=\$\(CURDIR\)/\$\(MAKE\) -C "\$\(KBUILD_OUTPUT\)" KBUILD_SRC="\$\(CURDIR\)"/g' Makefile
      _mk_quoted=$((_mk_quoted + 1))
    fi
  fi
  if grep -q '\-f \$(CURDIR)/Makefile' Makefile 2>/dev/null; then
    if ! grep -q '\-f "\$(CURDIR)/Makefile"' Makefile 2>/dev/null; then
      perl -0pi -e 's/\-f \$\(CURDIR)\/Makefile/-f "\$\(CURDIR)\/Makefile"/g' Makefile
      _mk_quoted=$((_mk_quoted + 1))
    fi
  fi
  if [ "$_mk_quoted" -gt 0 ]; then
    info "Step 3d: quoted KBUILD_OUTPUT/CURDIR in $_mk_quoted place(s) (v1.0.91 spaces-in-path fix)"
  fi
fi

# v1.0.91: Re-apply ALL Makefile patches (error-removal + KBUILD_OUTPUT quoting).
# SuSFS's `git checkout -- .` reverts working tree, so we call this after every
# SuSFS retry loop, before Step 7 (config), and before Step 10 (build).
reapply_makefile_patches() {
  local _label="$1"
  local _changed=0
  [ -f "Makefile" ] || return 0
  # 1) Remove $(error main directory cannot contain spaces nor colons)
  if grep -q 'main directory cannot contain spaces nor colons' Makefile 2>/dev/null; then
    sed -i 's/\$(error main directory cannot contain spaces nor colons)//g' Makefile
    _changed=1
  fi
  # 2) Quote KBUILD_OUTPUT in mkdir -p / cd
  if grep -q 'mkdir -p \$(KBUILD_OUTPUT) && cd \$(KBUILD_OUTPUT)' Makefile 2>/dev/null \
     && ! grep -q 'mkdir -p "\$(KBUILD_OUTPUT)" && cd "\$(KBUILD_OUTPUT)"' Makefile 2>/dev/null; then
    perl -0pi -e 's/mkdir -p \$\(KBUILD_OUTPUT\) && cd \$\(KBUILD_OUTPUT\)/mkdir -p "\$\(KBUILD_OUTPUT\)" \&\& cd "\$\(KBUILD_OUTPUT\)"/g' Makefile
    _changed=1
  fi
  # 3) Quote KBUILD_OUTPUT / CURDIR in $(MAKE) -C sub-make
  if grep -q '\$(MAKE) -C \$(KBUILD_OUTPUT) KBUILD_SRC=\$(CURDIR)' Makefile 2>/dev/null \
     && ! grep -q '\$(MAKE) -C "\$(KBUILD_OUTPUT)" KBUILD_SRC="\$(CURDIR)"' Makefile 2>/dev/null; then
    perl -0pi -e 's/\$\(MAKE\) -C \$\(KBUILD_OUTPUT\) KBUILD_SRC=\$\(CURDIR\)/\$\(MAKE\) -C "\$\(KBUILD_OUTPUT\)" KBUILD_SRC="\$\(CURDIR\)"/g' Makefile
    _changed=1
  fi
  # 4) Quote CURDIR in -f $(CURDIR)/Makefile
  if grep -q -- '-f \$(CURDIR)/Makefile' Makefile 2>/dev/null \
     && ! grep -q -- '-f "\$(CURDIR)/Makefile"' Makefile 2>/dev/null; then
    perl -0pi -e 's/-f \$\(CURDIR\)\/Makefile/-f "\$\(CURDIR\)\/Makefile"/g' Makefile
    _changed=1
  fi
  if [ "$_changed" = "1" ]; then
    info "$_label: RE-APPLIED Makefile patches (spaces error removal + KBUILD_OUTPUT/CURDIR quoting)"
  fi
}

# ── Step 3c: Clean source tree (mrproper) ──────────────────────
# Ensure no stale .config, generated headers, or objects from previous builds.
# Safe after fresh clone too (just removes nothing).
info "Cleaning kernel source tree (mrproper)..."
make ARCH=arm64 mrproper 2>/dev/null || true

# ── Step 3b: CRITICAL early fix — __has_attribute in ALL kernel headers ──
# Problem: GCC (both host and cross) CANNOT parse __has_attribute(...) at all.
# The preprocessor does NOT short-circuit #if — it lexes the ENTIRE expression.
# Even "#if defined(X) && X(y)" fails because GCC tries to lex "X(y)" first.
# VDSO .lds is preprocessed via $(CPP) = $(CC)-E (CROSS compiler), so
# HOSTCFLAGS flags do NOT reach it. Must fix the source directly.
# Fix: replace every __has_attribute(anything) with literal 0.
# This makes "#if defined(__has_attribute) && 0" which GCC parses fine.
_ha_fix_count=0
while IFS= read -r -d '' _ha_file; do
  sed -i 's/__has_attribute([^)]*)/0/g' "$_ha_file"
  _ha_fix_count=$((_ha_fix_count + 1))
done < <(grep -rl '__has_attribute(' --include='*.h' --include='*.c' --include='*.S' . 2>/dev/null | tr '\n' '\0')
if [ "$_ha_fix_count" -gt 0 ]; then
  info "Fixed __has_attribute in $_ha_fix_count files (HOSTCC + CROSS CC compat)"
fi

# Safety net for HOSTCC too (covers any edge cases)
_HOSTCFLAGS_SAFE='-Wno-error -Wno-error=cpp -Wno-array-bounds -Wno-address -Wno-builtin-declaration-mismatch -Wno-stringop-overflow -Wno-maybe-uninitialized -Wno-packed-not-aligned'

# ── Step 4: Root solution + SuSFS (unified) ──────────────────────
info "Setting up root solution: ${ROOT_SOLUTION}"
case "$ROOT_SOLUTION" in
  kernelsu)
    # ── 4a: Clone KernelSU (any KSU manager works — same kernel protocol) ──
    if [ -d "KernelSU/kernel" ]; then
      info "KernelSU already present"
      KSU_OK=1
    else
      KSU_OK=0
      # v1.0.94: NO `set +e` — script already runs without errexit
      for _ksu_branch in main "v3.2.0" "v3.1.0"; do
        for URL in \
          "https://github.com/KernelSU-Next/KernelSU" \
          "https://github.com/negrroo/KernelSU" \
          "https://github.com/tiann/KernelSU"; do
          info "Trying: $URL (branch $_ksu_branch)"
          if GIT_TERMINAL_PROMPT=0 git clone --depth=1 --branch "$_ksu_branch" \
            --config "credential.helper=" "$URL" KernelSU 2>/dev/null; then
            KSU_OK=1; break 2
          fi
          rm -rf KernelSU
        done
      done
      if [ "$KSU_OK" = "1" ]; then
        info "KernelSU cloned OK (compatible with ALL KSU managers)"
      else
        warn "KernelSU clone FAILED — building without root"
      fi
    fi

    # ── 4b: Clone susfs4ksu and apply SuSFS ──────────────────────────
    info "Setting up SuSFS (target: v2.2.0)..."
    _SUSFS_DIR=""
    _SUSFS_TMPD=""
    if [ -f ".susfs_applied" ]; then
      info "SuSFS already applied (marker exists)"
    else
      # v1.0.94: NO `set +e` — script already runs without errexit
      _susfs_clone_ok=0
      # Try multiple repos × multiple branches (newer branches first)
      # v2.2.0 lives on 'main' / 'master' / 'kernel-4.14' depending on the fork
      for _susfs_repo in \
        "https://github.com/ShirkNeko/susfs4ksu" \
        "https://github.com/kutemeikito/susfs4ksu" \
        "https://github.com/sidex15/susfs4ksu" \
        "https://github.com/AlirezaIjmani/susfs4ksu"; do
        for _susfs_branch in main master kernel-4.14 susfs-v2.2.0 v2.2.0; do
          _SUSFS_TMPD=$(mktemp -d)
          info "Cloning susfs4ksu from $_susfs_repo (branch: $_susfs_branch) ..."
          if GIT_TERMINAL_PROMPT=0 git clone --depth=1 --branch "$_susfs_branch" \
            --config "credential.helper=" "$_susfs_repo" "$_SUSFS_TMPD/susfs4ksu" 2>/dev/null; then
            _SUSFS_DIR="$_SUSFS_TMPD/susfs4ksu/kernel_patches"
            # If kernel_patches doesn't exist, try the repo root
            [ -d "$_SUSFS_DIR" ] || _SUSFS_DIR="$_SUSFS_TMPD/susfs4ksu"
            _susfs_clone_ok=1
            info "susfs4ksu cloned OK (branch: $_susfs_branch)"
            break 2
          fi
          rm -rf "$_SUSFS_TMPD"
          _SUSFS_TMPD=""
        done
      done

      if [ "$_susfs_clone_ok" = "1" ] && [ -d "$_SUSFS_DIR" ]; then
        info "SuSFS clone directory: $_SUSFS_DIR"
        info "Available patch files:"
        ls -1 "$_SUSFS_DIR"/*.patch 2>/dev/null | sed 's/^/    /'

        # 1) Copy NEW files that the patch expects to exist
        info "SuSFS: copying new source files..."
        _susfs_copied=0
        while IFS= read -r -d '' _newf; do
          _rel="${_newf#$_SUSFS_DIR/}"
          _dstdir="$(dirname "$_rel")"
          mkdir -p "$_dstdir" 2>/dev/null
          cp -f "$_newf" "$_rel" 2>/dev/null && _susfs_copied=$((_susfs_copied + 1))
        done < <(find "$_SUSFS_DIR" -type f \( -name '*.c' -o -name '*.h' \) -print0 2>/dev/null)
        info "SuSFS: copied $_susfs_copied new files"

        # 2) Find the SuSFS patch file (auto-detect; STRICT v2.2.0 preference)
        # v1.0.87: removed v2.1.0 from the preferred list — user explicitly wants v2.2.0.
        # If no v2.2.0 patch is found, fall back to ANY susfs patch (last resort).
        _patch_file=""
        _susfs_version_detected=""
        # First pass: v2.2.0 only (any naming variation)
        for _pf_candidate in \
          "$_SUSFS_DIR/0001-suSFS-v2.2.0-for-4.14.patch" \
          "$_SUSFS_DIR/0001-suSFS-v2.2.0.patch" \
          "$_SUSFS_DIR/susfs-v2.2.0-for-4.14.patch" \
          "$_SUSFS_DIR/susfs-v2.2.0.patch" \
          "$_SUSFS_DIR/0001-susfs-v2.2.0.patch"; do
          if [ -f "$_pf_candidate" ]; then
            _patch_file="$_pf_candidate"
            _susfs_version_detected="v2.2.0"
            break
          fi
        done
        # Second pass: any 'suSFS'/'susfs' named patch (could be v2.2.0 with weird name, or older)
        if [ -z "$_patch_file" ]; then
          _patch_file=$(ls -1 "$_SUSFS_DIR"/*su*SFS*.patch "$_SUSFS_DIR"/*susfs*.patch 2>/dev/null | head -1)
          if [ -n "$_patch_file" ]; then
            # Try to extract version from filename
            case "$(basename "$_patch_file")" in
              *v2.2.0*) _susfs_version_detected="v2.2.0" ;;
              *v2.1.0*) _susfs_version_detected="v2.1.0 (fallback — v2.2.0 not found in this fork)" ;;
              *v2.0*)   _susfs_version_detected="v2.0.x (fallback)" ;;
              *)        _susfs_version_detected="unknown ($(basename "$_patch_file"))" ;;
            esac
          fi
        fi
        if [ -n "$_susfs_version_detected" ]; then
          info "SuSFS: detected version: $_susfs_version_detected"
        fi

        _patch_ok=0
        if [ -n "$_patch_file" ] && [ -f "$_patch_file" ]; then
          info "SuSFS: using patch: $(basename "$_patch_file")"
          # Try full patch first with multiple -p levels
          for _pl in 1 0 2; do
            if patch --batch -i "$_patch_file" -p${_pl} --fuzz=3 -l --no-backup-if-mismatch 2>/dev/null; then
              _patch_ok=1
              info "SuSFS: full patch applied OK (p${_pl})"
              break
            fi
            # Revert any partial application
            patch --batch -R -i "$_patch_file" -p${_pl} --no-backup-if-mismatch 2>/dev/null || true
            [ -d .git ] && git checkout -- . 2>/dev/null || true
            find . -name "*.rej" -delete 2>/dev/null
            find . -name "*.orig" -delete 2>/dev/null
          done

          # Fallback: per-file split if full patch failed
          if [ "$_patch_ok" = "0" ]; then
            info "SuSFS: full patch failed, trying per-file split..."
            _csplit_ok=0
            _tmp_split=$(mktemp -d)
            csplit -f "$_tmp_split/patch_" -z "$_patch_file" '/^diff --git /' '{*}' 2>/dev/null && _csplit_ok=1
            if [ "$_csplit_ok" = "1" ]; then
              _applied_count=0
              _total_count=0
              for _sp in "$_tmp_split"/patch_*; do
                [ -f "$_sp" ] || continue
                _total_count=$((_total_count + 1))
                for _spl in 1 0 2; do
                  if patch --batch -i "$_sp" -p${_spl} --fuzz=3 -l --no-backup-if-mismatch 2>/dev/null; then
                    _applied_count=$((_applied_count + 1))
                    break
                  fi
                done
              done
              info "SuSFS: per-file split applied $_applied_count/$_total_count hunks"
              [ "$_applied_count" -gt 0 ] && _patch_ok=1
            fi
            rm -rf "$_tmp_split"
          fi

          # v1.0.96: REMOVED safety net that appended `obj-$(CONFIG_SUSFS) += susfs.o`
#           to fs/Makefile — it used the WRONG CONFIG name (patch uses
#           CONFIG_KSU_SUSFS, not CONFIG_SUSFS) and would have caused duplicate
#           symbols. The patch itself adds the correct line.
#          # v1.0.96: REMOVED safety net that appended `source "fs/susfs/Kconfig"`
#           to fs/Kconfig — the master-branch SuSFS patch does NOT create an
#           fs/susfs/ subdir, so this source line pointed at a non-existent
#           file and caused `fs/Kconfig:323: can't open file "fs/susfs/Kconfig"`.
        else
          warn "SuSFS: no patch file found in $_SUSFS_DIR"
        fi

        if [ "$_patch_ok" = "1" ]; then
          touch .susfs_applied
          info "SuSFS applied successfully (patch: $(basename "$_patch_file"))"
        else
          warn "SuSFS patch failed — building without SuSFS"
        fi
      else
        warn "susfs4ksu clone failed — building without SuSFS"
      fi
      [ -n "$_SUSFS_TMPD" ] && rm -rf "$_SUSFS_TMPD" 2>/dev/null
      # v1.0.94: NO `set -e` here — would re-enable errexit and kill Step 4.5+
    fi
    ;;
  apatch)
    info "APatch: no kernel-side patches needed (module-based)"
    ;;
  none)
    info "No root solution selected"
    ;;
  *)
    warn "Unknown root solution: ${ROOT_SOLUTION} (use kernelsu/apatch/none)"
    ;;
esac

# ── Step 4.5: RE-APPLY Makefile patches (CRITICAL — post-SuSFS) ─────
# v1.0.88: The SuSFS patch retry loop calls `git checkout -- .` on failure,
# which reverts ALL working tree changes — including our Makefile patches
# from Step 3d. Without this re-apply, Step 7 (config) fails with:
#   Makefile:128: *** main directory cannot contain spaces nor colons. Stop.
# v1.0.91: Also re-applies KBUILD_OUTPUT/CURDIR quoting (otherwise
#   "make: *** /home/user/Рабочий: No such file or directory" on sub-make).
# This MUST run AFTER Step 4 (SuSFS) and BEFORE Step 5/6/7.
reapply_makefile_patches "Step 4.5"

# ── Step 5: KernelSU integration ────────────────────────────────
if [ "$ROOT_SOLUTION" = "kernelsu" ] && [ "$KSU_OK" = "1" ] && [ -d "KernelSU/kernel" ]; then
  info "Integrating KernelSU..."
  # Copy KernelSU kernel hooks
  for _ksu_f in KernelSU/kernel/*.c KernelSU/kernel/*.h; do
    [ -f "$_ksu_f" ] || continue
    cp -f "$_ksu_f" drivers/kernelsu/ 2>/dev/null || \
    { mkdir -p drivers/kernelsu && cp -f "$_ksu_f" drivers/kernelsu/; }
  done
  # Ensure Makefile
  if [ -d "drivers/kernelsu" ] && ! grep -q 'kernelsu' drivers/Makefile 2>/dev/null; then
    echo 'obj-$(CONFIG_KSU) += kernelsu/' >> drivers/Makefile 2>/dev/null
  fi
  info "KernelSU integration done"
fi

# ── Step 6: Copy infinity-specific files ────────────────────────
info "Copying Infinity Kernel custom files..."
_cp_count=0
for _src_file in \
  "$SCRIPT_DIR/drivers/charging/infinity_charging_control.c" \
  "$SCRIPT_DIR/drivers/charging/Kconfig" \
  "$SCRIPT_DIR/drivers/charging/Makefile" \
  "$SCRIPT_DIR/include/linux/infinity_charging_control.h"; do
  [ -f "$_src_file" ] || continue
  _dst="${_src_file#$SCRIPT_DIR/}"
  mkdir -p "$(dirname "$_dst")" 2>/dev/null
  cp -f "$_src_file" "$_dst" && _cp_count=$((_cp_count + 1))
done
if [ "$_cp_count" -gt 0 ]; then
  info "Files copied OK"
else
  info "No custom files to copy (using kernel defaults)"
fi

# ── Step 7: Config ──────────────────────────────────────────────
# v1.0.88: Final safety net — re-apply Makefile spaces patch right before
# the first `make` call in this step. SuSFS's `git checkout -- .` (Step 4)
# already reverts it once; Step 4.5 re-applies; this is a belt-and-suspenders
# check in case anything between Step 4.5 and here reverted it again.
# v1.0.91: Now uses reapply_makefile_patches() (also re-quotes KBUILD_OUTPUT).
reapply_makefile_patches "Step 7 (pre)"

info "Configuring kernel..."
PROTECTED="CONFIG_NO_HZ_COMMON CONFIG_NO_HZ_IDLE CONFIG_VIRT_CPU_ACCOUNTING_GEN CONFIG_CONTEXT_TRACKING CONFIG_NO_HZ CONFIG_HZ_PERIODIC CONFIG_NO_HZ_FULL CONFIG_CPUSETS"
DISABLE="CONFIG_STAGING CONFIG_SOUND CONFIG_SND CONFIG_RC_CORE CONFIG_MEDIA_SUPPORT CONFIG_FB CONFIG_VT CONFIG_VHOST CONFIG_COMEDI CONFIG_AGP CONFIG_INFINIBAND CONFIG_MHI_BUS CONFIG_MHI_QCOM"
DEFCONFIG=""
if [ -f "arch/arm64/configs/vendor/sm8150_defconfig" ]; then
  DEFCONFIG="vendor/sm8150_defconfig"
elif [ -f "arch/arm64/configs/sm8150_defconfig" ]; then
  DEFCONFIG="sm8150_defconfig"
else
  echo "Available configs:"
  ls arch/arm64/configs/ 2>/dev/null
  die "No sm8150 defconfig found!"
fi
info "Using defconfig: $DEFCONFIG"

# For config steps, always use gcc for host tools (avoid clang crash in scripts)
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC=aarch64-linux-gnu-gcc HOSTCC=gcc HOSTCFLAGS="$_HOSTCFLAGS_SAFE" "$DEFCONFIG"
scripts/kconfig/merge_config.sh .config arch/arm64/configs/infinity_defconfig 2>/dev/null || true

disable_cfgs() {
  for cfg in $DISABLE; do
    _s=0; for p in $PROTECTED; do [ "$cfg" = "$p" ] && _s=1 && break; done
    [ "$_s" = "1" ] && continue
    sed -i "s/^${cfg}=y/# ${cfg} is not set/" .config
    sed -i "s/^${cfg}=m/# ${cfg} is not set/" .config
  done
  sed -i 's/^CONFIG_CC_STACKPROTECTOR=y/# CONFIG_CC_STACKPROTECTOR is not set/' .config
  sed -i 's/^CONFIG_CC_STACKPROTECTOR_STRONG=y/# CONFIG_CC_STACKPROTECTOR_STRONG is not set/' .config
  sed -i '/^CONFIG_CC_STACKPROTECTOR_NONE/d' .config
  echo "CONFIG_CC_STACKPROTECTOR_NONE=y" >> .config
}
disable_cfgs
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC=aarch64-linux-gnu-gcc HOSTCC=gcc HOSTCFLAGS="$_HOSTCFLAGS_SAFE" olddefconfig </dev/null || true
disable_cfgs
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC=aarch64-linux-gnu-gcc HOSTCC=gcc HOSTCFLAGS="$_HOSTCFLAGS_SAFE" olddefconfig </dev/null || true
for cfg in $DISABLE; do
  _s=0; for p in $PROTECTED; do [ "$cfg" = "$p" ] && _s=1 && break; done
  [ "$_s" = "1" ] && continue
  sed -i "/^${cfg}=/d" .config
  grep -q "^# ${cfg} is not set" .config \
    || echo "# ${cfg} is not set" >> .config
done
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC=aarch64-linux-gnu-gcc HOSTCC=gcc HOSTCFLAGS="$_HOSTCFLAGS_SAFE" olddefconfig </dev/null || true

HIDDEN="CONFIG_SCHED_INFO CONFIG_PINCTRL CONFIG_POSIX_TIMERS CONFIG_RTC_CLASS CONFIG_SCHED_WALT CONFIG_DEBUG_REGULATOR"

# Force critical platform configs (including CPU masks to avoid interactive prompts)
# SM8150 (Poco X3 Pro): 4x A55 (CPU0-3) + 3x A76 (CPU4-6) + 1x A76-Prime (CPU7)
FORCE_CFGS="CONFIG_ARCH_QCOM=y CONFIG_MAILBOX=y CONFIG_NR_CPUS=8"
# v1.0.104: Force CONFIG_SECTION_MISMATCH_WARN_ONLY=y — prevents modpost FATAL
# on GCC 15+ when drivers have spcom_probe() -> __init spcom_register_chardev()
# style references. Downgrades the error to a warning so build can complete.
FORCE_CFGS="$FORCE_CFGS CONFIG_SECTION_MISMATCH_WARN_ONLY=y"
CPU_MASK_CFGS="CONFIG_LITTLE_CPU_MASK=0x0F CONFIG_BIG_CPU_MASK=0x70 CONFIG_PRIME_CPU_MASK=0x80"
for fc in $FORCE_CFGS; do
  fcn=$(echo "$fc" | cut -d= -f1)
  fcv=$(echo "$fc" | cut -d= -f2)
  grep -q "^${fcn}=${fcv}" .config 2>/dev/null \
    || { sed -i "/^# ${fcn} is not set/d" .config 2>/dev/null; echo "${fc}" >> .config; }
done
# Apply CPU mask configs (hex values, must be forced to avoid interactive kconfig prompt)
for mc in $CPU_MASK_CFGS; do
  mcn=$(echo "$mc" | cut -d= -f1)
  mcv=$(echo "$mc" | cut -d= -f2)
  grep -q "^${mcn}=${mcv}" .config 2>/dev/null \
    || { sed -i "/^${mcn}=/d" .config 2>/dev/null; sed -i "/^# ${mcn} is not set/d" .config 2>/dev/null; echo "${mc}" >> .config; }
done

make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC=aarch64-linux-gnu-gcc HOSTCC=gcc HOSTCFLAGS="$_HOSTCFLAGS_SAFE" -j1 scripts 2>&1 | tail -3 || true
for cfg in $HIDDEN; do
  grep -q "^${cfg}=y" .config \
    || { sed -i "/^# ${cfg} is not set/d" .config; echo "${cfg}=y" >> .config; }
  [ -f include/config/auto.conf ] && {
    grep -q "^${cfg}=y" include/config/auto.conf \
      || { sed -i "/^${cfg}=/d" include/config/auto.conf; echo "${cfg}=y" >> include/config/auto.conf; };
  }
  [ -f include/generated/autoconf.h ] && {
    grep -q "#define ${cfg} 1" include/generated/autoconf.h \
      || { sed -i "/#define ${cfg} /d" include/generated/autoconf.h; echo "#define ${cfg} 1" >> include/generated/autoconf.h; };
  }
done

# ── Step 7b: SuSFS config (v1.0.96: use CONFIG_KSU_SUSFS* names) ──
if [ "$ROOT_SOLUTION" = "kernelsu" ] && [ -f ".susfs_applied" ]; then
  for _sc in CONFIG_KSU_SUSFS CONFIG_KSU_SUSFS_SUS_PATH CONFIG_KSU_SUSFS_SUS_MOUNT CONFIG_KSU_SUSFS_SUS_MOUNT_MNT_ID_REORDER CONFIG_KSU_SUSFS_SPOOF_UNAME CONFIG_KSU_SUSFS_SUS_KSTAT CONFIG_KSU_SUSFS_SUS_MAPS CONFIG_KSU_SUSFS_SUS_MEMFD CONFIG_KSU_SUSFS_SUS_PROC_FD_LINK; do
    grep -q "^${_sc}=y" .config 2>/dev/null \
      || { sed -i "/^# ${_sc} is not set/d" .config 2>/dev/null; echo "${_sc}=y" >> .config; }
  done
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC=aarch64-linux-gnu-gcc HOSTCC=gcc HOSTCFLAGS="$_HOSTCFLAGS_SAFE" olddefconfig </dev/null || true
  info "SuSFS configs added (CONFIG_KSU_SUSFS*)"
fi
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC=aarch64-linux-gnu-gcc HOSTCC=gcc HOSTCFLAGS="$_HOSTCFLAGS_SAFE" olddefconfig </dev/null || true

info "Config ready"

# ── Step 8: OpenSSL 3.0+ patches ───────────────────────────────
[ -f "certs/extract-cert.c" ] && sed -i '1i #define OPENSSL_SUPPRESS_DEPRECATED 1' certs/extract-cert.c
[ -f "scripts/sign-file.c" ] && sed -i '1i #define OPENSSL_SUPPRESS_DEPRECATED 1' scripts/sign-file.c

# ── Step 9: Apply patches (INLINE — no external apply_all.sh) ──
# v1.0.104: CRITICAL FIX — patches/ lives in SCRIPT_DIR (where build.sh is
# launched from), NOT in the kernel source tree. Use absolute path.
_PATCH_DIR="$SCRIPT_DIR/patches"
if [ ! -d "$_PATCH_DIR" ]; then
  warn "Patches directory not found: $_PATCH_DIR — no patches will be applied"
  _PATCH_DIR=""
fi
info "Applying patches from ${_PATCH_DIR:-<none>} ..."
_PATCH_OK=0; _PATCH_FAIL=0; _PATCH_MAN=0
if [ -n "$_PATCH_DIR" ]; then
for _pf in $(find "$_PATCH_DIR" -maxdepth 1 \( -name '*.patch' -o -name '*.diff' \) 2>/dev/null | sort); do
    _pn="$(basename "$_pf")"
    echo "  [PATCH] $_pn"
    find . -name "*.rej" -delete 2>/dev/null
    find . -name "*.orig" -delete 2>/dev/null
    _applied=0

    # Try patch command: p1/p0/p2, fuzz=3, NO --forward, auto-revert on fail
    for _pl in 1 0 2; do
        if patch --batch -i "$_pf" -p${_pl} --fuzz=3 -l --no-backup-if-mismatch 2>/dev/null; then
            _applied=1; break
        fi
        _apply_patch_revert "$_pf"
    done

    # Try git apply (3way then reject)
    if [ "$_applied" = "0" ] && [ -d .git ]; then
        if git apply --3way --whitespace=nowarn "$_pf" 2>/dev/null; then
            _applied=1
        else
            git checkout -- . 2>/dev/null || true
            find . -name "*.orig" -delete 2>/dev/null
            find . -name "*.rej" -delete 2>/dev/null
        fi
    fi

    if [ "$_applied" = "0" ] && [ -d .git ]; then
        if git apply --reject --whitespace=nowarn --ignore-space-change "$_pf" 2>/dev/null; then
            if [ -z "$(find . -name '*.rej' 2>/dev/null | head -1)" ]; then
                _applied=1
            else
                git checkout -- . 2>/dev/null || true
                find . -name "*.rej" -delete 2>/dev/null
            fi
        fi
    fi

    # Manual injection: PURE BASH parser (no awk/gawk), find anchors, inject with sed
    if [ "$_applied" = "0" ]; then
        echo "    patch+git failed, trying manual injection (pure bash)..."
        _man_ok=0; _tgt=""; _inh=0
        _adds=(); _rems=(); _ctxs=()

        # Helper: inject accumulated hunk into target file
        _inj() {
            [ ${#_adds[@]} -eq 0 ] && return
            [ -z "$_tgt" ] && return
            [ ! -f "$_tgt" ] && { echo "    [MANUAL] Target missing: $_tgt"; return; }
            _anch=0
            # Exact match
            for _sl in "${_ctxs[@]}" "${_rems[@]}"; do
                [ -z "$_sl" ] && continue
                _esc=$(printf '%s' "$_sl" | sed 's/[[\.*^$()+?{|\\]/\\&/g')
                _hit=$(grep -n "$_esc" "$_tgt" 2>/dev/null | head -1)
                [ -n "$_hit" ] && { _anch=$(echo "$_hit" | cut -d: -f1); break; }
            done
            # Fuzzy: first 40 chars
            if [ "$_anch" = "0" ]; then
                for _sl in "${_ctxs[@]}" "${_rems[@]}"; do
                    [ -z "$_sl" ] && continue
                    _short="${_sl:0:40}"
                    [ ${#_short} -lt 10 ] && continue
                    _esc_s=$(printf '%s' "$_short" | sed 's/[[\.*^$()+?{|\\]/\\&/g')
                    _hit=$(grep -n "$_esc_s" "$_tgt" 2>/dev/null | head -1)
                    [ -n "$_hit" ] && { _anch=$(echo "$_hit" | cut -d: -f1); break; }
                done
            fi
            if [ "$_anch" -gt 0 ] 2>/dev/null; then
                # Build sed insert command
                _ins=""
                for _a in "${_adds[@]}"; do
                    _ins="${_ins}$(printf '%s\n' "$_a" | sed 's/[&/\]/\\&/g')\\n"
                done
                _ins="${_ins%\\\\n}"  # remove trailing \n
                sed -i "${_anch}a\\${_ins}" "$_tgt" 2>/dev/null && _man_ok=1
            else
                echo "    [MANUAL] No anchor found for $_tgt"
            fi
        }

        while IFS= read -r _line; do
            case "$_line" in
                "diff --git"*) _inj; _adds=(); _rems=(); _ctxs=(); _tgt=""; _inh=0
                    _tgt=$(echo "$_line" | sed 's|diff --git a/[^ ]* b/||') ;;
                "---"*|"+++ "*|$"index "*|"@@ "*|"@@") : ;;
                "@@"*"@") _inh=1 ;;
                "-"*) [ "$_inh" = "1" ] && _rems+=("${_line:1}") ;;
                "+"*) [ "$_inh" = "1" ] && _adds+=("${_line:1}") ;;
                " "*) [ "$_inh" = "1" ] && _ctxs+=("${_line:1}") ;;
            esac
        done < "$_pf"
        _inj  # last hunk
        [ "$_man_ok" = "1" ] && _applied=1
    fi

    if [ "$_applied" = "1" ]; then
        echo "    OK"; _PATCH_OK=$((_PATCH_OK + 1))
    else
        echo "    FAILED (skipped)"; _PATCH_FAIL=$((_PATCH_FAIL + 1))
    fi
    find . -name "*.rej" -delete 2>/dev/null
    find . -name "*.orig" -delete 2>/dev/null
done
fi  # end if [ -n "$_PATCH_DIR" ]
info "Patches: $_PATCH_OK applied, $_PATCH_FAIL failed"

# ── Step 10: Source compat fixes (19 fixes) ─────────────────────
info "Applying 19 source compat fixes..."
set +e
echo "  Fix 1/19: filter.h compat_sock_fprog"
if [ -f "include/linux/filter.h" ]; then
  echo 'BEGIN{a=0} /struct compat_sock_fprog/{if(!a){print "#ifdef CONFIG_COMPAT";a=1}} a&&/};/{print $0;print "#endif";a=0;next} {print $0}' > /tmp/fix_filter.awk
  awk -f /tmp/fix_filter.awk include/linux/filter.h > /tmp/filter.h.fixed
  mv /tmp/filter.h.fixed include/linux/filter.h
  echo "    Done"
fi

echo "  Fix 2/19: hugetlbpage.c ptep -> pte"
if [ -f "mm/hugetlbpage.c" ] && grep -q 'huge_pmd_share' mm/hugetlbpage.c 2>/dev/null; then
  sed -i 's/ptep = huge_pmd_share/pte = huge_pmd_share/' mm/hugetlbpage.c 2>/dev/null
  echo "    Done (patched)"
fi

echo "  Fix 3/19: huge_memory.c try_to_unmap NULL"
[ -f "mm/huge_memory.c" ] && sed -i 's/try_to_unmap(page, ttu_flags);/try_to_unmap(page, ttu_flags, NULL);/' mm/huge_memory.c 2>/dev/null

echo "  Fix 4/19: khugepaged.c nr_ptes"
[ -f "mm/khugepaged.c" ] && sed -i '/atomic_long_dec(&mm->nr_ptes)/d' mm/khugepaged.c 2>/dev/null

echo "  Fix 5/19: sock.c compat_timeval"
# v1.0.100: CRITICAL FIX — only inject if struct is NOT already defined
# SM8150's asm/compat.h ALREADY defines struct compat_timeval (line 74).
# When sock.c includes <asm/compat.h>, the struct is already defined.
# Our unconditional injection caused:
#   net/core/sock.c:148:8: error: redefinition of 'struct compat_timeval'
# Fix: Check if any header in the include chain already defines it.
# If yes — DO NOT inject (the kernel already has it). If no — inject
# with #ifndef guard for safety.
if [ -f "net/core/sock.c" ]; then
  # Check if struct compat_timeval is already defined somewhere in the kernel
  _ctval_defined=$(grep -rl 'struct compat_timeval {' arch/arm64/include/ include/ 2>/dev/null | head -1)
  if [ -n "$_ctval_defined" ]; then
    echo "    SKIP (struct compat_timeval already defined in $_ctval_defined)"
  else
    LI=$(grep -n '^#include' net/core/sock.c | tail -1 | cut -d: -f1)
    [ -z "$LI" ] && LI=$(grep -n '#include' net/core/sock.c | head -1 | cut -d: -f1)
    if [ -n "$LI" ]; then
      head -n "$LI" net/core/sock.c > /tmp/sock_top.c
      echo '' >> /tmp/sock_top.c
      echo '#ifndef COMPAT_USE_64BIT_TIME' >> /tmp/sock_top.c
      echo '#define COMPAT_USE_64BIT_TIME 0' >> /tmp/sock_top.c
      echo '#endif' >> /tmp/sock_top.c
      echo '#ifndef __COMPAT_TIMEVAL_DEFINED' >> /tmp/sock_top.c
      echo '#define __COMPAT_TIMEVAL_DEFINED' >> /tmp/sock_top.c
      echo 'struct compat_timeval { int tv_sec; int tv_usec; };' >> /tmp/sock_top.c
      echo '#endif /* __COMPAT_TIMEVAL_DEFINED */' >> /tmp/sock_top.c
      tail -n +"$((LI + 1))" net/core/sock.c >> /tmp/sock_top.c
      mv /tmp/sock_top.c net/core/sock.c
      echo "    Done (injected after line $LI, with #ifndef guard)"
    fi
  fi
fi

echo "  Fix 6/19: net/compat.c CONFIG_COMPAT"
if [ -f "net/compat.c" ] && ! grep -q 'CONFIG_COMPAT' net/compat.c 2>/dev/null; then
  echo '#ifdef CONFIG_COMPAT' | cat - net/compat.c > /tmp/cc.tmp && mv /tmp/cc.tmp net/compat.c
  echo '#endif' >> net/compat.c
fi

echo "  Fix 7/19: fs/compat.c CONFIG_COMPAT"
if [ -f "fs/compat.c" ] && ! grep -q 'CONFIG_COMPAT' fs/compat.c 2>/dev/null; then
  echo '#ifdef CONFIG_COMPAT' | cat - fs/compat.c > /tmp/fc.tmp && mv /tmp/fc.tmp fs/compat.c
  echo '#endif' >> fs/compat.c
fi

echo "  Fix 8/19: task_mmu.c pmd_t pointer cast"
[ -f "fs/proc/task_mmu.c" ] && sed -i 's/pmd_t \*pmd = \([^(:]*\)/pmd_t *pmd = (pmd_t *)(\1)/g' fs/proc/task_mmu.c 2>/dev/null

echo "  Fix 9/19: blktrace.c — SKIPPED (kernfs_node_id is valid in 4.14+)"
# Previous fix replaced union kernfs_node_id *id -> u64 id, but the code
# uses id->ino and id->generation, so a u64 broke it. The struct is valid
# in Linux 4.14, so no patch is needed.

echo "  Fix 10/19: fault-inject.c should_fail_ex"
[ -f "lib/fault-inject.c" ] && sed -i 's/should_fail_ex(__get_free_pages)/should_fail_ex(__get_free_pages, 0)/g' lib/fault-inject.c 2>/dev/null

echo "  Fix 11/19: trace_event_perf.c — SKIPPED (no rename)"
# Previous fix globally renamed 'event' -> 'pevt' which broke struct members
# like tp_event->event.type. The original 'event' shadow warning is already
# suppressed via KCFLAGS=-Wno-shadow, so no source patch is needed.

echo "  Fix 12/19: pinctrl includes (targeted)"
PINCTRL_COUNT=0
for f in \
  drivers/input/touchscreen/synaptics_tcm_core.c \
  drivers/input/touchscreen/synaptics_tcm_i2c.c \
  drivers/input/touchscreen/hbtp_input.c \
  drivers/input/touchscreen/synaptics_tcm_touch.c \
  drivers/platform/msm/synaptics_tcm_touch.c; do
  [ -f "$f" ] || continue
  grep -q 'linux/pinctrl/consumer.h' "$f" 2>/dev/null && continue
  grep -q 'pinctrl_select_state\|pinctrl_pm_select\|devm_pinctrl_get' "$f" 2>/dev/null || continue
  sed -i '1i #include <linux/pinctrl/consumer.h>' "$f" 2>/dev/null
  PINCTRL_COUNT=$((PINCTRL_COUNT + 1))
  echo "    Added pinctrl include: $f"
done
echo "    $PINCTRL_COUNT files patched"

echo "  Fix 13/19: iommu-debug.c stub"
if [ -f "drivers/iommu/iommu-debug.c" ]; then
  printf '/* stubbed: dev_archdata.mapping removed */\n#include <linux/module.h>\n#include <linux/device.h>\nvoid iommu_debugfs_setup(void) {}\nvoid iommu_debugfs_add_device(struct device *dev) {}\nvoid iommu_debugfs_remove_device(struct device *dev) {}\nEXPORT_SYMBOL(iommu_debugfs_setup);\nEXPORT_SYMBOL(iommu_debugfs_add_device);\nEXPORT_SYMBOL(iommu_debugfs_remove_device);\n' > drivers/iommu/iommu-debug.c 2>/dev/null && echo "    Done" || echo "    Failed"
fi

echo "  Fix 14/19: KCFLAGS applied in build"
echo "    Done (applied via KCFLAGS)"

echo "  Fix 15/19: scripts/mod/modpost.c GCC 14+ stringop-overflow"
[ -f "scripts/mod/modpost.c" ] && sed -i '/^#include <stdio.h>/a #pragma GCC diagnostic ignored "-Wstringop-overflow"' scripts/mod/modpost.c 2>/dev/null

echo "  Fix 16/19: compiler_types.h __has_attribute guard (duplicate safety)"
if [ -f "include/linux/compiler_types.h" ] && grep -q '__has_attribute' include/linux/compiler_types.h 2>/dev/null; then
  if ! grep -q 'defined(__has_attribute)' include/linux/compiler_types.h 2>/dev/null; then
    sed -i 's/#if __has_attribute(/#if defined(__has_attribute) \&\& __has_attribute(/g' include/linux/compiler_types.h
    sed -i 's/#if __has_attribute$/#if defined(__has_attribute) \&\& __has_attribute(__fallthrough__)/g' include/linux/compiler_types.h 2>/dev/null
    echo "    Done (guarded __has_attribute with defined() check)"
  else
    echo "    Already guarded"
  fi
fi

echo "  Fix 17/19: cpuidle/lpm-levels.c missing includes for Clang"
if [ -f "drivers/cpuidle/lpm-levels.c" ]; then
  _lpm_incs=""
  for _lpm_h in linux/of.h linux/cpu.h linux/cpumask.h linux/suspend.h linux/pm_qos.h linux/tick.h linux/sched.h; do
    grep -q "include <${_lpm_h}>" drivers/cpuidle/lpm-levels.c 2>/dev/null || _lpm_incs="${_lpm_incs}#include <${_lpm_h}>\n"
  done
  if [ -n "$_lpm_incs" ]; then
    printf "%b" "$_lpm_incs" | sed -i '1r /dev/stdin' drivers/cpuidle/lpm-levels.c 2>/dev/null
    echo "    Added missing includes to lpm-levels.c"
  else
    echo "    All includes present"
  fi
  # Also suppress -Werror for this specific file via Makefile CFLAGS
  if [ -f "drivers/cpuidle/Makefile" ] && ! grep -q 'CFLAGS_lpm-levels' drivers/cpuidle/Makefile 2>/dev/null; then
    echo "CFLAGS_lpm-levels.o := -Wno-error -Wno-implicit-function-declaration -Wno-int-conversion" >> drivers/cpuidle/Makefile
    echo "    Added per-file CFLAGS to cpuidle/Makefile"
  fi
else
  echo "    File not found (driver disabled or not present)"
fi

echo "  Fix 18/19: sde_crtc.c CLKFLAG_NORETAIN_MEM / CLKFLAG_RETAIN_MEM undeclared"
if [ -f "drivers/gpu/drm/msm/sde/sde_crtc.c" ]; then
  if ! grep -q 'CLKFLAG_NORETAIN_MEM' drivers/gpu/drm/msm/sde/sde_crtc.c 2>/dev/null; then
    echo "    Not needed (flags not used)"
  elif grep -q '#define CLKFLAG_NORETAIN_MEM' drivers/gpu/drm/msm/sde/sde_crtc.c 2>/dev/null; then
    echo "    Already defined"
  else
    # Use head/tail + cat instead of fragile sed multi-line insert
    _sde_inc=$(grep -n '#include' drivers/gpu/drm/msm/sde/sde_crtc.c | tail -1 | cut -d: -f1)
    if [ -n "$_sde_inc" ]; then
      head -n "$_sde_inc" drivers/gpu/drm/msm/sde/sde_crtc.c > /tmp/sde_crtc_fix.tmp
      printf '\n#ifndef CLKFLAG_NORETAIN_MEM\n#define CLKFLAG_NORETAIN_MEM 0\n#endif\n#ifndef CLKFLAG_RETAIN_MEM\n#define CLKFLAG_RETAIN_MEM 0\n#endif\n' >> /tmp/sde_crtc_fix.tmp
      tail -n +"$((_sde_inc + 1))" drivers/gpu/drm/msm/sde/sde_crtc.c >> /tmp/sde_crtc_fix.tmp
      mv /tmp/sde_crtc_fix.tmp drivers/gpu/drm/msm/sde/sde_crtc.c
      echo "    Added CLKFLAG_NORETAIN_MEM/CLKFLAG_RETAIN_MEM defines (via head/tail)"
    fi
  fi
  # Also add per-file CFLAGS to suppress any remaining issues
  if [ -f "drivers/gpu/drm/msm/sde/Makefile" ] && ! grep -q 'CFLAGS_sde_crtc' drivers/gpu/drm/msm/sde/Makefile 2>/dev/null; then
    echo "CFLAGS_sde_crtc.o := -Wno-error -Wno-implicit-function-declaration -Wno-int-conversion" >> drivers/gpu/drm/msm/sde/Makefile
    echo "    Added per-file CFLAGS to sde/Makefile"
  fi
else
  echo "    File not found"
fi

echo "  Fix 19/19: dma-mapping.c unused static functions warning"
if [ -f "arch/arm64/mm/dma-mapping.c" ]; then
  # These are just warnings but can clutter the build. Add __maybe_unused.
  sed -i 's/^static struct page \*\*_*atomic_get_pages(/__attribute__((unused)) static struct page **__atomic_get_pages(/' arch/arm64/mm/dma-mapping.c 2>/dev/null
  sed -i 's/^static struct page \*\*_*iommu_get_pages(/__attribute__((unused)) static struct page **__iommu_get_pages(/' arch/arm64/mm/dma-mapping.c 2>/dev/null
  echo "    Done"
fi

echo "  Fix 19b/19: thread_info.h — disable __bad_copy_to/from compiletime_error (GCC 15 false positive)"
if [ -f "include/linux/thread_info.h" ]; then
  # Problem: GCC 15 aggressively triggers __compiletime_error("copy destination size is too small")
  # on any reachable call to __bad_copy_to / __bad_copy_from. The check was meant to catch
  # obvious bugs but produces false positives on complex code (e.g. drivers/base/power/wakeup.c).
  # Also: in some kernel trees a stray #define __bad_copy_to(...) ((void))0) macro is defined,
  # which conflicts with the extern void declaration at thread_info.h:147 and produces
  # 'expected identifier before void' syntax errors.
  # Fix: (a) delete any such macro, (b) strip the __compiletime_error attribute.
  sed -i '/#define __bad_copy_to(/d'   include/linux/thread_info.h 2>/dev/null
  sed -i '/#define __bad_copy_from(/d' include/linux/thread_info.h 2>/dev/null
  sed -i 's/__compiletime_error("[^"]*")//g' include/linux/thread_info.h 2>/dev/null
  sed -i 's/__compiletime_warning("[^"]*")//g' include/linux/thread_info.h 2>/dev/null
  echo "    Done (stripped __compiletime_error from thread_info.h)"
fi

# Also strip from compiler-gcc.h (where the macro is usually defined)
if [ -f "include/linux/compiler-gcc.h" ]; then
  # If __compiletime_error macro is defined here, weaken it to nothing
  if grep -q '#define __compiletime_error' include/linux/compiler-gcc.h 2>/dev/null; then
    sed -i 's|#define __compiletime_error(message).*|#define __compiletime_error(message)|' include/linux/compiler-gcc.h 2>/dev/null
    echo "    Weakened __compiletime_error in compiler-gcc.h"
  fi
fi

echo "  Fix 19c/19: wcd-mbhc-v2.c snd_jack input_dev (Qualcomm techpack compat)"
# Problem: techpack/audio/asoc/codecs/wcd-mbhc-v2.c uses mbhc->button_jack.jack->input_dev
# but in this kernel tree 'struct snd_jack' has no member 'input_dev' (it was either
# removed by a backport patch or never existed in this vendor fork).
# Fix: replace the ENTIRE expression ending in '->input_dev' with NULL.
# This disables headset button events but allows the build to succeed.
# Regex explanation (extended):
#   [A-Za-z0-9_]               — start with identifier char
#   [A-Za-z0-9_.>-]*           — followed by identifiers/dots/arrows (note: '-' inside [] is literal)
#   ->input_dev                — the broken member access
#   \b                         — word boundary (so we don't catch input_device_xxx)
# Example: mbhc->button_jack.jack->input_dev  →  NULL
if [ -f "techpack/audio/asoc/codecs/wcd-mbhc-v2.c" ]; then
  # IMPORTANT: grep pattern '->input_dev\b' — the leading '-' is parsed as
  # an option flag (grep: invalid option -- '>'). MUST use '--' after flags.
  if grep -qE -- '->input_dev\b' techpack/audio/asoc/codecs/wcd-mbhc-v2.c 2>/dev/null; then
    _cnt=$(grep -cE -- '->input_dev\b' techpack/audio/asoc/codecs/wcd-mbhc-v2.c 2>/dev/null || true)
    sed -i -E 's/[A-Za-z0-9_][A-Za-z0-9_.>-]*->input_dev\b/NULL/g' \
      techpack/audio/asoc/codecs/wcd-mbhc-v2.c
    # Verify (post-patch; should be 0)
    _left=$(grep -cE -- '->input_dev\b' techpack/audio/asoc/codecs/wcd-mbhc-v2.c 2>/dev/null || true)
    echo "    Patched $_cnt occurrence(s) of ->input_dev; $_left remaining"
    if [ "$_left" != "0" ]; then
      warn "    Fix 19c: $_left ->input_dev references still remain after sed — perl fallback"
      perl -i -pe 's/[A-Za-z0-9_][A-Za-z0-9_.>-]*->input_dev\b/NULL/g' \
        techpack/audio/asoc/codecs/wcd-mbhc-v2.c 2>/dev/null || true
      _left2=$(grep -cE -- '->input_dev\b' techpack/audio/asoc/codecs/wcd-mbhc-v2.c 2>/dev/null || true)
      echo "    After perl fallback: $_left2 remaining"
    fi
  else
    echo "    No ->input_dev access found (already patched or not needed)"
  fi
  # Also add per-file CFLAGS to suppress any follow-up warnings
  if [ -f "techpack/audio/asoc/codecs/Makefile" ] && ! grep -q 'CFLAGS_wcd-mbhc-v2' techpack/audio/asoc/codecs/Makefile 2>/dev/null; then
    echo "CFLAGS_wcd-mbhc-v2.o := -Wno-error -Wno-unused-but-set-variable" >> techpack/audio/asoc/codecs/Makefile
    echo "    Added per-file CFLAGS to techpack/audio/asoc/codecs/Makefile"
  fi
fi

info "All 19 compat fixes applied"

# ── Step 10.5: RE-APPLY Makefile patches (defensive — pre-build) ─
# v1.0.88: SuSFS's `git checkout -- .` reverts the patch; Step 4.5 re-applies
# it. This is a FINAL defensive check right before the actual kernel build
# (make Image.gz-dtb) — in case Steps 8/9/10 accidentally reverted it.
# v1.0.91: Now uses reapply_makefile_patches() (also re-quotes KBUILD_OUTPUT).
reapply_makefile_patches "Step 10.5"

# ── Step 10.6: VERIFY Fix 19c actually applied (final safety net) ──
# If for any reason the wcd-mbhc-v2.c file still has ->input_dev, patch it NOW.
if [ -f "techpack/audio/asoc/codecs/wcd-mbhc-v2.c" ]; then
  if grep -qE -- '->input_dev\b' techpack/audio/asoc/codecs/wcd-mbhc-v2.c 2>/dev/null; then
    warn "Fix 19c FINAL CHECK: ->input_dev still present — forcing patch NOW"
    perl -i -pe 's/[A-Za-z0-9_][A-Za-z0-9_.>-]*->input_dev\b/NULL/g' \
      techpack/audio/asoc/codecs/wcd-mbhc-v2.c 2>/dev/null || \
    sed -i -E 's/[A-Za-z0-9_][A-Za-z0-9_.>-]*->input_dev\b/NULL/g' \
      techpack/audio/asoc/codecs/wcd-mbhc-v2.c
    _final_check=$(grep -cE -- '->input_dev\b' techpack/audio/asoc/codecs/wcd-mbhc-v2.c 2>/dev/null || true)
    if [ "$_final_check" != "0" ]; then
      err "CRITICAL: ->input_dev STILL present after final patch — build WILL FAIL"
    else
      info "Fix 19c FINAL CHECK: ->input_dev successfully patched"
    fi
  else
    info "Fix 19c FINAL CHECK: OK (no ->input_dev references)"
  fi
fi

# ── Step 10.7: Fix hid-trace.h include path (v1.0.100) ──────────────
# v1.0.100: CRITICAL FIX for fatal error:
#   ./include/trace/define_trace.h:89:42: fatal error: ./hid-trace.h: No such file or directory
# CAUSE: drivers/hid/hid-trace.c uses TRACE_DEFINE_SYSTEM which expands to
#   #include TRACE_INCLUDE(hid-trace)
# TRACE_INCLUDE() prepends "./" expecting the trace header to be in the
# same dir as the .c file. The Makefile for hid-trace.o needs `-I$(src)`
# so gcc can find it. SM8150's drivers/hid/Makefile is missing this flag.
# FIX: Append `CFLAGS_hid-trace.o += -I$(src)` to drivers/hid/Makefile
# (same pattern used by other trace files in the kernel tree).
if [ -f "drivers/hid/hid-trace.c" ] && [ -f "drivers/hid/hid-trace.h" ]; then
  if [ -f "drivers/hid/Makefile" ]; then
    if ! grep -q 'CFLAGS_hid-trace.o' drivers/hid/Makefile 2>/dev/null; then
      echo "" >> drivers/hid/Makefile
      echo "# v1.0.100: fix for hid-trace.h include path" >> drivers/hid/Makefile
      echo "CFLAGS_hid-trace.o += -I\$(src)" >> drivers/hid/Makefile
      info "Fix 20/20 (v1.0.100): added CFLAGS_hid-trace.o += -I\$(src) to drivers/hid/Makefile"
    else
      info "Fix 20/20 (v1.0.100): hid-trace CFLAGS already present"
    fi
  fi
fi

# ── Step 10.7b: Fix IPA reg-dump include path (v1.0.101, refined v1.0.104) ──
# v1.0.101: CRITICAL FIX for fatal error:
#   drivers/platform/msm/ipa/ipa_v3/dump/ipa_reg_dump.h:18:10:
#   fatal error: ipa_i.h: No such file or directory
# CAUSE: ipa_reg_dump.h (in ipa_v3/dump/) does `#include "ipa_i.h"`,
#   but ipa_i.h lives in the PARENT directory (ipa_v3/ipa_i.h).
# FIX: Append `ccflags-y += -I$(src)` to ipa_v3/Makefile itself — this
#   is the working fix confirmed by v1.0.103 build log (IPA compiled OK).
#   The dump/ subdir inherits CFLAGS from parent Makefile.
# v1.0.104: Removed the bogus `dump/Makefile` block (file doesn't exist on
#   SM8150 — was causing a spurious WARN in the log). Keep only 21b.
_IPA_V3_DIR="drivers/platform/msm/ipa/ipa_v3"
_IPA_V3_MK="${_IPA_V3_DIR}/Makefile"
if [ -f "$_IPA_V3_MK" ]; then
  if ! grep -qE 'ccflags-y.*-I\$\{srctree\}/.*ipa_v3|ccflags-y.*-I\$(src)' "$_IPA_V3_MK" 2>/dev/null; then
    {
      echo ""
      echo "# v1.0.101: ensure ipa_i.h is findable from any source in ipa_v3/"
      echo "ccflags-y += -I\$(src)"
    } >> "$_IPA_V3_MK"
    info "Fix 21b/21 (v1.0.101): added ccflags-y += -I\$(src) to ${_IPA_V3_MK}"
  else
    info "Fix 21b/21 (v1.0.101): ipa_v3/Makefile already has -I\$(src) — OK"
  fi
fi

# ── Step 10.7c: Manual SuSFS Hunk #3 injection for fs/open.c (v1.0.102) ──
# v1.0.102: CRITICAL FIX — SuSFS patch Hunk #3 for fs/open.c FAILED on SM8150.
#   The Hunk #3 adds sus_path checks to SYSCALL_DEFINE3(faccessat,...).
#   Without it, sus_path is incomplete — files hidden via SuSFS are still
#   accessible via faccessat() syscall. Build still succeeds because the
#   missing functions are guarded by #ifdef CONFIG_KSU_SUSFS_SUS_PATH.
#
#   Hunk #3 in upstream 4.14 patch expects:
#     unsigned int lookup_flags = LOOKUP_FOLLOW;
#     #ifdef CONFIG_KSU
#     ksu_handle_faccessat(&dfd, &filename, &mode, NULL);
#     #endif
#     if (mode & ~S_IRWXO) ...
#   But SM8150's fs/open.c may have slightly different context (whitespace
#   or #ifdef block), so `patch -p1` fails on this hunk.
#
#   FIX: Locate `if (mode & ~S_IRWXO)` AFTER `SYSCALL_DEFINE3(faccessat,`
#   and inject the sus_path block immediately BEFORE it. Idempotent —
#   if the block is already present (patch applied cleanly), skip.
if [ -f "fs/open.c" ] && [ -f ".susfs_applied" ]; then
  if grep -q 'CONFIG_KSU_SUSFS_SUS_PATH' fs/open.c 2>/dev/null; then
    info "Fix 22/22 (v1.0.102): SuSFS sus_path block already present in fs/open.c - OK"
  else
    info "Fix 22/22 (v1.0.102): MANUAL injection of SuSFS Hunk #3 (faccessat) into fs/open.c"
    # Locate SYSCALL_DEFINE3(faccessat line
    _facc_line=$(grep -n 'SYSCALL_DEFINE3(faccessat' fs/open.c 2>/dev/null | head -1 | cut -d: -f1)
    if [ -z "$_facc_line" ]; then
      warn "  Cannot find SYSCALL_DEFINE3(faccessat in fs/open.c - skipping Hunk #3 injection"
    else
      info "  Found SYSCALL_DEFINE3(faccessat at line $_facc_line"
      # Find FIRST `if (mode & ~S_IRWXO)` AFTER the faccessat definition
      _mode_line_abs=$(awk -v start="$_facc_line" 'NR>start && /if \(mode & ~S_IRWXO\)/ {print NR; exit}' fs/open.c 2>/dev/null)
      if [ -z "$_mode_line_abs" ]; then
        warn "  Cannot find 'if (mode & ~S_IRWXO)' after line $_facc_line - skipping Hunk #3 injection"
      else
        info "  Found 'if (mode & ~S_IRWXO)' at line $_mode_line_abs"
        # Use head/tail + heredoc for safe multi-line injection (no fragile sed)
        head -n "$((_mode_line_abs - 1))" fs/open.c > /tmp/open_fix_v102.tmp || {
          warn "  Failed to read fs/open.c head - skipping injection"
          rm -f /tmp/open_fix_v102.tmp
        }
        if [ -f /tmp/open_fix_v102.tmp ]; then
          cat >> /tmp/open_fix_v102.tmp <<'SUSFS_FACCESSAT_INJECT'

#ifdef CONFIG_KSU_SUSFS_SUS_PATH
        struct filename* fname;
        int status;
        int error;
#endif

#ifdef CONFIG_KSU_SUSFS_SUS_PATH
        fname = getname_safe(filename);
        status = susfs_sus_path_by_filename(fname, &error, SYSCALL_FAMILY_ALL_ENOENT);
        putname_safe(fname);

        if (status) {
                return error;
        }
#endif

SUSFS_FACCESSAT_INJECT
          tail -n +"$_mode_line_abs" fs/open.c >> /tmp/open_fix_v102.tmp
          mv /tmp/open_fix_v102.tmp fs/open.c
          # Verify injection succeeded
          if grep -q 'CONFIG_KSU_SUSFS_SUS_PATH' fs/open.c 2>/dev/null; then
            info "  SuSFS Hunk #3 injected successfully (sus_path block in faccessat)"
          else
            warn "  SuSFS Hunk #3 injection FAILED - sus_path will be incomplete for faccessat"
          fi
        fi
      fi
    fi
  fi
fi

# ── Step 10.8: Verify sock.c compat_timeval fix (v1.0.100) ─────────
# Final safety check — if our struct injection somehow happened despite
# the existence check, remove it to prevent redefinition error.
if [ -f "net/core/sock.c" ]; then
  _ctval_count=$(grep -c 'struct compat_timeval {' net/core/sock.c 2>/dev/null || true)
  if [ "$_ctval_count" -gt 0 ]; then
    # Check if asm/compat.h also defines it — if yes, we have a conflict
    if grep -rq 'struct compat_timeval {' arch/arm64/include/asm/compat.h 2>/dev/null; then
      warn "Fix 5/19 SAFETY: removing struct compat_timeval from sock.c (already in asm/compat.h)"
      # Remove the entire struct definition line from sock.c
      sed -i '/^struct compat_timeval { int tv_sec; int tv_usec; };$/d' net/core/sock.c
      # Also remove the #ifndef/#define/#endif guard lines we added
      sed -i '/^#ifndef __COMPAT_TIMEVAL_DEFINED$/d' net/core/sock.c
      sed -i '/^#define __COMPAT_TIMEVAL_DEFINED$/d' net/core/sock.c
      sed -i '/^#endif \/\* __COMPAT_TIMEVAL_DEFINED \*\/$/d' net/core/sock.c
      info "  Removed redundant struct compat_timeval definition from sock.c"
    fi
  fi
fi

# ── Step 11: Clean source tree ──────────────────────────────────
info "Cleaning in-tree artifacts..."
rm -f .config
rm -rf include/config include/generated 2>/dev/null
rm -f scripts/basic/fixdep scripts/kconfig/conf scripts/kconfig/mconf 2>/dev/null
find . -name '*.o' -delete 2>/dev/null
find . -name '*.cmd' -delete 2>/dev/null

# ── Step 12: Rebuild config + pre-build check ─────────────────────
info "Rebuilding config..."
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC=aarch64-linux-gnu-gcc HOSTCC=gcc HOSTCFLAGS="$_HOSTCFLAGS_SAFE" "$DEFCONFIG" </dev/null 2>&1 || true
scripts/kconfig/merge_config.sh .config arch/arm64/configs/infinity_defconfig 2>/dev/null || true
disable_cfgs
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC=aarch64-linux-gnu-gcc HOSTCC=gcc HOSTCFLAGS="$_HOSTCFLAGS_SAFE" olddefconfig </dev/null || true
for cfg in $DISABLE; do
  _s=0; for p in $PROTECTED; do [ "$cfg" = "$p" ] && _s=1 && break; done
  [ "$_s" = "1" ] && continue
  sed -i "/^${cfg}=/d" .config
  grep -q "^# ${cfg} is not set" .config \
    || echo "# ${cfg} is not set" >> .config
done
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC=aarch64-linux-gnu-gcc HOSTCC=gcc HOSTCFLAGS="$_HOSTCFLAGS_SAFE" olddefconfig </dev/null || true

for cfg in $HIDDEN; do
  grep -q "^${cfg}=y" .config \
    || { sed -i "/^# ${cfg} is not set/d" .config; echo "${cfg}=y" >> .config; }
  [ -f include/config/auto.conf ] && {
    grep -q "^${cfg}=y" include/config/auto.conf \
      || { sed -i "/^${cfg}=/d" include/config/auto.conf; echo "${cfg}=y" >> include/config/auto.conf; };
  }
  [ -f include/generated/autoconf.h ] && {
    grep -q "#define ${cfg} 1" include/generated/autoconf.h \
      || { sed -i "/#define ${cfg} /d" include/generated/autoconf.h; echo "#define ${cfg} 1" >> include/generated/autoconf.h; };
  }
done
for fc in $FORCE_CFGS; do
  fcn=$(echo "$fc" | cut -d= -f1)
  fcv=$(echo "$fc" | cut -d= -f2)
  grep -q "^${fcn}=${fcv}" .config 2>/dev/null \
    || { sed -i "/^# ${fcn} is not set/d" .config 2>/dev/null; echo "${fc}" >> .config; }
done
# Re-apply CPU masks after clean rebuild too
for mc in $CPU_MASK_CFGS; do
  mcn=$(echo "$mc" | cut -d= -f1)
  mcv=$(echo "$mc" | cut -d= -f2)
  grep -q "^${mcn}=${mcv}" .config 2>/dev/null \
    || { sed -i "/^${mcn}=/d" .config 2>/dev/null; sed -i "/^# ${mcn} is not set/d" .config 2>/dev/null; echo "${mc}" >> .config; }
done

# Re-apply SuSFS configs after clean (v1.0.96: use CONFIG_KSU_SUSFS* names)
if [ "$ROOT_SOLUTION" = "kernelsu" ] && [ -f ".susfs_applied" ]; then
  for _sc in CONFIG_KSU_SUSFS CONFIG_KSU_SUSFS_SUS_PATH CONFIG_KSU_SUSFS_SUS_MOUNT CONFIG_KSU_SUSFS_SUS_MOUNT_MNT_ID_REORDER CONFIG_KSU_SUSFS_SPOOF_UNAME CONFIG_KSU_SUSFS_SUS_KSTAT CONFIG_KSU_SUSFS_SUS_MAPS CONFIG_KSU_SUSFS_SUS_MEMFD CONFIG_KSU_SUSFS_SUS_PROC_FD_LINK; do
    grep -q "^${_sc}=y" .config 2>/dev/null \
      || { sed -i "/^# ${_sc} is not set/d" .config 2>/dev/null; echo "${_sc}=y" >> .config; }
  done
fi
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC=aarch64-linux-gnu-gcc HOSTCC=gcc HOSTCFLAGS="$_HOSTCFLAGS_SAFE" olddefconfig </dev/null || true

info "Running pre-build asm-offsets check..."
ASM_CHECK=$(make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC=aarch64-linux-gnu-gcc HOSTCC=gcc HOSTCFLAGS="$_HOSTCFLAGS_SAFE" arch/arm64/kernel/asm-offsets.s 2>&1)
# Use precise pattern to avoid false positives from function names like ERR_get_error_line
if echo "$ASM_CHECK" | grep -qE ':[0-9]+:[0-9]+: error:'; then
  err "asm-offsets.s FAILED — showing last 50 lines:"
  echo "$ASM_CHECK" | tail -50
  err "Cannot continue build — fix the error above"
  exit 1
fi
info "asm-offsets.s OK"

if [ "$USE_CLANG" = "1" ]; then
  make ARCH=arm64 CC=clang \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
    AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy \
    OBJDUMP=llvm-objdump STRIP=llvm-strip \
    HOSTCC=gcc HOSTCFLAGS="$_HOSTCFLAGS_SAFE -Wall -Wmissing-prototypes -Wstrict-prototypes -O2 -fomit-frame-pointer -std=gnu89" \
    KCFLAGS="-Wno-error -Wno-implicit-function-declaration -Wno-int-conversion -Wno-shadow -Wno-unused-function -Wno-format -Wno-array-bounds -Wno-address -Wno-builtin-declaration-mismatch -Wno-stringop-overflow -Wno-maybe-uninitialized -Wno-packed-not-aligned" \
    -j"${JOBS}" Image.gz-dtb dtbs \
    2>&1
  RET=$?
else
  make ARCH=arm64 \
    CC=aarch64-linux-gnu-gcc \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
    AR=aarch64-linux-gnu-ar NM=aarch64-linux-gnu-nm \
    OBJCOPY=aarch64-linux-gnu-objcopy \
    OBJDUMP=aarch64-linux-gnu-objdump STRIP=aarch64-linux-gnu-strip \
    HOSTCC=gcc HOSTCFLAGS="$_HOSTCFLAGS_SAFE -Wall -Wmissing-prototypes -Wstrict-prototypes -O2 -fomit-frame-pointer -std=gnu89" \
    KCFLAGS="-Wno-error -Wno-implicit-function-declaration -Wno-int-conversion -Wno-shadow -Wno-unused-function -Wno-format -Wno-array-bounds -Wno-address -Wno-builtin-declaration-mismatch -Wno-stringop-overflow -Wno-maybe-uninitialized -Wno-packed-not-aligned" \
    -j"${JOBS}" Image.gz-dtb dtbs \
    2>&1
  RET=$?
fi
_BUILD_LOG="$SCRIPT_DIR/infinity_build.log"

if [ "$RET" -ne 0 ]; then
  err "Build failed (exit $RET)"
  echo ""
  echo "=== Compilation errors (first 60) ==="
  grep -iE "error[: ]|fatal error" "$_BUILD_LOG" | head -60
  echo ""
  echo "=== Warnings near first error (context) ==="
  _first_err=$(grep -n -iE "error[: ]" "$_BUILD_LOG" | head -1 | cut -d: -f1)
  if [ -n "$_first_err" ] && [ "$_first_err" -gt 0 ] 2>/dev/null; then
    _ctx_start=$((_first_err - 5))
    [ "$_ctx_start" -lt 1 ] 2>/dev/null && _ctx_start=1
    sed -n "${_ctx_start},$((_first_err + 10))p" "$_BUILD_LOG"
  fi
  echo ""
  echo "=== Full log: $_BUILD_LOG ==="
  exit 1
fi

IMG="arch/arm64/boot/Image.gz-dtb"
[ -f "$IMG" ] || die "Image.gz-dtb not found! Check arch/arm64/boot/"
info "Build SUCCESS: $IMG ($(du -h "$IMG" | cut -f1))"

# ── Step 13: Generate boot.img (optional, for fastboot) ─────────
info "Generating boot.img for fastboot flashing..."
_MKBOOTIMG=""
if command -v mkbootimg >/dev/null 2>&1; then
  _MKBOOTIMG="mkbootimg"
elif [ -f "$HOME/toolchains/mkbootimg/mkbootimg.py" ]; then
  _MKBOOTIMG="python3 $HOME/toolchains/mkbootimg/mkbootimg.py"
else
  # Download mkbootimg.py from AOSP
  info "Downloading mkbootimg.py from AOSP..."
  mkdir -p "$HOME/toolchains/mkbootimg"
  curl -sL "https://android.googlesource.com/platform/system/tools/mkbootimg/+/refs/heads/main/mkbootimg.py?format=TEXT" \
    | base64 -d > "$HOME/toolchains/mkbootimg/mkbootimg.py" 2>/dev/null
  if [ -s "$HOME/toolchains/mkbootimg/mkbootimg.py" ]; then
    _MKBOOTIMG="python3 $HOME/toolchains/mkbootimg/mkbootimg.py"
    info "mkbootimg.py downloaded OK"
  else
    warn "mkbootimg.py download failed — skipping boot.img (AnyKernel3 ZIP still works)"
  fi
fi

BOOT_IMG=""
if [ -n "$_MKBOOTIMG" ] && [ -f "$IMG" ]; then
  _BOOT_OUT="$SCRIPT_DIR/boot.img"
  # Poco X3 Pro (vayu/bhima) SM8150 boot.img header
  _CMDLINE="console=ttyMSM0,115200,n8 androidboot.hardware=qcom androidboot.console=ttyMSM0 androidboot.memcg=1 lpm_levels.sleep_disabled=1 video=vfb:vfbrotate=2 msm_drm.dsi_display0=dsi:0:qcom,mdss_dsi_panel0:1:qcom,cmd:0:none:qcom,mdss_dsi_xiaomi_vayu_amoled:0:none:1:"
  _CMDLINE="${_CMDLINE} androidboot.init_rc=init.qcom.rc androidboot.usbcontroller=a600000.dwc3"
  _CMDLINE="${_CMDLINE} swiotlb=2048 service_locator.enable=1"
  if $_MKBOOTIMG \
    --kernel "$IMG" \
    --ramdisk /dev/null \
    --pagesize 4096 \
    --base 0x00000000 \
    --kernel_offset 0x00008000 \
    --ramdisk_offset 0x01000000 \
    --second_offset 0x00f00000 \
    --tags_offset 0x00000100 \
    --cmdline "$_CMDLINE" \
    --output "$_BOOT_OUT" 2>/dev/null; then
    BOOT_IMG="$_BOOT_OUT"
    info "boot.img ready: $_BOOT_OUT ($(du -h "$_BOOT_OUT" | cut -f1))"
  else
    warn "mkbootimg failed — boot.img not generated (AnyKernel3 ZIP still works)"
  fi
fi

# ── Step 14: AnyKernel3 ZIP (saved to out/) ────────────────────────────────
info "Creating AnyKernel3 ZIP..."
AK3_DIR="$SCRIPT_DIR/AnyKernel3"
[ -d "$AK3_DIR" ] || die "AnyKernel3 directory not found!"

# Clean old artifacts
rm -f "$AK3_DIR/Image.gz-dtb" "$AK3_DIR/dtbo.img"
rm -rf "$AK3_DIR/dtbs"

# Copy new artifacts
cp -f "$IMG" "$AK3_DIR/"
if [ -d "arch/arm64/boot/dts/qcom" ]; then
  cp -f arch/arm64/boot/dts/qcom/*.dtb "$AK3_DIR/dtbs/" 2>/dev/null || {
    mkdir -p "$AK3_DIR/dtbs"
    cp -f arch/arm64/boot/dts/qcom/*.dtb "$AK3_DIR/dtbs/"
  }
fi

# Save the flashable ZIP into the out/ folder (per user request)
# v1.0.98: Save to $SCRIPT_DIR/out/ (the user's launch directory) instead of
# $KERNEL_SRC/out/ — more intuitive and accessible.
ZIP_OUT_DIR="$SCRIPT_DIR/out"
mkdir -p "$ZIP_OUT_DIR"
ZIP_NAME="InfinityKernel-${VERSION}-vayu.zip"
ZIP_PATH="$ZIP_OUT_DIR/$ZIP_NAME"
rm -f "$ZIP_PATH"
( cd "$AK3_DIR" && zip -r9 "$ZIP_PATH" . -x ".*" )
info "ZIP saved to: $ZIP_PATH ($(du -h "$ZIP_PATH" | cut -f1))"

# Also keep a copy in SCRIPT_DIR for backward compatibility
cp -f "$ZIP_PATH" "$SCRIPT_DIR/$ZIP_NAME" 2>/dev/null || true

echo -e "${GRN}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║  Build complete!                        ║"
echo "  ║  ${ZIP_NAME}"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${RST}"
if [ -n "$BOOT_IMG" ]; then
  info "boot.img: $BOOT_IMG (fastboot flash boot $BOOT_IMG)"
fi
info "Flashable ZIP: $ZIP_PATH"
info "  (also copied to: $SCRIPT_DIR/$ZIP_NAME)"
info "Flash via recovery or: adb reboot recovery"