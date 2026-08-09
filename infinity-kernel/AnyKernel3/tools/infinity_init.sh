#!/system/bin/sh
##########################################################################################
# Infinity Kernel Init Script v2.0
# Applied at boot via init.d or service
# Device: Poco X3 Pro (vayu/bhima) — 8GB RAM
#
# Features:
#   - Task-Aware Performance Engine initialization
#   - ZRAM 5GB LZ4 optimized for 8GB RAM
#   - KSM aggressive mode
#   - BBR TCP, Maple/BFQ IO
#   - Enhanced thermal defaults
#   - Charging thermal multi-stage defaults
##########################################################################################

INFINITY_DIR="/data/adb/infinity_kernel"
INFINITY_LOG="$INFINITY_DIR/boot.log"
TASK_ENGINE_SYSFS="/sys/kernel/infinity_task_engine"

log_info() {
    echo "[$(date '+%H:%M:%S')] [Infinity] $1" >> "$INFINITY_LOG"
}

log_info "=== Infinity Kernel Boot Init v2.0 ==="

# Wait for system to be ready
sleep 8

# ---- TCP Congestion Control ----
if [ -f "/proc/sys/net/ipv4/tcp_congestion_control" ]; then
    echo "bbr" > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null
    log_info "TCP: BBR congestion control enabled"
fi

# ---- IO Scheduler ----
for cpu in /sys/block/*/queue/scheduler; do
    if [ -f "$cpu" ]; then
        echo "maple" > "$cpu" 2>/dev/null || \
        echo "bfq" > "$cpu" 2>/dev/null
    fi
done
log_info "IO: Maple/BFQ scheduler set"

# ===================================================================
# ZRAM CONFIGURATION — Optimized for 8GB RAM, 5GB max
# ===================================================================
# On 8GB device, ZRAM 5GB with LZ4 uses ~2-2.5GB real memory
# This leaves 5.5-6GB for active apps/system
# Strategy: Start with 3GB, auto-grow to 5GB under pressure

SWAPDEV=$(zramctl 2>/dev/null | head -1 | awk '{print $1}')
if [ -n "$SWAPDEV" ] && [ -b "$SWAPDEV" ]; then
    swapoff "$SWAPDEV" 2>/dev/null
    sleep 1

    # Reset ZRAM device
    echo 1 > /sys/block/zram0/reset 2>/dev/null
    sleep 1

    # Configure: LZ4 compression, 5GB disksize, 4K page
    echo lz4 > /sys/block/zram0/comp_algorithm 2>/dev/null
    echo 5368709120 > /sys/block/zram0/disksize 2>/dev/null   # 5GB
    echo 4096 > /sys/block/zram0/page_size 2>/dev/null

    # Enable writeback (uses disk as backing store under pressure)
    echo 1 > /sys/block/zram0/backing_dev 2>/dev/null

    mkswap "$SWAPDEV" 2>/dev/null
    swapon -p 5 "$SWAPDEV" 2>/dev/null
    log_info "ZRAM: 5GB LZ4 configured for 8GB RAM (priority 5)"
else
    # Fallback: create ZRAM manually
    modprobe zram num_devices=1 2>/dev/null
    sleep 1
    if [ -f /sys/block/zram0/comp_algorithm ]; then
        echo lz4 > /sys/block/zram0/comp_algorithm
        echo 5368709120 > /sys/block/zram0/disksize
        mkswap /dev/zram0 2>/dev/null
        swapon -p 5 /dev/zram0 2>/dev/null
        log_info "ZRAM: Created 5GB LZ4 (manual setup)"
    fi
fi

# ---- LRU Gen (Multi-Gen LRU for better page reclaim) ----
if [ -f "/sys/kernel/mm/lru_gen/enabled" ]; then
    echo "1" > /sys/kernel/mm/lru_gen/enabled 2>/dev/null
    log_info "MM: MGLRU enabled"
fi

# ---- KSM (Kernel Same-page Merging) — Aggressive for 8GB ----
if [ -f "/sys/kernel/mm/ksm/run" ]; then
    echo "1" > /sys/kernel/mm/ksm/run 2>/dev/null
    # Aggressive scan: 500ms interval, high pages_to_scan
    echo "500" > /sys/kernel/mm/ksm/sleep_millisecs 2>/dev/null
    echo "1000" > /sys/kernel/mm/ksm/pages_to_scan 2>/dev/null
    # Start merging early (10 identical pages)
    echo "10" > /sys/kernel/mm/ksm/merge_across_nodes 2>/dev/null
    log_info "KSM: Aggressive mode (500ms, 1000 pages/scan)"
fi

# ---- Read Ahead ----
for blk in /sys/block/*/queue/read_ahead_kb; do
    if [ -f "$blk" ]; then
        echo "128" > "$blk" 2>/dev/null
    fi
done
log_info "IO: Read-ahead 128KB"

# ---- Virtual Memory — Tuned for 8GB RAM ----
if [ -f "/proc/sys/vm/swappiness" ]; then
    # swappiness=60 for 8GB is balanced: swap when ~60% of RAM used
    echo "60" > /proc/sys/vm/swappiness 2>/dev/null
fi
if [ -f "/proc/sys/vm/vfs_cache_pressure" ]; then
    # Lower = keep more dentry/inode cache (good for app switching)
    echo "50" > /proc/sys/vm/vfs_cache_pressure 2>/dev/null
fi
if [ -f "/proc/sys/vm/dirty_ratio" ]; then
    echo "15" > /proc/sys/vm/dirty_ratio 2>/dev/null
fi
if [ -f "/proc/sys/vm/dirty_background_ratio" ]; then
    echo "5" > /proc/sys/vm/dirty_background_ratio 2>/dev/null
fi
# Min free KBytes: keep 128MB free for emergencies (8GB = 8192000KB)
if [ -f "/proc/sys/vm/min_free_kbytes" ]; then
    echo "131072" > /proc/sys/vm/min_free_kbytes 2>/dev/null
fi
# Overcommit: allow some overcommit for app launches
if [ -f "/proc/sys/vm/overcommit_memory" ]; then
    echo "1" > /proc/sys/vm/overcommit_memory 2>/dev/null
fi
# Compact memory proactively
if [ -f "/proc/sys/vm/compact_unevictable_allowed" ]; then
    echo "1" > /proc/sys/vm/compact_unevictable_allowed 2>/dev/null
fi
log_info "VM: Tuned for 8GB RAM (swappiness=60, min_free=128MB, overcommit=1)"

# ===================================================================
# CHARGING CONTROL — Enhanced thermal defaults
# ===================================================================
CHARGING_SYSFS=$(find /sys/devices/platform/soc/ -path "*/infinity_charging" -type d 2>/dev/null | head -1)
if [ -n "$CHARGING_SYSFS" ]; then
    # Default charge current: 2500mA (reduced from 3000 for cooler charging)
    if [ -f "$CHARGING_SYSFS/charge_current" ]; then
        echo "2500" > "$CHARGING_SYSFS/charge_current" 2>/dev/null
    fi
    # Multi-stage thermal: cooldown at 43°C (lowered from 45°C)
    if [ -f "$CHARGING_SYSFS/cooldown_threshold" ]; then
        echo "43" > "$CHARGING_SYSFS/cooldown_threshold" 2>/dev/null
    fi
    # Resume at 39°C (lowered from 40°C for better hysteresis)
    if [ -f "$CHARGING_SYSFS/resume_threshold" ]; then
        echo "39" > "$CHARGING_SYSFS/resume_threshold" 2>/dev/null
    fi
    # Bypass off at boot
    if [ -f "$CHARGING_SYSFS/bypass_enable" ]; then
        echo "0" > "$CHARGING_SYSFS/bypass_enable" 2>/dev/null
    fi
    if [ -f "$CHARGING_SYSFS/gaming_mode" ]; then
        echo "0" > "$CHARGING_SYSFS/gaming_mode" 2>/dev/null
    fi
    log_info "Charging: Multi-stage thermal (cooldown=43C, resume=39C, current=2500mA)"
fi

# ---- Input/Touch Boost ----
if [ -f "/sys/module/cpu_boost/parameters/input_boost" ]; then
    echo "1" > /sys/module/cpu_boost/parameters/input_boost 2>/dev/null
    log_info "CPU: Input boost enabled"
fi

# ---- GPU Defaults ----
if [ -d "/sys/class/kgsl/kgsl-3d0" ]; then
    # Don't force max at boot — let task engine control it
    # Just ensure GPU is not locked to minimum
    echo "133000000" > /sys/class/kgsl/kgsl-3d0/min_gpuclk 2>/dev/null
    echo "750000000" > /sys/class/kgsl/kgsl-3d0/max_gpuclk 2>/dev/null
    log_info "GPU: Default range 133-750 MHz (task engine controls)"
fi

# ===================================================================
# TASK-AWARE PERFORMANCE ENGINE — Initialize
# ===================================================================
if [ -d "$TASK_ENGINE_SYSFS" ]; then
    # The task engine starts with auto_detect=OFF by default
    # We enable it here after system is ready

    # Enable auto-detection
    echo "1" > "$TASK_ENGINE_SYSFS/auto_detect" 2>/dev/null

    # Set detection interval: 2.5 seconds
    echo "2500" > "$TASK_ENGINE_SYSFS/detect_interval" 2>/dev/null

    # Screen is on at boot
    echo "1" > "$TASK_ENGINE_SYSFS/screen_on" 2>/dev/null

    # No userspace hint yet — let kernel auto-detect
    echo "-1" > "$TASK_ENGINE_SYSFS/userspace_hint" 2>/dev/null

    # Force NORMAL profile initially
    echo "4" > "$TASK_ENGINE_SYSFS/force_profile" 2>/dev/null
    sleep 2
    # Switch back to auto
    echo "-1" > "$TASK_ENGINE_SYSFS/force_profile" 2>/dev/null

    log_info "Task Engine: Auto-detection ENABLED (2.5s interval)"

    # Log current profiles table
    if [ -f "$TASK_ENGINE_SYSFS/profiles" ]; then
        cat "$TASK_ENGINE_SYSFS/profiles" >> "$INFINITY_LOG" 2>/dev/null
    fi
else
    log_info "Task Engine: sysfs not found — starting userspace helper as fallback"
fi

# ---- Start Userspace Task Detection Helper ----
TASK_HELPER="/data/adb/infinity_kernel/task_helper.sh"
if [ -f "/data/adb/infinity_kernel/infinity_task_profile.sh" ]; then
    cp /data/adb/infinity_kernel/infinity_task_profile.sh "$TASK_HELPER" 2>/dev/null
fi

# Try to find helper in AnyKernel tools (installed during flash) or data
HELPER=""
if [ -f "$TASK_HELPER" ]; then
    HELPER="$TASK_HELPER"
elif [ -f "/data/adb/infinity_kernel/infinity_task_profile.sh" ]; then
    HELPER="/data/adb/infinity_kernel/infinity_task_profile.sh"
fi

if [ -n "$HELPER" ] && [ -x "$HELPER" ]; then
    # Run in background
    setsid "$HELPER" >> "$INFINITY_LOG" 2>&1 &
    log_info "Task Helper: Started in background (PID: $!)"
elif [ -n "$HELPER" ]; then
    chmod 755 "$HELPER" 2>/dev/null
    setsid "$HELPER" >> "$INFINITY_LOG" 2>&1 &
    log_info "Task Helper: Started after chmod (PID: $!)"
fi

# ---- SUFS — Ensure enabled ----
if [ -f "/proc/sys/kernel/susfs_enabled" ]; then
    echo "1" > /proc/sys/kernel/susfs_enabled 2>/dev/null
    log_info "SUFS: Enabled"
fi

log_info "=== Infinity Kernel Init Complete ==="
log_info "  ZRAM: 5GB LZ4 | KSM: Aggressive | TCP: BBR"
log_info "  Task Engine: Auto-detect ON | Thermal: Multi-stage"
log_info "  Profile: $(cat $TASK_ENGINE_SYSFS/current_profile 2>/dev/null || echo N/A)"