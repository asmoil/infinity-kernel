/*
 * Infinity Charging Control Driver
 * Copyright (c) 2024 Infinity Kernel Team
 * SPDX-License-Identifier: MIT
 *
 * SM8150 charging control for Poco X3 Pro (vayu/bhima)
 * Sysfs: /sys/class/power_supply/battery/charge_ctrl_*
 * IOCTL: /dev/infinity_charger
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/power_supply.h>
#include <linux/workqueue.h>
#include <linux/slab.h>
#include <linux/uaccess.h>
#include <linux/ioctl.h>
#include <linux/delay.h>
#include <linux/of.h>
#include <linux/of_device.h>
#include <linux/platform_device.h>
#include <linux/infinity_charging_control.h>

#define DRIVER_NAME    "infinity_charging_control"
#define DRIVER_VERSION "1.0"

static int charging_mode = CHARGING_CTRL_ON;
static int charge_limit_percent = 80;
static bool driver_enabled = true;

/* Delayed work for monitoring */
static struct delayed_work charge_monitor_work;
static struct class *charge_class;
static struct device *charge_dev;
static struct cdev charge_cdev;
static dev_t charge_dev_t;
static int charge_major;

/* Mode names for sysfs display */
static const char *mode_names[] = {
    [CHARGING_CTRL_OFF]    = "off",
    [CHARGING_CTRL_ON]     = "on",
    [CHARGING_CTRL_PAUSE]  = "pause",
    [CHARGING_CTRL_LIMIT]  = "limit",
    [CHARGING_CTRL_BYPASS] = "bypass",
};

/* ── Monitor work ────────────────────────────────── */
static void charge_monitor_fn(struct work_struct *work)
{
    union power_supply_propval val = { .intval = 0 };
    struct power_supply *psy;
    int capacity = 0;

    psy = power_supply_get_by_name("battery");
    if (psy) {
        power_supply_get_property(psy, POWER_SUPPLY_PROP_CAPACITY, &val);
        capacity = val.intval;
        power_supply_put(psy);
    }

    /* Limit mode: disable charging above threshold */
    if (charging_mode == CHARGING_CTRL_LIMIT && charge_limit_percent > 0) {
        if (capacity >= charge_limit_percent) {
            psy = power_supply_get_by_name("battery");
            if (psy) {
                val.intval = 0;
                power_supply_set_property(psy, POWER_SUPPLY_PROP_CHARGE_ENABLE, &val);
                power_supply_put(psy);
            }
        } else {
            psy = power_supply_get_by_name("battery");
            if (psy) {
                val.intval = 1;
                power_supply_set_property(psy, POWER_SUPPLY_PROP_CHARGE_ENABLE, &val);
                power_supply_put(psy);
            }
        }
    }

    /* Reschedule every 30 seconds */
    schedule_delayed_work(&charge_monitor_work, msecs_to_jiffies(30000));
}

/* ── Sysfs show/store ────────────────────────────── */
static ssize_t mode_show(struct device *dev, struct device_attribute *attr, char *buf)
{
    if (charging_mode >= 0 && charging_mode <= CHARGING_CTRL_BYPASS)
        return snprintf(buf, PAGE_SIZE, "%s\n", mode_names[charging_mode]);
    return snprintf(buf, PAGE_SIZE, "unknown\n");
}

static ssize_t mode_store(struct device *dev, struct device_attribute *attr,
                          const char *buf, size_t count)
{
    int i;
    char input[16];

    if (count >= sizeof(input))
        return -EINVAL;

    memcpy(input, buf, count);
    input[count] = '\0';

    /* Strip trailing newline */
    if (count > 0 && input[count - 1] == '\n')
        input[count - 1] = '\0';

    for (i = 0; i <= CHARGING_CTRL_BYPASS; i++) {
        if (strcmp(input, mode_names[i]) == 0) {
            charging_mode = i;
            pr_info(DRIVER_NAME ": mode set to %s\n", mode_names[i]);
            return count;
        }
    }

    pr_err(DRIVER_NAME ": invalid mode '%s'\n", input);
    return -EINVAL;
}

static ssize_t limit_show(struct device *dev, struct device_attribute *attr, char *buf)
{
    return snprintf(buf, PAGE_SIZE, "%d\n", charge_limit_percent);
}

static ssize_t limit_store(struct device *dev, struct device_attribute *attr,
                           const char *buf, size_t count)
{
    int val;
    if (kstrtoint(buf, 10, &val) < 0)
        return -EINVAL;
    if (val < 5 || val > 100)
        return -EINVAL;
    charge_limit_percent = val;
    pr_info(DRIVER_NAME ": limit set to %d%%\n", val);
    return count;
}

static ssize_t enable_show(struct device *dev, struct device_attribute *attr, char *buf)
{
    return snprintf(buf, PAGE_SIZE, "%d\n", driver_enabled ? 1 : 0);
}

static ssize_t enable_store(struct device *dev, struct device_attribute *attr,
                            const char *buf, size_t count)
{
    int val;
    if (kstrtoint(buf, 10, &val) < 0)
        return -EINVAL;
    driver_enabled = !!val;
    if (!driver_enabled)
        cancel_delayed_work_sync(&charge_monitor_work);
    else
        schedule_delayed_work(&charge_monitor_work, msecs_to_jiffies(1000));
    return count;
}

static DEVICE_ATTR(mode, 0644, mode_show, mode_store);
static DEVICE_ATTR(limit, 0644, limit_show, limit_store);
static DEVICE_ATTR(enable, 0644, enable_show, enable_store);

static struct attribute *charge_attrs[] = {
    &dev_attr_mode.attr,
    &dev_attr_limit.attr,
    &dev_attr_enable.attr,
    NULL,
};

static const struct attribute_group charge_attr_group = {
    .attrs = charge_attrs,
};

/* ── IOCTL handlers ──────────────────────────────── */
static long charge_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
{
    int val;

    switch (cmd) {
    case INFINITY_CHARGE_GET_MODE:
        if (copy_to_user((int __user *)arg, &charging_mode, sizeof(int)))
            return -EFAULT;
        return 0;

    case INFINITY_CHARGE_SET_MODE:
        if (copy_from_user(&val, (int __user *)arg, sizeof(int)))
            return -EFAULT;
        if (val < CHARGING_CTRL_OFF || val > CHARGING_CTRL_BYPASS)
            return -EINVAL;
        charging_mode = val;
        return 0;

    case INFINITY_CHARGE_GET_LEVEL:
        if (copy_to_user((int __user *)arg, &charge_limit_percent, sizeof(int)))
            return -EFAULT;
        return 0;

    case INFINITY_CHARGE_SET_LIMIT:
        if (copy_from_user(&val, (int __user *)arg, sizeof(int)))
            return -EFAULT;
        if (val < 5 || val > 100)
            return -EINVAL;
        charge_limit_percent = val;
        return 0;

    default:
        return -ENOTTY;
    }
}

/* ── File ops ────────────────────────────────────── */
static const struct file_operations charge_fops = {
    .owner          = THIS_MODULE,
    .unlocked_ioctl = charge_ioctl,
    .compat_ioctl   = charge_ioctl,
    .open           = nonseekable_open,
};

/* ── Platform probe/remove ────────────────────────── */
static int infinity_charge_probe(struct platform_device *pdev)
{
    int ret;

    pr_info(DRIVER_NAME ": v%s probing\n", DRIVER_VERSION);

    /* Create device class */
    charge_class = class_create(THIS_MODULE, DRIVER_NAME);
    if (IS_ERR(charge_class))
        return PTR_ERR(charge_class);

    /* Allocate device number */
    ret = alloc_chrdev_region(&charge_dev_t, 0, 1, DRIVER_NAME);
    if (ret < 0) {
        class_destroy(charge_class);
        return ret;
    }
    charge_major = MAJOR(charge_dev_t);

    /* Init cdev */
    cdev_init(&charge_cdev, &charge_fops);
    charge_cdev.owner = THIS_MODULE;
    ret = cdev_add(&charge_cdev, charge_dev_t, 1);
    if (ret < 0) {
        unregister_chrdev_region(charge_dev_t, 1);
        class_destroy(charge_class);
        return ret;
    }

    /* Create device */
    charge_dev = device_create(charge_class, NULL, charge_dev_t, NULL, "infinity_charger");
    if (IS_ERR(charge_dev)) {
        cdev_del(&charge_cdev);
        unregister_chrdev_region(charge_dev_t, 1);
        class_destroy(charge_class);
        return PTR_ERR(charge_dev);
    }

    /* Create sysfs */
    ret = sysfs_create_group(&charge_dev->kobj, &charge_attr_group);
    if (ret < 0)
        pr_warn(DRIVER_NAME ": sysfs creation failed (%d)\n", ret);

    /* Start monitor */
    INIT_DELAYED_WORK(&charge_monitor_work, charge_monitor_fn);
    schedule_delayed_work(&charge_monitor_work, msecs_to_jiffies(5000));

    pr_info(DRIVER_NAME ": ready, mode=%s, limit=%d%%\n",
            mode_names[charging_mode], charge_limit_percent);
    return 0;
}

static int infinity_charge_remove(struct platform_device *pdev)
{
    cancel_delayed_work_sync(&charge_monitor_work);
    sysfs_remove_group(&charge_dev->kobj, &charge_attr_group);
    device_destroy(charge_class, charge_dev_t);
    cdev_del(&charge_cdev);
    unregister_chrdev_region(charge_dev_t, 1);
    class_destroy(charge_class);
    pr_info(DRIVER_NAME ": removed\n");
    return 0;
}

/* ── Device tree match ──────────────────────────── */
static const struct of_device_id infinity_charge_id[] = {
    { .compatible = "xiaomi,charging-control" },
    { .compatible = "qcom,sm8150-charging" },
    { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, infinity_charge_id);

static struct platform_driver infinity_charge_driver = {
    .probe  = infinity_charge_probe,
    .remove = infinity_charge_remove,
    .driver = {
        .name           = DRIVER_NAME,
        .of_match_table = infinity_charge_id,
    },
};

module_platform_driver(infinity_charge_driver);

MODULE_LICENSE("MIT");
MODULE_AUTHOR("Infinity Kernel Team");
MODULE_DESCRIPTION("Infinity Charging Control for Poco X3 Pro (vayu/bhima)");
MODULE_VERSION(DRIVER_VERSION);
