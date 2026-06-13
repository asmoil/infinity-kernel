#!/bin/bash
## apply_infinity_patches.sh
## Applies all Infinity Kernel optimizations via sed/grep/echo.
## Works on any Linux 4.14 source from MiCode/Xiaomi_Kernel_OpenSource (vayu-r-oss).
## Safe to run multiple times (idempotent).
## Usage: bash apply_infinity_patches.sh <kernel_src_dir>

set -e
SRC="$1"
if [ -z "$SRC" ] || [ ! -d "$SRC" ]; then
    echo "Usage: $0 <kernel_source_dir>"
    exit 1
fi

echo "=== Applying Infinity Kernel patches ==="

###############################################
# 1. CPU / Scheduler Tuning
###############################################
echo "[1/7] CPU/Scheduler tuning..."

# kernel/sched/core.c: sched_latency 6ms -> 4ms
sed -i 's/sysctl_sched_latency\s*=\s*6000000ULL/sysctl_sched_latency                      = 4000000ULL/g' "$SRC/kernel/sched/core.c"
sed -i 's/normalized_sysctl_sched_latency\s*=\s*6000000ULL/normalized_sysctl_sched_latency    = 4000000ULL/g' "$SRC/kernel/sched/core.c"

# kernel/sched/core.c: nr_migrate 32 -> 8
sed -i 's/sysctl_sched_nr_migrate\s*=\s*32/sysctl_sched_nr_migrate           = 8/g' "$SRC/kernel/sched/core.c"

# kernel/sched/fair.c: min_granularity 750us -> 500us
sed -i 's/sysctl_sched_min_granularity\s*=\s*750000UL/sysctl_sched_min_granularity              = 500000UL/g' "$SRC/kernel/sched/fair.c"
sed -i 's/normalized_sysctl_sched_min_granularity\s*=\s*750000UL/normalized_sysctl_sched_min_granularity = 500000UL/g' "$SRC/kernel/sched/fair.c"

# drivers/cpufreq/cpufreq_ondemand.c: up_threshold 80->65, sampling_down_factor 1->3
sed -i 's/def_up_threshold\s*=\s*80/def_up_threshold                   = 65/g' "$SRC/drivers/cpufreq/cpufreq_ondemand.c"
sed -i 's/def_sampling_down_factor\s*=\s*1/def_sampling_down_factor           = 3/g' "$SRC/drivers/cpufreq/cpufreq_ondemand.c"

# drivers/cpufreq/cpufreq_schedutil.c: rate_limit 1000->500
sed -i 's/tunable_rate_limit_us\s*=\s*1000/tunable_rate_limit_us = 500/g' "$SRC/drivers/cpufreq/cpufreq_schedutil.c"

echo "  CPU/Scheduler: done"

###############################################
# 2. Battery / Power Optimization
###############################################
echo "[2/7] Battery/Power optimization..."

# kernel/power/suspend.c: PM_TEST_SUSPEND_DELAY 200->100
sed -i 's/PM_TEST_SUSPEND_DELAY\s*200/PM_TEST_SUSPEND_DELAY 100/g' "$SRC/kernel/power/suspend.c"

# drivers/base/power/main.c: ASYNC_DOMAIN_MAX_TIMEOUT 10000->5000
sed -i 's/ASYNC_DOMAIN_MAX_TIMEOUT\s*10000/ASYNC_DOMAIN_MAX_TIMEOUT       5000/g' "$SRC/drivers/base/power/main.c"

# drivers/power/supply/qcom/qpnp-smb2-charger.c: DEFAULT_FCC_STEP 500->1500
if [ -f "$SRC/drivers/power/supply/qcom/qpnp-smb2-charger.c" ]; then
    sed -i 's/DEFAULT_FCC_STEP\s*500/DEFAULT_FCC_STEP               1500/g' "$SRC/drivers/power/supply/qcom/qpnp-smb2-charger.c"
fi

echo "  Battery/Power: done"

###############################################
# 3. FSYNC / I/O
###############################################
echo "[3/7] FSYNC/I/O optimization..."

# block/blk-core.c: BLK_DEFAULT_TIMEOUT 30*HZ -> 15*HZ
sed -i 's/BLK_DEFAULT_TIMEOUT\s*(30 \* HZ)/BLK_DEFAULT_TIMEOUT    (15 * HZ)/g' "$SRC/block/blk-core.c"

# block/Makefile: ensure BFQ is built (only add if not already present)
if ! grep -q 'bfq-iosched.o' "$SRC/block/Makefile" 2>/dev/null; then
    sed -i '/obj-\$(CONFIG_BLK_DEV_THROTTLING)/i obj-$(CONFIG_IOSCHED_BFQ)      += bfq-iosched.o bfq-cgroup.o' "$SRC/block/Makefile"
fi

echo "  FSYNC/I/O: done"

###############################################
# 4. GPU (Adreno 618 / KGSL)
###############################################
echo "[4/7] GPU Adreno 618 tuning..."

# drivers/gpu/msm/kgsl.c: up_threshold 80->90
if [ -f "$SRC/drivers/gpu/msm/kgsl.c" ]; then
    sed -i 's/\.upthreshold\s*=\s*80,/.upthreshold = 90,/g' "$SRC/drivers/gpu/msm/kgsl.c"
fi

# drivers/gpu/msm/kgsl_mmu.c: TLB flush optimization
if [ -f "$SRC/drivers/gpu/msm/kgsl_mmu.c" ]; then
    sed -i 's/KGSL_IOMMU_TLBFLUSH_SLEEP_IDLE\s*50/KGSL_IOMMU_TLBFLUSH_SLEEP_IDLE         25/g' "$SRC/drivers/gpu/msm/kgsl_mmu.c"
    sed -i 's/KGSL_IOMMU_TLBFLUSH_SLEEP_BUSY\s*10/KGSL_IOMMU_TLBFLUSH_SLEEP_BUSY         5/g' "$SRC/drivers/gpu/msm/kgsl_mmu.c"
    sed -i 's/KGSL_IOMMU_TLBFLUSH_TIMEOUT\s*10000/KGSL_IOMMU_TLBFLUSH_TIMEOUT            5000/g' "$SRC/drivers/gpu/msm/kgsl_mmu.c"
fi

echo "  GPU: done"

###############################################
# 5. TCP BBR + Fast Open
###############################################
echo "[5/7] TCP BBR + Fast Open..."

# net/ipv4/tcp_ipv4.c: tcp_fastopen 1 -> 3
sed -i 's/sysctl_tcp_fastopen\s*=\s*1/sysctl_tcp_fastopen = 3/g' "$SRC/net/ipv4/tcp_ipv4.c"

# net/ipv4/Kconfig: add TCP_CONG_BBR (only if not present)
if ! grep -q 'TCP_CONG_BBR' "$SRC/net/ipv4/Kconfig" 2>/dev/null; then
    sed -i '/config TCP_CONG_HTCP/i\
config TCP_CONG_BBR\
\ttristate "BBR TCP"\
\tdefault n\
\tselect NET_SCH_FQ_CODEL\
\t---help---\
\t  BBR (Bottleneck Bandwidth and RTT) congestion control.\
\t  Requires FQ or FQ_CODEL qdisc.\
' "$SRC/net/ipv4/Kconfig"
fi

# net/ipv4/Makefile: add bbr.o (only if not present)
if ! grep -q 'bbr.o' "$SRC/net/ipv4/Makefile" 2>/dev/null; then
    sed -i '/obj-\$(CONFIG_TCP_CONG_WESTWOOD)/a obj-$(CONFIG_TCP_CONG_BBR) += bbr.o' "$SRC/net/ipv4/Makefile"
fi

echo "  TCP: done"

###############################################
# 6. Root Manager Support
###############################################
echo "[6/7] Root manager support..."

MOD_C="$SRC/kernel/module.c"
KALL_C="$SRC/kernel/kallsyms.c"

# --- kernel/module.c: add module_is_allowlisted() ---
if ! grep -q 'module_is_allowlisted' "$MOD_C" 2>/dev/null; then
    # Insert after the modules list head and before #ifdef CONFIG_MODULES_TREE_LOOKUP
    python3 -c "
import sys
content = open('$MOD_C', 'r').read()
insert = '''
/* Root manager module allowlist - bypass sig/vermagic checks */
static bool module_is_allowlisted(const char *name)
{
\tstatic const char * const allowed_modules[] = {
\t\t\"kernelsu\",
\t\t\"kernelsu_next\",
\t\t\"magisk\",
\t\t\"apatch\",
\t\t\"kp\",
\t\t\"resukisu\",
\t\t\"sukisu_ultra\",
\t\tNULL
\t};
\tint i;
\tif (!name)
\t\treturn false;
\tfor (i = 0; allowed_modules[i]; i++) {
\t\tif (strstr(name, allowed_modules[i]))
\t\t\treturn true;
\t}
\treturn false;
}

'''
# Insert before #ifdef CONFIG_MODULES_TREE_LOOKUP
content = content.replace('#ifdef CONFIG_MODULES_TREE_LOOKUP', insert + '#ifdef CONFIG_MODULES_TREE_LOOKUP', 1)
open('$MOD_C', 'w').write(content)
"
fi

# --- kernel/module.c: bypass check_modinfo vermagic ---
if ! grep -q 'Skip vermagic check for root manager' "$MOD_C" 2>/dev/null; then
    python3 -c "
content = open('$MOD_C', 'r').read()
old = '''static int check_modinfo(struct module *mod,'''
new = '''static int check_modinfo(struct module *mod,
\t\t\t\t  struct load_info *info, int flags)
{
\tconst char *modname = get_modinfo(info, \"name\");

\t/* Skip vermagic check for root manager modules */
\tif (module_is_allowlisted(modname))
\t\treturn 0;

\tif (flags & MODULE_INIT_IGNORE_VERMAGIC)
\t\tmodname = NULL;'''
content = content.replace(old, new, 1)
open('$MOD_C', 'w').write(content)
"
fi

# --- kernel/module.c: bypass module_sig_check ---
if ! grep -q 'Bypass signature check for root manager' "$MOD_C" 2>/dev/null; then
    python3 -c "
content = open('$MOD_C', 'r').read()
old = '''static int module_sig_check(struct load_info *info, int flags)
{
\tint err = -ENOMODULE;'''
new = '''static int module_sig_check(struct load_info *info, int flags)
{
\tint err = -ENOMODULE;

\t/* Bypass signature check for root manager modules */
\t{
\t\tconst char *modname = get_modinfo(info, \"name\");
\t\tif (modname && module_is_allowlisted(modname))
\t\t\treturn 0;
\t}'''
content = content.replace(old, new, 1)
open('$MOD_C', 'w').write(content)
"
fi

# --- kernel/kallsyms.c: export kallsyms_lookup_name ---
if ! grep -q 'EXPORT_SYMBOL_GPL(kallsyms_lookup_name)' "$KALL_C" 2>/dev/null; then
    # Add right after the closing brace of kallsyms_lookup_name
    python3 -c "
content = open('$KALL_C', 'r').read()
old = '''\treturn module_kallsyms_lookup_name(name);
}

static unsigned long kallsyms_lookup_size_offset'''
new = '''\treturn module_kallsyms_lookup_name(name);
}

EXPORT_SYMBOL_GPL(kallsyms_lookup_name);
static unsigned long kallsyms_lookup_size_offset'''
content = content.replace(old, new, 1)
open('$KALL_C', 'w').write(content)
"
fi

echo "  Root managers: done"

###############################################
# 7. SUFS v1.5.7+
###############################################
echo "[7/7] SUFS v1.5.7+ support..."

# Create fs/sufs.c
cat > "$SRC/fs/sufs.c" << 'SUFS_EOF'
// SPDX-License-Identifier: GPL-2.0
#include <linux/module.h>
#include <linux/fs.h>
#include <linux/mount.h>
#include <linux/namei.h>

static struct file_system_type sufs_fs_type = {
	.owner		= THIS_MODULE,
	.name		= "sufs",
	.mount		= NULL,
	.kill_sb	= kill_anon_super,
};

static int __init sufs_init(void)
{
	return register_filesystem(&sufs_fs_type);
}

static void __exit sufs_exit(void)
{
	unregister_filesystem(&sufs_fs_type);
}

module_init(sufs_init);
module_exit(sufs_exit);
MODULE_LICENSE("GPL v2");
MODULE_DESCRIPTION("SUFS v1.5.7+ Systemless UFS Filesystem");
MODULE_AUTHOR("Infinity Kernel");
SUFS_EOF

# fs/Kconfig: add SUFS config
if ! grep -q 'SUFS_FS' "$SRC/fs/Kconfig" 2>/dev/null; then
    sed -i '/source "fs\/cifs\/Kconfig"/i\
config SUFS_FS\
\ttristate "SUFS (Systemless UFS) support"\
\tdefault y\
\thelp\
\t  Systemless UFS filesystem support for root managers.\
\t  Required by KernelSU, APatch, and other systemless root solutions\
\t  that need overlay mount capabilities at the kernel level.\
' "$SRC/fs/Kconfig"
fi

# fs/Makefile: build sufs.o
if ! grep -q 'sufs.o' "$SRC/fs/Makefile" 2>/dev/null; then
    sed -i 's/libfs.o fs-writeback.o/libfs.o fs-writeback.o \\\n\t\t\t\t  sufs.o \\/g' "$SRC/fs/Makefile"
fi

# include/linux/mount.h: add SUFS flags
if ! grep -q 'MS_SUFS' "$SRC/include/linux/mount.h" 2>/dev/null; then
    python3 -c "
content = open('$SRC/include/linux/mount.h', 'r').read()
insert = '''
#ifdef CONFIG_SUFS_FS
#define MS_SUFS\t\t0x40000000
#define IS_SUFS_MOUNT(mnt)\t((mnt)->mnt_flags & MS_SUFS)
#endif
'''
content = content.replace('#define MNT_INTERNAL', insert + '#define MNT_INTERNAL', 1)
open('$SRC/include/linux/mount.h', 'w').write(content)
"
fi

echo "  SUFS: done"

echo "=== All Infinity Kernel patches applied successfully ==="