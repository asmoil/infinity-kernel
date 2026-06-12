/*
 * Infinity Charging Bypass Control Driver
 *
 * Copyright (c) 2024 Infinity Kernel Project
 * Author: Infinity Kernel Team
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 *
 * Platform driver providing charge-current limiting with four gaming
 * profiles, thermal-cooldown logic, low-battery auto-resume, sysfs
 * and IOCTL interfaces.  Targets Linux 4.14.180 on Poco X3 Pro
 * (vayu/bhima, Snapdragon 732G / SM7150-AC).
 *
 * Power-supply integration reads live battery temperature and capacity
 * from the PMI8998 / SMB2 charger fuel-gauge exposed through the
 * standard Linux power-supply class.
 */

#define pr_fmt(fmt) "infinity_charge: " fmt

#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/of_device.h>
#include <linux/cdev.h>
#include <linux/fs.h>
#include <linux/slab.h>
#include <linux/delay.h>
#include <linux/mutex.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/power_supply.h>
#include <linux/sched.h>
#include <linux/uaccess.h>
#include <linux/ioctl.h>
#include <linux/init.h>
#include <linux/kernel.h>

#include <linux/infinity_charging_control.h>

/* ================================================================== */
/*  Driver Constants                                                   */
/* ================================================================== */

#define DRIVER_NAME       "infinity_charging_control"
#define DRIVER_CLASS_NAME "infinity-charge"
#define CHARDEV_NAME      "infinity_charge"
#define POLL_INTERVAL_MS  2000  /* 2 s between thermal / capacity checks */
#define MAX_STATUS_LEN    128

/* ================================================================== */
/*  Per-Instance Context                                               */
/* ================================================================== */

struct infinity_charge_ctx {
	/* --- Configuration (set once from DT / module param) --- */
	int cooldown_temp;       /* millidegrees C to pause charging   */
	int resume_temp;         /* millidegrees C to resume charging   */
	int low_batt_cap;        /* percent – auto-resume threshold     */
	int current_limits[CHARGING_MODE_MAX]; /* mA per mode index     */

	/* --- Mutable state --- */
	int mode;                /* enum charging_mode                  */
	bool enabled;            /* bypass active flag                  */
	bool thermal_cooldown;   /* currently throttled by temp         */
	int batt_temp;           /* cached batt temp (m°C)              */
	int batt_capacity;       /* cached batt capacity (0-100 %)      */
	int active_limit;        /* current mA limit applied            */

	/* --- Synchronisation --- */
	struct mutex lock;       /* protects mutable state              */

	/* --- Periodic poll --- */
	struct delayed_work poll_work;

	/* --- Misc --- */
	struct device *dev;      /* for dev_* logging helpers          */
	struct power_supply *batt_psy;
};

static struct infinity_charge_ctx *g_ctx;   /* singleton for sysfs / ioctl */

/* ================================================================== */
/*  Mode-to-string helpers                                             */
/* ================================================================== */

static const char *mode_to_str(int mode)
{
	switch (mode) {
	case CHARGING_MODE_DISABLED:  return "DISABLED";
	case CHARGING_MODE_LIGHT:     return "LIGHT";
	case CHARGING_MODE_BALANCED:  return "BALANCED";
	case CHARGING_MODE_EXTREME:   return "EXTREME";
	case CHARGING_MODE_ULTRA:     return "ULTRA";
	default:                      return "UNKNOWN";
	}
}

static int str_to_mode(const char *buf, size_t len)
{
	if (len >= 4 && !strncasecmp(buf, "light", 5))
		return CHARGING_MODE_LIGHT;
	if (len >= 5 && !strncasecmp(buf, "balanced", 8))
		return CHARGING_MODE_BALANCED;
	if (len >= 4 && !strncasecmp(buf, "extreme", 7))
		return CHARGING_MODE_EXTREME;
	if (len >= 4 && !strncasecmp(buf, "ultra", 5))
		return CHARGING_MODE_ULTRA;
	if (len >= 4 && !strncasecmp(buf, "disabled", 8))
		return CHARGING_MODE_DISABLED;
	/* Try numeric */
	if (kstrtoint(buf, 10, &len) == 0 && len >= 0 && len < CHARGING_MODE_MAX)
		return len;
	return -EINVAL;
}

/* ================================================================== */
/*  Power Supply Integration                                           */
/* ================================================================== */

/**
 * refresh_battery_status() - Read temp & capacity from power_supply.
 *
 * We look for a battery power_supply named "battery" (standard on
 * Qualcomm PMI8998 platforms).  On failure we keep the last-known
 * values so the driver degrades gracefully.
 */
static void refresh_battery_status(struct infinity_charge_ctx *ctx)
{
	union power_supply_propval val = { .intval = 0 };

	if (!ctx->batt_psy) {
		ctx->batt_psy = power_supply_get_by_name("battery");
		if (!ctx->batt_psy)
			return;
	}

	if (power_supply_get_property(ctx->batt_psy,
				POWER_SUPPLY_PROP_TEMP, &val) == 0)
		ctx->batt_temp = val.intval;

	if (power_supply_get_property(ctx->batt_psy,
				POWER_SUPPLY_PROP_CAPACITY, &val) == 0)
		ctx->batt_capacity = val.intval;
}

/**
 * apply_charge_limit() - Tell the charger IC the new current limit.
 *
 * On PMI8998 / SMB2 the fcc (fast-charge-current) is exposed through
 * POWER_SUPPLY_PROP_CONSTANT_CHARGE_CURRENT_MAX.  Writing to it
 * instructs the charger hardware to cap the input current.
 *
 * We skip the write when bypass is disabled so stock charging is
 * untouched.
 */
static void apply_charge_limit(struct infinity_charge_ctx *ctx)
{
	union power_supply_propval val;

	if (!ctx->batt_psy) {
		ctx->batt_psy = power_supply_get_by_name("battery");
		if (!ctx->batt_psy)
			return;
	}

	if (!ctx->enabled || ctx->mode == CHARGING_MODE_DISABLED) {
		ctx->active_limit = 0;
		pr_debug("bypass disabled – leaving stock charge current\n");
		return;
	}

	/* Auto-resume safety: if battery is critically low, disable limit */
	if (ctx->batt_capacity < ctx->low_batt_cap && ctx->batt_capacity >= 0) {
		pr_info("battery %d%% < %d%% – auto-resume full charging\n",
			ctx->batt_capacity, ctx->low_batt_cap);
		val.intval = 0;  /* 0 = restore hardware default */
		power_supply_set_property(ctx->batt_psy,
				POWER_SUPPLY_PROP_CONSTANT_CHARGE_CURRENT_MAX, &val);
		ctx->active_limit = 0;
		return;
	}

	/* Thermal cooldown: drop to minimum safe current */
	if (ctx->thermal_cooldown) {
		val.intval = ctx->current_limits[CHARGING_MODE_ULTRA];
		power_supply_set_property(ctx->batt_psy,
				POWER_SUPPLY_PROP_CONSTANT_CHARGE_CURRENT_MAX, &val);
		ctx->active_limit = val.intval;
		pr_debug("thermal cooldown – limit %d mA\n", val.intval);
		return;
	}

	/* Normal operation – apply profile limit */
	val.intval = ctx->current_limits[ctx->mode] * 1000; /* mA -> µA */
	power_supply_set_property(ctx->batt_psy,
			POWER_SUPPLY_PROP_CONSTANT_CHARGE_CURRENT_MAX, &val);
	ctx->active_limit = ctx->current_limits[ctx->mode];
	pr_debug("mode %s – limit %d mA\n",
		 mode_to_str(ctx->mode), ctx->active_limit);
}

/* ================================================================== */
/*  Periodic Monitoring Worker                                         */
/* ================================================================== */

static void poll_worker(struct work_struct *work)
{
	struct infinity_charge_ctx *ctx =
		container_of(work, struct infinity_charge_ctx, poll_work.work);
	bool prev_cooldown;
	bool need_apply = false;

	mutex_lock(&ctx->lock);

	refresh_battery_status(ctx);

	/* --- Thermal monitoring --- */
	prev_cooldown = ctx->thermal_cooldown;

	if (ctx->batt_temp >= ctx->cooldown_temp && !ctx->thermal_cooldown) {
		ctx->thermal_cooldown = true;
		pr_warn("battery %d m°C >= cooldown %d m°C – throttling\n",
			ctx->batt_temp, ctx->cooldown_temp);
		need_apply = true;
	} else if (ctx->batt_temp <= ctx->resume_temp && ctx->thermal_cooldown) {
		ctx->thermal_cooldown = false;
		pr_info("battery %d m°C <= resume %d m°C – normal charging\n",
			ctx->batt_temp, ctx->resume_temp);
		need_apply = true;
	}

	if (ctx->thermal_cooldown != prev_cooldown)
		need_apply = true;

	/* --- Low-battery auto-resume --- */
	if (ctx->enabled && ctx->batt_capacity < ctx->low_batt_cap
	    && ctx->batt_capacity >= 0) {
		need_apply = true;
	}

	if (need_apply)
		apply_charge_limit(ctx);

	mutex_unlock(&ctx->lock);

	schedule_delayed_work(&ctx->poll_work,
			msecs_to_jiffies(POLL_INTERVAL_MS));
}

/* ================================================================== */
/*  sysfs Attributes                                                   */
/* ================================================================== */

#define SYSFS_ATTR_RO(name) \
static ssize_t name##_show(struct kobject *kobj, \
		struct kobj_attribute *attr, char *buf)

#define SYSFS_ATTR_RW(name) \
static ssize_t name##_show(struct kobject *kobj, \
		struct kobj_attribute *attr, char *buf); \
static ssize_t name##_store(struct kobject *kobj, \
		struct kobj_attribute *attr, const char *buf, size_t count)

/* --- mode --- */
SYSFS_ATTR_RW(mode);

static ssize_t mode_show(struct kobject *kobj,
		struct kobj_attribute *attr, char *buf)
{
	struct infinity_charge_ctx *ctx = g_ctx;
	int mode;

	if (!ctx)
		return -ENODEV;

	mutex_lock(&ctx->lock);
	mode = ctx->mode;
	mutex_unlock(&ctx->lock);

	return scnprintf(buf, PAGE_SIZE, "%s\n", mode_to_str(mode));
}

static ssize_t mode_store(struct kobject *kobj,
		struct kobj_attribute *attr, const char *buf, size_t count)
{
	struct infinity_charge_ctx *ctx = g_ctx;
	int new_mode;

	if (!ctx)
		return -ENODEV;

	new_mode = str_to_mode(buf, count);
	if (new_mode < 0)
		return -EINVAL;

	mutex_lock(&ctx->lock);
	if (new_mode == ctx->mode) {
		mutex_unlock(&ctx->lock);
		return count;
	}
	ctx->mode = new_mode;
	pr_info("mode changed to %s\n", mode_to_str(new_mode));
	apply_charge_limit(ctx);
	mutex_unlock(&ctx->lock);

	return count;
}

/* --- enabled --- */
SYSFS_ATTR_RW(enabled);

static ssize_t enabled_show(struct kobject *kobj,
		struct kobj_attribute *attr, char *buf)
{
	struct infinity_charge_ctx *ctx = g_ctx;
	int en;

	if (!ctx)
		return -ENODEV;

	mutex_lock(&ctx->lock);
	en = ctx->enabled;
	mutex_unlock(&ctx->lock);

	return scnprintf(buf, PAGE_SIZE, "%d\n", en);
}

static ssize_t enabled_store(struct kobject *kobj,
		struct kobj_attribute *attr, const char *buf, size_t count)
{
	struct infinity_charge_ctx *ctx = g_ctx;
	unsigned long val;
	int ret;

	if (!ctx)
		return -ENODEV;

	ret = kstrtoul(buf, 10, &val);
	if (ret)
		return ret;
	if (val > 1)
		return -EINVAL;

	mutex_lock(&ctx->lock);
	if ((bool)val == ctx->enabled) {
		mutex_unlock(&ctx->lock);
		return count;
	}
	ctx->enabled = (bool)val;
	pr_info("bypass %s\n", ctx->enabled ? "enabled" : "disabled");
	apply_charge_limit(ctx);
	mutex_unlock(&ctx->lock);

	return count;
}

/* --- status (read-only, human-readable) --- */
SYSFS_ATTR_RO(status);

static ssize_t status_show(struct kobject *kobj,
		struct kobj_attribute *attr, char *buf)
{
	struct infinity_charge_ctx *ctx = g_ctx;
	char status[MAX_STATUS_LEN];

	if (!ctx)
		return -ENODEV;

	mutex_lock(&ctx->lock);
	snprintf(status, sizeof(status),
		"Mode: %s | Enabled: %s | Limit: %d mA | "
		"Temp: %d m°C | Cap: %d%% | Cooldown: %s\n",
		mode_to_str(ctx->mode),
		ctx->enabled ? "yes" : "no",
		ctx->active_limit,
		ctx->batt_temp,
		ctx->batt_capacity,
		ctx->thermal_cooldown ? "yes" : "no");
	mutex_unlock(&ctx->lock);

	return scnprintf(buf, PAGE_SIZE, "%s", status);
}

/* --- battery_temp (read-only) --- */
SYSFS_ATTR_RO(battery_temp);

static ssize_t battery_temp_show(struct kobject *kobj,
		struct kobj_attribute *attr, char *buf)
{
	struct infinity_charge_ctx *ctx = g_ctx;
	int temp;

	if (!ctx)
		return -ENODEV;

	mutex_lock(&ctx->lock);
	refresh_battery_status(ctx);
	temp = ctx->batt_temp;
	mutex_unlock(&ctx->lock);

	return scnprintf(buf, PAGE_SIZE, "%d\n", temp);
}

/* --- battery_capacity (read-only) --- */
SYSFS_ATTR_RO(battery_capacity);

static ssize_t battery_capacity_show(struct kobject *kobj,
		struct kobj_attribute *attr, char *buf)
{
	struct infinity_charge_ctx *ctx = g_ctx;
	int cap;

	if (!ctx)
		return -ENODEV;

	mutex_lock(&ctx->lock);
	refresh_battery_status(ctx);
	cap = ctx->batt_capacity;
	mutex_unlock(&ctx->lock);

	return scnprintf(buf, PAGE_SIZE, "%d\n", cap);
}

/* --- Attribute array --- */
static struct attribute *charge_attrs[] = {
	&attr_mode.attr,
	&attr_enabled.attr,
	&attr_status.attr,
	&attr_battery_temp.attr,
	&attr_battery_capacity.attr,
	NULL,
};

static const struct attribute_group charge_attr_group = {
	.attrs = charge_attrs,
};

static struct kobject *charge_kobj;

/* ================================================================== */
/*  Char Device / IOCTL                                                */
/* ================================================================== */

static dev_t charge_dev_t;
static struct cdev charge_cdev;
static struct class *charge_class;

static int charge_open(struct inode *inode, struct file *filp)
{
	return 0;
}

static int charge_release(struct inode *inode, struct file *filp)
{
	return 0;
}

static long charge_ioctl(struct file *filp, unsigned int cmd,
			 unsigned long arg)
{
	struct infinity_charge_ctx *ctx = g_ctx;
	void __user *argp = (void __user *)arg;
	int ret = 0, val;

	if (!ctx)
		return -ENODEV;

	switch (cmd) {
	case IOC_CHARGE_GET_MODE:
		mutex_lock(&ctx->lock);
		val = ctx->mode;
		mutex_unlock(&ctx->lock);
		if (copy_to_user(argp, &val, sizeof(val)))
			return -EFAULT;
		break;

	case IOC_CHARGE_SET_MODE:
		if (copy_from_user(&val, argp, sizeof(val)))
			return -EFAULT;
		if (val < 0 || val >= CHARGING_MODE_MAX)
			return -EINVAL;
		mutex_lock(&ctx->lock);
		ctx->mode = val;
		pr_info("ioctl: mode -> %s\n", mode_to_str(val));
		apply_charge_limit(ctx);
		mutex_unlock(&ctx->lock);
		break;

	case IOC_CHARGE_GET_ENABLED:
		mutex_lock(&ctx->lock);
		val = ctx->enabled;
		mutex_unlock(&ctx->lock);
		if (copy_to_user(argp, &val, sizeof(val)))
			return -EFAULT;
		break;

	case IOC_CHARGE_SET_ENABLED:
		if (copy_from_user(&val, argp, sizeof(val)))
			return -EFAULT;
		if (val < 0 || val > 1)
			return -EINVAL;
		mutex_lock(&ctx->lock);
		ctx->enabled = (bool)val;
		pr_info("ioctl: enabled -> %d\n", val);
		apply_charge_limit(ctx);
		mutex_unlock(&ctx->lock);
		break;

	case IOC_CHARGE_GET_STATUS: {
		struct infinity_charge_info info;
		char status[MAX_STATUS_LEN];

		mutex_lock(&ctx->lock);
		refresh_battery_status(ctx);
		info.mode = ctx->mode;
		info.enabled = ctx->enabled;
		info.battery_temp = ctx->batt_temp;
		info.battery_cap = ctx->batt_capacity;
		info.current_limit = ctx->active_limit;
		info.thermal_state = ctx->thermal_cooldown;
		snprintf(status, sizeof(status),
			"Mode:%s Enabled:%d Limit:%dmA Temp:%dm°C Cap:%d%%",
			mode_to_str(info.mode), info.enabled,
			info.current_limit, info.battery_temp,
			info.battery_cap);
		mutex_unlock(&ctx->lock);

		if (copy_to_user(argp, status, min((size_t)MAX_STATUS_LEN,
						(size_t)_IOC_SIZE(cmd))))
			return -EFAULT;
		break;
	}

	case IOC_CHARGE_GET_BATT_TEMP:
		mutex_lock(&ctx->lock);
		refresh_battery_status(ctx);
		val = ctx->batt_temp;
		mutex_unlock(&ctx->lock);
		if (copy_to_user(argp, &val, sizeof(val)))
			return -EFAULT;
		break;

	case IOC_CHARGE_GET_BATT_CAPACITY:
		mutex_lock(&ctx->lock);
		refresh_battery_status(ctx);
		val = ctx->batt_capacity;
		mutex_unlock(&ctx->lock);
		if (copy_to_user(argp, &val, sizeof(val)))
			return -EFAULT;
		break;

	default:
		return -ENOTTY;
	}

	return ret;
}

static const struct file_operations charge_fops = {
	.owner          = THIS_MODULE,
	.open           = charge_open,
	.release        = charge_release,
	.unlocked_ioctl = charge_ioctl,
#ifdef CONFIG_COMPAT
	.compat_ioctl   = charge_ioctl,
#endif
};

/* ================================================================== */
/*  Kernel-internal API (callable from other subsystems)               */
/* ================================================================== */

int infinity_charge_get_current_limit(void)
{
	struct infinity_charge_ctx *ctx = g_ctx;
	int limit = 0;

	if (!ctx)
		return 0;

	mutex_lock(&ctx->lock);
	limit = ctx->active_limit;
	mutex_unlock(&ctx->lock);
	return limit;
}
EXPORT_SYMBOL_GPL(infinity_charge_get_current_limit);

int infinity_charge_is_enabled(void)
{
	struct infinity_charge_ctx *ctx = g_ctx;
	int en = 0;

	if (!ctx)
		return 0;

	mutex_lock(&ctx->lock);
	en = ctx->enabled;
	mutex_unlock(&ctx->lock);
	return en;
}
EXPORT_SYMBOL_GPL(infinity_charge_is_enabled);

int infinity_charge_get_mode(void)
{
	struct infinity_charge_ctx *ctx = g_ctx;
	int mode = 0;

	if (!ctx)
		return 0;

	mutex_lock(&ctx->lock);
	mode = ctx->mode;
	mutex_unlock(&ctx->lock);
	return mode;
}
EXPORT_SYMBOL_GPL(infinity_charge_get_mode);

/* ================================================================== */
/*  Device-Tree Parsing                                                */
/* ================================================================== */

static void parse_dt_defaults(struct device *dev,
			      struct infinity_charge_ctx *ctx)
{
	struct device_node *np = dev->of_node;
	u32 val;

	if (!np)
		return;

	/* Thermal thresholds */
	if (!of_property_read_u32(np, "cooldown-temp-millic", &val))
		ctx->cooldown_temp = (int)val;

	if (!of_property_read_u32(np, "resume-temp-millic", &val))
		ctx->resume_temp = (int)val;

	if (!of_property_read_u32(np, "low-batt-cap-pct", &val))
		ctx->low_batt_cap = (int)val;

	/* Per-mode charge current limits */
	if (!of_property_read_u32_index(np, "charge-current-ma",
			CHARGING_MODE_LIGHT, &val))
		ctx->current_limits[CHARGING_MODE_LIGHT] = (int)val;

	if (!of_property_read_u32_index(np, "charge-current-ma",
			CHARGING_MODE_BALANCED, &val))
		ctx->current_limits[CHARGING_MODE_BALANCED] = (int)val;

	if (!of_property_read_u32_index(np, "charge-current-ma",
			CHARGING_MODE_EXTREME, &val))
		ctx->current_limits[CHARGING_MODE_EXTREME] = (int)val;

	if (!of_property_read_u32_index(np, "charge-current-ma",
			CHARGING_MODE_ULTRA, &val))
		ctx->current_limits[CHARGING_MODE_ULTRA] = (int)val;

	dev_info(dev, "DT config: cooldown=%d m°C  resume=%d m°C  "
		 "low_cap=%d%%  currents=[%d,%d,%d,%d] mA\n",
		 ctx->cooldown_temp, ctx->resume_temp,
		 ctx->low_batt_cap,
		 ctx->current_limits[CHARGING_MODE_LIGHT],
		 ctx->current_limits[CHARGING_MODE_BALANCED],
		 ctx->current_limits[CHARGING_MODE_EXTREME],
		 ctx->current_limits[CHARGING_MODE_ULTRA]);
}

/* ================================================================== */
/*  Platform Driver Probe / Remove                                     */
/* ================================================================== */

static int infinity_charge_probe(struct platform_device *pdev)
{
	struct infinity_charge_ctx *ctx;
	struct device *dev = &pdev->dev;
	int ret;

	/* Allocate context */
	ctx = devm_kzalloc(dev, sizeof(*ctx), GFP_KERNEL);
	if (!ctx)
		return -ENOMEM;

	/* Defaults */
	ctx->cooldown_temp = CHARGE_COOLDOWN_TEMP;
	ctx->resume_temp   = CHARGE_RESUME_TEMP;
	ctx->low_batt_cap  = CHARGE_LOW_BATT_CAP;
	ctx->current_limits[CHARGING_MODE_DISABLED] = 0;
	ctx->current_limits[CHARGING_MODE_LIGHT]    = CHARGE_CURRENT_LIGHT;
	ctx->current_limits[CHARGING_MODE_BALANCED]  = CHARGE_CURRENT_BALANCED;
	ctx->current_limits[CHARGING_MODE_EXTREME]   = CHARGE_CURRENT_EXTREME;
	ctx->current_limits[CHARGING_MODE_ULTRA]     = CHARGE_CURRENT_ULTRA;
	ctx->mode       = CHARGING_MODE_BALANCED;
	ctx->enabled    = false;
	ctx->thermal_cooldown = false;
	ctx->batt_temp  = 25000;  /* sane default until first read */
	ctx->batt_capacity = 50;
	ctx->active_limit = 0;
	ctx->dev       = dev;

	mutex_init(&ctx->lock);
	INIT_DELAYED_WORK(&ctx->poll_work, poll_worker);

	/* Override defaults from DT */
	parse_dt_defaults(dev, ctx);

	/* Store global singleton */
	g_ctx = ctx;

	/* --- sysfs --- */
	charge_kobj = kobject_create_and_add(SYSFS_DIR_NAME, kernel_kobj);
	if (!charge_kobj) {
		dev_err(dev, "failed to create sysfs kobject\n");
		ret = -ENOMEM;
		goto err_sysfs;
	}
	ret = sysfs_create_group(charge_kobj, &charge_attr_group);
	if (ret) {
		dev_err(dev, "failed to create sysfs group: %d\n", ret);
		goto err_sysfs_group;
	}

	/* --- char device --- */
	ret = alloc_chrdev_region(&charge_dev_t, 0, 1, CHARDEV_NAME);
	if (ret) {
		dev_err(dev, "alloc_chrdev_region failed: %d\n", ret);
		goto err_cdev_region;
	}

	cdev_init(&charge_cdev, &charge_fops);
	charge_cdev.owner = THIS_MODULE;
	ret = cdev_add(&charge_cdev, charge_dev_t, 1);
	if (ret) {
		dev_err(dev, "cdev_add failed: %d\n", ret);
		goto err_cdev_add;
	}

	charge_class = class_create(THIS_MODULE, DRIVER_CLASS_NAME);
	if (IS_ERR(charge_class)) {
		dev_err(dev, "class_create failed\n");
		ret = PTR_ERR(charge_class);
		goto err_class;
	}

	if (!device_create(charge_class, NULL, charge_dev_t,
			   NULL, CHARDEV_NAME)) {
		dev_err(dev, "device_create failed\n");
		ret = -ENOMEM;
		goto err_device;
	}

	/* --- Start periodic monitoring --- */
	schedule_delayed_work(&ctx->poll_work,
			msecs_to_jiffies(POLL_INTERVAL_MS));

	/* Initial battery read */
	refresh_battery_status(ctx);

	platform_set_drvdata(pdev, ctx);
	dev_info(dev, "Infinity Charging Bypass loaded – mode=%s enabled=%d\n",
		 mode_to_str(ctx->mode), ctx->enabled);

	return 0;

err_device:
	class_destroy(charge_class);
err_class:
	cdev_del(&charge_cdev);
err_cdev_add:
	unregister_chrdev_region(charge_dev_t, 1);
err_cdev_region:
	sysfs_remove_group(charge_kobj, &charge_attr_group);
err_sysfs_group:
	kobject_put(charge_kobj);
err_sysfs:
	g_ctx = NULL;
	mutex_destroy(&ctx->lock);
	return ret;
}

static int infinity_charge_remove(struct platform_device *pdev)
{
	struct infinity_charge_ctx *ctx = platform_get_drvdata(pdev);

	cancel_delayed_work_sync(&ctx->poll_work);

	device_destroy(charge_class, charge_dev_t);
	class_destroy(charge_class);
	cdev_del(&charge_cdev);
	unregister_chrdev_region(charge_dev_t, 1);

	sysfs_remove_group(charge_kobj, &charge_attr_group);
	kobject_put(charge_kobj);

	g_ctx = NULL;
	mutex_destroy(&ctx->lock);

	dev_info(&pdev->dev, "Infinity Charging Bypass removed\n");
	return 0;
}

/* ================================================================== */
/*  PM Suspend / Resume                                                */
/* ================================================================== */

static int infinity_charge_suspend(struct device *dev)
{
	struct infinity_charge_ctx *ctx = dev_get_drvdata(dev);

	cancel_delayed_work_sync(&ctx->poll_work);
	return 0;
}

static int infinity_charge_resume(struct device *dev)
{
	struct infinity_charge_ctx *ctx = dev_get_drvdata(dev);

	mutex_lock(&ctx->lock);
	refresh_battery_status(ctx);
	apply_charge_limit(ctx);
	mutex_unlock(&ctx->lock);

	schedule_delayed_work(&ctx->poll_work,
			msecs_to_jiffies(POLL_INTERVAL_MS));
	return 0;
}

static const struct dev_pm_ops infinity_charge_pm_ops = {
	.suspend = infinity_charge_suspend,
	.resume  = infinity_charge_resume,
};

/* ================================================================== */
/*  OF Match Table                                                     */
/* ================================================================== */

static const struct of_device_id infinity_charge_of_match[] = {
	{ .compatible = "infinity,charging-control", },
	{ .compatible = "qcom,sm7150-charging-control", },
	{ /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, infinity_charge_of_match);

/* ================================================================== */
/*  Platform Driver Struct                                             */
/* ================================================================== */

static struct platform_driver infinity_charge_driver = {
	.probe  = infinity_charge_probe,
	.remove = infinity_charge_remove,
	.driver = {
		.name           = DRIVER_NAME,
		.of_match_table = infinity_charge_of_match,
		.pm             = &infinity_charge_pm_ops,
	},
};

/* ================================================================== */
/*  Module Init / Exit                                                 */
/* ================================================================== */

static int __init infinity_charge_init(void)
{
	int ret;

	ret = platform_driver_register(&infinity_charge_driver);
	if (ret) {
		pr_err("driver registration failed: %d\n", ret);
		return ret;
	}

	pr_info("module loaded (v1.0 – Poco X3 Pro / SD732G)\n");
	return 0;
}

static void __exit infinity_charge_exit(void)
{
	platform_driver_unregister(&infinity_charge_driver);
	pr_info("module unloaded\n");
}

module_init(infinity_charge_init);
module_exit(infinity_charge_exit);

MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("Infinity Kernel Team");
MODULE_DESCRIPTION("Infinity Charging Bypass Control Driver");
MODULE_VERSION("1.0");
MODULE_ALIAS("platform:" DRIVER_NAME);