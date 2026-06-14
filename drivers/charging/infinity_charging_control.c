/*
 * Infinity Charging Control Driver
 * Copyright (C) 2024 Infinity Kernel Team
 *
 * Charging control driver for Poco X3 Pro (vayu/bhima) based on SM8250-AC
 * (Snapdragon 860) with PM8150L PMIC and qcom,smb2-charger.
 *
 * Provides four charging modes accessible via sysfs and ioctl:
 *   - Normal:      No intervention, default charger behavior
 *   - Balance:     Limit charge current to 1500mA, thermal limit 40 deg C
 *   - Performance: Limit charge current to 3000mA, thermal limit 45 deg C
 *   - Game:        Bypass charging — disable battery charging entirely,
 *                  device runs on wall/AC power to reduce heat during gaming
 *
 * Sysfs interface:
 *   /sys/class/power_supply/battery/charging_mode  (rw, shows mode name)
 *
 * Ioctl interface:
 *   /dev/infinity_charging
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
#include <linux/sysfs.h>
#include <linux/power_supply.h>
#include <linux/thermal.h>
#include <linux/workqueue.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/of_device.h>

/* Constants */

#define INFINITY_IOCTL_MAGIC            'IC'
#define MONITOR_INTERVAL_MS             3000
#define THERMAL_HYSTERESIS_C            3
#define DEFAULT_CHARGE_CURRENT_MA       5000    /* 5A SMB2 default */

/* Charging modes */

enum infinity_charge_mode {
        CHARGE_MODE_NORMAL = 0,
        CHARGE_MODE_BALANCE,
        CHARGE_MODE_PERFORMANCE,
        CHARGE_MODE_GAME,
        CHARGE_MODE_MAX
};

/* Ioctl commands */

#define INFINITY_CHG_IOC_SET_MODE       _IOW(INFINITY_IOCTL_MAGIC, 1, int)
#define INFINITY_CHG_IOC_GET_MODE       _IOR(INFINITY_IOCTL_MAGIC, 2, int)
#define INFINITY_CHG_IOC_GET_STATUS     _IOR(INFINITY_IOCTL_MAGIC, 3, \
                                                struct infinity_chg_status)
#define INFINITY_CHG_IOC_RESET          _IO(INFINITY_IOCTL_MAGIC, 4)

/**
 * struct infinity_chg_status - Battery and charging status for ioctl
 * @mode:               Current charging mode
 * @battery_temp_mc:    Battery temperature in millidegrees Celsius
 * @battery_uv:         Battery voltage in microvolts
 * @current_ua:         Battery current in microamps
 * @soc:                Battery state-of-charge (0-100%)
 * @is_charging:        Charging is currently enabled
 * @is_bypass:          Game-mode bypass is active
 * @thermal_throttled:  Thermal limit has been triggered
 */
struct infinity_chg_status {
        int mode;
        int battery_temp_mc;
        int battery_uv;
        int current_ua;
        int soc;
        int is_charging;
        int is_bypass;
        int thermal_throttled;
};

/**
 * struct charge_mode_config - Per-mode charging parameters
 * @current_limit_ma:   Charge current limit in mA (0 = no limit)
 * @thermal_limit_c:    Temperature limit in degrees C (0 = disabled)
 * @label:              Human-readable mode name
 */

/* Data structures */
struct charge_mode_config {
        int current_limit_ma;
        int thermal_limit_c;
        const char *label;
};

static const struct charge_mode_config mode_configs[CHARGE_MODE_MAX] = {
        [CHARGE_MODE_NORMAL] = {
                .current_limit_ma = 0,
                .thermal_limit_c  = 0,
                .label            = "Normal",
        },
        [CHARGE_MODE_BALANCE] = {
                .current_limit_ma = 1500,
                .thermal_limit_c  = 40,
                .label            = "Balance",
        },
        [CHARGE_MODE_PERFORMANCE] = {
                .current_limit_ma = 3000,
                .thermal_limit_c  = 45,
                .label            = "Performance",
        },
        [CHARGE_MODE_GAME] = {
                .current_limit_ma = 0,  /* N/A — charging disabled */
                .thermal_limit_c  = 0,  /* N/A */
                .label            = "Game",
        },
};

/**
 * struct infinity_chg_drvdata - Driver private data
 * @dev:                Platform device
 * @lock:               Mutex protecting all runtime state
 * @mode:               Active charging mode
 * @battery_psy:        Reference to "battery" power supply
 * @charger_psy:        Reference to charger power supply (SMB2)
 * @miscdev:            Misc device for /dev/infinity_charging
 * @monitor_work:       Delayed work for periodic monitoring
 * @monitor_active:     Monitor loop is running
 * @thermal_tzd:        Registered thermal zone device
 * @psy_nb:             Power supply notifier block
 * @sysfs_ready:        charging_mode sysfs attr on battery psy
 *
 * Cached battery state (protected by @lock):
 * @batt_temp_mc:       Temperature in millidegrees C
 * @batt_uv:            Voltage in microvolts
 * @batt_ua:            Current in microamps (negative = discharging)
 * @batt_soc:           State of charge percentage
 * @batt_status:        POWER_SUPPLY_STATUS_* value
 * @charging_on:        Charging is currently enabled
 * @bypass_on:          Game-mode bypass is active
 * @therm_throttled:    Thermal limit triggered, charging paused
 * @orig_current_ua:    Original input current before mode limits
 */
struct infinity_chg_drvdata {
        struct device *dev;
        struct mutex lock;

        enum infinity_charge_mode mode;

        struct power_supply *battery_psy;
        struct power_supply *charger_psy;

        struct miscdevice miscdev;
        struct delayed_work monitor_work;
        bool monitor_active;

        struct thermal_zone_device *thermal_tzd;
        struct notifier_block psy_nb;

        bool sysfs_ready;

        /* Cached battery state */
        int batt_temp_mc;
        int batt_uv;
        int batt_ua;
        int batt_soc;
        int batt_status;
        bool charging_on;
        bool bypass_on;
        bool therm_throttled;
        int orig_current_ua;
};

/* Global driver instance */
static struct infinity_chg_drvdata *g_drv;

/* Module parameters */

static int default_mode = CHARGE_MODE_NORMAL;
module_param_named(default_mode, default_mode, int, 0644);
MODULE_PARM_DESC(default_mode,
                 "Default charging mode at boot (0=Normal, 1=Balance, "
                 "2=Performance, 3=Game)");

static int monitor_interval_ms = MONITOR_INTERVAL_MS;
module_param_named(monitor_interval, monitor_interval_ms, int, 0644);
MODULE_PARM_DESC(monitor_interval,
                 "Monitoring interval in milliseconds (default 3000)");

/* Mode helpers */

static const char *mode_label(enum infinity_charge_mode mode)
{
        if (mode >= 0 && mode < CHARGE_MODE_MAX)
                return mode_configs[mode].label;
        return "Unknown";
}

static int parse_mode(const char *buf, size_t len,
                      enum infinity_charge_mode *out)
{
        char name[32];
        int i;

        if (len >= sizeof(name))
                return -EINVAL;

        memcpy(name, buf, len);
        name[len] = '\0';
        if (len > 0 && name[len - 1] == '\n')
                name[len - 1] = '\0';

        /* Try matching label (case-insensitive) */
        for (i = 0; i < CHARGE_MODE_MAX; i++) {
                if (strcasecmp(name, mode_configs[i].label) == 0) {
                        *out = i;
                        return 0;
                }
        }

        /* Fallback: numeric */
        {
                unsigned long v;
                int rc = kstrtoul(name, 10, &v);

                if (rc == 0 && v < CHARGE_MODE_MAX) {
                        *out = v;
                        return 0;
                }
        }
        return -EINVAL;
}

/* Power supply property helpers */

static int psy_read_batt(struct infinity_chg_drvdata *d,
                         enum power_supply_property psp,
                         union power_supply_propval *v)
{
        if (!d->battery_psy)
                d->battery_psy = power_supply_get_by_name("battery");
        if (!d->battery_psy)
                return -ENODEV;
        return power_supply_get_property(d->battery_psy, psp, v);
}

static int psy_write_batt(struct infinity_chg_drvdata *d,
                          enum power_supply_property psp,
                          union power_supply_propval *v)
{
        if (!d->charger_psy)
                d->charger_psy = power_supply_get_by_name("battery");
        if (!d->charger_psy)
                return -ENODEV;
        return power_supply_set_property(d->charger_psy, psp, v);
}

/**
 * refresh_battery() - Update all cached battery readings from psy
 */
static void refresh_battery(struct infinity_chg_drvdata *d)
{
        union power_supply_propval v;

        if (psy_read_batt(d, POWER_SUPPLY_PROP_TEMP, &v) == 0)
                d->batt_temp_mc = v.intval;
        if (psy_read_batt(d, POWER_SUPPLY_PROP_VOLTAGE_NOW, &v) == 0)
                d->batt_uv = v.intval;
        if (psy_read_batt(d, POWER_SUPPLY_PROP_CURRENT_NOW, &v) == 0)
                d->batt_ua = v.intval;
        if (psy_read_batt(d, POWER_SUPPLY_PROP_CAPACITY, &v) == 0)
                d->batt_soc = v.intval;
        if (psy_read_batt(d, POWER_SUPPLY_PROP_STATUS, &v) == 0)
                d->batt_status = v.intval;
}

/**
 * enable_charging() - Re-enable charging with mode-appropriate limits
 */
static int enable_charging(struct infinity_chg_drvdata *d)
{
        const struct charge_mode_config *cfg = &mode_configs[d->mode];
        union power_supply_propval v;
        int ret;

        /* Resume charging */
        v.intval = POWER_SUPPLY_CHARGE_TYPE_FAST;
        ret = psy_write_batt(d, POWER_SUPPLY_PROP_CHARGE_TYPE, &v);
        if (ret) {
                dev_err(d->dev, "failed to enable charging: %d\n", ret);
                return ret;
        }

        /* Set current limit */
        if (cfg->current_limit_ma > 0) {
                v.intval = cfg->current_limit_ma * 1000;
        } else {
                v.intval = d->orig_current_ua;
        }
        ret = psy_write_batt(d, POWER_SUPPLY_PROP_INPUT_CURRENT_LIMIT, &v);
        if (ret) {
                dev_warn(d->dev, "failed to set current limit: %d\n", ret);
                /* Non-fatal: charging is still enabled */
        }

        d->charging_on = true;
        d->bypass_on = false;

        dev_info(d->dev, "charging enabled — mode: %s, limit: %d mA\n",
                 cfg->label, cfg->current_limit_ma > 0 ?
                 cfg->current_limit_ma :
                 d->orig_current_ua / 1000);
        return 0;
}

/**
 * disable_charging() - Pause battery charging (bypass mode)
 *
 * On SM8250-AC with SMB2/PM8150L, setting charge type to NONE stops
 * battery charging while the system continues to draw power from the
 * USB/AC adapter.  This is bypass charging used during gaming.
 */
static int disable_charging(struct infinity_chg_drvdata *d)
{
        union power_supply_propval v;
        int ret;

        v.intval = POWER_SUPPLY_CHARGE_TYPE_NONE;
        ret = psy_write_batt(d, POWER_SUPPLY_PROP_CHARGE_TYPE, &v);
        if (ret) {
                dev_err(d->dev, "failed to disable charging: %d\n", ret);
                return ret;
        }

        d->charging_on = false;
        d->bypass_on = true;

        dev_info(d->dev, "charging disabled — bypass active (Game mode)\n");
        return 0;
}

/**
 * apply_mode() - Enforce the current mode's charging behavior
 * Must be called with d->lock held.
 */
static void apply_mode(struct infinity_chg_drvdata *d)
{
        const struct charge_mode_config *cfg = &mode_configs[d->mode];

        switch (d->mode) {
        case CHARGE_MODE_NORMAL:
                if (!d->charging_on)
                        enable_charging(d);
                break;

        case CHARGE_MODE_BALANCE:
        case CHARGE_MODE_PERFORMANCE:
                if (!d->charging_on) {
                        enable_charging(d);
                } else {
                        union power_supply_propval v;
                        /* Re-apply current limit in case it drifted */
                        v.intval = cfg->current_limit_ma * 1000;
                        psy_write_batt(d,
                                       POWER_SUPPLY_PROP_INPUT_CURRENT_LIMIT,
                                       &v);
                }
                break;

        case CHARGE_MODE_GAME:
                if (d->charging_on)
                        disable_charging(d);
                break;

        default:
                break;
        }
}

static int set_charge_mode(struct infinity_chg_drvdata *d,
                           enum infinity_charge_mode new_mode)
{
        if (new_mode < 0 || new_mode >= CHARGE_MODE_MAX) {
                dev_err(d->dev, "invalid mode %d\n", new_mode);
                return -EINVAL;
        }

        mutex_lock(&d->lock);

        dev_info(d->dev, "mode: %s -> %s\n",
                 mode_label(d->mode), mode_label(new_mode));

        d->mode = new_mode;
        d->therm_throttled = false;

        apply_mode(d);

        mutex_unlock(&d->lock);
        return 0;
}

/**
 * try_add_battery_sysfs() - Add charging_mode attr to battery psy
 * Retries from monitor work if battery psy isn't ready at probe.
 */
static void try_add_battery_sysfs(struct infinity_chg_drvdata *d)
{
        int ret;

        if (d->sysfs_ready)
                return;

        if (!d->battery_psy)
                d->battery_psy = power_supply_get_by_name("battery");
        if (!d->battery_psy)
                return;

        ret = sysfs_create_file(&d->battery_psy->dev.kobj,
                                &dev_attr_charging_mode.attr);
        if (ret) {
                dev_err_ratelimited(d->dev,
                                    "sysfs create on battery failed: %d\n",
                                    ret);
                return;
        }

        d->sysfs_ready = true;
        dev_info(d->dev,
                 "charging_mode sysfs attr added to battery power_supply\n");
}

/**
 * monitor_work_fn() - Periodic battery monitoring and mode enforcement
 */
static void monitor_work_fn(struct work_struct *work)
{
        struct infinity_chg_drvdata *d = g_drv;
        const struct charge_mode_config *cfg;
        int temp_c;

        if (!d || !d->monitor_active)
                return;

        mutex_lock(&d->lock);

        /* Fresh readings */
        refresh_battery(d);
        temp_c = d->batt_temp_mc / 1000;

        /* Update thermal zone */
        if (d->thermal_tzd)
                thermal_zone_device_update(d->thermal_tzd,
                                           THERMAL_EVENT_UNSPECIFIED);

        /* Try to register sysfs if battery appeared late */
        try_add_battery_sysfs(d);

        cfg = &mode_configs[d->mode];

        switch (d->mode) {
        case CHARGE_MODE_NORMAL:
                /* No action required */
                break;

        case CHARGE_MODE_BALANCE:
        case CHARGE_MODE_PERFORMANCE:
                /* Thermal throttle */
                if (cfg->thermal_limit_c > 0 &&
                    temp_c >= cfg->thermal_limit_c) {
                        if (d->charging_on) {
                                dev_info(d->dev,
                                         "thermal throttle: %d C >= %d C\n",
                                         temp_c, cfg->thermal_limit_c);
                                disable_charging(d);
                                d->therm_throttled = true;
                        }
                } else if (d->therm_throttled &&
                           temp_c <= (cfg->thermal_limit_c -
                                      THERMAL_HYSTERESIS_C)) {
                        dev_info(d->dev,
                                 "thermal recovery: %d C <= %d C\n",
                                 temp_c,
                                 cfg->thermal_limit_c - THERMAL_HYSTERESIS_C);
                        d->therm_throttled = false;
                        enable_charging(d);
                }
                break;

        case CHARGE_MODE_GAME:
                /* Keep bypass active — re-apply if charger reasserted */
                if (d->charging_on)
                        disable_charging(d);
                break;

        default:
                break;
        }

        mutex_unlock(&d->lock);

        if (d->monitor_active)
                schedule_delayed_work(&d->monitor_work,
                                      msecs_to_jiffies(monitor_interval_ms));
}

/* sysfs: /sys/class/power_supply/battery/charging_mode */

static ssize_t charging_mode_show(struct device *dev,
                                  struct device_attribute *attr, char *buf)
{
        struct infinity_chg_drvdata *d = g_drv;
        ssize_t len;

        if (!d)
                return -ENODEV;

        mutex_lock(&d->lock);
        len = snprintf(buf, PAGE_SIZE, "%s\n", mode_label(d->mode));
        mutex_unlock(&d->lock);

        return len;
}

static ssize_t charging_mode_store(struct device *dev,
                                   struct device_attribute *attr,
                                   const char *buf, size_t count)
{
        struct infinity_chg_drvdata *d = g_drv;
        enum infinity_charge_mode m;
        int ret;

        if (!d)
                return -ENODEV;

        ret = parse_mode(buf, count, &m);
        if (ret)
                return ret;

        ret = set_charge_mode(d, m);
        return ret ? ret : count;
}

static DEVICE_ATTR(charging_mode, 0644,
                   charging_mode_show, charging_mode_store);

/**
 * psy_event_notifier() - Handle power supply state changes
 *
 * Resets to Normal on charger disconnect for safety.
 * Re-applies active mode on charger connect.
 */
static int psy_event_notifier(struct notifier_block *nb,
                              unsigned long event, void *data)
{
        struct infinity_chg_drvdata *d = g_drv;
        struct power_supply *psy = data;
        union power_supply_propval v;
        bool online;
        int ret;

        if (!d || event != PSY_EVENT_PROP_CHANGED)
                return NOTIFY_DONE;

        /* Resolve battery psy on first call */
        if (!d->battery_psy)
                d->battery_psy = power_supply_get_by_name("battery");
        if (!d->battery_psy || psy != d->battery_psy)
                return NOTIFY_DONE;

        ret = power_supply_get_property(d->battery_psy,
                                        POWER_SUPPLY_PROP_ONLINE, &v);
        if (ret)
                return NOTIFY_DONE;

        online = !!v.intval;

        mutex_lock(&d->lock);

        if (!online) {
                /* Charger removed — reset to Normal for safety */
                if (d->mode != CHARGE_MODE_NORMAL) {
                        dev_info(d->dev,
                                 "charger unplugged, resetting to Normal\n");
                        d->mode = CHARGE_MODE_NORMAL;
                        d->therm_throttled = false;
                        d->bypass_on = false;
                        d->charging_on = true;
                }
        } else {
                /* Charger connected — apply active mode */
                refresh_battery(d);
                apply_mode(d);
        }

        mutex_unlock(&d->lock);

        return NOTIFY_OK;
}

/* Thermal zone */

static int ichg_tz_get_temp(void *data, int *temp)
{
        struct infinity_chg_drvdata *d = data;

        if (!d)
                return -ENODEV;

        mutex_lock(&d->lock);
        refresh_battery(d);
        *temp = d->batt_temp_mc;
        mutex_unlock(&d->lock);

        return 0;
}

static int ichg_tz_get_trend(void *data, int trip,
                             enum thermal_trend *trend)
{
        struct infinity_chg_drvdata *d = data;

        if (!d)
                return -ENODEV;

        mutex_lock(&d->lock);
        if (d->charging_on && d->batt_ua > 0)
                *trend = THERMAL_TREND_RAISING;
        else if (d->bypass_on || d->batt_ua < 0)
                *trend = THERMAL_TREND_DROPPING;
        else
                *trend = THERMAL_TREND_STABLE;
        mutex_unlock(&d->lock);

        return 0;
}

static const struct thermal_zone_device_ops ichg_tz_ops = {
        .get_temp  = ichg_tz_get_temp,
        .get_trend = ichg_tz_get_trend,
};

/**
 * register_thermal_zone() - Create thermal zone for battery monitoring
 */
static int register_thermal_zone(struct infinity_chg_drvdata *d)
{
        d->thermal_tzd = thermal_zone_device_register(
                        "infinity_battery",
                        0,              /* ntrips */
                        0,              /* mask */
                        d,              /* devdata */
                        &ichg_tz_ops,
                        NULL,           /* tzp */
                        0,              /* passive_delay */
                        0);             /* polling_delay */

        if (IS_ERR_OR_NULL(d->thermal_tzd)) {
                int rc = PTR_ERR(d->thermal_tzd);

                dev_warn(d->dev, "thermal zone register failed: %d\n", rc);
                d->thermal_tzd = NULL;
                return rc;
        }

        dev_info(d->dev, "thermal zone 'infinity_battery' registered\n");
        return 0;
}

/* Ioctl (misc device) */

static long ichg_ioctl(struct file *file, unsigned int cmd,
                       unsigned long arg)
{
        struct infinity_chg_drvdata *d = g_drv;
        void __user *argp = (void __user *)arg;
        int val, ret;

        if (!d)
                return -ENODEV;

        switch (cmd) {
        case INFINITY_CHG_IOC_SET_MODE:
                if (copy_from_user(&val, argp, sizeof(val)))
                        return -EFAULT;
                return set_charge_mode(d, val);

        case INFINITY_CHG_IOC_GET_MODE:
                mutex_lock(&d->lock);
                val = d->mode;
                mutex_unlock(&d->lock);
                if (copy_to_user(argp, &val, sizeof(val)))
                        return -EFAULT;
                return 0;

        case INFINITY_CHG_IOC_GET_STATUS: {
                struct infinity_chg_status s;

                mutex_lock(&d->lock);
                refresh_battery(d);
                s.mode             = d->mode;
                s.battery_temp_mc  = d->batt_temp_mc;
                s.battery_uv       = d->batt_uv;
                s.current_ua       = d->batt_ua;
                s.soc              = d->batt_soc;
                s.is_charging      = d->charging_on;
                s.is_bypass        = d->bypass_on;
                s.thermal_throttled = d->therm_throttled;
                mutex_unlock(&d->lock);

                if (copy_to_user(argp, &s, sizeof(s)))
                        return -EFAULT;
                return 0;
        }

        case INFINITY_CHG_IOC_RESET:
                return set_charge_mode(d, CHARGE_MODE_NORMAL);

        default:
                dev_warn_ratelimited(d->dev,
                                     "unknown ioctl cmd 0x%x\n", cmd);
                return -ENOTTY;
        }
}

static const struct file_operations ichg_fops = {
        .owner          = THIS_MODULE,
        .unlocked_ioctl = ichg_ioctl,
#ifdef CONFIG_COMPAT
        .compat_ioctl   = ichg_ioctl,
#endif
};

/* Device tree */

static int parse_dt(struct platform_device *pdev,
                    struct infinity_chg_drvdata *d)
{
        struct device_node *np = pdev->dev.of_node;
        u32 val;

        if (!np)
                return 0;

        if (!of_property_read_u32(np, "qcom,charge-current-ma", &val)) {
                if (val > 0 && val <= 10000) {
                        d->orig_current_ua = val * 1000;
                        dev_info(&pdev->dev,
                                 "DT: charge-current = %u mA\n", val);
                } else {
                        dev_warn(&pdev->dev,
                                 "DT: ignoring out-of-range charge-current %u\n",
                                 val);
                }
        }

        if (of_property_read_bool(np, "qcom,smb2-charger"))
                dev_info(&pdev->dev, "DT: smb2-charger flag confirmed\n");

        if (of_property_read_bool(np, "qcom,pm8150l"))
                dev_info(&pdev->dev, "DT: PM8150L PMIC confirmed\n");

        return 0;
}

/* Platform driver probe */

static int ichg_probe(struct platform_device *pdev)
{
        struct infinity_chg_drvdata *d;
        int ret;

        d = devm_kzalloc(&pdev->dev, sizeof(*d), GFP_KERNEL);
        if (!d)
                return -ENOMEM;

        d->dev = &pdev->dev;
        mutex_init(&d->lock);

        /* Defaults */
        d->mode = CHARGE_MODE_NORMAL;
        d->charging_on = true;
        d->orig_current_ua = DEFAULT_CHARGE_CURRENT_MA * 1000;

        /* Apply module parameter */
        if (default_mode >= 0 && default_mode < CHARGE_MODE_MAX)
                d->mode = default_mode;

        /* Parse device tree */
        ret = parse_dt(pdev, d);
        if (ret) {
                dev_err(&pdev->dev, "device tree parse failed: %d\n", ret);
                return ret;
        }

        /* Look up battery and charger power supplies */
        d->battery_psy = power_supply_get_by_name("battery");
        if (!d->battery_psy)
                dev_warn(&pdev->dev,
                         "battery power_supply not yet available, "
                         "will retry in monitor\n");
        else
                dev_info(&pdev->dev, "battery power_supply acquired\n");

        d->charger_psy = power_supply_get_by_name("battery");

        /* Read initial battery state */
        refresh_battery(d);

        /* Register misc device: /dev/infinity_charging */
        d->miscdev.minor  = MISC_DYNAMIC_MINOR;
        d->miscdev.name   = "infinity_charging";
        d->miscdev.fops   = &ichg_fops;
        d->miscdev.parent = &pdev->dev;

        ret = misc_register(&d->miscdev);
        if (ret) {
                dev_err(&pdev->dev,
                        "misc device registration failed: %d\n", ret);
                return ret;
        }
        dev_info(&pdev->dev, "/dev/infinity_charging created\n");

        /* Add sysfs attribute to battery power_supply */
        try_add_battery_sysfs(d);

        /* Register thermal zone for battery temperature monitoring */
        ret = register_thermal_zone(d);
        if (ret)
                dev_warn(&pdev->dev,
                         "thermal zone not available, continuing\n");

        /* Register power supply notifier for charger plug/unplug */
        d->psy_nb.notifier_call = psy_event_notifier;
        d->psy_nb.priority = 0;
        ret = power_supply_reg_notifier(&d->psy_nb);
        if (ret) {
                dev_warn(&pdev->dev,
                         "power_supply notifier registration failed: %d\n",
                         ret);
                /* Non-fatal — monitoring work handles state */
        }

        /* Kick off periodic monitoring */
        INIT_DELAYED_WORK(&d->monitor_work, monitor_work_fn);
        d->monitor_active = true;
        g_drv = d;

        platform_set_drvdata(pdev, d);
        schedule_delayed_work(&d->monitor_work,
                              msecs_to_jiffies(monitor_interval_ms));

        dev_info(&pdev->dev,
                 "Infinity Charging Control v2.0 — SM8250-AC / SMB2 / PM8150L\n");
        dev_info(&pdev->dev,
                 "  modes: Normal | Balance (1.5A/40C) | "
                 "Performance (3A/45C) | Game (bypass)\n");
        dev_info(&pdev->dev, "  default mode: %s\n",
                 mode_label(d->mode));

        return 0;
}

/* Platform driver remove */

static int ichg_remove(struct platform_device *pdev)
{
        struct infinity_chg_drvdata *d = platform_get_drvdata(pdev);

        if (!d)
                return 0;

        /* Stop monitoring */
        mutex_lock(&d->lock);
        d->monitor_active = false;
        mutex_unlock(&d->lock);
        cancel_delayed_work_sync(&d->monitor_work);

        /* Unregister power supply notifier */
        power_supply_unreg_notifier(&d->psy_nb);

        /* Remove sysfs attribute from battery psy */
        if (d->sysfs_ready && d->battery_psy)
                sysfs_remove_file(&d->battery_psy->dev.kobj,
                                  &dev_attr_charging_mode.attr);

        /* Unregister thermal zone */
        if (d->thermal_tzd) {
                thermal_zone_device_unregister(d->thermal_tzd);
                d->thermal_tzd = NULL;
        }

        /* Safety: restore default charging on unload */
        if (!d->charging_on) {
                union power_supply_propval v;

                v.intval = POWER_SUPPLY_CHARGE_TYPE_FAST;
                psy_write_batt(d, POWER_SUPPLY_PROP_CHARGE_TYPE, &v);
                v.intval = d->orig_current_ua;
                psy_write_batt(d, POWER_SUPPLY_PROP_INPUT_CURRENT_LIMIT, &v);
                dev_info(&pdev->dev, "charging restored to defaults\n");
        }

        /* Deregister misc device */
        misc_deregister(&d->miscdev);

        /* Release power supply references */
        if (d->battery_psy)
                power_supply_put(d->battery_psy);
        if (d->charger_psy)
                power_supply_put(d->charger_psy);

        g_drv = NULL;
        mutex_destroy(&d->lock);

        dev_info(&pdev->dev, "Infinity Charging Control removed\n");
        return 0;
}

/* OF match table and platform driver */

static const struct of_device_id ichg_of_match[] = {
        {
                .compatible = "qcom,sm8250-infinity-charger",
        },
        { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, ichg_of_match);

static struct platform_driver infinity_charging_driver = {
        .probe  = ichg_probe,
        .remove = ichg_remove,
        .driver = {
                .name           = "infinity-charging",
                .of_match_table = ichg_of_match,
        },
};
module_platform_driver(infinity_charging_driver);

MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("Infinity Kernel Team");
MODULE_DESCRIPTION(
        "Infinity Charging Control for Poco X3 Pro (SM8250-AC / SMB2 / PM8150L)");
MODULE_VERSION("2.0");
MODULE_ALIAS("platform:infinity-charging");