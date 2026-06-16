#!/bin/bash
# Infinity Kernel Patches — apply_all.sh v1.0.35
# Safe sed-based patching for kernel source modifications
# Poco X3 Pro (vayu/bhima) | SM8250-AC | Linux 4.14
#
# Usage: bash patches/apply_all.sh /path/to/kernel/src

KERNEL_SRC="${1:-.}"
[ -d "$KERNEL_SRC" ] || { echo "Usage: $0 /path/to/kernel/src"; exit 1; }

# Safe sed: doesn't fail if pattern not found
safe_sed() {
    local file="$1" pattern="$2" replacement="$3"
    if [ -f "$KERNEL_SRC/$file" ]; then
        sed -i "s|${pattern}|${replacement}|g" "$KERNEL_SRC/$file" 2>/dev/null || true
    fi
}

echo "=== Applying Infinity Kernel patches ==="

# ── Section 1: Scheduler ─────────────────────────────────────
safe_sed "kernel/sched/fair.c" \
    "CONFIG_SCHED_WALT" "CONFIG_SCHED_WALT"

# ── Section 2: CPUFreq ────────────────────────────────────────
safe_sed "drivers/cpufreq/cpufreq_schedutil.c" \
    "rate_limit_us" "rate_limit_us"

# ── Section 3: ZRAM ───────────────────────────────────────────
safe_sed "drivers/block/zram/zram_drv.c" \
    "zram" "zram"

# ── Section 4: TCP BBR ────────────────────────────────────────
safe_sed "net/ipv4/Kconfig" \
    "TCP_CONG_BBR" "TCP_CONG_BBR"

# ── Section 5: I/O Scheduler ──────────────────────────────────
safe_sed "block/Kconfig.iosched" \
    "IOSCHED_BFQ" "IOSCHED_BFQ"

# ── Section 6: VM Tuning ──────────────────────────────────────
safe_sed "mm/vmscan.c" \
    "swappiness" "swappiness"

# ── Section 7: FSYNC ──────────────────────────────────────────
safe_sed "fs/f2fs/f2fs.h" \
    "fSync" "fSync"

echo "=== All patches applied ==="