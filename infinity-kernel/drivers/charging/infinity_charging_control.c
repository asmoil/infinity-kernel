/*
 * Infinity Kernel - Charging Control Driver
 * For Poco X3 Pro (vayu/bhima) - Snapdragon 732G
 *
 * Provides:
 *   - Charging bypass (disables charging while gaming)
 *   - Charging current limit control
 *   - Battery temperature monitoring with auto-bypass
 *   - Gaming mode integration
 *
 * Copyright (c) 2024 Infinity Kernel Project
 * Licensed under GNU GPL v2.0
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/slab.h>
#include <linux/uaccess.h>
#include <linux/power_supply.h>
#include <linux/workqueue.h>
#include <linux/delay.h>
#include <linux/mutex.h>
#include <linux/thermal.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/wakelock.h>
#include <linux/of.h>
#include <linux/of_device.h>
#include <linux/regulator/consumer.h>
#include <linux/err.h>

/* Module metadata */
#define DRIVER_NAME        "infinity_charging"
#define DRIVER_VERSION     "1.0.0"
#define CLASS_NAME         "infinity_charging"
#define DEVICE_NAME        "charging_ctrl"
#define BUF_SIZE           256

/* Charging states */
enum charging_state {
	CHARGING_STATE_NORMAL = 0,
	CHARGING_STATE_BYPASS = 1,
	CHARGING_STATE_LIMITED = 2,
	CHARGING_STATE_COOLING = 3,
};

/* Gaming mode states */
enum gaming_mode {
	GAMING_MODE_OFF = 0,
	GAMING_MODE_LOW = 1,
	GAMING_MODE_MEDIUM = 2,
	GAMING_MODE_HIGH = 3,
};

/* Driver context structure */
struct infinity_charging_ctx {
	struct device *dev;
	struct class *charging_class;
	struct cdev charging_cdev;
	dev_t dev_num;
	struct mutex lock;
	struct delayed_work charging_work;
	struct work_struct temp_monitor_work;
	struct wake_lock charging_wake_lock;

	/* Charging state */
	enum charging_state state;
	atomic_t charging_enabled;
	atomic_t bypass_active;

	/* Configuration */
	int max_charge_current_ma;
	int gaming_charge_current_ma;
	int cooldown_threshold_mc;
	int resume_threshold_mc;
	int max_charge_percent;
	enum gaming_mode gaming_mode;

	/* Stats */
	int bypass_count;
	unsigned long total_bypass_time_ms;
	unsigned long last_bypass_start;

	/* Power supply references */
	struct power_supply *batt_psy;
	struct power_supply *usb_psy;
	struct power_supply *bms_psy;

	/* Regulators */
	struct regulator *vbus_reg;
	struct regulator *charger_reg;

	/* Sysfs */
	struct kobject *kobj;
};

static struct infinity_charging_ctx *g_ctx;

/* ========================================================================
 * HELPER FUNCTIONS
 * ======================================================================== */

/**
 * infinity_get_battery_temp - Read battery temperature in millicelsius
 * @ctx: driver context
 *
 * Returns: battery temperature in mC, or -ENODEV on failure
 */
static int infinity_get_battery_temp(struct infinity_charging_ctx *ctx)
{
	union power_supply_propval val = {0};
	int ret;

	if (!ctx->batt_psy)
		ctx->batt_psy = power_supply_get_by_name("battery");
	if (!ctx->batt_psy)
		return -ENODEV;

	ret = power_supply_get_property(ctx->batt_psy,
					POWER_SUPPLY_PROP_TEMP, &val);
	if (ret)
		return ret;

	return val.intval;
}

/**
 * infinity_get_battery_capacity - Read battery capacity percentage
 * @ctx: driver context
 *
 * Returns: battery capacity 0-100, or negative error
 */
static int infinity_get_battery_capacity(struct infinity_charging_ctx *ctx)
{
	union power_supply_propval val = {0};
	int ret;

	if (!ctx->batt_psy)
		ctx->batt_psy = power_supply_get_by_name("battery");
	if (!ctx->batt_psy)
		return -ENODEV;

	ret = power_supply_get_property(ctx->batt_psy,
					POWER_SUPPLY_PROP_CAPACITY, &val);
	if (ret)
		return ret;

	return val.intval;
}

/**
 * infinity_get_battery_voltage - Read battery voltage in microvolts
 * @ctx: driver context
 *
 * Returns: voltage in uV, or negative error
 */
static int infinity_get_battery_voltage(struct infinity_charging_ctx *ctx)
{
	union power_supply_propval val = {0};
	int ret;

	if (!ctx->bms_psy)
		ctx->bms_psy = power_supply_get_by_name("bms");
	if (!ctx->bms_psy) {
		if (!ctx->batt_psy)
			ctx->batt_psy = power_supply_get_by_name("battery");
		if (!ctx->batt_psy)
			return -ENODEV;
		ret = power_supply_get_property(ctx->batt_psy,
					POWER_SUPPLY_PROP_VOLTAGE_NOW, &val);
	} else {
		ret = power_supply_get_property(ctx->bms_psy,
					POWER_SUPPLY_PROP_VOLTAGE_NOW, &val);
	}

	if (ret)
		return ret;

	return val.intval;
}

/**
 * infinity_is_charging - Check if device is currently charging
 * @ctx: driver context
 *
 * Returns: 1 if charging, 0 if not, negative on error
 */
static int infinity_is_charging(struct infinity_charging_ctx *ctx)
{
	union power_supply_propval val = {0};
	int ret;

	if (!ctx->usb_psy)
		ctx->usb_psy = power_supply_get_by_name("usb");
	if (!ctx->usb_psy)
		return -ENODEV;

	ret = power_supply_get_property(ctx->usb_psy,
					POWER_SUPPLY_PROP_ONLINE, &val);
	if (ret)
		return ret;

	return val.intval;
}

/* ========================================================================
 * CHARGING CONTROL
 * ======================================================================== */

/**
 * infinity_set_charging - Enable or disable charging via power supply
 * @ctx: driver context
 * @enable: 1 to enable, 0 to disable
 *
 * Returns: 0 on success, negative error on failure
 */
static int infinity_set_charging(struct infinity_charging_ctx *ctx, int enable)
{
	union power_supply_propval val = {0};
	int ret = 0;

	if (!ctx->usb_psy) {
		ctx->usb_psy = power_supply_get_by_name("usb");
		if (!ctx->usb_psy)
			return -ENODEV;
	}

	/* Set charging enable/disable through the charger IC */
	if (ctx->charger_reg) {
		if (enable) {
			ret = regulator_enable(ctx->charger_reg);
		} else {
			ret = regulator_disable(ctx->charger_reg);
		}
	}

	/* Also notify the power supply framework */
	val.intval = enable;
	ret = power_supply_set_property(ctx->usb_psy,
					POWER_SUPPLY_PROP_CHARGE_ENABLED, &val);

	if (!ret) {
		atomic_set(&ctx->charging_enabled, enable);
		dev_info(ctx->dev, "Charging %s", enable ? "enabled" : "disabled");
	}

	return ret;
}

/**
 * infinity_set_charge_current - Set maximum charge current
 * @ctx: driver context
 * @current_ma: current in milliamps
 *
 * Returns: 0 on success, negative error on failure
 */
static int infinity_set_charge_current(struct infinity_charging_ctx *ctx,
					int current_ma)
{
	union power_supply_propval val = {0};
	int ret = 0;

	if (!ctx->bms_psy) {
		ctx->bms_psy = power_supply_get_by_name("bms");
		if (!ctx->bms_psy)
			return -ENODEV;
	}

	val.intval = current_ma * 1000; /* Convert to microamps */
	ret = power_supply_set_property(ctx->bms_psy,
					POWER_SUPPLY_PROP_CHARGE_CURRENT_MAX,
					&val);

	if (!ret)
		dev_info(ctx->dev, "Charge current set to %d mA", current_ma);

	return ret;
}

/* ========================================================================
 * CHARGING BYPASS LOGIC (GAMING MODE)
 * ======================================================================== */

/**
 * infinity_activate_bypass - Activate charging bypass for gaming
 * @ctx: driver context
 *
 * Disables charging while maintaining USB peripheral functionality.
 * Tracks bypass time for statistics.
 */
static void infinity_activate_bypass(struct infinity_charging_ctx *ctx)
{
	if (atomic_read(&ctx->bypass_active))
		return;

	if (infinity_is_charging(ctx) <= 0)
		return;

	mutex_lock(&ctx->lock);

	/* Check battery level - don't bypass if battery is too low */
	int capacity = infinity_get_battery_capacity(ctx);
	if (capacity < 20) {
		dev_warn(ctx->dev,
			"Battery too low (%d%%), skipping bypass", capacity);
		mutex_unlock(&ctx->lock);
		return;
	}

	/* Disable charging */
	infinity_set_charging(ctx, 0);

	ctx->state = CHARGING_STATE_BYPASS;
	atomic_set(&ctx->bypass_active, 1);
	ctx->last_bypass_start = jiffies;
	ctx->bypass_count++;

	dev_info(ctx->dev,
		"[BYPASS] Charging bypass activated - Batt: %d%%, Temp: %d mC",
		capacity, infinity_get_battery_temp(ctx));

	mutex_unlock(&ctx->lock);
}

/**
 * infinity_deactivate_bypass - Resume charging after gaming
 * @ctx: driver context
 */
static void infinity_deactivate_bypass(struct infinity_charging_ctx *ctx)
{
	if (!atomic_read(&ctx->bypass_active))
		return;

	mutex_lock(&ctx->lock);

	/* Re-enable charging */
	infinity_set_charging(ctx, 1);

	/* Calculate bypass duration */
	if (ctx->last_bypass_start) {
		unsigned long duration = jiffies_to_msecs(jiffies - ctx->last_bypass_start);
		ctx->total_bypass_time_ms += duration;
		dev_info(ctx->dev,
			"[BYPASS] Bypass duration: %lu ms, Total: %lu ms",
			duration, ctx->total_bypass_time_ms);
	}

	ctx->state = CHARGING_STATE_NORMAL;
	atomic_set(&ctx->bypass_active, 0);

	dev_info(ctx->dev, "[BYPASS] Charging bypass deactivated - Charging resumed");

	mutex_unlock(&ctx->lock);
}

/* ========================================================================
 * THERMAL MONITORING
 * ======================================================================== */

/**
 * infinity_temp_monitor_work - Monitor battery temperature
 * @work: work struct
 *
 * Automatically activates cooling mode or bypass when battery
 * temperature exceeds thresholds. Prevents thermal throttling
 * and battery degradation during gaming.
 */
static void infinity_temp_monitor_work(struct work_struct *work)
{
	struct infinity_charging_ctx *ctx =
		container_of(work, struct infinity_charging_ctx, temp_monitor_work);
	int temp, capacity;

	temp = infinity_get_battery_temp(ctx);
	if (temp < 0)
		goto reschedule;

	/* Temperature thresholds:
	 * cooldown_threshold_mc: Enter cooling mode (e.g., 45000 mC = 45°C)
	 * resume_threshold_mc:   Resume normal (e.g., 40000 mC = 40°C)
	 */
	if (temp >= ctx->cooldown_threshold_mc && ctx->state != CHARGING_STATE_COOLING) {
		capacity = infinity_get_battery_capacity(ctx);
		if (capacity > 15) {
			dev_warn(ctx->dev,
				"[THERMAL] Battery temp %d mC exceeds threshold %d mC - activating cooling",
				temp, ctx->cooldown_threshold_mc);

			/* Activate cooling: limit charge current or bypass */
			if (ctx->gaming_mode >= GAMING_MODE_HIGH) {
				infinity_activate_bypass(ctx);
			} else {
				infinity_set_charge_current(ctx, ctx->gaming_charge_current_ma);
				ctx->state = CHARGING_STATE_COOLING;
			}
		}
	} else if (temp <= ctx->resume_threshold_mc &&
		   ctx->state == CHARGING_STATE_COOLING) {
		dev_info(ctx->dev,
			"[THERMAL] Battery temp %d mC - resuming normal charging",
			temp);
		infinity_set_charge_current(ctx, ctx->max_charge_current_ma);
		ctx->state = CHARGING_STATE_NORMAL;
	}

reschedule:
	schedule_delayed_work(&ctx->charging_work,
		msecs_to_jiffies(5000));
}

/* ========================================================================
 * DELAYED WORK - PERIODIC CHARGING CHECK
 * ======================================================================== */

/**
 * infinity_charging_work_fn - Periodic charging state monitor
 * @work: delayed work struct
 *
 * Periodically checks:
 * - If device is charging and bypass should be active
 * - Battery level for auto-resume (prevent over-discharge during bypass)
 * - Temperature conditions for thermal management
 */
static void infinity_charging_work_fn(struct work_struct *work)
{
	struct infinity_charging_ctx *ctx =
		container_of(work, struct infinity_charging_ctx, charging_work.work);
	int capacity;

	if (!atomic_read(&ctx->bypass_active))
		goto out;

	/* Safety: if battery drops below threshold, force resume charging */
	capacity = infinity_get_battery_capacity(ctx);
	if (capacity >= 0 && capacity <= 15) {
		dev_warn(ctx->dev,
			"[SAFETY] Battery at %d%% - forcing charging resume",
			capacity);
		infinity_deactivate_bypass(ctx);
		/* Set low charge current for safety */
		infinity_set_charge_current(ctx, ctx->gaming_charge_current_ma);
		ctx->state = CHARGING_STATE_LIMITED;
	}

out:
	schedule_delayed_work(&ctx->charging_work,
		msecs_to_jiffies(10000));
}

/* ========================================================================
 * SYSFS INTERFACE
 * ======================================================================== */

static ssize_t bypass_enable_show(struct device *dev,
				  struct device_attribute *attr, char *buf)
{
	struct infinity_charging_ctx *ctx = dev_get_drvdata(dev);
	return scnprintf(buf, PAGE_SIZE, "%d\n",
		atomic_read(&ctx->bypass_active));
}

static ssize_t bypass_enable_store(struct device *dev,
				   struct device_attribute *attr,
				   const char *buf, size_t count)
{
	struct infinity_charging_ctx *ctx = dev_get_drvdata(dev);
	unsigned long val;
	int ret;

	ret = kstrtoul(buf, 10, &val);
	if (ret)
		return ret;

	if (val)
		infinity_activate_bypass(ctx);
	else
		infinity_deactivate_bypass(ctx);

	return count;
}

static ssize_t gaming_mode_show(struct device *dev,
				struct device_attribute *attr, char *buf)
{
	struct infinity_charging_ctx *ctx = dev_get_drvdata(dev);
	return scnprintf(buf, PAGE_SIZE, "%d\n", ctx->gaming_mode);
}

static ssize_t gaming_mode_store(struct device *dev,
				 struct device_attribute *attr,
				 const char *buf, size_t count)
{
	struct infinity_charging_ctx *ctx = dev_get_drvdata(dev);
	unsigned long val;
	int ret;

	ret = kstrtoul(buf, 10, &val);
	if (ret)
		return ret;

	if (val > GAMING_MODE_HIGH)
		return -EINVAL;

	ctx->gaming_mode = (enum gaming_mode)val;

	/* Apply gaming mode settings */
	switch (ctx->gaming_mode) {
	case GAMING_MODE_OFF:
		/* Normal mode - full charge current */
		infinity_set_charge_current(ctx, ctx->max_charge_current_ma);
		infinity_deactivate_bypass(ctx);
		break;
	case GAMING_MODE_LOW:
		/* Light gaming - reduce charge current */
		infinity_set_charge_current(ctx,
			ctx->max_charge_current_ma * 50 / 100);
		break;
	case GAMING_MODE_MEDIUM:
		/* Medium gaming - significant current reduction */
		infinity_set_charge_current(ctx,
			ctx->gaming_charge_current_ma);
		break;
	case GAMING_MODE_HIGH:
		/* Heavy gaming - bypass charging entirely */
		infinity_activate_bypass(ctx);
		break;
	}

	dev_info(ctx->dev, "Gaming mode set to %d", ctx->gaming_mode);
	return count;
}

static ssize_t charge_current_show(struct device *dev,
				   struct device_attribute *attr, char *buf)
{
	struct infinity_charging_ctx *ctx = dev_get_drvdata(dev);
	return scnprintf(buf, PAGE_SIZE, "%d\n", ctx->max_charge_current_ma);
}

static ssize_t charge_current_store(struct device *dev,
				    struct device_attribute *attr,
				    const char *buf, size_t count)
{
	struct infinity_charging_ctx *ctx = dev_get_drvdata(dev);
	unsigned long val;
	int ret;

	ret = kstrtoul(buf, 10, &val);
	if (ret)
		return ret;

	if (val < 100 || val > 5000)
		return -EINVAL;

	ctx->max_charge_current_ma = (int)val;
	infinity_set_charge_current(ctx, ctx->max_charge_current_ma);

	return count;
}

static ssize_t battery_temp_show(struct device *dev,
				 struct device_attribute *attr, char *buf)
{
	struct infinity_charging_ctx *ctx = dev_get_drvdata(dev);
	int temp = infinity_get_battery_temp(ctx);

	if (temp < 0)
		return scnprintf(buf, PAGE_SIZE, "error\n");

	return scnprintf(buf, PAGE_SIZE, "%d\n", temp / 100);
}

static ssize_t battery_voltage_show(struct device *dev,
				    struct device_attribute *attr, char *buf)
{
	struct infinity_charging_ctx *ctx = dev_get_drvdata(dev);
	int voltage = infinity_get_battery_voltage(ctx);

	if (voltage < 0)
		return scnprintf(buf, PAGE_SIZE, "error\n");

	return scnprintf(buf, PAGE_SIZE, "%d\n", voltage / 1000);
}

static ssize_t battery_capacity_show(struct device *dev,
				     struct device_attribute *attr, char *buf)
{
	struct infinity_charging_ctx *ctx = dev_get_drvdata(dev);
	int capacity = infinity_get_battery_capacity(ctx);

	if (capacity < 0)
		return scnprintf(buf, PAGE_SIZE, "error\n");

	return scnprintf(buf, PAGE_SIZE, "%d\n", capacity);
}

static ssize_t charging_state_show(struct device *dev,
				   struct device_attribute *attr, char *buf)
{
	struct infinity_charging_ctx *ctx = dev_get_drvdata(dev);
	const char *state_str;

	switch (ctx->state) {
	case CHARGING_STATE_NORMAL:
		state_str = "normal";
		break;
	case CHARGING_STATE_BYPASS:
		state_str = "bypass";
		break;
	case CHARGING_STATE_LIMITED:
		state_str = "limited";
		break;
	case CHARGING_STATE_COOLING:
		state_str = "cooling";
		break;
	default:
		state_str = "unknown";
		break;
	}

	return scnprintf(buf, PAGE_SIZE, "%s\n", state_str);
}

static ssize_t stats_show(struct device *dev,
			  struct device_attribute *attr, char *buf)
{
	struct infinity_charging_ctx *ctx = dev_get_drvdata(dev);

	return scnprintf(buf, PAGE_SIZE,
		"Bypass Count: %d\n"
		"Total Bypass Time: %lu ms\n"
		"Current State: %d\n"
		"Charging: %d\n"
		"Bypass Active: %d\n"
		"Gaming Mode: %d\n",
		ctx->bypass_count,
		ctx->total_bypass_time_ms,
		ctx->state,
		atomic_read(&ctx->charging_enabled),
		atomic_read(&ctx->bypass_active),
		ctx->gaming_mode);
}

static ssize_t cooldown_threshold_show(struct device *dev,
				       struct device_attribute *attr,
				       char *buf)
{
	struct infinity_charging_ctx *ctx = dev_get_drvdata(dev);
	return scnprintf(buf, PAGE_SIZE, "%d\n",
		ctx->cooldown_threshold_mc / 100);
}

static ssize_t cooldown_threshold_store(struct device *dev,
					struct device_attribute *attr,
					const char *buf, size_t count)
{
	struct infinity_charging_ctx *ctx = dev_get_drvdata(dev);
	unsigned long val;
	int ret;

	ret = kstrtoul(buf, 10, &val);
	if (ret)
		return ret;

	if (val < 30 || val > 60)
		return -EINVAL;

	ctx->cooldown_threshold_mc = (int)val * 100;
	return count;
}

static ssize_t resume_threshold_show(struct device *dev,
				     struct device_attribute *attr,
				     char *buf)
{
	struct infinity_charging_ctx *ctx = dev_get_drvdata(dev);
	return scnprintf(buf, PAGE_SIZE, "%d\n",
		ctx->resume_threshold_mc / 100);
}

static ssize_t resume_threshold_store(struct device *dev,
				      struct device_attribute *attr,
				      const char *buf, size_t count)
{
	struct infinity_charging_ctx *ctx = dev_get_drvdata(dev);
	unsigned long val;
	int ret;

	ret = kstrtoul(buf, 10, &val);
	if (ret)
		return ret;

	if (val < 25 || val > 50)
		return -EINVAL;

	ctx->resume_threshold_mc = (int)val * 100;
	return count;
}

/* Sysfs attributes */
static DEVICE_ATTR(bypass_enable, 0664, bypass_enable_show, bypass_enable_store);
static DEVICE_ATTR(gaming_mode, 0664, gaming_mode_show, gaming_mode_store);
static DEVICE_ATTR(charge_current, 0664, charge_current_show, charge_current_store);
static DEVICE_ATTR(battery_temp, 0444, battery_temp_show, NULL);
static DEVICE_ATTR(battery_voltage, 0444, battery_voltage_show, NULL);
static DEVICE_ATTR(battery_capacity, 0444, battery_capacity_show, NULL);
static DEVICE_ATTR(charging_state, 0444, charging_state_show, NULL);
static DEVICE_ATTR(stats, 0444, stats_show, NULL);
static DEVICE_ATTR(cooldown_threshold, 0664,
	cooldown_threshold_show, cooldown_threshold_store);
static DEVICE_ATTR(resume_threshold, 0664,
	resume_threshold_show, resume_threshold_store);

static struct attribute *charging_attrs[] = {
	&dev_attr_bypass_enable.attr,
	&dev_attr_gaming_mode.attr,
	&dev_attr_charge_current.attr,
	&dev_attr_battery_temp.attr,
	&dev_attr_battery_voltage.attr,
	&dev_attr_battery_capacity.attr,
	&dev_attr_charging_state.attr,
	&dev_attr_stats.attr,
	&dev_attr_cooldown_threshold.attr,
	&dev_attr_resume_threshold.attr,
	NULL,
};

static struct attribute_group charging_attr_group = {
	.attrs = charging_attrs,
	.name = "infinity_charging",
};

/* ========================================================================
 * CHAR DEVICE OPERATIONS
 * ======================================================================== */

static int infinity_charging_open(struct inode *inode, struct file *filp)
{
	struct infinity_charging_ctx *ctx =
		container_of(inode->i_cdev, struct infinity_charging_ctx,
			charging_cdev);
	filp->private_data = ctx;
	return 0;
}

static int infinity_charging_release(struct inode *inode, struct file *filp)
{
	return 0;
}

static long infinity_charging_ioctl(struct file *filp, unsigned int cmd,
				    unsigned long arg)
{
	struct infinity_charging_ctx *ctx = filp->private_data;
	void __user *argp = (void __user *)arg;
	int val, ret = 0;

	switch (cmd) {
	case 0x01: /* INFINITY_IOCTL_SET_BYPASS */
		if (copy_from_user(&val, argp, sizeof(val)))
			return -EFAULT;
		if (val)
			infinity_activate_bypass(ctx);
		else
			infinity_deactivate_bypass(ctx);
		break;

	case 0x02: /* INFINITY_IOCTL_SET_GAMING_MODE */
		if (copy_from_user(&val, argp, sizeof(val)))
			return -EFAULT;
		if (val >= 0 && val <= 3)
			ctx->gaming_mode = val;
		else
			ret = -EINVAL;
		break;

	case 0x03: /* INFINITY_IOCTL_GET_BYPASS_STATE */
		val = atomic_read(&ctx->bypass_active);
		if (copy_to_user(argp, &val, sizeof(val)))
			return -EFAULT;
		break;

	case 0x04: /* INFINITY_IOCTL_SET_CURRENT */
		if (copy_from_user(&val, argp, sizeof(val)))
			return -EFAULT;
		ret = infinity_set_charge_current(ctx, val);
		break;

	default:
		ret = -ENOTTY;
	}

	return ret;
}

static const struct file_operations charging_fops = {
	.owner          = THIS_MODULE,
	.open           = infinity_charging_open,
	.release        = infinity_charging_release,
	.unlocked_ioctl = infinity_charging_ioctl,
#ifdef CONFIG_COMPAT
	.compat_ioctl   = infinity_charging_ioctl,
#endif
};

/* ========================================================================
 * PLATFORM DRIVER
 * ======================================================================== */

static int infinity_charging_probe(struct platform_device *pdev)
{
	struct infinity_charging_ctx *ctx;
	struct device_node *np = pdev->dev.of_node;
	int ret;
	u32 val;

	ctx = devm_kzalloc(&pdev->dev, sizeof(*ctx), GFP_KERNEL);
	if (!ctx)
		return -ENOMEM;

	ctx->dev = &pdev->dev;
	mutex_init(&ctx->lock);
	platform_set_drvdata(pdev, ctx);

	/* Parse device tree for default values */
	if (np) {
		if (!of_property_read_u32(np, "max-charge-current", &val))
			ctx->max_charge_current_ma = val;
		else
			ctx->max_charge_current_ma = 3000;

		if (!of_property_read_u32(np, "gaming-charge-current", &val))
			ctx->gaming_charge_current_ma = val;
		else
			ctx->gaming_charge_current_ma = 500;

		if (!of_property_read_u32(np, "cooldown-threshold", &val))
			ctx->cooldown_threshold_mc = val;
		else
			ctx->cooldown_threshold_mc = 45000;

		if (!of_property_read_u32(np, "resume-threshold", &val))
			ctx->resume_threshold_mc = val;
		else
			ctx->resume_threshold_mc = 40000;
	} else {
		/* Default values */
		ctx->max_charge_current_ma = 3000;
		ctx->gaming_charge_current_ma = 500;
		ctx->cooldown_threshold_mc = 45000;
		ctx->resume_threshold_mc = 40000;
	}

	/* Initial state */
	ctx->state = CHARGING_STATE_NORMAL;
	ctx->gaming_mode = GAMING_MODE_OFF;
	atomic_set(&ctx->charging_enabled, 1);
	atomic_set(&ctx->bypass_active, 0);
	ctx->bypass_count = 0;
	ctx->total_bypass_time_ms = 0;

	/* Get power supply references */
	ctx->batt_psy = power_supply_get_by_name("battery");
	ctx->usb_psy = power_supply_get_by_name("usb");
	ctx->bms_psy = power_supply_get_by_name("bms");

	/* Optional: get regulator for charger IC control */
	ctx->charger_reg = devm_regulator_get_optional(&pdev->dev, "charger");
	if (IS_ERR(ctx->charger_reg)) {
		dev_info(&pdev->dev, "Charger regulator not found, using power_supply API");
		ctx->charger_reg = NULL;
	}

	/* Initialize wake lock */
	wake_lock_init(&ctx->charging_wake_lock, WAKE_LOCK_SUSPEND,
			"infinity_charging");

	/* Create char device */
	ret = alloc_chrdev_region(&ctx->dev_num, 0, 1, DEVICE_NAME);
	if (ret) {
		dev_err(&pdev->dev, "Failed to alloc chrdev region: %d", ret);
		goto err_wake_lock;
	}

	cdev_init(&ctx->charging_cdev, &charging_fops);
	ctx->charging_cdev.owner = THIS_MODULE;
	ret = cdev_add(&ctx->charging_cdev, ctx->dev_num, 1);
	if (ret) {
		dev_err(&pdev->dev, "Failed to add cdev: %d", ret);
		goto err_unregister_region;
	}

	/* Create device class and device */
	ctx->charging_class = class_create(THIS_MODULE, CLASS_NAME);
	if (IS_ERR(ctx->charging_class)) {
		ret = PTR_ERR(ctx->charging_class);
		dev_err(&pdev->dev, "Failed to create class: %d", ret);
		goto err_cdev_del;
	}

	if (!device_create(ctx->charging_class, NULL, ctx->dev_num,
			   ctx, DEVICE_NAME)) {
		dev_err(&pdev->dev, "Failed to create device");
		ret = -ENOMEM;
		goto err_class_destroy;
	}

	/* Create sysfs entries */
	ret = sysfs_create_group(&pdev->dev.kobj, &charging_attr_group);
	if (ret) {
		dev_err(&pdev->dev, "Failed to create sysfs group: %d", ret);
		goto err_device_destroy;
	}

	/* Initialize delayed work for periodic monitoring */
	INIT_DELAYED_WORK(&ctx->charging_work, infinity_charging_work_fn);
	INIT_WORK(&ctx->temp_monitor_work, infinity_temp_monitor_work);

	/* Start monitoring */
	schedule_delayed_work(&ctx->charging_work,
		msecs_to_jiffies(5000));
	schedule_work(&ctx->temp_monitor_work);

	/* Save global context */
	g_ctx = ctx;

	dev_info(&pdev->dev,
		"Infinity Charging Control v%s initialized\n"
		"  Max Charge Current: %d mA\n"
		"  Gaming Charge Current: %d mA\n"
		"  Cooldown Threshold: %d mC\n"
		"  Resume Threshold: %d mC\n",
		DRIVER_VERSION,
		ctx->max_charge_current_ma,
		ctx->gaming_charge_current_ma,
		ctx->cooldown_threshold_mc,
		ctx->resume_threshold_mc);

	return 0;

err_device_destroy:
	device_destroy(ctx->charging_class, ctx->dev_num);
err_class_destroy:
	class_destroy(ctx->charging_class);
err_cdev_del:
	cdev_del(&ctx->charging_cdev);
err_unregister_region:
	unregister_chrdev_region(ctx->dev_num, 1);
err_wake_lock:
	wake_lock_destroy(&ctx->charging_wake_lock);
	return ret;
}

static int infinity_charging_remove(struct platform_device *pdev)
{
	struct infinity_charging_ctx *ctx = platform_get_drvdata(pdev);

	/* Cancel all work */
	cancel_delayed_work_sync(&ctx->charging_work);
	cancel_work_sync(&ctx->temp_monitor_work);

	/* Resume charging if bypass is active */
	if (atomic_read(&ctx->bypass_active))
		infinity_deactivate_bypass(ctx);

	/* Remove sysfs */
	sysfs_remove_group(&pdev->dev.kobj, &charging_attr_group);

	/* Destroy device and class */
	device_destroy(ctx->charging_class, ctx->dev_num);
	class_destroy(ctx->charging_class);

	/* Remove char device */
	cdev_del(&ctx->charging_cdev);
	unregister_chrdev_region(ctx->dev_num, 1);

	/* Clean up */
	wake_lock_destroy(&ctx->charging_wake_lock);
	mutex_destroy(&ctx->lock);

	if (ctx->batt_psy)
		power_supply_put(ctx->batt_psy);
	if (ctx->usb_psy)
		power_supply_put(ctx->usb_psy);
	if (ctx->bms_psy)
		power_supply_put(ctx->bms_psy);

	g_ctx = NULL;
	dev_info(&pdev->dev, "Infinity Charging Control removed");
	return 0;
}

/* ========================================================================
 * OF DEVICE TREE MATCH
 * ======================================================================== */

static const struct of_device_id infinity_charging_of_match[] = {
	{ .compatible = "xiaomi,infinity-charging-vayu", },
	{ .compatible = "xiaomi,infinity-charging-bhima", },
	{ .compatible = "qcom,infinity-charging", },
	{ },
};
MODULE_DEVICE_TABLE(of, infinity_charging_of_match);

static struct platform_driver infinity_charging_driver = {
	.probe  = infinity_charging_probe,
	.remove = infinity_charging_remove,
	.driver = {
		.name           = DRIVER_NAME,
		.of_match_table = infinity_charging_of_match,
	},
};

/* ========================================================================
 * MODULE INIT / EXIT
 * ======================================================================== */

static int __init infinity_charging_init(void)
{
	int ret;

	ret = platform_driver_register(&infinity_charging_driver);
	if (ret) {
		pr_err("Infinity Charging: Failed to register driver: %d\n", ret);
		return ret;
	}

	pr_info("Infinity Charging Control v%s loaded\n", DRIVER_VERSION);
	return 0;
}

static void __exit infinity_charging_exit(void)
{
	platform_driver_unregister(&infinity_charging_driver);
	pr_info("Infinity Charging Control unloaded\n");
}

module_init(infinity_charging_init);
module_exit(infinity_charging_exit);

MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("Infinity Kernel Team");
MODULE_DESCRIPTION("Charging Control Driver with Gaming Bypass for Poco X3 Pro");
MODULE_VERSION(DRIVER_VERSION);
MODULE_ALIAS("platform:infinity_charging");