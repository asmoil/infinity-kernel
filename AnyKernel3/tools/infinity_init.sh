#!/system/bin/sh
# infinity_init.sh — Post-flash initialization for Infinity Kernel
# Runs at first boot after AnyKernel3 install
# Location: AnyKernel3/tools/infinity_init.sh

ILOG="/data/local/tmp/infinity_init.log"
log() { echo "$@" | tee -a "$ILOG"; }

log "[infinity_init] Starting post-flash init..."

# ── 1. TCP BBR ─────────────────────────────────────
log "[1/6] Setting TCP BBR..."
echo "bbr" > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || true
echo "bbr" > /sys/module/tcp_bbr/parameters/enabled 2>/dev/null || true

# ── 2. I/O Scheduler: Maple → BFQ fallback ──────────
log "[2/6] Setting I/O scheduler..."
for dev in /sys/block/*/queue/scheduler; do
    dir=$(dirname "$dev")
    devname=$(basename "$dir")
    if grep -q "\[maple\]" "$dev" 2>/dev/null; then
        echo "maple" > "$dev" 2>/dev/null && log "  $devname: maple"
    elif grep -q "bfq" "$dev" 2>/dev/null; then
        echo "bfq" > "$dev" 2>/dev/null && log "  $devname: bfq"
    else
        echo "cfq" > "$dev" 2>/dev/null && log "  $devname: cfq"
    fi
done

# ── 3. ZRAM 5GB ───────────────────────────────────
log "[3/6] Configuring ZRAM..."
ZRAM_SIZE=$((5 * 1024 * 1024 * 1024))  # 5 GB
for zram in /sys/block/zram*; do
    if [ -f "$zram/disksize" ]; then
        echo "$ZRAM_SIZE" > "$zram/disksize" 2>/dev/null
        mkswap "${zram#/sys/block}" 2>/dev/null
        swapon "${zram#/sys/block}" 2>/dev/null
        log "  $zram: ${ZRAM_SIZE} bytes"
    fi
done

# ── 4. KSM ─────────────────────────────────────────
log "[4/6] Enabling KSM..."
echo "1" > /sys/kernel/mm/ksm/run 2>/dev/null || true
echo "1000" > /sys/kernel/mm/ksm/sleep_millisecs 2>/dev/null || true
log "  KSM enabled"

# ── 5. VM tuning ───────────────────────────────────
log "[5/6] VM tuning..."
echo "5" > /proc/sys/vm/dirty_background_ratio 2>/dev/null || true
echo "10" > /proc/sys/vm/dirty_ratio 2>/dev/null || true
echo "60" > /proc/sys/vm/dirty_expire_centisecs 2>/dev/null || true
echo "30" > /proc/sys/vm/dirty_writeback_centisecs 2>/dev/null || true
echo "50" > /proc/sys/vm/vfs_cache_pressure 2>/dev/null || true
echo "4096" > /proc/sys/vm/min_free_kbytes 2>/dev/null || true
echo "0" > /proc/sys/vm/swappiness 2>/dev/null || true
log "  VM params set"

# ── 6. Battery / Charging control init ──────────────
log "[6/6] Charging control..."
if [ -f /sys/class/power_supply/battery/charge_ctrl_mode ]; then
    echo "on" > /sys/class/power_supply/battery/charge_ctrl_mode 2>/dev/null
    echo "80" > /sys/class/power_supply/battery/charge_ctrl_limit 2>/dev/null
    log "  Charging control: on, limit=80%"
else
    log "  Charging control sysfs not found (ok on first boot)"
fi

log "[infinity_init] Post-flash init complete"
log "[infinity_init] Remove this log with: rm $ILOG"
