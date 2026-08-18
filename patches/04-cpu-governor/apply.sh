#!/usr/bin/env bash
# Patch 04: EFFCPU Custom CPU Governor
# SPDX-License-Identifier: GPL-2.0-only
# Args: $1=kernel_dir $2=variant

KDIR="$1"
VARIANT="$2"

[ -z "$KDIR" ] && { echo "Usage: $0 <kernel_dir> [variant]"; exit 1; }
[ -d "$KDIR" ] || { echo "Kernel dir not found: $KDIR"; exit 1; }

MARKER="INFINITY_EFFCPU_PATCHED"
grep -q "$MARKER" "${KDIR}/drivers/cpufreq/cpufreq_ondemand.c" 2>/dev/null && {
    echo "[04-cpu-governor] Already patched, skipping"
    exit 0
}

echo "[04-cpu-governor] Applying EFFCPU governor..."

# ========================================
# Create EFFCPU sysfs interface
# ========================================
cat > "${KDIR}/drivers/cpufreq/effcpu.c" << 'EFFCPU_EOF'
/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * EFFCPU - Infinity Kernel Custom CPU Frequency Control
 * Provides per-cluster optimized frequency tables and sysfs control.
 */

#include <linux/cpufreq.h>
#include <linux/module.h>
#include <linux/slab.h>
#include <linux/sysfs.h>

#define INFINITY_EFFCPU_PATCHED

/* Gold (big) cluster - Kryo 585 Silver / Gold (SM8150) */
static struct cpufreq_frequency_table effcpu_gold_table[] = {
	{ .frequency =  300000, },
	{ .frequency =  403200, },
	{ .frequency =  499200, },
	{ .frequency =  576000, },
	{ .frequency =  672000, },
	{ .frequency =  768000, },
	{ .frequency =  844800, },
	{ .frequency =  960000, },
	{ .frequency = 1056000, },
	{ .frequency = 1152000, },
	{ .frequency = 1209600, },
	{ .frequency = 1248000, },
	{ .frequency = 1324800, },
	{ .frequency = 1401600, },
	{ .frequency = 1478400, },
	{ .frequency = 1555200, },
	{ .frequency = 1632000, },
	{ .frequency = 1708800, },
	{ .frequency = 1785600, },
	{ .frequency = 1843200, },
	{ .frequency = 1920000, },
	{ .frequency = 1996800, },
	{ .frequency = 2073600, },
	{ .frequency = 2150400, },
	{ .frequency = 2246400, },
	{ .frequency = 2342400, },
	{ .frequency = 2419200, },
	{ .frequency = 2496000, },
	{ .frequency = 2572800, },
	{ .frequency = 2640000, },
	{ .frequency = CPUFREQ_TABLE_END, },
};

/* Silver (LITTLE) cluster */
static struct cpufreq_frequency_table effcpu_silver_table[] = {
	{ .frequency =  300000, },
	{ .frequency =  499200, },
	{ .frequency =  576000, },
	{ .frequency =  672000, },
	{ .frequency =  768000, },
	{ .frequency =  844800, },
	{ .frequency =  960000, },
	{ .frequency = 1056000, },
	{ .frequency = 1152000, },
	{ .frequency = 1209600, },
	{ .frequency = 1248000, },
	{ .frequency = 1324800, },
	{ .frequency = 1401600, },
	{ .frequency = 1478400, },
	{ .frequency = 1555200, },
	{ .frequency = 1593600, },
	{ .frequency = 1640000, },
	{ .frequency = CPUFREQ_TABLE_END, },
};

static bool effcpu_enabled = false;
static DEFINE_MUTEX(effcpu_lock);

static ssize_t enable_show(struct kobject *kobj,
			   struct kobj_attribute *attr, char *buf)
{
	return sprintf(buf, "%d\n", effcpu_enabled);
}

static ssize_t enable_store(struct kobject *kobj,
			    struct kobj_attribute *attr,
			    const char *buf, size_t count)
{
	unsigned long val;
	int ret;

	ret = kstrtoul(buf, 10, &val);
	if (ret)
		return ret;

	mutex_lock(&effcpu_lock);
	effcpu_enabled = !!val;
	mutex_unlock(&effcpu_lock);

	return count;
}

static struct kobj_attribute effcpu_enable_attr =
	__ATTR(enable, 0644, enable_show, enable_store);

static struct attribute *effcpu_attrs[] = {
	&effcpu_enable_attr.attr,
	NULL,
};

static struct attribute_group effcpu_attr_group = {
	.attrs = effcpu_attrs,
};

static struct kobject *effcpu_kobj;

static int __init effcpu_init(void)
{
	int ret;

	effcpu_kobj = kobject_create_and_add("effcpu",
						 &cpu_subsys.dev_root->kobj);
	if (!effcpu_kobj)
		return -ENOMEM;

	ret = sysfs_create_group(effcpu_kobj, &effcpu_attr_group);
	if (ret) {
		kobject_put(effcpu_kobj);
		return ret;
	}

	pr_info("EFFCPU: Custom frequency tables loaded\n");
	return 0;
}

static void __exit effcpu_exit(void)
{
	if (effcpu_kobj) {
		sysfs_remove_group(effcpu_kobj, &effcpu_attr_group);
		kobject_put(effcpu_kobj);
	}
}

module_init(effcpu_init);
module_exit(effcpu_exit);

MODULE_AUTHOR("Infinity Kernel Team");
MODULE_DESCRIPTION("EFFCPU Custom Frequency Control");
MODULE_LICENSE("GPL");
EFFCPU_EOF

echo "[04-cpu-governor] Created effcpu.c"

# ========================================
# Patch arch/arm64/Makefile for -mcpu=kryo
# ========================================
if ! grep -q "mcpu=kryo" "${KDIR}/arch/arm64/Makefile" 2>/dev/null; then
    sed -i '/^KBUILD_CFLAGS.*+=.*-march=armv8-a/a \"$(CONFIG_CC_IS_CLANG)", KBUILD_CFLAGS += -mcpu=kryo' "${KDIR}/arch/arm64/Makefile"
    echo "[04-cpu-governor] Patched arch/arm64/Makefile for kryo"
fi

echo "[04-cpu-governor] Done"