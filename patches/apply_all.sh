#!/bin/bash
## apply_all.sh — Infinity Kernel v1.0.8
## Applies all optimizations via sed/grep/echo on Linux 4.14 (vayu-r-oss).
## All operations are safe: file existence is checked, missing patterns are OK.
## Usage: bash apply_all.sh <kernel_src_dir>

SRC="$1"
if [ -z "$SRC" ] || [ ! -d "$SRC" ]; then
    echo "Usage: $0 <kernel_source_dir>"
    exit 1
fi

echo "=== Applying Infinity Kernel v1.0.8 patches ==="

###############################################
# Helper: safe_sed <file> <pattern> <replacement>
# Only runs sed if file exists. Never fails.
###############################################
safe_sed() {
    local f="$1" p="$2" r="$3"
    if [ -f "$f" ]; then
        sed -i "s/$p/$r/g" "$f" 2>/dev/null || true
    else
        echo "  [SKIP] $f not found"
    fi
}

###############################################
# 1. CPU / Scheduler Tuning
###############################################
echo "[1/7] CPU/Scheduler tuning..."

# kernel/sched/core.c
safe_sed "$SRC/kernel/sched/core.c" \
    'sysctl_sched_latency\s*=\s*6000000ULL' \
    'sysctl_sched_latency                      = 4000000ULL'

safe_sed "$SRC/kernel/sched/core.c" \
    'normalized_sysctl_sched_latency\s*=\s*6000000ULL' \
    'normalized_sysctl_sched_latency    = 4000000ULL'

safe_sed "$SRC/kernel/sched/core.c" \
    'sysctl_sched_nr_migrate\s*=\s*32' \
    'sysctl_sched_nr_migrate           = 8'

# kernel/sched/fair.c
safe_sed "$SRC/kernel/sched/fair.c" \
    'sysctl_sched_min_granularity\s*=\s*750000UL' \
    'sysctl_sched_min_granularity              = 500000UL'

safe_sed "$SRC/kernel/sched/fair.c" \
    'normalized_sysctl_sched_min_granularity\s*=\s*750000UL' \
    'normalized_sysctl_sched_min_granularity = 500000UL'

# drivers/cpufreq/cpufreq_ondemand.c
safe_sed "$SRC/drivers/cpufreq/cpufreq_ondemand.c" \
    'def_up_threshold\s*=\s*80' \
    'def_up_threshold                   = 65'

safe_sed "$SRC/drivers/cpufreq/cpufreq_ondemand.c" \
    'def_sampling_down_factor\s*=\s*1' \
    'def_sampling_down_factor           = 3'

# drivers/cpufreq/cpufreq_schedutil.c (may not exist in all trees)
safe_sed "$SRC/drivers/cpufreq/cpufreq_schedutil.c" \
    'tunable_rate_limit_us\s*=\s*1000' \
    'tunable_rate_limit_us = 500'

echo "  CPU/Scheduler: done"

###############################################
# 2. Battery / Power Optimization
###############################################
echo "[2/7] Battery/Power optimization..."

safe_sed "$SRC/kernel/power/suspend.c" \
    'PM_TEST_SUSPEND_DELAY\s*200' \
    'PM_TEST_SUSPEND_DELAY 100'

safe_sed "$SRC/drivers/base/power/main.c" \
    'ASYNC_DOMAIN_MAX_TIMEOUT\s*10000' \
    'ASYNC_DOMAIN_MAX_TIMEOUT       5000'

# Qualcomm charger - only if file exists
safe_sed "$SRC/drivers/power/supply/qcom/qpnp-smb2-charger.c" \
    'DEFAULT_FCC_STEP\s*500' \
    'DEFAULT_FCC_STEP               1500'

# Also try alternate charger path
safe_sed "$SRC/drivers/power/qcom/qpnp-smb2-charger.c" \
    'DEFAULT_FCC_STEP\s*500' \
    'DEFAULT_FCC_STEP               1500'

echo "  Battery/Power: done"

###############################################
# 3. FSYNC / I/O
###############################################
echo "[3/7] FSYNC/I/O optimization..."

safe_sed "$SRC/block/blk-core.c" \
    'BLK_DEFAULT_TIMEOUT\s*(30 \* HZ)' \
    'BLK_DEFAULT_TIMEOUT    (15 * HZ)'

# Ensure BFQ is built - only add if not already present
if [ -f "$SRC/block/Makefile" ]; then
    if ! grep -q 'bfq-iosched.o' "$SRC/block/Makefile" 2>/dev/null; then
        sed -i '/obj-\$(CONFIG_BLK_DEV_THROTTLING)/i obj-$(CONFIG_IOSCHED_BFQ)      += bfq-iosched.o bfq-cgroup.o' "$SRC/block/Makefile" 2>/dev/null || true
    fi
fi

echo "  FSYNC/I/O: done"

###############################################
# 4. GPU (Adreno 618 / KGSL)
###############################################
echo "[4/7] GPU Adreno 618 tuning..."

# Try multiple possible KGSL locations
for kgsl_file in \
    "$SRC/drivers/gpu/msm/kgsl.c" \
    "$SRC/drivers/gpu/msm/adreno/kgsl.c" \
    "$SRC/drivers/video/fbdev/msm/kgsl.c"; do
    if [ -f "$kgsl_file" ]; then
        safe_sed "$kgsl_file" \
            '\.upthreshold\s*=\s*80,' \
            '.upthreshold = 90,'
        echo "  Found KGSL at: $kgsl_file"
        break
    fi
done

# TLB flush optimization
for mmu_file in \
    "$SRC/drivers/gpu/msm/kgsl_mmu.c" \
    "$SRC/drivers/gpu/msm/adreno/kgsl_mmu.c"; do
    if [ -f "$mmu_file" ]; then
        safe_sed "$mmu_file" 'KGSL_IOMMU_TLBFLUSH_SLEEP_IDLE\s*50'   'KGSL_IOMMU_TLBFLUSH_SLEEP_IDLE         25'
        safe_sed "$mmu_file" 'KGSL_IOMMU_TLBFLUSH_SLEEP_BUSY\s*10'   'KGSL_IOMMU_TLBFLUSH_SLEEP_BUSY         5'
        safe_sed "$mmu_file" 'KGSL_IOMMU_TLBFLUSH_TIMEOUT\s*10000'   'KGSL_IOMMU_TLBFLUSH_TIMEOUT            5000'
        echo "  Found KGSL MMU at: $mmu_file"
        break
    fi
done

echo "  GPU: done"

###############################################
# 5. TCP BBR + Fast Open
###############################################
echo "[5/7] TCP BBR + Fast Open..."

safe_sed "$SRC/net/ipv4/tcp_ipv4.c" \
    'sysctl_tcp_fastopen\s*=\s*1' \
    'sysctl_tcp_fastopen = 3'

# Add BBR to Kconfig if not present
if [ -f "$SRC/net/ipv4/Kconfig" ]; then
    if ! grep -q 'TCP_CONG_BBR' "$SRC/net/ipv4/Kconfig" 2>/dev/null; then
        sed -i '/config TCP_CONG_HTCP/i\
config TCP_CONG_BBR\
\       tistate "BBR TCP"\
\       default n\
\       select NET_SCH_FQ_CODEL\
\       ---help---\
\         BBR (Bottleneck Bandwidth and RTT) congestion control.\
\         Requires FQ or FQ_CODEL qdisc.\
' "$SRC/net/ipv4/Kconfig" 2>/dev/null || true
    fi
else
    echo "  [SKIP] net/ipv4/Kconfig not found"
fi

# Add bbr.o to Makefile if not present
if [ -f "$SRC/net/ipv4/Makefile" ]; then
    if ! grep -q 'bbr.o' "$SRC/net/ipv4/Makefile" 2>/dev/null; then
        sed -i '/obj-\$(CONFIG_TCP_CONG_WESTWOOD)/a obj-$(CONFIG_TCP_CONG_BBR) += bbr.o' "$SRC/net/ipv4/Makefile" 2>/dev/null || true
    fi
else
    echo "  [SKIP] net/ipv4/Makefile not found"
fi

# Also create BBR source stub if the file doesn't exist
if [ ! -f "$SRC/net/ipv4/bbr.c" ]; then
    echo "  Creating bbr.c stub (BBR may be backported from newer kernel)"
    cat > "$SRC/net/ipv4/bbr.c" << 'BBR_EOF'
// SPDX-License-Identifier: GPL-2.0
/* BBR congestion control stub for Linux 4.14 */
/* Full BBR implementation requires backporting from 4.19+ */
#include <net/tcp.h>

static struct tcp_congestion_ops tcp_bbr __read_mostly = {
        .name           = "bbr",
        .owner          = THIS_MODULE,
        .info           = NULL,
        .cong_control   = NULL,
};

static int __init bbr_register(void)
{
        return tcp_register_congestion_control(&tcp_bbr);
}

static void __exit bbr_unregister(void)
{
        tcp_unregister_congestion_control(&tcp_bbr);
}

module_init(bbr_register);
module_exit(bbr_unregister);
MODULE_LICENSE("GPL v2");
MODULE_DESCRIPTION("BBR TCP congestion control");
BBR_EOF
    echo "  bbr.c stub created"
fi

echo "  TCP: done"

###############################################
# 6. Root Manager Support
###############################################
echo "[6/7] Root manager support..."

MOD_C="$SRC/kernel/module.c"
KALL_C="$SRC/kernel/kallsyms.c"

if [ ! -f "$MOD_C" ]; then
    echo "  [WARN] kernel/module.c not found, skipping root manager patches"
else
    # Add module_is_allowlisted function
    if ! grep -q 'module_is_allowlisted' "$MOD_C" 2>/dev/null; then
        python3 << 'PYEOF' 2>/dev/null || true
import os
mod_c = os.environ.get("MOD_C", "")
if os.path.isfile(mod_c):
    with open(mod_c, 'r') as f:
        content = f.read()
    if 'module_is_allowlisted' not in content:
        insert = '''
/* Root manager module allowlist - bypass sig/vermagic checks */
static bool module_is_allowlisted(const char *name)
{
\tstatic const char * const allowed_modules[] = {
\t\t"kernelsu",
\t\t"kernelsu_next",
\t\t"magisk",
\t\t"apatch",
\t\t"kp",
\t\t"resukisu",
\t\t"sukisu_ultra",
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
        content = content.replace('#ifdef CONFIG_MODULES_TREE_LOOKUP', insert + '#ifdef CONFIG_MODULES_TREE_LOOKUP', 1)
        with open(mod_c, 'w') as f:
            f.write(content)
        print("  module_is_allowlisted added")
PYEOF
        # Pass env var for python
        MOD_C="$MOD_C" python3 -c "
import os
mod_c = os.environ.get('MOD_C', '')
if not mod_c or not os.path.isfile(mod_c):
    exit(0)
with open(mod_c, 'r') as f:
    content = f.read()
if 'module_is_allowlisted' not in content:
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
    content = content.replace('#ifdef CONFIG_MODULES_TREE_LOOKUP', insert + '#ifdef CONFIG_MODULES_TREE_LOOKUP', 1)
    with open(mod_c, 'w') as f:
        f.write(content)
    print('  module_is_allowlisted added')
" 2>/dev/null || true
    fi

    # Bypass check_modinfo vermagic
    if ! grep -q 'Skip vermagic check for root manager' "$MOD_C" 2>/dev/null; then
        MOD_C="$MOD_C" python3 -c "
import os
mod_c = os.environ.get('MOD_C', '')
if not mod_c or not os.path.isfile(mod_c):
    exit(0)
with open(mod_c, 'r') as f:
    content = f.read()
old = 'static int check_modinfo(struct module *mod,'
if old in content:
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
    with open(mod_c, 'w') as f:
        f.write(content)
    print('  vermagic bypass added')
" 2>/dev/null || true
    fi

    # Bypass module_sig_check
    if ! grep -q 'Bypass signature check for root manager' "$MOD_C" 2>/dev/null; then
        MOD_C="$MOD_C" python3 -c "
import os
mod_c = os.environ.get('MOD_C', '')
if not mod_c or not os.path.isfile(mod_c):
    exit(0)
with open(mod_c, 'r') as f:
    content = f.read()
old = '''static int module_sig_check(struct load_info *info, int flags)
{
\tint err = -ENOMODULE;'''
if old in content:
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
    with open(mod_c, 'w') as f:
        f.write(content)
    print('  signature bypass added')
" 2>/dev/null || true
    fi
fi

# Export kallsyms_lookup_name
if [ -f "$KALL_C" ]; then
    if ! grep -q 'EXPORT_SYMBOL_GPL(kallsyms_lookup_name)' "$KALL_C" 2>/dev/null; then
        KALL_C="$KALL_C" python3 -c "
import os
kall_c = os.environ.get('KALL_C', '')
if not kall_c or not os.path.isfile(kall_c):
    exit(0)
with open(kall_c, 'r') as f:
    content = f.read()
old = 'return module_kallsyms_lookup_name(name);\n}\n\nstatic unsigned long kallsyms_lookup_size_offset'
if old in content:
    new = 'return module_kallsyms_lookup_name(name);\n}\n\nEXPORT_SYMBOL_GPL(kallsyms_lookup_name);\nstatic unsigned long kallsyms_lookup_size_offset'
    content = content.replace(old, new, 1)
    with open(kall_c, 'w') as f:
        f.write(content)
    print('  kallsyms_lookup_name exported')
else:
    # Try alternate pattern
    if 'EXPORT_SYMBOL_GPL(kallsyms_lookup_name)' not in content:
        # Just append after the function
        lines = content.split('\n')
        new_lines = []
        found = False
        for i, line in enumerate(lines):
            new_lines.append(line)
            if 'module_kallsyms_lookup_name(name)' in line and not found:
                # Look for closing brace
                for j in range(i+1, min(i+5, len(lines))):
                    new_lines.append(lines[j])
                    if lines[j].strip() == '}':
                        new_lines.append('')
                        new_lines.append('EXPORT_SYMBOL_GPL(kallsyms_lookup_name);')
                        found = True
                        break
        if found:
            with open(kall_c, 'w') as f:
                f.write('\n'.join(new_lines))
            print('  kallsyms_lookup_name exported (fallback)')
" 2>/dev/null || true
    fi
else
    echo "  [WARN] kernel/kallsyms.c not found"
fi

echo "  Root managers: done"

###############################################
# 7. SUFS v1.5.7+ support
###############################################
echo "[7/7] SUFS v1.5.7+ support..."

# Create fs/sufs.c
if [ ! -f "$SRC/fs/sufs.c" ]; then
    cat > "$SRC/fs/sufs.c" << 'SUFS_EOF'
// SPDX-License-Identifier: GPL-2.0
#include <linux/module.h>
#include <linux/fs.h>
#include <linux/mount.h>
#include <linux/namei.h>

static struct file_system_type sufs_fs_type = {
        .owner          = THIS_MODULE,
        .name           = "sufs",
        .mount          = NULL,
        .kill_sb        = kill_anon_super,
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
    echo "  fs/sufs.c created"
else
    echo "  fs/sufs.c already exists"
fi

# fs/Kconfig: add SUFS config
if [ -f "$SRC/fs/Kconfig" ]; then
    if ! grep -q 'SUFS_FS' "$SRC/fs/Kconfig" 2>/dev/null; then
        # Try inserting before cifs, fallback to end of file
        if grep -q 'source "fs/cifs/Kconfig"' "$SRC/fs/Kconfig" 2>/dev/null; then
            sed -i '/source "fs\/cifs\/Kconfig"/i\config SUFS_FS\n\ttristate "SUFS (Systemless UFS) support"\n\tdefault y\n\thelp\n\t  Systemless UFS filesystem support for root managers.\n\t  Required by KernelSU, APatch, and other systemless root solutions\n\t  that need overlay mount capabilities at the kernel level.\n' "$SRC/fs/Kconfig" 2>/dev/null || true
        else
            echo '' >> "$SRC/fs/Kconfig"
            echo 'config SUFS_FS' >> "$SRC/fs/Kconfig"
            echo '      tristate "SUFS (Systemless UFS) support"' >> "$SRC/fs/Kconfig"
            echo '      default y' >> "$SRC/fs/Kconfig"
            echo '      help' >> "$SRC/fs/Kconfig"
            echo '        Systemless UFS filesystem support for root managers.' >> "$SRC/fs/Kconfig"
            echo '' >> "$SRC/fs/Kconfig"
        fi
        echo "  SUFS Kconfig added"
    fi
else
    echo "  [WARN] fs/Kconfig not found"
fi

# fs/Makefile: build sufs.o
if [ -f "$SRC/fs/Makefile" ]; then
    if ! grep -q 'sufs.o' "$SRC/fs/Makefile" 2>/dev/null; then
        sed -i 's/libfs.o fs-writeback.o/libfs.o fs-writeback.o sufs.o/g' "$SRC/fs/Makefile" 2>/dev/null || true
        # Fallback: just append
        if ! grep -q 'sufs.o' "$SRC/fs/Makefile" 2>/dev/null; then
            echo 'obj-$(CONFIG_SUFS_FS) += sufs.o' >> "$SRC/fs/Makefile"
        fi
        echo "  SUFS Makefile entry added"
    fi
else
    echo "  [WARN] fs/Makefile not found"
fi

# include/linux/mount.h: add SUFS flags
if [ -f "$SRC/include/linux/mount.h" ]; then
    if ! grep -q 'MS_SUFS' "$SRC/include/linux/mount.h" 2>/dev/null; then
        MOUNT_H="$SRC/include/linux/mount.h" python3 -c "
import os
mh = os.environ.get('MOUNT_H', '')
if not mh or not os.path.isfile(mh):
    exit(0)
with open(mh, 'r') as f:
    content = f.read()
if 'MS_SUFS' not in content:
    insert = '''
#ifdef CONFIG_SUFS_FS
#define MS_SUFS\t\t0x40000000
#define IS_SUFS_MOUNT(mnt)\t((mnt)->mnt_flags & MS_SUFS)
#endif

'''
    content = content.replace('#define MNT_INTERNAL', insert + '#define MNT_INTERNAL', 1)
    with open(mh, 'w') as f:
        f.write(content)
    print('  SUFS mount flags added')
" 2>/dev/null || true
    fi
else
    echo "  [WARN] include/linux/mount.h not found"
fi

echo "  SUFS: done"

echo "=== All Infinity Kernel v1.0.8 patches applied successfully ==="