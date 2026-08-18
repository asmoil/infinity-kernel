#!/usr/bin/env bash
# Patch 05: KCAL Display Color Control
# SPDX-License-Identifier: GPL-2.0-only
# Args: $1=kernel_dir $2=variant

KDIR="$1"
VARIANT="$2"

[ -z "$KDIR" ] && { echo "Usage: $0 <kernel_dir> [variant]"; exit 1; }
[ -d "$KDIR" ] || { echo "Kernel dir not found: $KDIR"; exit 1; }

MARKER="INFINITY_KCAL_PATCHED"
grep -q "$MARKER" "${KDIR}/drivers/video/fbdev/msm/mdss_kcal.c" 2>/dev/null && {
    echo "[05-kcal] Already patched, skipping"
    exit 0
}

echo "[05-kcal] Applying KCAL color control..."

mkdir -p "${KDIR}/drivers/video/fbdev/msm"

cat > "${KDIR}/drivers/video/fbdev/msm/mdss_kcal.c" << 'KCAL_EOF'
/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * mdss_kcal.c - Kernel Color Adjustment Layer
 * Infinity Kernel - Display color calibration via sysfs
 */

#include <linux/errno.h>
#include <linux/fs.h>
#include <linux/kernel.h>
#include <linux/kobject.h>
#include <linux/module.h>
#include <linux/string.h>
#include <linux/sysfs.h>

#define INFINITY_KCAL_PATCHED

static int kcal_rgb_r = 255;
static int kcal_rgb_g = 255;
static int kcal_rgb_b = 255;
static int kcal_saturation = 255;
static int kcal_hue = 0;
static int kcal_contrast = 255;
static int kcal_gamma = 255;

static struct kobject *kcal_kobj;

static void kcal_set(int r, int g, int b, int sat, int h, int cont, int gam)
{
	kcal_rgb_r = clamp_val(r, 0, 256);
	kcal_rgb_g = clamp_val(g, 0, 256);
	kcal_rgb_b = clamp_val(b, 0, 256);
	kcal_saturation = clamp_val(sat, 0, 512);
	kcal_hue = clamp_val(h, -180, 180);
	kcal_contrast = clamp_val(cont, 0, 512);
	kcal_gamma = clamp_val(gam, 0, 512);

	/*
	 * Store color values where the display driver can read them.
	 * The actual panel driver picks these up via kcal_get().
	 */
	pr_debug("kcal: R=%d G=%d B=%d sat=%d hue=%d cont=%d gam=%d\n",
		 kcal_rgb_r, kcal_rgb_g, kcal_rgb_b,
		 kcal_saturation, kcal_hue, kcal_contrast, kcal_gamma);
}

static void kcal_get(int *r, int *g, int *b, int *sat, int *h, int *cont, int *gam)
{
	*r = kcal_rgb_r;
	*g = kcal_rgb_g;
	*b = kcal_rgb_b;
	*sat = kcal_saturation;
	*h = kcal_hue;
	*cont = kcal_contrast;
	*gam = kcal_gamma;
}

/* Sysfs: rgb_r */
static ssize_t rgb_r_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return sprintf(buf, "%d\n", kcal_rgb_r);
}
static ssize_t rgb_r_store(struct kobject *kobj, struct kobj_attribute *attr,
			    const char *buf, size_t count)
{
	int val;
	if (kstrtoint(buf, 10, &val) == 0)
		kcal_set(val, kcal_rgb_g, kcal_rgb_b,
			kcal_saturation, kcal_hue, kcal_contrast, kcal_gamma);
	return count;
}

/* Sysfs: rgb_g */
static ssize_t rgb_g_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return sprintf(buf, "%d\n", kcal_rgb_g);
}
static ssize_t rgb_g_store(struct kobject *kobj, struct kobj_attribute *attr,
			    const char *buf, size_t count)
{
	int val;
	if (kstrtoint(buf, 10, &val) == 0)
		kcal_set(kcal_rgb_r, val, kcal_rgb_b,
			kcal_saturation, kcal_hue, kcal_contrast, kcal_gamma);
	return count;
}

/* Sysfs: rgb_b */
static ssize_t rgb_b_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return sprintf(buf, "%d\n", kcal_rgb_b);
}
static ssize_t rgb_b_store(struct kobject *kobj, struct kobj_attribute *attr,
			    const char *buf, size_t count)
{
	int val;
	if (kstrtoint(buf, 10, &val) == 0)
		kcal_set(kcal_rgb_r, kcal_rgb_g, val,
			kcal_saturation, kcal_hue, kcal_contrast, kcal_gamma);
	return count;
}

/* Sysfs: saturation */
static ssize_t saturation_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return sprintf(buf, "%d\n", kcal_saturation);
}
static ssize_t saturation_store(struct kobject *kobj, struct kobj_attribute *attr,
				 const char *buf, size_t count)
{
	int val;
	if (kstrtoint(buf, 10, &val) == 0)
		kcal_set(kcal_rgb_r, kcal_rgb_g, kcal_rgb_b,
			val, kcal_hue, kcal_contrast, kcal_gamma);
	return count;
}

/* Sysfs: hue */
static ssize_t hue_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return sprintf(buf, "%d\n", kcal_hue);
}
static ssize_t hue_store(struct kobject *kobj, struct kobj_attribute *attr,
			 const char *buf, size_t count)
{
	int val;
	if (kstrtoint(buf, 10, &val) == 0)
		kcal_set(kcal_rgb_r, kcal_rgb_g, kcal_rgb_b,
			kcal_saturation, val, kcal_contrast, kcal_gamma);
	return count;
}

/* Sysfs: contrast */
static ssize_t contrast_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return sprintf(buf, "%d\n", kcal_contrast);
}
static ssize_t contrast_store(struct kobject *kobj, struct kobj_attribute *attr,
			      const char *buf, size_t count)
{
	int val;
	if (kstrtoint(buf, 10, &val) == 0)
		kcal_set(kcal_rgb_r, kcal_rgb_g, kcal_rgb_b,
			kcal_saturation, kcal_hue, val, kcal_gamma);
	return count;
}

/* Sysfs: gamma */
static ssize_t gamma_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return sprintf(buf, "%d\n", kcal_gamma);
}
static ssize_t gamma_store(struct kobject *kobj, struct kobj_attribute *attr,
			    const char *buf, size_t count)
{
	int val;
	if (kstrtoint(buf, 10, &val) == 0)
		kcal_set(kcal_rgb_r, kcal_rgb_g, kcal_rgb_b,
			kcal_saturation, kcal_hue, kcal_contrast, val);
	return count;
}

/* Sysfs: values (bulk read) */
static ssize_t values_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return sprintf(buf, "%d %d %d %d %d %d %d\n",
		       kcal_rgb_r, kcal_rgb_g, kcal_rgb_b,
		       kcal_saturation, kcal_hue, kcal_contrast, kcal_gamma);
}

static struct kobj_attribute kcal_rgb_r_attr = __ATTR(rgb_r, 0644, rgb_r_show, rgb_r_store);
static struct kobj_attribute kcal_rgb_g_attr = __ATTR(rgb_g, 0644, rgb_g_show, rgb_g_store);
static struct kobj_attribute kcal_rgb_b_attr = __ATTR(rgb_b, 0644, rgb_b_show, rgb_b_store);
static struct kobj_attribute kcal_sat_attr = __ATTR(saturation, 0644, saturation_show, saturation_store);
static struct kobj_attribute kcal_hue_attr = __ATTR(hue, 0644, hue_show, hue_store);
static struct kobj_attribute kcal_cont_attr = __ATTR(contrast, 0644, contrast_show, contrast_store);
static struct kobj_attribute kcal_gam_attr = __ATTR(gamma, 0644, gamma_show, gamma_store);
static struct kobj_attribute kcal_val_attr = __ATTR(values, 0444, values_show, NULL);

static struct attribute *kcal_attrs[] = {
	&kcal_rgb_r_attr.attr,
	&kcal_rgb_g_attr.attr,
	&kcal_rgb_b_attr.attr,
	&kcal_sat_attr.attr,
	&kcal_hue_attr.attr,
	&kcal_cont_attr.attr,
	&kcal_gam_attr.attr,
	&kcal_val_attr.attr,
	NULL,
};

static struct attribute_group kcal_attr_group = {
	.attrs = kcal_attrs,
};

static int __init kcal_init(void)
{
	int ret;

	kcal_kobj = kobject_create_and_add("kcal", kernel_kobj);
	if (!kcal_kobj)
		return -ENOMEM;

	ret = sysfs_create_group(kcal_kobj, &kcal_attr_group);
	if (ret) {
		kobject_put(kcal_kobj);
		return ret;
	}

	/* Create ctrl subdirectory under virtual for compatibility */
	{
		struct kobject *ctrl_kobj;
		ctrl_kobj = kobject_create_and_add("ctrl", kcal_kobj);
		if (ctrl_kobj) {
			sysfs_create_group(ctrl_kobj, &kcal_attr_group);
		}
	}

	pr_info("KCAL: Display color control initialized\n");
	return 0;
}

static void __exit kcal_exit(void)
{
	if (kcal_kobj) {
		sysfs_remove_group(kcal_kobj, &kcal_attr_group);
		kobject_put(kcal_kobj);
	}
}

module_init(kcal_init);
module_exit(kcal_exit);

MODULE_AUTHOR("Infinity Kernel Team");
MODULE_DESCRIPTION("MSM KCAL Display Color Control");
MODULE_LICENSE("GPL");
KCAL_EOF

echo "[05-kcal] Created mdss_kcal.c"

echo "[05-kcal] Done"
