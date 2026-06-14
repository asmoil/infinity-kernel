#!/system/bin/sh
# Infinity Kernel Init Script
# Runs at boot to apply system optimizations

LOG="/cache/infinity_kernel.log"
echo "[$(date)] Infinity Kernel init starting" > $LOG

# TCP: BBR
echo "bbr" > /proc/sys/net/ipv4/tcp_congestion_control
echo "1" > /proc/sys/net/ipv4/tcp_bbr_low_memory

# I/O Schedulers: Maple for UFS, BFQ for fallback
for dev in /sys/block/sd*/queue/scheduler; do
    if grep -q "maple" "$dev" 2>/dev/null; then
        echo "maple" > "$dev"
    else
        echo "bfq" > "$dev"
    fi
done

# ZRAM: 5GB, LZ4
SWAP_SIZE=$((5*1024*1024*1024))  # 5GB in bytes
if [ ! -e /dev/block/zram0 ]; then
    modprobe zram num_devices=1
fi
echo $SWAP_SIZE > /sys/block/zram0/disksize
echo "lz4" > /sys/block/zram0/comp_algorithm
mkswap /dev/block/zram0
swapon -p 100 /dev/block/zram0

# KSM
echo "1" > /sys/kernel/mm/ksm/run
echo "1000" > /sys/kernel/mm/ksm/sleep_millisecs
echo "500" > /sys/kernel/mm/ksm/pages_to_scan

# FSYNC
echo "1" > /sys/fs/fcntl/max_active

# VM Tuning
echo "10" > /proc/sys/vm/dirty_ratio
echo "5" > /proc/sys/vm/dirty_background_ratio
echo "60" > /proc/sys/vm/swappiness
echo "50" > /proc/sys/vm/vfs_cache_pressure
echo "18432" > /proc/sys/vm/min_free_kbytes

# GPU: Adreno 618 governor
if [ -d /sys/class/kgsl/kgsl-3d0 ]; then
    echo "performance" > /sys/class/kgsl/kgsl-3d0/gpu_governor
fi

echo "[$(date)] Infinity Kernel init completed" >> $LOG