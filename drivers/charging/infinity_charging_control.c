/*
 * Infinity Kernel Charging Bypass Control Driver
 * Copyright (C) 2024 Infinity Kernel Team
 *
 * Platform driver for Poco X3 Pro (SM7325) providing gaming-optimized
 * charging bypass control with thermal monitoring and auto-resume.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 and
 * only version 2 as published by the Free Software Foundation.
 */

#define pr_fmt(fmt) "infinity-charging: " fmt

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/platform_device.h>
#include <linux/miscdevice.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/slab.h>
#include <linux/delay.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/power_supply.h>
#include <linux/workqueue.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/of_device.h>

#include <linux/infinity_charging_control.h>

/* ------------------------------------------------------------------ */
/* Mode configuration table                                           */
/* ------------------------------------------------------------------ */

/**
 * struct charging_mode_config - Per-mode charging parameters
 * @pause_soc:          SoC percentage at which charging is paused
 * @thermal_limit:      Thermal throttle threshold in Celsius
 * @current_reduction:  Percentage to reduce charge current (0-100)
 * @label:              Human-readable mode name for sysfs
 */
struct charging_mode_config {
	int  pause_soc;
	int  thermal_limit;
	int  current_reduction;
	const char *label;
};

static const struct charging_mode_config mode_configs[] = {
	[CHARGING_MODE_OFF] = {
		.pause_soc		= 100,
		.thermal_limit		= THERMAL_LIMIT_DISABLED,
		.current_reduction	= 0,
		.label			= "OFF",
	},
	[CHARGING_MODE_LIGHT] = {
		.pause_soc		= 80,
		.thermal_limit		= THERMAL_LIMIT_45C,
		.current_reduction	= 10,
		.label			= "LIGHT",
	},
	[CHARGING_MODE_BALANCED] = {
		.pause_soc		= 70,
		.thermal_limit		= THERMAL_LIMIT_40C,
		.current_reduction	= 30,
		.label			= "BALANCED",
	},
	[CHARGING_MODE_EXTREME] = {
		.pause_soc		= 60,
		.thermal_limit		= THERMAL_LIMIT_35C,
		.current_reduction	= 50,
		.label			= "EXTREME",
	},
	[CHARGING_MODE_ULTRA] = {
		.pause_soc		= 50,
		.thermal_limit		= THERMAL_LIMIT_35C,
		.current_reduction	= 70,
		.label			= "ULTRA",
	},
};

/* ------------------------------------------------------------------ */
/* Driver private state                                               */
/* ------------------------------------------------------------------ */

#define THERMAL_MONITOR_INTERVAL_MS	2000
#define AUTO_RESUME_DEFAULT		15
#define THERMAL_HYSTERESIS_C		5
#define SOC_HYSTERESIS			2
#define MAX_MODE			CHARGING_MODE_ULTRA
#define MAX_THERMAL_LIMIT		55
#define MIN_THERMAL_LIMIT		20
#define DEFAULT_INPUT_CURRENT_UA	3000000  /* 3A default */

struct infinity_charging_drv {
	struct device		*dev;
	struct miscdevice	miscdev;
	struct mutex		lock;

	/* Current configuration */
	enum infinity_charging_mode mode;
	int			thermal_limit_override; /* 0 = use mode default */
	int			auto_resume_threshold;

	/* Runtime state */
	int			battery_voltage_uv;
	int			battery_current_ua;
	int			battery_temp_mc;
	int			battery_soc;
	int			battery_charging_status;
	bool			is_charging;
	bool			thermal_throttled;
	bool			bypass_active;
	bool			soc_paused;

	/* Saved original charge current for restoration */
	int			original_current_ua;
	int			effective_current_ua;

	/* Work queue for periodic thermal / SoC monitoring */
	struct delayed_work	monitor_work;
	bool			monitor_running;

	/* Power supply references */
	struct power_supply	*battery_psy;
	struct power_supply	*charger_psy;

	/* sysfs kobject for /sys/kernel/infinity_charging */
	struct kobject		*sysfs_kobj;
};

static struct infinity_charging_drv *g_charging_drv;

/* ------------------------------------------------------------------ */
/* Power supply helpers                                               */
/* ------------------------------------------------------------------ */

static int icc_read_battery_property(struct infinity_charging_drv *drv,
				     enum power_supply_property psp,
				     union power_supply_propval *val)
{
	if (!drv->battery_psy)
		drv->battery_psy = power_supply_get_by_name("battery");

	if (!drv->battery_psy) {
		dev_err_ratelimited(drv->dev,
				    "battery power_supply not found\n");
		return -ENODEV;
	}

	return power_supply_get_property(drv->battery_psy, psp, val);
}

static int icc_set_charger_property(struct infinity_charging_drv *drv,
				    enum power_supply_property psp,
				    union power_supply_propval *val)
{
	if (!drv->charger_psy)
		drv->charger_psy = power_supply_get_by_name("battery");

	if (!drv->charger_psy) {
		dev_err_ratelimited(drv->dev,
				    "charger power_supply not found\n");
		return -ENODEV;
	}

	return power_supply_set_property(drv->charger_psy, psp, val);
}

/* ------------------------------------------------------------------ */
/* Charging control logic                                             */
/* ------------------------------------------------------------------ */

/**
 * icc_enable_charging() - Re-enable charging at the effective current
 */
static int icc_enable_charging(struct infinity_charging_drv *drv)
{
	union power_supply_propval val;
	int ret;

	/* Set charge type to enable charging */
	val.intval = POWER_SUPPLY_CHARGE_TYPE_FAST;
	ret = icc_set_charger_property(drv, POWER_SUPPLY_PROP_CHARGE_TYPE, &val);
	if (ret) {
		dev_err(drv->dev, "failed to enable charging: %d\n", ret);
		return ret;
	}

	/* Restore effective input current limit */
	val.intval = drv->effective_current_ua;
	ret = icc_set_charger_property(drv, POWER_SUPPLY_PROP_INPUT_CURRENT_LIMIT,
				       &val);
	if (ret) {
		dev_err(drv->dev, "failed to set input current: %d\n", ret);
		return ret;
	}

	drv->is_charging = true;
	drv->bypass_active = false;
	drv->thermal_throttled = false;
	drv->soc_paused = false;

	dev_info(drv->dev, "charging enabled at %d uA\n",
		 drv->effective_current_ua);
	return 0;
}

/**
 * icc_disable_charging() - Pause / disable charging
 */
static int icc_disable_charging(struct infinity_charging_drv *drv)
{
	union power_supply_propval val;
	int ret;

	/* Disable charging by setting charge type to none */
	val.intval = POWER_SUPPLY_CHARGE_TYPE_NONE;
	ret = icc_set_charger_property(drv, POWER_SUPPLY_PROP_CHARGE_TYPE, &val);
	if (ret) {
		dev_err(drv->dev, "failed to disable charging: %d\n", ret);
		return ret;
	}

	drv->is_charging = false;
	drv->bypass_active = true;

	dev_info(drv->dev, "charging disabled (bypass active)\n");
	return 0;
}

/**
 * icc_update_effective_current() - Calculate and apply charge current reduction
 */
static int icc_update_effective_current(struct infinity_charging_drv *drv)
{
	const struct charging_mode_config *cfg;
	union power_supply_propval val;
	int reduction_ua;

	if (drv->mode == CHARGING_MODE_OFF) {
		drv->effective_current_ua = drv->original_current_ua;
	} else {
		cfg = &mode_configs[drv->mode];
		reduction_ua = (drv->original_current_ua *
				cfg->current_reduction) / 100;
		drv->effective_current_ua = drv->original_current_ua - reduction_ua;
	}

	/* Only set the current if charging is currently active */
	if (drv->is_charging) {
		val.intval = drv->effective_current_ua;
		return icc_set_charger_property(
			drv, POWER_SUPPLY_PROP_INPUT_CURRENT_LIMIT, &val);
	}

	return 0;
}

/**
 * icc_read_battery_status() - Refresh all cached battery readings
 */
static void icc_read_battery_status(struct infinity_charging_drv *drv)
{
	union power_supply_propval val;

	/* Battery temperature in millidegrees Celsius */
	if (icc_read_battery_property(drv, POWER_SUPPLY_PROP_TEMP, &val) == 0)
		drv->battery_temp_mc = val.intval;

	/* Battery SoC percentage */
	if (icc_read_battery_property(drv, POWER_SUPPLY_PROP_CAPACITY, &val) == 0)
		drv->battery_soc = val.intval;

	/* Battery voltage in microvolts */
	if (icc_read_battery_property(drv, POWER_SUPPLY_PROP_VOLTAGE_NOW, &val) == 0)
		drv->battery_voltage_uv = val.intval;

	/* Battery current in microamps */
	if (icc_read_battery_property(drv, POWER_SUPPLY_PROP_CURRENT_NOW, &val) == 0)
		drv->battery_current_ua = val.intval;

	/* Charging status */
	if (icc_read_battery_property(drv, POWER_SUPPLY_PROP_STATUS, &val) == 0)
		drv->battery_charging_status = val.intval;
}

/* ------------------------------------------------------------------ */
/* Thermal / SoC monitoring work                                      */
/* ------------------------------------------------------------------ */

/**
 * icc_monitor_work_fn() - Periodic monitoring of temperature and SoC
 *
 * Runs every THERMAL_MONITOR_INTERVAL_MS to check if charging should
 * be paused or resumed based on thermal limits, SoC thresholds, and
 * the auto-resume safety feature.
 */
static void icc_monitor_work_fn(struct work_struct *work)
{
	struct infinity_charging_drv *drv = g_charging_drv;
	const struct charging_mode_config *cfg;
	int temp_c, active_thermal_limit;
	int pause_soc, hysteresis_soc;

	if (!drv || !drv->monitor_running)
		return;

	mutex_lock(&drv->lock);

	/* Always refresh readings */
	icc_read_battery_status(drv);

	/* In OFF mode, ensure monitoring loop continues but no control */
	if (drv->mode == CHARGING_MODE_OFF) {
		if (!drv->is_charging)
			icc_enable_charging(drv);
		goto schedule_next;
	}

	cfg = &mode_configs[drv->mode];
	temp_c = drv->battery_temp_mc / 1000;

	/* Determine effective thermal limit */
	if (drv->thermal_limit_override > 0)
		active_thermal_limit = drv->thermal_limit_override;
	else
		active_thermal_limit = cfg->thermal_limit;

	pause_soc = cfg->pause_soc;
	hysteresis_soc = max(pause_soc - SOC_HYSTERESIS, 0);

	/* ---- Auto-resume safety check ---- */
	if (drv->bypass_active &&
	    drv->battery_soc <= drv->auto_resume_threshold) {
		dev_info(drv->dev,
			 "auto-resume triggered: SoC=%d%% <= threshold=%d%%\n",
			 drv->battery_soc, drv->auto_resume_threshold);
		icc_enable_charging(drv);
		goto schedule_next;
	}

	/* ---- Thermal throttle check ---- */
	if (active_thermal_limit > THERMAL_LIMIT_DISABLED &&
	    temp_c >= active_thermal_limit) {
		if (drv->is_charging) {
			dev_info(drv->dev,
				 "thermal throttle: temp=%dC >= limit=%dC\n",
				 temp_c, active_thermal_limit);
			icc_disable_charging(drv);
			drv->thermal_throttled = true;
		}
	} else if (drv->thermal_throttled &&
		   temp_c <= (active_thermal_limit - THERMAL_HYSTERESIS_C)) {
		dev_info(drv->dev,
			 "thermal de-throttle: temp=%dC <= %dC\n",
			 temp_c,
			 active_thermal_limit - THERMAL_HYSTERESIS_C);
		drv->thermal_throttled = false;
		/* Don't re-enable here; let SoC check handle it */
	}

	/* ---- SoC pause check ---- */
	if (drv->battery_soc >= pause_soc) {
		if (drv->is_charging) {
			dev_info(drv->dev,
				 "SoC pause: level=%d%% >= limit=%d%%\n",
				 drv->battery_soc, pause_soc);
			icc_disable_charging(drv);
			drv->soc_paused = true;
		}
	} else if (drv->soc_paused &&
		   drv->battery_soc <= hysteresis_soc &&
		   !drv->thermal_throttled) {
		dev_info(drv->dev,
			 "SoC resume: level=%d%% <= %d%%\n",
			 drv->battery_soc, hysteresis_soc);
		drv->soc_paused = false;
		icc_enable_charging(drv);
	} else if (!drv->is_charging && !drv->thermal_throttled &&
		   !drv->soc_paused && !drv->bypass_active) {
		/* Nothing is blocking; re-enable if somehow disabled */
		icc_enable_charging(drv);
	}

schedule_next:
	mutex_unlock(&drv->lock);

	if (drv->monitor_running)
		schedule_delayed_work(&drv->monitor_work,
				      msecs_to_jiffies(THERMAL_MONITOR_INTERVAL_MS));
}

/* ------------------------------------------------------------------ */
/* Mode switching                                                     */
/* ------------------------------------------------------------------ */

static int icc_set_mode(struct infinity_charging_drv *drv,
			enum infinity_charging_mode new_mode)
{
	if (new_mode > MAX_MODE) {
		dev_err(drv->dev, "invalid mode %d\n", new_mode);
		return -EINVAL;
	}

	mutex_lock(&drv->lock);

	drv->mode = new_mode;
	dev_info(drv->dev, "mode set to %s\n", mode_configs[new_mode].label);

	/* Recalculate effective current for the new mode */
	icc_update_effective_current(drv);

	/* If switching to OFF, immediately re-enable charging */
	if (new_mode == CHARGING_MODE_OFF && !drv->is_charging) {
		icc_enable_charging(drv);
	}

	mutex_unlock(&drv->lock);
	return 0;
}

/* ------------------------------------------------------------------ */
/* sysfs attributes                                                   */
/* ------------------------------------------------------------------ */

static ssize_t charging_mode_show(struct kobject *kobj,
				  struct kobj_attribute *attr, char *buf)
{
	struct infinity_charging_drv *drv = g_charging_drv;

	if (!drv)
		return -ENODEV;

	return snprintf(buf, PAGE_SIZE, "%d\n", drv->mode);
}

static ssize_t charging_mode_store(struct kobject *kobj,
				   struct kobj_attribute *attr,
				   const char *buf, size_t count)
{
	struct infinity_charging_drv *drv = g_charging_drv;
	unsigned long val;
	int ret;

	if (!drv)
		return -ENODEV;

	ret = kstrtoul(buf, 10, &val);
	if (ret)
		return ret;

	if (val > MAX_MODE)
		return -EINVAL;

	ret = icc_set_mode(drv, (enum infinity_charging_mode)val);
	return ret ? ret : count;
}

static ssize_t thermal_limit_show(struct kobject *kobj,
				  struct kobj_attribute *attr, char *buf)
{
	struct infinity_charging_drv *drv = g_charging_drv;

	if (!drv)
		return -ENODEV;

	return snprintf(buf, PAGE_SIZE, "%d\n",
			drv->thermal_limit_override > 0 ?
			drv->thermal_limit_override :
			mode_configs[drv->mode].thermal_limit);
}

static ssize_t thermal_limit_store(struct kobject *kobj,
				   struct kobj_attribute *attr,
				   const char *buf, size_t count)
{
	struct infinity_charging_drv *drv = g_charging_drv;
	unsigned long val;
	int ret;

	if (!drv)
		return -ENODEV;

	ret = kstrtoul(buf, 10, &val);
	if (ret)
		return ret;

	if (val > MAX_THERMAL_LIMIT)
		return -EINVAL;

	mutex_lock(&drv->lock);
	drv->thermal_limit_override = (int)val;
	mutex_unlock(&drv->lock);

	return count;
}

static ssize_t auto_resume_threshold_show(struct kobject *kobj,
					  struct kobj_attribute *attr,
					  char *buf)
{
	struct infinity_charging_drv *drv = g_charging_drv;

	if (!drv)
		return -ENODEV;

	return snprintf(buf, PAGE_SIZE, "%d\n", drv->auto_resume_threshold);
}

static ssize_t auto_resume_threshold_store(struct kobject *kobj,
					   struct kobj_attribute *attr,
					   const char *buf, size_t count)
{
	struct infinity_charging_drv *drv = g_charging_drv;
	unsigned long val;
	int ret;

	if (!drv)
		return -ENODEV;

	ret = kstrtoul(buf, 10, &val);
	if (ret)
		return ret;

	if (val > 50)
		return -EINVAL;

	mutex_lock(&drv->lock);
	drv->auto_resume_threshold = (int)val;
	mutex_unlock(&drv->lock);

	return count;
}

static ssize_t status_show(struct kobject *kobj,
			   struct kobj_attribute *attr, char *buf)
{
	struct infinity_charging_drv *drv = g_charging_drv;
	const char *mode_str;
	char throttled[32] = "";
	char paused[32] = "";

	if (!drv)
		return -ENODEV;

	mutex_lock(&drv->lock);

	mode_str = mode_configs[drv->mode].label;

	if (drv->thermal_throttled)
		snprintf(throttled, sizeof(throttled), ", thermal_throttled");
	if (drv->soc_paused)
		snprintf(paused, sizeof(paused), ", soc_paused");

	mutex_unlock(&drv->lock);

	return snprintf(buf, PAGE_SIZE,
			"mode=%s, charging=%s, bypass=%s%s%s\n"
			"temp=%d, soc=%d%%, voltage=%duV, current=%duA\n",
			mode_str,
			drv->is_charging ? "yes" : "no",
			drv->bypass_active ? "yes" : "no",
			throttled, paused,
			drv->battery_temp_mc / 1000,
			drv->battery_soc,
			drv->battery_voltage_uv,
			drv->battery_current_ua);
}

static ssize_t battery_temp_show(struct kobject *kobj,
				 struct kobj_attribute *attr, char *buf)
{
	struct infinity_charging_drv *drv = g_charging_drv;

	if (!drv)
		return -ENODEV;

	return snprintf(buf, PAGE_SIZE, "%d\n", drv->battery_temp_mc);
}

static ssize_t battery_level_show(struct kobject *kobj,
				  struct kobj_attribute *attr, char *buf)
{
	struct infinity_charging_drv *drv = g_charging_drv;

	if (!drv)
		return -ENODEV;

	return snprintf(buf, PAGE_SIZE, "%d\n", drv->battery_soc);
}

/* clang-format off */
static struct kobj_attribute charging_mode_attr =
	__ATTR(charging_mode, 0644, charging_mode_show, charging_mode_store);
static struct kobj_attribute thermal_limit_attr =
	__ATTR(thermal_limit, 0644, thermal_limit_show, thermal_limit_store);
static struct kobj_attribute auto_resume_attr =
	__ATTR(auto_resume_threshold, 0644,
	       auto_resume_threshold_show, auto_resume_threshold_store);
static struct kobj_attribute status_attr =
	__ATTR(status, 0444, status_show, NULL);
static struct kobj_attribute battery_temp_attr =
	__ATTR(battery_temp, 0444, battery_temp_show, NULL);
static struct kobj_attribute battery_level_attr =
	__ATTR(battery_level, 0444, battery_level_show, NULL);

static struct attribute *infinity_charging_attrs[] = {
	&charging_mode_attr.attr,
	&thermal_limit_attr.attr,
	&auto_resume_attr.attr,
	&status_attr.attr,
	&battery_temp_attr.attr,
	&battery_level_attr.attr,
	NULL,
};
/* clang-format on */

static struct attribute_group infinity_charging_attr_group = {
	.attrs = infinity_charging_attrs,
};

/* ------------------------------------------------------------------ */
/* IOCTL handling (misc device)                                       */
/* ------------------------------------------------------------------ */

static long icc_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
{
	struct infinity_charging_drv *drv = g_charging_drv;
	void __user *argp = (void __user *)arg;
	int val;
	int ret;

	if (!drv)
		return -ENODEV;

	switch (cmd) {
	case INFINITY_CHARGING_SET_MODE:
		if (copy_from_user(&val, argp, sizeof(val)))
			return -EFAULT;
		ret = icc_set_mode(drv, (enum infinity_charging_mode)val);
		return ret;

	case INFINITY_CHARGING_GET_STATUS: {
		struct infinity_charging_status status;

		mutex_lock(&drv->lock);
		status.mode = drv->mode;
		status.battery_voltage = drv->battery_voltage_uv;
		status.battery_current = drv->battery_current_ua;
		status.battery_temp = drv->battery_temp_mc;
		status.is_charging = drv->is_charging;
		status.thermal_throttled = drv->thermal_throttled;
		status.bypass_active = drv->bypass_active;
		mutex_unlock(&drv->lock);

		if (copy_to_user(argp, &status, sizeof(status)))
			return -EFAULT;
		return 0;
	}

	case INFINITY_CHARGING_SET_THERMAL_LIMIT:
		if (copy_from_user(&val, argp, sizeof(val)))
			return -EFAULT;
		if (val > MAX_THERMAL_LIMIT || val < MIN_THERMAL_LIMIT)
			return -EINVAL;
		mutex_lock(&drv->lock);
		drv->thermal_limit_override = val;
		mutex_unlock(&drv->lock);
		return 0;

	case INFINITY_CHARGING_SET_AUTO_RESUME:
		if (copy_from_user(&val, argp, sizeof(val)))
			return -EFAULT;
		if (val > 50 || val < 0)
			return -EINVAL;
		mutex_lock(&drv->lock);
		drv->auto_resume_threshold = val;
		mutex_unlock(&drv->lock);
		return 0;

	default:
		dev_warn(drv->dev, "unknown ioctl cmd 0x%x\n", cmd);
		return -ENOTTY;
	}
}

static const struct file_operations icc_fops = {
	.owner		= THIS_MODULE,
	.unlocked_ioctl	= icc_ioctl,
#ifdef CONFIG_COMPAT
	.compat_ioctl	= icc_ioctl,
#endif
};

/* ------------------------------------------------------------------ */
/* Device tree parsing                                                */
/* ------------------------------------------------------------------ */

static int icc_parse_dt(struct platform_device *pdev,
			struct infinity_charging_drv *drv)
{
	struct device_node *np = pdev->dev.of_node;

	if (!np)
		return 0;

	of_property_read_u32(np, "default-thermal-limit",
			     &drv->thermal_limit_override);
	of_property_read_u32(np, "default-auto-resume",
			     &drv->auto_resume_threshold);

	/* Validate parsed values */
	if (drv->thermal_limit_override > MAX_THERMAL_LIMIT)
		drv->thermal_limit_override = THERMAL_LIMIT_45C;
	if (drv->auto_resume_threshold > 50 || drv->auto_resume_threshold < 0)
		drv->auto_resume_threshold = AUTO_RESUME_DEFAULT;

	dev_info(&pdev->dev,
		 "DT: thermal_limit=%d, auto_resume=%d\n",
		 drv->thermal_limit_override,
		 drv->auto_resume_threshold);

	return 0;
}

/* ------------------------------------------------------------------ */
/* Platform driver probe / remove                                     */
/* ------------------------------------------------------------------ */

static int icc_probe(struct platform_device *pdev)
{
	struct infinity_charging_drv *drv;
	int ret;

	drv = devm_kzalloc(&pdev->dev, sizeof(*drv), GFP_KERNEL);
	if (!drv)
		return -ENOMEM;

	drv->dev = &pdev->dev;
	mutex_init(&drv->lock);

	/* Defaults */
	drv->mode = CHARGING_MODE_OFF;
	drv->thermal_limit_override = 0; /* use mode default */
	drv->auto_resume_threshold = AUTO_RESUME_DEFAULT;
	drv->original_current_ua = DEFAULT_INPUT_CURRENT_UA;
	drv->effective_current_ua = DEFAULT_INPUT_CURRENT_UA;
	drv->is_charging = true;
	drv->bypass_active = false;
	drv->thermal_throttled = false;
	drv->soc_paused = false;
	drv->monitor_running = false;

	/* Parse device tree */
	ret = icc_parse_dt(pdev, drv);
	if (ret) {
		dev_err(&pdev->dev, "DT parse failed: %d\n", ret);
		return ret;
	}

	/* Acquire power supply references early */
	drv->battery_psy = power_supply_get_by_name("battery");
	if (!drv->battery_psy) {
		/* Not fatal — may appear later via monitor_work */
		dev_warn(&pdev->dev,
			 "battery power_supply not yet available\n");
	}
	drv->charger_psy = power_supply_get_by_name("battery");

	/* Read initial battery state */
	icc_read_battery_status(drv);

	/* Register misc device for IOCTL */
	drv->miscdev.minor = MISC_DYNAMIC_MINOR;
	drv->miscdev.name = "infinity-charging";
	drv->miscdev.fops = &icc_fops;
	drv->miscdev.parent = &pdev->dev;

	ret = misc_register(&drv->miscdev);
	if (ret) {
		dev_err(&pdev->dev, "misc_register failed: %d\n", ret);
		return ret;
	}

	/* Create sysfs kobject under /sys/kernel/infinity_charging */
	drv->sysfs_kobj = kobject_create_and_add("infinity_charging",
						 kernel_kobj);
	if (!drv->sysfs_kobj) {
		dev_err(&pdev->dev, "sysfs kobject create failed\n");
		ret = -ENOMEM;
		goto err_misc;
	}

	ret = sysfs_create_group(drv->sysfs_kobj, &infinity_charging_attr_group);
	if (ret) {
		dev_err(&pdev->dev, "sysfs group create failed: %d\n", ret);
		goto err_kobj;
	}

	/* Initialize and schedule the monitoring delayed work */
	INIT_DELAYED_WORK(&drv->monitor_work, icc_monitor_work_fn);
	drv->monitor_running = true;
	g_charging_drv = drv;

	schedule_delayed_work(&drv->monitor_work,
			      msecs_to_jiffies(THERMAL_MONITOR_INTERVAL_MS));

	platform_set_drvdata(pdev, drv);

	dev_info(&pdev->dev,
		 "Infinity Charging Control v1.0 initialized\n");
	dev_info(&pdev->dev,
		 "  default current: %d uA, auto-resume: %d%%\n",
		 drv->original_current_ua, drv->auto_resume_threshold);

	return 0;

err_kobj:
	kobject_put(drv->sysfs_kobj);
err_misc:
	misc_deregister(&drv->miscdev);
	return ret;
}

static int icc_remove(struct platform_device *pdev)
{
	struct infinity_charging_drv *drv = platform_get_drvdata(pdev);

	if (!drv)
		return 0;

	/* Stop monitoring */
	mutex_lock(&drv->lock);
	drv->monitor_running = false;
	mutex_unlock(&drv->lock);
	cancel_delayed_work_sync(&drv->monitor_work);

	/* Re-enable charging before unloading */
	if (!drv->is_charging) {
		union power_supply_propval val;
		val.intval = POWER_SUPPLY_CHARGE_TYPE_FAST;
		icc_set_charger_property(drv, POWER_SUPPLY_PROP_CHARGE_TYPE, &val);
		val.intval = drv->original_current_ua;
		icc_set_charger_property(drv,
					 POWER_SUPPLY_PROP_INPUT_CURRENT_LIMIT,
					 &val);
	}

	/* Tear down sysfs and misc device */
	sysfs_remove_group(drv->sysfs_kobj, &infinity_charging_attr_group);
	kobject_put(drv->sysfs_kobj);
	misc_deregister(&drv->miscdev);

	/* Release power supply references */
	if (drv->battery_psy)
		power_supply_put(drv->battery_psy);
	if (drv->charger_psy)
		power_supply_put(drv->charger_psy);

	g_charging_drv = NULL;
	mutex_destroy(&drv->lock);

	dev_info(&pdev->dev, "Infinity Charging Control removed\n");
	return 0;
}

/* ------------------------------------------------------------------ */
/* OF match table                                                     */
/* ------------------------------------------------------------------ */

static const struct of_device_id icc_of_match[] = {
	{ .compatible = "infinity,charging-control" },
	{ /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, icc_of_match);

/* ------------------------------------------------------------------ */
/* Platform driver definition                                         */
/* ------------------------------------------------------------------ */

struct platform_driver infinity_charging_driver = {
	.probe	= icc_probe,
	.remove	= icc_remove,
	.driver	= {
		.name		= "infinity-charging",
		.of_match_table	= icc_of_match,
	},
};
EXPORT_SYMBOL_GPL(infinity_charging_driver);

module_platform_driver(infinity_charging_driver);

MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("Infinity Kernel");
MODULE_DESCRIPTION("Infinity Kernel Charging Bypass Control v1.0");
MODULE_VERSION("1.0");
MODULE_ALIAS("platform:infinity-charging");