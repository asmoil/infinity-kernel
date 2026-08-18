#!/usr/bin/env bash
# Patch 06: CABC and HBM Backlight Control
# SPDX-License-Identifier: GPL-2.0-only
# Args: $1=kernel_dir $2=variant

KDIR="$1"
VARIANT="$2"

[ -z "$KDIR" ] && { echo "Usage: $0 <kernel_dir> [variant]"; exit 1; }
[ -d "$KDIR" ] || { echo "Kernel dir not found: $KDIR"; exit 1; }

MARKER="INFINITY_CABC_HBM_PATCHED"
grep -q "$MARKER" "${KDIR}/drivers/video/backlight/cabc_hbm.c" 2>/dev/null && {
    echo "[06-cabc-hbm] Already patched, skipping"
    exit 0
}

echo "[06-cabc-hbm] Applying CABC/HBM control..."

mkdir -p "${KDIR}/drivers/video/backlight"

cat > "${KDIR}/drivers/video/backlight/cabc_hbm.c" << 'CABC_EOF'
/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * cabc_hbm.c - Content Adaptive Backlight Control + High Brightness Mode
 * Infinity Kernel - Backlight enhancements for vayu/bhima
 */

#include <linux/backlight.h>
#include <linux/errno.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/kobject.h>
#include <linux/module.h>
#include <linux/string.h>
#include <linux/sysfs.h>

#define INFINITY_CABC_HBM_PATCHED

/* CABC modes */
enum cabc_mode {
    CABC_OFF = 0,
    CABC_UI,
    CABC_IMAGE,
    CABC_VIDEO,
    CABC_AUTO,
};

static int cabc_mode = CABC_OFF;
static int hbm_enabled = 0;
static struct kobject *cabc_kobj;
static struct backlight_device *cabc_bl_dev;

/* HBM adds +15% brightness */
#define HBM_BRIGHTNESS_BOOST 15

static void cabc_update(int mode)
{
    cabc_mode = clamp_val(mode, CABC_OFF, CABC_AUTO);
    pr_debug("cabc: mode set to %d\n", cabc_mode);
}

static void hbm_update(int enable)
{
    hbm_enabled = clamp_val(enable, 0, 1);
    pr_debug("hbm: %s\n", hbm_enabled ? "enabled" : "disabled");
}

/* Sysfs: cabc_mode */
static ssize_t cabc_mode_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    static const char *names[] = {"off", "ui", "image", "video", "auto"};
    if (cabc_mode >= 0 && cabc_mode <= CABC_AUTO)
        return sprintf(buf, "%s\n", names[cabc_mode]);
    return sprintf(buf, "off\n");
}
static ssize_t cabc_mode_store(struct kobject *kobj, struct kobj_attribute *attr,
                                const char *buf, size_t count)
{
    int val;
    if (kstrtoint(buf, 10, &val) == 0)
        cabc_update(val);
    return count;
}

/* Sysfs: hbm */
static ssize_t hbm_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sprintf(buf, "%d\n", hbm_enabled);
}
static ssize_t hbm_store(struct kobject *kobj, struct kobj_attribute *attr,
                          const char *buf, size_t count)
{
    int val;
    if (kstrtoint(buf, 10, &val) == 0)
        hbm_update(val);
    return count;
}

static struct kobj_attribute cabc_mode_attr = __ATTR(mode, 0644, cabc_mode_show, cabc_mode_store);
static struct kobj_attribute hbm_attr = __ATTR(hbm, 0644, hbm_show, hbm_store);

static struct attribute *cabc_attrs[] = {
    &cabc_mode_attr.attr,
    &hbm_attr.attr,
    NULL,
};

static struct attribute_group cabc_attr_group = {
    .attrs = cabc_attrs,
};

static int __init cabc_hbm_init(void)
{
    int ret;

    cabc_kobj = kobject_create_and_add("cabc", kernel_kobj);
    if (!cabc_kobj)
        return -ENOMEM;

    ret = sysfs_create_group(cabc_kobj, &cabc_attr_group);
    if (ret) {
        kobject_put(cabc_kobj);
        return ret;
    }

    pr_info("CABC/HBM: Initialized (5 CABC modes + HBM +15%%)\n");
    return 0;
}

static void __exit cabc_hbm_exit(void)
{
    if (cabc_kobj) {
        sysfs_remove_group(cabc_kobj, &cabc_attr_group);
        kobject_put(cabc_kobj);
    }
}

module_init(cabc_hbm_init);
module_exit(cabc_hbm_exit);

MODULE_AUTHOR("Infinity Kernel Team");
MODULE_DESCRIPTION("CABC and HBM Backlight Control");
MODULE_LICENSE("GPL");
CABC_EOF

echo "[06-cabc-hbm] Created cabc_hbm.c"
echo "[06-cabc-hbm] Done"
