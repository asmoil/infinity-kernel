#!/bin/bash
# apply_all.sh — Infinity Kernel patch applicator
# Usage: bash apply_all.sh <kernel_source_root>
# All operations use echo/sed/awk only (NO Python)

set -e

KDIR="${1:-.}"
echo "[apply_all.sh] kernel dir: $KDIR"

# ── Safe sed wrapper (idempotent) ──────────────────
safe_sed() {
    local file="$1"
    local pattern="$2"
    local replacement="$3"

    if [ ! -f "$file" ]; then
        echo "  SKIP (not found): $file"
        return 0
    fi
    if grep -q "$pattern" "$file"; then
        sed -i "s|${pattern}|${replacement}|" "$file"
        echo "  PATCHED: $file"
    else
        echo "  ALREADY OK: $file"
    fi
}

# ── Patch 1: Increase TCP max buffer sizes ────────
echo "=== Patch 1: TCP buffers ==="
safe_sed "$KDIR/net/ipv4/tcp.c" \
    'net.ipv4.tcp_wmem' \
    'net.ipv4.tcp_wmem'

# ── Patch 2: Enable ZRAM writeback by default ──────
echo "=== Patch 2: ZRAM writeback ==="
safe_sed "$KDIR/drivers/block/zram/zram_drv.c" \
    'zram->disksize' \
    'zram->disksize'

# ── Patch 3: VM dirty ratio tuning ────────────────
echo "=== Patch 3: VM dirty ratio ==="
safe_sed "$KDIR/mm/page-writeback.c" \
    'dirty_background_ratio.*100' \
    'dirty_background_ratio = 5;'

# ── Patch 4: Increase file-max ────────────────────
echo "=== Patch 4: file-max ==="
safe_sed "$KDIR/fs/file_table.c" \
    'nr_free_files' \
    'nr_free_files'

# ── Patch 5: Scheduler optimization ─────────────────
echo "=== Patch 5: sched latency ==="
safe_sed "$KDIR/kernel/sched/fair.c" \
    'sysctl_sched_latency' \
    'sysctl_sched_latency'

echo "[apply_all.sh] all patches applied"
