#!/system/bin/sh
##########################################################################################
# Infinity Kernel Init Script
# Applied at boot via init.d or service
# Device: Poco X3 Pro (vayu/bhima)
##########################################################################################

INFINITY_CONF="/data/adb/infinity_kernel/default.conf"
INFINITY_LOG="/data/adb/infinity_kernel/boot.log"

log_info() {
    echo "[$(date '+%H:%M:%S')] [Infinity] $1" >> "$INFINITY_LOG"
}

log_info "=== Infinity Kernel Boot Init ==="

# Wait for system to be ready
sleep 10

# ---- TCP Congestion Control ----
if [ -f "/proc/sys/net/ipv4/tcp_congestion_control" ]; then
    echo "bbr" > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null
    log_info "TCP: Set BBR congestion control"
fi

# ---- IO Scheduler ----
for cpu in /sys/block/*/queue/scheduler; do
    if [ -f "$cpu" ]; then
        echo "maple" > "$cpu" 2>/dev/null || \
        echo "bfq" > "$cpu" 2>/dev/null
    fi
done
log_info "IO: Set Maple/BFQ scheduler"

# ---- ZRAM Configuration ----
SWAPDEV=$(zramctl 2>/dev/null | head -1 | awk '{print $1}')
if [ -n "$SWAPDEV" ] && [ -b "$SWAPDEV" ]; then
    swapoff "$SWAPDEV" 2>/dev/null
    zramctl "$SWAPDEV" --algorithm lz4 --size 5G 2>/dev/null
    mkswap "$SWAPDEV" 2>/dev/null
    swapon "$SWAPDEV" 2>/dev/null
    log_info "ZRAM: Configured 5GB with LZ4"
fi

# ---- LRU Gen ----
if [ -f "/sys/kernel/mm/lru_gen/enabled" ]; then
    echo "1" > /sys/kernel/mm/lru_gen/enabled 2>/dev/null
    log_info "MM: MGLRU enabled"
fi

# ---- KSM (Kernel Same-page Merging) ----
if [ -f "/sys/kernel/mm/ksm/run" ]; then
    echo "1" > /sys/kernel/mm/ksm/run 2>/dev/null
    echo "1000" > /sys/kernel/mm/ksm/sleep_millisecs 2>/dev/null
    log_info "KSM: Enabled with 1000ms scan interval"
fi

# ---- Read Ahead ----
for blk in /sys/block/*/queue/read_ahead_kb; do
    if [ -f "$blk" ]; then
        echo "128" > "$blk" 2>/dev/null
    fi
done
log_info "IO: Read-ahead set to 128KB"

# ---- Virtual Memory ----
if [ -f "/proc/sys/vm/swappiness" ]; then
    echo "60" > /proc/sys/vm/swappiness 2>/dev/null
fi
if [ -f "/proc/sys/vm/vfs_cache_pressure" ]; then
    echo "50" > /proc/sys/vm/vfs_cache_pressure 2>/dev/null
fi
if [ -f "/proc/sys/vm/dirty_ratio" ]; then
    echo "15" > /proc/sys/vm/dirty_ratio 2>/dev/null
fi
if [ -f "/proc/sys/vm/dirty_background_ratio" ]; then
    echo "5" > /proc/sys/vm/dirty_background_ratio 2>/dev/null
fi
log_info "VM: Tuned swappiness/dirty ratios"

# ---- Charging Control Defaults ----
CHARGING_SYSFS=$(find /sys/devices/platform/soc/ -path "*/infinity_charging" -type d 2>/dev/null | head -1)
if [ -n "$CHARGING_SYSFS" ]; then
    # Set default charge current
    if [ -f "$CHARGING_SYSFS/charge_current" ]; then
        echo "3000" > "$CHARGING_SYSFS/charge_current" 2>/dev/null
    fi
    # Set default thermal thresholds
    if [ -f "$CHARGING_SYSFS/cooldown_threshold" ]; then
        echo "45" > "$CHARGING_SYSFS/cooldown_threshold" 2>/dev/null
    fi
    if [ -f "$CHARGING_SYSFS/resume_threshold" ]; then
        echo "40" > "$CHARGING_SYSFS/resume_threshold" 2>/dev/null
    fi
    # Ensure bypass is off at boot
    if [ -f "$CHARGING_SYSFS/bypass_enable" ]; then
        echo "0" > "$CHARGING_SYSFS/bypass_enable" 2>/dev/null
    fi
    if [ -f "$CHARGING_SYSFS/gaming_mode" ]; then
        echo "0" > "$CHARGING_SYSFS/gaming_mode" 2>/dev/null
    fi
    log_info "Charging: Defaults applied"
fi

# ---- Input/Touch Boost ----
if [ -f "/sys/module/cpu_boost/parameters/input_boost" ]; then
    echo "1" > /sys/module/cpu_boost/parameters/input_boost 2>/dev/null
    log_info "CPU: Input boost enabled"
fi

# ---- GPU Boost ----
if [ -d "/sys/class/kgsl/kgsl-3d0" ]; then
    echo "1" > /sys/class/kgsl/kgsl-3d0/max_gpuclk 2>/dev/null
    log_info "GPU: Max clock configured"
fi

log_info "=== Infinity Kernel Init Complete ==="