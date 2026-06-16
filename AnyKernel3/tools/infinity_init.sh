#!/system/bin/sh
## infinity_init.sh — Infinity Kernel Boot Initialization
## ROM-agnostic: works on MIUI, HyperOS, and any AOSP-based custom ROM
## Runs at early-boot via init.d or post-fs-data

INFINITY_VERSION="1.0.32"
INFINITY_DIR="/data/adb/infinity"

###############################################
# Logging
###############################################
log_inf() {
    echo "[InfinityKernel] $1" > /dev/kmsg
    log -t InfinityKernel "$1"
}

log_inf "Infinity Kernel v${INFINITY_VERSION} initializing..."

###############################################
# ROM Detection (runtime, boot context)
###############################################
detect_rom_runtime() {
    if [ -f /system/build.prop ]; then
        local miui_ver=$(getprop ro.miui.ui.version.name 2>/dev/null)
        local hyperos_ver=$(getprop ro.os.build.version.hyper_os 2>/dev/null)

        if [ -n "$miui_ver" ]; then
            CURRENT_ROM="miui"
            log_inf "ROM: MIUI $miui_ver"
        elif [ -n "$hyperos_ver" ]; then
            CURRENT_ROM="hyperos"
            log_inf "ROM: HyperOS $hyperos_ver"
        else
            CURRENT_ROM="custom"
            log_inf "ROM: Custom/AOSP"
        fi
    else
        CURRENT_ROM="unknown"
        log_inf "ROM: unknown (no build.prop)"
    fi
}

###############################################
# TCP Congestion Control — BBR
###############################################
setup_tcp() {
    log_inf "Setting TCP BBR congestion control..."
    echo "bbr" > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null
    echo "1" > /proc/sys/net/ipv4/tcp_fack 2>/dev/null

    # TCP Fast Open
    echo "3" > /proc/sys/net/ipv4/tcp_fastopen 2>/dev/null

    # TCP optimizations
    echo "1" > /proc/sys/net/ipv4/tcp_low_latency 2>/dev/null
    echo "4096 87380 6291456" > /proc/sys/net/ipv4/tcp_rmem 2>/dev/null
    echo "4096 65536 4194304" > /proc/sys/net/ipv4/tcp_wmem 2>/dev/null

    log_inf "TCP BBR configured"
}

###############################################
# I/O Scheduler — Prefer Maple, fallback to BFQ
###############################################
setup_io() {
    log_inf "Configuring I/O schedulers..."

    # Try Maple first (best for mobile flash storage)
    for dev in /sys/block/sd[a-z]/queue/scheduler; do
        if [ -f "$dev" ]; then
            if grep -q "\[maple\]" "$dev" 2>/dev/null || grep -q "maple" "$dev" 2>/dev/null; then
                echo "maple" > "$dev" 2>/dev/null
            else
                echo "bfq" > "$dev" 2>/dev/null
            fi
        fi
    done

    # For UFS devices (sd* and mmcblk*)
    for dev in /sys/block/mmcblk*/queue/scheduler; do
        if [ -f "$dev" ]; then
            if grep -q "maple" "$dev" 2>/dev/null; then
                echo "maple" > "$dev" 2>/dev/null
            else
                echo "bfq" > "$dev" 2>/dev/null
            fi
        fi
    done

    # Read-ahead optimization (128KB for sequential perf)
    for dev in /sys/block/sd[a-z]/queue/read_ahead_kb; do
        [ -f "$dev" ] && echo "128" > "$dev" 2>/dev/null
    done
    for dev in /sys/block/mmcblk*/queue/read_ahead_kb; do
        [ -f "$dev" ] && echo "128" > "$dev" 2>/dev/null
    done

    log_inf "I/O schedulers configured"
}

###############################################
# ZRAM — 5GB LZ4 for 8GB RAM device
###############################################
setup_zram() {
    log_inf "Configuring ZRAM 5GB LZ4..."

    local zram_size_mb=5120
    local zram_dev=""

    # Find zram device
    for d in /dev/block/zram0 /dev/zram0; do
        if [ -b "$d" ]; then
            zram_dev="$d"
            break
        fi
    done

    # Try to use module-loaded zram
    if [ -z "$zram_dev" ] && [ -f /proc/zraminfo ]; then
        zram_dev="/dev/block/$(head -1 /proc/zraminfo 2>/dev/null | cut -d' ' -f1)"
    fi

    if [ -z "$zram_dev" ]; then
        log_inf "ZRAM: No device found, loading module..."
        modprobe zram num_devices=1 2>/dev/null
        zram_dev="/dev/block/zram0"
    fi

    if [ -b "$zram_dev" ]; then
        # Set LZ4 compression (best ratio/perf balance for mobile)
        echo "lz4" > /sys/block/zram0/comp_algorithm 2>/dev/null

        # Set disksize to 5GB
        echo "${zram_size_mb}M" > /sys/block/zram0/disksize 2>/dev/null

        # Enable ZRAM writeback (reduces wear, leverages free RAM)
        echo "1" > /sys/block/zram0/backing_dev 2>/dev/null

        # High priority for swap (use ZRAM before actual swap)
        if [ -f /proc/swaps ] && ! grep -q zram /proc/swaps 2>/dev/null; then
            mkswap "$zram_dev" 2>/dev/null
            swapon -p 100 "$zram_dev" 2>/dev/null
        fi

        log_inf "ZRAM: ${zram_size_mb}MB LZ4 active on $zram_dev"
    else
        log_inf "ZRAM: Could not initialize"
    fi
}

###############################################
# VM / Swappiness
###############################################
setup_vm() {
    log_inf "Configuring VM parameters..."

    # Swappiness 60 = default Linux, good for 8GB + 5GB ZRAM
    # Higher value = more aggressive swap to ZRAM (good for 8GB device)
    echo "60" > /proc/sys/vm/swappiness 2>/dev/null

    # VFS cache pressure — lower = keep more file cache (benefits app switching)
    echo "80" > /proc/sys/vm/vfs_cache_pressure 2>/dev/null

    # Min free Kbytes — prevent OOM on heavy load (48MB)
    echo "49152" > /proc/sys/vm/min_free_kbytes 2>/dev/null

    # Dirty pages — faster writeback for responsiveness
    echo "500" > /proc/sys/vm/dirty_ratio 2>/dev/null
    echo "100" > /proc/sys/vm/dirty_background_ratio 2>/dev/null

    # Overcommit memory — allow slight overcommit for app launches
    echo "0" > /proc/sys/vm/overcommit_memory 2>/dev/null

    log_inf "VM parameters configured"
}

###############################################
# KSM — Kernel Same-page Merging
###############################################
setup_ksm() {
    log_inf "Configuring KSM (Kernel Same-page Merging)..."

    # Enable KSM
    echo "1" > /sys/kernel/mm/ksm/run 2>/dev/null

    # Aggressive scanning for 8GB device
    echo "500" > /sys/kernel/mm/ksm/sleep_millisecs 2>/dev/null
    echo "1000" > /sys/kernel/mm/ksm/pages_to_scan 2>/dev/null

    # Only merge zero pages aggressively
    echo "1" > /sys/kernel/mm/ksm/merge_across_nodes 2>/dev/null

    log_inf "KSM configured"
}

###############################################
# FSYNC — fdatasync optimization
###############################################
setup_fsync() {
    log_inf "FSYNC optimization..."

    # Ensure FSYNC sysfs is available (from kernel patch)
    if [ -f /sys/fs/fsync/enable ]; then
        echo "1" > /sys/fs/fsync/enable 2>/dev/null
        log_inf "FSYNC enabled via sysfs"
    fi

    # Also set via sysctl if available
    sysctl -w fs.fsync_enable=1 2>/dev/null

    log_inf "FSYNC configured"
}

###############################################
# Charging Control Defaults
###############################################
setup_charging() {
    log_inf "Setting charging control defaults..."

    # Set default mode to OFF (normal charging)
    if [ -f /sys/kernel/infinity_charging/charging_mode ]; then
        echo "0" > /sys/kernel/infinity_charging/charging_mode 2>/dev/null
    fi

    # Thermal limit for charging: 42C default (balanced)
    if [ -f /sys/kernel/infinity_charging/thermal_limit ]; then
        echo "42" > /sys/kernel/infinity_charging/thermal_limit 2>/dev/null
    fi

    # Auto-resume threshold: 15%
    if [ -f /sys/kernel/infinity_charging/auto_resume_threshold ]; then
        echo "15" > /sys/kernel/infinity_charging/auto_resume_threshold 2>/dev/null
    fi

    log_inf "Charging defaults: mode=OFF, thermal=42C, auto_resume=15%"
}

###############################################
# GPU (KGSL) Optimization
###############################################
setup_gpu() {
    log_inf "Configuring GPU (Adreno 618)..."

    # Set governor to performance-aware default
    if [ -f /sys/class/kgsl/kgsl-3d0/gpuclk ]; then
        # No-op if using sysfs-controlled GPU frequencies
        :
    fi

    # Min/max frequency bounds (if exposed)
    if [ -f /sys/class/kgsl/kgsl-3d0/max_gpuclk ]; then
        # Let the GPU driver manage dynamically
        :
    fi

    # Idle timer — faster idle for battery
    if [ -f /sys/class/kgsl/kgsl-3d0/idle_timer ]; then
        echo "64" > /sys/class/kgsl/kgsl-3d0/idle_timer 2>/dev/null
    fi

    log_inf "GPU configured"
}

###############################################
# Root Manager Compatibility Fixes
###############################################
setup_root_compat() {
    log_inf "Applying root manager compatibility..."

    # Ensure /data/adb exists for root managers
    mkdir -p /data/adb 2>/dev/null
    chmod 700 /data/adb 2>/dev/null

    # Fix SELinux contexts for root manager directories
    restorecon -R /data/adb 2>/dev/null

    # Ensure kallsyms is accessible for KernelSU/APatch modules
    if [ -f /proc/sys/kernel/kptr_restrict ]; then
        # Keep restricted by default, root managers handle this
        :
    fi

    log_inf "Root manager compatibility applied"
}

###############################################
# Main
###############################################
main() {
    detect_rom_runtime

    # Core optimizations (all ROMs)
    setup_tcp
    setup_io
    setup_zram
    setup_vm
    setup_ksm
    setup_fsync
    setup_gpu
    setup_charging
    setup_root_compat

    log_inf "Infinity Kernel v${INFINITY_VERSION} initialized successfully"
    log_inf "ROM: $CURRENT_ROM | RAM: $(free -m 2>/dev/null | awk '/Mem:/{print $2}')MB"
}

# Execute
main "$@"