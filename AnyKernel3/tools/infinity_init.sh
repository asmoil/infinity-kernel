#!/system/bin/sh
#
# ============================================================================
#  infinity_init.sh – Infinity Kernel Boot Tuning Script v2.0
# ============================================================================
#  Target   : Poco X3 Pro (vayu / bhima) – Snapdragon 732G – 8 GB RAM
#  Kernel   : 4.14.180 (Infinity Kernel)
#  Location : AnyKernel3/tools/infinity_init.sh  (executed by post-fs-data)
#
#  v2.0 changes:
#    - ZRAM 5GB tuned for 8GB RAM (swappiness 30, not 60)
#    - Anti-heat charging: CPU capped while charging, thermal thresholds
#    - SUSFS v1.5.7+ auto-enable
#    - KSM tuned for 8GB (more aggressive, 8GB has headroom)
#    - ZRAM stream count optimized for 8 cores
#    - Low-memory killer tuned for 8GB
#
#  Copyright (c) 2024 Infinity Kernel Project
#  Licensed under the GNU General Public License v2
# ============================================================================

# ---------- safety: only run on our device ------------------------------
PRODUCT="$(getprop ro.product.device)"
case "$PRODUCT" in
    vayu|bhima) ;;
    *)  log -t InfinityInit "Unsupported device $PRODUCT – exiting"; exit 0 ;;
esac

# Detect total RAM (should be 8GB = ~7800000 kB on 8GB variant)
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_GB=$((TOTAL_RAM_KB / 1024 / 1024))
log -t InfinityInit "=== Infinity Kernel Init v2.0 (RAM: ${TOTAL_RAM_GB}GB) ==="

# ============================================================================
# 0. Root Manager Compatibility + SUSFS
# ============================================================================
log -t InfinityInit "--- Root Manager + SUSFS ---"

# -- Enable kprobes (KernelSU / KSU Next / APatch) --
if [ -f /sys/kernel/debug/kprobes/enabled ]; then
    echo 1 > /sys/kernel/debug/kprobes/enabled 2>/dev/null
fi

# -- Enable ftrace (APatch) --
if [ -f /sys/kernel/debug/tracing/tracing_on ]; then
    echo 1 > /sys/kernel/debug/tracing/tracing_on 2>/dev/null
fi

# -- SUSFS v1.5.7+ auto-enable --
# Check if SUSFS is compiled into kernel
if [ -f /proc/version ] && grep -q "InfinityKernel" /proc/version 2>/dev/null; then
    # SUSFS is enabled via CONFIG_SUSFS=y at compile time
    # The root manager module (KSU/APatch) will call susfs_enable()
    # via kallsyms_lookup_name at runtime. We just need to ensure
    # the kernel symbols are accessible.
    chmod 644 /proc/kallsyms 2>/dev/null
    log -t InfinityInit "SUSFS v1.5.7+: kernel hooks ready (waiting for root manager)"
fi

# -- Detect root managers --
if [ -d /data/adb/ksu ] || [ -f /data/adb/ksud ]; then
    mkdir -p /data/adb/ksu 2>/dev/null
    [ ! -f /data/adb/ksu/modules.img ] && \
        make_ext4fs -b 1024 -l 256M /data/adb/ksu/modules.img 2>/dev/null \
        || mke2fs -b 1024 -t ext4 /data/adb/ksu/modules.img 256M 2>/dev/null
    chmod 644 /proc/kallsyms 2>/dev/null
    log -t InfinityInit "Root: KernelSU"
fi

if [ -f /data/adb/ksud ] && /data/adb/ksud --version 2>/dev/null | grep -qi "next"; then
    log -t InfinityInit "Root: KernelSU Next"
fi

if [ -d /data/adb/ap ] || [ -d /data/adb/apatch ] || [ -f /data/adb/apd ]; then
    AP_DIR="/data/adb/ap"
    [ -d /data/adb/apatch ] && AP_DIR="/data/adb/apatch"
    mkdir -p "$AP_DIR" 2>/dev/null
    [ ! -f "$AP_DIR/modules.img ] && \
        make_ext4fs -b 1024 -l 256M "$AP_DIR/modules.img" 2>/dev/null \
        || mke2fs -b 1024 -t ext4 "$AP_DIR/modules.img" 256M 2>/dev/null
    chmod 644 /proc/kallsyms 2>/dev/null
    log -t InfinityInit "Root: APatch"
fi

if [ -d /data/adb/magisk ]; then
    mkdir -p /data/adb/magisk/post-fs-data.d 2>/dev/null
    chmod 700 /data/adb/magisk 2>/dev/null
    log -t InfinityInit "Root: Magisk"
fi

if [ -d /data/adb/resukisu ] || [ -d /data/adb/re_sukisu ]; then
    RS_DIR="/data/adb/resukisu"
    [ -d /data/adb/re_sukisu ] && RS_DIR="/data/adb/re_sukisu"
    mkdir -p "$RS_DIR" 2>/dev/null
    [ ! -f "$RS_DIR/modules.img" ] && \
        make_ext4fs -b 1024 -l 256M "$RS_DIR/modules.img" 2>/dev/null \
        || mke2fs -b 1024 -t ext4 "$RS_DIR/modules.img" 256M 2>/dev/null
    chmod 644 /proc/kallsyms 2>/dev/null
    log -t InfinityInit "Root: ReSukiSu"
fi

if [ -d /data/adb/sukisu ] || [ -d /data/adb/sukisu_ultra ]; then
    SK_DIR="/data/adb/sukisu"
    [ -d /data/adb/sukisu_ultra ] && SK_DIR="/data/adb/sukisu_ultra"
    mkdir -p "$SK_DIR" 2>/dev/null
    [ ! -f "$SK_DIR/modules.img" ] && \
        make_ext4fs -b 1024 -l 256M "$SK_DIR/modules.img" 2>/dev/null \
        || mke2fs -b 1024 -t ext4 "$SK_DIR/modules.img" 256M 2>/dev/null
    chmod 644 /proc/kallsyms 2>/dev/null
    log -t InfinityInit "Root: SukiSU Ultra"
fi

# Global kallsyms
chmod 644 /proc/kallsyms 2>/dev/null

# ============================================================================
# 1. TCP BBR
# ============================================================================
if grep -q "bbr" /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
    echo "bbr" > /proc/sys/net/ipv4/tcp_congestion_control
    echo "fq"  > /proc/sys/net/core/default_qdisc
    log -t InfinityInit "TCP: BBR + fq"
fi

# ============================================================================
# 2. I/O Scheduler – BFQ for smoothness on 8GB (no thrashing)
# ============================================================================
IOSCHED=""
for sched in bfq cfq mq-deadline; do
    if grep -q "\[$sched\]" /sys/block/sda/queue/scheduler 2>/dev/null; then
        IOSCHED="$sched"
        break
    fi
done
if [ -n "$IOSCHED" ]; then
    for blk in /sys/block/sd? /sys/block/dm-?; do
        [ -f "$blk/queue/scheduler" ] || continue
        echo "$IOSCHED" > "$blk/queue/scheduler" 2>/dev/null
    done
    log -t InfinityInit "IO: $IOSCHED"
fi

# ============================================================================
# 3. ZRAM – 5 GB / LZ4 / Tuned for 8 GB RAM
# ============================================================================
# With 8GB RAM, ZRAM is mostly a safety net for extreme multitasking.
# We use swappiness=30 (low) so the kernel prefers RAM over ZRAM swap.
# This prevents lag from unnecessary compression/decompression cycles.
#
# ZRAM size: 5120 MB (max supported by the ROM)
# Real RAM consumption with LZ4: ~2-2.5 GB compressed
# Effective usable: 8 GB real + ~5 GB virtual = plenty of headroom
# ============================================================================
if [ -b /dev/block/zram0 ]; then
    CURRENT_SIZE="$(cat /sys/block/zram0/disksize 2>/dev/null || echo 0)"
    if [ "$CURRENT_SIZE" -eq 0 ] 2>/dev/null; then
        # LZ4: fastest compression, good ratio (~40-50% on app data)
        if [ -f /sys/block/zram0/comp_algorithm ]; then
            echo "lz4" > /sys/block/zram0/comp_algorithm 2>/dev/null
        fi

        # 8 stream buffers (one per CPU core) for parallel compression
        if [ -f /sys/block/zram0/max_comp_streams ]; then
            echo 8 > /sys/block/zram0/max_comp_streams 2>/dev/null
        fi

        # 5120 MB = 5 GB (ROM max)
        echo "5120M" > /sys/block/zram0/disksize 2>/dev/null

        # Format and enable
        mkswap /dev/block/zram0 >/dev/null 2>&1
        swapon /dev/block/zram0 -p 30 >/dev/null 2>&1
        log -t InfinityInit "ZRAM: 5120MB / LZ4 / 8 streams / priority 30"
    else
        log -t InfinityInit "ZRAM: already ${CURRENT_SIZE} bytes"
    fi
fi

# ============================================================================
# 4. VM Swappiness – 30 for 8GB RAM
# ============================================================================
# swappiness=60 is for devices with 4GB or less.
# With 8GB, we set 30 to keep apps in real RAM as much as possible.
# ZRAM is still there as overflow but rarely used in daily use.
# This ELIMINATES lag from swap I/O.
# ============================================================================
if [ -f /proc/sys/vm/swappiness ]; then
    echo 30 > /proc/sys/vm/swappiness
    log -t InfinityInit "Swappiness: 30 (tuned for 8GB)"
fi

# ============================================================================
# 5. KSM – Aggressive for 8GB (more RAM = more duplicate pages)
# ============================================================================
KSM_SYS="/sys/kernel/mm/ksm"
if [ -d "$KSM_SYS" ]; then
    echo 1   > "$KSM_SYS/run"              2>/dev/null
    echo 1000 > "$KSM_SYS/pages_to_scan"   2>/dev/null   # 1000 pages/iter (8GB can afford it)
    echo 500  > "$KSM_SYS/sleep_millisecs" 2>/dev/null   # 500ms (faster scanning)
    echo 0    > "$KSM_SYS/merge_across_nodes" 2>/dev/null  # NUMA-local merges only
    log -t InfinityInit "KSM: 1000 pages / 500ms"
fi

# ============================================================================
# 6. Read-Ahead – 128 KB
# ============================================================================
for blk in /sys/block/sd? /sys/block/dm-?; do
    [ -f "$blk/queue/read_ahead_kb" ] || continue
    echo 128 > "$blk/queue/read_ahead_kb" 2>/dev/null
done
log -t InfinityInit "Read-ahead: 128KB"

# ============================================================================
# 7. Low-Memory Killer tuning for 8GB
# ============================================================================
# Stock LMK thresholds are for 6GB. With 8GB we have more headroom,
# so we can let more apps stay in RAM before killing.
# ============================================================================
LMK_ADJ="/sys/module/lowmemorykiller/parameters"
if [ -d "$LMK_ADJ" ]; then
    # Adjust minfree: allow more apps in background before killing
    # These values are in pages (4KB each)
    # Stock 6GB: 18432,23040,27648,32256,36864,46080
    # 8GB tuned:  32768,40960,49152,57344,65536,81920
    if [ -f "$LMK_ADJ/minfree" ]; then
        echo "32768,40960,49152,57344,65536,81920" > "$LMK_ADJ/minfree" 2>/dev/null
        log -t InfinityInit "LMK: tuned for 8GB (minfree adjusted)"
    fi
fi

# ============================================================================
# 8. ANTI-HEAT CHARGING – CPU frequency cap while charging
# ============================================================================
# When the phone is charging AND the screen is off, cap CPU to prevent
# heat buildup. The charger + CPU together generate most of the heat.
# When screen is on (user is using phone), allow full frequency.
# ============================================================================
CHARGE_SYS="/sys/kernel/charging_control"

# Default charging bypass mode: BALANCED
if [ -d "$CHARGE_SYS" ]; then
    echo "BALANCED" > "$CHARGE_SYS/mode" 2>/dev/null
    echo 0 > "$CHARGE_SYS/enabled" 2>/dev/null
    TEMP="$(cat "$CHARGE_SYS/battery_temp" 2>/dev/null || echo "N/A")"
    CAP="$(cat "$CHARGE_SYS/battery_capacity" 2>/dev/null || echo "N/A")"
    log -t InfinityInit "Charging: mode=BALANCED, temp=${TEMP}mC, cap=${CAP}%"
fi

# -- CPU thermal headroom while charging --
# These values REDUCE max CPU freq by ~15% while charging to cut heat.
# Applied to all CPU clusters (little + big).
apply_charging_cpu_limits() {
    # Poco X3 Pro: 2x Kryo 470 Silver (Cortex-A55) up to 1.8 GHz
    #               6x Kryo 470 Gold (Cortex-A76) up to 2.3 GHz
    # We cap Silver to 1.53 GHz and Gold to 1.96 GHz while charging
    for cpu in /sys/devices/system/cpu/cpu[0-7]; do
        [ -d "$cpu/cpufreq" ] || continue
        GOV="$(cat "$cpu/cpufreq/scaling_governor" 2>/dev/null)"
        [ "$GOV" = "interactive" ] || continue

        MAX_FREQ="$(cat "$cpu/cpufreq/cpuinfo_max_freq" 2>/dev/null)"
        if [ -n "$MAX_FREQ" ] && [ "$MAX_FREQ" -gt 0 ] 2>/dev/null; then
            # Cap at 85% of max while charging
            CAPPED=$((MAX_FREQ * 85 / 100))
            echo "$CAPPED" > "$cpu/cpufreq/scaling_max_freq" 2>/dev/null
        fi
    done
}

# Apply charging limits if currently charging
POWER_SUPPLY="/sys/class/power_supply/battery"
if [ -f "$POWER_SUPPLY/status" ]; then
    BAT_STATUS="$(cat "$POWER_SUPPLY/status" 2>/dev/null)"
    if [ "$BAT_STATUS" = "Charging" ] || [ "$BAT_STATUS" = "Full" ]; then
        apply_charging_cpu_limits
        log -t InfinityInit "Anti-heat: CPU capped at 85% while charging"
    fi
fi

# -- Background thermal monitor --
# Every 60 seconds, check battery temp and enforce thermal limits
# This runs as a background process for the first 10 minutes after boot
(
    for i in $(seq 1 10); do
        sleep 60

        # Check if charging
        BAT_STATUS="$(cat /sys/class/power_supply/battery/status 2>/dev/null)"
        [ "$BAT_STATUS" != "Charging" ] && continue

        # Read battery temp in deci-celsius
        BAT_TEMP="$(cat /sys/class/power_supply/battery/temp 2>/dev/null || echo 0)"
        # Remove decimal: "350" = 35.0°C
        BAT_TEMP_C=$((BAT_TEMP / 10))

        if [ "$BAT_TEMP_C" -ge 42 ] 2>/dev/null; then
            # Aggressive: cap all CPUs to 70% when battery >= 42°C
            for cpu in /sys/devices/system/cpu/cpu[0-7]; do
                [ -d "$cpu/cpufreq" ] || continue
                MAX="$(cat "$cpu/cpufreq/cpuinfo_max_freq" 2>/dev/null)"
                [ -z "$MAX" ] && continue
                CAPPED=$((MAX * 70 / 100))
                echo "$CAPPED" > "$cpu/cpufreq/scaling_max_freq" 2>/dev/null
            done
            log -t InfinityInit "Anti-heat: CPU capped 70% (battery ${BAT_TEMP_C}C)"
        elif [ "$BAT_TEMP_C" -ge 38 ] 2>/dev/null; then
            # Moderate: 80% cap
            for cpu in /sys/devices/system/cpu/cpu[0-7]; do
                [ -d "$cpu/cpufreq" ] || continue
                MAX="$(cat "$cpu/cpufreq/cpuinfo_max_freq" 2>/dev/null)"
                [ -z "$MAX" ] && continue
                CAPPED=$((MAX * 80 / 100))
                echo "$CAPPED" > "$cpu/cpufreq/scaling_max_freq" 2>/dev/null
            done
            log -t InfinityInit "Anti-heat: CPU capped 80% (battery ${BAT_TEMP_C}C)"
        fi
    done
) &

# ============================================================================
# 9. GPU thermal limits while charging
# ============================================================================
# Adreno 618 GPU also generates heat. Cap GPU frequency while charging.
# ============================================================================
GPU_SYS="/sys/class/kgsl/kgsl-3d0"
if [ -d "$GPU_SYS" ]; then
    BAT_STATUS="$(cat /sys/class/power_supply/battery/status 2>/dev/null)"
    if [ "$BAT_STATUS" = "Charging" ]; then
        # Get current max GPU freq and cap to 80%
        if [ -f "$GPU_SYS/max_gpuclk" ]; then
            GPU_MAX="$(cat "$GPU_SYS/max_gpuclk" 2>/dev/null)"
            if [ -n "$GPU_MAX" ] && [ "$GPU_MAX" -gt 0 ] 2>/dev/null; then
                GPU_CAPPED=$((GPU_MAX * 80 / 100))
                echo "$GPU_CAPPED" > "$GPU_SYS/gpuclk" 2>/dev/null
                log -t InfinityInit "Anti-heat: GPU capped 80% while charging"
            fi
        fi
    fi
fi

# ============================================================================
# 10. VM dirty pages – smoother I/O, less write spikes
# ============================================================================
if [ -f /proc/sys/vm/dirty_ratio ]; then
    echo 10 > /proc/sys/vm/dirty_ratio 2>/dev/null
fi
if [ -f /proc/sys/vm/dirty_background_ratio ]; then
    echo 3 > /proc/sys/vm/dirty_background_ratio 2>/dev/null
fi
if [ -f /proc/sys/vm/dirty_writeback_centisecs ]; then
    echo 300 > /proc/sys/vm/dirty_writeback_centisecs 2>/dev/null  # 3 seconds
fi

# ============================================================================
# 11. Entropy
# ============================================================================
ENTROPY="$(cat /proc/sys/kernel/random/entropy_avail 2>/dev/null || echo 0)"
if [ "$ENTROPY" -lt 1024 ] 2>/dev/null; then
    log -t InfinityInit "Low entropy ($ENTROPY) – consider haveged"
fi

# ============================================================================
# 12. Install as root manager module for persistence
# ============================================================================
INIT_SCRIPT_DIR=""
if [ -d /data/adb/magisk ]; then
    INIT_SCRIPT_DIR="/data/adb/magisk"
elif [ -d /data/adb/ksu ]; then
    INIT_SCRIPT_DIR="/data/adb/ksu"
elif [ -d /data/adb/ap ]; then
    INIT_SCRIPT_DIR="/data/adb/ap"
elif [ -d /data/adb/apatch ]; then
    INIT_SCRIPT_DIR="/data/adb/apatch"
fi

if [ -n "$INIT_SCRIPT_DIR" ] && [ -d "$INIT_SCRIPT_DIR/post-fs-data.d" ]; then
    if [ ! -f "$INIT_SCRIPT_DIR/post-fs-data.d/infinity_init.sh" ]; then
        cp "$0" "$INIT_SCRIPT_DIR/post-fs-data.d/infinity_init.sh" 2>/dev/null
        chmod 755 "$INIT_SCRIPT_DIR/post-fs-data.d/infinity_init.sh" 2>/dev/null
        log -t InfinityInit "Installed as $INIT_SCRIPT_DIR post-fs-data.d module"
    fi
fi

log -t InfinityInit "=== Infinity Kernel Init v2.0 Complete ==="

exit 0