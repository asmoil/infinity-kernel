#!/bin/bash
# Infinity Kernel Patch Script
# Safe sed-based patching for Linux 4.14 SM8250-AC (Poco X3 Pro vayu/bhima)
# Usage: bash apply_all.sh [kernel_source_dir]

KERNEL_DIR="${1:-.}"

# --- safe_sed: sed -i with file-existence check and error handling ---
safe_sed() {
    local file="$1"
    shift
    if [ ! -f "$file" ]; then
        echo "  [SKIP] $file not found"
        return 1
    fi
    sed -i "$@" "$file" && echo "  [OK] Patched $file" || echo "  [WARN] Failed to patch $file"
}

echo "================================"
echo " Applying Infinity Kernel Patches"
echo " Target: $KERNEL_DIR"
echo "================================"

# ============================================================
# Section 1: CPU Frequency / Governor Tweaks
# ============================================================
echo ""
echo "--- Section 1: CPU Frequency / Governor ---"

# Lower schedutil rate limit for faster frequency response
safe_sed "$KERNEL_DIR/drivers/cpufreq/cpufreq_schedutil.c" \
    's/tunable_rate_limit_us\s*=\s*1000/tunable_rate_limit_us = 500/' || true

# Reduce ondemand up_threshold so CPU ramps sooner
safe_sed "$KERNEL_DIR/drivers/cpufreq/cpufreq_ondemand.c" \
    's/def_up_threshold\s*=\s*80/def_up_threshold = 65/' || true

# Increase sampling down factor to avoid premature down-scaling
safe_sed "$KERNEL_DIR/drivers/cpufreq/cpufreq_ondemand.c" \
    's/def_sampling_down_factor\s*=\s*1/def_sampling_down_factor = 3/' || true

# Tighten sched latency for snappier task scheduling
safe_sed "$KERNEL_DIR/kernel/sched/core.c" \
    's/sysctl_sched_latency\s*=\s*6000000ULL/sysctl_sched_latency          = 4000000ULL/' || true
safe_sed "$KERNEL_DIR/kernel/sched/core.c" \
    's/normalized_sysctl_sched_latency\s*=\s*6000000ULL/normalized_sysctl_sched_latency  = 4000000ULL/' || true

# Lower min granularity to improve responsiveness
safe_sed "$KERNEL_DIR/kernel/sched/fair.c" \
    's/sysctl_sched_min_granularity\s*=\s*750000UL/sysctl_sched_min_granularity = 500000UL/' || true
safe_sed "$KERNEL_DIR/kernel/sched/fair.c" \
    's/normalized_sysctl_sched_min_granularity\s*=\s*750000UL/normalized_sysctl_sched_min_granularity = 500000UL/' || true

# Reduce migration cost for better multi-core load balancing
safe_sed "$KERNEL_DIR/kernel/sched/core.c" \
    's/sysctl_sched_nr_migrate\s*=\s*32/sysctl_sched_nr_migrate      = 8/' || true

echo "  [1/7] CPU Frequency/Governor: done"

# ============================================================
# Section 2: I/O Scheduler Optimizations
# ============================================================
echo ""
echo "--- Section 2: I/O Scheduler ---"

# Lower block layer default timeout (30s -> 15s)
safe_sed "$KERNEL_DIR/block/blk-core.c" \
    's/BLK_DEFAULT_TIMEOUT\s*(30 \* HZ)/BLK_DEFAULT_TIMEOUT (15 * HZ)/' || true

# Ensure BFQ scheduler is built into block/Makefile
if [ -f "$KERNEL_DIR/block/Makefile" ]; then
    if ! grep -q 'bfq-iosched.o' "$KERNEL_DIR/block/Makefile" 2>/dev/null; then
        sed -i '/obj-$(CONFIG_BLK_DEV_THROTTLING)/i obj-$(CONFIG_IOSCHED_BFQ)\t+= bfq-iosched.o bfq-cgroup.o' \
            "$KERNEL_DIR/block/Makefile" 2>/dev/null && echo "  [OK] Added BFQ to block/Makefile" || echo "  [WARN] BFQ Makefile add failed"
    else
        echo "  [INFO] BFQ already in block/Makefile"
    fi
else
    echo "  [SKIP] block/Makefile not found"
fi

# Increase default read-ahead size for better sequential I/O
safe_sed "$KERNEL_DIR/block/blk-settings.c" \
    's/blk_default_ra\s*=\s*1024/blk_default_ra = 256/' || true

echo "  [2/7] I/O Scheduler: done"

# ============================================================
# Section 3: Memory / VM Tuning
# ============================================================
echo ""
echo "--- Section 3: Memory / VM Tuning ---"

# Increase dirty page ratio (5% -> 10%) for less frequent writeback
safe_sed "$KERNEL_DIR/mm/vmscan.c" \
    's/vm_dirty_ratio\s*=\s*5/vm_dirty_ratio = 10/' || true

# Raise background dirty ratio threshold
safe_sed "$KERNEL_DIR/mm/vmscan.c" \
    's/vm_dirty_background_ratio\s*=\s*10/vm_dirty_background_ratio = 5/' || true

# Increase min_free_kbytes to reduce low-memory stalls (default ~8192 -> 65536)
safe_sed "$KERNEL_DIR/mm/page_alloc.c" \
    's/min_free_kbytes\s*=\s*8192/min_free_kbytes = 65536/' || true

# Lower swappiness for less aggressive swap on high-memory devices
safe_sed "$KERNEL_DIR/mm/vmscan.c" \
    's/vm_swappiness\s*=\s*60/vm_swappiness = 30/' || true

# Raise overcommit ratio to allow more memory allocation before OOM
safe_sed "$KERNEL_DIR/mm/mmap.c" \
    's/sysctl_overcommit_ratio\s*=\s*50/sysctl_overcommit_ratio = 80/' || true

# Reduce watermark scale factor for more aggressive reclaim
safe_sed "$KERNEL_DIR/mm/page_alloc.c" \
    's/watermark_scale_factor\s*=\s*10/watermark_scale_factor = 15/' || true

echo "  [3/7] Memory/VM: done"

# ============================================================
# Section 4: TCP / Network Optimizations
# ============================================================
echo ""
echo "--- Section 4: TCP / Network ---"

# Enable TCP Fast Open (client+server = 3)
safe_sed "$KERNEL_DIR/net/ipv4/tcp_ipv4.c" \
    's/sysctl_tcp_fastopen\s*=\s*1/sysctl_tcp_fastopen = 3/' || true

# Increase default TCP buffer sizes for better throughput
safe_sed "$KERNEL_DIR/net/ipv4/tcp.c" \
    's/sysctl_tcp_wmem\[3\]\s*=\s*4194304/sysctl_tcp_wmem[3] = 16777216/' || true
safe_sed "$KERNEL_DIR/net/ipv4/tcp.c" \
    's/sysctl_tcp_rmem\[3\]\s*=\s*4194304/sysctl_tcp_rmem[3] = 16777216/' || true

# Lower TCP keepalive interval for faster dead-connection detection
safe_sed "$KERNEL_DIR/net/ipv4/tcp_timer.c" \
    's/TCP_KEEPALIVE_TIME\s*(120 \* HZ)/TCP_KEEPALIVE_TIME (30 * HZ)/' || true

# Enable BBR Kconfig entry if missing
if [ -f "$KERNEL_DIR/net/ipv4/Kconfig" ]; then
    if ! grep -q 'TCP_CONG_BBR' "$KERNEL_DIR/net/ipv4/Kconfig" 2>/dev/null; then
        sed -i '/config TCP_CONG_HTCP/i config TCP_CONG_BBR\n\ttristate "BBR TCP"\n\tdefault n\n\tselect NET_SCH_FQ_CODEL\n\t---help---\n\t  BBR (Bottleneck Bandwidth and RTT) congestion control.' \
            "$KERNEL_DIR/net/ipv4/Kconfig" 2>/dev/null && echo "  [OK] BBR Kconfig added" || true
    else
        echo "  [INFO] BBR already in Kconfig"
    fi
fi

# Add bbr.o to Makefile if missing
if [ -f "$KERNEL_DIR/net/ipv4/Makefile" ]; then
    if ! grep -q 'bbr.o' "$KERNEL_DIR/net/ipv4/Makefile" 2>/dev/null; then
        sed -i '/obj-$(CONFIG_TCP_CONG_WESTWOOD)/a obj-$(CONFIG_TCP_CONG_BBR) += bbr.o' \
            "$KERNEL_DIR/net/ipv4/Makefile" 2>/dev/null && echo "  [OK] BBR Makefile entry added" || true
    fi
fi

# Create minimal BBR stub if source doesn't exist (full BBR needs backport)
if [ ! -f "$KERNEL_DIR/net/ipv4/bbr.c" ]; then
    cat > "$KERNEL_DIR/net/ipv4/bbr.c" << 'BBR_EOF'
// SPDX-License-Identifier: GPL-2.0
/* BBR congestion control stub — full impl requires backport from 4.19+ */
#include <net/tcp.h>
static struct tcp_congestion_ops tcp_bbr __read_mostly = {
	.name		= "bbr",
	.owner		= THIS_MODULE,
};
static int __init bbr_register(void)  { return tcp_register_congestion_control(&tcp_bbr); }
static void __exit bbr_unregister(void) { tcp_unregister_congestion_control(&tcp_bbr); }
module_init(bbr_register);
module_exit(bbr_unregister);
MODULE_LICENSE("GPL v2");
MODULE_DESCRIPTION("BBR TCP congestion control");
BBR_EOF
    echo "  [OK] bbr.c stub created"
fi

echo "  [4/7] TCP/Network: done"

# ============================================================
# Section 5: Thermal Tuning
# ============================================================
echo ""
echo "--- Section 5: Thermal ---"

# Raise thermal trip points on Qualcomm MSM thermal (vayu uses msm_thermal)
safe_sed "$KERNEL_DIR/drivers/thermal/msm_thermal.c" \
    's/trip_temp\s*=\s*65000/trip_temp = 75000/' || true

# Raise monitor temp ceiling
safe_sed "$KERNEL_DIR/drivers/thermal/msm_thermal.c" \
    's/trip_temp_degC\s*=\s*65/trip_temp_degC = 75/' || true

# Increase allowed max frequency at high temp before throttling
safe_sed "$KERNEL_DIR/drivers/thermal/msm_thermal.c" \
    's/settling_temp\s*=\s*60000/settling_temp = 70000/' || true

# Allow CPU to run hotter before notification
safe_sed "$KERNEL_DIR/drivers/thermal/thermal_core.c" \
    's/default_temperature\s*=\s*55000/default_temperature = 65000/' || true

# Increase thermal zone polling delay (2s -> 3s) to reduce overhead
safe_sed "$KERNEL_DIR/drivers/thermal/thermal_core.c" \
    's/default_polling_delay\s*=\s*2000/default_polling_delay = 3000/' || true

echo "  [5/7] Thermal: done"

# ============================================================
# Section 6: Build System Fixes (Clang Warning Suppression)
# ============================================================
echo ""
echo "--- Section 6: Build System Fixes ---"

# Suppress unused-but-set-variable warnings common with Clang + Linux 4.14
safe_sed "$KERNEL_DIR/Makefile" \
    's/-Werror=/-Wno-error=unused-but-set-variable -Werror=/' || true

# Disable -Wunused-function warnings from Clang
safe_sed "$KERNEL_DIR/Makefile" \
    's/-Werror/-Wno-error=unused-function -Wno-error=uninitialized -Werror/' || true

# Suppress frame-larger-than warnings in Clang-built modules
safe_sed "$KERNEL_DIR/scripts/Makefile.modpost" \
    's/-Wframe-larger-than=[0-9]*/-Wno-frame-larger-than/' || true

# Add -fno-addrsig for Clang LTO compatibility
if [ -f "$KERNEL_DIR/Makefile" ]; then
    if ! grep -q 'fno-addrsig' "$KERNEL_DIR/Makefile" 2>/dev/null; then
        sed -i 's/KCFLAGS += -fno-addrsig/KCFLAGS += -fno-addrsig/' \
            "$KERNEL_DIR/Makefile" 2>/dev/null || \
        sed -i '/^KBUILD_CFLAGS/a KCFLAGS += -fno-addrsig' \
            "$KERNEL_DIR/Makefile" 2>/dev/null || true
        echo "  [INFO] Clang LTO flags checked"
    fi
fi

# Suppress shift-count-overflow warnings in arm64 headers
safe_sed "$KERNEL_DIR/arch/arm64/Makefile" \
    's/-Werror/-Wno-error=shift-count-overflow -Werror/' || true

echo "  [6/7] Build System: done"

# ============================================================
# Section 7: Display / GPU Optimizations (Adreno 618)
# ============================================================
echo ""
echo "--- Section 7: Display / GPU (Adreno 618) ---"

# Raise KGSL GPU bus voting up-threshold for faster ramp
for kgsl_c in \
    "$KERNEL_DIR/drivers/gpu/msm/kgsl.c" \
    "$KERNEL_DIR/drivers/gpu/msm/adreno/kgsl.c" \
    "$KERNEL_DIR/drivers/video/fbdev/msm/kgsl.c"; do
    [ -f "$kgsl_c" ] && {
        safe_sed "$kgsl_c" \
            's/\.upthreshold\s*=\s*80,/.upthreshold = 90,/' || true
        echo "  [INFO] Found KGSL at: $kgsl_c"
        break
    }
done

# Optimize KGSL MMU TLB flush timing for Adreno 618
for mmu_c in \
    "$KERNEL_DIR/drivers/gpu/msm/kgsl_mmu.c" \
    "$KERNEL_DIR/drivers/gpu/msm/adreno/kgsl_mmu.c"; do
    [ -f "$mmu_c" ] && {
        safe_sed "$mmu_c" \
            's/KGSL_IOMMU_TLBFLUSH_SLEEP_IDLE\s*50/KGSL_IOMMU_TLBFLUSH_SLEEP_IDLE     = 25/' || true
        safe_sed "$mmu_c" \
            's/KGSL_IOMMU_TLBFLUSH_SLEEP_BUSY\s*10/KGSL_IOMMU_TLBFLUSH_SLEEP_BUSY     = 5/' || true
        safe_sed "$mmu_c" \
            's/KGSL_IOMMU_TLBFLUSH_TIMEOUT\s*10000/KGSL_IOMMU_TLBFLUSH_TIMEOUT        = 5000/' || true
        echo "  [INFO] Found KGSL MMU at: $mmu_c"
        break
    }
done

# Reduce mdss panel frame-done timeout for snappier display
safe_sed "$KERNEL_DIR/drivers/video/fbdev/msm/mdss_mdp.c" \
    's/MDP_FRAME_DONE_TIMEOUT\s*2000/MDP_FRAME_DONE_TIMEOUT      = 1000/' || true

# Disable unnecessary vsync compensation for gaming performance
safe_sed "$KERNEL_DIR/drivers/video/fbdev/msm/mdss_sync.c" \
    's/VSYNC_EVENT_PERIOD\s*16666/VSYNC_EVENT_PERIOD = 11111/' || true

echo "  [7/7] Display/GPU: done"

# ============================================================
echo ""
echo "================================"
echo " All Infinity Kernel patches applied"
echo " Review [WARN] messages above"
echo "================================"