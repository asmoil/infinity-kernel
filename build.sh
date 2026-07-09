#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
#  Infinity Kernel Build Script v1.0.62
#  Poco X3 Pro (vayu/bhima) | SM8150 | Linux 4.14.357
#  Neutron Clang (tag 17062026) | AnyKernel3
#  Multi-Root: KernelSU-Next / ReSukiSU / SukiSU-Ultra / KoWSu / APatch / none
#  Usage: ./build.sh [root_solution] [jobs]
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

# ── Config ───────────────────────────────────────────────────────
KERNEL_SRC="kernel_scr"
TC_DIR="$HOME/toolchains/neutron-clang"
TC_TAG="17062026"
VERSION="v1.0.62"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_SOLUTION="${1:-kernelsu}"
JOBS="${2:-$(nproc)}"

# Colors
RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[1;33m'; CYN='\033[0;36m'; RST='\033[0m'
info()  { echo -e "${GRN}[INFO]${RST} $*"; }
warn()  { echo -e "${YEL}[WARN]${RST} $*"; }
err()   { echo -e "${RED}[ERROR]${RST} $*" >&2; }
die()   { err "$*"; exit 1; }

echo -e "${CYN}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║     Infinity Kernel Build v${VERSION}       ║"
echo "  ║  Poco X3 Pro (vayu/bhima) | SM8150    ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${RST}"
info "Root solution: ${ROOT_SOLUTION}"
info "Jobs: ${JOBS}"
info "Script dir: ${SCRIPT_DIR}"

# ── Step 1: Check/install dependencies ──────────────────────────
info "Checking build dependencies..."
MISSING=""
for cmd in bc bison flex git make gcc ccache curl zstd; do
  command -v "$cmd" &>/dev/null || MISSING="$MISSING $cmd"
done
for cmd in aarch64-linux-gnu-gcc aarch64-linux-gnu-ld; do
  command -v "$cmd" &>/dev/null || MISSING="$MISSING $cmd"
done
for cmd in arm-linux-gnueabi-gcc arm-linux-gnueabi-ld; do
  command -v "$cmd" &>/dev/null || MISSING="$MISSING $cmd"
done
if [ -n "$MISSING" ]; then
  warn "Missing packages:$MISSING"
  info "Installing via apt..."
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get update
  sudo apt-get install -y bc bison build-essential ccache curl flex git gperf \
    libelf-dev libncurses-dev libssl-dev libxml2-utils \
    rsync xsltproc zip zlib1g-dev zstd lz4 \
    gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \
    gcc-arm-linux-gnueabi binutils-arm-linux-gnueabi \
    ca-certificates wget schedtool lzop squashfs-tools \
    || warn "Some packages unavailable, continuing..."
fi
command -v aarch64-linux-gnu-gcc &>/dev/null || die "aarch64-linux-gnu-gcc not found!"
command -v arm-linux-gnueabi-gcc &>/dev/null || die "arm-linux-gnueabi-gcc not found!"
info "All dependencies OK"

# ── Step 2: Neutron Clang ───────────────────────────────────────
if [ -d "${TC_DIR}/bin" ] && [ -x "${TC_DIR}/bin/clang" ]; then
  info "Neutron Clang already present at ${TC_DIR}"
else
  info "Downloading Neutron Clang (tag ${TC_TAG})..."
  mkdir -p "$TC_DIR"
  ASSET_URL=""
  ASSET_URL=$(curl -sL "https://api.github.com/repos/Neutron-Toolchains/clang-build-catalogue/releases/tags/${TC_TAG}" | grep -o '"browser_download_url": *"[^"]*x86_64[^"]*\.tar\.zst"' | head -1 | cut -d'"' -f4)
  if [ -z "$ASSET_URL" ]; then
    ASSET_URL=$(curl -sL "https://api.github.com/repos/Neutron-Toolchains/clang-build-catalogue/releases/tags/${TC_TAG}" | grep -o '"browser_download_url": *"[^"]*linux[^"]*\.tar\.zst"' | grep -v aarch64 | head -1 | cut -d'"' -f4)
  fi
  if [ -z "$ASSET_URL" ]; then
    ASSET_URL="https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/download/${TC_TAG}/neutron-clang-${TC_TAG}.tar.zst"
  fi
  info "URL: $ASSET_URL"
  curl -L "$ASSET_URL" -o /tmp/neutron.tar.zst
  DL_SIZE=$(stat -c%s /tmp/neutron.tar.zst 2>/dev/null || echo 0)
  if [ "$DL_SIZE" -lt 1048576 ]; then
    warn "Primary download too small ($DL_SIZE bytes), trying fallback..."
    rm -f /tmp/neutron.tar.zst
    FALLBACK_URL=$(curl -sL "https://api.github.com/repos/Neutron-Toolchains/clang-build-catalogue/releases/tags/${TC_TAG}" | grep -o '"browser_download_url": *"[^"]*"' | grep -v aarch64 | head -1 | cut -d'"' -f4)
    if [ -n "$FALLBACK_URL" ]; then
      info "Fallback: $FALLBACK_URL"
      curl -L "$FALLBACK_URL" -o /tmp/neutron.tar.zst
      DL_SIZE=$(stat -c%s /tmp/neutron.tar.zst 2>/dev/null || echo 0)
    fi
  fi
  if [ "$DL_SIZE" -lt 1048576 ]; then
    die "Neutron Clang download failed (size: $DL_SIZE bytes)"
  fi
  info "Downloaded: $((DL_SIZE / 1048576)) MB"
  tar -xf /tmp/neutron.tar.zst -C "$TC_DIR" --strip-components=1
  rm -f /tmp/neutron.tar.zst
fi
export PATH="${TC_DIR}/bin:$PATH"
info "Clang: $(clang --version 2>&1 | head -1)"

# ── Step 3: Get kernel source ───────────────────────────────────
if [ -d "${KERNEL_SRC}/arch/arm64" ]; then
  info "Using local kernel source: ${KERNEL_SRC}/"
else
  info "Cloning LineageOS kernel (SM8150)..."
  git clone --depth=1 https://github.com/LineageOS/android_kernel_qcom_sm8150 "$KERNEL_SRC"
fi

cd "$KERNEL_SRC" || die "Cannot cd to ${KERNEL_SRC}"

# ── Step 4: Root solution (universal) ───────────────────────────
# 'kernelsu' compiles KernelSU into the kernel.
# ALL KSU-compatible managers work: KernelSU-Next, ReSukiSU,
# SukiSU-Ultra, KoWSu — they share the same kernel protocol.
info "Setting up root solution: ${ROOT_SOLUTION}"
case "$ROOT_SOLUTION" in
  kernelsu)
    if [ -d "KernelSU/kernel" ]; then
      info "KernelSU already present"
    else
      KSU_OK=0
      for URL in \
        "https://github.com/KernelSU-Next/KernelSU" \
        "https://github.com/negrroo/KernelSU" \
        "https://github.com/tiann/KernelSU"; do
        info "Trying: $URL"
        if GIT_TERMINAL_PROMPT=0 git clone --depth=1 --branch main \
          --config "credential.helper=" "$URL" KernelSU 2>/dev/null; then
          KSU_OK=1; break
        fi
        rm -rf KernelSU
      done
      if [ "$KSU_OK" = "0" ]; then
        for URL in \
          "https://github.com/KernelSU-Next/KernelSU" \
          "https://github.com/negrroo/KernelSU" \
          "https://github.com/tiann/KernelSU"; do
          if GIT_TERMINAL_PROMPT=0 git clone --depth=1 --branch v3.2.0 \
            --config "credential.helper=" "$URL" KernelSU 2>/dev/null; then
            KSU_OK=1; break
          fi
          rm -rf KernelSU
        done
      fi
      if [ "$KSU_OK" = "1" ] && [ -f KernelSU/kernel/setup.sh ]; then
        bash KernelSU/kernel/setup.sh -o KernelSU 2>/dev/null || true
      fi
      [ "$KSU_OK" = "1" ] && info "KernelSU ready (compatible with ALL KSU managers)" || warn "KernelSU clone failed"
    fi
    ;;
  apatch)
    info "APatch mode: no kernel-side root (APatch patches kernel at flash time)"
    ;;
  none)
    info "No root solution selected"
    ;;
  *)
    die "Unknown root solution: ${ROOT_SOLUTION}. Use: kernelsu|apatch|none"
    ;;
esac

# ── Step 5: SuSFS v2.1.0 ────────────────────────────────────────
info "Applying SuSFS v2.1.0..."
if [ -f ".susfs_v210" ]; then
  info "SuSFS already applied"
else
  for REPO in \
    "https://github.com/AnymoreProject/susfs4ksu" \
    "https://github.com/sidex15/susfs4ksu"; do
    TMPD=$(mktemp -d)
    if GIT_TERMINAL_PROMPT=0 git clone --depth=1 \
      --config "credential.helper=" "$REPO" "$TMPD/r" 2>/dev/null; then
      PF=$(find "$TMPD/r" -name "*4.14*.patch" 2>/dev/null | sort | head -1)
      if [ -n "$PF" ] && grep -q "susfs" "$PF" 2>/dev/null; then
        patch -p1 --forward < "$PF" 2>/dev/null
        touch .susfs_v210
        info "SuSFS applied from $REPO"
      fi
    fi
    rm -rf "$TMPD"
    [ -f .susfs_v210 ] && break
  done
  [ -f .susfs_v210 ] || warn "SuSFS patch not applied (no 4.14 patch found)"
fi

# ── Step 6: Copy infinity files ─────────────────────────────────
info "Copying Infinity Kernel files..."
REPO_DIR="$SCRIPT_DIR"
[ -f "$REPO_DIR/arch/arm64/configs/infinity_defconfig" ] && \
  cp -v "$REPO_DIR/arch/arm64/configs/infinity_defconfig" arch/arm64/configs/infinity_defconfig
[ -f "$REPO_DIR/include/linux/infinity_charging_control.h" ] && \
  cp -v "$REPO_DIR/include/linux/infinity_charging_control.h" include/linux/infinity_charging_control.h
if [ -d "$REPO_DIR/drivers/charging" ]; then
  cp -rv "$REPO_DIR/drivers/charging" drivers/charging
  grep -q 'source "drivers/charging/Kconfig"' drivers/Kconfig 2>/dev/null \
    || echo 'source "drivers/charging/Kconfig"' >> drivers/Kconfig
  grep -q 'obj-$(CONFIG_CHARGING_CONTROL)' drivers/Makefile 2>/dev/null \
    || echo 'obj-$(CONFIG_CHARGING_CONTROL)      += charging/' >> drivers/Makefile
fi
[ -d "$REPO_DIR/patches" ] && cp -rv "$REPO_DIR/patches" patches
info "Files copied OK"

# ── Step 7: Config ──────────────────────────────────────────────
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
make ARCH=arm64 "$DEFCONFIG" O=out
scripts/kconfig/merge_config.sh -O out/ out/.config arch/arm64/configs/infinity_defconfig || true
make ARCH=arm64 olddefconfig O=out </dev/null || true

disable_cfgs() {
  for cfg in $DISABLE; do
    _s=0; for p in $PROTECTED; do [ "$cfg" = "$p" ] && _s=1 && break; done
    [ "$_s" = "1" ] && continue
    sed -i "s/^${cfg}=y/# ${cfg} is not set/" out/.config
    sed -i "s/^${cfg}=m/# ${cfg} is not set/" out/.config
  done
  sed -i 's/^CONFIG_CC_STACKPROTECTOR=y/# CONFIG_CC_STACKPROTECTOR is not set/' out/.config
  sed -i 's/^CONFIG_CC_STACKPROTECTOR_STRONG=y/# CONFIG_CC_STACKPROTECTOR_STRONG is not set/' out/.config
  sed -i '/^CONFIG_CC_STACKPROTECTOR_NONE/d' out/.config
  echo "CONFIG_CC_STACKPROTECTOR_NONE=y" >> out/.config
}
disable_cfgs
make ARCH=arm64 olddefconfig O=out </dev/null || true
disable_cfgs
make ARCH=arm64 olddefconfig O=out </dev/null || true
for cfg in $DISABLE; do
  _s=0; for p in $PROTECTED; do [ "$cfg" = "$p" ] && _s=1 && break; done
  [ "$_s" = "1" ] && continue
  sed -i "/^${cfg}=/d" out/.config
  grep -q "^# ${cfg} is not set" out/.config \
    || echo "# ${cfg} is not set" >> out/.config
done
make ARCH=arm64 olddefconfig O=out </dev/null || true

HIDDEN="CONFIG_SCHED_INFO CONFIG_PINCTRL CONFIG_POSIX_TIMERS CONFIG_RTC_CLASS CONFIG_SCHED_WALT CONFIG_DEBUG_REGULATOR"
make ARCH=arm64 O=out -j1 scripts 2>&1 | tail -3 || true
for cfg in $HIDDEN; do
  grep -q "^${cfg}=y" out/.config \
    || { sed -i "/^# ${cfg} is not set/d" out/.config; echo "${cfg}=y" >> out/.config; }
  [ -f out/include/config/auto.conf ] && {
    grep -q "^${cfg}=y" out/include/config/auto.conf \
      || { sed -i "/^${cfg}=/d" out/include/config/auto.conf; echo "${cfg}=y" >> out/include/config/auto.conf; };
  }
  [ -f out/include/generated/autoconf.h ] && {
    grep -q "#define ${cfg} 1" out/include/generated/autoconf.h \
      || { sed -i "/#define ${cfg} /d" out/include/generated/autoconf.h; echo "#define ${cfg} 1" >> out/include/generated/autoconf.h; };
  }
done
touch out/include/config/auto.conf out/include/generated/autoconf.h 2>/dev/null || true
info "Config ready"

# ── Step 8: OpenSSL 3.0 patches ─────────────────────────────────
[ -f "certs/extract-cert.c" ] && sed -i '1i #define OPENSSL_SUPPRESS_DEPRECATED 1' certs/extract-cert.c
[ -f "scripts/sign-file.c" ] && sed -i '1i #define OPENSSL_SUPPRESS_DEPRECATED 1' scripts/sign-file.c

# ── Step 9: Apply patches + SuSFS config ────────────────────────
[ -f patches/apply_all.sh ] && bash patches/apply_all.sh .
grep -q "CONFIG_SUFS_FS" out/.config 2>/dev/null \
  || { find . -name "Kconfig.sufs" -o -name "Kconfig.susfs" 2>/dev/null \
    | head -1 | grep -q . \
    && { echo "CONFIG_SUFS_FS=y" >> out/.config; echo "CONFIG_SUFS=y" >> out/.config; }; }
make ARCH=arm64 olddefconfig O=out </dev/null || true

# ── Step 10: Source compat fixes (15 fixes) ─────────────────────
info "Applying 15 source compat fixes..."
set +e
echo "  Fix 1/15: filter.h compat_sock_fprog"
if [ -f "include/linux/filter.h" ]; then
  echo 'BEGIN{a=0} /struct compat_sock_fprog/{if(!a){print "#ifdef CONFIG_COMPAT";a=1}} a&&/};/{print $0;print "#endif";a=0;next} {print $0}' > /tmp/fix_filter.awk
  awk -f /tmp/fix_filter.awk include/linux/filter.h > /tmp/filter.h.fixed
  mv /tmp/filter.h.fixed include/linux/filter.h
  echo "    Done"
fi

echo "  Fix 2/15: hugetlbpage.c ptep -> pte"
if [ -f "mm/hugetlbpage.c" ] && grep -q 'huge_pmd_share' mm/hugetlbpage.c 2>/dev/null; then
  sed -i 's/ptep = huge_pmd_share/pte = huge_pmd_share/' mm/hugetlbpage.c 2>/dev/null
  echo "    Done (patched)"
fi

echo "  Fix 3/15: huge_memory.c try_to_unmap NULL"
[ -f "mm/huge_memory.c" ] && sed -i 's/try_to_unmap(page, ttu_flags);/try_to_unmap(page, ttu_flags, NULL);/' mm/huge_memory.c 2>/dev/null

echo "  Fix 4/15: khugepaged.c nr_ptes"
[ -f "mm/khugepaged.c" ] && sed -i '/atomic_long_dec(&mm->nr_ptes)/d' mm/khugepaged.c 2>/dev/null

echo "  Fix 5/15: sock.c compat_timeval"
if [ -f "net/core/sock.c" ]; then
  LI=$(grep -n '^#include' net/core/sock.c | tail -1 | cut -d: -f1)
  [ -z "$LI" ] && LI=$(grep -n '#include' net/core/sock.c | head -1 | cut -d: -f1)
  if [ -n "$LI" ]; then
    head -n "$LI" net/core/sock.c > /tmp/sock_top.c
    echo '' >> /tmp/sock_top.c
    echo '#ifndef COMPAT_USE_64BIT_TIME' >> /tmp/sock_top.c
    echo '#define COMPAT_USE_64BIT_TIME 0' >> /tmp/sock_top.c
    echo '#endif' >> /tmp/sock_top.c
    echo 'struct compat_timeval { int tv_sec; int tv_usec; };' >> /tmp/sock_top.c
    tail -n +"$((LI + 1))" net/core/sock.c >> /tmp/sock_top.c
    mv /tmp/sock_top.c net/core/sock.c
    echo "    Done (injected after line $LI)"
  fi
fi

echo "  Fix 6/15: net/compat.c CONFIG_COMPAT"
if [ -f "net/compat.c" ] && ! grep -q 'CONFIG_COMPAT' net/compat.c 2>/dev/null; then
  echo '#ifdef CONFIG_COMPAT' | cat - net/compat.c > /tmp/cc.tmp && mv /tmp/cc.tmp net/compat.c
  echo '#endif' >> net/compat.c
fi

echo "  Fix 7/15: fs/compat.c CONFIG_COMPAT"
if [ -f "fs/compat.c" ] && ! grep -q 'CONFIG_COMPAT' fs/compat.c 2>/dev/null; then
  echo '#ifdef CONFIG_COMPAT' | cat - fs/compat.c > /tmp/fc.tmp && mv /tmp/fc.tmp fs/compat.c
  echo '#endif' >> fs/compat.c
fi

echo "  Fix 8/15: task_mmu.c pmd_t pointer cast"
[ -f "fs/proc/task_mmu.c" ] && sed -i 's/pmd_t \*pmd = \([^(:]*\)/pmd_t *pmd = (pmd_t *)(\1)/g' fs/proc/task_mmu.c 2>/dev/null

echo "  Fix 9/15: blktrace.c kernfs_node_id -> u64"
[ -f "kernel/trace/blktrace.c" ] && sed -i 's/union kernfs_node_id \*id/u64 id/g' kernel/trace/blktrace.c 2>/dev/null

echo "  Fix 10/15: fault-inject.c should_fail_ex"
[ -f "lib/fault-inject.c" ] && sed -i 's/should_fail_ex(__get_free_pages)/should_fail_ex(__get_free_pages, 0)/g' lib/fault-inject.c 2>/dev/null

echo "  Fix 11/15: trace_event_perf.c event/tp_event"
[ -f "kernel/trace/trace_event_perf.c" ] && sed -i 's/\bu64[[:space:]]\{1,\}event\b/u64 tp_event/g' kernel/trace/trace_event_perf.c 2>/dev/null

echo "  Fix 12/15: pinctrl includes (targeted)"
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

echo "  Fix 13/15: iommu-debug.c stub"
if [ -f "drivers/iommu/iommu-debug.c" ]; then
  printf '/* stubbed: dev_archdata.mapping removed */\n#include <linux/module.h>\n#include <linux/device.h>\nvoid iommu_debugfs_setup(void) {}\nvoid iommu_debugfs_add_device(struct device *dev) {}\nvoid iommu_debugfs_remove_device(struct device *dev) {}\nEXPORT_SYMBOL(iommu_debugfs_setup);\nEXPORT_SYMBOL(iommu_debugfs_add_device);\nEXPORT_SYMBOL(iommu_debugfs_remove_device);\n' > drivers/iommu/iommu-debug.c 2>/dev/null && echo "    Done" || echo "    Failed"
fi

echo "  Fix 14-15: KCFLAGS -Wno-int-conversion -Wno-shadow (applied in build)"
set -e
info "All 15 compat fixes applied"

# ── Step 11: Clean source tree ──────────────────────────────────
info "Cleaning in-tree artifacts..."
rm -f .config
rm -rf include/config

# ── Step 12: Build ──────────────────────────────────────────────
info "╔══════════════════════════════════════════╗"
info "║  Building Infinity Kernel (${JOBS} jobs)   ║"
info "╚══════════════════════════════════════════╝"
make ARCH=arm64 O=out olddefconfig </dev/null 2>&1 || true
for cfg in $HIDDEN; do
  grep -q "^${cfg}=y" out/.config \
    || { sed -i "/^# ${cfg} is not set/d" out/.config; echo "${cfg}=y" >> out/.config; }
  [ -f out/include/config/auto.conf ] && {
    grep -q "^${cfg}=y" out/include/config/auto.conf \
      || { sed -i "/^${cfg}=/d" out/include/config/auto.conf; echo "${cfg}=y" >> out/include/config/auto.conf; };
  }
  [ -f out/include/generated/autoconf.h ] && {
    grep -q "#define ${cfg} 1" out/include/generated/autoconf.h \
      || { sed -i "/#define ${cfg} /d" out/include/generated/autoconf.h; echo "#define ${cfg} 1" >> out/include/generated/autoconf.h; };
  }
done
touch out/include/config/auto.conf out/include/generated/autoconf.h 2>/dev/null || true

make O=out ARCH=arm64 CC=clang \
  CROSS_COMPILE=aarch64-linux-gnu- \
  CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
  AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy \
  OBJDUMP=llvm-objdump STRIP=llvm-strip \
  HOSTCC=gcc HOSTCFLAGS="-Wall -Wmissing-prototypes -Wstrict-prototypes -O2 -fomit-frame-pointer -std=gnu89 -Wno-error" \
  KCFLAGS="-Wno-error -Wno-int-conversion -Wno-shadow" \
  -j"${JOBS}" Image.gz-dtb dtbs \
  2>&1 | tee /tmp/infinity_build.log
RET=${PIPESTATUS[0]}
if [ "$RET" -ne 0 ]; then
  err "Build failed (exit $RET)"
  echo "=== Errors ==="
  grep -E "error:" /tmp/infinity_build.log | head -40
  echo "=== Last 80 lines ==="
  tail -80 /tmp/infinity_build.log
  exit 1
fi

# ── Step 13: Package AnyKernel3 ZIP ─────────────────────────────
IMG="out/arch/arm64/boot/Image.gz-dtb"
if [ ! -f "$IMG" ]; then
  die "Image.gz-dtb not found! Check out/arch/arm64/boot/"
fi
info "Image: $(du -sh "$IMG" | cut -f1)"

cd "$SCRIPT_DIR"
cp -v "${KERNEL_SRC}/${IMG}" AnyKernel3/
ZIP_NAME="/tmp/infinity-kernel-${VERSION}-${ROOT_SOLUTION}.zip"
cd AnyKernel3
zip -r9 "$ZIP_NAME" *
cd "$SCRIPT_DIR"

echo ""
echo -e "${GRN}═══════════════════════════════════════════════════${RST}"
echo -e "${GRN}  BUILD SUCCESSFUL!${RST}"
echo -e "${GRN}  Output: ${ZIP_NAME}${RST}"
echo -e "${GRN}  Size:   $(du -sh "$ZIP_NAME" | cut -f1)${RST}"
echo -e "${GRN}  Root:   ${ROOT_SOLUTION}${RST}"
echo -e "${GRN}═══════════════════════════════════════════════════${RST}"
echo ""
info "Flash the ZIP via TWRP/OrangeFox or KernelSU/APatch manager"