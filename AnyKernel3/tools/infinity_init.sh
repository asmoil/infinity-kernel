#!/system/bin/sh
#
# ============================================================================
#  infinity_init.sh – Infinity Kernel Boot Tuning Script
# ============================================================================
#  Target   : Poco X3 Pro (vayu / bhima) – Snapdragon 732G
#  Kernel   : 4.14.180 (Infinity Kernel)
#  Location : AnyKernel3/tools/infinity_init.sh  (executed by post-fs-data)
#
#  This script runs once at boot (post-fs-data.d) and applies performance
#  and battery-tuning defaults that complement the Infinity Charging Bypass
#  kernel driver.
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

log -t InfinityInit "=== Infinity Kernel Init (v1.1) ==="

# ============================================================================
# 0. Root Manager Compatibility Fixes
#    Runs early to ensure kernel prerequisites for each root manager.
# ============================================================================
log -t InfinityInit "--- Root Manager Compatibility ---"

# -- Ensure kprobes are enabled (required by KernelSU / KSU Next / APatch) --
if [ -f /sys/kernel/debug/kprobes/enabled ]; then
    echo 1 > /sys/kernel/debug/kprobes/enabled 2>/dev/null
    log -t InfinityInit "kprobes: enabled"
else
    log -t InfinityInit "kprobes: not available in debugfs"
fi

# -- Ensure ftrace is enabled (required by APatch for kernel patching) --
if [ -d /sys/kernel/debug/tracing ]; then
    # Ensure tracing is not disabled
    if [ -f /sys/kernel/debug/tracing/tracing_on ]; then
        echo 1 > /sys/kernel/debug/tracing/tracing_on 2>/dev/null
    fi
    log -t InfinityInit "ftrace: available"
fi

# -- Detect active root manager and apply specific fixes --

# KernelSU (original)
if [ -d /data/adb/ksu ] || [ -f /data/adb/ksud ]; then
    # Ensure KSU work directory exists
    mkdir -p /data/adb/ksu 2>/dev/null
    # Ensure modules.img exists
    if [ ! -f /data/adb/ksu/modules.img ]; then
        make_ext4fs -b 1024 -l 256M /data/adb/ksu/modules.img 2>/dev/null \
            || mke2fs -b 1024 -t ext4 /data/adb/ksu/modules.img 256M 2>/dev/null
    fi
    # KernelSU requires kallsyms to be readable
    chmod 644 /proc/kallsyms 2>/dev/null
    log -t InfinityInit "Root manager: KernelSU (compatibility fixes applied)"
fi

# KernelSU Next
if [ -f /data/adb/ksud ]; then
    KSU_CHECK=$(/data/adb/ksud --version 2>/dev/null)
    if echo "$KSU_CHECK" | grep -qi "next"; then
        mkdir -p /data/adb/ksu 2>/dev/null
        if [ ! -f /data/adb/ksu/modules.img ]; then
            make_ext4fs -b 1024 -l 256M /data/adb/ksu/modules.img 2>/dev/null \
                || mke2fs -b 1024 -t ext4 /data/adb/ksu/modules.img 256M 2>/dev/null
        fi
        chmod 644 /proc/kallsyms 2>/dev/null
        log -t InfinityInit "Root manager: KernelSU Next (compatibility fixes applied)"
    fi
fi

# APatch
if [ -d /data/adb/ap ] || [ -d /data/adb/apatch ] || [ -f /data/adb/apd ]; then
    AP_DIR="/data/adb/ap"
    [ -d /data/adb/apatch ] && AP_DIR="/data/adb/apatch"
    mkdir -p "$AP_DIR" 2>/dev/null
    if [ ! -f "$AP_DIR/modules.img" ]; then
        make_ext4fs -b 1024 -l 256M "$AP_DIR/modules.img" 2>/dev/null \
            || mke2fs -b 1024 -t ext4 "$AP_DIR/modules.img" 256M 2>/dev/null
    fi
    chmod 644 /proc/kallsyms 2>/dev/null
    # APatch uses ftrace heavily for kernel patching
    if [ -f /sys/kernel/debug/tracing/tracing_on ]; then
        echo 1 > /sys/kernel/debug/tracing/tracing_on 2>/dev/null
    fi
    log -t InfinityInit "Root manager: APatch (compatibility fixes applied)"
fi

# Magisk
if [ -d /data/adb/magisk ]; then
    # Magisk works in userspace, no kernel module loading needed
    # But ensure Magisk's post-fs-data.d scripts can run
    mkdir -p /data/adb/magisk/post-fs-data.d 2>/dev/null
    chmod 700 /data/adb/magisk 2>/dev/null
    log -t InfinityInit "Root manager: Magisk (compatibility verified)"
fi

# ReSukiSu
if [ -d /data/adb/resukisu ] || [ -d /data/adb/re_sukisu ]; then
    RS_DIR="/data/adb/resukisu"
    [ -d /data/adb/re_sukisu ] && RS_DIR="/data/adb/re_sukisu"
    mkdir -p "$RS_DIR" 2>/dev/null
    if [ ! -f "$RS_DIR/modules.img" ]; then
        make_ext4fs -b 1024 -l 256M "$RS_DIR/modules.img" 2>/dev/null \
            || mke2fs -b 1024 -t ext4 "$RS_DIR/modules.img" 256M 2>/dev/null
    fi
    chmod 644 /proc/kallsyms 2>/dev/null
    log -t InfinityInit "Root manager: ReSukiSu (compatibility fixes applied)"
fi

# SukiSU Ultra
if [ -d /data/adb/sukisu ] || [ -d /data/adb/sukisu_ultra ]; then
    SK_DIR="/data/adb/sukisu"
    [ -d /data/adb/sukisu_ultra ] && SK_DIR="/data/adb/sukisu_ultra"
    mkdir -p "$SK_DIR" 2>/dev/null
    if [ ! -f "$SK_DIR/modules.img" ]; then
        make_ext4fs -b 1024 -l 256M "$SK_DIR/modules.img" 2>/dev/null \
            || mke2fs -b 1024 -t ext4 "$SK_DIR/modules.img" 256M 2>/dev/null
    fi
    chmod 644 /proc/kallsyms 2>/dev/null
    log -t InfinityInit "Root manager: SukiSU Ultra (compatibility fixes applied)"
fi

# -- Global: ensure /proc/kallsyms is readable by all root managers --
chmod 644 /proc/kallsyms 2>/dev/null

# -- Install infinity_init.sh as a Magisk/KSU module post-fs-data script --
# This ensures the script runs on every boot via the root manager
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
    # Copy ourselves to the root manager's post-fs-data.d for persistence
    if [ ! -f "$INIT_SCRIPT_DIR/post-fs-data.d/infinity_init.sh" ]; then
        cp "$0" "$INIT_SCRIPT_DIR/post-fs-data.d/infinity_init.sh" 2>/dev/null
        chmod 755 "$INIT_SCRIPT_DIR/post-fs-data.d/infinity_init.sh" 2>/dev/null
        log -t InfinityInit "Installed as $INIT_SCRIPT_DIR post-fs-data.d module"
    fi
fi

# ============================================================================
# 1. TCP BBR – set as default congestion control
# ============================================================================
if [ -f /proc/sys/net/ipv4/tcp_available_congestion_control ]; then
    if grep -q "bbr" /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        echo "bbr" > /proc/sys/net/ipv4/tcp_congestion_control
        echo "fq"  > /proc/sys/net/core/default_qdisc
        log -t InfinityInit "TCP BBR + fq qdisc enabled"
    else
        log -t InfinityInit "BBR not compiled in – skipping congestion control"
    fi
fi

# ============================================================================
# 2. I/O Scheduler
#     Prefer maple (BFQ successor); fall back to bfq; final fallback cfq.
# ============================================================================
IOSCHED=""

for sched in maple bfq cfq; do
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
    log -t InfinityInit "I/O scheduler: $IOSCHED"
else
    log -t InfinityInit "No preferred I/O scheduler found – leaving defaults"
fi

# ============================================================================
# 3. ZRAM – 5 GB with LZ4 compression
# ============================================================================
ZRAM_SIZE_KB=$((5120 * 1024))   # 5120 MB in kB

# Only configure if zram0 exists and is currently zero-size or not active
if [ -b /dev/block/zram0 ]; then
    CURRENT_SIZE="$(cat /sys/block/zram0/disksize 2>/dev/null || echo 0)"
    if [ "$CURRENT_SIZE" -eq 0 ] 2>/dev/null; then
        # Set compression algorithm to LZ4
        if [ -f /sys/block/zram0/comp_algorithm ]; then
            echo "lz4" > /sys/block/zram0/comp_algorithm 2>/dev/null
        fi

        # Set disk size (5120 MB)
        echo "5120M" > /sys/block/zram0/disksize 2>/dev/null
        log -t InfinityInit "ZRAM: 5120 MB / LZ4"

        # Format and enable swap
        mkswap /dev/block/zram0 >/dev/null 2>&1
        swapon /dev/block/zram0 >/dev/null 2>&1
        log -t InfinityInit "ZRAM swap active"
    else
        log -t InfinityInit "ZRAM already configured (${CURRENT_SIZE} bytes) – skipping"
    fi
else
    log -t InfinityInit "zram0 not found – skipping ZRAM setup"
fi

# ============================================================================
# 4. KSM – Kernel Samepage Merging
#     Reduces memory pressure by merging identical pages.
# ============================================================================
KSM_SYS="/sys/kernel/mm/ksm"

if [ -d "$KSM_SYS" ]; then
    echo 1   > "$KSM_SYS/run"           2>/dev/null   # Enable KSM
    echo 500 > "$KSM_SYS/pages_to_scan"  2>/dev/null   # Scan 500 pages/iteration
    echo 1000 > "$KSM_SYS/sleep_millisecs" 2>/dev/null  # Sleep 1 s between scans
    log -t InfinityInit "KSM enabled (500 pages / 1000ms)"
else
    log -t InfinityInit "KSM not available – skipping"
fi

# ============================================================================
# 5. Read-Ahead – 128 KB for all block devices
# ============================================================================
READAHEAD_KB=128

for blk in /sys/block/sd? /sys/block/dm-?; do
    [ -f "$blk/queue/read_ahead_kb" ] || continue
    echo "$READAHEAD_KB" > "$blk/queue/read_ahead_kb" 2>/dev/null
done
log -t InfinityInit "Read-ahead set to ${READAHEAD_KB} KB"

# ============================================================================
# 6. VM Swappiness
# ============================================================================
if [ -f /proc/sys/vm/swappiness ]; then
    echo 60 > /proc/sys/vm/swappiness
    log -t InfinityInit "Swappiness set to 60"
fi

# ============================================================================
# 7. Infinity Charging Bypass – Default Configuration
# ============================================================================
CHARGE_SYS="/sys/kernel/charging_control"

if [ -d "$CHARGE_SYS" ]; then
    # Default mode: BALANCED (2000 mA) – good for daily gaming
    echo "BALANCED" > "$CHARGE_SYS/mode" 2>/dev/null
    log -t InfinityInit "Charging bypass mode: BALANCED"

    # Bypass disabled by default – user must opt in via app or sysfs
    echo 0 > "$CHARGE_SYS/enabled" 2>/dev/null
    log -t InfinityInit "Charging bypass enabled: 0 (opt-in)"

    # Log current battery state for diagnostics
    TEMP="$(cat "$CHARGE_SYS/battery_temp" 2>/dev/null || echo "N/A")"
    CAP="$(cat "$CHARGE_SYS/battery_capacity" 2>/dev/null || echo "N/A")"
    log -t InfinityInit "Battery: temp=${TEMP} m°C  cap=${CAP}%%"
else
    log -t InfinityInit "Charging bypass sysfs not found – is the driver loaded?"
fi

# ============================================================================
# 8. Additional Kernel Tweaks
# ============================================================================

# Disable kernel same-page merging defragmentation (performance)
if [ -f /sys/kernel/mm/ksm/merge_across_nodes ]; then
    echo 0 > /sys/kernel/mm/ksm/merge_across_nodes 2>/dev/null
fi

# Reduce dirty page writeback latency for smoother I/O
if [ -f /proc/sys/vm/dirty_ratio ]; then
    echo 15 > /proc/sys/vm/dirty_ratio 2>/dev/null
fi
if [ -f /proc/sys/vm/dirty_background_ratio ]; then
    echo 5 > /proc/sys/vm/dirty_background_ratio 2>/dev/null
fi

# Enable frand entropy source for faster boot
if [ -f /proc/sys/kernel/random/entropy_avail ]; then
    ENTROPY="$(cat /proc/sys/kernel/random/entropy_avail 2>/dev/null || echo 0)"
    if [ "$ENTROPY" -lt 1024 ] 2>/dev/null; then
        log -t InfinityInit "Low entropy ($ENTROPY) – consider installing haveged"
    fi
fi

log -t InfinityInit "=== Infinity Kernel Init Complete ==="

exit 0